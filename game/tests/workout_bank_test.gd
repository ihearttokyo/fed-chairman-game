extends SceneTree
const Economy = preload("res://model/economy.gd")
var checks := 0
var failures := 0
var calls := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures <= 10:
			print("FAIL: ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(abs(actual - expected) <= 1e-10 * maxf(1.0, abs(expected)), label)

func bank(changes: Dictionary = {}) -> Dictionary:
	var state := {"quarter_index": 0, "cash": 0.0, "deposits": 3.0,
		"withdrawal_queue": 0.0, "central_bank_loan": 2.0, "loan_arrears": 0.0,
		"annual_yield_pct": 0.0, "claims": [{"maturity_quarter": 4, "face": 10.0}],
		"initial_face": 10.0, "matured_face": 0.0}
	state.merge(changes, true)
	return state

func order(changes: Dictionary = {}) -> Dictionary:
	var action := {"annual_yield_pct": 0.0, "new_withdrawals": 1.0,
		"liquidity_offer": 100.0, "haircut_pct": 4.0, "pledgeable_share": 1.0}
	action.merge(changes, true)
	return action

func step(state: Dictionary, action: Dictionary) -> Dictionary:
	calls += 1
	return Economy.bank_workout_step(state, action)

func _initialize() -> void:
	_test_renewal_and_headroom()
	_test_queue_and_maturity_recovery()
	_test_cash_waterfall_and_equity()
	_test_pricing()
	_test_numeric_erasure()
	_test_validation()
	print("BW617_CHECKS ", checks, " FAILURES ", failures, " PUBLIC_STEP_CALLS ", calls)
	if failures == 0:
		print("PASS: optional zero-interest workout accounting, persistent claims, dated maturity and replay; not shipping qualification")
	quit(1 if failures else 0)

func _test_renewal_and_headroom() -> void:
	var prior := bank()
	var action := order()
	var frozen := var_to_bytes([prior, action])
	var result := step(prior, action)
	check(result.ok, "Renewal plus a fresh withdrawal settles")
	if not result.ok:
		return
	check(result.repayment == 0.0 and result.renewal == 2.0 and result.new_cash == 1.0, "Renewals move no cash; only the new withdrawal creates a cash advance")
	check(result.state.central_bank_loan == 3.0 and result.net_cb_flow == 1.0, "Total exposure includes renewed debt once; net CB flow is new cash minus repayment")
	check(result.state.deposits == 2.0 and result.state.withdrawal_queue == 0.0 and result.state.cash == 0.0, "Withdrawals reduce deposits only when actually paid")
	check(result.prequote_reference_need == 3.0, "Reference need is frozen without collateral in its denominator")
	near(result.equity_before, 5.0, "Opening equity subtracts debt and deposits, not subset flags twice")
	near(result.equity_change, 0.0, "Loan origination and withdrawals cannot create equity")
	check(not result.payment_distress and not result.workout and result.solvent, "Liquid solvent case has no workout flag")
	check(var_to_bytes([prior, action]) == frozen, "Successful settlement is caller-pure")
	var renewal := step(prior, order({"new_withdrawals": 0.0, "liquidity_offer": 2.0}))
	check(renewal.ok and renewal.renewal == 2.0 and renewal.new_cash == 0.0 and renewal.net_cb_flow == 0.0, "Pure renewal neither retires debt nor manufactures reserve cash")
	for old_debt in [4.0, 6.0]:
		var constrained := step(bank({"central_bank_loan": old_debt, "deposits": 4.0}), order({"new_withdrawals": 4.0, "liquidity_offer": 5.0, "haircut_pct": 50.0}))
		check(constrained.ok, "Existing debt above collateral remains a valid distress transition")
		if not constrained.ok:
			continue
		var fresh := 1.0 if old_debt == 4.0 else 0.0
		check(constrained.new_cash == fresh and constrained.state.central_bank_loan == old_debt + fresh, "All old exposure, not just renewed exposure, consumes fresh headroom")
		check(constrained.state.withdrawal_queue == 4.0 - fresh, "Unpaid withdrawal claims remain in the queue")
		check(constrained.loan_arrears == maxf(0.0, old_debt - 5.0), "Unrenewed principal remains recorded as arrears")

func _test_queue_and_maturity_recovery() -> void:
	var state := bank()
	var replay := state.duplicate(true)
	var starting := state
	var frozen := var_to_bytes(starting)
	for quarter in range(1, 6):
		var action := order({"liquidity_offer": 0.0, "new_withdrawals": 1.0 if quarter == 1 else 0.0})
		var action_bytes := var_to_bytes(action)
		var result := step(state, action)
		var repeated := step(replay, action)
		check(result.ok and repeated.ok, "Distress does not freeze the represented career clock")
		if not result.ok or not repeated.ok:
			return
		check(var_to_bytes(result) == var_to_bytes(repeated), "Independent whole-workout replay is byte-exact")
		check(result.state.quarter_index == quarter and var_to_bytes(action) == action_bytes, "Advance once without mutating the order")
		near(result.equity_after, 5.0, "Constant-quote payment/reinvestment-free path conserves equity")
		near(result.equity_change, result.expected_equity_change, "Equity bridge reconciles each transition")
		if quarter < 4:
			check(result.state.central_bank_loan == 2.0 and result.loan_arrears == 2.0, "Zero offer retains all unpaid CB principal")
			check(result.state.withdrawal_queue == 1.0 and result.state.deposits == 3.0, "A queued request is not resubmitted or deducted twice")
			check(result.payment_distress and result.workout and result.solvent, "Payment distress is distinct from negative equity")
		elif quarter == 4:
			check(result.matured_principal == 10.0 and result.capacity == 0.0, "Maturing cash cannot remain pledged as securities")
			check(result.repayment == 2.0 and result.withdrawals_paid == 1.0 and result.state.cash == 7.0, "Authored cash waterfall pays CB principal before the queued withdrawal")
			check(result.state.central_bank_loan == 0.0 and result.state.withdrawal_queue == 0.0 and not result.workout, "Actual maturity cash cures distress without a bailout")
		else:
			check(result.matured_principal == 0.0 and result.state.cash == 7.0, "An empty book cannot duplicate a receipt")
		state = result.state
		replay = repeated.state
	check(state.claims.is_empty() and state.matured_face == 10.0 and state.initial_face == 10.0, "Dated principal is conserved without replenishment")
	check(var_to_bytes(starting) == frozen, "Whole-path replay preserves the original starting bank")
	for restriction in [{"liquidity_offer": 0.0}, {"haircut_pct": 100.0}, {"pledgeable_share": 0.0}]:
		var action := order()
		action.merge(restriction, true)
		var result := step(bank(), action)
		check(result.ok and result.state.central_bank_loan == 2.0 and result.state.withdrawal_queue == 1.0, "No offer or collateral preserves claims instead of rejecting ordinary distress")

func _test_cash_waterfall_and_equity() -> void:
	var rich := step(bank({"cash": 5.0}), order())
	check(rich.ok, "Cash-rich bank uses its own cash first")
	if rich.ok:
		check(rich.repayment == 2.0 and rich.renewal == 0.0 and rich.new_cash == 0.0 and rich.state.cash == 2.0, "Large desired offer cannot create unnecessary cash parking")
		check(rich.net_cb_flow == -2.0, "Actual CB repayment is a negative reserve/loan-asset flow")
	var distressed := step(bank({"cash": 5.0, "deposits": 20.0, "central_bank_loan": 0.0,
		"claims": [{"maturity_quarter": 4, "face": 1.0}], "initial_face": 1.0}), order({"new_withdrawals": 2.0}))
	check(distressed.ok and not distressed.solvent and not distressed.payment_distress and distressed.workout, "Negative equity is not confused with payment feasibility")
	if distressed.ok:
		check(distressed.equity_after == -14.0, "Negative equity is neither clipped nor repaired by borrowing")
	var queued := bank({"withdrawal_queue": 1.0, "loan_arrears": 1.0})
	var repaired := step(queued, order({"new_withdrawals": 0.0}))
	check(repaired.ok and repaired.withdrawals_paid == 1.0 and repaired.renewal == 2.0 and repaired.loan_arrears == 0.0, "Restored renewal permission cures arrears without retiring the old exposure")
	if repaired.ok:
		near(repaired.equity_before, 5.0, "Queue and arrears are subsets of deposits and CB debt, not extra liabilities")

func _test_pricing() -> void:
	var prior := bank()
	var frozen := var_to_bytes(prior)
	var zero: Dictionary = Economy.bank_workout_value(prior, 0.0)
	var raised: Dictionary = Economy.bank_workout_value(prior, 10.0)
	var negative: Dictionary = Economy.bank_workout_value(prior, -1.0)
	check(zero.ok and zero.market_value == 10.0, "Zero-yield face value is exact")
	near(raised.market_value, 10.0 / pow(1.05, 2.0), "Annual nominal yield uses semiannual discount periods")
	check(negative.ok and negative.market_value > 10.0, "Negative yields permit above-face value")
	check(var_to_bytes(Economy.bank_workout_value(prior, 0.0)) == var_to_bytes(zero) and var_to_bytes(prior) == frozen, "Same-date price roundtrip cannot create cash or new face")
	var distant := bank({"claims": [{"maturity_quarter": 9007199254740992, "face": 1.0}], "initial_face": 1.0})
	var tiny: Dictionary = Economy.bank_workout_value(distant, 1e-14)
	check(tiny.ok, "Tiny quote over a long representable horizon is retained")
	if tiny.ok:
		near(tiny.market_value, 0.7983725136500446, "Stable log1p pricing does not silently use zero yield")
	var short := bank({"claims": [{"maturity_quarter": 1, "face": 1.0}], "initial_face": 1.0})
	var boundary: Dictionary = Economy.bank_workout_value(short, -199.99999999999997)
	check(boundary.ok, "Near-negative-domain price remains representable")
	if boundary.ok:
		near(boundary.market_value, 83886080.0, "Near-minus200 base preserves significant digits")
	check(not Economy.bank_workout_value(distant, 1.0).ok, "Positive-claim PV underflow fails closed")
	var unchanged := step(prior, order({"new_withdrawals": 0.0}))
	var repriced := step(prior, order({"new_withdrawals": 0.0, "annual_yield_pct": -1.0}))
	check(unchanged.ok and repriced.ok and unchanged.prequote_reference_need == repriced.prequote_reference_need, "Collateral repricing cannot shrink its own predecision reference")

func _test_numeric_erasure() -> void:
	var large := bank({"cash": 9007199254740992, "deposits": 1.0, "central_bank_loan": 9007199254740992,
		"claims": [], "initial_face": 0.0})
	var result := step(large, order({"liquidity_offer": 0.0}))
	check(result.ok, "Representable distress after large principal cancellation advances")
	if result.ok:
		check(result.state.withdrawal_queue == 1.0 and result.state.deposits == 1.0 and result.state.central_bank_loan == 0.0, "Offset principal cannot erase a one-unit unpaid deposit claim")
		check(result.equity_before == -1.0 and result.equity_after == -1.0, "Original equity legs retain the one-unit liability")
	for prior in [bank({"cash": 1e20, "deposits": 1.0, "central_bank_loan": 0.0, "claims": [], "initial_face": 0.0}),
		bank({"cash": 1.0, "deposits": 1e20, "central_bank_loan": 0.0, "claims": [{"maturity_quarter": 4, "face": 1e20}], "initial_face": 1e20})]:
		var action := order({"liquidity_offer": 0.0})
		var frozen := var_to_bytes([prior, action])
		var refused := step(prior, action)
		check(not refused.ok and not refused.has("state"), "Unrepresentable cash or deposit reduction cannot silently erase a payment")
		check(var_to_bytes([prior, action]) == frozen, "Representation refusal is caller-pure")
	var huge_noop := bank({"cash": 1e20, "deposits": 1e20, "central_bank_loan": 0.0, "claims": [], "initial_face": 0.0})
	check(step(huge_noop, order({"new_withdrawals": 0.0})).ok, "Finite floats have no arbitrary integer-range quantity cap")
	var compound := bank({"deposits": 1.0, "central_bank_loan": 1e20,
		"claims": [{"maturity_quarter": 4, "face": 1e20}], "initial_face": 1e20})
	var continued := step(compound, order({"liquidity_offer": 0.0}))
	check(continued.ok, "Representable distress continues even if a compound evaluation scalar cannot fit")
	if continued.ok:
		check(not continued.prequote_reference_representable and not continued.has("prequote_reference_need"), "Unrepresentable scalar reference is flagged, not rounded into a false denominator")
		check(continued.state.withdrawal_queue == 1.0 and continued.equity_after == -1.0, "Original claim legs preserve the small liability beside large debt")
	var late: int = 9007199254740993
	var clock := bank({"quarter_index": late, "claims": [{"maturity_quarter": late + 1, "face": 10.0}]})
	var advanced := step(clock, order())
	check(advanced.ok and advanced.state.quarter_index == late + 1 and advanced.matured_principal == 10.0, "Integer clocks remain exact beyond the monetary coercion range")

func _test_validation() -> void:
	for field_and_value in [["cash", -1.0], ["deposits", NAN], ["central_bank_loan", INF],
		["withdrawal_queue", 4.0], ["loan_arrears", 3.0], ["annual_yield_pct", -200.0],
		["quarter_index", true], ["initial_face", 11.0], ["cash", 9007199254740993]]:
		var prior := bank()
		prior[field_and_value[0]] = field_and_value[1]
		var frozen := var_to_bytes(prior)
		check(not step(prior, order()).ok and var_to_bytes(prior) == frozen, "Invalid bank data rejects without mutation")
	for field_and_value in [["annual_yield_pct", -200.0], ["new_withdrawals", 4.0], ["new_withdrawals", true],
		["liquidity_offer", -1.0], ["liquidity_offer", INF], ["haircut_pct", 101.0], ["pledgeable_share", -0.1]]:
		var action := order()
		action[field_and_value[0]] = field_and_value[1]
		var frozen := var_to_bytes(action)
		check(not step(bank(), action).ok and var_to_bytes(action) == frozen, "Invalid order rejects without mutation")
	check(not step(bank({"withdrawal_queue": 2.0}), order({"new_withdrawals": 2.0})).ok, "Queued deposits cannot be requested again as new withdrawals")
	var unknown := bank(); unknown.bailout = 1.0
	check(not step(unknown, order()).ok, "Unknown state injection fails closed")
	var missing := order(); missing.erase("haircut_pct")
	check(not step(bank(), missing).ok, "Missing order input fails closed")
	var interest := order(); interest.new_loan_rate_pct = 0.0
	check(not step(bank(), interest).ok, "An undeclared interest contract is not silently accepted")
	for claim in [{"maturity_quarter": 0, "face": 10.0}, {"maturity_quarter": true, "face": 10.0},
		{"maturity_quarter": 4, "face": -10.0}, {"maturity_quarter": 4, "face": 10.0, "coupon": 1.0}]:
		check(not step(bank({"claims": [claim]}), order()).ok, "Dated zero-coupon schema is exact")
	for quote in [true, "4", NAN, INF, -200.0]:
		check(not Economy.bank_workout_value(bank(), quote).ok, "Malformed valuation quote is rejected")
