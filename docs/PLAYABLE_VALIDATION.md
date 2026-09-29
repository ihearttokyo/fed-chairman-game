# Playable Policy Lab validation

The clean-sheet Godot game is a local pre-release candidate, not a market-ready
or notarized release. It keeps the Swift application and its saved careers
separate. The [model contract](MODEL_CONTRACT.md) and [model README](../game/README.md)
define the equations, assumptions and limits.

## Implemented and checked

Six hypothetical scenarios share one deterministic economic model. Players stage
a rate, conditional guidance, asset flow and eligible lending request, compare an
eight-quarter conditional path, then adopt. Careers preserve expectations,
transmission lags, hardship memory and chart history across 12-quarter reviews.
There is no popularity or unemployment dismissal threshold.

The parent ran the career, chart and UI tests with Godot 4.7.2. Regression tests
cover exact save replay, invalid-save preservation, seed bounds, forecast
isolation, chart ticks, displayed rate precision and deferred dialog lifetimes.
Luna xhigh read-only reviews covered the career/chart section and UI/release
section. The parent reproduced and fixed their seed-range, outcome-announcement
and review-wording findings before broader checks.

Live computer-use checks covered supply-shock play through quarter 17, a funding
case with lending, save/load and continued play after a review. In the actual
export, the journal retained quarter-17 history and the next adopted decision
applied a 5.22 percent rate to a 6.30 percent request because of the model's
quarterly change limit. These checks demonstrate those paths, not optimal play
or a representative human difficulty study.

The original Blender city has editable source and a GLB runtime asset. The
export loads it without requiring Blender on the player's machine. Engine and
component copyright/license texts are available under Credits.

## Export evidence

The earlier universal macOS candidate used the official checksum-verified 4.7.2 template.
Its historical local ZIP SHA-256 is:

```text
2855f81ca43b6e3fcb59a9b52190924f309530c2ed57cd7f2e7574c4645969fc
```

Its extracted app passed strict ad-hoc signature verification. Running the actual
release executable passed 141 explicit checks: six 20-quarter careers, lossless
replay, main-scene initialization and city loading. Bundled model digest:

```text
4f28f022f9dbbb1342571d437519d79377d9219fede9a885b0c714f0446758f2
```

The official template's external script/path restrictions remain enabled. The
fixed `--verify-build` entry point performs no external script loading or writes.
Source and executable hashes were recorded before the live export checks.

An earlier export produced a Godot embedded-window focus error after Cancel.
An isolated reproduction and failing deferred-lifetime test identified an early
window hide. Native dialog buttons now queue deletion after the accessibility
action finishes. The final export's targeted Cancel and Load checks preserved
state and produced no engine errors. Earlier error logs remain failed evidence.

## Spreadsheet and remaining gates

The accompanying formula workbook matches all six 48-quarter reference cases and
four one-control variations within 6e-13. LibreOffice headless recalculation of
the default case matches within 1e-13, with no formula errors and four bound
charts. All numerical coefficients other than source-defined identities and the
inflation objective are disclosed design assumptions. This is not an empirically
fitted forecasting model.

Interactive workbook validation has not run: its background file dialog stalled,
and permission to foreground LibreOffice is pending. VoiceOver speech and a
second physical Mac have not been tested. The exported game has been inspected
at its default large-window size, not across a responsive size matrix.

PR2's legacy native launch check still fails at the existing `macro-metrics`
accessibility lookup; that is not a passing native release gate. The native
workflow remains intact. Godot checks have their own all-PR workflow so stacked
game changes can be validated without repeating unchanged legacy UI automation.

The September 30 Apple Silicon candidate is ARM64-only and signed with Jared's
Developer ID Application identity, team 4QUZHBXSVT. Strict signature verification,
hardened runtime, secure timestamp and all 141 release checks passed. The same
architecture assertion first rejected the earlier universal candidate.

Live computer use against the signed app loaded the saved quarter-17 career,
staged the staff rate and adopted quarter 18 with the correct 5.22 percent limit.
The city, charts, labels and outcome feedback were visually inspected at the
current window size. Source and bundle hashes were recorded before interaction.
No gameplay source changed during the packaging correction.

Apple rejected the existing stored notarization credential before accepting an
upload. A working credential is required; no security bypass or store publication
occurred. Intel hardware validation is not a gate for the ARM64-only release.
Rollback is a revert of the isolated playable-game commit; no legacy save
migration or replacement installation is included.
