#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/FedChairmanGameNative.xcodeproj"
SCHEME="FedChairmanGameNative"
APP_NAME="Fed Chairman Game Native.app"
RELEASE_ROOT="${FED_CHAIRMAN_NATIVE_RELEASE_ROOT:-$ROOT_DIR/release/native-local}"
ARCHIVE_PATH="$RELEASE_ROOT/FedChairmanGameNative.xcarchive"
APP_OUTPUT="$RELEASE_ROOT/$APP_NAME"
MANIFEST="$RELEASE_ROOT/release-manifest.txt"
JSON_MANIFEST="$RELEASE_ROOT/release-manifest.json"
INSTALL_APP=false

if [[ "${1:-}" == "--install" ]]; then
  INSTALL_APP=true
fi

cd "$ROOT_DIR"
mkdir -p "$RELEASE_ROOT"

for required_tool in swiftformat swiftlint xcodebuild codesign shasum ditto; do
  if ! command -v "$required_tool" >/dev/null 2>&1; then
    echo "Missing required tool: $required_tool" >&2
    exit 1
  fi
done

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
else
  echo "Missing optional tool: xcodegen. Continuing with the existing Xcode project." >&2
fi

swiftformat Sources Tests --swift-version 6.1 --lint
swiftlint lint --strict
swift test
xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -destination 'platform=macOS'

rm -rf "$ARCHIVE_PATH" "$APP_OUTPUT"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  ENABLE_HARDENED_RUNTIME=NO \
  SKIP_INSTALL=NO

ditto --norsrc "$ARCHIVE_PATH/Products/Applications/$APP_NAME" "$APP_OUTPUT"
xattr -cr "$APP_OUTPUT" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "$APP_OUTPUT"
SPCTL_RESULT="not run"
if command -v spctl >/dev/null 2>&1; then
  set +e
  SPCTL_OUTPUT="$(spctl --assess --type execute "$APP_OUTPUT" 2>&1)"
  SPCTL_EXIT=$?
  set -e
  SPCTL_RESULT="exit $SPCTL_EXIT: $SPCTL_OUTPUT"
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_OUTPUT/Contents/Info.plist")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_OUTPUT/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_OUTPUT/Contents/Info.plist")"
CATEGORY="$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' "$APP_OUTPUT/Contents/Info.plist")"
EXECUTABLE="$APP_OUTPUT/Contents/MacOS/Fed Chairman Game Native"
EXECUTABLE_SHA="$(shasum -a 256 "$EXECUTABLE" | awk '{print $1}')"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "$MANIFEST" <<MANIFEST_TEXT
Fed Chairman Game Native release candidate
Created: $CREATED_AT
Bundle ID: $BUNDLE_ID
Version: $VERSION
Build: $BUILD
Category: $CATEGORY
Archive: $ARCHIVE_PATH
App: $APP_OUTPUT
Executable SHA-256: $EXECUTABLE_SHA
Signing: ad-hoc local signing for development/beta smoke only
Hardened runtime: disabled for ad-hoc local launch compatibility
Notarization: not notarized
Gatekeeper assessment: $SPCTL_RESULT
MANIFEST_TEXT

python3 - "$JSON_MANIFEST" "$CREATED_AT" "$BUNDLE_ID" "$VERSION" "$BUILD" "$CATEGORY" "$ARCHIVE_PATH" "$APP_OUTPUT" "$EXECUTABLE_SHA" "$SPCTL_RESULT" <<'PY'
import json
import sys

manifest_path, created_at, bundle_id, version, build, category, archive, app, executable_sha, spctl_result = sys.argv[1:]
payload = {
    "product": "Fed Chairman Game Native",
    "createdAt": created_at,
    "bundleId": bundle_id,
    "version": version,
    "build": build,
    "category": category,
    "archivePath": archive,
    "appPath": app,
    "executableSha256": executable_sha,
    "signing": "ad-hoc local signing for development/beta smoke only",
    "hardenedRuntime": False,
    "notarized": False,
    "gatekeeperAssessment": spctl_result,
    "artifacts": {
        "dmg": None,
        "zip": None
    }
}
with open(manifest_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
PY

if [[ "$INSTALL_APP" == true ]]; then
  osascript -e 'tell application id "local.fed-chairman-game.native" to quit' >/dev/null 2>&1 || true
  rm -rf "/Applications/$APP_NAME"
  ditto --norsrc "$APP_OUTPUT" "/Applications/$APP_NAME"
  codesign --verify --deep --strict --verbose=2 "/Applications/$APP_NAME"
fi

echo "$APP_OUTPUT"
echo "$MANIFEST"
echo "$JSON_MANIFEST"
