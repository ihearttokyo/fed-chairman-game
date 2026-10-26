extends RefCounted
## Pure quote preparation. No advance/save, future tape, or control mutation.
const Committee = preload("res://play/policy_committee.gd")
const Career = preload("res://play/career.gd")
const Economy = preload("res://model/economy.gd")
const FIELDS := ["four_quarter_inflation_pct", "unemployment_rate_pct", "uncovered_funding_pct_initial_gdp"]
var forecast_calls: int = 0

static func metrics(path: Dictionary) -> Dictionary:
	if not path.get("ok", false):
		return {"ok": false, "error": path.get("error", "Conditional path unavailable")}
	if not path.get("states") is Array or path.states.size() != 8:
		return {"ok": false, "error": "Eight-quarter path unavailable"}
	var peak: float = 0.0
	for state in path.states:
		if not state is Dictionary:
			return {"ok": false, "error": "Conditional state unavailable"}
		for field in FIELDS:
			if not state.get(field) is float and not state.get(field) is int:
				return {"ok": false, "error": "Conditional metric unavailable: " + field}
			if not is_finite(float(state[field])):
				return {"ok": false, "error": "Nonfinite conditional metric: " + field}
		if state.uncovered_funding_pct_initial_gdp < 0.0:
			return {"ok": false, "error": "Invalid unmet funding"}
		peak = maxf(peak, state.uncovered_funding_pct_initial_gdp)
	return {"ok": true, "values": [float(path.states[-1].four_quarter_inflation_pct), float(path.states[-1].unemployment_rate_pct), peak]}

static func value_text(value: float, funding: bool = false) -> String:
	if not is_finite(value):
		return "unavailable"
	if absf(value) >= 10000.0:
		return String.num_scientific(value)
	if funding:
		return Career.funding_amount_text(value)
	if value != 0.0 and absf(value) < 0.005:
		return ("−" if value < 0.0 else "+") + "<0.005"
	return "%.2f" % value

static func policy_for(choice: Dictionary, staged: Dictionary, params: Dictionary, nominal_gdp: float) -> Dictionary:
	var policy: Dictionary = staged.duplicate(true)
	policy.policy_rate_request_pct = choice.rate
	policy.guidance_rate_pct = choice.rate
	policy.guidance_inflation_sensitivity = params.policy_inflation_response
	policy.guidance_output_gap_sensitivity = params.policy_output_gap_response
	if choice.has("lending_offer_current_gdp"):
		policy.liquidity_request_pct_initial_gdp = choice.lending_offer_current_gdp * nominal_gdp
	return policy

func entry(career: Career, id: String, label: String, policy: Dictionary, summary: String, details: String = "") -> Dictionary:
	# Input validity is distinct from full-horizon settlement/projection success.
	var valid: Dictionary = career.model._validate_policy(policy, career.params)
	var projection: Dictionary = {"ok": false, "error": valid.get("error", "Invalid policy controls")}
	if valid.ok:
		forecast_calls += 1
		projection = metrics(career.forecast(policy))
	return {"id": id, "label": label, "policy": policy.duplicate(true), "valid": valid.ok,
		"validation_error": valid.get("error", ""), "projection": projection, "summary": summary, "details": details}

func build(career: Career, staged: Dictionary, horizon: int) -> Dictionary:
	forecast_calls = 0
	if career.state.is_empty() or career.decisions.size() >= horizon:
		return {"ok": false, "error": "Career complete. No active committee decision.", "entries": [], "forecast_calls": 0}
	var valid: Dictionary = career.model._validate_policy(staged, career.params)
	if not valid.ok:
		return {"ok": false, "error": "Staged controls invalid: " + valid.error, "entries": [], "forecast_calls": 0}
	var n: float = career.model.nominal_gdp_ratio(career.state)
	var held: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold")
	var entries: Array = [entry(career, "staged", "Current staged decision", staged, controls_text(staged, n)),
		entry(career, "hold", "Hold reference", held, controls_text(held, n), "Hold today's rate with matching data-dependent guidance. No new assets or loans; default reinvestment and reserve maintenance on, sterilization off.")]
	for choice in Committee.proposals(career.state, career.params, career.current_briefing(), n):
		var policy: Dictionary = policy_for(choice, staged, career.params, n)
		var item: Dictionary = entry(career, choice.id, choice.label, policy, controls_text(policy, n), choice.tradeoff)
		item.liquidity_current_gdp = choice.get("lending_offer_current_gdp", staged.liquidity_request_pct_initial_gdp / n)
		entries.append(item)
	return {"ok": true, "entries": entries, "forecast_calls": forecast_calls,
		"quarter": int(career.state.quarter_index), "horizon": horizon, "nominal_gdp": n,
		"diagnostic": int(career.state.quarter_index) + 8 > horizon,
		"references": [float(career.params.inflation_target_pct), float(career.state.structural_unemployment_pct), 0.0]}

static func controls_text(policy: Dictionary, n: float) -> String:
	return "Rate %s%% · guidance %s%% (responses %s / %s)\nAssets %s · loan offer %s (%% current GDP)\nReinvest %s · ample reserves %s · sterilize %s" % [value_text(policy.policy_rate_request_pct), value_text(policy.guidance_rate_pct), value_text(policy.guidance_inflation_sensitivity), value_text(policy.guidance_output_gap_sensitivity), value_text(policy.asset_flow_request_pct_initial_gdp / n, true), value_text(policy.liquidity_request_pct_initial_gdp / n, true), "on" if policy.get("reinvest_principal", Economy.POLICY_SWITCHES.reinvest_principal) else "off", "on" if policy.get("maintain_ample_reserves", Economy.POLICY_SWITCHES.maintain_ample_reserves) else "off", "on" if policy.get("sterilize_purchases", Economy.POLICY_SWITCHES.sterilize_purchases) else "off"]
