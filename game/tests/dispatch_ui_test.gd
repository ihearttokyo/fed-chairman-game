extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func _initialize() -> void: call_deferred("run")
func press(window: Window, code: Key) -> void:
	var target: Window = root if window.is_embedded() else window
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	target.push_input(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	if is_instance_valid(target): target.push_input(event)
	else: root.push_input(event)
	await process_frame
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false) # Native input remains live; only automatic clock is frozen.
	game._advance()
	var saved: PackedByteArray = game.career.encode()
	var policy: Dictionary = game._policy()
	var details: Button = game.dispatch_details_button
	var before_text: String = game.dispatch_details_text
	check(game.briefing.text.length() < before_text.length() and not game.briefing.text.contains("MARKETS /"), "current summary is genuinely shorter without repeated narration")
	for activation in ["keyboard", "pointer signal"]:
		check(game.routine.arm(game.career.state, game.career.params, game._policy(), Engine.get_process_frames()).ok, "valid completed state arms routine for disclosure")
		game.segment_start = 0
		game.follow_up_toggle.set_pressed_no_signal(true)
		details.grab_focus()
		if activation == "keyboard": await press(root, KEY_ENTER)
		else:
			details.pressed.emit()
			await process_frame
		var report = game.get_child(game.get_child_count() - 1)
		check(not game.routine.active and report is AcceptDialog and report.title == "Current conditions", activation + " discloses current conditions after cancelling automatic follow-up")
		if report is AcceptDialog:
			check(report.get_child(0).text == before_text, "Details keeps the full unchanged current snapshot")
			await press(report, KEY_ESCAPE)
			await process_frame
		check(details.has_focus() and game.career.encode() == saved and game._policy() == policy, activation + " restores focus without advancing or staging policy")
	# Find the first currently published event by advancing the real career, never peeking ahead.
	game._start_career("mixed_crises", 417)
	while game.career.current_shock_episode().is_empty() and game.career.decisions.size() < 24:
		check(game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params)).ok, "event fixture advances native policy")
	game._refresh(true)
	var episode: Dictionary = game.career.current_shock_episode()
	check(not episode.is_empty() and game.dispatch_event.text == episode.title and game.dispatch_dilemma.text == episode.policy_dilemma, "current known shock and dilemma are prominent and exact")
	game.career.shocks[game.career.decisions.size()].demand_shock_pct += 0.125
	game._refresh()
	check(not game.dispatch_event.visible and not game.dispatch_dilemma.visible and game.dispatch_event.text.is_empty() and game.dispatch_dilemma.text.is_empty(), "edited current inputs cannot retain an authored episode label")
	if not failures: print("PASS: compact current briefing, active-routine Details focus/purity and current-only event prominence")
	await game._quit_app(1 if failures else 0)
