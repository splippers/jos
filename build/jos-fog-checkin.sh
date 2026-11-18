#!/bin/bash
# JOS overlay for FOS's /bin/fog.checkin.
#
# FOS's stock checkin draws the FOG banner and then, while a multicast host
# waits for the queue to fill, prints "Attempting to check in ... Failed" every
# five seconds. This replacement keeps the exact same check-in semantics and
# variables (it is sourced by fog.download, not executed) but hands the screen
# to jos-mc-wait-tui.sh for the duration of the wait.

. /usr/share/fog/lib/funcs.sh

RUN_CHKDSK=""
OS_ID_WIN7=5
OS_ID_WIN8=6
for arg in $(cat /proc/cmdline | tr -d \\0); do
    case $arg in
        initsh)
            ash -i
            ;;
        nombr)
            nombr=1
            ;;
        *)
            [[ $imgPartitionType != all && $imgPartitionType != mbr ]] && nombr=1
            ;;
    esac
done

osname=""
mbrfile=""
macWinSafe=$(echo $mac | sed 's/://g')
sockets=$(grep "physical id" /proc/cpuinfo | sort -u | wc -l)
arch=$(uname -m)
[[ $chkdsk -eq 1 ]] && RUN_CHKDSK="-x"
case $mc in
    yes)   method="UDPCAST" ;;
    bt)    method="Torrent-CAST" ;;
    *)     method="NFS" ;;
esac
blGo=0
nfsServerName=""

# Keep the pre-flight probes, but send their chatter to a log so the TUI owns
# the console. All variables they set remain visible to fog.download.
{
    debugPause
    verifyNetworkConnection
    dots "Checking Operating System"
    [[ -z $deployed ]] && determineOS "$osid"
    echo "$osname"
    dots "Checking CPU Cores"
    cores=$(nproc)
    echo "$cores"
    dots "Send method"
    echo "$method"
} >/tmp/jog-checkin-progress.log 2>&1

case $mc in
    [Yy][Ee][Ss]) php_post="mc_checkin.php" ;;
    *)            php_post="Pre_Stage1.php" ;;
esac
sysuuid=$(dmidecode -s system-uuid)
sysuuid=${sysuuid,,}
poststring="sysuuid=${sysuuid}&mac=$mac&type=$type"

# Same function name/behaviour as stock fog.checkin so any later caller works.
checkin() {
    local poststring="$1"
    local php_post="$2"
    local res=""
    local waittime=0
    local tui_pid=""
    local tty=/dev/tty0
    [[ -w "$tty" ]] || tty=/dev/console

    if [[ $mc == yes ]]; then
        : >/tmp/jog-checkin-state
        JOG_TUI_TTY="$tty" \
        JOG_TUI_WAIT_STATE=/tmp/jog-checkin-state \
        JOG_STATUS_FEED="${web}service/jog-screen-status.php" \
            /usr/sbin/jos-mc-wait-tui.sh "$mac" "${web}service/jog-screen-status.php" &
        tui_pid=$!
    fi

    # No bail-out while waiting for a queue slot, exactly as upstream.
    while [[ $res != "##@GO" ]]; do
        callServer "${web}service/$php_post" "$poststring"
        res="$serverBody"
        if [[ $res != "##@GO" ]]; then
            printf 'reason=%s\nwaittime=%s\n' \
                "${serverReason:-$res}" "$waittime" >/tmp/jog-checkin-state
            let waittime+=5
            usleep 5000000
        fi
    done

    if [[ -n "$tui_pid" ]]; then
        kill "$tui_pid" 2>/dev/null || true
        wait "$tui_pid" 2>/dev/null || true
    fi
    rm -f /tmp/jog-checkin-state

    # One normal status line so the non-TUI log/flow is unchanged downstream.
    [[ -w "$tty" ]] && echo " * Attempting to check in....................Done" >"$tty"
    echo "Done"
    debugPause
}

[[ ! $capone -eq 1 ]] && checkin "$poststring" "$php_post"
