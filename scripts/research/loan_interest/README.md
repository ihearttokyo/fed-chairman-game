# Performing-loan interest accounting — unshipped experiment

Godot in `game/` remains the sole maintained economic implementation. This small
pure GDScript prototype has **no production imports or integration**, is not a
second maintained backend, and changes neither the zero-interest parent lab nor
the current release. It establishes no gameplay benefit, calibration, winning
policy, credit eligibility, or adoption decision.

## Boundary and APIs

- `opening(cash, securities, deposits, principal, opening_fed_capital,
  performing=true)` requires an explicit authored opening capital assumption
  consistent with the supplied balance sheet. It is **not earned income**.
- `inspect(state)` validates exact schemas, paired claims and identities; returns
  derived bank equity and Fed capital. Negative equity is not automatically a
  finding of impairment, soundness, regulatory capital, or eligibility.
- `accrue(state, annual_rate_pct, days, allow_negative=false)` accrues
  `opening principal × APR% / 100 × actual whole days / 365` without compounding.
  A caller supplies each constant-rate segment; a rate change does not rewrite
  earlier accrual. Zero APR/days/principal produces no interest.
- `settle_positive(state, amount)` transfers bank reserve cash to the Fed against
  the positive interest payable/receivable. Insufficient cash refuses the requested
  payment atomically; an explicit smaller payment leaves the unpaid claim intact.
- `settle_negative(state, amount)` pays the **separate** reverse claim by increasing
  bank reserve cash and the Fed reserve liability. It recognizes no second income.
- `repay_principal(state, amount)` retires equal bank/Fed principal and reserve
  balances using actual bank cash. It leaves accrued positive and negative
  interest intact and recognizes no income. Later accrual uses the remaining
  principal. An explicit caller chooses payment timing/priority; no waterfall,
  renewal, new advance or implied interest settlement is introduced here.

All operations return `{ok:false,error}` without a partial state on refusal.
Successful transitions return a detached `state`, opposite interest-income flows,
`cash_to_bank`, actual `principal_change`, derived equity/capital, and disclosed
equity/capital roundoff residuals. Positive and negative claims coexist across
sign changes: there is no automatic setoff, principal capitalization, forgiveness,
deposit change, securities repricing, or equity repair.

This is a **closed one-bank reserve-account laboratory**: bank `cash` is entirely
its reserve asset and equals the Fed's sole reserve liability. Securities/deposits
are passive outside-sector balances. These are restrictive authored accounting
assumptions, not a claim about an actual consolidated Federal Reserve balance
sheet. Positive accrual raises Fed receivables/capital and bank expense/payables
without cash movement; settlement reduces both receivable and reserve liability.
Negative accrual and settlement reverse those entries without netting the claims.

Only externally attested **performing, collectible credit** is supported. Setting
`performing=false` refuses both accrual and recovery atomically. No impairment,
allowance, nonaccrual, default or recovery law has been estimated or implemented;
cash shortage alone is not a modeled collectibility diagnosis. Negative loan
interest requires an explicit counterfactual opt-in and is **not a US policy fact**.

## Numerical and evidence limits

Nonfinite, Boolean, malformed and unsafe integer amounts (`abs(int)>2^53`) refuse
before float coercion. Whole days must be an exact nonnegative integer within that
representation range. There is no economic principal/rate cap. Floating overflow,
positive-obligation underflow, erased cash/claim legs and unrepresentable updates
refuse rather than clip accounts. Arithmetic uses cancellation-safe signed legs;
roundoff reconciliation is bounded by `1e-12 × this transaction's amount`, never
the whole book, and residuals are reported rather than hidden or booked as income.
Some extreme finite inputs can therefore refuse; universal floating-point support
is not claimed.

Tests independently check equity/capital **changes against income**, not just
tautological closing identities, and ensure settlement does not recognize income
twice. They cover partial payment/unpaid carry, rate-sign switches, zero periods,
principal invariance, replay, immutability, impaired-credit refusal and numerical
boundaries. No engine has been run by the implementing child. Root can run:

```sh
godot --headless --path "$PWD/game" \
  --script "$PWD/scripts/research/loan_interest/ledger_test.gd"
```

`principal_test.gd` additionally checks partial/full retirement, the next day's
reduced accrual, retained unpaid interest after principal reaches zero, both
interest signs, cash/principal overpayment refusals and anti-erasure boundaries.
The original accounting suite and this new suite must both pass. Principal
repayment support does not resolve impaired-credit handling or qualify a coupled
gameplay feature.

Source groundwork was supplied in the parent's retained
`working-document320/funding-decisions-20261026/loan-interest-research.md`
(retrieved 2026-10-26): [Fed Discount Window](https://www.federalreserve.gov/monetarypolicy/discountrate.htm),
[Discount Window General Information](https://www.frbdiscountwindow.org/Pages/General-Information/The-Discount-Window),
[FAM Chapter 1](https://www.federalreserve.gov/aboutthefed/chapter-1-balance-sheet.htm),
[FAM Chapter 8](https://www.federalreserve.gov/aboutthefed/chapter-8-special-topics.htm).
Sources support distinct principal/interest, actual-days/365 accrual, floating
terms and a nonaccrual boundary—not these authored opening balances or an APR/4
quarter approximation. No additional network retrieval occurred here.

Before any later coupled/held-out qualification: freeze quarter/day and payment
timing, previous-day/floating-rate segments and target-range mapping, native
principal retirement/renewal, reserve counterparties, collectibility/impairment,
negative-rate funding and legal setoff assumptions. None is resolved by this ledger.

## Coupled native experiment

The optional native transition and its current evidence/limits are documented in
[`docs/PRICED_CREDIT_EXPERIMENT.md`](../../../docs/PRICED_CREDIT_EXPERIMENT.md).
They do not enable a released game controller. The parent
model is frozen at the released Alpha617 commit; do not silently replace it with
the candidate when comparing outcomes. From the repository root:

```sh
out=$(mktemp -d /tmp/fed-credit-study.XXXXXX)
git show 26794f68b3cac10761bacb7524b73d6a22cb091e:game/model/economy.gd > "$out/original.gd"
FED_PRICED_BASELINE_MODEL="$out/original.gd" FED_PRICED_REPORT="$out/heldout.json" \
  FED_PRICED_FINANCE_INTEREST=1 FED_PRICED_COHORT=holdout_B \
  godot --headless --quit-after 600 --path "$PWD/game" \
  --script "$PWD/scripts/research/loan_interest/paired_study.gd"
```

Use a private `HOME` for execution. Reports refuse overwrite; engine exit status
alone is insufficient—require `PASS:` and no `SCRIPT ERROR:`, `ERROR:` or `FAIL:`.
Repeated qualification of fixed cases is regression evidence, not a fresh
independent discovery sample or proof of player enjoyment.

### Minimum-loan regression

The coupled controller remains unexposed. `minimum_loan_diagnostic.gd` retains
the original desired-success assertions for a 0.0001% GDP loan followed by security
maturity at either interest sign. The original six-failure receipt is retained;
the stock-booking repair now passes all twelve checks, including preview/adoption
parity. These cases also run in the default controller suite. Contractual claims
are not forgiven or relaxed. See `docs/PRICED_CREDIT_EXPERIMENT.md` for numerical
limits and the still-unfinished player-facing/release qualification.
