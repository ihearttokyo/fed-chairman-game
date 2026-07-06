# Fed Chairman Playtest Repair Acceptance Inventory

Goal version: `fed-chairman-playtest-repair-2026-07-06-v1`

Authority sources:

- Jared's latest product critique and request for a critique-driven loop.
- Latest computer-use playtest of `/Applications/Fed Chairman Game.app` built
  from commit `afd5e033c8d6ede1f2835d4e5b73c43791b0568e`.
- Root `AGENTS.md` GUI validation and XCUITest anti-loop rules.
- Current native source, package scripts, and tests.

Statuses: `OPEN`, `PASS_PENDING_FINAL`, `PASS`, `STUCK`,
`BLOCKED_EXTERNAL`, `QUARANTINED`.

## Criteria

- id: `AC-001`
  statement: Policy preview is compact and readable; label/value pairs no longer span a giant horizontal gulf.
  source: latest computer-use playtest.
  authority: Jared playtest feedback plus visual screenshot evidence.
  verifier: fresh current-build large-window screenshot after selecting a policy move.
  pass_evidence: preview values sit near their labels, selected move is obvious, no stranded far-right values.
  fail_evidence: selected move preview looks like a broken wide form.
  status: `PASS_PENDING_FINAL`
  depends_on: []
  reopen_condition: preview layout or selected-move surface changes.
  last_verification: "2026-07-06: current-build GUI screenshot after selecting +25 bps showed compact staged move, metrics, and no stranded far-right label/value rows."

- id: `AC-002`
  statement: Policy preview explains directional consequences without pretending to provide exact simulation promises.
  source: redesign contract and latest playtest.
  authority: current product direction.
  verifier: source inspection plus selected-move screenshot.
  pass_evidence: preview copy uses clear directional language and no overprecise fake certainty.
  fail_evidence: preview reads as arbitrary deltas, opaque jargon, or exact forecast guarantees.
  status: `PASS_PENDING_FINAL`
  depends_on: [`AC-001`]
  reopen_condition: preview copy/model changes.
  last_verification: "2026-07-06: source and screenshot show directional labels such as Lower pressure, Little changed, Cleaner read; no exact simulation promise added."

- id: `AC-003`
  statement: Commit and Clear affordances match the importance of the decision and remain visually reachable.
  source: latest computer-use playtest.
  authority: player usability.
  verifier: screenshot after selecting a policy move.
  pass_evidence: primary commit action is visually clear, clear/reset is available but secondary.
  fail_evidence: commit/clear controls are visually lost or ambiguous.
  status: `PASS_PENDING_FINAL`
  depends_on: [`AC-001`]
  reopen_condition: policy decision center changes.
  last_verification: "2026-07-06: selected +25 bps screenshot shows Commit and Clear visible in the preview header row."

- id: `AC-004`
  statement: After a commit, the quarter review is visible in Desk without being clipped below the viewport.
  source: latest computer-use playtest.
  authority: screenshot evidence.
  verifier: fresh screenshot immediately after first commit in large-window Desk mode.
  pass_evidence: post-commit quarter review fits in the visible cockpit or has an obvious, usable scroll/route.
  fail_evidence: quarter review is pushed off the bottom and the consequence is easy to miss.
  status: `OPEN`
  depends_on: []
  reopen_condition: cockpit layout, desk copy, or post-commit feedback changes.
  last_verification: not run.

- id: `AC-005`
  statement: Post-commit feedback does not duplicate Decision Tape, Records, and Desk content without a clear purpose.
  source: Jared critique about redundancies.
  authority: product clarity.
  verifier: source inspection plus post-commit Desk and Records screenshots.
  pass_evidence: each surface has a distinct role: immediate receipt, historical record, or strategic interpretation.
  fail_evidence: the same quarter summary appears in multiple places with no added value.
  status: `OPEN`
  depends_on: [`AC-004`]
  reopen_condition: decision tape, records, or desk summary changes.
  last_verification: not run.

- id: `AC-006`
  statement: Decision Tape is an efficient receipt, not a dense competing briefing.
  source: latest playtest and redesign intent.
  authority: player clarity.
  verifier: screenshot after two committed quarters.
  pass_evidence: tape entries are scannable and make recent decisions obvious.
  fail_evidence: tape text is dense, redundant, or visually competes with the main decision loop.
  status: `OPEN`
  depends_on: [`AC-005`]
  reopen_condition: decision tape changes.
  last_verification: not run.

- id: `AC-007`
  statement: Early-game chart points and traces remain legible through Q1-Q3.
  source: latest computer-use playtest.
  authority: visual evidence.
  verifier: screenshots at launch, after Q1, and after Q3 in Charts or Desk mode.
  pass_evidence: dots, labels, and traces are readable and not crowded into an ambiguous cluster.
  fail_evidence: early points collapse visually or labels become unclear.
  status: `OPEN`
  depends_on: []
  reopen_condition: chart scale, drawing, or metrics presentation changes.
  last_verification: not run.

- id: `AC-008`
  statement: The current chart point has a keyboard- and mouse-independent textual explanation somewhere in the primary loop.
  source: accessibility and usability review.
  authority: player clarity.
  verifier: source inspection plus Desk/Charts screenshot after a commit.
  pass_evidence: current quarter metrics and meaning are visible without relying on hover.
  fail_evidence: chart details require hover or are only available in a secondary panel.
  status: `OPEN`
  depends_on: [`AC-007`]
  reopen_condition: chart or current-state rail changes.
  last_verification: not run.

- id: `AC-009`
  statement: The current rail explains board risk and mandate state rather than only repeating numbers.
  source: latest playtest.
  authority: game clarity.
  verifier: screenshot at Q0 and after a commit.
  pass_evidence: player can tell why the board is safe, tense, or angry.
  fail_evidence: rail repeats metrics without explaining risk.
  status: `OPEN`
  depends_on: []
  reopen_condition: current rail or board-risk model changes.
  last_verification: not run.

- id: `AC-010`
  statement: The briefing strip is readable and does not truncate important risk chips.
  source: latest playtest.
  authority: visual evidence.
  verifier: large-window first-launch and post-commit screenshots.
  pass_evidence: briefing text and chips fit or intentionally collapse with no lost meaning.
  fail_evidence: clipped chips or crowded right-side badges hide important state.
  status: `OPEN`
  depends_on: []
  reopen_condition: briefing strip layout changes.
  last_verification: not run.

- id: `AC-011`
  statement: Newspaper mode adds meaningful context or is demoted/removed; it does not duplicate the briefing with awkward cropped art.
  source: latest computer-use playtest.
  authority: Jared critique and visual evidence.
  verifier: screenshot of Newspaper opened from current build.
  pass_evidence: newspaper content is useful, readable, and visually intentional, or the surface is simplified out of the core loop.
  fail_evidence: cropped art and duplicate copy make the panel feel decorative or broken.
  status: `OPEN`
  depends_on: []
  reopen_condition: newspaper panel/content changes.
  last_verification: not run.

- id: `AC-012`
  statement: Help is discoverable and useful without becoming another redundant explanation surface.
  source: GUI playtest scope.
  authority: player onboarding.
  verifier: screenshot and quick read of Help panel.
  pass_evidence: help clarifies controls/core loop in minimal language and does not duplicate every other panel.
  fail_evidence: help is opaque, too hidden, or bloated.
  status: `OPEN`
  depends_on: []
  reopen_condition: help or dock changes.
  last_verification: not run.

- id: `AC-013`
  statement: Records mode separates history from preferences/export affordances so controls are not tiny or clipped.
  source: latest playtest observation.
  authority: visual evidence.
  verifier: Records screenshot at Q2 or later.
  pass_evidence: historical records are readable and utility actions are reachable with non-truncated labels.
  fail_evidence: save/export/settings controls crowd the history or labels clip.
  status: `OPEN`
  depends_on: []
  reopen_condition: Records or settings/export UI changes.
  last_verification: not run.

- id: `AC-014`
  statement: Records mode remains valuable but does not become the only place where the latest quarter consequence is readable.
  source: latest playtest.
  authority: primary-loop clarity.
  verifier: compare Desk and Records screenshots after a commit.
  pass_evidence: Desk gives enough immediate feedback; Records adds history/depth.
  fail_evidence: player must switch to Records to understand what just happened.
  status: `OPEN`
  depends_on: [`AC-004`, `AC-013`]
  reopen_condition: Desk or Records feedback changes.
  last_verification: not run.

- id: `AC-015`
  statement: Mode rail avoids redundant labels and wasted width.
  source: visual review.
  authority: UI economy.
  verifier: first-launch screenshot.
  pass_evidence: navigation labels are distinct, compact, and do not repeat title/subtitle text.
  fail_evidence: visible duplication such as "Desk" repeated as label and heading without purpose.
  status: `OPEN`
  depends_on: []
  reopen_condition: mode rail or cockpit hierarchy changes.
  last_verification: not run.

- id: `AC-016`
  statement: Board renewal thresholds are clearly distinguished from monetary policy targets.
  source: gameplay clarity review.
  authority: economic/game semantics.
  verifier: source inspection plus UI screenshot where board-risk language appears.
  pass_evidence: player can distinguish 2% inflation target from board-renewal danger gates such as 4%.
  fail_evidence: board thresholds look like arbitrary contradictions to the mandate target.
  status: `OPEN`
  depends_on: [`AC-009`]
  reopen_condition: board-risk copy/model changes.
  last_verification: not run.

- id: `AC-017`
  statement: Early policy response and lag behavior feel economically coherent, not arbitrary.
  source: Jared critique about mechanics and reaction functions.
  authority: current core mechanic and economic plausibility.
  verifier: unit/model inspection plus playtest of several early decisions.
  pass_evidence: directional outcomes make intuitive sense under inflation/labor/credibility tradeoffs and lags are surfaced.
  fail_evidence: normal decisions create unexplained deterministic inflation/unemployment jumps or collapses.
  status: `OPEN`
  depends_on: []
  reopen_condition: game engine, scenario, or preview model changes.
  last_verification: not run.

- id: `AC-018`
  statement: No cheat or scenario path deterministically worsens inflation and unemployment without an explicit, grounded model reason.
  source: Jared critique of the prior Trump cheat.
  authority: product/game mechanics.
  verifier: source search for cheat/scenario branches plus relevant tests.
  pass_evidence: no hidden cheat path or arbitrary deterministic macro penalty remains.
  fail_evidence: cheat/scenario code injects unexplained inflation and unemployment changes.
  status: `OPEN`
  depends_on: [`AC-017`]
  reopen_condition: scenario or debug command code changes.
  last_verification: not run.

- id: `AC-019`
  statement: Credibility language describes an interpretable policy channel instead of a gamey punishment.
  source: playtest and economic clarity review.
  authority: player comprehension.
  verifier: source inspection plus preview/commit screenshots.
  pass_evidence: credibility copy explains signal, confidence, or institutional trust in context.
  fail_evidence: normal hikes show opaque "credibility cost" with no reason.
  status: `PASS_PENDING_FINAL`
  depends_on: [`AC-002`, `AC-017`]
  reopen_condition: credibility model or copy changes.
  last_verification: "2026-07-06: DecisionFeedback now says policy signal/anchor drift/trust building instead of rate cost; selected-move preview says credibility signal burden instead of credibility cost."

- id: `AC-020`
  statement: Early game has enough meaningful variation to feel alive without scripted or fake shocks.
  source: playtest observation.
  authority: game feel.
  verifier: playtest through at least Q4 plus source inspection of shock/variation model.
  pass_evidence: outcomes vary because of model state, policy lag, or documented events; not random clutter.
  fail_evidence: first quarters feel deterministic and inert, or variation is decorative and unexplained.
  status: `OPEN`
  depends_on: [`AC-017`]
  reopen_condition: shock/event/model changes.
  last_verification: not run.

- id: `AC-021`
  statement: Settings exposes Fast commit clearly, defaults off, and does not conflict with the selection-first decision loop.
  source: redesign Package A contract.
  authority: current product requirement.
  verifier: Settings screenshot and keyboard behavior inspection.
  pass_evidence: Fast commit is visible, defaults off, and selection/Return/Escape behavior remains coherent.
  fail_evidence: fast commit is hidden, defaults on, or creates duplicate/bypassing flows.
  status: `OPEN`
  depends_on: []
  reopen_condition: settings or input contract changes.
  last_verification: not run.

- id: `AC-022`
  statement: Accessibility/test hooks do not leak confusing hidden strings into the player-facing VoiceOver experience.
  source: playtest note about `motion-mode-reduced`.
  authority: accessibility quality.
  verifier: accessibility tree inspection or targeted source inspection.
  pass_evidence: identifiers remain useful for tests without noisy labels being read as content.
  fail_evidence: hidden test strings are exposed as player-facing accessibility labels.
  status: `OPEN`
  depends_on: []
  reopen_condition: accessibility identifiers/labels change.
  last_verification: not run.

- id: `AC-023`
  statement: Save/load/export flows are actually exercised, not assumed from code checks.
  source: latest playtest not-run gap.
  authority: product reliability.
  verifier: current-build GUI playtest or scriptable macOS dialog-safe inspection covering save/load/export.
  pass_evidence: user can save, load, and export without losing state or hitting broken dialogs.
  fail_evidence: flow untested, blocked by dialogs, clipped labels, or state mismatch.
  status: `OPEN`
  depends_on: [`AC-013`]
  reopen_condition: persistence/export code or Records controls change.
  last_verification: not run.

- id: `AC-024`
  statement: Installed-app validation always proves provenance before accepting screenshots.
  source: root `AGENTS.md` and recent false claim correction.
  authority: repo rule.
  verifier: validation notes in `loop/VERIFY.md` include commit, app path, and executable hash or bundle metadata.
  pass_evidence: GUI evidence names the current commit and installed artifact metadata.
  fail_evidence: screenshots are accepted without proving they came from the intended build.
  status: `PASS_PENDING_FINAL`
  depends_on: []
  reopen_condition: every GUI validation run.
  last_verification: "2026-07-06: validation notes recorded current git commit, /Applications path, bundle metadata, and executable sha256 64f1fc446ba4cd567ecb4146b3f7289033ba29986a6ba0c0d168730cb8a928e1."

- id: `AC-025`
  statement: The loop does not re-enter broad XCUITest or repeated GUI-suite loops as a substitute for player validation.
  source: Jared repeated instruction and root `AGENTS.md`.
  authority: repo validation policy.
  verifier: command history/final report includes no broad XCUITest unless explicitly requested.
  pass_evidence: validation uses code checks plus one large-window screenshot-first playtest.
  fail_evidence: repeated `npm run test:ui`, raw `xcodebuild test`, or responsive matrices without explicit request.
  status: `PASS_PENDING_FINAL`
  depends_on: []
  reopen_condition: every validation run.
  last_verification: "2026-07-06: no raw xcodebuild UI test, npm run test:ui, or broad XCUITest suite was run; validation used code checks plus one large-window computer-use pass."

- id: `AC-026`
  statement: Final report is evidence-first and names skipped checks, residual risks, branch/commit, dirty files, and unpushed commits.
  source: root `AGENTS.md` final report and git hygiene rules.
  authority: repo operating rules.
  verifier: final response/report review.
  pass_evidence: report starts with Result/Attention and includes relevant Validation/Git/Next sections.
  fail_evidence: report buries blockers or implies unverified quality.
  status: `OPEN`
  depends_on: []
  reopen_condition: every loop halt or package handoff.
  last_verification: not run.

- id: `AC-027`
  statement: Commercial-readiness cleanup removes dead/duplicative UI paths only after proving no internal dependency.
  source: Jared request to prune stale pathways and clean modern app.
  authority: maintainability and product clarity.
  verifier: `rg` dependency scan plus build/tests after deletion.
  pass_evidence: removed code has no live references and validation passes.
  fail_evidence: duplicate/dead path remains or deletion breaks live flow.
  status: `OPEN`
  depends_on: []
  reopen_condition: cleanup/deletion work.
  last_verification: not run.

- id: `AC-028`
  statement: Core mechanics remain the product center; new UI surfaces must support decisions, consequences, and mandate state.
  source: Jared critique of BS duplicative changes.
  authority: product direction.
  verifier: visual review plus source inspection of newly touched UI.
  pass_evidence: every visible surface has a clear role in policy decision, consequence, mandate, or record.
  fail_evidence: decorative or duplicative panels crowd the main loop.
  status: `OPEN`
  depends_on: [`AC-005`, `AC-011`, `AC-015`]
  reopen_condition: any new UI surface.
  last_verification: not run.
