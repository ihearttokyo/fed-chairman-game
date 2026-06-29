#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/../.." && pwd)"
PROJECT="$ROOT_DIR/FedChairmanGameNative.xcodeproj"
SCHEME="FedChairmanGameNative"
APP_NAME="Fed Chairman Game.app"
LEGACY_APP_NAME="Fed Chairman Game Native.app"
RELEASE_ROOT="${FED_CHAIRMAN_NATIVE_PRODUCTION_ROOT:-$ROOT_DIR/release/native-production}"
ARCHIVE_PATH="$RELEASE_ROOT/FedChairmanGameNative.xcarchive"
APP_OUTPUT="$RELEASE_ROOT/$APP_NAME"
MANIFEST="$RELEASE_ROOT/production-manifest.json"
NOTARY_LOG="$RELEASE_ROOT/notary-log.json"
CODESIGN_DETAILS="$RELEASE_ROOT/codesign-details.txt"
INSTALL_APP=false
SKIP_TESTS=false
RUN_XCUITEST=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL_APP=true
      shift
      ;;
    --skip-tests)
      SKIP_TESTS=true
      shift
      ;;
    --with-xcuitest)
      RUN_XCUITEST=true
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"
mkdir -p "$RELEASE_ROOT"

for required_tool in swiftformat swiftlint xcodebuild codesign ditto shasum python3 xcrun; do
  if ! command -v "$required_tool" >/dev/null 2>&1; then
    echo "Missing required tool: $required_tool" >&2
    exit 1
  fi
done

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Missing required tool: xcodegen" >&2
  exit 1
fi

DEVELOPMENT_TEAM="${FED_CHAIRMAN_DEVELOPMENT_TEAM:-${DEVELOPMENT_TEAM:-}}"
SIGNING_IDENTITY="${FED_CHAIRMAN_DEVELOPER_ID_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${FED_CHAIRMAN_NOTARY_KEYCHAIN_PROFILE:-}"
APPLE_ID="${FED_CHAIRMAN_NOTARY_APPLE_ID:-${APPLE_ID:-}}"
APPLE_PASSWORD="${FED_CHAIRMAN_NOTARY_PASSWORD:-${APPLE_PASSWORD:-}}"
NOTARY_TEAM_ID="${FED_CHAIRMAN_NOTARY_TEAM_ID:-${DEVELOPMENT_TEAM:-}}"

if [[ -z "$DEVELOPMENT_TEAM" ]]; then
  echo "Set FED_CHAIRMAN_DEVELOPMENT_TEAM to your Apple Developer Team ID." >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -F "$SIGNING_IDENTITY" >/dev/null 2>&1; then
  echo "No usable signing identity matching '$SIGNING_IDENTITY' was found in the keychain." >&2
  exit 1
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "$APPLE_ID" && -n "$APPLE_PASSWORD" && -n "$NOTARY_TEAM_ID" ]]; then
  NOTARY_ARGS=(--apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$NOTARY_TEAM_ID")
else
  echo "Set FED_CHAIRMAN_NOTARY_KEYCHAIN_PROFILE, or FED_CHAIRMAN_NOTARY_APPLE_ID + FED_CHAIRMAN_NOTARY_PASSWORD + FED_CHAIRMAN_NOTARY_TEAM_ID." >&2
  exit 1
fi

xcodegen generate

swiftformat Sources Tests --swift-version 6.1 --lint
swiftlint lint --strict
if [[ "$SKIP_TESTS" != true ]]; then
  swift test
  if [[ "$RUN_XCUITEST" == true ]]; then
    "$REPO_ROOT/scripts/native-validation.sh" ui-final
  fi
fi

rm -rf "$ARCHIVE_PATH" "$APP_OUTPUT" "$RELEASE_ROOT/$LEGACY_APP_NAME" "$MANIFEST" "$NOTARY_LOG" "$CODESIGN_DETAILS"
xcodebuild archive \
  -configuration Release \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  SKIP_INSTALL=NO

ditto --norsrc "$ARCHIVE_PATH/Products/Applications/$APP_NAME" "$APP_OUTPUT"
xattr -cr "$APP_OUTPUT" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "$APP_OUTPUT"
codesign -dv --verbose=4 "$APP_OUTPUT" >"$CODESIGN_DETAILS" 2>&1

if ! grep -F "Authority=Developer ID Application" "$CODESIGN_DETAILS" >/dev/null 2>&1; then
  echo "The app is signed, but not with a Developer ID Application authority." >&2
  cat "$CODESIGN_DETAILS" >&2
  exit 1
fi

UPLOAD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fed-chairman-notary.XXXXXX")"
UPLOAD_ZIP="$UPLOAD_DIR/FedChairmanGame-notary-upload.zip"
cleanup_upload() {
  if [[ "${FED_CHAIRMAN_KEEP_NOTARY_UPLOAD:-0}" != "1" ]]; then
    rm -rf "$UPLOAD_DIR"
  else
    echo "Kept temporary notarization upload at $UPLOAD_ZIP"
  fi
}
trap cleanup_upload EXIT

ditto -c -k --keepParent "$APP_OUTPUT" "$UPLOAD_ZIP"
xcrun notarytool submit "$UPLOAD_ZIP" "${NOTARY_ARGS[@]}" --wait --output-format json | tee "$NOTARY_LOG"
python3 - "$NOTARY_LOG" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)
status = payload.get("status")
if status != "Accepted":
    raise SystemExit(f"Notarization did not succeed: {status}")
PY

xcrun stapler staple "$APP_OUTPUT"
xcrun stapler validate "$APP_OUTPUT"
SPCTL_OUTPUT="$(spctl --assess --type execute --verbose=4 "$APP_OUTPUT" 2>&1)"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_OUTPUT/Contents/Info.plist")"
DISPLAY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP_OUTPUT/Contents/Info.plist")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_OUTPUT/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_OUTPUT/Contents/Info.plist")"
CATEGORY="$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' "$APP_OUTPUT/Contents/Info.plist")"
EXECUTABLE="$APP_OUTPUT/Contents/MacOS/Fed Chairman Game"
if [[ "$BUNDLE_ID" != "local.fed-chairman-game" || "$DISPLAY_NAME" != "Fed Chairman Game" || ! -x "$EXECUTABLE" ]]; then
  echo "Packaged app identity is invalid: bundle=$BUNDLE_ID display=$DISPLAY_NAME executable=$EXECUTABLE" >&2
  exit 1
fi
EXECUTABLE_SHA="$(shasum -a 256 "$EXECUTABLE" | awk '{print $1}')"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 - "$MANIFEST" "$CREATED_AT" "$BUNDLE_ID" "$DISPLAY_NAME" "$VERSION" "$BUILD" "$CATEGORY" "$ARCHIVE_PATH" "$APP_OUTPUT" "$EXECUTABLE_SHA" "$DEVELOPMENT_TEAM" "$SIGNING_IDENTITY" "$SPCTL_OUTPUT" "$RUN_XCUITEST" <<'PY'
import json
import sys

(
    manifest_path,
    created_at,
    bundle_id,
    display_name,
    version,
    build,
    category,
    archive,
    app,
    executable_sha,
    team_id,
    signing_identity,
    spctl_output,
    run_xcuitest,
) = sys.argv[1:]
payload = {
    "product": "Fed Chairman Game",
    "createdAt": created_at,
    "bundleId": bundle_id,
    "displayName": display_name,
    "version": version,
    "build": build,
    "category": category,
    "archivePath": archive,
    "appPath": app,
    "executableSha256": executable_sha,
    "teamId": team_id,
    "signingIdentity": signing_identity,
    "hardenedRuntime": True,
    "notarized": True,
    "stapled": True,
    "xcuitestGate": run_xcuitest == "true",
    "gatekeeperAssessment": spctl_output,
    "artifacts": {
        "deliverable": "app",
        "dmg": None,
        "zip": None
    }
}
with open(manifest_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
PY

if [[ "$INSTALL_APP" == true ]]; then
  osascript -e 'tell application id "local.fed-chairman-game" to quit' >/dev/null 2>&1 || true
  osascript -e 'tell application id "local.fed-chairman-game.native" to quit' >/dev/null 2>&1 || true
  rm -rf "/Applications/$APP_NAME"
  rm -rf "/Applications/$LEGACY_APP_NAME"
  ditto --norsrc "$APP_OUTPUT" "/Applications/$APP_NAME"
  codesign --verify --deep --strict --verbose=2 "/Applications/$APP_NAME"
  xcrun stapler validate "/Applications/$APP_NAME"
  spctl --assess --type execute --verbose=4 "/Applications/$APP_NAME"
fi

echo "$APP_OUTPUT"
echo "$MANIFEST"
