# Funded-production reference

Opt-in, standard-library Python qualification fixture. Godot remains the game's
only shipping economic implementation. Nothing in `game/` imports this package.

From the repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s scripts/research/funded_production/tests -v
```

The package reads and verifies the existing model parameters, portfolio reference
and Godot source through repository-relative paths. It needs no private task files,
network, Godot process, Excel session or installed game. It does not write saves.

## What it covers

- One immutable monetary ledger: funded invoices, production, payroll, bank credit,
  signed coupons, principal settlement and physical capital vintages.
- A macro adapter driven by actual paid output and employment, with source-timed
  prices, expectations, credibility and hardship memory.
- Finite NOW/WAIT/NEVER project episodes, explicit no-rollover claims, and a
  conditional waiting option. Operating DCF excludes financing flows; finance
  still constrains feasibility. This is not shareholder NPV or welfare.
- Optional bank payout targets retain only earned profits, reduce owner cash
  distributions and never grant equity/reserves or waive loan covenants. Disabled
  targets preserve baseline transitions; they are not an implemented bank planner.
- A pure `households.cash_stock_budget` quotation deducts desired cash-target
  growth from planned spending and caps funding at opening cash plus paid wages.
  Forecast dividends cannot fund purchases. Its income/wealth adjustment is an
  authored behavioral convention, used by the explicitly selected research
  `Controls(household_mode='cash_stock_close_v1')` with `market_clearing=True`.
  This mode freezes funded baskets after paid payroll and distributes firm/bank
  dividends only after trading and mandatory debt settlement. Income history
  comes from the last paid report; q0 income seeds are 20/3.15 times nominal
  scale, not new deposits. Cash ratios 3/20 and 1/21 and adjustment 1/4 are fixed
  version-1 conventions. Dividend forecasts use explicit order inputs or the
  initial/last paid reference; they do not assume a solved growth path.
  Legacy modes are unchanged. The macro adapter still explicitly refuses this
  new mode: endogenous hiring/investment, contractual cash sweeps, project
  commitments/draws and a coupled reference remain unqualified.
- Optional `ClosingCreditForecast` inputs in that closing mode quote next
  nominal payroll and gross project finance for A/R and B/F. Bank payout targets
  use actual post-firm-payout cash and all closing legal principal, including
  next-due claims. Requests round up; only earned distributable income can be
  retained. Traces separate quoted requests from the next quarter's paid payroll
  and submitted new offers. These conditional forecasts neither approve lending
  nor guarantee future cash, hiring or investment. The input defaults to `None`;
  it is not accepted by legacy household modes or the current macro adapter.
- New `OperatingLoanOffer`/`OperatingLoan` contracts have two settlement dates
  and permit automatic surplus-cash repayment in the closing-budget mode. After
  mandatory dues and actual purchases, the executor keeps one actual paid payroll
  as a buffer and repays eligible face in maturity/claim-ID order before dividends
  and the next credit quotation. Principal retirement destroys matching deposits;
  it is neither an expense nor new GDP. Ordinary legacy/project claims are not
  swept. Consented renewals preserve the contract type and two-date term. Typed
  restoration preserves eligibility; other household modes explicitly refuse
  these contracts instead of silently dropping their repayment semantics.
- Optional `ProjectCommitment` commands reserve opening gross lending headroom
  without creating money. The closing mode attempts the full construction
  tranche before residual household goods, using actual service receipts and a
  minimum sufficient loan draw. Undrawn capacity expires. Failed resource or
  financing preflight leaves no loan, coupon or WIP; internally financed projects
  issue no claims. Actual draws use up to 16 positive dated `ProjectLoan` claims
  whose explicit renewal is forbidden. WIP basis is the whole paid invoice,
  including internal funds. Signed coupons retain their actual payer. This does
  not provide endogenous project selection or a qualified macro adapter.
- Dated financing helpers quote opening operating credit at two future closing
  dates, while a closing project draw has a same-date coupon and 16 future
  principal dates. An authored 16-interval curve separates current-rate and
  long-anchor exposure; its rational root grid leaves a reported compounding
  residual. Promised-schedule par is not option-adjusted for early repayment.
  Per-claim settlement PV reports rounding differences without posting fictional
  profit. Factories return conditional loan/commitment commands, not approvals;
  existing macro pricing and historical payment results remain unchanged.
- Typed checkpoints and exact command replay. Project restrictions survive restore;
  principal paid cannot silently become a refinanced claim.

The golden fixture retains all state fields and non-digest command fields from a
16-quarter committed experiment and its specified quarter-17 resume fork. Class
names were normalized when moving the reference into this package. The fixture
records original file hashes, not proof of original run custody. Package-specific
source digests necessarily differ. This format does not migrate historical Python
checkpoints or native game saves. Digests check consistency, not authenticity.

## Limits before adoption

This is a candidate qualification tool, not a validated replacement simulation.
The source-backed parameters coexist with disclosed authored production and
investment conventions. The public balance-sheet adapter supports only a
stationary same-face Treasury rollover program. Full QE/MBS, currency/RRP and
public-interest accounting are not implemented here. Household allocation is a
fixed structural rule, not an optimal utility solution. Ordinary private default
still refuses the transition rather than modeling an economic successor.

The experiment has **not** established balanced growth, a neutral 240-quarter
career, held-out gameplay improvement, runtime performance, native/workbook
parity or player enjoyment. Flat initial capital vintages are a transition state.
A 64-quarter Python choice forecast is not a qualified game-turn runtime path.
The previously failed gameplay screens remain failed. These tests neither replace
nor waive the game's existing model, save, accessibility, export or release checks.
