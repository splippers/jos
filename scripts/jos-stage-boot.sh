#!/bin/bash
set -euo pipefail
# Stage the Secure Boot PXE chain for JOS under the TFTP root:
#   <tftp>/ubuntu-signed/{shimx64,grubx64}.efi   Canonical/Microsoft-signed (jog-copy-signed-ubuntu-efi-to-tftpboot.sh)
#   <tftp>/grub/grub.cfg                         rendered here
#   <tftp>/jos/vmlinuz                           Canonical-signed kernel, copied unmodified
#   <tftp>/jos/initrd.img                        JOS initramfs (unsigned; GRUB does not verify initrds)
#   <tftp>/jos/modules.img                       signed kernel modules matching vmlinuz (second initrd)
# Under Secure Boot the kernel is locked down and refuses unsigned modules, so the JOS initramfs cannot ship
# its own: the modules must come from the same kernel package as vmlinuz. Hence the pinned KVER.
#
# Env: JOG_TFTP_ROOT (/tftpboot)  JOS_KVER (newest /boot/vmlinuz-*)  JOS_INITRD (build/out/initrd.img)  JOS_DIR (/opt/JOG/jos)
#      JOS_CMDLINE_EXTRA (e.g. "console=ttyS0")

log() { echo "[jos-stage-boot] $*"; }
die() { echo "[jos-stage-boot] ERROR: $*" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TFTP="${JOG_TFTP_ROOT:-/tftpboot}"
KVER="${JOS_KVER:-$(ls /boot/vmlinuz-* 2>/dev/null | sed 's|.*/vmlinuz-||' | sort -V | tail -1)}"
[[ -n "$KVER" ]] || die "no kernel found in /boot"
KERNEL="/boot/vmlinuz-${KVER}"
INITRD="${JOS_INITRD:-$HERE/../build/out/initrd.img}"
[[ -r "$INITRD" ]] || INITRD="${JOS_DIR:-/opt/JOG/jos}/build/out/initrd.img"
MODDIR="/lib/modules/${KVER}"
[[ -r "$KERNEL" ]] || die "$KERNEL not readable (run as root: Ubuntu ships kernels 0600 on some releases)"
[[ -d "$MODDIR" ]] || die "$MODDIR missing"
[[ -r "$INITRD" ]] || die "JOS initrd not found at $INITRD (build it: build/build-initrd.sh)"

# FOS builds its drivers into its own kernel; Ubuntu's are modules, so JOS must ship them. Default profile
# "full" = every wired NIC / PHY / USB-NIC, NVMe, SATA/AHCI, SCSI/SAS HBA, device-mapper/RAID, USB host +
# storage, Thunderbolt, MMC, HID/keyboard and I2C-HID (laptop keyboards), plus the filesystems partclone/NFS
# touch. Wireless and GPU are left out (FOS has no use for them). JOS_PROFILE=small restores the old 28-module
# Dell shortlist; JOS_MODULES="a b c" overrides the list; JOS_MODULE_DIRS overrides the directories scanned.
SMALL_MODULES="r8152 ax88179_178a cdc_ether cdc_ncm r8153_ecm usbnet r8169 e1000e igc igb tg3 \
xhci_pci xhci_hcd ehci_pci uhci_hcd usb_storage uas nvme vmd ahci sd_mod \
nfs nfsv3 nfsv4 vfat ext4 ntfs3 exfat"
FULL_DIRS="drivers/net/ethernet drivers/net/usb drivers/net/phy drivers/net/mdio drivers/net/pcs \
drivers/nvme drivers/ata drivers/scsi drivers/md drivers/usb/storage drivers/usb/host drivers/usb/typec \
drivers/thunderbolt drivers/mmc/host drivers/hid drivers/input/keyboard drivers/i2c/busses"
FULL_EXTRA="vmd sd_mod sr_mod sg loop nfs nfsv3 nfsv4 vfat fat ext4 ntfs3 exfat xfs btrfs usbhid hid_generic i2c_hid_acpi \
dm_mod dm_crypt usb_storage uas xhci_pci xhci_hcd ehci_pci uhci_hcd thunderbolt \
fuse f2fs hfsplus hfs jfs ext2 efivarfs squashfs overlay isofs udf cifs nbd loop zram \
nls_utf8 nls_cp437 nls_iso8859-1 raid0 raid1 raid10 raid456 dm_raid"
if [[ -n "${JOS_MODULES:-}" ]]; then MODULES="$JOS_MODULES"
elif [[ "${JOS_PROFILE:-full}" == small ]]; then MODULES="$SMALL_MODULES"
else
  MODULES="$FULL_EXTRA"
  for d in ${JOS_MODULE_DIRS:-$FULL_DIRS}; do
    [[ -d "/lib/modules/${KVER}/kernel/$d" ]] || continue
    MODULES+=" $(find "/lib/modules/${KVER}/kernel/$d" -name '*.ko*' -printf '%f\n' | sed 's/\.ko.*//')"
  done
fi
FIRMWARE_DIRS="${JOS_FIRMWARE_DIRS:-rtl_nic tigon bnx2 bnx2x e100}"

command -v sbverify >/dev/null || die "install sbsigntool (sbverify)"
sbverify --list "$KERNEL" 2>&1 | grep -q 'signature 1' || die "$KERNEL has no Secure Boot signature"
log "kernel ${KVER} is signed"

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
R="$W/root"; mkdir -p "$R$MODDIR"

want=(); : >"$W/files"
for m in $MODULES; do
  deps="$(modprobe -S "$KVER" --show-depends "$m" 2>/dev/null || true)"
  [[ -n "$deps" ]] || { log "skip $m (unknown or built in)"; continue; }
  want+=("$m")
  { grep '^insmod' <<<"$deps" || true; } | awk '{print $2}' >>"$W/files"
done
sort -u "$W/files" | while read -r f; do
  rel="${f#/}"; mkdir -p "$R/$(dirname "$rel")"
  case "$f" in
    *.zst) zstd -dqc "$f" >"$R/${rel%.zst}" ;;   # BusyBox modprobe reads plain .ko; the signature stays embedded
    *.xz)  xz -dc "$f" >"$R/${rel%.xz}" ;;
    *)     cp "$f" "$R/$rel" ;;
  esac
done
for f in modules.builtin modules.builtin.modinfo modules.order; do   # lets kmod skip drivers built into the kernel
  [[ -f "$MODDIR/$f" ]] && cp "$MODDIR/$f" "$R$MODDIR/$f"
done
depmod -b "$R" "$KVER"
printf '%s\n' "${want[@]}" >"$R$MODDIR/jos-modules.list"

for d in $FIRMWARE_DIRS; do
  for src in /lib/firmware/$d /usr/lib/firmware/$d; do
    [[ -d "$src" ]] || continue
    mkdir -p "$R/lib/firmware"; cp -rL "$src" "$R/lib/firmware/"
    find "$R/lib/firmware/$d" -name '*.zst' -exec zstd -dq --rm {} \;
    break
  done
done

install -d "$TFTP/jos" "$TFTP/grub"
(cd "$R" && find . | cpio -H newc -o --quiet | gzip -9) >"$W/modules.img"
install -m 0644 "$KERNEL" "$TFTP/jos/vmlinuz"
install -m 0644 "$INITRD" "$TFTP/jos/initrd.img"
install -m 0644 "$W/modules.img" "$TFTP/jos/modules.img"
# Memtest86+ is unsigned, so it only runs with Secure Boot off; the menu entry says so. Needs the memtest86+ package.
MEMTEST="${JOS_MEMTEST:-/boot/mt86+x64}"
if [[ -f "$MEMTEST" ]]; then install -m 0644 "$MEMTEST" "$TFTP/jos/memtest"; else rm -f "$TFTP/jos/memtest"; log "no memtest at $MEMTEST (apt install memtest86+); menu entry omitted"; fi
echo "$KVER" >"$TFTP/jos/kver"
# Shim derives the directory it fetches grubx64.efi from out of what the DHCP server sent as the boot file, and
# real DHCP servers (dnsmasq/FOG's TFTP) do not always carry the sub-directory through. Serve the pair from both
# the sub-directory and the TFTP root so either lookup succeeds.
for f in shimx64.efi grubx64.efi; do
  [[ -f "$TFTP/ubuntu-signed/$f" ]] && install -m 0644 "$TFTP/ubuntu-signed/$f" "$TFTP/$f"
done

[[ -f /etc/jog/jog.env ]] && { set -a; source /etc/jog/jog.env; set +a; }
WEB="${JOS_FOG_WEB:-http://${JOG_NEXT_SERVER:-10.99.0.1}/fog/}"
if [[ -f "${INITRD%.img}.fos-tag" ]]; then
  # FOS userland (build/build-from-fos.sh): same arguments as the stock FOS USB image. FOS fetches the
  # host's task from the FOG server itself, so the only site-specific value here is web=.
  FOS_ARGS="keymap= web=${WEB} boottype=usb consoleblank=0"
  FLAVOR="FOS $(cat "${INITRD%.img}.fos-tag")"
else
  FOS_ARGS="ip=dhcp"   # legacy shell JOS (initrd/init); needs /etc/fog/jos.conf
  FLAVOR="legacy shell JOS"
fi
# Menu mirrors the stock FOS USB image (FOGProject/fos create-usb-image.sh) so a technician gets the same
# choices FOG's PXE menu gives. the iPXE jumpstart entry is omitted (unsigned). Memtest86+ is kept but is also
# unsigned, so it is labelled as needing Secure Boot off. Timeout defaults to 5s on entry 1 (deploy/capture); set JOS_GRUB_TIMEOUT=-1 to wait.
entry() { # title extra-args
  printf 'menuentry "%s" {\n    linux  /jos/vmlinuz %s loglevel=4 %s %s\n    initrd /jos/initrd.img /jos/modules.img\n}\n' \
    "$1" "$FOS_ARGS" "$2" "${JOS_CMDLINE_EXTRA:-}"
}
{
  echo "# Generated by jos-stage-boot.sh (kernel ${KVER}, ${FLAVOR}) — do not edit by hand."
  echo "set default=0"
  echo "set timeout=${JOS_GRUB_TIMEOUT:-5}"
  echo "insmod all_video"
  echo 'echo "JOS - Jonathan'"'"'s OS"'
  # First entry (default): JOS repairs/creates the UEFI boot entries for the local disk's bootloaders, then
  # reboots into them (build/jos-localboot.sh). A bare GRUB `exit` or chainload does not help machines whose
  # firmware has no local boot entry at all.
  entry "0. Boot from local disk (create UEFI entry)" "jos_localboot=1"
  entry "1. JOS Image Deploy/Capture" ""
  if [[ -f "${INITRD%.img}.fos-tag" ]]; then
    # Everything the stock FOG PXE menu offers that FOS itself implements (bin/fog `mode=` dispatch).
    entry "2. Full Host Registration and Inventory" "mode=manreg"
    entry "3. Quick Registration and Inventory" "mode=autoreg"
    entry "4. Client System Information (Compatibility)" "mode=sysinfo"
    # Capone (FOG plugin): reads this machine's DMI value (JOS_CAPONE_DMI, default system-product-name), asks
    # the server which image is mapped to it, and deploys it. Needs the Capone plugin installed and a mapping
    # (Plugins > Capone) for the DMI value; the server side is not touched by this script.
    entry "5. Auto-deploy image by hardware inventory (Capone)" "mode=capone dmi=${JOS_CAPONE_DMI:-system-product-name}"
    entry "6. Debug Mode" "mode=onlydebug"
    # FOG menu actions that stock FOG draws in iPXE (not usable under Secure Boot); JOS asks on the console and
    # calls the same server endpoints (build/jos-fogmenu.sh).
    entry "7. Deploy Image (login, choose image)" "jos_fogmenu=deploy"
    entry "8. Join Multicast Session" "jos_fogmenu=multijoin"
    entry "9. Update Product Key" "jos_fogmenu=keyreg"
    printf 'submenu "10. Advanced / Diagnostics" {\n'
    entry "Disk Surface Test (badblocks)" "mode=badblocks"
    entry "Test Disk (checkdisk)" "mode=checkdisk"
    entry "Recover Files (PhotoRec)" "mode=photorec"
    entry "Windows Password Reset (chntpw)" "mode=winpassreset"
    entry "Wipe: fast" "mode=wipe wipemode=fast"
    entry "Wipe: normal" "mode=wipe wipemode=normal"
    entry "Wipe: full" "mode=wipe wipemode=full"
    entry "Enroll Secure Boot key (FOS kernel only; unneeded under JOS)" "mode=enrollsb"
    printf '}\n'
  fi
  entry "11. JOS Debug (verbose, isdebug=yes)" "loglevel=7 isdebug=yes"
  if [[ -f "$TFTP/jos/memtest" ]]; then
    printf 'menuentry "12. Memtest86+ (Needs Secure Boot off)" {\n    linux /jos/memtest\n}\n'
  fi
} >"$TFTP/grub/grub.cfg"
log "staged into $TFTP: $(wc -w <<<"${want[*]}") modules ($(du -h "$TFTP/jos/modules.img" | cut -f1)), kernel ${KVER}"
