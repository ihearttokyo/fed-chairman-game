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
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
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
