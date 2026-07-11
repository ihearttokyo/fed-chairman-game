#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/../.." && pwd)"
PROJECT="$ROOT_DIR/FedChairmanGameNative.xcodeproj"
SCHEME="FedChairmanGameNative"
APP_NAME="Fed Chairman Game.app"
LEGACY_APP_NAME="Fed Chairman Game Native.app"
RELEASE_ROOT="${FED_CHAIRMAN_NATIVE_RELEASE_ROOT:-$ROOT_DIR/release/native-local}"
ARCHIVE_PATH="$RELEASE_ROOT/FedChairmanGameNative.xcarchive"
APP_OUTPUT="$RELEASE_ROOT/$APP_NAME"
MANIFEST="$RELEASE_ROOT/release-manifest.txt"
JSON_MANIFEST="$RELEASE_ROOT/release-manifest.json"
SOURCE_PROVENANCE_SCRIPT="$ROOT_DIR/scripts/source-provenance.sh"
INSTALL_APP=false
RUN_XCUITEST=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL_APP=true
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
if [[ "$RUN_XCUITEST" == true ]]; then
  "$REPO_ROOT/scripts/native-validation.sh" ui-final
fi

# shellcheck source=source-provenance.sh
source "$SOURCE_PROVENANCE_SCRIPT"
collect_source_provenance "$REPO_ROOT"

rm -rf "$ARCHIVE_PATH" "$APP_OUTPUT" "$RELEASE_ROOT/$LEGACY_APP_NAME"
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

cat > "$MANIFEST" <<MANIFEST_TEXT
Fed Chairman Game release candidate
Created: $CREATED_AT
Bundle ID: $BUNDLE_ID
Display Name: $DISPLAY_NAME
Version: $VERSION
Build: $BUILD
Category: $CATEGORY
Archive: $ARCHIVE_PATH
App: $APP_OUTPUT
Executable SHA-256: $EXECUTABLE_SHA
Source Git HEAD: $SOURCE_GIT_HEAD
Source dirty: $SOURCE_DIRTY
Source fingerprint: $SOURCE_FINGERPRINT
Signing: ad-hoc local signing for development/beta smoke only
Hardened runtime: disabled for ad-hoc local launch compatibility
Notarization: not notarized
XCUITest gate: $([[ "$RUN_XCUITEST" == true ]] && echo "run" || echo "skipped")
Gatekeeper assessment: $SPCTL_RESULT
MANIFEST_TEXT

python3 - "$JSON_MANIFEST" "$CREATED_AT" "$BUNDLE_ID" "$DISPLAY_NAME" "$VERSION" "$BUILD" "$CATEGORY" "$ARCHIVE_PATH" "$APP_OUTPUT" "$EXECUTABLE_SHA" "$SPCTL_RESULT" "$RUN_XCUITEST" "$SOURCE_GIT_HEAD" "$SOURCE_DIRTY" "$SOURCE_FINGERPRINT" "$SOURCE_GIT_STATUS_SHORT" <<'PY'
import json
import sys

manifest_path, created_at, bundle_id, display_name, version, build, category, archive, app, executable_sha, spctl_result, run_xcuitest, source_git_head, source_dirty, source_fingerprint, source_git_status = sys.argv[1:]
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
    "sourceGitHead": source_git_head,
    "sourceDirty": source_dirty == "true",
    "sourceFingerprint": source_fingerprint,
    "sourceGitStatusShort": source_git_status,
    "builtFromCleanCommit": source_dirty == "false",
    "signing": "ad-hoc local signing for development/beta smoke only",
    "hardenedRuntime": False,
    "notarized": False,
    "xcuitestGate": run_xcuitest == "true",
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
  osascript -e 'tell application id "local.fed-chairman-game" to quit' >/dev/null 2>&1 || true
  osascript -e 'tell application id "local.fed-chairman-game.native" to quit' >/dev/null 2>&1 || true
  rm -rf "/Applications/$APP_NAME"
  rm -rf "/Applications/$LEGACY_APP_NAME"
  rm -f "/Applications/Fed Chairman Game.release-manifest.json" "/Applications/Fed Chairman Game.production-manifest.json"
  ditto --norsrc "$APP_OUTPUT" "/Applications/$APP_NAME"
  ditto --norsrc "$JSON_MANIFEST" "/Applications/Fed Chairman Game.release-manifest.json"
  codesign --verify --deep --strict --verbose=2 "/Applications/$APP_NAME"
fi

echo "$APP_OUTPUT"
echo "$MANIFEST"
echo "$JSON_MANIFEST"
