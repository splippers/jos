#!/bin/bash
set -euo pipefail
# Build the JOS initramfs from the official FOS userland instead of re-implementing it.
#
# FOS (https://github.com/FOGProject/fos) ships init.xz: an ext2 root filesystem holding every FOG client
# script (fog, fog.download, fog.upload, fog.checkin, ...), partclone, udpcast, NFS, udhcpc, udev, kmod.
# FOS only differs from JOS in the kernel: FOS builds its own (everything built in, signed with a per-site key
# that each machine must enrol). JOS runs the same userland under the Canonical-signed kernel, with the matching
# signed modules supplied separately (modules.img, see scripts/jog-stage-jos-boot.sh); FOS's udev + kmod load them.
#
# The FOG server stays the single source of truth: GRUB passes only `web=` and `boottype=usb`, and FOS's `fog`
# script fetches this host's task from the server (status/hostgetkey.php, service/hostinfo.php) exactly as the
# stock FOS USB image does. No API tokens in the image.
#
# Env: FOS_TAG (release to pin)   OUT (build/out/initrd.img)   FOS_CACHE (build/tmp/fos)
# Output is GPL-3 FOS code: it is gitignored, never commit it.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOS_TAG="${FOS_TAG:-20261005-221112}"   # a non-EXP release; bump deliberately and re-run the VM test
CACHE="${FOS_CACHE:-$HERE/tmp/fos}"
OUT="${OUT:-$HERE/out/initrd.img}"
URL="https://github.com/FOGProject/fos/releases/download/${FOS_TAG}"

command -v debugfs >/dev/null || { echo "need e2fsprogs (debugfs)" >&2; exit 1; }
mkdir -p "$CACHE/$FOS_TAG" "$(dirname "$OUT")"
cd "$CACHE/$FOS_TAG"
if [[ ! -f init.xz ]]; then
  curl -fL -o init.xz "$URL/init.xz"; curl -fL -o init.xz.sha256 "$URL/init.xz.sha256"
fi
sha256sum -c init.xz.sha256

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
xz -dc init.xz >"$W/init.ext2"
# debugfs reads the image without root or a loop mount. Its chown errors are expected as non-root; cpio -R 0:0 fixes ownership.
mkdir -p "$W/root"
debugfs -R "rdump / $W/root" "$W/init.ext2" >/dev/null 2>"$W/rdump.err" || true
[[ -x "$W/root/bin/busybox" && -f "$W/root/usr/share/fog/lib/funcs.sh" ]] || { echo "FOS rootfs extraction failed" >&2; cat "$W/rdump.err" >&2; exit 1; }
rm -rf "$W/root/lost+found"

# FOS boots from root=/dev/ram0, where the kernel itself mounts devtmpfs before PID 1. As a plain initramfs the
# Canonical kernel does not, so /init mounts the pseudo filesystems and then hands over to FOS's own init
# (BusyBox init -> /etc/inittab -> rcS -> S99fog).
cp "$HERE/jos-report-boot-facts.sh" "$W/root/jos-report-boot-facts.sh"
chmod 0755 "$W/root/jos-report-boot-facts.sh"
# "Boot from local disk" fallback: runs after udev/modules (S10/S11) and before the FOG client (S99fog), and only
# acts when GRUB passed jos_localboot=1 (see scripts/jog-stage-jos-boot.sh).
cp "$HERE/jos-localboot.sh" "$W/root/etc/init.d/S98jos-localboot"
chmod 0755 "$W/root/etc/init.d/S98jos-localboot"
# FOG menu actions that need a login or prompt (deploy image, join multicast, product key); same slot, gated on
# jos_fogmenu=<action>. S97 so it runs after the network is up and before S99fog.
cp "$HERE/jos-fogmenu.sh" "$W/root/etc/init.d/S97jos-fogmenu"
chmod 0755 "$W/root/etc/init.d/S97jos-fogmenu"
cat >"$W/root/init" <<'INIT'
#!/bin/busybox sh
/bin/busybox mount -t devtmpfs devtmpfs /dev
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sysfs /sys
/jos-report-boot-facts.sh &
exec /sbin/init
INIT
chmod 0755 "$W/root/init"
(cd "$W/root" && find . | cpio -H newc -o -R 0:0 --quiet | gzip -9) >"$OUT"
echo "$FOS_TAG" >"${OUT%.img}.fos-tag"
echo "built $OUT from FOS $FOS_TAG ($(du -h "$OUT" | cut -f1))"
