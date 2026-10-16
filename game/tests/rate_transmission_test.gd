extends SceneTree

const Economy = preload("res://model/economy.gd")
var model := Economy.new()
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func close(actual: float, expected: float, message: String) -> void:
	check(is_finite(actual) and abs(actual - expected) < 1e-8, "%s: got %.10f, expected %.10f" % [message, actual, expected])

func policy(rate: float, guidance: float) -> Dictionary:
	return {"policy_rate_request_pct":rate,"guidance_rate_pct":guidance,
		"guidance_inflation_sensitivity":1.5,"guidance_output_gap_sensitivity":0.5,
		"asset_flow_request_pct_initial_gdp":0.0,"liquidity_request_pct_initial_gdp":0.0}

func _initialize() -> void:
	var params: Dictionary = model.load_parameters().values
	var state: Dictionary = model.initial_state(params).state
	var preserved := state.duplicate(true)
	var negative: Dictionary = model.step(state, policy(-0.5, -0.75), {}, params)
	check(negative.ok, "negative nominal rate and guidance are admissible")
	if negative.ok:
		close(negative.state.policy_rate_pct, -0.5, "negative request applies fully without a ramp cap")
	var large: Dictionary = model.step(state, policy(25.0, 30.0), {}, params)
	check(large.ok, "positive nominal rates and guidance have no arbitrary ceiling")
	if large.ok:
		close(large.state.policy_rate_pct, 25.0, "large positive rate request applies fully")
	for quote in [-0.01, 0.0, 0.01, 3.51]:
		check(model.step(state, policy(quote, quote), {}, params).ok, "one-basis-point quote grid accepts both signs")
	check(not model.step(state, policy(3.501, 3.5), {}, params).ok, "sub-basis-point rate quote is rejected")
	check(not model.step(state, policy(3.5, 3.501), {}, params).ok, "sub-basis-point guidance quote is rejected")
	var invalid_initial := params.duplicate(true)
	invalid_initial.initial_policy_rate_pct = 3.501
	check(not model.initial_state(invalid_initial, {"policy_rate_pct":0.0}).ok, "a scenario override cannot conceal an off-grid initial-rate parameter")
	check(state.has("effective_policy_rate_pct") and state.has("stance_best_feasible_distance_pct") and state.has("stance_adequacy_score"), "state exposes effective transmission and feasible-stance diagnostics")
	check(params.has("negative_rate_efficacy_scale_pct") and params.has("minimum_rate_increment_pct"), "rate efficacy and quoting increment are disclosed assumptions")
	check(model.has_method("conditional_commitment"), "conditional promises use the same admissible nominal quote grid")
	if params.has("negative_rate_efficacy_scale_pct") and state.has("stance_adequacy_score"):
		_test_transmission(params, state)
		_test_stance(params)
		_test_current_credit(params)
		if model.has_method("conditional_commitment"):
			var announcement: Dictionary = model.step(state, policy(3.5, 3.65), {"demand_shock_pct":1.2}, params)
			var raw: float = announcement.state.guidance_rate_pct + announcement.state.guidance_inflation_sensitivity * (announcement.state.four_quarter_inflation_pct - announcement.state.guidance_reference_inflation_pct) + announcement.state.guidance_output_gap_sensitivity * (announcement.state.output_gap_pct - announcement.state.guidance_reference_output_gap_pct)
			var quoted: float = model.conditional_commitment(announcement.state, params)
			close(quoted, roundf(raw / params.minimum_rate_increment_pct) * params.minimum_rate_increment_pct, "conditional data response is rounded only to the quoted grid")
			var delivered: Dictionary = model.step(announcement.state, policy(quoted, quoted), {}, params)
			check(delivered.ok, "data-dependent guidance produces an admissible next decision")
			if delivered.ok:
				close(delivered.state.guidance_followthrough_score, 1.0, "delivering the conditional quoted promise receives full follow-through")
	check(state == preserved, "accepted and rejected rate experiments preserve their input")
	for failure in failures:
		printerr("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: unrestricted signed nominal quotes, 1bp grid, diminishing efficacy and effective feasible stance")
	quit(0 if failures.is_empty() else 1)

func _test_transmission(params: Dictionary, state: Dictionary) -> void:
	var effective: Array[float] = []
	for rate in [-3.0, -2.0, -1.0, -0.5, -0.25, 0.0, 0.25, 3.5]:
		var result: Dictionary = model.step(state, policy(rate, rate), {}, params)
		check(result.ok, "signed transmission path remains valid")
		if not result.ok:
			return
		var expected: float = rate if rate >= 0.0 else params.negative_rate_efficacy_scale_pct * tanh(rate / params.negative_rate_efficacy_scale_pct)
		close(result.state.effective_policy_rate_pct, expected, "effective rate follows the disclosed smooth negative channel")
		close(result.state.long_yield_pct, expected + params.initial_term_premium_pct, "credible equal guidance shares the same effective rate")
		effective.append(result.state.effective_policy_rate_pct)
	for i in range(1, effective.size()):
		check(effective[i] > effective[i - 1], "effective transmission remains monotone through zero")
	check(effective[1] - effective[0] < effective[3] - effective[2], "deep negative cuts have diminishing marginal financing benefits")
	var no_trust := state.duplicate(true)
	no_trust.credibility = 0.0
	var promised: Dictionary = model.step(no_trust, policy(0.0, -1.0), {}, params)
	var unchanged: Dictionary = model.step(no_trust, policy(0.0, 0.0), {}, params)
	close(promised.state.long_yield_pct, unchanged.state.long_yield_pct, "untrusted negative guidance does not manufacture financing relief")
	for requested in [-3.505, 3.505]:
		var midpoint: Dictionary = model.initial_state(params, {"r_star_pct":requested - params.inflation_target_pct}).state
		var quoted: Dictionary = model.benchmark_policy(midpoint, params, "neutral")
		close(quoted.policy_rate_request_pct, -3.51 if requested < 0.0 else 3.51, "benchmark half-step rounding is symmetric away from zero")

func _test_current_credit(params: Dictionary) -> void:
	var state: Dictionary = model.initial_state(params).state
	var benchmark: Dictionary = model.benchmark_policy(state, params)
	close(benchmark.policy_rate_request_pct, 3.5, "opening benchmark does not directly adjust for the current credit innovation")
	var alternate := benchmark.duplicate(true)
	alternate.policy_rate_request_pct = 2.5
	alternate.guidance_rate_pct = 2.5
	var shocks := {"credit_risk_innovation_pct":1.0}
	var preserved := var_to_bytes([state, benchmark, alternate, shocks, params])
	var baseline: Dictionary = model.step(state, benchmark, shocks, params)
	var compensated: Dictionary = model.step(state, alternate, shocks, params)
	check(baseline.ok and compensated.ok, "both current-credit choices are valid with identical other controls")
	check(var_to_bytes([state, benchmark, alternate, shocks, params]) == preserved, "current-credit comparison preserves state, policies, shocks and parameters")
	if not baseline.ok or not compensated.ok:
		return
	close(baseline.state.spot_financial_gap_pct, 1.0, "benchmark leaves one point of current spot restraint")
	close(compensated.state.spot_financial_gap_pct, 0.0, "lower equal rate and guidance offset current credit restraint")
	var adequacy: float = exp(-1.0 / params.credibility_stance_scale_pct)
	close(baseline.state.stance_adequacy_score, adequacy, "benchmark stance score includes the current spread")
	close(compensated.state.stance_adequacy_score, 1.0, "compensated first-step stance is adequate")
	var credibility_delta: float = params.credibility_adjustment * 0.4 * (1.0 - adequacy)
	close(compensated.state.credibility - baseline.state.credibility, credibility_delta, "current stance changes first-step credibility without claiming whole-career superiority")

func _test_stance(params: Dictionary) -> void:
	var neutral: Dictionary = model.initial_state(params).state
	var balanced: Dictionary = model.step(neutral, policy(3.5, 3.5), {}, params)
	close(balanced.state.stance_adequacy_score, 1.0, "attainable neutral equilibrium has full stance adequacy")
	var deflation: Dictionary = model.initial_state(params, {"annualized_quarterly_inflation_pct":-4.0,"expected_short_inflation_pct":-4.0,"expected_long_inflation_pct":-4.0}).state
	var first: Dictionary = model.step(deflation, policy(-30.0, -30.0), {}, params)
	var deeper: Dictionary = model.step(deflation, policy(-40.0, -40.0), {}, params)
	check(first.ok and deeper.ok, "unattainable-restraint diagnostics accept deep nominal choices")
	if first.ok and deeper.ok:
		close(first.state.stance_adequacy_score, deeper.state.stance_adequacy_score, "equivalent effective restraint has equivalent adequacy despite nominal alignment")
		check(first.state.stance_best_feasible_distance_pct > 0.0 and first.state.stance_adequacy_score < 0.2, "constrained best effort is not falsely scored as fully adequate")
		close(first.state.stance_adequacy_score, params.credibility_stance_scale_pct / (params.credibility_stance_scale_pct + first.state.stance_best_feasible_distance_pct), "asymptotic best effort retains the economic shortfall penalty")
	var zero_loading := params.duplicate(true)
	zero_loading.real_rate_short_weight = 0.0
	zero_loading.long_yield_current_rate_weight = 0.0
	var trusted: Dictionary = model.initial_state(zero_loading, {"credibility":1.0,"annualized_quarterly_inflation_pct":4.0,"expected_short_inflation_pct":4.0,"expected_long_inflation_pct":4.0}).state
	var high: Dictionary = model.step(trusted, policy(25.0, 3.5), {}, zero_loading)
	var low: Dictionary = model.step(trusted, policy(-25.0, 3.5), {}, zero_loading)
	check(high.ok and low.ok, "zero current-rate loading endpoint is admissible")
	if high.ok and low.ok:
		close(high.state.stance_adequacy_score, low.state.stance_adequacy_score, "fixed credible guidance gives identical feasible stance when the current-rate loading vanishes")
		close(high.state.stance_distance_pct, high.state.stance_best_feasible_distance_pct, "zero-loading feasible set is a point, not an unlimited positive interval")
	var pledged: Dictionary = model.step(neutral, policy(3.5, -30.0), {}, params)
	var broken: Dictionary = model.step(pledged.state, policy(0.0, 0.0), {}, params)
	check(broken.ok and broken.state.guidance_followthrough_score < 0.001, "nominal promises remain accountable despite effective-rate saturation")
