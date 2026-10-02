# Playable Policy Lab validation

## Current verified candidate, October 2, 2026 (UTC)

The local Apple Silicon prerelease has passed Developer ID signing, Apple
notarization, stapling and Gatekeeper assessment. It is not market-ready or
store-published. Human playtesting and the checks below remain separate gates.

Validated runtime source: [PR32](https://github.com/ihearttokyo/fed-chairman-game/pull/32),
merge `985308d3764848bb7683e985a9f8cdf5cfa62356`. Its complete Git tree matches
reviewed build head `13b8cf801127852a78a70d512eaf217129d21095`.
[Exact-head CI](https://github.com/ihearttokyo/fed-chairman-game/actions/runs/37048399649)
and [merged-main CI](https://github.com/ihearttokyo/fed-chairman-game/actions/runs/37056416938)
passed. Later documentation or workbook-tooling changes do not imply a rebuilt app.

The validated ZIP is retained outside Git as
`The Chair — Apple Silicon keyboard reports notarized.zip`, SHA-256
`58870a4fac96f9e93b9d60f42b58cbef9b74f3decd27fea1474fc43633bbe41f`.
Apple accepted submission `6ad58890-ee4f-4562-8dcc-12c07319c1e3` with no issues.
The original and extracted apps passed ARM64-only, strict Developer ID,
hardened-runtime, secure-timestamp, staple and Gatekeeper checks. Actual
executables passed 164 release checks with model digest
`55a22f0cc0d6a658698cc8aa72ce489e586c6fe23ce23497902e44a30cf8d315`.
Six packaged source hashes and the original Blender city resources were checked.
No installed legacy app or user save was replaced.

### Current evidence and limits

- **Live game:** The signed production UI completed 240 actual Recurring crises
  meetings at seed 417, with all 20 periodic reviews. Its journal exposed all 241
  consecutive states and 33,391 selected characters; every applied rate matched
  the corresponding adoption feedback. Native read-only typing, Page Down,
  keyboard journal-to-review/OK and final disabled controls passed. No simulated
  prefix, external script override, Save or Load was used.
- **Live extracted app:** Funding stress at seed 42 completed five actual meetings.
  An 8% request applied 4.18%; lending normalized to the UI's 5% limit and applied
  only 3.02% of initial annual GDP against eligible need. Lending reduced the credit
  spread while a solvency-risk premium remained. Comparison, Cancel, the
  six-state read-only journal, deferred realized review and Help keyboard paths
  passed, with inspected pixels and unchanged window bounds/saved career.
- **Static and automated:** Full model/game and package/workbook guards passed.
  Independent GPT-6.1-Sol/xhigh read-only correctness/Ponytail review accepted
  the final report diff. Seven-case formula-workbook parity, native headless
  recalculation and four editable charts remain unchanged by this UI-only fix.
  These checks do not establish human difficulty or optimal policy.
- **Unverified:** macOS AXValue/selected-text reporting omits some wrapped
  fragments, including in the realized review. The full native assistive
  description and visible, keyboard-scrollable text do not certify that adapter
  output or actual VoiceOver speech. Representative human playtesting and a
  second physical Mac have not run. Native Excel checks passed case 7, quarter
  0/48, both benchmarks and an explicit-zero policy override followed by restoration.
  All five sheet views and four charts were inspected. Visible metrics matched
  rounded native references; this is not a full-precision Excel parity claim.
  The original hold-rate unemployment chart showed duplicate rounded axis labels.
  A format-only repair passed native Excel checks in a fresh workbook: case 7's
  0.05-point unemployment ticks display distinct two-decimal labels. All four
  charts, quarter 0/48 and restored default inputs passed; edits were discarded
  without saving. The repaired workbook's SHA-256 is
  `728a347760bcec5b7913ce55c413ea914d082412b32d3ede2d378a950f3b446f`.
  This does not establish unique labels at every possible automatic tick interval.
  LibreOffice's earlier macOS accessibility-bridge crash remains recorded. Both
  routes used disposable copies; original workbooks stayed unchanged, with no
  add-in, connector or Save used.

Current equations, seven scenarios, workbook regeneration and packaging belong
in the [model README](../game/README.md); economic acceptance belongs in the
[model contract](MODEL_CONTRACT.md). The older narrative below records prior artifacts
and failed checks; its architecture, counts and credential blocker describe
those earlier candidates, not the verified candidate above.

## Historical validation record, September 29–30, 2026

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

## Policy-comparison briefing, September 30

The source game now compares staged policy with a same-shock hold reference,
including requested versus applied tools, financial conditions, quarterly
outcome differences, credibility and public support. The new UI assertion first
failed because the comparison was absent. It then passed alongside the existing
career, chart and UI suites, 141 resource/replay checks and packaging safety
checks. Tests use the actual paired forecasts and verify career isolation and
no access to future realized shocks. Parent correctness and Ponytail reviews
found no remaining issue in this diff; model equations and saves are unchanged.

Live computer use covered an identical-policy comparison and a constrained-rate
comparison from saved quarter 17. The scrollable briefing showed a 6.30 percent
request capped at 5.22, and quarter-8 differences of -0.022 percentage points for
inflation, +0.063 for unemployment and -0.188 for output. Credibility was 56.9
versus 56.7; support rounded to 65.4 in both paths. Closing the briefing and
adopting advanced to quarter 18 with the capped rate and visible outcome
feedback. No engine errors appeared. Source hashes were captured before the
default-size GUI check; the existing save was not overwritten.

This briefing was tested in the source build, not the earlier signed ZIP. Jared
deferred Apple account recovery and notarization; development continues without
retrying authentication. Existing release and workbook validation gaps above
remain open. Rollback of this addition is a revert of its isolated UI commit.

## Realized policy review

The 12-quarter review now reports average inflation distance and employment
shortfall over the period, rather than only endpoint inflation movement. Its
hold-rate reference begins at the actual period-start state, shares only the
shocks already observed, and retains policy lags and hardship memory. It does
not replace the player's history or combine the two mandate costs into a score.

The missing comparison and missing UI explanation each produced intended RED
failures. Career tests then verified period boundaries, exact equality for hold
play, independent reference replay, distinct actual outcomes, state/save
immutability and exclusion of current/future unadopted shocks. Correctness and
Ponytail reviews passed before the broader career/chart/UI tests, 141 build
checks and packaging guards. The model digest is unchanged.

Live current-source computer use loaded the existing Q17 save, adopted seven
decisions and inspected the Q13–Q24 review. Actual versus hold-reference average
inflation distance was 1.124 versus 1.130 percentage points; average employment
shortfall was 0.118 versus 0.093. Ending credibility was 66.3 versus 57.3, while
support was 65.4 versus 65.5. The player achieved a small inflation improvement
at an employment cost over this period; the comparison makes no optimality claim.
The scrollable text was readable, and closing the review allowed Q25 adoption
without a reset. No engine errors appeared, and the saved career was not
overwritten. This is source-build evidence, not a newly signed release.
