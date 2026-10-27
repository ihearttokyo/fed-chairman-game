extends SceneTree
## Candidate controller-only closed-book runoff. No UI adoption or new economics.
const Workout = preload("res://play/workout_career.gd")
const Priced = preload("res://play/priced_workout_career.gd")
var checks := 0
var failures := 0

class CountingEconomy:
	extends "res://model/economy.gd"
	var transitions := 0
	func bank_workout_transition(state: Dictionary, policy: Dictionary, shocks: Dictionary, params: Dictionary, bank: Variant, order: Variant, credit: Dictionary = {}) -> Dictionary:
		transitions += 1
		return super.bank_workout_transition(state, policy, shocks, params, bank, order, credit)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func authored_requests() -> Array:
	# Same authored waves/final remaining-depositor request as the legacy recipe;
	# twenty explicit entries, not production padding or new withdrawal events.
	return [2.4, 0.1, 0.1, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

func frozen(career: Variant) -> PackedByteArray:
	return var_to_bytes([career.encode(), career.episode_quarters, career.params, career.cases, career._seeded_shocks, career.episodes])

func policy_for(career: Variant, first := false) -> Dictionary:
	var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold")
	policy.policy_rate_request_pct = 4.0
	policy.guidance_rate_pct = 4.0
	policy.liquidity_request_pct_initial_gdp = 2.0 if first else 0.0
	return policy

func begin(career: Variant, recipe: Dictionary, requests: Array, horizon: Variant) -> Dictionary:
	return career.start_episode(recipe.bank, requests, recipe.haircut_pct, recipe.pledgeable_share, "stagflation_bank_run", 417, recipe.remaining_request_index, horizon)

func legacy_and_validation(priced: bool) -> void:
	var legacy: Variant = Priced.new() if priced else Workout.new()
	var explicit: Variant = Priced.new() if priced else Workout.new()
	var recipe: Dictionary = legacy.model.bank_workout_opening(legacy.params)
	check(legacy.start_episode(recipe.bank, recipe.requests, recipe.haircut_pct, recipe.pledgeable_share, "stagflation_bank_run", 417, recipe.remaining_request_index).ok, "unchanged seven-argument caller starts")
	check(begin(explicit, recipe, recipe.requests, 8).ok, "explicit8 starts")
	check(legacy.EPISODE_QUARTERS == 8 and legacy.episode_quarters == 8 and explicit.episode_quarters == 8, "public constant and default instance remain8")
	check(frozen(legacy) == frozen(explicit), "default and explicit8 initial payload/state remain byte-identical")
	for meeting in range(8):
		var policy := policy_for(legacy, meeting == 0)
		check(var_to_bytes(legacy.forecast(policy)) == var_to_bytes(explicit.forecast(policy)), "default and explicit8 conditional result bytes agree")
		check(legacy.advance(policy).ok and explicit.advance(policy).ok and frozen(legacy) == frozen(explicit), "default and explicit8 actual histories/credit remain byte-identical")
	var terminal := frozen(legacy)
	check(not legacy.advance(policy_for(legacy)).ok and frozen(legacy) == terminal and legacy.mandate_assessment().complete, "default still refuses meeting9 atomically")
	check(legacy.situation_briefing() == "Eight-quarter episode complete. Retained claims remain visible in the bank ledger.", "legacy completion wording is unchanged")
	var requests := authored_requests()
	check(begin(legacy, recipe, requests, 20).ok and legacy.episode_quarters == 20, "explicit authored20 starts")
	check(legacy.advance(policy_for(legacy, true)).ok and legacy.advance(policy_for(legacy)).ok, "validation fixture has real adopted state and credit history")
	var preserved := frozen(legacy)
	var input_bytes := var_to_bytes([recipe, requests])
	for invalid in [0, -1, 241, 9223372036854775807, true, false, 20.0, 1.5, NAN, INF, -INF, "20", null, [], {}]:
		check(not begin(legacy, recipe, requests, invalid).ok and frozen(legacy) == preserved, "invalid horizon/type refuses without mutating any controller state: " + str(invalid))
	for length in [19, 21]:
		var bad := requests.duplicate()
		if length == 19:
			bad.pop_back()
		else:
			bad.append(0.0)
		check(not begin(legacy, recipe, bad, 20).ok and frozen(legacy) == preserved and bad.size() == length, "exact authored request count required; no truncation or extension")
	for index in [-2, 20, 21]:
		check(not legacy.start_episode(recipe.bank, requests, recipe.haircut_pct, recipe.pledgeable_share, "stagflation_bank_run", 417, index, 20).ok and frozen(legacy) == preserved, "remaining-depositor index must fit effective horizon")
	var later_wave := requests.duplicate()
	later_wave[19] = 0.1
	check(not begin(legacy, recipe, later_wave, 20).ok and frozen(legacy) == preserved, "later authored wave after final remaining request still refuses")
	var invalid_request := requests.duplicate()
	invalid_request[19] = NAN
	check(not begin(legacy, recipe, invalid_request, 20).ok and frozen(legacy) == preserved, "new tail entries receive the same finite request validation")
	check(var_to_bytes([recipe, requests]) == input_bytes, "all restarts preserve caller-owned recipe and request arrays")
	var upper: Array = []
	for index in range(240): upper.append(0.0)
	check(legacy.start_episode(recipe.bank, upper, recipe.haircut_pct, recipe.pledgeable_share, "base", 417, 239, 240).ok and legacy.episode_quarters == 240, "existing240 macro-record bound and last valid remaining index accepted")
	check(legacy.start_episode(recipe.bank, [0.0], recipe.haircut_pct, recipe.pledgeable_share, "base", 417, -1, 1).ok and legacy.episode_quarters == 1, "positive lower horizon bound accepted")
	check(legacy.start_episode(recipe.bank, recipe.requests, recipe.haircut_pct, recipe.pledgeable_share, "base", 417, recipe.remaining_request_index).ok and legacy.episode_quarters == 8, "later legacy restart resets custom horizon to default8")

func twenty_meetings(priced: bool) -> void:
	var career: Variant = Priced.new() if priced else Workout.new()
	var recipe: Dictionary = career.model.bank_workout_opening(career.params)
	check(begin(career, recipe, authored_requests(), 20).ok, "closed-book runoff controller starts at20")
	career.model = CountingEconomy.new()
	for meeting in range(20):
		var policy := policy_for(career, meeting == 0)
		if meeting in [0, 8, 19]:
			var before := frozen(career)
			var steps: int = career.model.transitions
			var forecast: Dictionary = career.forecast(policy)
			check(forecast.ok and forecast.states.size() == 8 and forecast.bank_results.size() == 8 and career.model.transitions == steps + 8, "custom horizon does not turn preview into20 steps")
			check(forecast.episode_end_quarter == 20 and forecast.diagnostic_beyond_episode == (meeting + 8 > 20) and frozen(career) == before, "forecast metadata uses effective horizon without mutating actual state")
		if meeting == 8:
			check(career._current_request().ok and career.workout_briefing().ok and not career.current_briefing().is_empty() and not career.mandate_assessment().complete, "meeting9 briefing/request/assessment remain active under20")
			if priced:
				check(career.credit_snapshot().next_days == 90 and career.credit_snapshot().held_annual_rate_pct == 4.0, "priced next-day/APR snapshot remains available after legacy endpoint")
		if meeting == 19:
			check(career.bank_state.claims.size() == 1 and career.bank_state.claims[0].maturity_quarter == 20 and career.bank_state.claims[0].face == 2.97, "native last security is still present beforeQ20, not forgiven early")
			check(career.bank_state.loan_arrears > 0 and career.bank_state.withdrawal_queue > 0, "real overdue principal and withdrawal queue carry beyondQ8 until last maturity")
			if priced:
				check(career.credit_state.payable > 0 and career.credit_results.size() == 19, "unpaid positive interest carries natively throughQ19")
		var steps: int = career.model.transitions
		var actual: Dictionary = career.advance(policy)
		check(actual.ok, "actual meeting%d settles with unchanged native transition" % (meeting + 1))
		if not actual.ok:
			printerr("TRANSITION_ERROR: ", actual)
			return
		check(career.model.transitions == steps + 1 and career.bank_state.quarter_index == meeting + 1 and career.state.quarter_index == meeting + 1, "each adoption remains exactly one synchronized bank/macro transition")
		check(career.bank_state.central_bank_loan == career.state.outstanding_liquidity_pct_initial_gdp, "principal remains on both native ledgers")
		if priced and meeting == 1:
			check(career.credit_results[-1].accrued_positive > 0 and career.credit_state.payable > 0, "extended priced run uses real native loan-interest accrual and retained unpaid claims")
		if meeting == 19:
			check(actual.bank_result.matured_principal == 2.97 and career.bank_state.claims.is_empty() and is_equal_approx(career.bank_state.matured_face, 4.04), "Q20 pays the native final face once and removes its security claim")
	check(career.decisions.size() == 20 and career.history.size() == 21 and career.bank_history.size() == 21 and career.settlements.size() == 20 and career.mandate_assessment().complete and not career.mandate_assessment().eligible, "terminal histories/assessment use20 without granting normal awards")
	if priced:
		check(career.credit_history.size() == 21 and career.credit_results.size() == 20 and career.credit_contexts.size() == 20 and career.credit_snapshot().next_days == null, "all20 credit records retained and terminal quote cleared")
	var complete := frozen(career)
	var steps: int = career.model.transitions
	check(not career.advance(policy_for(career)).ok and career.model.transitions == steps and frozen(career) == complete, "meeting21 refuses atomically before another economic step")
	check(not career._current_request().ok and not career.workout_briefing().ok and career.current_briefing().is_empty() and not career.forecast(policy_for(career)).ok and frozen(career) == complete, "all complete request/briefing/forecast guards use20 and retain state")
	check(career.situation_briefing().begins_with("20-quarter episode complete"), "custom completion text reports its actual authored length")
	print("RUNOFF20: priced=", priced, " Q=", career.state.quarter_index, " principal=", career.bank_state.central_bank_loan, " queue=", career.bank_state.withdrawal_queue, " matured=", career.bank_state.matured_face, " steps=", career.model.transitions)

func _initialize() -> void:
	for priced in [false, true]:
		legacy_and_validation(priced)
		twenty_meetings(priced)
	if failures == 0:
		print("PASS: configurable workout horizon ", checks, " checks; controller candidate only, not gameplay acceptance")
	quit(1 if failures else 0)
