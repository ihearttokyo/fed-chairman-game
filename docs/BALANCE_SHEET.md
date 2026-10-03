# Portfolio and funding model

This specification governs the coupled balance-sheet section. The economy is hypothetical; observed starting portfolio data inform principal timing, not fitted forecasts or legal powers. The model uses quarterly principal snapshots, not a daily bank, fiscal or term-structure simulator.

## Units and accounting

Nominal amounts remain in percent of initial annual GDP. At a meeting, current-GDP offers convert once using

`n = (actual output / initial actual output) × (price index / initial price index)`.

An offer of p% of current GDP becomes p×n in the engine's nominal units. Ending stock ratios divide by ending n. The price index is a PCE-based proxy, not a separately modeled GDP deflator. GDP growth changes ratios; it cannot create holdings, loans or reserves.

The principal identity is

`Treasuries + MBS + maintenance bills + window loans = reserves + reverse repos + currency + Treasury account + signed capital/other residual`.

The residual reconciles the initial snapshot and stays fixed. Purchases and loans create matching reserve liabilities; loan and MBS principal repayments remove matching reserves. Treasury redemption debits the Treasury account. The model separately assumes private Treasury funding transfers reserves into that account, keeping its net balance stable. This is an explicit funding convention, not a claim that redemption itself immediately debits reserves.

No coupon income, interest expense, mark-to-market changes or future TIPS indexation are modeled. Genuine nonfinite quantities or infeasible final settlement fail before replacing the current state. A large valid offer is not rejected merely for exceeding an invented quota.

## Principal, reinvestment and runoff

The initial Treasury ladder uses 426 holdings from the December 31, 2025 SOMA snapshot. Reported par plus initial TIPS compensation is grouped into 120 equal-length model-quarter bins. Actual maturity dates determine due principal; inverse weighted-average maturity is not a redemption hazard. Scaling the observed ladder to the hypothetical initial portfolio is a design choice.

The MBS starting paydown proxy is three times average 2025 monthly principal divided by year-end MBS holdings. Future paydown varies smoothly with lagged financing conditions through authored coefficients. It is not an observed constant hazard. Treasury replacements use a two-bin approximation to the reported market-average remaining maturity; MBS reinvestment replaces MBS principal. Same-type reinvestment is a counterfactual option, not current Fed agency-to-bill practice.

| Offer | Reinvest principal on | Reinvest principal off |
| --- | --- | --- |
| Positive | Roll due principal; add the purchase | Allow due principal runoff; add the purchase |
| Zero | Roll all due principal | Allow full natural runoff |
| Negative | Run off at most its magnitude and actual principal due; reinvest the rest | The same explicit cap overrides full natural runoff |

A runoff cap is not an immediate securities sale. Excess requested runoff cannot remove unmatured holdings. Due principal is allocated consistently across Treasury, MBS and bill stocks. Purchases have no invented quantity or stock ceiling.

## Duration and reserves are different channels

The duration-equivalent proxy compares long Treasury/MBS holdings with the initialized passive same-type portfolio. Both actual and reference exposure use the same current-GDP denominator. Passive full reinvestment therefore cannot create policy drift merely because GDP grows. A bounded smooth premium response replaces indefinitely linear yield compression. Fixed type weights are an approximation; cohort aging controls principal timing, not a complete yield curve.

Reserve-maintenance bills are separate short assets, excluded from the modeled duration channel. The optional maintenance rule buys or rolls bills to meet a disclosed observed-GDP reserve buffer after other transactions. Currency demand changes through explicit reserve/currency transfers. Those operations preserve ample reserves along the neutral trend but can change funding conditions.

Long-security runoff can be replaced by maintenance bills. Report long runoff, bill purchases and total-asset change separately: a duration contraction need not be an aggregate balance-sheet contraction. Switch maintenance off to expose reserve scarcity. The common scarcity premium is zero in abundance and rises nonlinearly below the disclosed threshold; its coefficients are game assumptions, not the published bank-assets threshold relabeled as GDP.

## Temporary secured lending

The lending offer is desired concurrent facility exposure, not accumulated quarterly turnover. All prior representative short loans mature at the next settlement. Continuing exposure requires a fresh eligible advance. The quarterly convention represents short credit and renewal decisions, not one overnight loan surviving for years.

New funding need remains a flow. Requested refinancing is separate and cannot exceed principal due; default zero assumes borrowers obtain repayment funds outside the Fed. Eligible local advances cover requested refinancing first, then new need. Haircut-adjusted lending value limits concurrent exposure. Aggregate reserve-driven borrowing uses only remaining accommodation/collateral and is evaluated after planned absorption and maintenance. It cannot cover an ineligible borrower's local shortfall.

There is no invented request or quarterly expansion ceiling. Eligibility, lending value, borrower demand and final settlement remain constraints. The abstraction does not make lending an entitlement or replicate daily counterparty operations. Loans do not create bank capital, erase existing credit losses or repair supply damage. Common scarcity is computed once; lending and purchases do not receive a second direct output bonus for injecting cash.

## Sterilized purchases

Sterilization replaces reserve liabilities with reverse-repo liabilities while securities remain assets. Identical long purchases retain the same direct duration input with or without absorption; reserve/funding effects can differ.

A tagged subset of Treasury cohorts tracks principal associated with sterilized discretionary purchases. Tags are annotations, not extra assets. Replacement principal rolls existing tags without increasing desired absorption. Tagged runoff reduces that target. Switching sterilization off releases the associated absorption.

Actual absorption depends on eligible uptake, available Treasury collateral and final reserves. Maturing/encumbered collateral cannot be reused. Requested, applied and unsterilized amounts remain visible; full uptake is a disclosed default abstraction, not a real-world guarantee. Quarterly RRP balances represent snapshots of repeated overnight renewal, not quarter-long overnight contracts.

## Evidence and limits

[NYFed SOMA snapshot](https://markets.newyorkfed.org/api/soma/tsy/get/asof/2025-12-31.json) supplies initial Treasury principal and maturities. The [2025 operations report](https://www.newyorkfed.org/medialibrary/media/markets/omo/omo2025-pdf.pdf) supplies aggregate portfolio/paydown/maturity observations. Their future scaling and behavioral responses remain authored assumptions.

The [July 2026 Monetary Policy Report](https://www.federalreserve.gov/monetarypolicy/2026-07-mpr-part2.htm) separates reserve-maintenance operations from stance changes. [NYFed reserve-demand research](https://www.newyorkfed.org/research/staff_reports/sr1019) supports nonlinear scarcity, not this game's GDP threshold. The [RRP FAQ](https://www.newyorkfed.org/markets/rrp_faq) supports liability substitution and collateral/uptake limits. [Discount-window terms](https://www.frbdiscountwindow.org/pages/general-information/primary-and-secondary-credit-programs) and [collateral valuation](https://www.frbdiscountwindow.org/pages/collateral/collateral_valuation) support secured eligible credit, not unconditional unlimited access.

[Policy-normalization history](https://www.federalreserve.gov/monetarypolicy/policy-normalization.htm) records the end of historical runoff in December 2025. This game's runoff/reinvestment alternatives are counterfactual policy choices. None of the sources estimates the game's elasticities, guarantees recovery or certifies its playability.
