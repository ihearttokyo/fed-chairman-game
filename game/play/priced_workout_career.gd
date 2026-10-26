extends "res://play/workout_career.gd"
## Optional authored borrowing-cost laboratory. No normal career storage.
const DAY_SCHEDULE := [90, 91, 92, 92]
const CREDIT_CONTRACT := {
	"version": 2,
	"apr_mapping": "Economy._effective_rate(requested_policy_rate_pct,negative_rate_efficacy_scale_pct)",
	"day_schedule": [90, 91, 92, 92], "day_index": "opening_bank_quarter_modulo_four",
	"accrual": "opening_principal_times_apr_percent_times_days_over_365",
	"collectibility": "externally_authored_collectible_only; impairment_unsupported",
	"negative_interest": "explicit_fictional_US_counterfactual",
	"finance_interest": true, "automatic_claim_setoff": false,
	"cash_priority": "principal_then_reverse_interest_cash_then_positive_interest_then_withdrawals",
	"source_limit": "not_exact_primary_credit_governance_terms_or_GAAP_CECL"
}

var credit_state: Dictionary = {"payable": 0.0, "receivable": 0.0}
var credit_history: Array = []
var credit_contexts: Array = []
var credit_results: Array = []

func start_episode(opening: Dictionary, requests: Array, haircut: float, share: float, case_id: String = "stagflation_bank_run", seed_number: int = 417, remaining_index: int = -1) -> Dictionary:
	var result := super.start_episode(opening, requests, haircut, share, case_id, seed_number, remaining_index)
	if not result.ok:
		return result
	credit_state = {"payable": 0.0, "receivable": 0.0}
	credit_history = [credit_state.duplicate(true)]
	credit_contexts = []
	credit_results = []
	return result

func _loan_apr(rate: Variant) -> Variant:
	var scale: Variant = params.get("negative_rate_efficacy_scale_pct", NAN)
	# Preserve native credit-number validation before any conversion: strings/bools
	# and integers outside the exact +/-2^53 range must never become valid rates.
	# NAN propagates to the existing atomic credit-context validation on failure.
	if not Economy._bw_number(rate):
		return NAN
	if not Economy._bw_number(scale) or scale <= 0.0:
		return NAN
	return rate if rate >= 0.0 else Economy._effective_rate(float(rate), float(scale))

func _credit_context(rate: Variant, opening_quarter: int, claims: Dictionary) -> Dictionary:
	# Reuse the nonlinear transmission channel only for this authored loan quote.
	# Requested policy/guidance and the externally authored raw-APR primitive stay intact.
	return {"annual_rate_pct": _loan_apr(rate), "days": DAY_SCHEDULE[posmod(opening_quarter, 4)],
		"payable": claims.get("payable", NAN), "receivable": claims.get("receivable", NAN),
		"collectible": true, "allow_negative": true, "finance_interest": true}

func _today_macro_shock() -> Dictionary:
	var index := decisions.size()
	if index >= shocks.size() or not shocks[index] is Dictionary:
		return {"ok": false, "error": "Current priced-workout shock record is unavailable."}
	return {"ok": true, "shock": shocks[index].duplicate(true)}

func advance(policy: Dictionary) -> Dictionary:
	if bank_state.is_empty() or decisions.size() >= EPISODE_QUARTERS:
		return {"ok": false, "error": "The eight-quarter priced-workout episode has no remaining decision."}
	var request := _current_request()
	if not request.ok:
		return request
	var today := _today_macro_shock()
	if not today.ok:
		return today
	var credit := _credit_context(policy.get("policy_rate_request_pct", NAN), bank_state.quarter_index, credit_state)
	var result: Dictionary = model.bank_workout_transition(state, policy, today.shock, params, bank_state, _order(request.request), credit)
	if not result.ok:
		return result
	if not result.has("credit_state") or not result.has("credit_result"):
		return {"ok": false, "error": "Priced transition omitted its separate credit ledger."}
	# Commit only after every native/private/credit validation has succeeded.
	state = result.state.duplicate(true)
	bank_state = result.bank_state.duplicate(true)
	credit_state = result.credit_state.duplicate(true)
	history.append(state.duplicate(true))
	bank_history.append(bank_state.duplicate(true))
	credit_history.append(credit_state.duplicate(true))
	settlements.append(result.bank_result.duplicate(true))
	credit_results.append(result.credit_result.duplicate(true))
	credit_contexts.append(credit.duplicate(true))
	decisions.append(policy.duplicate(true))
	return result

func workout_briefing() -> Dictionary:
	if bank_state.is_empty() or decisions.size() >= EPISODE_QUARTERS:
		return {"ok": false, "error": "No remaining priced-workout decision."}
	var request := _current_request()
	if not request.ok:
		return request
	# The inherited current_briefing merges these authoritative current-rate
	# conditions with today's nonfunding seeded shock, never a future request.
	return model.bank_workout_briefing(bank_state, _order(request.request), _credit_context(state.policy_rate_pct, bank_state.quarter_index, credit_state))

func forecast(policy: Dictionary, follow_guidance: bool = false) -> Dictionary:
	if bank_state.is_empty() or decisions.size() >= EPISODE_QUARTERS:
		return {"ok": false, "error": "No remaining priced-workout decision."}
	var today := _current_request()
	if not today.ok:
		return today
	var macro_today := _today_macro_shock()
	if not macro_today.ok:
		return macro_today
	var projected := state.duplicate(true)
	var projected_bank := bank_state.duplicate(true)
	var projected_credit := credit_state.duplicate(true)
	var states: Array = []
	var banks: Array = []
	var credits: Array = []
	var results: Array = []
	var bank_results: Array = []
	var contexts: Array = []
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
		var request: float = today.request if q == 0 else 0.0
		var credit := _credit_context(choice.get("policy_rate_request_pct", NAN), projected_bank.quarter_index, projected_credit)
		var result: Dictionary = model.bank_workout_transition(projected, choice, macro_today.shock if q == 0 else {}, params, projected_bank, _order(request), credit)
		if not result.ok:
			return result
		projected = result.state
		projected_bank = result.bank_state
		projected_credit = result.credit_state
		states.append(projected.duplicate(true))
		banks.append(projected_bank.duplicate(true))
		credits.append(projected_credit.duplicate(true))
		results.append(result.credit_result.duplicate(true))
		bank_results.append(result.bank_result.duplicate(true))
		contexts.append(credit.duplicate(true))
	return {"ok": true, "states": states, "bank_states": banks, "credit_states": credits,
		"credit_results": results, "bank_results": bank_results, "credit_contexts": contexts,
		"episode_end_quarter": EPISODE_QUARTERS, "diagnostic_beyond_episode": states[-1].quarter_index > EPISODE_QUARTERS}

func panel_snapshot() -> Dictionary:
	var view := super.panel_snapshot()
	if view.is_empty():
		return view
	if not settlements.is_empty():
		if credit_results.size() != settlements.size():
			return {}
		view.equity = credit_results[-1].bank_equity_after
	return view

func credit_snapshot() -> Dictionary:
	if bank_state.is_empty():
		return {}
	var snapshot := {"ok": true, "has_settlement": not credit_results.is_empty(), "quarter_index": bank_state.quarter_index,
		"payable": credit_state.payable, "receivable": credit_state.receivable,
		"annual_rate_pct": null, "requested_policy_rate_pct": null, "days": null, "accrued_positive": null, "accrued_negative": null,
		"paid_positive": null, "paid_negative": null, "new_cash_for_interest": null, "new_cash_for_withdrawals": null,
		"held_annual_rate_pct": _loan_apr(state.policy_rate_pct) if decisions.size() < EPISODE_QUARTERS else null,
		"held_requested_policy_rate_pct": state.policy_rate_pct if decisions.size() < EPISODE_QUARTERS else null,
		"quote_basis": "mapped_current_policy_rate_not_staged_controls",
		"next_days": DAY_SCHEDULE[posmod(bank_state.quarter_index, 4)] if decisions.size() < EPISODE_QUARTERS else null,
		"externally_collectible_assumption": true, "negative_rate_counterfactual": true, "finance_interest": true}
	if not credit_results.is_empty():
		snapshot.annual_rate_pct = credit_contexts[-1].annual_rate_pct
		snapshot.requested_policy_rate_pct = decisions[-1].policy_rate_request_pct
		snapshot.days = credit_contexts[-1].days
		for key in ["accrued_positive", "accrued_negative", "paid_positive", "paid_negative", "new_cash_for_interest", "new_cash_for_withdrawals"]:
			snapshot[key] = credit_results[-1][key]
	return snapshot

func payload() -> Dictionary:
	var data := super.payload()
	data.priced_workout_version = 2
	data.credit_state = credit_state.duplicate(true)
	data.credit_history = credit_history.duplicate(true)
	data.credit_contexts = credit_contexts.duplicate(true)
	data.credit_results = credit_results.duplicate(true)
	data.credit_contract = CREDIT_CONTRACT.duplicate(true)
	return data
