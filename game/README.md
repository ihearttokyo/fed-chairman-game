# Policy Lab economic core

This directory holds the clean-sheet Godot simulation. The playable game and
formula workbook are still being built. The original Swift app and its saves
remain separate. Start with the [research](../docs/FED_RESEARCH.md) and
[acceptance contract](../docs/MODEL_CONTRACT.md) for scope and evidence limits.

## Run and inspect

Use Godot 4.7.2 and run from the repository root:

```sh
scripts/test-model.sh
scripts/test-model.sh --boundaries-only
scripts/test-model.sh --impulse-only
godot --headless --path game --script res://tests/export_reference.gd -- \
  --output /tmp/policy-reference.json --scenario supply_shock \
  --quarters 48 --seed 1 --policy feedback
```

The test wrapper rejects runtime errors even when Godot exits with status zero.
The exporter requires an absolute destination outside this repository. Its
lexical path check is a guard against misplaced artifacts, not a sandbox for
untrusted paths or symlinks. The export contains parameters, starting state,
realized shocks, decisions and full quarterly states. Retain the realized shock
path when reproducing a run across engine versions.

`model/economy.gd` owns the equations. `parameters.json` records each parameter's
units and source classification; `scenarios.json` contains six hypothetical
cases. Rates and inflation use percent units: 2 means 2 percent. Asset and loan
amounts use percent of **initial annual GDP**, so growth does not silently change
their denominator. Output and price levels start at index 100.

## Quarterly order

1. Observe the previous state and choose a rate, conditional guidance, net asset
   flow and liquidity request. `step` receives realized exogenous inputs
   separately. It validates inputs and returns a new state without changing the
   supplied state. Benchmark policies cannot inspect future shocks.
2. Apply rate-change and asset-capacity limits. Roll the term premium forward
   from its prior value using the applied asset flow. Repay part of outstanding
   loans, then limit new lending by new funding need, flow capacity and remaining
   eligible collateral after haircuts. Funding need denotes new financing needed
   during this quarter. Lending does not remove the solvency-risk wedge.
3. Price guidance according to prior credibility. Form short and long real-rate
   gaps, add the credit spread, subtract the neutral real rate and smooth the
   result into financial restraint. Output responds gradually to restraint and
   separately to demand and supply disturbances. Unemployment adjusts toward a
   gap-dependent level around an exogenous structural reference.
4. Inflation depends on prior inflation, prior short expectations, prior output
   pressure and current supply pressure. Compound the price index and calculate
   four-quarter inflation from five price levels. Actual output equals potential
   output times one plus the output gap; growth follows the level ratio.
5. Short expectations follow recent observed inflation and supply pressure.
   Long expectations gradually approach a credibility-weighted combination of
   the target and observed inflation. This is a reduced-form expectation rule.
6. Update credibility from inflation performance, stance adequacy and conditional
   follow-through, weighted 40/40/20. These weights and the policy reaction rule
   are game-design assumptions, not an estimated Federal Reserve objective.
   Guidance promises are evaluated against delivery; an unreachable promise can
   lose credibility. The game interface must disclose that consequence.
7. Calculate current hardship and its decaying memory. Public support closes
   25 percent of the distance to hardship-implied support each quarter. It can
   recover without a term reset and has no legal dismissal meaning. It never
   terminates the laboratory simulation.

The policy rate represents a target-range midpoint. The model does not let a
chair set the market's effective funds rate directly. Asset flows represent a
term-premium policy channel, excluding routine reserve-management purchases.
Liquidity eligibility is supplied externally and represents soundness and
collateral restrictions. Emergency lending authorities and bank recapitalization
are outside this model.

## What the tests establish

The suite checks 240-quarter neutral equilibrium, output/price accounting,
delayed rate effects, separate tool channels, conditional guidance, gradual
credibility and support changes, invalid-input rejection and reproducibility.
It also reports 1,000 seeds across four shock cases under two benchmark policies
for 48 quarters each. The sweep asserts numerical validity; recovery and severe
outcome counts remain visible rather than being forced to pass.

The unanchored-inflation case remains difficult. With the current assumptions,
the feedback benchmark misses the 48-quarter recovery criterion for all 1,000
seeds; a separately tested 96-quarter path recovers. This is a difficulty and
calibration diagnostic, not evidence about optimal play or human performance.

A one-variable lag experiment increased financial-restraint persistence from
0.55 to 0.85. A single 75-basis-point rate surprise then has its largest output
effect at quarter 4 instead of quarter 2, with peak output-gap effects of about
-0.018 and -0.035 percentage points respectively. This design choice places the
output response within the broad timing discussed in the research. It does not
fit an impulse response to data. Under an unresponsive nominal-rate peg,
inflation is still declining at quarter 240 in that experiment: an inflation
trough and global stability under arbitrary policies have not been established.

The 2 percent inflation objective is source-defined. Other behavioral
coefficients, initial conditions, constraints, shock sizes and support scores
are disclosed design assumptions. This is an auditable research-informed game
model, with no FRB/US equivalence, empirical confidence interval or forecasting
claim. Workbook parity, playtesting and production exports remain separate
release gates.
