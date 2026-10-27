extends SceneTree
## Production New modal and native input; headless mechanics, not pixel acceptance.
var failures := 0
var checks := 0

class RecordingMain:
	extends "res://play/main.gd"
	var starts: Array = []
	var previews := 0
	func _start_career(id: String, seed_number: int) -> void:
		starts.append([id, seed_number])
		super._start_career(id, seed_number)
	func _preview() -> void:
		previews += 1
		super._preview()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func settle() -> void:
	for frame in range(8):
		await process_frame

func key(window: Window, code: Key, command := false, shift := false, character := 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.unicode = character
	event.meta_pressed = command and OS.get_name() == "macOS"
	event.ctrl_pressed = command and OS.get_name() != "macOS"
	event.shift_pressed = shift
	event.pressed = true
	var receiver: Window = root if window.is_embedded() else window
	receiver.window_input.emit(event)
	receiver.push_input(event)
	event = event.duplicate()
	event.pressed = false
	receiver.window_input.emit(event)
	receiver.push_input(event)
	await process_frame
	await process_frame

func press_without_frame(window: Window, code: Key) -> void:
	var receiver: Window = root if window.is_embedded() else window
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	receiver.window_input.emit(event)
	receiver.push_input(event)
	event = event.duplicate()
	event.pressed = false
	receiver.window_input.emit(event)
	receiver.push_input(event)

func drafts(game: Control) -> PackedByteArray:
	var rows: Array = []
	for input in [game.rate, game.guidance, game.assets, game.liquidity, game.inflation_response, game.activity_response]:
		rows.append([input.value, input.get_line_edit().text])
	return var_to_bytes(rows)

func signal_flags(game: Control) -> Array:
	var flags: Array = []
	for input in [game.rate, game.guidance, game.assets, game.liquidity, game.inflation_response, game.activity_response]:
		flags.append(input.get_line_edit().is_blocking_signals())
	return flags

func pointer_at(position: Vector2, pressed: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = pressed
	root.push_input(event)

func aborted_and_overlap_cases(game: Control, opener: Button, pending: PackedByteArray) -> void:
	game.rate.get_line_edit().grab_focus()
	game.guidance.get_line_edit().set_block_signals(true)
	var flags := signal_flags(game)
	pointer_at(opener.get_global_rect().get_center(), true)
	await process_frame
	await process_frame
	check(game.entry_signal_states.size() == 6 and signal_flags(game).all(func(flag): return flag), "held New press protects every policy edit before GUI focus exit")
	pointer_at(Vector2(1, 1), false)
	await settle()
	check(not is_instance_valid(game.career_opening_picker) and game.entry_signal_states.is_empty(), "release outside New aborts the opening and releases its guard")
	check(drafts(game) == pending and signal_flags(game) == flags, "aborted held press restores literal invalid draft and distinct prior signal flags")
	# A keyboard command can supersede a still-held pointer opening. The guards
	# must hand back original flags, not capture one another's temporary blocks.
	game.rate.get_line_edit().grab_focus()
	pointer_at(opener.get_global_rect().get_center(), true)
	await process_frame
	await key(root, KEY_K, true)
	var docket: Window = game.committee_docket
	check(is_instance_valid(docket) and game.entry_signal_states.is_empty() and game.docket_signal_states.size() == 6, "committee supersedes an unused entry pointer guard without nested signal ownership")
	game._new_dialog()
	check(not is_instance_valid(game.career_opening_picker) and game.entry_signal_states.is_empty(), "New refuses to nest inside an existing committee modal")
	await key(docket, KEY_ESCAPE)
	pointer_at(Vector2(1, 1), false)
	await settle()
	check(drafts(game) == pending and signal_flags(game) == flags and game.docket_signal_states.is_empty(), "overlap cancellation restores original drafts/flags instead of temporary suppression")
	game.shutting_down = true
	game._new_dialog()
	check(game.entry_signal_states.is_empty() and not is_instance_valid(game.career_opening_picker), "shutdown refuses a new picker without taking draft ownership")
	game.shutting_down = false
	game.guidance.get_line_edit().set_block_signals(false)

func replacement_guard_case(game: Control) -> void:
	game.guidance.get_line_edit().set_block_signals(true)
	var flags := signal_flags(game)
	game._new_dialog()
	await settle()
	var older = modal(game)
	var original_state: Dictionary = game.career.state
	game._start_career("supply_shock", 99)
	check(not is_same(game.career.state, original_state), "replacement fixture actually changes state identity")
	await settle()
	game.rate.get_line_edit().text = "replacement pending"
	var replacement := drafts(game)
	# Queue the replacement from the actual exit before the old tree_exited
	# cleanup callback; do not free a Window with pending native layout work.
	older.tree_exiting.connect(func(): game._new_dialog.call_deferred())
	older.queue_free()
	await settle()
	var newer = modal(game)
	check(is_instance_valid(newer) and game.entry_signal_states.size() == 6, "an exited older picker with deferred cleanup allows a fresh independently captured picker")
	if drafts(game) != replacement:
		printerr("REPLACEMENT_DIAG expected=%s actual=%s flags=%s" % [str(bytes_to_var(replacement)), str(bytes_to_var(drafts(game))), str(signal_flags(game))])
	check(is_instance_valid(newer) and drafts(game) == replacement and signal_flags(game).all(func(flag): return flag), "older deferred release neither consumes the newer guard nor overwrites replacement drafts")
	await key(newer, KEY_ESCAPE)
	await settle()
	check(drafts(game) == replacement and signal_flags(game) == flags and game.entry_signal_states.is_empty(), "newer cancellation preserves replacement state and restores actual prior flags")
	game.guidance.get_line_edit().set_block_signals(false)

func modal(game: Control) -> AcceptDialog:
	return game.get_child(game.get_child_count() - 1) as AcceptDialog

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1440, 960)
	var game: Control = load("res://main.tscn").instantiate()
	game.set_script(RecordingMain)
	root.add_child(game)
	await settle()
	game.save_path = "user://entry-picker-test.save"
	game._save()
	var saved := FileAccess.get_file_as_bytes(game.save_path)
	check(not saved.is_empty(), "fixture uses a real guarded private-HOME save")
	check(game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "feedback")).ok, "fixture has unsaved adopted history")
	game._refresh(true)
	await settle()
	game.rate.get_line_edit().grab_focus()
	game.rate.get_line_edit().text = "not a number"
	game.guidance.get_line_edit().text = "7 + 1"
	var before: PackedByteArray = game.career.encode()
	var pending := drafts(game)
	var previews: int = game.previews
	game.starts.clear()
	await key(root, KEY_N, true)
	await settle()
	var picker = modal(game)
	check(picker != null and picker.get_script() == load("res://play/career_opening_picker.gd"), "production New uses the reusable picker")
	check(game.scenario == picker.scenario and game.seed_input == picker.seed_input, "public scenario and seed interfaces stay compatible")
	check(picker.primary_buttons[0].has_focus() and picker.primary_buttons[0].button_pressed, "opening focuses the visible selected default primary choice")
	for expected in picker.primary_buttons.slice(1) + [picker.scenario, picker.seed_input.get_line_edit()]:
		await key(picker, KEY_TAB)
		check(picker.gui_get_focus_owner() == expected and game.starts.is_empty(), "initial sequential Tab visits every choice then selector and seed without starting")
	check(game.scenario.get_item_metadata(game.scenario.selected) == game.Career.DEFAULT_SCENARIO and game.seed_input.value == 1, "unchanged policy_career default and seed 1")
	check(picker.primary_ids.slice(0, 4) == ["policy_career", "stagflation_bank_run", "__priced_bank_workout", "__bank_workout"] and picker.primary_ids[4] == game.RUNOFF_CASE, "four primary cards use the actual production constant IDs")
	check(picker.primary_buttons.size() == 5, "all original four choices and separate runoff choice exist immediately")
	check(game.scenario.item_count == game.career.cases.size() + 3, "all normal cases, both original labs and separate runoff remain in the selector")
	var index := 0
	for id in game.career.cases:
		check(game.scenario.get_item_metadata(index) == id and game.scenario.get_item_text(index) == game.career.cases[id].label, "original case ordering, label and ID retained: " + id)
		index += 1
	check(game.scenario.get_item_text(index) == "Bank workout · borrowing costs" and game.scenario.get_item_metadata(index) == game.PRICED_WORKOUT_CASE, "priced lab label and metadata retained")
	check(game.scenario.get_item_text(index + 1) == "Bank workout · 8-meeting laboratory" and game.scenario.get_item_metadata(index + 1) == game.WORKOUT_CASE, "ordinary lab label and metadata retained")
	for card_index in range(4):
		picker.primary_buttons[card_index].grab_focus()
		await key(picker, KEY_ENTER)
		check(is_instance_valid(picker) and game.scenario.get_item_metadata(game.scenario.selected) == picker.primary_ids[card_index], "native Return selects card only: " + str(card_index))
		check(picker.primary_buttons.filter(func(button): return button.button_pressed).size() == 1 and picker.primary_buttons[card_index].button_pressed, "card and dropdown selection have one source of truth")
		check(game.career.encode() == before and drafts(game) == pending and game.starts.is_empty(), "card inspection preserves career and raw numeric drafts")
		if card_index == 1:
			check(picker.summary.text.contains("rolling stabilization") and picker.summary.text.contains("Q240") and picker.primary_buttons[1].caption.text.contains("−3% gap"), "crisis cue discloses immediate pressure and rolling, nonterminal recovery")
		if card_index >= 2:
			check(picker.summary.text.contains("No normal career awards or saves") and picker.primary_buttons[card_index].caption.text.contains("UNSAVED"), "both laboratories disclose unsaved eight-meeting mode")
	picker.primary_buttons[0].grab_focus()
	await key(picker, KEY_RIGHT)
	check(picker.primary_buttons[1].has_focus(), "native Right arrow reaches the adjacent primary choice")
	await key(picker, KEY_DOWN)
	check(picker.primary_buttons[3].has_focus() and game.starts.is_empty(), "native Down arrow inspects the lower choice without starting")
	picker.scenario.grab_focus()
	await key(picker, KEY_SPACE)
	for step in range(picker.scenario.selected):
		await key(picker.scenario.get_popup(), KEY_UP)
	await key(picker.scenario.get_popup(), KEY_DOWN)
	await key(picker.scenario.get_popup(), KEY_ENTER)
	var advanced_id: String = picker.scenario.get_item_metadata(picker.scenario.selected)
	check(advanced_id == game.career.cases.keys()[1] and picker.primary_buttons.all(func(button): return not button.button_pressed), "native selector arrows choose an advanced case without stale card selection")
	check(picker.details.text.begins_with(game.career.cases[advanced_id].description), "advanced case keeps its original metadata description")
	picker.details_button.grab_focus()
	await key(picker, KEY_ENTER)
	check(picker.details.visible and game.starts.is_empty(), "native Return expands useful details without starting")
	await key(picker, KEY_TAB)
	check(picker.details.has_focus(), "expanded details have a native selectable reading surface")
	await key(picker, KEY_ENTER, true)
	check(is_instance_valid(picker) and game.starts.is_empty(), "modified Return cannot start or dismiss the picker while inspecting")
	picker.scenario.grab_focus()
	await key(picker, KEY_TAB)
	check(game.seed_input.get_line_edit().has_focus(), "selector Tab still reaches seed")
	await key(picker, KEY_A, true)
	await key(picker, KEY_4, false, false, 52)
	await key(picker, KEY_2, false, false, 50)
	await key(picker, KEY_ENTER)
	check(game.seed_input.value == 42 and game.seed_input.get_line_edit().has_focus() and game.starts.is_empty(), "native seed Return commits 42 only, without start or focus loss")
	var seed_scroll: int = picker.scroll.scroll_vertical
	await key(picker, KEY_HOME)
	check(game.seed_input.get_line_edit().caret_column == 0 and picker.scroll.scroll_vertical == seed_scroll, "seed Home edits the caret without scrolling the picker")
	await key(picker, KEY_END)
	check(game.seed_input.get_line_edit().caret_column == game.seed_input.get_line_edit().text.length() and picker.scroll.scroll_vertical == seed_scroll and game.starts.is_empty(), "seed End retains native caret and explicit-Start semantics")
	await key(picker, KEY_ESCAPE)
	check(not is_instance_valid(picker) and game.rate.get_line_edit().has_focus(), "Escape closes the production modal and restores its numeric opener")
	check(game.career.encode() == before and drafts(game) == pending and game.previews == previews and FileAccess.get_file_as_bytes(game.save_path) == saved, "opening, selection, details and Escape preserve career/drafts/save with no extra forecasts")
	# Cancel via its native button, including previously blocked signal flags.
	game.guidance.get_line_edit().set_block_signals(true)
	game._new_dialog()
	await settle()
	picker = modal(game)
	picker.cancel.grab_focus()
	await key(picker, KEY_ENTER)
	check(not is_instance_valid(picker) and game.rate.get_line_edit().has_focus() and game.guidance.get_line_edit().is_blocking_signals(), "Cancel restores opener and pre-existing signal suppression")
	game.guidance.get_line_edit().set_block_signals(false)
	check(game.career.encode() == before and drafts(game) == pending and FileAccess.get_file_as_bytes(game.save_path) == saved, "Cancel preserves unsaved decisions, invalid drafts and stored bytes")
	# Native pointer opening, with a held press long enough for focus-exit work.
	var opener: Button
	for button in game.find_children("*", "Button", true, false):
		if button.text == "New career": opener = button
	check(opener != null, "production New button exists")
	game.guidance.get_line_edit().set_block_signals(true)
	var pointer_flags := signal_flags(game)
	var pointer := InputEventMouseButton.new()
	pointer.button_index = MOUSE_BUTTON_LEFT
	pointer.position = opener.get_global_rect().get_center()
	pointer.pressed = true
	root.push_input(pointer)
	await process_frame
	await process_frame
	pointer = pointer.duplicate()
	pointer.pressed = false
	root.push_input(pointer)
	await settle()
	picker = modal(game)
	check(picker != null, "native pointer opens the production modal")
	print("POINTER_ENTRY raw_rate_after=", game.rate.get_line_edit().text, " preview_delta=", game.previews - previews)
	check(drafts(game) == pending, "pointer opening preserves pending policy drafts")
	check(game.previews == previews, "pointer opening does not compute extra forecasts")
	check(game.career.encode() == before and FileAccess.get_file_as_bytes(game.save_path) == saved, "pointer opening preserves unsaved career and save bytes")
	if picker != null:
		picker.cancel.grab_focus()
		await key(picker, KEY_ENTER)
	check(drafts(game) == pending and signal_flags(game) == pointer_flags and game.entry_signal_states.is_empty(), "pointer Cancel restores original raw drafts and pre-existing signal flags")
	game.guidance.get_line_edit().set_block_signals(false)
	await aborted_and_overlap_cases(game, opener, pending)
	# Independent failure fixture, after the separately asserted pointer path.
	var failure_career: PackedByteArray = game.career.encode()
	var failure_drafts := drafts(game)
	game.assets.get_line_edit().set_block_signals(true)
	var failure_flags := signal_flags(game)
	# Failure dispatched through actual Start retains the current career/drafts/save.
	game._new_dialog()
	await settle()
	picker = modal(game)
	picker.scenario.set_item_metadata(picker.scenario.selected, "unknown-entry-validation-case")
	picker.get_ok_button().grab_focus()
	await key(picker, KEY_ENTER)
	check(game.starts == [["unknown-entry-validation-case", 1]] and game.status_label.text == "Unknown scenario", "explicit Start preserves existing validation failure feedback")
	check(game.career.encode() == failure_career and drafts(game) == failure_drafts and FileAccess.get_file_as_bytes(game.save_path) == saved, "failed Start cannot reset career, submit policy drafts or overwrite save")
	check(signal_flags(game) == failure_flags and game.entry_signal_states.is_empty(), "failed Start releases suppression and restores distinct prior flags")
	game.assets.get_line_edit().set_block_signals(false)
	await replacement_guard_case(game)
	# Actual Start and real normal/lab transitions, using native Return every time.
	for id in [game.PRICED_WORKOUT_CASE, game.WORKOUT_CASE, "supply_shock", game.Career.DEFAULT_SCENARIO]:
		game.starts.clear()
		game.activity_response.get_line_edit().set_block_signals(true)
		var start_flags := signal_flags(game)
		game._new_dialog()
		await settle()
		picker = modal(game)
		if id in picker.primary_ids:
			picker.primary_buttons[picker.primary_ids.find(id)].grab_focus()
			await key(picker, KEY_ENTER)
		else:
			picker.select_id(id)
		game.seed_input.value = 417
		await settle()
		picker.get_ok_button().grab_focus()
		await key(picker, KEY_ENTER)
		check(game.starts == [[id, 417]] and not is_instance_valid(picker), "explicit native Start dispatches exactly once with selected ID/seed: " + id)
		check(game.entry_signal_states.is_empty() and signal_flags(game) == start_flags and game.rate.get_line_edit().text != "replacement pending", "successful Start releases protection without restoring old-career drafts")
		check(game.career.seed_value == 417 and game.career.decisions.is_empty(), "real new career is initialized only after Start")
		check(game._is_workout() == (id in [game.PRICED_WORKOUT_CASE, game.WORKOUT_CASE]) and game._is_priced_workout() == (id == game.PRICED_WORKOUT_CASE), "normal/lab switching uses existing mode implementation")
		check(FileAccess.get_file_as_bytes(game.save_path) == saved, "explicit Start never writes the prior normal save")
		game.activity_response.get_line_edit().set_block_signals(false)
	# Same-frame repeat confirmation must not invoke the existing starter twice.
	game.starts.clear()
	game._new_dialog()
	await settle()
	picker = modal(game)
	picker.get_ok_button().pressed.emit()
	picker.confirmed.emit()
	check(game.starts == [[game.Career.DEFAULT_SCENARIO, 1]], "queued close and duplicate confirmation cannot double-dispatch Start")
	await settle()
	await layout_checks(game)
	# Parent tree exit is also a release path, even with a live picker.
	game.rate.get_line_edit().text = "tree exit pending"
	game.guidance.get_line_edit().set_block_signals(true)
	var exit_flags := signal_flags(game)
	var exit_drafts := drafts(game)
	game._new_dialog()
	check(game.entry_signal_states.size() == 6, "tree-exit fixture holds an actual picker guard")
	root.remove_child(game)
	check(game.entry_signal_states.is_empty() and signal_flags(game) == exit_flags and drafts(game) == exit_drafts, "parent tree exit restores drafts and prior flags without leaving blocked edits")
	print("ENTRY_PICKER_CHECKS ", checks, " FAILURES ", failures)
	if failures == 0:
		print("PASS: production career opening picker ", checks, " checks; native headless keys, guarded storage, not GUI acceptance")
	game.free()
	var audio_deadline := Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < audio_deadline:
		await process_frame
	quit(1 if failures else 0)

func layout_checks(game: Control) -> void:
	var density := maxf(1.0, DisplayServer.screen_get_scale(root.current_screen))
	for logical in [Vector2i(1440, 960), Vector2i(800, 480), Vector2i(520, 480)]:
		root.size = Vector2i((Vector2(logical) * density).round())
		await settle()
		game.rate.get_line_edit().grab_focus()
		var before: PackedByteArray = game.career.encode()
		var previews: int = game.previews
		game._new_dialog()
		await settle()
		var picker = modal(game)
		# Inspect the untouched initial viewport, before any manual scroll reset.
		if logical.x >= 800:
			for button in picker.primary_buttons:
				check(picker.scroll.get_global_rect().grow(1).encloses(button.get_global_rect()) and picker.scroll.get_global_rect().grow(1).encloses(button.caption.get_global_rect()), "initial opening shows every full primary title/cue without a scroll reset at " + str(logical))
		var replacement_warning: Label
		for label in picker.find_children("*", "Label", true, false):
			if label.text == "Start replaces unsaved decisions. Nothing is saved automatically.":
				replacement_warning = label
		check(replacement_warning != null and not picker.scroll.is_ancestor_of(replacement_warning) and picker.get_visible_rect().grow(1).encloses(replacement_warning.get_global_rect()), "replacement warning is persistent and fully visible outside the scroller at " + str(logical))
		if replacement_warning != null:
			check(replacement_warning.get_theme_font_size("font_size") == picker.primary_buttons[0].caption.get_theme_font_size("font_size") and replacement_warning.get_line_count() <= 2, "fixed warning retains ordinary readable type and bounded wrapping")
			check(replacement_warning.get_global_rect().end.y <= picker.cancel.get_global_rect().position.y and picker.cancel.get_global_rect().position.y - replacement_warning.get_global_rect().end.y <= 24, "replacement warning stays immediately above the native action row")
		print("INITIAL_ENTRY logical=", logical, " scroll=", picker.scroll.scroll_vertical, " first=", picker.primary_buttons[0].get_global_rect(), " viewport=", picker.scroll.get_global_rect())
		var decorated := Rect2(Vector2(picker.get_position_with_decorations()), Vector2(picker.get_size_with_decorations()))
		check(root.get_visible_rect().grow(1).encloses(decorated), "picker chrome bounded at " + str(logical))
		check(picker.get_visible_rect().grow(1).encloses(picker.scroll.get_global_rect()), "scroll body bounded at " + str(logical))
		for button in [picker.cancel, picker.get_ok_button()]:
			check(picker.get_visible_rect().grow(1).encloses(button.get_global_rect()), "fixed explicit action reachable at " + str(logical))
		check(picker.cards.columns == (2 if picker.scroll.size.x >= 600 else 1), "choice grid reflows without font scaling")
		if logical.x >= 800:
			picker.scroll.scroll_vertical = 0
			await settle()
			for button in picker.primary_buttons:
				check(picker.scroll.get_global_rect().grow(1).encloses(button.get_global_rect()), "all four primary choices immediately visible at " + str(logical))
		check(picker.primary_buttons[0].has_focus() and picker.scroll.get_global_rect().grow(1).encloses(picker.primary_buttons[0].get_global_rect()) and not picker._focus_reveal_pending, "initial selected choice has visible settled focus without polling")
		var visited: Array = []
		var expected_order: Array = []
		expected_order.append_array(picker.primary_buttons)
		expected_order.append_array([picker.scenario, picker.seed_input.get_line_edit(), picker.details_button, picker.cancel, picker.get_ok_button(), picker.scroll])
		for expected in expected_order:
			var focused: Control = picker.gui_get_focus_owner()
			check(focused == expected, "native Tab follows the complete visible primary/selector/seed/details/action sequence")
			if focused != null:
				visited.append(focused)
				check(replacement_warning != null and picker.get_visible_rect().grow(1).encloses(replacement_warning.get_global_rect()) and not picker.scroll.get_global_rect().intersects(replacement_warning.get_global_rect()), "replacement warning remains beside actions through the complete focus cycle")
				if picker.content.is_ancestor_of(focused):
					if not picker.scroll.get_global_rect().grow(2).encloses(focused.get_global_rect()):
						printerr("ENTRY_FOCUS_DIAG logical=%s control=%s rect=%s viewport=%s bar=%s page=%s pending=%s" % [str(logical), str(focused), str(focused.get_global_rect()), str(picker.scroll.get_global_rect()), str(picker.scroll.scroll_vertical), str(picker.scroll.get_v_scroll_bar().page), str(picker._focus_reveal_pending)])
					check(picker.scroll.get_global_rect().grow(2).encloses(focused.get_global_rect()), "native focus-follow scroll reveals tab target at " + str(logical))
			await key(picker, KEY_TAB)
		for control in [picker.scenario, picker.seed_input.get_line_edit(), picker.cancel, picker.get_ok_button(), picker.details_button, picker.scroll] + picker.primary_buttons:
			check(control in visited, "complete forward native Tab cycle includes " + control.get_class())
		picker.scenario.grab_focus()
		await key(picker, KEY_TAB, false, true)
		check(picker.primary_buttons[-1].has_focus(), "ShiftTab returns from All scenarios to the last visible primary choice")
		picker.primary_buttons[0].grab_focus()
		await key(picker, KEY_TAB, false, true)
		check(picker.scroll.has_focus(), "ShiftTab wraps from the first primary choice to scrolling")
		if logical.x <= 800:
			for code in [KEY_END, KEY_HOME, KEY_PAGEDOWN, KEY_PAGEUP]:
				picker._schedule_focus_reveal()
				check(picker._focus_reveal_pending, "manual reading navigation starts with an older queued reveal")
				var before_manual: int = picker.scroll.scroll_vertical
				press_without_frame(picker, code)
				var manual: int = picker.scroll.scroll_vertical
				check(manual != before_manual and not picker._focus_reveal_pending, "native Page/Home/End moves reading scroll and disconnects the older reveal")
				await process_frame
				await process_frame
				check(picker.scroll.scroll_vertical == manual and not picker._focus_reveal_pending, "older reveal cannot undo explicit reading navigation")
		await key(picker, KEY_END)
		check(picker.scroll.scroll_vertical > 0 or picker.scroll.get_v_scroll_bar().max_value <= picker.scroll.get_v_scroll_bar().page, "native scroll End reaches lower content")
		picker.details_button.grab_focus()
		await key(picker, KEY_ENTER)
		await key(picker, KEY_TAB)
		check(picker.details.has_focus() and picker.scroll.get_global_rect().grow(2).encloses(picker.details.get_global_rect()), "expanded detail remains focus-scroll reachable at " + str(logical))
		var details_scroll: int = picker.scroll.scroll_vertical
		picker.details.set_caret_line(0)
		picker.details.set_caret_column(5)
		await key(picker, KEY_HOME)
		check(picker.details.get_caret_column() == 0 and picker.scroll.scroll_vertical == details_scroll, "details Home retains native text navigation instead of moving the body")
		await key(picker, KEY_END)
		check(picker.details.get_caret_column() > 0 and picker.scroll.scroll_vertical == details_scroll, "details End retains native text navigation instead of moving the body")
		# Fit the same open production modal after the parent shrinks.
		root.size = Vector2i((Vector2(800, 480) * density).round())
		await settle()
		check(root.get_visible_rect().grow(1).encloses(Rect2(Vector2(picker.get_position_with_decorations()), Vector2(picker.get_size_with_decorations()))), "open picker refits when parent shrinks")
		await key(picker, KEY_ESCAPE)
		check(game.career.encode() == before and game.previews == previews and game.rate.get_line_edit().has_focus(), "layout, scrolling and cancellation do not forecast/adopt and restore focus")
