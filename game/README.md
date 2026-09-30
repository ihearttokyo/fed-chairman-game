# Policy Lab economic core

This directory holds the clean-sheet Godot game and its deterministic economic
core, the sole maintained game implementation. The current build is a local
pre-release candidate. The installed Swift app and its saves remain separate;
its source and obsolete build paths are retired to Git history. Start with the
[research](../docs/FED_RESEARCH.md) and
[acceptance contract](../docs/MODEL_CONTRACT.md) for scope and evidence limits.

## Run and inspect

Use Godot 4.7.2 and run from the repository root:

```sh
godot --path game
scripts/test-game.sh
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

## Playable career

Choose one of six scenarios, inspect the current meeting dispatch and stage a
rate, guidance, asset-flow and lending decision. The preview uses the known
current shock, then assumes no new shocks and holds the rate for eight quarters.
It cannot read the realized future shock path. The staff rate rule is a disclosed
benchmark rather than an optimal-play recommendation.

Comparison and adoption stay in the bottom action bar while the cockpit scrolls.
Expanding custom guidance keeps both actions available without hiding any policy
tool, unit, preview assumption or outcome from the scrollable content.

Guidance can use the existing data-dependent preset, a firm pledge, or custom
responses to changes in four-quarter inflation and the output gap. Custom
responses range from -2 to +2 rate percentage points per 1 percentage-point
change since the announcement. They adjust the promise evaluated at the next
meeting, rather than granting an immediate credibility bonus. The comparison
shows the previous condition-adjusted promise, projected follow-through and
any binding rate cap. Announcing a new path does not erase the previous promise.
Committed conditions survive adoption and lossless replay; a new career restores
the defaults. These quantitative conditions are game-design choices, not a
claim about the FOMC's current communication practice.

Choose **Compare policy paths** before adopting to inspect requested and applied
tools, current financial conditions and quarter-1, quarter-4 and quarter-8
differences from holding policy. The reference holds today's rate, uses
data-dependent guidance and requests no new asset flows or lending. Both paths
use the same current shock and no future innovations. The briefing also compares
credibility and public support and explains binding tool limits. Its Q+1
diagnostics expose inflation-miss memory, the model stance target and applied-rate
distance, prior-promise follow-through, current hardship and remembered hardship
for both paths. The stance rule and score weights are disclosed game assumptions,
not an optimal policy or a measured institutional reputation. The briefing does
not change the career or select a policy for the player.

Careers continue through 12-quarter reviews without resetting policy lags,
expectations, hardship memory or charts. The local career limit is 240 quarters.
Data & journal also opens a realized review on demand after any completed
decision, including after loading a career. It compares the latest up to twelve
completed quarters and labels the actual interval. Each review compares realized
average inflation distance and unemployment above
the structural reference, plus ending credibility and support, against holding
the period's initial rate. Both paths begin at the same state and use the same
already-realized shocks. This hindsight comparison is not the forward preview
or an optimal-policy score; it makes the period's tradeoffs inspectable.
Save and Load use separate `FedChairmanPolicyLab` user storage and never touch the
Swift game's saves. Native-value serialization preserves floating-point inputs
exactly; loading validates every shock and replays decisions in isolation before
replacing the active state. Model-version mismatches are refused rather than
silently migrated. Save is a single explicit slot, replaced only when selected.

The original city is authored by `art/build_city.py`; its editable `.blend` source
is retained beside the script. The game loads `assets/policy_city.glb`, so players
and CI do not need Blender. Art source is excluded from runtime imports. Animation
is off by default, controls expose accessibility labels, and the journal supplies
exact chart values. Engine and component notices are available under Credits.

## Apple Silicon release

The shipping target is Apple Silicon (ARM64), not Intel. Godot's official 4.7.2
macOS template is universal; the `macOS universal staging` preset is an
intermediate, not a distributable release. The packager removes the Intel slice
with Apple's `lipo`, then signs the ARM64 application with the supplied Developer
ID identity. No custom engine or export template is needed. This follows the
[Godot architecture contract](https://docs.godotengine.org/en/4.7/classes/class_editorexportplatformmacos.html#class-editorexportplatformmacos-property-binary-format-architecture).

Install that official template, then run from the repository root on macOS:

```sh
scripts/package-game.sh "$HOME/.cache/fed-chairman-builds/NEW_RELEASE" \
  'Developer ID Application: YOUR NAME (TEAM_ID)' TEAM_ID
```

The destination must not exist. The script retains the app, export log,
verification log and ZIP. It checks ARM64-only native code, Developer ID team,
hardened runtime, secure timestamp and strict bundle integrity before packaging.
Signing uses the existing Keychain identity; no credentials belong in this repo.
Apple notarization and store publication are separate actions. A Developer ID
signature alone does not establish notarization or Gatekeeper acceptance.

Stage unpacked apps outside cloud-synced folders: a File Provider may attach
Finder metadata that invalidates strict bundle verification. Do not strip
quarantine or weaken Gatekeeper. Plaintext scripts remain included so the model
is inspectable and save fingerprints survive export.

The actual release executable's `--headless -- --verify-build` entry point runs
141 resource, career and replay checks without external scripts or path
overrides. The release verifier also runs that self-check. Linux CI validates
source behavior; it does not build or distribute an Intel Mac game. Intel
hardware testing is not a release gate for this ARM64-only product.
