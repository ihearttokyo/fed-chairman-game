# Native Migration Status

## Status

In progress. The native SwiftUI/SpriteKit product now has a generated Xcode project, native macOS UI tests, an ad-hoc signed local release-candidate package path, and an installed `/Applications` build. The root README, root npm shims, and GitHub verification workflow point at the native app, and the old Web/Tauri source has been removed from the release tree. It is still not a final notarized release.

## Completed In This Slice

- Added a SwiftPM package under `native/FedChairmanGame`.
- Ported the core monetary-policy types, deterministic RNG, policy decisions, quarter engine, score engine, session store, shock deck, and save-file digest validation to Swift.
- Added a SwiftUI/SpriteKit command-desk prototype with fixed dashboard, policy lever, metrics, quarter review, bottom-dock briefing panel, and cockpit dock.
- Added original generated UI assets to a SpriteKit atlas folder for native art-pipeline continuity.
- Wired the native cockpit dock to original generated Newspaper, Help, and Settings icon assets through SwiftPM resources.
- Added native full-career CSV, JSON, Markdown, and portable save/load functions, plus macOS save/open panel actions in the Settings dock panel.
- Added native auto-start active play plus a term-end debrief overlay with continue-next-term, retire-career, and start-new-career paths.
- Added rich native debrief modeling and UI content: board verdict, gate status/choice, term standing, policy style, best stretch, turning point, mandate trend, decision mix, final impulse, coaching focus, career ledger, carryover brief, next-term brief, retirement status, and term-handoff metrics.
- Added model-backed native briefing/help separation: dynamic newspaper briefing copy now carries headline, metadata, severity, policy implication, and risk-calendar status, while static policy/watch/explanatory copy lives in Help topics.
- Ported the Web policy notebook into native Help topics, including dynamic Federal Funds Rate stance, dual-mandate basics, expansionary/contractionary policy, policy lags, policy questions, what-to-watch, credibility, easing-with-care, lagged-decision, and shock/trend guidance.
- Added testable native cockpit dock state with panel toggles, deterministic layout offsets, reduced-motion mode selection, and mutually exclusive Newspaper/Help/Settings behavior in the native UI.
- Added native Policy menu keyboard shortcuts: `R` raises 25 bps, `H` holds, and `C` cuts 25 bps.
- Improved the SpriteKit mandate dashboard graph with an instrument plate, y-axis labels, start/latest labels, native legend, latest readout, vertical grid, target bands, and emphasized latest pips.
- Installed full Xcode 26.5 globally, selected `/Applications/Xcode.app/Contents/Developer` with `xcode-select`, and installed `swiftlint` globally through Homebrew.
- Added an ad-hoc signed SwiftPM development app packaging script, hardened it against file-provider xattrs by staging the app outside the repo, and installed the native dev bundle into `/Applications/Fed Chairman Game Native.app` for local smoke testing.
- Ported the full three-month transmission briefing surface from the Web implementation into Swift, including decision receipt, decision memo, three causal steps, mandate path, trace-backed changes, and deterministic trace-input labels.
- Rebuilt the native Quarter Review into a richer cockpit readout with step chips, three monthly transmission cards, progress bars, trace-backed change cards, and next-bias guidance.
- Added `project.yml` and generated `FedChairmanGameNative.xcodeproj` through globally installed XcodeGen.
- Added a real native macOS XCUITest bundle covering the fixed policy lever, briefing auto-retract behavior, dock panel toggles, and Policy menu command path.
- Refined the native cockpit into a mahogany/liquid-glass command desk: taller graph, keyboard-like policy buttons, right-side y-axis labels, mouse hover readout on the SpriteKit chart, and mutually exclusive Newspaper/Help/Settings dock panels.
- Moved the newspaper briefing out of the old top/nub overlay path and into the bottom dock panel flow with fully opaque generated newspaper panel art.
- Fixed Xcode project build settings for the native core framework/test targets so generated Info.plists are available for bundle signing.
- Added native app accessibility identifiers for dashboard, policy lever, metrics, quarter review, briefing panel, dock buttons, and dock panels.
- Installed and verified `/Applications/Fed Chairman Game Native.app` from the current ad-hoc signed development package.
- Added Swift unit tests for engine parity, custom bps, reappointment credibility grace, deterministic shocks, tamper-evident saves, full-career exports, load/recompute behavior, term-end debrief continuation, rich debrief content, notebook/help topic parity, briefing/help separation, dock cascade behavior, and reduced-motion behavior.
- Incorporated the original cockpit prompt and later native art direction into the native target requirements: no duplicated active-play title, dynamic alerts only in the fully opaque bottom-dock newspaper panel, static policy/watch/help content in the Help panel, equal bottom-right Newspaper/Help/Settings dock buttons, mutually exclusive panel toggles, native bouncy open/close motion, click feedback, generated icon/newspaper art, liquid-glass UI touches, mahogany command-desk styling, and no layout movement from rate decisions.
- Added a local release-candidate packaging script that runs formatting/lint/unit/UI-test gates, creates an Xcode archive, stages the app without DMG/zip artifacts, verifies ad-hoc signing, emits text/JSON manifests, and can install the verified bundle into `/Applications`.
- Added hardened-runtime-ready Xcode configuration, an explicit native app entitlements file, and a Developer ID/notarization production packaging script that validates credentials, archives with hardened runtime, submits with `notarytool`, staples the accepted ticket, verifies Gatekeeper, and leaves the release surface as a `.app` plus manifest rather than DMG/ZIP deliverables.
- Retired the root Web/Tauri release surface: root `npm` scripts now dispatch to native Swift/Xcode verification and packaging, the GitHub workflow runs native macOS checks only, the root README describes the SwiftUI/SpriteKit product, stale Tauri DMG packaging scripts were removed, and the generated local DMG artifact was deleted.
- Removed the old Web/Tauri source tree, TypeScript/Vite/Playwright configs, root npm lockfile, Node modules, generated browser output, and stale web e2e sources from the working tree. Historical web code is available through git history only.

## Not Complete

- The local release-candidate `.app` is useful for native testing and private beta smoke, but it is still ad-hoc signed and not notarized.
- Production Developer ID signing and notarization are scripted but not yet proven on this machine because Apple Developer ID/notary credentials are not configured in the environment.
- The native app still needs final visual variant validation.
- XCUITest covers the Policy menu command path. Raw `XCUIApplication.typeKey` did not exercise the app-level shortcut monitor reliably in automation, so a future pass should add a lower-level AppKit shortcut test or a manually verified keyboard smoke note before beta release.
- The prior Stable Cockpit Overlay Plan was only partially implemented because it landed in Web/Tauri; native graphics and native macOS animation remain the required final direction.
