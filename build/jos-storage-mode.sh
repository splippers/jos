#!/bin/busybox sh
# Detect the BIOS storage mode of the booting client and decide whether the
# JOS kernel can drive it. This runs from /init before the FOG userland starts,
# so it must use only busybox applets and sysfs/proc -- no lspci, no Python.
#
# Writes /tmp/jos-storage-mode.env for jos-report-boot-facts.sh and
# S96jos-taskcheck. Neither consumer treats a failure here as fatal: detection
# is advisory, and an UNKNOWN result is reported rather than guessed at.
#
# Priority matters: a machine in Intel VMD/RST mode still exposes an AHCI-class
# controller, so VMD wins over RAID, which wins over plain AHCI.

bb() { /bin/busybox "$@"; }

STATE=/tmp/jos-storage-mode.env
MODE="${JOS_STORAGE_MODE:-}"
PRI=0
DETAIL=""

set_mode() {
  candidate="$1"
  priority="$2"
  if [ "$priority" -gt "$PRI" ]; then
    MODE="$candidate"
    PRI="$priority"
  fi
}

# An env var or kernel command line override is the escape hatch for odd
# hardware and for tests.
for arg in $(bb cat /proc/cmdline 2>/dev/null); do
  case "$arg" in
    jos_storage_mode=*) set_mode "${arg#jos_storage_mode=}" 99 ;;
  esac
done

if [ -z "$MODE" ]; then
  for dev in /sys/bus/pci/devices/*; do
    [ -d "$dev" ] || continue
    cls="$(bb cat "$dev/class" 2>/dev/null | bb tr -d '\r\n')"
    alias="$(bb cat "$dev/modalias" 2>/dev/null | bb tr 'A-Z' 'a-z')"
    drv=""
    if [ -e "$dev/driver" ]; then
      drv="$(bb basename "$(bb readlink -f "$dev/driver" 2>/dev/null)" 2>/dev/null)"
    fi
    id="${dev##*/}"
    interesting=0

    # VMD: driver binding is authoritative; these modalias IDs cover the
    # common Tiger/Lunar/Raptor Lake controllers before vmd has loaded.
    case "$drv" in
      vmd) set_mode VMD 5; interesting=1 ;;
    esac
    case "$alias" in
      *d00009a0b*|*d00009a0d*|*d00009a0f*|*d00007a0b*|*d0000a0b*|*d0000a0f*)
        set_mode VMD 5; interesting=1
        ;;
    esac

    # Hardware RAID (including Intel RAID in non-VMD mode).
    case "$drv" in
      megaraid_sas|mpt3sas|aacraid|hpsa|cciss|smartpqi) set_mode RAID 4; interesting=1 ;;
    esac
    case "$cls" in
      *0104*) set_mode RAID 4; interesting=1 ;;
    esac

    case "$drv" in
      ahci) set_mode AHCI 3; interesting=1 ;;
    esac
    case "$cls" in
      *010601*) set_mode AHCI 3; interesting=1 ;;
      *0101*|*0102*) set_mode IDE 2; interesting=1 ;;
      *010802*) set_mode NVME 1; interesting=1 ;;
    esac

    if [ "$interesting" -eq 1 ]; then
      DETAIL="${DETAIL} ${id}:class=${cls:-?},driver=${drv:-none}"
    fi
  done
fi

MODE="$(printf '%s' "$MODE" | bb tr 'a-z' 'A-Z')"
[ -n "$MODE" ] || MODE=UNKNOWN

# Which JOS modules are needed for this mode? modules.img is staged under
# /lib/modules/$KVER, and S11 has normally loaded them by the time this runs.
KVER="$(bb uname -r)"
LIST="/lib/modules/${KVER}/jos-modules.list"
BUILTIN="/lib/modules/${KVER}/modules.builtin"
REQUIRED=""
case "$MODE" in
  VMD)  REQUIRED="vmd" ;;
  AHCI) REQUIRED="ahci" ;;
  RAID) REQUIRED="dm_raid dm_mod raid0 raid1 raid10 raid456" ;;
  IDE)  REQUIRED="pata_acpi" ;;
  NVME) REQUIRED="nvme" ;;
esac

MISSING=""
for mod in $REQUIRED; do
  found=0
  if [ -r "$LIST" ] && bb grep -qx "$mod" "$LIST" 2>/dev/null; then found=1; fi
  if [ -r "$BUILTIN" ] && bb grep -Eq "(^|/)${mod}|${mod}_mod|$(printf '%s' "$mod" | bb tr '_' '-')" "$BUILTIN" 2>/dev/null; then found=1; fi
  if bb grep -q "^${mod} " /proc/modules 2>/dev/null; then found=1; fi
  [ "$found" -eq 0 ] && MISSING="${MISSING} ${mod}"
done

SUPPORT="unknown"
if [ -n "$REQUIRED" ]; then
  if [ -n "$MISSING" ]; then
    SUPPORT="missing:${MISSING# }"
  else
    SUPPORT="ok"
  fi
fi

DETAIL="$(printf '%s' "$DETAIL" | bb sed 's/^ *//')"
{
  printf 'JOS_STORAGE_MODE=%s\n' "$MODE"
  printf 'JOS_STORAGE_SUPPORT=%s\n' "$SUPPORT"
  printf 'JOS_STORAGE_DETAIL="%s"\n' "$DETAIL"
} >"$STATE"

if [ "$SUPPORT" != "ok" ]; then
  printf '[JOS] WARNING: storage mode %s is not confirmed (support=%s)\n' "$MODE" "$SUPPORT"
fi
if [ -n "$DETAIL" ]; then
  printf '[JOS] storage mode %s detected from:%s\n' "$MODE" "$DETAIL"
fi

exit 0
