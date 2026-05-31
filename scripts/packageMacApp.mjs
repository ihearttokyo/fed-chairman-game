import { chmodSync, existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const projectRoot = dirname(dirname(fileURLToPath(import.meta.url)))
const releaseDir = join(projectRoot, 'release')
const appName = 'Fed Chairman Game'
const appDir = join(releaseDir, `${appName}.app`)
const contentsDir = join(appDir, 'Contents')
const macOsDir = join(contentsDir, 'MacOS')
const resourcesDir = join(contentsDir, 'Resources')
const executablePath = join(macOsDir, appName)

function xmlEscape(value) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;')
}

function createAppBundle() {
  if (existsSync(appDir)) {
    rmSync(appDir, { recursive: true, force: true })
  }
  mkdirSync(macOsDir, { recursive: true })
  mkdirSync(resourcesDir, { recursive: true })

  writeFileSync(
    join(contentsDir, 'Info.plist'),
    `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${xmlEscape(appName)}</string>
  <key>CFBundleExecutable</key>
  <string>${xmlEscape(appName)}</string>
  <key>CFBundleIdentifier</key>
  <string>local.fed-chairman-game</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${xmlEscape(appName)}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
`,
  )

  writeFileSync(
    executablePath,
    `#!/bin/zsh
set -e

APP_EXECUTABLE="$0"
APP_ROOT="$(cd "$(dirname "$APP_EXECUTABLE")/../../../.." && pwd)"
cd "$APP_ROOT"

if ! command -v npm >/dev/null 2>&1; then
  osascript -e 'display alert "Fed Chairman Game cannot start" message "npm was not found. Install Node.js dependencies, then open the app again."'
  exit 1
fi

npm run launch
`,
  )
  chmodSync(executablePath, 0o755)
}

createAppBundle()
console.log(`Created ${appDir}`)
