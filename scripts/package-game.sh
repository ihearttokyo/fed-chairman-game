#!/usr/bin/env bash
# Official templates are universal; distribution is Apple Silicon only.
set -euo pipefail
if [[ $# != 3 ]]; then
  echo 'Usage: package-game.sh NEW_OUTPUT_DIRECTORY DEVELOPER_ID_IDENTITY TEAM_ID' >&2
  exit 1
fi
if [[ -e "$1" || -L "$1" ]]; then
  echo 'Refusing to replace existing output' >&2
  exit 1
fi
mkdir -p "$(dirname "$1")"
mkdir "$1"
out="$(cd "$1" && pwd)"
cd "$(dirname "$0")/.."
app="$out/The Chair — Federal Reserve Policy Lab.app"
engine="$(command -v godot)"
python3 scripts/tests/verify-godot-toolchain.py "$engine" | tee "$out/toolchain.log"
"$engine" --headless --log-file "$out/export-engine.log" --path game --export-release 'macOS universal staging' "$app" 2>&1 | tee "$out/export.log"
if grep -Eq 'SCRIPT ERROR:|ERROR:|FAIL:' "$out/export.log"; then exit 1; fi
binary="$app/Contents/MacOS/The Chair — Federal Reserve Policy Lab"
lipo "$binary" -thin arm64 -output "$binary"
python3 - "$app/Contents/Info.plist" <<'PY'
import plistlib
import sys
from pathlib import Path
path = Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
info['LSMinimumSystemVersionByArchitecture'].pop('x86_64', None)
path.write_bytes(plistlib.dumps(info))
PY
codesign --force --timestamp --options runtime --sign "$2" "$app"
python3 scripts/tests/verify-game-release.py "$app" "$3" | tee "$out/verification.log"
ditto -c -k --keepParent "$app" "$out/The Chair — Apple Silicon.zip"
shasum -a 256 "$out/The Chair — Apple Silicon.zip"
echo 'Signed Apple Silicon package created. Apple notarization is a separate step.'
