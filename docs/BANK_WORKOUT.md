# Bank-workout episode

The optional eight-meeting laboratory is connected in current source. Choose
New career → Bank workout. The laboratory shipped in Alpha 615; Alpha 616 adds
the lending allocation preview and repairs fractional refinancing.

After eight meetings, the current source shows a payment timeline and ending
queued withdrawals, overdue CB principal and signed equity. Each bar is paid/due
for that meeting, not an amount on a shared scale. A dash means no payment due;
gold marks even a tiny shortfall. Queued claims recur until paid, so the chart
does not add repeated queues into a fictitious total. Ending claims remain
subsets of deposits and CB principal; payment coverage is not a solvency grade.
The debrief is read-only and clears when leaving the laboratory.

## Mechanism

Dated securities mature into cash once and leave collateral. Market-value losses
remain distinct from unpaid claims. Cash first repays existing CB principal;
accepted renewal moves no cash. Fresh advances use only headroom after all old
exposure, including overdue principal. Unpaid withdrawals remain a subset of
deposits; overdue CB principal remains a subset of the loan. Neither is added as
a second liability or silently forgiven. Financial distress does not stop the
bank calendar. Lending cannot create mark-to-market equity.

This exercise currently assumes zero contractual loan interest and an automatic
cash-first payment waterfall. Both are authored teaching assumptions, not actual
discount-window pricing or statutory insolvency priority. The flat semiannual
yield proxy is not an estimated term structure. These limits must remain visible
in the playable episode's Details.

`Economy.bank_workout_step` reports actual cash repayment, renewal, fresh cash,
paid withdrawals, retained claims and signed equity. Its evaluation reference is
formed before repricing, not from reduced collateral. An unrepresentable compound
reference retains its original legs and an explicit unavailable flag; it cannot
be presented as a perfect funding score.

The panel separately labels depositor payments, CB arrears and mark-to-market
equity. No payments due is n.a.; partial payments do not snap to full coverage.
Tiny amounts and near-threshold shortfalls remain distinguishable. It performs
no forecasting, settlement, saving or regulatory-capital calculation.

## Compatibility evidence

The public four-argument economic step now delegates to an internal step with
an optional workout context. Normal careers take the unchanged default ledger
branch; workout calls supply actual repayment, renewal, advances and retained
debt. Source-integrity hashing still changes the model digest. The compatibility
bridge admits the previous current digest only for nine explicit existing
scenarios and preserves the older eight-only whitelist. Both bridges require
the exact newly qualified source digest and reject future drift. Unknown/lab
headers are not admitted. The digest algorithm is not filtered.

Before implementation, genuine seed-417 feedback-policy Q240 payloads and complete
state/history/decision/shock bytes were generated for all nine scenarios. The
new implementation replays every byte identically in the retained fixtures;
loading never rewrites them. Explicit new encoding uses the new header. This is
selected-path compatibility evidence, not a universal numerical-parity proof.

Native checks cover the accounting component (119), presentation (149), coupled
transition (276), authored opening (112), controller (867, including 32 varied
eight-turn policy paths), Main integration (28) and original-career compatibility
(98). Independent review and native regressions caught two actual freeze cases:
a rounded final withdrawal mismatch and a negative residual in the ordinary
ledger used for a provisional quote. The final wave now requests actual
unrequested deposits; the quote uses the same persistent-claim ledger as the
accepted frame. Strict claim validation and default equations remain intact.
Captures, original fixtures and detailed receipts remain outside Git.

## Coupled episode integration

The optional transition couples the bank calendar to the Fed's actual loan and
reserve ledger. Cash repayments reduce reserves; cashless renewal does not.
Unpaid principal remains on both balance sheets. Existing funding-spread
coefficients are unchanged. The one-bank exercise cannot reuse its collateral
for an additional aggregate borrower. A detached provisional frame determines
the discount quote; the final frame must produce exactly the same quote or the
transition is refused. No numerical fixed-point iteration conceals circularity.

The in-memory eight-quarter controller advances both histories atomically. Its
previews carry maturities, arrears and queued withdrawals, but never read future
withdrawal requests. Diagnostic paths beyond the playable eighth quarter are
explicitly marked. Current funding briefings use the actual bank, not inherited
scenario funding amounts. Laboratory payloads cannot read or write normal
career slots or earn normal career awards. Historical benchmark comparisons are
explicitly unavailable until their coupled replay is implemented.

The authored opening holds 2.7% initial-GDP deposits against a .52/.55/2.97
face-value ladder due at Q2/Q5/Q20, with a 4% haircut and five-sixths
pledgeability. The request waves culminate in all remaining unrequested
depositors; this is not a tolerance that erases old queued claims. These are
optional design assumptions, not an estimated bank.

Main now exposes the eight-meeting laboratory in New career, with the separate
bank ledger, compact current conditions and a dedicated Help topic. Source-native
qualification includes background Computer Use: partial lending, renewal, retained
arrears, a negative-rate decision, chart inspection, Return/Escape dismissal and
focus restoration. Bank and policy panels remain side by side at1050 logical
points, with locally stacked charts; narrower windows use the existing stacked
cockpit. All native instances used private storage and were verified exited.
Captures and exact source hashes are retained outside Git. These checks do not qualify
new difficulty, enjoyment, empirical calibration, workbook integration or
release readiness on their own. The laboratory subsequently shipped in Alpha 615;
release and notarization evidence remains separate from source-native checks.

## Borrowing-cost variant

New career also offers **Bank workout · borrowing costs**. It keeps the same
bank, withdrawal waves and eight-meeting horizon, adding explicit interest on
actual opening loan principal. Its staged APR follows the policy-rate choice;
negative loan APR is a fictional US counterfactual, not a claim about real primary
credit. The original zero-interest lab and normal careers remain separate.

The compact cost panel shows bank-to-Fed and Fed-to-bank cash separately, with
first-staged and last-actual terms clearly labelled. Unpaid interest is separate
from loan principal and highlighted as a funding obligation. Explicit supported
new cash may pay interest before withdrawals; unused offers create neither cash
nor equity. The journal retains actual credit terms/claims and the debrief uses
combined equity including accrued interest. Help discloses authored priority,
day-count and collectibility limits. See `PRICED_CREDIT_EXPERIMENT.md` for source
research, rejected hypotheses and numeric qualification.

Source-native testing completed two eight-meeting Computer Use paths in private
storage: mixed positive/negative rates with partial support, and a keyboard-only
8% path with first-meeting support then no new offers. Screenshots verified the
opposing cash lanes, unpaid-claim warning, readable Help, Escape dismissal, normal
terminal behavior and keyboard Home/End access to the full debrief. An initial
muted warning and empty terminal rows were repaired and visually rechecked.
These are current-size functional/pixel checks, not measured enjoyment, actual
assistive-technology certification or release/export qualification.
