#!/bin/sh
set -e
exec 2>>/tmp/jos_error.log

# udp-receiver wrapper with mandatory suicide clause:
# every 10s inspect throughput; if parsed avg < JOS_UDPCAST_MIN_MB_S (default 30MB/s)
# for JOS_UDPCAST_STRIKES consecutive checks (default 3) -> kill + reboot.
# Unknown/zero parsed speed before the stream starts does not count as a strike.
#
# Tunables (kernel command line or environment):
#   JOS_UDPCAST_MIN_MB_S       minimum average throughput in MB/s (default 30)
#   JOS_UDPCAST_STRIKES        consecutive weak checks before reboot (default 3)
#   JOS_UDPCAST_GRACE_CHECKS   startup checks to ignore (default 6, ~60s)
#
# This is the legacy shell JOS path. The default FOS-based initrd uses FOS's
# own udpcast receiver; these tunables do not affect that path.

. /scripts/jos-common.sh

UDP_RECEIVER="${UDP_RECEIVER:-/tools/udp-receiver}"
LOG_FILE="${JOS_UDPCAST_LOG:-/tmp/udp-receiver.log}"
MIN_MB_S="${JOS_UDPCAST_MIN_MB_S:-30}"
STRIKES="${JOS_UDPCAST_STRIKES:-3}"

if [[ ! -x "$UDP_RECEIVER" ]]; then
  UDP_RECEIVER="udp-receiver"
fi

require_cmd "$UDP_RECEIVER"
require_cmd reboot

touch "$LOG_FILE"

log "UDPCast: starting receiver (logging to $LOG_FILE)"
"$UDP_RECEIVER" "$@" 2>&1 | tee -a "$LOG_FILE" &
UDP_PID=$!

weak=0
# Ignore suicide strikes for the first N intervals (startup / parse settling). Default ~60s at 10s/step.
GRACE_LEFT="${JOS_UDPCAST_GRACE_CHECKS:-6}"

extract_speed_mb_s() {
  local s
  s="$(tail -n 50 "$LOG_FILE" | \
      sed -n -E 's/.*([Aa]verage[^0-9]*|avg[^0-9]*)([0-9]+(\.[0-9]+)?) *([Mm][Bb]\/s).*/\2/p' | \
      tail -n1)"
  if [[ -z "$s" ]]; then
    s="$(tail -n 50 "$LOG_FILE" | sed -n -E 's/.*[^0-9]([0-9]+(\.[0-9]+)?) *[Mm][Bb]\/s.*/\1/p' | tail -n1)"
  fi
  echo "${s:-}"
}

sleep 1
if ! kill -0 "$UDP_PID" 2>/dev/null; then
  err "UDPCast: udp-receiver exited immediately; last output:"
  tail -n 50 "$LOG_FILE" 2>/dev/null || true
  exit 1
fi

while kill -0 "$UDP_PID" 2>/dev/null; do
  sleep 10

  speed="$(extract_speed_mb_s)"
  speed_int="${speed%%.*}"
  speed_int="$(printf '%s' "$speed_int" | tr -cd '0-9')"
  [ -n "$speed_int" ] || speed_int=0

  if [[ -z "$speed" ]]; then
    log "UDPCast: no throughput parse yet (waiting)"
    weak=0
    continue
  fi

  if [[ "$GRACE_LEFT" -gt 0 ]]; then
    GRACE_LEFT=$((GRACE_LEFT - 1))
    log "UDPCast: grace (${GRACE_LEFT} checks left after this) observed ~${speed}MB/s — not enforcing suicide clause yet"
    continue
  fi

  if [[ "$speed_int" -lt "$MIN_MB_S" ]]; then
    weak=$((weak + 1))
    err "UDPCast: weak link detected (avg ${speed}MB/s < ${MIN_MB_S}MB/s) strike ${weak}/${STRIKES}"
  else
    weak=0
    log "UDPCast: healthy (avg ${speed}MB/s)"
  fi

  if [[ "$weak" -ge "$STRIKES" ]]; then
    err "UDPCast: suicide clause triggered; killing udp-receiver and rebooting"
    kill "$UDP_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$UDP_PID" 2>/dev/null || true
    reboot -f || reboot || true
    exit 1
  fi
done

wait "$UDP_PID" || true
log "UDPCast: receiver exited"
