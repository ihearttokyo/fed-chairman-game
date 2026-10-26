extends SceneTree
const Priced = preload("res://play/priced_workout_career.gd")
const Workout = preload("res://play/workout_career.gd")
const Career = preload("res://play/career.gd")
const Economy = preload("res://model/economy.gd")
class UnavailableCurrentQuote:
	extends "res://play/priced_workout_career.gd"
	func workout_briefing() -> Dictionary:
		return {"ok": false, "error": "Injected current-rate quote failure"}
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures <= 15:
			printerr("FAIL: " + message)

func recipe(career: Object) -> Dictionary:
	return career.model.bank_workout_opening(career.params)

func start(career: Object, opening: Dictionary) -> Dictionary:
	return career.start_episode(opening.bank, opening.requests, opening.haircut_pct, opening.pledgeable_share, "stagflation_bank_run", 417, opening.remaining_request_index)

func choice(career: Object, rate: float = 4.0, offer: float = 4.0) -> Dictionary:
	var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold")
	policy.policy_rate_request_pct = rate
	policy.guidance_rate_pct = rate
	policy.liquidity_request_pct_initial_gdp = offer
	policy.maintain_ample_reserves = true
	return policy

func _initialize() -> void:
	var priced := Priced.new()
	var opening := recipe(priced)
	check(opening.ok, "Native authored recipe is available")
	if not opening.ok:
		finish()
		return
	var original := var_to_bytes(opening)
	check(start(priced, opening).ok, "Priced lab starts through the exact base signature")
	check(var_to_bytes(opening) == original, "Start preserves the authored opening and requests")
	var initial := priced.encode()
	var initial_credit := priced.credit_snapshot()
	check(initial_credit.ok and not initial_credit.has_settlement and initial_credit.annual_rate_pct == null and initial_credit.accrued_positive == null and initial_credit.paid_positive == null, "Opening claims are zero without fabricated prior-period income")
	check(priced.credit_history == [{"payable": 0.0, "receivable": 0.0}] and priced.credit_results.is_empty(), "Successful start installs a detached zero-credit history")
	var policy := choice(priced)
	var preview := priced.forecast(policy)
	check(initial_credit.held_annual_rate_pct == 3.5 and initial_credit.quote_basis == "current_applied_policy_rate_not_staged_controls" and not initial_credit.has("next_annual_rate_pct") and preview.credit_contexts[0].annual_rate_pct == 4.0, "Held-rate reference and the distinct staged APR cannot be confused")
	check(preview.ok and preview.states.size() == 8 and preview.bank_states.size() == 8 and preview.credit_states.size() == 8 and preview.credit_results.size() == 8, "Eight conditional steps carry all three ledgers")
	check(priced.encode() == initial, "Full conditional preview is byte-pure")
	var alternate := Priced.new()
	var alternate_opening := opening.duplicate(true)
	alternate_opening.requests = [2.4, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	alternate_opening.remaining_request_index = -1
	check(start(alternate, alternate_opening).ok, "Alternative hidden request tape starts")
	alternate.shocks[1].supply_innovation_pct = 5.0
	check(var_to_bytes(alternate.forecast(policy)) == var_to_bytes(preview), "Future withdrawals and nonfunding shocks cannot leak into conditional preview")
	var first := priced.advance(policy)
	check(first.ok, "First actual priced transition settles")
	if not first.ok:
		printerr(first.get("error", "unknown"))
		finish()
		return
	if first.ok and preview.ok:
		check(first.state == preview.states[0] and first.bank_state == preview.bank_states[0] and first.bank_result == preview.bank_results[0] and first.credit_state == preview.credit_states[0] and first.credit_result == preview.credit_results[0], "First preview equals actual macro, bank, settlement and credit ledgers")
	check(priced.encode() != initial and priced.credit_history.size() == 2 and priced.credit_contexts.size() == 1, "Actual credit adoption participates in dirty tracking and both histories")
	check(priced.panel_snapshot().equity == priced.credit_results[-1].bank_equity_after, "Panel uses combined equity including separate interest claims")
	var conditions := priced.workout_briefing()
	var current_accrual: float = first.bank_state.central_bank_loan * 0.04 * 91.0 / 365.0
	check(conditions.ok and absf(conditions.bank_result.credit_result.accrued_positive - current_accrual) <= 1e-12, "Current briefing accrues current-rate interest on the actual funded principal")
	var frozen := priced.encode()
	var invalid := policy.duplicate(true)
	invalid.policy_rate_request_pct = NAN
	check(not priced.advance(invalid).ok and priced.encode() == frozen, "Failed policy advance preserves every encoded ledger")
	check(not priced.forecast(invalid).ok and priced.encode() == frozen, "Rejected conditional policy also preserves all histories")
	check(not priced.start_episode(opening.bank, [999.0, 0, 0, 0, 0, 0, 0, 0], 4, 1).ok and priced.encode() == frozen, "Failed restart preserves existing base and credit state")
	var next_policy := choice(priced, -1.0, 4.0)
	var second := priced.advance(next_policy)
	check(second.ok, "Negative-rate counterfactual is explicit and executable")
	if second.ok:
		var expected_accrual: float = first.bank_state.central_bank_loan * 0.01 * 91.0 / 365.0
		check(absf(second.credit_result.accrued_negative - expected_accrual) <= 1e-12 and priced.credit_contexts[-1].annual_rate_pct == -1 and priced.credit_contexts[-1].days == 91, "Next accrual uses actual previously funded principal, actual staged rate and opening-quarter days")
		var current := priced.credit_snapshot()
		check(current.has_settlement and current.annual_rate_pct == -1 and current.days == 91 and current.accrued_negative == second.credit_result.accrued_negative and current.new_cash_for_interest == second.credit_result.new_cash_for_interest, "Read-only credit details report actual contract, accrual, cash and purposes distinctly")
	var copy := priced.payload()
	var before_copy := priced.encode()
	copy.credit_state.payable = 999
	copy.credit_contract.day_schedule[0] = 999
	copy.bank_history[0].cash = 999
	check(priced.encode() == before_copy, "Payload and nested contract/history containers are detached")
	check(start(priced, opening).ok and priced.credit_state == {"payable": 0.0, "receivable": 0.0} and priced.credit_history.size() == 1 and priced.credit_contexts.is_empty() and priced.credit_results.is_empty(), "Successful restart alone clears prior credit balances and traces")
	_test_minimum_loan(opening)
	_test_fractional_rate_change(opening)
	_test_guidance(opening)
	_test_paths(opening)
	_test_briefing_independence(opening)
	var ordinary := Workout.new()
	check(start(ordinary, opening).ok, "Default zero-interest Workout remains available unchanged")
	var ordinary_policy := choice(ordinary)
	var request := ordinary._current_request()
	var ordinary_expected: Dictionary = ordinary.model.bank_workout_transition(ordinary.state, ordinary_policy, ordinary.current_briefing(), ordinary.params, ordinary.bank_state, ordinary._order(request.request))
	var actual := ordinary.advance(ordinary_policy)
	check(var_to_bytes(ordinary_expected) == var_to_bytes(actual) and not ordinary.payload().has("credit_state"), "Default Workout still takes the original context-free transition and payload")
	finish()

func _test_minimum_loan(opening: Dictionary) -> void:
	for rate in [4.0, -4.0]:
		var career := Priced.new()
		check(start(career, opening).ok, "Minimum-loan fixture starts")
		var first := career.advance(choice(career, rate, 0.0001))
		check(first.ok and first.bank_state.central_bank_loan == 0.0001, "Minimum policy offer becomes actual opening principal")
		if not first.ok:
			continue
		var quote := career.workout_briefing()
		check(quote.ok, "Ordinary small-loan interest remains quoteable after security maturity")
		var staged := choice(career, rate, 4.0)
		var forecast := career.forecast(staged)
		check(forecast.ok, "Ordinary minimum-loan conditional forecast remains available")
		var second := career.advance(staged)
		check(second.ok, "Ordinary minimum-loan maturity settles without a numerical dead end")
		if not second.ok:
			printerr("MINIMUM LOAN: ", rate, " ", second.get("error", "unknown"))
		if second.ok and forecast.ok:
			check(second.state == forecast.states[0] and second.credit_result == forecast.credit_results[0], "Minimum-loan preview and actual settlement agree for both interest signs")


func _test_fractional_rate_change(opening: Dictionary) -> void:
	var career := Priced.new()
	check(start(career, opening).ok, "Fractional-principal rate-change fixture starts")
	var first := career.advance(choice(career, 4.0, 0.0001))
	check(first.ok and first.bank_state.central_bank_loan == 0.0001, "Rate-change fixture funds the actual minimum offer")
	if not first.ok:
		return
	career.shocks[1].demand_shock_pct = 0.75
	career.shocks[1].supply_innovation_pct = 0.5
	var staged := choice(career, 0.0, 4.0)
	var request := career._current_request()
	var expected: Dictionary = career.model.bank_workout_transition(career.state, staged, career.shocks[1].duplicate(true), career.params, career.bank_state, career._order(request.request), career._credit_context(0.0, career.bank_state.quarter_index, career.credit_state))
	var forecast := career.forecast(staged)
	check(expected.ok and forecast.ok and forecast.states[0] == expected.state, "Small-loan rate change previews today's actual macro shocks, independently of the held-rate quote")
	var actual := career.advance(staged)
	check(expected.ok and actual.ok and actual.state == expected.state and actual.credit_result == expected.credit_result, "Small-loan rate change adopts the same shocks and settlement as the independent facade")

func _test_briefing_independence(opening: Dictionary) -> void:
	var reference := Priced.new()
	var unavailable := UnavailableCurrentQuote.new()
	check(start(reference, opening).ok and start(unavailable, opening).ok, "Matched current-quote failure fixture starts")
	for c in [reference, unavailable]:
		c.shocks[0].demand_shock_pct = 0.75
		c.shocks[0].supply_innovation_pct = 0.5
	check(unavailable.current_briefing().is_empty(), "Injected current-rate presentation failure is exercised")
	var policy := choice(reference)
	var expected := reference.forecast(policy)
	var observed := unavailable.forecast(policy)
	check(expected.ok and observed.ok and observed.states[0] == expected.states[0], "A failed held-rate quote cannot erase today's nonfunding shocks from a staged preview")
	var actual := unavailable.advance(policy)
	check(actual.ok and expected.ok and actual.state == expected.states[0], "Actual adoption also preserves today's seeded shocks independently of the display quote")

func _test_guidance(opening: Dictionary) -> void:
	var career := Priced.new()
	check(start(career, opening).ok, "Guidance fixture starts")
	var policy := choice(career, 4.0, 4.0)
	policy.guidance_rate_pct = 3.0
	policy.guidance_inflation_sensitivity = 0.0
	policy.guidance_output_gap_sensitivity = 0.0
	policy.reinvest_principal = false
	policy.sterilize_purchases = true
	var forecast := career.forecast(policy, true)
	check(forecast.ok, "Conditional guidance priced preview is available")
	if not forecast.ok:
		return
	var projected: Dictionary = forecast.states[0]
	var due: float = career.model.conditional_commitment(projected, career.params)
	check(forecast.credit_contexts[1].annual_rate_pct == due, "Future APR follows the actual conditional guidance choice")
	var choice_next: Dictionary = career.model.benchmark_policy(projected, career.params, "hold")
	choice_next.policy_rate_request_pct = due
	choice_next.guidance_rate_pct = due
	choice_next.guidance_inflation_sensitivity = policy.guidance_inflation_sensitivity
	choice_next.guidance_output_gap_sensitivity = policy.guidance_output_gap_sensitivity
	for flag in Economy.POLICY_SWITCHES:
		choice_next[flag] = policy.get(flag, Economy.POLICY_SWITCHES[flag])
	var expected: Dictionary = career.model.bank_workout_transition(projected, choice_next, {}, career.params, forecast.bank_states[0], career._order(0.0), forecast.credit_contexts[1])
	check(expected.ok and expected.state == forecast.states[1] and expected.credit_result == forecast.credit_results[1], "Future flags, maturity and claims match an independent conditional replay")

func _test_paths(opening: Dictionary) -> void:
	for rate in [0.0, 4.0, -1.0, 8.0]:
		for offer in [0.0, 4.0]:
			var career := Priced.new()
			check(start(career, opening).ok, "Bounded eight-meeting priced path starts")
			for meeting in range(8):
				var policy := choice(career, rate, offer)
				var prior_principal: float = career.bank_state.central_bank_loan
				if meeting == 7:
					var forecast := career.forecast(policy)
					check(forecast.ok and forecast.episode_end_quarter == 8 and forecast.diagnostic_beyond_episode, "Late eight-step preview retains beyond-horizon diagnostic label")
				var result := career.advance(policy)
				check(result.ok, "Actual bounded priced meeting advances")
				if not result.ok:
					printerr(result.get("error", "unknown"))
					break
				check(career.credit_contexts[-1].days == [90, 91, 92, 92][meeting % 4] and career.credit_contexts[-1].annual_rate_pct == rate, "Actual contract schedule uses opening quarter and staged APR")
				if prior_principal > 0 and rate != 0:
					var accrued: float = result.credit_result.accrued_positive if rate > 0 else result.credit_result.accrued_negative
					var expected: float = prior_principal * absf(rate) / 100.0 * [90, 91, 92, 92][meeting % 4] / 365.0
					check(accrued > 0 and absf(accrued - expected) <= 1e-12, "Both signs accrue on actual opening funded principal, never offer or old original loan")
			check(career.decisions.size() == 8 and career.history.size() == 9 and career.bank_history.size() == 9 and career.credit_history.size() == 9 and career.credit_results.size() == 8, "Completed path has synchronized eight-meeting histories")
			var frozen := career.encode()
			check(not career.advance(choice(career, rate, offer)).ok and career.encode() == frozen and career.current_briefing().is_empty(), "Ninth adoption is rejected atomically with no phantom shock")
			check(not career.forecast(choice(career, rate, offer)).ok and not career.mandate_assessment().eligible and not career.recovery_assessment().eligible, "Terminal path has no extra decision or normal awards")
			check(career.credit_snapshot().held_annual_rate_pct == null and career.credit_snapshot().next_days == null, "Terminal snapshot makes no next-contract promise")
			check(not career.save_to("user://priced-workout-forbidden.bin").ok and not career.load_from("user://priced-workout-forbidden.bin").ok and not career.restore(career.payload()).ok and career.encode() == frozen, "Normal storage/restore remains prohibited without mutation")
			check(not Career.new().restore(career.payload()).ok, "Priced payload is never a normal career save")

func finish() -> void:
	if failures == 0:
		print("PASS: priced workout career ", checks, " checks; unexposed authored laboratory")
	else:
		printerr("FAIL: priced workout career ", failures, " of ", checks)
	quit(0 if failures == 0 else 1)
