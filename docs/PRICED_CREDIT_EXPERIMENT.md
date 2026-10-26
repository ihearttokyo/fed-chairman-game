# Priced-credit experiment — optional mode released in Alpha618

**Current status — 2026-10-26:** merged at `356abf5` (PR #140) and released
in Alpha618. New career → **Bank workout · borrowing costs** enables optional,
explicitly collectible-credit accounting in the native bank and macro transition.
The original Bank workout remains zero-interest; neither laboratory uses normal
career save slots or awards. The normal-save compatibility evidence is below.

The historical sections retain rejected and unexposed milestones recorded by
2026-10-26, before release. Their holds and unfinished gates describe those stages,
not the current release; individual milestone dates were not separately recorded.

## Candidate A (historical pre-release, recorded by 2026-10-26)

An external context supplies annual APR, whole days, separate payable/receivable
claims, collectibility and negative-rate opt-in. Accrual uses opening principal,
APR and days/365, without compounding. Securities mature, principal is repaid or
renewed, interest uses remaining cash, then withdrawals and fresh advances settle.
Unpaid interest stays separate. Negative APR is a US counterfactual.

The existing Fed ledger tracks principal assets. Unpaid interest is an explicit
sidecar: combined Fed capital adds net accrued claims to core capital. Cash
settlement moves reserves and core capital oppositely without earning income
twice. Combined bank equity includes both interest claims. Active status flags
include unpaid due interest and combined equity, but do not determine regulatory
capital, credit eligibility or impairment. Default calls retain their original
schemas and arithmetic.

The APR-to-policy mapping, illustrative quarterly day schedule and payment
priority are authored assumptions, not exact US discount-window terms or statutory
insolvency priority. External collectibility is a boundary, not an estimated CECL
or nonaccrual model. Unsupported noncollectible inputs refuse atomically.

## Evidence and decision (historical pre-release, recorded by 2026-10-26)

Native tests passed 126 checks after independent review found two active-context
status errors. The final paired study passed 3,017 checks across 64 frozen-policy
cases, including held-out seeds and bank tapes. Default complete frames matched
the original source; zero-APR contexts preserved legacy fields. Nine genuine
Q240 normal-career histories also matched exactly through manual replay. This
does not qualify old-header loading.

All 64 pairs retained identical inflation-distance, employment-shortfall, ending
withdrawal-queue and principal-arrears metrics. Eight negative-APR cases transferred
cash to banks; ten positive-cost cases paid interest only in the held-out maturity
variant. These are cash/accounting effects, not pooled evidence of better gameplay.
**Historical decision: hold adoption of A.** Full receipts and rejected harness versions remain outside Git.

The next hypothesis is funding completeness: allow an explicitly offered,
collateral-supported cash advance to settle interest due, rather than allocating
fresh credit only to withdrawal shortages. This must show actual cash legs and
retain unpaid claims when financing is unavailable. It is not automatic interest
capitalization. All previously observed cases become development cases for that
revision; new held-out cases must be frozen before testing.

## Revision B: actual debt-service financing (historical pre-release, recorded by 2026-10-26)

An optional `finance_interest=true` context allows actual collateral/offer-backed
cash advances for interest due, before deposit payments. Existing principal still
uses headroom first. The result separates fresh cash for interest and withdrawals;
unpaid interest enters funding pressure once. Reverse interest is a real cash
receipt, not automatic setoff. Unpaid claims do not compound, but genuinely
advanced principal—including financed debt service—accrues next period's interest.
No rate, spread, loan ceiling, coefficient, horizon or scoring weight was tuned.

The first development run rejected nine valid paths. Fully funded fractional
purposes had been reconstructed by subtracting interest from a gross advance,
creating a tiny surplus withdrawal advance/cash asset. The repair books original
validated purpose legs and audits actual gross receipt/remittance at the advance's
scale, disclosing roundoff rather than forgiving claims. Both 0.1/0.2 and
1.98/0.1 regressions pass; earlier failed reports remain retained.

After that repair, 64 development cases passed 4,361 checks and 32 independently
frozen held-out cases passed 2,181 checks, with zero refused paths. Legacy full
frames and zero-APR legacy fields matched independently of priced-arm success.
The A suite, nine original Q240 manual histories and the unchanged controller's
867 checks also passed. At this stage, a new playable UI was not yet qualified.

The exact composite source digest admits the prior Alpha616/617 header for the
same nine explicit normal scenarios. Genuine Q240 saves restored byte-identically
in 71 checks, including unchanged original files, current new-encoding headers and
future/unknown/laboratory rejection. Prior Alpha615 and Alpha614 fixtures also
passed their existing 60- and 98-check restore suites. The older eight-only bridge
stays eight-only. No fixture/header rewrite or automatic save migration occurred;
future model-source edits close these bridges until qualified again.

Positive-cost cases changed average unpaid withdrawals in 20/40 development
paths and 16/20 held-out paths. Held-out ending queues differed by up to 0.3715%
of initial GDP. Macro inflation/employment effects were much smaller (below
0.001 percentage point), not evidence of dramatically harder macro gameplay.
Negative-APR transfers and zero/no-borrowing controls are reported separately.
These are bounded cash-flow results, not an optimal-policy, empirical calibration
or enjoyment claim. B was unshipped at this milestone; its later player-facing
integration and release are documented below and in the current status above.

[Discount Window general information](https://www.frbdiscountwindow.org/Pages/General-Information/The-Discount-Window)
supports the accrual/claim distinction. [Primary-credit program guidance](https://www.frbdiscountwindow.org/pages/general-information/primary-and-secondary-credit-programs)
allows broad uses, subject to eligibility and collateral; it does not establish
this experiment's payment priority. [FAM Chapter 8](https://www.federalreserve.gov/aboutthefed/chapter-8-special-topics.htm)
requires separate attention to expected loss and collectibility. No empirical,
full-Fed-accounting or enjoyment claim follows from these tests.

## Controller qualification and original minimum-loan failure (historical pre-release, recorded by 2026-10-26)

Before the numeric repair, the unexposed controller passed 250 native checks: synchronized ledgers,
byte-pure previews, first-step preview/adoption equality, both interest signs,
eight-meeting termination and refusal of normal career storage. Held-rate quotes
are explicitly labelled separately from staged rates. Today's nonfunding shocks
are copied directly into preview/adoption; a failed presentation quote cannot
silently remove them. A fault-injected quote failure was RED before that fix.

**Historical status: unexposed, not ready to ship.** A subsequent real-input diagnostic
found a normal, not extreme, precision failure. Borrow 0.0001% of initial GDP at
the first meeting, then hold either +4% or -4%. At the next security maturity,
interest settlement was refused by transaction-relative floating-point guards.
The original desired quote/advance checks failed for both signs; the existing passing
cohort did not cover this minimum-size combination. Its results do not establish
universal input coverage or readiness.

`minimum_loan_diagnostic.gd` preserves the desired-success assertions as a
research diagnostic. The failing receipt is retained; the same desired-success
assertions now also run in the default controller suite after the repair below.
The original reproducer recorded six failed desired-success checks out of ten.
The first attempted stock-only rounding allowance still failed combined-equity
reconciliation and was withdrawn. The final repair below separately audits
cash/deposit/core-capital representation errors while retaining strict contractual
claims/principal and anti-erasure safeguards.
Do not book unexplained residuals as income, forgive claims, or ship a stuck turn.

Run the reproducer in an isolated HOME with the same native Godot command used
by `scripts/test-game.sh`, using the absolute script path under
`scripts/research/loan_interest/minimum_loan_diagnostic.gd`. A future nonzero exit is a
regression, not a qualification pass.

The pre-repair default headless game suite completed successfully (54 PASS markers,
including storage checks and relaunch/atomic-preference fixtures). This is native
headless regression evidence, not visual usability acceptance. No GUI, installed
app, release asset or user save was changed. That cohort did not establish
minimum-loan coverage; the separate RED diagnostic identified the missing case.

## Stock-booking repair (historical pre-release, recorded by 2026-10-26)

The cause was numerical, not an economic constraint: a normal cash movement was
being held to interest-claim-relative accuracy even after larger maturity,
principal and depositor transactions rounded their own stocks. A first cash-only
allowance was rejected because it did not audit the other stock movements.

The repair keeps contractual claim/principal fidelity unchanged. Cash and deposit
bookings carry signed residual components, computed with finite floating-point
expansions. Each stock booking must satisfy all three limits: a local binary64
operation-error bound, an absolute 1e-12% initial-GDP ceiling, and 1ppm of the actual
flow. A nonzero flow cannot disappear into an unchanged stock. Principal booking
retains its stricter existing 1e-12 transaction-relative guard. Residuals are never
income, capital injections, claim reductions or cash available for payment.

Combined bank-equity reconciliation explicitly removes measured cash residuals
and adds liability residuals before checking accrued income. Fed reconciliation
removes only measured core-capital rounding; reserve rounding is separately
reported. Gross receipt/remittance residuals are process diagnostics, not counted
again in the final purpose-booked cash bridge. Independent review caught another
ordinary small advance into cash of 50% of initial GDP; it was native RED before the
same stock-only repair, with principal fidelity retained.

The genuine minimum-loan quote, preview and actual checks now pass for both signs
(12 checks). Controller coverage is 262 checks; the original A suite passes 126
and expanded B suite 148. The stock audit passes 85 checks, including 24 binary64
goldens independently verified using Python exact-rational arithmetic, huge-stock
and erased-flow refusals, and multi-component cancellation. Goldens use binary
bytes to avoid cross-language decimal-literal parsing differences; this does not
claim correct rounding of every decimal parser. The accompanying Python verifier
can be run with `python3 -B scripts/tests/test-priced-stock-goldens.py`.

The expansion approach tracks otherwise lost partial sums; see [Python's fsum
accuracy discussion](https://docs.python.org/3/library/math.html#math.fsum).
This implementation refuses nonfinite intermediates and does not claim universal
support for every finite extreme, arbitrary-precision money or decimal accounting.

The frozen 64-development and 32-held-out cohort regressions again passed 4,361
and 2,181 checks with no refused paths after this repair. These are reruns of
previously frozen cases, not new independent gameplay discoveries. Normal nine-
scenario Q240 histories again replay byte-identically. Native regression and
numeric correctness do not establish enjoyment or visual usability. The later player-facing integration and native Computer Use are documented below;
release qualification was still unfinished at that milestone.

Final-source verification: the default native headless suite passed with 55 PASS
markers, including the 262-check controller and 85-check stock suite. Original
Alpha616/617, Alpha615 and Alpha614 saves passed the 71-, 60- and 98-check loader
compatibility suites. The exact composite source pin was advanced only after the
nine Q240 manual histories matched; unknown headers, future source drift and
laboratory saves still fail closed. No original save was rewritten. Independent
correctness and test/evidence reviews found and closed the gross-cash and stale-
documentation issues; they did not substitute static review for native execution.

## Player-facing integration (historical pre-release qualification, recorded by 2026-10-26)

Main now offers the priced variant separately from the original lab. A compact
cash-flow panel keeps first-staged terms apart from the last actual settlement;
it never nets opposite payments or reads future forecast entries. Failed previews
clear staged data. The debrief and journal use combined model equity, not the
principal-only book. Private native checks pass 206 component, 25 Main-wiring and
206 debrief checks; the original lab's 33 integration checks also pass. Review
caught missing Main value-binding assertions; those now verify rates/day counts,
actual versus staged payments/claims/purposes, and adoption-only actual updates.

Two source-bound native Computer Use episodes completed eight real decisions
each. The first exercised a small loan, reverse-interest payment and later unpaid
positive interest. The second used keyboard-only scenario selection, seed entry,
policy editing and adoption. F1/Escape and focused-cockpit Home/End worked. An
initial warning-color/empty-row issue was repaired and rechecked against new
source hashes. Both task-owned instances exited normally; original save and audio
preference hashes were unchanged. Current-size captures remain outside Git.

The full default headless suite passed with 57 PASS markers, including all current
priced component/controller/integration tests. These results do not qualify every
possible window size, actual VoiceOver use, a second Mac, measured difficulty or
human enjoyment. At this pre-release milestone, ARM64 export, matching packaged-runtime
checks, reviewed PR publication/merge and release were separate unfinished delivery
work. The mode subsequently merged and shipped as recorded in the current status above.

The final source also passed the full macro model suite and the current curated
career diagnostic: 1,100 completed careers, 264,000 transitions, 100 paired
comparisons, all 50 curated events observed and zero diagnostic failures. This
normal-career regression is separate from the 96 priced-bank cases and does not
establish human difficulty or optimality of the feedback reference.

## Uncapped negative-APR counterfactual — 2026-10-26 diagnostic

One installed Godot 4.7.2 headless process, with private temporary HOME and a
90-second limit, ran two matched seed-1 episodes through the actual priced
controller. Q1 used rate/guidance 8% and a 2.4% current-GDP liquidity offer
(equal to initial-GDP units at opening). Q2 used −10% versus −1000%, with no
offer; Q3 returned both to 8%, still with no offer. Guidance matched each chosen
rate with default data-dependent sensitivities; reinvestment and ample reserves
were on, sterilization off, asset offers zero. This is an explicitly staged
policy assumption, not a claim that changing the rate field also changes guidance.
Q1 encoded ledgers and Q2 observed briefings matched byte-for-byte. Neither
choice used future information; the results below are realized, not forecasts.

Amounts below are percent of **initial annual GDP**; equity includes separate
interest claims. Figures are rounded only for display.

| Actual result | Q2: −10% | Q2: −1000% | Q3 after −10% | Q3 after −1000% |
| --- | ---: | ---: | ---: | ---: |
| Negative interest accrued and paid to bank | 0.059836 | 5.983562 | 0 | 0 |
| Positive interest accrued | 0 | 0 | 0.037909 | 0.037909 |
| Positive interest paid | 0 | 0 | 0 | 0.037909 |
| Closing bank cash | 0 | 5.883562 | 0 | 3.865653 |
| Closing combined bank equity | 1.469573 | 7.393299 | 0.454523 | 6.378249 |
| Closing loan principal / overdue principal | 1.880000 | 1.880000 | 1.880000 | 0 |
| Closing unpaid interest | 0 | 0 | 0.037909 | 0 |
| Closing withdrawal queue | 0.040164 | 0 | 0.140164 | 0 |
| Macro uncovered funding (principal, queue and interest) | 1.920164 | 1.880000 | 2.058073 | 0 |

Q1 advanced and paid withdrawals of 2.4, with zero closing cash and no interest
on its zero opening principal. Q2's 0.52 security maturity repaid principal
before reverse interest arrived: both branches therefore retained 1.88 overdue
principal that meeting despite the larger subsidy. Q3's larger-subsidy branch
then repaid that 1.88 from cash, paid interest and paid 0.1 of withdrawals; the
other branch paid none of those cash legs. No fresh advance or renewal occurred
in Q2 or Q3. Q3 core Fed capital was −0.059836 versus −5.945653: the bank's
transfer income has a central-bank cost, not free aggregate wealth.

The source accrues `opening_principal * abs(APR)/100 * days/365`: Q2 uses 91 days,
so −1000% pays exactly 100 times −10%. Negative APR therefore provides an
**uncapped linear bank subsidy** for fixed principal/days, subject to finite
representation and existing validity guards. Macro rate transmission instead
saturates at `s*tanh(i/s)`, with `s=1pp`: Q2 effective rates were
−0.999999995878% and −1%. Funding relief still changes credit spreads, so this
does not make the complete macro paths identical.

Q2 four-quarter inflation was 6.794678% in both branches. At Q3, −10% versus
−1000% histories produced inflation 6.671826913% versus 6.671829938%, unemployment
5.545624790% versus 5.544661600%, and output gaps −0.918481323% versus −0.910846941%.
Credibility was 0.285375735 versus 0.285375188; support 59.270028507 versus
59.270658278. Thus the large cash/equity gain did not proportionately improve
macro outcomes; inflation remained well above 2%, and credibility was slightly
lower. This bounded accounting counterfactual establishes no overall policy win,
optimality, empirical Fed behavior or human enjoyment. No coefficients, rate caps
or model version changed.

All six adoptions completed and 20 diagnostic checks passed, but the engine also
logged a macOS system-CA-certificate error on exit. This is diagnostic execution
evidence, **not a clean regression-suite pass** under the wrapper's error policy.
Script, source hashes, JSON results and logs remain outside Git in temporary
evidence. NOT RUN: computer-use GUI validation (headless accounting diagnostic
only; no UI changes or usability claim). No user saves or GUI were accessed.
