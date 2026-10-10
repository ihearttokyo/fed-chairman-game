extends SceneTree

const Career = preload("res://play/career.gd")
const Economy = preload("res://model/economy.gd")
const Exporter = preload("res://tests/export_reference.gd")

class CountingEconomy:
	extends "res://model/economy.gd"
	var steps := 0
	func step(state: Dictionary, policy: Dictionary, shocks: Dictionary, params: Dictionary) -> Dictionary:
		steps += 1
		return super.step(state, policy, shocks, params)

var checks := 0
var failures := 0
var baseline: Array = []

func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
	return condition

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--capture-baseline":
		if not check(Exporter.output_is_outside_repository(args[1], ProjectSettings.globalize_path("res://")) and not FileAccess.file_exists(args[1]), "baseline destination is new and outside the repository"):
			quit(1)
			return
		native_paths(true)
		if failures == 0:
			var file := FileAccess.open(args[1], FileAccess.WRITE)
			if check(file != null, "private baseline is writable"):
				file.store_buffer(var_to_bytes(baseline))
				file.close()
				print("BASELINE: prior native P/S/SF seed-1 histories, reviews and version-1 payloads captured; checks=", checks)
		quit(1 if failures else 0)
		return
	if not check(Career.new().has_method("mandate_assessment"), "Career must expose pure mandate_assessment"):
		quit(1)
		return
	if args.size() == 2 and args[0] == "--baseline":
		var file := FileAccess.open(args[1], FileAccess.READ)
		if not check(file != null, "prior native baseline is readable"):
			quit(1)
			return
		baseline = bytes_to_var(file.get_buffer(file.get_length()))
		file.close()
		if not check(baseline.size() == 3, "prior native baseline contains all three policies"):
			quit(1)
			return
	elif not check(args.is_empty(), "expected no arguments or --baseline private-file"):
		quit(1)
		return
	boundaries()
	funding_flows()
	eligibility_and_purity()
	native_paths(false)
	if failures == 0:
		print("PASS: pure realized-prefix mandate boundaries, funding flows, native P/S/SF and version-1 replay; checks=", checks)
	quit(1 if failures else 0)

# Synthetic histories below are arithmetic fixtures, not simulated careers.
func fixture(count: int):
	var career := Career.new()
	check(career.start("unanchored_inflation", 1).ok, "arithmetic fixture starts with a canonical shock reference")
	career.decisions.resize(count)
	career.history = [career.state.duplicate(true)]
	for q in range(count):
		var outcome: Dictionary = career.state.duplicate(true)
		outcome.quarter_index = q + 1
		outcome.four_quarter_inflation_pct = career.params.inflation_target_pct
		outcome.unemployment_rate_pct = outcome.structural_unemployment_pct
		outcome.eligible_local_need_pct_initial_gdp = 0.0
		outcome.lending_collateral_capacity_pct_initial_gdp = 0.0
		outcome.liquidity_local_applied_pct_initial_gdp = 0.0
		career.history.append(outcome)
	if count > 0:
		career.state = career.history[-1].duplicate(true)
	return career

func boundaries() -> void:
	var empty := Career.new()
	var untouched: Dictionary = empty.mandate_assessment()
	check(not untouched.eligible and not untouched.complete and untouched.quarters == 0, "unstarted career is not eligible or complete")
	var career = fixture(0)
	var assessment: Dictionary = career.mandate_assessment()
	check(assessment.eligible and not assessment.complete and assessment.quarters == 0, "canonical Q0 is eligible but unassessed")
	for key in ["inflation_miss", "employment_shortfall", "recent_inflation_miss", "recent_employment_shortfall", "funding_coverable", "funding_applied", "funding_coverage"]:
		check(assessment[key] == 0.0 and untouched[key] == 0.0, "Q0 numeric zero: " + key)
	for key in ["prices_met", "employment_met", "funding_active", "funding_met", "achieved"]:
		check(not assessment[key] and not untouched[key], "Q0 has no earned criterion: " + key)
	var keys: Array = assessment.keys()
	keys.sort()
	var expected := ["eligible", "complete", "quarters", "inflation_miss", "employment_shortfall", "recent_inflation_miss", "recent_employment_shortfall", "funding_coverable", "funding_applied", "funding_active", "funding_coverage", "prices_met", "employment_met", "funding_met", "achieved"]
	expected.sort()
	check(keys == expected, "assessment API has exactly the contracted flat keys")
	career = fixture(1)
	career.history[0].four_quarter_inflation_pct = 1000.0
	career.history[0].unemployment_rate_pct = 1000.0
	career.history[0].eligible_local_need_pct_initial_gdp = 1000.0
	career.history[0].lending_collateral_capacity_pct_initial_gdp = 1000.0
	career.history[1].four_quarter_inflation_pct += 1.0
	career.history[1].unemployment_rate_pct += 0.5
	assessment = career.mandate_assessment()
	check(assessment.inflation_miss == 1.0 and assessment.employment_shortfall == 0.5 and assessment.prices_met and assessment.employment_met, "inclusive whole thresholds exclude Q0")
	check(assessment.recent_inflation_miss == 1.0 and assessment.recent_employment_shortfall == 0.5 and not assessment.funding_active and not assessment.achieved, "short history uses all completed quarters, not Q0 or an early award")
	career.history[1].four_quarter_inflation_pct += 0.00000001
	check(not career.mandate_assessment().prices_met, "unrounded whole inflation above 1 pp fails")
	career.history[1].four_quarter_inflation_pct = career.params.inflation_target_pct - 1.0
	check(career.mandate_assessment().prices_met, "inflation distance is absolute on both sides of target")
	career.history[1].unemployment_rate_pct += 0.00000001
	check(not career.mandate_assessment().employment_met, "unrounded whole employment above 0.5 pp fails")
	career.history[1].structural_unemployment_pct = 8.0
	career.history[1].unemployment_rate_pct = 7.0
	check(career.mandate_assessment().employment_shortfall == 0.0, "employment uses each realized structural reference and excludes negative shortfall")
	career = fixture(239)
	assessment = career.mandate_assessment()
	check(assessment.prices_met and assessment.employment_met and not assessment.complete and not assessment.achieved, "Q239 cannot earn an early achievement")
	career = fixture(240)
	assessment = career.mandate_assessment()
	check(assessment.complete and assessment.achieved and not assessment.funding_active and not assessment.funding_met, "Q240 can achieve with funding not applicable, without earning a funding award")
	career.history[1].four_quarter_inflation_pct += 240.0
	career.history[1].unemployment_rate_pct += 120.0
	assessment = career.mandate_assessment()
	check(assessment.inflation_miss == 1.0 and assessment.employment_shortfall == 0.5 and assessment.achieved, "inclusive full-career thresholds before rounding")
	career.history[1].four_quarter_inflation_pct += 0.000001
	check(not career.mandate_assessment().prices_met, "opening costs remain in the full-career average")
	career = fixture(240)
	career.history[240].four_quarter_inflation_pct += 12.0
	career.history[240].unemployment_rate_pct += 12.0
	assessment = career.mandate_assessment()
	check(assessment.recent_inflation_miss == 1.0 and assessment.recent_employment_shortfall == 1.0 and assessment.achieved, "inclusive latest-twelve thresholds at completion")
	career.history[240].four_quarter_inflation_pct += 0.000001
	assessment = career.mandate_assessment()
	check(assessment.inflation_miss < 1.0 and not assessment.prices_met and not assessment.achieved, "final-twelve inflation deterioration cannot hide in lifetime performance")
	career.history[240].four_quarter_inflation_pct = career.params.inflation_target_pct
	career.history[240].unemployment_rate_pct += 0.000001
	assessment = career.mandate_assessment()
	check(assessment.employment_shortfall < 0.5 and not assessment.employment_met and not assessment.achieved, "final-twelve employment deterioration cannot hide in lifetime performance")
	career = fixture(240)
	career.history[228].four_quarter_inflation_pct += 13.0
	career.history[228].unemployment_rate_pct += 13.0
	check(career.mandate_assessment().recent_inflation_miss == 0.0 and career.mandate_assessment().recent_employment_shortfall == 0.0, "completed final twelve are exactly Q229 through Q240")

func funding_flows() -> void:
	var career = fixture(240)
	var outcome: Dictionary = career.history[1]
	outcome.eligible_local_need_pct_initial_gdp = 100.0
	outcome.lending_collateral_capacity_pct_initial_gdp = 100.0
	outcome.liquidity_local_applied_pct_initial_gdp = 95.0
	var assessment: Dictionary = career.mandate_assessment()
	check(assessment.funding_coverable == 100.0 and assessment.funding_applied == 95.0 and assessment.funding_coverage == 0.95 and assessment.funding_met and assessment.achieved, "funding threshold is inclusive at recorded local settlement")
	outcome.liquidity_local_applied_pct_initial_gdp = 94.99999999
	check(not career.mandate_assessment().funding_met and not career.mandate_assessment().achieved, "unrounded funding below 95 percent fails")
	outcome.eligible_local_need_pct_initial_gdp = 10.0
	outcome.lending_collateral_capacity_pct_initial_gdp = 4.0
	outcome.liquidity_local_applied_pct_initial_gdp = 4.0
	outcome.liquidity_applied_pct_initial_gdp = 104.0
	outcome.liquidity_aggregate_applied_pct_initial_gdp = 100.0
	outcome.uncovered_funding_pct_initial_gdp = 6.0
	assessment = career.mandate_assessment()
	check(assessment.funding_coverable == 4.0 and assessment.funding_applied == 4.0 and assessment.funding_coverage == 1.0, "collateral shortage bounds coverable local flow and aggregate lending is excluded")
	outcome.lending_collateral_capacity_pct_initial_gdp = 0.0
	outcome.liquidity_local_applied_pct_initial_gdp = 0.0
	assessment = career.mandate_assessment()
	check(not assessment.funding_active and not assessment.funding_met and assessment.funding_coverage == 0.0, "zero collateral provides no coverable funding achievement")
	outcome.eligible_local_need_pct_initial_gdp = 0.0
	outcome.lending_collateral_capacity_pct_initial_gdp = 100.0
	outcome.uncovered_funding_pct_initial_gdp = 100.0
	check(not career.mandate_assessment().funding_active, "ineligible need is excluded rather than penalized as coverable")
	career = fixture(2)
	for q in [1, 2]:
		outcome = career.history[q]
		outcome.eligible_local_need_pct_initial_gdp = 5.0
		outcome.lending_collateral_capacity_pct_initial_gdp = 5.0
		outcome.liquidity_local_applied_pct_initial_gdp = 5.0
		outcome.outstanding_liquidity_pct_initial_gdp = 5.0
		outcome.liquidity_refinancing_applied_pct_initial_gdp = 5.0 if q == 2 else 0.0
		outcome.decision_nominal_gdp_ratio = float(q)
	assessment = career.mandate_assessment()
	check(assessment.funding_coverable == 10.0 and assessment.funding_applied == 10.0 and assessment.funding_met, "repeated refinancing counts settlement flows in common initial-GDP units, not GDP ratios or unique principal")
	for spec in [{"eligibility":0.0, "collateral":10.0, "coverable":0.0}, {"eligibility":100.0, "collateral":0.0, "coverable":0.0}, {"eligibility":100.0, "collateral":4.0, "coverable":4.0}]:
		var native := Career.new()
		check(native.start("base", 1).ok, "funding boundary native fixture starts")
		native.shocks[0] = {"funding_need_pct_initial_gdp":10.0, "eligible_collateral_pct_initial_gdp":spec.collateral, "liquidity_eligibility_pct":spec.eligibility}
		var policy: Dictionary = native.model.benchmark_policy(native.state, native.params, "hold")
		policy.liquidity_request_pct_initial_gdp = 10.0
		if check(native.advance(policy).ok, "native constrained lending settles"):
			assessment = native.mandate_assessment()
			check(assessment.funding_coverable == spec.coverable and assessment.funding_applied == spec.coverable, "assessment consumes native eligibility/collateral diagnostics")
	var native := Career.new()
	check(native.start("base", 1).ok, "native refinancing fixture starts")
	for q in range(2):
		native.shocks[q] = {"funding_need_pct_initial_gdp":5.0 if q == 0 else 0.0, "refinancing_need_pct_initial_gdp":5.0 if q == 1 else 0.0, "eligible_collateral_pct_initial_gdp":5.0, "liquidity_eligibility_pct":100.0}
		var policy: Dictionary = native.model.benchmark_policy(native.state, native.params, "hold")
		policy.liquidity_request_pct_initial_gdp = 5.0
		check(native.advance(policy).ok, "native new need and then refinancing settle")
	assessment = native.mandate_assessment()
	check(native.state.liquidity_refinancing_applied_pct_initial_gdp == 5.0 and assessment.funding_applied == 10.0 and assessment.funding_coverable == 10.0, "native refinancing is included once per actual settlement")

func live_bytes(career) -> PackedByteArray:
	return var_to_bytes([career.encode(), career.state, career.history, career.decisions, career.shocks, career._seeded_shocks, career.params, career.cases, career.episodes, career.scenario_id, career.seed_value])

func eligibility_and_purity() -> void:
	var career := Career.new()
	career.model = CountingEconomy.new()
	check(career.start("unanchored_inflation", 1).ok, "purity fixture starts")
	for q in range(13):
		check(career.advance(career.model.benchmark_policy(career.state, career.params, "feedback")).ok, "purity fixture completes native history")
	var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold")
	var preview: Dictionary = career.forecast(policy)
	var before := live_bytes(career)
	var steps: int = career.model.steps
	var assessment: Dictionary = career.mandate_assessment()
	check(assessment.eligible and assessment.quarters == 13, "completed canonical prefix qualifies")
	check(career.model.steps == steps, "assessment runs no economic model steps")
	check(live_bytes(career) == before and career.mandate_assessment() == assessment and live_bytes(career) == before, "assessment preserves exact encode, state, history, parameters and inputs repeatedly")
	check(var_to_bytes(career.forecast(policy)) == var_to_bytes(preview), "current policy preview remains byte-identical")
	for q in range(career.decisions.size(), career.shocks.size()):
		career.shocks[q] = {"unrealized_fixture":INF}
	career.episodes = [{"unrealized_fixture":true}]
	before = live_bytes(career)
	check(career.mandate_assessment() == assessment and live_bytes(career) == before, "all current/future shock and episode changes leave assessment and inputs unchanged")
	career.shocks[0] = career.shocks[0].duplicate(true)
	career.shocks[0].demand_shock_pct = career.shocks[0].get("demand_shock_pct", 0.0) + 0.00000001
	check(not career.mandate_assessment().eligible and not career.mandate_assessment().achieved, "even a tiny completed custom shock makes the path practice")
	career.shocks[0] = career._seeded_shocks[0].duplicate(true)
	check(career.mandate_assessment() == assessment, "restoring the canonical completed pulse restores eligibility without a cache")
	for case_id in ["base", "demand_boom", "supply_shock", "funding_stress", "lower_bound_slump", "mixed_crises"]:
		var practice := Career.new()
		check(practice.start(case_id, 1).ok, "practice case starts: " + case_id)
		check(not practice.mandate_assessment().eligible and not practice.mandate_assessment().achieved, "other scenario is practice: " + case_id)
	career = fixture(240)
	career.shocks[239] = {"demand_shock_pct":0.12345}
	check(not career.mandate_assessment().eligible and not career.mandate_assessment().achieved, "eligibility checks the final completed quarter, not only the opening prefix")

func native_paths(capture: bool) -> void:
	var shared := PackedByteArray()
	for index in range(3):
		var mode: String = ["P", "S", "SF"][index]
		var career := Career.new()
		if not check(career.start("unanchored_inflation", 1).ok, mode + " native seed-1 starts"):
			return
		if index == 0:
			shared = var_to_bytes(career.shocks)
		check(var_to_bytes(career.shocks) == shared, mode + " shares the exact exogenous path")
		var independent: Dictionary = career.state.duplicate(true)
		var model := Economy.new()
		var reviews: Array = []
		for q in range(Career.MAX_QUARTERS):
			var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold" if mode == "P" else "feedback")
			if mode == "SF":
				var current: Dictionary = career.current_briefing()
				policy.liquidity_request_pct_initial_gdp = current.get("funding_need_pct_initial_gdp", 0.0) + minf(current.get("refinancing_need_pct_initial_gdp", 0.0), career.state.outstanding_liquidity_pct_initial_gdp)
			var direct: Dictionary = model.step(independent, policy, career.shocks[q], career.params)
			if not check(direct.ok and career.advance(policy).ok, "%s Q%d native and independent transitions complete" % [mode, q + 1]):
				return
			independent = direct.state
			check(var_to_bytes(career.state) == var_to_bytes(independent), mode + " every physical state equals direct equation replay")
			if not capture:
				var before := live_bytes(career)
				var assessment: Dictionary = career.mandate_assessment()
				check(live_bytes(career) == before and assessment.eligible and assessment.quarters == q + 1, mode + " assessment preserves every live/native-save byte")
				check(not assessment.achieved if q + 1 < Career.MAX_QUARTERS else assessment.achieved == (mode == "SF"), mode + " only completed SF achieves the mandate")
			if q + 1 in [1, 12, 239, 240]:
				reviews.append(career.review_comparison())
		var record := {"history":career.history.duplicate(true), "payload":bytes_to_var(career.encode()), "reviews":reviews}
		if capture:
			baseline.append(record)
		else:
			if not baseline.is_empty():
				check(var_to_bytes(record) == var_to_bytes(baseline[index]), mode + " all physical history, review fields/values and version-1 payload bytes match the pre-change native baseline")
			var old_payload: Dictionary = baseline[index].payload if not baseline.is_empty() else record.payload
			check(old_payload.version == 1 and old_payload.keys() == ["version", "model_digest", "scenario_id", "seed", "shocks", "episodes", "decisions"], mode + " retains the unchanged version-1 payload shape")
			var restored := Career.new()
			check(restored.restore(old_payload).ok, mode + " prior version-1 payload restores")
			check(var_to_bytes(restored.history) == var_to_bytes(career.history) and restored.encode() == career.encode(), mode + " prior save reproduces exact physical history and bytes")
			check(var_to_bytes(restored.mandate_assessment()) == var_to_bytes(career.mandate_assessment()), mode + " restored assessment is byte-identical")
			var before := live_bytes(career)
			check(not career.advance(career.model.benchmark_policy(career.state, career.params, "hold")).ok and live_bytes(career) == before, mode + " Q240 advancement guard remains unchanged")
