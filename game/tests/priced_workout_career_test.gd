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
	check(initial_credit.ok and not initial_credit.has_settlement and initial_credit.annual_rate_pct == null and initial_credit.requested_policy_rate_pct == null and initial_credit.accrued_positive == null and initial_credit.paid_positive == null, "Opening claims are zero without fabricated prior-period income or contract")
	check(priced.credit_history == [{"payable": 0.0, "receivable": 0.0}] and priced.credit_results.is_empty(), "Successful start installs a detached zero-credit history")
	var policy := choice(priced)
	var preview := priced.forecast(policy)
	check(initial_credit.held_annual_rate_pct == 3.5 and initial_credit.held_requested_policy_rate_pct == 3.5 and initial_credit.quote_basis == "mapped_current_policy_rate_not_staged_controls" and not initial_credit.has("next_annual_rate_pct") and preview.credit_contexts[0].annual_rate_pct == 4.0, "Held-rate reference and the distinct staged APR cannot be confused")
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
		var expected_apr := -0.7615941559557649
		var expected_accrual: float = first.bank_state.central_bank_loan * absf(expected_apr) / 100.0 * 91.0 / 365.0
		check(absf(second.credit_result.accrued_negative - expected_accrual) <= 1e-12 and absf(priced.credit_contexts[-1].annual_rate_pct - expected_apr) <= 1e-15 and priced.credit_contexts[-1].days == 91, "Next accrual uses actual previously funded principal, mapped APR and opening-quarter days")
		var current := priced.credit_snapshot()
		check(current.has_settlement and current.annual_rate_pct == priced.credit_contexts[-1].annual_rate_pct and current.requested_policy_rate_pct == -1 and current.days == 91 and current.accrued_negative == second.credit_result.accrued_negative and current.new_cash_for_interest == second.credit_result.new_cash_for_interest, "Read-only credit details distinguish committed APR from nominal request, accrual, cash and purposes")
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
	_test_guidance(opening, -10.0)
	_test_paths(opening)
	_test_briefing_independence(opening)
	_test_loan_transmission(opening)
	_test_invalid_inputs(opening)
	_test_integer_rate_inputs(opening)
	_test_extreme_subsidy(opening)
	var ordinary := Workout.new()
	check(start(ordinary, opening).ok, "Default zero-interest Workout remains available unchanged")
	var ordinary_policy := choice(ordinary)
	var request := ordinary._current_request()
	var ordinary_expected: Dictionary = ordinary.model.bank_workout_transition(ordinary.state, ordinary_policy, ordinary.current_briefing(), ordinary.params, ordinary.bank_state, ordinary._order(request.request))
	var actual := ordinary.advance(ordinary_policy)
	check(var_to_bytes(ordinary_expected) == var_to_bytes(actual) and not ordinary.payload().has("credit_state"), "Default Workout still takes the original context-free transition and payload")
	check(not ordinary.payload().has("priced_workout_version") and not Career.new().payload().has("credit_contract"), "Priced metadata never enters original lab or normal career payloads")
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

func _test_guidance(opening: Dictionary, guidance: float = 3.0) -> void:
	var career := Priced.new()
	check(start(career, opening).ok, "Guidance fixture starts")
	var policy := choice(career, 4.0, 4.0)
	policy.guidance_rate_pct = guidance
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
	var expected_apr: float = -0.9999999958776927 if guidance == -10.0 else guidance
	check(due == guidance and absf(forecast.credit_contexts[1].annual_rate_pct - expected_apr) <= 1e-15 and forecast.states[1].policy_rate_pct == due, "Future APR maps conditional guidance without changing the positive or negative nominal commitment")
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
				var expected_apr: float = -0.7615941559557649 if rate == -1.0 else rate
				check(career.credit_contexts[-1].days == [90, 91, 92, 92][meeting % 4] and absf(career.credit_contexts[-1].annual_rate_pct - expected_apr) <= 1e-15, "Actual contract schedule uses opening quarter and mapped staged APR")
				if prior_principal > 0 and rate != 0:
					var accrued: float = result.credit_result.accrued_positive if rate > 0 else result.credit_result.accrued_negative
					var expected: float = prior_principal * absf(expected_apr) / 100.0 * [90, 91, 92, 92][meeting % 4] / 365.0
					check(accrued > 0 and absf(accrued - expected) <= 1e-12, "Both signs accrue on actual opening funded principal, never offer or old original loan")
			check(career.decisions.size() == 8 and career.history.size() == 9 and career.bank_history.size() == 9 and career.credit_history.size() == 9 and career.credit_results.size() == 8, "Completed path has synchronized eight-meeting histories")
			var frozen := career.encode()
			check(not career.advance(choice(career, rate, offer)).ok and career.encode() == frozen and career.current_briefing().is_empty(), "Ninth adoption is rejected atomically with no phantom shock")
			check(not career.forecast(choice(career, rate, offer)).ok and not career.mandate_assessment().eligible and not career.recovery_assessment().eligible, "Terminal path has no extra decision or normal awards")
			check(career.credit_snapshot().held_annual_rate_pct == null and career.credit_snapshot().held_requested_policy_rate_pct == null and career.credit_snapshot().next_days == null, "Terminal snapshot makes no next-contract promise")
			check(not career.save_to("user://priced-workout-forbidden.bin").ok and not career.load_from("user://priced-workout-forbidden.bin").ok and not career.restore(career.payload()).ok and career.encode() == frozen, "Normal storage/restore remains prohibited without mutation")
			check(not Career.new().restore(career.payload()).ok, "Priced payload is never a normal career save")

func _test_loan_transmission(opening: Dictionary) -> void:
	var career := Priced.new()
	check(start(career, opening).ok, "Loan-transmission fixture starts")
	# Independent Python math oracle: s * math.tanh(i / s), not Economy output.
	var goldens := [[1.0, -1.0, -0.7615941559557649], [1.0, -10.0, -0.9999999958776927],
		[1.0, -1000.0, -1.0], [2.5, -1.0, -0.9498724056380623],
		[2.5, -10.0, -2.4983232493476675], [2.5, -1000.0, -2.5]]
	for point in goldens:
		career.params.negative_rate_efficacy_scale_pct = point[0]
		var context := career._credit_context(point[1], 0, career.credit_state)
		check(absf(context.annual_rate_pct - point[2]) <= 1e-15, "Loan APR matches independent analytic golden at scale %s, request %s" % [point[0], point[1]])
	for scale in [1.0, 2.5]:
		career.params.negative_rate_efficacy_scale_pct = scale
		for rate in [0.0, 0.25, 4.0, 1000.0]:
			check(career._credit_context(rate, 0, career.credit_state).annual_rate_pct == rate, "Zero and positive APR are exactly unchanged at either scale")
		var prior := -INF
		for rate in [-1000.0, -10.0, -3.0, -1.0, -0.01, -0.000001, 0.0, 0.000001, 1.0, 10.0]:
			var apr: float = career._credit_context(rate, 0, career.credit_state).annual_rate_pct
			check(apr > prior and apr >= -scale, "Loan transmission is monotone and asymptotic on the analytic grid")
			prior = apr
		check(absf(career._credit_context(-0.000001, 0, career.credit_state).annual_rate_pct + 0.000001) < 1e-17, "Negative loan transmission joins the unchanged positive branch continuously at zero")
	var data := career.payload()
	check(data.priced_workout_version == 2 and data.credit_contract.version == 2 and data.credit_contract.apr_mapping == "Economy._effective_rate(requested_policy_rate_pct,negative_rate_efficacy_scale_pct)", "Only the priced payload identifies the revised authored contract")
	check(career.advance(choice(career, 4.0, 2.4)).ok, "Custom-scale fixture originates principal")
	career.params.negative_rate_efficacy_scale_pct = 2.5
	var policy := choice(career, -10.0, 1000000.0)
	var preview := career.forecast(policy)
	var actual := career.advance(policy)
	check(preview.ok and actual.ok and preview.credit_results[0] == actual.credit_result and absf(career.credit_contexts[-1].annual_rate_pct - -2.4983232493476675) <= 1e-15 and career.credit_snapshot().held_annual_rate_pct == career.credit_contexts[-1].annual_rate_pct, "Custom positive scale is shared by preview, actual contract and held snapshot")
	check(actual.ok and career.decisions[-1] == policy, "Large loan offers, requested policy and guidance are preserved without hard input caps")

func _test_invalid_inputs(opening: Dictionary) -> void:
	var career := Priced.new()
	check(start(career, opening).ok, "Atomic input fixture starts")
	for key in ["policy_rate_request_pct", "guidance_rate_pct", "liquidity_request_pct_initial_gdp"]:
		for value in [NAN, INF, -INF, true, false, "-10", null, [], {}]:
			var policy := choice(career)
			policy[key] = value
			var policy_bytes := career.encode()
			check(not career.forecast(policy).ok and career.encode() == policy_bytes, "Invalid typed/nonfinite policy preview is atomic: " + key)
			check(not career.advance(policy).ok and career.encode() == policy_bytes, "Invalid typed/nonfinite policy adoption is atomic: " + key)
		var missing := choice(career)
		missing.erase(key)
		var missing_bytes := career.encode()
		check(not career.forecast(missing).ok and not career.advance(missing).ok and career.encode() == missing_bytes, "Missing policy input rejects atomically: " + key)
	for value in [0.0, -1.0, NAN, INF, -INF, true, "1", null]:
		career.params.negative_rate_efficacy_scale_pct = value
		var scale_bytes := career.encode()
		check(not career.forecast(choice(career, -10.0)).ok and not career.advance(choice(career, -10.0)).ok and career.encode() == scale_bytes, "Invalid mapping scale rejects without mutation or coercion")
	career.params.erase("negative_rate_efficacy_scale_pct")
	var without_scale_bytes := career.encode()
	check(not career.forecast(choice(career, -10.0)).ok and not career.advance(choice(career, -10.0)).ok and career.encode() == without_scale_bytes, "Missing mapping scale rejects atomically")

func _test_integer_rate_inputs(opening: Dictionary) -> void:
	var career := Priced.new()
	check(start(career, opening).ok, "Exact-integer rate fixture starts")
	for rate in [-9007199254740993, 9007199254740993]:
		# Direct assignment deliberately avoids choice()'s typed float argument.
		var policy := choice(career)
		policy.policy_rate_request_pct = rate
		var frozen := career.encode()
		var context := career._credit_context(policy.policy_rate_request_pct, 0, career.credit_state)
		check(typeof(policy.policy_rate_request_pct) == TYPE_INT and is_nan(context.annual_rate_pct) and not Economy._bw_credit_accrual(0.0, context).ok and career.encode() == frozen, "Either out-of-range integer sign is invalid before loan-APR conversion")
		check(not career.forecast(policy).ok and career.encode() == frozen, "Out-of-range integer requested rate rejects preview atomically")
		check(not career.advance(policy).ok and career.encode() == frozen, "Out-of-range integer requested rate rejects adoption atomically")
	for rate in [-9007199254740992, 9007199254740992]:
		var context := career._credit_context(rate, 0, career.credit_state)
		var raw_context: Dictionary = context.duplicate(true)
		raw_context.annual_rate_pct = rate
		check(Economy._bw_credit_accrual(0.0, raw_context).ok and Economy._bw_credit_accrual(0.0, context).ok, "Exact integer boundary retains original primitive admissibility on zero opening principal")
		check(context.annual_rate_pct == (-1.0 if rate < 0 else rate), "Safe integer boundary maps only the negative branch")
	for rate in [-9007199254740994.0, 9007199254740994.0]:
		var context := career._credit_context(rate, 0, career.credit_state)
		check(Economy._bw_credit_accrual(0.0, context).ok and context.annual_rate_pct == (-1.0 if rate < 0 else rate), "Exact-integer validation does not impose a finite-floating-rate cap")
	for scale in [-9007199254740993, 9007199254740993]:
		career.params.negative_rate_efficacy_scale_pct = scale
		var policy := choice(career, -10.0)
		var frozen := career.encode()
		var context := career._credit_context(policy.policy_rate_request_pct, 0, career.credit_state)
		check(is_nan(context.annual_rate_pct) and not Economy._bw_credit_accrual(0.0, context).ok, "Scale also rejects out-of-range integers before conversion")
		check(not career.forecast(policy).ok and career.encode() == frozen, "Invalid integer scale rejects preview atomically")
		check(not career.advance(policy).ok and career.encode() == frozen, "Invalid integer scale rejects adoption atomically")
	career.params.negative_rate_efficacy_scale_pct = 9007199254740992
	check(career._credit_context(-1.0, 0, career.credit_state).annual_rate_pct == -1.0, "Positive exact integer scale boundary remains admissible")

func _test_extreme_subsidy(opening: Dictionary) -> void:
	var payments: Array = []
	var raw_payments: Array = []
	for rate in [-10.0, -1000.0]:
		var career := Priced.new()
		check(career.start_episode(opening.bank, opening.requests, opening.haircut_pct, opening.pledgeable_share, "stagflation_bank_run", 1, opening.remaining_request_index).ok, "Historical-diagnostic seed-1 fixture starts")
		var first := career.advance(choice(career, 8.0, 2.4))
		check(first.ok and first.bank_state.central_bank_loan == 2.4, "Q1 fixes actual Q2 opening principal at 2.4 initial-GDP units")
		if not first.ok:
			continue
		var policy := choice(career, rate, 0.0)
		var frozen := career.encode()
		var forecast := career.forecast(policy)
		check(forecast.ok and career.encode() == frozen and career.credit_snapshot().held_annual_rate_pct == 8.0, "Extreme staged preview is pure and distinct from held-rate quote")
		if not forecast.ok:
			continue
		var future: Dictionary = career.shocks[2].duplicate(true)
		var future_request: Variant = career.withdrawal_requests[2]
		career.shocks[2].supply_innovation_pct = 5.0
		career.withdrawal_requests[2] = 0.2
		check(var_to_bytes(career.forecast(policy)) == var_to_bytes(forecast), "Extreme negative-rate preview cannot see future shocks or withdrawals")
		career.shocks[2] = future
		career.withdrawal_requests[2] = future_request
		var raw_context := career._credit_context(rate, 1, career.credit_state)
		raw_context.annual_rate_pct = rate
		var raw := Economy.bank_workout_step(career.bank_state, {"annual_yield_pct": 8.0, "new_withdrawals": 0.0, "liquidity_offer": 0.0, "haircut_pct": career.haircut_pct, "pledgeable_share": career.pledgeable_share}, raw_context)
		check(raw.ok, "External raw APR still enters the general credit primitive")
		if raw.ok:
			raw_payments.append(raw.credit_result.paid_negative)
		var actual := career.advance(policy)
		check(actual.ok, "Extreme negative requested policy remains admissible")
		if not actual.ok:
			continue
		check(actual.state == forecast.states[0] and actual.bank_state == forecast.bank_states[0] and actual.credit_result == forecast.credit_results[0] and actual.credit_state == forecast.credit_states[0] and career.credit_contexts[-1] == forecast.credit_contexts[0], "Extreme negative first preview equals actual state, principal, claims and committed contract")
		check(career.decisions[-1] == policy and actual.state.policy_rate_pct == rate and career.decisions[-1].guidance_rate_pct == rate and career.decisions[-1].liquidity_request_pct_initial_gdp == 0.0, "Nominal request, guidance and loan offer remain uncapped and unchanged")
		var expected_payment := 0.005983561619169537 if rate == -10.0 else 0.005983561643835617
		check(absf(actual.credit_result.accrued_negative - expected_payment) < 1e-15 and actual.credit_result.paid_negative == actual.credit_result.accrued_negative, "Q2 actual reverse cash matches independent fixed-principal analytic oracle")
		payments.append(actual.credit_result.paid_negative)
		var snapshot := career.credit_snapshot()
		check(snapshot.requested_policy_rate_pct == rate and snapshot.held_requested_policy_rate_pct == rate and snapshot.annual_rate_pct == career.credit_contexts[-1].annual_rate_pct and snapshot.held_annual_rate_pct == snapshot.annual_rate_pct, "Held and actual negative quote share mapping but retain nominal policy separately")
		var briefing := career.workout_briefing()
		check(briefing.ok and absf(briefing.bank_result.credit_result.accrued_negative - actual.bank_state.central_bank_loan * absf(snapshot.held_annual_rate_pct) / 100.0 * 92.0 / 365.0) < 1e-15, "Held briefing uses the same mapped APR on actual next opening principal")
		career.params.negative_rate_efficacy_scale_pct = 2.5
		check(career.credit_snapshot().annual_rate_pct == snapshot.annual_rate_pct and career.credit_snapshot().held_annual_rate_pct != snapshot.held_annual_rate_pct, "Last actual APR is the committed contract, never recomputed from a later quote scale")
	check(payments.size() == 2 and payments[1] / payments[0] < 1.00000001 and payments[1] > payments[0], "Minus1000 no longer pays a hundredfold Q2 subsidy versus minus10")
	check(raw_payments.size() == 2 and absf(raw_payments[1] - 5.983561643835617) < 1e-12 and absf(raw_payments[1] / raw_payments[0] - 100.0) < 1e-12, "Externally authored raw minus1000 APR remains linear in the general primitive")

func finish() -> void:
	if failures == 0:
		print("PASS: priced workout career ", checks, " checks; optional authored laboratory")
	else:
		printerr("FAIL: priced workout career ", failures, " of ", checks)
	quit(0 if failures == 0 else 1)
