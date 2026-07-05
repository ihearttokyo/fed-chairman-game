# Fed Chair Redesign LLDD Evaluation

Date: 2026-07-04

Source package: `/Users/jared/Downloads/fed_chair_redesign_package`

Current app baseline: native macOS SwiftUI/SpriteKit cockpit on `main`, with a single cockpit surface, top status rail, dock panels for Newspaper/Help/Settings, SpriteKit mandate chart, direct-commit policy lever, portable save/load/export, and term debrief overlay.

## Executive Verdict

The redesign package is directionally strong and should be taken seriously. Its biggest product insight is not the visual styling; it is the move from "instrument panel with immediate buttons" toward "guided policy desk with mode-specific decision preparation." That can materially improve player clarity, onboarding, commercial polish, and replayability.

The best implementation path is not a literal web-dashboard transplant. The current product is a native macOS game, not a SaaS control panel. Adopt the package as a native mode architecture: persistent status, explicit modes, semantic severity, clearer risk hierarchy, policy preview before commit, chart focus, richer briefing, dedicated preferences/export, and a tighter end-of-term report.

Highest-leverage first package for the next turn:

1. Add a core `TermSnapshot`/semantic-state layer and design tokens.
2. Convert the direct policy lever into a pending-selection -> preview -> commit decision center.
3. Introduce a native `CockpitMode` shell with Overview, Briefing, Mandate, Policy, Preferences, and History/Term Summary destinations.

Do not implement third-party telemetry from the LLDD notes. The repo explicitly excludes telemetry and backend services; use local debug instrumentation/tests only.

## Evaluation Rubric

Each LLDD was scored against the current implementation on a 100-point internal rubric:

- Player clarity and decision usefulness: 25
- Strategic fit with the current native game: 20
- Implementation leverage from existing code: 15
- Risk-adjusted complexity: 15
- Accessibility and native macOS quality: 10
- Testability and release confidence: 10
- Commercial polish: 5

Adoption bands:

- 85-100: adopt as a major product direction.
- 70-84: adopt, but phase or adapt heavily.
- 55-69: selectively mine for components.
- Below 55: defer or reject.

## Current Implementation Observations

The existing app already contains several seeds of the redesign:

- Derived cockpit models exist for board watch, briefing, debrief, decision feedback, chart inspection, and transmission review.
- The main view computes these models directly from `GameSession` and lays them into one fixed cockpit stack: status rail, dock panels, metrics, dashboard, policy lever, and optional review.
- `GameSessionStore` already offers a single published session mutation surface, but there is no explicit LLDD-style `termSnapshot` object or route/mode state.
- The current policy buttons commit immediately. A hover only changes selection; selection itself is not a pending decision.
- The chart already uses fixed 0-10 scaling, target bands, metric colors, endpoint/latest labels, and hover inspection, but it is constrained by the cockpit layout and lacks a full focus mode.
- Save, load, CSV, JSON, and Markdown export already exist, but they live inside the Settings drawer rather than a dedicated route.
- The term-ended overlay already includes verdict, score, grade, career quarter, narrative lines, handoff metrics, and start/continue actions, but lacks replay/export actions and a report-first layout.

Key code anchors:

- Fixed cockpit stack: `native/FedChairmanGame/Sources/FedChairmanNativeApp/FedChairmanGameNativeApp.swift:115`
- Status rail and board watch: `native/FedChairmanGame/Sources/FedChairmanNativeApp/FedChairmanGameNativeApp.swift:176`
- Direct-commit policy buttons: `native/FedChairmanGame/Sources/FedChairmanNativeApp/FedChairmanGameNativeApp.swift:325`
- Commit mutation path: `native/FedChairmanGame/Sources/FedChairmanCore/GameSessionStore.swift:17`
- Current briefing model: `native/FedChairmanGame/Sources/FedChairmanCore/CockpitBriefing.swift:10`
- Current chart rendering: `native/FedChairmanGame/Sources/FedChairmanNativeApp/CockpitScene.swift:39`
- Save/load/export actions: `native/FedChairmanGame/Sources/FedChairmanNativeApp/FedChairmanGameNativeApp.swift:765`
- Settings drawer: `native/FedChairmanGame/Sources/FedChairmanNativeApp/NewspaperPanelView.swift:258`
- Term debrief overlay: `native/FedChairmanGame/Sources/FedChairmanNativeApp/FedChairmanGameNativeApp.swift:720`
- Telemetry exclusion: `README.md:143`

## Scores By LLDD

| Change | Score | Verdict | Why |
| --- | ---: | --- | --- |
| 01 Clearer Product Structure | 86 | Adopt, native-adapted | Strong fix for orientation and mode clarity; current app has no route model. Left rail should become a native game mode rail/sidebar, not a literal web dashboard shell. |
| 02 More Readable Hierarchy | 88 | Adopt | Directly addresses the current "everything is visible, but not all of it is prioritized" problem. Requires a risk-driver model but fits existing briefing/board-watch code. |
| 03 State-Based Color System | 82 | Adopt as foundation | Important because current colors mix metric identity and semantic health. Needs tokens and labels/icons; should precede broad visual redesign. |
| 04 Improved Policy Decision Flow | 95 | Adopt first | Highest product payoff. Current direct commit makes policy decisions too fast and under-explained. Pending preview would make the game feel more deliberate and teachable. |
| 05 Cleaner Mandate Chart | 84 | Adopt in phases | Current SpriteKit chart is already capable, but focus mode, current-value rail, target labels, and insight band would materially improve comprehension. Series toggles can wait. |
| 06 Expanded Briefing & Guidance | 80 | Adopt after shell/snapshot | Current briefing has useful copy fields but not a true prep mode with decomposed risk and handoff. High clarity payoff once modes exist. |
| 07 Dedicated Preferences & Export | 72 | Adopt later | Existing save/export/settings work is functional. Dedicated route improves cleanliness, but it is less urgent than policy flow and briefing. Preference persistence needs careful native design. |
| 08 Focused Term-Ended Summary | 78 | Adopt as polish-plus | Current debrief is close. Add replay/export/summary structure after snapshot/report models are stable. |

## Per-Change Evaluation

### 01 Clearer Product Structure

Current fit: partial. The current cockpit has a top status rail and repeated card-like panels, but no persistent navigation or route state. Primary modes are implicit: the main cockpit plus dock panels.

Why it matters: new players need orientation. A mode rail would make "Overview vs Briefing vs Mandate vs Policy vs Preferences" explicit and would give future features a stable home.

Risks:

- A literal left nav plus top bar may make the game feel like an admin dashboard rather than a monetary policy game.
- More routes can fragment the tight "read chart, choose rate, see consequence" loop if the policy lever disappears too often.
- Route state must not corrupt deterministic replay or save/load.

Recommendation:

- Implement `CockpitMode` as native state, likely in `UiState` or view-local state depending on save semantics.
- Keep the top status rail persistent.
- Preserve an Overview cockpit for fast play.
- Let Briefing, Mandate, Policy, Preferences, and History be mode-specific layouts.
- Defer any telemetry SDK. If needed, add local debug counters under test flags only.

Implementation readiness: medium. Requires significant SwiftUI composition work but little engine change.

### 02 More Readable Hierarchy

Current fit: strong. The app already computes `CockpitBriefing`, `BoardWatch`, `DecisionFeedback`, and `TransmissionBriefing`, but their outputs are distributed across equal-weight panels.

Why it matters: this is the package's second-biggest clarity upgrade. A player should know the main risk driver before choosing a policy action.

Risks:

- Risk priority must be deterministic and explainable; vague "severity" copy will feel arbitrary.
- Critical banners can become visually noisy if every bad quarter screams.
- Needs color tokens first to avoid another round of ad hoc colors.

Recommendation:

- Add a core `RiskDriver`/`PriorityItem` model derived from inflation gap, unemployment gap, credibility, lagged policy, and active shocks.
- Render a severity briefing banner and concise consequence/review strip.
- Keep critical states visually distinct with text/icon labels, not color alone.

Implementation readiness: high. Most inputs already exist in `GameSession`, `ScoreState`, traces, and briefing code.

### 03 State-Based Color System

Current fit: partial. Metric colors are consistent enough in the chart, but semantic state uses ad hoc `.green`, `.orange`, `.red`, `.yellow`, `.cyan`, and `.mint` across board watch, metrics, transmission, settings, and panels.

Why it matters: the current app sometimes uses green both as semantic success and as the fed funds series color. The LLDD correctly separates metric identity from state health.

Risks:

- Over-tokenizing too early could create a design-system refactor with little user payoff.
- WCAG validation needs practical native screenshot/contrast checks, not just code constants.

Recommendation:

- Add a small `CockpitPalette`/`SemanticState` layer, not a huge design system.
- Keep metric colors stable: inflation orange, unemployment blue, fed funds green, expectations cyan/mint, credibility yellow.
- Add semantic states: neutral, onTrack, atRisk, critical, disabled.
- Require adjacent labels/icons for all semantic states.

Implementation readiness: high. This should be a prerequisite for the visual parts of the redesign.

### 04 Improved Policy Decision Flow

Current fit: gap. The current policy lever commits on click. There is no pending selection, preview status, impact table, or explicit clear step.

Why it matters: this is the most revolutionary change. It turns the core interaction from twitchy button press into a policy deliberation loop: select, understand, commit. It also reduces accidental commits.

Risks:

- Extra friction could slow experienced play if the preview/commit flow is not keyboard-friendly.
- The preview model must be honest. A fake exact forecast would undermine the simulation; label it as estimated directional impact with confidence.
- Needs careful keyboard shortcuts: current numeric shortcuts commit immediately.

Recommendation:

- Add pending policy selection state and a preview model in core.
- Use the existing engine coefficients/traces to estimate directional next-quarter effects without mutating session state.
- Change button behavior to select, not commit.
- Add explicit Commit and Clear actions.
- Preserve fast play with keyboard: number selects; Return commits; Escape clears.
- Tighten custom range to the visible direct-action range of -150 to +150 unless there is a product reason to keep the hidden +/-300 path.

Implementation readiness: medium-high. Engine mutation is centralized, so a non-mutating preview can be added cleanly, but tests are important.

### 05 Cleaner Mandate Chart

Current fit: strong partial. The current SpriteKit chart already has the fixed 0-10 domain, target bands, axis labels, legend, endpoint/latest labels, and hover readout. The LLDD's focus-mode layout and current-value rail are the missing pieces.

Why it matters: the mandate chart is the product's main game board. Bigger chart plus target labels and side rail would materially reduce interpretation time.

Risks:

- Full series toggle and tooltip interactivity in SpriteKit may cost more than it is worth in the first pass.
- A larger chart competes with the policy decision center unless mode routing exists.
- Native accessibility for SpriteKit chart details must remain backed by SwiftUI labels/inspection strips.

Recommendation:

- Implement Mandate mode as a larger chart view using the existing `SpriteKitChart`.
- Add visible target labels for 2.0% inflation and 5.0% unemployment.
- Move latest values into a SwiftUI side rail outside the SpriteKit canvas for accessibility.
- Add an insight band derived from `ChartInspection`/score gaps.
- Defer legend toggles until after the core focus view proves useful.

Implementation readiness: high for focus view and side rail; medium for series toggles.

### 06 Expanded Briefing & Guidance Modes

Current fit: medium. `CockpitBriefing` already has headline, severity, body, policy implication, and risk calendar. Help topics and transmission readouts already add context. The missing part is a true briefing route with risk drivers, sparkline evidence, handoff metrics, and a CTA into policy.

Why it matters: this can make the game teach itself. It should reduce the "what should I be looking at?" problem without making the player feel railroaded.

Risks:

- Guidance can become too prescriptive. The game should explain the bias, not tell the player the only correct move.
- Sparkline cards require either mini chart rendering or simplified SwiftUI paths.
- Briefing must never reference stale metrics after a commit.

Recommendation:

- Extend the core briefing model with `riskDrivers`, `policyImplication.bias`, and `handoffMetrics`.
- Use deterministic wording and existing trace data.
- Add "Go to Policy" mode switch carrying briefing context.
- Avoid "recommended move" language; use "bias" and "watch item."

Implementation readiness: medium. Needs model work but aligns with existing briefing helpers.

### 07 Dedicated Preferences & Export Screen

Current fit: partial. Current settings drawer has motion, sound, noise, save, load, CSV, JSON, and Markdown. It lacks auto-advance/tooltips toggles, explicit process guards, richer feedback, and app-launch preference hydration.

Why it matters: moving file operations away from the policy surface reduces cockpit clutter and makes release/export features feel real.

Risks:

- This is lower gameplay payoff than policy preview and briefing.
- Native "local storage/page refresh" needs translation to app relaunch preferences, likely `UserDefaults`, not web local storage.
- Save/load/export should remain AppKit-native and secure.

Recommendation:

- Promote Settings drawer into Preferences mode after shell exists.
- Persist UI preferences through `UserDefaults` and include them in portable saves.
- Keep save/load/export services in core/AppKit wrappers.
- Show filename/timestamp result feedback.
- Add schema/process guard copy as visible confidence, but avoid turning it into a wall of text.

Implementation readiness: medium. Existing actions reduce risk.

### 08 Focused Term-Ended Summary

Current fit: strong partial. The app already builds a rich `NativeDebrief` and displays it in an overlay. The LLDD improves structure, hierarchy, and next actions.

Why it matters: the end of term is the emotional payoff. A sharper report modal can make loss/reappointment feel deserved and replayable.

Risks:

- The current overlay already covers most content; rewriting it too early is less valuable than improving policy decisions before term end.
- Replay same seed must reset correctly without polluting completed term/career history.
- Export summary should not resume or mutate the simulation.

Recommendation:

- Keep the overlay pattern but restyle into report sections.
- Add `Replay same seed`, `Start new career`, and `Export summary`.
- Add tests that debrief score/gates match board-watch/score calculations.
- Disable/ignore policy shortcuts while term modal is active.

Implementation readiness: high for visual report; medium for replay/export semantics.

## Cross-Cutting Architecture Recommendations

### 1. Add `TermSnapshot`

The LLDDs repeatedly assume a single snapshot event. Current SwiftUI recomputes multiple derived models separately from `session`. That is workable today, but route/mode redesign will benefit from a single stable projection.

Recommended core shape:

```swift
public struct TermSnapshot: Equatable, Sendable {
    public var session: GameSession
    public var boardWatch: BoardWatch
    public var briefing: CockpitBriefing
    public var decisionFeedback: DecisionFeedback
    public var chartInspection: ChartInspection?
    public var severity: SemanticState
    public var riskDrivers: [RiskDriver]
    public var latestMetrics: LatestMetrics
}
```

Do not duplicate authoritative state in `TermSnapshot`; treat it as a derived projection from `GameSession`.

### 2. Add Native Modes, Not Web Routes

Use `CockpitMode` rather than web-style `route` naming:

```swift
public enum CockpitMode: String, Codable, CaseIterable, Sendable {
    case overview
    case briefing
    case mandate
    case policy
    case preferences
    case history
}
```

The mode can map to a sidebar/rail visually, but should still feel like a command desk.

### 3. Keep Current Product Constraints

- Native macOS only.
- No Web/Tauri/server paths.
- No telemetry SDK or backend.
- Screenshot/computer-use validation for UI changes.
- XCUITest remains opt-in/final-gate only.
- Generated redesign images are reference only; do not copy them into the app as product assets.

### 4. Use Tests As Product Contracts

Add or update tests for:

- Snapshot derivation stays deterministic.
- Risk-driver ranking matches known states.
- Policy preview does not mutate session.
- Commit after preview matches existing engine behavior.
- Preferences persist and save/load validates schema before mutation.
- Term summary score/grade/gates match `ScoreState` and `BoardWatch`.
- Accessibility identifiers exist for each mode and primary action.

## Recommended Implementation Sequence

### Package A: Foundation And Policy Decision Center

Goal: convert the app from immediate action to deliberate policy choice without losing current gameplay.

Scope:

- `SemanticState` and small palette tokens.
- `TermSnapshot` projection.
- `PolicyPreview` model and tests.
- Pending policy selection state.
- Policy mode/center layout with Select -> Preview -> Commit/Clear.
- Keyboard updates: number selects, Return commits, Escape clears.

Success criteria:

- Preview appears before commit and does not mutate `GameSession`.
- Existing engine tests still pass.
- One screenshot-first GUI pass confirms the decision flow is understandable.

### Package B: Native Mode Shell And Hierarchy

Goal: establish the durable structure from LLDD 01/02.

Scope:

- `CockpitMode` state.
- Persistent top status rail.
- Native mode rail/sidebar.
- Overview layout preserving fast play.
- Severity banner and priority risk panel.
- Consequence/review strip.

Success criteria:

- User can reach all primary modes in one click from large-window layout.
- Policy decision remains reachable from Overview and Policy mode.
- No horizontal scrolling or major overlap at supported sizes.

### Package C: Mandate Focus And Briefing Mode

Goal: improve analysis and decision prep.

Scope:

- Mandate focus route with larger chart and current-value rail.
- Target labels and insight band.
- Briefing route with risk snapshot, policy implication, and handoff.
- CTA from Briefing to Policy mode.

Success criteria:

- Main risk driver and chart target gaps are readable within seconds.
- Latest values are accessible outside SpriteKit.
- Briefing updates after every quarter and never shows stale metrics.

### Package D: Preferences/Export And Term Report

Goal: finish commercial polish around persistence, exports, and end-state payoff.

Scope:

- Preferences/export route.
- `UserDefaults` preference hydration.
- Filename/timestamp feedback for save/export.
- Focused term-ended report modal.
- Replay same seed and export summary.

Success criteria:

- Preference changes persist after relaunch.
- Invalid save files do not mutate active state.
- End-term modal supports next action without ambiguity.

## Open Questions For The Next Turn

- Should mode selection be saved in portable saves, or should every load start in Overview?
- Should policy preview be a deterministic one-step simulation estimate or a simpler directional model derived from current gaps and lag pressure?
- Should the app keep one-click Commit for expert users behind a preference, or should all players use preview-first?
- Should the dedicated Preferences route replace the existing Settings dock panel entirely, or should the dock icon navigate to the route?
- Should History represent completed term summaries only, or also active career timeline/decision log?

## Final Recommendation

Proceed. The LLDD package is not perfect, but it identifies the right product-level weaknesses. The most valuable move is to build a native, snapshot-driven decision architecture rather than repainting the current cockpit. Start with policy preview and semantic state, because those improve both the game feel and every later design screen.
