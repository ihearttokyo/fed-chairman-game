extends Control

const Career = preload("res://play/career.gd")
const Chart = preload("res://play/history_chart.gd")
const SAVE_PATH := "user://career-late-compound-v1.save"
const GOLD := Color("e9b76e")
const MINT := Color("75d4c0")
const MUTED := Color("a4babe")
var career := Career.new()
var stats: Array = []
var charts: Array = []
var quarter_label: Label
var case_title: Label
var case_detail: Label
var briefing: Label
var consequence: Label
var mandate_label: Label
var forecast_label: Label
var status_label: Label
var rate: SpinBox
var guidance: SpinBox
var assets: SpinBox
var liquidity: SpinBox
var reinvestment: CheckBox
var reserve_maintenance: CheckBox
var sterilization: CheckBox
var commitment: OptionButton
var custom_guidance: VBoxContainer
var inflation_response: SpinBox
var activity_response: SpinBox
var scenario: OptionButton
var seed_input: SpinBox
var city: Node3D
var reduced_motion := true
var decision_button: Button
var loading_controls := false
var keyboard_controls: Array[Control] = []
var cockpit_scroll: ScrollContainer
var body_layout: BoxContainer
var action_layout: BoxContainer
var save_path := SAVE_PATH
var clean_career: PackedByteArray
var quit_dialog: AcceptDialog

const KEYBOARD_HELP := "Keyboard controls\nTab / Shift+Tab move forward / back through visible controls. Return or Space activates a focused button. In numeric fields, type a value and press Return to commit only that field; Up / Down use its advertised step. Arrow keys navigate open scenario or guidance menus; Return selects and Escape cancels.\n\nCharts: Left / Right inspect completed quarters; Home / End select the first / latest. Focused cockpit and reports: Page Up / Down scroll, Home / End reach the ends. Escape closes a report or cancels replacement and returns focus.\n\nOptional accelerators use Cmd on macOS or Ctrl elsewhere: N New, S Save, O Load, J journal, P Compare, R staff rule, modified Return adopt one quarter. F1 opens this guide. Every command also has a Tab-accessible control; plain typing never adopts a quarter.\n\n"

func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(_request_quit)
	_fit_initial_window()
	_resize_layout()
	_apply_theme()
	var background := ColorRect.new()
	background.color = Color("0c191f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	var scroll := ScrollContainer.new()
	cockpit_scroll = scroll
	scroll.follow_focus = true
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.accessibility_name = "Meeting cockpit"
	scroll.accessibility_description = "Page Up and Page Down scroll the cockpit. Home and End jump to its ends. Tab continues to the next control."
	scroll.gui_input.connect(_scroll_key)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var action_margin := MarginContainer.new()
	for side in ["left", "right"]:
		action_margin.add_theme_constant_override("margin_" + side, 24)
	action_margin.add_theme_constant_override("margin_top", 8)
	action_margin.add_theme_constant_override("margin_bottom", 16)
	layout.add_child(action_margin)
	action_layout = BoxContainer.new()
	action_layout.alignment = BoxContainer.ALIGNMENT_END
	action_layout.add_theme_constant_override("separation", 12)
	action_margin.add_child(action_layout)
	var feedback := _vbox(action_layout, 5)
	feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	consequence = _label(feedback, "", 14, MINT)
	consequence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	consequence.accessibility_live = AccessibilityServer.LIVE_POLITE
	mandate_label = _label(feedback, "", 13, GOLD)
	mandate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mandate_label.accessibility_live = AccessibilityServer.LIVE_POLITE
	status_label = _label(feedback, "", 13, MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.accessibility_live = AccessibilityServer.LIVE_POLITE
	var action_buttons := HBoxContainer.new()
	action_buttons.alignment = BoxContainer.ALIGNMENT_END
	action_buttons.add_theme_constant_override("separation", 12)
	action_layout.add_child(action_buttons)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)
	_build_header(root)
	var cards := HFlowContainer.new()
	cards.add_theme_constant_override("h_separation", 12)
	cards.add_theme_constant_override("v_separation", 12)
	root.add_child(cards)
	for heading in ["INFLATION", "UNEMPLOYMENT", "CREDIBILITY", "PUBLIC SUPPORT"]:
		var panel := _panel(cards)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.get_theme_stylebox("panel").set_content_margin_all(10)
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		panel.add_child(box)
		_label(box, heading, 12, MUTED)
		var value := _label(box, "", 20, GOLD if stats.size() == 0 else Color("e7eee9"))
		value.mouse_filter = Control.MOUSE_FILTER_PASS
		value.accessibility_name = heading
		var note := _label(box, "", 11, MUTED)
		note.visible = stats.size() < 2
		stats.append([value, note])
	body_layout = BoxContainer.new()
	body_layout.add_theme_constant_override("separation", 18)
	root.add_child(body_layout)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	left.custom_minimum_size.x = 630
	body_layout.add_child(left)
	_build_city(left)
	var brief_box := _vbox(_panel(left), 5)
	_label(brief_box, "Meeting dispatch", 12, GOLD)
	briefing = _label(brief_box, "", 14)
	briefing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing.mouse_filter = Control.MOUSE_FILTER_PASS
	var chart_row := HBoxContainer.new()
	chart_row.add_theme_constant_override("separation", 20)
	left.add_child(chart_row)
	for n in range(2):
		var chart := Chart.new()
		chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if n == 1:
			chart.heading = "UNEMPLOYMENT & STRUCTURAL REFERENCE"
			chart.keys = ["unemployment_rate_pct", "structural_unemployment_pct"]
			chart.labels = ["Unemployment", "Structural reference"]
		chart_row.add_child(chart)
		charts.append(chart)
		keyboard_controls.append(chart)
	_build_policy(body_layout, action_buttons)
	_start_career("unanchored_inflation", 1)
	get_window().size_changed.connect(_resize_layout)
	get_window().dpi_changed.connect(_resize_layout)
	_resize_layout()
	keyboard_controls.append(scroll)
	_link_focus(_keyboard_focus_order())
	rate.get_line_edit().grab_focus.call_deferred()
	cockpit_scroll.set_deferred("scroll_vertical", 0)
	if "--verify-build" in OS.get_cmdline_user_args():
		get_tree().quit(load("res://play/build_check.gd").new().run(self))

static func _responsive_canvas_size(physical: Vector2i, display_scale: float) -> Vector2i:
	return Vector2i((Vector2(physical) / maxf(1.0, display_scale)).round()).max(Vector2i.ONE)

func _resize_layout() -> void:
	var window := get_window()
	var logical := _responsive_canvas_size(window.size, DisplayServer.screen_get_scale(window.current_screen))
	if window.content_scale_size != logical:
		window.content_scale_size = logical
	if body_layout == null:
		return
	# Reserve the scrollbar even before it appears, avoiding breakpoint oscillation.
	var available := window.get_visible_rect().size.x - 48 - cockpit_scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var wide_minimum: float = body_layout.get_child(0).get_combined_minimum_size().x + body_layout.get_child(1).get_combined_minimum_size().x + body_layout.get_theme_constant("separation")
	body_layout.vertical = available < wide_minimum
	action_layout.vertical = body_layout.vertical

static func _initial_window_size(design: Vector2i, display_scale: float, available: Vector2i) -> Vector2i:
	var desired := Vector2(design) * display_scale
	var fit := minf(1.0, minf(available.x / desired.x, available.y / desired.y))
	return Vector2i((desired * fit).round()).min(available)

func _fit_initial_window() -> void:
	var window := get_window()
	if OS.get_name() != "macOS" or DisplayServer.get_name() == "headless" or window.mode != Window.MODE_WINDOWED:
		return
	if window.size != window.content_scale_size:
		return
	# Godot consumes native window flags before exposing its GDScript argument list.
	var launch: Array = []
	if OS.execute("/bin/ps", ["-ww", "-p", str(OS.get_process_id()), "-o", "command="], launch) != 0 or launch.is_empty() or String(launch[0]).strip_edges().is_empty():
		return
	if String(launch[0]).contains("--position") or String(launch[0]).contains("--resolution"):
		return
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
	var decoration_size := window.get_size_with_decorations() - window.size
	var decoration_offset := window.position - window.get_position_with_decorations()
	var available := usable.size - decoration_size
	if available.x <= 0 or available.y <= 0:
		return
	window.size = _initial_window_size(window.content_scale_size, DisplayServer.screen_get_scale(window.current_screen), available)
	window.position = usable.position + (usable.size - window.get_size_with_decorations()) / 2 + decoration_offset

func _apply_theme() -> void:
	var design := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Avenir Next", "DejaVu Sans"])
	design.default_font = font
	design.default_font_size = 14
	design.set_color("font_color", "Label", Color("e7eee9"))
	for node_type in ["Button", "OptionButton", "LineEdit", "SpinBox"]:
		design.set_color("font_color", node_type, Color("e7eee9"))
		design.set_color("font_hover_color", node_type, Color.WHITE)
		for state_name in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("203740") if state_name == "normal" else Color("34505a")
			style.set_corner_radius_all(5)
			style.set_content_margin_all(9)
			style.border_color = GOLD if state_name == "focus" else Color("46626a")
			style.set_border_width_all(2 if state_name == "focus" else 1)
			design.set_stylebox(state_name, node_type, style)
	var dialog_style := StyleBoxFlat.new()
	dialog_style.bg_color = Color("14282f")
	dialog_style.set_content_margin_all(18)
	dialog_style.set_border_width_all(1)
	dialog_style.border_color = Color("527078")
	design.set_stylebox("panel", "AcceptDialog", dialog_style)
	theme = design

func _panel(parent: Node) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("14282f")
	style.border_color = Color("2c454c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _vbox(parent: Node, separation := 10) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box

func _label(parent: Node, text: String, size_px := 14, color := Color("e7eee9")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable, code: Key = KEY_NONE, command := true) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	keyboard_controls.append(button)
	if code != KEY_NONE:
		var event := InputEventKey.new()
		event.keycode = code
		event.command_or_control_autoremap = command
		button.shortcut = Shortcut.new()
		button.shortcut.events = [event]
	return button

func _keyboard_focus_order() -> Array[Control]:
	var order: Array[Control] = []
	for control in keyboard_controls:
		if control.is_visible_in_tree() and not (control is BaseButton and control.disabled):
			order.append(control)
	return order

func _link_focus(order: Array[Control]) -> void:
	for index in range(order.size()):
		order[index].focus_next = order[index].get_path_to(order[(index + 1) % order.size()])
		order[index].focus_previous = order[index].get_path_to(order[(index - 1 + order.size()) % order.size()])

func _scroll_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.alt_pressed and not event.is_command_or_control_pressed():
		match event.keycode:
			KEY_PAGEUP: cockpit_scroll.scroll_vertical -= int(cockpit_scroll.size.y * 0.8)
			KEY_PAGEDOWN: cockpit_scroll.scroll_vertical += int(cockpit_scroll.size.y * 0.8)
			KEY_HOME: cockpit_scroll.scroll_vertical = 0
			KEY_END: cockpit_scroll.scroll_vertical = int(cockpit_scroll.get_v_scroll_bar().max_value)
			_: return
		cockpit_scroll.accept_event()

func _build_header(parent: Node) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 12)
	parent.add_child(row)
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 12)
	row.add_child(brand)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _label(brand, "THE CHAIR", 31)
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "Liberation Serif"])
	title.add_theme_font_override("font", serif)
	_label(brand, "Federal Reserve Policy Lab", 11, GOLD)
	quarter_label = _label(row, "", 15, MINT)
	_button(row, "New career", _new_dialog, KEY_N)
	var save_button := _button(row, "Save", _save, KEY_S)
	save_button.tooltip_text = "Save to career-late-compound-v1.save. Only this campaign slot is replaced; career-v1.save is untouched."
	save_button.accessibility_description = save_button.tooltip_text
	var load_button := _button(row, "Load", _load, KEY_O)
	load_button.tooltip_text = "Load career-late-compound-v1.save only. No fallback or migration from career-v1.save."
	load_button.accessibility_description = load_button.tooltip_text
	_button(row, "Data & journal", _journal, KEY_J)
	_button(row, "How to play", _help, KEY_F1, false)
	_button(row, "Credits", _credits)

static func _city_texture_size(area: Vector2, physical: Vector2i, logical: Vector2) -> Vector2i:
	var density := 1.0
	if logical.x > 0 and logical.y > 0:
		density = clampf(minf(physical.x / logical.x, physical.y / logical.y), 1.0, 2.0)
	density = minf(density, 2048.0 / maxf(2.0, maxf(area.x, area.y)))
	return Vector2i((area * density).ceil()).max(Vector2i(2, 2))

func _build_city(parent: Node) -> void:
	var panel := _panel(parent)
	var box := _vbox(panel, 3)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(top)
	var motion := CheckButton.new()
	motion.text = "Animate city"
	top.add_child(motion)
	keyboard_controls.append(motion)
	var scene_row := HBoxContainer.new()
	box.add_child(scene_row)
	var context := _vbox(scene_row, 12)
	context.custom_minimum_size.x = 230
	context.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	case_title = _label(context, "", 24, GOLD)
	case_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	case_detail = _label(context, "", 14)
	case_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var container := TextureRect.new()
	container.custom_minimum_size = Vector2(0, 215)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_stretch_ratio = 2.0
	container.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	container.stretch_mode = TextureRect.STRETCH_SCALE
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_row.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2, 2)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.transparent_bg = true
	container.add_child(viewport)
	container.texture = viewport.get_texture()
	var world := Node3D.new()
	viewport.add_child(world)
	city = load("res://assets/policy_city.glb").instantiate()
	world.add_child(city)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18
	camera.position = Vector3(17, 19, 23)
	world.add_child(camera)
	camera.look_at(Vector3(0, 0.8, 0))
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -30, 0)
	key.light_color = Color("ffdfab")
	key.light_energy = 1.6
	key.shadow_enabled = true
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 150, 0)
	fill.light_color = Color("83bbcf")
	fill.light_energy = 0.8
	world.add_child(fill)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("14282f")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b8d7db")
	environment.environment.ambient_light_energy = 0.6
	world.add_child(environment)
	var redraw := func():
		viewport.render_target_update_mode = (SubViewport.UPDATE_ONCE if reduced_motion else SubViewport.UPDATE_ALWAYS) if container.is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	viewport.size_changed.connect(redraw)
	var resize := func():
		viewport.size = _city_texture_size(container.size, get_window().size, get_window().get_visible_rect().size)
		redraw.call()
	container.resized.connect(resize)
	get_window().size_changed.connect(resize)
	container.visibility_changed.connect(redraw)
	motion.toggled.connect(func(enabled: bool):
		reduced_motion = not enabled
		redraw.call())
	resize.call()

func _spin(parent: Node, title: String, low: float, high: float, step_size: float, tip: String) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(row, title, 14)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var input := SpinBox.new()
	input.min_value = low
	input.max_value = high
	input.step = 0.01 if step_size < 1 else step_size
	input.custom_arrow_step = step_size
	input.custom_minimum_size.x = 105
	input.accessibility_name = title
	input.tooltip_text = tip
	var edit := input.get_line_edit()
	edit.keep_editing_on_text_submit = true
	edit.accessibility_name = title
	edit.tooltip_text = tip
	edit.gui_input.connect(func(event: InputEvent):
		# LineEdit consumes Return before button shortcuts, including modified Return.
		if event is InputEventKey and event.pressed and not event.alt_pressed and event.is_command_or_control_pressed() and event.keycode in [KEY_ENTER, KEY_KP_ENTER] and input.get_window() == get_window():
			if not event.echo and not decision_button.disabled:
				_advance()
			edit.accept_event()
			return
		if event is InputEventKey and event.pressed and not event.alt_pressed and not event.is_command_or_control_pressed() and event.keycode in [KEY_UP, KEY_DOWN]:
			_apply_input(input)
			input.value += input.custom_arrow_step * (1 if event.keycode == KEY_UP else -1)
			edit.accept_event())
	# Numeric setters update the visible text on draw; accessible setters only edit text.
	input.set_meta("numeric_text", input.get_line_edit().text)
	input.set_meta("numeric_text_pending", true)
	input.value_changed.connect(func(_v: float):
		input.set_meta("numeric_text", input.get_line_edit().text)
		input.set_meta("numeric_text_pending", true)
		_preview())
	input.draw.connect(func():
		if input.get_meta("numeric_text_pending"):
			input.set_meta("numeric_text", input.get_line_edit().text)
			input.set_meta("numeric_text_pending", false))
	row.add_child(input)
	if input.get_window() == get_window():
		keyboard_controls.append(edit)
	return input

func _portfolio_switch(parent: Node, title: String, enabled: bool, tip: String) -> CheckBox:
	var control := CheckBox.new()
	control.text = title
	control.button_pressed = enabled
	control.accessibility_name = title
	control.tooltip_text = tip
	control.accessibility_description = tip
	control.toggled.connect(func(_enabled: bool): _preview())
	parent.add_child(control)
	keyboard_controls.append(control)
	return control

func _build_policy(parent: Node, actions: Node) -> void:
	var panel := _panel(parent)
	panel.custom_minimum_size.x = 380
	var box := _vbox(panel, 13)
	_label(box, "FOMC DECISION", 18, GOLD)
	rate = _spin(box, "Target midpoint (%)", 0, 15, 0.25, "1bp quotes; 25bp arrows. No nominal rate or change cap. Negative policy is a U.S. counterfactual with diminishing financing benefits.")
	rate.allow_lesser = true
	rate.allow_greater = true
	guidance = _spin(box, "Next-quarter guidance (%)", 0, 15, 0.25, "1bp quotes; 25bp arrows. Signed quotes have no nominal cap. Credibility prices guidance before negative-rate transmission; broken nominal promises reduce follow-through.")
	guidance.allow_lesser = true
	guidance.allow_greater = true
	commitment = OptionButton.new()
	commitment.accessibility_name = "Guidance commitment"
	commitment.add_item("Data-dependent guidance")
	commitment.add_item("Firm rate pledge")
	commitment.add_item("Custom conditional guidance")
	commitment.tooltip_text = "Data dependence adjusts your promise by %.2f × the change in inflation and %.2f × the change in output gap. A firm pledge does not adjust." % [career.params.policy_inflation_response, career.params.policy_output_gap_response]
	commitment.item_selected.connect(func(_i: int): _guidance_controls())
	box.add_child(commitment)
	keyboard_controls.append(commitment)
	custom_guidance = _vbox(box, 6)
	var bound: float = career.params.guidance_sensitivity_limit
	inflation_response = _spin(custom_guidance, "Inflation response", -bound, bound, 0.1, "Adjust the announced rate by this many percentage points for each 1 pp change in four-quarter inflation since the announcement.")
	activity_response = _spin(custom_guidance, "Output-gap response", -bound, bound, 0.1, "Adjust the announced rate by this many percentage points for each 1 pp change in the output gap since the announcement.")
	var units := _label(custom_guidance, "Rate pp per 1 pp change since your announcement. Negative responses reverse the direction; these are game-design choices.", 11, MUTED)
	units.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	assets = _spin(box, "Purchases / runoff cap", -2, 2, 0.25, "Percent of current annual GDP. Positive: purchase long Treasuries. Negative: cap runoff at actual principal due; reinvest the remainder. No purchase or stock ceiling.")
	assets.allow_lesser = true
	assets.allow_greater = true
	var modes := _vbox(box, 0)
	var portfolio_row := HBoxContainer.new()
	modes.add_child(portfolio_row)
	reinvestment = _portfolio_switch(portfolio_row, "Reinvest principal", true, "With zero or positive purchases, roll principal on or allow natural runoff off. A negative runoff cap overrides either setting; no unmatured securities are sold.")
	sterilization = _portfolio_switch(portfolio_row, "Sterilize purchases", false, "Absorb purchase-created reserves through overnight reverse repos. Securities remain assets; duration effects persist. Uptake, collateral and settlement can limit absorption.")
	reserve_maintenance = _portfolio_switch(modes, "Maintain ample reserves", true, "Buy short bills after runoff, currency conversion, lending and absorption to meet the modeled reserve buffer. Bills can change funding conditions but are excluded from the long-duration channel.")
	liquidity = _spin(box, "Liquidity offer", 0, 5, 0.25, "Desired concurrent exposure, percent of current annual GDP. No offer ceiling. Borrower need, eligibility, haircut-adjusted collateral and settlement limit advances; loans do not create bank capital.")
	liquidity.allow_greater = true
	_label(box, "Asset and loan units: % of current annual GDP", 11, MUTED)
	_button(box, "Use staff rate rule", _staff_rule, KEY_R)
	forecast_label = _label(box, "", 13, MINT)
	forecast_label.custom_minimum_size.y = 114
	forecast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(actions, "Compare policy paths", _compare, KEY_P)
	decision_button = _button(actions, "Adopt decision  →  Next quarter", _advance, KEY_ENTER)
	decision_button.custom_minimum_size = Vector2(380, 48)
	var explanation := _label(box, "Preview: this decision, then hold the rate for eight quarters. No new future shocks. This is a conditional path, not a confidence interval.", 11, MUTED)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _policy() -> Dictionary:
	var n: float = career.model.nominal_gdp_ratio(career.state) if not career.state.is_empty() else 1.0
	return {"policy_rate_request_pct": rate.value, "guidance_rate_pct": guidance.value,
		"guidance_inflation_sensitivity": inflation_response.value if commitment.selected == 2 else (career.params.policy_inflation_response if commitment.selected == 0 else 0.0),
		"guidance_output_gap_sensitivity": activity_response.value if commitment.selected == 2 else (career.params.policy_output_gap_response if commitment.selected == 0 else 0.0),
		"asset_flow_request_pct_initial_gdp": assets.value * n, "liquidity_request_pct_initial_gdp": liquidity.value * n,
		"reinvest_principal": reinvestment.button_pressed, "maintain_ample_reserves": reserve_maintenance.button_pressed, "sterilize_purchases": sterilization.button_pressed}

func _apply_policy_inputs() -> void:
	loading_controls = true
	for input in [rate, guidance, assets, liquidity, inflation_response, activity_response]:
		_apply_input(input)
	loading_controls = false

func _apply_input(input: SpinBox) -> void:
	var edit := input.get_line_edit()
	if edit.text != input.get_meta("numeric_text") or (edit.has_focus() and not input.get_meta("numeric_text_pending")):
		input.apply()

func _compare() -> void:
	_apply_policy_inputs()
	_preview()
	var text := _decision_briefing()
	var dialog := AcceptDialog.new()
	dialog.title = "Compare policy paths"
	var box := _vbox(dialog)
	box.custom_minimum_size = Vector2(690, 450)
	_label(box, "Jump to section", 13, MUTED)
	var chooser := OptionButton.new()
	chooser.accessibility_name = "Comparison section"
	chooser.tooltip_text = "Jump within the complete report. All calculations, explanations and limits remain available."
	box.add_child(chooser)
	var body := _read_only_report("Policy comparison report", text)
	body.custom_minimum_size = Vector2.ZERO
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	for section in [["Meeting", "CURRENT MEETING /"], ["Deliberation", "COMMITTEE DELIBERATION /"], ["Guidance", "GUIDANCE /"], ["Guidance continuation", "GUIDANCE CONTINUATION /"], ["Scores", "Q+1 / WHY"], ["Forecasts", "CURRENT TRANSMISSION /"], ["Tools", "ONE-CONTROL CONTRASTS /"], ["Limits", "REFERENCE AND LIMITS"]]:
		var offset := text.find(section[1])
		if offset >= 0:
			chooser.add_item(section[0])
			chooser.set_item_metadata(chooser.item_count - 1, text.substr(0, offset).count("\n"))
	chooser.disabled = chooser.item_count == 0
	chooser.item_selected.connect(func(index): body.set_line_as_first_visible(chooser.get_item_metadata(index)))
	_show_dialog(dialog, Vector2i(740, 540), body)
	_link_focus([chooser, body, dialog.get_ok_button()])

func _guidance_controls() -> void:
	var use_custom := commitment.selected == 2
	var focused: Control = get_viewport().gui_get_focus_owner()
	if not use_custom and focused != null and custom_guidance.is_ancestor_of(focused):
		commitment.grab_focus()
	custom_guidance.visible = use_custom
	_link_focus(_keyboard_focus_order())
	_preview()

func _start_career(case_id: String, seed_number: int) -> void:
	var result: Dictionary = career.start(case_id, seed_number)
	if not result.ok:
		status_label.text = result.error
		return
	clean_career = career.encode()
	_refresh(true)
	consequence.text = "Your first meeting: read the dispatch, compare the policy preview, then adopt a decision. There is no arbitrary unemployment or popularity game-over."
	status_label.text = "New unsaved career · %s · seed %d" % [career.cases[case_id].label, seed_number]

func _refresh(reset_controls := false) -> void:
	var s: Dictionary = career.state
	var complete := career.decisions.size() >= Career.MAX_QUARTERS
	case_title.text = career.cases[career.scenario_id].label
	var n: float = career.model.nominal_gdp_ratio(s)
	case_detail.text = "Holdings %.1f%% · Loans %.2f%% · Reserves %.2f%% · RRP %.2f%%\nUnits: current annual GDP" % [s.asset_stock_pct_initial_gdp / n, s.outstanding_liquidity_pct_initial_gdp / n, s.reserves_pct_initial_gdp / n, s.reverse_repo_pct_initial_gdp / n]
	quarter_label.text = "CAREER COMPLETE · %d MEETINGS" % Career.MAX_QUARTERS if complete else "YEAR %02d / Q%d   ·   MEETING %d" % [int(s.quarter_index / 4) + 1, int(s.quarter_index) % 4 + 1, s.quarter_index + 1]
	var assessment := career.mandate_assessment()
	mandate_label.text = _mandate_summary(assessment)
	mandate_label.tooltip_text = _mandate_rules_text()
	mandate_label.accessibility_description = mandate_label.tooltip_text
	if complete and assessment.eligible:
		quarter_label.text = ("MANDATE ACHIEVED" if assessment.achieved else "MANDATE NOT MET") + " · %d MEETINGS" % Career.MAX_QUARTERS
	stats[0][0].text = "%.2f%%" % s.four_quarter_inflation_pct
	stats[0][1].text = "Target 2%"
	stats[1][0].text = "%.2f%%" % s.unemployment_rate_pct
	stats[1][1].text = "Ref %.2f%%" % s.structural_unemployment_pct
	stats[2][0].text = "%.0f / 100" % (100 * s.credibility)
	stats[2][1].text = "Long expectations %.2f%%" % s.expected_long_inflation_pct
	stats[3][0].text = "%.0f / 100" % s.public_support
	stats[3][1].text = "Hardship memory %.2f" % s.public_hardship_memory
	var metric_details := ["Four-quarter inflation; 2% annual objective.", "Unemployment rate; uncertain structural reference, not a fixed employment target.", stats[2][1].text, stats[3][1].text]
	for index in range(stats.size()):
		stats[index][0].accessibility_name = "%s %s" % [stats[index][0].get_parent().get_child(0).text, stats[index][0].text]
		stats[index][0].tooltip_text = metric_details[index]
		stats[index][0].accessibility_description = metric_details[index]
	for chart in charts:
		chart.history = career.history
		chart.queue_redraw()
	var shock: Dictionary = career.current_briefing()
	var refinancing_request: float = shock.get("refinancing_need_pct_initial_gdp", 0.0)
	var refinancing_need := minf(refinancing_request, s.outstanding_liquidity_pct_initial_gdp)
	var collateral: float = shock.get("eligible_collateral_pct_initial_gdp", 0.0)
	var haircut: float = shock.get("collateral_haircut_pct", 0.0)
	var eligibility: float = shock.get("liquidity_eligibility_pct", 0.0)
	var lending_value := collateral * (1.0 - haircut / 100.0) * (eligibility / 100.0)
	briefing.text = "Demand impulse %+.2f pp · supply innovation %+.2f pp · output gap %+.2f%%." % [shock.get("demand_shock_pct", 0), shock.get("supply_innovation_pct", 0), s.output_gap_pct]
	if shock.get("funding_need_pct_initial_gdp", 0.0) > 0.0 or refinancing_request > 0.0 or s.outstanding_liquidity_pct_initial_gdp > 0.0 or collateral > 0.0:
		briefing.text += "\nFunding need %.2f (new) · Requested refinancing %.2f · Refinancing need %.2f (%% current GDP).\nMaturing principal %.2f (short loans) · Collateral before haircut %.2f · Lending value %.2f (%% current GDP).\nCollateral haircut %.2f%% · Eligibility %.2f%%." % [shock.get("funding_need_pct_initial_gdp", 0) / n, refinancing_request / n, refinancing_need / n, s.outstanding_liquidity_pct_initial_gdp / n, collateral / n, lending_value / n, haircut, eligibility]
	if shock.get("solvency_risk_innovation_pct", 0.0) != 0.0 or s.solvency_risk_wedge_pct != 0.0:
		briefing.text += "\nCurrent impairment impulse %+.2f pp · Prior impairment %.2f pp (spread proxy, not booked bank loss)." % [shock.get("solvency_risk_innovation_pct", 0.0), s.solvency_risk_wedge_pct]
	briefing.tooltip_text = "Refinancing need is capped by maturing short-loan principal. Lending value applies the current collateral haircut and eligibility. Impairment is a credit-spread proxy; liquidity lending cannot create bank capital."
	briefing.accessibility_description = briefing.tooltip_text
	briefing.text += "\nDeferred demand %+.2f%% potential · prior release %+.2f pp." % [s.deferred_demand_pct, s.demand_release_pct]
	briefing.text += "\n\n" + career.situation_briefing()
	if reset_controls:
		loading_controls = true
		for input in [rate, guidance, assets, liquidity, inflation_response, activity_response]:
			_apply_input(input)
		rate.value = s.policy_rate_pct
		guidance.value = s.policy_rate_pct
		assets.value = 0
		liquidity.value = 0
		var prior: Dictionary = career.decisions[-1] if not career.decisions.is_empty() else {}
		reinvestment.button_pressed = prior.get("reinvest_principal", true)
		reserve_maintenance.button_pressed = prior.get("maintain_ample_reserves", true)
		sterilization.button_pressed = prior.get("sterilize_purchases", false)
		inflation_response.value = s.guidance_inflation_sensitivity if s.guidance_active else career.params.policy_inflation_response
		activity_response.value = s.guidance_output_gap_sensitivity if s.guidance_active else career.params.policy_output_gap_response
		commitment.select(0)
		if s.guidance_active:
			if inflation_response.value == 0.0 and activity_response.value == 0.0:
				commitment.select(1)
			elif inflation_response.value != career.params.policy_inflation_response or activity_response.value != career.params.policy_output_gap_response:
				commitment.select(2)
		_guidance_controls()
		loading_controls = false
	decision_button.disabled = complete
	decision_button.text = "Career complete" if complete else "Adopt decision  →  Next quarter"
	_link_focus(_keyboard_focus_order())
	_preview()

func _preview() -> void:
	if loading_controls or forecast_label == null or career.state.is_empty():
		return
	var result: Dictionary = career.forecast(_policy())
	if not result.ok:
		forecast_label.text = "Preview unavailable: " + result.error
		return
	var first: Dictionary = result.states[0]
	var last: Dictionary = result.states[-1]
	var rate_text := "Rate %.2f%%" % first.policy_rate_pct
	if first.policy_rate_pct < 0.0:
		rate_text += " (effective %.2f%%)" % first.effective_policy_rate_pct
	var n: float = first.decision_nominal_gdp_ratio
	forecast_label.text = "APPLIED NOW\n%s · assets %+.2f · lending %.2f\nRunoff %.2f · RMP %.2f · RRP %.2f\nUnsterilized %.2f · uncovered funding %.2f\n\nCONDITIONAL Q+8\nInflation %.2f%% · unemployment %.2f%% · output gap %+.2f%%" % [rate_text, first.asset_flow_applied_pct_initial_gdp / n, first.liquidity_applied_pct_initial_gdp / n, first.long_securities_runoff_pct_initial_gdp / n, first.reserve_maintenance_purchase_pct_initial_gdp / n, first.sterilization_applied_pct_initial_gdp / n, first.sterilization_unfulfilled_pct_initial_gdp / n, first.uncovered_funding_pct_initial_gdp / n, last.four_quarter_inflation_pct, last.unemployment_rate_pct, last.output_gap_pct]

func _decision_briefing() -> String:
	var policy := _policy()
	var selected: Dictionary = career.forecast(policy)
	var held: Dictionary = career.forecast(career.model.benchmark_policy(career.state, career.params, "hold"))
	if not selected.ok or not held.ok:
		return "Comparison unavailable: " + (selected.error if not selected.ok else held.error)
	var first: Dictionary = selected.states[0]
	var reference: Dictionary = held.states[0]
	var n: float = first.decision_nominal_gdp_ratio
	var text := "CURRENT MEETING / REQUESTED AND APPLIED\nRequested rate %.2f%% · Applied rate %.2f%%\nRequested assets %+.2f · Applied assets %+.2f\nRequested lending %.2f · Applied lending %.2f\n\nNominal rates apply in full on a 1bp quote grid; arrow convenience is 25bp. Negative policy is a U.S. counterfactual with diminishing effective borrowing-rate benefits. No invented purchase, stock or lending-offer ceilings. Runoff cannot exceed principal due. Lending is limited by borrower demand, eligibility, lending value and settlement. Asset and loan amounts here use %% of current annual GDP.\n\n" % [policy.policy_rate_request_pct, first.policy_rate_pct, policy.asset_flow_request_pct_initial_gdp / n, first.asset_flow_applied_pct_initial_gdp / n, policy.liquidity_request_pct_initial_gdp / n, first.liquidity_applied_pct_initial_gdp / n]
	text += "PORTFOLIO AND FUNDING / CURRENT MEETING\nPrincipal due %.2f; runoff %.2f; reinvested %.2f\nLong runoff %.2f; reserve-maintenance bills %.2f; total-asset change %+.2f\nSterilization requested %.2f; applied RRP %.2f; unfulfilled %.2f\nLoan principal repaid %.2f; refinancing %.2f; new local lending %.2f; aggregate lending %.2f\nEnding reserves %.2f; reserve-scarcity premium %.3f pp\n\n" % [first.principal_due_pct_initial_gdp / n, first.principal_runoff_pct_initial_gdp / n, first.principal_reinvestment_pct_initial_gdp / n, first.long_securities_runoff_pct_initial_gdp / n, first.reserve_maintenance_purchase_pct_initial_gdp / n, first.total_asset_change_pct_initial_gdp / n, first.sterilization_requested_pct_initial_gdp / n, first.sterilization_applied_pct_initial_gdp / n, first.sterilization_unfulfilled_pct_initial_gdp / n, first.liquidity_repayment_pct_initial_gdp / n, first.liquidity_refinancing_applied_pct_initial_gdp / n, first.liquidity_new_need_applied_pct_initial_gdp / n, first.liquidity_aggregate_applied_pct_initial_gdp / n, first.reserves_pct_initial_gdp / first.ending_nominal_gdp_ratio, first.reserve_scarcity_wedge_pct]
	text += "Lending value %.2f; Eligible local demand %.2f; aggregate demand %.2f\nBinding constraints: lending offer %s, collateral %s, eligibility %s; RRP uptake %s, collateral %s, reserves %s\n\n" % [first.lending_collateral_capacity_pct_initial_gdp / n, first.eligible_local_need_pct_initial_gdp / n, first.liquidity_aggregate_need_pct_initial_gdp / n, "yes" if first.liquidity_offer_binding or first.liquidity_aggregate_offer_binding else "no", "yes" if first.liquidity_collateral_binding or first.liquidity_aggregate_collateral_binding else "no", "yes" if first.liquidity_eligibility_binding else "no", "yes" if first.sterilization_uptake_binding else "no", "yes" if first.sterilization_collateral_binding else "no", "yes" if first.sterilization_reserve_binding else "no"]
	var s: Dictionary = career.state
	text += "COMMITTEE DELIBERATION / FEASIBLE RATE ALTERNATIVES\nFictional viewpoints, not votes or advice. Test a higher rate for inflation risk, a lower rate for employment risk, and continuity while past decisions work. Every other staged tool and the new quote stay unchanged. Each path uses the disclosed current shock, then no new shocks and its own applied-rate hold.\n\n"
	for alternative in [["Selected", policy.policy_rate_request_pct], ["Tighter rate", first.policy_rate_pct + 0.25], ["Gentler rate", first.policy_rate_pct - 0.25], ["Rate continuity", s.policy_rate_pct]]:
		var other: Dictionary = policy.duplicate()
		other.policy_rate_request_pct = alternative[1]
		var path: Dictionary = selected if var_to_bytes(other) == var_to_bytes(policy) else career.forecast(other)
		if not path.ok:
			text += "%s / unavailable: %s\n\n" % [alternative[0], path.error]
			continue
		var outcome: Dictionary = path.states[-1]
		text += "%s / applied %.2f%%\nQ+8 inflation %.3f%%; unemployment %.3f%%; credibility %.1f/100; support %.1f/100\n" % [alternative[0], path.states[0].policy_rate_pct, outcome.four_quarter_inflation_pct, outcome.unemployment_rate_pct, 100 * outcome.credibility, outcome.public_support]
		text += "\n"
	text += "GUIDANCE / COMMITMENT AND FLEXIBILITY\n"
	if s.guidance_active:
		var prior_promise: float = career.model.conditional_commitment(s, career.params)
		text += "Previous quote %.2f%%; inflation response %.2f, output-gap response %.2f.\nReference inflation %.3f%%, output gap %+.3f%%.\nAdjusted prior promise %.3f%%\nProjected follow-through %.1f / 100\n" % [s.guidance_rate_pct, s.guidance_inflation_sensitivity, s.guidance_output_gap_sensitivity, s.guidance_reference_inflation_pct, s.guidance_reference_output_gap_pct, prior_promise, 100 * first.guidance_followthrough_score]
	else:
		text += "No previous announcement to evaluate at this meeting.\n"
	text += "\nNew quote %.2f%%; inflation response %.2f, output-gap response %.2f.\nA new announcement does not erase the previous obligation. Conditions affect next meeting's follow-through, not an immediate credibility bonus. Follow-through is one component of credibility, alongside inflation performance and policy stance.\n\n" % [policy.guidance_rate_pct, policy.guidance_inflation_sensitivity, policy.guidance_output_gap_sensitivity]
	text += "GUIDANCE CONTINUATION / SELECTED HOLD VS PROMISE-FOLLOW\nA: selected-rate hold. B: follow the implied nominal promise at each later meeting and renew the originally chosen conditions.\nBoth apply the identical current decision and shock, then no future shocks. Portfolio switches persist; future asset/lending offers are zero. No automatic player decision.\nNominal delivery and effective borrowing rates differ under negative policy. Fulfillment need not improve stance adequacy or credibility; this is not an optimal-policy recommendation.\n\n"
	if s.quarter_index + selected.states.size() > Career.MAX_QUARTERS:
		text += "Beyond Q240: diagnostic continuation only, not extra playable turns.\n\n"
	var promise_follow: Dictionary = career.forecast(policy, true)
	if not promise_follow.ok:
		text += "Promise-follow unavailable: " + promise_follow.error + "\n\n"
	else:
		var a: Dictionary = selected.states[1]
		var b: Dictionary = promise_follow.states[1]
		text += "Q+2 / A VS B\nNominal rate %.2f%% vs %.2f%%\nEffective borrowing rate %.3f%% vs %.3f%%\nPromise follow-through %.1f vs %.1f / 100\nStance adequacy %.1f vs %.1f / 100\n\n" % [a.policy_rate_pct, b.policy_rate_pct, a.effective_policy_rate_pct, b.effective_policy_rate_pct, 100 * a.guidance_followthrough_score, 100 * b.guidance_followthrough_score, 100 * a.stance_adequacy_score, 100 * b.stance_adequacy_score]
		a = selected.states[7]
		b = promise_follow.states[7]
		text += "Q+8 / A VS B\nNominal rate %.2f%% vs %.2f%%\nEffective borrowing rate %.3f%% vs %.3f%%\n\nB / Q+8 PROMISE-FOLLOW\nInflation %.3f%%; unemployment %.3f%%; output gap %+.3f%%\nCredibility %.1f / 100; public support %.1f / 100\n\n" % [a.policy_rate_pct, b.policy_rate_pct, a.effective_policy_rate_pct, b.effective_policy_rate_pct, b.four_quarter_inflation_pct, b.unemployment_rate_pct, b.output_gap_pct, 100 * b.credibility, b.public_support]
		text += "Q+8 / B MINUS A\nInflation %s; unemployment %s\nOutput gap %s; credibility %s; support %s\n\n" % [_change_text(b.four_quarter_inflation_pct - a.four_quarter_inflation_pct, 3, "pp"), _change_text(b.unemployment_rate_pct - a.unemployment_rate_pct, 3, "pp"), _change_text(b.output_gap_pct - a.output_gap_pct, 3, "pp"), _change_text(100 * (b.credibility - a.credibility), 2), _change_text(b.public_support - a.public_support, 2)]
	text += "Q+1 / WHY CREDIBILITY AND SUPPORT MOVE\nSELECTED vs HOLD\nCredibility %.1f vs %.1f / 100\nPublic support %.1f vs %.1f / 100\nInflation-miss memory %.3f vs %.3f pp\nEffective rate %.3f%% vs %.3f%%\nDesired real restraint %+.3f vs %+.3f pp\nEffective-stance distance %.3f vs %.3f pp\nTransmission-frontier shortfall %.3f vs %.3f pp\nStance adequacy %.1f vs %.1f / 100\nPrior-promise follow-through %.1f vs %.1f / 100\nCurrent hardship %.3f vs %.3f support points\nHardship memory %.3f vs %.3f support points\n\n" % [100 * first.credibility, 100 * reference.credibility, first.public_support, reference.public_support, first.inflation_miss_memory_pct, reference.inflation_miss_memory_pct, first.effective_policy_rate_pct, reference.effective_policy_rate_pct, first.stance_target_gap_pct, reference.stance_target_gap_pct, first.stance_distance_pct, reference.stance_distance_pct, first.stance_best_feasible_distance_pct, reference.stance_best_feasible_distance_pct, 100 * first.stance_adequacy_score, 100 * reference.stance_adequacy_score, 100 * first.guidance_followthrough_score, 100 * reference.guidance_followthrough_score, first.current_hardship, reference.current_hardship, first.public_hardship_memory, reference.public_hardship_memory]
	text += "Credibility combines 40%% inflation performance, 40%% stance, 20%% follow-through. Remembered inflation misses reduce performance. Stance compares current effective financing restraint with the unsaturated desired real gap. Other staged tools and the quote are held fixed when calculating the relaxed continuous transmission frontier. The 1bp grid can leave a small remaining distance. Unattainable restraint reduces adequacy even at best effort; extreme nominal cuts cannot earn full credit merely by matching a nominal rule. Inflation memory and the desired gap use prior observations; current market inputs are disclosed. Without a prior announcement, follow-through is neutral. Credibility closes %.0f%% of the distance to its combined score each quarter.\n\nPublic support closes %.0f%% of the distance to its hardship-implied level each quarter. Current inflation/deflation and employment hardship reduce that level; weighted hardship memory prolongs the effect after conditions improve. These scores and the stance rule are game assumptions, not an optimal policy or a measured institutional reputation.\n\n" % [100 * career.params.credibility_adjustment, 100 * career.params.public_support_adjustment]
	text += "CURRENT TRANSMISSION / SELECTED VS HOLD\nLong yield %.3f%% vs %.3f%%\nCredit spread %.3f%% vs %.3f%%\nUncovered funding %.2f vs %.2f\n\n" % [first.long_yield_pct, reference.long_yield_pct, first.credit_spread_pct, reference.credit_spread_pct, first.uncovered_funding_pct_initial_gdp / n, reference.uncovered_funding_pct_initial_gdp / n]
	text += "DIFFERENCE FROM HOLD / SELECTED MINUS REFERENCE\n"
	for index in [0, 3, 7]:
		var choice: Dictionary = selected.states[index]
		var baseline: Dictionary = held.states[index]
		text += "Q+%d: Inflation %s · unemployment %s\nOutput gap %s\n\n" % [index + 1, _change_text(choice.four_quarter_inflation_pct - baseline.four_quarter_inflation_pct, 3, "pp"), _change_text(choice.unemployment_rate_pct - baseline.unemployment_rate_pct, 3, "pp"), _change_text(choice.output_gap_pct - baseline.output_gap_pct, 3, "pp")]
	var last: Dictionary = selected.states[-1]
	var baseline: Dictionary = held.states[-1]
	text += "Q+8 / SELECTED VS HOLD\nCredibility %.1f vs %.1f / 100\nPublic support %.1f vs %.1f / 100\n\n" % [100 * last.credibility, 100 * baseline.credibility, last.public_support, baseline.public_support]
	text += "ONE-CONTROL CONTRASTS / SELECTED MINUS ALTERNATIVE\nEach alternative changes only its named input. Guidance keeps conditional coefficients unchanged. Each path uses the same current shock, then no new shocks and its own applied-rate hold. Existing stocks, loans, prior promises and lags remain. These conditional differences are not additive or estimated U.S. effects; zero can mean an unused or constrained tool.\n\n"
	var alternatives := [
		["Rate / alternative request today's rate", "policy_rate_request_pct", s.policy_rate_pct, "%"],
		["Guidance quote / alternative quote applied rate", "guidance_rate_pct", first.policy_rate_pct, "%"],
		["Asset flow / alternative no new flow", "asset_flow_request_pct_initial_gdp", 0.0, "% of current annual GDP"],
		["Lending / alternative no new loans", "liquidity_request_pct_initial_gdp", 0.0, "% of current annual GDP"],
	]
	for alternative in alternatives:
		var other: Dictionary = policy.duplicate()
		other[alternative[1]] = alternative[2]
		var path: Dictionary = selected if var_to_bytes(other) == var_to_bytes(policy) else career.forecast(other)
		text += "%s: %.2f%s\n" % [alternative[0], alternative[2], alternative[3]]
		if not path.ok:
			text += "Contrast unavailable: " + path.error + "\n\n"
			continue
		var reference_first: Dictionary = path.states[0]
		var reference_last: Dictionary = path.states[-1]
		text += "Q+1 long yield %s; credit spread %s\nQ+8 inflation %s; unemployment %s; credibility %s; support %s\n\n" % [_change_text(first.long_yield_pct - reference_first.long_yield_pct, 3, "pp"), _change_text(first.credit_spread_pct - reference_first.credit_spread_pct, 3, "pp"), _change_text(last.four_quarter_inflation_pct - reference_last.four_quarter_inflation_pct, 3, "pp"), _change_text(last.unemployment_rate_pct - reference_last.unemployment_rate_pct, 3, "pp"), _change_text(100 * (last.credibility - reference_last.credibility), 2), _change_text(last.public_support - reference_last.public_support, 2)]
	text += "REFERENCE AND LIMITS\nHold today's rate, guide to that rate with data dependence, and request no new asset flows or loans. Both paths use the same current shock and no new future shocks. After this meeting, each holds its own applied rate and portfolio switches, with no new asset flows or loans. Principal, short-loan repayment, reserve maintenance and policy lags still operate. The HOLD reference uses default reinvestment/maintenance and no sterilization.\n\nThese are combined effects of the staged controls, not an optimal-policy recommendation or a confidence interval. Positive differences mean a higher value, not necessarily a better outcome. Policy lags can leave first-quarter inflation unchanged even when later outcomes differ."
	return text

func _staff_rule() -> void:
	var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, "feedback")
	loading_controls = true
	_apply_input(rate)
	_apply_input(guidance)
	rate.value = policy.policy_rate_request_pct
	guidance.value = policy.guidance_rate_pct
	commitment.select(0)
	_guidance_controls()
	loading_controls = false
	_preview()
	status_label.text = "Staff benchmark selected. This simple rule is a comparison, not an optimal policy. Other tools are unchanged."

func _change_text(change: float, decimals := 1, unit := "points") -> String:
	if change == 0:
		return "unchanged"
	var threshold := 0.5 / pow(10, decimals)
	if abs(change) < threshold:
		return ("up" if change > 0 else "down") + " <" + String.num(threshold, decimals + 1) + " " + unit
	return ("%+." + str(decimals) + "f " + unit) % change

func _advance() -> void:
	_apply_policy_inputs()
	var before: Dictionary = career.state.duplicate(true)
	var result: Dictionary = career.advance(_policy())
	if not result.ok:
		status_label.text = result.error + " Last valid quarter retained."
		return
	_refresh(true)
	var s: Dictionary = career.state
	consequence.text = "Q%d OUTCOME  ·  Inflation %s; unemployment %s.\nApplied rate %.2f%%. Public support %s; credibility %s." % [s.quarter_index, _change_text(s.four_quarter_inflation_pct - before.four_quarter_inflation_pct, 2, "pp"), _change_text(s.unemployment_rate_pct - before.unemployment_rate_pct, 2, "pp"), s.policy_rate_pct, _change_text(s.public_support - before.public_support), _change_text((s.credibility - before.credibility) * 100)]
	if s.liquidity_applied_pct_initial_gdp > 0.0 or s.uncovered_funding_pct_initial_gdp > 0.0 or s.liquidity_repayment_pct_initial_gdp > 0.0:
		var n: float = s.decision_nominal_gdp_ratio
		consequence.text += "\nFunding (%% meeting GDP): lent %.2f · uncovered %.2f · repaid %.2f." % [s.liquidity_applied_pct_initial_gdp / n, s.uncovered_funding_pct_initial_gdp / n, s.liquidity_repayment_pct_initial_gdp / n]
	if before.guidance_active:
		consequence.text += "\nPrevious promise follow-through: %.1f / 100." % (100 * s.guidance_followthrough_score)
	status_label.text = "Quarter %d completed. Unsaved changes · %s" % [s.quarter_index, career.cases[career.scenario_id].label]
	if int(s.quarter_index) % 12 == 0:
		_review()

func _save() -> void:
	var result: Dictionary = career.save_to(save_path)
	if result.ok:
		clean_career = career.encode()
	status_label.text = "Saved quarter %d. Late-compound slot updated; older saves untouched." % career.state.quarter_index if result.ok else result.error

func _load() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Load saved career"
	var cancel := dialog.add_button("Cancel", true)
	cancel.pressed.connect(dialog.queue_free)
	dialog.dialog_text = "Load the late-compound slot? Unsaved decisions will be replaced. career-v1.save is preserved; no fallback or migration."
	dialog.confirmed.connect(func():
		var result: Dictionary = career.load_from(save_path)
		if result.ok:
			clean_career = career.encode()
			_refresh(true)
			consequence.text = "Saved career restored with its decisions, economic history and policy lags."
		status_label.text = "Loaded quarter %d." % career.state.quarter_index if result.ok else result.error
	)
	_show_dialog(dialog, Vector2i(740, 180), cancel)
	_link_focus([cancel, dialog.get_ok_button()])

func _request_quit() -> void:
	if is_instance_valid(quit_dialog):
		return
	if career.encode() == clean_career:
		_quit_app()
		return
	var dialog := AcceptDialog.new()
	quit_dialog = dialog
	dialog.title = "Unsaved career"
	dialog.dialog_text = "Adopted quarters have not been saved. Quit without saving them?\nCancel returns to your career and pending policy edits. No save is written automatically."
	dialog.get_ok_button().text = "Quit without saving"
	var cancel := dialog.add_button("Cancel", true)
	cancel.pressed.connect(dialog.queue_free)
	dialog.confirmed.connect(_quit_app)
	var invoker: Control = get_viewport().gui_get_focus_owner()
	var numeric_edit := invoker is LineEdit and invoker.get_parent() is SpinBox
	var was_blocking := invoker.is_blocking_signals() if numeric_edit else false
	# SpinBox's focus-exit signal must not submit a draft when Quit takes focus.
	if numeric_edit:
		invoker.set_block_signals(true)
	_show_dialog(dialog, Vector2i(740, 180), cancel)
	_link_focus([cancel, dialog.get_ok_button()])
	if numeric_edit:
		invoker.set_block_signals.call_deferred(was_blocking)

func _quit_app() -> void:
	get_tree().quit()

func _restore_keyboard_focus(invoker: WeakRef) -> void:
	for child in get_children():
		if child is Window and child.visible:
			return
	var control: Control = invoker.get_ref() if invoker != null else null
	if control != null and control.is_visible_in_tree() and not (control is BaseButton and control.disabled):
		control.grab_focus()
	else:
		rate.get_line_edit().grab_focus()

func _show_dialog(dialog: Window, desired_size := Vector2i(740, 540), initial: Control = null) -> void:
	var invoker: WeakRef = weakref(get_viewport().gui_get_focus_owner())
	add_child(dialog)
	dialog.tree_exited.connect(func(): _restore_keyboard_focus.call_deferred(invoker))
	dialog.window_input.connect(func(event: InputEvent):
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_close_dialog"):
			dialog.queue_free()
			dialog.set_input_as_handled())
	dialog.close_requested.connect(dialog.queue_free)
	if dialog is AcceptDialog:
		# AccessKit finishes the button action with a focus request. Keep its window
		# registered until queue_free runs at frame end, instead of hiding immediately.
		dialog.dialog_hide_on_ok = false
		dialog.dialog_close_on_escape = false
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(desired_size)
	if initial != null:
		initial.grab_focus.call_deferred()

func _read_only_report(title: String, text: String) -> TextEdit:
	var body := TextEdit.new()
	body.text = text
	body.custom_minimum_size = Vector2(690, 450)
	body.editable = false
	body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	body.tab_input_mode = false
	body.accessibility_name = title
	body.accessibility_description = text
	body.add_theme_color_override("font_readonly_color", Color("e7eee9"))
	body.gui_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed and not event.shift_pressed and not event.alt_pressed and not event.is_command_or_control_pressed():
			var bar := body.get_v_scroll_bar()
			match event.keycode:
				KEY_PAGEUP: bar.value -= bar.page
				KEY_PAGEDOWN: bar.value += bar.page
				KEY_HOME: bar.value = 0
				KEY_END: bar.value = bar.max_value
				_: return
			body.accept_event())
	return body

func _text_dialog(title: String, text: String) -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.title = title
	var body := _read_only_report(title, text)
	dialog.add_child(body)
	_show_dialog(dialog, Vector2i(740, 540), body)
	_link_focus([body, dialog.get_ok_button()])
	return dialog

func _new_dialog() -> void:
	var dialog := AcceptDialog.new()
	var cancel := dialog.add_button("Cancel", true)
	cancel.pressed.connect(dialog.queue_free)
	dialog.title = "Start a new career · unsaved decisions will be replaced"
	var box := _vbox(dialog)
	_label(box, "Choose a hypothetical economy, not a historical forecast.\nEvery career includes seeded background disturbances, even the baseline.")
	scenario = OptionButton.new()
	scenario.accessibility_name = "Career scenario"
	for case_id in career.cases:
		scenario.add_item(career.cases[case_id].label)
		scenario.set_item_metadata(scenario.item_count - 1, case_id)
		if case_id == "unanchored_inflation":
			scenario.select(scenario.item_count - 1)
	box.add_child(scenario)
	seed_input = _spin(box, "Scenario seed", 1, 2147483647, 1, "Same scenario and seed reproduce the path within the same engine and model.")
	seed_input.value = 1
	_label(box, "Default challenge: weakly anchored inflation; holding rates prolongs inflation.\nBaseline and supply shock are practice labs. Recurring crises adds later episodes.", 13, MUTED)
	dialog.confirmed.connect(func():
		_apply_input(seed_input)
		_start_career(scenario.get_item_metadata(scenario.selected), int(seed_input.value))
	)
	_show_dialog(dialog, Vector2i(740, 240), scenario)
	_link_focus([scenario, seed_input.get_line_edit(), cancel, dialog.get_ok_button()])

func _review() -> void:
	var s: Dictionary = career.state
	var compared: Dictionary = career.review_comparison()
	if not compared.ok:
		_text_dialog("Policy review", compared.error)
		return
	var paths: Array = [compared.actual, compared.held]
	var staff: Dictionary = compared.get("staff", {})
	var text := "REALIZED PATHS / Q%d–Q%d\nYour policy / Hold" % [compared.from_quarter + 1, compared.to_quarter]
	if not staff.is_empty():
		paths.append(staff)
		text += " / Staff"
	text += "\n\n"
	for metric in [["Avg inflation distance", "inflation_miss", "%.3f", "pp", 1.0],
		["Avg employment shortfall", "employment_shortfall", "%.3f", "pp", 1.0],
		["Avg uncovered funding", "uncovered_funding", "%.3f", "% meeting GDP", 1.0],
		["Ending credibility", "credibility", "%.1f", "(each / 100)", 100.0],
		["Ending public support", "public_support", "%.1f", "(each / 100)", 1.0]]:
		var values := PackedStringArray()
		for path in paths:
			values.append(String(metric[2]) % (metric[4] * path[metric[1]]))
		text += "%s: %s %s\n" % [metric[0], " / ".join(values), metric[3]]
	if not staff.is_empty():
		text += "\n"
	else:
		text += "\n%s\n\n" % compared.get("staff_error", "Staff reference unavailable.")
	text += "References start at your actual Q%d state and use only shocks that already occurred. Hold holds %.2f%% and guides to that rate with data dependence. Staff applies the simple feedback rate rule with matching guidance and data dependence. Both request no new asset flows or loans. Default reinvestment and reserve maintenance stay on; sterilization stays off. Principal and short-loan repayments still settle. Existing stocks, expectations and policy lags carry forward. This is a hindsight comparison, not a forecast or proof of optimal policy.\n\n" % [compared.from_quarter, compared.hold_rate]
	text += "Lower inflation distance from 2%% and employment shortfall mean lower costs on those separate measures. Only unemployment above structural reference contributes to employment shortfall. There is no dismissal threshold. Uncovered funding is unmet need, averaged using each meeting's nominal GDP, not booked bank losses. Structural unemployment is a model assumption.\n\nCurrent inflation %.2f%%; unemployment %.2f%%; output gap %+.2f%%." % [s.four_quarter_inflation_pct, s.unemployment_rate_pct, s.output_gap_pct]
	var assessment := career.mandate_assessment()
	text += "\n\n" + _mandate_summary(assessment)
	if assessment.eligible and assessment.quarters > 0:
		text += "\nCareer averages / prices %s pp; employment %s pp.\nLatest %d quarters / prices %s pp; employment %s pp.\n" % [_mandate_value_text(assessment.inflation_miss, Career.MANDATE_INFLATION_MISS_MAX), _mandate_value_text(assessment.employment_shortfall, Career.MANDATE_EMPLOYMENT_SHORTFALL_MAX), mini(Career.MANDATE_RECENT_QUARTERS, assessment.quarters), _mandate_value_text(assessment.recent_inflation_miss, Career.MANDATE_INFLATION_MISS_MAX), _mandate_value_text(assessment.recent_employment_shortfall, Career.MANDATE_RECENT_EMPLOYMENT_SHORTFALL_MAX)]
	text += "\n" + _mandate_rules_text()
	_text_dialog("Your %d-quarter policy review" % (compared.to_quarter - compared.from_quarter), text)

static func _mandate_value_text(value: float, limit: float) -> String:
	var shown := "%.3f" % value
	if value > limit and float(shown) <= limit:
		return ">%.3f" % limit
	if value < limit and float(shown) >= limit:
		return "<%.3f" % limit
	return shown

func _mandate_summary(assessment: Dictionary) -> String:
	if not assessment.eligible:
		return "Practice · No Mandate v1 award; laboratory or custom realized inputs."
	var status := "Mandate achieved" if assessment.achieved else "Mandate not met" if assessment.complete else "In progress"
	if assessment.quarters == 0:
		return "MANDATE v1 · Prices ≤1 pp · Jobs ≤0.5 pp · Eligible funding ≥95% · " + status
	var prices := "Prices avg %s/1 pp" % _mandate_value_text(assessment.inflation_miss, Career.MANDATE_INFLATION_MISS_MAX)
	if assessment.inflation_miss <= Career.MANDATE_INFLATION_MISS_MAX and assessment.recent_inflation_miss > Career.MANDATE_INFLATION_MISS_MAX:
		prices = "Prices 12q %s/1 pp" % _mandate_value_text(assessment.recent_inflation_miss, Career.MANDATE_INFLATION_MISS_MAX)
	var jobs := "Jobs avg %s/0.5 pp" % _mandate_value_text(assessment.employment_shortfall, Career.MANDATE_EMPLOYMENT_SHORTFALL_MAX)
	if assessment.employment_shortfall <= Career.MANDATE_EMPLOYMENT_SHORTFALL_MAX and assessment.recent_employment_shortfall > Career.MANDATE_RECENT_EMPLOYMENT_SHORTFALL_MAX:
		jobs = "Jobs 12q %s/1 pp" % _mandate_value_text(assessment.recent_employment_shortfall, Career.MANDATE_RECENT_EMPLOYMENT_SHORTFALL_MAX)
	var funding := "Eligible funding n.a."
	if assessment.funding_active:
		var coverage := "%.3f" % (100.0 * assessment.funding_coverage)
		if float(coverage) == 100.0 * Career.MANDATE_FUNDING_COVERAGE_MIN:
			# Use the scorer's principal comparison; division can round below 95%.
			var required: float = Career.MANDATE_FUNDING_COVERAGE_MIN * assessment.funding_coverable
			if assessment.funding_applied < required:
				coverage = "<" + coverage
			elif assessment.funding_applied > required:
				coverage = ">" + coverage
		funding = "Funding %s/95%%" % coverage
	if not assessment.complete and assessment.quarters >= 24 and (assessment.recent_inflation_miss > Career.MANDATE_INFLATION_MISS_MAX or assessment.recent_employment_shortfall > Career.MANDATE_RECENT_EMPLOYMENT_SHORTFALL_MAX):
		status += " · 12q warning"
	return "MANDATE v1 · %s · %s · %s · %s" % [prices, jobs, funding, status]

func _mandate_rules_text() -> String:
	return "Mandate v1 is a fictional game challenge for the default weakly anchored inflation career. At Q240, career-average inflation distance must be ≤%.2f pp and unemployment above its changing structural reference ≤%.2f pp. Latest %d-quarter averages must each be ≤%.2f pp. Cover ≥%.0f%% of haircut/eligibility-supported local funding, including refinancing; aggregate reserve loans and insolvency repair do not count. No eligible need is not applicable. Criteria use unrounded values. Early misses never stop play. Other laboratories and custom completed shock paths are practice. Assessment is recalculated from completed history; it is not a Federal Reserve dismissal rule or an optimal-policy claim." % [Career.MANDATE_INFLATION_MISS_MAX, Career.MANDATE_EMPLOYMENT_SHORTFALL_MAX, Career.MANDATE_RECENT_QUARTERS, Career.MANDATE_RECENT_EMPLOYMENT_SHORTFALL_MAX, 100.0 * Career.MANDATE_FUNDING_COVERAGE_MIN]

func _journal() -> void:
	var text := "%s · seed %d\nRates and changes are percentage units. Asset and lending flows below use %% of each meeting's current annual GDP; ending stocks use ending GDP.\n\n" % [career.cases[career.scenario_id].label, career.seed_value]
	for s in career.history:
		text += "Q%03d | inflation %.2f%% | long expectations %.2f%% | unemployment %.2f%% | structural reference %.2f%% | rate %.2f%% | output gap %+.2f%% | credibility %.1f | support %.1f | hardship memory %.2f | assets %+.2f | loans %.2f\n\n" % [s.quarter_index, s.four_quarter_inflation_pct, s.expected_long_inflation_pct, s.unemployment_rate_pct, s.structural_unemployment_pct, s.policy_rate_pct, s.output_gap_pct, s.credibility * 100, s.public_support, s.public_hardship_memory, s.asset_flow_applied_pct_initial_gdp / s.decision_nominal_gdp_ratio, s.liquidity_applied_pct_initial_gdp / s.decision_nominal_gdp_ratio]
	var dialog := _text_dialog("Economic history and policy journal", text)
	var review := dialog.add_button("Review realized policy")
	review.disabled = career.decisions.is_empty()
	var order: Array[Control] = [dialog.get_child(0), review, dialog.get_ok_button()]
	if review.disabled:
		order.erase(review)
	_link_focus(order)
	review.tooltip_text = "Compare the latest up to twelve completed quarters with holding policy. Complete a decision first."
	review.pressed.connect(func():
		# A frame signal can precede deletion. Wait for the exclusive journal to
		# actually exit, then deliver after its AccessKit action has finished.
		dialog.tree_exited.connect(_review, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
		dialog.queue_free()
	)

func _help() -> void:
	_text_dialog("How to play", KEYBOARD_HELP + _mandate_rules_text() + "\n\nYour role\nGuide a simplified FOMC policy decision. The target-rate midpoint is an abstraction; a real chair does not unilaterally set the market rate.\n\nEvery career includes seeded background disturbances. The baseline starts at equilibrium with no scheduled scenario events, but its playable path is not shock-free. The same scenario and seed reproduce the path within the same engine and model.\n\n1. Read the dispatch. It describes current conditions, not future shocks.\n2. Set the target rate. Higher real rates restrain demand gradually; inflation reacts with a lag. A supply shock can raise prices while weakening activity.\n3. Choose guidance. A firm promise is easier to understand but costly to break. Data dependence adjusts the prior promise when inflation and the output gap change.\n4. Set purchases or a runoff cap; choose reinvestment, reserve maintenance and sterilization. Offer secured liquidity for eligible funding, not insolvency.\n5. Inspect applied amounts and the eight-quarter preview, then adopt. The preview assumes no new future shocks and no later rate changes.\n\nRates and guidance\nNominal rates apply in full; quotes use 1bp increments and arrows move 25bp. Negative rates are a U.S. counterfactual. Their effective financing rate is s*tanh(i/s) below zero, unchanged above zero; the illustrative scale s=1 percentage point is not an estimated lower bound. Credibility prices the nominal guidance quote before this transmission. Deep cuts have diminishing benefits. Stance credibility compares effective restraint with an unsaturated real-gap objective: constrained best effort receives partial credit, not full adequacy. Conditional implied quotes round to the same 1bp grid before nominal promise follow-through.\n\nBalance sheet and funding\nAsset and lending offers are percent of current annual GDP, converted once at the meeting. Purchases have no invented ceiling; their duration-premium effect diminishes with scale. A negative offer caps runoff at actual maturing Treasury, MBS and bill principal; it is not a sale of unmatured holdings. With a zero or positive offer, reinvestment on rolls principal and off allows natural runoff. MBS paydown responds nonlinearly to lagged financing; Treasury timing uses a source-backed maturity ladder.\n\nMaintain ample reserves buys short bills after all other transactions to meet the disclosed reserve buffer. Bills are excluded from the long-duration channel but can ease funding scarcity; long runoff can coexist with unchanged total assets. Sterilized purchases retain securities and duration effects while replacing reserves with overnight reverse repo liabilities. Uptake, Treasury collateral and settlement can leave absorption incomplete. Tagged principal rolls without accumulating a new absorption target.\n\nThe liquidity offer is desired concurrent exposure, not accumulated quarterly turnover. Prior representative overnight/short loans mature next quarter. New needs and requested refinancing are separate; eligible refinancing receives priority. Default zero refinancing assumes private repayment funds. Eligibility and haircut-adjusted collateral limit advances; excess offers do not become loans. Lending can relieve funding scarcity, not erase losses or create capital. Inspect applied amounts, RRP, reserve-maintenance purchases (RMP), and uncovered funding before adopting. Portfolio switches persist through the preview and subsequent meetings; one-time purchase and lending offers reset.\n\nRecovery channels\nDeferred demand tracks postponed durable/replacement purchases, not all lost consumption. Positive stock supports catch-up spending; negative stock means purchases were brought forward. Financing restraint delays release; growth changes the denominator, and obsolete plans decay. The stock uses percent of quarterly potential output. Short expectations gradually mix observed inflation with prior long expectations in proportion to credibility. Transitory neutral-rate deviations revert toward a structural reference; permanent structural shifts change it. These channels provide a recovery impulse, with no guaranteed return to 2% under persistent restraint.\n\nCredibility changes how markets price guidance and long-run inflation expectations. Public support remembers both inflation/deflation hardship and unemployment. It recovers gradually, without term resets or a game-over threshold.\n\nSave preserves a career in this game's separate storage. New career and Load ask before replacing unsaved play. Tab navigates controls; charts also have exact values in Data & journal. Animation is off by default.\n\nModel limits\nSeven hypothetical scenarios. Recurring crises draws from 50 curated exogenous events: disasters, demand/supply changes, funding and credit losses, and favorable developments. Forty-eight independent profiles use a no-repeat bag; two private-bank normalization events require prior eligible stress. The current dispatch names an active event, never its future pulses. Private normalization cannot erase old losses or loans. The 2% objective and portfolio reference observations are source-backed; behavioral coefficients, starting conditions and shock incidence are design assumptions. This is a hypothetical economy, not an empirical forecast or financial advice. No Federal Reserve affiliation. See the repository's FED_RESEARCH and model README for primary sources and equations.\n\nCredits\nOriginal procedural Blender city by the project. Godot Engine is MIT-licensed.\n\n" + Engine.get_license_text())

func _process(delta: float) -> void:
	if city != null and not reduced_motion:
		city.rotation.y += delta * 0.025

func _credits() -> void:
	var text := "THE CHAIR / FEDERAL RESERVE POLICY LAB\n\nOriginal game and procedural Blender city © 2026 Jared Bland.\nSystem fonts are supplied by the operating system and are not redistributed.\n\nGODOT ENGINE\n" + Engine.get_license_text()
	for component in Engine.get_copyright_info():
		text += "\n\n" + component.name + "\n"
		for part in component.parts:
			text += "\n".join(part.copyright) + "\nLicense: " + part.license + "\nFiles: " + ", ".join(part.files) + "\n"
	for license_name in Engine.get_license_info():
		text += "\n\n" + license_name + "\n" + Engine.get_license_info()[license_name]
	_text_dialog("Engine and third-party notices", text)
