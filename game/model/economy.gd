extends RefCounted

const PARAMETER_KEYS := [
	"inflation_target_pct", "quarters_per_year", "percent_multiplier",
	"initial_output_index", "initial_price_index", "initial_potential_growth_pct",
	"initial_inflation_rate_pct", "initial_expected_short_inflation_pct",
	"initial_expected_long_inflation_pct", "initial_policy_rate_pct", "initial_r_star_pct",
	"initial_structural_unemployment_pct", "initial_unemployment_pct", "initial_output_gap_pct",
	"initial_credibility", "initial_public_support", "initial_asset_stock_pct_initial_gdp",
	"initial_term_premium_pct", "asset_stock_capacity_pct_initial_gdp",
	"asset_flow_quarter_limit_pct_initial_gdp", "asset_flow_request_limit_pct_initial_gdp",
	"term_premium_asset_sensitivity", "policy_rate_min_pct", "policy_rate_max_pct",
	"policy_rate_change_limit_pct", "policy_inflation_response", "policy_output_gap_response",
	"guidance_sensitivity_limit", "long_yield_current_rate_weight", "real_rate_short_weight",
	"real_rate_gap_persistence", "output_gap_persistence", "real_rate_output_sensitivity",
	"inflation_persistence", "short_expectation_recent_weight",
	"short_expectation_supply_sensitivity", "inflation_output_gap_sensitivity",
	"inflation_supply_sensitivity", "supply_pressure_persistence",
	"supply_output_gap_sensitivity", "long_expectation_adjustment",
	"unemployment_gap_persistence", "unemployment_gap_sensitivity", "credibility_adjustment",
	"credibility_miss_persistence", "credibility_miss_tolerance_pct",
	"credibility_stance_scale_pct", "credibility_followthrough_tolerance_pct",
	"solvency_risk_persistence", "funding_spread_sensitivity",
	"normal_credit_spread_pct", "liquidity_repayment_fraction",
	"liquidity_flow_quarter_limit_pct_initial_gdp", "liquidity_request_limit_pct_initial_gdp",
	"public_support_base", "public_inflation_burden_weight",
	"public_unemployment_burden_weight", "public_hardship_memory_persistence",
	"public_hardship_memory_weight", "public_support_adjustment",
	"deferred_demand_share", "demand_cancellation_fraction",
	"demand_release_base_fraction", "demand_release_max_fraction",
	"demand_release_backlog_scale_pct", "demand_release_financing_scale_pct",
	"r_star_reversion_persistence", "short_expectation_anchor_weight",
]
const POLICY_KEYS := [
	"policy_rate_request_pct", "guidance_rate_pct", "guidance_inflation_sensitivity",
	"guidance_output_gap_sensitivity", "asset_flow_request_pct_initial_gdp",
	"liquidity_request_pct_initial_gdp",
]
const SHOCK_LIMITS := {
	"demand_shock_pct": 10.0,
	"supply_innovation_pct": 5.0,
	"potential_growth_pct": 20.0,
	"r_star_change_pct": 1.0,
	"r_star_reference_change_pct": 1.0,
	"structural_unemployment_change_pct": 0.5,
	"funding_need_pct_initial_gdp": 100.0,
	"eligible_collateral_pct_initial_gdp": 100.0,
	"collateral_haircut_pct": 100.0,
	"liquidity_eligibility_pct": 100.0,
	"credit_risk_innovation_pct": 5.0,
	"solvency_risk_innovation_pct": 5.0,
}
const INITIAL_OVERRIDE_KEYS := [
	"output_gap_pct", "annualized_quarterly_inflation_pct", "expected_short_inflation_pct",
	"expected_long_inflation_pct", "policy_rate_pct", "unemployment_rate_pct", "credibility",
	"public_support", "r_star_pct", "structural_unemployment_pct",
	"asset_stock_pct_initial_gdp", "term_premium_pct",
	"supply_pressure_pct", "solvency_risk_wedge_pct", "public_hardship_memory",
	"deferred_demand_pct", "r_star_reference_pct",
]
const POLICY_REQUIRED_HINT := "policy requires all six disclosed controls"


static func annualized_growth(current_output: float, previous_output: float) -> float:
	return 100.0 * (pow(current_output / previous_output, 4.0) - 1.0)


func load_parameters(path: String = "res://model/parameters.json") -> Dictionary:
	var parsed := _read_json(path)
	if not parsed.ok:
		return parsed
	if typeof(parsed.value) != TYPE_ARRAY:
		return {"ok": false, "error": "parameter file must be an array"}
	var values := {}
	for row in parsed.value:
		if typeof(row) != TYPE_DICTIONARY:
			return {"ok": false, "error": "each parameter must be an object"}
		for field in ["key", "value", "unit", "classification", "description", "source"]:
			if not row.has(field):
				return {"ok": false, "error": "parameter record missing %s" % field}
		var key: String = str(row.key)
		if not key.is_valid_identifier() or key != key.to_lower() or values.has(key):
			return {"ok": false, "error": "invalid or duplicate parameter key: %s" % key}
		if typeof(row.value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(row.value)):
			return {"ok": false, "error": "parameter %s must be finite numeric" % key}
		if row.classification not in ["source_value", "design_assumption", "mathematical_identity"]:
			return {"ok": false, "error": "invalid parameter classification: %s" % key}
		if row.classification == "source_value" and not str(row.source).begins_with("https://"):
			return {"ok": false, "error": "source value lacks a primary URL: %s" % key}
		if row.classification == "design_assumption" and str(row.source) != "":
			return {"ok": false, "error": "design coefficient must not imply an empirical source: %s" % key}
		if str(row.unit) == "" or str(row.description) == "":
			return {"ok": false, "error": "parameter %s needs units and description" % key}
		values[key] = float(row.value)
	for key in PARAMETER_KEYS:
		if not values.has(key):
			return {"ok": false, "error": "required parameter missing: %s" % key}
	var checked := _validate_parameters(values)
	if not checked.ok:
		return checked
	return {"ok": true, "values": values, "records": parsed.value}


func load_scenarios(path: String = "res://model/scenarios.json") -> Dictionary:
	var parsed := _read_json(path)
	if not parsed.ok:
		return parsed
	if typeof(parsed.value) != TYPE_ARRAY:
		return {"ok": false, "error": "scenario file must be an array"}
	var scenarios := {}
	for row in parsed.value:
		if typeof(row) != TYPE_DICTIONARY:
			return {"ok": false, "error": "each scenario must be an object"}
		for field in ["id", "label", "description", "initial", "events"]:
			if not row.has(field):
				return {"ok": false, "error": "scenario record missing %s" % field}
		var id: String = str(row.id)
		if not id.is_valid_identifier() or id != id.to_lower() or scenarios.has(id):
			return {"ok": false, "error": "invalid or duplicate scenario id: %s" % id}
		if typeof(row.initial) != TYPE_DICTIONARY or typeof(row.events) != TYPE_ARRAY:
			return {"ok": false, "error": "scenario initial must be an object and events an array"}
		var event_quarters := {}
		for event in row.events:
			if typeof(event) != TYPE_DICTIONARY or not event.has("quarter_index"):
				return {"ok": false, "error": "each event needs a quarter_index"}
			if typeof(event.quarter_index) not in [TYPE_INT, TYPE_FLOAT]:
				return {"ok": false, "error": "scenario event quarter must be numeric"}
			var q: int = int(event.quarter_index)
			if q < 0 or float(event.quarter_index) != q or event_quarters.has(q):
				return {"ok": false, "error": "scenario has invalid or repeated event quarter"}
			event_quarters[q] = true
			var inputs: Dictionary = event.duplicate(true)
			inputs.erase("quarter_index")
			var valid := _validate_shocks(inputs)
			if not valid.ok:
				return {"ok": false, "error": "scenario %s event %d: %s" % [id, q, valid.error]}
		scenarios[id] = row.duplicate(true)
	return {"ok": true, "scenarios": scenarios, "records": parsed.value}


func initial_state(params: Dictionary, override: Dictionary = {}) -> Dictionary:
	var valid := _validate_parameters(params)
	if not valid.ok:
		return valid
	for key in override:
		if key not in INITIAL_OVERRIDE_KEYS or typeof(override[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(override[key])):
			return {"ok": false, "error": "invalid initial-state override: %s" % key}
	var state := {
		"quarter_index": 0,
		"initial_annual_gdp_index": params.initial_output_index,
		"potential_output_index": params.initial_output_index,
		"actual_output_index": params.initial_output_index * (1.0 + params.initial_output_gap_pct / 100.0),
		"output_gap_pct": params.initial_output_gap_pct,
		"potential_growth_pct": params.initial_potential_growth_pct,
		"annualized_potential_growth_pct": params.initial_potential_growth_pct,
		"annualized_actual_growth_pct": params.initial_potential_growth_pct,
		"price_index": params.initial_price_index,
		"annualized_quarterly_inflation_pct": params.initial_inflation_rate_pct,
		"four_quarter_inflation_pct": params.initial_inflation_rate_pct,
		"expected_short_inflation_pct": params.initial_expected_short_inflation_pct,
		"expected_long_inflation_pct": params.initial_expected_long_inflation_pct,
		"unemployment_rate_pct": params.initial_unemployment_pct,
		"structural_unemployment_pct": params.initial_structural_unemployment_pct,
		"r_star_pct": params.initial_r_star_pct,
		"r_star_reference_pct": params.initial_r_star_pct,
		"deferred_demand_pct": 0.0,
		"demand_release_pct": 0.0,
		"policy_rate_pct": params.initial_policy_rate_pct,
		"last_policy_rate_request_pct": params.initial_policy_rate_pct,
		"long_yield_pct": params.initial_policy_rate_pct + params.initial_term_premium_pct,
		"financial_restraint_gap_pct": 0.0,
		"asset_stock_pct_initial_gdp": params.initial_asset_stock_pct_initial_gdp,
		"initial_asset_stock_pct_initial_gdp": params.initial_asset_stock_pct_initial_gdp,
		"asset_stock_capacity_pct_initial_gdp": params.asset_stock_capacity_pct_initial_gdp,
		"term_premium_pct": params.initial_term_premium_pct,
		"asset_flow_request_pct_initial_gdp": 0.0,
		"asset_flow_applied_pct_initial_gdp": 0.0,
		"funding_need_pct_initial_gdp": 0.0,
		"eligible_collateral_pct_initial_gdp": 0.0,
		"outstanding_liquidity_pct_initial_gdp": 0.0,
		"liquidity_repayment_pct_initial_gdp": 0.0,
		"liquidity_request_pct_initial_gdp": 0.0,
		"liquidity_applied_pct_initial_gdp": 0.0,
		"uncovered_funding_pct_initial_gdp": 0.0,
		"credit_spread_pct": params.normal_credit_spread_pct,
		"credit_risk_wedge_pct": 0.0,
		"solvency_risk_wedge_pct": 0.0,
		"supply_pressure_pct": 0.0,
		"credibility": params.initial_credibility,
		"inflation_miss_memory_pct": 0.0,
		"guidance_active": false,
		"guidance_rate_pct": params.initial_policy_rate_pct,
		"guidance_inflation_sensitivity": 0.0,
		"guidance_output_gap_sensitivity": 0.0,
		"guidance_reference_inflation_pct": params.initial_inflation_rate_pct,
		"guidance_reference_output_gap_pct": params.initial_output_gap_pct,
		"guidance_followthrough_score": 1.0,
		"reaction_function_target_pct": params.initial_policy_rate_pct,
		"public_support": params.initial_public_support,
		"public_hardship_memory": 0.0,
		"current_hardship": 0.0,
	}
	for key in override:
		state[key] = float(override[key])
	if not override.has("r_star_reference_pct"):
		state.r_star_reference_pct = state.r_star_pct
	state.credit_risk_wedge_pct = state.solvency_risk_wedge_pct
	state.credit_spread_pct = params.normal_credit_spread_pct + state.credit_risk_wedge_pct
	state.actual_output_index = state.potential_output_index * (1.0 + state.output_gap_pct / 100.0)
	if override.has("asset_stock_pct_initial_gdp") and not override.has("term_premium_pct"):
		state.term_premium_pct = params.initial_term_premium_pct - params.term_premium_asset_sensitivity * (state.asset_stock_pct_initial_gdp - state.initial_asset_stock_pct_initial_gdp)
	state.long_yield_pct = state.policy_rate_pct + state.term_premium_pct
	state.guidance_rate_pct = state.policy_rate_pct
	state.last_policy_rate_request_pct = state.policy_rate_pct
	var annual_rate: float = 1.0 + state.annualized_quarterly_inflation_pct / 100.0
	if state.output_gap_pct <= -100.0 or state.potential_growth_pct <= -100.0 or annual_rate <= 0.0:
		return {"ok": false, "error": "initial state implies nonpositive output or prices"}
	var q_price_ratio := pow(annual_rate, 0.25)
	state.price_history = []
	for age in range(4, -1, -1):
		state.price_history.append(state.price_index / pow(q_price_ratio, age))
	state.four_quarter_inflation_pct = _four_quarter_inflation(state.price_history, params.percent_multiplier)
	var checked := _validate_state(state, params)
	if not checked.ok:
		return checked
	return {"ok": true, "state": state}


func step(state: Dictionary, policy: Dictionary, shocks: Dictionary, params: Dictionary) -> Dictionary:
	var param_check := _validate_parameters(params)
	if not param_check.ok:
		return param_check
	var state_check := _validate_state(state, params)
	if not state_check.ok:
		return state_check
	var policy_check := _validate_policy(policy, params)
	if not policy_check.ok:
		return policy_check
	var shock_check := _validate_shocks(shocks)
	if not shock_check.ok:
		return shock_check

	# Timeline: observe state[q], choose policy[q] and observe shocks[q]; current
	# market conditions then drive output[q+1], and lagged resources drive prices.
	var next: Dictionary = state.duplicate(true)
	var prior_rate: float = state.policy_rate_pct
	var rate_request: float = policy.policy_rate_request_pct
	var rate_change: float = params.policy_rate_change_limit_pct
	var rate: float = clamp(rate_request, max(params.policy_rate_min_pct, prior_rate - rate_change), min(params.policy_rate_max_pct, prior_rate + rate_change))
	var asset_request: float = policy.asset_flow_request_pct_initial_gdp
	var asset_limit: float = params.asset_flow_quarter_limit_pct_initial_gdp
	var asset_delta: float = clamp(asset_request, -min(asset_limit, state.asset_stock_pct_initial_gdp), min(asset_limit, state.asset_stock_capacity_pct_initial_gdp - state.asset_stock_pct_initial_gdp))
	var asset_stock: float = state.asset_stock_pct_initial_gdp + asset_delta
	var term_premium: float = state.term_premium_pct - params.term_premium_asset_sensitivity * asset_delta

	var liquidity_request: float = policy.liquidity_request_pct_initial_gdp
	var repayment: float = state.outstanding_liquidity_pct_initial_gdp * params.liquidity_repayment_fraction
	var outstanding_after_repayment: float = state.outstanding_liquidity_pct_initial_gdp - repayment
	var funding_need: float = shocks.get("funding_need_pct_initial_gdp", 0.0)
	var collateral: float = shocks.get("eligible_collateral_pct_initial_gdp", 0.0)
	var haircut: float = shocks.get("collateral_haircut_pct", 0.0)
	var eligibility: float = shocks.get("liquidity_eligibility_pct", 0.0)
	var eligible_capacity: float = collateral * (1.0 - haircut / 100.0) * (eligibility / 100.0)
	var lending_headroom: float = max(0.0, eligible_capacity - outstanding_after_repayment)
	var liquidity_delta: float = min(liquidity_request, funding_need, params.liquidity_flow_quarter_limit_pct_initial_gdp, lending_headroom)
	var outstanding_liquidity: float = outstanding_after_repayment + liquidity_delta
	var uncovered_funding: float = max(0.0, funding_need - liquidity_delta)
	var solvency_wedge: float = state.solvency_risk_wedge_pct * params.solvency_risk_persistence + shocks.get("solvency_risk_innovation_pct", 0.0)
	var credit_wedge: float = params.funding_spread_sensitivity * uncovered_funding + solvency_wedge + shocks.get("credit_risk_innovation_pct", 0.0)
	var credit_spread: float = params.normal_credit_spread_pct + credit_wedge

	var guide_rate: float = policy.guidance_rate_pct
	var guide_infl_sensitivity: float = policy.guidance_inflation_sensitivity
	var guide_gap_sensitivity: float = policy.guidance_output_gap_sensitivity
	var prior_commitment := rate
	if state.guidance_active:
		prior_commitment = state.guidance_rate_pct \
			+ state.guidance_inflation_sensitivity * (state.four_quarter_inflation_pct - state.guidance_reference_inflation_pct) \
			+ state.guidance_output_gap_sensitivity * (state.output_gap_pct - state.guidance_reference_output_gap_pct)
	var followthrough := exp(-abs(rate - prior_commitment) / params.credibility_followthrough_tolerance_pct) if state.guidance_active else 1.0
	var credibility: float = state.credibility
	var priced_guidance: float = rate + credibility * (guide_rate - rate)
	var expected_policy_path: float = params.long_yield_current_rate_weight * rate + (1.0 - params.long_yield_current_rate_weight) * priced_guidance
	var long_yield: float = expected_policy_path + term_premium
	var rstar_reference: float = state.r_star_reference_pct + shocks.get("r_star_reference_change_pct", 0.0)
	var rstar: float = rstar_reference + params.r_star_reversion_persistence * (state.r_star_pct - state.r_star_reference_pct) + shocks.get("r_star_change_pct", 0.0)
	var spot_financial_gap: float = params.real_rate_short_weight * (rate - state.expected_short_inflation_pct) \
		+ (1.0 - params.real_rate_short_weight) * (long_yield - params.initial_term_premium_pct - state.expected_long_inflation_pct) \
		+ (credit_spread - params.normal_credit_spread_pct) - rstar
	var financial_gap: float = params.real_rate_gap_persistence * state.financial_restraint_gap_pct \
		+ (1.0 - params.real_rate_gap_persistence) * spot_financial_gap

	var growth: float = shocks.get("potential_growth_pct", state.potential_growth_pct)
	var structural_u: float = state.structural_unemployment_pct + shocks.get("structural_unemployment_change_pct", 0.0)
	if structural_u <= 0.0 or structural_u >= 100.0:
		return {"ok": false, "error": "structural unemployment reference must be between 0 and 100 percent"}
	var potential_output: float = state.potential_output_index * pow(1.0 + growth / 100.0, 1.0 / params.quarters_per_year)
	var supply_pressure: float = params.supply_pressure_persistence * state.supply_pressure_pct + shocks.get("supply_innovation_pct", 0.0)
	var underlying_gap: float = params.output_gap_persistence * state.output_gap_pct \
		- params.real_rate_output_sensitivity * financial_gap \
		+ shocks.get("demand_shock_pct", 0.0) - params.supply_output_gap_sensitivity * supply_pressure
	# Rebase prior stock to current potential output; growth cannot create purchases.
	var available_demand: float = state.deferred_demand_pct * state.potential_output_index / potential_output
	var release_fraction: float = (params.demand_release_base_fraction \
		+ (params.demand_release_max_fraction - params.demand_release_base_fraction) \
		* abs(available_demand) / (params.demand_release_backlog_scale_pct + abs(available_demand))) \
		/ (1.0 + pow(max(0.0, financial_gap) / params.demand_release_financing_scale_pct, 2.0))
	var demand_release: float = release_fraction * available_demand
	var output_gap: float = underlying_gap + demand_release
	var deferred_demand: float = (1.0 - params.demand_cancellation_fraction) * available_demand \
		- params.deferred_demand_share * underlying_gap - demand_release
	# A bounded design target preserves the local Okun-style slope without clipping outcomes.
	var labor_target: float = structural_u * exp(-params.unemployment_gap_sensitivity * output_gap / structural_u) if output_gap >= 0.0 \
		else 100.0 - (100.0 - structural_u) * exp(params.unemployment_gap_sensitivity * output_gap / (100.0 - structural_u))
	var unemployment: float = lerpf(state.unemployment_rate_pct, labor_target, 1.0 - params.unemployment_gap_persistence)

	# Positive gross growth preserves the unforced blend and local percent slopes at target.
	var inflation_scale: float = 100.0 + params.inflation_target_pct
	var inflation_base: float = params.inflation_persistence * (1.0 + state.annualized_quarterly_inflation_pct / 100.0) \
		+ (1.0 - params.inflation_persistence) * (1.0 + state.expected_short_inflation_pct / 100.0)
	var price_growth_base: float = inflation_base * exp((params.inflation_output_gap_sensitivity * state.output_gap_pct \
		+ params.inflation_supply_sensitivity * supply_pressure) / inflation_scale)
	if output_gap <= -100.0 or potential_output <= 0.0 or price_growth_base <= 0.0:
		return {"ok": false, "error": "transition implied nonpositive output, potential or prices"}
	var price_index: float = state.price_index * pow(price_growth_base, 1.0 / params.quarters_per_year)
	var history: Array = state.price_history.duplicate()
	history.append(price_index)
	history.pop_front()
	var four_quarter: float = _four_quarter_inflation(history, params.percent_multiplier)
	var short_anchor_weight: float = params.short_expectation_anchor_weight * credibility
	var recent_expectation_base: float = (1.0 - short_anchor_weight) * (1.0 + state.four_quarter_inflation_pct / 100.0) \
		+ short_anchor_weight * (1.0 + state.expected_long_inflation_pct / 100.0)
	var expected_short_base: float = (1.0 - params.short_expectation_recent_weight) * (1.0 + state.expected_short_inflation_pct / 100.0) \
		+ params.short_expectation_recent_weight * recent_expectation_base
	var expected_short: float = 100.0 * (expected_short_base * exp(params.short_expectation_supply_sensitivity * supply_pressure / inflation_scale) - 1.0)
	var long_anchor: float = credibility * params.inflation_target_pct + (1.0 - credibility) * state.four_quarter_inflation_pct
	var expected_long: float = state.expected_long_inflation_pct \
		+ params.long_expectation_adjustment * (long_anchor - state.expected_long_inflation_pct)
	var reaction_target: float = rstar + state.expected_short_inflation_pct \
		+ params.policy_inflation_response * (state.four_quarter_inflation_pct - params.inflation_target_pct) \
		+ params.policy_output_gap_response * state.output_gap_pct
	var miss_memory: float = params.credibility_miss_persistence * state.inflation_miss_memory_pct \
		+ (1.0 - params.credibility_miss_persistence) * abs(state.four_quarter_inflation_pct - params.inflation_target_pct)
	var inflation_performance := exp(-miss_memory / params.credibility_miss_tolerance_pct)
	var stance_adequacy := exp(-abs(rate - reaction_target) / params.credibility_stance_scale_pct)
	var credibility_score := 0.4 * inflation_performance + 0.4 * stance_adequacy + 0.2 * followthrough
	var next_credibility: float = clamp(credibility + params.credibility_adjustment * (credibility_score - credibility), 0.0, 1.0)
	var hardship: float = params.public_inflation_burden_weight * abs(four_quarter - params.inflation_target_pct) \
		+ params.public_unemployment_burden_weight * max(0.0, unemployment - structural_u)
	var hardship_memory: float = params.public_hardship_memory_persistence * state.public_hardship_memory \
		+ (1.0 - params.public_hardship_memory_persistence) * hardship
	var support_target: float = clamp(params.public_support_base - hardship - params.public_hardship_memory_weight * hardship_memory, 0.0, 100.0)
	var support: float = state.public_support + params.public_support_adjustment * (support_target - state.public_support)
	var actual_output: float = potential_output * (1.0 + output_gap / 100.0)
	var actual_growth: float = annualized_growth(actual_output, state.actual_output_index)
	var potential_growth: float = annualized_growth(potential_output, state.potential_output_index)
	var quarterly_inflation: float = 100.0 * (pow(price_index / state.price_index, params.quarters_per_year) - 1.0)

	var updates := {
		"quarter_index": state.quarter_index + 1,
		"potential_output_index": potential_output,
		"actual_output_index": actual_output,
		"output_gap_pct": output_gap,
		"potential_growth_pct": growth,
		"annualized_potential_growth_pct": potential_growth,
		"annualized_actual_growth_pct": actual_growth,
		"price_index": price_index,
		"price_history": history,
		"annualized_quarterly_inflation_pct": quarterly_inflation,
		"four_quarter_inflation_pct": four_quarter,
		"expected_short_inflation_pct": expected_short,
		"expected_long_inflation_pct": expected_long,
		"unemployment_rate_pct": unemployment,
		"structural_unemployment_pct": structural_u,
		"r_star_pct": rstar,
		"r_star_reference_pct": rstar_reference,
		"deferred_demand_pct": deferred_demand,
		"demand_release_pct": demand_release,
		"last_policy_rate_request_pct": rate_request,
		"policy_rate_pct": rate,
		"long_yield_pct": long_yield,
		"financial_restraint_gap_pct": financial_gap,
		"asset_stock_pct_initial_gdp": asset_stock,
		"term_premium_pct": term_premium,
		"asset_flow_request_pct_initial_gdp": asset_request,
		"asset_flow_applied_pct_initial_gdp": asset_delta,
		"funding_need_pct_initial_gdp": funding_need,
		"eligible_collateral_pct_initial_gdp": collateral,
		"outstanding_liquidity_pct_initial_gdp": outstanding_liquidity,
		"liquidity_repayment_pct_initial_gdp": repayment,
		"liquidity_request_pct_initial_gdp": liquidity_request,
		"liquidity_applied_pct_initial_gdp": liquidity_delta,
		"uncovered_funding_pct_initial_gdp": uncovered_funding,
		"credit_spread_pct": credit_spread,
		"credit_risk_wedge_pct": credit_wedge,
		"solvency_risk_wedge_pct": solvency_wedge,
		"supply_pressure_pct": supply_pressure,
		"credibility": next_credibility,
		"inflation_miss_memory_pct": miss_memory,
		"guidance_active": true,
		"guidance_rate_pct": guide_rate,
		"guidance_inflation_sensitivity": guide_infl_sensitivity,
		"guidance_output_gap_sensitivity": guide_gap_sensitivity,
		"guidance_reference_inflation_pct": state.four_quarter_inflation_pct,
		"guidance_reference_output_gap_pct": state.output_gap_pct,
		"guidance_followthrough_score": followthrough,
		"reaction_function_target_pct": reaction_target,
		"public_support": support,
		"public_hardship_memory": hardship_memory,
		"current_hardship": hardship,
	}
	for key in updates:
		next[key] = updates[key]
	var final_check := _validate_state(next, params)
	if not final_check.ok:
		return {"ok": false, "error": "invalid transition result: %s" % final_check.error}
	var trace := {
		"quarter_index": next.quarter_index,
		"policy_rate_request_pct": rate_request,
		"policy_rate_applied_pct": rate,
		"r_star_reference_pct": rstar_reference,
		"deferred_demand_pct": deferred_demand,
		"demand_release_pct": demand_release,
		"guidance_rate_pct": guide_rate,
		"guidance_followthrough_score": followthrough,
		"long_yield_pct": long_yield,
		"financial_restraint_gap_pct": financial_gap,
		"asset_flow_request_pct_initial_gdp": asset_request,
		"asset_flow_applied_pct_initial_gdp": asset_delta,
		"asset_stock_pct_initial_gdp": asset_stock,
		"term_premium_pct": term_premium,
		"liquidity_request_pct_initial_gdp": liquidity_request,
		"liquidity_applied_pct_initial_gdp": liquidity_delta,
		"liquidity_repayment_pct_initial_gdp": repayment,
		"outstanding_liquidity_pct_initial_gdp": outstanding_liquidity,
		"uncovered_funding_pct_initial_gdp": uncovered_funding,
		"credit_spread_pct": credit_spread,
		"solvency_risk_wedge_pct": solvency_wedge,
		"supply_pressure_pct": supply_pressure,
		"output_gap_pct": output_gap,
		"annualized_quarterly_inflation_pct": quarterly_inflation,
		"four_quarter_inflation_pct": four_quarter,
		"expected_short_inflation_pct": expected_short,
		"expected_long_inflation_pct": expected_long,
		"unemployment_rate_pct": unemployment,
		"credibility": next_credibility,
		"public_support": support,
	}
	return {"ok": true, "state": next, "trace": trace}


func benchmark_policy(state: Dictionary, params: Dictionary, kind: String = "feedback") -> Dictionary:
	var target: float = state.policy_rate_pct
	if kind == "neutral":
		target = state.r_star_pct + params.inflation_target_pct
	elif kind == "feedback":
		target = state.r_star_pct + state.expected_short_inflation_pct \
			+ params.policy_inflation_response * (state.four_quarter_inflation_pct - params.inflation_target_pct) \
			+ params.policy_output_gap_response * state.output_gap_pct
	elif kind != "hold":
		return {"ok": false, "error": "unknown benchmark policy: %s" % kind}
	target = clamp(target, params.policy_rate_min_pct, params.policy_rate_max_pct)
	var applied_rate: float = clamp(target, max(params.policy_rate_min_pct, state.policy_rate_pct - params.policy_rate_change_limit_pct), min(params.policy_rate_max_pct, state.policy_rate_pct + params.policy_rate_change_limit_pct))
	var reachable_quote: float = clamp(target, max(params.policy_rate_min_pct, applied_rate - params.policy_rate_change_limit_pct), min(params.policy_rate_max_pct, applied_rate + params.policy_rate_change_limit_pct))
	return {
		"policy_rate_request_pct": target,
		"guidance_rate_pct": reachable_quote,
		"guidance_inflation_sensitivity": params.policy_inflation_response,
		"guidance_output_gap_sensitivity": params.policy_output_gap_response,
		"asset_flow_request_pct_initial_gdp": 0.0,
		"liquidity_request_pct_initial_gdp": 0.0,
	}


func shock_for_quarter(scenario: Dictionary, quarter: int) -> Dictionary:
	for event in scenario.get("events", []):
		if int(event.quarter_index) == quarter:
			var shocks: Dictionary = event.duplicate(true)
			shocks.erase("quarter_index")
			return shocks
	return {}


func seeded_shock_path(seed: int, scenario: Dictionary, quarters: int) -> Array:
	if scenario.id == "mixed_crises":
		scenario = scenario.duplicate(true)
		var templates: Dictionary = load_scenarios().scenarios
		var episodes := RandomNumberGenerator.new()
		episodes.seed = seed ^ 0x43414D50
		var bag: Array = []
		var onset := episodes.randi_range(12, 20)
		while onset < quarters:
			if bag.is_empty():
				bag = ["demand_boom", "supply_shock", "funding_stress"]
			var id: String = bag.pop_at(episodes.randi_range(0, bag.size() - 1))
			var strength := episodes.randf_range(0.75, 1.25)
			var polarity := 1.0 if id == "funding_stress" or episodes.randi_range(0, 1) == 1 else -1.0
			var events: Array = templates[id].events
			for template in events:
				var event: Dictionary = template.duplicate(true)
				event.quarter_index = onset + int(template.quarter_index) - int(events[0].quarter_index)
				for key in ["demand_shock_pct", "supply_innovation_pct", "funding_need_pct_initial_gdp", "eligible_collateral_pct_initial_gdp", "solvency_risk_innovation_pct"]:
					if event.has(key):
						event[key] *= strength * polarity
				scenario.events.append(event)
			onset += episodes.randi_range(12, 20)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var path: Array = []
	for q in range(quarters):
		var shocks: Dictionary = shock_for_quarter(scenario, q)
		shocks["demand_shock_pct"] = shocks.get("demand_shock_pct", 0.0) + rng.randf_range(-0.18, 0.18)
		shocks["supply_innovation_pct"] = shocks.get("supply_innovation_pct", 0.0) + rng.randf_range(-0.04, 0.04)
		shocks["r_star_change_pct"] = shocks.get("r_star_change_pct", 0.0) + rng.randf_range(-0.01, 0.01)
		if scenario.id == "funding_stress":
			var extra_need: float = rng.randf_range(0.0, 0.05)
			shocks["funding_need_pct_initial_gdp"] = shocks.get("funding_need_pct_initial_gdp", 0.0) + extra_need
			shocks["eligible_collateral_pct_initial_gdp"] = max(shocks.get("eligible_collateral_pct_initial_gdp", 0.0), 2.0 * extra_need)
			shocks["collateral_haircut_pct"] = shocks.get("collateral_haircut_pct", 25.0)
			shocks["liquidity_eligibility_pct"] = 100.0
		path.append(shocks)
	return path


func _validate_parameters(params: Dictionary) -> Dictionary:
	for key in PARAMETER_KEYS:
		if not params.has(key) or typeof(params[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(params[key])):
			return {"ok": false, "error": "missing or nonfinite parameter: %s" % key}
	if params.public_support_base < 0.0 or params.public_support_base > 100.0 or params.public_support_adjustment < 0.0 or params.public_support_adjustment > 1.0 or params.normal_credit_spread_pct < 0.0:
		return {"ok": false, "error": "invalid public-support or normal-spread parameter"}
	for key in ["real_rate_gap_persistence", "output_gap_persistence", "inflation_persistence", "short_expectation_recent_weight", "supply_pressure_persistence", "long_expectation_adjustment", "unemployment_gap_persistence", "credibility_adjustment", "credibility_miss_persistence", "solvency_risk_persistence", "liquidity_repayment_fraction", "public_hardship_memory_persistence", "real_rate_short_weight", "long_yield_current_rate_weight"]:
		if params[key] < 0.0 or params[key] > 1.0:
			return {"ok": false, "error": "share parameter out of range: %s" % key}
	for key in ["deferred_demand_share", "demand_cancellation_fraction", "demand_release_base_fraction", "demand_release_max_fraction", "r_star_reversion_persistence", "short_expectation_anchor_weight"]:
		if params[key] < 0.0 or params[key] > 1.0:
			return {"ok": false, "error": "recovery fraction out of range: %s" % key}
	if params.demand_release_base_fraction > params.demand_release_max_fraction or params.demand_release_max_fraction + params.demand_cancellation_fraction > 1.0 or params.demand_release_backlog_scale_pct <= 0.0 or params.demand_release_financing_scale_pct <= 0.0:
		return {"ok": false, "error": "inconsistent demand-release fractions or nonpositive recovery scale"}
	if params.policy_rate_min_pct < 0.0 or params.policy_rate_max_pct <= params.policy_rate_min_pct or params.initial_asset_stock_pct_initial_gdp < 0.0 or params.asset_stock_capacity_pct_initial_gdp < params.initial_asset_stock_pct_initial_gdp or params.inflation_target_pct != 2.0:
		return {"ok": false, "error": "inconsistent bounds or unsupported target parameter"}
	if params.quarters_per_year != 4.0 or params.percent_multiplier != 100.0 or params.initial_output_index <= 0.0 or params.initial_price_index <= 0.0 or params.initial_structural_unemployment_pct <= 0.0 or params.initial_structural_unemployment_pct >= 100.0:
		return {"ok": false, "error": "invalid scale or initial reference parameter"}
	if params.initial_inflation_rate_pct <= -100.0 or params.initial_expected_short_inflation_pct <= -100.0 or params.initial_expected_long_inflation_pct <= -100.0 or params.initial_output_gap_pct <= -100.0 or params.initial_policy_rate_pct < params.policy_rate_min_pct or params.initial_policy_rate_pct > params.policy_rate_max_pct:
		return {"ok": false, "error": "invalid initial inflation, output gap or rate"}
	if params.initial_credibility < 0.0 or params.initial_credibility > 1.0 or params.initial_public_support < 0.0 or params.initial_public_support > 100.0 or params.initial_unemployment_pct < 0.0 or params.initial_unemployment_pct > 100.0:
		return {"ok": false, "error": "initial bounded state outside its domain"}
	for key in ["asset_flow_quarter_limit_pct_initial_gdp", "asset_flow_request_limit_pct_initial_gdp", "liquidity_flow_quarter_limit_pct_initial_gdp", "liquidity_request_limit_pct_initial_gdp", "policy_rate_change_limit_pct", "guidance_sensitivity_limit", "policy_inflation_response", "policy_output_gap_response", "credibility_miss_tolerance_pct", "credibility_stance_scale_pct", "credibility_followthrough_tolerance_pct", "real_rate_output_sensitivity", "inflation_output_gap_sensitivity", "inflation_supply_sensitivity", "short_expectation_supply_sensitivity", "supply_output_gap_sensitivity", "unemployment_gap_sensitivity", "term_premium_asset_sensitivity", "funding_spread_sensitivity", "public_inflation_burden_weight", "public_unemployment_burden_weight", "public_hardship_memory_weight"]:
		if params[key] < 0.0:
			return {"ok": false, "error": "negative sensitivity, scale or capacity: %s" % key}
	if params.credibility_miss_tolerance_pct == 0.0 or params.credibility_stance_scale_pct == 0.0 or params.credibility_followthrough_tolerance_pct == 0.0:
		return {"ok": false, "error": "credibility scales must be positive"}
	return {"ok": true}


func _validate_state(state: Dictionary, params: Dictionary) -> Dictionary:
	var keys := [
		"quarter_index", "initial_annual_gdp_index", "potential_output_index", "actual_output_index", "output_gap_pct",
		"potential_growth_pct", "annualized_potential_growth_pct", "annualized_actual_growth_pct", "price_index",
		"annualized_quarterly_inflation_pct", "four_quarter_inflation_pct", "expected_short_inflation_pct",
		"expected_long_inflation_pct", "unemployment_rate_pct", "structural_unemployment_pct", "r_star_pct",
		"policy_rate_pct", "last_policy_rate_request_pct", "long_yield_pct", "financial_restraint_gap_pct",
		"asset_stock_pct_initial_gdp", "initial_asset_stock_pct_initial_gdp", "asset_stock_capacity_pct_initial_gdp",
		"term_premium_pct", "asset_flow_request_pct_initial_gdp", "asset_flow_applied_pct_initial_gdp",
		"funding_need_pct_initial_gdp", "eligible_collateral_pct_initial_gdp", "outstanding_liquidity_pct_initial_gdp",
		"liquidity_repayment_pct_initial_gdp", "liquidity_request_pct_initial_gdp", "liquidity_applied_pct_initial_gdp",
		"uncovered_funding_pct_initial_gdp", "credit_spread_pct", "credit_risk_wedge_pct", "solvency_risk_wedge_pct",
		"supply_pressure_pct", "credibility", "inflation_miss_memory_pct", "guidance_rate_pct",
		"guidance_inflation_sensitivity", "guidance_output_gap_sensitivity", "guidance_reference_inflation_pct",
		"guidance_reference_output_gap_pct", "guidance_followthrough_score", "reaction_function_target_pct",
		"public_support", "public_hardship_memory", "current_hardship",
		"deferred_demand_pct", "demand_release_pct", "r_star_reference_pct",
	]
	for key in keys:
		if not state.has(key) or typeof(state[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(state[key])):
			return {"ok": false, "error": "missing or nonfinite state field: %s" % key}
	if not state.has("price_history") or typeof(state.price_history) != TYPE_ARRAY or state.price_history.size() != 5 or not state.has("guidance_active") or typeof(state.guidance_active) != TYPE_BOOL:
		return {"ok": false, "error": "invalid price history or guidance state"}
	for price in state.price_history:
		if typeof(price) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(price)) or price <= 0.0:
			return {"ok": false, "error": "price history contains a nonpositive or nonfinite value"}
	if abs(float(state.price_history[4]) - state.price_index) > 1e-7 or abs(_four_quarter_inflation(state.price_history, params.percent_multiplier) - state.four_quarter_inflation_pct) > 1e-7:
		return {"ok": false, "error": "price history conflicts with current price or four-quarter inflation"}
	if abs(annualized_growth(state.price_history[4], state.price_history[3]) - state.annualized_quarterly_inflation_pct) > 1e-7:
		return {"ok": false, "error": "quarterly inflation conflicts with price history"}
	if state.asset_stock_capacity_pct_initial_gdp != params.asset_stock_capacity_pct_initial_gdp:
		return {"ok": false, "error": "state asset capacity conflicts with parameter capacity"}
	if state.quarter_index < 0 or float(state.quarter_index) != int(state.quarter_index) or state.initial_annual_gdp_index <= 0.0 or state.potential_output_index <= 0.0 or state.actual_output_index <= 0.0 or state.price_index <= 0.0 or state.output_gap_pct <= -100.0 or state.structural_unemployment_pct <= 0.0 or state.structural_unemployment_pct >= 100.0 or state.unemployment_rate_pct < 0.0 or state.unemployment_rate_pct > 100.0 or state.credibility < 0.0 or state.credibility > 1.0 or state.public_support < 0.0 or state.public_support > 100.0:
		return {"ok": false, "error": "state violates positive-scale or bounded-domain invariant"}
	if state.policy_rate_pct < params.policy_rate_min_pct or state.policy_rate_pct > params.policy_rate_max_pct or state.last_policy_rate_request_pct < params.policy_rate_min_pct or state.last_policy_rate_request_pct > params.policy_rate_max_pct or state.guidance_rate_pct < params.policy_rate_min_pct or state.guidance_rate_pct > params.policy_rate_max_pct:
		return {"ok": false, "error": "state rate outside declared bounds"}
	if state.expected_short_inflation_pct <= -100.0 or state.expected_long_inflation_pct <= -100.0 or state.annualized_quarterly_inflation_pct <= -100.0 or abs(state.guidance_inflation_sensitivity) > params.guidance_sensitivity_limit or abs(state.guidance_output_gap_sensitivity) > params.guidance_sensitivity_limit:
		return {"ok": false, "error": "state inflation or guidance outside declared bounds"}
	if state.asset_stock_pct_initial_gdp < 0.0 or state.asset_stock_pct_initial_gdp > state.asset_stock_capacity_pct_initial_gdp or state.asset_stock_capacity_pct_initial_gdp < 0.0 or state.initial_asset_stock_pct_initial_gdp < 0.0 or state.outstanding_liquidity_pct_initial_gdp < 0.0 or state.funding_need_pct_initial_gdp < 0.0 or state.eligible_collateral_pct_initial_gdp < 0.0 or state.liquidity_repayment_pct_initial_gdp < 0.0 or state.liquidity_applied_pct_initial_gdp < 0.0 or state.uncovered_funding_pct_initial_gdp < 0.0:
		return {"ok": false, "error": "asset or liquidity stock outside physical capacity"}
	if state.credit_spread_pct < 0.0 or state.credit_risk_wedge_pct < 0.0 or state.solvency_risk_wedge_pct < 0.0 or state.inflation_miss_memory_pct < 0.0 or state.public_hardship_memory < 0.0 or state.current_hardship < 0.0:
		return {"ok": false, "error": "risk, inflation memory or hardship memory outside domain"}
	if state.asset_stock_capacity_pct_initial_gdp < state.initial_asset_stock_pct_initial_gdp or state.initial_asset_stock_pct_initial_gdp > params.asset_stock_capacity_pct_initial_gdp:
		return {"ok": false, "error": "asset stock baseline exceeds declared capacity"}
	var implied_output: float = state.potential_output_index * (1.0 + state.output_gap_pct / 100.0)
	if abs(implied_output - state.actual_output_index) > 1e-7:
		return {"ok": false, "error": "actual output index conflicts with potential output and gap"}
	return {"ok": true}


func _validate_policy(policy: Dictionary, params: Dictionary) -> Dictionary:
	for key in POLICY_KEYS:
		if not policy.has(key) or typeof(policy[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(policy[key])):
			return {"ok": false, "error": "%s: missing or nonfinite %s" % [POLICY_REQUIRED_HINT, key]}
	for key in policy:
		if key not in POLICY_KEYS:
			return {"ok": false, "error": "unknown policy control: %s" % key}
	if policy.policy_rate_request_pct < params.policy_rate_min_pct or policy.policy_rate_request_pct > params.policy_rate_max_pct or policy.guidance_rate_pct < params.policy_rate_min_pct or policy.guidance_rate_pct > params.policy_rate_max_pct:
		return {"ok": false, "error": "rate control outside declared bounds"}
	if abs(policy.guidance_inflation_sensitivity) > params.guidance_sensitivity_limit or abs(policy.guidance_output_gap_sensitivity) > params.guidance_sensitivity_limit:
		return {"ok": false, "error": "guidance sensitivity outside declared bounds"}
	if abs(policy.asset_flow_request_pct_initial_gdp) > params.asset_flow_request_limit_pct_initial_gdp or policy.liquidity_request_pct_initial_gdp < 0.0 or policy.liquidity_request_pct_initial_gdp > params.liquidity_request_limit_pct_initial_gdp:
		return {"ok": false, "error": "tool request outside declared bounds"}
	return {"ok": true}


func _validate_shocks(shocks: Dictionary) -> Dictionary:
	for key in shocks:
		if not SHOCK_LIMITS.has(key):
			return {"ok": false, "error": "unknown exogenous input: %s" % key}
		if typeof(shocks[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(shocks[key])):
			return {"ok": false, "error": "nonfinite exogenous input: %s" % key}
		var magnitude: float = float(shocks[key])
		if key == "potential_growth_pct":
			if magnitude < -20.0 or magnitude > SHOCK_LIMITS[key]:
				return {"ok": false, "error": "exogenous input outside declared domain: %s" % key}
		elif key in ["supply_innovation_pct", "r_star_change_pct", "r_star_reference_change_pct", "structural_unemployment_change_pct", "demand_shock_pct"]:
			if abs(magnitude) > SHOCK_LIMITS[key]:
				return {"ok": false, "error": "exogenous input outside declared domain: %s" % key}
		elif magnitude < 0.0 or magnitude > SHOCK_LIMITS[key]:
			return {"ok": false, "error": "exogenous input outside declared domain: %s" % key}
	return {"ok": true}


func _four_quarter_inflation(history: Array, multiplier: float) -> float:
	return multiplier * (history[history.size() - 1] / history[0] - 1.0)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "file not found: %s" % path}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		return {"ok": false, "error": "invalid JSON in %s" % path}
	return {"ok": true, "value": parsed}
