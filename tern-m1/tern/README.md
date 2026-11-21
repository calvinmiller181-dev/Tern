# Tern - Milestone 1: bootable baseline + repeatable measurement

"Tern" is a placeholder name (do a trademark check before committing to one).

**M1 goal:** a bootable Debian-based live ISO with a lean Wayland session, and a measurement harness
that gives every later change a before/after number. No custom shell, Optimization Mode or assistant yet;
those are M2-M5. The desktop here (labwc + waybar + foot) is deliberately off-the-shelf so we know the
cost of "a normal lean desktop" before building our own.

## What has and hasn't been verified

| Part | Status |
|---|---|
| `scripts/tern-measure-idle` | Written and self-tested on Linux (`tests/test-measure.sh` passes) |
| `build.sh` tuning on/off + build-stamp logic | Tested against a stub `lb` |
| `rc.xml` / `config.jsonc` | Parsed as valid XML / JSON |
| **The ISO build itself, booting, labwc/waybar behaviour, QEMU scripts** | **NOT run.** The authoring sandbox had no network, no Debian host and no QEMU. Expect a few small fixes on the first real build (see below). |

## Requirements

A **Debian 12 or 13** host or VM (Ubuntu hosts can work but are not the supported path), ~20 GB free disk,
a fast connection (first build downloads roughly 1-2 GB), and:

    sudo apt install live-build debootstrap debian-archive-keyring xorriso squashfs-tools \
                     qemu-system-x86 ovmf jq python3

## Quick start

    ./build.sh                  # tuned build  -> tern-amd64.hybrid.iso
    tests/qemu-run.sh -m 2048   # boot it in a window; Super+Enter = terminal, Super+Space = launcher
    sudo tern-measure-idle --wait 300 --label tuned     # inside the VM, with nothing open

Headless and repeatable (the one to use for comparisons):

    tests/qemu-measure.sh -m 1024 -w 300 -l tuned
    ./build.sh --no-tuning && tests/qemu-measure.sh -m 1024 -w 300 -l no-tuning

Results append to `results/baseline.jsonl`, one JSON line per run. Compare runs with, for example:

    jq -r '[.label, .idle_used_mib, .userspace_pss_mib, .zram_mem_used_mib] | @tsv' results/baseline.jsonl

Live session login: user `tern`, auto-login on tty1. `sudo` should work without a password in the live session.

## How to read the numbers

- **Idle footprint = MemTotal - MemAvailable**, sampled after the system has been idle for `--wait` seconds
  (median of 5 samples). This is the only number we quote as "RAM use".
- Per-process **PSS** shows who is responsible (shared pages are split fairly). The residual is the kernel,
  drivers, the RAM-backed live overlay and rounding, and is approximate.
- The live ISO keeps its writable overlay in RAM, so **compare live-to-live**, never live-to-installed.
- Display resolution changes the result (one 4K buffer is about 33 MB). Always record it; the script does.
- `--no-tuning` omits `tuning/` (zram, sysctl, journald limits). Without the zram config there should be no
  zram swap (confirm with `swapon --show`). Run both and publish both. Don't assume the tuning helps.
- This VM-based number is a **repeatable proxy**, not what your laptop will show. Measure real hardware too.

## M1 is done when

1. `./build.sh` produces an ISO and it boots to a desktop in QEMU at 1 GB RAM.
2. `tests/qemu-measure.sh` returns a JSON line twice in a row and the two idle numbers are within a few MiB.
3. You have one tuned and one no-tuning result saved, and the top-PSS list tells you where the memory goes.

## If the first build misbehaves (most likely culprits)

- **A package name is rejected** by apt (first suspects: `fuzzel`, `firmware-linux`, `libegl-mesa0`, `labwc`):
  remove or rename that line in `config/package-lists/`. The error is in `build.log`.
- **An `lb config` option is rejected:** option names shift between live-build versions; check
  `man lb_config` and edit `auto/config`.
- **Hook did not run:** hooks live in `config/hooks/live/` for current live-build; older versions used
  `config/hooks/normal/`.
- **Boots to a text login instead of the desktop:** check `~/.bash_profile` ran (it only starts labwc on tty1)
  and `journalctl -b` / run `labwc` by hand to see its error. In a VM without 3D, `WLR_RENDERER_ALLOW_SOFTWARE=1`
  (already set in `~/.config/labwc/environment`) is what lets it start with software rendering.
- **Auto-login did not happen:** the username in `autologin.conf` must match `username=` in `auto/config`.
- **`tests/qemu-measure.sh` returns nothing:** run `tests/qemu-run.sh` to watch the boot; the measurement unit
  only runs when `tern.measure=1` is on the kernel command line, which that script passes itself.

## Layout

    auto/config                         all `lb config` flags in one place
    config/package-lists/               what goes in the image (base / desktop / apps)
    config/includes.chroot/             files copied into the image (session config, autologin, measure unit)
    config/hooks/live/                  build-time hook (mask timers, enable measure unit)
    tuning/                             zram + sysctl + journald, switchable per build
    scripts/tern-measure-idle           the measurement tool (copied into the image by build.sh)
    tests/                              self-test, interactive QEMU, headless measuring QEMU
    build.sh                            stamps the build, applies tuning on/off, runs lb

## Safety notes

- The tty1 auto-login and the live user's known password are for the live ISO only. The installer (M6)
  must not ship them.
- The ISO volume and publisher strings say "unofficial" on purpose; don't imply Debian endorsement.

## What comes next

| Milestone | Deliverable |
|---|---|
| M2 | Our own shell (bar, dock, launcher, notifications) replacing waybar; design-token theming |
| M3 | `ternd` + Optimization Mode, using this harness to report measured before/after |
| M4 | Settings app, accessibility, per-app resource controls |
| M5 | Assistant app (bring your own Anthropic API key), permission broker |
| M6 | Installer, signed repo, encryption, A/B updates |
