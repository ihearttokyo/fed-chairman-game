extends SceneTree
const Routine = preload("res://play/routine_follow_up.gd")
class NoForecastMain:
	extends "res://play/main.gd"
	func _preview() -> void:
		pass
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = NoForecastMain.new()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._start_career("base", 1)
	game.assets.value = 0.1
	game.liquidity.value = 0.05
	game.reinvestment.button_pressed = false
	var tools: Dictionary = game._policy()
	var original: Dictionary = game.career.state.duplicate(true)
	game._staff_rule()
	var first: Dictionary = game._policy()
	for key in ["asset_flow_request_pct_initial_gdp", "liquidity_request_pct_initial_gdp", "reinvest_principal", "maintain_ample_reserves", "sterilize_purchases"]:
		check(first[key] == tools[key], "actual shortcut preserves manual tool " + key)
	for hidden in ["r_star_pct", "expected_short_inflation_pct"]:
		game.career.state = original.duplicate(true)
		game.career.state[hidden] += 1.0
		check(game.career.model._validate_state(game.career.state, game.career.params).ok, "shortcut observer twin valid")
		var before := var_to_bytes(game.career.state)
		game._staff_rule()
		check(game.rate.value == first.policy_rate_request_pct, "production staff estimate excludes hidden " + hidden)
		check(var_to_bytes(game.career.state) == before, "shortcut staging preserves native state")
	game.career.state = original.duplicate(true)
	game.assets.value = 0.0
	game.liquidity.value = 0.0
	game._staff_rule()
	var attended: Dictionary = game._policy()
	check(game.career.advance(attended).ok, "attended native adoption succeeds")
	var state: Dictionary = game.career.state.duplicate(true)
	var routine := Routine.new()
	check(routine.arm(state, game.career.params, attended, 1).ok, "real routine arms")
	var quiet := {"demand_shock_pct":0.0,"supply_innovation_pct":0.0,"r_star_change_pct":0.0}
	var next: Dictionary = routine.proposal(state, quiet, {}, game.career.params, 1, 2, 2)
	check(next.ok, "quiet current production proposal permitted")
	check(next.policy.liquidity_request_pct_initial_gdp == 0 and next.policy.asset_flow_request_pct_initial_gdp == 0, "actual routine offers no new one-shot tools")
	check(not next.policy.reinvest_principal, "actual routine retains explicit false switch")
	var baseline: float = next.policy.policy_rate_request_pct
	for hidden in ["r_star_pct", "expected_short_inflation_pct"]:
		routine.arm(state, game.career.params, attended, 1)
		var twin := state.duplicate(true)
		twin[hidden] += 1.0
		var response: Dictionary = routine.proposal(twin, quiet, {}, game.career.params, 1, 2, 2)
		check(not response.policy.is_empty() and response.policy.policy_rate_request_pct == baseline, "routine proposal excludes hidden " + hidden)
		check(not "BENCHMARK_DRIFT" in response.reasons, "hidden change cannot trigger staff-rate drift return")
	routine.arm(state, game.career.params, attended, 1)
	var need := quiet.duplicate(true)
	need.funding_need_pct_initial_gdp = 0.1
	var returned: Dictionary = routine.proposal(state, need, {}, game.career.params, 1, 2, 2)
	check(not returned.ok and "FUNDING_NEED" in returned.reasons and not routine.active, "actual funding need returns control instead of injecting automatic loans")
	game.music.free()
	game.queue_free()
	await process_frame
	var deadline := Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < deadline:
		await process_frame
	print("%s: production advice contract %d checks, %d failures; public advice integrated; full-information diagnostic remains separate" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
