extends SceneTree

const Economy = preload("res://model/economy.gd")
var model := Economy.new()
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func ledger(s: Dictionary) -> float:
	var assets: float = s.mbs_stock_pct_initial_gdp + s.outstanding_liquidity_pct_initial_gdp
	for cohorts in [s.treasury_cohorts_pct_initial_gdp, s.bill_cohorts_pct_initial_gdp]:
		for principal in cohorts:
			assets += float(principal)
	return assets \
		- s.reserves_pct_initial_gdp - s.reverse_repo_pct_initial_gdp \
		- s.currency_pct_initial_gdp - s.treasury_account_pct_initial_gdp - s.capital_other_pct_initial_gdp

func _initialize() -> void:
	var params: Dictionary = model.load_parameters().values
	var initial: Dictionary = model.initial_state(params, {"credibility":0.2, "output_gap_pct":-3.0,
		"annualized_quarterly_inflation_pct":1.0, "expected_short_inflation_pct":1.3,
		"expected_long_inflation_pct":1.7, "unemployment_rate_pct":6.5})
	check(initial.ok, "compound opening is valid")
	if initial.ok:
		var state: Dictionary = initial.state
		var policy: Dictionary = model.benchmark_policy(state, params)
		policy.maintain_ample_reserves = true
		var shock := {"funding_need_pct_initial_gdp":3.0, "eligible_collateral_pct_initial_gdp":6.0,
			"collateral_haircut_pct":25.0, "liquidity_eligibility_pct":100.0,
			"supply_innovation_pct":0.35, "solvency_risk_innovation_pct":0.6}
		var preserved := var_to_bytes([state, params, policy, shock])
		var offered: Dictionary = policy.duplicate(true)
		offered.liquidity_request_pct_initial_gdp = 3.0
		var offer_before := var_to_bytes(offered)
		var control: Dictionary = model.step(state, policy, shock, params)
		var treatment: Dictionary = model.step(state, offered, shock, params)
		check(control.ok and treatment.ok, "matched compound transitions succeed")
		check(var_to_bytes([state, params, policy, shock]) == preserved
			and var_to_bytes(offered) == offer_before, "both transitions preserve every input")
		if control.ok and treatment.ok:
			var a: Dictionary = control.state
			var b: Dictionary = treatment.state
			check(b.liquidity_local_applied_pct_initial_gdp == 3.0
				and b.liquidity_applied_pct_initial_gdp == 3.0
				and b.outstanding_liquidity_pct_initial_gdp == 3.0
				and b.liquidity_aggregate_applied_pct_initial_gdp == 0.0
				and a.liquidity_applied_pct_initial_gdp == 0.0
				and a.outstanding_liquidity_pct_initial_gdp == 0.0
				and a.uncovered_funding_pct_initial_gdp == 3.0
				and b.uncovered_funding_pct_initial_gdp == 0.0, "eligible lending covers exactly the local need")
			for key in ["supply_pressure_pct", "solvency_risk_wedge_pct", "price_index",
				"annualized_quarterly_inflation_pct", "four_quarter_inflation_pct"]:
				check(a[key] == b[key], "lending does not directly change " + key)
			check(state.deferred_demand_pct == 0.0 and a.reserve_scarcity_wedge_pct == 0.0
				and b.reserve_scarcity_wedge_pct == 0.0, "analytic oracle has zero backlog and ample reserves")
			var spread_relief: float = params.funding_spread_sensitivity * 3.0
			var gap_relief: float = params.real_rate_output_sensitivity \
				* (1.0 - params.real_rate_gap_persistence) * spread_relief
			check(abs(spread_relief - 0.6) < 1e-10 and abs(gap_relief - 0.0108) < 1e-10,
				"current calibration retains the frozen compound-response magnitudes")
			check(abs(a.credit_spread_pct - b.credit_spread_pct - spread_relief) < 1e-10,
				"local credit-spread relief matches the disclosed equation")
			check(gap_relief > 0.0 and abs(b.output_gap_pct - a.output_gap_pct - gap_relief) < 1e-10,
				"demand relief matches its lagged analytic oracle, not a cash bonus")
			check(abs(ledger(a)) < 1e-7 and abs(ledger(b)) < 1e-7,
				"both principal ledgers independently reconcile")
			var replay_a: Dictionary = model.step(state, policy, shock, params)
			var replay_b: Dictionary = model.step(state, offered, shock, params)
			check(replay_a.ok and replay_b.ok and replay_a.state == a
				and replay_b.state == b, "exact paired replay")
		for boundary in [{"liquidity_eligibility_pct":0.0}, {"liquidity_eligibility_pct":50.0},
			{"eligible_collateral_pct_initial_gdp":0.0}, {"eligible_collateral_pct_initial_gdp":2.0},
			{"collateral_haircut_pct":100.0}]:
			var constrained := shock.duplicate(true)
			constrained.merge(boundary, true)
			var before := var_to_bytes(constrained)
			var result: Dictionary = model.step(state, offered, constrained, params)
			check(result.ok, "physical funding boundary is valid: %s" % boundary)
			if result.ok:
				var capacity: float = constrained.eligible_collateral_pct_initial_gdp \
					* (1.0 - constrained.collateral_haircut_pct / 100.0) \
					* constrained.liquidity_eligibility_pct / 100.0
				var expected: float = minf(3.0 * constrained.liquidity_eligibility_pct / 100.0, capacity)
				check(result.state.liquidity_local_applied_pct_initial_gdp == expected
					and result.state.liquidity_applied_pct_initial_gdp == expected
					and result.state.outstanding_liquidity_pct_initial_gdp == expected
					and result.state.liquidity_aggregate_applied_pct_initial_gdp == 0.0
					and result.state.uncovered_funding_pct_initial_gdp == 3.0 - expected
					and abs(ledger(result.state)) < 1e-7, "constraints limit lending without breaking the ledger")
			check(var_to_bytes(constrained) == before, "boundary shock is unchanged")
		for invalid in [{"liquidity_eligibility_pct":101.0}, {"eligible_collateral_pct_initial_gdp":-1.0}]:
			var bad := shock.duplicate(true)
			bad.merge(invalid, true)
			var before := var_to_bytes(bad)
			check(not model.step(state, offered, bad, params).ok, "out-of-domain funding rejects: %s" % invalid)
			check(var_to_bytes(bad) == before, "rejected shock is unchanged")
		check(var_to_bytes([state, params, policy, shock]) == preserved
			and var_to_bytes(offered) == offer_before, "all boundary and rejection paths preserve original inputs")
	for failure in failures:
		printerr("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: compound low-trust lending separates funding, supply, solvency and lagged demand")
	quit(0 if failures.is_empty() else 1)
