#!/bin/bash
# JOS "boot from local disk" fallback (runs from /etc/init.d/S98jos-localboot, after udev + modules, before the
# FOG client). Selected by the GRUB menu entry that adds jos_localboot=1 to the kernel command line.
#
# Machines with no usable UEFI boot entry (fresh hardware, cleared NVRAM, image deployed without one) cannot
# "fall back to disk": there is nothing in the firmware list to fall back to. So: find every EFI System Partition
# on the local disks, create a UEFI boot entry for each bootloader found, put them first in BootOrder, reboot.
case " $(cat /proc/cmdline) " in *" jos_localboot=1 "*) ;; *) exit 0 ;; esac

exec >/dev/tty0 2>&1 </dev/tty0
say() { echo "[jos-localboot] $*"; }
fail() {
  say "$*"
  say "Dropping to a shell; type 'exit' to reboot."
  /bin/bash
  reboot -f
  sleep 60
}

[[ -d /sys/firmware/efi ]] || fail "not booted in UEFI mode, cannot manage UEFI boot entries"
modprobe efivarfs 2>/dev/null; modprobe vfat 2>/dev/null; modprobe nvme 2>/dev/null
mountpoint -q /sys/firmware/efi/efivars 2>/dev/null || mount -t efivarfs efivarfs /sys/firmware/efi/efivars
udevadm settle --timeout=15 2>/dev/null; sleep 2

# priority order; label is what firmware shows
CANDIDATES=(
  "EFI/Microsoft/Boot/bootmgfw.efi|Windows Boot Manager"
  "EFI/ubuntu/shimx64.efi|ubuntu"
  "EFI/debian/shimx64.efi|debian"
  "EFI/fedora/shimx64.efi|Fedora"
  "EFI/BOOT/BOOTX64.EFI|Local Disk"
)
mnt=/tmp/jos-esp; mkdir -p "$mnt"
found=()   # "disk|partnum|loader|label"

for sys in /sys/class/block/*/partition; do
  [[ -e "$sys" ]] || continue
  p="$(basename "$(dirname "$sys")")"
  pnum="$(<"$sys")"
  disk="/dev/$(basename "$(readlink -f "/sys/class/block/$p/..")")"
  mount -t vfat -o ro "/dev/$p" "$mnt" 2>/dev/null || continue
  hit=0
  for c in "${CANDIDATES[@]}"; do
    f="${c%%|*}"; l="${c##*|}"
    [[ "$l" == "Local Disk" && $hit -eq 1 ]] && continue
    for real in "$mnt"/$f; do
      if [[ -f "$real" ]]; then
        found+=("$disk|$pnum|\\${f//\//\\}|$l"); hit=1; say "found $l on /dev/$p"
      fi
    done
  done
  umount "$mnt"
done

((${#found[@]})) || fail "no EFI bootloader found on any local disk (has an image been deployed?)"

# efibootmgr -c puts the new entry first, so create in reverse to end with the highest priority on top
for ((i=${#found[@]}-1; i>=0; i--)); do
  IFS='|' read -r disk pnum loader label <<<"${found[i]}"
  for n in $(efibootmgr | awk -v l="$label" '$0 ~ "^Boot[0-9A-F][0-9A-F][0-9A-F][0-9A-F]\\*? "l"$" {print substr($1,5,4)}'); do
    efibootmgr -q -B -b "$n"
  done
  efibootmgr -q -c -d "$disk" -p "$pnum" -L "$label" -l "$loader" && say "created '$label' ($disk part $pnum)" \
    || fail "efibootmgr failed to create '$label'"
done

efibootmgr
say "Rebooting into local disk in 5s"
sleep 5
reboot -f
sleep 60
