extends "res://play/career.gd"
## Optional in-memory episode. Normal career slots are deliberately inaccessible.
const EPISODE_QUARTERS := 8
var bank_state: Dictionary = {}
var bank_history: Array = []
var settlements: Array = []
var withdrawal_requests: Array = []
var haircut_pct := 4.0
var pledgeable_share := 1.0
var remaining_request_index := -1

func start(_case_id: String, _seed_number: int) -> Dictionary:
	return {"ok": false, "error": "Start a bank-workout episode with its opening bank and request schedule."}

func start_episode(opening: Dictionary, requests: Array, haircut: float, share: float, case_id: String = "stagflation_bank_run", seed_number: int = 417, remaining_index: int = -1) -> Dictionary:
	if remaining_index < -1 or remaining_index >= EPISODE_QUARTERS or requests.size() != EPISODE_QUARTERS or not is_finite(haircut) or haircut < 0.0 or haircut > 100.0 or not is_finite(share) or share < 0.0 or share > 1.0:
		return {"ok": false, "error": "Invalid eight-quarter workout configuration."}
	var checked := model.bank_workout_value(opening, opening.get("annual_yield_pct", NAN))
	if not checked.ok:
		return checked
	var unrequested: float = opening.deposits - opening.withdrawal_queue
	for index in range(requests.size()):
		var request: Variant = requests[index]
		if typeof(request) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(request)) or request < 0.0 or (index != remaining_index and request > unrequested):
			return {"ok": false, "error": "Withdrawals exceed unrequested deposits or are invalid."}
		if index != remaining_index:
			unrequested -= request
	if remaining_index >= 0:
		for index in range(remaining_index + 1, EPISODE_QUARTERS):
			if requests[index] != 0.0:
				return {"ok": false, "error": "New withdrawal waves cannot follow the final remaining-depositor wave."}
	# Build a detached ordinary starting economy before installing either state.
	var fresh = preload("res://play/career.gd").new()
	var begun: Dictionary = fresh.start(case_id, seed_number)
	if not begun.ok:
		return begun
	if opening.quarter_index != fresh.state.quarter_index or opening.central_bank_loan != fresh.state.outstanding_liquidity_pct_initial_gdp:
		return {"ok": false, "error": "Opening bank and economy must share clock and loan principal."}
	params = fresh.params
	cases = fresh.cases
	scenario_id = fresh.scenario_id
	seed_value = fresh.seed_value
	state = fresh.state
	history = fresh.history
	decisions = []
	shocks = fresh.shocks
	_seeded_shocks = fresh._seeded_shocks
	episodes = []
	bank_state = opening.duplicate(true)
	bank_history = [bank_state.duplicate(true)]
	settlements = []
	withdrawal_requests = requests.duplicate(true)
	haircut_pct = haircut
	pledgeable_share = share
	remaining_request_index = remaining_index
	return {"ok": true}

func _order(request: float) -> Dictionary:
	return {"new_withdrawals": request, "haircut_pct": haircut_pct, "pledgeable_share": pledgeable_share}

func _current_request() -> Dictionary:
	if bank_state.is_empty() or decisions.size() >= EPISODE_QUARTERS:
		return {"ok": false, "error": "No remaining bank-workout request."}
	if decisions.size() == remaining_request_index:
		return model.bank_workout_remaining_request(bank_state)
	return {"ok": true, "request": withdrawal_requests[decisions.size()]}

func advance(policy: Dictionary) -> Dictionary:
	if bank_state.is_empty() or decisions.size() >= EPISODE_QUARTERS:
		return {"ok": false, "error": "The eight-quarter bank-workout episode is complete."}
	var request := _current_request()
	if not request.ok:
		return request
	var result: Dictionary = model.bank_workout_transition(state, policy, current_briefing(), params, bank_state, _order(request.request))
	if not result.ok:
		return result
	state = result.state
	bank_state = result.bank_state
	history.append(state.duplicate(true))
	bank_history.append(bank_state.duplicate(true))
	settlements.append(result.bank_result.duplicate(true))
	decisions.append(policy.duplicate(true))
	return result

func workout_briefing() -> Dictionary:
	if bank_state.is_empty() or decisions.size() >= EPISODE_QUARTERS:
		return {"ok": false, "error": "No remaining bank-workout decision."}
	var request := _current_request()
	if not request.ok:
		return request
	return model.bank_workout_briefing(bank_state, _order(request.request))

func current_briefing() -> Dictionary:
	if bank_state.is_empty() or decisions.size() >= EPISODE_QUARTERS:
		return {}
	var shown := workout_briefing()
	if not shown.ok:
		return {}
	var current: Dictionary = shocks[decisions.size()].duplicate(true)
	current.merge(shown.shocks, true)
	return current

func situation_briefing() -> String:
	if bank_state.is_empty():
		return "Bank workout not started."
	if decisions.size() >= EPISODE_QUARTERS:
		return "Eight-quarter episode complete. Retained claims remain visible in the bank ledger."
	var shown := workout_briefing()
	if not shown.ok:
		return "Bank conditions unavailable: " + shown.error
	return "Bank funding %s · Refinancing %s (%% initial GDP)." % [funding_amount_text(shown.shocks.funding_need_pct_initial_gdp), funding_amount_text(shown.shocks.refinancing_need_pct_initial_gdp)]

func current_shock_episode() -> Dictionary:
	# Native seeded funding quantities are replaced by this explicit bank ledger.
	# Do not attach their original catalogue labels to the modified conditions.
	return {}

func forecast(policy: Dictionary, follow_guidance: bool = false) -> Dictionary:
	if bank_state.is_empty() or decisions.size() >= EPISODE_QUARTERS:
		return {"ok": false, "error": "No remaining bank-workout decision."}
	var today := _current_request()
	if not today.ok:
		return today
	var projected := state.duplicate(true)
	var projected_bank := bank_state.duplicate(true)
	var states: Array = []
	var banks: Array = []
	var bank_results: Array = []
	for q in range(8):
		var choice: Dictionary = policy.duplicate(true) if q == 0 else model.benchmark_policy(projected, params, "hold")
		if q > 0:
			if follow_guidance:
				var due: float = model.conditional_commitment(projected, params)
				choice.policy_rate_request_pct = due
				choice.guidance_rate_pct = due
				choice.guidance_inflation_sensitivity = policy.guidance_inflation_sensitivity
				choice.guidance_output_gap_sensitivity = policy.guidance_output_gap_sensitivity
			for key in Economy.POLICY_SWITCHES:
				choice[key] = policy.get(key, Economy.POLICY_SWITCHES[key])
		# Future maturities and existing queues are known; future request tape is not.
		var request: float = today.request if q == 0 else 0.0
		var result: Dictionary = model.bank_workout_transition(projected, choice, current_briefing() if q == 0 else {}, params, projected_bank, _order(request))
		if not result.ok:
			return result
		projected = result.state
		projected_bank = result.bank_state
		states.append(projected.duplicate(true))
		banks.append(projected_bank.duplicate(true))
		bank_results.append(result.bank_result.duplicate(true))
	return {"ok": true, "states": states, "bank_states": banks, "bank_results": bank_results, "episode_end_quarter": EPISODE_QUARTERS,
		"diagnostic_beyond_episode": states[-1].quarter_index > EPISODE_QUARTERS}

func panel_snapshot() -> Dictionary:
	if bank_state.is_empty():
		return {}
	var priced: Dictionary
	if settlements.is_empty():
		priced = model.bank_workout_step(bank_state, {"annual_yield_pct": bank_state.annual_yield_pct,
			"new_withdrawals": 0.0, "liquidity_offer": 0.0, "haircut_pct": haircut_pct, "pledgeable_share": pledgeable_share})
		if not priced.ok:
			return {}
	else:
		priced = settlements[-1]
	var view := bank_state.duplicate(true)
	view.securities_value = priced.old_market_value if settlements.is_empty() else priced.remaining_market_value
	view.equity = priced.equity_before if settlements.is_empty() else priced.equity_after
	view.payment_due = 0.0 if settlements.is_empty() else priced.deposit_due
	view.payments_made = 0.0 if settlements.is_empty() else priced.withdrawals_paid
	return view

func review_comparison() -> Dictionary:
	return {"ok": false, "error": "Historical bank-workout references are not yet available. Conditional previews include this bank's retained claims."}

func mandate_assessment() -> Dictionary:
	var assessment := super.mandate_assessment()
	assessment.eligible = false
	assessment.achieved = false
	assessment.complete = decisions.size() == EPISODE_QUARTERS
	return assessment

func recovery_assessment() -> Dictionary:
	var assessment := super.recovery_assessment()
	assessment.eligible = false
	assessment.stabilized = false
	return assessment

func payload() -> Dictionary:
	return {"workout_version": 1, "model_digest": model_digest(), "scenario_id": scenario_id,
		"seed": seed_value, "shocks": shocks.duplicate(true), "decisions": decisions.duplicate(true),
		"state": state.duplicate(true), "history": history.duplicate(true), "bank_state": bank_state.duplicate(true),
		"bank_history": bank_history.duplicate(true), "settlements": settlements.duplicate(true),
		"withdrawal_requests": withdrawal_requests.duplicate(true),
		"haircut_pct": haircut_pct, "pledgeable_share": pledgeable_share, "remaining_request_index": remaining_request_index}

func save_to(_path: String) -> Dictionary:
	return {"ok": false, "error": "Bank workout is an unsaved laboratory; normal career slots are untouched."}

func load_from(_path: String) -> Dictionary:
	return {"ok": false, "error": "Leave the bank-workout laboratory to load a normal career."}

func restore(_data: Variant) -> Dictionary:
	return {"ok": false, "error": "Bank-workout payloads are not normal career saves."}
