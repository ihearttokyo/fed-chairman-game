extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func check_reserve_recovery(game: Control) -> void:
	game._start_career("lower_bound_slump", 1)
	var failure: Dictionary = {}
	for q in range(240):
		var policy: Dictionary = game.career.model.benchmark_policy(game.career.state, game.career.params, "feedback")
		policy.maintain_ample_reserves = false
		var prior: PackedByteArray = game.career.encode()
		var result: Dictionary = game.career.advance(policy)
		if not result.ok:
			failure = result
			check(game.career.encode() == prior, "native reserve exhaustion rejects a quarter atomically")
			break
	check(not failure.is_empty() and failure.get("error", "") == "infeasible mandatory settlement after simultaneous principal netting", "real zero-rate slump staff path with reserve maintenance off reproduces settlement rejection")
	if failure.is_empty():
		return
	print("RESERVE_RECOVERY_FIXTURE: Q", game.career.state.quarter_index, " reserves=", game.career.state.reserves_pct_initial_gdp)
	game._refresh(true)
	game._staff_rule()
	check(not game.reserve_maintenance.button_pressed, "staff rate rule does not silently change reserve policy")
	var preserved: PackedByteArray = game.career.encode()
	var staged: Dictionary = game._policy().duplicate(true)
	for message in [game.forecast_label.text, game._decision_briefing()]:
		check(message.contains("reserves") and message.contains("Maintain ample reserves"), "failed preview and comparison explain the constraint and a concrete corrective control")
	game._advance()
	check(game.status_label.text.contains("Maintain ample reserves") and game.status_label.text.contains("Last valid quarter retained"), "adoption rejection explains the recovery without implying a crash")
	check(game.career.encode() == preserved and game._policy() == staged, "failed UI adoption retains all valid history and staged controls")
	if game.has_method("_policy_error"):
		check(game.call("_policy_error", "unrelated diagnostic") == "unrelated diagnostic", "unrecognized errors keep their exact diagnostic")
	else:
		check(false, "policy error presentation is shared by its callers")
	game.reserve_maintenance.button_pressed = true
	var corrected: Dictionary = game.career.forecast(game._policy())
	check(corrected.ok and game.career.encode() == preserved, "explicit reserve maintenance restores a feasible read-only preview from the same state")
	game._advance()
	check(game.career.state.quarter_index == bytes_to_var(preserved).decisions.size() + 1, "corrected policy advances exactly once instead of resetting or discarding the career")
	if corrected.ok:
		check(game.career.state == corrected.states[0], "reserve recovery adopts the exact corrected preview")

func check_small_funding_readouts(game: Control) -> void:
	check(game.rate.step == 0.01 and game.guidance.step == 0.01, "funding precision preserves the 1bp rate and guidance grid")
	check(game.liquidity.step == 0.0001 and game.liquidity.custom_arrow_step == 0.25, "small lending quotes are enterable without changing convenience arrows")
	game._start_career("base", 17)
	for q in range(4):
		check(game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "neutral")).ok, "small-funding fixture advances the actual economy")
	var n: float = game.career.model.nominal_gdp_ratio(game.career.state)
	check(abs(n - 1.0) > 0.001, "small-funding fixture uses nonunit current GDP")
	var shock: Dictionary = game.career.shocks[4]
	shock.refinancing_need_pct_initial_gdp = 0.0
	shock.eligible_collateral_pct_initial_gdp = 0.004 * n
	shock.collateral_haircut_pct = 0.0
	shock.liquidity_eligibility_pct = 100.0
	for pair in [[0.0, "0.00"], [0.00001, "<0.0001"], [0.0001, "0.0001"], [0.004, "0.0040"], [0.01, "0.01"], [0.0123, "0.01"]]:
		shock.funding_need_pct_initial_gdp = pair[0] * n
		game._refresh(true)
		var before: PackedByteArray = game.career.encode()
		game._preview()
		check(game.dispatch_details_text.contains("Funding need %s (new)" % pair[1]), "dispatch details preserve small positive funding rather than round it to zero: " + str(pair[0]))
		check(game.briefing.text.contains("Funding (%% current GDP): new %s · refi need 0.00 · eligible need %s · secured value 0.0040" % [pair[1], pair[1]]), "compact funding essentials preserve the actual small amount, eligibility and adjusted collateral in current GDP: " + str(pair[0]))
		check(game.forecast_label.text.contains("uncovered funding %s" % pair[1]), "preview distinguishes small uncovered funding from zero: " + str(pair[0]))
		check(game._decision_briefing().contains("Uncovered funding %s vs %s" % [pair[1], pair[1]]), "comparison preserves small funding on both paths: " + str(pair[0]))
		check(game.career.encode() == before, "small-funding displays and comparisons remain read-only")
	shock.funding_need_pct_initial_gdp = 0.004 * n
	game._refresh(true)
	game.liquidity.get_line_edit().text = "0.004"
	game._apply_policy_inputs()
	check(is_equal_approx(game.liquidity.value, 0.004), "typed small lending quote does not snap to zero")
	var policy: Dictionary = game._policy()
	check(is_equal_approx(policy.liquidity_request_pct_initial_gdp, 0.004 * n), "small quote converts current GDP exactly once")
	var before: PackedByteArray = game.career.encode()
	var forecast: Dictionary = game.career.forecast(policy)
	game._preview()
	check(forecast.ok and game.career.encode() == before, "small lending preview is feasible and read-only")
	check(game.forecast_label.text.contains("lending 0.0040") and game.forecast_label.text.contains("uncovered funding 0.00\n"), "preview shows the accepted small loan and actual zero residual")
	var report: String = game._decision_briefing()
	for fragment in ["Requested lending 0.0040", "Applied lending 0.0040", "Lending value 0.0040", "Eligible local demand 0.0040", "new local lending 0.0040"]:
		check(report.contains(fragment), "comparison retains " + fragment)
	if forecast.ok:
		game._advance()
		check(game.career.state == forecast.states[0] and game.career.decisions.size() == 5, "small quote adopts the exact preview once")
		check(game.consequence.text.contains("lent 0.0040"), "outcome retains the small loan")
		check(game.dispatch_details_text.contains("Last decision: lending 0.0040"), "next dispatch details retain the small prior loan")
		check(not game.case_detail.text.contains("Loans 0.00%"), "ending stock does not present a small positive loan as zero")
		game._journal()
		var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
		check(dialog.get_child(0).text.contains("loans 0.0040"), "journal retains the small loan at its decision GDP")
		dialog.get_ok_button().pressed.emit()
		await process_frame

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
		await game._quit_app(1)
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
	var guide = dialog.get_child(0)
	guide.topics.select(3)
	guide.topics.item_selected.emit(3)
	await process_frame
	await process_frame
	var help: String = guide.body.text.to_lower()
	check(guide.topics.selected == 3 and guide.body.accessibility_description == guide.body.text, "actual Assets/reserves/liquidity help topic exposes its current complete native assistive page")
	for concept in ["current annual gdp", "reinvestment", "matur", "reverse repo", "overnight", "collateral", "steriliz"]:
		check(help.contains(concept), "concise guide explains " + concept)
	var complete_help: String = guide.reference_text.to_lower()
	check(not complete_help.contains("stock capacity") and not complete_help.contains("quarterly capacity"), "complete guide no longer describes invented asset or lending caps")
	dialog.get_ok_button().pressed.emit()
	await process_frame
	check(game.career.encode() == saved, "reading balance-sheet help leaves the unsaved career intact")
	game._start_career("base", 17)
	check(game.reinvestment.button_pressed and game.reserve_maintenance.button_pressed and not game.sterilization.button_pressed, "explicit new-career reset restores initial portfolio defaults")
	await check_small_funding_readouts(game)
	await check_reserve_recovery(game)
	if failures == 0:
		print("PASS: unrestricted current-GDP offers, keyboard portfolio modes, exact adoption and concise explanations")
	await game._quit_app(1 if failures else 0)
