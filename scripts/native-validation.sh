#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_ROOT="$REPO_ROOT/native/FedChairmanGame"
PROJECT="$NATIVE_ROOT/FedChairmanGameNative.xcodeproj"
SCHEME="FedChairmanGameNative"
DESTINATION="${FED_CHAIRMAN_XCUITEST_DESTINATION:-platform=macOS}"
DERIVED_DATA="${FED_CHAIRMAN_XCUITEST_DERIVED_DATA:-/tmp/fed-chairman-xcuitest-derived-data}"
RESULT_ROOT="${FED_CHAIRMAN_XCUITEST_RESULT_ROOT:-/tmp/fed-chairman-xcuitest-results}"
STATE_DIR="${FED_CHAIRMAN_XCUITEST_STATE_DIR:-/tmp/fed-chairman-xcuitest-guard}"
STATE_FILE="$STATE_DIR/state"
HISTORY_LOG="$STATE_DIR/history.log"
DRY_RUN="${FED_CHAIRMAN_VALIDATION_DRY_RUN:-0}"
ALLOW_REPEAT_FINAL="${FED_CHAIRMAN_ALLOW_REPEAT_UI_FINAL:-0}"
FINAL_UI_TEST="FedChairmanGameNativeUITests/NativeCockpitUITests/testLaunchStartsWithDockPanelsClosedAndPrimarySurfacesClear"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/fed-chairman-clang-module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

usage() {
  cat <<'USAGE'
Usage:
  scripts/native-validation.sh fast
  scripts/native-validation.sh gui
  scripts/native-validation.sh ui-prepare
  scripts/native-validation.sh ui-one <Target/Class/testMethod>
  scripts/native-validation.sh ui-final
  scripts/native-validation.sh reset-ui-guard

Environment:
  FED_CHAIRMAN_VALIDATION_DRY_RUN=1         Print commands without executing them.
  FED_CHAIRMAN_ALLOW_REPEAT_UI_FINAL=1      Allow repeated ui-final for the same workspace fingerprint.
  FED_CHAIRMAN_XCUITEST_DERIVED_DATA=PATH   Override reusable DerivedData path.
USAGE
}

timestamp() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

ensure_state_dir() {
  mkdir -p "$STATE_DIR" "$RESULT_ROOT" "$DERIVED_DATA"
}

log_event() {
  ensure_state_dir
  printf '%s %s\n' "$(timestamp)" "$*" >>"$HISTORY_LOG"
}

load_state() {
  local key value
  consecutive_ui_failures=0
  last_ui_final_fingerprint=""
  last_failure_signature=""
  if [[ -f "$STATE_FILE" ]]; then
    while IFS='=' read -r key value; do
      case "$key" in
        consecutive_ui_failures)
          if [[ "$value" =~ ^[0-9]+$ ]]; then
            consecutive_ui_failures="$value"
          fi
          ;;
        last_ui_final_fingerprint)
          last_ui_final_fingerprint="$value"
          ;;
        last_failure_signature)
          last_failure_signature="$value"
          ;;
      esac
    done <"$STATE_FILE"
  fi
}

save_state() {
  local tmp_file
  ensure_state_dir
  tmp_file="$(mktemp "$STATE_DIR/state.XXXXXX")"
  {
    printf 'consecutive_ui_failures=%s\n' "${consecutive_ui_failures:-0}"
    printf 'last_ui_final_fingerprint=%s\n' "${last_ui_final_fingerprint:-}"
    printf 'last_failure_signature=%s\n' "${last_failure_signature:-}"
  } >"$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
}

workspace_fingerprint() {
  local head diff_hash staged_hash
  head="$(git -C "$REPO_ROOT" rev-parse --verify HEAD 2>/dev/null || printf 'no-head')"
  diff_hash="$(git -C "$REPO_ROOT" diff --binary | shasum -a 256 | awk '{print $1}')"
  staged_hash="$(git -C "$REPO_ROOT" diff --cached --binary | shasum -a 256 | awk '{print $1}')"
  printf '%s:%s:%s\n' "$head" "$diff_hash" "$staged_hash"
}

result_bundle_path() {
  local mode safe_mode
  mode="$1"
  safe_mode="${mode//[^A-Za-z0-9_.-]/_}"
  printf '%s/%s-%s.xcresult\n' "$RESULT_ROOT" "$(date -u +%Y%m%dT%H%M%SZ)" "$safe_mode"
}

print_command() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
}

run_command() {
  print_command "$@"
  if [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi
  "$@"
}

has_prepared_ui_products() {
  [[ -d "$DERIVED_DATA/Build/Products" ]] && find "$DERIVED_DATA/Build/Products" -name '*.xctestrun' -print -quit | grep -q .
}

failure_signature() {
  local log_file
  log_file="$1"
  if grep -Eiq 'System authentication|not frontmost|occlu|accessibility|AX|kAXError|lost connection|Failed to get matching snapshot|Timed out|timeout|IDETest|test runner|UI Testing Failure' "$log_file"; then
    printf 'desktop-or-ui-automation'
  else
    printf 'xcodebuild-failure'
  fi
}

record_ui_result() {
  local mode status log_file signature
  mode="$1"
  status="$2"
  log_file="$3"
  load_state
  if [[ "$status" == "0" ]]; then
    consecutive_ui_failures=0
    last_failure_signature=""
    log_event "mode=$mode status=passed log=$log_file"
  else
    consecutive_ui_failures=$((consecutive_ui_failures + 1))
    signature="$(failure_signature "$log_file")"
    last_failure_signature="$signature"
    log_event "mode=$mode status=failed signature=$signature count=$consecutive_ui_failures log=$log_file"
    if [[ "$signature" == "desktop-or-ui-automation" ]]; then
      printf '\nXCUITest failed with a desktop/UI-automation-shaped symptom. Stop here and report it instead of patching and rerunning in a loop.\n' >&2
    fi
    if (( consecutive_ui_failures >= 2 )); then
      printf '\nXCUITest has failed %s consecutive times. Stop here and report likely flake/environment/test debt instead of looping.\n' "$consecutive_ui_failures" >&2
    fi
  fi
  save_state
}

run_xcode_ui() {
  local mode result_path log_file status
  mode="$1"
  shift
  result_path="$(result_bundle_path "$mode")"
  log_file="${result_path%.xcresult}.log"
  mkdir -p "$(dirname "$result_path")"
  print_command "$@"
  if [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi
  set +e
  "$@" -resultBundlePath "$result_path" 2>&1 | tee "$log_file"
  status=${PIPESTATUS[0]}
  set -e
  record_ui_result "$mode" "$status" "$log_file"
  return "$status"
}

mode="${1:-}"
if [[ -z "$mode" ]]; then
  usage >&2
  exit 2
fi
shift || true

case "$mode" in
  fast)
    (
      cd "$NATIVE_ROOT"
      run_command swift build
      run_command swift test
    )
    ;;
  gui)
    run_command "$REPO_ROOT/scripts/agentic-gui-verify.sh"
    ;;
  ui-prepare)
    ensure_state_dir
    run_xcode_ui "ui-prepare" \
      xcodebuild build-for-testing \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination "$DESTINATION" \
      -derivedDataPath "$DERIVED_DATA" \
      -parallel-testing-enabled NO
    ;;
  ui-one)
    test_identifier="${1:-}"
    if [[ -z "$test_identifier" ]]; then
      printf 'ui-one requires one XCTest identifier, for example:\n  FedChairmanGameNativeUITests/NativeCockpitUITests/testLaunchStartsWithDockPanelsClosedAndPrimarySurfacesClear\n' >&2
      exit 2
    fi
    if [[ "$DRY_RUN" != "1" ]] && ! has_prepared_ui_products; then
      printf 'No reusable UI test products found at %s. Run `npm run test:ui:prepare` first.\n' "$DERIVED_DATA" >&2
      exit 2
    fi
    run_xcode_ui "ui-one" \
      xcodebuild test-without-building \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination "$DESTINATION" \
      -derivedDataPath "$DERIVED_DATA" \
      -parallel-testing-enabled NO \
      -only-testing:"$test_identifier"
    ;;
  ui-final)
    ensure_state_dir
    load_state
    current_fingerprint="$(workspace_fingerprint)"
    if [[ "$ALLOW_REPEAT_FINAL" != "1" && "$last_ui_final_fingerprint" == "$current_fingerprint" ]]; then
      cat >&2 <<'BLOCKED'
Refusing to repeat ui-final for the same workspace fingerprint.
Stop and report the previous result instead of looping. To override intentionally, set FED_CHAIRMAN_ALLOW_REPEAT_UI_FINAL=1 with a named reason in the final report.
BLOCKED
      exit 2
    fi
    if [[ "$DRY_RUN" != "1" ]]; then
      last_ui_final_fingerprint="$current_fingerprint"
      save_state
    fi
    if [[ "$DRY_RUN" != "1" ]] && ! has_prepared_ui_products; then
      "$0" ui-prepare
    fi
    run_xcode_ui "ui-final" \
      xcodebuild test-without-building \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination "$DESTINATION" \
      -derivedDataPath "$DERIVED_DATA" \
      -parallel-testing-enabled NO \
      -only-testing:"$FINAL_UI_TEST"
    ;;
  reset-ui-guard)
    if [[ "$DRY_RUN" == "1" ]]; then
      printf 'Would remove %s\n' "$STATE_DIR"
    else
      rm -rf "$STATE_DIR"
      printf 'Reset XCUITest guard state at %s\n' "$STATE_DIR"
    fi
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    printf 'Unknown validation mode: %s\n\n' "$mode" >&2
    usage >&2
    exit 2
    ;;
esac
