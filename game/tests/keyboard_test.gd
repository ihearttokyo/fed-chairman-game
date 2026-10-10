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

func viewport_key(window: Window, code: Key, command := false, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.meta_pressed = command and OS.get_name() == "macOS"
	event.ctrl_pressed = command and OS.get_name() != "macOS"
	event.pressed = true
	event.echo = echo
	var receiver: Window = root if window.is_embedded() else window
	receiver.push_input(event)
	event = event.duplicate()
	event.pressed = false
	event.echo = false
	receiver.push_input(event)
	await process_frame
	await process_frame

func check_periodic_review_keys(game: Control) -> void:
	for closing in [[KEY_ESCAPE, false], [KEY_ENTER, false], [KEY_KP_ENTER, false], [KEY_ENTER, true], [KEY_KP_ENTER, true]]:
		for button_focus in [false, true]:
			game._start_career("unanchored_inflation", 1)
			for q in range(11):
				check(game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "feedback")).ok, "periodic review fixture advances real prior quarters")
			game._refresh(true)
			game._staff_rule()
			game.rate.get_line_edit().grab_focus()
			await viewport_key(root, KEY_ENTER, true)
			var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1) as AcceptDialog
			check(game.career.state.quarter_index == 12 and dialog != null and dialog.title.contains("policy review"), "actual modified Return opens automatic Q12 review without losing its opening event")
			if dialog == null:
				continue
			if button_focus:
				dialog.get_ok_button().grab_focus()
			else:
				dialog.get_child(0).grab_focus()
			var career_bytes: PackedByteArray = game.career.encode()
			var staged: Dictionary = game._policy().duplicate(true)
			await viewport_key(dialog, closing[0], closing[1])
			check(not is_instance_valid(dialog), "viewport input dismisses periodic review from body and button: " + str(closing))
			if is_instance_valid(dialog):
				dialog.queue_free() # Cleanup is not the dismissal evidence.
				await process_frame
				await process_frame
			check(game.career.encode() == career_bytes and game._policy() == staged, "review dismissal never adopts or changes staged policy")
			check(game.rate.get_line_edit().has_focus(), "periodic review dismissal restores its actual invoking field")
			await viewport_key(root, KEY_ENTER, true, true)
			check(game.career.encode() == career_bytes, "held adoption key echo cannot advance after report dismissal")
			await viewport_key(root, KEY_ENTER, true)
			check(game.career.state.quarter_index == 13, "next deliberate command adopts exactly one new quarter")

func check_actionable_report_enter(game: Control) -> void:
	game._start_career("base", 17)
	check(game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "feedback")).ok, "actionable report fixture completes a real quarter")
	game._refresh(true)
	var preserved: PackedByteArray = game.career.encode()
	game._journal()
	await process_frame
	await process_frame
	var journal: AcceptDialog = game.get_child(game.get_child_count() - 1) as AcceptDialog
	var review: Button = button(game, "Review realized policy")
	check(review != null and not review.disabled, "completed journal exposes the real review action")
	if review != null:
		review.grab_focus()
		await viewport_key(journal, KEY_ENTER)
		var report: AcceptDialog = game.get_child(game.get_child_count() - 1) as AcceptDialog
		check(report != null and report.title.contains("policy review"), "plain Return activates journal review rather than dismissing its action")
		if report != null:
			await viewport_key(report, KEY_ESCAPE)
	check(game.career.encode() == preserved, "journal action via Return preserves the exact career")
	game._compare()
	await process_frame
	await process_frame
	var comparison: AcceptDialog = game.get_child(game.get_child_count() - 1) as AcceptDialog
	var chooser: OptionButton = comparison.find_children("*", "OptionButton", true, false)[0]
	chooser.grab_focus()
	await viewport_key(comparison, KEY_ENTER)
	check(is_instance_valid(comparison) and chooser.get_popup().visible, "plain Return opens the comparison chooser without dismissing its report")
	if is_instance_valid(comparison):
		if chooser.get_popup().visible:
			await viewport_key(chooser.get_popup(), KEY_DOWN)
			await viewport_key(chooser.get_popup(), KEY_ENTER)
			check(is_instance_valid(comparison) and chooser.selected == 1 and not chooser.get_popup().visible, "popup Return selects a section and preserves the report")
		await viewport_key(comparison, KEY_ESCAPE)
	check(game.career.encode() == preserved, "section opening/selection/dismissal never adopts a quarter")

func check_deferred_close(dialog: AcceptDialog, action: String) -> void:
	var followup := [false]
	dialog.window_input.connect(func(event: InputEvent):
		if event.is_action_pressed(action):
			(func():
				followup[0] = true
				check(is_instance_valid(dialog) and dialog.visible and dialog.is_queued_for_deletion(), "modal stays registered until queued disposal for deferred focus after " + action)
				if is_instance_valid(dialog) and dialog.visible:
					dialog.get_ok_button().grab_focus()
			).call_deferred())
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	var receiver: Window = root if dialog.is_embedded() else dialog
	receiver.push_input(event)
	await process_frame
	await process_frame
	check(followup[0] and not is_instance_valid(dialog), "close action reaches the actual modal and disposes it: " + action)

func check_wm_close(dialog: AcceptDialog) -> void:
	var title: String = dialog.title
	var canceled := [0]
	dialog.canceled.connect(func(): canceled[0] += 1)
	# Window's native close event sends this notification before close_requested.
	# AcceptDialog intentionally queues hide; unlike keyboard close, visibility
	# during cancellation is not an invariant of this notification path.
	dialog.notification(Window.NOTIFICATION_WM_CLOSE_REQUEST)
	check(canceled[0] == 1 and dialog.is_queued_for_deletion(), "WM notification cancels once and queues disposal: " + title)
	dialog.close_requested.emit()
	await process_frame
	await process_frame
	check(canceled[0] == 1, "WM cancellation remains exactly once after signal and deferred processing: " + title)
	check(not is_instance_valid(dialog), "WM cancellation eventually disposes the actual dialog: " + title)
	print("WM_CLOSE_CASE: " + title)

func type_number(window: Window, field: SpinBox, text: String, submit := true) -> void:
	var codes := {"-": KEY_MINUS, ".": KEY_PERIOD,
		"0": KEY_0, "1": KEY_1, "2": KEY_2, "3": KEY_3, "4": KEY_4,
		"5": KEY_5, "6": KEY_6, "7": KEY_7, "8": KEY_8, "9": KEY_9}
	field.get_line_edit().grab_focus()
	await key(window, KEY_A, true)
	for character in text:
		await key(window, codes[character], false, false, character.unicode_at(0))
	if submit:
		await key(window, KEY_ENTER)

func button(game: Node, text: String) -> Button:
	for candidate in game.find_children("*", "Button", true, false):
		if candidate.text == text:
			return candidate
	return null

func check_journal(report: AcceptDialog, history: Array) -> void:
	for observation in history:
		var row := "Q%03d |" % observation.quarter_index
		var report_text: String = report.get_child(0).text
		var offset := report_text.find(row)
		var following := report_text.find("\n\n", offset)
		check(offset >= 0 and following > offset, "journal preserves each completed-quarter row")
		var observed_row := report_text.substr(offset, following - offset)
		for detail in ["long expectations %.2f%%" % observation.expected_long_inflation_pct, "structural reference %.2f%%" % observation.structural_unemployment_pct, "hardship memory %.2f" % observation.public_hardship_memory]:
			check(observed_row.contains(detail), "journal exposes each historical chart/support detail without hover: " + detail)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var startup_size := root.size
	var startup_scale := root.content_scale_size
	root.size = Vector2i(1440, 600)
	root.content_scale_size = Vector2i(1440, 600)
	var game: Control = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	check(game.rate.get_line_edit().has_focus(), "startup places keyboard focus in the target-rate field")
	check(game.cockpit_scroll.get_v_scroll_bar().max_value > game.cockpit_scroll.get_v_scroll_bar().page, "startup fixture genuinely overflows before initial focus")
	check(game.cockpit_scroll.scroll_vertical == 0, "startup retains the whole header instead of pre-scrolling to the rate field")
	var title: Label
	for label in game.find_children("*", "Label", true, false):
		if label.text == "THE CHAIR": title = label
	check(title != null and game.cockpit_scroll.get_global_rect().encloses(title.get_global_rect()), "cold overflowing startup contains the whole title")
	root.size = startup_size
	root.content_scale_size = startup_scale
	await process_frame
	await process_frame
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
		check(not is_instance_valid(report), "modified Return dismisses the report without adoption")
		await key(root, KEY_P, true)
		report = game.get_child(game.get_child_count() - 1) as AcceptDialog
		await key(report, KEY_ESCAPE)
		check(not is_instance_valid(report), "Escape closes a report without a pointer")
		check(game.rate.get_line_edit().has_focus(), "closing a report restores the invoking numeric field")
	check(game.career.encode() == start, "keyboard comparison and dismissal preserve every career byte")
	for action in ["ui_cancel", "ui_close_dialog"]:
		await key(root, KEY_P, true)
		report = game.get_child(game.get_child_count() - 1) as AcceptDialog
		check(report is AcceptDialog and report.title == "Compare policy paths", "close fixture opens the actual comparison")
		if report is AcceptDialog:
			await check_deferred_close(report, action)
			check(game.rate.get_line_edit().has_focus() and game.career.encode() == start, "deferred modal close restores its invoking field without economic mutation: " + action)
	for shortcut in [KEY_P, KEY_F1, KEY_N, KEY_O]:
		game.rate.get_line_edit().grab_focus()
		var staged: Dictionary = game._policy().duplicate(true)
		await key(root, shortcut, shortcut != KEY_F1)
		report = game.get_child(game.get_child_count() - 1) as AcceptDialog
		var titles := {KEY_P: "Compare policy paths", KEY_F1: "How to play", KEY_N: "Start a new career", KEY_O: "Load saved career"}
		check(report is AcceptDialog and report.title.begins_with(titles[shortcut]), "WM fixture opens each real dialog family")
		if report is AcceptDialog:
			await check_wm_close(report)
			check(game.rate.get_line_edit().has_focus(), "WM cancellation restores the live invoking field")
			check(game.career.encode() == start and game._policy() == staged, "WM cancellation preserves exact unsaved career and staged policy")
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
	for pair in [[game.reinvestment, "reinvest_principal"], [game.reserve_maintenance, "maintain_ample_reserves"], [game.sterilization, "sterilize_purchases"]]:
		var control: CheckBox = pair[0]
		var mode: String = pair[1]
		var previous_mode: bool = game._policy()[mode]
		control.grab_focus()
		await key(root, KEY_SPACE)
		check(game._policy()[mode] == not previous_mode and control.button_pressed == not previous_mode, "focused Space toggles each actual staged portfolio mode")
		check(game.career.encode() == start, "keyboard portfolio mode changes never adopt a quarter")
		await key(root, KEY_SPACE)
		check(game._policy()[mode] == previous_mode and game.career.encode() == start, "keyboard mode toggles restore exactly without economic mutation")
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
	for custom_field in [game.inflation_response, game.activity_response]:
		game.commitment.select(2)
		game._guidance_controls()
		custom_field.get_line_edit().grab_focus()
		await key(root, KEY_R, true)
		check(game.commitment.selected == 0 and not game.custom_guidance.visible and root.gui_get_focus_owner() == game.commitment, "staff shortcut from each custom field hands focus to visible commitment selector")
		check(game.career.encode() == start, "custom-to-default staff advice never mutates the career")
		await key(root, KEY_TAB)
		check(game.assets.get_line_edit().has_focus(), "Tab continues from commitment into visible asset input after custom fields hide")
		await key(root, KEY_TAB, false, true)
		check(root.gui_get_focus_owner() == game.commitment, "Shift-Tab returns to visible commitment after custom fields hide")
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
	for i in range(5):
		await key(game.scenario.get_popup(), KEY_UP)
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
	# A valid audit input makes historical structural references differ.
	game.career.shocks[0]["structural_unemployment_change_pct"] = 0.25
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
	var manual_scroll: int = game.cockpit_scroll.scroll_vertical
	await process_frame
	await process_frame
	check(game.cockpit_scroll.scroll_vertical == manual_scroll, "startup reset never cancels later manual scroll")
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
			check_journal(report, game.career.history)
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
	game.rate.get_line_edit().grab_focus()
	var unsaved_policy: Dictionary = game._policy().duplicate(true)
	await key(root, KEY_O, true)
	var wm_load := game.get_child(game.get_child_count() - 1) as AcceptDialog
	check(wm_load is AcceptDialog and wm_load.title == "Load saved career", "WM fixture opens Load with actual unsaved completed quarters")
	if wm_load is AcceptDialog:
		await check_wm_close(wm_load)
		check(game.rate.get_line_edit().has_focus() and game.career.encode() == unsaved and game._policy() == unsaved_policy, "WM Load cancellation preserves nonzero-quarter unsaved play and staged policy")
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
	for field in ["expected_long_inflation_pct", "structural_unemployment_pct", "public_hardship_memory"]:
		var displayed_values := {}
		for observation in game.career.history:
			displayed_values["%.2f" % observation[field]] = true
		check(displayed_values.size() > 1, "journal fixture distinguishes historical values from current state at displayed precision: " + field)
	await key(root, KEY_J, true)
	report = game.get_child(game.get_child_count() - 1) as AcceptDialog
	check(report is AcceptDialog and report.gui_get_focus_owner() is TextEdit, "terminal history opens keyboard-readable completed observations")
	if report is AcceptDialog:
		check_journal(report, game.career.history)
		await key(report, KEY_ESCAPE)
	check(game.career.encode() == adopted, "terminal journal and dismissal preserve every completed career byte")
	# Additive typing boundaries follow the untouched 240-quarter fixture.
	for quotes in [["-0.50", "-0.75", "-150.00", "0.00"], ["25.01", "30.02", "150.00", "400.00"]]:
		game._start_career("base", 17)
		for q in range(4):
			check(game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "neutral")).ok, "typed current-GDP fixture advances the actual economy")
		game._refresh(true)
		await process_frame
		await process_frame
		var n: float = game.career.model.nominal_gdp_ratio(game.career.state)
		check(abs(n - 1.0) > 0.001, "typed offer fixture distinguishes current GDP from initial GDP")
		game.career.shocks[4].funding_need_pct_initial_gdp = 8.0 * n
		game.career.shocks[4].eligible_collateral_pct_initial_gdp = 2.0 * n
		game.career.shocks[4].liquidity_eligibility_pct = 100.0
		var typed_start: PackedByteArray = game.career.encode()
		var fields := [game.rate, game.guidance, game.assets, game.liquidity]
		for index in range(fields.size()):
			await type_number(root, fields[index], quotes[index])
			check(fields[index].get_line_edit().is_editing(), "ordinary Return keeps the numeric field ready for further keyboard edits")
			check(fields[index].value == quotes[index].to_float() and fields[index].get_line_edit().text.to_float() == quotes[index].to_float(), "key-entered signed and large quotes retain their numeric value and visible precision")
			check(game.career.encode() == typed_start, "ordinary Return commits each boundary field without adopting")
		var expected := {"policy_rate_request_pct": quotes[0].to_float(), "guidance_rate_pct": quotes[1].to_float(),
			"guidance_inflation_sensitivity": game.career.params.policy_inflation_response,
			"guidance_output_gap_sensitivity": game.career.params.policy_output_gap_response,
			"asset_flow_request_pct_initial_gdp": quotes[2].to_float() * n,
			"liquidity_request_pct_initial_gdp": quotes[3].to_float() * n,
			"reinvest_principal": true, "maintain_ample_reserves": true, "sterilize_purchases": false}
		check(game._policy() == expected, "typed offers convert from meeting-current GDP exactly once")
		var staged_preview: Dictionary = game.career.forecast(expected)
		check(staged_preview.ok and game.career.encode() == typed_start, "committed typed boundaries have a pure actual preview")
		if not staged_preview.ok:
			continue
		var applied: Dictionary = staged_preview.states[0]
		check(game.forecast_label.text.contains("Rate %.2f%%" % applied.policy_rate_pct) and game.forecast_label.text.contains("assets %+.2f" % (applied.asset_flow_applied_pct_initial_gdp / n)) and game.forecast_label.text.contains("lending %.2f" % (applied.liquidity_applied_pct_initial_gdp / n)), "typed boundary preview visibly reports actual rate, runoff or purchases and collateral-limited lending in meeting units")
		var committed: Dictionary = expected.duplicate()
		var negative: bool = quotes[0].begins_with("-")
		if negative:
			expected.guidance_rate_pct = -0.76
			await type_number(root, game.guidance, "-0.76", false)
		else:
			expected.liquidity_request_pct_initial_gdp = 400.01 * n
			await type_number(root, game.liquidity, "400.01", false)
		check(game._policy() == committed and game.career.encode() == typed_start, "key-entered pending boundary text leaves the committed policy and career unchanged")
		var boundary_preview: Dictionary = game.career.forecast(expected)
		check(boundary_preview.ok and game.career.encode() == typed_start, "independently constructed pending boundary policy has a pure actual forecast")
		if not boundary_preview.ok:
			continue
		var first: Dictionary = boundary_preview.states[0]
		check(first.policy_rate_pct == expected.policy_rate_request_pct and first.guidance_rate_pct == expected.guidance_rate_pct, "accepted nominal quotes apply in full and preserve the announced guidance")
		check(first.asset_flow_request_pct_initial_gdp == expected.asset_flow_request_pct_initial_gdp and first.liquidity_request_pct_initial_gdp == expected.liquidity_request_pct_initial_gdp and first.decision_nominal_gdp_ratio == n, "forecast retains the accepted offers and meeting denominator without another conversion")
		if negative:
			check(is_equal_approx(first.principal_runoff_pct_initial_gdp, minf(-expected.asset_flow_request_pct_initial_gdp, first.principal_due_pct_initial_gdp)) and is_equal_approx(first.asset_flow_applied_pct_initial_gdp, -first.principal_runoff_pct_initial_gdp), "negative typed offer caps actual due principal, independently of reserve-maintenance bills")
			await key(root, KEY_P, true)
			report = game.get_child(game.get_child_count() - 1) as AcceptDialog
			check(report is AcceptDialog and report.title == "Compare policy paths", "keyboard comparison opens the actual pending negative-quote report")
			if report is AcceptDialog:
				var body: TextEdit = report.find_children("*", "TextEdit", true, false)[0]
				check(body.text.contains("New quote -0.76%") and body.text.contains("Requested assets -150.00") and body.text.contains("Applied assets %+.2f" % (first.asset_flow_applied_pct_initial_gdp / n)), "comparison distinguishes typed negative requests from physically applied runoff")
				check(game._policy() == expected and game.forecast_label.text.contains("Rate -0.50%% (effective %.2f%%)" % first.effective_policy_rate_pct) and game.forecast_label.text.contains("assets %+.2f" % (first.asset_flow_applied_pct_initial_gdp / n)) and game.career.encode() == typed_start, "Compare submits pending negative guidance and refreshes applied feedback without career mutation")
				await key(report, KEY_ESCAPE)
				check(not is_instance_valid(report) and game.guidance.get_line_edit().has_focus() and game.career.encode() == typed_start, "negative comparison dismissal restores its invoking field and every career byte")
		else:
			check(first.asset_flow_applied_pct_initial_gdp == expected.asset_flow_request_pct_initial_gdp, "large typed purchases apply without an invented offer ceiling")
			check(first.liquidity_applied_pct_initial_gdp > 0.0 and first.liquidity_applied_pct_initial_gdp < expected.liquidity_request_pct_initial_gdp and first.liquidity_applied_pct_initial_gdp <= first.lending_collateral_capacity_pct_initial_gdp and first.liquidity_applied_pct_initial_gdp <= first.eligible_local_need_pct_initial_gdp and first.liquidity_collateral_binding == 1.0, "large typed lending is accepted but actual advances bind to eligible collateral, not the quote")
		var pending_lending_input := {"text": game.liquidity.get_line_edit().text, "value": game.liquidity.value, "focused": game.liquidity.get_line_edit().has_focus(), "numeric_text": game.liquidity.get_meta("numeric_text"), "numeric_text_pending": game.liquidity.get_meta("numeric_text_pending")}
		check(negative or pending_lending_input.text.strip_edges() == "400.01", "operator typing retains the pending large lending quote before adoption: %s" % pending_lending_input)
		await key(root, KEY_ENTER, true)
		var policy_differences: PackedStringArray = []
		for field in expected:
			if game.career.decisions[-1].get(field) != expected[field]:
				policy_differences.append("%s: actual %.17f; expected %.17f" % [field, float(game.career.decisions[-1][field]), float(expected[field])])
		var state_differences: PackedStringArray = []
		for field in first:
			if game.career.state.get(field) != first[field]:
				state_differences.append(field)
		check(game.career.state.quarter_index == 5 and game.career.decisions.size() == 5 and game.career.history.size() == 6 and game.career.decisions[-1] == expected and game.career.state == first, "modified Return adopts exactly one independently forecast boundary decision, including pending large lending: case %s; input %s; policy differences %s; state differences %s" % [quotes, pending_lending_input, policy_differences, state_differences])
		check(game.consequence.text.begins_with("Q5 OUTCOME") and game.consequence.text.contains("Applied rate %.2f%%" % first.policy_rate_pct) and game.status_label.text.begins_with("Quarter 5 completed."), "boundary adoption reports its actual completed quarter and applied rate")
		check(game.assets.value == 0.0 and game.liquidity.value == 0.0 and game.career.state.guidance_rate_pct == expected.guidance_rate_pct, "one-time offers reset while the committed guidance survives in economic state")
		var boundary_saved: PackedByteArray = game.career.encode()
		var replay = game.career.get_script().new()
		var restored: Dictionary = replay.restore(bytes_to_var(boundary_saved))
		check(restored.ok and replay.state == game.career.state and replay.history == game.career.history and replay.decisions == game.career.decisions and replay.encode() == boundary_saved and game.career.encode() == boundary_saved, "in-memory replay preserves all typed boundary decisions, states, history and career bytes")
	game._start_career("base", 17)
	await process_frame
	await process_frame
	var floor_start: PackedByteArray = game.career.encode()
	var floor_policy: Dictionary = game._policy()
	await type_number(root, game.liquidity, "-1.00")
	check(game.liquidity.value == 0.0 and game.liquidity.get_line_edit().text.to_float() == 0.0 and game._policy() == floor_policy and game.forecast_label.text.contains("lending 0.00") and game.career.encode() == floor_start, "typed negative lending normalizes to the nonnegative floor without adopting or changing applied feedback")
	await check_periodic_review_keys(game)
	await check_actionable_report_enter(game)
	game.free()
	if failures == 0:
		print("PASS: complete keyboard career, editing, focus, menus, charts, reports, save/replay and terminal guards")
	quit(1 if failures else 0)
