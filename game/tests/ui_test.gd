extends SceneTree
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
func _initialize() -> void:
	call_deferred("run")
func check_cancel_window(dialog: AcceptDialog) -> void:
	check(dialog.visible, "cancel keeps the window registered through deferred accessibility focus")
func check_custom_guidance(game: Control) -> void:
	check(game.commitment.item_count == 3, "player can choose custom conditional guidance")
	if game.commitment.item_count != 3:
		return
	game._start_career("base", 417)
	game.career.shocks[0] = {"demand_shock_pct": 1.2}
	game.rate.value = 3.5
	game.guidance.value = 3.65
	var preset: Dictionary = game.career.forecast(game._policy())
	game.commitment.select(2)
	game.commitment.item_selected.emit(2)
	check(game.custom_guidance.visible, "custom conditions are visible only when selected")
	check(game.inflation_response.min_value == -game.career.params.guidance_sensitivity_limit and game.activity_response.max_value == game.career.params.guidance_sensitivity_limit, "custom conditions use model-defined bounds")
	game.inflation_response.value = 1.0
	game.activity_response.value = -0.25
	var preserved: PackedByteArray = game.career.encode()
	var preview: Dictionary = game.career.forecast(game._policy())
	check(preview.states[0].credibility == preset.states[0].credibility and preview.states[0].long_yield_pct == preset.states[0].long_yield_pct, "new conditions do not invent an immediate credibility or market-pricing bonus")
	check(game.career.encode() == preserved, "custom preview cannot change the career")
	game._advance()
	check(game.career.decisions[0].guidance_inflation_sensitivity == 1.0 and game.career.decisions[0].guidance_output_gap_sensitivity == -0.25, "custom coefficients reach the committed policy")
	check(game.commitment.selected == 2 and game._policy().guidance_output_gap_sensitivity == -0.25, "custom conditions persist after adoption")
	var replay = game.career.get_script().new()
	check(replay.restore(bytes_to_var(game.career.encode())).ok and replay.state == game.career.state, "custom communication survives lossless replay")
	var s: Dictionary = game.career.state
	var promise: float = s.guidance_rate_pct + s.guidance_inflation_sensitivity * (s.four_quarter_inflation_pct - s.guidance_reference_inflation_pct) + s.guidance_output_gap_sensitivity * (s.output_gap_pct - s.guidance_reference_output_gap_pct)
	game.rate.value = promise
	game.guidance.value = 4.0
	var follows: Dictionary = game.career.forecast(game._policy())
	var report: String = game._decision_briefing()
	check(report.contains("Adjusted prior promise %.3f%%" % promise), "comparison reveals the previous condition-adjusted promise")
	check(report.contains("Projected follow-through %.1f / 100" % (100 * follows.states[0].guidance_followthrough_score)), "comparison uses the actual model's projected follow-through")
	check(report.contains("new announcement does not erase"), "comparison distinguishes new communication from the previous obligation")
	game.rate.value = s.guidance_rate_pct
	var breaks: Dictionary = game.career.forecast(game._policy())
	check(follows.states[0].guidance_followthrough_score > breaks.states[0].guidance_followthrough_score and follows.states[0].credibility > breaks.states[0].credibility, "honoring the custom condition improves subsequent follow-through and credibility")
	game.commitment.select(1)
	game.commitment.item_selected.emit(1)
	check(not game.custom_guidance.visible and game._policy().guidance_inflation_sensitivity == 0.0 and game._policy().guidance_output_gap_sensitivity == 0.0, "firm preset cannot leak custom conditions")
	game.commitment.select(0)
	game.commitment.item_selected.emit(0)
	check(game._policy().guidance_inflation_sensitivity == game.career.params.policy_inflation_response and game._policy().guidance_output_gap_sensitivity == game.career.params.policy_output_gap_response, "data-dependent preset keeps its original coefficients")
	game.assets.value = 1.25
	game.liquidity.value = 2.0
	game._staff_rule()
	check(game.commitment.selected == 0 and game.assets.value == 1.25 and game.liquidity.value == 2.0, "staff selection restores its guidance rule without changing other tools")
	game._start_career("base", 417)
	check(game.commitment.selected == 0 and game.inflation_response.value == game.career.params.policy_inflation_response, "new career restores known guidance defaults")
	game.commitment.select(1)
	game.commitment.item_selected.emit(1)
	game.guidance.value = 15.0
	game._advance()
	check(game._decision_briefing().contains("outside this meeting's feasible rate range"), "comparison warns when an earlier pledge cannot be delivered")
	game._start_career("supply_shock", 1)
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	check_custom_guidance(game)
	var compare_button: Button
	for button in game.find_children("*", "Button", true, false):
		if button.text == "Compare policy paths":
			compare_button = button
	check(compare_button != null, "player can compare selected policy with holding policy")
	if compare_button != null:
		game._start_career("funding_stress", 11)
		for q in range(4):
			game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "hold"))
		game._refresh(true)
		game.rate.value = 8.0
		game.guidance.value = 8.0
		game.assets.value = 2.0
		game.liquidity.value = 5.0
		var preserved: Dictionary = game.career.payload()
		var selected: Dictionary = game.career.forecast(game._policy())
		var held: Dictionary = game.career.forecast(game.career.model.benchmark_policy(game.career.state, game.career.params, "hold"))
		var report: String = game._decision_briefing()
		check(report.contains("Requested rate 8.00%"), "briefing shows the requested instrument")
		check(report.contains("Applied rate %.2f%%" % selected.states[0].policy_rate_pct), "briefing shows actual capped rate")
		check(report.contains("Applied lending %.2f" % selected.states[0].liquidity_applied_pct_initial_gdp), "briefing shows collateral-constrained lending")
		check(report.contains("Inflation %+.3f pp" % (selected.states[7].four_quarter_inflation_pct - held.states[7].four_quarter_inflation_pct)), "comparison uses the actual paired Q8 paths")
		check(report.contains("Credibility %.1f vs %.1f" % [100 * selected.states[7].credibility, 100 * held.states[7].credibility]), "comparison exposes credibility consequences")
		check(report.contains("no new asset flows or loans") and report.contains("same current shock"), "reference policy and shock assumptions are explicit")
		check(game.career.payload() == preserved and game.rate.value == 8.0, "comparison cannot alter the career or controls")
		game.career.shocks[6].demand_shock_pct = 10.0
		check(game._decision_briefing() == report, "comparison cannot peek at future realized shocks")
		compare_button.pressed.emit()
		await process_frame
		var comparison: AcceptDialog = game.get_child(game.get_child_count() - 1)
		check(comparison.title == "Compare policy paths", "comparison button opens its briefing")
		comparison.get_ok_button().pressed.emit()
		await process_frame
		game._start_career("supply_shock", 1)
	game.rate.value = 4.25
	game.guidance.value = 4.25
	await process_frame # SpinBox updates its visible text on the next frame.
	check(game.rate.get_line_edit().text == "4.25", "rate field must display its actual 4.25 decision")
	check(game.guidance.get_line_edit().text == "4.25", "guidance field must display its actual 4.25 promise")
	check(game.forecast_label.text.contains("Rate 4.25%"), "preview reflects staged rate")
	game._advance()
	check(game.career.state.quarter_index == 1 and game.career.state.policy_rate_pct == 4.25, "UI adopts the displayed policy")
	check(game.charts[0].history.size() == 2 and game.consequence.text.contains("Q1 OUTCOME"), "adoption updates chart and feedback")
	check(game.consequence.accessibility_live == AccessibilityServer.LIVE_POLITE, "quarterly outcome is announced to assistive technology")
	game.career.state.four_quarter_inflation_pct = 2.0
	game.career.state.output_gap_pct = 0.0
	game.career.state.unemployment_rate_pct = 9.0
	game._review()
	await process_frame
	var review: AcceptDialog = game.get_child(game.get_child_count() - 1)
	var review_text: Label = review.get_child(0).get_child(0)
	check(not review_text.text.contains("employment are close"), "review cannot infer employment from the output gap")
	check(review_text.text.contains("REALIZED PATHS") and review_text.text.contains("unemployment above structural reference"), "review exposes realized inflation and employment tradeoffs")
	check(review_text.text.contains("already occurred") and review_text.text.contains("not a forecast"), "review distinguishes hindsight from a conditional future preview")
	review.get_ok_button().pressed.emit()
	await process_frame
	game._new_dialog()
	await process_frame
	var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	dialog.get_ok_button().pressed.emit()
	check(dialog.visible and dialog.is_queued_for_deletion(), "dialog stays valid until the accessibility action finishes")
	await process_frame
	game._new_dialog()
	await process_frame
	var cancel_dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	var cancel_button: Button
	for button in cancel_dialog.get_ok_button().get_parent().get_children():
		if button is Button and button.text == "Cancel":
			cancel_button = button
	cancel_button.pressed.emit()
	# Deferred calls run before deletion. Cancel must not hide the embedded window
	# before an assistive action's deferred focus request completes.
	call_deferred("check_cancel_window", cancel_dialog)
	await process_frame
	game._credits()
	await process_frame
	var credits: AcceptDialog = game.get_child(game.get_child_count() - 1)
	var notices: Label = credits.get_child(0).get_child(0)
	check(notices.text.contains(Engine.get_license_info()["FTL"]), "bundled component license is preserved verbatim")
	credits.get_ok_button().pressed.emit()
	await process_frame
	game.free()
	if failures == 0:
		print("PASS: exact rate display and UI adoption path")
	quit(1 if failures else 0)
