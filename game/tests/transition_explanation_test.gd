extends SceneTree

var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var helper = load("res://play/transition_explanation.gd")
	check(helper != null, "completed-path explanation helper exists")
	if helper == null:
		quit(1)
		return
	var model = load("res://model/economy.gd").new()
	var params: Dictionary = model.load_parameters().values
	var before: Dictionary = model.initial_state(params).state
	var after := before.duplicate(true)
	after.quarter_index = 1
	before.output_gap_pct = -1.0
	before.deferred_demand_pct = 2.0
	after.financial_restraint_gap_pct = 1.0
	after.supply_pressure_pct = 0.5
	after.output_gap_pct = -0.5171428571428571
	after.deferred_demand_pct = 1.8611428571428572
	after.demand_release_pct = 0.18285714285714286
	# Keep the separate price/output identities consistent with this hand fixture.
	var price_base: float = 0.6 * (1 + before.annualized_quarterly_inflation_pct / 100) + 0.4 * (1 + before.expected_short_inflation_pct / 100)
	after.price_index = before.price_index * pow(price_base * exp((0.08 * before.output_gap_pct + 0.2 * after.supply_pressure_pct) / 102), 0.25)
	before.actual_output_index = before.potential_output_index * 0.99
	after.actual_output_index = after.potential_output_index * (1 + after.output_gap_pct / 100)
	var frozen := var_to_bytes([before, after, params])
	var result: Dictionary = helper.explain(before, after, {"demand_shock_pct": 0.2}, params)
	check(result.ok, "first independent hand example reconstructs gap, backlog, prices and output")
	if result.ok:
		for index in range(5):
			check(abs(result.terms[index] - [0.28, -0.12, 0.2, -0.06, 0.18285714285714286][index]) < 1e-12, "hand term %d" % index)
		check(abs(result.change - 0.48285714285714286) < 1e-12, "first gap change is not a policy counterfactual")
		check(abs(result.backlog_change + 0.13885714285714286) < 1e-12, "backlog cancellation and release reconcile")
	check(var_to_bytes([before, after, params]) == frozen, "explanation does not mutate inputs")
	var second_before := before.duplicate(true)
	var second_after := after.duplicate(true)
	second_before.output_gap_pct = 1.0
	# Positive root of .2 B² + .368125 B - .159375 = 0 gives release .03.
	second_before.deferred_demand_pct = (-0.368125 + sqrt(pow(0.368125, 2) + 0.1275)) / 0.4
	second_before.actual_output_index = second_before.potential_output_index * 1.01
	second_after.financial_restraint_gap_pct = 0.5
	second_after.supply_pressure_pct = 0.1
	second_after.demand_release_pct = 0.03
	second_after.output_gap_pct = 0.878
	second_after.deferred_demand_pct = 0.98 * second_before.deferred_demand_pct - 0.12 * 0.848 - 0.03
	second_after.actual_output_index = second_after.potential_output_index * 1.00878
	second_after.price_index = second_before.price_index * pow(price_base * exp(0.1 / 102), 0.25)
	var second: Dictionary = helper.explain(second_before, second_after, {"demand_shock_pct": 0.2}, params)
	var independent_terms := [-0.28, -0.06, 0.2, -0.012, 0.03]
	check(second.ok and abs(second.change + 0.122) < 1e-12, "second independent gap oracle reconstructs -.122 pp")
	if second.ok:
		for index in range(5):
			check(abs(second.terms[index] - independent_terms[index]) < 1e-12, "second hand term %d" % index)
	var chain: Array = [before, after]
	var next := after.duplicate(true)
	next.quarter_index = 2
	var available: float = after.deferred_demand_pct * after.potential_output_index / next.potential_output_index
	var next_fraction: float = (0.08 + 0.12 * abs(available) / (5 + abs(available))) / (1 + pow(1.0 / 2, 2))
	var next_release: float = next_fraction * available
	var next_underlying: float = 0.72 * after.output_gap_pct - 0.12 + 0.1 - 0.06
	next.output_gap_pct = next_underlying + next_release
	next.demand_release_pct = next_release
	next.deferred_demand_pct = 0.98 * available - 0.12 * next_underlying - next_release
	next.actual_output_index = next.potential_output_index * (1 + next.output_gap_pct / 100)
	next.price_index = after.price_index * pow(price_base * exp((0.08 * after.output_gap_pct + 0.1) / 102), 0.25)
	chain.append(next)
	var combined: Dictionary = helper.segment(chain, [{"demand_shock_pct": 0.2}, {"demand_shock_pct": 0.1}], 0, 2, params)
	check(combined.ok and abs(combined.change - (next.output_gap_pct - before.output_gap_pct)) < 1e-12, "two connected transitions telescope over the whole segment")
	var later_chain := chain.duplicate(true)
	for index in range(later_chain.size()):
		later_chain[index].quarter_index = index + 37
	var later: Dictionary = helper.segment(later_chain, [{"demand_shock_pct": 0.2}, {"demand_shock_pct": 0.1}], 0, 2, params)
	check(later.ok and later.text.begins_with("Q38–Q39 ") and later.terms == combined.terms, "detached late segment preserves actual quarter labels and equation contributions")
	var wrong_quarter := after.duplicate(true)
	wrong_quarter.quarter_index = 7
	check(not helper.explain(before, wrong_quarter, {"demand_shock_pct": 0.2}, params).ok, "explanation rejects nonadjacent completed quarters")
	check(not helper.segment(chain, [{}, {}], 2, 1, params).ok, "invalid completed interval is rejected")
	var scaled_before := before.duplicate(true)
	var scaled_after := after.duplicate(true)
	scaled_before.actual_output_index *= 2
	scaled_after.actual_output_index *= 2
	check(not helper.explain(scaled_before, scaled_after, {"demand_shock_pct": 0.2}, params).ok, "matching output ratios cannot conceal invalid output levels")
	var rounding_chain: Array = [model.initial_state(params).state]
	var rounding_shocks: Array = [{}, {}, {}, {}]
	for index in range(4):
		var prior: Dictionary = rounding_chain[-1]
		var rounded := prior.duplicate(true)
		rounded.quarter_index = prior.quarter_index + 1
		var demand: float = prior.deferred_demand_pct
		var fraction: float = 0.08 + 0.12 * abs(demand) / (5 + abs(demand))
		var released: float = fraction * demand
		var underlying: float = 0.72 * prior.output_gap_pct
		rounded.output_gap_pct = underlying + released + 9e-10
		rounded.demand_release_pct = released
		rounded.deferred_demand_pct = 0.98 * demand - 0.12 * underlying - released
		rounded.actual_output_index = rounded.potential_output_index * (1 + rounded.output_gap_pct / 100)
		rounded.price_index = prior.price_index * pow(price_base * exp(0.08 * prior.output_gap_pct / 102), 0.25)
		check(helper.explain(prior, rounded, {}, params).ok, "small individual reconstruction residual remains within its tolerance")
		rounding_chain.append(rounded)
	check(not helper.segment(rounding_chain, rounding_shocks, 0, 4, params).ok, "individually small residuals cannot conceal a segment mismatch")
	var corrupt := after.duplicate(true)
	corrupt.output_gap_pct += 0.01
	check(not helper.explain(before, corrupt, {"demand_shock_pct": 0.2}, params).ok, "wrong completed gap fails closed")
	check(not helper.explain(before, after, {"demand_shock_pct": -0.2}, params).ok, "next-meeting shock cannot explain completed transition")
	corrupt = after.duplicate(true)
	corrupt.price_index = NAN
	check(not helper.explain(before, corrupt, {}, params).ok, "nonfinite input cannot produce a trusted explanation")
	corrupt = after.duplicate(true)
	corrupt.erase("deferred_demand_pct")
	check(not helper.explain(before, corrupt, {}, params).ok, "missing state is not guessed")
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() == 2 and arguments[0] == "--native-records":
		var successful := 0
		for line in FileAccess.get_file_as_string(arguments[1]).split("\n"):
			if not line.begins_with("NATIVE_CALL: "):
				continue
			var record: Dictionary = bytes_to_var(line.trim_prefix("NATIVE_CALL: ").hex_decode())
			if record.result.ok:
				var native_before: Dictionary = bytes_to_var(record.before)
				check(helper.explain(native_before, record.result.state, record.shock, params).ok, "retained native completed transition reconciles: " + record.context)
				successful += 1
		check(successful == 16, "Gate0 contains all sixteen confirmed native transitions")
	print("%s: transition explanation %d checks, %d failures; zero native transitions" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
