extends RefCounted
## Fictional public-information feedback rule, not an optimal policy.
## No evolving neutral rate, short expectations or future pulse is consumed.
const OBSERVATIONS := ["expected_long_inflation_pct", "four_quarter_inflation_pct", "output_gap_pct"]
const DESIGN_INPUTS := ["initial_r_star_pct", "inflation_target_pct", "policy_inflation_response", "policy_output_gap_response", "minimum_rate_increment_pct"]
static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
static func observe(state: Dictionary) -> Dictionary:
	var published := {}
	for key in OBSERVATIONS:
		if not _number(state.get(key)):
			return {"ok":false,"error":"Staff estimate requires finite published " + key}
		published[key] = float("%.2f" % state[key])
	return published
static func policy(state: Dictionary, params: Dictionary) -> Dictionary:
	var published := observe(state)
	if not published.get("ok", true):
		return published
	return from_observation(published, params)
static func from_observation(published: Dictionary, params: Dictionary) -> Dictionary:
	if published.size() != OBSERVATIONS.size():
		return {"ok":false,"error":"Staff observation requires exactly three published measures."}
	for key in OBSERVATIONS:
		if not _number(published.get(key)):
			return {"ok":false,"error":"Invalid published staff observation: " + key}
	for key in DESIGN_INPUTS:
		if not _number(params.get(key)):
			return {"ok":false,"error":"Invalid staff rule input: " + key}
	if params.minimum_rate_increment_pct <= 0:
		return {"ok":false,"error":"Staff quote increment must be positive."}
	var target: float = params.initial_r_star_pct + published.expected_long_inflation_pct + params.policy_inflation_response * (published.four_quarter_inflation_pct - params.inflation_target_pct) + params.policy_output_gap_response * published.output_gap_pct
	if not is_finite(target) or not is_finite(target / params.minimum_rate_increment_pct):
		return {"ok":false,"error":"Staff estimate exceeds finite quote precision."}
	target = snappedf(target, params.minimum_rate_increment_pct)
	if not is_finite(target):
		return {"ok":false,"error":"Staff estimate is not finite."}
	return {"policy_rate_request_pct":target,"guidance_rate_pct":target,"guidance_inflation_sensitivity":params.policy_inflation_response,"guidance_output_gap_sensitivity":params.policy_output_gap_response,"asset_flow_request_pct_initial_gdp":0.0,"liquidity_request_pct_initial_gdp":0.0}
