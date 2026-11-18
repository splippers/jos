#!/bin/bash
# JOS multicast wait TUI: full-screen console view while a client is queued.
#
# Usage: jos-mc-wait-tui.sh <mac> <status-feed-url> [interface]
#
# Started in the background by the JOS overlay of /bin/fog.checkin and stopped
# as soon as check-in succeeds. Reads the appliance feed (KEY=value lines) plus
# local sysfs link statistics. Requires only bash, curl and ANSI escapes.
#
# All drawing goes to $JOG_TUI_TTY (default: stdout) so it cannot interleave
# with FOG's own script output on the console.

set -u

MAC="${1:-}"
FEED="${2:-${JOG_STATUS_FEED:-http://10.99.0.1/fog/service/jog-screen-status.php}}"
IFACE="${3:-${JOG_TUI_IFACE:-}}"
REFRESH="${JOG_TUI_REFRESH:-3}"
WAIT_STATE="${JOG_TUI_WAIT_STATE:-/tmp/jog-checkin-state}"
TTY="${JOG_TUI_TTY:-}"

if [[ -n "$TTY" ]]; then
    exec >"$TTY" 2>&1
fi

if [[ -z "$IFACE" ]]; then
    IFACE="$(cat /tmp/jos-active-iface 2>/dev/null || true)"
fi
if [[ -z "$IFACE" ]]; then
    IFACE="$(awk '$2 == "00000000" {print $1; exit}' /proc/net/route 2>/dev/null || true)"
fi
[[ -n "$IFACE" ]] || IFACE="eth0"

declare -A S W

enter_tui() { printf '\033[?1049h\033[?25l\033[2J'; }
leave_tui() { printf '\033[?25h\033[?1049l'; }
trap leave_tui EXIT INT TERM

at() { printf '\033[%s;%sH' "$1" "$2"; }

BGF='\033[48;5;17m'
CYAN='\033[38;5;51m'
WHITE='\033[38;5;255m'
GREY='\033[38;5;245m'
GREEN='\033[38;5;46m'
AMBER='\033[38;5;214m'
BOLD='\033[1m'
RST='\033[0m'

box() {
    local row=$1 col=$2 w=$3 h=$4 title=$5 r
    for ((r = row; r < row + h; r++)); do
        at "$r" "$col"
        printf '%b%*s%b' "$BGF" "$w" '' "$RST"
    done
    at "$row" "$col"
    printf '%b%s%b' "$BGF$CYAN" '+--' "$RST"
    at "$row" "$((col + 4))"
    printf '%b%s%b' "$BGF$BOLD$WHITE" " ${title} " "$RST"
}

field() {
    at "$1" "$2"
    printf '%b%s: %b%s%b' "$BGF$GREY" "$3" "$WHITE" "$4" "$RST"
}

status_colour() {
    case "$1" in
        active|complete|running|ready|1|2) printf '%b' "${GREEN}$1${RST}" ;;
        ''|unknown|NULL|0)                printf '%b' "${GREY}${1:-unknown}${RST}" ;;
        *)                               printf '%b' "${AMBER}$1${RST}" ;;
    esac
}

bar() {
    local pct=$1 width=$2 filled i out=''
    [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
    (( pct > 100 )) && pct=100
    filled=$((pct * width / 100))
    for ((i = 0; i < filled; i++)); do out+='#'; done
    for ((i = filled; i < width; i++)); do out+='.'; done
    printf '%b%s%b' "$CYAN" "$out" "$RST"
}

fetch_status() {
    local body
    body="$(curl -fsS -m 5 -X POST --data "mac=$MAC" "$FEED" 2>/dev/null || true)"
    S=()
    while IFS='=' read -r key value; do
        [[ -z "$key" ]] && continue
        S["$key"]="$value"
    done <<<"$body"

    W=()
    if [[ -f "$WAIT_STATE" ]]; then
        while IFS='=' read -r key value; do
            [[ -z "$key" ]] && continue
            W["$key"]="$value"
        done <"$WAIT_STATE"
    fi
}

local_link() {
    local base="/sys/class/net/$IFACE" speed duplex rx tx
    speed="$(cat "$base/speed" 2>/dev/null || echo '?')"
    duplex="$(cat "$base/duplex" 2>/dev/null || echo '?')"
    rx="$(cat "$base/statistics/rx_errors" 2>/dev/null || echo '?')"
    tx="$(cat "$base/statistics/tx_errors" 2>/dev/null || echo '?')"
    printf '%s|%s|%s|%s' "$speed" "$duplex" "$rx" "$tx"
}

paint() {
    printf '\033[2J\033[H'
    at 1 1
    printf '%b%s%b' "$BOLD$CYAN" \
        '  ___  ___  ___  ___    _  _  ___  _   _  ___  ___  ___  ___ ' "$RST"
    at 2 1
    printf '%b%s%b' "$BOLD$WHITE" \
        ' / __|| _ \| _ \| _ \  | \| ||_ _|| | | ||_ _|| _ \| _ \| _ \' "$RST"
    at 3 1
    printf '%b%s%b' "$BOLD$CYAN" \
        '| (_ ||  _/|  _/|  _/  | .` | | | | |_| | | | |  _/|  _/|  _/' "$RST"
    at 4 1
    printf '%b%s%b' "$BOLD$WHITE" \
        ' \___||_|  |_|  |_|    |_|\_||___| \___/ |___||_|  |_|  |_|  ' "$RST"
    at 5 1
    printf '%b%s%b' "$GREY" \
        '  M U L T I C A S T   I M A G I N G   /   q u e u e   s t a t u s' "$RST"

    box 6 1 39 6 'JOB'
    box 6 41 39 6 'LINK'
    field 8 3 'Host' "${S[host]:-unknown}"
    field 9 3 'Image' "${S[host_image]:-unknown}"
    field 10 3 'Task' "${S[task]:-none}"
    IFS='|' read -r speed duplex rx tx <<<"$(local_link)"
    field 8 43 'Interface' "$IFACE"
    field 9 43 'Link' "${speed} Mb/s  ${duplex}"
    field 10 43 'RX/TX errors' "$rx / $tx"

    box 13 1 79 7 'QUEUE'
    field 15 3 'Session' "${S[session0_name]:-none}"
    field 15 42 'Image' "${S[session0_image]:-unknown}"
    field 16 3 'Joined' "${S[session0_sessclients]:-0} / ${S[session0_clients]:-0} clients"
    field 16 42 'State' "$(status_colour "${S[session0_state]:-unknown}")"
    field 17 3 'Check-in' "${W[reason]:-waiting for server}"
    field 17 42 'Waiting' "${W[waittime]:-0}s / max ${S[session0_maxwait]:-?}s"
    at 18 3
    printf '%b%s%b' "$GREY" 'Progress ' "$RST"
    printf '%s' "$(bar "${S[session0_percent]:-0}" 58)"

    box 21 1 79 4 'SURROUNDING SYSTEMS'
    field 22 3 'Appliance' "${S[appliance]:-?} (${S[imaging_ip]:-?})"
    field 22 44 'Multicast' "$(status_colour "${S[svc_fog_multicast]:-}")"
    field 23 3 'DHCP / NFS' "$(status_colour "${S[svc_dnsmasq]:-}") / $(status_colour "${S[svc_nfs]:-}")"
    field 23 44 'APIs' "$(status_colour "${S[svc_mobile_api]:-}")/$(status_colour "${S[svc_imaging_api]:-}")/$(status_colour "${S[svc_model_api]:-}")"

    at 25 1
    printf '%b%s%b' "$GREY" \
        "  MAC ${MAC:-unknown}    refreshed ${S[time]:-?}    refresh ${REFRESH}s" "$RST"
}

enter_tui
while true; do
    fetch_status
    paint
    sleep "$REFRESH"
done
