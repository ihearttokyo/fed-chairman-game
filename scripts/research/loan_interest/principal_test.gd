extends SceneTree
const Ledger = preload("ledger.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: ", message)

func _initialize() -> void:
	var opened: Dictionary = Ledger.opening(100.0, 200.0, 50.0, 100.0, 0.0)
	check(opened.ok, "Opening independent balance sheet")
	var initial: Dictionary = opened.state
	var frozen := var_to_bytes(initial)
	var accrued: Dictionary = Ledger.accrue(initial, 365.0, 1)
	check(accrued.ok and accrued.state.bank.interest_payable == 1, "Opening principal accrues first day's interest")
	var before: Dictionary = accrued.state
	var repaid: Dictionary = Ledger.repay_principal(before, 40.0)
	check(repaid.ok, "Representable partial repayment accepted")
	if repaid.ok:
		check(repaid.state.bank.cash == 60 and repaid.state.fed.reserve_liabilities == 60, "Cash repayment retires reserves on both sides")
		check(repaid.state.bank.cb_principal == 60 and repaid.state.fed.principal_asset == 60, "Principal retired on both sides")
		check(repaid.state.bank.interest_payable == 1 and repaid.state.fed.interest_receivable == 1, "Principal repayment cannot forgive accrued interest")
		check(repaid.bank_interest_income == 0 and repaid.fed_interest_income == 0, "Principal retirement is not interest income")
		check(repaid.principal_change == -40 and repaid.cash_to_bank == -40, "Principal and reserve flows disclosed separately")
		check(repaid.bank_equity == accrued.bank_equity and repaid.fed_capital == accrued.fed_capital, "Repayment cannot recapitalize either counterparty")
		var next_day: Dictionary = Ledger.accrue(repaid.state, 365.0, 1)
		check(next_day.ok and is_equal_approx(next_day.state.bank.interest_payable, 1.6), "Later accrual uses remaining principal; earlier accrual unchanged")
		var full: Dictionary = Ledger.repay_principal(repaid.state, 60.0)
		check(full.ok and full.state.bank.cb_principal == 0 and full.state.bank.cash == 0, "Full retirement closes only principal/reserve balances")
		if full.ok:
			var after: Dictionary = Ledger.accrue(full.state, 365.0, 365)
			check(after.ok and after.state.bank.interest_payable == 1, "No interest on retired principal or unpaid interest")
		check(var_to_bytes(repaid) == var_to_bytes(Ledger.repay_principal(before, 40.0)), "Repayment replays exactly")
	for invalid in [-1, 101, true, NAN, INF, "40", null, 9007199254740993]:
		var result: Dictionary = Ledger.repay_principal(initial, invalid)
		check(not result.ok and not result.has("state"), "Invalid or excessive repayment refuses atomically")
	var cash_poor: Dictionary = Ledger.opening(2.0, 200.0, 50.0, 100.0, 98.0)
	check(not Ledger.repay_principal(cash_poor.state, 3.0).ok, "Cannot manufacture repayment cash")
	var cash_rich: Dictionary = Ledger.opening(200.0, 200.0, 50.0, 100.0, -100.0)
	check(not Ledger.repay_principal(cash_rich.state, 101.0).ok, "Cash availability cannot authorize over-repayment of principal")
	var reverse: Dictionary = Ledger.accrue(initial, -365.0, 1, true)
	var reverse_paid: Dictionary = Ledger.repay_principal(reverse.state, 40.0)
	check(reverse_paid.ok and reverse_paid.state.bank.interest_receivable == 1 and reverse_paid.state.fed.interest_payable == 1, "Principal retirement also preserves separate counterfactual negative-interest claim")
	var reverse_next: Dictionary = Ledger.accrue(reverse_paid.state, -365.0, 1, true)
	check(reverse_next.ok and is_equal_approx(reverse_next.state.bank.interest_receivable, 1.6), "Negative accrual also follows remaining principal without rewriting earned claims")
	var huge: Dictionary = Ledger.opening(1e20, 0.0, 0.0, 1e20, 0.0)
	check(not Ledger.repay_principal(huge.state, 1.0).ok, "Tiny principal/cash reduction cannot disappear in huge balances")
	var zero: Dictionary = Ledger.repay_principal(initial, 0.0)
	check(zero.ok and var_to_bytes(zero.state) == frozen, "Zero principal repayment is a byte-identical no-op")
	var fractional: Dictionary = Ledger.opening(2.08, 5.0, 1.0, 1.98, 1.98 - 2.08)
	check(fractional.ok, "Unequal fractional opening balances validate")
	var fraction_paid: Dictionary = Ledger.repay_principal(fractional.state, 0.1)
	check(fraction_paid.ok, "Unequal fractional principal/cash repayment accepted")
	if fraction_paid.ok:
		check(absf(fraction_paid.state.bank.cash - 1.98) <= 1e-13 and absf(fraction_paid.state.bank.cb_principal - 1.88) <= 1e-13, "Both fractional retirement legs have transaction-sized bounds")
		check(absf(fraction_paid.bank_equity_roundoff) <= 1e-13 and absf(fraction_paid.fed_capital_roundoff) <= 1e-13, "Roundoff disclosures use repayment size, not book size")
	var unsupported: Dictionary = initial.duplicate(true)
	unsupported.performing = false
	check(not Ledger.repay_principal(unsupported, 1.0).ok, "Impaired recovery remains outside prototype boundary")
	check(var_to_bytes(initial) == frozen and before.bank.cash == 100, "Caller inputs remain unchanged")
	if repaid.ok:
		repaid.state.bank.cash = 999.0
		check(before.bank.cash == 100, "Successful repayment result has detached nested accounts")
	print("Principal research: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
