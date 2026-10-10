# Policy Lab economic core

This directory holds the clean-sheet Godot game and its deterministic economic
core, the sole maintained game implementation. The current build is a local
pre-release candidate. The installed Swift app and its saves remain separate;
its source and obsolete build paths are retired to Git history. Start with the
[research](../docs/FED_RESEARCH.md) and
[acceptance contract](../docs/MODEL_CONTRACT.md) for scope and evidence limits.

## Run and inspect

Use Godot 4.7.2 and run from the repository root:

```sh
godot --path game
scripts/test-game.sh
scripts/test-model.sh
scripts/test-model.sh --boundaries-only
scripts/test-model.sh --impulse-only
scripts/test-model.sh --price-only
reference=$(mktemp -d /tmp/fed-reference.XXXXXX)
godot --headless --log-file "$reference/engine.log" --path game \
  --script res://tests/export_reference.gd -- \
  --output "$reference/reference.json" --scenario supply_shock \
  --quarters 48 --seed 1 --policy feedback
```

Default macOS startup treats the1440×960 design as logical display size, fits
its decorated window uniformly to the usable screen, and uses native canvas
scaling. Explicit `--resolution` and `--position`, nondefault window sizes,
fullscreen/maximized and headless runs are preserved. Godot consumes native
window flags before exposing GDScript arguments, so this startup-only check
reads its own process command through the fixed system `/bin/ps` path. Failed
or blank reads preserve the original window. No lookup runs during gameplay,
and later user resizes do not trigger an automatic reset. Other platforms retain
engine startup geometry. No gameplay or font-size constants change.

The test wrapper rejects runtime errors even when Godot exits with status zero.
The fixed `-- --verify-build` entry point checks the bundled careers, replay,
scene and city, then firm and signed conditional guidance paths against
independent eight-quarter replays. It also builds the main comparison without
changing the career, controls or preview. CI and the macOS release verifier
require baseline, guidance and mandate completion markers; earlier output
cannot certify the new assessment. Release templates retain their restriction on
external script/path overrides.
The exporter requires an absolute destination outside this repository. Its
lexical path check is a guard against misplaced artifacts, not a sandbox for
untrusted paths or symlinks. The export contains parameters, starting state,
realized shocks, decisions and full quarterly states. Retain the realized shock
path when reproducing a run across engine versions.

## Regenerate the formula workbook

The repository owns the workbook builder, reference exporters and saved-file
checker. Use Godot 4.7.2 and managed Node/artifact-tool dependencies. In Codex,
`load_workspace_dependencies` supplies the Node executable and `node_modules`
directory. No npm install, repo-local dependency or game-runtime dependency is
needed. From the repository root:

```sh
python3 scripts/build-workbook.py /absolute/new/workbook-directory \
  --node /absolute/managed/node --modules /absolute/managed/node_modules
python3 scripts/tests/test-workbook-safety.py
```

The command refuses existing destinations and paths inside Git checkouts before
invoking tools. It creates an external execution copy of the source builder and
a link to managed dependencies. References, logs, previews and source hashes
stay beside the new workbook rather than entering Git. Failed builds are kept
for diagnosis; rerun with a new destination instead of replacing one.

Seven seed-1, 48-quarter careers, four one-variable policy edits, three price,
seven signed-rate and fifteen balance-sheet boundary traces come from the
current Godot equations. Balance fixtures cover natural/capped runoff, large
offers, full/partial sterilization, actual tagged maturity, loan refinancing,
reserve scarcity and nonzero initial output gaps. The single formula chain
checks every state and cohort, exercises input boundaries and causality,
exports four editable charts and renders all five sheets. Policy offers use
current meeting GDP; exogenous nominal shocks retain initial-GDP units so
policy edits cannot change the shared shock path. Original portfolio JSON bytes
and their hash bind every native export; the decoded snapshot alone is not an
exact decimal serialization of that source. These are hypothetical design assumptions,
not historically calibrated forecasts. Six additional full-state checkpoint fixtures
resume Q120–Q168, Q168–Q216 and Q216–Q240 for hold and responsive policies.
They preserve original GDP bases, price history, guidance and portfolio cohorts.
Each segment is saved before restoring the original calculation chain, then
checked against its own native reference. This is late-segment parity, not a
full 240-quarter workbook. Generating files does not prove native spreadsheet
usability or human playability.
Checkpoint summaries use only whole offsets within the available segment and
show `n.a.` for invalid selectors, including pasted values.

Authoring runs in three mandatory, serial phases: the main workbook, three hold
segments and three responsive segments. Each recreates the same formula chain;
completion requires every phase and all saved-file checks.

For a separately recalculated disposable copy, run the same saved-file checker:

```sh
python3 scripts/spreadsheet/check-workbook.py /absolute/recalculated.xlsx \
  --reference /absolute/new/workbook-directory/reference-v1/supply_shock.json \
  --map /absolute/new/workbook-directory/evidence/workbook-model-map.json
```

The checker reads the supplied workbook without editing it. It verifies all
quarterly state values for the default supply case, formula errors, chart
bindings and the absence of macros or external links. Native recalculation and
interactive GUI validation remain separate checks; the build does not launch
or change a spreadsheet application's windows.

Outcome and matched-policy change text distinguishes exact zero (`unchanged`)
from tiny increases or decreases with an explicit magnitude bound. For example,
a nonzero macro outcome below two-decimal precision says `down <0.005 pp`, not
`-0.00 pp`. Ordinary changes retain their signed precision and units. Outcomes
use two decimal places for percentage-point changes and one for score points;
comparisons use three and two respectively. Higher does not necessarily mean
better. These are presentation rules, not changes to the simulation.

`model/economy.gd` owns the equations. `parameters.json` records each parameter's
units and source classification; `scenarios.json` contains seven hypothetical
cases. Rates and inflation use percent units: 2 means 2 percent. Internal asset and loan
amounts use percent of **initial annual GDP**. The cockpit accepts offers in percent
of observed current annual nominal GDP and converts once before commitment. Flow
displays use meeting GDP; ending stocks use ending GDP. Output and price levels
start at index 100. The [portfolio and funding specification](../docs/BALANCE_SHEET.md)
owns principal, maturity, reserve and sterilization equations.

## Scenarios and background disturbances

Startup and New career default to Weakly anchored inflation: 4.5% inflation,
0.25 credibility and a rate below the expectations-adjusted neutral stance.
After initial stabilization, the same career adds three extended fictional
windows: demand with eligible funding, supply pressure with credit impairment,
and contraction with supply/funding pressure. These authored inputs are not
unchanged catalogue profiles or historically calibrated crisis incidence.
The baseline and one-off supply shock remain selectable practice laboratories.
Advancing without editing holds the prior rate; it does not apply the staff rule.

The opening regression retains 32 disclosed seeds through 96 quarters. A separate
late regression first recovers through Q120, then branches the exact same state
into passive and responsive policies. It measures inflation and employment costs,
misses in separate response windows, actual Q240 conditions and exact replay.
Its 96-quarter empty-shock tail is a model diagnostic beyond playable retirement,
not extra game turns. In the prospective 96-seed heldout experiment, passive play
missed the recovery bands at every career endpoint; responsive policy ended inside
those bands and reduced median combined diagnostic costs by 22.6%. No responsive
path was inside for all final eight playable quarters. These results establish a
policy-sensitive challenge, not optimal policy, human enjoyment or an empirical
welfare estimate. Equations, coefficients and initial conditions are unchanged.

This edition uses `user://career-late-compound-v1.save`. The earlier
`career-v1.save` slot remains untouched; Save and Load do not copy, migrate or
fall back to it. Payload version and scenario IDs remain unchanged. Scenario
inputs are fingerprinted, so earlier files require their matching prior app/model.

The equilibrium baseline starts at equilibrium and has no scheduled scenario
events. Every seeded career nevertheless receives quarterly background demand,
supply and neutral-rate disturbances, including the baseline. The generator adds
demand innovations in [-0.18, +0.18] percentage points, supply innovations in
[-0.04, +0.04] and transitory neutral-rate innovations in [-0.01, +0.01]. Funding stress also
receives small funding needs with eligible collateral. These are design choices.
Scheduled scenario events are added to that background path.

The optional Recurring crises (advanced) case draws from the reviewed top fifty
of [150 concrete concepts](../docs/EXOGENOUS_SHOCKS.md), including natural disasters,
energy/food disruptions, labor and productive-capacity changes, funding needs,
credit losses and favorable normalization. Forty-eight independent profiles use
a no-repeat bag and 12–20-quarter onset intervals. Two conditional bank-finance
follow-ups require qualifying prior stress and one quiet quarter after its end.
Every profile retains its authored one-to-four-quarter sign/timing sequence;
growth levels, haircuts and eligibility are not randomly rescaled. Separate
seed-derived generation precomputes the numeric path and event context at start,
without changing background randomness or the six earlier scenario paths.

Incidence and magnitude choices are fictional game design, not empirical crisis
frequencies. The shared seeded generator supplies the game, exports and workbook.
Current dispatch uses only the current entry in an accepted concept's
`phase_briefings`: its phase-local title and policy dilemma. Each authored phase
describes current or already observed signals, never a future pulse, remaining
duration or next episode. Research titles, mechanisms and full dilemmas remain
available for offline education, outside live dispatch. Previews use only the
disclosed current shock.
Private bank/deposit normalization is relief relative to continuing stress, not
an unconditional negative-risk impulse: old impairment and loan repayment remain.
The catalogue is fingerprinted; incompatible saves and altered context reject
without overwrite or silent migration. Saved realized inputs remain authoritative.
At start and restore, an independent seeded reconstruction supplies a private
immutable reference separate from mutable realized inputs. Event attribution
requires an exact match to that quarter's seeded reference, including its
background disturbances. Even a small audit edit within the general background
ranges suppresses the label; restoring the exact pulse restores attribution.

The dispatch also interprets markets, public hardship and funding as an offline
storyline. It reads only current information and completed history; replay
reconstructs the same text. Large disclosed needs begin or continue a funding
scare, followed by remaining credit impairment or loan repayment. The existing
0.1% initial-GDP display threshold separates major needs from small background
flows. These labels change no equations, scores, shocks or save fields. Public
forgiveness follows the modeled hardship memory, not a new political rule.

The same scenario and seed reproduce the path within the same engine and model.
Saved careers retain the realized path. The 240-quarter neutral equilibrium assertion instead
supplies explicit empty shocks; it does not promise a flat seeded career.
Forward comparisons use the current observed shock, then no new disturbances.
The separate formula workbook exposes realized seed-1 paths for audit and labels
their background shocks; it is not a forecast or the game's concealed future.

## Realized policy review

Every twelve completed meetings, the review compares your decisions with two
references from the same actual starting state and already realized shocks.
Hold keeps the starting rate. Staff applies the existing simple feedback rate
rule with matching data-dependent guidance. Both request no purchases or loans,
reinvest principal, maintain reserves and leave sterilization off. Neither is
an optimal-policy recommendation or a forecast.

The report shows separate average inflation distance from 2%, employment
shortfall and uncovered funding, plus ending credibility and public support.
Funding gaps use each meeting's nominal GDP; they are unmet need, not booked
bank losses. A failed staff reference leaves the actual/hold comparison usable
with its native error. No equations, scores, saved decisions or future inputs
change, and following staff is not itself a winning criterion.

## Mandate achievement

Completing 240 meetings is not itself successful policy. Mandate v1 evaluates
only the default weakly anchored inflation challenge with its canonical realized
shocks. Other laboratories and valid custom shock paths remain practice.

To achieve the mandate, finish Q240 with whole-career average inflation distance
from 2% at most 1 pp and average unemployment above its changing structural
reference at most 0.5 pp. Both latest-twelve-quarter averages must be at most
1 pp. Cover at least 95% of local funding supported by eligibility and
haircut-adjusted collateral. Funding coverage divides total recorded local
settlements by total coverable local flows in common initial-GDP units;
refinancing counts at each settlement, while aggregate reserve loans do not.
No eligible funding need is not applicable, not an earned funding award.

These are fictional game objectives, not welfare estimates or legal dismissal
rules. Early misses never end play. A persistent cockpit assessment reports
progress, identifies a limiting recent-period measure and warns after Q24 when
recent bands are missed. Reviews show whole-career and recent costs separately.
Unrounded values govern; a rounded equality cannot conceal a threshold miss.
Loaded careers recalculate under Mandate v1 without new save fields or migration.

The frozen prospective experiment retained 96 new default seeds: passive policy
met the criteria in 0/96 careers, the staff rate rule without lending in 0/96,
and that rule with currently disclosed eligible lending in 93/96. Three lending
paths missed the final inflation band and remain in the results. Six other
cases across eight seeds each were diagnostic practice paths. All 432 careers
completed their native 240-quarter paths. This supports reachability and
policy-sensitive objectives; it does not establish optimal policy or human fun.

## Quarterly order

1. Observe the previous state and choose a rate, conditional guidance, net asset
   flow and liquidity request. `step` receives realized exogenous inputs
   separately. It validates inputs and returns a new state without changing the
   supplied state. Benchmark policies cannot inspect future shocks.
2. Apply the full nominal rate on the quote grid. Age the Treasury/bill ladders,
   calculate financing-sensitive MBS paydown, and reinvest or allow principal
   runoff. Negative offers cap runoff at actual principal due; purchases have no
   invented ceiling. Prior short loans mature in full. Jointly settle eligible
   local/aggregate advances, reverse-repo absorption, currency conversion and
   optional reserve-maintenance bills. Principal assets and liabilities reconcile
   without resetting capital. The bounded duration-premium response and one
   nonlinear reserve-scarcity channel affect financing; lending cannot erase
   solvency risk. New funding and requested refinancing remain distinct.
3. Price nominal guidance according to prior credibility, then apply diminishing
   negative-rate transmission to the spot and priced guidance rates separately. Form short and long real-rate
   gaps, add the credit spread, subtract the neutral real rate and smooth the
   result into financial restraint. Output responds gradually to restraint and
   separately to demand and supply disturbances. Deferred durable/replacement
   spending adds a financing-dependent catch-up impulse. Transitory neutral-rate
   deviations decay around a separate structural reference; permanent reference
   shifts change that centre. Unemployment adjusts toward a
   bounded, gap-dependent target around an exogenous structural reference.
4. Inflation depends on prior inflation, prior short expectations, prior output
   pressure and current supply pressure. Compound the price index and calculate
   four-quarter inflation from five price levels. Actual output equals potential
   output times one plus the output gap; growth follows the level ratio.
5. Short expectations mix recent observed inflation with prior long expectations
   in proportion to credibility, then incorporate supply pressure.
   Long expectations gradually approach a credibility-weighted combination of
   the target and observed inflation. This is a reduced-form expectation rule.
6. Update credibility from inflation performance, stance adequacy and conditional
   follow-through, weighted 40/40/20. These weights and the policy reaction rule
   are game-design assumptions, not an estimated Federal Reserve objective.
   Conditional implied promises round to the same nominal quote grid before
   evaluating delivery; genuinely broken promises lose follow-through. Effective
   stance adequacy is distinct from this nominal accountability.
7. Calculate current hardship and its decaying memory. Public support closes
   25 percent of the distance to hardship-implied support each quarter. It can
   recover without a term reset and has no legal dismissal meaning. It never
   terminates the laboratory simulation.

The policy rate represents a target-range midpoint. The model does not let a
chair set the market's effective funds rate directly. Asset flows represent a
term-premium policy channel, excluding routine reserve-management purchases.
Liquidity eligibility is supplied externally and represents soundness and
collateral restrictions. Emergency lending authorities and bank recapitalization
are outside this model.

## Signed rate choices and effective stance

Nominal rate and guidance quotes use a 0.01-percentage-point grid (1bp), with
0.25-point arrow convenience. There is no nominal range or quarterly ramp cap.
Benchmark and conditional implied quotes round to nearest grid value, ties away
from zero. The pure engine rejects sub-grid requests before changing state.
Quote discretization is a game-design choice, not a U.S. legal restriction.
Physical positivity and finite-precision limits still apply to resulting paths.
The cockpit adds the effective rate beside a negative nominal choice; it omits
that duplicate when nonnegative transmission is unchanged. The comparison
retains effective-rate, financing and stance diagnostics for both paths.

Negative rates are a U.S. counterfactual. The effective borrowing-rate map is
`phi(i)=i` above zero and `s*tanh(i/s)` below zero, with illustrative `s=1pp`.
Its slope is continuous at zero and falls toward zero for deep negative cuts.
Prior credibility first prices nominal guidance as `i+C*(g-i)`; the map then
transforms spot and priced guidance separately before the existing long-yield
weighting. This is a reduced-form cash/deposit friction, not an estimated lower
bound or a model of reserves, bank margins or a universal reversal rate.
Retained research notes cite [Fischer](https://www.federalreserve.gov/newsevents/speech/fischer20160103a.htm),
[the FEDS policy-rate survey](https://www.federalreserve.gov/econres/feds/issues-regarding-the-use-of-the-policy-rate-tool.htm)
and [ECB evidence](https://www.ecb.europa.eu/press/economic-bulletin/articles/2020/html/ecb.ebart202003_02~4768be84e7.en.html)
for these directional limits, not the chosen scale or equation.

Desired current real restraint is `z=inflation_response*(prior_pi-target)+gap_response*prior_gap`,
without saturation. Actual spot restraint includes effective rates, prior
expectations, current term/credit conditions and the current neutral rate. Hold
other staged tools and the guidance quote fixed. The monotone current-rate
channel has an analytic negative-rate frontier; its upper limit is unbounded
unless the rate loading is exactly zero, when its feasible set is a point.
Credibility one makes priced guidance independent of the current rate.

Let `d` be actual distance to `z`, `d0` the shortfall at the relaxed continuous
transmission frontier, and `sigma` the existing positive stance tolerance.
The score is `exp(-max(0,d-d0)/sigma)*sigma/(sigma+d0)`. The frontier is a lower
bound on achievable distance, not a discrete 1bp optimum or a promise that a
finite nominal cut reaches the limiting effective rate. Remaining grid/finite
choice distance still reduces the score. An unattainable objective cannot earn
full adequacy even at constrained best effort. Identical effective financing
conditions receive identical stance scores; nominal promise follow-through
remains separate. Parameters, scoring weights and this frontier rule are
explicit design assumptions, not an optimal policy or measured reputation.

## Physical labor bounds

Unemployment is a percent of the labor force, from 0 to 100. Its structural
reference must remain strictly between those endpoints. The earlier linear
target could turn negative under prolonged inflationary expansion, rejecting
otherwise valid careers. The replacement uses a disclosed design target, not
an estimated labor equation. With structural reference `a`, output gap `g` and
local sensitivity `k`, the target is `a * exp(-k*g/a)` for nonnegative gaps and
`100 - (100-a) * exp(k*g/(100-a))` for negative gaps.

Both branches meet at `a` with local slope `-k`. They approach physical bounds
without clipping outcomes. The existing persistence blends the previous actual
unemployment rate toward this target. Structural-reference changes therefore
affect unemployment gradually rather than instantly rebasing it one-for-one.
Zero persistence reaches the target immediately; full persistence retains the
previous rate. Invalid reference shifts reject without changing the career.

This repairs the labor domain, not unstable inflation under unsuitable policy.
The labor-only repair left inflation, activity, expectations, credibility,
tool constraints and hardship formulas unchanged. Labor hardship and public
support can change because they depend on unemployment. Changed model
fingerprints reject incompatible saves without overwriting or silently migrating
them.

## Positive price and expectation factors

Annual inflation and expectations remain ordinary percentages, with a physical
lower bound strictly above -100. The earlier additive inflation rule crossed
that bound under valid 15% rate pegs late in the career. A separate valid supply
improvement could also push short expectations below -100 even while prices
remained positive. Both recurrences now blend positive gross price factors and
apply signed resource or supply pressure multiplicatively.

Define `G(x)=1+x/100`, `c=100+target=102`, persistence `rho`, recent-price
expectation weight `w`, and `d=k*prior_gap+s*current_supply`. The annual price
factor is `[rho*G(prior_pi)+(1-rho)*G(prior_short)]*exp(d/c)`. The short expected
factor is `[(1-w)*G(prior_short)+w*((1-a)*G(prior_four_quarter_pi)+a*G(prior_long))]*exp(s_short*current_supply/c)`.
Here `a=short_expectation_anchor_weight*prior_credibility`.
Prices compound the annual factor over four quarters; observed inflation still
comes from actual price-level ratios. Economy row 64 in the workbook shows the
annual gross factor, not a percentage.

The normalization preserves the 2% equilibrium and local price-pressure
sensitivities there; the hybrid expectation slopes follow their disclosed weights. With no forcing, arithmetic averaging and
equal off-target inputs remain fixed when all three inflation inputs agree.
Long-expectation anchoring and the financial-restraint lag are unchanged. Short
expectations now give credible prior long expectations an explicit influence. These nonlinear
forcing rules are disclosed design assumptions, not estimated Fed equations.
They preserve mathematical positivity without a floor or forced recovery;
floating-point overflow, underflow and representability remain numerical limits.
Model fingerprints change, so incompatible saves are refused without overwrite.

## Endogenous recovery channels

Deferred demand is a signed stock of postponed durable/replacement spending,
not all lost consumption. Positive stock supplies later catch-up demand;
negative stock represents purchases brought forward and later payback. A share
of underlying activity shortfall enters this stock even after supply or funding
pressure. That is an explicit reduced-form assumption, not measured household
inventory or destroyed productive capacity.

Let `x0` be activity before stock adjustment and rebase prior stock `b` into
current quarterly potential-output units: `available=b*prior_potential/new_potential`.
Release is `q=k*available`, activity is `x=x0+q`, and next stock is
`b_next=(1-cancellation)*available-deferred_share*x0-q`. Growth therefore changes
units without manufacturing purchases. Release and cancellation subtract once;
cancellation itself creates no spending.

The smooth fraction is
`k=(base+(maximum-base)*abs(available)/(backlog_scale+abs(available)))/(1+(max(financial_restraint,0)/financing_scale)^2)`.
Its design defaults are base .08, maximum .20, cancellation .02 and deferred
share .12; backlog and financing scales are 5% of quarterly potential output and
2 percentage points respectively. Large backlogs increase the release fraction;
restrictive financing delays it. Neither stock nor policy choice is clipped by
this mechanism. The maximum is a transmission fraction, not a policy-tool cap.

The neutral real rate has a separate structural reference. Its next value is
`new_reference+rho*(prior_r_star-prior_reference)+transitory_innovation`, with
`rho=.95`. The optional `r_star_reference_change_pct` input changes the reference
permanently; a transitory innovation decays. Initial scenario neutral rates set
their reference unless a separate initial reference is supplied.

Short expectations blend positive gross factors. Their recent-price component
mixes observed four-quarter inflation with prior long expectations at weight
`.5*prior_credibility`. Credibility zero remains fully adaptive. This channel is
gradual, preserves signed supply effects and does not reset inflation to target.

[FRBSF recovery analysis](https://www.frbsf.org/research-and-insights/publications/economic-letter/2010/05/shape-things-come-economic-recovery-recession/)
and [Fed durable-stock analysis](https://www.federalreserve.gov/feeds/the-unusual-composition-of-demand-during-the-pandemic-20210114.htm)
motivate postponed/replacement demand alongside financial headwinds. They do not
estimate these equations or coefficients. [Yellen's inflation analysis](https://www.federalreserve.gov/newsevents/speech/yellen20150924a.htm)
distinguishes anchoring from debt-deflation dynamics. All new numerical values
remain disclosed game-design assumptions.

Independent local analysis and real engine traces agree: a frozen low-credibility
neutral nominal peg can remain unstable; feasible feedback stabilizes small
perturbations locally. This is conditional stability around balanced growth,
not stability under arbitrary policy or a guaranteed return to 2%. Persistent
financial restraint can leave an off-target economy despite finite catch-up
spending. The recovery-only experiment retained the old tool constraints and
nominal stance score. The subsequent rate-transmission slice below changes
rate choices and stance accounting; balance-sheet constraints remain separate.

## What the tests establish

The suite checks 240-quarter neutral equilibrium, output/price accounting,
delayed rate effects, separate tool channels, conditional guidance, gradual
credibility and support changes, invalid-input rejection and reproducibility.
It also reports 1,000 seeds across four shock cases under two benchmark policies
for 48 quarters each. The sweep asserts numerical validity; recovery and severe
outcome counts remain visible rather than being forced to pass.

The unanchored-inflation case is a difficult benchmark. For that case, the suite reports 48-quarter recovery counts and separately
requires a seeded 96-quarter recovery path. These are difficulty and calibration diagnostics, not evidence about
optimal play or human performance.

A historical, pre-recovery-model lag experiment increased financial-restraint persistence from
0.55 to 0.85. A single 75-basis-point rate surprise then has its largest output
effect at quarter 4 instead of quarter 2, with peak output-gap effects of about
-0.018 and -0.035 percentage points respectively. This design choice places the
output response within the broad timing discussed in the research. It does not
fit an impulse response to data. In that earlier model, inflation was still
declining at quarter 240 under an unresponsive nominal-rate peg. That historical
result is not a trace of the current recovery equations.

The recovery-only slice at commit 14e7c5c ran matched 240-quarter engine paths with the same realized funding-stress shocks at
seeds 1, 417 and 2026. Early feedback reaches sustained terminal-window recovery
in all three baseline and revised runs. After 96 quarters of an 8% rate and
guidance, neither a zero-rate peg nor feedback meets that criterion in either
model. With late feedback, revised ending inflation is 0.43% to 1.47%, versus
-25.45% to -22.55% previously; cumulative hardship falls by about 78% to 80%.
Recovery means every one of the final sixteen quarters has inflation within
0.5 percentage points of target and absolute output gap below 0.5. A less severe
ending alone is not recovery. One-variable ablations retain these failed cases:
removing deferred spending or short-expectation anchoring worsens late outcomes,
while neutral-rate reversion does not improve every seed. No coefficient was
selected to make a benchmark win. These simulated paths do not establish global
stability or empirical calibration.

The subsequent signed-rate slice compares nonnegative and signed feedback with
the same current equations, parameters and 240-quarter funding-stress shocks at
seeds 1, 417 and 2026. Early feedback is identical and reaches sustained recovery
in both domains. After a shared 96-quarter 8% restrictive prefix, signed feedback
meets the final 16-quarter criterion in all three seeds; nonnegative feedback
does so in one. Signed ending inflation is 1.92% to 1.93%, with cumulative hardship
about 16% to 19% lower than the matched nonnegative path. The initial 8% choice now
applies fully, so this prefix is different from the earlier ramp-limited
experiment. These twelve simulated careers demonstrate this conditional
recovery channel, with no global or empirical stability claim.

The 2 percent inflation objective is source-defined. Other behavioral
coefficients, initial conditions, constraints, shock sizes and support scores
are disclosed design assumptions. This is an auditable research-informed game
model, with no FRB/US equivalence, empirical confidence interval or forecasting
claim. Workbook parity, playtesting and production exports remain separate
release gates.

## Playable career

Choose one of seven scenarios, inspect the current meeting dispatch and stage a
rate, guidance, asset-flow and lending decision. The preview uses the known
current shock, then assumes no new shocks and holds the rate and staged portfolio
switches for eight quarters. One-time offers do not repeat. Principal, loan
repayment and optional reserve maintenance still operate.
It cannot read the realized future shock path. The staff rate rule is a disclosed
benchmark rather than an optimal-play recommendation.

The staff rule rounds its requested rate and matching guidance to the 1bp quote
grid. Workbook blank guidance follows the same benchmark. Later data changes
the conditional implied promise, rounded to the same grid before delivery is
evaluated. Nominal promises are not forgiven because financing transmission is
weak; effective stance adequacy is a separate score.

Comparison and adoption stay in the bottom action bar while the cockpit scrolls.
Career status and the complete quarterly outcome also stay visible in that bar,
including credibility, public support and prior follow-through. Transmission lags
are explained in How to play and policy comparison, not repeated in each outcome.
Outcome score changes use points on the displayed 0–100 scales. Changes smaller
than 0.05 points show their direction and magnitude bound; exact zero says unchanged.
Expanding custom guidance keeps both actions available without hiding any policy
tool, unit, preview assumption or outcome from the scrollable content.
Both actions submit the field currently being edited, so a valid typed decision
does not require a separate Return keystroke. Native input bounds still apply.
New-career confirmation also submits the currently edited scenario seed.

Guidance can use the existing data-dependent preset, a firm pledge, or custom
responses to changes in four-quarter inflation and the output gap. Custom
responses range from -2 to +2 rate percentage points per 1 percentage-point
change since the announcement. They adjust the promise evaluated at the next
meeting, rather than granting an immediate credibility bonus. The comparison
shows the previous condition-adjusted promise, projected follow-through and
the current transmission frontier. Announcing a new path does not erase the previous promise.
Committed conditions survive adoption and lossless replay; a new career restores
the defaults. These quantitative conditions are game-design choices, not a
claim about the FOMC's current communication practice.

Choose **Compare policy paths** before adopting to inspect requested and applied
tools, current financial conditions and quarter-1, quarter-4 and quarter-8
differences from holding policy. The reference holds today's rate, uses
data-dependent guidance and requests no new asset flows or lending. Both paths
use the same current shock and no future innovations. The briefing also compares
credibility and public support and explains binding tool limits. Its Q+1
diagnostics expose inflation-miss memory, effective borrowing rates, desired real
restraint, actual stance distance and transmission-frontier shortfall,
prior-promise follow-through, current hardship and remembered hardship
for both paths. The stance rule and score weights are disclosed game assumptions,
not an optimal policy or a measured institutional reputation. The briefing does
not change the career or select a policy for the player.

Its report-only Guidance continuation section compares A, the selected-rate hold,
with B, following the implied nominal promise at later meetings and renewing the
originally chosen conditions. Both apply the identical current decision and
shock, then no future shocks; portfolio switches persist and future asset/lending
offers are zero. Q+2 pairs nominal/effective rates, follow-through and stance
adequacy. Q+8 shows B outcomes and B-minus-A changes in inflation, unemployment,
output gap, credibility and support. Fulfilling a nominal promise need not improve
effective stance or credibility. Unavailable B paths retain their native error
without replacing the valid report. Continuation beyond Q240 is diagnostic, not
extra playable turns. The cockpit preview and player decisions stay unchanged.

Four one-control contrasts also show how the staged rate, guidance quote, asset
flow and lending differ from changing only that input. The rate alternative
requests today's rate; the guidance alternative quotes the selected applied rate
while retaining the staged conditions; the other alternatives request zero new
flow or loans. Q+1 yield/spread and Q+8 inflation, employment, credibility and
support differences come from the same model forecasts. They are conditional,
nonadditive contrasts, including legitimate zero effects for unused or constrained
tools, rather than an attribution of measured U.S. policy effects.
The persistent section chooser jumps directly to Meeting, Deliberation, Guidance,
Guidance continuation, Scores, Forecasts, Tools and Limits within the complete
report. Native text selection and keyboard scrolling keep its calculations,
explanations and warnings available.

After adoption, funding feedback reports applied loans, uncovered need and repaid
principal as percentages of that meeting's GDP. These are realized flows, not the
next preview or ending loan stock.

Careers continue through 12-quarter reviews without resetting policy lags,
expectations, hardship memory or charts. The local career limit is 240 quarters.
Data & journal also opens a realized review on demand after any completed
decision, including after loading a career. It compares the latest up to twelve
completed quarters and labels the actual interval. Each review compares realized
average inflation distance and unemployment above
the structural reference, plus ending credibility and support, against holding
the period's initial rate. Both paths begin at the same state and use the same
already-realized shocks. This hindsight comparison is not the forward preview
or an optimal-policy score; it makes the period's tradeoffs inspectable.
Save and Load use separate `FedChairmanPolicyLab` user storage and never touch the
Swift game's saves. Native-value serialization preserves floating-point inputs
exactly; loading validates every shock and replays decisions in isolation before
replacing the active state. Model-version mismatches are refused rather than
silently migrated. Save is a single explicit slot, replaced only when selected.

Native app quit/close compares the adopted career with the last successful New,
Save or Load. Changed careers open a Cancel-first "Quit without saving"
confirmation; Cancel, Escape or closing that dialog returns to play with pending
policy edits intact. Fresh/unchanged careers exit directly. Quitting never saves.

The original city is authored by `art/build_city.py`; its editable `.blend` source
is retained beside the script. The game loads `assets/policy_city.glb`, so players
and CI do not need Blender. Art source is excluded from runtime imports. Animation
is off by default, controls expose accessibility labels, and the journal supplies
exact chart values. Engine and component notices are available under Credits.

The static city uses a native one-shot render, refreshed after viewport size or
visibility changes. Enabling animation restores continuous rendering; disabling
it retains the final orientation. Camera framing and four-sample antialiasing
are unchanged. This reduces redundant rendering, not economic simulation work.
The city is presented through a native TextureRect and SubViewportTexture at
uniform physical canvas density. Ordinary sampling stays between 1x and 2x;
the largest texture dimension is capped at 2048, with uniform downsampling for
oversized areas. Logical layout, camera, materials, MSAA4 and ignored mouse
input remain unchanged. Control/window size notifications update the texture;
no per-turn sizing, GPU readback or background service is required.


## Offline policy deliberation

The comparison report includes a Deliberation section. It shows your selected
path, nearby tighter and gentler applied rates, and rate continuity while keeping
all other staged tools and the new guidance quote unchanged. Nearby choices use
the existing 0.25-point arrow convenience, without a nominal rate or ramp cap.
Unavailable numerical paths remain explicit rather than being silently clipped.
Each path uses the disclosed current shock, then no future shocks and its own
applied-rate hold. The report shows actual Q+8 inflation, unemployment, credibility
and public support without choosing a winner or changing your staged decision.

These are fictional viewpoints, not actual officials, votes or policy advice.
The [Board's FOMC overview](https://www.federalreserve.gov/monetarypolicy/fomc.htm)
describes committee assessment of economic conditions, policy options and risks;
it supplies no calibrated disagreement or voting coefficients for this game.
Quarterly turns aggregate time rather than reproduce the real eight regularly
scheduled annual meetings. No AI, connector or network call runs during play.

## Apple Silicon release

The shipping target is Apple Silicon (ARM64), not Intel. Godot's official 4.7.2
macOS template is universal; the `macOS universal staging` preset is an
intermediate, not a distributable release. The packager removes the Intel slice
with Apple's `lipo`, then signs the ARM64 application with the supplied Developer
ID identity. No custom engine or export template is needed. This follows the
[Godot architecture contract](https://docs.godotengine.org/en/4.7/classes/class_editorexportplatformmacos.html#class-editorexportplatformmacos-property-binary-format-architecture).

Install that official template, then run from the repository root on macOS:

```sh
scripts/package-game.sh "$HOME/.cache/fed-chairman-builds/NEW_RELEASE" \
  'Developer ID Application: YOUR NAME (TEAM_ID)' TEAM_ID
```

The destination must not exist. The script retains the app, export log,
verification log and ZIP. It checks ARM64-only native code, Developer ID team,
hardened runtime, secure timestamp and strict bundle integrity before packaging.
Signing uses the existing Keychain identity; no credentials belong in this repo.
Apple notarization and store publication are separate actions. A Developer ID
signature alone does not establish notarization or Gatekeeper acceptance.

Stage unpacked apps outside cloud-synced folders: a File Provider may attach
Finder metadata that invalidates strict bundle verification. Do not strip
quarantine or weaken Gatekeeper. Plaintext scripts remain included so the model
is inspectable and save fingerprints survive export.

The actual release executable's `--headless -- --verify-build` entry point runs
235 bundled checks:164 resource, career and replay checks,59 guidance
continuation/comparison checks and12 mandate assessment/replay checks, without external scripts or path overrides.
The release verifier also runs that self-check. Linux CI validates
source behavior; it does not build or distribute an Intel Mac game. Intel
hardware testing is not a release gate for this ARM64-only product.
