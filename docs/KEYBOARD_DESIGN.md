# Keyboard-complete policy lab

## Value, scope and acceptance

The entire game must be playable without a mouse: start or cancel a career,
choose its scenario and seed, stage every policy input, inspect forecasts and
history, adopt decisions, read or close reviews, save or cancel a load, inspect
credits and help, and toggle animation. Keyboard use must not reduce policy
depth. Reading the dispatch and chart values must not depend on hover.

This pass changes input, focus and cockpit density, not equations, shocks, save
format, assets or window geometry. Preserve the installed legacy app, all stored careers
and the externally used test window. Use an isolated unsaved canary. Rollback is
the isolated PR; no user-data conversion or installation is part of this pass.

Acceptance requires actual key-event tests for complete forward/backward focus
cycles, hidden custom guidance, disabled terminal adoption, all numeric fields,
scenario selection, chart inspection, scroll access, modal entry/exit, shortcuts
and accidental-input prevention. Compare remains pure; adoption occurs exactly
once. Confirmed save/load uses a disposable path in tests, never the user's save.
Native background keyboard interaction and inspected screenshots are separate
live gates; headless checks alone do not prove usability.

## Research: six data-heavy simulation examples

Sources checked October 3, 2026. These examples include literal terminal-style
economy simulation and adjacent business, transport, sports-management and
grand-strategy interfaces. They establish useful patterns, not a claim that
every example is itself entirely keyboard accessible.

### Prosperous Universe: terminal operations

The official APEX handbook documents Ctrl+Space opening a buffer and Escape
closing the selected buffer. This makes a large information workspace navigable
through a small, consistent command vocabulary. The transferable pattern is
direct access to information and predictable dismissal. Our reports should
receive focus when opened and return it when closed. Its short documented list
does not establish keyboard coverage of every APEX operation.
[Official handbook](https://handbook.apex.prosperousuniverse.com/wiki/miscellaneous/index.html).

### Capitalism Lab: reports, numeric changes and records

The developer documents mnemonic report shortcuts, save/load commands,
plus/minus numeric changes, Page Up/Down and Home/End for records, and Escape
to leave a screen. These match the lab's repeated cycle of inspect, edit and
compare. However, its record navigation can depend on which list contains the
mouse pointer. We should use the focused control instead: a keyboard player
must never need to position a pointer to select the target of a key.
[Developer shortcut reference](https://www.capitalismlab.com/shortcut-keys/).

### OpenTTD: context and platform conventions

The project manual groups shortcuts by open tool/window, gives Escape a cancel
role, and distinguishes macOS from Windows combinations. It warns that some
keys assume US QWERTY and documents configurable bindings. Its removed enormous
map-screenshot shortcut is also a warning against expensive accidental actions.
For the lab, keep edit keys local, use platform-aware command modifiers, and
never map an unmodified typing key or ordinary Return to global adoption.
The game is already turn-based; speed and camera shortcuts would add no value.
[Project hotkey manual](https://wiki.openttd.org/en/Manual/Hotkeys).

### Football Manager: discovery and personal workflows

Sports Interactive's FM2022 manual describes adjustable keyboard shortcuts and
a discoverable list in Preferences. It also describes multiple data views and
bookmarks for useful screens. The relevant lesson is that commands need a
visible reference and consistent destinations, not memorization alone. The lab
will expose its commands in How to play and button hints, while every command
also remains available through ordinary focused controls. This manual is
version-specific; no undocumented FM2026 bindings are assumed.
[Developer manual](https://community.sports-interactive.com/sigames-manual/football-manager-2022/die-benutzeroberfl%C3%A4che-r4560/).

### Victoria 3: customization and deliberate interruption

Paradox's update 1.2 changelog explicitly introduced rebindable hotkeys and
notification behavior that can pause single-player play. These are useful in a
dense macroeconomic simulation: commands should be adaptable, and information
should not make the player race the clock. Our quarterly game already waits
indefinitely for a decision. Keyboard access must preserve that pacing, isolate
modal reports from gameplay commands, and make adoption a deliberate action.
The changelog supports these features, not a complete default-key inventory.
[Developer changelog](https://www.paradoxinteractive.com/games/victoria-3/news/dev-diary-78-update-1-2-changelog).

### Offworld Trading Company: fast commands with visible hints

The distributed almanac's Player Controls section, page 13 of the PDF, documents
Tab cycling headquarters, direct action keys, modified transaction amounts and
hover-discoverable construction shortcuts. The useful pattern is reducing
repeated navigation while showing commands where actions occur. Hover-only
discovery is insufficient here: How to play must provide the same information
to keyboard users. Its real-time competition and pointer-based map placement
are not suitable templates for our deliberative policy decisions.
[Distributed almanac](https://cdn.fastly.steamstatic.com/steam/apps/271240/manuals/Offworld_Trading_Company_Almanac.pdf?t=1598370244).

## Accessibility and engine constraints

Microsoft XAG107 calls for digitally operable interface components and less
physically demanding alternatives to timed, held or simultaneous input. Use
ordinary Tab and focused activation for every command; modifier shortcuts are
optional accelerators, never the only route.
[Xbox input guideline](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/107).

W3C's keyboard guidance favors platform conventions, describes focused button
activation with Return/Space, and rejects MouseKeys as a keyboard equivalent.
Its grid pattern distinguishes navigation from text editing. Apply that
distinction to numeric fields and charts without pretending this Godot app is
a web grid or claiming WCAG certification.
[Keyboard guidance](https://www.w3.org/WAI/WCAG22/Understanding/keyboard.html),
[grid interaction](https://www.w3.org/WAI/ARIA/apg/patterns/grid/).

Godot provides native UI focus, next/previous neighbors, button shortcuts and
native text editing. Its documentation warns against repurposing UI actions as
gameplay and against leaving complex focus order to engine guesses. Prefer
these facilities over a second input framework. Hidden controls can lose focus;
modal restoration and custom-guidance visibility need explicit tests.
[Godot 4.7 focus](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_navigation.html),
[native button shortcuts](https://docs.godotengine.org/en/4.7/classes/class_basebutton.html).

## Chosen controls

- Tab / Shift+Tab: forward / backward through visible enabled controls.
- Return / Space: activate the focused button; Return in a numeric field
  commits that field only. Ordinary typing never adopts a quarter.
- Up / Down in a numeric field: increase / decrease by its advertised arrow
  step; typing and standard selection/editing shortcuts remain available.
- Arrow keys in a scenario/guidance menu: navigate choices; Return selects;
  Escape dismisses without adopting a decision.
- Left / Right on a chart: inspect adjacent completed quarters; Home / End:
  first / latest. Exact selected values remain visibly displayed.
- Page Up / Down and Home / End in the cockpit scroll control or report body:
  browse long content. Focus-following scroll keeps inputs visible.
- Escape: close or cancel the current modal, preserving staged decisions.
- Cmd on macOS / Ctrl elsewhere plus N, S, O, J, P and R: New, Save, Load,
  journal, Compare and staff rule. Modified Return: adopt one quarter.
- F1: How to play. Every shortcut has an ordinary Tab-accessible equivalent.

No global unmodified-letter shortcuts, double-tap timing, held-key adoption,
pointer-directed keys or runtime network work. A new focus ring or faithful
keyboard value readout is a mechanical accessibility change, not an asset
redesign. Economic and asset redesigns remain outside this PR. The existing cockpit uses
one-line title and metric rows with smaller padding. Slogans, city provenance
and the legal footer move out of the main screen; disclosure and notices remain
in Help and Credits. Immediate metric tooltips retain secondary detail in
assistive descriptions. Targets, reference values, policy units and forecast
assumptions stay visible.
