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
sleep 1

osascript \
  -e 'tell application "System Events" to tell process "Fed Chairman Game" to set frontmost to true' \
  -e "tell application \"System Events\" to tell process \"Fed Chairman Game\" to set position of window 1 to {80, 80}" \
  -e "tell application \"System Events\" to tell process \"Fed Chairman Game\" to set size of window 1 to {$width, $height}"

sleep 0.5

actual_size="$(osascript -e 'tell application "System Events" to tell process "Fed Chairman Game" to get size of window 1' | tr -d ' ')"
actual_width="${actual_size%,*}"
actual_height="${actual_size#*,}"

screencapture -x -R"80,80,${actual_width},${actual_height}" "$path"

echo "$path"
