#!/bin/sh
set -e
exec 2>>/tmp/jos_error.log
# Bring up networking with BusyBox udhcpc — deterministic waits, USB imaging NIC first.

. /scripts/jos-common.sh

log "NET: Initialising network..."

# Wait for NICs (USB-C docks, laptops).
for _ in 1 2 3 4 5 6 7 8 9 10; do
  IFACES="$(ls /sys/class/net 2>/dev/null | grep -v '^lo$' || true)"
  [[ -n "$IFACES" ]] && break
  log "NET: Waiting for network interfaces..."
  sleep 1
done

[[ -n "$IFACES" ]] || die "NET: No network interfaces found."

# Preference: USB-attached NICs first (deployment "Forbidden" NIC), then enx* (MAC-named), then others.
jos_net_iface_sort_key() {
  local iface="$1"
  local devpath pref
  devpath="$(readlink -f "/sys/class/net/${iface}/device" 2>/dev/null || true)"
  pref=20
  if [[ "$devpath" == *"/usb"* ]]; then
    pref=0
  elif [[ "$iface" == enx* ]]; then
    pref=5
  fi
  printf '%02d %s\n' "$pref" "$iface"
}

MAX_ROUNDS="${JOS_NET_DHCP_ROUNDS:-4}"

for round in $(seq 1 "$MAX_ROUNDS"); do
  sorted_list="$(for iface in $IFACES; do
    case "$iface" in
      lo|docker*|veth*|virbr*|br*|tap*) continue ;;
    esac
    jos_net_iface_sort_key "$iface"
  done | sort | awk '{print $2}')"

  for iface in $sorted_list; do
    log "NET: [round ${round}/${MAX_ROUNDS}] DHCP on ${iface}"

    if udhcpc -i "$iface" -q -t 8 -n -s /scripts/udhcpc-jos.sh; then
      log "NET: DHCP successful on ${iface}"
      exit 0
    fi

    log "NET: DHCP failed on ${iface}"
  done

  if [[ "$round" -lt "$MAX_ROUNDS" ]]; then
    backoff=$((round * 3))
    log "NET: No lease this round; sleeping ${backoff}s before retry..."
    sleep "$backoff"
  fi
done

err "NET: No network interfaces received a DHCP lease after ${MAX_ROUNDS} rounds."
exit 1
