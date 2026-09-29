extends SceneTree

const Economy = preload("res://model/economy.gd")
var model = Economy.new()
var failures: Array[String] = []


func expect_close(actual: float, expected: float, context: String) -> void:
	if not is_finite(actual) or abs(actual - expected) > 1e-8:
		failures.append("%s: got %.10f, expected %.10f" % [context, actual, expected])


func expect_true(condition: bool, context: String) -> void:
	if not condition:
		failures.append(context)


func neutral_policy(state: Dictionary) -> Dictionary:
	return {
		"policy_rate_request_pct": state.r_star_pct + state.expected_short_inflation_pct,
		"guidance_rate_pct": state.r_star_pct + state.expected_short_inflation_pct,
		"guidance_inflation_sensitivity": 1.5,
		"guidance_output_gap_sensitivity": 0.5,
		"asset_flow_request_pct_initial_gdp": 0.0,
		"liquidity_request_pct_initial_gdp": 0.0,
	}


func load_parameters() -> Dictionary:
	return model.call("load_parameters")


func load_scenarios() -> Dictionary:
	return model.call("load_scenarios")


func initial_state(params: Dictionary, override: Dictionary = {}) -> Dictionary:
	return model.callv("initial_state", [params, override])


func step(state: Dictionary, policy: Dictionary, shocks: Dictionary, params: Dictionary) -> Dictionary:
	return model.callv("step", [state, policy, shocks, params])


func policy_at(rate: float, guide: float, asset_flow: float = 0.0, liquidity: float = 0.0, infl_sensitivity: float = 1.5, gap_sensitivity: float = 0.5) -> Dictionary:
	return {
		"policy_rate_request_pct": rate,
		"guidance_rate_pct": guide,
		"guidance_inflation_sensitivity": infl_sensitivity,
		"guidance_output_gap_sensitivity": gap_sensitivity,
		"asset_flow_request_pct_initial_gdp": asset_flow,
		"liquidity_request_pct_initial_gdp": liquidity,
	}


func _initialize() -> void:
	# A 1% quarter is not a 1% annualized growth rate (BEA's level-ratio definition).
	expect_close(Economy.annualized_growth(101.0, 100.0), 4.060401, "Quarterly growth compounds four times")
	# At a fixed output gap, actual and potential output grow at the same rate.
	var previous_potential := 100.0
	var next_potential := previous_potential * pow(1.02, 0.25)
	for gap in [-5.0, 0.0, 3.0]:
		expect_close(Economy.annualized_growth(next_potential * (1.0 + gap / 100.0), previous_potential * (1.0 + gap / 100.0)), 2.0, "Constant %.1f%% gap has potential growth" % gap)
	# RED established before implementation: the canonical API was missing.
	var engine := Economy.new()
	if not engine.has_method("initial_state") or not engine.has_method("step"):
		failures.append("canonical quarterly state/step API is missing")
	elif OS.get_cmdline_user_args().has("--boundaries-only"):
		_test_review_regressions()
	elif OS.get_cmdline_user_args().has("--impulse-only"):
		_test_policy_impulse_and_peak()
		if failures.is_empty():
			print("PASS: focused policy impulse diagnostics")
			quit(0)
		else:
			for failure in failures:
				printerr("FAIL: ", failure)
			quit(1)
		return
	else:
		_test_equilibrium_and_pure_step()
		_test_accounting()
		_test_validation_and_no_mutation()
		_test_review_regressions()
		_test_market_lag_parameter()
		_test_signed_supply_relief()
		_test_asset_purchases_change_financial_conditions()
		_test_policy_impulse_and_peak()
		_test_demand_and_supply_channels()
		_test_expectations_and_credibility()
		_test_conditional_guidance()
		_test_liquidity_limits_and_solvency_separation()
		_test_public_support_recovers_without_reset()
		_test_shipped_scenarios_and_seeded_robustness()
	if not failures.is_empty():
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)
	else:
		print("PASS: growth, equilibrium, accounting, validation")
		quit(0)


func _test_review_regressions() -> void:
	var exporter = load("res://tests/export_reference.gd")
	expect_true(not exporter.output_is_outside_repository("/repo/reference.json", "/repo/game/"), "export refuses the repository parent of the Godot project")
	expect_true(not exporter.output_is_outside_repository("/repo/game/../reference.json", "/repo/game/"), "export normalizes parent traversal")
	expect_true(not exporter.output_is_outside_repository("relative.json", "/repo/game/"), "export requires an absolute path")
	expect_true(exporter.output_is_outside_repository("/repo-copy/reference.json", "/repo/game/"), "export does not reject a sibling with a shared prefix")
	var params: Dictionary = load_parameters().values
	var state: Dictionary = initial_state(params).state
	var premium: Dictionary = initial_state(params, {"term_premium_pct": 1.5}).state
	var held: Dictionary = step(premium, neutral_policy(premium), {}, params)
	expect_true(held.ok, "nondefault initial term premium permits a hold")
	if held.ok:
		expect_close(held.state.term_premium_pct, 1.5, "no asset flow preserves the initial term premium")
	var low_support: Dictionary = initial_state(params, {"public_support": 10.0}).state
	var recovering: Dictionary = step(low_support, neutral_policy(low_support), {}, params)
	expect_true(recovering.ok, "low initial support permits recovery")
	if recovering.ok:
		expect_true(recovering.state.public_support > 10.0 and recovering.state.public_support < 30.0, "initial public support recovers gradually without an instant reset")
	expect_true(not initial_state(params, {"credit_spread_pct": 2.0}).ok, "derived initial spread cannot be overridden independently of risk")
	var risk: Dictionary = initial_state(params, {"solvency_risk_wedge_pct": 0.6}).state
	expect_close(risk.credit_spread_pct, params.normal_credit_spread_pct + 0.6, "initial spread includes the initial risk wedge")
	var malformed: Dictionary = state.duplicate(true)
	malformed.annualized_quarterly_inflation_pct = 50.0
	var snapshot: Dictionary = malformed.duplicate(true)
	expect_true(not step(malformed, neutral_policy(state), {}, params).ok, "quarterly inflation must reconcile with price history")
	expect_true(malformed == snapshot, "rejected history leaves input unchanged")
	malformed = initial_state(params, {"asset_stock_pct_initial_gdp": 99.0}).state
	malformed.asset_stock_capacity_pct_initial_gdp = 1000.0
	expect_true(not step(malformed, policy_at(3.5, 3.5, 100.0), {}, params).ok, "state cannot override the parameter-owned stock capacity")
	var invalid_params: Dictionary = params.duplicate(true)
	invalid_params.public_support_base = 120.0
	expect_true(not initial_state(invalid_params).ok, "public support baseline respects its declared domain")


func _test_equilibrium_and_pure_step() -> void:
	var loaded: Dictionary = load_parameters()
	expect_true(loaded.ok, "parameters load: %s" % loaded.get("error", ""))
	if not loaded.ok:
		return
	var initialized: Dictionary = initial_state(loaded.values)
	expect_true(initialized.ok, "baseline state initializes: %s" % initialized.get("error", ""))
	if not initialized.ok:
		return
	var state: Dictionary = initialized.state
	var start: Dictionary = state.duplicate(true)
	for q in range(240):
		var result: Dictionary = step(state, neutral_policy(state), {}, loaded.values)
		expect_true(result.ok, "equilibrium step %d: %s" % [q, result.get("error", "")])
		if not result.ok:
			return
		state = result.state
		expect_close(state.output_gap_pct, 0.0, "no-shock equilibrium output gap q%d" % state.quarter_index)
		expect_close(state.unemployment_rate_pct, state.structural_unemployment_pct, "equilibrium unemployment q%d" % state.quarter_index)
		expect_close(state.annualized_actual_growth_pct, state.annualized_potential_growth_pct, "equilibrium growth identity q%d" % state.quarter_index)
		expect_close(state.annualized_quarterly_inflation_pct, 2.0, "equilibrium inflation q%d" % state.quarter_index)
		expect_close(state.public_support, start.public_support, "equilibrium support q%d" % state.quarter_index)
		expect_true(state.credibility >= start.credibility and state.credibility <= 1.0, "equilibrium credibility remains bounded q%d" % state.quarter_index)
		if q == 0:
			expect_true(state.credibility < start.credibility + 0.01, "credible performance earns gradual, not instant, trust")
	expect_close(start.quarter_index, 0.0, "step leaves caller's input state unchanged")


func _test_accounting() -> void:
	var loaded: Dictionary = load_parameters()
	if not loaded.ok:
		return
	var initialized: Dictionary = initial_state(loaded.values, {"output_gap_pct": 3.0})
	expect_true(initialized.ok, "nonzero-gap state initializes")
	if not initialized.ok:
		return
	var state: Dictionary = initialized.state
	var result: Dictionary = step(state, neutral_policy(state), {"demand_shock_pct": 0.84}, loaded.values)
	expect_true(result.ok, "constant-gap accounting step")
	if result.ok:
		var next: Dictionary = result.state
		expect_close(next.actual_output_index, next.potential_output_index * (1.0 + next.output_gap_pct / 100.0), "actual output is potential times gap")
		expect_close(next.annualized_actual_growth_pct, next.annualized_potential_growth_pct, "constant gap grows at potential")
		expect_true(next.price_index > state.price_index, "positive inflation compounds the price index")
		expect_close(next.four_quarter_inflation_pct, 100.0 * (next.price_history[4] / next.price_history[0] - 1.0), "rolling price history reconciles four-quarter inflation")


func _test_validation_and_no_mutation() -> void:
	var loaded: Dictionary = load_parameters()
	if not loaded.ok:
		return
	var initialized: Dictionary = initial_state(loaded.values)
	if not initialized.ok:
		return
	var state: Dictionary = initialized.state
	var before: Dictionary = state.duplicate(true)
	var bad := neutral_policy(state)
	bad.erase("policy_rate_request_pct")
	var rejected: Dictionary = step(state, bad, {}, loaded.values)
	expect_true(not rejected.ok, "missing policy rate rejected")
	expect_true(state == before, "invalid step does not mutate state")
	bad = neutral_policy(state)
	bad.policy_rate_request_pct = NAN
	rejected = step(state, bad, {}, loaded.values)
	expect_true(not rejected.ok, "nonfinite policy rate rejected")
	expect_true(state == before, "nonfinite policy does not mutate state")
	bad = neutral_policy(state)
	bad.asset_flow_request_pct_initial_gdp = 101.0
	rejected = step(state, bad, {}, loaded.values)
	expect_true(not rejected.ok, "out-of-range tool request rejected")
	expect_true(state == before, "out-of-range tool request does not mutate state")
	rejected = step(state, neutral_policy(state), {"future_quarter_shock": 10.0}, loaded.values)
	expect_true(not rejected.ok, "unknown or future exogenous input rejected")
	expect_true(state == before, "invalid shock does not mutate state")


func _test_market_lag_parameter() -> void:
	var loaded: Dictionary = load_parameters()
	if not loaded.ok:
		return
	var params_fast: Dictionary = loaded.values.duplicate(true)
	var params_slow: Dictionary = loaded.values.duplicate(true)
	params_fast.real_rate_gap_persistence = 0.1
	params_slow.real_rate_gap_persistence = 0.85
	var fast: Dictionary = initial_state(params_fast).state
	var slow: Dictionary = initial_state(params_slow).state
	var fast_policy := neutral_policy(fast)
	var slow_policy := neutral_policy(slow)
	fast_policy.policy_rate_request_pct = 4.25
	slow_policy.policy_rate_request_pct = 4.25
	var fast_result: Dictionary = step(fast, fast_policy, {}, params_fast)
	var slow_result: Dictionary = step(slow, slow_policy, {}, params_slow)
	expect_true(fast_result.ok and slow_result.ok, "rate impulse accepts both transmission calibrations")
	if fast_result.ok and slow_result.ok:
		expect_true(abs(slow_result.state.financial_restraint_gap_pct) < abs(fast_result.state.financial_restraint_gap_pct), "higher financial persistence delays the market-rate pass-through")


func _test_signed_supply_relief() -> void:
	var loaded: Dictionary = load_parameters()
	if not loaded.ok:
		return
	var state: Dictionary = initial_state(loaded.values).state
	var result: Dictionary = step(state, neutral_policy(state), {"supply_innovation_pct": -0.01}, loaded.values)
	expect_true(result.ok, "signed supply improvements should be valid exogenous shocks")


func _test_asset_purchases_change_financial_conditions() -> void:
	var loaded: Dictionary = load_parameters()
	if not loaded.ok:
		return
	var base: Dictionary = initial_state(loaded.values).state
	var bought: Dictionary = base.duplicate(true)
	var policy_base := neutral_policy(base)
	var policy_buy := neutral_policy(bought)
	policy_buy.asset_flow_request_pct_initial_gdp = 4.0
	var base_result: Dictionary = step(base, policy_base, {}, loaded.values)
	var buy_result: Dictionary = step(bought, policy_buy, {}, loaded.values)
	expect_true(base_result.ok and buy_result.ok, "paired asset-purchase steps are valid")
	if base_result.ok and buy_result.ok:
		expect_close(buy_result.state.asset_flow_applied_pct_initial_gdp, 2.0, "requested purchases obey quarterly flow cap")
		expect_close(buy_result.state.term_premium_pct, 0.45, "holdings lower term premium relative to start stock")
		expect_true(buy_result.state.financial_restraint_gap_pct < base_result.state.financial_restraint_gap_pct, "lower term premium reduces real borrowing restraint")


func _test_policy_impulse_and_peak() -> void:
	var params: Dictionary = load_parameters().values
	var baseline: Dictionary = initial_state(params).state
	var raised: Dictionary = initial_state(params).state
	var response: Array[float] = []
	var inflation_response: Array[float] = []
	var unemployment_response: Array[float] = []
	for q in range(240):
		var baseline_result: Dictionary = step(baseline, policy_at(3.5, baseline.guidance_rate_pct), {}, params)
		var raised_policy := policy_at(3.5, raised.guidance_rate_pct)
		if q == 0:
			raised_policy.policy_rate_request_pct = 4.25
		var raised_result: Dictionary = step(raised, raised_policy, {}, params)
		expect_true(baseline_result.ok and raised_result.ok, "paired rate-impulse paths remain in model domain")
		if not baseline_result.ok or not raised_result.ok:
			return
		baseline = baseline_result.state
		raised = raised_result.state
		response.append(raised.output_gap_pct - baseline.output_gap_pct)
		inflation_response.append(raised.annualized_quarterly_inflation_pct - baseline.annualized_quarterly_inflation_pct)
		unemployment_response.append(raised.unemployment_rate_pct - baseline.unemployment_rate_pct)
	expect_true(response[0] < 0.0, "rate surprise reduces next-quarter demand")
	expect_true(response.min() < response[0], "output response peaks after financial conditions move")
	var trough_q := response.find(response.min()) + 1
	expect_true(trough_q >= 4 and trough_q <= 8, "diagnostic output peak is delayed to the broad 1-2 year window (q%d)" % trough_q)
	var inflation_trough_q := inflation_response.find(inflation_response.min()) + 1
	expect_true(inflation_trough_q >= 2, "inflation response is delayed beyond the first output transition")
	var inflation_timing: String = "trough q%d" % inflation_trough_q if inflation_trough_q < inflation_response.size() else "still declining at q%d (trough unobserved)" % inflation_trough_q
	print("IMPULSE one-quarter rate surprise: output trough q%d (gap delta %.4f pp), quarterly-inflation %s (delta %.4f pp)" % [trough_q, response.min(), inflation_timing, inflation_response.min()])
	print("IMPULSE response at q48/q96/q240: gap=%.4f/%.4f/%.4f pp; quarterly inflation=%.4f/%.4f/%.4f pp; final levels pi=%.3f gap=%.3f" % [response[47], response[95], response[239], inflation_response[47], inflation_response[95], inflation_response[239], raised.four_quarter_inflation_pct, raised.output_gap_pct])
	expect_true(unemployment_response[0] > 0.0, "rate impulse raises unemployment after activity weakens")
	expect_true(inflation_response[0] == 0.0, "inflation does not jump with the current rate action")
	expect_true(inflation_response[1] < 0.0, "lagged resource pressure lowers later inflation")


func _test_demand_and_supply_channels() -> void:
	var params: Dictionary = load_parameters().values
	var baseline: Dictionary = initial_state(params).state
	var demand: Dictionary = initial_state(params).state
	var supply: Dictionary = initial_state(params).state
	var base_result: Dictionary = step(baseline, neutral_policy(baseline), {}, params)
	var demand_result: Dictionary = step(demand, neutral_policy(demand), {"demand_shock_pct": 1.2}, params)
	var supply_result: Dictionary = step(supply, neutral_policy(supply), {"supply_innovation_pct": 1.8}, params)
	expect_true(base_result.ok and demand_result.ok and supply_result.ok, "demand and supply pulses run")
	if not base_result.ok or not demand_result.ok or not supply_result.ok:
		return
	expect_true(demand_result.state.output_gap_pct > base_result.state.output_gap_pct, "positive demand shock lifts activity")
	expect_true(supply_result.state.annualized_quarterly_inflation_pct > base_result.state.annualized_quarterly_inflation_pct, "adverse supply shock raises inflation")
	expect_true(supply_result.state.output_gap_pct < base_result.state.output_gap_pct and supply_result.state.unemployment_rate_pct > base_result.state.unemployment_rate_pct, "adverse supply shock weakens activity and labor")
	var supply_again: Dictionary = step(supply_result.state, neutral_policy(supply_result.state), {}, params)
	expect_true(supply_again.ok and supply_again.state.supply_pressure_pct > 0.0, "policy cannot erase the persistent exogenous supply shock")
	if supply_again.ok:
		expect_true(supply_again.state.annualized_quarterly_inflation_pct > 2.0, "supply-cost effect persists into the following quarter")


func _test_expectations_and_credibility() -> void:
	var params: Dictionary = load_parameters().values
	var high: Dictionary = initial_state(params, {"credibility": 0.9}).state
	var low: Dictionary = initial_state(params, {"credibility": 0.2}).state
	var high1: Dictionary = step(high, neutral_policy(high), {"supply_innovation_pct": 1.0}, params).state
	var low1: Dictionary = step(low, neutral_policy(low), {"supply_innovation_pct": 1.0}, params).state
	var high2: Dictionary = step(high1, neutral_policy(high1), {}, params).state
	var low2: Dictionary = step(low1, neutral_policy(low1), {}, params).state
	expect_true(high1.expected_short_inflation_pct > 2.0, "short expectation reacts to temporary supply pressure")
	expect_true(high2.expected_long_inflation_pct - high.expected_long_inflation_pct < low2.expected_long_inflation_pct - low.expected_long_inflation_pct, "long expectation is more anchored at high credibility")
	var positive: Dictionary = initial_state(params, {"credibility": 0.2}).state
	var negative: Dictionary = initial_state(params, {"credibility": 0.2}).state
	positive = step(positive, policy_at(3.5, 3.5), {"supply_innovation_pct": 1.0}, params).state
	negative = step(negative, policy_at(3.5, 3.5), {"supply_innovation_pct": -1.0}, params).state
	positive = step(positive, policy_at(3.5, 3.5), {}, params).state
	negative = step(negative, policy_at(3.5, 3.5), {}, params).state
	expect_true(positive.expected_long_inflation_pct > 2.0 and negative.expected_long_inflation_pct < 2.0, "long expectations preserve both inflationary and disinflationary risk")
	var unanchored: Dictionary = initial_state(params, {"credibility": 0.0, "expected_long_inflation_pct": 2.0}).state
	for q in range(240):
		var result: Dictionary = step(unanchored, neutral_policy(unanchored), {"supply_innovation_pct": 0.01}, params)
		expect_true(result.ok, "zero-credibility long-expectation path stays finite q%d" % q)
		if not result.ok:
			return
		unanchored = result.state
		expect_true(is_finite(unanchored.expected_long_inflation_pct), "zero credibility does not create an unbounded expectation integrator")
	var missed: Dictionary = initial_state(params, {"credibility": 0.9, "annualized_quarterly_inflation_pct": 4.0}).state
	var weak: Dictionary = step(missed, policy_at(3.51, 3.51), {}, params)
	var strong: Dictionary = step(missed, policy_at(4.25, 4.25), {}, params)
	expect_true(weak.ok and strong.ok, "small and effective policy changes are valid")
	if weak.ok and strong.ok:
		expect_true(strong.state.credibility > weak.state.credibility, "effective target-consistent action earns more credibility than a 1 bp sign-only move")
	var unanchored_miss: Dictionary = initial_state(params, {"credibility": 0.25, "annualized_quarterly_inflation_pct": 4.5, "expected_short_inflation_pct": 4.8, "expected_long_inflation_pct": 3.8}).state
	var one_hike: Dictionary = step(unanchored_miss, policy_at(4.25, 4.25), {}, params)
	expect_true(one_hike.ok, "one-step unanchored-credibility impulse is valid")
	if one_hike.ok:
		expect_true(one_hike.state.expected_long_inflation_pct > 3.0 and one_hike.state.expected_long_inflation_pct - unanchored_miss.expected_long_inflation_pct < 0.1, "one policy move cannot instantly repair unanchored long expectations")
	var guide_high_base: Dictionary = initial_state(params, {"credibility": 0.9}).state
	var guide_low_base: Dictionary = initial_state(params, {"credibility": 0.2}).state
	var no_guide_high: Dictionary = step(guide_high_base, policy_at(3.5, 3.5), {}, params).state
	var no_guide_low: Dictionary = step(guide_low_base, policy_at(3.5, 3.5), {}, params).state
	var guide_high: Dictionary = step(guide_high_base, policy_at(3.5, 5.0), {}, params).state
	var guide_low: Dictionary = step(guide_low_base, policy_at(3.5, 5.0), {}, params).state
	expect_true(guide_high.long_yield_pct - no_guide_high.long_yield_pct > guide_low.long_yield_pct - no_guide_low.long_yield_pct, "guidance long-yield effect scales with credibility")


func _test_conditional_guidance() -> void:
	var params: Dictionary = load_parameters().values
	var state: Dictionary = initial_state(params).state
	var first: Dictionary = step(state, policy_at(3.5, 3.65, 0.0, 0.0, 1.5, 0.5), {"demand_shock_pct": 1.2}, params)
	expect_true(first.ok, "initial conditional guidance quote accepted")
	if not first.ok:
		return
	var changed: Dictionary = first.state
	var revised_rate: float = changed.guidance_rate_pct \
		+ changed.guidance_inflation_sensitivity * (changed.four_quarter_inflation_pct - changed.guidance_reference_inflation_pct) \
		+ changed.guidance_output_gap_sensitivity * (changed.output_gap_pct - changed.guidance_reference_output_gap_pct)
	var follows: Dictionary = step(changed, policy_at(revised_rate, revised_rate), {}, params)
	var breaks: Dictionary = step(changed, policy_at(changed.guidance_rate_pct, changed.guidance_rate_pct), {}, params)
	expect_true(follows.ok and breaks.ok, "conditional guidance allows both data-dependent and broken paths")
	if follows.ok and breaks.ok:
		expect_close(follows.state.guidance_followthrough_score, 1.0, "disclosed data revision follows conditional commitment")
		expect_true(breaks.state.guidance_followthrough_score < follows.state.guidance_followthrough_score, "unconditional deviation reduces follow-through")


func _test_liquidity_limits_and_solvency_separation() -> void:
	var params: Dictionary = load_parameters().values
	var state_off: Dictionary = initial_state(params).state
	var state_on: Dictionary = initial_state(params).state
	var funding := {"funding_need_pct_initial_gdp": 3.0, "eligible_collateral_pct_initial_gdp": 6.0, "collateral_haircut_pct": 25.0, "liquidity_eligibility_pct": 100.0, "solvency_risk_innovation_pct": 0.6}
	var off: Dictionary = step(state_off, neutral_policy(state_off), funding, params)
	var on: Dictionary = step(state_on, policy_at(3.5, 3.5, 0.0, 20.0), funding, params)
	expect_true(off.ok and on.ok, "paired liquidity support runs")
	if not off.ok or not on.ok:
		return
	expect_close(on.state.liquidity_applied_pct_initial_gdp, 3.0, "new support limited to actual funding need")
	expect_close(on.state.uncovered_funding_pct_initial_gdp, 0.0, "collateral-backed liquidity closes eligible funding need")
	expect_close(off.state.liquidity_applied_pct_initial_gdp, 0.0, "no-tool paired path provides no liquidity")
	expect_true(off.state.credit_spread_pct > on.state.credit_spread_pct, "uncovered funding need widens credit spreads")
	expect_close(off.state.solvency_risk_wedge_pct, on.state.solvency_risk_wedge_pct, "liquidity does not repair insolvency risk")
	expect_true(off.state.output_gap_pct < on.state.output_gap_pct, "uncovered funding stress weakens activity")
	var repay: Dictionary = step(on.state, neutral_policy(on.state), {}, params)
	expect_true(repay.ok, "liquidity rolls down on the next quarter")
	if repay.ok:
		expect_close(repay.state.liquidity_repayment_pct_initial_gdp, 0.45, "repayment uses disclosed fraction")
		expect_close(repay.state.outstanding_liquidity_pct_initial_gdp, 2.55, "outstanding loan declines by explicit repayment")
	var limited: Dictionary = step(state_off, policy_at(3.5, 3.5, 0.0, 20.0), {"funding_need_pct_initial_gdp": 10.0, "eligible_collateral_pct_initial_gdp": 1.0, "collateral_haircut_pct": 50.0, "liquidity_eligibility_pct": 100.0}, params)
	expect_true(limited.ok, "collateral-limited support path runs")
	if limited.ok:
		expect_close(limited.state.liquidity_applied_pct_initial_gdp, 0.5, "haircuts limit eligible lending capacity")
	var stock_override: Dictionary = initial_state(params, {"asset_stock_pct_initial_gdp": 99.0}).state
	var capped: Dictionary = step(stock_override, policy_at(3.5, 3.5, 4.0), {}, params)
	expect_true(capped.ok, "asset-stock-cap path runs")
	if capped.ok:
		expect_close(capped.state.asset_flow_applied_pct_initial_gdp, 1.0, "purchases stop at stock capacity")
		var runoff: Dictionary = step(capped.state, policy_at(capped.state.policy_rate_pct, capped.state.guidance_rate_pct, -100.0), {}, params)
		expect_true(runoff.ok, "asset runoff remains available")
		if runoff.ok:
			expect_close(runoff.state.asset_flow_applied_pct_initial_gdp, -2.0, "runoff respects flow limit")
			expect_true(runoff.state.term_premium_pct < 0.0, "term premium can cross below zero without a clamp")


func _test_public_support_recovers_without_reset() -> void:
	var params: Dictionary = load_parameters().values
	var state: Dictionary = initial_state(params, {"public_support": 63.0, "public_hardship_memory": 20.0}).state
	var first: Dictionary = step(state, neutral_policy(state), {}, params)
	expect_true(first.ok, "post-hardship recovery step runs")
	if not first.ok:
		return
	var second: Dictionary = step(first.state, neutral_policy(first.state), {}, params)
	expect_true(second.ok, "second recovery step runs")
	if second.ok:
		expect_true(second.state.public_support > first.state.public_support and second.state.public_support < 70.0, "support recovers gradually as hardship memory decays")
		expect_close(float(second.state.quarter_index), float(state.quarter_index + 2), "ordinary transitions do not reset the quarter history")


func _run_policy_path(start: Dictionary, params: Dictionary, path: Array, policy_kind: String) -> Dictionary:
	var state: Dictionary = start.duplicate(true)
	var severe := false
	var error_message := ""
	for shocks in path:
		var decision: Dictionary = model.callv("benchmark_policy", [state, params, policy_kind])
		if decision.has("error"):
			error_message = decision.error
			break
		var transition: Dictionary = step(state, decision, shocks, params)
		if not transition.ok:
			error_message = transition.error
			break
		state = transition.state
		if abs(state.four_quarter_inflation_pct - params.inflation_target_pct) > 5.0 or abs(state.output_gap_pct) > 10.0 or state.unemployment_rate_pct > 12.0 or state.public_support < 20.0 or state.solvency_risk_wedge_pct > 5.0:
			severe = true
	var failed_inflation: bool = abs(state.four_quarter_inflation_pct - params.inflation_target_pct) > 1.0
	var failed_gap: bool = abs(state.output_gap_pct) > 1.0
	var failed_unemployment: bool = state.unemployment_rate_pct > state.structural_unemployment_pct + 1.5
	return {
		"ok": error_message == "",
		"error": error_message,
		"state": state,
		"severe": severe,
		"recovered": not failed_inflation and not failed_gap and not failed_unemployment,
		"failed_inflation": failed_inflation,
		"failed_gap": failed_gap,
		"failed_unemployment": failed_unemployment,
	}


func _test_shipped_scenarios_and_seeded_robustness() -> void:
	var params: Dictionary = load_parameters().values
	var scenarios_result: Dictionary = load_scenarios()
	expect_true(scenarios_result.ok and scenarios_result.scenarios.size() == 6, "six named scenarios validate")
	if not scenarios_result.ok:
		return
	var scenarios: Dictionary = scenarios_result.scenarios
	for id in scenarios:
		var scenario: Dictionary = scenarios[id]
		var start_result: Dictionary = initial_state(params, scenario.initial)
		expect_true(start_result.ok, "%s initial state: %s" % [id, start_result.get("error", "")])
		if not start_result.ok:
			continue
		var path: Array = model.callv("seeded_shock_path", [1000, scenario, 48])
		var simulation: Dictionary = _run_policy_path(start_result.state, params, path, "feedback")
		expect_true(simulation.ok, "%s 48-quarter feedback path: %s" % [id, simulation.error])
		if simulation.ok:
			print("SCENARIO %s q48: pi=%.2f gap=%.2f u=%.2f support=%.1f severe=%s recovered=%s" % [id, simulation.state.four_quarter_inflation_pct, simulation.state.output_gap_pct, simulation.state.unemployment_rate_pct, simulation.state.public_support, simulation.severe, simulation.recovered])
	var funding_scenario: Dictionary = scenarios.funding_stress
	var replay_a: Array = model.callv("seeded_shock_path", [71, funding_scenario, 48])
	var replay_b: Array = model.callv("seeded_shock_path", [71, funding_scenario, 48])
	var different_seed: Array = model.callv("seeded_shock_path", [72, funding_scenario, 48])
	expect_true(replay_a == replay_b, "seeded exogenous path exactly replays")
	expect_true(replay_a != different_seed, "different seed changes exogenous path")
	var unanchored: Dictionary = scenarios.unanchored_inflation
	var long_initial: Dictionary = initial_state(params, unanchored.initial).state
	var long_path: Array = model.callv("seeded_shock_path", [417, unanchored, 96])
	var long_recovery: Dictionary = _run_policy_path(long_initial, params, long_path, "feedback")
	expect_true(long_recovery.ok and long_recovery.recovered, "unanchored inflation benchmark recovers within a 96-quarter horizon")
	if long_recovery.ok:
		print("LONG unanchored/feedback seed417 q96: pi=%.2f gap=%.2f u=%.2f cred=%.3f support=%.1f recovered=%s" % [long_recovery.state.four_quarter_inflation_pct, long_recovery.state.output_gap_pct, long_recovery.state.unemployment_rate_pct, long_recovery.state.credibility, long_recovery.state.public_support, long_recovery.recovered])
	var failures_by_model: Array[String] = []
	for id in ["demand_boom", "supply_shock", "funding_stress", "unanchored_inflation"]:
		var scenario: Dictionary = scenarios[id]
		var stats_by_policy := {}
		for policy_kind in ["hold", "feedback"]:
			stats_by_policy[policy_kind] = {
				"model_errors": 0, "severe": 0, "failed_recovery": 0,
				"failed_inflation": 0, "failed_gap": 0, "failed_unemployment": 0,
				"inflation_sum": 0.0, "gap_sum": 0.0, "unemployment_sum": 0.0, "support_sum": 0.0,
				"worst_miss": 0.0, "worst_seed": -1,
			}
		for seed in range(1000):
			var initial: Dictionary = initial_state(params, scenario.initial).state
			var shock_path: Array = model.callv("seeded_shock_path", [seed, scenario, 48])
			for policy_kind in ["hold", "feedback"]:
				var result: Dictionary = _run_policy_path(initial, params, shock_path, policy_kind)
				var stats: Dictionary = stats_by_policy[policy_kind]
				if not result.ok:
					stats.model_errors += 1
					stats_by_policy[policy_kind] = stats
					if failures_by_model.size() < 8:
						failures_by_model.append("%s/%s/seed%d: %s" % [id, policy_kind, seed, result.error])
					continue
				var final: Dictionary = result.state
				stats.severe += int(result.severe)
				stats.failed_recovery += int(not result.recovered)
				stats.failed_inflation += int(result.failed_inflation)
				stats.failed_gap += int(result.failed_gap)
				stats.failed_unemployment += int(result.failed_unemployment)
				stats.inflation_sum += final.four_quarter_inflation_pct
				stats.gap_sum += final.output_gap_pct
				stats.unemployment_sum += final.unemployment_rate_pct
				stats.support_sum += final.public_support
				var miss: float = abs(final.four_quarter_inflation_pct - params.inflation_target_pct)
				if miss > stats.worst_miss:
					stats.worst_miss = miss
					stats.worst_seed = seed
				stats_by_policy[policy_kind] = stats
		for policy_kind in ["hold", "feedback"]:
			var stats: Dictionary = stats_by_policy[policy_kind]
			var total_runs := 1000.0
			var mean_pi: float = stats.inflation_sum / total_runs
			var mean_gap: float = stats.gap_sum / total_runs
			var mean_u: float = stats.unemployment_sum / total_runs
			var mean_support: float = stats.support_sum / total_runs
			print("SEEDS %s/%s n=1000: severe=%d nonrecovered=%d final(pi/gap/u/support)=%.2f/%.2f/%.2f/%.1f model_errors=%d; failure_causes(pi/gap/u)=%d/%d/%d worst_abs_pi_miss=%.2f@seed%d" % [id, policy_kind, stats.severe, stats.failed_recovery, mean_pi, mean_gap, mean_u, mean_support, stats.model_errors, stats.failed_inflation, stats.failed_gap, stats.failed_unemployment, stats.worst_miss, stats.worst_seed])
	expect_true(failures_by_model.is_empty(), "seeded 48-quarter model transitions have no numerical failures: %s" % str(failures_by_model))
