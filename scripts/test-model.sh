#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log="$(mktemp -t fed-model-tests.XXXXXX)"
# Godot can exit zero after a script runtime error; the engine status alone is insufficient.
godot --headless --path "$root/game" --script res://tests/model_test.gd -- "$@" 2>&1 | tee "$log"
! grep -Eq '^(SCRIPT ERROR:|ERROR:|FAIL:)' "$log"
grep -q '^PASS:' "$log"
