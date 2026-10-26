extends SceneTree
## Adoption diagnostic: retains the original desired-success assertions.
## Also covered by the default controller suite after the rounding repair.
## A pass alone does not establish shipped-mode or whole-game acceptance.
const Priced = preload("res://play/priced_workout_career.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)
func choice(career: Object, rate: float, offer: float) -> Dictionary:
	var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold")
	policy.policy_rate_request_pct = rate
	policy.guidance_rate_pct = rate
	policy.liquidity_request_pct_initial_gdp = offer
	policy.maintain_ample_reserves = true
	return policy
func start(career: Object, opening: Dictionary) -> Dictionary:
	return career.start_episode(opening.bank, opening.requests, opening.haircut_pct, opening.pledgeable_share, "stagflation_bank_run", 417, opening.remaining_request_index)
func _initialize() -> void:
	var career := Priced.new()
	var opening: Dictionary = career.model.bank_workout_opening(career.params)
	_test_minimum_loan(opening)
	print("MINIMUM_LOAN_DIAGNOSTIC: ", failures, " failures / ", checks, " checks; adoption blocked if nonzero")
	quit(1 if failures else 0)

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

