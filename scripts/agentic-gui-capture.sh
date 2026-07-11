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
provenance_candidates=()
for candidate in \
  "$app/Contents/Resources/build-provenance.json" \
  "$(dirname "$app")/build-provenance.json" \
  "${app%.app}.release-manifest.json" \
  "$(dirname "$app")/release-manifest.json" \
  "${app%.app}.production-manifest.json" \
  "$(dirname "$app")/production-manifest.json"
do
  if [[ -f "$candidate" ]]; then
    provenance_candidates+=("$candidate")
  fi
done
if [[ ${#provenance_candidates[@]} -eq 0 ]]; then
  echo "No artifact provenance manifest found for: $app" >&2
  exit 1
fi
if [[ ${#provenance_candidates[@]} -ne 1 ]]; then
  echo "Ambiguous artifact provenance: found multiple manifests for $app" >&2
  printf '  %s\n' "${provenance_candidates[@]}" >&2
  exit 1
fi
provenance_manifest="${provenance_candidates[0]}"
IFS=$'\t' read -r artifact_git_head artifact_dirty artifact_fingerprint artifact_executable_sha < <(
  python3 - "$provenance_manifest" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)
print("\t".join([
    str(payload.get("sourceGitHead", "unknown")),
    str(payload.get("sourceDirty", True)).lower(),
    str(payload.get("sourceFingerprint", "unknown")),
    str(payload.get("executableSha256", "missing")),
]))
PY
)
if [[ "$artifact_executable_sha" != "$executable_sha" ]]; then
  echo "Artifact provenance hash does not match the app executable." >&2
  exit 1
fi
if [[ -n "$repo_root" ]]; then
  # shellcheck source=../native/FedChairmanGame/scripts/source-provenance.sh
  source "$repo_root/native/FedChairmanGame/scripts/source-provenance.sh"
  collect_source_provenance "$repo_root"
  if [[ "$artifact_fingerprint" != "$SOURCE_FINGERPRINT" ]]; then
    echo "Artifact build-input fingerprint does not match the current app source tree." >&2
    exit 1
  fi
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

process_name="Fed Chairman Game"

window_info() {
  /usr/bin/swift -e '
    import Foundation
    import CoreGraphics
    let windows = CGWindowListCopyWindowInfo(CGWindowListOption(arrayLiteral: .optionAll), kCGNullWindowID) as? [[String: Any]] ?? []
    for window in windows {
      guard (window[kCGWindowOwnerName as String] as? String) == "Fed Chairman Game",
            (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
            (window[kCGWindowIsOnscreen as String] as? NSNumber)?.intValue == 1,
            let number = (window[kCGWindowNumber as String] as? NSNumber)?.intValue,
            let bounds = window[kCGWindowBounds as String] as? [String: Any]
      else { continue }
      let x = (bounds["X"] as? NSNumber)?.intValue ?? 0
      let y = (bounds["Y"] as? NSNumber)?.intValue ?? 0
      let width = (bounds["Width"] as? NSNumber)?.intValue ?? 0
      let height = (bounds["Height"] as? NSNumber)?.intValue ?? 0
      print("\(number),\(x),\(y),\(width),\(height)")
      break
    }
  ' 2>/dev/null || true
}

screenshot_has_visible_pixels() {
  /usr/bin/swift - "$path" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO

let path = CommandLine.arguments[1]
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    exit(2)
}

let width = min(96, image.width)
let height = min(96, image.height)
let bytesPerPixel = 4
let bytesPerRow = width * bytesPerPixel
var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

guard let context = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
) else {
    exit(2)
}

context.interpolationQuality = .none
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

var visiblePixels = 0
for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
    let red = Int(pixels[index])
    let green = Int(pixels[index + 1])
    let blue = Int(pixels[index + 2])
    if red + green + blue > 30 {
        visiblePixels += 1
    }
}

exit(visiblePixels > max(24, (width * height) / 200) ? 0 : 1)
SWIFT
}

osascript -e 'tell application id "local.fed-chairman-game" to quit' >/dev/null 2>&1 || true
sleep 0.5
open -F -n --env "FED_CHAIRMAN_TEST_WINDOW_SIZE=$size" "$app"
osascript -e 'tell application id "local.fed-chairman-game" to activate' >/dev/null 2>&1 || true
for _ in {1..80}; do
  if [[ -n "$(window_info)" ]]; then
    break
  fi
  sleep 0.25
done

cg_info="$(window_info)"
if [[ -z "$cg_info" ]]; then
  echo "Timed out waiting for a visible $process_name window from: $app" >&2
  exit 1
fi

sleep 0.5
cg_info="$(window_info)"

IFS=, read -r window_id actual_x actual_y actual_width actual_height <<<"$cg_info"

capture_mode="window"
if [[ -z "$window_id" ]]; then
  echo "The intended app window has no captureable window id." >&2
  exit 1
fi
if ! screencapture -x -l"$window_id" "$path" 2>/dev/null; then
  echo "Could not capture the intended Fed Chairman Game window." >&2
  exit 1
fi

if ! screenshot_has_visible_pixels; then
  echo "Screenshot capture produced an unusable black frame: $path" >&2
  echo "Grant Screen Recording permission or use Computer Use for visual validation." >&2
  exit 1
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
  provenance_manifest: $provenance_manifest
  artifact_source_commit: $artifact_git_head
  artifact_source_dirty: $artifact_dirty
  artifact_source_fingerprint: $artifact_fingerprint
  capture_mode: $capture_mode
screenshot:
EOF
echo "$path"
