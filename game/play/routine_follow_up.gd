extends RefCounted

const Advice = preload("res://play/policy_advice.gd")
const Economy = preload("res://model/economy.gd")
var active := false
var generation := 0
var automatic_left := 0
var anchor: Dictionary = {}
var switches: Dictionary = {}
var last_commit_frame := -1
var _start_count := 0
var _serial := 0
var _pending: Dictionary = {}
var _model := Economy.new()

func _result(reasons: Array[String], policy: Dictionary = {}, token: Dictionary = {}, waiting: bool = false) -> Dictionary:
	return {"ok": reasons.is_empty() and not waiting, "reasons": reasons, "policy": policy, "token": token, "waiting": waiting}

func _malformed(error: String) -> Dictionary:
	stop()
	var result := _result(["MALFORMED_OBSERVER"])
	result.error = error
	return result

func _validate(state: Dictionary, params: Dictionary) -> Dictionary:
	var valid := _model._validate_parameters(params)
	if not valid.ok:
		return valid
	return _model._validate_state(state, params)

func arm(state: Dictionary, params: Dictionary, committed_policy: Dictionary, frame: int) -> Dictionary:
	stop()
	var valid := _validate(state, params)
	if not valid.ok:
		return _malformed(valid.error)
	valid = _model._validate_policy(committed_policy, params)
	if not valid.ok:
		return _malformed(valid.error)
	for key in Economy.POLICY_SWITCHES:
		if not committed_policy.has(key) or typeof(committed_policy[key]) != TYPE_BOOL:
			return _malformed("Committed policy requires three explicit boolean switches.")
	if frame < 0 or state.quarter_index < 1 or state.quarter_index > 240:
		return _malformed("Arm requires a completed attended adoption and a valid frame.")
	var policy := Advice.policy(state, params)
	if not policy.get("ok", true):
		return _malformed(policy.error)
	valid = _model._validate_policy(policy, params)
	if not valid.ok:
		return _malformed(valid.error)
	anchor = {"four_quarter_inflation_pct": state.four_quarter_inflation_pct, "output_gap_pct": state.output_gap_pct, "expected_long_inflation_pct": state.expected_long_inflation_pct, "benchmark_rate_pct": policy.policy_rate_request_pct}
	switches = {}
	for key in Economy.POLICY_SWITCHES:
		switches[key] = committed_policy[key]
	_start_count = int(state.quarter_index)
	last_commit_frame = frame
	automatic_left = 3
	active = true
	return _result([])

func stop() -> void:
	generation += 1
	active = false
	automatic_left = 0
	_pending = {}

func proposal(state: Dictionary, current_shock: Dictionary, current_phase: Dictionary, params: Dictionary, completed_count: int, history_count: int, frame: int) -> Dictionary:
	_pending = {}
	if not active:
		return _result(["INACTIVE"])
	var valid := _validate(state, params)
	if not valid.ok:
		return _malformed(valid.error)
	valid = _model._validate_shocks(current_shock)
	if not valid.ok:
		return _malformed(valid.error)
	if completed_count != state.quarter_index or history_count != completed_count + 1 or completed_count != _start_count + 3 - automatic_left or completed_count > 240 or frame < 0:
		return _malformed("Current state, completed history, allowance or frame is inconsistent.")
	if not current_phase.is_empty():
		if current_phase.size() != 2 or typeof(current_phase.get("title")) != TYPE_STRING or typeof(current_phase.get("policy_dilemma")) != TYPE_STRING or current_phase.title.is_empty() or current_phase.policy_dilemma.is_empty():
			return _malformed("Current phase must contain only its title and policy dilemma.")
	var policy := Advice.policy(state, params)
	if not policy.get("ok", true):
		return _malformed(policy.error)
	policy.merge(switches)
	valid = _model._validate_policy(policy, params)
	if not valid.ok:
		return _malformed(valid.error)
	var reasons: Array[String] = []
	if completed_count >= 240:
		reasons.append("CAREER_END")
	if automatic_left == 0:
		reasons.append("QUOTA_EXHAUSTED")
	if not current_phase.is_empty():
		reasons.append("CURRENT_PHASE")
	if current_shock.get("funding_need_pct_initial_gdp", 0.0) > 0.0:
		reasons.append("FUNDING_NEED")
	if current_shock.get("refinancing_need_pct_initial_gdp", 0.0) > 0.0:
		reasons.append("REFINANCING_NEED")
	if state.outstanding_liquidity_pct_initial_gdp > 0.0:
		reasons.append("OUTSTANDING_LOANS")
	if state.reserve_scarcity_wedge_pct > 0.0:
		reasons.append("RESERVE_SCARCITY")
	if state.uncovered_funding_pct_initial_gdp > 0.0:
		reasons.append("UNCOVERED_FUNDING")
	var news: bool = abs(current_shock.get("demand_shock_pct", 0.0)) > 0.18 or abs(current_shock.get("supply_innovation_pct", 0.0)) > 0.04 or abs(current_shock.get("r_star_change_pct", 0.0)) > 0.01
	for key in ["credit_risk_innovation_pct", "solvency_risk_innovation_pct", "r_star_reference_change_pct", "structural_unemployment_change_pct"]:
		news = news or current_shock.get(key, 0.0) != 0.0
	news = news or current_shock.get("potential_growth_pct", state.potential_growth_pct) != state.potential_growth_pct
	news = news or current_shock.get("rrp_encumbered_collateral_pct_initial_gdp", 0.0) > 0.0 or current_shock.get("rrp_uptake_fraction", 1.0) != 1.0
	news = news or current_shock.get("eligible_collateral_pct_initial_gdp", 0.0) > 0.0 or current_shock.get("collateral_haircut_pct", 0.0) != 0.0 or current_shock.get("liquidity_eligibility_pct", 0.0) != 0.0
	if news:
		reasons.append("CURRENT_NEWS")
	for entry in [["four_quarter_inflation_pct", "INFLATION_DRIFT"], ["output_gap_pct", "OUTPUT_GAP_DRIFT"], ["expected_long_inflation_pct", "LONG_EXPECTATIONS_DRIFT"]]:
		if abs(state[entry[0]] - anchor[entry[0]]) >= 0.25:
			reasons.append(entry[1])
	if abs(policy.policy_rate_request_pct - anchor.benchmark_rate_pct) >= 0.25:
		reasons.append("BENCHMARK_DRIFT")
	if state.guidance_active:
		var due: float = _model.conditional_commitment(state, params)
		if not is_finite(due):
			return _malformed("Current promise is not finite.")
		if abs(policy.policy_rate_request_pct - due) >= 0.25:
			reasons.append("PROMISE_GAP")
	if not reasons.is_empty():
		stop()
		return _result(reasons, policy)
	if frame <= last_commit_frame:
		return _result([], {}, {}, true)
	_serial += 1
	_pending = {"generation": generation, "serial": _serial, "frame": frame, "completed_count": completed_count}
	_pending.make_read_only()
	return _result([], policy, _pending)

# Main acknowledges only after one successful atomic Career.advance; failure calls stop.
func committed(frame: int, token: Dictionary) -> bool:
	if not active or automatic_left <= 0 or _pending.is_empty() or token != _pending or token.generation != generation or frame != token.frame or frame <= last_commit_frame:
		return false
	_pending = {}
	last_commit_frame = frame
	automatic_left -= 1
	return true
