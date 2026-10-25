extends SceneTree
const Economy = preload("res://model/economy.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures <= 10:
			print("FAIL: ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(abs(actual - expected) <= 1e-10, label)

func _initialize() -> void:
	var model := Economy.new()
	var loaded: Dictionary = model.load_parameters()
	check(loaded.ok, "Parameter records load with the optional authored recipe")
	if not loaded.ok:
		finish()
		return
	var params: Dictionary = loaded.values
	var frozen := var_to_bytes(params)
	var opening: Dictionary = Economy.bank_workout_opening(params)
	check(opening.ok, "Authored optional opening validates")
	if not opening.ok:
		finish()
		return
	check(opening.bank.quarter_index == 0 and opening.bank.central_bank_loan == 0.0 and opening.bank.loan_arrears == 0.0 and opening.bank.withdrawal_queue == 0.0, "Opening clock and all prior-credit/request balances are zero")
	check(opening.bank.deposits == 2.7 and opening.bank.cash == 0.0 and opening.bank.annual_yield_pct == 4.0, "Configured deposits, cash and historical quote are explicit")
	check(opening.bank.claims == [{"maturity_quarter": 2, "face": 0.52}, {"maturity_quarter": 5, "face": 0.55}, {"maturity_quarter": 20, "face": 2.97}], "Dated fixed-face ladder is constructed without reinvestment")
	near(opening.bank.initial_face, 4.04, "Initial face is the stable sum of the three supplied claims")
	check(opening.bank.matured_face == 0.0 and opening.haircut_pct == 4.0 and opening.pledgeable_share == 5.0 / 6.0, "Opening collateral assumptions match the authored recipe")
	check(opening.requests == [2.4, 0.1, 0.1, 0.1, 0.0, 0.0, 0.0, 0.0], "All eight requests are explicit and aligned to Q1 through Q8")
	check(opening.remaining_request_index == 3, "Q4 final wave explicitly requests actual remaining unrequested deposits")
	var quoted: Dictionary = Economy.bank_workout_value(opening.bank, 4.0)
	check(quoted.ok, "Opening is accepted by the shared bank validator/pricer")
	var state: Dictionary = opening.bank
	var replay := state.duplicate(true)
	var paid := 0.0
	for turn in range(8):
		var request: float = opening.requests[turn]
		if turn == opening.remaining_request_index:
			var remaining: Dictionary = Economy.bank_workout_remaining_request(state)
			check(remaining.ok, "Final wave computes its actual unrequested claim")
			if not remaining.ok:
				finish()
				return
			request = remaining.request
		var order := {"annual_yield_pct": 4.0, "new_withdrawals": request, "liquidity_offer": 0.0,
			"haircut_pct": opening.haircut_pct, "pledgeable_share": opening.pledgeable_share}
		var result: Dictionary = Economy.bank_workout_step(state, order)
		var repeated: Dictionary = Economy.bank_workout_step(replay, order)
		check(result.ok and repeated.ok, "Complete request schedule remains physically valid through distress")
		if not result.ok or not repeated.ok:
			finish()
			return
		check(var_to_bytes(result) == var_to_bytes(repeated), "Recipe path has exact independent replay")
		check(result.state.quarter_index == turn + 1, "Recipe advances one meeting per request")
		paid += result.withdrawals_paid
		state = result.state
		replay = repeated.state
	near(paid + state.withdrawal_queue, 2.7, "Paid and queued requests retain all originally requested deposits")
	check(state.withdrawal_queue == state.deposits and state.claims == [{"maturity_quarter": 20, "face": 2.97}], "Every deposit was requested; only the dated long claim remains")
	near(state.matured_face, 1.07, "Q2/Q5 receipts mature exactly once")
	check(var_to_bytes(params) == frozen, "Opening and complete schedule preserve the caller parameter dictionary")
	var fresh: Dictionary = Economy.bank_workout_opening(params)
	var fresh_bytes := var_to_bytes(fresh)
	opening.bank.claims[0].face = 999.0
	opening.requests[0] = 999.0
	check(var_to_bytes(Economy.bank_workout_opening(params)) == fresh_bytes and var_to_bytes(params) == frozen, "Each call returns fresh bank/claim/request containers")
	_test_normal_core(model, params)
	_test_metadata()
	_test_invalid(params)
	_test_partial_payment_roundoff(params)
	finish()

func _test_partial_payment_roundoff(params: Dictionary) -> void:
	var opening: Dictionary = Economy.bank_workout_opening(params)
	var state: Dictionary = opening.bank
	var offers := [0.28, 2.5602, 3.5387, 0.885]
	var paid := 0.0
	for turn in range(3):
		var action := {"annual_yield_pct": 4.0, "new_withdrawals": opening.requests[turn],
			"liquidity_offer": offers[turn], "haircut_pct": opening.haircut_pct, "pledgeable_share": opening.pledgeable_share}
		var result: Dictionary = Economy.bank_workout_step(state, action)
		check(result.ok, "Confirmed partial-payment path reaches the final request")
		if not result.ok:
			return
		paid += result.withdrawals_paid
		state = result.state
	check(state.deposits < 0.1 and state.withdrawal_queue == 0.0, "Regression retains the real rounded liability, not a normalized decimal")
	var frozen := var_to_bytes(state)
	var action := {"annual_yield_pct": 4.0, "new_withdrawals": 0.1, "liquidity_offer": offers[3],
		"haircut_pct": opening.haircut_pct, "pledgeable_share": opening.pledgeable_share}
	var raw: Dictionary = Economy.bank_workout_step(state, action)
	check(not raw.ok and not raw.has("state"), "Raw fixed request correctly refuses to overdraw the actual deposit claim")
	var remaining: Dictionary = Economy.bank_workout_remaining_request(state)
	check(remaining.ok and remaining.request == state.deposits, "Final request uses exactly the actual unrequested deposits without epsilon")
	check(var_to_bytes(state) == frozen, "Remaining-request helper changes no queue, debt or cash")
	if not remaining.ok:
		return
	action.new_withdrawals = remaining.request
	var accepted: Dictionary = Economy.bank_workout_step(state, action)
	check(accepted.ok, "Semantic final wave advances the confirmed RED path")
	if accepted.ok:
		check(accepted.state.withdrawal_queue == accepted.state.deposits and accepted.state.central_bank_loan == state.central_bank_loan, "All actual deposits are requested; existing debt is not forgiven")
		near(paid + accepted.withdrawals_paid + accepted.state.deposits, opening.bank.deposits, "Actual paid and still-owed deposits conserve the original claim")
		near(accepted.equity_change, accepted.expected_equity_change, "Final request creates no equity or unbooked settlement correction")
	var queued := state.duplicate(true)
	queued.withdrawal_queue = 0.02
	var queued_bytes := var_to_bytes(queued)
	var rest: Dictionary = Economy.bank_workout_remaining_request(queued)
	check(rest.ok and rest.request == queued.deposits - queued.withdrawal_queue and var_to_bytes(queued) == queued_bytes, "Existing queued claims remain separate and unchanged")
	check(not Economy.bank_workout_remaining_request({}).ok and not Economy.bank_workout_remaining_request([]).ok, "Malformed remaining-request inputs fail closed")

func _test_normal_core(model: Object, params: Dictionary) -> void:
	var core := params.duplicate(true)
	for key in Economy.BANK_WORKOUT_RECIPE_KEYS:
		check(key not in Economy.PARAMETER_KEYS, "Optional lab inputs are not newly required core coefficients")
		core.erase(key)
	check(model._validate_parameters(core).ok, "Normal core accepts all optional recipe records being absent")
	var baseline: Dictionary = model.initial_state(core)
	var full: Dictionary = model.initial_state(params)
	check(baseline.ok and full.ok and var_to_bytes(baseline.state) == var_to_bytes(full.state), "Optional recipe does not change a fresh default macro state")
	if not baseline.ok or not full.ok:
		return
	check(full.state.quarter_index == 0 and full.state.outstanding_liquidity_pct_initial_gdp == 0.0, "Default native caller matches the optional opening clock/principal")
	var policy: Dictionary = model.benchmark_policy(baseline.state, core, "hold")
	var plain: Dictionary = model.step(baseline.state, policy, {}, core)
	var with_recipe: Dictionary = model.step(full.state, policy, {}, params)
	check(var_to_bytes(plain) == var_to_bytes(with_recipe), "Normal step ignores optional recipe values")
	var bad_optional := params.duplicate(true)
	bad_optional.bank_workout_initial_deposits_pct_initial_gdp = -1.0
	check(not Economy.bank_workout_opening(bad_optional).ok, "Only the optional opening enforces recipe economic domains")
	check(var_to_bytes(model.step(baseline.state, policy, {}, bad_optional)) == var_to_bytes(plain), "Invalid unused recipe cannot alter normal-core behavior")

func _test_metadata() -> void:
	var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://model/parameters.json"))
	var found := 0
	for row in rows:
		if row.key in Economy.BANK_WORKOUT_RECIPE_KEYS:
			found += 1
			check(row.classification == "design_assumption" and row.source == "" and not str(row.unit).is_empty(), "Optional recipe metadata declares authored units without an empirical source")
	check(found == Economy.BANK_WORKOUT_RECIPE_KEYS.size(), "Every recipe input has a disclosed numeric parameter record")

func _test_invalid(params: Dictionary) -> void:
	for key in Economy.BANK_WORKOUT_RECIPE_KEYS:
		var missing := params.duplicate(true)
		missing.erase(key)
		check(not Economy.bank_workout_opening(missing).ok, "Optional opening rejects incomplete recipe")
	for field_and_value in [["bank_workout_initial_deposits_pct_initial_gdp", -1.0], ["bank_workout_initial_cash_pct_initial_gdp", NAN],
		["bank_workout_reference_yield_pct", -200.0], ["bank_workout_short_face_pct_initial_gdp", -1.0],
		["bank_workout_short_maturity_quarter", 0.0], ["bank_workout_middle_maturity_quarter", 2.5],
		["bank_workout_long_face_pct_initial_gdp", 9007199254740993], ["bank_workout_haircut_pct", 101.0],
		["bank_workout_pledgeable_share", 1.1], ["bank_workout_first_withdrawal_pct_initial_gdp", 3.0],
		["bank_workout_following_withdrawal_pct_initial_gdp", -0.1], ["bank_workout_first_withdrawal_pct_initial_gdp", true]]:
		var invalid := params.duplicate(true)
		invalid[field_and_value[0]] = field_and_value[1]
		var frozen := var_to_bytes(invalid)
		check(not Economy.bank_workout_opening(invalid).ok and var_to_bytes(invalid) == frozen, "Invalid physical/numeric recipe rejects without mutation")
	check(not Economy.bank_workout_opening([]).ok, "Recipe requires a parameter dictionary")

func finish() -> void:
	print("BW_OPENING_CHECKS ", checks, " FAILURES ", failures)
	if failures == 0:
		print("PASS: optional authored eight-meeting opening, complete requests and unaffected default macro path; no calibration claim")
	quit(1 if failures else 0)
