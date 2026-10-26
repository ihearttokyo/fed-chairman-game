extends SceneTree
var failures := 0
class CountCareer:
	extends "res://play/career.gd"
	var forecast_calls := 0
	var refuse_preview := false
	func forecast(policy: Dictionary, follow_guidance: bool = false) -> Dictionary:
		forecast_calls += 1
		if refuse_preview:
			return {"ok":false,"error":"Synthetic failed-preview fixture"}
		return super.forecast(policy, follow_guidance)
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func texts(node: Node) -> String:
	var output := str(node.text) if node is Label else ""
	for child in node.get_children():
		output += "\n" + texts(child)
	return output
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.career = CountCareer.new()
	root.add_child(game)
	await process_frame
	await process_frame
	game._start_career("base",417)
	check(not game.funding_plan.visible, "quiet zero offer adds no dashboard clutter")
	check(game._policy_error("unrepresentable fractional refinancing advance").contains("Reduce the offer"), "unrepresentable loan booking gives an actionable numerical limit, not a spurious freeze")
	game.career.shocks[0] = {"funding_need_pct_initial_gdp":1.98,"eligible_collateral_pct_initial_gdp":10.0,"liquidity_eligibility_pct":100.0}
	var p: Dictionary = game.career.model.benchmark_policy(game.career.state,game.career.params,"hold")
	p.liquidity_request_pct_initial_gdp = 1.98
	check(game._commit_policy(p).ok, "public native transition originates the actual loan")
	game.career.shocks[1] = {"funding_need_pct_initial_gdp":0.1,"refinancing_need_pct_initial_gdp":1.98,"eligible_collateral_pct_initial_gdp":10.0,"liquidity_eligibility_pct":100.0}
	game._refresh(true,false)
	check(not game.funding_plan.visible, "suppressed preview clears the previous plan")
	game.loading_controls = true
	game.liquidity.value = 3.0
	game.loading_controls = false
	var before := var_to_bytes([game.career.payload(),game.career.state,game.career.history,game.career.shocks])
	game.career.forecast_calls = 0
	game._preview()
	check(game.career.forecast_calls == 1, "graphic consumes the existing forecast, never runs another")
	check(game.funding_plan.visible and game.funding_plan.snapshot.get("ok",false), "valid current first-quarter allocation is shown")
	check(texts(game.funding_plan).contains("Renew") and texts(game.funding_plan).contains("Fresh cash"), "renewal and actual new cash have distinct visible labels")
	check(var_to_bytes([game.career.payload(),game.career.state,game.career.history,game.career.shocks]) == before, "plan rendering is fully read-only")
	game.career.refuse_preview = true
	game._preview()
	check(not game.funding_plan.visible and not game.funding_plan.snapshot.get("ok",false), "failed preview cannot leave a stale valid plan")
	game.career.refuse_preview = false
	game._preview()
	game._advance()
	check(game.career.decisions.size() == 2 and game.career.state.uncovered_funding_pct_initial_gdp == 0.0, "actual Main adoption crosses the previously frozen fractional refinancing")
	check(game.career.state.liquidity_new_need_applied_pct_initial_gdp == 0.1 and game.career.state.liquidity_refinancing_applied_pct_initial_gdp == 1.98, "adopted loan split is exactly the advertised native allocation")
	check(game.consequence.text.contains("local cash 0.10") and game.consequence.text.contains("renewed 1.96") and not game.consequence.text.contains("repaid"), "normal outcome does not label cashless renewal as fresh cash or cash repayment")
	game._start_career(game.WORKOUT_CASE,417)
	game.liquidity.value = 1.0
	game._preview()
	check(game.funding_plan.visible, "optional bank workout uses its coupled preview, not a separate allocator")
	game._start_career("base",417)
	check(not game.funding_plan.visible, "returning to a quiet normal career clears the workout plan")
	if failures == 0:
		print("PASS: Main lending plan reuses one forecast, native fractional adoption, no mutation, stale clearing and mode transitions")
	await game._quit_app(1 if failures else 0)
