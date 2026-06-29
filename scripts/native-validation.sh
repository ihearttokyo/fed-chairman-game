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
PRE_FLIGHT_ROOT="${FED_CHAIRMAN_XCUITEST_PRE_FLIGHT_ROOT:-/tmp/fed-chairman-xcuitest-preflight}"
STATE_FILE="$STATE_DIR/state"
HISTORY_LOG="$STATE_DIR/history.log"
LOCK_DIR="$STATE_DIR/lock"
DRY_RUN="${FED_CHAIRMAN_VALIDATION_DRY_RUN:-0}"
ALLOW_REPEAT_FINAL="${FED_CHAIRMAN_ALLOW_REPEAT_UI_FINAL:-0}"
PREFLIGHT_COMMAND_TIMEOUT_SECONDS="${FED_CHAIRMAN_PREFLIGHT_COMMAND_TIMEOUT_SECONDS:-30}"
FINAL_UI_TEST="FedChairmanGameNativeUITests/NativeCockpitUITests/testLaunchStartsWithDockPanelsClosedAndPrimarySurfacesClear"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/fed-chairman-clang-module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

usage() {
  cat <<'USAGE'
Usage:
  scripts/native-validation.sh fast
  scripts/native-validation.sh gui
  scripts/native-validation.sh ui-preflight
  scripts/native-validation.sh ui-prepare
  scripts/native-validation.sh ui-one <Target/Class/testMethod>
  scripts/native-validation.sh ui-final
  scripts/native-validation.sh reset-ui-guard

Environment:
  FED_CHAIRMAN_VALIDATION_DRY_RUN=1         Print commands without executing them.
  FED_CHAIRMAN_ALLOW_REPEAT_UI_FINAL=1      Allow repeated ui-final for the same workspace fingerprint.
  FED_CHAIRMAN_PREFLIGHT_COMMAND_TIMEOUT_SECONDS=30
                                             Timeout for each ui-preflight metadata command.
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

acquire_state_lock() {
  local attempts=0
  ensure_state_dir
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    attempts=$((attempts + 1))
    if (( attempts >= 50 )); then
      printf 'Could not acquire XCUITest guard lock at %s\n' "$LOCK_DIR" >&2
      return 1
    fi
    sleep 0.1
  done
}

release_state_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
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
  acquire_state_lock
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
  release_state_lock
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

status() {
  local level="$1"
  shift
  printf '%-5s %s\n' "$level" "$*"
}

run_capture_command() {
  local label="$1"
  local output_path="$2"
  local pid watcher status timed_out=0 timeout_seconds
  shift 2
  timeout_seconds="$PREFLIGHT_COMMAND_TIMEOUT_SECONDS"

  mkdir -p "$(dirname "$output_path")"

  if [[ "$DRY_RUN" == "1" ]]; then
    status WARN "DRY_RUN: skipped command check for $label"
    print_command "$@"
    printf 'DRY_RUN\n' >"$output_path"
    return 0
  fi

  print_command "$@"
  set +e
  "$@" >"$output_path" 2>&1 &
  pid=$!
  (
    sleep "$timeout_seconds"
    if kill -0 "$pid" 2>/dev/null; then
      printf '\nCOMMAND_TIMEOUT after %ss: %s\n' "$timeout_seconds" "$label" >>"$output_path"
      kill "$pid" 2>/dev/null
      sleep 2
      kill -9 "$pid" 2>/dev/null
    fi
  ) &
  watcher=$!
  wait "$pid"
  status=$?
  if grep -q 'COMMAND_TIMEOUT after' "$output_path" 2>/dev/null; then
    timed_out=1
    status=124
  fi
  kill "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  set -e
  if (( timed_out == 1 )); then
    status FAIL "$label timed out after ${timeout_seconds}s"
  fi
  return "$status"
}

report_env_warnings() {
  local output_path="$1"
  local context="$2"
  local warning_line

  if grep -Eiq 'CoreSimulator|coresimulator|xcrun simctl|not.*frontmost|accessibility|AXError|kAXError|UI Testing Failure|timed out|permission|not authorized|not permitted' "$output_path"; then
    while IFS= read -r warning_line; do
      status WARN "$context: $warning_line"
    done < <(grep -Eia 'CoreSimulator|coresimulator|xcrun simctl|not.*frontmost|accessibility|AXError|kAXError|UI Testing Failure|timed out|permission|not authorized|not permitted' "$output_path" | head -n 5)
  fi
  return 0
}

report_hard_env_blockers() {
  local output_path="$1"
  local context="$2"
  local hard_line

  if grep -Eiq 'COMMAND_TIMEOUT after|CoreSimulator is out of date|CoreSimulatorService connection became invalid|Cannot talk to the service|System authentication is running|sandbox_apply|Operation not permitted|Trace/BPT trap|IDETest.*thwarted|lost connection|Failed to initialize simulator device set' "$output_path"; then
    while IFS= read -r hard_line; do
      status FAIL "$context: $hard_line"
    done < <(grep -Eia 'COMMAND_TIMEOUT after|CoreSimulator is out of date|CoreSimulatorService connection became invalid|Cannot talk to the service|System authentication is running|sandbox_apply|Operation not permitted|Trace/BPT trap|IDETest.*thwarted|lost connection|Failed to initialize simulator device set' "$output_path" | head -n 5)
    return 1
  fi

  return 0
}

check_writeable_tmp_dir() {
  local path="$1"
  local label="$2"
  local probe_file

  if [[ "$DRY_RUN" == "1" ]]; then
    status WARN "$label: DRY_RUN, write check skipped"
    return 0
  fi

  probe_file="$path/.fed-chairman-validation-write-check"
  if mkdir -p "$path" && : >"$probe_file" && rm -f "$probe_file"; then
    status PASS "$label"
    return 0
  fi

  status FAIL "$label"
  return 1
}

run_preflight() {
  local failures=0
  local preflight_run_root
  local destination_output
  local simctl_output
  local scheme_path
  local platform
  local destination_match

  platform="${DESTINATION#platform=}"
  destination_match="${platform%%,*}"
  scheme_path="$PROJECT/xcshareddata/xcschemes/$SCHEME.xcscheme"
  mkdir -p "$PRE_FLIGHT_ROOT"
  preflight_run_root="$(mktemp -d "$PRE_FLIGHT_ROOT/run-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")"
  destination_output="$preflight_run_root/metadata-destinations.log"
  simctl_output="$preflight_run_root/simctl.log"

  status INFO "Running ui-preflight checks (non-launch)"

  if command -v xcodebuild >/dev/null 2>&1; then
    status PASS "xcodebuild binary found"
  else
    status FAIL "xcodebuild binary missing"
    ((failures += 1))
  fi

  if [[ -d "$PROJECT" ]]; then
    status PASS "Project exists: $PROJECT"
  else
    status FAIL "Project not found: $PROJECT"
    ((failures += 1))
  fi

  if ! check_writeable_tmp_dir "$DERIVED_DATA" "DerivedData path writable"; then
    ((failures += 1))
  fi
  if ! check_writeable_tmp_dir "$RESULT_ROOT" "Result root writable"; then
    ((failures += 1))
  fi
  if ! check_writeable_tmp_dir "$STATE_DIR" "State cache path writable"; then
    ((failures += 1))
  fi
  if ! check_writeable_tmp_dir "$CLANG_MODULE_CACHE_PATH" "Clang module cache writable"; then
    ((failures += 1))
  fi
  if ! check_writeable_tmp_dir "$PRE_FLIGHT_ROOT" "Preflight scratch path writable"; then
    ((failures += 1))
  fi

  if [[ -f "$scheme_path" ]]; then
    status PASS "Shared scheme found: $SCHEME"
  else
    status FAIL "Shared scheme not found: $scheme_path"
    ((failures += 1))
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    run_capture_command "xcodebuild -showdestinations" "$destination_output" xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations
    status WARN "Destination metadata validation skipped under DRY_RUN"
  elif run_capture_command "xcodebuild -showdestinations" "$destination_output" xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations; then
    if grep -Eiq "platform:[[:space:]]*$destination_match" "$destination_output"; then
      status PASS "Destination metadata includes: $destination_match"
    else
      status WARN "Destination '$DESTINATION' not shown by xcodebuild -showdestinations"
    fi
  else
    status FAIL "xcodebuild -showdestinations failed"
    ((failures += 1))
  fi
  report_env_warnings "$destination_output" "xcodebuild -showdestinations"
  if [[ "$destination_match" == "macOS" ]]; then
    status INFO "Ignoring CoreSimulator diagnostics for macOS destination preflight"
  elif ! report_hard_env_blockers "$destination_output" "xcodebuild -showdestinations"; then
    ((failures += 1))
  fi

  if [[ "$destination_match" == "macOS" ]]; then
    status INFO "Skipping simctl diagnostics for macOS destination preflight"
  elif command -v xcrun >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == "1" ]]; then
      run_capture_command "xcrun simctl" "$simctl_output" xcrun simctl list devices
      status WARN "xcrun simctl validation skipped under DRY_RUN"
    elif run_capture_command "xcrun simctl" "$simctl_output" xcrun simctl list devices; then
      status PASS "xcrun simctl executable reachable"
    else
      status WARN "xcrun simctl command failed; environment may still be usable for macOS UI tests"
    fi

    if [[ "$DRY_RUN" != "1" ]]; then
      if grep -Eiq 'Error|Unable|unavailable|not found' "$simctl_output"; then
        status WARN "xcrun simctl output indicates environment issues"
      fi
      report_env_warnings "$simctl_output" "xcrun simctl list devices"
      if ! report_hard_env_blockers "$simctl_output" "xcrun simctl list devices"; then
        ((failures += 1))
      fi
    fi
  else
    status WARN "xcrun not found; environment simulator diagnostics may be incomplete"
  fi

  if (( failures > 0 )); then
    status FAIL "Preflight failed with $failures blocker(s). Do not run ui-prepare/ui-one/ui-final until resolved."
    return 2
  fi

  status PASS "ui-preflight passed; continue guarded UI commands"
  return 0
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
  ui-preflight)
    run_preflight
    ;;
  ui-prepare)
    run_preflight
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
    run_preflight
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
    run_preflight
    ensure_state_dir
    current_fingerprint="$(workspace_fingerprint)"
    load_state
    if [[ "$DRY_RUN" != "1" ]]; then
      acquire_state_lock
      load_state
    fi
    if [[ "$ALLOW_REPEAT_FINAL" != "1" && "$last_ui_final_fingerprint" == "$current_fingerprint" ]]; then
      if [[ "$DRY_RUN" != "1" ]]; then
        release_state_lock
      fi
      cat >&2 <<'BLOCKED'
Refusing to repeat ui-final for the same workspace fingerprint.
Stop and report the previous result instead of looping. To override intentionally, set FED_CHAIRMAN_ALLOW_REPEAT_UI_FINAL=1 with a named reason in the final report.
BLOCKED
      exit 2
    fi
    if [[ "$DRY_RUN" != "1" ]]; then
      release_state_lock
    fi
    if [[ "$DRY_RUN" != "1" ]] && ! has_prepared_ui_products; then
      "$0" ui-prepare
    fi
    if [[ "$DRY_RUN" != "1" ]]; then
      acquire_state_lock
      last_ui_final_fingerprint="$current_fingerprint"
      save_state
      release_state_lock
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
