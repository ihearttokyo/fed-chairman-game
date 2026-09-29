# Fed Chairman Game

Fed Chairman Game is a native macOS simulation about the pressure of running monetary policy across real four-year Fed Chair terms.

Players make one policy decision per quarter, read the briefing, watch credibility and macro lags transmit through the economy, then face a reappointment decision after 16 quarters. Reappointed chairs continue into another full term with one continuous career history.

This project is independent and is not affiliated with, sponsored by, or endorsed by the Board of Governors of the Federal Reserve System or any Federal Reserve Bank.

## Clean-sheet rebuild

A research-first Godot replacement is in development. The existing Swift app
below remains the legacy release; no save migration or replacement release is
ready. Start with the [full-pass review](docs/REBUILD_REVIEW.md),
[Federal Reserve research decisions](docs/FED_RESEARCH.md) and
[economic model acceptance contract](docs/MODEL_CONTRACT.md).

## Beta Scope

- Native macOS app built with SwiftUI and SpriteKit.
- Classic Monetary Policy Mode only: fixed four-year, 16-quarter terms.
- Preview-first rate decisions plus validated custom basis-point moves.
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
```

Root `npm` scripts are compatibility shims for the native app only. They do not install Node dependencies or build a web surface.

```bash
npm run test:fast
npm run typecheck
npm run lint
npm test
npm run test:gui
npm run test:ui:preflight
npm run test:ui:prepare
npm run test:ui:one -- FedChairmanGameNativeUITests/NativeCockpitUITests/testLaunchStartsWithDockPanelsClosedAndPrimarySurfacesClear
npm run test:ui:final
```

`npm run test:fast` is the cheap inner loop: Swift build plus Swift unit tests.

`npm run test:gui` is the default desktop evidence gate. It builds a current local app bundle, launches it, and captures provenance-backed screenshots that must be visually inspected before UI work is called complete. Normal product work uses one large window; responsive-size matrices are reserved for changes that directly target responsive layout. Use Computer Use for the interactive playability pass against that same app build.

If the active macOS capture backend returns black screenshots, `test:gui` fails rather than treating those files as evidence. In that case, grant Screen Recording permission to the invoking app/terminal or use Computer Use directly and report that evidence path.

`npm run test:ui` and `npm run test:ui:final` run the guarded native XCUITest final gate. They do not run raw `xcodebuild test`; they use the repo validation ladder, reusable DerivedData, `test-without-building`, and one large-window smoke test.

Run `npm run test:ui:preflight` before `npm run test:ui:prepare`, `npm run test:ui:one -- ...`, or `npm run test:ui:final` so known desktop/XCUITest blockers are surfaced before building UI test products or launching UI tests. For the default macOS destination, CoreSimulator/simctl noise is warning-only because the app does not need an iOS simulator.
If preflight fails, report the failure and do not continue with the UI ladder on that run.
Use `npm run test:ui:prepare` before `npm run test:ui:one -- <Target/Class/testMethod>` when a single targeted UI regression is explicitly useful.

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

`npm run build`, `npm run package:mac`, and `npm run install:mac` run formatting, lint, unit tests, archive, codesign, manifest, and optional install gates. They do not run native XCUITest by default. Use `npm run package:mac:xcuitest` only when a clean-desktop native UI regression pass is explicitly desired.

## Production Signing

Developer ID signing and notarization are scripted but require Apple credentials:

```bash
npm run package:production
```

The production script archives with hardened runtime, submits the app to Apple notarization, staples the accepted ticket, verifies Gatekeeper acceptance, and keeps the release surface focused on the notarized `.app` plus manifests. It runs format/lint/unit gates by default and runs XCUITest only with `--with-xcuitest`.

## Verification

```bash
npm run native:generate
npm run typecheck
npm run lint
npm test
npm run test:gui
npm run build
```

The native release-candidate script also runs its own formatting, lint, unit-test, archive, codesign, manifest, and optional install gates. For day-to-day UI work, prefer `npm run test:fast` plus a single screenshot-first large-window check and reserve `npm run test:ui:final` for an explicit clean-desktop regression pass. Final reports should name the highest validation ladder step run and why broader UI gates were skipped.

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
- `docs/ECONOMIC_MODEL_RATIONALE.md`
- `THIRD_PARTY_NOTICES.md`
