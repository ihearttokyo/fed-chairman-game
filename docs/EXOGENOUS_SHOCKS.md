# Exogenous shock selection and gameplay

## Frozen contract

Parent: `01a0ed6e-3b18-7d13-b13b-dce7470f355d`. Child task: Fed Chairman exogenous shock curation. Rules frozen before the final catalogue is authored, October 3, 2026.

Value hypothesis: concrete external events with different channels, signs and recovery paths will support more meaningful policy decisions than renamed versions of the three existing templates. The original packet supplied concepts; the native deterministic integration is described below. It adds no monetary powers or new economic equations.

Acceptance: exactly 150 distinct candidates, exactly the highest-ranked 50 accepted, all ten requested categories represented, primary references for channels, modest fictional profiles using only verified numerical shock fields, and explicit explanations for the 100 exclusions. Parent owns independent content review, integration, replay, RGR and runtime validation. That research-child scope excluded game and external mutations. Parent integration is isolated above the signed-rate commit; rollback is its local change/PR revert. Installed apps and user saves remain untouched.

## Rubric and ordering

Each integer score is 0 through 5; the five scores have equal weight. Their sum is `total` out of 25. Scores are editorial judgments, not empirical estimates.

| Score | What earns 5 | What reduces the score |
| --- | --- | --- |
| Distinctness | A concrete cause and transmission story unlike other candidates | Different labels for the same bottleneck or a similar aftermath |
| Policy tradeoff | Conflicting inflation/activity signals or a clear tool-limit decision | A routine one-direction response with little diagnostic uncertainty |
| Recognizability | A player can identify the event and its economic stakes | Obscure sector detail or extensive explanation before the dilemma is clear |
| Model fit | Existing fields represent the principal channel without inventing powers | Missing sector, wealth, labor-force, exchange-rate or institutional mechanics |
| Replay variety | Adds a useful sign, timing, recovery or tool-constraint combination | Repeats a better candidate's policy experience |

Rank by descending total, then descending policy tradeoff, model fit, distinctness, replay variety and recognizability, then ascending stable ID. That complete lexicographic key is the deterministic strict order. Accept ranks 1 through 50; do not override it with quotas or a later category preference. Scores are never presented as objective measurements.

Balance is a design and audit criterion, not a post-ranking exception: author 15 candidates in each of the ten categories, seek at least three selections per category and at least 12 favorable selections, and inspect near-duplicates before freezing final scores. If the resulting top 50 fails those checks, report the shortfall rather than silently displace a higher-ranked event. Favorable means external cost relief, productive-capacity improvement, restored demand or restored private financing; it does not promise every household benefits or that stimulus is appropriate.

## Model compatibility and magnitude rules

Research curation used baseline `a9b5fe8`. The complete concept/ranking record is [exogenous_shocks.json](../game/model/exogenous_shocks.json); only its exact top fifty execute. [Primary channel references](EXOGENOUS_SHOCK_SOURCES.md) distinguish evidence from authored profiles. Incidence below is game design, not empirical calibration.

`game/model/economy.gd` owns numerical shock domains and catalogue validation. The 150 authored profiles use ten of the currently supported fields. Transitory neutral-rate innovations remain background-only; they are not authored catalogue pulses. `quarter_index` is scheduling metadata, excluded from each numerical pulse.

| Existing field | Interpretation and authored limit |
| --- | --- |
| `demand_shock_pct` | Output-gap disturbance, not percent sector spending. Absolute authored pulse at most 0.80 versus template 1.20 |
| `supply_innovation_pct` | Innovation to persistent supply pressure, not observed inflation. Absolute authored pulse at most 1.20 versus template 1.80 |
| `potential_growth_pct` | Annualized potential-growth level, not a change. Temporary profiles explicitly return to the 2.0 baseline |
| `r_star_change_pct` | Background-only transitory neutral-rate innovation; no authored catalogue pulse uses it |
| `structural_unemployment_change_pct` | Cumulative structural-reference change, not an immediate unemployment jump. Temporary episodes explicitly offset prior changes |
| `funding_need_pct_initial_gdp` | Gross new funding need, authored at most 2.40 versus template 3.00 |
| `eligible_collateral_pct_initial_gdp` | Scenario-supplied eligible collateral stock; outstanding loans consume capacity |
| `collateral_haircut_pct` | Scenario-supplied valuation haircut, 0 through 100; not a player-controlled waiver |
| `liquidity_eligibility_pct` | Eligible share of aggregate funding counterparties; 0 does not grant nonbanks access |
| `credit_risk_innovation_pct` | Nonnegative temporary credit-risk addition; no negative spread repair field exists |
| `solvency_risk_innovation_pct` | Nonnegative addition to persistent impairment, authored at most 0.35 versus template 0.60 |

Profiles are one to four consecutive quarters. Duration is the input schedule, not the lifetime of the economic consequences: supply pressure persists at 0.70, solvency impairment at 0.98, and existing policy/output/expectation memories continue after the episode. Recovery supply innovations are modest partial relief, not a reset of prices or capacity. Favorable finance uses smaller needs or a temporary nonnegative risk path returning to zero; it cannot subtract accumulated solvency losses.

Every quarter with a funding need includes all four funding/collateral/eligibility fields, even when eligibility is zero. Lending is temporary secured support to eligible institutions, subject to outstanding exposure, collateral and haircut. It cannot transfer fiscal resources, prevent weather, insure deposits, erase bad loans, recapitalize an insolvent bank or directly lend to an ineligible nonbank. Any fiscal or foreign-policy event is external to the player.

All pulse sizes, durations, co-movements and selection scores are fictional design assumptions. Sources support channels or episode observations, not this game's coefficients, incidence, precise net aggregate sign or best policy. The reduced form cannot show distributional losses, separate sectors, damaged capital stocks or labor-force participation directly. Some candidates are excluded because those missing mechanics matter too much.

## Research and validation plan

Use a bounded primary-source ledger with separate channel evidence and author inference. Keep each source's paraphrase brief; do not quote passages. Candidate URLs identify the channel reference, not empirical calibration. Validate record schema, IDs/titles, counts, totals, full strict ordering, ranks, accepted prefix, categories, duration/profile length, finite numerical values, model domains and explicit funding constraints. Run the Markdown prose checker separately and preserve its raw output. Content review remains a separate judgment from mechanical checks.

## Final results

Catalogue: 150 candidates; 50 accepted and 100 excluded. The accepted cutoff is 23/25; rank 51 scores 21/25. There are 19 favorable or conditional-relief selections. Balance was achieved without overriding score order.

| Category | Candidates | Accepted |
| --- | ---: | ---: |
| `energy` | 15 | 5 |
| `financial_funding` | 15 | 5 |
| `financial_solvency` | 15 | 5 |
| `food` | 15 | 5 |
| `health` | 15 | 5 |
| `household_business_demand` | 15 | 5 |
| `labor` | 15 | 5 |
| `logistics_trade` | 15 | 5 |
| `natural_disasters` | 15 | 5 |
| `technology_productivity` | 15 | 5 |

### Ranked top 50

| Rank | ID | Total | Editorial reason |
| ---: | --- | ---: | --- |
| 1 | `ai_productivity_diffusion` | 25 | Accepted: Favorable innovation combines investment, capacity and unit-cost timing without claiming an estimated AI effect. |
| 2 | `fertilizer_export_ban` | 25 | Accepted: A lagged input-to-harvest shock differs from weather destroying the current crop. |
| 3 | `import_input_tariff` | 25 | Accepted: A nonmonetary policy event tests cost pass-through and supply limits without assigning fiscal/trade powers to the player. |
| 4 | `office_property_credit_losses` | 25 | Accepted: A persistent loss wedge without funding need makes the liquidity-versus-capital distinction explicit. |
| 5 | `oil_cartel_cut` | 25 | Accepted: A familiar adverse supply event gives a strong inflation/activity conflict without assigning the Chair energy powers. |
| 6 | `pandemic_contact_avoidance` | 25 | Accepted: Combines a large demand interruption with supply limits and an explicit reopening phase. |
| 7 | `shipping_route_attacks` | 25 | Accepted: Security-driven rerouting has a clear duration and cost channel, unlike a generic demand slowdown. |
| 8 | `sound_bank_uninsured_run` | 25 | Accepted: The pure funding case cleanly tests liquidity versus stance and requires no invented bank recapitalization. |
| 9 | `avian_flu_egg_supply` | 24 | Accepted: Recognizable biological supply loss has a slower replenishment path and a narrow-price-versus-broad-policy dilemma. |
| 10 | `canal_water_transit_limits` | 24 | Accepted: A capacity constraint tied to lock water differs physically from security-driven detours and remains legible in the reduced form. |
| 11 | `flu_absenteeism_wave` | 24 | Accepted: A health-driven labor-hours shock differs from voluntary avoidance of services. |
| 12 | `fuel_pipeline_cyber_stop` | 24 | Accepted: Short physical interruption and purchase payback make the event different from persistent foreign production cuts. |
| 13 | `gas_storage_cold_draw` | 24 | Accepted: Demand for essential heating meets a delivery constraint, producing a different energy dilemma from pipeline damage. |
| 14 | `grain_drought_crop_loss` | 24 | Accepted: Broad grain and feed transmission makes a familiar food supply shock with a clear monetary limit. |
| 15 | `heat_outdoor_work` | 24 | Accepted: A recognizable productivity interruption tests supply diagnosis without requiring a bank crisis. |
| 16 | `shared_cloud_ransomware` | 24 | Accepted: Digital concentration transmits an operational shock broadly without requiring a fabricated solvency loss. |
| 17 | `vehicle_assembly_strike` | 24 | Accepted: A production stoppage driven by bargaining differs from unavailable chips and has a concrete negotiated restart. |
| 18 | `bank_payment_float_failure` | 24 | Accepted: A cash-timing failure without assumed insolvency adds a different origin and short unwind to funding stress. |
| 19 | `cattle_liquidation_reversal` | 24 | Accepted: The biological sign reversal creates a strong sequencing problem that a generic food-price increase would miss. |
| 20 | `corporate_accounting_fraud` | 24 | Accepted: An external borrower-information shock separates credit losses from cash withdrawal pressure; aggregate size is fictional. |
| 21 | `dealer_repo_haircut_jump` | 24 | Accepted: Private haircut-driven cash needs show the hard counterparty boundary; model haircut is zero because no window-eligible collateral is pledged. |
| 22 | `effective_vaccine_reopening` | 24 | Accepted: Favorable reopening brings a genuine demand-versus-capacity sequencing problem; no vaccine-effect magnitude is claimed. |
| 23 | `farm_commodity_price_defaults` | 24 | Accepted: Opposite consumer-price and financial-loss signals force a demand-versus-capital diagnosis. |
| 24 | `federal_shutdown_interruption` | 24 | Accepted: A fiscal interruption with pay timing and service loss gives an identifiable multi-quarter demand/supply puzzle. |
| 25 | `hurricane_housing_loss` | 24 | Accepted: Housing loss followed by rebuilding gives opposite activity signals across quarters and a clear limit to monetary tools. |
| 26 | `migrant_worker_inflow` | 24 | Accepted: Favorable labor supply with concurrent demand requires diagnosis and preserves the Chair immigration-policy limit. |
| 27 | `robotics_skill_transition` | 24 | Accepted: Favorable productive capacity with temporary mismatch tests the difference between cyclical demand and structural adjustment. |
| 28 | `wildfire_smoke_closures` | 24 | Accepted: Combines labor availability and lost services demand through smoke rather than direct asset destruction. |
| 29 | `bumper_grain_harvest` | 24 | Accepted: Favorable supply and household purchasing power provide a noncrisis food episode; magnitudes are authored. |
| 30 | `chip_capacity_ramp` | 24 | Accepted: Favorable intermediate-input relief connects an identifiable capacity expansion to the existing supply field. |
| 31 | `external_fiscal_rebate` | 24 | Accepted: Favorable household cash relief creates a finite demand pulse and a clear fiscal-versus-monetary boundary. |
| 32 | `bank_dollar_rollover_squeeze` | 23 | Accepted: Mixed eligibility and working-capital demand create a distinct partial-coverage dilemma; shares are fictional aggregate design. |
| 33 | `battery_process_cost_gain` | 23 | Accepted: A favorable manufactured-input efficiency gain offers a clear adoption-before-cost-relief sequence. |
| 34 | `early_retirement_buyout` | 23 | Accepted: A concrete voluntary-exit trigger avoids presenting slow demographic aging as a surprise and highlights missing participation accounting. |
| 35 | `earnings_news_wealth_drop` | 23 | Accepted: Separates a policy-independent valuation and spending shock from the selected banking funding run. |
| 36 | `industrial_flood_shutdown` | 23 | Accepted: Production interruption and subsequent replacement demand create a concrete timing problem. |
| 37 | `mortgage_lien_documentation_failure` | 23 | Accepted: A collateral-recovery loss differs from fabricated corporate income and from unavailable pledge documentation in a funding bridge. |
| 38 | `persistent_post_viral_illness` | 23 | Accepted: A persistent health/labor channel tests low unemployment alongside constrained supply; longer-run effects remain outside the profile. |
| 39 | `private_bank_recapitalization` | 23 | Accepted: Conditional favorable private repair tests the policy boundary; its true capital accounting is explicitly outside the existing fields. |
| 40 | `stable_private_deposits_return` | 23 | Accepted: Conditional favorable normalization tests an orderly liquidity unwind without fabricating negative needs or deleting losses. |
| 41 | `precautionary_saving_scare` | 23 | Accepted: A reversible preference for cash is different from lost supply or insolvent lenders. |
| 42 | `sea_lane_security_restored` | 23 | Accepted: Favorable security resolution adds disinflation plus inventory payback rather than another adverse transport crisis. |
| 43 | `shale_drilling_productivity` | 23 | Accepted: Favorable production efficiency contrasts with an oil-demand slump and offers a capacity-led expansion. |
| 44 | `childcare_capacity_opens` | 23 | Accepted: Favorable care capacity improves labor availability without treating participation gains as a mechanical unemployment reduction. |
| 45 | `customs_digitization_release` | 23 | Accepted: Favorable border efficiency adds a concrete cost-relief/rebound path; the rollout magnitude is not sourced. |
| 46 | `foreign_tourism_revival` | 23 | Accepted: Favorable demand comes from external customers. Its net national scale is an author assumption. |
| 47 | `generic_medicine_supply_restored` | 23 | Accepted: Favorable restoration gives cost relief and delayed demand while respecting that the Chair cannot manufacture medicines. |
| 48 | `mild_winter_building` | 23 | Accepted: Favorable weather adds supply relief alongside construction spending; the sign is an authored inference. |
| 49 | `professional_credentials_recognized` | 23 | Accepted: Favorable access to existing skills is distinct from migration volume or new training; the structural reference resets explicitly. |
| 50 | `renewable_grid_connection` | 23 | Accepted: A favorable supply completion uses sunk capacity rather than another commodity-price collapse. |

### Favorable selections

`ai_productivity_diffusion`, `effective_vaccine_reopening`, `migrant_worker_inflow`, `robotics_skill_transition`, `bumper_grain_harvest`, `chip_capacity_ramp`, `external_fiscal_rebate`, `battery_process_cost_gain`, `private_bank_recapitalization`, `stable_private_deposits_return`, `sea_lane_security_restored`, `shale_drilling_productivity`, `childcare_capacity_opens`, `customs_digitization_release`, `foreign_tourism_revival`, `generic_medicine_supply_restored`, `mild_winter_building`, `professional_credentials_recognized`, `renewable_grid_connection`.

Private-deposit normalization and private-bank recapitalization are conditional relief from continuing distress, not unconditional improvements against an empty-shock baseline. Other favorable events have explicit cost/capacity relief or recovered external demand; side effects and uncertainty remain in their dilemmas.

### Exclusion and duplicate review

Each rank 51–150 record includes its own exclusion reason. Those alternatives remain concrete concepts, not deferred acceptance. Lower rank can reflect narrower scale, sector accounting that is absent, weaker direct source support, less policy tension or similarity to a stronger selected experience. Different source or region names alone never establish distinctness.

Pre-catalogue ideas rejected as duplicates or unauthorized powers: separate hurricanes distinguished only by landfall city; droughts distinguished only by state; repeated generic bank runs with new institution names; player-generated rate-induced recessions as exogenous events; Fed fiscal transfers; Fed weather prevention; unrestricted nonbank emergency rescue; and Fed recapitalization of insolvent banks. These do not count toward 150.

Opposite-sign or recovery candidates count only when they have a specified different cause or temporal mechanism. New drilling efficiency improves output per crew, private term deposits change maturity commitments, and a completed chip facility adds qualified production capacity. These have different causes from oil-output cuts, uninsured withdrawals and chip contamination. Near-overlaps were retained below the cutoff only where the causal distinction remains concrete, and the reduced replay value is explained.

### Parent integration gates

Static catalogue validation does not prove economic magnitudes, playability or recovery. The parent must independently review content and traces, map event onset metadata outside numerical profiles, preserve realized shocks and model fingerprints, and test additive background/overlap domains and eligible lending headroom. Never dispatch these events from a runtime AI service or claim empirical crisis incidence.

Potential-growth profiles use the documented 2.0 baseline and explicitly restore it. Their temporary growth changes leave level effects; they are not loss-of-capital or restoration-of-capital equations. Structural-unemployment offsets sum to zero, subject to other independent shocks. Neutral-rate pulses now enter the transitory reversion equation: opposing innovations need not restore the exact earlier rate. Neither mechanism resets the full state.

The research child supplied static and source evidence only. Parent native headless integration tests validate profiles, saved context, full careers and conditional relief; they do not certify GUI usability or empirical calibration.


## Deterministic gameplay integration

Recurring crises draws from a no-repeat bag of 48 independent selected concepts, plus two conditional follow-ups, using a separate seed-derived RNG. Ordinary onsets are 12–20 quarters apart. Authored one-to-four-quarter profiles retain their signs and timing: growth levels, haircuts and borrower eligibility are never polarity-flipped or randomly rescaled. Background randomness and the six earlier scenario paths stay unchanged. Exact shorter paths are prefixes of longer paths, including partially completed episodes.

Private bank recapitalization may follow commercial-property or mortgage-lien bank losses. Stable deposits may follow an eligible uninsured run, bank payment-float failure or bank dollar-rollover squeeze, never an ineligible nonbank repo event. Each follow-up may occur once per bag, one quiet quarter after its trigger finishes. Their profiles taper new credit or funding pressure relative to continuing distress; neither subtracts old impairment or deletes outstanding loans. Private equity repair itself remains outside the reduced-form accounting.

### Live information boundary

Each accepted concept adds `phase_briefings`, an array with exactly one entry per authored quarter. Each entry contains only a nonempty `title` and `policy_dilemma`. Live dispatch selects the current entry, including its phase-local title, rather than the concept's full research title or dilemma. Copy describes current and previously observed information; it never announces a scheduled later development, future pulse, remaining duration or next event. General economic uncertainty can remain explicit.

Herd liquidation initially describes current beef supply and farm spending, without announcing later scarcity. The first hurricane phase describes displacement and interrupted work, without announcing rebuilding demand. Initial battery-equipment investment describes current spending, without announcing later cost relief. Later phases may discuss a reversal or recovery once it is observed. The original mechanisms and full policy dilemmas remain unchanged and useful for offline education; excluded concepts receive no live phase arrays.

Forecasts use the full current shock dictionary, not just its dispatch summary, followed by no new innovations. Numeric paths and named context are precomputed at career start and preserved through native-value saves; model fingerprints include this catalogue. Altered saved context rejects atomically. An independent seeded reconstruction at start and restore supplies a private immutable reference, separate from mutable realized inputs. Attribution requires an exact match to the current seeded pulse, including its particular background disturbances. A small audit edit suppresses the label even if the edited value remains within general background ranges. Saved edited numeric inputs remain authoritative for replay; restoring the exact seeded pulse restores attribution.

AI productivity diffusion is a fictional external economic episode, not runtime AI integration. No connector, service, model inference or network request runs during play. These profiles form a finite designed event mixture, not an estimated tail distribution, kurtosis fit, disaster frequency or empirical policy forecast.
