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
	if failures == 0:
		print("PASS: portfolio-bound saves, persistent conditional modes and exact balance-sheet replay")
	quit(1 if failures else 0)
