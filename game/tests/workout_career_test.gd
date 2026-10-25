extends SceneTree
const Workout = preload("res://play/workout_career.gd")
const Career = preload("res://play/career.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func opening() -> Dictionary:
	# Authored fixture, not a calibrated bank or a playable production recipe.
	return {"quarter_index": 0, "cash": 0.0, "deposits": 3.0, "withdrawal_queue": 0.0,
		"central_bank_loan": 0.0, "loan_arrears": 0.0, "annual_yield_pct": 4.0,
		"claims": [{"maturity_quarter": 3, "face": 5.0}], "initial_face": 5.0, "matured_face": 0.0}

func snapshot(career: Object) -> PackedByteArray:
	return var_to_bytes([career.state, career.history, career.decisions, career.bank_state, career.bank_history,
		career.settlements, career.shocks, career.withdrawal_requests, career.params])

func _initialize() -> void:
	var career := Workout.new()
	var bank := opening()
	var requests := [1.0, 0.25, 0.25, 0.0, 0.0, 0.0, 0.0, 0.0]
	var original := var_to_bytes([bank, requests])
	check(career.start_episode(bank, requests, 4.0, 1.0, "base").ok, "Episode installs both valid opening states")
	check(var_to_bytes([bank, requests]) == original, "Episode does not mutate author inputs")
	check(career.current_briefing().funding_need_pct_initial_gdp == 1.0, "Current briefing uses actual bank request instead of ordinary zero funding")
	var initial := career.encode()
	var original_state := snapshot(career)
	var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold")
	policy.liquidity_request_pct_initial_gdp = 1.0
	var projected := career.forecast(policy)
	check(projected.ok and projected.states.size() == 8 and projected.bank_states.size() == 8, "Preview advances both ledgers for eight conditional quarters")
	check(career.encode() == initial and snapshot(career) == original_state, "Preview leaves actual bank, history and decisions unchanged")
	var alternate := Workout.new()
	check(alternate.start_episode(bank, [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 4.0, 1.0, "base").ok, "Alternate future-only request fixture starts")
	check(var_to_bytes(alternate.forecast(policy)) == var_to_bytes(projected), "Hidden future requests cannot leak into conditional previews")
	var first := career.advance(policy)
	check(first.ok, "An actual first policy originates the workout loan")
	if first.ok:
		check(first.state == projected.states[0] and first.bank_state == projected.bank_states[0], "Preview first step exactly equals actual settlement")
		check(first.bank_result.withdrawals_paid == 1.0 and career.bank_state.central_bank_loan == 1.0, "Depositor payment and native loan are real accepted flows")
	check(career.encode() != initial, "Actual settlement marks the in-memory episode dirty")
	check(not career.mandate_assessment().eligible and not career.recovery_assessment().eligible, "Laboratory cannot earn normal career awards")
	check(career.current_shock_episode().is_empty(), "Overridden funding never borrows a catalogue label")
	var frozen := career.encode()
	var frozen_state := snapshot(career)
	var invalid := policy.duplicate(true)
	invalid.policy_rate_request_pct = NAN
	check(not career.advance(invalid).ok and career.encode() == frozen and snapshot(career) == frozen_state, "Rejected policy preserves both histories")
	var no_offer: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold")
	check(career.advance(no_offer).ok, "Zero offer advances rather than freezing on distress")
	check(career.bank_state.central_bank_loan == 1.0 and career.bank_state.loan_arrears == 1.0 and career.bank_state.withdrawal_queue == 0.25, "Unpaid debt and queued withdrawals persist across meetings")
	for q in range(2, 8):
		var choice: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold")
		if q == 7:
			var end_preview := career.forecast(choice)
			check(end_preview.ok and end_preview.states.size() == 8 and end_preview.diagnostic_beyond_episode and end_preview.episode_end_quarter == 8, "Q7 preview explicitly labels diagnostic continuation beyond playable Q8")
		check(career.advance(choice).ok, "Remaining workout meeting advances")
	check(career.bank_state.claims.is_empty() and career.bank_state.central_bank_loan == 0.0 and career.bank_state.withdrawal_queue == 0.0, "Maturity cash cures retained claims once")
	check(career.decisions.size() == 8 and career.bank_history.size() == 9 and career.history.size() == 9, "Episode horizon and paired histories agree")
	frozen = career.encode()
	frozen_state = snapshot(career)
	check(not career.advance(no_offer).ok and career.encode() == frozen and snapshot(career) == frozen_state, "Ninth adoption is rejected without mutation")
	check(career.current_briefing().is_empty(), "Completed episode exposes no ordinary ninth-quarter shock")
	check(not career.forecast(no_offer).ok, "Completed episode cannot pretend to have another decision")
	check(not career.start_episode(bank, [4.0, 0, 0, 0, 0, 0, 0, 0], 4, 1).ok and career.encode() == frozen, "Invalid restart preserves existing episode")
	var ordinary := Career.new()
	check(not ordinary.restore(career.payload()).ok, "Laboratory payload cannot enter a normal save")
	var forbidden := "user://workout-must-not-exist.bin"
	check(not FileAccess.file_exists(forbidden), "Isolation sentinel absent initially")
	check(not career.save_to(forbidden).ok and not career.load_from(forbidden).ok and not career.restore({}).ok, "All inherited storage entry points fail before file access")
	check(not FileAccess.file_exists(forbidden) and career.encode() == frozen and snapshot(career) == frozen_state, "Save rejection neither writes a file nor mutates the episode")
	var smaller_params := career.params.duplicate(true)
	smaller_params.bank_workout_initial_deposits_pct_initial_gdp = 2.65
	var smaller: Dictionary = career.model.bank_workout_opening(smaller_params)
	check(smaller.ok and Workout.new().start_episode(smaller.bank, smaller.requests, smaller.haircut_pct, smaller.pledgeable_share, "base", 417, smaller.remaining_request_index).ok, "Final-wave display placeholder cannot reject a valid smaller remaining balance")
	var recipe: Dictionary = career.model.bank_workout_opening(career.params)
	check(recipe.ok, "Production authored opening is available for bounded policy-path tests")
	if recipe.ok:
		var rng := RandomNumberGenerator.new()
		rng.seed = 618
		for run_index in range(32):
			var trial := Workout.new()
			check(trial.start_episode(recipe.bank, recipe.requests, recipe.haircut_pct, recipe.pledgeable_share, "stagflation_bank_run", 417, recipe.remaining_request_index).ok, "Varied-policy episode starts with explicit final remaining-depositor wave")
			for meeting in range(8):
				var choice: Dictionary = trial.model.benchmark_policy(trial.state, trial.params, "hold")
				choice.policy_rate_request_pct = snappedf(rng.randf_range(-2.0, 12.0), 0.01)
				choice.guidance_rate_pct = choice.policy_rate_request_pct
				choice.liquidity_request_pct_initial_gdp = rng.randf_range(0.0, 4.0)
				var request := trial._current_request()
				check(request.ok, "Current request remains physically valid after partial-payment histories")
				var outcome := trial.advance(choice)
				check(outcome.ok, "Finite varied rate/partial-offer path advances without a rounded fixed-request freeze")
				if not outcome.ok:
					printerr("DETAIL: path ", run_index, " meeting ", meeting, " ", outcome.error)
					break
				check(trial.bank_state.central_bank_loan == trial.state.outstanding_liquidity_pct_initial_gdp, "Every varied path keeps bank and native principal identical")
			check(trial.decisions.size() == 8, "All eight meetings remain playable in the bounded policy set")
	if failures == 0:
		print("PASS: workout career %d checks" % checks)
	quit(0 if failures == 0 else 1)
