#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for test in career_test chart_test ui_test; do
  log="$(mktemp -t fed-game-test.XXXXXX)"
  godot --headless --path game --script "res://tests/$test.gd" --quit-after 600 2>&1 | tee "$log"
  if grep -Eq 'SCRIPT ERROR:|ERROR:|FAIL:' "$log"; then exit 1; fi
  grep -q 'PASS:' "$log"
done
