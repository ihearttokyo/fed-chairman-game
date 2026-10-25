# Bank-workout episode — in development

The accounting component and read-only panel are implemented. They are **not yet
connected to a playable episode**. Alpha 614 remains the installed/public game.

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

The original 74,423-byte economic core remains an exact prefix; only unused
workout static methods were appended. Default equations, cases, parameters and
RNG order were not edited. Nevertheless, source-integrity hashing changes the
model digest. The bridge therefore admits the previous current digest only for
nine explicit existing scenarios and preserves the older eight-only whitelist.
Both bridges require the exact new source digest and reject future drift.
Unknown/lab headers are not admitted. The digest algorithm is not filtered.

Before implementation, genuine seed-417 feedback-policy Q240 payloads and complete
state/history/decision/shock bytes were generated for all nine scenarios. The
new implementation replays every byte identically in the retained fixtures;
loading never rewrites them. Explicit new encoding uses the new header. This is
selected-path compatibility evidence, not a universal numerical-parity proof.

Current native checks: 119 accounting checks across 52 public steps, 98 full
compatibility checks and 149 synthetic presentation/layout checks. Independent
reviews identified the native meter precision issue; it was fixed and rerun.
Captures, original fixtures and detailed receipts remain outside Git.

## Remaining integration

The native Fed ledger still assumes automatic old-loan retirement. A complete
workout adapter must instead preserve overdue principal, balance actual cash and
contract renewals, price the same remaining bank cashflows and retain both input
states across previews. It must not reuse the earlier atomic-failure or gross
funding-pressure mapping as a substitute. Normal career save slots and awards
must remain protected.

A short, player-operated episode, its financial/macro tradeoffs, meaningful
keyboard play and current-source GUI validation remain unfinished. Passing these
components does not qualify new difficulty, enjoyment, empirical calibration,
workbook integration or release readiness.
