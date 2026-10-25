# Funded-production reference

Opt-in, standard-library Python qualification fixture. Godot remains the game's
only shipping economic implementation. Nothing in `game/` imports this package.

From the repository root:

```sh
python3 -B -m unittest discover \
  -s scripts/research/funded_production/tests -v
```

The package ships its three historical inputs in `reference_inputs/`, so a cold
copy of this package needs no `game/` tree, private task files, network, Godot
process, Excel session or installed game. It does not write saves.

### Frozen source provenance

The following files were preserved byte-for-byte from Git commit
`2703f7965a3c5f67c5bc233ce3d3c6560268ce7c`, under `game/model/`. Each extracted
file was verified against the pre-existing `SOURCE_DIGESTS` pin **before** being
added here. These are canonical qualification inputs, not a working game copy.

| Frozen file | SHA-256 |
|---|---|
| `parameters.json` | `6e45d72e2231d59f67305270c10ccb5b7afcfc2a3475ec8eb72a497522320949` |
| `economy.gd` | `52580ad1073aca877912527ecc7a6aa36f935de17fbc93e460323b8eba4a0987` |
| `portfolio_reference.json` | `5e7362e82bc848e85869df0c69334f05eb68349b19bf84f7bd7d03b283b19e7e` |

The loader still checks all three exact hashes before loading parameters or the
portfolio. Missing or changed frozen inputs refuse; there is no live-game
fallback, silent refresh or relaxed drift check. Changes to current `game/model/`
inputs do not alter this research baseline. The source pins and historical
goldens are unchanged. Checkpoints also fingerprint the Python implementation;
this path repair does not authorize migration of differently source-bound
checkpoints or qualify the reference as the current/native game model.

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
  prepared records have no qualified decision-replay format. Conditional future
  branches are separate from this current-quarter adapter; endogenous career
  investment adoption remains unqualified. QE,
  currency conversion, new RRP and implicit CB contracts are unsupported here.
- `public_scenarios` declares nineteen dated public programs in four authored
  demand/promise cells. Full-roll instructions resolve each branch's actual
  holder dues and explicit issuer consent, not another branch's calendar. Rates,
  news and facilities are explicit. A caller may supply a fixed IORB or an
  explicit `PolicyIORB()` nominal-policy identity; the latter is an authored
  zero-spread convention, not an estimated Fed relationship or the nonlinear
  effective borrowing rate. Missing dates or inactive promises remain unknown.
- Fresh-Q0 `PaydatePublicBook` is a separate, authored payment convention.
  Principal and non-household coupons settle first; household mortgage coupons
  and matched MBS pass-through settle after funded payroll, before purchases.
  CB earnings/remittance close only after all coupons. Phase witnesses bind
  actual ordered payments, reserves, four wallets, debt, rights and budgets;
  validation does not execute another quarter or authenticate historical custody.
  A negative cash-adjustment base is not negative owned cash. Only opening cash,
  actual paid wages and signed settled income fund the household wallet; forecasts
  affect intentions only. Insufficient deposits/reserves still fail atomically.
  Existing books, modes and their timing remain unchanged. This new research
  subtype has explicit checkpoint tags; there is no paid-career migration.
  The older current/future entry points still refuse it. Journal hand cases
  and checkpoint consistency do not establish recovery or native adoption.
- The explicit `public_paydate` current bridge quotes only principal and early
  non-household coupons before hiring. Its signed conditional household wallet
  uses observed-job wage intentions; a shortfall yields zero spending intention,
  not a declaration of actual insolvency or invented wages. Actual execution
  still funds wages and mandatory coupons through one journal. Conditional
  bank earnings inform credit quotations, not approval. Current public commands,
  IORB and facilities are bound before execution; legacy demand-stock migration,
  QE, new RRP and currency routes remain unsupported by this adapter.
  `paydate_scenarios` requires explicit bounded market-funding declarations at
  every covered date. `public_paydate_branches` shares the finite reducer,
  operating cashflow accounting and protected project-principal checks with
  the original route, selecting only the code-owned new adapter/scenario pair.
  All current public declarations, including unused bid/issue limits, must agree
  across cells before any forecast attempt. WAIT observes only current public
  and own-firm facts. Failed baselines and missing coverage cannot recommend
  investment. A full quotation can execute 228 simulated quarters; it is an
  offline research computation, not a qualified game-turn runtime or controller.
- The separate pure `public_market.resolve_date` quotes a bounded Treasury
  funding command. Explicit roll consent, additional issue authorization, bank
  bids, coupon rates, maturity and allocation priority are required. Subscriptions
  cover only the signed Treasury coupon/principal cash prefix and use actual
  current bank reserves, RRP returns and private principal redemptions. They do
  not use future coupons, IORB, payroll, remittance or CB primary purchases.
  New issuance creates Treasury debt and bank securities, not household income
  or GDP; its coupon rights start after the original-opening coupon bases.
  Deterministic bid priority is not an auction or optimizer. The command remains
  outside the four-cell scenario API and saved commands; source binding is not
  historical custody. It does not cure pre-payroll household mortgage shortages,
  execute a quarter or qualify recovery. Existing full-roll scenarios are unchanged.
- `public_branches.evaluate` simulates one candidate tranche: NOW at date zero,
  WAIT at date one, or NEVER, with no further replacement orders. Each branch
  recomputes its own hiring, payroll, purchases, dividends, credit and policy-rule
  response through the same ledger. There are at most 228 forecast attempts,
  not zero-executor quotations or real career adoptions. Only scalar rows and
  candidate-debt receipts survive; successful nineteen-date paths must retire
  newly issued project principal. Operating PV deducts the actual whole invoice
  once, excludes financial flows and depreciation, and uses eighteen explicit
  common discount factors with date zero undiscounted. No salvage is assumed.
  WAIT exercise uses conditional expectation within a documented coarse public
  release/own-firm information set; neither latent cell labels nor future news
  enter it. Failed positive-weight baselines remain visible. Unknown coverage,
  including a canceled draw with undeclared CB terms, is not an economic rejection
  or approval. These are conditional research choices, not an adopted investment
  controller, future-decision checkpoint format, recovery or native qualification.
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

## Recurring-background counterfactual (experimental)

The separate opt-in recurring forecast declares one fixed physical replacement
request at every forecast date, common across all actions and cells. It adds a
NOW/WAIT tranche only on its legal decision date, and compares whole-firm actual
unlevered cashflow against an identically declared NEVER background. This is an
authored counterfactual—not an endogenous investment rule or a recovery fix.
The original zero-background API and record types remain unchanged.

Background and extra construction can share one actual loan. The new records
therefore name the **decision-date joint construction cohort**, never a fictional
candidate-only fraction. Later background claims remain separately visible and
can extend beyond the nineteen-date horizon. Actual cash, resources, underwriting
and principal receipts remain the one ledger's responsibility. Known background
shortfalls are recorded, not filled by decree; missing public-credit coverage
cannot become an investment recommendation. A partially paid joint order does
not establish delivery of the extra candidate.

No recurring forecast is enabled in the shipping game or accepted as an adopted
checkpoint. Full-table, held-out, recovery, native, workbook and game-turn
qualification require their own evidence.

## Early public liquidity (experimental)

The fresh opt-in `EarlyPaydateBook` adds a witnessed credit phase after public
principal settlement and before the original nonhousehold coupons. It is a
quarter-resolution secured-credit convention, not a daily payment-system model
or a claim of actual Federal Reserve borrower eligibility. The strict paid-payroll
calendar remains separate; unsupported old adapters refuse the new book.

The journal retires a due CB claim once through same-counterparty novation,
records the replacement and cash repayment, then creates only the additional
reserves needed for the ordered coupon prefix. Refinanced face and new draws use
one shared gross facility offer. Existing collateral, positive current modeled
bank equity and explicit contract terms still bind. No early security sale,
Treasury-primary funding, household cash gift or anticipated remittance funds
the phase. The existing haircut and eligibility test are authored assumptions.

Current coupons use the frozen original balances: new reserves and replacement
debt do not retroactively earn or owe opening interest. Later draws retain their
actual conditions, pledges and remaining gross usage. New phase/credit witnesses
and reference-codec tags check consistency, not historical custody or native
save compatibility. The factory does not migrate paid careers.

Targeted raw-journal and codec tests do not establish economic recovery,
heterogeneous CB contract pricing, a qualified current-policy/forecast adapter,
long-run solvency, workbook parity or native adoption. Nothing here is enabled
in the shipping game.

## Experimental current early-paydate bridge

`public_early_paydate` exposes explicit `quote_prefix`, `prepare`, `controls`
and `execute` entry points for the exact `EarlyPaydateBook`. Its pure prefix
uses original coupon bases, public principal settlement, conditional secured
credit and non-household coupons in that order. Projected reserves and wages
are quotations, not owned funds. Execution uses the same atomic journal once;
only positive actual paid output can close the macro state. A refusal preserves
the predecessor. Fiscal instructions, IORB and gross facility limits remain
bound to the preparation.

The old current bridge still requires the exact old book. Preparations have
closed source-bound schemas but are not serialized adopted commands. This new
route does not provide future branch programs, migrate paid careers, establish
recovery or endogenous investment, or change the shipping game. Long-run
checkpoint size and runtime remain separate qualification work.

## Experimental post-payroll settlement liquidity

The fresh-only `HouseholdLiquidityBook` adds a fixed `household_credit` phase
between actual payroll and original mortgage coupons. It first checks household
owned deposits, then quotes the minimum money-grid bank reserve advance from
actual current equity, collateral, CB debt and remaining gross facility room.
Borrowing creates matching bank reserves and CB liabilities, not household
income, bank equity or GDP. Missing needed contracts remain unsupported; a
household wallet shortfall remains a funding failure even with ample facilities.

Early refinancing, household advances and other draws share one gross offer;
repayment does not reopen it. Current coupon bases stay frozen before new credit.
Private collateral witnesses reconcile preceding actual claims and flows. A
failure rolls back the entire quarter. Neither security sales nor future wages,
remittance or invented deposits fund this phase.

`public_household_paydate` provides the explicit current-quarter bridge;
`public_market.resolve_household_paydate_date` uses the existing bounded Treasury
arithmetic. Pure preparations do not approve future post-payroll credit and are
not serialized adopted commands. Old books, entry points and paid reference
checkpoints are not migrated. This authored convention still needs recovery,
long-run codec/runtime, future-program, native and workbook qualification.

## Experimental household policy futures

`public_household_branches` provides explicit single-tranche and recurring
NOW/WAIT/NEVER quotations for the exact household-liquidity book. Its authored
four-cell, nineteen-date programs call the same current adapter and monetary
journal at every forecast date. Old funded/paydate routes remain separate.
Recurring construction uses background plus extra units as one actual invoice
and debt cohort; its matched NEVER path has the same background. Operating DCF
excludes financing flows, while actual financing still constrains feasibility.
Decision-date principal must retire; later background debt is right-censored.

WAIT groups use only the declared realized public and own-firm facts plus current
published policy/news/IORB. Hidden labels, future declarations, bank books and
claim IDs cannot separate indistinguishable groups. Incomplete positive-weight
baselines prevent a recommendation, rather than becoming zero-valued success.
Outputs contain scalar receipts, not adopted future economies or commands.
A selected current decision must be rebuilt against its actual opening state.
Scenario weights, construction schedules and discount factors are authored;
qualification of policy incentives, heldouts, recovery and runtime is unfinished.

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
