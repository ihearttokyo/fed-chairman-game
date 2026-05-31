#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
APP_STAGING_ROOT="${FED_CHAIRMAN_NATIVE_APP_STAGING_ROOT:-${TMPDIR:-/tmp}/fed-chairman-game-native}"
APP_DIR="$APP_STAGING_ROOT/Fed Chairman Game.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE_NAME="Fed Chairman Game"
SWIFTPM_EXECUTABLE="$BUILD_DIR/FedChairmanGameNative"
SWIFTPM_RESOURCE_BUNDLE="$BUILD_DIR/FedChairmanGame_FedChairmanNativeApp.bundle"
APP_ICON="$ROOT_DIR/App/AppIcon.icns"

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$APP_STAGING_ROOT"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
ditto --norsrc "$SWIFTPM_EXECUTABLE" "$MACOS_DIR/$EXECUTABLE_NAME"
if [[ -d "$SWIFTPM_RESOURCE_BUNDLE" ]]; then
  ditto --norsrc "$SWIFTPM_RESOURCE_BUNDLE" "$RESOURCES_DIR/$(basename "$SWIFTPM_RESOURCE_BUNDLE")"
fi
if [[ -f "$APP_ICON" ]]; then
  ditto --norsrc "$APP_ICON" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Fed Chairman Game</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>local.fed-chairman-game</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Fed Chairman Game</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSQuitAlwaysKeepsWindows</key>
  <false/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

clean_xattrs() {
  xattr -cr "$APP_DIR" 2>/dev/null || true
  xattr -dr com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
  xattr -dr 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true
  xattr -dr com.apple.provenance "$APP_DIR" 2>/dev/null || true
}

clean_xattrs
codesign --force --deep --sign - "$APP_DIR" >/dev/null
clean_xattrs
codesign --force --deep --sign - "$APP_DIR" >/dev/null
echo "$APP_DIR"
