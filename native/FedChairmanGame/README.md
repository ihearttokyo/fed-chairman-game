# Fed Chairman Game Native

This directory is the native macOS migration target for Fed Chairman Game.

## Direction

- Stack: SwiftUI for app structure and controls, SpriteKit for the animated 2D cockpit graph and instrument motion.
- Art direction: premium command desk, with tactile native controls and original generated UI art.
- Migration strategy: native-first beta. The old React/Tauri source has been removed from the release tree; root build scripts, CI, and beta packaging target this native app.

## Current Build

The local machine now has full Xcode selected globally:

- `xcode-select -p` points to `/Applications/Xcode.app/Contents/Developer`.
- `xcodebuild -version` reports Xcode 26.5.
- `swiftformat`, `swiftlint`, `xcbeautify`, and `xcodegen` are installed globally through Homebrew.
- `swift test`, `swift build`, `swiftformat Sources Tests --swift-version 6.1 --lint`, and `swiftlint lint --strict` are the current native verification commands.
- `project.yml` is the source of truth for the generated Xcode project. Run `xcodegen generate` before Xcode build/test work when the project spec changes.
- `xcodebuild test -project FedChairmanGameNative.xcodeproj -scheme FedChairmanGameNative -destination 'platform=macOS'` runs the core tests plus the real native macOS UI tests.
- `scripts/package-native-dev-app.sh` builds an ad-hoc signed development `.app` bundle from SwiftPM, stages it outside the file-provider-backed repo, and can be copied into `/Applications/Fed Chairman Game Native.app`.
- `scripts/package-native-release-candidate.sh --install` runs the native formatting/lint/unit/UI-test gates, creates an Xcode archive, stages an ad-hoc signed local release-candidate `.app`, writes text/JSON manifests, and installs it into `/Applications`.
- `scripts/package-native-production.sh` is the Developer ID/notarization path. It requires Apple signing credentials, archives with hardened runtime, notarizes with `notarytool`, staples the ticket to the `.app`, verifies Gatekeeper acceptance, and emits a production manifest without keeping DMG/ZIP deliverables.
- The current installed native development app is `/Applications/Fed Chairman Game Native.app`, bundle id `local.fed-chairman-game.native`.

## Production Signing

The native Xcode target has hardened runtime enabled and uses `Config/FedChairmanGameNative.entitlements` so production signing is explicit and auditable. The entitlements file is intentionally empty until the app genuinely needs a capability.

For outside-Mac-App-Store beta distribution, configure one of these credential paths before running `scripts/package-native-production.sh`:

- `FED_CHAIRMAN_DEVELOPMENT_TEAM`: Apple Developer Team ID.
- `FED_CHAIRMAN_DEVELOPER_ID_IDENTITY`: optional signing identity override; defaults to `Developer ID Application`.
- `FED_CHAIRMAN_NOTARY_KEYCHAIN_PROFILE`: preferred `notarytool` keychain profile.
- Or: `FED_CHAIRMAN_NOTARY_APPLE_ID`, `FED_CHAIRMAN_NOTARY_PASSWORD`, and `FED_CHAIRMAN_NOTARY_TEAM_ID`.

The production script creates a temporary ZIP only for Apple notarization upload, deletes it by default, and keeps the release surface focused on the stapled `.app` plus manifest. Set `FED_CHAIRMAN_KEEP_NOTARY_UPLOAD=1` only when debugging notarization failures.

## Native Parity Targets

- Preserve the 16-quarter Classic Monetary Policy Mode, reappointment gate, full-career timeline, custom bps, and credibility grace mechanics.
- Preserve `.fedchair-save.json` envelope compatibility with canonical payload digest validation.
- Keep policy controls fixed in the viewport; briefing/help/settings overlays must never push layout or trigger scroll after a rate click.
- Put the mandate dashboard first, then the fixed policy lever, then inflation/unemployment/fed funds/expectations/credibility indicators, then the quarter review.
- Treat labor-market and macro alerts as dynamic newspaper copy only: they open from the bottom-right Newspaper dock button, auto-peek after decisions, retract without moving layout, and render as fully opaque native briefing panels with original newspaper art.
- Move static policy questions, watch items, educational notes, output-gap explanations, and other reference text into the Help dock panel.
- Replace web/CSS motion with native SwiftUI spring/bouncy transitions and SpriteKit instrument pulses: dock buttons squash/rebound, closing panels visually absorb back into the icon, and the dock keeps Newspaper, Help, and Settings mutually exclusive so one open tool never leaves stale panels behind.
- Use generated icon-first native dock controls for Newspaper, Help, and Settings; add short native click feedback when reduced-noise is off; avoid repeating "Classic Monetary Policy Mode" on the active play screen.
- Keep native keyboard shortcuts available through the Policy menu: `R` for +25 bps, `H` for Hold, and `C` for -25 bps.
- Keep the primary visual surface in the current premium command-desk direction: mahogany/library warmth, Bloomberg-terminal density, a taller full-width graph with right-side y-axis labels, mouse hover readouts, liquid-glass dock tools, and keyboard-like rate buttons.

## Known Incomplete Items

- This is not yet a notarized or App Store-ready release app bundle. The local `/Applications` app is an ad-hoc signed development build.
- Production Developer ID signing and notarization automation is present, but it has not been executed successfully because local Apple Developer ID/notary credentials have not been configured in this environment.
- Final visual variant validation is still pending, but the old top/nub web briefing variant is no longer the chosen native direction and the Web/Tauri source is no longer in the release tree.
- The previous Stable Cockpit Overlay web implementation remains incomplete against the product requirement because it is not native macOS graphics; it should be treated as reference behavior only, not as completed product UI.
