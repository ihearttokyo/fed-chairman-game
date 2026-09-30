# Economic Model Rationale

Historical rationale for the retired Swift implementation, retained as a research
record. It does not describe the current Godot equations or release behavior.
Use [game/README.md](../game/README.md) and the [current acceptance
contract](MODEL_CONTRACT.md) for the maintained model.

## Purpose and standard of interpretation

Fed Chairman Game is a directional pedagogical simulation, not a structural macroeconomic model, policy recommendation, point forecast, or estimate of the effect of any real Federal Open Market Committee decision. Its mechanics preserve a small set of economically recognizable signs and tradeoffs so that a player can reason about policy under uncertainty. Numerical outcomes are game calibration. They should be read as internally consistent comparisons, not as predicted percentage-point effects in the U.S. economy.

This distinction matters because monetary-policy transmission is broad, changes over time, and is difficult to assess in real time. Federal Reserve Governor Adriana Kugler describes channels running through borrowing costs, asset prices, wealth, credit, and expectations, while also emphasizing uncertainty about their overall effect. The game compresses those channels into a transparent reduced-form engine rather than pretending to reproduce them.

## Policy paths and lags

Monetary policy acts with long and variable lags. Kugler summarizes research estimates in which the maximum effects on activity and inflation are observed after roughly one to two years, while stressing variation across episodes and transmission channels. That evidence motivates delayed effects in the game; it does **not** identify the game's lag length or quarter weights.

The policy preview therefore compares two counterfactuals over the engine's four-quarter lag window:

- **Selected path:** the staged federal funds rate is maintained through the preview horizon.
- **Hold path:** the current federal funds rate is maintained through the same horizon.

The displayed difference isolates the direction of the staged choice inside the game's own mechanics. Maintaining each rate is a comparison convention, not a claim about future FOMC behavior. Four quarters is the engine's bounded teaching horizon, not an assertion that real-world effects peak after four quarters. It is especially important not to relabel the preview as a forecast or attach empirical confidence intervals to its game-generated values.

## Expectations and credibility

Expectations anchoring is symmetric around the inflation target. In Kugler's discussion of credibility, policy actions consistent with the long-run goal move expectations toward the stated target; inconsistent surprises can move perceived long-run inflation expectations either higher or lower. Board staff research likewise finds that policy strategies responding to long-run expectations can reinforce anchoring and reduce volatility.

Accordingly, weak credibility in the game may allow expected inflation to drift upward when inflation is above target or downward when inflation is below target. Credibility strengthens reversion toward target rather than imposing an upward-only premium. This is a product simplification: neither the credibility score nor its mapping into expectations is an empirical index, and symmetry of the game rule does not claim equal real-world speeds or magnitudes in both directions.

## Demand, labor, supply, and finance

The Federal Reserve's monetary-policy explainer states the core demand relationship directly: when demand slows relative to productive capacity, unemployment tends to rise and inflation tends to decline; when demand is too strong, unemployment can fall to unsustainably low levels and inflation can rise. San Francisco Fed research similarly treats labor-market tightness as a gauge of excess demand and notes that a heating economy makes workers harder to find, placing pressure on wages and prices.

That sign convention controls named shocks. A `labor-market-heats-up` shock represents stronger labor demand and tighter conditions, so it lowers unemployment rather than raising it. A shock intended to raise unemployment should instead be named and modeled as labor-market cooling, labor-supply disruption, financial stress, or another adverse channel. The game uses unemployment as a compact labor-state variable; it does not model vacancies, participation, matching efficiency, hours, or wage formation separately.

Demand and supply shocks must remain distinguishable. San Francisco Fed research identifies demand-driven movements when unexpected price and quantity changes move together, while supply-driven movements move in opposite directions. An oil-supply contraction, for example, can raise oil prices and inflation while reducing activity. The game may therefore let adverse supply or energy shocks raise inflation without the expansionary activity and lower-unemployment signature of a positive demand shock. A supply shock need not be neutral for employment; it simply should not be routed as demand stimulus.

Financial tightening belongs on the adverse-activity side. The Board explains that policy and financial conditions affect household spending, business investment, and job creation. Board staff's Financial Conditions Impulse on Growth work characterizes tighter conditions as headwinds to future GDP growth and associates peak tightening with greater downside risk to employment growth. The game therefore allows financial stress or tighter conditions to weaken activity and raise unemployment, subject to its lag and persistence rules.

## Decision table

| Economic principle | Game rule | Official source |
| --- | --- | --- |
| Transmission is delayed, variable, and uncertain. | Apply policy through a four-quarter engine window; compare maintained selected and hold paths; present direction, not a point forecast. | [Kugler, "Transmission of Monetary Policy" (2025)](https://www.federalreserve.gov/newsevents/speech/kugler20250422a.htm) |
| Credibility anchors expectations to the goal; inconsistency can move them higher or lower. | Let weak credibility amplify misses on either side of target; let strong credibility pull expectations toward target. | [Kugler, "Central Bank Independence and the Conduct of Monetary Policy" (2024)](https://www.federalreserve.gov/newsevents/speech/kugler20241114a.htm); [Kiley, FEDS 2025-027](https://www.federalreserve.gov/econres/feds/monetary-policy-strategy-and-the-anchoring-of-long-run-inflation-expectations.htm) |
| Stronger demand tends to support activity, lower unemployment, and raise inflation pressure; weaker demand reverses those signs. | `labor-market-heats-up` lowers unemployment; restrictive policy and adverse financial conditions weaken activity. | [Federal Reserve Board, "Monetary Policy: What Are Its Goals? How Does It Work?"](https://www.federalreserve.gov/monetarypolicy/monetary-policy-what-are-its-goals-how-does-it-work.htm); [Barnichon and Shapiro (2024)](https://www.frbsf.org/research-and-insights/publications/economic-letter/2024/11/how-much-has-cooling-economy-reduced-inflation/) |
| Supply and energy disruptions can raise inflation while weakening activity. | Route supply/energy inflation separately from positive demand; do not attach a demand-boom labor signature. | [Lansing (2025)](https://www.frbsf.org/research-and-insights/publications/economic-letter/2025/06/is-demand-or-supply-more-important-for-inflation/) |
| Financial conditions transmit through growth and employment with lags. | Financial tightening lowers activity and can raise unemployment. | [Ajello et al., "Financial Conditions and Risks to the Economic Outlook" (2024)](https://www.federalreserve.gov/econres/notes/feds-notes/financial-conditions-and-risks-to-the-economic-outlook-20240920.html) |

## Modeling limits and calibration cautions

The engine is intentionally reduced-form. It does not separately estimate a yield curve, credit spreads, bank lending, balance sheets, exchange rates, fiscal policy, global spillovers, heterogeneous households or firms, labor-force participation, vacancies, productivity, or nonlinear regime changes. Its shock magnitudes, persistence, lag weights, neutral-rate proxy, Phillips/Okun-style sensitivities, credibility updates, bounds, and noise are design parameters unless a future calibration note documents an estimation procedure.

Maintainers should preserve signs before magnitudes, test candidate-versus-hold neutrality, and avoid calibrating one episode as a universal law. The San Francisco Fed's [nonlinear Phillips-curve work](https://www.frbsf.org/research-and-insights/publications/economic-letter/2023/07/reducing-inflation-along-nonlinear-phillips-curve/) shows that labor-inflation relationships vary with tightness and depend on anchored expectations. Its [tariff analysis](https://www.frbsf.org/research-and-insights/publications/economic-letter/2025/11/economic-effects-of-tariffs/) also shows that one disturbance can have different demand and supply effects over time and cautions against extrapolating beyond the historical sample. Those are reasons to keep labels modest, scenarios separable, and coefficients easy to audit. Any empirical recalibration should record the sample, variables, identification method, uncertainty, and version; otherwise it remains a product tuning change.
