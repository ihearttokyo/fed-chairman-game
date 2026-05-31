# Native macOS Implementation Plan

## Summary

Fed Chairman Game is moving to a real native macOS implementation using SwiftUI and SpriteKit. The old React/Tauri source has been removed from the release tree; historical web code is available through git history only.

The previous Stable Cockpit Overlay work is not considered complete product implementation because it was delivered inside a WebView. The native app must implement the same behavior with native layout, native graphics, native animation, and installed-app testing.

## Research And Prior-Art Anchors

- Apple macOS window guidance: preserve a stable, native window surface and keep transient content from reflowing the primary task area. References: https://developer.apple.com/design/human-interface-guidelines/windows and https://developer.apple.com/design/human-interface-guidelines/popovers/
- Apple SwiftUI motion/accessibility guidance: implement spring motion natively, and honor reduced-motion settings with simplified transitions. References: https://developer.apple.com/documentation/SwiftUI/Animations and https://developer.apple.com/documentation/SwiftUI/EnvironmentValues/accessibilityReduceMotion
- Material speed-dial/FAB guidance and open-source implementations: use a small set of related floating actions, icon-first buttons, deterministic expansion direction, and predictable toggle behavior. References: https://mui.com/material-ui/react-speed-dial/ and https://m2.material.io/components/buttons-floating-action-button
- Accessible game HUD guidance: keep critical game state readable at a glance, use overlays for secondary information, and pair visual feedback with restrained audio feedback when noise reduction is off.
- SwiftUI floating-button examples: attach floating controls with overlay alignment rather than inserting them into the document layout.

## Required Native Cockpit Behavior

- Active play has no repeated "Classic Monetary Policy Mode" title. It uses only a thin status rail for scenario, term, quarter, career quarters, and progress.
- The mandate dashboard is the first major surface and stays visually dominant.
- The policy lever sits under the dashboard and must not move by more than 4 px after any rate click, alert change, dock open/close, or quarter transition.
- Inflation, unemployment, fed funds, expectations, and credibility sit below the policy lever.
- Quarter Review sits below the macro indicators and is allowed to grow downward, never upward into controls.
- Dynamic labor-market/macro alerts are native newspaper panels:
  - originate from the bottom-right Newspaper dock button;
  - render at 100% opacity with original newspaper art and liquid-glass framing;
  - auto-peek on each new quarter;
  - retract after 4 seconds unless manually pinned;
  - absorb back into the originating Newspaper icon when closed;
  - include headline, metadata, severity, policy implication, and risk-calendar status;
  - never physically affect dashboard, lever, metrics, or review layout.
- Static content belongs in Help, not the alert:
  - policy questions;
  - watch lists;
  - unemployment/output-gap explanations;
  - educational notebook text;
  - keyboard/help copy.
- Bottom-right dock has exactly three equally spaced icon-first buttons:
  - Newspaper;
  - Help;
  - Settings.
- Dock interactions are playful and native:
  - first click opens, second click closes;
  - toggling one dock panel closes the other dock panels, so stale panels never linger over the cockpit;
  - opening panels overshoot/bounce at the edge;
  - closing panels visually absorb into the originating icon;
  - the icon itself rebounds after absorbing the panel;
  - clicks get a short native sound when reduced-noise is off;
  - reduced-motion mode swaps bounce/slide for fade/instant transforms.
- The selected visual direction is a premium command desk:
  - mahogany/library warmth underneath Bloomberg-terminal information density;
  - a large full-width graph with clear left/right y-axis labels, target bands, and mouse-hover vertical stat readouts;
  - rate buttons presented as keyboard-like physical controls;
  - all dock panels and buttons using restrained liquid-glass highlights.
  Any future variant must beat this direction on policy-lever stability, readability, keyboard flow, and first-session comprehension before replacing it.

## Native Implementation Changes

- Swift core engine:
  - port and preserve the macro model, deterministic shock deck, scoring, reappointment grace, custom bps, and save digest behavior;
  - maintain parity fixtures against the TypeScript engine until the web reference is retired.
- SwiftUI app shell:
  - own window layout, keyboard commands, dock panels, settings, file import/export, debrief gates, and accessibility state;
  - use AppKit only where needed for save/open panels, menu commands, and installed-app packaging behavior.
- SpriteKit cockpit layer:
  - animate the mandate graph, policy pips, rate-decision pulses, hover readouts, and alert accents;
  - keep all animated art in atlases and use stable scene coordinates so content updates cannot resize the policy lever.
- Art pipeline:
  - use original generated UI art as native atlas inputs;
  - generate/refine additional command-desk assets as needed;
  - replace text-only dock buttons with original icon-first newspaper/help/settings art;
  - add native instrument textures, graph tick marks, rate pips, alert ribbons, and command-surface bezels;
  - no Federal Reserve seals, buildings, flags, official emblems, copied text, or copied UI.
- Release path:
  - build SwiftPM foundation first;
  - add full Xcode project once Xcode is installed;
  - add XCUITest and app archive/export;
  - remove Tauri/Web release scripts and source once native save/load/export/debrief parity is proven;
  - ship local beta as an `.app` plus manifest, with production Developer ID notarization when credentials are configured.

## Testing And Acceptance

- Swift tests:
  - engine parity;
  - deterministic shocks;
  - credibility grace;
  - custom bps;
  - save digest tamper detection;
  - score recomputation.
- Native UI tests after Xcode installation:
  - alert auto-retracts after 4 seconds;
  - lever frame delta stays within 4 px across rate clicks and overlay changes;
  - dock buttons are equally spaced and keyboard reachable;
  - Escape closes panels;
  - reduced motion disables bounce/slide;
  - keyboard shortcuts remain R/H/C.
- macOS verification:
  - install the built app into `/Applications`;
  - launch the installed app;
  - click real policy decisions through Computer Use/appshot;
  - verify no scroll jump or layout shift in the installed native app.
