#!/usr/bin/env bash
# Build the Tern M1 live ISO.
# Needs a Debian 12/13 host or VM with: live-build debootstrap debian-archive-keyring xorriso squashfs-tools
# usage: ./build.sh [--no-tuning] [--purge-cache]
set -euo pipefail
cd "$(dirname "$0")"

TUNING=1; PURGE=0
for a in "$@"; do
	case "$a" in
		--no-tuning) TUNING=0 ;;
		--purge-cache) PURGE=1 ;;
		-h|--help) sed -n '2,5p' "$0"; exit 0 ;;
		*) echo "unknown option: $a" >&2; exit 2 ;;
	esac
done

command -v lb >/dev/null || { echo "live-build not found. On Debian: sudo apt install live-build debootstrap debian-archive-keyring xorriso squashfs-tools" >&2; exit 1; }
SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"

# permissions can be lost when unpacking a zip
chmod +x auto/config scripts/tern-measure-idle tests/*.sh config/hooks/live/*.hook.chroot

# single source of truth for the measurement script
install -D -m 0755 scripts/tern-measure-idle config/includes.chroot/usr/local/bin/tern-measure-idle

# tuning on/off (kept outside config/ so it can be switched per build)
while IFS= read -r -d '' f; do
	rel=${f#tuning/}
	if [ "$TUNING" -eq 1 ]; then install -D -m 0644 "$f" "config/includes.chroot/$rel"; else rm -f "config/includes.chroot/$rel"; fi
done < <(find tuning -type f -print0)

# build stamp
build_id=$(date -u +%Y%m%dT%H%M%SZ)
git_id=$(git rev-parse --short HEAD 2>/dev/null || echo nogit)
install -d config/includes.chroot/etc
cat > config/includes.chroot/etc/tern-release <<EOF
TERN_VERSION=0.1.0-m1
TERN_BUILD=${build_id}-${git_id}
TERN_TUNING=$([ "$TUNING" -eq 1 ] && echo on || echo off)
EOF

if [ "$PURGE" -eq 1 ]; then $SUDO lb clean --purge; else $SUDO lb clean; fi
lb config
$SUDO lb build 2>&1 | tee build.log

iso=$(ls -1 ./*.iso 2>/dev/null | head -n 1 || true)
[ -n "$iso" ] || { echo "Build finished without an ISO. Check build.log." >&2; exit 1; }
$SUDO chown "$(id -u):$(id -g)" "$iso" 2>/dev/null || true
sha256sum "$iso" | tee "$iso.sha256"
ls -lh "$iso"
echo "Next: tests/qemu-run.sh   (look at it)   |   tests/qemu-measure.sh   (headless baseline)"
