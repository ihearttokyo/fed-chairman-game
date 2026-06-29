# Fed Chairman Game Native App

This directory contains the shipped product surface: a native macOS game built with SwiftUI, SpriteKit, and AppKit.

## Current Shape

- `Sources/FedChairmanCore/`: deterministic macro model, scoring, saves, exports, briefings, debriefs, and cockpit state models.
- `Sources/FedChairmanNativeApp/`: SwiftUI/SpriteKit macOS cockpit, panels, menu commands, file import/export, sound, keyboard dispatch, and launch behavior.
- `Tests/FedChairmanCoreTests/`: fast engine and model contract tests.
- `Tests/FedChairmanNativeUITests/`: native macOS XCUITest regression coverage.
- `Assets.xcassets/`, `App/`, and `SpriteAtlases/`: original native app icon and cockpit art inputs.
- `scripts/`: local development, release-candidate, and production packaging.

The release tree is intentionally native-only. Browser, WebView, local-server, Tauri, and web packaging paths are not part of the product.

## Tooling

The root `package.json` exposes compatibility shims for the native commands. You can run checks from the repo root:

```bash
npm run native:generate
npm run typecheck
npm run lint
npm test
npm run test:gui
```

The native package can also be driven directly:

```bash
xcodegen generate
swift build
swift test
swiftformat Sources Tests --swift-version 6.1 --lint
swiftlint lint --strict
xcodebuild test -project FedChairmanGameNative.xcodeproj -scheme FedChairmanGameNative -destination 'platform=macOS'
```

`project.yml` is the source of truth for the generated Xcode project. Regenerate the project after changing target structure, resources, build settings, or test targets.

The internal target and scheme still use `FedChairmanGameNative` as a stable build identifier. The installed product name is `Fed Chairman Game`.

## Packaging

Local development app:

```bash
scripts/package-native-dev-app.sh
```

Local release candidate:

```bash
scripts/package-native-release-candidate.sh
scripts/package-native-release-candidate.sh --install
```

The release-candidate script runs formatting, lint, unit tests, archive, codesign, manifest, and optional install gates. It skips native XCUITest by default so local install is not blocked by desktop automation state. Add `--with-xcuitest` only when a clean-desktop native UI regression pass is explicitly desired.

Production signing and notarization:

```bash
scripts/package-native-production.sh
```

Production packaging requires Apple credentials:

- `FED_CHAIRMAN_DEVELOPMENT_TEAM`
- `FED_CHAIRMAN_DEVELOPER_ID_IDENTITY`, optional
- `FED_CHAIRMAN_NOTARY_KEYCHAIN_PROFILE`, preferred
- Or `FED_CHAIRMAN_NOTARY_APPLE_ID`, `FED_CHAIRMAN_NOTARY_PASSWORD`, and `FED_CHAIRMAN_NOTARY_TEAM_ID`

The production path creates a temporary ZIP only for Apple notarization upload and deletes it by default. Set `FED_CHAIRMAN_KEEP_NOTARY_UPLOAD=1` only when debugging notarization failures.

## Validation Expectations

Use fast code checks for core/model changes:

```bash
npm run typecheck
npm run lint
npm test
```

For UI, layout, chart, dock, settings, briefing, or gameplay changes, follow the repo root `AGENTS.md` and `docs/AGENTIC_GUI_VALIDATION.md`: build the current app, verify artifact provenance, inspect real screenshots or Computer Use state, interact through meaningful gameplay paths, then run supporting code checks.

Use `npm run test:ui` only when a clean-desktop XCUITest regression pass is specifically useful or explicitly requested.

## Source Control Hygiene

Do not commit generated app bundles, archives, release manifests, notarization logs, `.xcresult` bundles, `.DS_Store` files, or SwiftPM build output. The source-controlled product is the Swift package, XcodeGen spec, assets, scripts, tests, and docs.
