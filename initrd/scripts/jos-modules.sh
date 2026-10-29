#!/bin/sh
# Load kernel modules from the modules.img overlay (signed modules matching the booted kernel).
# Secure Boot lockdown rejects unsigned modules, so nothing here can come from the JOS build itself.
. /scripts/jos-common.sh

KVER="$(uname -r)"
if [ ! -f "/lib/modules/${KVER}/modules.dep" ]; then
  log "MODULES: no modules for ${KVER} (modules.img missing or kernel mismatch); relying on built-ins"
  exit 0
fi

# Everything the hardware advertises, then the explicit list (USB NICs often appear after the host controller).
find /sys/devices -name modalias -exec cat {} + 2>/dev/null | sort -u | while read -r a; do
  modprobe -q "$a" 2>/dev/null || true
done
if [ -f "/lib/modules/${KVER}/jos-modules.list" ]; then
  while read -r m; do modprobe -q "$m" 2>/dev/null || true; done < "/lib/modules/${KVER}/jos-modules.list"
fi
log "MODULES: loaded for ${KVER}"
