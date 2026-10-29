#!/bin/busybox sh
# Report this host's architecture and Secure Boot state to FOG, replicating
# what FOG's own iPXE menu does on every PXE boot (src/Boot/IpxeBootMenu.php,
# _recordHostArch()/_recordSecureBootState()) via the same advisory, unauthenticated
# endpoint (service/ipxe/boot.php). JOS boots shim -> grub -> kernel and never
# requests that endpoint on its own, so without this call every JOS-imaged host
# sits with hostArchID and sbstate permanently unset -- found the hard way
# after a real deploy completed cleanly but left both fields blank.
#
# Started in the background by the tiny wrapper /init, before FOS's own init
# even begins, so it must not assume anything about PATH or busybox applet
# symlinks yet -- every external command below goes through the busybox
# binary explicitly, matching the wrapper's own `/bin/busybox mount` style.
# Runs fully independently of FOS's own boot, so it cannot delay or break
# imaging if FOG is unreachable. Advisory only, by FOG's own design (ADR 0029
# on the server) -- getting this wrong costs a wrong label on a form, nothing
# else.

bb() { /bin/busybox "$@"; }

WEB=""
for arg in $(bb cat /proc/cmdline); do
  case "$arg" in
    web=*) WEB="${arg#web=}" ;;
  esac
done
[ -n "$WEB" ] || exit 0
case "$WEB" in
  */) : ;;
  *) WEB="${WEB}/" ;;
esac

MAC=""
i=0
while [ "$i" -lt 30 ]; do
  for ifc in /sys/class/net/*; do
    name="${ifc##*/}"
    [ "$name" = "lo" ] && continue
    [ -f "$ifc/address" ] || continue
    addr="$(bb cat "$ifc/address" 2>/dev/null)"
    oper="$(bb cat "$ifc/operstate" 2>/dev/null)"
    if [ -n "$addr" ] && [ "$addr" != "00:00:00:00:00:00" ] && [ "$oper" = "up" ]; then
      MAC="$addr"
      break 2
    fi
  done
  i=$((i + 1))
  bb sleep 1
done
[ -n "$MAC" ] || exit 0

ARCH=""
case "$(bb uname -m)" in
  x86_64) ARCH="x86_64" ;;
  i?86) ARCH="i386" ;;
  aarch64) ARCH="arm64" ;;
esac

PLATFORM="bios"
SECUREBOOT=""
SETUPMODE=""
EFIVARS=/sys/firmware/efi/efivars
if [ -d "$EFIVARS" ]; then
  PLATFORM="efi"
  sb_file=""
  sm_file=""
  for f in "${EFIVARS}"/SecureBoot-*; do [ -e "$f" ] && sb_file="$f" && break; done
  for f in "${EFIVARS}"/SetupMode-*; do [ -e "$f" ] && sm_file="$f" && break; done
  # Each EFI variable file is a 4-byte attribute header followed by the value;
  # SecureBoot/SetupMode are both single boolean bytes.
  [ -n "$sb_file" ] && SECUREBOOT="$(bb dd if="$sb_file" bs=1 skip=4 count=1 2>/dev/null | bb od -An -tx1 | bb tr -d ' \n')"
  [ -n "$sm_file" ] && SETUPMODE="$(bb dd if="$sm_file" bs=1 skip=4 count=1 2>/dev/null | bb od -An -tx1 | bb tr -d ' \n')"
fi

bb wget -q -O /dev/null -T 10 \
  --post-data="mac0=${MAC}&arch=${ARCH}&platform=${PLATFORM}&secureboot=${SECUREBOOT}&setupmode=${SETUPMODE}" \
  "${WEB}service/ipxe/boot.php" 2>/tmp/jos_bootfacts_error.log

exit 0
