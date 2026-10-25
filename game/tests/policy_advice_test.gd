extends SceneTree
const Advice = preload("res://play/policy_advice.gd")
const Career = preload("res://play/career.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func _initialize() -> void:
	var career := Career.new()
	check(career.start("base", 1).ok, "native baseline starts")
	var state: Dictionary = career.state.duplicate(true)
	var params: Dictionary = career.params.duplicate(true)
	var original := var_to_bytes([state, params])
	var base := Advice.policy(state, params)
	check(career.model._validate_policy(base, params).ok, "advice is valid native policy")
	check(base.policy_rate_request_pct == 3.5 and base.guidance_rate_pct == 3.5, "equilibrium reference is independently 1.5 plus2")
	check(base.asset_flow_request_pct_initial_gdp == 0 and base.liquidity_request_pct_initial_gdp == 0, "advice never invents one-shot offers")
	for hidden in ["r_star_pct", "expected_short_inflation_pct"]:
		var twin := state.duplicate(true)
		twin[hidden] += 1.0
		check(Advice.policy(twin, params) == base, "public advice invariant to " + hidden)
		check(career.model.benchmark_policy(twin, params).policy_rate_request_pct != career.model.benchmark_policy(state, params).policy_rate_request_pct, "oracle positive control still sensitive to " + hidden)
	var observed := Advice.observe(state)
	check(observed.size() == 3 and not observed.has("r_star_pct") and not observed.has("expected_short_inflation_pct"), "observation boundary contains only three published inputs")
	for key in Advice.OBSERVATIONS:
		var twin := state.duplicate(true)
		twin[key] = float("%.2f" % state[key]) + 0.001
		check(Advice.policy(twin, params) == base, "sub-display changes cannot alter advice for " + key)
	var slump := state.duplicate(true)
	slump.expected_long_inflation_pct = 0.0
	slump.four_quarter_inflation_pct = -5.0
	slump.output_gap_pct = -8.0
	check(Advice.policy(slump, params).policy_rate_request_pct == -13.0, "negative rates remain available without clipping")
	var tie := state.duplicate(true)
	tie.expected_long_inflation_pct = 1.5
	tie.four_quarter_inflation_pct = 0.0
	tie.output_gap_pct = -0.01
	check(Advice.policy(tie, params).policy_rate_request_pct == 0.0, "negative half-grid tie matches frozen snapped quote semantics")
	for bad in [NAN, INF, true, "2.00"]:
		for key in Advice.OBSERVATIONS:
			var broken := state.duplicate(true)
			broken[key] = bad
			check(not Advice.policy(broken, params).get("ok", true), "invalid visible observation fails closed")
	for key in Advice.DESIGN_INPUTS:
		var broken := params.duplicate(true)
		broken[key] = NAN
		check(not Advice.policy(state, broken).get("ok", true), "nonfinite design input rejected")
	var zero := params.duplicate(true)
	zero.minimum_rate_increment_pct = 0.0
	check(not Advice.policy(state, zero).get("ok", true), "zero quote increment rejected")
	var overflow := slump.duplicate(true)
	overflow.four_quarter_inflation_pct = 1e308
	overflow.output_gap_pct = 1e308
	check(not Advice.policy(overflow, params).get("ok", true), "finite input with unrepresentable advice rejected")
	var extra := observed.duplicate(true)
	extra.r_star_pct = 1.5
	check(not Advice.from_observation(extra, params).get("ok", true), "explicit observer rejects extra latent field")
	check(var_to_bytes([state, params]) == original, "advice leaves all caller inputs unchanged")
	print("%s: public policy advice %d checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
