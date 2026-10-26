extends SceneTree
## Optional, externally collectible-credit experiment; no UI/adoption/save test.
const Economy = preload("res://model/economy.gd")
const Career = preload("res://play/career.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures <= 15:
			printerr("FAIL: " + message)

func near(actual: float, expected: float, message: String) -> void:
	check(is_finite(actual) and absf(actual - expected) <= 1e-11, message)

func context(apr: float = 0.0, payable: float = 0.0, receivable: float = 0.0, days: int = 365) -> Dictionary:
	return {"annual_rate_pct": apr, "days": days, "payable": payable, "receivable": receivable, "collectible": true, "allow_negative": true}

func legacy(result: Dictionary) -> Dictionary:
	var copy := result.duplicate(true)
	copy.erase("credit_state")
	copy.erase("credit_result")
	if copy.has("bank_result"):
		copy.bank_result = legacy(copy.bank_result)
	return copy

func refuse(result: Dictionary, message: String) -> void:
	check(not result.ok and not result.has("state") and not result.has("bank_state"), message)

func paired(fixture: Dictionary, bank: Dictionary, credit: Dictionary, withdrawals: float = 1.0, offer: float = 0.0) -> Dictionary:
	var policy: Dictionary = fixture.model.benchmark_policy(fixture.native, fixture.params, "hold")
	policy.liquidity_request_pct_initial_gdp = offer
	policy.maintain_ample_reserves = false
	var order := {"new_withdrawals": withdrawals, "haircut_pct": 4.0, "pledgeable_share": 1.0}
	var inputs := [fixture.native, policy, {}, fixture.params, bank, order, credit]
	var frozen := var_to_bytes(inputs)
	var result: Dictionary = fixture.model.bank_workout_transition(fixture.native, policy, {}, fixture.params, bank, order, credit)
	var repeated: Dictionary = fixture.model.bank_workout_transition(fixture.native, policy, {}, fixture.params, bank, order, credit)
	check(result.ok, "Actual native/private priced transition accepts the authored fixture")
	if not result.ok:
		printerr(result.get("error", "unknown"))
	check(var_to_bytes(result) == var_to_bytes(repeated), "Entire coupled result repeats exactly")
	check(var_to_bytes(inputs) == frozen, "All coupled/context caller inputs remain byte-pure")
	if result.ok and not credit.is_empty():
		var diagnostic: Dictionary = result.credit_result
		var income: float = diagnostic.accrued_positive - diagnostic.accrued_negative
		near(diagnostic.fed_interest_income, income, "Recognized Fed income is accrual, not cash receipts a second time")
		near(diagnostic.fed_capital_after - diagnostic.fed_capital_before, income, "Independent combined Fed capital delta equals recognized income")
		near(diagnostic.bank_equity_after - diagnostic.bank_equity_before, result.bank_result.expected_equity_change - diagnostic.net_cash_to_bank - income, "Independent combined bank-equity delta equals repricing minus accrued expense")
		near(result.state.capital_other_pct_initial_gdp - fixture.native.capital_other_pct_initial_gdp, diagnostic.paid_positive - diagnostic.paid_negative, "Core Fed capital changes only for actual settled cash interest")
		check(result.state.outstanding_liquidity_pct_initial_gdp == result.bank_state.central_bank_loan and result.state.quarter_index == result.bank_state.quarter_index, "Native/private principal and clocks remain paired")
	return result

func _initialize() -> void:
	var career := Career.new()
	# Constructor-validated cash-settlement headroom, not an estimated coefficient.
	career.params.initial_reserves_pct_initial_gdp = 20.0
	var started: Dictionary = career.start("stagflation_bank_run", 417)
	check(started.ok, "Genuine native career starts")
	if not started.ok:
		finish()
		return
	var origin: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold")
	origin.liquidity_request_pct_initial_gdp = 2.0
	origin.maintain_ample_reserves = true
	var warmed: Dictionary = career.advance(origin)
	check(warmed.ok and career.state.outstanding_liquidity_pct_initial_gdp == 2.0, "Old principal is actually originated by the native ledger")
	if not warmed.ok:
		finish()
		return
	var fixture := {"model": career.model, "native": career.state.duplicate(true), "params": career.params}
	var q: int = career.state.quarter_index
	var bank := {"quarter_index": q, "cash": 4.0, "deposits": 3.0, "withdrawal_queue": 0.0,
		"central_bank_loan": 2.0, "loan_arrears": 0.0, "annual_yield_pct": 0.0,
		"claims": [{"maturity_quarter": q + 3, "face": 10.0}], "initial_face": 10.0, "matured_face": 0.0}
	var bank_order := {"annual_yield_pct": 0.0, "new_withdrawals": 1.0, "liquidity_offer": 0.0, "haircut_pct": 4.0, "pledgeable_share": 1.0}
	var brief_order := {"new_withdrawals": 1.0, "haircut_pct": 4.0, "pledgeable_share": 1.0}
	var old_step := Economy.bank_workout_step(bank, bank_order)
	var zero_step := Economy.bank_workout_step(bank, bank_order, context())
	check(var_to_bytes(old_step) == var_to_bytes(legacy(zero_step)), "Zero APR/claims preserve every original bank-step field exactly")
	check(var_to_bytes(Economy.bank_workout_briefing(bank, brief_order)) == var_to_bytes(legacy(Economy.bank_workout_briefing(bank, brief_order, context()))), "Zero APR/claims preserve the briefing including original projection exactly")
	var baseline := paired(fixture, bank, {})
	var zero := paired(fixture, bank, context())
	if baseline.ok and zero.ok:
		check(var_to_bytes(baseline) == var_to_bytes(legacy(zero)), "All legacy coupled fields/state/trace are byte-identical for zero APR/claims")
	var positive := paired(fixture, bank, context(50.0))
	var negative := paired(fixture, bank, context(-50.0))
	if positive.ok and negative.ok and baseline.ok:
		check(positive.credit_result.accrued_positive == 1 and positive.credit_result.paid_positive == 1 and positive.credit_state.payable == 0, "Positive accrual and paid cash are distinct equal entries in this fixture")
		check(negative.credit_result.accrued_negative == 1 and negative.credit_result.paid_negative == 1 and negative.credit_state.receivable == 0, "Explicit counterfactual negative accrual has the reverse claim/cash entry")
		check(positive.bank_state.central_bank_loan == baseline.bank_state.central_bank_loan and negative.bank_state.central_bank_loan == baseline.bank_state.central_bank_loan, "Interest is never capitalized into principal")
		near(positive.state.reserves_pct_initial_gdp - baseline.state.reserves_pct_initial_gdp, -1.0, "Positive cash interest retires native reserves")
		near(negative.state.reserves_pct_initial_gdp - baseline.state.reserves_pct_initial_gdp, 1.0, "Negative cash interest creates native reserves")
	var fresh := paired(fixture, bank, context(50.0), 3.0, 100.0)
	if fresh.ok:
		check(fresh.credit_result.paid_positive == 1 and fresh.credit_state.payable == 0 and fresh.bank_result.new_cash == 2 and fresh.bank_result.withdrawals_paid == 3, "Uncapped collateral-supported fresh cash funds deposits only after prior cash paid interest")
		check(fresh.bank_state.central_bank_loan == fresh.bank_result.new_cash and fresh.state.liquidity_new_need_applied_pct_initial_gdp == fresh.bank_result.new_cash, "Any changed new principal has an actual fresh-cash counterpart, never capitalization")
	var low_cash := bank.duplicate(true)
	low_cash.cash = 2.25
	var partial := paired(fixture, low_cash, context(100.0))
	if partial.ok:
		check(partial.credit_result.paid_positive == 0.25 and partial.credit_state.payable == 1.75 and partial.bank_state.central_bank_loan == 0, "Principal is repaid first; insufficient remaining cash retains unpaid interest separately")
		check(partial.bank_state.withdrawal_queue == 1 and partial.bank_state.cash == 0, "Interest cash settlement precedes depositor payments without forgiveness")
	var no_cash := bank.duplicate(true)
	no_cash.cash = 0.0
	var carried := paired(fixture, no_cash, context(50.0))
	if carried.ok:
		check(carried.credit_state.payable == 1 and carried.credit_result.paid_positive == 0 and carried.bank_state.central_bank_loan == 2, "Unpaid interest and old principal remain separate")
		var next_fixture := {"model": fixture.model, "native": carried.state, "params": fixture.params}
		var reverse := paired(next_fixture, carried.bank_state, context(-50.0, carried.credit_state.payable), 0.0)
		if reverse.ok:
			check(reverse.credit_state.payable == 1 and reverse.credit_result.paid_positive == 0 and reverse.credit_result.paid_negative == 1, "Sign switch does not net/forgive the old positive claim")
	var maturity := bank.duplicate(true)
	maturity.cash = 0.0
	maturity.claims = [{"maturity_quarter": q + 1, "face": 4.0}]
	maturity.initial_face = 4.0
	var matured := paired(fixture, maturity, context(50.0))
	if matured.ok:
		check(matured.bank_result.matured_principal == 4 and matured.bank_result.repayment == 2 and matured.credit_result.paid_positive == 1 and matured.bank_result.withdrawals_paid == 1 and matured.bank_state.cash == 0, "Maturity cash follows principal, interest, then deposit waterfall")
		check(matured.bank_result.capacity == 0, "Matured cash is not still pledged collateral")
	var zero_days := Economy.bank_workout_step(bank, bank_order, context(50, 1, 0, 0))
	check(zero_days.ok and zero_days.credit_result.accrued_positive == 0 and zero_days.credit_result.paid_positive == 1, "Zero days accrue nothing but do not erase an existing payable")
	for key in context():
		var missing := context()
		missing.erase(key)
		refuse(Economy.bank_workout_step(bank, bank_order, missing), "Missing credit field refuses")
	for key in ["annual_rate_pct", "payable", "receivable"]:
		for value in [NAN, INF, true, "1", 9007199254740993]:
			var invalid := context()
			invalid[key] = value
			refuse(Economy.bank_workout_step(bank, bank_order, invalid), "Invalid credit amount refuses before coercion")
	for value in [-1, 1.5, true, 9007199254740993]:
		var invalid := context()
		invalid.days = value
		refuse(Economy.bank_workout_step(bank, bank_order, invalid), "Invalid actual whole days refuse")
	for key in ["payable", "receivable"]:
		var negative_claim := context()
		negative_claim[key] = -1.0
		refuse(Economy.bank_workout_step(bank, bank_order, negative_claim), "Negative separate claim refuses")
	var extra := context()
	extra.extra = 0
	refuse(Economy.bank_workout_step(bank, bank_order, extra), "Unknown context fields refuse")
	var impaired := context(50)
	impaired.collectible = false
	refuse(Economy.bank_workout_step(bank, bank_order, impaired), "Unsupported impaired/noncollectible interest refuses atomically")
	var disabled_negative := context(-50)
	disabled_negative.allow_negative = false
	refuse(Economy.bank_workout_step(bank, bank_order, disabled_negative), "Negative APR requires counterfactual opt-in")
	var rich := bank.duplicate(true)
	rich.cash = 1e20
	refuse(Economy.bank_workout_step(rich, bank_order, context(50)), "Cash interest cannot disappear in a huge balance")
	refuse(Economy.bank_workout_step(bank, bank_order, context(50, 1e20)), "Accrued positive interest cannot disappear inside an old huge claim")
	var tiny := 1e-300
	tiny *= 1e-20
	var tiny_bank := bank.duplicate(true)
	tiny_bank.central_bank_loan = tiny
	tiny_bank.cash = 0.0
	check(tiny > 0, "Underflow fixture begins with genuinely positive principal")
	refuse(Economy.bank_workout_step(tiny_bank, bank_order, context(1e-10, 0, 0, 1)), "Positive accrual underflow refuses, never becomes free credit")
	var crossing := bank.duplicate(true)
	crossing.cash = 0.0
	crossing.deposits = 7.5
	var renewal_order := {"annual_yield_pct": 0.0, "new_withdrawals": 0.0, "liquidity_offer": 2.0, "haircut_pct": 0.0, "pledgeable_share": 1.0}
	var crossing_result := Economy.bank_workout_step(crossing, renewal_order, context(50))
	check(crossing_result.ok, "Collectible-credit accounting permits signed negative equity without inferring impairment")
	if crossing_result.ok:
		check(crossing_result.equity_after == 0.5 and crossing_result.credit_result.bank_equity_after == -0.5, "Unpaid interest can cross combined equity through zero while principal-only equity remains positive")
		check(not crossing_result.solvent and crossing_result.workout, "Active-credit status flags use combined equity including unpaid interest")
	var interest_only := bank.duplicate(true)
	interest_only.cash = 2.0
	interest_only.deposits = 0.0
	var interest_only_result := Economy.bank_workout_step(interest_only, renewal_order, context(50))
	check(interest_only_result.ok, "A remaining interest payment is not inferred to be uncollectible")
	if interest_only_result.ok:
		check(interest_only_result.credit_state.payable == 1.0 and interest_only_result.loan_arrears == 0.0 and interest_only_result.remaining_queue == 0.0 and interest_only_result.solvent, "Interest-only shortfall is distinct from principal arrears, withdrawal queues and negative equity")
		check(interest_only_result.payment_distress and interest_only_result.workout, "Due unpaid interest is included in active-credit payment-distress flags")
	finish()

func finish() -> void:
	if failures == 0:
		print("PASS: priced workout ", checks, " checks, 0 failures; optional authored collectible-credit experiment")
	quit(0 if failures == 0 else 1)
