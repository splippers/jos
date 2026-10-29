#!/bin/bash
# JOS console versions of the FOG PXE menu actions that need a login or a prompt (stock FOG draws these in iPXE,
# which cannot run under Secure Boot). Runs from /etc/init.d/S97jos-fogmenu, after udev + network (S10-S40) and
# before the FOG client (S99fog), when GRUB passed jos_fogmenu=<action>:
#
#   deploy     Deploy Image: log in, pick an image, queue a deploy task for this host
#   multijoin  Join Multicast Session: log in, name a session, queue a multicast task for this host
#   keyreg     Update Product Key
#
# Each action drives the same endpoint iPXE uses (service/ipxe/boot.php) with the same parameters, so the server
# applies its normal checks (credentials, task permission, host validity). After a task is queued this script
# returns and S99fog starts the normal FOS client, which picks the task up exactly as menu entry 1 does.
args=" $(cat /proc/cmdline) "
action=""
for a in $args; do [[ "$a" == jos_fogmenu=* ]] && action="${a#jos_fogmenu=}"; done
[[ -n "$action" ]] || exit 0

exec >/dev/tty0 2>&1 </dev/tty0
web=""; for a in $args; do [[ "$a" == web=* ]] && web="${a#web=}"; done
[[ -n "$web" ]] || web="http://10.99.0.1/fog/"
[[ "$web" == */ ]] || web="$web/"
BOOT="${web}service/ipxe/boot.php"

say() { echo "[jos-fogmenu] $*"; }
fail() {
  say "$*"
  say "Press Enter for a shell; exit it to reboot."
  read -r _
  /bin/bash
  reboot -f
  sleep 60
}

# wait for the network (S40network has run, but DHCP can lag)
for _ in $(seq 1 30); do curl -s -m 3 -o /dev/null "${web}" && break; sleep 1; done

macargs=()
i=0
for dev in /sys/class/net/*; do
  n="$(basename "$dev")"; [[ "$n" == lo ]] && continue
  m="$(<"$dev/address")"; [[ -n "$m" && "$m" != 00:00:00:00:00:00 ]] || continue
  macargs+=(--data-urlencode "mac$i=$m"); i=$((i+1))
done
((i)) || fail "no network interface with a MAC address"
macargs+=(--data-urlencode "mac=$(<"/sys/class/net/$(ls /sys/class/net | grep -v '^lo$' | head -1)/address")")

# call <key=value>... -> boot.php response on stdout
call() {
  local p=() kv
  for kv in "$@"; do p+=(--data-urlencode "$kv"); done
  curl -s -m 20 -X POST "${macargs[@]}" "${p[@]}" "$BOOT"
}
login() {
  read -r -p "FOG username: " USER_
  read -r -s -p "FOG password: " PASS_; echo
}
# the server prints iPXE scripts; the useful parts are echo lines and, when a task was queued, the kernel args
messages() { grep -E '^echo ' <<<"$1" | sed 's/^echo //'; }
queued() { grep -q 'type=down' <<<"$1"; }
bad_login() { grep -q 'Invalid login' <<<"$1"; }

case "$action" in
  deploy)
    login
    resp="$(call qihost=1 "username=$USER_" "password=$PASS_")"
    bad_login "$resp" && fail "Invalid login"
    mapfile -t items < <(grep -E '^item ' <<<"$resp" | grep -v '^item return')
    ((${#items[@]})) || fail "$(messages "$resp" | head -3)${resp:+ (no images offered)}"
    echo; echo "Images:"
    for n in "${!items[@]}"; do echo "  $((n+1))) $(sed -E 's/^item [^ ]+ //' <<<"${items[n]}")"; done
    read -r -p "Image number: " c
    [[ "$c" =~ ^[0-9]+$ && $c -ge 1 && $c -le ${#items[@]} ]] || fail "invalid choice"
    id="$(sed -E 's/.*\(([0-9]+)\)$/\1/' <<<"${items[c-1]}")"
    resp="$(call qihost=1 "imageID=$id" "username=$USER_" "password=$PASS_")"
    queued "$resp" || fail "task not queued: $(messages "$resp" | head -3). Is this host registered?"
    say "Deploy task queued for image $id; starting imaging"
    ;;
  multijoin)
    login
    read -r -p "Multicast session name: " sess
    resp="$(call sessionJoin=1 "sessname=$sess" "username=$USER_" "password=$PASS_")"
    bad_login "$resp" && fail "Invalid login"
    queued "$resp" || fail "could not join session '$sess': $(messages "$resp" | head -3)"
    say "Joined multicast session '$sess'; starting imaging"
    ;;
  keyreg)
    read -r -p "Product key: " key
    resp="$(call "key=$key")"
    messages "$resp" | head -3
    grep -q 'Successfully' <<<"$resp" || fail "product key not changed (is this host registered?)"
    sleep 3
    reboot -f   # nothing to image; back to the PXE menu
    sleep 60
    ;;
  *) say "unknown action '$action'" ;;
esac
exit 0
