extends SceneTree
const Explanation = preload("res://play/transition_explanation.gd")
class RejectableMain:
	extends "res://play/main.gd"
	var reject_staged := false
	func _policy() -> Dictionary:
		var policy := super._policy()
		if reject_staged: policy.policy_rate_request_pct = 3.505
		return policy
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func _initialize() -> void: call_deferred("run")
func press(window: Window, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	var receiver: Window = root if window.is_embedded() else window
	receiver.push_input(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	if is_instance_valid(receiver): receiver.push_input(event)
	else: root.push_input(event)
	await process_frame
func run() -> void:
	var game := RejectableMain.new()
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	game.set_process(false) # Exercise cancellation without the automatic clock racing test input.
	check(not game.outcome_drivers.visible, "new career does not invent completed contributions")
	game.rate.value = -0.5
	game._advance()
	await process_frame
	var expected := Explanation.segment(game.career.history, game.career.shocks, 0, 1, game.career.params)
	check(expected.ok and game.outcome_drivers.visible and game.outcome_drivers.values == expected.terms, "actual signed-rate adoption displays exact reconciled terms")
	check(game.outcome_drivers.details_text == expected.text and not game.consequence.text.contains("Equation contributions"), "full explanation remains available without equation prose in the main footer")
	var details: Button = game.outcome_drivers.details_button
	check(game._keyboard_focus_order().has(details), "visible Details joins the actual Tab cycle")
	var saved: PackedByteArray = game.career.encode()
	var policy: Dictionary = game._policy()
	details.grab_focus()
	await press(root, KEY_ENTER)
	var report: AcceptDialog = game.get_child(game.get_child_count() - 1)
	check(report.title == "Output-gap drivers" and report.get_child(0).text == expected.text, "Return opens the complete exact snapshot and caveats")
	await press(report, KEY_ESCAPE)
	await process_frame
	check(details.has_focus() and game.career.encode() == saved and game._policy() == policy, "Escape restores Details focus without policy adoption or career changes")
	for activation in ["keyboard", "pointer signal"]:
		check(game.routine.arm(game.career.state, game.career.params, game._policy(), Engine.get_process_frames()).ok, "actual post-adoption state arms for active Details test")
		game.segment_start = 0
		game.follow_up_toggle.set_pressed_no_signal(true)
		details.grab_focus()
		if activation == "keyboard": await press(root, KEY_ENTER)
		else:
			details.pressed.emit()
			await process_frame
		var active_report = game.get_child(game.get_child_count() - 1)
		check(not game.routine.active and active_report is AcceptDialog and active_report.title == "Output-gap drivers", activation + " opens Details after stopping routine")
		if active_report is AcceptDialog:
			check(active_report.get_child(0).text == expected.text, "active Details discloses the reconciled completed interval")
			await press(active_report, KEY_ESCAPE)
			await process_frame
		check(details.has_focus() and game.career.encode() == saved and game._policy() == policy, activation + " retains Details focus and exact career/policy after Escape")
	var old_details: String = game.outcome_drivers.details_text
	game.reject_staged = true
	game._advance()
	game.reject_staged = false
	check(game.career.encode() == saved and game.outcome_drivers.details_text == old_details, "rejected off-grid input retains the last valid outcome graphic")
	game._start_career("base", 1)
	check(not game.outcome_drivers.visible and game.outcome_drivers.details_text.is_empty(), "replacement career cannot retain stale contributions")
	check(not game._keyboard_focus_order().has(details), "hidden Details leaves the Tab cycle")
	# Pure display path: failed attribution must hide rather than display stale terms.
	game.outcome_drivers.update_result(expected, 1, 1)
	game._update_outcome_drivers(-1)
	check(not game.outcome_drivers.visible, "unreconciled or invalid interval clears stale display")
	if not failures: print("PASS: actual outcome graph, keyboard disclosure/focus, rejection retention and career reset")
	await game._quit_app(1 if failures else 0)
