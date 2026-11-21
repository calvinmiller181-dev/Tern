#!/usr/bin/env bash
# Headless, repeatable baseline: boots the ISO with tern.measure=1, waits, collects one JSON line.
# usage: tests/qemu-measure.sh [-i ISO] [-m RAM_MB] [-c CPUS] [-w WAIT_SECONDS] [-l LABEL] [-o results.jsonl]
#
# The ISO's kernel command line can't be edited from outside, so this extracts the kernel and
# initrd from the ISO and boots them directly with the extra tern.* parameters.
set -euo pipefail
cd "$(dirname "$0")/.."

ISO=""; RAM=1024; CPUS=2; WAIT=300; LABEL="qemu"; OUT="results/baseline.jsonl"
while [ $# -gt 0 ]; do
	case "$1" in
		-i) ISO="$2"; shift 2 ;;
		-m) RAM="$2"; shift 2 ;;
		-c) CPUS="$2"; shift 2 ;;
		-w) WAIT="$2"; shift 2 ;;
		-l) LABEL="$2"; shift 2 ;;
		-o) OUT="$2"; shift 2 ;;
		-h|--help) sed -n '2,3p' "$0"; exit 0 ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done
[ -n "$ISO" ] || ISO=$(ls -1 ./*.iso 2>/dev/null | head -n 1 || true)
[ -n "$ISO" ] && [ -f "$ISO" ] || { echo "No ISO found. Build one first (./build.sh) or pass -i FILE." >&2; exit 1; }
command -v xorriso >/dev/null || { echo "xorriso is required (sudo apt install xorriso)" >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
xorriso -osirrox on -indev "$ISO" -extract /live "$work/live" >/dev/null 2>&1 || { echo "could not read /live from $ISO" >&2; exit 1; }
kernel=$(ls -1 "$work"/live/vmlinuz* 2>/dev/null | head -n 1 || true)
initrd=$(ls -1 "$work"/live/initrd* 2>/dev/null | head -n 1 || true)
[ -n "$kernel" ] && [ -n "$initrd" ] || { echo "kernel/initrd not found under /live in the ISO" >&2; exit 1; }

kvm=(); if [ -w /dev/kvm ]; then kvm=(-enable-kvm -cpu host); else echo "warning: no /dev/kvm; this will be slow and the timing is not comparable" >&2; fi
serial="$work/serial.log"
mkdir -p "$(dirname "$OUT")"

echo "Booting headless: ${RAM} MiB RAM, ${CPUS} CPUs, waiting ${WAIT}s inside the guest..."
timeout $((WAIT + 300)) qemu-system-x86_64 "${kvm[@]}" -m "$RAM" -smp "$CPUS" \
	-kernel "$kernel" -initrd "$initrd" -cdrom "$ISO" \
	-append "boot=live components quiet username=tern hostname=tern tern.measure=1 tern.measure_wait=$WAIT" \
	-vga none -device virtio-vga -display none -nic user,model=virtio-net-pci \
	-serial "file:$serial" -no-reboot || true

line=$(tr -d '\r' < "$serial" | grep -a '^TERN_MEASURE_JSON ' | tail -n 1 | sed 's/^TERN_MEASURE_JSON //' || true)
if [ -z "$line" ]; then
	echo "No measurement came back. Try tests/qemu-run.sh to watch the boot, and see README 'If the first build misbehaves'." >&2
	exit 1
fi
printf '%s\n' "$line" | sed "s/\"label\":\"[^\"]*\"/\"label\":\"$LABEL\"/" >> "$OUT"
echo "Saved to $OUT"
python3 - "$OUT" <<'PY' 2>/dev/null || tail -n 1 "$OUT"
import json, sys
d = [json.loads(l) for l in open(sys.argv[1]) if l.strip()][-1]
print(f"idle footprint: {d['idle_used_mib']} MiB of {d['mem_total_mib']} MiB  (label={d['label']}, userspace PSS {d['userspace_pss_mib']} MiB)")
PY
