extends SceneTree
const Career = preload("res://play/career.gd")
const Workout = preload("res://play/workout_career.gd")
const Priced = preload("res://play/priced_workout_career.gd")
const Committee = preload("res://play/policy_committee.gd")
const Docket = preload("res://play/policy_docket.gd")
var failures: int = 0

class FailedProjection:
	extends "res://play/career.gd"
	func forecast(_policy: Dictionary, _follow: bool = false) -> Dictionary:
		return {"ok": false, "error": "diagnostic horizon failure"}

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func verify(career: Career, horizon: int) -> Dictionary:
	var builder := Docket.new()
	var staged: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold")
	staged.asset_flow_request_pct_initial_gdp = 0.75
	staged.liquidity_request_pct_initial_gdp = 0.2
	staged.guidance_rate_pct = -1.0
	staged.guidance_inflation_sensitivity = 0.0
	staged.guidance_output_gap_sensitivity = 0.0
	staged.sterilize_purchases = true
	var original: PackedByteArray = career.encode()
	var controls: PackedByteArray = var_to_bytes(staged)
	var result: Dictionary = builder.build(career, staged, horizon)
	check(result.ok and result.entries.size() == 5 and result.forecast_calls == 5 and builder.forecast_calls == 5, "five cached paths only per explicit build")
	check(career.encode() == original and var_to_bytes(staged) == controls, "quote preserves encoded career and incoming policy")
	if not result.ok:
		return result
	var choices: Array = Committee.proposals(career.state, career.params, career.current_briefing(), career.model.nominal_gdp_ratio(career.state))
	check(result.entries[0].policy == staged, "current staged reference is exact")
	check(result.entries[1].policy == career.model.benchmark_policy(career.state, career.params, "hold"), "Hold uses existing benchmark definition")
	check(result.entries[1].summary.contains("Reinvest on · ample reserves on · sterilize off"), "Hold summary resolves existing optional-switch defaults exactly")
	for index in range(5):
		var item: Dictionary = result.entries[index]
		var expected: Dictionary = staged.duplicate(true)
		if index == 1:
			expected = career.model.benchmark_policy(career.state, career.params, "hold")
		elif index >= 2:
			var choice: Dictionary = choices[index - 2]
			expected.policy_rate_request_pct = choice.rate
			expected.guidance_rate_pct = choice.rate
			expected.guidance_inflation_sensitivity = career.params.policy_inflation_response
			expected.guidance_output_gap_sensitivity = career.params.policy_output_gap_response
			if index == 4:
				expected.liquidity_request_pct_initial_gdp = choice.lending_offer_current_gdp * career.model.nominal_gdp_ratio(career.state)
		check(item.policy == expected, "independent advertised-policy construction: " + item.id)
		var direct: Dictionary = career.forecast(expected)
		check(item.projection.ok == direct.ok, "direct forecast availability: " + item.id)
		if direct.ok:
			var last: Dictionary = direct.states[7]
			var peak: float = 0.0
			for state in direct.states:
				peak = maxf(peak, state.uncovered_funding_pct_initial_gdp)
			check(item.projection.values == [last.four_quarter_inflation_pct, last.unemployment_rate_pct, peak], "direct numerical Q8 and all-eight-quarter peak parity: " + item.id)
	return result

func run() -> void:
	var career := Career.new()
	check(career.start("stagflation_bank_run", 1).ok, "normal career starts")
	var baseline: Dictionary = verify(career, 240)
	for index in range(1, career.shocks.size()):
		career.shocks[index].demand_shock_pct = 20.0
		career.shocks[index].funding_need_pct_initial_gdp = 100.0
	check(verify(career, 240) == baseline, "future shock mutation cannot change any docket path or proposal")
	career.shocks[0].demand_shock_pct += 1.0
	check(verify(career, 240) != baseline, "known current shock is included, not discarded")
	for script in [Workout, Priced]:
		var lab: Variant = script.new()
		var opening: Dictionary = lab.model.bank_workout_opening(lab.params)
		check(lab.start_episode(opening.bank, opening.requests, opening.haircut_pct, opening.pledgeable_share, "stagflation_bank_run", 417, opening.remaining_request_index).ok, "isolated lab starts")
		var before: Dictionary = verify(lab, 8)
		for index in range(1, 7):
			lab.withdrawal_requests[index] = 0.0
			lab.shocks[index].demand_shock_pct = 20.0
		check(verify(lab, 8) == before, "original/priced forecasts exclude future withdrawals and shocks")
		check(lab.start_episode(opening.bank, opening.requests, opening.haircut_pct, opening.pledgeable_share, "stagflation_bank_run", 417, opening.remaining_request_index).ok, "restart horizon fixture without mutated future tape")
		for quarter in range(7):
			var held: Dictionary = lab.model.benchmark_policy(lab.state, lab.params, "hold")
			check(lab.advance(held).ok, "lab advances actual meeting for near-horizon fixture")
		var late: Dictionary = verify(lab, 8)
		check(late.ok and late.diagnostic and lab.decisions.size() == 7, "Q7 diagnostic continuation adds no turns")
		check(lab.advance(lab.model.benchmark_policy(lab.state, lab.params, "hold")).ok, "last lab meeting adopts normally")
		var ended: Dictionary = Docket.new().build(lab, lab.model.benchmark_policy(lab.state, lab.params, "hold"), 8)
		check(not ended.ok and ended.forecast_calls == 0 and ended.entries.is_empty(), "completed labs expose no active staging")
	var broken := FailedProjection.new()
	check(broken.start("base", 1).ok, "projection failure fixture starts")
	var failed: Dictionary = Docket.new().build(broken, broken.model.benchmark_policy(broken.state, broken.params, "hold"), 240)
	for item in failed.entries:
		check(item.valid and not item.projection.ok and not item.projection.has("values"), "valid controls remain stageable without invented zero metrics")
	var states: Array = []
	for index in range(8):
		states.append({"four_quarter_inflation_pct": -4.0, "unemployment_rate_pct": 0.0, "uncovered_funding_pct_initial_gdp": 6.0 if index == 2 else 0.0})
	check(Docket.metrics({"ok": true, "states": states}).values == [-4.0, 0.0, 6.0], "signed inflation, zero unemployment and nonterminal funding peak preserved")
	for state in states:
		state.uncovered_funding_pct_initial_gdp = 0.0
	check(Docket.metrics({"ok": true, "states": states}).values == [-4.0, 0.0, 0.0], "zero unmet need is a real zero")
	states[3].unemployment_rate_pct = NAN
	check(not Docket.metrics({"ok": true, "states": states}).ok, "nonfinite path never becomes zero")
	states[3].erase("unemployment_rate_pct")
	check(not Docket.metrics({"ok": true, "states": states}).ok, "missing metric never becomes zero")
	check(Docket.value_text(-4.0) == "-4.00" and Docket.value_text(-0.0001).contains("−") and Docket.value_text(1e100).contains("e+"), "signed/tiny/large finite displays remain meaningful")
	check(Docket.value_text(0.0, true) == "0.00" and Docket.value_text(0.00001, true) == "<0.0001" and Docket.value_text(INF) == "unavailable", "funding formatter reused and nonfinite explicit")
	# Synthetic terminal clock tests the docket guard without 240 unrelated turns.
	check(career.start("base", 1).ok, "fresh stable normal horizon fixture")
	career.decisions.resize(239)
	career.state.quarter_index = 239
	var late_normal: Dictionary = Docket.new().build(career, career.model.benchmark_policy(career.state, career.params, "hold"), 240)
	check(late_normal.ok and late_normal.diagnostic and late_normal.entries[0].projection.ok, "normal Q239 continuation labelled diagnostic")
	career.decisions.resize(240)
	check(not Docket.new().build(career, career.model.benchmark_policy(career.state, career.params, "hold"), 240).ok, "normal terminal staging unavailable")
	if failures == 0:
		print("PASS: direct docket parity, current-only information, pure normal/priced/original forecasts, failures and horizons")
	quit(1 if failures else 0)
