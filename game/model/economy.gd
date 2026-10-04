extends RefCounted

const PARAMETER_KEYS := [
	"inflation_target_pct", "quarters_per_year", "percent_multiplier",
	"initial_output_index", "initial_price_index", "initial_potential_growth_pct",
	"initial_inflation_rate_pct", "initial_expected_short_inflation_pct",
	"initial_expected_long_inflation_pct", "initial_policy_rate_pct", "initial_r_star_pct",
	"initial_structural_unemployment_pct", "initial_unemployment_pct", "initial_output_gap_pct",
	"initial_credibility", "initial_public_support", "initial_asset_stock_pct_initial_gdp",
	"initial_term_premium_pct",
	"minimum_rate_increment_pct", "negative_rate_efficacy_scale_pct",
	"policy_inflation_response", "policy_output_gap_response",
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
	"normal_credit_spread_pct",
	"public_support_base", "public_inflation_burden_weight",
	"public_unemployment_burden_weight", "public_hardship_memory_persistence",
	"public_hardship_memory_weight", "public_support_adjustment",
	"deferred_demand_share", "demand_cancellation_fraction",
	"demand_release_base_fraction", "demand_release_max_fraction",
	"demand_release_backlog_scale_pct", "demand_release_financing_scale_pct",
	"r_star_reversion_persistence", "short_expectation_anchor_weight",
	"portfolio_premium_max_shift_pct", "portfolio_premium_scale_pct_gdp",
	"treasury_duration_years", "mbs_duration_years", "treasury_reinvestment_maturity_quarters",
	"mbs_base_repayment_fraction", "mbs_repayment_rate_scale_pct", "mbs_repayment_relative_response",
	"initial_reserves_pct_initial_gdp", "initial_currency_pct_initial_gdp", "initial_treasury_account_pct_initial_gdp",
	"reserve_buffer_pct_current_gdp", "reserve_clear_pct_current_gdp", "reserve_scarcity_sensitivity_pct",
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
	"funding_need_pct_initial_gdp": INF,
	"refinancing_need_pct_initial_gdp": INF,
	"rrp_encumbered_collateral_pct_initial_gdp": INF,
	"rrp_uptake_fraction": 1.0,
	"eligible_collateral_pct_initial_gdp": INF,
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
const POLICY_SWITCHES := {"reinvest_principal":true, "maintain_ample_reserves":true, "sterilize_purchases":false}
const BALANCE_STOCK_KEYS := [
	"initial_actual_output_index", "initial_price_index", "initial_duration_equivalent_pct_initial_gdp",
	"initial_portfolio_premium_pct", "initial_mbs_financing_rate_pct",
	"mbs_stock_pct_initial_gdp", "reserves_pct_initial_gdp", "reverse_repo_pct_initial_gdp",
	"currency_pct_initial_gdp", "treasury_account_pct_initial_gdp", "capital_other_pct_initial_gdp",
]
const BALANCE_DIAGNOSTICS := [
	"decision_nominal_gdp_ratio", "ending_nominal_gdp_ratio", "duration_equivalent_pct_initial_gdp",
	"total_assets_pct_initial_gdp", "total_asset_change_pct_initial_gdp", "principal_due_pct_initial_gdp",
	"treasury_redemption_pct_initial_gdp", "treasury_funding_transfer_pct_initial_gdp",
	"mbs_repayment_pct_initial_gdp", "bill_redemption_pct_initial_gdp", "bill_funding_transfer_pct_initial_gdp", "mbs_repayment_fraction",
	"principal_runoff_pct_initial_gdp", "principal_reinvestment_pct_initial_gdp",
	"treasury_reinvestment_pct_initial_gdp", "mbs_reinvestment_pct_initial_gdp", "bill_rollover_pct_initial_gdp",
	"long_securities_runoff_pct_initial_gdp", "discretionary_purchase_pct_initial_gdp",
	"reserve_maintenance_purchase_pct_initial_gdp", "currency_conversion_pct_initial_gdp",
	"reverse_repo_closed_pct_initial_gdp", "reserves_before_accommodation_pct_initial_gdp",
	"reserve_buffer_pct_initial_gdp", "reserve_clear_pct_initial_gdp", "reserve_scarcity_wedge_pct",
	"local_access_wedge_pct", "refinancing_request_pct_initial_gdp", "refinancing_need_pct_initial_gdp",
	"eligible_local_need_pct_initial_gdp", "lending_collateral_capacity_pct_initial_gdp",
	"liquidity_local_applied_pct_initial_gdp", "liquidity_refinancing_applied_pct_initial_gdp",
	"liquidity_new_need_applied_pct_initial_gdp", "liquidity_aggregate_applied_pct_initial_gdp",
	"liquidity_aggregate_need_pct_initial_gdp", "liquidity_aggregate_offer_binding", "liquidity_aggregate_collateral_binding",
	"uncovered_new_funding_pct_initial_gdp", "uncovered_refinancing_pct_initial_gdp",
	"liquidity_offer_binding", "liquidity_collateral_binding", "liquidity_eligibility_binding",
	"sterilization_requested_pct_initial_gdp", "sterilization_planned_pct_initial_gdp",
	"sterilization_applied_pct_initial_gdp", "sterilization_unfulfilled_pct_initial_gdp",
	"sterilization_collateral_available_pct_initial_gdp", "sterilization_uptake_fraction",
	"sterilization_uptake_binding", "sterilization_collateral_binding", "sterilization_reserve_binding",
	"sterilized_principal_runoff_pct_initial_gdp", "sterilized_principal_reinvestment_pct_initial_gdp",
	"principal_ledger_error_pct_initial_gdp",
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
		"financial_restraint_gap_pct": 0.0,
		"asset_stock_pct_initial_gdp": params.initial_asset_stock_pct_initial_gdp,
		"initial_asset_stock_pct_initial_gdp": params.initial_asset_stock_pct_initial_gdp,
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
	var reference := load_portfolio_reference()
	if not reference.ok:
		return reference
	var ref: Dictionary = reference.value
	var treasury_share: float = float(ref.source_treasury_principal_usd) / (float(ref.source_treasury_principal_usd) + float(ref.mbs_stock_billion_usd) * 1e9)
	var treasuries: Array = []
	for weight in ref.treasury_maturity_weights:
		treasuries.append(state.asset_stock_pct_initial_gdp * treasury_share * float(weight))
	state.treasury_cohorts_pct_initial_gdp = treasuries
	state.sterilized_treasury_cohorts_pct_initial_gdp = _zero_cohorts(120)
	state.bill_cohorts_pct_initial_gdp = _zero_cohorts(4)
	state.mbs_stock_pct_initial_gdp = state.asset_stock_pct_initial_gdp * (1.0 - treasury_share)
	state.initial_asset_stock_pct_initial_gdp = state.asset_stock_pct_initial_gdp
	state.initial_actual_output_index = state.actual_output_index
	state.initial_price_index = state.price_index
	state.initial_portfolio_premium_pct = state.term_premium_pct
	state.initial_duration_equivalent_pct_initial_gdp = _cohort_sum(treasuries) + state.mbs_stock_pct_initial_gdp * (params.mbs_duration_years / params.treasury_duration_years)
	state.reserves_pct_initial_gdp = params.initial_reserves_pct_initial_gdp
	state.reverse_repo_pct_initial_gdp = 0.0
	state.currency_pct_initial_gdp = params.initial_currency_pct_initial_gdp
	state.treasury_account_pct_initial_gdp = params.initial_treasury_account_pct_initial_gdp
	# Reconcile only once; transitions preserve this signed principal residual.
	state.capital_other_pct_initial_gdp = state.asset_stock_pct_initial_gdp - state.reserves_pct_initial_gdp - state.currency_pct_initial_gdp - state.treasury_account_pct_initial_gdp
	for key in BALANCE_DIAGNOSTICS:
		state[key] = 0.0
	state.decision_nominal_gdp_ratio = 1.0
	state.ending_nominal_gdp_ratio = 1.0
	state.duration_equivalent_pct_initial_gdp = state.initial_duration_equivalent_pct_initial_gdp
	state.total_assets_pct_initial_gdp = state.asset_stock_pct_initial_gdp
	state.reserve_buffer_pct_initial_gdp = params.reserve_buffer_pct_current_gdp
	state.reserve_clear_pct_initial_gdp = params.reserve_clear_pct_current_gdp
	state.sterilization_uptake_fraction = 1.0
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
	state.merge(_rate_conditions(state, state.policy_rate_pct, state.policy_rate_pct, state.term_premium_pct, state.credit_spread_pct, state.r_star_pct, params), true)
	state.initial_mbs_financing_rate_pct = state.long_yield_pct + state.credit_spread_pct
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
	var rate_request: float = policy.policy_rate_request_pct
	var rate: float = rate_request
	var balance := _balance_sheet_step(state, policy, shocks, params)
	if not balance.ok:
		return balance
	var ledger: Dictionary = balance.updates
	var asset_request: float = policy.asset_flow_request_pct_initial_gdp
	var asset_delta: float = ledger.asset_flow_applied_pct_initial_gdp
	var asset_stock: float = ledger.asset_stock_pct_initial_gdp
	var term_premium: float = ledger.term_premium_pct
	var liquidity_request: float = policy.liquidity_request_pct_initial_gdp
	var repayment: float = ledger.liquidity_repayment_pct_initial_gdp
	var funding_need: float = shocks.get("funding_need_pct_initial_gdp", 0.0)
	var collateral: float = shocks.get("eligible_collateral_pct_initial_gdp", 0.0)
	var liquidity_delta: float = ledger.liquidity_applied_pct_initial_gdp
	var outstanding_liquidity: float = ledger.outstanding_liquidity_pct_initial_gdp
	var uncovered_funding: float = ledger.uncovered_funding_pct_initial_gdp
	var solvency_wedge: float = state.solvency_risk_wedge_pct * params.solvency_risk_persistence + shocks.get("solvency_risk_innovation_pct", 0.0)
	var credit_wedge: float = ledger.reserve_scarcity_wedge_pct + ledger.local_access_wedge_pct + solvency_wedge + shocks.get("credit_risk_innovation_pct", 0.0)
	var credit_spread: float = params.normal_credit_spread_pct + credit_wedge

	var guide_rate: float = policy.guidance_rate_pct
	var guide_infl_sensitivity: float = policy.guidance_inflation_sensitivity
	var guide_gap_sensitivity: float = policy.guidance_output_gap_sensitivity
	var prior_commitment := rate
	if state.guidance_active:
		prior_commitment = conditional_commitment(state, params)
	var followthrough := exp(-abs(rate - prior_commitment) / params.credibility_followthrough_tolerance_pct) if state.guidance_active else 1.0
	var credibility: float = state.credibility
	var rstar_reference: float = state.r_star_reference_pct + shocks.get("r_star_reference_change_pct", 0.0)
	var rstar: float = rstar_reference + params.r_star_reversion_persistence * (state.r_star_pct - state.r_star_reference_pct) + shocks.get("r_star_change_pct", 0.0)
	var rate_conditions := _rate_conditions(state, rate, guide_rate, term_premium, credit_spread, rstar, params)
	var spot_financial_gap: float = rate_conditions.spot_financial_gap_pct
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
	var miss_memory: float = params.credibility_miss_persistence * state.inflation_miss_memory_pct \
		+ (1.0 - params.credibility_miss_persistence) * abs(state.four_quarter_inflation_pct - params.inflation_target_pct)
	var inflation_performance := exp(-miss_memory / params.credibility_miss_tolerance_pct)
	var stance_adequacy: float = rate_conditions.stance_adequacy_score
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
		"public_support": support,
		"public_hardship_memory": hardship_memory,
		"current_hardship": hardship,
	}
	updates.merge(ledger, true)
	updates.merge(rate_conditions, true)
	for key in updates:
		next[key] = updates[key]
	next.ending_nominal_gdp_ratio = nominal_gdp_ratio(next)
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
	for key in BALANCE_DIAGNOSTICS:
		trace[key] = next[key]
	trace.merge(rate_conditions, true)
	return {"ok": true, "state": next, "trace": trace}


func load_portfolio_reference(path: String = "res://model/portfolio_reference.json") -> Dictionary:
	var parsed := _read_json(path)
	if not parsed.ok:
		return parsed
	var valid := _validate_portfolio_reference(parsed.value)
	return parsed if valid.ok else valid


func _validate_portfolio_reference(reference: Variant) -> Dictionary:
	if typeof(reference) != TYPE_DICTIONARY or reference.get("schema_version") != 1:
		return {"ok":false,"error":"invalid portfolio reference schema"}
	var weights: Variant = reference.get("treasury_maturity_weights")
	if typeof(weights) != TYPE_ARRAY or weights.size() != 120:
		return {"ok":false,"error":"Treasury reference requires120 maturity weights"}
	for weight in weights:
		if typeof(weight) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(weight)) or weight < 0.0:
			return {"ok":false,"error":"invalid Treasury maturity weight"}
	if abs(_cohort_sum(weights) - 1.0) > 1e-12:
		return {"ok":false,"error":"Treasury maturity weights must be normalized"}
	var principal: Variant = reference.get("source_treasury_principal_usd")
	if typeof(principal) != TYPE_STRING or not principal.is_valid_float() or not is_finite(float(principal)) or float(principal) <= 0.0:
		return {"ok":false,"error":"invalid observed Treasury principal"}
	for key in ["mbs_monthly_principal_billion_usd", "mbs_stock_billion_usd", "market_treasury_wam_years", "treasury_duration_years", "mbs_duration_years"]:
		if not reference.has(key) or typeof(reference[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(reference[key])) or reference[key] <= 0.0:
			return {"ok":false,"error":"invalid portfolio observation: %s" % key}
	return {"ok":true}


func nominal_gdp_ratio(state: Dictionary) -> float:
	# Actual initial output includes the initial scenario gap. PCE proxies the GDP deflator.
	return (state.actual_output_index / state.initial_actual_output_index) * (state.price_index / state.initial_price_index)


func _portfolio_premium(exposure_difference: float, nominal_ratio: float, anchor: float, params: Dictionary) -> float:
	if exposure_difference == 0.0:
		return anchor
	var log_ratio: float = log(abs(exposure_difference)) - log(nominal_ratio) - log(params.portfolio_premium_scale_pct_gdp)
	var response := signf(exposure_difference) if log_ratio > log(20.0) else tanh(signf(exposure_difference) * exp(log_ratio))
	return anchor - params.portfolio_premium_max_shift_pct * response


func _mbs_repayment_fraction(state: Dictionary, params: Dictionary) -> float:
	var lagged_financing: float = state.long_yield_pct + state.credit_spread_pct
	return params.mbs_base_repayment_fraction * (1.0 + params.mbs_repayment_relative_response * tanh((state.initial_mbs_financing_rate_pct - lagged_financing) / params.mbs_repayment_rate_scale_pct))


func _zero_cohorts(count: int) -> Array:
	var cohorts: Array = []
	cohorts.resize(count)
	cohorts.fill(0.0)
	return cohorts


func _cohort_sum(cohorts: Array) -> float:
	var total := 0.0
	for principal in cohorts:
		total += float(principal)
	return total


func _aged_cohorts(cohorts: Array) -> Array:
	var aged := cohorts.slice(1)
	aged.append(0.0)
	return aged


func _add_treasury(cohorts: Array, principal: float, maturity: float) -> void:
	var lower := int(floor(maturity))
	var upper_weight := maturity - lower
	cohorts[lower - 1] += principal * (1.0 - upper_weight)
	if upper_weight > 0.0:
		cohorts[lower] += principal * upper_weight


func _principal_net(legs: Array) -> float:
	# Cancel opposite principal legs before summing: large simultaneous flows need not overflow.
	var credits: Array = []
	var debits: Array = []
	for leg in legs:
		if not is_finite(float(leg)):
			return NAN
		if leg > 0.0:
			credits.append(float(leg))
		elif leg < 0.0:
			debits.append(-float(leg))
	credits.sort()
	debits.sort()
	while not credits.is_empty() and not debits.is_empty():
		var credit: float = credits.pop_back()
		var debit: float = debits.pop_back()
		if credit > debit:
			credits.append(credit - debit)
		elif debit > credit:
			debits.append(debit - credit)
	return _cohort_sum(credits) - _cohort_sum(debits)


func _validate_balance_state(state: Dictionary) -> Dictionary:
	for key in ["treasury_cohorts_pct_initial_gdp", "sterilized_treasury_cohorts_pct_initial_gdp", "bill_cohorts_pct_initial_gdp"]:
		var count := 4 if key == "bill_cohorts_pct_initial_gdp" else 120
		if not state.has(key) or typeof(state[key]) != TYPE_ARRAY or state[key].size() != count:
			return {"ok":false,"error":"invalid balance cohort shape: %s" % key}
		for principal in state[key]:
			if typeof(principal) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(principal)) or principal < 0.0:
				return {"ok":false,"error":"invalid balance cohort principal: %s" % key}
	for q in range(120):
		if state.sterilized_treasury_cohorts_pct_initial_gdp[q] > state.treasury_cohorts_pct_initial_gdp[q]:
			return {"ok":false,"error":"sterilized Treasury tag exceeds actual cohort"}
	for key in ["mbs_stock_pct_initial_gdp", "reserves_pct_initial_gdp", "reverse_repo_pct_initial_gdp", "currency_pct_initial_gdp", "treasury_account_pct_initial_gdp", "initial_duration_equivalent_pct_initial_gdp"]:
		if state[key] < 0.0:
			return {"ok":false,"error":"negative principal stock: %s" % key}
	if state.initial_actual_output_index <= 0.0 or state.initial_price_index <= 0.0 or not is_finite(nominal_gdp_ratio(state)) or nominal_gdp_ratio(state) <= 0.0:
		return {"ok":false,"error":"observed nominal GDP ratio must be positive and representable"}
	var tagged_total := _cohort_sum(state.sterilized_treasury_cohorts_pct_initial_gdp)
	if state.reverse_repo_pct_initial_gdp > tagged_total + 1e-12 * tagged_total:
		return {"ok":false,"error":"policy RRP liability exceeds tagged Treasury principal"}
	var securities: float = _cohort_sum(state.treasury_cohorts_pct_initial_gdp) + _cohort_sum(state.bill_cohorts_pct_initial_gdp) + state.mbs_stock_pct_initial_gdp
	var assets: float = securities + state.outstanding_liquidity_pct_initial_gdp
	var liabilities: float = state.reserves_pct_initial_gdp + state.reverse_repo_pct_initial_gdp + state.currency_pct_initial_gdp + state.treasury_account_pct_initial_gdp
	var tolerance: float = 1e-7 + 1e-12 * max(assets, liabilities, abs(state.capital_other_pct_initial_gdp))
	if not is_finite(assets) or not is_finite(liabilities) or abs(securities - state.asset_stock_pct_initial_gdp) > tolerance or abs(assets - liabilities - state.capital_other_pct_initial_gdp) > tolerance:
		return {"ok":false,"error":"principal ledger does not reconcile or is unrepresentable"}
	if abs(state.total_assets_pct_initial_gdp - assets) > tolerance:
		return {"ok":false,"error":"total assets diagnostic conflicts with principal ledger"}
	return {"ok":true}


func _balance_sheet_step(state: Dictionary, policy: Dictionary, shocks: Dictionary, params: Dictionary) -> Dictionary:
	var n := nominal_gdp_ratio(state)
	var reinvest: bool = policy.get("reinvest_principal", POLICY_SWITCHES.reinvest_principal)
	var maintain: bool = policy.get("maintain_ample_reserves", POLICY_SWITCHES.maintain_ample_reserves)
	var sterilize: bool = policy.get("sterilize_purchases", POLICY_SWITCHES.sterilize_purchases)
	var request: float = policy.asset_flow_request_pct_initial_gdp
	var purchase := maxf(0.0, request)
	var repayment_fraction := _mbs_repayment_fraction(state, params)
	var treasury_due: float = state.treasury_cohorts_pct_initial_gdp[0]
	var mbs_due: float = state.mbs_stock_pct_initial_gdp * repayment_fraction
	var bill_due: float = state.bill_cohorts_pct_initial_gdp[0]
	var due: float = treasury_due + mbs_due + bill_due
	var runoff: float = minf(-request, due) if request < 0.0 else (0.0 if reinvest else due)
	var runoff_share: float = runoff / due if due > 0.0 else 0.0
	var treasury_runoff := treasury_due * runoff_share
	var mbs_runoff := mbs_due * runoff_share
	var reinvest_share := 1.0 - runoff_share
	var treasury_roll := treasury_due * reinvest_share
	var mbs_roll := mbs_due * reinvest_share
	var bill_roll := bill_due * reinvest_share
	var treasury := _aged_cohorts(state.treasury_cohorts_pct_initial_gdp)
	var bills := _aged_cohorts(state.bill_cohorts_pct_initial_gdp)
	_add_treasury(treasury, treasury_roll, params.treasury_reinvestment_maturity_quarters)
	_add_treasury(treasury, purchase, params.treasury_reinvestment_maturity_quarters)
	bills[3] += bill_roll
	var mbs: float = state.mbs_stock_pct_initial_gdp - mbs_runoff
	var tags := _aged_cohorts(state.sterilized_treasury_cohorts_pct_initial_gdp) if sterilize else _zero_cohorts(120)
	var tagged_due: float = state.sterilized_treasury_cohorts_pct_initial_gdp[0] if sterilize else 0.0
	var tagged_runoff := tagged_due * runoff_share
	var tagged_roll := tagged_due * reinvest_share
	if sterilize:
		_add_treasury(tags, tagged_roll, params.treasury_reinvestment_maturity_quarters)
		_add_treasury(tags, purchase, params.treasury_reinvestment_maturity_quarters)
	var desired_absorption := _cohort_sum(tags)
	var uptake: float = shocks.get("rrp_uptake_fraction", 1.0)
	# Exclude next-quarter maturity; quarterly snapshots assume repeated overnight renewal.
	var available_collateral: float = maxf(0.0, _principal_net([_cohort_sum(treasury), _cohort_sum(bills), -float(treasury[0]), -float(bills[0]), -float(shocks.get("rrp_encumbered_collateral_pct_initial_gdp", 0.0))]))
	var uptake_absorption := desired_absorption * uptake
	var planned_absorption := minf(uptake_absorption, available_collateral)
	var currency: float = params.initial_currency_pct_initial_gdp * n
	var currency_conversion: float = currency - state.currency_pct_initial_gdp
	var old_loan_due: float = state.outstanding_liquidity_pct_initial_gdp
	# Treasury redemption and its assumed private funding leg exactly net at TGA.
	var reserve_base := _principal_net([state.reserves_pct_initial_gdp, state.reverse_repo_pct_initial_gdp, purchase, -runoff, -old_loan_due, -currency_conversion])
	var offer: float = policy.liquidity_request_pct_initial_gdp
	var new_need: float = shocks.get("funding_need_pct_initial_gdp", 0.0)
	var refinancing_request: float = shocks.get("refinancing_need_pct_initial_gdp", 0.0)
	var refinancing_need := minf(refinancing_request, old_loan_due)
	var collateral: float = shocks.get("eligible_collateral_pct_initial_gdp", 0.0)
	var eligibility: float = shocks.get("liquidity_eligibility_pct", 0.0) / 100.0
	var capacity: float = collateral * (1.0 - float(shocks.get("collateral_haircut_pct", 0.0)) / 100.0) * eligibility
	var eligible_refinancing := refinancing_need * eligibility
	var eligible_new := new_need * eligibility
	var eligible_local := eligible_refinancing + eligible_new
	var local: float = minf(offer, minf(capacity, eligible_local))
	var local_refinancing := minf(local, eligible_refinancing)
	var local_new := local - local_refinancing
	var uncovered_new := new_need - local_new
	var uncovered_refinancing := refinancing_need - local_refinancing
	var uncovered := uncovered_new + uncovered_refinancing
	var buffer: float = params.reserve_buffer_pct_current_gdp * n
	var clear: float = params.reserve_clear_pct_current_gdp * n
	var aggregate := 0.0
	var aggregate_need := 0.0
	var maintenance := 0.0
	var absorption := planned_absorption
	var local_after_absorption := _principal_net([reserve_base, local, -planned_absorption])
	if maintain:
		maintenance = maxf(0.0, _principal_net([buffer, -local_after_absorption]))
	else:
		aggregate_need = maxf(0.0, _principal_net([clear, -local_after_absorption]))
		aggregate = minf(maxf(0.0, offer - local), minf(maxf(0.0, capacity - local), aggregate_need))
		absorption = minf(planned_absorption, maxf(0.0, _principal_net([reserve_base, local, aggregate])))
	var loans := local + aggregate
	var reserves := _principal_net([reserve_base, local, aggregate, -absorption, maintenance])
	if not is_finite(reserves) or not is_finite(currency) or not is_finite(buffer) or not is_finite(clear) or clear <= 0.0 or not is_finite(eligible_local) or not is_finite(uncovered) or not is_finite(loans):
		return {"ok":false,"error":"unrepresentable principal ledger quantity"}
	if reserves < 0.0 or state.treasury_account_pct_initial_gdp < 0.0:
		return {"ok":false,"error":"infeasible mandatory settlement after simultaneous principal netting"}
	bills[3] += maintenance
	var scarcity: float = 0.0 if reserves >= clear else params.reserve_scarcity_sensitivity_pct * pow(1.0 - reserves / clear, 2.0)
	var local_access: float = params.funding_spread_sensitivity * uncovered
	var duration: float = _cohort_sum(treasury) + mbs * (params.mbs_duration_years / params.treasury_duration_years)
	var securities: float = _principal_net([state.asset_stock_pct_initial_gdp, purchase, -runoff, maintenance])
	var assets: float = securities + loans
	var ledger_error := _principal_net([assets, -reserves, -absorption, -currency, -state.treasury_account_pct_initial_gdp, -state.capital_other_pct_initial_gdp])
	var updates := {
		"treasury_cohorts_pct_initial_gdp":treasury, "sterilized_treasury_cohorts_pct_initial_gdp":tags,
		"bill_cohorts_pct_initial_gdp":bills, "mbs_stock_pct_initial_gdp":mbs,
		"reserves_pct_initial_gdp":reserves, "reverse_repo_pct_initial_gdp":absorption,
		"currency_pct_initial_gdp":currency, "treasury_account_pct_initial_gdp":state.treasury_account_pct_initial_gdp,
		"capital_other_pct_initial_gdp":state.capital_other_pct_initial_gdp,
		"asset_stock_pct_initial_gdp":securities, "asset_flow_applied_pct_initial_gdp":purchase - runoff,
		"term_premium_pct":_portfolio_premium(duration - state.initial_duration_equivalent_pct_initial_gdp, n, state.initial_portfolio_premium_pct, params),
		"outstanding_liquidity_pct_initial_gdp":loans, "liquidity_repayment_pct_initial_gdp":old_loan_due,
		"liquidity_applied_pct_initial_gdp":loans, "uncovered_funding_pct_initial_gdp":uncovered,
		"decision_nominal_gdp_ratio":n, "duration_equivalent_pct_initial_gdp":duration,
		"total_assets_pct_initial_gdp":assets, "total_asset_change_pct_initial_gdp":assets - state.total_assets_pct_initial_gdp,
		"principal_due_pct_initial_gdp":due, "treasury_redemption_pct_initial_gdp":treasury_due,
		"treasury_funding_transfer_pct_initial_gdp":treasury_due, "mbs_repayment_pct_initial_gdp":mbs_due,
		"bill_redemption_pct_initial_gdp":bill_due, "bill_funding_transfer_pct_initial_gdp":bill_due, "mbs_repayment_fraction":repayment_fraction,
		"principal_runoff_pct_initial_gdp":runoff, "principal_reinvestment_pct_initial_gdp":due - runoff,
		"treasury_reinvestment_pct_initial_gdp":treasury_roll, "mbs_reinvestment_pct_initial_gdp":mbs_roll,
		"bill_rollover_pct_initial_gdp":bill_roll, "long_securities_runoff_pct_initial_gdp":treasury_runoff + mbs_runoff,
		"discretionary_purchase_pct_initial_gdp":purchase, "reserve_maintenance_purchase_pct_initial_gdp":maintenance,
		"currency_conversion_pct_initial_gdp":currency_conversion, "reverse_repo_closed_pct_initial_gdp":state.reverse_repo_pct_initial_gdp,
		"reserves_before_accommodation_pct_initial_gdp":reserve_base,
		"reserve_buffer_pct_initial_gdp":buffer, "reserve_clear_pct_initial_gdp":clear,
		"reserve_scarcity_wedge_pct":scarcity, "local_access_wedge_pct":local_access,
		"refinancing_request_pct_initial_gdp":refinancing_request, "refinancing_need_pct_initial_gdp":refinancing_need,
		"eligible_local_need_pct_initial_gdp":eligible_local, "lending_collateral_capacity_pct_initial_gdp":capacity,
		"liquidity_local_applied_pct_initial_gdp":local, "liquidity_refinancing_applied_pct_initial_gdp":local_refinancing,
		"liquidity_new_need_applied_pct_initial_gdp":local_new, "liquidity_aggregate_applied_pct_initial_gdp":aggregate,
		"liquidity_aggregate_need_pct_initial_gdp":aggregate_need,
		"liquidity_aggregate_offer_binding":float(aggregate < aggregate_need and aggregate == maxf(0.0, offer - local)),
		"liquidity_aggregate_collateral_binding":float(aggregate < aggregate_need and aggregate == maxf(0.0, capacity - local)),
		"uncovered_new_funding_pct_initial_gdp":uncovered_new, "uncovered_refinancing_pct_initial_gdp":uncovered_refinancing,
		"liquidity_offer_binding":float(local < eligible_local and local == offer),
		"liquidity_collateral_binding":float(local < eligible_local and local == capacity), "liquidity_eligibility_binding":float(eligibility < 1.0 and (new_need > 0.0 or refinancing_need > 0.0)),
		"sterilization_requested_pct_initial_gdp":desired_absorption, "sterilization_planned_pct_initial_gdp":planned_absorption,
		"sterilization_applied_pct_initial_gdp":absorption, "sterilization_unfulfilled_pct_initial_gdp":desired_absorption - absorption,
		"sterilization_collateral_available_pct_initial_gdp":available_collateral, "sterilization_uptake_fraction":uptake,
		"sterilization_uptake_binding":float(uptake_absorption < desired_absorption),
		"sterilization_collateral_binding":float(available_collateral < uptake_absorption),
		"sterilization_reserve_binding":float(absorption < planned_absorption),
		"sterilized_principal_runoff_pct_initial_gdp":tagged_runoff, "sterilized_principal_reinvestment_pct_initial_gdp":tagged_roll,
		"principal_ledger_error_pct_initial_gdp":ledger_error,
	}
	return {"ok":true,"updates":updates}


func conditional_commitment(state: Dictionary, params: Dictionary) -> float:
	var implied: float = state.guidance_rate_pct \
		+ state.guidance_inflation_sensitivity * (state.four_quarter_inflation_pct - state.guidance_reference_inflation_pct) \
		+ state.guidance_output_gap_sensitivity * (state.output_gap_pct - state.guidance_reference_output_gap_pct)
	return roundf(implied / params.minimum_rate_increment_pct) * params.minimum_rate_increment_pct


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
	target = roundf(target / params.minimum_rate_increment_pct) * params.minimum_rate_increment_pct
	return {
		"policy_rate_request_pct": target,
		"guidance_rate_pct": target,
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


func load_shock_catalogue(path: String = "res://model/exogenous_shocks.json") -> Dictionary:
	var parsed := _read_json(path)
	return validate_shock_catalogue(parsed.value) if parsed.ok else parsed


const CATALOGUE_SHOCK_LIMITS := {
	"demand_shock_pct":0.80, "supply_innovation_pct":1.20,
	"funding_need_pct_initial_gdp":2.40, "solvency_risk_innovation_pct":0.35,
	"potential_growth_pct":INF, "structural_unemployment_change_pct":INF,
	"eligible_collateral_pct_initial_gdp":INF, "collateral_haircut_pct":INF,
	"liquidity_eligibility_pct":INF, "credit_risk_innovation_pct":INF,
}

func validate_shock_catalogue(records: Variant) -> Dictionary:
	if typeof(records) != TYPE_ARRAY or records.size() != 150:
		return {"ok":false,"error":"Shock catalogue requires150 ranked concepts."}
	var categories := {"energy":0,"financial_funding":0,"financial_solvency":0,"food":0,"health":0,
		"household_business_demand":0,"labor":0,"logistics_trade":0,"natural_disasters":0,"technology_productivity":0}
	var ids := {}
	var titles := {}
	var profiles := {}
	var accepted: Array = []
	for i in range(records.size()):
		var row: Variant = records[i]
		if typeof(row) != TYPE_DICTIONARY:
			return {"ok":false,"error":"Shock concept must be an object."}
		for field in ["id","title","category","mechanism","policy_dilemma","selection_reason"]:
			if typeof(row.get(field)) != TYPE_STRING or row[field].strip_edges().is_empty():
				return {"ok":false,"error":"Shock concept lacks %s." % field}
		if not row.id.is_valid_identifier() or row.id != row.id.to_lower() or ids.has(row.id) or titles.has(row.title.to_lower()) or not categories.has(row.category):
			return {"ok":false,"error":"Invalid or repeated shock identity/category."}
		var total := 0
		for score in ["distinctness","policy_tradeoff","recognizability","model_fit","replay_variety"]:
			var value: Variant = row.get(score)
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or value < 0 or value > 5 or value != int(value):
				return {"ok":false,"error":"Invalid editorial shock score."}
			total += int(value)
		if row.get("rank") != i + 1 or row.get("total") != total or typeof(row.get("accepted")) != TYPE_BOOL or row.accepted != (i < 50):
			return {"ok":false,"error":"Shock ranking/selection must retain the exact top50."}
		if i > 0 and not _shock_precedes(records[i - 1], row):
			return {"ok":false,"error":"Shock ranking is not in the reviewed strict order."}
		var duration: Variant = row.get("duration_quarters")
		if typeof(duration) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(duration)) or duration < 1 or duration > 4 or duration != int(duration) or typeof(row.get("shock_profile")) != TYPE_ARRAY or row.shock_profile.size() != int(duration):
			return {"ok":false,"error":"Shock profile requires one to four consecutive quarters."}
		if row.accepted or row.has("phase_briefings"):
			var briefings: Variant = row.get("phase_briefings")
			if typeof(briefings) != TYPE_ARRAY or briefings.size() != int(duration):
				return {"ok":false,"error":"Accepted shocks require current information for every phase."}
			for briefing in briefings:
				if typeof(briefing) != TYPE_DICTIONARY or briefing.size() != 2:
					return {"ok":false,"error":"Phase briefing must contain only title and policy dilemma."}
				for field in ["title", "policy_dilemma"]:
					if typeof(briefing.get(field)) != TYPE_STRING or briefing[field].strip_edges().is_empty():
						return {"ok":false,"error":"Phase briefing lacks %s." % field}
		for pulse in row.shock_profile:
			if typeof(pulse) != TYPE_DICTIONARY or not _validate_shocks(pulse).ok:
				return {"ok":false,"error":"Shock profile contains invalid economic inputs."}
			# INF means the existing engine domain applies, not an unbounded input.
			for field in pulse:
				if not CATALOGUE_SHOCK_LIMITS.has(field) or abs(pulse[field]) > CATALOGUE_SHOCK_LIMITS[field]:
					return {"ok":false,"error":"Shock profile exceeds its authored field/domain contract."}
			if pulse.has("funding_need_pct_initial_gdp"):
				for key in ["eligible_collateral_pct_initial_gdp","collateral_haircut_pct","liquidity_eligibility_pct"]:
					if not pulse.has(key):
						return {"ok":false,"error":"Funding concept must disclose collateral and eligibility."}
		var profile: String = JSON.stringify(row.shock_profile)
		if profiles.has(profile) or typeof(row.get("source_urls")) != TYPE_ARRAY or row.source_urls.is_empty():
			return {"ok":false,"error":"Shock profiles must differ and retain channel sources."}
		for url in row.source_urls:
			if typeof(url) != TYPE_STRING or not url.begins_with("https://"):
				return {"ok":false,"error":"Shock source must retain its HTTPS reference."}
		ids[row.id] = true
		titles[row.title.to_lower()] = true
		profiles[profile] = true
		categories[row.category] += 1
		if row.accepted:
			accepted.append(row)
	for count in categories.values():
		if count != 15:
			return {"ok":false,"error":"Shock catalogue requires fifteen candidates per category."}
	return {"ok":true,"records":records,"accepted":accepted}


static func _shock_precedes(a: Dictionary, b: Dictionary) -> bool:
	for key in ["total","policy_tradeoff","model_fit","distinctness","replay_variety","recognizability"]:
		if a[key] != b[key]:
			return a[key] > b[key]
	return a.id < b.id


func seeded_shock_path(seed: int, scenario: Dictionary, quarters: int) -> Array:
	return seeded_campaign(seed, scenario, quarters).get("shocks", [])


func seeded_campaign(seed: int, scenario: Dictionary, quarters: int) -> Dictionary:
	var context: Array = []
	if scenario.id == "mixed_crises":
		var catalogue := load_shock_catalogue()
		if not catalogue.ok:
			return catalogue
		scenario = scenario.duplicate(true)
		var concepts := {}
		var independent: Array = []
		for concept in catalogue.accepted:
			concepts[concept.id] = concept
			if concept.id not in ["private_bank_recapitalization","stable_private_deposits_return"]:
				independent.append(concept.id)
		var episodes := RandomNumberGenerator.new()
		episodes.seed = seed ^ 0x43414D50
		var bag: Array = []
		var followups: Array = []
		var onset := episodes.randi_range(12, 20)
		while onset < quarters:
			if bag.is_empty():
				bag = independent.duplicate()
				followups = ["private_bank_recapitalization","stable_private_deposits_return"]
			var id: String = bag.pop_at(episodes.randi_range(0, bag.size() - 1))
			_append_shock_episode(scenario, context, concepts[id], onset)
			var followup := "private_bank_recapitalization" if id in ["office_property_credit_losses","mortgage_lien_documentation_failure"] else "stable_private_deposits_return" if id in ["sound_bank_uninsured_run","bank_payment_float_failure","bank_dollar_rollover_squeeze"] else ""
			var followup_onset: int = onset + int(concepts[id].duration_quarters) + 1
			if followups.has(followup):
				followups.erase(followup)
				if followup_onset < quarters:
					_append_shock_episode(scenario, context, concepts[followup], followup_onset, id)
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
	return {"ok":true,"shocks":path,"episodes":context}


static func _append_shock_episode(scenario: Dictionary, context: Array, concept: Dictionary, onset: int, trigger: String = "") -> void:
	context.append({"id":concept.id,"quarter_index":onset,"trigger_id":trigger,
		"title":concept.title,"policy_dilemma":concept.policy_dilemma,
		"phase_briefings":concept.phase_briefings.duplicate(true),
		"duration_quarters":concept.duration_quarters,"shock_profile":concept.shock_profile.duplicate(true)})
	for q in range(concept.shock_profile.size()):
		var event: Dictionary = concept.shock_profile[q].duplicate(true)
		event.quarter_index = onset + q
		scenario.events.append(event)


static func _rate_on_grid(rate: float, increment: float) -> bool:
	var units := rate / increment
	return is_finite(units) and abs(units - round(units)) < 1e-6


static func _effective_rate(rate: float, scale: float) -> float:
	return rate if rate >= 0.0 else scale * tanh(rate / scale)


func _rate_conditions(state: Dictionary, rate: float, guide: float, premium: float, spread: float, rstar: float, params: Dictionary) -> Dictionary:
	var scale: float = params.negative_rate_efficacy_scale_pct
	var effective_rate := _effective_rate(rate, scale)
	var priced_guide: float = rate + state.credibility * (guide - rate)
	var effective_guide := _effective_rate(priced_guide, scale)
	var current_weight: float = params.long_yield_current_rate_weight
	var short_weight: float = params.real_rate_short_weight
	var long_yield: float = current_weight * effective_rate + (1.0 - current_weight) * effective_guide + premium
	var spread_gap: float = spread - params.normal_credit_spread_pct
	var spot: float = short_weight * (effective_rate - state.expected_short_inflation_pct) \
		+ (1.0 - short_weight) * (long_yield - params.initial_term_premium_pct - state.expected_long_inflation_pct) + spread_gap - rstar
	var target: float = params.policy_inflation_response * (state.four_quarter_inflation_pct - params.inflation_target_pct) + params.policy_output_gap_response * state.output_gap_pct
	# Hold other staged tools/guide fixed. Credibility1 makes the quote independent of rate.
	var floor_guide: float = _effective_rate(guide, scale) if state.credibility == 1.0 else -scale
	var floor_long: float = -current_weight * scale + (1.0 - current_weight) * floor_guide + premium
	var floor_spot: float = short_weight * (-scale - state.expected_short_inflation_pct) \
		+ (1.0 - short_weight) * (floor_long - params.initial_term_premium_pct - state.expected_long_inflation_pct) + spread_gap - rstar
	var upward_loading: float = short_weight + (1.0 - short_weight) * (current_weight + (1.0 - current_weight) * (1.0 - state.credibility))
	var distance: float = abs(spot - target)
	var best_distance: float = abs(spot - target) if upward_loading == 0.0 else max(0.0, floor_spot - target)
	var tolerance: float = params.credibility_stance_scale_pct
	var adequacy := exp(-max(0.0, distance - best_distance) / tolerance) * tolerance / (tolerance + best_distance)
	return {"effective_policy_rate_pct":effective_rate,"long_yield_pct":long_yield,
		"spot_financial_gap_pct":spot,"stance_target_gap_pct":target,"stance_distance_pct":distance,
		"stance_best_feasible_distance_pct":best_distance,"stance_adequacy_score":adequacy,
		"reaction_function_target_pct":rstar + state.expected_short_inflation_pct + target}


func _validate_parameters(params: Dictionary) -> Dictionary:
	for key in params:
		if key not in PARAMETER_KEYS:
			return {"ok":false,"error":"unknown parameter: %s" % key}
	for key in PARAMETER_KEYS:
		if not params.has(key) or typeof(params[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(params[key])):
			return {"ok": false, "error": "missing or nonfinite parameter: %s" % key}
	if params.public_support_base < 0.0 or params.public_support_base > 100.0 or params.public_support_adjustment < 0.0 or params.public_support_adjustment > 1.0 or params.normal_credit_spread_pct < 0.0:
		return {"ok": false, "error": "invalid public-support or normal-spread parameter"}
	for key in ["real_rate_gap_persistence", "output_gap_persistence", "inflation_persistence", "short_expectation_recent_weight", "supply_pressure_persistence", "long_expectation_adjustment", "unemployment_gap_persistence", "credibility_adjustment", "credibility_miss_persistence", "solvency_risk_persistence", "public_hardship_memory_persistence", "real_rate_short_weight", "long_yield_current_rate_weight"]:
		if params[key] < 0.0 or params[key] > 1.0:
			return {"ok": false, "error": "share parameter out of range: %s" % key}
	for key in ["deferred_demand_share", "demand_cancellation_fraction", "demand_release_base_fraction", "demand_release_max_fraction", "r_star_reversion_persistence", "short_expectation_anchor_weight"]:
		if params[key] < 0.0 or params[key] > 1.0:
			return {"ok": false, "error": "recovery fraction out of range: %s" % key}
	if params.demand_release_base_fraction > params.demand_release_max_fraction or params.demand_release_max_fraction + params.demand_cancellation_fraction > 1.0 or params.demand_release_backlog_scale_pct <= 0.0 or params.demand_release_financing_scale_pct <= 0.0:
		return {"ok": false, "error": "inconsistent demand-release fractions or nonpositive recovery scale"}
	if params.minimum_rate_increment_pct <= 0.0 or params.negative_rate_efficacy_scale_pct <= 0.0 or params.initial_asset_stock_pct_initial_gdp < 0.0 or params.inflation_target_pct != 2.0:
		return {"ok": false, "error": "inconsistent bounds or unsupported target parameter"}
	if params.quarters_per_year != 4.0 or params.percent_multiplier != 100.0 or params.initial_output_index <= 0.0 or params.initial_price_index <= 0.0 or params.initial_structural_unemployment_pct <= 0.0 or params.initial_structural_unemployment_pct >= 100.0:
		return {"ok": false, "error": "invalid scale or initial reference parameter"}
	if params.initial_inflation_rate_pct <= -100.0 or params.initial_expected_short_inflation_pct <= -100.0 or params.initial_expected_long_inflation_pct <= -100.0 or params.initial_output_gap_pct <= -100.0 or not _rate_on_grid(params.initial_policy_rate_pct, params.minimum_rate_increment_pct):
		return {"ok": false, "error": "invalid initial inflation, output gap or rate"}
	if params.initial_credibility < 0.0 or params.initial_credibility > 1.0 or params.initial_public_support < 0.0 or params.initial_public_support > 100.0 or params.initial_unemployment_pct < 0.0 or params.initial_unemployment_pct > 100.0:
		return {"ok": false, "error": "initial bounded state outside its domain"}
	for key in ["guidance_sensitivity_limit", "policy_inflation_response", "policy_output_gap_response", "credibility_miss_tolerance_pct", "credibility_stance_scale_pct", "credibility_followthrough_tolerance_pct", "real_rate_output_sensitivity", "inflation_output_gap_sensitivity", "inflation_supply_sensitivity", "short_expectation_supply_sensitivity", "supply_output_gap_sensitivity", "unemployment_gap_sensitivity", "funding_spread_sensitivity", "public_inflation_burden_weight", "public_unemployment_burden_weight", "public_hardship_memory_weight"]:
		if params[key] < 0.0:
			return {"ok": false, "error": "negative sensitivity, scale or capacity: %s" % key}
	for key in ["portfolio_premium_max_shift_pct", "portfolio_premium_scale_pct_gdp", "treasury_duration_years", "mbs_duration_years", "mbs_repayment_rate_scale_pct", "reserve_clear_pct_current_gdp"]:
		if params[key] <= 0.0:
			return {"ok":false,"error":"balance transmission scale must be positive: %s" % key}
	if params.reserve_buffer_pct_current_gdp < params.reserve_clear_pct_current_gdp or params.initial_reserves_pct_initial_gdp < params.reserve_clear_pct_current_gdp or params.initial_currency_pct_initial_gdp < 0.0 or params.initial_treasury_account_pct_initial_gdp < 0.0 or params.reserve_scarcity_sensitivity_pct < 0.0:
		return {"ok":false,"error":"inconsistent reserve buffer, clear threshold or initial liabilities"}
	if params.mbs_base_repayment_fraction <= 0.0 or params.mbs_repayment_relative_response < 0.0 or params.mbs_repayment_relative_response >= 1.0 or params.mbs_base_repayment_fraction * (1.0 + params.mbs_repayment_relative_response) > 1.0 or params.treasury_reinvestment_maturity_quarters < 1.0 or params.treasury_reinvestment_maturity_quarters > 120.0:
		return {"ok":false,"error":"invalid physical MBS repayment or Treasury replacement maturity"}
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
		"asset_stock_pct_initial_gdp", "initial_asset_stock_pct_initial_gdp",
		"term_premium_pct", "asset_flow_request_pct_initial_gdp", "asset_flow_applied_pct_initial_gdp",
		"funding_need_pct_initial_gdp", "eligible_collateral_pct_initial_gdp", "outstanding_liquidity_pct_initial_gdp",
		"liquidity_repayment_pct_initial_gdp", "liquidity_request_pct_initial_gdp", "liquidity_applied_pct_initial_gdp",
		"uncovered_funding_pct_initial_gdp", "credit_spread_pct", "credit_risk_wedge_pct", "solvency_risk_wedge_pct",
		"supply_pressure_pct", "credibility", "inflation_miss_memory_pct", "guidance_rate_pct",
		"guidance_inflation_sensitivity", "guidance_output_gap_sensitivity", "guidance_reference_inflation_pct",
		"guidance_reference_output_gap_pct", "guidance_followthrough_score", "reaction_function_target_pct",
		"public_support", "public_hardship_memory", "current_hardship",
		"deferred_demand_pct", "demand_release_pct", "r_star_reference_pct",
		"effective_policy_rate_pct", "spot_financial_gap_pct", "stance_target_gap_pct",
		"stance_distance_pct", "stance_best_feasible_distance_pct", "stance_adequacy_score",
	]
	keys.append_array(BALANCE_STOCK_KEYS)
	keys.append_array(BALANCE_DIAGNOSTICS)
	for key in state:
		if key not in keys and key not in ["price_history", "guidance_active", "treasury_cohorts_pct_initial_gdp", "sterilized_treasury_cohorts_pct_initial_gdp", "bill_cohorts_pct_initial_gdp"]:
			return {"ok":false,"error":"unknown state field: %s" % key}
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
	if state.quarter_index < 0 or float(state.quarter_index) != int(state.quarter_index) or state.initial_annual_gdp_index <= 0.0 or state.potential_output_index <= 0.0 or state.actual_output_index <= 0.0 or state.price_index <= 0.0 or state.output_gap_pct <= -100.0 or state.structural_unemployment_pct <= 0.0 or state.structural_unemployment_pct >= 100.0 or state.unemployment_rate_pct < 0.0 or state.unemployment_rate_pct > 100.0 or state.credibility < 0.0 or state.credibility > 1.0 or state.public_support < 0.0 or state.public_support > 100.0:
		return {"ok": false, "error": "state violates positive-scale or bounded-domain invariant"}
	for quote in [state.policy_rate_pct, state.last_policy_rate_request_pct, state.guidance_rate_pct]:
		if not _rate_on_grid(quote, params.minimum_rate_increment_pct):
			return {"ok": false, "error": "state nominal rate or guidance outside quote grid"}
	if state.stance_distance_pct < 0.0 or state.stance_best_feasible_distance_pct < 0.0 or state.stance_adequacy_score < 0.0 or state.stance_adequacy_score > 1.0:
		return {"ok": false, "error": "invalid effective-stance diagnostics"}
	if state.expected_short_inflation_pct <= -100.0 or state.expected_long_inflation_pct <= -100.0 or state.annualized_quarterly_inflation_pct <= -100.0 or abs(state.guidance_inflation_sensitivity) > params.guidance_sensitivity_limit or abs(state.guidance_output_gap_sensitivity) > params.guidance_sensitivity_limit:
		return {"ok": false, "error": "state inflation or guidance outside declared bounds"}
	if state.asset_stock_pct_initial_gdp < 0.0 or state.initial_asset_stock_pct_initial_gdp < 0.0 or state.outstanding_liquidity_pct_initial_gdp < 0.0 or state.funding_need_pct_initial_gdp < 0.0 or state.eligible_collateral_pct_initial_gdp < 0.0 or state.liquidity_repayment_pct_initial_gdp < 0.0 or state.liquidity_applied_pct_initial_gdp < 0.0 or state.uncovered_funding_pct_initial_gdp < 0.0:
		return {"ok": false, "error": "asset or liquidity stock outside physical capacity"}
	if state.credit_spread_pct < 0.0 or state.credit_risk_wedge_pct < 0.0 or state.solvency_risk_wedge_pct < 0.0 or state.inflation_miss_memory_pct < 0.0 or state.public_hardship_memory < 0.0 or state.current_hardship < 0.0:
		return {"ok": false, "error": "risk, inflation memory or hardship memory outside domain"}
	var balance_check := _validate_balance_state(state)
	if not balance_check.ok:
		return balance_check
	var implied_output: float = state.potential_output_index * (1.0 + state.output_gap_pct / 100.0)
	if abs(implied_output - state.actual_output_index) > 1e-7:
		return {"ok": false, "error": "actual output index conflicts with potential output and gap"}
	return {"ok": true}


func _validate_policy(policy: Dictionary, params: Dictionary) -> Dictionary:
	for key in POLICY_KEYS:
		if not policy.has(key) or typeof(policy[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(policy[key])):
			return {"ok": false, "error": "%s: missing or nonfinite %s" % [POLICY_REQUIRED_HINT, key]}
	for key in policy:
		if key in POLICY_SWITCHES:
			if typeof(policy[key]) != TYPE_BOOL:
				return {"ok":false,"error":"optional %s must be boolean" % key}
		elif key not in POLICY_KEYS:
			return {"ok": false, "error": "unknown policy control: %s" % key}
	for quote in [policy.policy_rate_request_pct, policy.guidance_rate_pct]:
		if not _rate_on_grid(quote, params.minimum_rate_increment_pct):
			return {"ok": false, "error": "rate and guidance quotes require %.4f pp increments" % params.minimum_rate_increment_pct}
	if abs(policy.guidance_inflation_sensitivity) > params.guidance_sensitivity_limit or abs(policy.guidance_output_gap_sensitivity) > params.guidance_sensitivity_limit:
		return {"ok": false, "error": "guidance sensitivity outside declared bounds"}
	if policy.liquidity_request_pct_initial_gdp < 0.0:
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
