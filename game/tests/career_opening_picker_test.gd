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

func drafts(game: Control) -> PackedByteArray:
	var rows: Array = []
	for input in [game.rate, game.guidance, game.assets, game.liquidity, game.inflation_response, game.activity_response]:
		rows.append([input.value, input.get_line_edit().text])
	return var_to_bytes(rows)

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
	check(game.scenario.has_focus(), "existing scenario-first keyboard opening is preserved")
	check(game.scenario.get_item_metadata(game.scenario.selected) == game.Career.DEFAULT_SCENARIO and game.seed_input.value == 1, "unchanged policy_career default and seed 1")
	check(picker.primary_ids == ["policy_career", "stagflation_bank_run", "__priced_bank_workout", "__bank_workout"], "four primary cards use the actual production constant IDs")
	check(picker.primary_buttons.size() == 4, "all four choices exist immediately")
	check(game.scenario.item_count == game.career.cases.size() + 2, "all normal cases and both labs remain in the selector")
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
	# Independent failure fixture, after the separately asserted pointer path.
	var failure_career: PackedByteArray = game.career.encode()
	var failure_drafts := drafts(game)
	# Failure dispatched through actual Start retains the current career/drafts/save.
	game._new_dialog()
	await settle()
	picker = modal(game)
	picker.scenario.set_item_metadata(picker.scenario.selected, "unknown-entry-validation-case")
	picker.get_ok_button().grab_focus()
	await key(picker, KEY_ENTER)
	check(game.starts == [["unknown-entry-validation-case", 1]] and game.status_label.text == "Unknown scenario", "explicit Start preserves existing validation failure feedback")
	check(game.career.encode() == failure_career and drafts(game) == failure_drafts and FileAccess.get_file_as_bytes(game.save_path) == saved, "failed Start cannot reset career, submit policy drafts or overwrite save")
	# Actual Start and real normal/lab transitions, using native Return every time.
	for id in [game.PRICED_WORKOUT_CASE, game.WORKOUT_CASE, "supply_shock", game.Career.DEFAULT_SCENARIO]:
		game.starts.clear()
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
		check(game.career.seed_value == 417 and game.career.decisions.is_empty(), "real new career is initialized only after Start")
		check(game._is_workout() == (id in [game.PRICED_WORKOUT_CASE, game.WORKOUT_CASE]) and game._is_priced_workout() == (id == game.PRICED_WORKOUT_CASE), "normal/lab switching uses existing mode implementation")
		check(FileAccess.get_file_as_bytes(game.save_path) == saved, "explicit Start never writes the prior normal save")
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
		var visited: Array = []
		picker.scenario.grab_focus()
		for step in range(11):
			var focused: Control = picker.gui_get_focus_owner()
			if focused != null:
				visited.append(focused)
				if picker.content.is_ancestor_of(focused):
					check(picker.scroll.get_global_rect().grow(2).encloses(focused.get_global_rect()), "native focus-follow scroll reveals tab target at " + str(logical))
			await key(picker, KEY_TAB)
		for control in [picker.scenario, picker.seed_input.get_line_edit(), picker.cancel, picker.get_ok_button(), picker.details_button, picker.scroll] + picker.primary_buttons:
			check(control in visited, "complete forward native Tab cycle includes " + control.get_class())
		picker.scenario.grab_focus()
		await key(picker, KEY_TAB, false, true)
		check(picker.scroll.has_focus(), "ShiftTab reaches scroll from selector")
		await key(picker, KEY_END)
		check(picker.scroll.scroll_vertical > 0 or picker.scroll.get_v_scroll_bar().max_value <= picker.scroll.get_v_scroll_bar().page, "native scroll End reaches lower content")
		picker.details_button.grab_focus()
		await key(picker, KEY_ENTER)
		await key(picker, KEY_TAB)
		check(picker.details.has_focus() and picker.scroll.get_global_rect().grow(2).encloses(picker.details.get_global_rect()), "expanded detail remains focus-scroll reachable at " + str(logical))
		# Fit the same open production modal after the parent shrinks.
		root.size = Vector2i((Vector2(800, 480) * density).round())
		await settle()
		check(root.get_visible_rect().grow(1).encloses(Rect2(Vector2(picker.get_position_with_decorations()), Vector2(picker.get_size_with_decorations()))), "open picker refits when parent shrinks")
		await key(picker, KEY_ESCAPE)
		check(game.career.encode() == before and game.previews == previews and game.rate.get_line_edit().has_focus(), "layout, scrolling and cancellation do not forecast/adopt and restore focus")
