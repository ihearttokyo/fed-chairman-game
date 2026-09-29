# Research decisions for the replacement model

Research cut: September 29, 2026. These decisions constrain an educational
simulation. They do not establish estimated coefficients or forecast accuracy.
The [acceptance contract](MODEL_CONTRACT.md) owns the behavioral gates; the
[baseline review](REBUILD_REVIEW.md) owns the legacy findings.

## Make each tool solve a different problem

| Model control | Causal role | Boundary |
| --- | --- | --- |
| Target-range midpoint | Steers short-rate conditions, then borrowing costs and demand. | A scalar midpoint is a simplification. The FOMC sets a range; the effective rate is a market outcome, and IORB is a Board decision. |
| Conditional guidance | Changes the expected policy path and longer borrowing rates. | Its influence depends on credibility. A justified response to new data is different from breaking an unconditional promise. |
| Long-duration purchases/runoff | Changes the securities stock and term premium. | Reserve-management bill purchases serve a different purpose and are excluded from this control. Asset purchases are neither fiscal spending nor automatic loan creation. |
| Eligible liquidity support | Covers funding needs against acceptable collateral, then unwinds through repayment. | Cash provision does not restore capital or erase credit losses. Eligibility and collateral come from the scenario, not a player-created exemption. |

The [New York Fed's implementation overview](https://www.newyorkfed.org/markets/domestic-market-operations/monetary-policy-implementation)
and [Board IORB explanation](https://www.federalreserve.gov/monetarypolicy/iorb-faqs.htm)
support the separation between policy stance and overnight-rate implementation.
The [discount-window description](https://www.federalreserve.gov/monetarypolicy/discountrate.htm)
supports temporary, secured lending and primary-credit eligibility. Emergency
firm rescues, deposit insurance, fiscal spending and reserve-ratio changes remain
outside the model. This leaves room for meaningful tool choice without
inventing powers for the Chair.

## Give expectations a horizon and policy a memory

Current inflation, near-term expectations and long-term expectations are
different states. Recent prices affect near-term views more strongly; persistent
policy performance matters to long-term anchoring. Market compensation measures
also contain risk premiums, so the game must not present every long-yield change
as changed expected inflation.
[Kugler, April 2, 2025](https://www.federalreserve.gov/newsevents/speech/kugler20250402a.htm).

Guidance affects financial conditions before its full effects on activity and
prices. Clear conditional commitments and follow-through support credibility;
overconfident promises can create uncertainty when they fail.
[Jefferson, May 13, 2024](https://www.federalreserve.gov/newsevents/speech/jefferson20240513a.htm).
The observed lag varies by episode and channel. Research summarized by Kugler
places peak effects around one to two years, which is a diagnostic range for
impulse tests rather than a calibrated law.
[Kugler, April 22, 2025](https://www.federalreserve.gov/newsevents/speech/kugler20250422a.htm).

Credibility therefore changes gradually and influences anchoring and guidance.
Public support instead records economic hardship and its fading memory. Its
formula is a game assumption; an approval score must not directly rewrite
inflation expectations or silently confer legal appointment authority.

## Allow different kinds of adverse conditions

Credit availability can tighten independently of policy rates. Research using
bank lending standards identifies a credit-supply channel affecting output and
borrowing. Keep a funding wedge separate from credit-loss risk, so lending can
address the former without deleting the latter.
[Bassett et al., October 2013](https://www.federalreserve.gov/econres/feds/changes-in-bank-lending-standards-and-the-macroeconomy.htm);
[Carlson, Duygan-Bump and Nelson, February 2015](https://www.federalreserve.gov/econres/feds/why-do-we-need-both-liquidity-regulations-and-a-lender-of-last-resort.htm).

Neutral rates and productive capacity are uncertain estimates. Expose them as
scenario assumptions and test sensitivity rather than pretending that the Chair
knows a permanent neutral rate. The New York Fed supplies model estimates,
vintages and code, expressly distinguished from official forecasts.
[Measuring the Natural Rate of Interest](https://www.newyorkfed.org/research/policy/rstar).
Output-gap estimates also change with real-time information.
[Barbarino et al., December 2020](https://www.federalreserve.gov/econres/feds/which-output-gap-estimates-are-stable-in-real-time-and-why.htm).

## Use research without claiming a fitted model

Kiley's model experiments support examining explicit reactions to long-run
expectation drift. They do not identify the coefficients of this replacement
game. [FEDS 2025-027](https://www.federalreserve.gov/econres/feds/monetary-policy-strategy-and-the-anchoring-of-long-run-inflation-expectations.htm).
FRB/US has estimated equations, alternative expectation specifications and a much
larger economic structure. It is a reference for comparative impulse behavior,
not a label to attach to a small spreadsheet.
[FRB/US project](https://www.federalreserve.gov/econres/us-models-about.htm).

The research pass reviewed official explanations, speeches, paper abstracts and
model documentation. It did not estimate parameters, run FRB/US or fit raw time
series. Each workbook coefficient must distinguish a source-defined value from
an assumed magnitude supported only by a directional relationship. Tests can
establish internal consistency and the intended mechanisms; external realism
still needs sensitivity analysis and comparison with observed episodes.
