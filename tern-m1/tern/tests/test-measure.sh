#!/usr/bin/env bash
# Sanity checks for scripts/tern-measure-idle. Works on any Linux box (needs python3 to validate JSON).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
s="$root/scripts/tern-measure-idle"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

bash -n "$s"

json=$("$s" --now --samples 2 --json --label selftest)
python3 - "$json" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
need = ["schema", "label", "timestamp", "kernel", "mem_total_mib", "idle_used_mib",
        "idle_used_min_mib", "idle_used_max_mib", "userspace_pss_mib", "residual_mib",
        "zram_mem_used_mib", "psi_mem_some_avg300", "top"]
missing = [k for k in need if k not in d]
assert not missing, f"missing keys: {missing}"
assert d["label"] == "selftest"
assert 0 < d["idle_used_mib"] < d["mem_total_mib"], "idle_used_mib out of range"
assert d["idle_used_min_mib"] <= d["idle_used_mib"] <= d["idle_used_max_mib"], "min/median/max inconsistent"
assert isinstance(d["top"], list)
PY

"$s" --now --samples 1 --label a --out "$tmp/r.jsonl" >/dev/null 2>&1
"$s" --now --samples 1 --label b --out "$tmp/r.jsonl" >/dev/null 2>&1
[ "$(wc -l < "$tmp/r.jsonl")" -eq 2 ] || { echo "FAIL: --out should append one line per run"; exit 1; }

"$s" --now --samples 1 --tty "$tmp/tty" --json >/dev/null
grep -q '^TERN_MEASURE_JSON {' "$tmp/tty" || { echo "FAIL: --tty marker line missing"; exit 1; }

if "$s" --wait abc >/dev/null 2>&1; then echo "FAIL: bad --wait accepted"; exit 1; fi
if "$s" --samples 0 >/dev/null 2>&1; then echo "FAIL: --samples 0 accepted"; exit 1; fi

echo "tern-measure-idle: all checks passed"
