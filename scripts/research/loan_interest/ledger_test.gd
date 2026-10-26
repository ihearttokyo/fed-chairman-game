extends SceneTree
const Ledger = preload("ledger.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures <= 15:
			print("FAIL: ", message)

func opening(cash: float = 10.0) -> Dictionary:
	var result: Dictionary = Ledger.opening(cash, 200.0, 50.0, 100.0, 100.0 - cash)
	check(result.ok, "Explicit authored opening balance sheet validates")
	return result.state if result.ok else {}

func bank_equity(state: Dictionary) -> float:
	# Independent normal-sized fixture arithmetic, not the implementation helper.
	return state.bank.cash + state.bank.securities + state.bank.interest_receivable - state.bank.deposits - state.bank.cb_principal - state.bank.interest_payable

func fed_capital(state: Dictionary) -> float:
	return state.fed.principal_asset + state.fed.interest_receivable - state.fed.reserve_liabilities - state.fed.interest_payable

func assert_transition(before: Dictionary, result: Dictionary, income: float, cash_flow: float) -> void:
	check(result.ok, "Performing-credit transition is supported")
	if not result.ok:
		return
	var after: Dictionary = result.state
	check(bank_equity(after) - bank_equity(before) == -income, "Independent delta bank equity equals income minus expense")
	check(fed_capital(after) - fed_capital(before) == income, "Independent delta Fed capital equals recognized income/expense")
	check(after.fed.capital - before.fed.capital == income, "Recorded capital change independently matches income")
	check(result.bank_interest_income == -income and result.fed_interest_income == income, "Explicit opposite income entries")
	check(after.bank.cash - before.bank.cash == cash_flow and after.fed.reserve_liabilities - before.fed.reserve_liabilities == cash_flow, "Cash settlement has a one-for-one reserve-liability counterpart")
	check(result.cash_to_bank == cash_flow and result.principal_change == 0.0, "Cash and principal flows are not conflated with accrued income")
	check(after.bank.cb_principal == before.bank.cb_principal and after.fed.principal_asset == before.fed.principal_asset, "Both original principal accounts remain unchanged")
	check(after.bank.securities == before.bank.securities and after.bank.deposits == before.bank.deposits, "Passive securities/deposits unchanged")
	check(after.bank.interest_payable == after.fed.interest_receivable and after.bank.interest_receivable == after.fed.interest_payable, "Separate positive and negative claims have exact counterparties")
	check(after.bank.cash == after.fed.reserve_liabilities and after.fed.capital == fed_capital(after), "Independent closing balance sheet identities")
	check(Ledger.inspect(after).ok, "Output is admissible as the next input")

func refusal(result: Dictionary, message: String) -> void:
	check(not result.ok and not result.has("state") and result.has("error"), message)

func _initialize() -> void:
	var initial := opening()
	if initial.is_empty():
		finish()
		return
	var frozen := var_to_bytes(initial)
	var zero: Dictionary = Ledger.accrue(initial, 0.0, 365)
	assert_transition(initial, zero, 0.0, 0.0)
	check(var_to_bytes(zero.state) == frozen, "Zero APR leaves all opening accounts byte-identical")
	var no_days: Dictionary = Ledger.accrue(initial, 5.0, 0)
	assert_transition(initial, no_days, 0.0, 0.0)
	check(var_to_bytes(no_days.state) == frozen, "Zero actual days have no manufactured interest")
	var positive: Dictionary = Ledger.accrue(initial, 5.0, 365)
	assert_transition(initial, positive, 5.0, 0.0)
	var positive_bytes := var_to_bytes(positive.state)
	check(positive.state.bank.interest_payable == 5.0 and positive.state.fed.interest_receivable == 5.0, "Positive APR accrues expense/receivable without cash settlement")
	check(var_to_bytes(positive) == var_to_bytes(Ledger.accrue(initial, 5.0, 365)), "Accrual replays exactly from unchanged input")
	var paid: Dictionary = Ledger.settle_positive(positive.state, 5.0)
	assert_transition(positive.state, paid, 0.0, -5.0)
	check(paid.state.bank.interest_payable == 0 and paid.state.bank.cash == 5, "Full payment extinguishes only the paid positive claim")
	var partial_open := opening(2.0)
	var partial: Dictionary = Ledger.accrue(partial_open, 5.0, 365)
	var partial_bytes := var_to_bytes(partial.state)
	var partial_paid: Dictionary = Ledger.settle_positive(partial.state, 2.0)
	assert_transition(partial.state, partial_paid, 0.0, -2.0)
	check(partial_paid.state.bank.cash == 0 and partial_paid.state.bank.interest_payable == 3 and partial_paid.state.fed.interest_receivable == 3, "Partial cash payment retains the full unpaid carry")
	refusal(Ledger.settle_positive(partial_paid.state, 1.0), "Insufficient cash refuses rather than capitalizes or forgives unpaid interest")
	check(var_to_bytes(partial.state) == partial_bytes, "Settlement preserves its caller state")
	refusal(Ledger.accrue(initial, -2.0, 365), "Counterfactual negative APR is not silently enabled")
	var negative: Dictionary = Ledger.accrue(initial, -2.0, 365, true)
	assert_transition(initial, negative, -2.0, 0.0)
	check(negative.state.bank.interest_receivable == 2 and negative.state.fed.interest_payable == 2, "Negative APR creates a separate reverse claim")
	var negative_paid: Dictionary = Ledger.settle_negative(negative.state, 1.0)
	assert_transition(negative.state, negative_paid, 0.0, 1.0)
	check(negative_paid.state.bank.interest_receivable == 1 and negative_paid.state.fed.interest_payable == 1, "Partial reverse payment carries its separate unpaid balance")
	var switched: Dictionary = Ledger.accrue(positive.state, -2.0, 365, true)
	assert_transition(positive.state, switched, -2.0, 0.0)
	check(switched.state.bank.interest_payable == 5 and switched.state.bank.interest_receivable == 2, "Rate sign switch neither nets nor forgives the existing positive claim")
	var switched_paid: Dictionary = Ledger.settle_negative(switched.state, 2.0)
	assert_transition(switched.state, switched_paid, 0.0, 2.0)
	check(switched_paid.state.bank.interest_payable == 5, "Paying the reverse claim does not extinguish the other direction")
	check(var_to_bytes(positive.state) == positive_bytes, "Payment and sign-switch accrual preserve their supplied claim state")
	var daily: Dictionary = Ledger.accrue(initial, 365.0, 1)
	assert_transition(initial, daily, 1.0, 0.0)
	check(daily.state.bank.interest_payable == 1.0, "Actual one-day/365 convention, not APR/4")
	var floated: Dictionary = Ledger.accrue(daily.state, 730.0, 1)
	assert_transition(daily.state, floated, 2.0, 0.0)
	check(floated.state.bank.interest_payable == 3, "Successive externally timed rate segments use unchanged principal, not compound claims")
	for invalid in [NAN, INF, -INF, true, "5", null, [], {}, 9007199254740993]:
		refusal(Ledger.accrue(initial, invalid, 1), "Invalid APR refuses atomically")
		refusal(Ledger.settle_positive(positive.state, invalid), "Invalid settlement amount refuses atomically")
		refusal(Ledger.opening(invalid, 200, 50, 100, 90), "Invalid opening amount refuses before coercion")
	for invalid_days in [-1, 0.5, true, "1", NAN, 9007199254740993]:
		refusal(Ledger.accrue(initial, 5, invalid_days), "Invalid day count refuses")
	refusal(Ledger.accrue(initial, -2, 1, 1), "Negative-rate opt-in must be Boolean")
	refusal(Ledger.settle_positive(positive.state, -1), "Negative cash-settlement request refuses")
	refusal(Ledger.settle_positive(positive.state, 6), "Cannot pay more than the separate positive claim")
	refusal(Ledger.settle_negative(initial, 1), "Cannot pay a reverse claim that does not exist")
	refusal(Ledger.opening(10, 200, 50, 100, 0), "Inconsistent explicit opening capital refuses; not manufactured earnings")
	refusal(Ledger.opening(10, 200, 50, 100, 90, false), "Impaired opening is outside the supported accounting boundary")
	var impaired: Dictionary = initial.duplicate(true)
	impaired.performing = false
	var impaired_bytes := var_to_bytes(impaired)
	refusal(Ledger.accrue(impaired, 5, 365), "Impaired/noncollectible loan refuses instead of booking income")
	refusal(Ledger.settle_positive(impaired, 0), "Unsupported impaired recovery accounting also refuses")
	check(var_to_bytes(impaired) == impaired_bytes, "Impairment refusal is atomic")
	for mutated in ["unpaired", "extra", "capital", "boolean"]:
		var broken: Dictionary = initial.duplicate(true)
		if mutated == "unpaired": broken.fed.principal_asset = 101.0
		elif mutated == "extra": broken.bank.extra = 0
		elif mutated == "capital": broken.fed.capital += 1
		else: broken.bank.deposits = true
		refusal(Ledger.accrue(broken, 5, 1), "Malformed or unpaired state refuses")
	var huge: Dictionary = Ledger.opening(0, 0, 0, 1e20, 1e20)
	check(huge.ok, "No arbitrary finite principal cap")
	refusal(Ledger.accrue(huge.state, 1e-18, 365), "Interest cannot disappear inside huge derived capital/equity")
	var rich: Dictionary = Ledger.opening(1e20, 0, 0, 1e20, 0)
	var rich_accrual: Dictionary = Ledger.accrue(rich.state, 1e-18, 365)
	check(rich.ok and rich_accrual.ok, "Balanced huge cash/principal can retain a separate one-unit claim")
	refusal(Ledger.settle_positive(rich_accrual.state, 1.0), "Positive cash payment cannot vanish from a huge reserve balance")
	var large_claim: Dictionary = Ledger.accrue(huge.state, 100.0, 365)
	check(large_claim.ok, "Large representable claim is not capped")
	refusal(Ledger.accrue(large_claim.state, 1e-18, 365), "Additional positive interest cannot vanish inside an existing huge claim")
	var tiny := 1e-300
	tiny *= 1e-20 # Literal subnormals can be parsed as zero; construct at runtime.
	check(tiny > 0, "Underflow regression begins with actual positive principal")
	var tiny_open: Dictionary = Ledger.opening(0, 0, 0, tiny, tiny)
	check(tiny_open.ok, "Positive subnormal opening is represented")
	refusal(Ledger.accrue(tiny_open.state, 1e-10, 1), "Positive contracted accrual underflow cannot silently become zero")
	refusal(Ledger.accrue(initial, 1e308, 9007199254740992), "Overflowed accrual refuses without partial state")
	check(var_to_bytes(initial) == frozen, "All successful and rejected operations preserve the caller opening")
	var detached: Dictionary = Ledger.accrue(initial, 5, 365)
	detached.state.bank.cash = 999
	check(var_to_bytes(initial) == frozen, "Returned nested dictionaries are detached from caller state")
	finish()

func finish() -> void:
	print("Loan-interest research: ", checks, " checks, ", failures, " failures; performing-credit accounting only")
	quit(0 if failures == 0 else 1)
