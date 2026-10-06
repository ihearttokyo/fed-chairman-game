#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-full}" in
  pilot) set -- --pilot; mode=pilot; counts='attempted=7 completed=7 transitions=168 paired=3' ;;
  full) set --; mode=full; counts='attempted=1100 completed=1100 transitions=264000 paired=100' ;;
  *) echo 'Expected pilot or full' >&2; exit 2 ;;
esac
log="$(mktemp -t fed-curated-diagnostic.XXXXXX)"
timeout 1200s godot --headless --path game --script res://tests/curated_career_diagnostic.gd -- "$@" 2>&1 | tee "$log"
if grep -Eq 'SCRIPT ERROR:|ERROR:|FAIL:' "$log"; then exit 1; fi
grep -Eq "^COUNTS mode=$mode $counts .*failures=0$" "$log"
grep -qx "PASS: current-source curated career diagnostic $mode" "$log"
