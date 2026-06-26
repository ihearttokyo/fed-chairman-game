#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --show-toplevel)"
capture_script="$repo_root/scripts/agentic-gui-capture.sh"
out_dir="${FED_CHAIRMAN_AGENTIC_GUI_OUT_DIR:-/tmp/fed-chairman-agentic-gui}"
app="${FED_CHAIRMAN_AGENTIC_GUI_APP:-}"
build_app=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      app="$2"
      build_app=false
      shift 2
      ;;
    --skip-build)
      build_app=false
      shift
      ;;
    --out-dir)
      out_dir="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$build_app" == true ]]; then
  app="$("$repo_root/native/FedChairmanGame/scripts/package-native-dev-app.sh" | tail -n 1)"
elif [[ -z "$app" ]]; then
  app="/Applications/Fed Chairman Game.app"
fi

if [[ ! -x "$capture_script" ]]; then
  echo "Missing capture script: $capture_script" >&2
  exit 1
fi
if [[ ! -d "$app" ]]; then
  echo "App not found: $app" >&2
  exit 1
fi

osascript -e 'tell application id "local.fed-chairman-game" to quit' >/dev/null 2>&1 || true
sleep 0.5

mkdir -p "$out_dir"
evidence="$out_dir/agentic-gui-evidence-$(date +%Y%m%d-%H%M%S).txt"

record() {
  printf '%s\n' "$*" | tee -a "$evidence"
}

capture() {
  local size="$1"
  local label="$2"
  record
  record "capture: $label ($size)"
  "$capture_script" --app "$app" --size "$size" --label "$label" --out-dir "$out_dir" | tee -a "$evidence"
}

record "Fed Chairman Game agentic GUI evidence run"
record "repo: $repo_root"
record "commit: $(git -C "$repo_root" rev-parse --short=12 HEAD)"
record "app: $app"
record "out_dir: $out_dir"

capture "1180x700" "first-launch"
capture "1360x860" "standard-responsive"
capture "1600x1000" "large-responsive"

record
record "required_visual_review:"
record "  - Inspect each screenshot path above before declaring UI/UX complete."
record "  - Check readability, clipping, occlusion, hierarchy, affordances, chart stability, and panel reachability."
record "  - Use Computer Use to interact with at least one decision plus Newspaper, Help, and Settings."
record "  - Run npm run test:ui separately only as a final XCUITest regression gate when the desktop is clear."
record "evidence_file: $evidence"
