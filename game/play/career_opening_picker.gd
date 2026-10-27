extends "res://play/report_dialog.gd"
## Selection only. Main owns the explicit Start action and career validation.
var scenario: OptionButton
var seed_input: SpinBox
var scroll: ScrollContainer
var replacement_warning: Label
var content: VBoxContainer
var cards: GridContainer
var primary_buttons: Array[Button] = []
var primary_ids: Array[String] = []
var summary: Label
var details_button: Button
var details: TextEdit
var cancel: Button
var _cases: Dictionary
var _lab_help: Dictionary
var _runoff_id := ""
var _submitted := false
var _focus_reveal_pending := false

class OpeningChoice:
	extends Button
	var marker := 0
	var caption: Label
	func configure(title: String, cue: String, shape: int) -> void:
		marker = shape
		toggle_mode = true
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(0, 84)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 38)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_top", 8)
		margin.add_theme_constant_override("margin_bottom", 8)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(margin)
		caption = Label.new()
		caption.text = title + "\n" + cue
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(caption)
		margin.minimum_size_changed.connect(func(): custom_minimum_size.y = maxf(84, margin.get_combined_minimum_size().y))
		accessibility_name = title
		accessibility_description = cue + ". Selects only; use Start to begin."
	func _draw() -> void:
		# Original geometric mode markers, not simulated data or trend graphics.
		var c := Color("75d4c0") if button_pressed else Color("a4babe")
		var p := Vector2(19, size.y * 0.5)
		match marker:
			0: draw_arc(p, 7, 0, TAU, 24, c, 2, true)
			1: draw_colored_polygon(PackedVector2Array([p + Vector2(0, -8), p + Vector2(8, 7), p + Vector2(-8, 7)]), c)
			2:
				draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), c, false, 2)
				draw_line(p + Vector2(-4, 0), p + Vector2(4, 0), c, 2)
			4:
				draw_line(p + Vector2(-7, 7), p + Vector2(7, 7), c, 2)
				draw_line(p + Vector2(7, 7), p + Vector2(7, -7), c, 2)
			3: draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), c, false, 2)

func build(cases: Dictionary, default_id: String, priced_id: String, workout_id: String, lab_help: Dictionary, runoff_id: String = "") -> void:
	_runoff_id = runoff_id
	_cases = cases
	_lab_help = lab_help
	title = "Start a new career"
	get_ok_button().text = "Start"
	cancel = add_button("Cancel", true)
	cancel.pressed.connect(queue_free)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	add_child(body)
	scroll = ScrollContainer.new()
	# Native synchronous focus following can see transient wrapped-card heights.
	# Reveal current focus once actual layout/focus events have coalesced.
	scroll.follow_focus = false
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	cards = GridContainer.new()
	cards.columns = 2
	cards.add_theme_constant_override("h_separation", 8)
	cards.add_theme_constant_override("v_separation", 8)
	content.add_child(cards)
	primary_ids.assign([default_id, "stagflation_bank_run", priced_id, workout_id])
	var titles := [str(cases[default_id].label), str(cases.stagflation_bank_run.label), "Bank workout · borrowing costs", "Bank workout · 8-meeting laboratory"]
	var cues := ["60 years / Q240 · recurring dilemmas", "7% inflation · −3% gap\nImmediate funding · through Q240", "8 meetings · UNSAVED\nBorrowing costs / equity", "8 meetings · UNSAVED\nCash / collateral / rollover"]
	if not runoff_id.is_empty():
		primary_ids.append(runoff_id)
		titles.append("Bank runoff · to maturity")
		cues.append("20 meetings · UNSAVED\nThrough final maturity Q20")
	for index in range(primary_ids.size()):
		var choice := OpeningChoice.new()
		choice.configure(titles[index], cues[index], index)
		cards.add_child(choice)
		primary_buttons.append(choice)
		choice.pressed.connect(func(): select_id(primary_ids[index]))
	_label("All scenarios")
	scenario = OptionButton.new()
	scenario.accessibility_name = "Career scenario"
	scenario.fit_to_longest_item = false
	scenario.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(scenario)
	for case_id in cases:
		scenario.add_item(cases[case_id].label)
		scenario.set_item_metadata(scenario.item_count - 1, case_id)
	for pair in [[priced_id, titles[2]], [workout_id, titles[3]]]:
		scenario.add_item(pair[1])
		scenario.set_item_metadata(scenario.item_count - 1, pair[0])
	if not runoff_id.is_empty():
		scenario.add_item("Bank runoff · to maturity")
		scenario.set_item_metadata(scenario.item_count - 1, runoff_id)
	scenario.item_selected.connect(func(_index: int): _selection_changed())
	summary = _label("")
	var seed_row := HBoxContainer.new()
	content.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "Scenario seed"
	seed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(seed_label)
	seed_input = SpinBox.new()
	seed_input.min_value = 1
	seed_input.max_value = 2147483647
	seed_input.step = 1
	seed_input.custom_arrow_step = 1
	seed_input.custom_minimum_size.x = 150
	seed_input.accessibility_name = "Scenario seed"
	seed_input.tooltip_text = "Same scenario and seed reproduce the path within the same engine and model."
	seed_row.add_child(seed_input)
	var edit := seed_input.get_line_edit()
	edit.keep_editing_on_text_submit = true
	edit.accessibility_name = "Scenario seed"
	edit.tooltip_text = seed_input.tooltip_text
	seed_input.set_meta("numeric_text", edit.text)
	seed_input.set_meta("numeric_text_pending", true)
	seed_input.value_changed.connect(func(_value: float):
		seed_input.set_meta("numeric_text", edit.text)
		seed_input.set_meta("numeric_text_pending", true))
	seed_input.draw.connect(func():
		if seed_input.get_meta("numeric_text_pending"):
			seed_input.set_meta("numeric_text", edit.text)
			seed_input.set_meta("numeric_text_pending", false))
	details_button = Button.new()
	details_button.text = "Details & assumptions"
	details_button.toggle_mode = true
	content.add_child(details_button)
	details = TextEdit.new()
	details.editable = false
	details.add_theme_color_override("font_readonly_color", Color("e7eee9"))
	details.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	details.tab_input_mode = false
	details.custom_minimum_size.y = 180
	details.hide()
	content.add_child(details)
	details_button.toggled.connect(func(expanded: bool):
		details.visible = expanded
		_link_focus())
	_label("Every career includes seeded background disturbances, even the baseline.")
	replacement_warning = Label.new()
	replacement_warning.text = "Start replaces unsaved decisions. Nothing is saved automatically."
	replacement_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	replacement_warning.accessibility_name = replacement_warning.text
	body.add_child(replacement_warning)
	scroll.resized.connect(_reflow)
	scroll.resized.connect(_schedule_focus_reveal)
	body.sort_children.connect(_schedule_focus_reveal)
	content.sort_children.connect(_schedule_focus_reveal)
	for container in content.find_children("*", "Container", true, false):
		container.sort_children.connect(_schedule_focus_reveal)
	gui_focus_changed.connect(func(_control: Control): _schedule_focus_reveal())
	scroll.gui_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed and not event.is_command_or_control_pressed():
			var focused := gui_get_focus_owner()
			if focused is LineEdit or focused is TextEdit or event.keycode not in [KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END]:
				return
			_cancel_focus_reveal()
			match event.keycode:
				KEY_PAGEUP: scroll.scroll_vertical -= int(scroll.size.y)
				KEY_PAGEDOWN: scroll.scroll_vertical += int(scroll.size.y)
				KEY_HOME: scroll.scroll_vertical = 0
				KEY_END: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
				_: return
			scroll.accept_event())
	select_id(default_id)

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(label)
	return label

func select_id(id: String) -> void:
	for index in range(scenario.item_count):
		if scenario.get_item_metadata(index) == id:
			scenario.select(index)
			_selection_changed()
			return

func _selection_changed() -> void:
	var id: String = scenario.get_item_metadata(scenario.selected)
	for index in range(primary_buttons.size()):
		primary_buttons[index].set_pressed_no_signal(primary_ids[index] == id)
	if id == "stagflation_bank_run":
		summary.text = "Recovery v1: rolling stabilization, not a 12-quarter ending. Continues to Q240."
	elif not _runoff_id.is_empty() and id == _runoff_id:
		summary.text = "20 meetings through final maturity Q20. Seeded macro shocks continue. No normal career awards or saves."
	elif id in _lab_help:
		summary.text = "Eight-meeting unsaved exercise. No normal career awards or saves."
	elif id in [primary_ids[0], "unanchored_inflation"]:
		summary.text = "60 years / Q240 · Mandate v1 eligible."
	else:
		summary.text = "60 years / Q240 · practice scenario."
	details.text = str(_lab_help[id]) if id in _lab_help else str(_cases[id].description) + "\n\nEvery career includes seeded background disturbances. Hypothetical economy, not a historical forecast."
	details.accessibility_name = "Selected scenario details"
	details.accessibility_description = details.text
	_link_focus()

func _reflow() -> void:
	cards.columns = 2 if scroll.size.x >= 600 else 1
	for index in range(primary_buttons.size()):
		var button := primary_buttons[index]
		var column := index % cards.columns
		button.focus_neighbor_left = button.get_path_to(primary_buttons[index - 1] if column > 0 else button)
		button.focus_neighbor_right = button.get_path_to(primary_buttons[index + 1] if column + 1 < cards.columns and index + 1 < primary_buttons.size() else button)
		button.focus_neighbor_top = button.get_path_to(primary_buttons[index - cards.columns] if index >= cards.columns else button)
		button.focus_neighbor_bottom = button.get_path_to(primary_buttons[index + cards.columns] if index + cards.columns < primary_buttons.size() else button)

func _link_focus() -> void:
	# Follow the visible choices first, then retain selector → seed and the
	# conservative Cancel-before-Start route after optional reading.
	var order: Array[Control] = []
	order.append_array(primary_buttons)
	order.append_array([scenario, seed_input.get_line_edit(), details_button])
	if details.visible:
		order.append(details)
	order.append_array([cancel, get_ok_button(), scroll])
	for index in range(order.size()):
		order[index].focus_next = order[index].get_path_to(order[(index + 1) % order.size()])
		order[index].focus_previous = order[index].get_path_to(order[(index - 1 + order.size()) % order.size()])

func _schedule_focus_reveal() -> void:
	if _focus_reveal_pending or not is_inside_tree() or not visible or is_queued_for_deletion():
		return
	_focus_reveal_pending = true
	get_tree().process_frame.connect(_reveal_current_focus, CONNECT_ONE_SHOT)

func _cancel_focus_reveal() -> void:
	if _focus_reveal_pending:
		if get_tree().process_frame.is_connected(_reveal_current_focus):
			get_tree().process_frame.disconnect(_reveal_current_focus)
		_focus_reveal_pending = false

func _reveal_current_focus() -> void:
	_focus_reveal_pending = false
	if not is_inside_tree() or not visible or is_queued_for_deletion():
		return
	var focused := gui_get_focus_owner()
	if focused != null and content.is_ancestor_of(focused):
		# Absolute unscrolled coordinates cannot double-count a bar update whose
		# deferred ScrollContainer reposition has not run yet.
		var relative := content.get_global_transform().affine_inverse() * focused.get_global_transform()
		var rect: Rect2 = relative * Rect2(Vector2.ZERO, focused.size)
		for axis in [HORIZONTAL, VERTICAL]:
			var bar: ScrollBar = scroll.get_h_scroll_bar() if axis == HORIZONTAL else scroll.get_v_scroll_bar()
			if rect.position[axis] < bar.value:
				bar.value = floorf(rect.position[axis])
			elif rect.end[axis] > bar.value + bar.page:
				bar.value = ceilf(rect.end[axis] - bar.page)

func claim_start() -> bool:
	if _submitted:
		return false
	_submitted = true
	get_ok_button().disabled = true
	return true

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		# Reading/selecting never confirms. Let native buttons/fields handle Return;
		# do not inherit ReportDialog's Return-to-dismiss reading-surface behavior.
		if event.is_command_or_control_pressed():
			if gui_get_focus_owner() == seed_input.get_line_edit():
				seed_input.apply()
			set_input_as_handled()
		return
	super._input(event)
