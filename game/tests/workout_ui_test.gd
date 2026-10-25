extends SceneTree
var checks := 0
var failures := 0
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.save_path = "user://workout-existing-normal-career.bin"
	var normal: PackedByteArray = game.career.encode()
	check(game.career.save_to(game.save_path).ok, "Private pre-existing normal save fixture is created before laboratory entry")
	var save_existed := FileAccess.file_exists(game.save_path)
	var save_before := FileAccess.get_file_as_bytes(game.save_path) if FileAccess.file_exists(game.save_path) else PackedByteArray()
	game._new_dialog()
	var new_dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	var workout_index: int = game.scenario.item_count - 1
	check(game.scenario.get_item_metadata(workout_index) == game.WORKOUT_CASE, "Actual New menu exposes the optional episode")
	game.scenario.select(workout_index)
	game.seed_input.value = 417
	new_dialog.get_ok_button().pressed.emit()
	await process_frame
	await process_frame
	check(game._is_workout() and game._active_horizon() == 8, "Main enters the eight-meeting optional mode")
	check(game.normal_storage_buttons.all(func(button): return button.disabled) and not game.city_panel.visible and not game.mandate_label.visible, "Laboratory hides unrelated city/scoring and disables normal storage affordances")
	check(game.workout_panel.visible and game.workout_board.snapshot.ok, "Main shows valid actual bank data")
	check(game._keyboard_focus_order().has(game.workout_board.details_button), "Bank details participates in the keyboard focus cycle")
	check(game.follow_up_toggle.disabled and not game.follow_up_toggle.button_pressed, "Laboratory cannot silently run automatic follow-up")
	game.career.shocks[0].demand_shock_pct = 0.75
	game.career.shocks[0].supply_innovation_pct = 0.5
	game._refresh(false, false)
	check(game.dispatch_details_text.contains("+0.75") and game.dispatch_details_text.contains("+0.50"), "Bank current-condition Details retains active macro shocks")
	var frozen: PackedByteArray = game.career.encode()
	game._save()
	game._load()
	check(game.career.encode() == frozen and FileAccess.file_exists(game.save_path) == save_existed and (FileAccess.get_file_as_bytes(game.save_path) if save_existed else PackedByteArray()) == save_before, "Laboratory Save/Load cannot touch normal career slots")
	var quote: Dictionary = game.career.model.benchmark_policy(game.career.state, game.career.params, "hold")
	quote.liquidity_request_pct_initial_gdp = 2.4
	game.loading_controls = true
	game.rate.value = quote.policy_rate_request_pct
	game.guidance.value = quote.guidance_rate_pct
	game.liquidity.value = 2.4
	game.loading_controls = false
	var brief: String = game._decision_briefing()
	check(brief.contains("BANK WORKOUT") and game.comparison_series.size() == 9 and game.career.encode() == frozen, "Comparison uses coupled paths without adoption")
	game._advance()
	check(game.consequence.text.contains("Cash repaid") and game.consequence.text.contains("Renewed") and not game.consequence.text.contains("Funding (% meeting GDP)"), "Workout footer separates actual cash repayment from cashless contract renewal")
	check(game.career.decisions.size() == 1 and game.workout_board.snapshot.ok, "Main adopts exactly one coupled meeting and refreshes its board")
	check(game.career.state.outstanding_liquidity_pct_initial_gdp == game.career.bank_state.central_bank_loan, "Main's Fed loan stock equals actual bank debt")
	for q in range(1, 8):
		game._advance()
	check(game.career.decisions.size() == 8 and game.decision_button.disabled and game.decision_button.text == "Episode complete", "Eight meetings disable adoption without hanging")
	check(game.forecast_label.text.contains("Episode complete") and game.quarter_label.text.contains("EPISODE COMPLETE"), "Terminal feedback describes the episode, not a sixty-year career")
	frozen = game.career.encode()
	game._advance()
	check(game.career.encode() == frozen, "Accelerator cannot advance a ninth meeting")
	var original_size := root.size
	var scale := maxf(1.0, DisplayServer.screen_get_scale(root.current_screen))
	root.size = Vector2i(Vector2(1050, 650) * scale)
	for frame in range(6): await process_frame
	game._resize_layout()
	check(not game.body_layout.vertical and game.chart_layout.vertical, "At1050 logical points the bank and cockpit stay side by side while charts stack locally")
	for input in [game.rate, game.guidance, game.liquidity]:
		check(input.get_global_rect().end.x <= root.get_visible_rect().end.x + 0.5, "Every policy field stays inside the1050-point viewport")
		print("WORKOUT_LAYOUT_GEOMETRY input=", input.get_global_rect(), " viewport=", root.get_visible_rect(), " left_min=", game.chart_layout.get_parent().get_combined_minimum_size(), " policy_min=", game.policy_panel.get_combined_minimum_size())
	root.size = Vector2i(Vector2(700, 650) * scale)
	for frame in range(6): await process_frame
	game._refresh(false, false)
	check(game.body_layout.vertical and game.chart_layout.get_parent().custom_minimum_size.x == 0.0, "Narrow laboratory refresh does not restore an overflowing left minimum")
	game._help()
	var help_dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	var guide = help_dialog.get_child(0)
	check(guide.topics.get_item_text(guide.topics.selected) == "Bank workout" and not guide.body.text.contains("Bank workout\n\nBank workout"), "Episode Help opens on one nonduplicated relevant heading")
	help_dialog.get_ok_button().pressed.emit()
	await process_frame
	game._journal()
	var journal: AcceptDialog = game.get_child(game.get_child_count() - 1)
	check(journal.get_child(0).text.contains("Bank ledger · % initial GDP") and journal.get_child(0).text.contains("cash repayment"), "Journal retains an inspectable actual-cash and renewal ledger")
	journal.get_ok_button().pressed.emit()
	await process_frame
	game._start_career("policy_career", 1)
	check(not game._is_workout() and game._active_horizon() == 240 and not game.workout_panel.visible, "Normal career mode and horizon restore")
	check(game.city_panel.visible and game.mandate_label.visible and game.normal_storage_buttons.all(func(button): return not button.disabled), "Normal city/scoring/storage affordances restore")
	check(game.body_layout.vertical and game.chart_layout.get_parent().custom_minimum_size.x == 0.0, "Narrow normal mode preserves its original stacked minimum after laboratory exit")
	root.size = original_size
	check(game.career.encode() == normal, "Returning to the same seed restores the unchanged normal initial payload")
	check((FileAccess.get_file_as_bytes(game.save_path) if FileAccess.file_exists(game.save_path) else PackedByteArray()) == save_before, "Mode transitions preserve the save slot")
	if failures == 0:
		print("PASS: bank workout Main integration %d checks (headless; not live usability evidence)" % checks)
	await game._quit_app(1 if failures else 0)
