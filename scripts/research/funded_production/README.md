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
  Legacy modes are unchanged. The legacy macro adapter still explicitly refuses this
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
- The opt-in `coupled` quarter builds hiring from current cash-budget sales
  forecasts, then lets the single ledger fund payroll and purchases. Actual GDP
  and employment feed the shared price/expectation/credibility closure. The
  old IS-consumption and generated-jobs paths are not evaluated by this mode;
  incompatible old demand/backlog stocks are refused, not erased. A disclosed
  exponential demand preference impulse changes desired spending once, before
  the owned-wallet cap. Last paid dividends are forecasts, never spendable cash.
  Closing-mode firm buffers now consistently use one actual paid payroll,
  including ordinary internally financed investment; detached order floors
  still apply to legacy modes. Historical fixed-mode golden results are retained.
  Current-state capital ages and paid WIP follow the same legal opening calendar.
  The default private plan remains explicitly **unqualified, no project**;
  supplied project units are research inputs, not an autonomous optimum. The
  quotation/financial planner, coupled reference existence, exact new-mode
  checkpoint/replay, full public adapter and native integration remain unfinished.
- Typed checkpoints and exact command replay. Project restrictions survive restore;
  principal paid cannot silently become a refinanced claim.
- An opt-in `PublicIncomeBook` settles opening-stock Treasury, mortgage/MBS,
  reserve, CB-loan and RRP coupons inside the same atomic journal. Explicit
  annual Treasury cash masses follow actual holder/maturity pools through
  consenting same-face rolls. Treasury payments use actual TGA funds; borrower
  payments use owned deposits/reserves, not automatic new borrowing. Bank
  earnings reach households only through actual earned distributions. Signed
  coupons reverse the payer; mortgage and MBS legs are one funded flow.
  Missing applicable CB/RRP terms refuse, while explicit zero is a contract.
  Deferred CB losses are an explicit nonspendable asset, not private bank capital
  or collateral. Earnings cover that deficit before remittance. The model assumes
  zero CB operating costs/dividends and no surplus adjustment; this is narrower
  than [Federal Reserve accounting](https://www.federalreserve.gov/aboutthefed/chapter-1-balance-sheet.htm).
  Opening stocks proxy quarterly averages, not
  [actual daily IORB calculation and payment timing](https://www.federalreserve.gov/monetarypolicy/iorb-faqs.htm).
  Treasury coupons aggregate per holder before toward-zero monetary rounding;
  other coupons round separately per owner. No empirical coupon calibration is
  selected. Rates for this declared program are research inputs, not an
  implemented policy-to-IORB or security-market pricing bridge.
  An explicit `PublicIncomeControls` command may set the current administered
  reserve rate inside the journal, without rewriting prior paid history or fixed
  Treasury/mortgage coupons. A bounded eleven-obligation opening snapshot binds
  current payment purposes, owners, claims and amounts. Missing, invented or
  duplicate matched receipts fail checkpoint validation and raw-ledger history
  consumption. These consistency checks do not establish historical custody.
  A signed disposable-income budget uses nonnegative desired transaction-cash
  targets; for nonnegative incomes its formula equals the existing rule.
  Paid interest is observed without crediting the wallet twice. Existing book,
  control and report serialized fields remain unchanged; strict new subtype
  identities carry the additional state. Source-bound historical checkpoints
  still require their original source; there is no silent migration.
  QE, coupon-right transfers and new public quantity operations remain explicitly
  refused in this income-first program. Existing private/macro forecasts refuse
  enabled books until their public-income bridge is implemented and qualified.
  These accounting hand cases do not establish recovery, a complete public-policy
  adapter, native/workbook parity or release adoption.
- The separate opt-in `FundedPublicBook` uses `public_funding` projections to
  check authorized principal settlement and exact coupon-right transfers in the
  existing monetary journal. `enable_funded_public` accepts only fresh legacy
  Q0 books; it does not migrate a paid career or change the stationary program.
  Private subscriptions require actual quoted reserves, issuer authorization
  and explicit signed annual coupon cash; missing terms are not zero rates.
  Fractional maturities use the ledger's existing principal allocation, and
  proportional coupon rights follow the actual allocated face without rounding.
  Income uses original opening stocks, not newly issued or transferred claims.
  The declared order returns due RRP, settles mortgage and Treasury principal,
  pays Treasury coupons, then CB-origin outflows and private obligations, and
  remits CB earnings last. Later remittance cannot fund an earlier shortfall.
  Pure inputs and results are immutable asserted snapshots, not authenticated
  books or paid transactions. The journal checks its actual cash prefix against
  those projections before private operations. One current opening snapshot,
  funding batch and ordered transfer tuple bind final holdings, coupon rights,
  TGA/deferred balances and exact principal/trade and income receipts. Raw
  continuation and checkpoint validation reject mismatched receipts before
  consuming current income. Transfer validation checks current proportional rights,
  not event uniqueness; an executor must enforce its own transaction identity.
  The par, pooled quarterly rollover convention carries
  existing coupon mass; it does not price a new auction, accrued interest or
  market yields. Currency conversion, new RRP, CB secondary sales and quarterless
  settlement remain refused in this subtype. Legacy serialized fields stay
  unchanged; explicit new checkpoint types retain the additional current state.
  Macro/private forecasts still refuse enabled books: their public-income bridge,
  recovery and gameplay qualification remain unfinished. Accounting hand cases
  are not evidence of a better game or an adopted native/workbook model.
- The research-only `public_forecast` current-quarter bridge accepts an explicit
  `PublicStep`: administered IORB, funded fiscal instructions and facility limits.
  There is no inferred policy-to-IORB identity. Preparation quotes the canonical
  public prefix without executing a quarter, then uses post-public household
  wallets and signed disposable-income intentions for hiring. Mortgage cash is
  not added twice; expected dividends remain expectations, not spending money.
  Public bank earnings inform conditional capital room, but reach households
  only through actual constrained distributions. Execution revalidates the
  preparation and public command, attempts one existing ledger transition and
  closes GDP/employment from paid production. A known current funding shortfall
  is a refusal, not missing future coverage. Shared quotation helpers preserve
  the old price equations and coupled baseline; legacy entry-point guards stay.
  Actual resulting states use existing checkpoints, but public commands and
  prepared records have no qualified decision-replay format. Future scenario
  coverage, fair NOW/WAIT/NEVER forecasts and endogenous investment selection
  remain unimplemented; this is not a qualified runtime/private planner. QE,
  currency conversion, new RRP and implicit CB contracts are unsupported here.
- A pure partial-equilibrium prospectus quotes four declared forecast cells,
  three actions and 19 dates: 228 scalar rows and zero ledger transitions.
  Sold services are limited by demand, dated capital and focal labor. The
  unlevered score subtracts wages and the whole construction invoice, never
  adds financing receipts or loan coupons, and assumes zero salvage. WAIT
  exercises by conditional expectation within declared observable groups;
  default grouping reveals no cell identity. Unknown financing checks cannot
  become approval, and failed positive-weight baselines are not discarded.
  Caller-supplied vectors and admission flags are assertions, not actual
  borrower/bank verification. This table does not yet construct current-state
  forecasts, hire labor, reserve simultaneous construction resources or execute
  a coupled economy. It is not a qualified live private planner.
- The opt-in `investment` wrapper builds the four physical forecast cells from
  current observations and freezes the current Staff fallback. It quotes demand
  signals, observable next-policy branches and a conditional BankB/F financing
  schedule, then adopts the selected tranche through the real coupled ledger.
  One physical table (228 rows), at most 228 conditional finance dates and
  additional claim scans/draw probes use zero paid forecast transitions; adoption
  uses one actual transition. Loan proceeds and debt service stay out of the
  unlevered value score. Forecasted purchases are conditions, not proven future
  household affordability. Opening BankB CB debt or unsupported claim ownership
  leaves admission unknown. Other-bank future finance, reserve/collateral access
  and full public interest are not projected; actual settlement still enforces
  them and can refuse/cancel a proposal. Forecast errors are returned, not booked
  as income. Quarterly price/productivity roots use the explicit decimal quote
  of Python's floating root; later vector arithmetic is rational. This is not
  an optimal planner, an autonomous reference qualification or native adoption.

The golden fixture retains all state fields and non-digest command fields from a
16-quarter committed experiment and its specified quarter-17 resume fork. Class
names were normalized when moving the reference into this package. The fixture
records original file hashes, not proof of original run custody. Package-specific
source digests necessarily differ. This format does not migrate historical Python
checkpoints or native game saves. Digests check consistency, not authenticity.

## Limits before adoption

**The current candidate has not demonstrated recovery or gameplay depth.**
At source commit `48d5bb4`, all four private paths wait twice, then propose no
investment as forecast sales collapse. Their eight-quarter GDP matches the
no-project comparator: a GDP index of about 12.46 or 12.86 from initial 100.
All twelve conditional finance cases remain admissible under their quoted sales
assumptions; no funding refusal explains the result. The
[retained pilot evidence](../../../docs/research/PRIVATE_INVESTMENT_552_PILOT.json)
records the fixed design, actions and exact paths. It is a falsifier, not a
contract to preserve the bad behavior. Unit-test success does not qualify this
economy. The wrapper's name `adopt` means one simulated private decision, not
product adoption. Nothing here is enabled in the released game.

This is a candidate qualification tool, not a validated replacement simulation.
The source-backed parameters coexist with disclosed authored production and
investment conventions. The macro balance-sheet adapter supports only a
stationary same-face Treasury rollover program. The separate opt-in income
program does not qualify the full QE/MBS, currency/RRP or public-policy bridge.
Household allocation is a
fixed structural rule, not an optimal utility solution. Ordinary private default
still refuses the transition rather than modeling an economic successor.

The experiment has **not** established balanced growth, a neutral 240-quarter
career, held-out gameplay improvement, runtime performance, native/workbook
parity or player enjoyment. Flat initial capital vintages are a transition state.
A 64-quarter Python choice forecast is not a qualified game-turn runtime path.
The previously failed gameplay screens remain failed. These tests neither replace
nor waive the game's existing model, save, accessibility, export or release checks.
