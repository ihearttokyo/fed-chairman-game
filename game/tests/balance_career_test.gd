extends SceneTree

const Career = preload("res://play/career.gd")
const SWITCHES := {"reinvest_principal":true, "maintain_ample_reserves":true, "sterilize_purchases":false}
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var career := Career.new()
	check(career.start("base", 17).ok, "balance career starts through the actual entry point")
	var digest_input := ""
	for source in ["economy.gd", "parameters.json", "scenarios.json", "exogenous_shocks.json", "portfolio_reference.json"]:
		digest_input += FileAccess.get_sha256("res://model/" + source)
	check(career.model_digest() == digest_input.sha256_text(), "save fingerprint includes the source-backed portfolio reference")
	var old_digest_input := ""
	for source in ["economy.gd", "parameters.json", "scenarios.json", "exogenous_shocks.json"]:
		old_digest_input += FileAccess.get_sha256("res://model/" + source)
	var legacy: Dictionary = career.payload()
	legacy.model_digest = old_digest_input.sha256_text()
	var preserved := career.encode()
	check(not career.restore(legacy).ok and career.encode() == preserved, "a portfolio-unbound save is rejected atomically")
	for switches in [
		{"reinvest_principal":false,"maintain_ample_reserves":true,"sterilize_purchases":false},
		{"reinvest_principal":true,"maintain_ample_reserves":false,"sterilize_purchases":true},
		{"reinvest_principal":false,"maintain_ample_reserves":false,"sterilize_purchases":true},
	]:
		var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold")
		policy.merge(switches, true)
		policy.asset_flow_request_pct_initial_gdp = 2.0
		var preview: Dictionary = career.forecast(policy)
		check(preview.ok, "all staged portfolio modes can be forecast")
		if not preview.ok:
			continue
		var projected: Dictionary = career.state.duplicate(true)
		for q in range(8):
			var choice: Dictionary = policy.duplicate(true) if q == 0 else career.model.benchmark_policy(projected, career.params, "hold")
			choice.merge(switches, true)
			var expected: Dictionary = career.model.step(projected, choice, career.current_briefing() if q == 0 else {}, career.params)
			check(expected.ok, "independent conditional reference remains physically feasible")
			if not expected.ok:
				break
			projected = expected.state
			check(preview.states[q] == projected, "eight-quarter forecast retains all staged switches without repeating purchases or loans")
		check(career.encode() == preserved, "portfolio forecast preserves every career byte")
		var replay := Career.new()
		check(replay.restore(bytes_to_var(career.encode())).ok, "isolated switched career replay starts")
		check(replay.advance(policy).ok, "switched decision commits")
		var loaded := Career.new()
		check(loaded.restore(bytes_to_var(replay.encode())).ok and loaded.state == replay.state and loaded.decisions == replay.decisions, "all explicit portfolio switches survive exact save replay")
	var omitted: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold")
	var explicit_defaults: Dictionary = omitted.duplicate(true)
	explicit_defaults.merge(SWITCHES, true)
	check(career.forecast(omitted) == career.forecast(explicit_defaults), "legacy omitted switches have precisely the documented defaults")
	_test_fractional_refinancing()
	_test_accepted_fractional_path()
	if failures == 0:
		print("PASS: portfolio-bound saves, persistent conditional modes and exact balance-sheet replay")
	quit(1 if failures else 0)

# Real public career transitions, not a manually fabricated outstanding loan.
func _test_fractional_refinancing() -> void:
	for maintenance in [false, true]:
		var c := Career.new()
		check(c.start("base", 417).ok, "fractional funding career starts")
		c.shocks[0] = {"funding_need_pct_initial_gdp":1.98, "eligible_collateral_pct_initial_gdp":10.0, "liquidity_eligibility_pct":100.0}
		var p: Dictionary = c.model.benchmark_policy(c.state, c.params, "hold")
		p.maintain_ample_reserves = maintenance
		p.liquidity_request_pct_initial_gdp = 1.98
		var originated: Dictionary = c.advance(p)
		check(originated.ok, "first native decision originates actual principal")
		if not originated.ok:
			continue
		c.shocks[1] = {"funding_need_pct_initial_gdp":0.1, "refinancing_need_pct_initial_gdp":1.98, "eligible_collateral_pct_initial_gdp":10.0, "liquidity_eligibility_pct":100.0}
		p = c.model.benchmark_policy(c.state, c.params, "hold")
		p.maintain_ample_reserves = maintenance
		p.liquidity_request_pct_initial_gdp = 2.08
		var frozen := var_to_bytes([c.payload(), c.state, c.history, c.decisions, c.shocks])
		var preview := c.forecast(p)
		check(preview.ok and var_to_bytes([c.payload(), c.state, c.history, c.decisions, c.shocks]) == frozen, "fractional refinancing previews without mutation")
		var settled: Dictionary = c.advance(p)
		check(settled.ok, "fully covered fractional refinancing cannot freeze adoption")
		if not settled.ok:
			continue
		check(preview.ok and var_to_bytes(preview.states[0]) == var_to_bytes(c.state), "first preview is byte-exact with actual fractional settlement")
		check(c.state.liquidity_new_need_applied_pct_initial_gdp == 0.1, "fresh advance does not exceed requested new cash")
		check(c.state.liquidity_refinancing_applied_pct_initial_gdp == 1.98, "renewal principal is not silently reduced")
		check(c.state.uncovered_new_funding_pct_initial_gdp == 0.0 and c.state.uncovered_refinancing_pct_initial_gdp == 0.0, "fully paid claims have zero unpaid balances")
		check(c.state.liquidity_applied_pct_initial_gdp <= 2.08, "gross advances stay within the offered total")
		check(abs(c.state.principal_ledger_error_pct_initial_gdp) < 1e-10, "fractional funding preserves the Fed ledger")
		var restored := Career.new()
		check(restored.restore(c.payload()).ok and restored.encode() == c.encode() and var_to_bytes([restored.state, restored.history, restored.decisions, restored.shocks]) == var_to_bytes([c.state, c.history, c.decisions, c.shocks]), "fractional funding survives exact full-history save replay")

func _test_accepted_fractional_path() -> void:
	var c := Career.new()
	check(c.start("base", 417).ok, "near-full eligibility career starts")
	c.shocks[0] = {"funding_need_pct_initial_gdp":0.28, "eligible_collateral_pct_initial_gdp":10.0, "liquidity_eligibility_pct":100.0}
	var p: Dictionary = c.model.benchmark_policy(c.state, c.params, "hold")
	p.maintain_ample_reserves = false
	p.liquidity_request_pct_initial_gdp = 0.28
	check(c.advance(p).ok, "near-full eligibility originates real principal")
	c.shocks[1] = {"funding_need_pct_initial_gdp":0.01, "refinancing_need_pct_initial_gdp":0.28, "eligible_collateral_pct_initial_gdp":10.0, "liquidity_eligibility_pct":99.9999999999999}
	var share: float = float(c.shocks[1].liquidity_eligibility_pct) / 100.0
	p = c.model.benchmark_policy(c.state, c.params, "hold")
	p.maintain_ample_reserves = false
	p.liquidity_request_pct_initial_gdp = 0.29
	var old_local: float = minf(0.29, 0.28 * share + 0.01 * share)
	var old_renewal := minf(old_local, 0.28 * share)
	var old_new := old_local - old_renewal
	var old_uncovered := (0.01 - old_new) + (0.28 - old_renewal)
	check(old_new > 0.01 and old_uncovered >= 0.0, "fixture distinguishes a previously accepted aggregate from rejected negative aggregate")
	var result: Dictionary = c.advance(p)
	check(result.ok, "previously accepted near-full eligibility remains accepted")
	if result.ok:
		check(c.state.liquidity_new_need_applied_pct_initial_gdp == old_new and c.state.uncovered_funding_pct_initial_gdp == old_uncovered, "previously accepted allocation bytes are not silently rewritten")
	var huge := Career.new()
	check(huge.start("base", 417).ok, "unrepresentable fresh-leg fixture starts")
	var principal := 9007199254740992.0
	huge.shocks[0] = {"funding_need_pct_initial_gdp":principal, "eligible_collateral_pct_initial_gdp":principal * 2.0, "liquidity_eligibility_pct":100.0}
	p = huge.model.benchmark_policy(huge.state, huge.params, "hold")
	p.maintain_ample_reserves = false
	p.liquidity_request_pct_initial_gdp = principal
	var opened: Dictionary = huge.advance(p)
	check(opened.ok, "large finite loan originates without arbitrary policy ceiling")
	if not opened.ok:
		return
	huge.shocks[1] = {"funding_need_pct_initial_gdp":1.5, "refinancing_need_pct_initial_gdp":principal, "eligible_collateral_pct_initial_gdp":principal * 2.0, "liquidity_eligibility_pct":100.0}
	p = huge.model.benchmark_policy(huge.state, huge.params, "hold")
	p.maintain_ample_reserves = false
	p.liquidity_request_pct_initial_gdp = principal + 2.0
	var frozen := var_to_bytes([huge.payload(), huge.state, huge.history, huge.decisions, huge.shocks])
	var refused: Dictionary = huge.advance(p)
	check(not refused.ok and refused.get("error", "").contains("unrepresentable fractional refinancing"), "cannot report1.5 paid while booking2.0 fresh principal")
	check(var_to_bytes([huge.payload(), huge.state, huge.history, huge.decisions, huge.shocks]) == frozen, "unrepresentable fresh-leg refusal is atomic")
