extends SceneTree

const Economy = preload("res://model/economy.gd")
const SETTLEMENTS := 12
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

func finite_state(state: Dictionary) -> bool:
	for key in state:
		var values: Array = state[key] if typeof(state[key]) == TYPE_ARRAY else [state[key]]
		for value in values:
			if typeof(value) in [TYPE_INT, TYPE_FLOAT] and not is_finite(float(value)):
				return false
	return true

func checked_step(state: Dictionary, policy: Dictionary, shock: Dictionary,
		params: Dictionary, label: String) -> Dictionary:
	var preserved := var_to_bytes([state, policy, shock, params])
	var result: Dictionary = model.step(state, policy, shock, params)
	check(result.ok, "%s: unexpected transition status: %s" % [label, result.get("error", "")])
	check(var_to_bytes([state, policy, shock, params]) == preserved, label + ": every input is unchanged")
	var recorded := var_to_bytes(result)
	var replay: Dictionary = model.step(state, policy, shock, params)
	check(var_to_bytes(result) == recorded and var_to_bytes(replay) == recorded,
		label + ": exact state and trace replay")
	check(var_to_bytes([state, policy, shock, params]) == preserved,
		label + ": replay preserves every input")
	if result.ok:
		var next: Dictionary = result.state
		check(finite_state(next), label + ": all scalar and array state values are finite")
		check(next.quarter_index == state.quarter_index + 1, label + ": one settlement advances one quarter")
		check(abs(ledger(next)) < 1e-7, label + ": independent cohort principal ledger reconciles")
		check(next.capital_other_pct_initial_gdp == state.capital_other_pct_initial_gdp,
			label + ": capital residual is not reset")
		check(next.liquidity_repayment_pct_initial_gdp == state.outstanding_liquidity_pct_initial_gdp,
			label + ": all prior loan principal matures")
		check(next.outstanding_liquidity_pct_initial_gdp == next.liquidity_applied_pct_initial_gdp
			and next.liquidity_applied_pct_initial_gdp == next.liquidity_local_applied_pct_initial_gdp
				+ next.liquidity_aggregate_applied_pct_initial_gdp,
			label + ": ending loans are fresh advances, not accumulated turnover")
		var asset_change: float = next.asset_stock_pct_initial_gdp - state.asset_stock_pct_initial_gdp \
			+ next.liquidity_applied_pct_initial_gdp - state.outstanding_liquidity_pct_initial_gdp
		check(abs(next.total_asset_change_pct_initial_gdp - asset_change) < 1e-7
			and abs(next.total_assets_pct_initial_gdp - state.total_assets_pct_initial_gdp - asset_change) < 1e-7,
			label + ": securities change, old repayment and fresh lending remain separate")
		var n: float = (state.actual_output_index / state.initial_actual_output_index) \
			* (state.price_index / state.initial_price_index)
		var currency_change: float = params.initial_currency_pct_initial_gdp * n - state.currency_pct_initial_gdp
		var reserves: float = state.reserves_pct_initial_gdp + state.reverse_repo_pct_initial_gdp \
			- next.reverse_repo_pct_initial_gdp + next.discretionary_purchase_pct_initial_gdp \
			- next.principal_runoff_pct_initial_gdp - state.outstanding_liquidity_pct_initial_gdp \
			+ next.liquidity_applied_pct_initial_gdp - currency_change \
			+ next.reserve_maintenance_purchase_pct_initial_gdp
		check(abs(next.reserves_pct_initial_gdp - reserves) < 1e-7
			and next.decision_nominal_gdp_ratio == n, label + ": reserve settlement uses meeting GDP and net principal")
		check(next.supply_pressure_pct == params.supply_pressure_persistence * state.supply_pressure_pct
				+ shock.get("supply_innovation_pct", 0.0)
			and next.solvency_risk_wedge_pct == params.solvency_risk_persistence * state.solvency_risk_wedge_pct
				+ shock.get("solvency_risk_innovation_pct", 0.0),
			label + ": policy cannot rewrite exogenous supply or solvency recurrences")
	return result

func check_local_lending(before: Dictionary, after: Dictionary, policy: Dictionary,
		shock: Dictionary, params: Dictionary, label: String) -> void:
	# These fixtures exclude aggregate advances: maintenance is on, or the offer is zero.
	var new_need: float = shock.get("funding_need_pct_initial_gdp", 0.0)
	var refinancing: float = minf(shock.get("refinancing_need_pct_initial_gdp", 0.0),
		before.outstanding_liquidity_pct_initial_gdp)
	var eligibility: float = shock.get("liquidity_eligibility_pct", 0.0) / 100.0
	var capacity: float = shock.get("eligible_collateral_pct_initial_gdp", 0.0) \
		* (1.0 - shock.get("collateral_haircut_pct", 0.0) / 100.0) * eligibility
	var eligible_need: float = (refinancing + new_need) * eligibility
	var local: float = minf(policy.liquidity_request_pct_initial_gdp, minf(capacity, eligible_need))
	var renewed: float = minf(local, refinancing * eligibility)
	var fresh: float = local - renewed
	var uncovered: float = refinancing - renewed + new_need - fresh
	check(after.refinancing_request_pct_initial_gdp == shock.get("refinancing_need_pct_initial_gdp", 0.0)
		and after.refinancing_need_pct_initial_gdp == refinancing
		and after.lending_collateral_capacity_pct_initial_gdp == capacity,
		label + ": requested refinancing is capped at actual maturing principal")
	check(after.liquidity_local_applied_pct_initial_gdp == local
		and after.liquidity_refinancing_applied_pct_initial_gdp == renewed
		and after.liquidity_new_need_applied_pct_initial_gdp == fresh
		and after.liquidity_aggregate_applied_pct_initial_gdp == 0.0
		and after.outstanding_liquidity_pct_initial_gdp == local,
		label + ": collateral and eligibility bound concurrent lending; refinancing is served first")
	check(after.uncovered_refinancing_pct_initial_gdp == refinancing - renewed
		and after.uncovered_new_funding_pct_initial_gdp == new_need - fresh
		and after.uncovered_funding_pct_initial_gdp == uncovered
		and abs(after.local_access_wedge_pct - params.funding_spread_sensitivity * uncovered) < 1e-10,
		label + ": uncovered old and new needs drive only the local access wedge")
	check(after.liquidity_collateral_binding == float(local < eligible_need and local == capacity)
		and after.liquidity_eligibility_binding == float(eligibility < 1.0 and (new_need > 0.0 or refinancing > 0.0)),
		label + ": collateral and eligibility binding diagnostics agree with physical inputs")

func test_sustained_lending(initial: Dictionary, params: Dictionary, policy: Dictionary, shock: Dictionary) -> void:
	var control := initial.duplicate(true)
	var treatment := initial.duplicate(true)
	for q in range(SETTLEMENTS):
		var current := shock.duplicate(true)
		current.refinancing_need_pct_initial_gdp = 6.0
		match q:
			3: current.liquidity_eligibility_pct = 50.0
			4: current.eligible_collateral_pct_initial_gdp = 2.0
			5: current.liquidity_eligibility_pct = 0.0
			7: current.refinancing_need_pct_initial_gdp = 0.0
			8: current.eligible_collateral_pct_initial_gdp = 0.0
			9: current.collateral_haircut_pct = 100.0
		var offered := policy.duplicate(true)
		offered.liquidity_request_pct_initial_gdp = 0.0 if q == SETTLEMENTS - 1 else 4.5
		var a := checked_step(control, policy, current, params, "control Q%d" % (q + 1))
		var b := checked_step(treatment, offered, current, params, "lending Q%d" % (q + 1))
		if not a.ok or not b.ok:
			return
		check_local_lending(control, a.state, policy, current, params, "control Q%d" % (q + 1))
		check_local_lending(treatment, b.state, offered, current, params, "lending Q%d" % (q + 1))
		control = a.state
		treatment = b.state
		check(control.supply_pressure_pct == treatment.supply_pressure_pct
			and control.solvency_risk_wedge_pct == treatment.solvency_risk_wedge_pct,
			"Q%d: identical shocks retain identical exogenous mechanisms" % (q + 1))
		check(control.policy_rate_pct == treatment.policy_rate_pct
			and control.guidance_rate_pct == treatment.guidance_rate_pct
			and control.reserve_scarcity_wedge_pct == 0.0 and treatment.reserve_scarcity_wedge_pct == 0.0,
			"Q%d: matched rate/guidance isolate local lending from aggregate scarcity" % (q + 1))
		var spread_difference: float = params.funding_spread_sensitivity \
			* (control.uncovered_funding_pct_initial_gdp - treatment.uncovered_funding_pct_initial_gdp)
		check(abs(control.credit_spread_pct - treatment.credit_spread_pct - spread_difference) < 1e-10,
			"Q%d: spread differences follow uncovered need, including failed renewal" % (q + 1))
		check(abs(control.term_premium_pct - initial.term_premium_pct) < 1e-10
			and abs(treatment.term_premium_pct - initial.term_premium_pct) < 1e-10,
			"Q%d: lending and maintenance bills do not create duration easing" % (q + 1))
		if q == 1:
			check(treatment.liquidity_repayment_pct_initial_gdp == 3.0
				and treatment.liquidity_refinancing_applied_pct_initial_gdp == 3.0
				and treatment.liquidity_new_need_applied_pct_initial_gdp == 1.5
				and treatment.outstanding_liquidity_pct_initial_gdp == 4.5,
				"Q2: repayment, renewal and fresh funding coexist without accumulating old principal")
		if q == 3:
			check(treatment.credit_spread_pct > control.credit_spread_pct,
				"Q4: restricted renewal can leave more uncovered need than the no-facility path")
		if q == 7:
			check(treatment.liquidity_repayment_pct_initial_gdp == 3.0
				and treatment.liquidity_refinancing_applied_pct_initial_gdp == 0.0
				and treatment.liquidity_new_need_applied_pct_initial_gdp == 3.0,
				"Q8: zero refinancing demand separates externally funded repayment from new lending")
	check(control.quarter_index == initial.quarter_index + SETTLEMENTS
		and treatment.quarter_index == initial.quarter_index + SETTLEMENTS
		and treatment.liquidity_repayment_pct_initial_gdp == 3.0
		and treatment.outstanding_liquidity_pct_initial_gdp == 0.0,
		"twelve settlements finish with full repayment and no advance after withdrawal")

func test_sterilized_purchase(initial: Dictionary, params: Dictionary, policy: Dictionary, shock: Dictionary) -> void:
	# Transfer liabilities within a copied opening ledger; coefficients and capital stay unchanged.
	var opening := initial.duplicate(true)
	opening.treasury_account_pct_initial_gdp += opening.reserves_pct_initial_gdp - 3.0
	opening.reserves_pct_initial_gdp = 3.0
	var raw := opening.duplicate(true)
	var sterile := opening.duplicate(true)
	for q in range(SETTLEMENTS):
		var purchase := policy.duplicate(true)
		purchase.maintain_ample_reserves = false
		purchase.asset_flow_request_pct_initial_gdp = 2.0 if q == 0 else 0.0
		var absorbed := purchase.duplicate(true)
		absorbed.sterilize_purchases = true
		var a := checked_step(raw, purchase, shock, params, "unsterilized Q%d" % (q + 1))
		var b := checked_step(sterile, absorbed, shock, params, "sterilized Q%d" % (q + 1))
		if not a.ok or not b.ok:
			return
		for pair in [[raw, a.state], [sterile, b.state]]:
			var before: Dictionary = pair[0]
			var after: Dictionary = pair[1]
			var n: float = (before.actual_output_index / before.initial_actual_output_index) \
				* (before.price_index / before.initial_price_index)
			check(abs(after.duration_equivalent_pct_initial_gdp - initial.initial_duration_equivalent_pct_initial_gdp - 2.0) < 1e-10,
				"purchase Q%d: full principal reinvestment retains the known Q1 duration increment" % (q + 1))
			var expected_premium: float = initial.term_premium_pct - params.portfolio_premium_max_shift_pct \
				* tanh(2.0 / (n * params.portfolio_premium_scale_pct_gdp))
			var clear: float = params.reserve_clear_pct_current_gdp * n
			var scarcity: float = 0.0 if after.reserves_pct_initial_gdp >= clear else \
				params.reserve_scarcity_sensitivity_pct * pow(1.0 - after.reserves_pct_initial_gdp / clear, 2.0)
			check(abs(after.term_premium_pct - expected_premium) < 1e-10
				and abs(after.reserve_scarcity_wedge_pct - scarcity) < 1e-10,
				"purchase Q%d: duration and reserve scarcity use distinct equations and each path's meeting GDP" % (q + 1))
		raw = a.state
		sterile = b.state
		check(abs(raw.duration_equivalent_pct_initial_gdp - sterile.duration_equivalent_pct_initial_gdp) < 1e-10
			and raw.reverse_repo_pct_initial_gdp == 0.0
			and abs(sterile.reverse_repo_pct_initial_gdp - 2.0) < 1e-10
			and abs(sterile.sterilization_requested_pct_initial_gdp - 2.0) < 1e-10,
			"purchase Q%d: one purchase retains duration while RRP absorption renews without accumulating" % (q + 1))
		check(abs(raw.reserves_pct_initial_gdp - sterile.reserves_pct_initial_gdp
			- (sterile.reverse_repo_pct_initial_gdp + sterile.currency_pct_initial_gdp
				- raw.currency_pct_initial_gdp)) < 1e-7,
			"purchase Q%d: reserve/RRP substitution accounts for endogenous currency differences" % (q + 1))
		check(abs(sterile.credit_spread_pct - raw.credit_spread_pct
			- (sterile.reserve_scarcity_wedge_pct - raw.reserve_scarcity_wedge_pct)) < 1e-10,
			"purchase Q%d: the funding difference is scarcity, not a second duration channel" % (q + 1))
		if q == 0:
			check(raw.term_premium_pct == sterile.term_premium_pct
				and sterile.reserve_scarcity_wedge_pct > raw.reserve_scarcity_wedge_pct,
				"first purchase: equal duration easing but absorption leaves greater reserve scarcity")

func _initialize() -> void:
	var loaded: Dictionary = model.load_parameters()
	check(loaded.ok, "parameters load: %s" % loaded.get("error", ""))
	if loaded.ok:
		var params: Dictionary = loaded.values
		var initial: Dictionary = model.initial_state(params, {"credibility":0.2, "output_gap_pct":-3.0,
			"annualized_quarterly_inflation_pct":1.0, "expected_short_inflation_pct":1.3,
			"expected_long_inflation_pct":1.7, "unemployment_rate_pct":6.5})
		check(initial.ok, "compound opening is valid: %s" % initial.get("error", ""))
		if initial.ok:
			var state: Dictionary = initial.state
			var policy: Dictionary = model.benchmark_policy(state, params)
			policy.reinvest_principal = true
			policy.maintain_ample_reserves = true
			policy.sterilize_purchases = false
			var shock := {"funding_need_pct_initial_gdp":3.0, "eligible_collateral_pct_initial_gdp":6.0,
				"collateral_haircut_pct":25.0, "liquidity_eligibility_pct":100.0,
				"supply_innovation_pct":0.35, "solvency_risk_innovation_pct":0.6}
			var preserved := var_to_bytes([state, params, policy, shock])
			test_sustained_lending(state, params, policy, shock)
			test_sterilized_purchase(state, params, policy, shock)
			check(var_to_bytes([state, params, policy, shock]) == preserved,
				"all fixtures preserve the original state, parameters, policy and shock")
	for failure in failures:
		printerr("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: twelve-quarter lending renewal and sterilized duration/reserve separation")
	quit(0 if failures.is_empty() else 1)
