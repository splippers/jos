#!/bin/bash
set -euo pipefail
# Boot the staged chain in QEMU with Secure Boot enforcing (Microsoft keys) and check JOS (FOS or legacy userland) boots.
# Also runs an unsigned-bootloader control, which must be rejected. Needs: qemu-system-x86_64 ovmf sbsigntool.
# Usage: test-secureboot-vm.sh <tftp-root>      (stage it first with JOG_TFTP_ROOT=<dir> jos-stage-boot.sh)
T="$(realpath "${1:?tftp root}")"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
OVMF=/usr/share/OVMF
run() { # bootfile logfile timeout
  cp "$OVMF/OVMF_VARS_4M.ms.fd" "$W/vars.fd"
  timeout "$3" qemu-system-x86_64 -machine q35,smm=on -m 2048 $( [[ -w /dev/kvm ]] && echo -accel kvm -cpu host ) \
    -display none -serial "file:$2" -global driver=cfi.pflash01,property=secure,value=on \
    -drive if=pflash,format=raw,unit=0,file="$OVMF/OVMF_CODE_4M.secboot.fd",readonly=on \
    -drive if=pflash,format=raw,unit=1,file="$W/vars.fd" \
    -netdev user,id=n0,tftp="$T",bootfile="$1" -device virtio-net-pci,netdev=n0 -boot n -no-reboot || true
}
clean() { sed 's/\x1b\[[0-9;?=]*[a-zA-Z]//g' "$1" | tr -d '\r'; }
rc=0
run ubuntu-signed/shimx64.efi "$W/pos.log" 60
if clean "$W/pos.log" | grep -aqE 'INIT: Starting FOG task runner|Starting udevd'; then echo "PASS signed chain reached JOS /init under Secure Boot"; else echo "FAIL signed chain did not reach JOS"; rc=1; fi
cp /usr/lib/grub/x86_64-efi/monolithic/grubnetx64.efi "$W/unsigned.efi" 2>/dev/null && ln -s "$W/unsigned.efi" "$T/unsigned.efi.test" 2>/dev/null || true
run unsigned.efi.test "$W/neg.log" 25; rm -f "$T/unsigned.efi.test"
if clean "$W/neg.log" | grep -aq 'Access Denied'; then echo "PASS unsigned bootloader rejected"; else echo "FAIL control: unsigned bootloader was not rejected (is Secure Boot enforcing?)"; rc=1; fi
exit $rc
