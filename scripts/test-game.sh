#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tests=(workout_bank_test workout_panel_test workout_transition_test workout_opening_test workout_career_test workout_ui_test forecast_overview_test objective_board_test help_guide_test public_advice_production_contract_test policy_advice_test dispatch_brief_test dispatch_ui_test outcome_drivers_test outcome_ui_test tooltip_test policy_review_test policy_committee_test crisis_campaign_test crisis_objectives_test music_test varied_career_test mandate_test mandate_ui_test challenge_test late_challenge_test compound_policy_test sustained_toolkit_test balance_sheet_test balance_career_test balance_ui_test recovery_test rate_transmission_test shock_catalogue_test campaign_save_slot_test career_test chart_test keyboard_test compact_ui_test ui_test transition_explanation_test routine_follow_up_test routine_ui_test comparison_performance_test music_shutdown_test)
if (( $# )); then
  # Full-career qualification is opt-in, not repeated by the default UI suite.
  case " ${tests[*]} routine_career_test public_advice_integration_test workout_bank_test workout_compatibility_test workout_panel_test workout_transition_test workout_career_test workout_ui_test workout_opening_test " in
    *" $1 "*) tests=("$1"); shift ;;
    *) echo "Unknown game test: $1" >&2; exit 2 ;;
  esac
  if [[ "${1:-}" == -- ]]; then shift; fi
fi
home="$(mktemp -d /tmp/fed-game-home.XXXXXX)"
export HOME="$(cd "$home" && pwd -P)"
export FED_GAME_TEST_HOME="$HOME"
export XDG_DATA_HOME="$HOME/.local/share" XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache"
export TMPDIR="$HOME/tmp"
mkdir -p "$TMPDIR" "$XDG_CACHE_HOME"
echo "TEST_HOME: $HOME (retained with logs for diagnosis)"
godot=(godot)
if [[ "$(uname -s)" == Darwin ]]; then
	mkdir -p "$HOME/Library/Caches"
  godot=(/usr/bin/arch -arm64 /Applications/Godot.app/Contents/MacOS/Godot)
fi
"${godot[@]}" --headless --path game --log-file "$HOME/storage-engine.log" --script res://tests/campaign_save_slot_test.gd -- --storage-only 2>&1 | tee "$HOME/storage.log"
if grep -Eq 'SCRIPT ERROR:|ERROR:|FAIL:' "$HOME/storage.log"; then exit 1; fi
grep -q '^PASS: isolated Godot user storage verified before fixture writes' "$HOME/storage.log"
for test in "${tests[@]}"; do
  frames=600
  engine_flags=(--headless)
  if [[ "$test" == music_test || "$test" == music_shutdown_test ]]; then frames=1800; engine_flags+=(--max-fps 60); fi
  if [[ "$test" == ui_test ]]; then engine_flags+=(--max-fps 60); fi
  if [[ "$test" == keyboard_test ]]; then frames=900; fi
  if [[ "$test" == comparison_performance_test ]]; then frames=6000; fi
  if [[ "$test" == public_advice_integration_test ]]; then frames=12000; fi
  log="$HOME/$test.log"
  "${godot[@]}" "${engine_flags[@]}" --path game --log-file "$HOME/$test-engine.log" --script "res://tests/$test.gd" --quit-after "$frames" -- "$@" 2>&1 | tee "$log"
  if grep -Eq 'SCRIPT ERROR:|ERROR:|FAIL:' "$log"; then exit 1; fi
  grep -q '^PASS:' "$log"
  if [[ "$test" == music_test && $# == 0 ]]; then
    "${godot[@]}" --headless --max-fps 60 --path game --log-file "$HOME/music-relaunch-engine.log" --script res://tests/music_test.gd --quit-after 1800 -- --relaunch-off 2>&1 | tee "$HOME/music-relaunch.log"
    if grep -Eq 'SCRIPT ERROR:|ERROR:|FAIL:' "$HOME/music-relaunch.log"; then exit 1; fi
    grep -q '^PASS: persisted music off survives process relaunch' "$HOME/music-relaunch.log"
    python3 -B scripts/tests/test-music-atomic.py "${godot[@]}"
  fi
  if [[ "$test" == comparison_performance_test ]]; then
    grep -q '^PASS: comparison count, exact parity and paired timing fixture' "$log"
  fi
done
