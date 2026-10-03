extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	check(game.assets.allow_greater and game.assets.allow_lesser and game.liquidity.allow_greater, "asset and liquidity fields have no arbitrary offer ceilings")
	check(not game.liquidity.allow_lesser and game.liquidity.min_value == 0.0, "lending offers remain nonnegative")
	var found := {}
	for property in game.get_property_list():
		found[property.name] = true
	var ready := true
	for field in ["reinvestment", "reserve_maintenance", "sterilization"]:
		if not found.has(field):
			check(false, "cockpit exposes " + field + " as a typed keyboard control")
			ready = false
	if not ready:
		game.free()
		quit(1)
		return
	for control in [game.reinvestment, game.reserve_maintenance, game.sterilization]:
		check(control is CheckBox and control.focus_mode == Control.FOCUS_ALL and game._keyboard_focus_order().has(control), "each portfolio mode participates in the actual keyboard focus cycle")
		check(not control.accessibility_name.is_empty() and not control.tooltip_text.is_empty(), "each mode has immediate explanatory and assistive text")
	check(game.reinvestment.button_pressed and game.reserve_maintenance.button_pressed and not game.sterilization.button_pressed, "initial portfolio modes match documented defaults")
	game._start_career("base", 17)
	for q in range(4):
		check(game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "neutral")).ok, "current-GDP fixture advances the actual economy")
	game._refresh(true)
	var n: float = game.career.model.nominal_gdp_ratio(game.career.state)
	check(abs(n - 1.0) > 0.001, "denominator fixture really differs from initial GDP")
	game.career.shocks[4].funding_need_pct_initial_gdp = 8.0 * n
	game.career.shocks[4].eligible_collateral_pct_initial_gdp = 2.0 * n
	game.career.shocks[4].liquidity_eligibility_pct = 100.0
	game.assets.value = 150.0
	game.liquidity.value = 400.0
	game.reinvestment.button_pressed = false
	game.reserve_maintenance.button_pressed = true
	game.sterilization.button_pressed = true
	var policy: Dictionary = game._policy()
	check(is_equal_approx(policy.asset_flow_request_pct_initial_gdp, 150.0 * n) and is_equal_approx(policy.liquidity_request_pct_initial_gdp, 400.0 * n), "displayed current-GDP offers convert exactly once to the engine denominator")
	check(not policy.reinvest_principal and policy.maintain_ample_reserves and policy.sterilize_purchases, "staged switches reach the actual policy")
	var preserved: PackedByteArray = game.career.encode()
	var selected: Dictionary = game.career.forecast(policy)
	game._preview()
	check(selected.ok and game.career.encode() == preserved, "large sterilized preview remains feasible and read-only")
	if selected.ok:
		var first: Dictionary = selected.states[0]
		var applied: String = "assets %+.2f" % (first.asset_flow_applied_pct_initial_gdp / n)
		check(game.forecast_label.text.contains(applied), "applied current-meeting amounts use decision GDP rather than ending GDP")
		check(game.forecast_label.text.contains("RRP") and game.forecast_label.text.contains("RMP"), "main-screen preview separates sterilization and reserve-maintenance flows")
		var report: String = game._decision_briefing()
		check(report.contains("Lending value") and report.contains("Eligible local demand") and report.contains("Binding constraints"), "decision report exposes demand, lending value and actual binding constraints")
		var held: Dictionary = game.career.forecast(game.career.model.benchmark_policy(game.career.state, game.career.params, "hold"))
		check(first.uncovered_funding_pct_initial_gdp > 0.0 and held.ok, "comparison denominator fixture really has positive uncovered funding")
		if held.ok:
			check(report.contains("Uncovered funding %.2f vs %.2f" % [first.uncovered_funding_pct_initial_gdp / n, held.states[0].uncovered_funding_pct_initial_gdp / n]), "transmission comparison consistently reports meeting-current-GDP funding on both paths")
		game._advance()
		check(game.career.state == first, "adoption commits the exact preview without converting its offers again")
		check(not game.reinvestment.button_pressed and game.reserve_maintenance.button_pressed and game.sterilization.button_pressed, "portfolio modes persist after adoption")
		var ending_n: float = game.career.model.nominal_gdp_ratio(game.career.state)
		check(game.case_detail.text.contains("Holdings %.1f%%" % (first.asset_stock_pct_initial_gdp / ending_n)), "stock display uses observed ending nominal GDP")
		check(game.assets.value == 0.0 and game.liquidity.value == 0.0, "one-time offers reset without silently resetting portfolio modes")
	var saved: PackedByteArray = game.career.encode()
	game._help()
	var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	var help: String = dialog.get_child(0).text.to_lower()
	for concept in ["current annual gdp", "reinvestment", "matur", "reverse repo", "overnight", "collateral", "steriliz"]:
		check(help.contains(concept), "concise guide explains " + concept)
	check(not help.contains("stock capacity") and not help.contains("quarterly capacity"), "guide no longer describes invented asset or lending caps")
	dialog.get_ok_button().pressed.emit()
	await process_frame
	check(game.career.encode() == saved, "reading balance-sheet help leaves the unsaved career intact")
	game._start_career("base", 17)
	check(game.reinvestment.button_pressed and game.reserve_maintenance.button_pressed and not game.sterilization.button_pressed, "explicit new-career reset restores initial portfolio defaults")
	game.free()
	if failures == 0:
		print("PASS: unrestricted current-GDP offers, keyboard portfolio modes, exact adoption and concise explanations")
	quit(1 if failures else 0)
