# Economic model acceptance contract

Owner: parent rebuild task `01a0ed6e-3b18-7d13-b13b-dce7470f355d`.
Scope frozen before implementation on September 29, 2026. This contract governs
the reference simulation and formula workbook before integration into Godot.
The [baseline review](REBUILD_REVIEW.md) records why a replacement is needed.

## Value and authority

Players should be able to distinguish a demand problem, a supply problem and a
funding crisis, choose tools with different causal effects, and recover through
credible policy over time. The acceptance evidence is equilibrium, impulse,
stress and recovery tests plus a recalculating workbook. Attractive scenes,
bounded numbers and surviving unit tests alone do not establish this outcome.

Authorized: new source, tests, original assets, local builds and workbook,
global Blender/Godot installation, reviewed PRs and merges. Preserve the Swift
app, installed user career, unrelated files and credentials. No store release,
paid service, credential setup or signing-identity change is included.

## Required behavior

1. **Accounting and time:** track output and price levels so annualized growth
   and four-quarter inflation reconcile. A constant output gap grows at potential
   growth. A constant gap must not cause unemployment to drift indefinitely.
   Keep units and timing explicit, with no rounding in the simulation state.
2. **Equilibrium:** an economy at target with neutral policy and no shocks stays
   there for at least 240 quarters, within floating-point tolerance. No hidden
   drift, unexplained reset or protective clamp may conceal instability.
3. **Transmission:** an unanticipated rate increase changes financial conditions
   before its full activity/inflation effects. A paired impulse test must show
   delayed lower demand and inflation, with higher unemployment than the matched
   baseline. Preserve the lag state across appointment boundaries.
4. **Different shocks:** a positive demand disturbance initially raises activity
   and inflation pressure; an adverse supply disturbance raises inflation and
   weakens activity; a funding shock widens credit spreads and weakens activity.
   Policy cannot directly erase a supply disturbance.
5. **Different tools:** the rate controls short-rate conditions; guidance affects
   expected policy subject to credibility; asset purchases/runoff affect a
   separately visible balance-sheet stock and term premium; eligible liquidity
   lending reduces funding pressure without creating bank capital. Each tool
   needs a paired on/off test, constraints and an explanation of its limits.
6. **Expectations:** distinguish short- and long-horizon expectations. With the
   same temporary supply disturbance, anchored long expectations move less than
   short expectations; weaker credibility increases their sensitivity. Tests
   must reject instant, costless expectation repair by a token rate move.
7. **Credibility and support:** monetary credibility reflects demonstrated policy
   consistency, while public support responds to lived economic outcomes. Both
   have bounded, disclosed adjustment rules and recovery paths. Public support
   is an explicit game abstraction, not a measured approval forecast or legal
   dismissal threshold. Economic continuity never depends on resetting either.
8. **Recoverability and variety:** run the same benchmark policies through at
   least 1,000 reproducible seeds across demand, supply, funding and anchoring
   scenarios for 48 quarters. Report distributions, severe outcomes and causes,
   including failed recoveries. Select no coefficients solely to make one policy
   win. The laboratory permits every finite valid path to be inspected through
   its horizon; a game challenge may add an explicitly fictional failure rule.
9. **Validation:** reject missing, nonfinite or invalid policy inputs before
   mutating state. Seeded exogenous paths and committed policies fully reproduce
   the result. Candidate previews preserve the actual state and share shocks
   with the comparison path without revealing unknown future events to players.
10. **Workbook:** use one active scenario and one calculation chain. Expose policy
    paths, shocks, assumptions, intermediate equations and source classifications.
    Editable inputs update formulas and charts. Match reference outputs for all
    shipped cases and one-variable policy edits within `1e-7` where both engines
    use equivalent arithmetic. Scan all formulas for errors, test invalid inputs,
    render every sheet, recalculate from editable inputs, and validate the saved
    files against independent native model exports. Work directly on files;
    Excel, its add-in and sign-in are not required. Do not infer native-app
    behavior from file checks. Label unavailable engine checks explicitly.

## Evidence and interpretation

The Fed's framework provides the inflation objective and a variable, uncertain
employment concept. Published research informs signs, channels and plausible
timing. It does not identify this game's coefficients. Record each numerical
assumption, units, role and source status beside its workbook input. Parameter
changes require a before/after test receipt and the reason for the change.

The initial model is a transparent, research-informed reduced form. It will not
claim FRB/US equivalence, empirical confidence intervals, an optimal policy rule
or point forecasts. A future empirical fit would need identified data vintages,
sample, estimation method, held-out tests and uncertainty; none may be implied
by passing directional tests.

GDP annualization follows the level-ratio definition rather than an independently
tuned growth equation. [BEA, quarterly growth annualization](https://www.bea.gov/help/faq/122).
The inflation objective and employment distinction follow the
[2025 FOMC strategy](https://www.federalreserve.gov/monetarypolicy/monetary-policy-strategy-tools-and-communications-statement-on-longer-run-goals-monetary-policy-strategy-2025.htm).
The separation between short/long expectations and policy credibility follows
[Kugler, April 2, 2025](https://www.federalreserve.gov/newsevents/speech/kugler20250402a.htm).
Guidance requires understandable policy and follow-through, while preserving
data dependence. [Jefferson, May 13, 2024](https://www.federalreserve.gov/newsevents/speech/jefferson20240513a.htm).

## Gates and rollback

Write behavioral assertions before implementation and record the intended RED,
first GREEN, correctness/Ponytail review and final GREEN. Use bounded section
reviews under the user's current testing-runtime instructions. The parent owns
integration and live validation.
Do not merge a replacement engine solely because the workbook looks plausible.

Promote in order: reviewed baseline evidence, reference-model acceptance,
workbook parity and usability, then game integration and visual playtesting.
Production exports and signing are later release gates. The initial canary is
an isolated local workbook/game build, never the user's installed Swift career.

Rollback a failed change by reverting its isolated PR. Jared authorized complete
legacy frontend retirement: Godot is the sole maintained implementation and
retired Swift source remains recoverable from Git history. Preserve the installed
Swift app and all user saves; no migration or silent conversion is authorized.
Run heavy builds/renders serially and stop launches on unexplained memory or
swap growth. Check current disk headroom before large template archives or asset
bakes; defer them rather than removing unrelated user data.
