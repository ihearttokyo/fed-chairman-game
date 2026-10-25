# Public advice: rounded observations and prior risk

Research only; no production policy or save changes. Scripts preload the current native model from the project path. Both runs use the same 240-quarter horizon and matched offer/portfolio rules across arms. Realized GDP, refinancing and lending can diverge.

## Rounded observation screen
`rounded.gd` replaces full precision with the actual %.2f string boundary for long expectations, four-quarter inflation and output gap. Frozen coefficients and initial-neutral prior remain unchanged. Seeds 61217/90371: 30 careers, 7,200 transitions, zero reported failures.

## Prior stress
`prior-stress.gd` adds observer-only neutral-prior errors of -1/+1 percentage point, leaving the underlying model parameters unchanged. Separate seeds 63239/90389: 30 careers, 7,200 transitions, zero reported failures.

In the crisis scenario, the lower prior raised average inflation distance from 1.053 to 1.664pp. The higher prior reduced it to 0.940pp but increased employment shortfall from 0.252 to 0.354pp. These are means across only two seeded careers, not general causal estimates or evidence of enjoyment.

The public baseline remains close to the oracle, so this alone does not fix one-button dominance. No candidate is adopted. Missing qualification includes a complete observation/disclosure contract, whole-action information isolation, native routine/manual staging, extreme/negative-rate cases, recent/worst windows, explicit initial-state/tape identity assertions and independently reviewed adoption criteria. Both seed sets are now explored, not fresh holdouts for future tuning.

## Independent static review
Sol reviewer found no direct latent-rate/short-expectations read in either reference-rate helper. Material limitation: all arms receive exact state-contingent collateral-backed funding each quarter, unlike production manual staging (preserves tools) and routine follow-up (attendance gates/no new offers). This is a matched rate-rule screen, not production shortcut/routine qualification.

## Native production-path screen

`game/tests/public_advice_production_contract_test.gd` characterizes existing behavior:21 checks pass. Both manual benchmark staging and routine proposals currently depend on hidden neutral/short expectations. Manual staging preserves other tools; routine proposals make no new asset/loan offers and funding returns control. These assertions expose current behavior; they do not endorse it.

`game/tests/public_advice_production_diagnostic.gd` injects the rounded public rate into separate main/routine model instances. All other adoption, attendance and one-shot/reset behavior uses the actual production handlers. Twelve paths of60quarters (720confirmed native adoptions) cover varied career, zero-rate slump and stagflation/bank run, with paired initial state/parameters/shock-tape byte equality. Input/frame timing is simulated headlessly and forecasts are disabled; this is not physical-input UX validation or full240-quarter qualification. No production policy has changed.

The first run completed numerical checks but leaked an audio resource at shutdown. It is not a clean pass. Adding the established100ms mixer-release wait after scene teardown yielded a clean rerun with identical rows and no engine warnings/errors.

Run these opt-in scripts only after the campaign-save-slot storage-only guard passes in an external private HOME, with HOME/FED_GAME_TEST_HOME and XDG/cache/temp paths all isolated, as in scripts/test-game.sh. They are intentionally not in the default suite. No native GUI or player save is involved.

Next adoption gates: isolate rounded-vs-raw behavior on the same seeds; test an explicit public-information adapter, not broad model substitution; qualify full-career/extreme/recent-window behavior and the native manual/routine policy contract; disclose the neutral-rate prior. Near-oracle performance is not evidence of adequate challenge, and matched funding results above must not be substituted for these production-tool results.

Independent review also limits this to a method-level screen: disabling previews bypasses preview-triggered edit cancellation; nondefault manual-tool combinations and physical input are untested. The paired metadata assertion covers state/parameters/shock arrays, not episode metadata. Do not describe it as all gate inputs being proven identical. Final clean log has no warning/error/failure lines and all twelve result rows match the earlier run exactly.
