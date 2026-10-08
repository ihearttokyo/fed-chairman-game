#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for test in challenge_test compound_policy_test sustained_toolkit_test balance_sheet_test balance_career_test balance_ui_test recovery_test rate_transmission_test shock_catalogue_test career_test chart_test keyboard_test compact_ui_test ui_test; do
  log="$(mktemp -t fed-game-test.XXXXXX)"
  godot --headless --path game --script "res://tests/$test.gd" --quit-after 600 2>&1 | tee "$log"
  if grep -Eq 'SCRIPT ERROR:|ERROR:|FAIL:' "$log"; then exit 1; fi
  grep -q 'PASS:' "$log"
done

# Differential comparison metrics need more disposal frames than the small suites.
log="$(mktemp -t fed-comparison-test.XXXXXX)"
godot --headless --path game --script res://tests/comparison_performance_test.gd --quit-after 6000 2>&1 | tee "$log"
if grep -Eq 'SCRIPT ERROR:|ERROR:|FAIL:' "$log"; then exit 1; fi
grep -q '^PASS: comparison count, exact parity and paired timing fixture' "$log"
