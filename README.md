# Fed Chairman Game

Fed Chairman Game is a native macOS simulation about the pressure of running monetary policy across real four-year Fed Chair terms.

Players make one policy decision per quarter, read the briefing, watch credibility and macro lags transmit through the economy, then face a reappointment decision after 16 quarters. Reappointed chairs continue into another full term with one continuous career history.

This project is independent and is not affiliated with, sponsored by, or endorsed by the Board of Governors of the Federal Reserve System or any Federal Reserve Bank.

## Beta Scope

- Native macOS app built with SwiftUI and SpriteKit.
- Classic Monetary Policy Mode only: fixed four-year, 16-quarter terms.
- One-click rate decisions plus validated custom basis-point moves.
- Deterministic seeded shocks, credibility, policy lags, scorecards, and reappointment debriefs.
- Full-career chart history that appends across terms.
- Portable `.fedchair-save.json` saves with tamper-evident SHA-256 digests.
- CSV, JSON, and Markdown exports for the full career timeline.
- Native dock panels for Newspaper, Help, and Settings with reduced-motion support.

The release direction is intentionally narrow: one native macOS application. There are no browser-launcher, website, standalone local-server, DMG, or ZIP product paths.

## Gameplay Loop

1. Read the quarterly newspaper briefing.
2. Inspect inflation, unemployment, fed funds, credibility, and the policy path.
3. Commit exactly one policy move for the quarter.
4. Review the fixed policy decision tape and three-month transmission readout.
5. Complete 16 quarters, face reappointment, then continue or retire when eligible.

## Native Development

The native product lives in `native/FedChairmanGame`.

```bash
cd native/FedChairmanGame
xcodegen generate
swift build
swift test
xcodebuild test -project FedChairmanGameNative.xcodeproj -scheme FedChairmanGameNative -destination 'platform=macOS'
```

Root `npm` scripts are compatibility shims for the native app only. They do not install Node dependencies or build a web surface.

```bash
npm run typecheck
npm run lint
npm test
npm run test:gui
npm run test:ui
```

`npm run test:gui` is the default desktop evidence gate. It builds a current local app bundle, launches it, captures provenance-backed screenshots at responsive sizes, then prints the screenshot paths that must be visually inspected before UI work is called complete. Use Computer Use for the interactive playability pass: make at least one policy decision and open Newspaper, Help, and Settings against that same app build.

If the active macOS capture backend returns black screenshots, `test:gui` fails rather than treating those files as evidence. In that case, grant Screen Recording permission to the invoking app/terminal or use Computer Use directly and report that evidence path.

`npm run test:ui` still runs the native XCUITest regression suite. Use it as a final clean-desktop guardrail when the app can run unobstructed, not as the primary visual QA loop.

## Build And Install

Create a local native release candidate:

```bash
npm run build
```

Install the verified local build into `/Applications`:

```bash
npm run install:mac
```

The local release-candidate path creates and verifies an `.app` bundle only. It does not create a DMG or ZIP. Local builds are ad-hoc signed for private machine testing.

## Production Signing

Developer ID signing and notarization are scripted but require Apple credentials:

```bash
npm run package:production
```

The production script archives with hardened runtime, submits the app to Apple notarization, staples the accepted ticket, verifies Gatekeeper acceptance, and keeps the release surface focused on the notarized `.app` plus manifests.

## Verification

```bash
npm run native:generate
npm run typecheck
npm run lint
npm test
npm run test:gui
npm run build
```

The native release-candidate script also runs its own formatting, lint, unit-test, XCUITest, archive, codesign, manifest, and optional install gates. For day-to-day UI work, prefer the screenshot-first `npm run test:gui` loop and reserve XCUITest for a clear-desktop regression pass.

## Tech Stack

- Swift 6.1
- SwiftUI for native macOS app structure and controls
- SpriteKit for the animated mandate dashboard graph
- AppKit where macOS save/open panels, sounds, keyboard dispatch, and packaging behavior require it
- XcodeGen for reproducible Xcode project generation
- Swift Testing and XCUITest for core and native UI coverage

## Project Map

```text
native/FedChairmanGame/
  Sources/FedChairmanCore/       deterministic macro model, saves, exports, debriefs
  Sources/FedChairmanNativeApp/  SwiftUI/SpriteKit native cockpit
  Tests/                         Swift core tests and native macOS UI tests
  Assets.xcassets/               native app icon assets
  SpriteAtlases/                 original generated cockpit art
  scripts/                       native release-candidate and production packaging
```

The old Web/Tauri source has been removed from the release tree. Historical web code remains available through git history only.

## Release Artifacts

Generated artifacts are ignored by git:

- `release/`
- `native/FedChairmanGame/.build/`
- `native/FedChairmanGame/release/`

Do not commit generated app bundles, disk images, ZIPs, build output, or notarization upload archives.

## Clean-Room Discipline

The game uses original UI, copy, model code, and assets only. It does not include Federal Reserve seals, Federal Reserve building photos, screenshots from other products, copied source text, external audio packs, backend services, telemetry, accounts, or live economic data.

Supporting docs:

- `ASSET_PROVENANCE.md`
- `CLEANROOM.md`
- `THIRD_PARTY_NOTICES.md`
- `native/FedChairmanGame/NATIVE_MIGRATION_STATUS.md`
