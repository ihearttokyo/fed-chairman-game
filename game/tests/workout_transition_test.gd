extends SceneTree
const Career = preload("res://play/career.gd")
const Economy = preload("res://model/economy.gd")

class CircularEconomy:
	extends "res://model/economy.gd"
	var workout_passes := 0
	func _step_internal(state: Dictionary, policy: Dictionary, shocks: Dictionary, params: Dictionary, workout_context: Dictionary = {}) -> Dictionary:
		var result := super._step_internal(state, policy, shocks, params, workout_context)
		if not workout_context.is_empty():
			workout_passes += 1
		if result.ok and workout_passes == 2:
			# Perturb the accepted frame only, not the detached quote frame.
			result.state.long_yield_pct += 0.125
		return result

class CountingEconomy:
	extends "res://model/economy.gd"
	var public_steps := 0
	func step(state: Dictionary, policy: Dictionary, shocks: Dictionary, params: Dictionary) -> Dictionary:
		public_steps += 1
		return super.step(state, policy, shocks, params)

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
	check(abs(actual - expected) <= 1e-9, label)

func origin(low_reserves: bool = false) -> Dictionary:
	var career := Career.new()
	if low_reserves:
		# A separately authored, constructor-validated reserve-boundary fixture;
		# no source parameter or manually patched native balance is installed.
		career.params.initial_reserves_pct_initial_gdp = career.params.reserve_clear_pct_current_gdp
	check(career.start("stagflation_bank_run", 417).ok, "Genuine native career starts")
	if career.state.is_empty():
		return {"ok": false}
	var model := career.model
	var before: Dictionary = career.state.duplicate(true)
	var pulse: Dictionary = career.current_briefing()
	var policy: Dictionary = model.benchmark_policy(before, career.params, "hold")
	policy.liquidity_request_pct_initial_gdp = 2.0
	policy.maintain_ample_reserves = true
	var frozen := var_to_bytes([before, pulse, policy, career.params])
	var actual: Dictionary = career.advance(policy)
	var repeated: Dictionary = model.step(before, policy, pulse, career.params)
	check(actual.ok and repeated.ok and var_to_bytes(actual) == var_to_bytes(repeated), "Real originating step and full native repeat agree")
	check(var_to_bytes([before, pulse, policy, career.params]) == frozen, "Originating native inputs remain pure")
	if not actual.ok:
		return {"ok": false}
	check(career.state.outstanding_liquidity_pct_initial_gdp == 2.0, "Opening debt was actually originated, not fabricated")
	if career.state.outstanding_liquidity_pct_initial_gdp != 2.0:
		return {"ok": false}
	var q: int = career.state.quarter_index
	var bank := {"quarter_index": q, "cash": 0.0, "deposits": 3.0, "withdrawal_queue": 0.0,
		"central_bank_loan": 2.0, "loan_arrears": 0.0, "annual_yield_pct": 0.0,
		"claims": [{"maturity_quarter": q + 3, "face": 10.0}], "initial_face": 10.0, "matured_face": 0.0}
	return {"ok": true, "model": model, "native": career.state.duplicate(true), "bank": bank, "params": career.params}

func policy_for(model: Object, native: Dictionary, params: Dictionary, offer: float, change: float = 0.0) -> Dictionary:
	var policy: Dictionary = model.benchmark_policy(native, params, "hold")
	policy.policy_rate_request_pct += change
	policy.guidance_rate_pct += change
	policy.liquidity_request_pct_initial_gdp = offer
	policy.maintain_ample_reserves = true
	return policy

func order(new_withdrawals: float = 0.0, share: float = 1.0) -> Dictionary:
	return {"new_withdrawals": new_withdrawals, "haircut_pct": 4.0, "pledgeable_share": share}

func paired(model: Object, native: Dictionary, policy: Dictionary, params: Dictionary, bank: Dictionary, action: Dictionary) -> Dictionary:
	var shocks := {}
	var frozen := var_to_bytes([native, policy, shocks, params, bank, action])
	calls += 2
	var result: Dictionary = model.bank_workout_transition(native, policy, shocks, params, bank, action)
	var repeated: Dictionary = model.bank_workout_transition(native, policy, shocks, params, bank, action)
	check(result.ok, "Coupled native/workout transition accepts this physical fixture")
	if not result.ok and failures <= 10:
		print("DETAIL: ", result.get("error", "unknown"))
	check(var_to_bytes(result) == var_to_bytes(repeated), "Complete coupled result repeats exactly")
	check(var_to_bytes([native, policy, shocks, params, bank, action]) == frozen, "All six caller inputs remain byte-pure")
	if result.ok:
		identities(native, bank, result)
	return result

func identities(prior: Dictionary, bank: Dictionary, result: Dictionary) -> void:
	var n: Dictionary = result.state
	var b: Dictionary = result.bank_result
	check(n.quarter_index == prior.quarter_index + 1 and n.quarter_index == result.bank_state.quarter_index, "Both clocks advance exactly once")
	check(n.outstanding_liquidity_pct_initial_gdp == result.bank_state.central_bank_loan, "Native total exposure includes the authoritative remaining bank debt")
	check(n.lending_collateral_capacity_pct_initial_gdp == b.capacity, "Collateral capacity has one authoritative multiplication order")
	near(n.liquidity_repayment_pct_initial_gdp, b.repayment + b.renewal, "Retired old contracts are cash repayment plus cashless renewal")
	near(n.liquidity_applied_pct_initial_gdp, b.renewal + b.new_cash, "Gross new local exposure includes renewal and fresh cash only")
	check(n.liquidity_refinancing_applied_pct_initial_gdp == b.renewal and n.liquidity_new_need_applied_pct_initial_gdp == b.new_cash, "Renewal and genuinely new lending remain separate")
	check(n.refinancing_need_pct_initial_gdp == b.old_exposure_remaining and n.uncovered_refinancing_pct_initial_gdp == b.loan_arrears, "Refinancing need is all remaining old debt; uncovered refinancing is arrears")
	check(n.uncovered_new_funding_pct_initial_gdp == b.remaining_queue, "Native unmet new need is the unpaid deposit queue")
	near(n.uncovered_funding_pct_initial_gdp, b.loan_arrears + b.remaining_queue, "Both disclosed local pressure components reconcile")
	check(n.liquidity_aggregate_applied_pct_initial_gdp == 0.0 and n.liquidity_eligibility_binding == 0.0, "One-bank mode neither reuses collateral for aggregate loans nor changes counterparty eligibility")
	near(n.liquidity_applied_pct_initial_gdp - n.liquidity_repayment_pct_initial_gdp, b.net_cb_flow, "Gross contract flows net to actual CB cash flow")
	near(n.outstanding_liquidity_pct_initial_gdp - bank.central_bank_loan, b.net_cb_flow, "Carried arrears are not silently retired")
	near(n.total_assets_pct_initial_gdp, n.asset_stock_pct_initial_gdp + n.outstanding_liquidity_pct_initial_gdp, "Native asset ledger includes retained overdue principal")
	near(n.total_assets_pct_initial_gdp, n.reserves_pct_initial_gdp + n.reverse_repo_pct_initial_gdp + n.currency_pct_initial_gdp + n.treasury_account_pct_initial_gdp + n.capital_other_pct_initial_gdp, "Native Fed balance sheet closes")
	var reserve_change: float = b.net_cb_flow + n.asset_flow_applied_pct_initial_gdp + n.reserve_maintenance_purchase_pct_initial_gdp - n.currency_conversion_pct_initial_gdp + prior.reverse_repo_pct_initial_gdp - n.reverse_repo_pct_initial_gdp
	near(n.reserves_pct_initial_gdp - prior.reserves_pct_initial_gdp, reserve_change, "Reserves use fresh cash minus actual repayment, never renewal cash")
	near(n.total_assets_pct_initial_gdp - prior.total_assets_pct_initial_gdp, n.asset_stock_pct_initial_gdp - prior.asset_stock_pct_initial_gdp + b.net_cb_flow, "Native asset change matches securities and actual loan-principal change")
	check(n.capital_other_pct_initial_gdp == prior.capital_other_pct_initial_gdp, "Private mark losses do not repair or revalue Fed capital")
	near(b.equity_change, b.expected_equity_change, "Private equity bridge remains separate and closed")
	check(b.deposit_due >= b.withdrawals_paid and b.deposit_due - b.withdrawals_paid == b.remaining_queue, "UI deposit_due is the already calculated requested amount")

func _initialize() -> void:
	var fixture := origin()
	if not fixture.ok:
		finish()
		return
	var model: Object = fixture.model
	var n: Dictionary = fixture.native
	var b: Dictionary = fixture.bank
	var p: Dictionary = fixture.params
	var default_policy := policy_for(model, n, p, 0.0)
	var direct: Dictionary = model.step(n, default_policy, {}, p)
	var internal: Dictionary = model._step_internal(n, default_policy, {}, p)
	check(var_to_bytes(direct) == var_to_bytes(internal), "Public default four-argument step retains the raw internal result")
	var counted := CountingEconomy.new()
	var subclass: Dictionary = counted.step(n, default_policy, {}, p)
	check(counted.public_steps == 1 and var_to_bytes(subclass) == var_to_bytes(direct), "Existing four-argument counting subclasses retain their call semantics")
	_test_briefing(b)
	var menu: Array = []
	for change in [0.0, 2.0]:
		var result := paired(model, n, policy_for(model, n, p, 100.0, change), p, b, order(1.0))
		if result.ok:
			menu.append(result)
	check(menu.size() == 2, "Both fixed quote alternatives settle")
	if menu.size() == 2:
		check(menu[1].discount_yield_pct > menu[0].discount_yield_pct and menu[1].bank_result.remaining_market_value < menu[0].bank_result.remaining_market_value, "Higher native quote lowers the same dated collateral value")
		check(menu[0].bank_result.prequote_reference_need == menu[1].bank_result.prequote_reference_need, "Repricing cannot shrink the frozen reference need")
	var zero := paired(model, n, policy_for(model, n, p, 0.0), p, b, order(1.0))
	if zero.ok:
		check(zero.bank_state.central_bank_loan == 2.0 and zero.bank_state.loan_arrears == 2.0 and zero.bank_state.withdrawal_queue == 1.0, "Zero offer preserves both unpaid classes and advances")
		var later := paired(model, zero.state, policy_for(model, zero.state, p, 0.0), p, zero.bank_state, order())
		if later.ok:
			check(later.bank_result.deposit_due == 1.0 and later.bank_state.withdrawal_queue == 1.0, "Persistent requests are not resubmitted")
			var mature := paired(model, later.state, policy_for(model, later.state, p, 0.0), p, later.bank_state, order())
			if mature.ok:
				check(mature.bank_result.matured_principal == 10.0 and mature.bank_result.capacity == 0.0 and mature.bank_state.cash == 7.0, "Maturity cash pays claims and cannot also be pledged")
				check(mature.state.uncovered_funding_pct_initial_gdp == 0.0 and mature.state.outstanding_liquidity_pct_initial_gdp == 0.0, "Cash-aware native need fixes the earlier maturity semantic mismatch")
				var empty := paired(model, mature.state, policy_for(model, mature.state, p, 0.0), p, mature.bank_state, order())
				check(empty.ok and empty.bank_result.matured_principal == 0.0, "Matured principal cannot pay a second time")
		var cure := paired(model, zero.state, policy_for(model, zero.state, p, 100.0), p, zero.bank_state, order())
		if cure.ok:
			check(cure.bank_result.renewal == 2.0 and cure.bank_result.new_cash == 1.0 and cure.bank_state.loan_arrears == 0.0 and cure.bank_state.withdrawal_queue == 0.0, "Later credit permission cures distress without erasing old principal")
	for share in [0.37, 0.25, 0.0]:
		var partial := paired(model, n, policy_for(model, n, p, 100.0), p, b, order(1.0, share))
		if partial.ok:
			check(partial.state.eligible_local_need_pct_initial_gdp == 3.0, "Asset pledgeability does not reduce counterparty-eligible need")
	_test_actual_switches()
	var frozen := var_to_bytes([n, b, p])
	for field in ["quarter_index", "central_bank_loan"]:
		var wrong := b.duplicate(true)
		wrong[field] += 1
		calls += 1
		var refused: Dictionary = model.bank_workout_transition(n, default_policy, {}, p, wrong, order())
		check(not refused.ok and not refused.has("state") and not refused.has("bank_state"), "Opening clock/principal mismatches cannot create a next state")
	var circular := CircularEconomy.new()
	calls += 1
	var rejected: Dictionary = circular.bank_workout_transition(n, policy_for(model, n, p, 100.0), {}, p, b, order(1.0))
	check(not rejected.ok and not rejected.has("state"), "Introduced quote circularity is refused, not iterated")
	check(var_to_bytes([n, b, p]) == frozen, "Rejections preserve the genuine opening inputs")
	finish()

func _test_briefing(bank: Dictionary) -> void:
	var action := order(1.0)
	var frozen := var_to_bytes([bank, action])
	var brief: Dictionary = Economy.bank_workout_briefing(bank, action)
	check(brief.ok and brief.shocks.funding_need_pct_initial_gdp == 1.0 and brief.shocks.refinancing_need_pct_initial_gdp == 2.0, "Current funding briefing uses cash-aware bank requests, not the inherited ordinary pulse")
	check(brief.ok and brief.shocks.eligible_collateral_pct_initial_gdp == 10.0 and brief.shocks.liquidity_eligibility_pct == 100.0, "Before-policy mark is distinct from borrower eligibility")
	check(var_to_bytes([bank, action]) == frozen, "Public prequote briefing is caller-pure")
	var matured := bank.duplicate(true)
	matured.claims[0].maturity_quarter = matured.quarter_index + 1
	var paid: Dictionary = Economy.bank_workout_briefing(matured, action)
	check(paid.ok and paid.shocks.funding_need_pct_initial_gdp == 0.0 and paid.shocks.refinancing_need_pct_initial_gdp == 0.0 and paid.shocks.eligible_collateral_pct_initial_gdp == 0.0, "Known maturity cash removes financing need and pledged matured collateral")
	check(not Economy.bank_workout_briefing(bank, {}).ok and not Economy.bank_workout_briefing({}, action).ok, "Malformed current briefing inputs fail closed")

func _test_actual_switches() -> void:
	var fixture := origin(true)
	if not fixture.ok:
		return
	var bank: Dictionary = fixture.bank.duplicate(true)
	bank.claims = [{"maturity_quarter": bank.quarter_index + 1, "face": 2.0}, {"maturity_quarter": bank.quarter_index + 8, "face": 10.0}]
	bank.initial_face = 12.0
	var policy := policy_for(fixture.model, fixture.native, fixture.params, 100.0)
	policy.maintain_ample_reserves = false
	policy.sterilize_purchases = true
	policy.asset_flow_request_pct_initial_gdp = 1.0
	var result := paired(fixture.model, fixture.native, policy, fixture.params, bank, order())
	if result.ok:
		check(result.state.reserve_maintenance_purchase_pct_initial_gdp == 0.0 and result.state.reserve_scarcity_wedge_pct > 0.0, "Final frame honors actual maintenance-off scarcity, not provisional accommodation")
		check(result.state.liquidity_aggregate_need_pct_initial_gdp > 0.0 and result.state.liquidity_aggregate_applied_pct_initial_gdp == 0.0, "Remaining private collateral cannot also fund aggregate reserve need")
		check(result.state.discretionary_purchase_pct_initial_gdp == 1.0 and result.state.sterilization_applied_pct_initial_gdp > 0.0, "Actual asset and sterilization switches survive quote preparation")

func finish() -> void:
	print("BW618_CHECKS ", checks, " FAILURES ", failures, " PUBLIC_COUPLED_CALLS ", calls)
	if failures == 0:
		print("PASS: optional coupled principal/arrears/cash transition and raw-default parity; no release qualification")
	quit(1 if failures else 0)
