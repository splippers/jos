#!/bin/bash
# Auto-imaging gate for the default GRUB entry ("JOS Image Deploy/Capture").
#
# GRUB defaults to that entry, but FOS's `fog` treats an empty task type as a
# fatal error ("Unknown request type :: Null"), waits a minute and reboots.
# With network first in the firmware boot order that becomes a loop. Ask the
# server before committing: if this host has no task, hand over to the local
# disk fallback; if it has one, return and let S99fog run it.
#
# Explicit menu choices are left alone: registration and diagnostics pass
# mode=..., the console fogmenu actions pass jos_fogmenu=..., "boot from local
# disk" passes jos_localboot=1, and debug passes isdebug=yes.
args=" $(cat /proc/cmdline) "
for a in $args; do
  case "$a" in
    jos_localboot=1|mode=*|jos_fogmenu=*|isdebug=*) exit 0 ;;
  esac
done

web=""; boottype=""
for a in $args; do
  case "$a" in
    web=*) web="${a#web=}" ;;
    boottype=*) boottype="${a#boottype=}" ;;
  esac
done
[[ "$boottype" == "usb" ]] || exit 0
[[ -n "$web" ]] || web="http://10.99.0.1/fog/"
[[ "$web" == */ ]] || web="$web/"

exec >/dev/tty0 2>&1 </dev/tty0
say() { echo "[jos-taskcheck] $*"; }
localboot() {
  say "$*"
  JOS_LOCALBOOT_FORCE=1 /etc/init.d/S98jos-localboot
  # S98 always reboots. Never fall through to S99fog: it would error on the
  # empty task type and reboot again, which can loop.
  reboot -f
  sleep 60
  exit 0
}

# Same handshake bin/fog uses, so the server sees the identity it will use for
# the imaging run. funcs.sh also exports the kernel command line.
. /usr/share/fog/lib/funcs.sh
sysuuid=$(dmidecode -s system-uuid 2>/dev/null); sysuuid=${sysuuid,,}
mac=$(getMACAddresses)
if [[ -z "$mac" ]]; then
  say "No MAC yet; leaving the boot to S99fog"
  exit 0
fi
callServer "${web}status/hostgetkey.php" "mac=$(printf '%s' "$mac" | base64)"
token="$serverBody"
if [[ -z "$token" || "$token" == "Invalid Host" ]]; then
  localboot "Server has no key for this host; booting the local disk"
fi
curl -Lks -o /tmp/hinfo.txt --data "sysuuid=${sysuuid}&mac=$mac&hosttoken=${token}" "${web}service/hostinfo.php" -A ''
# Only source the reply when it looks like the expected shell fragment; an
# error page or "Invalid Host" is not a tasking.
if [[ -f /tmp/hinfo.txt ]] && head -c 2 /tmp/hinfo.txt | grep -q '\['; then
  # shellcheck disable=SC1091
  . /tmp/hinfo.txt
fi

if [[ -n "$type" ]]; then
  say "Server has a $type task for this host; starting imaging"
  exit 0
fi

localboot "No task for this host; booting the local disk"
