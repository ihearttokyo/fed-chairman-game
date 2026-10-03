extends SceneTree

const Economy = preload("res://model/economy.gd")
var failures: Array[String] = []
var model := Economy.new()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _initialize() -> void:
	check(model.has_method("nominal_gdp_ratio"), "balance ledger exposes the observed nominal-GDP ratio")
	check(model.has_method("_portfolio_premium"), "bounded duration equation permits direct numerical boundary checks")
	check(model.has_method("_validate_portfolio_reference"), "reference validation rejects malformed resident ladders")
	check(model.has_method("_mbs_repayment_fraction"), "MBS principal uses nonlinear lagged refinancing rather than1/WAM")
	var params: Dictionary = model.load_parameters().values
	var initial: Dictionary = model.initial_state(params).state
	for key in ["treasury_cohorts_pct_initial_gdp", "sterilized_treasury_cohorts_pct_initial_gdp", "bill_cohorts_pct_initial_gdp", "mbs_stock_pct_initial_gdp", "reserves_pct_initial_gdp", "reverse_repo_pct_initial_gdp", "currency_pct_initial_gdp", "treasury_account_pct_initial_gdp", "capital_other_pct_initial_gdp"]:
		check(initial.has(key), "balance ledger requires explicit %s" % key)
	if failures.is_empty():
		_test_initial_and_denominator(initial)
		_test_tools(initial, params)
		_test_neutrality(initial, params)
		_test_extended_contract(initial, params)
		_test_joint_constraints(initial, params)
		_test_validation_edges(initial, params)
		_test_schema_rejection(initial, params)
		var extreme: float = model.call("_portfolio_premium", 1e308, 1e-308, 0.5, params)
		check(is_finite(extreme) and abs(extreme - (0.5 - params.portfolio_premium_max_shift_pct)) < 1e-12, "bounded premium saturates without rejecting a representable ledger for an overflowing quotient")
	for failure in failures:
		printerr("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: explicit source-backed balance ledger and GDP denominator")
	quit(0 if failures.is_empty() else 1)

func _sum(values: Array) -> float:
	var total := 0.0
	for value in values:
		total += float(value)
	return total

func _ledger(state: Dictionary) -> float:
	return _sum(state.treasury_cohorts_pct_initial_gdp) + _sum(state.bill_cohorts_pct_initial_gdp) + state.mbs_stock_pct_initial_gdp + state.outstanding_liquidity_pct_initial_gdp - state.reserves_pct_initial_gdp - state.reverse_repo_pct_initial_gdp - state.currency_pct_initial_gdp - state.treasury_account_pct_initial_gdp - state.capital_other_pct_initial_gdp

func _test_initial_and_denominator(initial: Dictionary) -> void:
	check(initial.treasury_cohorts_pct_initial_gdp.size() == 120 and initial.sterilized_treasury_cohorts_pct_initial_gdp.size() == 120 and initial.bill_cohorts_pct_initial_gdp.size() == 4, "principal and subset cohorts retain bounded source-backed shape")
	check(abs(_ledger(initial)) < 1e-7, "actual ledger assets equal liabilities plus the fixed signed residual")
	check(abs(float(model.call("nominal_gdp_ratio", initial)) - 1.0) < 1e-12, "initial nominal-GDP ratio is one, including a scenario output gap")
	var changed := initial.duplicate(true)
	changed.actual_output_index *= 2.0
	changed.potential_output_index *= 2.0
	check(abs(float(model.call("nominal_gdp_ratio", changed)) - 2.0) < 1e-12, "changed observed output changes only the denominator")
	check(changed.treasury_cohorts_pct_initial_gdp == initial.treasury_cohorts_pct_initial_gdp and changed.reserves_pct_initial_gdp == initial.reserves_pct_initial_gdp, "GDP ratio conversion cannot fabricate principal or reserves")

func _test_tools(initial: Dictionary, params: Dictionary) -> void:
	var policy: Dictionary = model.benchmark_policy(initial, params, "neutral")
	var preserved := initial.duplicate(true)
	var large := policy.duplicate(true)
	large.asset_flow_request_pct_initial_gdp = 150.0
	var purchased: Dictionary = model.step(initial, large, {}, params)
	check(purchased.ok, "large finite purchases are not rejected by an invented request quota")
	if purchased.ok:
		check(abs(purchased.state.asset_stock_pct_initial_gdp - 170.0) < 1e-7 and abs(_ledger(purchased.state)) < 1e-7, "full large purchase creates matching securities and liabilities")
	var sterile := large.duplicate(true)
	sterile.asset_flow_request_pct_initial_gdp = 2.0
	sterile.sterilize_purchases = true
	var plain := sterile.duplicate(true)
	plain.sterilize_purchases = false
	var full: Dictionary = model.step(initial, sterile, {}, params)
	var raw: Dictionary = model.step(initial, plain, {}, params)
	check(full.ok and raw.ok, "paired duration purchases and reserve absorption settle")
	if full.ok and raw.ok:
		check(abs(full.state.term_premium_pct - raw.state.term_premium_pct) < 1e-12, "sterilization retains the identical direct duration effect")
		check(abs(full.state.reserves_pct_initial_gdp - initial.reserves_pct_initial_gdp) < 1e-7 and abs(raw.state.reserves_pct_initial_gdp - initial.reserves_pct_initial_gdp - 2.0) < 1e-7, "full absorption offsets purchase-created reserves without deleting securities")
		var repeat := model.benchmark_policy(full.state, params, "neutral")
		repeat.sterilize_purchases = true
		var rolled: Dictionary = model.step(full.state, repeat, {}, params)
		check(rolled.ok, "reinvestment and repeated overnight absorption settle")
		if rolled.ok:
			check(abs(rolled.state.reverse_repo_pct_initial_gdp - full.state.reverse_repo_pct_initial_gdp) < 1e-7, "matched principal reinvestment cannot accumulate fresh sterilization liability")
	for switch in ["reinvest_principal", "maintain_ample_reserves", "sterilize_purchases"]:
		var bad := policy.duplicate(true)
		bad[switch] = 1
		check(not model.step(initial, bad, {}, params).ok, "optional %s requires a boolean, not a numeric surrogate" % switch)
	var explicit := policy.duplicate(true)
	explicit.reinvest_principal = true
	explicit.maintain_ample_reserves = true
	explicit.sterilize_purchases = false
	check(model.step(initial, policy, {}, params) == model.step(initial, explicit, {}, params), "missing switches match explicit defaults exactly")
	var natural := policy.duplicate(true)
	natural.reinvest_principal = false
	natural.maintain_ample_reserves = false
	var runoff: Dictionary = model.step(initial, natural, {}, params)
	check(runoff.ok, "ordinary natural principal runoff is feasible at initial ample reserves")
	if runoff.ok:
		check(runoff.state.asset_stock_pct_initial_gdp < initial.asset_stock_pct_initial_gdp and abs(_ledger(runoff.state)) < 1e-7, "natural runoff reduces only actual maturing securities and reconciles liabilities")
	for reinvest in [true, false]:
		var capped := natural.duplicate(true)
		capped.reinvest_principal = reinvest
		capped.asset_flow_request_pct_initial_gdp = -0.25
		var limited: Dictionary = model.step(initial, capped, {}, params)
		check(limited.ok, "explicit runoff cap can reinvest remaining due principal")
		if limited.ok:
			check(abs(initial.asset_stock_pct_initial_gdp - limited.state.asset_stock_pct_initial_gdp - 0.25) < 1e-7, "negative cap has the same physical semantics with either checkbox state")
	var offered := policy.duplicate(true)
	offered.liquidity_request_pct_initial_gdp = 400.0
	var funding := {"funding_need_pct_initial_gdp":100.0,"eligible_collateral_pct_initial_gdp":100.0,"collateral_haircut_pct":10.0,"liquidity_eligibility_pct":100.0}
	var loan: Dictionary = model.step(initial, offered, funding, params)
	check(loan.ok, "large loan offer is accepted independently from applied collateral capacity")
	if loan.ok:
		check(abs(loan.state.outstanding_liquidity_pct_initial_gdp - 90.0) < 1e-7 and abs(_ledger(loan.state)) < 1e-7, "concurrent secured loan exposure respects actual collateral, not a quarter quota")
		var due: Dictionary = model.step(loan.state, model.benchmark_policy(loan.state, params, "neutral"), {}, params)
		check(due.ok, "old representative short loans settle without automatic multiyear survival")
		if due.ok:
			check(due.state.outstanding_liquidity_pct_initial_gdp == 0.0 and abs(due.state.liquidity_repayment_pct_initial_gdp - 90.0) < 1e-7, "no renewal means full principal maturity, not15% amortization")
	funding.liquidity_eligibility_pct = 0.0
	var denied: Dictionary = model.step(initial, offered, funding, params)
	check(denied.ok, "ineligible local funding remains a valid economic shock")
	if denied.ok:
		check(denied.state.outstanding_liquidity_pct_initial_gdp == 0.0 and denied.state.uncovered_funding_pct_initial_gdp == 100.0, "unlimited offers cannot make ineligible borrowers eligible")
	check(initial == preserved, "valid and rejected balance decisions leave the supplied state untouched")

func _test_neutrality(initial: Dictionary, params: Dictionary) -> void:
	var state := initial.duplicate(true)
	for q in range(240):
		var result: Dictionary = model.step(state, model.benchmark_policy(state, params, "neutral"), {}, params)
		check(result.ok, "passive balance-sheet neutrality settles quarter%d" % q)
		if not result.ok:
			return
		state = result.state
		check(abs(state.output_gap_pct) < 1e-7 and abs(state.annualized_quarterly_inflation_pct - 2.0) < 1e-7, "passive reference and reserve housekeeping cannot create macro drift")
		check(abs(state.term_premium_pct - initial.term_premium_pct) < 1e-7 and abs(_ledger(state)) < 1e-7, "duration-reference neutrality and actual ledger accounting hold together")

func _test_extended_contract(initial: Dictionary, params: Dictionary) -> void:
	var policy: Dictionary = model.benchmark_policy(initial, params, "neutral")
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://model/portfolio_reference.json"))
	for malformed in [[], [1.0], reference.treasury_maturity_weights.duplicate()]:
		var bad := reference.duplicate(true)
		bad.treasury_maturity_weights = malformed
		if malformed.size() == 120:
			bad.treasury_maturity_weights[0] = -1.0
		check(not model.call("_validate_portfolio_reference", bad).ok, "malformed or negative Treasury reference weights reject")
	var bad_reference := reference.duplicate(true)
	bad_reference.treasury_maturity_weights[0] += 0.1
	check(not model.call("_validate_portfolio_reference", bad_reference).ok, "Treasury reference must be normalized, not silently repaired")
	for key in ["treasury_cohorts_pct_initial_gdp", "sterilized_treasury_cohorts_pct_initial_gdp", "bill_cohorts_pct_initial_gdp"]:
		for malformed in [[], [NAN], "not an array"]:
			var bad := initial.duplicate(true)
			bad[key] = malformed
			check(not model.step(bad, policy, {}, params).ok, "invalid state cohort shape/type rejects atomically")
	var bad_subset := initial.duplicate(true)
	bad_subset.sterilized_treasury_cohorts_pct_initial_gdp[0] = initial.treasury_cohorts_pct_initial_gdp[0] + 1.0
	check(not model.step(bad_subset, policy, {}, params).ok, "sterilization tags cannot exceed their actual Treasury cohort")
	var bad_residual := initial.duplicate(true)
	bad_residual.capital_other_pct_initial_gdp += 1.0
	check(not model.step(bad_residual, policy, {}, params).ok, "unreconciled state cannot reset the fixed residual")
	for switch in ["reinvest_principal", "maintain_ample_reserves", "sterilize_purchases"]:
		for value in ["true", null, 0.0]:
			var bad := policy.duplicate(true)
			bad[switch] = value
			check(not model.step(initial, bad, {}, params).ok, "all nonboolean policy switch representations reject")
	var unknown := policy.duplicate(true)
	unknown.future_policy = true
	check(not model.step(initial, unknown, {}, params).ok and not model.step(initial, policy, {"future_need":1.0}, params).ok, "unknown policy and exogenous inputs reject")
	var changed_gap: Dictionary = model.initial_state(params, {"output_gap_pct":-5.0})
	check(changed_gap.ok and abs(float(model.call("nominal_gdp_ratio", changed_gap.state)) - 1.0) < 1e-12, "nonzero initial output gap uses actual output as immutable GDP anchor")
	var base_fraction: float = model.call("_mbs_repayment_fraction", initial, params)
	check(abs(base_fraction - 3.0 * 16.2 / 2040.0) < 1e-12 and abs(base_fraction - 1.0 / (5.9 * 4.0)) > 1e-3, "observed MBS principal proxy is not inverse market WAM")
	var cheap := initial.duplicate(true)
	cheap.long_yield_pct -= 2.0
	var expensive := initial.duplicate(true)
	expensive.long_yield_pct += 2.0
	var faster: float = model.call("_mbs_repayment_fraction", cheap, params)
	var slower: float = model.call("_mbs_repayment_fraction", expensive, params)
	check(faster > base_fraction and slower < base_fraction and faster < 1.0 and slower > 0.0, "lagged cheaper refinancing increases bounded nonlinear MBS repayment")
	var natural := policy.duplicate(true)
	natural.reinvest_principal = false
	natural.maintain_ample_reserves = false
	var matured: Dictionary = model.step(initial, natural, {}, params)
	check(matured.ok, "source-backed principal settles without maintenance")
	if matured.ok:
		var due: float = initial.treasury_cohorts_pct_initial_gdp[0] + initial.mbs_stock_pct_initial_gdp * base_fraction
		check(abs(matured.state.principal_due_pct_initial_gdp - due) < 1e-10 and abs(matured.state.principal_runoff_pct_initial_gdp - due) < 1e-10, "Treasury first cohort and nonlinear MBS principal determine actual due/runoff")
		check(abs(matured.state.treasury_funding_transfer_pct_initial_gdp - matured.state.treasury_redemption_pct_initial_gdp) < 1e-12 and matured.state.treasury_account_pct_initial_gdp == initial.treasury_account_pct_initial_gdp, "Treasury funding/redemption net simultaneously without phantom TGA funds")
	var held: Dictionary = model.step(initial, policy, {}, params)
	check(held.ok, "full reinvestment settles")
	if held.ok:
		check(abs(held.state.principal_reinvestment_pct_initial_gdp - held.state.principal_due_pct_initial_gdp) < 1e-10 and held.state.principal_runoff_pct_initial_gdp == 0.0, "same-type principal conservation under full reinvestment")
		check(abs(held.state.capital_other_pct_initial_gdp - initial.capital_other_pct_initial_gdp) < 1e-12, "residual stays fixed through actual transactions")
	var offer := policy.duplicate(true)
	offer.liquidity_request_pct_initial_gdp = 400.0
	var funding := {"funding_need_pct_initial_gdp":100.0,"eligible_collateral_pct_initial_gdp":100.0,"collateral_haircut_pct":10.0,"liquidity_eligibility_pct":100.0}
	var lent: Dictionary = model.step(initial, offer, funding, params)
	check(lent.ok, "initial representative secured advance settles")
	if lent.ok:
		var refinance := {"funding_need_pct_initial_gdp":5.0,"refinancing_need_pct_initial_gdp":90.0,"eligible_collateral_pct_initial_gdp":100.0,"liquidity_eligibility_pct":100.0}
		var renewed: Dictionary = model.step(lent.state, offer, refinance, params)
		check(renewed.ok, "explicit refinancing and new need settle together")
		if renewed.ok:
			check(renewed.state.liquidity_refinancing_applied_pct_initial_gdp == 90.0 and renewed.state.liquidity_new_need_applied_pct_initial_gdp == 5.0 and renewed.state.liquidity_aggregate_applied_pct_initial_gdp == 0.0, "local refinancing is served first and stays separate from current new need/aggregate reserves")
		refinance.refinancing_need_pct_initial_gdp = 0.0
		var fresh: Dictionary = model.step(lent.state, offer, refinance, params)
		check(fresh.ok and fresh.state.outstanding_liquidity_pct_initial_gdp == 5.0, "default-zero refinancing never manufactures renewal demand")
		var insolvent: Dictionary = lent.state.duplicate(true)
		insolvent.treasury_account_pct_initial_gdp += insolvent.reserves_pct_initial_gdp - 0.1
		insolvent.reserves_pct_initial_gdp = 0.1
		var saved: Dictionary = insolvent.duplicate(true)
		var saved_policy := natural.duplicate(true)
		var saved_params := params.duplicate(true)
		var rejected: Dictionary = model.step(insolvent, natural, {}, params)
		check(not rejected.ok and str(rejected.get("error", "")).contains("mandatory settlement"), "infeasible complete net mandatory principal settlement returns a precise atomic error")
		check(insolvent == saved and natural == saved_policy and params == saved_params, "mandatory settlement failure preserves every supplied input")
	var sterile := policy.duplicate(true)
	sterile.asset_flow_request_pct_initial_gdp = 2.0
	sterile.sterilize_purchases = true
	var partial: Dictionary = model.step(initial, sterile, {"rrp_uptake_fraction":0.25}, params)
	check(partial.ok, "partial eligible RRP uptake settles")
	if partial.ok:
		check(abs(partial.state.sterilization_requested_pct_initial_gdp - 2.0) < 1e-12 and abs(partial.state.sterilization_applied_pct_initial_gdp - 0.5) < 1e-12 and abs(partial.state.sterilization_unfulfilled_pct_initial_gdp - 1.5) < 1e-12, "requested/applied/unsterilized principal exposes partial uptake")
		check(partial.state.sterilization_uptake_binding == 1.0, "uptake constraint is numeric and explicit")
	var encumbered: Dictionary = model.step(initial, sterile, {"rrp_encumbered_collateral_pct_initial_gdp":1e6}, params)
	check(encumbered.ok and encumbered.state.reverse_repo_pct_initial_gdp == 0.0 and encumbered.state.sterilization_collateral_binding == 1.0, "unavailable eligible RRP collateral cannot guarantee absorption")
	for uptake in [-0.1, 1.1]:
		check(not model.step(initial, sterile, {"rrp_uptake_fraction":uptake}, params).ok, "RRP uptake must remain a physical fraction")
	var tagged := initial.duplicate(true)
	tagged.sterilized_treasury_cohorts_pct_initial_gdp[0] = 0.5
	tagged.reverse_repo_pct_initial_gdp = 0.5
	tagged.reserves_pct_initial_gdp -= 0.5
	var tag_policy := policy.duplicate(true)
	tag_policy.sterilize_purchases = true
	tag_policy.asset_flow_request_pct_initial_gdp = -0.25
	var reduced: Dictionary = model.step(tagged, tag_policy, {}, params)
	check(reduced.ok, "tagged maturity/runoff settles")
	if reduced.ok:
		check(reduced.state.reverse_repo_pct_initial_gdp < 0.5 and abs(_sum(reduced.state.sterilized_treasury_cohorts_pct_initial_gdp) - reduced.state.reverse_repo_pct_initial_gdp) < 1e-10, "tagged principal runoff releases matching absorption rather than accumulating tags")
	var released: Dictionary = model.step(tagged, policy, {}, params)
	check(released.ok and released.state.reverse_repo_pct_initial_gdp == 0.0 and _sum(released.state.sterilized_treasury_cohorts_pct_initial_gdp) == 0.0, "switching sterilization off expires tags and prior absorption")
	var only_sterile := policy.duplicate(true)
	only_sterile.sterilize_purchases = true
	var no_new: Dictionary = model.step(initial, only_sterile, {}, params)
	check(no_new.ok and no_new.state.reverse_repo_pct_initial_gdp == 0.0, "passive reinvestment with sterilization enabled cannot create fresh tags")
	var scarce_policy := policy.duplicate(true)
	scarce_policy.maintain_ample_reserves = false
	var spreads: Array = []
	for reserves in [10.0, 9.0, 5.0, 4.0]:
		var snapshot := initial.duplicate(true)
		snapshot.treasury_account_pct_initial_gdp += snapshot.reserves_pct_initial_gdp - reserves
		snapshot.reserves_pct_initial_gdp = reserves
		var outcome: Dictionary = model.step(snapshot, scarce_policy, {}, params)
		check(outcome.ok, "scarcity comparison uses physically consistent snapshots")
		if outcome.ok:
			spreads.append(outcome.state.reserve_scarcity_wedge_pct)
	check(spreads.size() == 4 and spreads[0] == 0.0 and spreads[1] == 0.0 and spreads[3] > spreads[2] and spreads[2] > 0.0, "reserve scarcity is flat in abundance and stronger below the clear threshold")
	var plain := sterile.duplicate(true)
	plain.sterilize_purchases = false
	var raw: Dictionary = model.step(initial, plain, {}, params)
	var absorbed: Dictionary = model.step(initial, sterile, {}, params)
	check(raw.ok and absorbed.ok and abs(raw.state.output_gap_pct - absorbed.state.output_gap_pct) < 1e-12, "abundant reserve cash adds no separate QE output bonus beyond duration")
	var huge := policy.duplicate(true)
	huge.asset_flow_request_pct_initial_gdp = 1e308
	huge.liquidity_request_pct_initial_gdp = 1e308
	var extreme: Dictionary = model.step(initial, huge, {}, params)
	check(extreme.ok and is_finite(extreme.state.term_premium_pct) and extreme.state.liquidity_applied_pct_initial_gdp == 0.0, "huge finite offers settle with bounded duration and collateral-first lending")
	check(model.call("_validate_shocks", {"funding_need_pct_initial_gdp":1e308,"eligible_collateral_pct_initial_gdp":1e308}).ok, "finite funding/collateral have no100%-GDP validation ceiling")
	var tiny_premium: float = model.call("_portfolio_premium", 0.0, 1e-308, 0.5, params)
	check(tiny_premium == 0.5, "zero duration exposure returns the exact anchor before any tiny denominator division")

func _test_joint_constraints(initial: Dictionary, params: Dictionary) -> void:
	var policy: Dictionary = model.benchmark_policy(initial, params, "neutral")
	policy.sterilize_purchases = true
	policy.maintain_ample_reserves = false
	var tagged := initial.duplicate(true)
	var total := _sum(tagged.treasury_cohorts_pct_initial_gdp)
	for q in range(120):
		tagged.sterilized_treasury_cohorts_pct_initial_gdp[q] = tagged.treasury_cohorts_pct_initial_gdp[q] * 12.0 / total
	var limited: Dictionary = model.step(tagged, policy, {}, params)
	check(limited.ok, "reserve-limited tagged absorption is a feasible net snapshot")
	if limited.ok:
		check(limited.state.reserves_pct_initial_gdp == 0.0 and limited.state.sterilization_reserve_binding == 1.0 and abs(limited.state.reverse_repo_pct_initial_gdp - 9.0) < 1e-10, "RRP cannot consume more than final settlement reserves")
	policy.liquidity_request_pct_initial_gdp = 5.0
	var collateral := {"eligible_collateral_pct_initial_gdp":5.0,"liquidity_eligibility_pct":100.0}
	var accommodated: Dictionary = model.step(tagged, policy, collateral, params)
	check(accommodated.ok, "aggregate reserve need sees planned absorption before secured lending")
	if accommodated.ok:
		check(accommodated.state.liquidity_aggregate_applied_pct_initial_gdp == 5.0 and accommodated.state.liquidity_local_applied_pct_initial_gdp == 0.0 and accommodated.state.uncovered_funding_pct_initial_gdp == 0.0, "aggregate reserve accommodation is never credited as local access coverage")
		check(accommodated.state.has("liquidity_aggregate_need_pct_initial_gdp") and accommodated.state.has("liquidity_aggregate_offer_binding") and accommodated.state.has("liquidity_aggregate_collateral_binding"), "aggregate demand and both binding concurrent exposure constraints are explicit numeric diagnostics")
	policy.maintain_ample_reserves = true
	var maintained: Dictionary = model.step(tagged, policy, collateral, params)
	check(maintained.ok, "joint maintenance and absorption settle")
	if maintained.ok:
		check(maintained.state.liquidity_aggregate_applied_pct_initial_gdp == 0.0 and abs(maintained.state.reserves_pct_initial_gdp - 6.0) < 1e-10 and maintained.state.reserve_maintenance_purchase_pct_initial_gdp > 0.0, "maintenance cannot follow an unnecessary reserve-driven loan")
		check(abs(maintained.state.term_premium_pct - initial.term_premium_pct) < 1e-10, "short maintenance bills do not create hidden duration easing")
	var state := initial.duplicate(true)
	state.reserves_pct_initial_gdp = 3.0
	state.treasury_account_pct_initial_gdp += 6.0
	for q in range(5):
		var rolled: Dictionary = model.step(state, model.benchmark_policy(state, params, "neutral"), {}, params)
		check(rolled.ok, "four-quarter maintenance bill ladder rolls explicitly")
		if not rolled.ok:
			return
		state = rolled.state
		if q == 4:
			check(state.bill_redemption_pct_initial_gdp >= 3.0 and state.bill_rollover_pct_initial_gdp == state.bill_redemption_pct_initial_gdp, "maintenance bills mature and roll outside Treasury cohorts")
	var extreme_initial: Dictionary = model.initial_state(params, {"asset_stock_pct_initial_gdp":1e308})
	check(extreme_initial.ok, "large finite initialized holdings have a representable duration proxy without intermediate overflow")

func _test_validation_edges(initial: Dictionary, params: Dictionary) -> void:
	var policy: Dictionary = model.benchmark_policy(initial, params, "neutral")
	for key in ["treasury_cohorts_pct_initial_gdp", "sterilized_treasury_cohorts_pct_initial_gdp", "bill_cohorts_pct_initial_gdp"]:
		for bad_value in [NAN, INF, -1.0, true, "principal"]:
			var snapshot := initial.duplicate(true)
			snapshot[key][0] = bad_value
			check(not model.step(snapshot, policy, {}, params).ok, "valid-size cohort arrays reject invalid element types/values")
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://model/portfolio_reference.json"))
	for bad_value in [NAN, INF, true, "weight"]:
		var bad := reference.duplicate(true)
		bad.treasury_maturity_weights[0] = bad_value
		check(not model.call("_validate_portfolio_reference", bad).ok, "full-size reference ladder rejects malformed elements")
	for missing in ["mbs_stock_billion_usd", "source_treasury_principal_usd", "market_treasury_wam_years"]:
		var bad := reference.duplicate(true)
		bad.erase(missing)
		check(not model.call("_validate_portfolio_reference", bad).ok, "required resident source observations cannot be absent")
	var mixed := policy.duplicate(true)
	mixed.liquidity_request_pct_initial_gdp = 1000.0
	var half := {"funding_need_pct_initial_gdp":8.0,"eligible_collateral_pct_initial_gdp":1000.0,"liquidity_eligibility_pct":50.0}
	var covered: Dictionary = model.step(initial, mixed, half, params)
	check(covered.ok and covered.state.liquidity_new_need_applied_pct_initial_gdp == 4.0 and covered.state.uncovered_new_funding_pct_initial_gdp == 4.0, "partial local eligibility remains a real access shortfall despite abundant collateral/offers")
	half.collateral_haircut_pct = 100.0
	var no_value: Dictionary = model.step(initial, mixed, half, params)
	check(no_value.ok and no_value.state.outstanding_liquidity_pct_initial_gdp == 0.0, "complete collateral haircut prevents lending without rejecting the shock")
	var overflow := mixed.duplicate(true)
	overflow.asset_flow_request_pct_initial_gdp = 1e308
	var preserved := initial.duplicate(true)
	var impossible: Dictionary = model.step(initial, overflow, {"funding_need_pct_initial_gdp":1e308,"eligible_collateral_pct_initial_gdp":1e308,"liquidity_eligibility_pct":100.0}, params)
	check(not impossible.ok and initial == preserved, "genuinely unrepresentable combined asset ledger rejects without mutating caller state")
	check(abs(float(model.call("_principal_net", [1e308, 9.0, -1e308])) - 9.0) < 1e-12, "net principal settlement preserves small balances beside cancelling huge legs")

func _test_schema_rejection(initial: Dictionary, params: Dictionary) -> void:
	var policy: Dictionary = model.benchmark_policy(initial, params, "neutral")
	var unknown_state := initial.duplicate(true)
	unknown_state.future_funding_pct_initial_gdp = 1.0
	check(not model.step(unknown_state, policy, {}, params).ok, "unknown state fields cannot smuggle hidden future inputs into the ledger schema")
	var unknown_params := params.duplicate(true)
	unknown_params.asset_flow_request_limit_pct_initial_gdp = 100.0
	check(not model.initial_state(unknown_params).ok, "retired policy quotas cannot reenter the parameter schema")
	var untagged := initial.duplicate(true)
	untagged.reverse_repo_pct_initial_gdp = 1.0
	untagged.reserves_pct_initial_gdp -= 1.0
	check(not model.step(untagged, policy, {}, params).ok, "policy RRP snapshot cannot exceed its actual tagged Treasury principal")
