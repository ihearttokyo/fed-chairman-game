extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func key(window: Window, code: Key, command := false, shift := false, character := 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.unicode = character
	event.meta_pressed = command and OS.get_name() == "macOS"
	event.ctrl_pressed = command and OS.get_name() != "macOS"
	event.shift_pressed = shift
	event.pressed = true
	# Embedded windows must receive keys through their embedder, which forwards
	# Window::_window_input (including PopupMenu's native key handling).
	var receiver: Window = root if window.is_embedded() else window
	receiver.window_input.emit(event)
	receiver.push_input(event)
	event = event.duplicate()
	event.pressed = false
	receiver.window_input.emit(event)
	receiver.push_input(event)
	await process_frame
	await process_frame

func button(game: Node, text: String) -> Button:
	for candidate in game.find_children("*", "Button", true, false):
		if candidate.text == text:
			return candidate
	return null

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	check(game.rate.get_line_edit().has_focus(), "startup places keyboard focus in the target-rate field")
	var start: PackedByteArray = game.career.encode()
	game.rate.get_line_edit().grab_focus()
	var previous: float = game.rate.value
	await key(root, KEY_UP)
	check(is_equal_approx(game.rate.value, previous + 0.25), "Up edits the rate by its advertised 25bp step")
	await key(root, KEY_DOWN)
	check(is_equal_approx(game.rate.value, previous), "Down reverses the same advertised step")
	await key(root, KEY_A, true)
	await key(root, KEY_5, false, false, 53)
	await key(root, KEY_PERIOD, false, false, 46)
	await key(root, KEY_2, false, false, 50)
	await key(root, KEY_5, false, false, 53)
	await key(root, KEY_ENTER)
	check(is_equal_approx(game.rate.value, 5.25), "ordinary typing and Return commit the numeric field")
	check(game.career.encode() == start, "typing, numeric arrows and ordinary Return never adopt a quarter")
	await key(root, KEY_P, true)
	var report := game.get_child(game.get_child_count() - 1) as AcceptDialog
	check(report is AcceptDialog and report.title == "Compare policy paths", "platform command-P opens the actual comparison")
	if report is AcceptDialog:
		await process_frame
		check(report.gui_get_focus_owner() is TextEdit, "opening a report immediately focuses its native readable body")
		await key(report, KEY_ENTER, true)
		check(game.career.encode() == start, "adoption accelerator cannot escape a modal report")
		await key(report, KEY_ESCAPE)
		check(not is_instance_valid(report), "Escape closes a report without a pointer")
		check(game.rate.get_line_edit().has_focus(), "closing a report restores the invoking numeric field")
	check(game.career.encode() == start, "keyboard comparison and dismissal preserve every career byte")
	if not game.has_method("_keyboard_focus_order"):
		check(false, "cockpit has an explicit complete focus order")
	else:
		var order: Array = game._keyboard_focus_order()
		check(order.size() >= 18 and not order.has(game.inflation_response.get_line_edit()), "normal focus order includes all actions and omits hidden custom inputs")
		order[0].grab_focus()
		for next in order.slice(1) + [order[0]]:
			await key(root, KEY_TAB)
			check(root.gui_get_focus_owner() == next, "Tab follows the complete visible control cycle")
		for index in range(order.size() - 1, -1, -1):
			await key(root, KEY_TAB, false, true)
			check(root.gui_get_focus_owner() == order[index], "Shift-Tab reverses the complete focus cycle")
	game.commitment.grab_focus()
	await key(root, KEY_SPACE)
	await key(game.commitment.get_popup(), KEY_DOWN)
	await key(game.commitment.get_popup(), KEY_DOWN)
	await key(game.commitment.get_popup(), KEY_ENTER)
	check(game.commitment.selected == 2 and game.custom_guidance.visible, "keyboard menu selects custom conditional guidance")
	if game.has_method("_keyboard_focus_order"):
		check(game._keyboard_focus_order().has(game.inflation_response.get_line_edit()) and game._keyboard_focus_order().has(game.activity_response.get_line_edit()), "both custom coefficients enter the visible focus cycle")
	for field in [game.guidance, game.assets, game.liquidity, game.inflation_response, game.activity_response]:
		field.get_line_edit().grab_focus()
		var value: float = field.value
		await key(root, KEY_UP)
		check(is_equal_approx(field.value, minf(field.max_value, value + field.custom_arrow_step)), "all policy fields use their advertised numeric step")
		await key(root, KEY_DOWN)
		check(is_equal_approx(field.value, value), "all policy fields permit reversible keyboard adjustment")
	var chart: Control = game.charts[0]
	chart.grab_focus()
	await key(root, KEY_HOME)
	check(chart.focus_mode == Control.FOCUS_ALL and chart.hovered == 0, "chart inspection has a native keyboard route to the first quarter")
	await key(root, KEY_END)
	check(chart.accessibility_description.contains("Q0"), "keyboard chart exposes selected exact values without hover")
	await key(root, KEY_N, true)
	var chooser := game.get_child(game.get_child_count() - 1) as AcceptDialog
	check(chooser is AcceptDialog and game.scenario.has_focus(), "New accelerator focuses scenario selection in the actual chooser")
	if chooser is AcceptDialog:
		await key(chooser, KEY_SPACE)
		await key(game.scenario.get_popup(), KEY_DOWN)
		await key(game.scenario.get_popup(), KEY_ENTER)
		await key(chooser, KEY_TAB)
		check(game.seed_input.get_line_edit().has_focus(), "Tab enters the seed after choosing the scenario")
		await key(chooser, KEY_A, true)
		await key(chooser, KEY_4, false, false, 52)
		await key(chooser, KEY_2, false, false, 50)
		await key(chooser, KEY_ENTER)
		check(game.seed_input.value == 42 and game.career.encode() == start, "typing a seed does not silently confirm replacement")
		await key(chooser, KEY_ESCAPE)
		check(not is_instance_valid(chooser) and game.career.encode() == start, "Escape cancels replacement and preserves unsaved play")
	await key(root, KEY_N, true)
	chooser = game.get_child(game.get_child_count() - 1) as AcceptDialog
	await key(chooser, KEY_SPACE)
	await key(game.scenario.get_popup(), KEY_DOWN)
	await key(game.scenario.get_popup(), KEY_DOWN)
	await key(game.scenario.get_popup(), KEY_ENTER)
	await key(chooser, KEY_TAB)
	await key(chooser, KEY_A, true)
	await key(chooser, KEY_4, false, false, 52)
	await key(chooser, KEY_2, false, false, 50)
	await key(chooser, KEY_ENTER)
	await key(chooser, KEY_TAB)
	check(chooser.gui_get_focus_owner() is Button and chooser.gui_get_focus_owner().text == "Cancel", "replacement puts Cancel before confirmation in its keyboard cycle")
	await key(chooser, KEY_TAB)
	check(chooser.gui_get_focus_owner() == chooser.get_ok_button(), "Tab reaches explicit replacement confirmation")
	await key(chooser, KEY_SPACE)
	check(not is_instance_valid(chooser) and game.career.scenario_id == "supply_shock" and game.career.seed_value == 42, "keyboard-only scenario and seed confirmation starts the exact selected career")
	start = game.career.encode()
	await key(root, KEY_R, true)
	check(game.career.encode() == start, "staff accelerator stages advice without adopting")
	game.rate.get_line_edit().grab_focus()
	var projected: Dictionary = game.career.forecast(game._policy())
	await key(root, KEY_ENTER, true)
	check(game.career.state.quarter_index == 1 and game.career.state == projected.states[0], "modified Return adopts exactly one actual previewed economic state")
	var adopted: PackedByteArray = game.career.encode()
	var echo := InputEventKey.new()
	echo.keycode = KEY_ENTER
	echo.pressed = true
	echo.echo = true
	echo.meta_pressed = OS.get_name() == "macOS"
	echo.ctrl_pressed = OS.get_name() != "macOS"
	root.push_input(echo)
	await process_frame
	check(game.career.encode() == adopted, "held adoption key repeats cannot advance another quarter")
	var motion: Button = button(game, "Animate city")
	motion.grab_focus()
	await key(root, KEY_SPACE)
	check(not game.reduced_motion, "focused Space enables optional city motion")
	await key(root, KEY_SPACE)
	check(game.reduced_motion and game.career.encode() == adopted, "keyboard motion toggles restore stillness without economic effects")
	# Native fonts can fit the compact cockpit entirely; create a real scroll edge.
	var original_size: Vector2 = game.size
	game.size.y = 480
	await process_frame
	await process_frame
	check(game.cockpit_scroll.get_v_scroll_bar().max_value > game.cockpit_scroll.get_v_scroll_bar().page, "scroll fixture contains actual off-screen content on every platform")
	game.cockpit_scroll.grab_focus()
	await key(root, KEY_END)
	check(game.cockpit_scroll.scroll_vertical > 0, "keyboard End reaches off-screen cockpit content")
	await key(root, KEY_HOME)
	check(game.cockpit_scroll.scroll_vertical == 0, "keyboard Home returns the cockpit to its beginning")
	game.size = original_size
	await process_frame
	await process_frame
	for shortcut in [KEY_F1, KEY_J]:
		await key(root, shortcut, shortcut == KEY_J)
		report = game.get_child(game.get_child_count() - 1) as AcceptDialog
		check(report is AcceptDialog and report.gui_get_focus_owner() is TextEdit, "help and history accelerators immediately focus readable native content")
		if shortcut == KEY_F1:
			check(report.get_child(0).text.contains("Keyboard controls") and report.get_child(0).text.contains("modified Return"), "in-game guide exposes every accelerator and ordinary-key alternative")
			await key(report, KEY_PAGEDOWN)
			check(report.get_child(0).get_v_scroll_bar().value > 0, "focused report Page Down scrolls actual long content: " + str([report.get_child(0).get_v_scroll_bar().value, report.get_child(0).get_v_scroll_bar().max_value, report.get_child(0).get_v_scroll_bar().page, report.get_child(0).get_caret_line(), report.gui_get_focus_owner()]))
		else:
			await key(report, KEY_TAB)
			check(report.gui_get_focus_owner().text == "Review realized policy", "journal keyboard cycle includes its completed-policy review")
			await key(report, KEY_SPACE)
			await process_frame
			await process_frame
			report = game.get_child(game.get_child_count() - 1) as AcceptDialog
			check(report.title == "Your 1-quarter policy review", "keyboard journal transition opens one actual realized review")
		await key(report, KEY_ESCAPE)
		check(game.career.encode() == adopted, "keyboard help, history and realized review remain pure")
	button(game, "Credits").grab_focus()
	await key(root, KEY_SPACE)
	report = game.get_child(game.get_child_count() - 1) as AcceptDialog
	check(report.title == "Engine and third-party notices", "focused Space opens credits and bundled notices")
	await key(report, KEY_TAB)
	check(report.gui_get_focus_owner() == report.get_ok_button(), "credits body permits Tab to its close button")
	await key(report, KEY_SPACE)
	check(not is_instance_valid(report) and game.career.encode() == adopted, "focused close button dismisses credits without changing play")
	var temporary := OS.get_cache_dir().path_join("fed-keyboard-%d.save" % OS.get_process_id())
	if FileAccess.file_exists(temporary) or FileAccess.file_exists(temporary + ".pending"):
		check(false, "keyboard save fixture collision; existing final and pending files preserved")
		quit(1)
		return
	game.save_path = temporary
	await key(root, KEY_S, true)
	check(FileAccess.file_exists(temporary) and game.status_label.text.begins_with("Saved quarter 1."), "save accelerator writes the actual disposable career and reports success")
	await key(root, KEY_ENTER, true)
	var unsaved: PackedByteArray = game.career.encode()
	await key(root, KEY_O, true)
	var load_dialog := game.get_child(game.get_child_count() - 1) as AcceptDialog
	check(load_dialog.gui_get_focus_owner().text == "Cancel", "Load starts on safe cancellation, not destructive confirmation")
	await key(load_dialog, KEY_SPACE)
	check(not is_instance_valid(load_dialog) and game.career.encode() == unsaved, "keyboard cancellation preserves unsaved decisions")
	await key(root, KEY_O, true)
	load_dialog = game.get_child(game.get_child_count() - 1) as AcceptDialog
	await key(load_dialog, KEY_TAB)
	await key(load_dialog, KEY_SPACE)
	check(not is_instance_valid(load_dialog) and game.career.encode() == adopted, "explicit keyboard confirmation restores the exact saved career through real replay")
	check(DirAccess.remove_absolute(temporary) == OK, "remove only the exact generated keyboard-save fixture")
	chart.grab_focus()
	await key(root, KEY_HOME)
	await key(root, KEY_RIGHT)
	check(chart.hovered == 1 and chart.accessibility_description.contains("Q1"), "chart arrows inspect a real completed quarter")
	await key(root, KEY_LEFT)
	check(chart.hovered == 0, "chart reverse arrow returns to Q0")
	for q in range(1, game.career.MAX_QUARTERS):
		check(game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "feedback")).ok, "terminal keyboard fixture uses actual valid economic decisions")
	game._refresh(true)
	await process_frame
	await process_frame
	adopted = game.career.encode()
	check(not game._keyboard_focus_order().has(game.decision_button), "disabled terminal adoption leaves the keyboard focus cycle")
	game.rate.get_line_edit().grab_focus()
	await process_frame
	await process_frame
	var terminal_status: String = game.status_label.text
	var terminal_feedback: String = game.consequence.text
	var terminal_rate: float = game.rate.value
	var pending_terminal_rate := "%.2f" % (terminal_rate + 0.25)
	game.rate.get_line_edit().text = pending_terminal_rate
	await key(root, KEY_ENTER, true)
	check(game.rate.value == terminal_rate and game.rate.get_line_edit().text == pending_terminal_rate and game.status_label.text == terminal_status and game.consequence.text == terminal_feedback, "disabled terminal shortcut preserves pending fields and completed feedback")
	check(game.career.encode() == adopted and game.career.state.quarter_index == 240, "terminal adoption accelerator cannot create meeting 241")
	game.free()
	if failures == 0:
		print("PASS: complete keyboard career, editing, focus, menus, charts, reports, save/replay and terminal guards")
	quit(1 if failures else 0)
