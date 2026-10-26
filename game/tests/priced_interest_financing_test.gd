extends SceneTree
## Revision B optional experiment, not production adoption or calibrated behavior.
const Economy = preload("res://model/economy.gd")
const Career = preload("res://play/career.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures <= 15:
			printerr("FAIL: " + message)

func ctx(finance: bool = true, payable: float = 0.0, receivable: float = 0.0, rate: float = 50.0) -> Dictionary:
	return {"annual_rate_pct": rate, "days": 365, "payable": payable, "receivable": receivable,
		"collectible": true, "allow_negative": true, "finance_interest": finance}

func bank(q: int = 0) -> Dictionary:
	return {"quarter_index": q, "cash": 0.0, "deposits": 3.0, "withdrawal_queue": 0.0,
		"central_bank_loan": 2.0, "loan_arrears": 0.0, "annual_yield_pct": 0.0,
		"claims": [{"maturity_quarter": q + 5, "face": 10.0}], "initial_face": 10.0, "matured_face": 0.0}

func action(offer: float = 100.0, withdrawals: float = 1.0) -> Dictionary:
	return {"annual_yield_pct": 0.0, "new_withdrawals": withdrawals, "liquidity_offer": offer, "haircut_pct": 0.0, "pledgeable_share": 1.0}

func step(b: Dictionary, a: Dictionary, c: Dictionary) -> Dictionary:
	var frozen := var_to_bytes([b, a, c])
	var result := Economy.bank_workout_step(b, a, c)
	check(result.ok, "Physical B bank fixture is accepted")
	if not result.ok:
		printerr(result.get("error", "unknown"))
	check(var_to_bytes([b, a, c]) == frozen, "Bank/order/context inputs stay byte-pure")
	check(var_to_bytes(result) == var_to_bytes(Economy.bank_workout_step(b, a, c)), "B result replays exactly")
	if result.ok:
		var d: Dictionary = result.credit_result
		check(d.new_cash_for_interest + d.new_cash_for_withdrawals == result.new_cash, "Purpose split equals actual fresh cash, not offer")
		check(result.state.central_bank_loan == b.central_bank_loan - result.repayment + result.new_cash, "Total principal has an actual repayment/fresh-cash bridge")
		check(result.state.withdrawal_queue == result.deposit_due - result.withdrawals_paid, "Only unpaid deposits enter the queue")
	return result

func refusal(result: Dictionary, message: String) -> void:
	check(not result.ok and not result.has("state") and not result.has("bank_state"), message)

func without_b(result: Dictionary) -> Dictionary:
	var copy := result.duplicate(true)
	for key in ["finance_interest", "interest_financing_active", "interest_due", "paid_positive_from_pre_advance_cash", "new_cash_for_interest", "new_cash_for_withdrawals", "uncovered_interest", "funding_need_before_advances"]:
		if copy.has("credit_result"):
			copy.credit_result.erase(key)
	if copy.has("bank_result"):
		copy.bank_result = without_b(copy.bank_result)
	return copy

func _initialize() -> void:
	var large_cash := bank()
	large_cash.cash = 50.0
	large_cash.deposits = 60.0
	large_cash.central_bank_loan = 0.0001
	var small_interest := ctx(true, 0.0, 0.0, 4.0)
	small_interest.days = 91
	var fractional_receipt := step(large_cash, action(0.0001, 50.0002), small_interest)
	if fractional_receipt.ok:
		check(fractional_receipt.new_cash == 0.0001 and fractional_receipt.state.central_bank_loan == 0.0001, "Small real advance survives a larger cash stock without altering principal")
		check(fractional_receipt.credit_result.has("gross_cash_roundoff"), "Gross receipt/remittance rounding is disclosed separately from final booked cash")
	var full := step(bank(), action(), ctx())
	var funded_once := step(bank(), action(100.0, 0.0), ctx())
	if funded_once.ok:
		check(funded_once.state.central_bank_loan == 3.0 and funded_once.credit_state.payable == 0.0 and funded_once.credit_result.new_cash_for_interest == 1.0, "First interest payment has an actual new loan, not an unpaid-claim capitalization")
		var funded_twice := step(funded_once.state, action(100.0, 0.0), ctx())
		if funded_twice.ok:
			check(funded_twice.credit_result.accrued_positive == 1.5 and funded_twice.state.central_bank_loan == 4.5 and funded_twice.credit_state.payable == 0.0, "Next-period interest uses actually advanced principal, including funded debt service")
	var fractional := step(bank(), action(100.0, 0.2), ctx(true, 0.1, 0.0, 0.0))
	if fractional.ok:
		check(fractional.credit_result.new_cash_for_interest == 0.1 and fractional.credit_result.new_cash_for_withdrawals == 0.2 and fractional.state.cash == 0.0, "Fully supported fractional purposes stay exact without manufactured residual cash")
	var decimal_fee := step(bank(), action(100.0, 0.1), ctx(true, 0.0, 0.0, 99.0))
	if decimal_fee.ok:
		check(decimal_fee.credit_result.new_cash_for_interest == 1.98 and decimal_fee.credit_result.new_cash_for_withdrawals == 0.1 and decimal_fee.state.cash == 0.0, "The 2.08 gross advance keeps 1.98 interest and 0.1 withdrawal purposes without a spurious asset")
		check(absf(decimal_fee.credit_result.cash_purpose_reconciliation) <= 1e-12 * decimal_fee.new_cash, "Fractional cash reconciliation is disclosed at this advance's scale")
	if full.ok:
		check(full.new_cash == 2 and full.credit_result.new_cash_for_interest == 1 and full.credit_result.new_cash_for_withdrawals == 1, "Actual fresh loan pays due interest then withdrawals")
		check(full.credit_result.paid_positive == 1 and full.credit_state.payable == 0 and full.withdrawals_paid == 1 and full.state.central_bank_loan == 4, "Interest claim declines only after actual cash remittance")
		check(full.credit_result.bank_equity_after - full.credit_result.bank_equity_before == -1, "Borrowing/remittance does not repair combined bank equity")
		check(full.prequote_reference_need == 4, "Fixed reference contains old principal, all due interest and deposit requests")
	var zero := step(bank(), action(0), ctx())
	if zero.ok:
		check(zero.credit_state.payable == 1 and zero.remaining_queue == 1 and zero.loan_arrears == 2 and zero.payment_distress, "Zero offer retains three separate unpaid classes")
		check(zero.credit_result.funding_need_before_advances == 2 and zero.credit_result.uncovered_interest == 1, "Interest need does not disappear when it cannot be paid")
	var interest_only := bank()
	interest_only.deposits = 0.0
	var interest_short := step(interest_only, action(2.0, 0.0), ctx())
	if interest_short.ok:
		check(interest_short.credit_state.payable == 1.0 and interest_short.loan_arrears == 0.0 and interest_short.remaining_queue == 0.0 and interest_short.payment_distress and interest_short.workout, "Due interest alone marks payment distress without adding principal/depositor arrears or inferring impairment")
	var partial := step(bank(), action(3.25), ctx())
	if partial.ok:
		check(partial.credit_result.new_cash_for_interest == 1 and partial.credit_result.new_cash_for_withdrawals == 0.25 and partial.remaining_queue == 0.75, "Limited fresh support pays interest first without double counting queue")
	var scarce := bank()
	scarce.claims[0].face = 2.5
	scarce.initial_face = 2.5
	var limited := step(scarce, action(), ctx())
	if limited.ok:
		check(limited.new_cash == 0.5 and limited.credit_state.payable == 0.5 and limited.withdrawals_paid == 0 and limited.remaining_queue == 1, "Old exposure occupies collateral headroom before partial interest funding")
	var cash_rich := bank()
	cash_rich.cash = 4.0
	var cash_paid := step(cash_rich, action(0), ctx())
	if cash_paid.ok:
		check(cash_paid.repayment == 2 and cash_paid.credit_result.paid_positive == 1 and cash_paid.new_cash == 0 and cash_paid.withdrawals_paid == 1, "Existing cash suffices: no loan is invented")
	var signs := step(bank(), action(0, 0), ctx(true, 1, 1, 0))
	if signs.ok:
		check(signs.credit_result.paid_positive == 1 and signs.credit_result.paid_negative == 1 and signs.new_cash == 0 and signs.credit_state == {"payable": 0.0, "receivable": 0.0}, "Reverse cash payout pays the positive claim through two real cash legs, not setoff")
	var negative := step(bank(), action(0), ctx(true, 1, 0, -50))
	if negative.ok:
		check(negative.credit_result.accrued_negative == 1 and negative.credit_result.paid_negative == 1 and negative.credit_result.paid_positive == 1 and negative.new_cash == 0, "Current negative accrual can actually fund an older due positive claim")
	var a_context := ctx(false)
	a_context.erase("finance_interest")
	check(var_to_bytes(Economy.bank_workout_step(bank(), action(), a_context)) == var_to_bytes(Economy.bank_workout_step(bank(), action(), ctx(false))), "Absent and explicit-false financing preserve A entire result")
	var zero_a := a_context.duplicate(true)
	zero_a.annual_rate_pct = 0.0
	check(var_to_bytes(Economy.bank_workout_step(bank(), action(), zero_a)) == var_to_bytes(without_b(Economy.bank_workout_step(bank(), action(), ctx(true, 0, 0, 0)))), "Zero APR/claims true preserves all legacy A fields exactly")
	var extreme := step(bank(), action(1e308), ctx())
	if extreme.ok and full.ok:
		check(extreme.new_cash == full.new_cash and extreme.credit_state == full.credit_state, "Arbitrary finite offer is not an arbitrary borrowing cap or booked loan")
	var no_pledge := action()
	no_pledge.pledgeable_share = 0.0
	var unsupported := step(bank(), no_pledge, ctx())
	if unsupported.ok:
		check(unsupported.new_cash == 0 and unsupported.credit_state.payable == 1, "No collateral cannot fund or forgive the interest claim")
	for value in [1, 0.0, "true", null]:
		var invalid := ctx()
		invalid.finance_interest = value
		refusal(Economy.bank_workout_step(bank(), action(), invalid), "Financing switch must be Boolean")
	var unknown := ctx()
	unknown.extra = true
	refusal(Economy.bank_workout_step(bank(), action(), unknown), "Unknown context key still refuses")
	refusal(Economy.bank_workout_step(bank(), action(100, 0), ctx(true, 1e-300, 0, 0)), "Tiny positive advance cannot disappear inside old principal")
	_native()
	if failures == 0:
		print("PASS: priced-interest financing ", checks, " checks; optional B experiment")
	else:
		printerr("FAIL: priced-interest financing ", failures, " of ", checks)
	quit(0 if failures == 0 else 1)

func _native() -> void:
	var career := Career.new()
	career.params.initial_reserves_pct_initial_gdp = 20.0
	var started: Dictionary = career.start("stagflation_bank_run", 417)
	check(started.ok, "Constructor-valid native career for coupled B fixture")
	if not started.ok:
		return
	var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold")
	policy.liquidity_request_pct_initial_gdp = 2.0
	var originated: Dictionary = career.advance(policy)
	check(originated.ok and career.state.outstanding_liquidity_pct_initial_gdp == 2, "Native ledger genuinely originates old principal")
	if not originated.ok:
		return
	var b := bank(career.state.quarter_index)
	var order := {"new_withdrawals": 1.0, "haircut_pct": 0.0, "pledgeable_share": 1.0}
	for offer in [0.0, 3.25, 100.0]:
		policy = career.model.benchmark_policy(career.state, career.params, "hold")
		policy.maintain_ample_reserves = false
		policy.liquidity_request_pct_initial_gdp = offer
		var c := ctx()
		var frozen := var_to_bytes([career.state, policy, career.params, b, order, c])
		var result: Dictionary = career.model.bank_workout_transition(career.state, policy, {}, career.params, b, order, c)
		check(result.ok, "Actual macro/private B transition settles")
		if not result.ok:
			printerr(result.get("error", "unknown"))
			continue
		check(var_to_bytes([career.state, policy, career.params, b, order, c]) == frozen, "Coupled B inputs are immutable")
		check(var_to_bytes(result) == var_to_bytes(career.model.bank_workout_transition(career.state, policy, {}, career.params, b, order, c)), "Coupled B full frame replays exactly")
		var d: Dictionary = result.credit_result
		check(result.state.funding_need_pct_initial_gdp == 2 and result.state.eligible_local_need_pct_initial_gdp == 4, "Current macro need and eligible local need include due interest")
		check(result.state.uncovered_new_funding_pct_initial_gdp == result.bank_state.withdrawal_queue + result.credit_state.payable, "Macro unmet new need counts unpaid interest plus deposit queue once")
		check(result.state.uncovered_funding_pct_initial_gdp == result.bank_state.loan_arrears + result.bank_state.withdrawal_queue + result.credit_state.payable, "Total pressure retains principal arrears and both different new claims")
		check(result.state.outstanding_liquidity_pct_initial_gdp == result.bank_state.central_bank_loan and result.state.quarter_index == result.bank_state.quarter_index, "Native/private debt and clocks stay synchronized")
		check(absf((d.fed_capital_after - d.fed_capital_before) - d.fed_interest_income) <= 1e-11, "Combined Fed capital change recognizes accrual exactly once")
		check(absf(result.state.capital_other_pct_initial_gdp - career.state.capital_other_pct_initial_gdp - d.paid_positive + d.paid_negative) <= 1e-11, "Borrowed interest remittance has a real opposite Fed capital/reserve entry")
