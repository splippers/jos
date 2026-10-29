#!/bin/sh
set -e
exec 2>>/tmp/jos_error.log
# Register host — FOG GET …/host/search + dynamic POST paths from server version probe.

SERIAL="$1"

. /scripts/jos-common.sh

[[ -n "$SERIAL" ]] || die "REGISTER: No serial provided."

jos_load_fog_config

FOG_BASE="$(jos_fog_base_url)"

log "REGISTER: FOG≈${FOG_VERSION_RAW:-?} sort=${FOG_VER_SORTKEY:-0} host_paths=${JOS_FOG_HOST_CREATE_PATHS}"

log "REGISTER: Registering/updating host $SERIAL with FOG..."

ACTIVE_IFACE="$(cat /tmp/jos-active-iface 2>/dev/null || true)"
if [[ -z "$ACTIVE_IFACE" ]]; then
  ACTIVE_IFACE="$(ls /sys/class/net | grep -v '^lo$' | head -n1 || true)"
fi

MAC_RAW="$(cat "/sys/class/net/${ACTIVE_IFACE}/address" 2>/dev/null || true)"
MAC="$(printf '%s' "$MAC_RAW" | tr '[:lower:]' '[:upper:]')"
[[ -n "$MAC" ]] || die "REGISTER: Unable to determine MAC address (iface: ${ACTIVE_IFACE:-unknown})"

EXISTING_ID="$(jos_fog_resolve_host_id "$SERIAL")"
if [[ -n "$EXISTING_ID" ]]; then
  log "REGISTER: Host already present in FOG (host id=${EXISTING_ID}). Skipping creation."
  exit 0
fi

if [[ -z "${JOS_MODULES_JSON:-}" ]]; then
  JOS_MODULES_JSON="$(jos_fog_default_modules_json_for_key "${FOG_VER_SORTKEY:-0}")"
fi

JSON_PAYLOAD=$(cat <<EOF
{
  "name": "${SERIAL}",
  "description": "Auto-registered by JOS",
  "macs": ["${MAC}"],
  "modules": ${JOS_MODULES_JSON}
}
EOF
)

RESULT="$(jos_fog_api_post_first_id "$FOG_BASE" "$JOS_FOG_HOST_CREATE_PATHS" "${JSON_PAYLOAD}" 2>/dev/null || true)"

jos_fog_json_has_entity_id "$RESULT" || die "REGISTER: Host registration failed. FOG response: ${RESULT}"

log "REGISTER: Host successfully registered."

exit 0
