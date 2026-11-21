#!/usr/bin/env bash
# Boot the Tern ISO in a window so you can look at it and click around.
# usage: tests/qemu-run.sh [-i ISO] [-m RAM_MB] [-c CPUS] [--uefi] [--gl]
set -euo pipefail
cd "$(dirname "$0")/.."

ISO=""; RAM=2048; CPUS=2; UEFI=0; GL=0
while [ $# -gt 0 ]; do
	case "$1" in
		-i) ISO="$2"; shift 2 ;;
		-m) RAM="$2"; shift 2 ;;
		-c) CPUS="$2"; shift 2 ;;
		--uefi) UEFI=1; shift ;;
		--gl) GL=1; shift ;;
		-h|--help) sed -n '2,3p' "$0"; exit 0 ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done
[ -n "$ISO" ] || ISO=$(ls -1 ./*.iso 2>/dev/null | head -n 1 || true)
[ -n "$ISO" ] && [ -f "$ISO" ] || { echo "No ISO found. Build one first (./build.sh) or pass -i FILE." >&2; exit 1; }

args=(-m "$RAM" -smp "$CPUS" -cdrom "$ISO" -boot d -vga none -nic user,model=virtio-net-pci)
if [ -w /dev/kvm ]; then args+=(-enable-kvm -cpu host); else echo "warning: no /dev/kvm, running without hardware acceleration (slow)" >&2; fi
if [ "$GL" -eq 1 ]; then args+=(-device virtio-vga-gl -display gtk,gl=on); else args+=(-device virtio-vga -display gtk); fi
if [ "$UEFI" -eq 1 ]; then
	for c in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd; do
		[ -f "$c" ] && { args+=(-drive "if=pflash,format=raw,readonly=on,file=$c"); break; }
	done
fi
exec qemu-system-x86_64 "${args[@]}"
