# The Chair: next major upgrades

## Aim
A decision desk, not a wall of explanation. Make economic consequences visible,
make the controls easy to learn, and make later policy decisions worth making.
Ship coherent improvements with a matching app and private walkthrough.

## What is actually delivered

Baseline: Alpha 620, game source `a91d7dfc8ee2ac04e408285b20203a047711ebd2`.

| Feature | Delivered | Still needed |
|---|---|---|
| Policy cockpit | Compact metrics, contextual Help, keyboard controls, responsive containers, immediate wrapped tooltips | Intended-use review across compact and desktop sizes; cold-start learnability |
| Decision comparison | Graphical price/jobs/funding proposals, cached native paths, exact staging, cancel and stale guards | Clearer recognition of small or identical consequences; no claim that the interface creates economic depth |
| Economics | Negative-rate transmission, expectations/credibility, deferred demand, balance-sheet settlement, collateral-backed lending | Stronger later-career decisions supported by prospective experiments, not arbitrary extra volatility |
| Shocks and objectives | Fifty accepted event concepts, seeded careers, current dispatch, Mandate/Recovery objectives | Measure realized event cadence, persistence and decision relevance before tuning |
| Bank laboratories | Original workout and borrowing-cost lab; debt/equity distinction and diminishing negative-rate loan quote | Teach the ledger in a guided decision sequence; these labs remain separate from normal saves |
| Art and music | Original Blender city accepted at cockpit size; retained sources; local looping JRB-1 with persistent off switch | Preserve accepted city; assess remaining presentation only where a substantial visible gain is demonstrated |
| Delivery | Public Alpha 620, signed/notarized ARM64, installed app, public download page and owner-private interactive learning desk | Keep walkthrough and future native releases aligned with finalized mechanics |

Native tests establish specific behaviors, not human comprehension, empirical
forecast accuracy, sustained fun or whole-game visual acceptance. Existing
failures and rejected R0/C360/T412 hypotheses remain evidence; do not retune those
experiments retrospectively or reintroduce runtime AI.

## Release sequence

### 1. Private learning desk — delivered and frozen
The [owner-private learning desk](https://the-chair-walkthrough.jaymoney.chatgpt.site)
contains eight interactive lessons using actual native-engine conditional paths: committee,
rates/negative rates, guidance, portfolios/reserves, secured liquidity,
expectations/credibility, recovery and the priced bank workout. Each presents a
choice, a graphic, a short consequence and the matching native control sequence.
A logic atlas links the remaining finalized controls and scoring/save/music rules.

This is a **precomputed native-engine rehearsal**, not the browser game or an
arbitrary-policy simulator. No player saves, private accounts, model API, analytics
or fabricated outcomes. Source identity, units and conditional assumptions stay
inspectable. The walkthrough is owner-private; the existing public download page
stays public. Native game export to Web is a separate option, not a prerequisite.

The shipped desk covers 21 choices and 168 native forecast steps. Its consumer
comparison checked 3,867 numerical values with no nonzero differences; 18 signed
zero differences were explicitly classified. Offline data and UI checks passed
22 and 20 tests respectively. Actual browser checks covered all eight lessons
and keyboard navigation. This is not VoiceOver, universal viewport or human
comprehension acceptance. The native-entry correction now converts initial-GDP
offers to current-GDP control quotes using each lesson's decision state; the
existing outcome paths are unchanged. Full guidance/switch settings stay in
keyboard-accessible Details. Do not reopen accepted design for polish.

### 2. Make later decisions matter
Start from the retained cadence reconnaissance and known null depth findings.
The retained reconnaissance identifies 8–14-quarter normal-career event spacing,
with current-only previews and separate ambient disturbances. The registered
event-window diagnostic is complete: the first eligible named funding onset
was a Q12 normalization follow-up, retained rather than replaced after inspection.
A 2.4% initial-GDP lending offer cleared 0.7% initial-GDP unmet funding, but the
Q8 inflation/employment spans stayed below the fixed 0.10 pp macro screen.
This funding-only result does not rescue the prior null depth findings or justify
more frequent events.

The isolated fire-sale/credit prototype also failed its prospectively frozen
decision-value screen despite passing accounting and exact replay checks. Retain
the [failure and evidence](GAMEPLAY_DEPTH.md#alpha-620-later-event-sensitivity-and-fire-sale-screen);
do not adopt it as normal-career depth or tune thresholds after inspecting results.
The next mechanism must add central-bank decisions, not bank-treasurer busywork.

Compare at most three distinct mechanisms against an unchanged baseline. Register
material decision outcomes and failure criteria before running. Measure later
tradeoffs and policy-response differences, not merely higher volatility or lower
scores. Keep rejected variants. Promote only a demonstrated improvement; then
update workbook/model documentation and affected replay/accounting checks.

### 3. A cockpit that teaches through interaction
Use walkthrough observations to identify actual navigation and interpretation
failures. Prioritize graphic comparisons, causal outcome links and short inline
feedback over more text. Preserve full depth in details. Test keyboard-only
primary paths, focus recovery, narrow layouts and long/negative/large values.
Do not rewrite the engine merely to replace a screen.

### 4. A coherent visual world
Inventory runtime assets at their intended size and function before generating
replacements. Compare a small number of deliberate art directions. Preserve
originals and editable Blender sources; use Blender background CLI. Runtime art
must serve its intended function without implying a geographic or economic model.
The original city has now passed an independent intended-size review using the
installed Alpha 620 cockpit and six source renders across three angles and two
sizes. Retain it as a small illustrative identity, not a geographic or economic
state display. Source renders do not establish runtime FPS or source/export byte
parity. Keep accepted assets fixed. Generated concepts are not production assets, editable
Blender files or native-resolution masters until those outputs actually exist.

### 5. Deliver the actual upgrade
Batch related changes. Independently review correctness and intended-use quality,
inspect every GitHub review surface at the exact candidate, and honor required
checks. Reuse unchanged evidence; prefer bounded local checks over redundant
Actions. Match source, download, installed app, README and walkthrough. Preserve
rollback and saves. Nonblocking polish goes to a concrete backlog, not an endless
release hold. A preview is not whole-game completion.

## Acceptance and working method

Before a feature, fix its intended use, baseline, measurable outcomes and rubric.
Separate asset craft, UI task clarity, UX decision understanding, economic behavior
and delivery fidelity. The independent adversarial reviewer rates actual intended
use; the implementer receives concrete repair tasks, not private ratings.
Accepted feature identities are frozen; reopen only for a material regression or
changed requirement. Never round a failed rating into acceptance.

No test-count bonus, fabricated green status or claim that a screenshot proves
human enjoyment. Critical data loss, security, accounting, crash and primary-flow
failures block their affected release; minor cosmetics do not block an otherwise
qualified alpha. Keep PASS, FAIL, NOT RUN and unavailable evidence distinct.

## Completion
The new learning desk is live privately, primary native flows are understandable
and keyboard-usable, remaining major improvements have demonstrated benefits,
and the reviewed source matches the actual released game. One merged plan or
one graphical screen does not complete the game.
