#!/usr/bin/env bash
set -euo pipefail

app="/Applications/Fed Chairman Game.app"
size="1180x700"
label="capture"
out_dir="/tmp/fed-chairman-agentic-gui"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      app="$2"
      shift 2
      ;;
    --size)
      size="$2"
      shift 2
      ;;
    --label)
      label="$2"
      shift 2
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

if [[ ! -e "$app" ]]; then
  echo "App not found: $app" >&2
  exit 1
fi

repo_root="$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --show-toplevel 2>/dev/null || true)"
git_commit="unknown"
if [[ -n "$repo_root" ]]; then
  git_commit="$(git -C "$repo_root" rev-parse --short=12 HEAD)"
fi
executable="$app/Contents/MacOS/Fed Chairman Game"
executable_sha="missing"
if [[ -x "$executable" ]]; then
  executable_sha="$(shasum -a 256 "$executable" | awk '{print $1}')"
fi
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || echo unknown)"
bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || echo unknown)"
bundle_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist" 2>/dev/null || echo unknown)"
app_modified="$(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%S%z' "$app" 2>/dev/null || echo unknown)"

width="${size%x*}"
height="${size#*x}"
if [[ -z "$width" || -z "$height" || "$width" == "$height" ]]; then
  echo "Size must be WIDTHxHEIGHT, got: $size" >&2
  exit 2
fi

mkdir -p "$out_dir"
timestamp="$(date +%Y%m%d-%H%M%S)"
safe_label="$(printf '%s' "$label" | tr -c 'A-Za-z0-9._-' '-')"
path="$out_dir/${timestamp}-${safe_label}-${size}.png"

open -a "$app"
for _ in {1..20}; do
  if osascript -e 'tell application "System Events" to tell process "Fed Chairman Game" to get count of windows' >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

osascript \
  -e 'tell application "Fed Chairman Game" to activate' \
  -e 'delay 0.2' \
  -e 'tell application "System Events" to tell process "Fed Chairman Game" to set frontmost to true' \
  -e 'tell application "System Events" to tell process "Fed Chairman Game" to perform action "AXRaise" of window 1' \
  -e "tell application \"System Events\" to tell process \"Fed Chairman Game\" to set position of window 1 to {80, 80}" \
  -e "tell application \"System Events\" to tell process \"Fed Chairman Game\" to set size of window 1 to {$width, $height}"

sleep 0.5

actual_size="$(osascript -e 'tell application "System Events" to tell process "Fed Chairman Game" to get size of window 1' | tr -d ' ')"
actual_width="${actual_size%,*}"
actual_height="${actual_size#*,}"
actual_position="$(osascript -e 'tell application "System Events" to tell process "Fed Chairman Game" to get position of window 1' | tr -d ' ')"
actual_x="${actual_position%,*}"
actual_y="${actual_position#*,}"
window_id="$(/usr/bin/swift -e 'import CoreGraphics; let windows = CGWindowListCopyWindowInfo(CGWindowListOption(arrayLiteral: .optionAll), kCGNullWindowID) as! [[String: Any]]; for window in windows { if (window[kCGWindowOwnerName as String] as? String) == "Fed Chairman Game", (window[kCGWindowName as String] as? String) == "Fed Chairman Game" { print(window[kCGWindowNumber as String] as! Int); break } }' 2>/dev/null || true)"

if [[ -n "$window_id" ]]; then
  if ! screencapture -x -l"$window_id" "$path"; then
    screencapture -x -R"${actual_x},${actual_y},${actual_width},${actual_height}" "$path"
  fi
else
  screencapture -x -R"${actual_x},${actual_y},${actual_width},${actual_height}" "$path"
fi

cat <<EOF
artifact_provenance:
  git_commit: $git_commit
  app: $app
  bundle_id: $bundle_id
  version: $bundle_version
  build: $bundle_build
  app_modified: $app_modified
  executable_sha256: $executable_sha
screenshot:
EOF
echo "$path"
