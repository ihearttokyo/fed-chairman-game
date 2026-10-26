extends RefCounted
# Unshipped performing-credit accounting experiment. No production imports.
const BANK_KEYS = ["cash", "securities", "deposits", "cb_principal", "interest_payable", "interest_receivable"]
const FED_KEYS = ["principal_asset", "interest_receivable", "reserve_liabilities", "interest_payable", "capital"]

static func opening(cash: Variant, securities: Variant, deposits: Variant, principal: Variant, opening_fed_capital: Variant, performing: Variant = true) -> Dictionary:
	for value in [cash, securities, deposits, principal]:
		if not _number(value) or value < 0:
			return _fail("Opening amounts must be finite nonnegative representable numbers")
	if not _number(opening_fed_capital):
		return _fail("Explicit finite opening Fed capital assumption required; not current-period earnings")
	if typeof(performing) != TYPE_BOOL or not performing:
		return _fail("Model boundary: impaired/noncollectible credit and nonaccrual accounting unsupported")
	var state := {"performing": true,
		"bank": {"cash": float(cash), "securities": float(securities), "deposits": float(deposits), "cb_principal": float(principal), "interest_payable": 0.0, "interest_receivable": 0.0},
		"fed": {"principal_asset": float(principal), "interest_receivable": 0.0, "reserve_liabilities": float(cash), "interest_payable": 0.0, "capital": float(opening_fed_capital)}}
	var checked := inspect(state)
	if not checked.ok:
		return checked
	return {"ok": true, "state": state, "bank_equity": checked.bank_equity, "fed_capital": checked.fed_capital}

static func inspect(state: Variant) -> Dictionary:
	if not _schema(state, ["performing", "bank", "fed"]) or not _schema(state.bank, BANK_KEYS) or not _schema(state.fed, FED_KEYS):
		return _fail("Exact ledger schema required")
	if typeof(state.performing) != TYPE_BOOL or not state.performing:
		return _fail("Model boundary: impaired/noncollectible credit and nonaccrual accounting unsupported")
	for key in BANK_KEYS:
		if not _number(state.bank[key]) or state.bank[key] < 0:
			return _fail("Invalid bank amount: " + key)
	for key in FED_KEYS:
		if not _number(state.fed[key]) or (key != "capital" and state.fed[key] < 0):
			return _fail("Invalid Fed amount: " + key)
	if state.bank.cb_principal != state.fed.principal_asset or state.bank.cash != state.fed.reserve_liabilities or state.bank.interest_payable != state.fed.interest_receivable or state.bank.interest_receivable != state.fed.interest_payable:
		return _fail("Unpaired principal, reserve, or interest claims")
	var bank_equity := _bank_equity(state)
	var fed_capital := _fed_capital(state)
	if not is_finite(bank_equity) or not is_finite(fed_capital) or fed_capital != state.fed.capital:
		return _fail("Unrepresentable or inconsistent equity/capital identity")
	return {"ok": true, "bank_equity": bank_equity, "fed_capital": fed_capital}

static func accrue(state: Variant, annual_rate_pct: Variant, days: Variant, allow_negative: Variant = false) -> Dictionary:
	var checked := inspect(state)
	if not checked.ok:
		return checked
	if not _number(annual_rate_pct) or typeof(days) != TYPE_INT or days < 0 or days > 9007199254740992 or typeof(allow_negative) != TYPE_BOOL:
		return _fail("Finite APR, nonnegative exact whole days, and Boolean counterfactual opt-in required")
	if annual_rate_pct < 0 and not allow_negative:
		return _fail("Negative loan interest requires explicit counterfactual opt-in; not a US primary-credit fact")
	var amount := 0.0
	if annual_rate_pct != 0 and days != 0 and state.bank.cb_principal != 0:
		amount = (absf(float(annual_rate_pct)) / 100.0) * (float(days) / 365.0) * float(state.bank.cb_principal)
		if not is_finite(amount) or amount <= 0:
			return _fail("Unrepresentable accrued interest: overflow or positive obligation underflow")
	var next: Dictionary = state.duplicate(true)
	var positive: bool = annual_rate_pct >= 0
	var bank_key := "interest_payable" if positive else "interest_receivable"
	var fed_key := "interest_receivable" if positive else "interest_payable"
	next.bank[bank_key] = _move(float(state.bank[bank_key]), amount)
	next.fed[fed_key] = next.bank[bank_key]
	return _finish(state, next, amount if positive else -amount, 0.0)

static func settle_positive(state: Variant, amount: Variant) -> Dictionary:
	return _settle(state, amount, true)

static func settle_negative(state: Variant, amount: Variant) -> Dictionary:
	return _settle(state, amount, false)

static func repay_principal(state: Variant, amount: Variant) -> Dictionary:
	var checked := inspect(state)
	if not checked.ok:
		return checked
	if not _number(amount) or amount < 0:
		return _fail("Principal repayment must be finite, nonnegative and representable")
	if amount > state.bank.cb_principal or amount > state.bank.cash:
		return _fail("Principal repayment exceeds outstanding principal or available reserve cash")
	var next: Dictionary = state.duplicate(true)
	next.bank.cash = _move(float(state.bank.cash), -float(amount))
	next.fed.reserve_liabilities = next.bank.cash
	next.bank.cb_principal = _move(float(state.bank.cb_principal), -float(amount))
	next.fed.principal_asset = next.bank.cb_principal
	# Principal settlement neither cancels interest claims nor recognizes income.
	return _finish(state, next, 0.0, -float(amount))

static func _settle(state: Variant, amount: Variant, positive: bool) -> Dictionary:
	var checked := inspect(state)
	if not checked.ok:
		return checked
	if not _number(amount) or amount < 0:
		return _fail("Settlement amount must be finite, nonnegative and representable")
	var bank_key := "interest_payable" if positive else "interest_receivable"
	var fed_key := "interest_receivable" if positive else "interest_payable"
	if amount > state.bank[bank_key] or (positive and amount > state.bank.cash):
		return _fail("Settlement exceeds the separate claim or available bank reserve cash; unpaid claim remains")
	var next: Dictionary = state.duplicate(true)
	var cash_flow := -float(amount) if positive else float(amount)
	next.bank.cash = _move(float(state.bank.cash), cash_flow)
	next.fed.reserve_liabilities = next.bank.cash
	next.bank[bank_key] = _move(float(state.bank[bank_key]), -float(amount))
	next.fed[fed_key] = next.bank[bank_key]
	return _finish(state, next, 0.0, cash_flow)

static func _finish(old: Dictionary, next: Dictionary, fed_income: float, cash_flow: float) -> Dictionary:
	next.fed.capital = _fed_capital(next)
	var checked := inspect(next)
	if not checked.ok:
		return checked
	var old_equity := _bank_equity(old)
	var bank_error := _net([checked.bank_equity, -old_equity, fed_income])
	var fed_error := _net([checked.fed_capital, -float(old.fed.capital), -fed_income])
	# This is an explicit representation audit, never a liability adjustment.
	# Scale by this transaction, not the book; disclose residuals in the result.
	var bound := 1e-12 * maxf(absf(fed_income), absf(cash_flow))
	if not is_finite(bank_error) or not is_finite(fed_error) or absf(bank_error) > bound or absf(fed_error) > bound:
		return _fail("Unrepresentable transaction-sized equity/income reconciliation")
	return {"ok": true, "state": next, "bank_equity": checked.bank_equity, "fed_capital": checked.fed_capital,
		"bank_interest_income": -fed_income, "fed_interest_income": fed_income, "cash_to_bank": cash_flow,
		"principal_change": next.bank.cb_principal - old.bank.cb_principal, "bank_equity_roundoff": bank_error, "fed_capital_roundoff": fed_error}

static func _bank_equity(state: Dictionary) -> float:
	return _net([float(state.bank.cash), float(state.bank.securities), float(state.bank.interest_receivable), -float(state.bank.deposits), -float(state.bank.cb_principal), -float(state.bank.interest_payable)])

static func _fed_capital(state: Dictionary) -> float:
	return _net([float(state.fed.principal_asset), float(state.fed.interest_receivable), -float(state.fed.reserve_liabilities), -float(state.fed.interest_payable)])

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func _schema(value: Variant, keys: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true

static func _number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= -9007199254740992 and value <= 9007199254740992
	return typeof(value) == TYPE_FLOAT and is_finite(value)

static func _move(old: float, change: float) -> float:
	var next := _net([old, change])
	var error := _net([next, -old, -change])
	if next < 0 or not is_finite(error) or absf(error) > 1e-12 * absf(change):
		return NAN
	return next

static func _difference(larger: float, smaller: float) -> float:
	var residual := larger - smaller
	if residual < 0 or (smaller > 0 and residual == larger):
		return NAN
	var virtual := residual - larger
	var roundoff := (larger - (residual - virtual)) + (-smaller - virtual)
	if larger == floor(larger) and smaller == floor(smaller) and roundoff != 0:
		return NAN
	return residual

static func _net(legs: Array) -> float:
	# Cancel original opposite legs first; reject erased positive legs, not debt.
	var credits: Array = []
	var debits: Array = []
	for leg in legs:
		if not is_finite(float(leg)):
			return NAN
		if leg > 0:
			credits.append(float(leg))
		elif leg < 0:
			debits.append(-float(leg))
	credits.sort()
	debits.sort()
	while not credits.is_empty() and not debits.is_empty():
		var credit: float = credits.pop_back()
		var debit: float = debits.pop_back()
		if credit > debit:
			var residual := _difference(credit, debit)
			if not is_finite(residual):
				return NAN
			credits.append(residual)
			credits.sort()
		elif debit > credit:
			var residual := _difference(debit, credit)
			if not is_finite(residual):
				return NAN
			debits.append(residual)
			debits.sort()
	var residuals: Array = credits if not credits.is_empty() else debits
	var total := 0.0
	for amount in residuals:
		var combined: float = total + amount
		if not is_finite(combined):
			return NAN
		var virtual: float = combined - total
		var roundoff: float = (total - (combined - virtual)) + (amount - virtual)
		if (total > 0 and (combined == total or combined == amount)) or (total == floor(total) and amount == floor(amount) and roundoff != 0):
			return NAN
		total = combined
	return -total if not debits.is_empty() else total
