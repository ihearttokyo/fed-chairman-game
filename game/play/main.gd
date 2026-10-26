extends Control

const Career = preload("res://play/career.gd")
const Workout = preload("res://play/workout_career.gd")
const WorkoutPanel = preload("res://play/bank_workout_panel.gd")
const FundingPlan = preload("res://play/funding_plan.gd")
const WORKOUT_CASE := "__bank_workout"
const WORKOUT_HELP := "Eight meetings. Rate decisions change inflation, activity and the market value of the bank's securities. Lending can pay withdrawals or renew debt; it cannot create equity. Unpaid withdrawals and overdue loans carry forward. A final withdrawal wave requests all remaining unrequested deposits. Maturing securities turn into cash and stop serving as collateral.\n\nThis authored exercise uses zero loan interest and automatic cash-first repayment of CB principal, then deposit withdrawals. That is a teaching assumption, not statutory insolvency priority. Securities use one flat semiannual discount yield. Quantities are % of initial annual GDP; policy offers remain % of current GDP.\n\nPreviews include known maturities and today's request, not future withdrawal requests or shocks. Paths beyond meeting eight are diagnostics, not additional playable meetings. Normal career saves and awards are unavailable in this unsaved laboratory."
const Chart = preload("res://play/history_chart.gd")
const HelpGuide = preload("res://play/help_guide.gd")
const ReportDialog = preload("res://play/report_dialog.gd")
const PolicyReview = preload("res://play/policy_review.gd")
const ForecastOverview = preload("res://play/forecast_overview.gd")
const Music = preload("res://play/music.gd")
const Advice = preload("res://play/policy_advice.gd")
const RoutineFollowUp = preload("res://play/routine_follow_up.gd")
const TransitionExplanation = preload("res://play/transition_explanation.gd")
const ObjectiveBoard = preload("res://play/objective_board.gd")
const OutcomeDrivers = preload("res://play/outcome_drivers.gd")
const DispatchBrief = preload("res://play/dispatch_brief.gd")
const PolicyCommittee = preload("res://play/policy_committee.gd")
const FOLLOW_UP_INTERVAL_SECONDS := 2.0
const FOLLOW_UP_MAX_FRAME_CREDIT_SECONDS := 0.1
const SAVE_PATH := "user://policy-career-v2.save"
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
var dispatch_event: Label
var dispatch_dilemma: Label
var dispatch_details_button: Button
var dispatch_details_text := ""
var consequence: Label
var outcome_drivers: OutcomeDrivers
var objective_board: ObjectiveBoard
var objective_panel: PanelContainer
var mandate_label: Label
var forecast_label: Label
var comparison_series: Array = []
var status_label: Label
var rate: SpinBox
var guidance: SpinBox
var assets: SpinBox
var liquidity: SpinBox
var funding_plan: FundingPlan
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
var overflow_scroll: ScrollContainer
var body_layout: BoxContainer
var action_layout: BoxContainer
var action_buttons: BoxContainer
var chart_layout: BoxContainer
var portfolio_layout: BoxContainer
var metric_layout: GridContainer
var policy_panel: PanelContainer
var save_path := SAVE_PATH
var clean_career: PackedByteArray
var quit_dialog: AcceptDialog
var music: Music
var music_toggle: CheckBox
var shutting_down := false
var routine := RoutineFollowUp.new()
var follow_up_toggle: CheckBox
var stop_follow_up: Button
var follow_up_note: Label
var follow_up_wait_seconds := 0.0
var segment_start := -1
var adopting := false
var last_follow_up_reasons: Array[String] = []
var committee: OptionButton
var committee_note: Label
var workout_panel: PanelContainer
var workout_board: WorkoutPanel
var workout_fed_stock: Label
var city_panel: PanelContainer
var normal_storage_buttons: Array[Button] = []

const KEYBOARD_HELP := "Keyboard controls\nTab / Shift+Tab move forward / back through visible controls. Return or Space activates a focused button. In numeric fields, type a value and press Return to commit only that field; Up / Down use its advertised step. Arrow keys navigate open scenario or guidance menus; Return selects and Escape cancels.\n\nCharts: Left / Right inspect completed quarters; Home / End select the first / latest. Focused cockpit and reports: Page Up / Down scroll, Home / End reach the ends. Escape or modified Return closes an informational report and returns focus. Plain Return closes its text or OK button, otherwise activates the focused report control. Escape cancels replacement; Return still follows the focused confirmation control.\n\nOptional accelerators use Cmd on macOS or Ctrl elsewhere: N New, S Save, O Load, J journal, P Compare, R staff estimate, K stage committee proposal, modified Return adopt one quarter. F1 opens this guide. Every command also has a Tab-accessible control; plain typing never adopts a quarter.\n\n"
const STAFF_HELP := "Staff estimates use two-decimal published inflation, output gap and long expectations with the scenario’s initial neutral-rate prior. They do not know the evolving neutral rate or short expectations. An estimate is not an optimal policy; other tools remain unchanged. The rate formula does not directly adjust for credit spreads, term premiums or weaker negative-rate transmission."
const BENCHMARK_HELP := "The full-information benchmark uses the true neutral rate, short inflation expectations, inflation and output gap from the current model state. It does not know future shocks or identify an optimal policy. The rate formula does not directly adjust for credit spreads, term premiums or weaker negative-rate transmission."

func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(_request_quit)
	_fit_initial_window()
	_resize_layout()
	_apply_theme()
	music = Music.new()
	music.name = "Soundtrack"
	music.stream = preload("res://assets/audio/jrb-1.wav")
	music.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	music.stream.loop_begin = 0
	music.stream.loop_end = roundi(music.stream.get_length() * music.stream.mix_rate)
	music.volume_db = -12.0
	add_child(music)
	var background := ColorRect.new()
	background.color = Color("0c191f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	overflow_scroll = ScrollContainer.new()
	overflow_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overflow_scroll.follow_focus = true
	add_child(overflow_scroll)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 0)
	overflow_scroll.add_child(layout)
	var scroll := ScrollContainer.new()
	cockpit_scroll = scroll
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Keep the existing usable cockpit floor; short windows scroll the whole layout.
	scroll.custom_minimum_size.y = 200
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
	consequence.mouse_filter = Control.MOUSE_FILTER_PASS
	consequence.accessibility_live = AccessibilityServer.LIVE_POLITE
	mandate_label = _label(feedback, "", 13, GOLD)
	mandate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mandate_label.accessibility_live = AccessibilityServer.LIVE_POLITE
	status_label = _label(feedback, "", 13, MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.accessibility_live = AccessibilityServer.LIVE_POLITE
	action_buttons = BoxContainer.new()
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
	var cards := GridContainer.new()
	metric_layout = cards
	cards.columns = 4
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
	workout_panel = _panel(left)
	workout_board = WorkoutPanel.new()
	workout_panel.add_child(workout_board)
	workout_fed_stock = _label(workout_board, "", 12, MUTED)
	workout_fed_stock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	workout_board.details_requested.connect(_workout_details)
	keyboard_controls.append(workout_board.details_button)
	workout_panel.hide()
	var brief_box := _vbox(_panel(left), 5)
	var dispatch_header := HBoxContainer.new()
	brief_box.add_child(dispatch_header)
	var dispatch_title := _label(dispatch_header, "Current conditions", 12, GOLD)
	dispatch_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dispatch_details_button = _button(dispatch_header, "Details", _dispatch_details)
	dispatch_details_button.add_theme_font_size_override("font_size", 12)
	dispatch_details_button.accessibility_name = "Current conditions details"
	dispatch_details_button.tooltip_text = "Read current shocks, funding calculations and their limits."
	dispatch_event = _label(brief_box, "", 16, GOLD)
	dispatch_event.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dispatch_dilemma = _label(brief_box, "", 13, MUTED)
	dispatch_dilemma.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing = _label(brief_box, "", 14)
	briefing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing.mouse_filter = Control.MOUSE_FILTER_PASS
	objective_panel = _panel(left)
	objective_board = ObjectiveBoard.new()
	objective_panel.add_child(objective_board)
	objective_board.details_requested.connect(_objective_details)
	keyboard_controls.append(objective_board.details_button)
	outcome_drivers = OutcomeDrivers.new()
	left.add_child(outcome_drivers)
	outcome_drivers.details_requested.connect(_driver_details)
	keyboard_controls.append(outcome_drivers.details_button)
	var chart_row := BoxContainer.new()
	chart_layout = chart_row
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
	_start_career(Career.DEFAULT_SCENARIO, 1)
	get_window().size_changed.connect(_resize_layout)
	get_window().dpi_changed.connect(_resize_layout)
	overflow_scroll.resized.connect(_resize_layout)
	overflow_scroll.get_v_scroll_bar().visibility_changed.connect(_resize_layout)
	cockpit_scroll.resized.connect(_reveal_focus)
	for card in metric_layout.get_children():
		card.minimum_size_changed.connect(_resize_layout)
	_resize_layout()
	keyboard_controls.append(scroll)
	_link_focus(_keyboard_focus_order())
	rate.get_line_edit().grab_focus.call_deferred()
	if not body_layout.vertical:
		cockpit_scroll.set_deferred("scroll_vertical", 0)
	preload("res://play/wrapped_tooltip.gd").install(self)
	if "--verify-build" in OS.get_cmdline_user_args():
		Engine.max_fps = 60
		_quit_app(load("res://play/build_check.gd").new().run(self))

static func _responsive_canvas_size(physical: Vector2i, display_scale: float) -> Vector2i:
	var logical := Vector2(physical).max(Vector2.ONE) / maxf(1.0, display_scale)
	return Vector2i(logical.round()).max(Vector2i.ONE)

func _row_minimum(row: BoxContainer) -> float:
	var width := 0.0
	for child in row.get_children():
		if child.visible:
			if width > 0:
				width += row.get_theme_constant("separation")
			width += child.get_combined_minimum_size().x
	return width

func _reveal_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		if cockpit_scroll.is_ancestor_of(focused):
			cockpit_scroll.ensure_control_visible(focused)
		if overflow_scroll.is_ancestor_of(focused):
			overflow_scroll.ensure_control_visible(focused)

func _resize_layout() -> void:
	var window := get_window()
	var logical := _responsive_canvas_size(window.size, DisplayServer.screen_get_scale(window.current_screen))
	if window.content_scale_size != logical:
		window.content_scale_size = logical
	if body_layout == null:
		return
	# Reserve the scrollbar even before it appears, avoiding breakpoint oscillation.
	var available := window.get_visible_rect().size.x - 48 - cockpit_scroll.get_v_scroll_bar().get_combined_minimum_size().x - overflow_scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var left: Control = chart_layout.get_parent()
	# Project the unstacked chart width so narrower rows cannot move the wide breakpoint.
	var policy_minimum := maxf(policy_panel.get_combined_minimum_size().x, _row_minimum(portfolio_layout) + policy_panel.get_theme_stylebox("panel").get_minimum_size().x)
	var left_minimum := 420.0 if _is_workout() else 630.0
	var chart_floor := _row_minimum(chart_layout)
	if _is_workout():
		# The bank ledger takes priority; its two macro charts can stack locally
		# without forcing the entire policy cockpit into a full-width column.
		chart_floor = 0.0
		for chart in chart_layout.get_children():
			chart_floor = maxf(chart_floor, chart.get_combined_minimum_size().x)
	var wide_minimum: float = maxf(left_minimum, chart_floor) + policy_minimum + body_layout.get_theme_constant("separation")
	var metric_width := 3.0 * metric_layout.get_theme_constant("h_separation")
	var cards := metric_layout.get_children()
	for card in cards:
		metric_width += card.get_combined_minimum_size().x
	var paired_width := maxf(cards[0].get_combined_minimum_size().x, cards[2].get_combined_minimum_size().x) + maxf(cards[1].get_combined_minimum_size().x, cards[3].get_combined_minimum_size().x) + metric_layout.get_theme_constant("h_separation")
	metric_layout.columns = 4 if available >= metric_width else 2 if available >= paired_width else 1
	body_layout.vertical = available < wide_minimum
	action_layout.vertical = body_layout.vertical
	left.custom_minimum_size.x = 0 if body_layout.vertical else left_minimum
	var chart_available: float = available - policy_minimum - body_layout.get_theme_constant("separation") if _is_workout() and not body_layout.vertical else available
	chart_layout.vertical = chart_available < _row_minimum(chart_layout)
	action_buttons.vertical = available < _row_minimum(action_buttons)
	portfolio_layout.vertical = available < _row_minimum(portfolio_layout) + policy_panel.get_theme_stylebox("panel").get_minimum_size().x
	var policy_index := 0 if body_layout.vertical else 1
	if policy_panel.get_index() != policy_index:
		body_layout.move_child(policy_panel, policy_index)
		_link_focus(_keyboard_focus_order())
	_reveal_focus.call_deferred()
	for child in get_children():
		if child is ReportDialog and child.visible:
			_fit_report.call_deferred(child)

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
	order.sort_custom(func(a: Control, b: Control):
		if a == cockpit_scroll: return false
		if b == cockpit_scroll: return true
		return b.is_greater_than(a))
	return order

func _link_focus(order: Array[Control]) -> void:
	for index in range(order.size()):
		order[index].focus_next = order[index].get_path_to(order[(index + 1) % order.size()])
		order[index].focus_previous = order[index].get_path_to(order[(index - 1 + order.size()) % order.size()])

func _scroll_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.alt_pressed and not event.is_command_or_control_pressed():
		match event.keycode:
			KEY_PAGEUP, KEY_PAGEDOWN:
				var direction := -1 if event.keycode == KEY_PAGEUP else 1
				var bar := cockpit_scroll.get_v_scroll_bar()
				var can_move := bar.value > 0 if direction < 0 else bar.value < bar.max_value - bar.page
				var scroll := cockpit_scroll if can_move else overflow_scroll
				scroll.scroll_vertical += direction * int(scroll.size.y * 0.8)
			KEY_HOME:
				cockpit_scroll.scroll_vertical = 0
				overflow_scroll.scroll_vertical = 0
			KEY_END:
				cockpit_scroll.scroll_vertical = int(cockpit_scroll.get_v_scroll_bar().max_value)
				overflow_scroll.scroll_vertical = int(overflow_scroll.get_v_scroll_bar().max_value)
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
	save_button.tooltip_text = "Save to policy-career-v2.save only. policy-career-v1.save and both older slots remain untouched."
	save_button.accessibility_description = save_button.tooltip_text
	var load_button := _button(row, "Load", _load, KEY_O)
	normal_storage_buttons.assign([save_button, load_button])
	load_button.tooltip_text = "Load policy-career-v2.save only. Older slots need their matching prior app/model; no fallback or migration."
	load_button.accessibility_description = load_button.tooltip_text
	_button(row, "Data & journal", _journal, KEY_J)
	_button(row, "How to play", _help, KEY_F1, false)
	_button(row, "Credits", _credits)
	music_toggle = CheckBox.new()
	music_toggle.name = "MusicToggle"
	music_toggle.text = "Music"
	music_toggle.focus_mode = Control.FOCUS_ALL
	music_toggle.tooltip_text = "JRB-1 by ihearttokyo. Looping soundtrack; off stops playback. This preference is saved separately from your career."
	music_toggle.accessibility_description = music_toggle.tooltip_text
	music_toggle.set_pressed_no_signal(music.music_enabled)
	music_toggle.toggled.connect(_set_music_enabled)
	row.add_child(music_toggle)
	keyboard_controls.append(music_toggle)

func _set_music_enabled(enabled: bool) -> void:
	var error := music.set_enabled(enabled)
	if error != OK:
		status_label.text = "Music %s; preference not saved (%s)." % ["on" if enabled else "off", error_string(error)]
	elif status_label.text.begins_with("Music "):
		status_label.text = "Music %s." % ("on" if enabled else "off")

static func _city_texture_size(area: Vector2, physical: Vector2i, logical: Vector2) -> Vector2i:
	var density := 1.0
	if logical.x > 0 and logical.y > 0:
		density = clampf(minf(physical.x / logical.x, physical.y / logical.y), 1.0, 2.0)
	density = minf(density, 2048.0 / maxf(2.0, maxf(area.x, area.y)))
	return Vector2i((area * density).ceil()).max(Vector2i(2, 2))

func _build_city(parent: Node) -> void:
	var panel := _panel(parent)
	city_panel = panel
	var box := _vbox(panel, 3)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(top)
	var motion := CheckButton.new()
	motion.text = "Animate city"
	motion.add_theme_font_size_override("font_size", 13)
	var motion_style := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "disabled"]:
		motion.add_theme_stylebox_override(style_name, motion_style)
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
	container.custom_minimum_size = Vector2(0, 140)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	policy_panel = panel
	panel.custom_minimum_size.x = 380
	var box := _vbox(panel, 8)
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
	var portfolio_row := BoxContainer.new()
	portfolio_layout = portfolio_row
	modes.add_child(portfolio_row)
	reinvestment = _portfolio_switch(portfolio_row, "Reinvest principal", true, "With zero or positive purchases, roll principal on or allow natural runoff off. A negative runoff cap overrides either setting; no unmatured securities are sold.")
	sterilization = _portfolio_switch(portfolio_row, "Sterilize purchases", false, "Absorb purchase-created reserves through overnight reverse repos. Securities remain assets; duration effects persist. Uptake, collateral and settlement can limit absorption.")
	reserve_maintenance = _portfolio_switch(modes, "Maintain ample reserves", true, "Buy short bills after runoff, currency conversion, lending and absorption to meet the modeled reserve buffer. Bills can change funding conditions but are excluded from the long-duration channel.")
	liquidity = _spin(box, "Liquidity offer", 0, 5, 0.25, "Desired concurrent exposure, percent of current annual GDP. Quotes use 0.0001 increments; arrows move 0.25. No offer ceiling. Borrower need, eligibility, haircut-adjusted collateral and settlement limit advances; loans do not create bank capital.")
	liquidity.step = 0.0001
	liquidity.allow_greater = true
	_label(box, "Asset and loan units: % of current annual GDP", 11, MUTED)
	funding_plan = FundingPlan.new()
	box.add_child(funding_plan)
	var benchmark_button := _button(box, "Stage staff estimate", _staff_rule, KEY_R)
	benchmark_button.tooltip_text = STAFF_HELP
	benchmark_button.accessibility_description = benchmark_button.tooltip_text
	committee = OptionButton.new()
	committee.accessibility_name = "Policy committee priority"
	committee.tooltip_text = "Competing fictional mandates using current published conditions, not the true neutral rate or future shocks. Select a priority, then stage its proposal. Nothing is adopted automatically."
	committee.accessibility_description = committee.tooltip_text
	box.add_child(committee)
	keyboard_controls.append(committee)
	committee.item_selected.connect(_committee_selected)
	_button(box, "Stage committee proposal", _stage_committee, KEY_K)
	committee_note = _label(box, "", 11, MUTED)
	committee_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	forecast_label = _label(box, "", 13, MINT)
	forecast_label.custom_minimum_size.y = 114
	forecast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(actions, "Policy paths", _compare, KEY_P)
	var decision_controls := _vbox(actions, 4)
	decision_button = _button(decision_controls, "Adopt decision  →  Next quarter", _advance, KEY_ENTER)
	decision_button.custom_minimum_size = Vector2(380, 48)
	follow_up_toggle = _portfolio_switch(decision_controls, "Routine follow-up · up to 4 quarters", false, "After adoption: up to 3 staff rate/guidance updates, at least 2 seconds apart. Portfolio switches persist; new offers reset. Funding, news or drift returns control. Escape or Stop cancels.")
	stop_follow_up = _button(decision_controls, "Stop routine follow-up", func(): _finish_follow_up("Stopped", false, true))
	stop_follow_up.visible = false
	follow_up_note = _label(decision_controls, "", 11, MUTED)
	follow_up_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var explanation := _label(box, "Preview: this decision, then hold its rate for seven more quarters. No new future shocks. This is a conditional path, not a confidence interval.", 11, MUTED)
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
	if career.decisions.size() < _active_horizon():
		_apply_policy_inputs()
	_preview()
	var text := _decision_briefing()
	var dialog := ReportDialog.new()
	dialog.title = "Compare policy paths"
	var tabs := TabContainer.new()
	dialog.add_child(tabs)
	var overview := ForecastOverview.new()
	overview.name = "Paths"
	tabs.add_child(overview)
	overview.build(comparison_series, career.decisions.size() >= _active_horizon(), career.decisions.size() + 8 > _active_horizon(), _active_horizon())
	var box := VBoxContainer.new()
	box.name = "Details"
	tabs.add_child(box)
	box.custom_minimum_size = Vector2.ZERO
	_label(box, "Jump to section", 13, MUTED)
	var chooser := OptionButton.new()
	chooser.allow_reselect = true
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
	tabs.custom_minimum_size = Vector2(690, 450)
	if comparison_series.is_empty():
		tabs.current_tab = 1
	tabs.tab_changed.connect(_comparison_tab_focus.bind(tabs, overview, chooser, body, dialog.get_ok_button()))
	_show_dialog(dialog, Vector2i(740, 540), body if comparison_series.is_empty() else tabs.get_tab_bar())
	_comparison_tab_focus(tabs.current_tab, tabs, overview, chooser, body, dialog.get_ok_button())

func _comparison_tab_focus(_index: int, tabs: TabContainer, overview: Control, chooser: Control, body: Control, close: Control) -> void:
	var order: Array[Control] = []
	if tabs.current_tab == 1:
		order.assign([tabs.get_tab_bar(), chooser, body, close])
	else:
		order.append(tabs.get_tab_bar())
		for chart in overview.charts:
			order.append(chart)
		order.append(close)
	_link_focus(order)

func _dispatch_details() -> void:
	if routine.active:
		_finish_follow_up("Current conditions opened", false)
	if not dispatch_details_text.is_empty():
		_text_dialog("Current conditions", dispatch_details_text)

func _guidance_controls() -> void:
	var use_custom := commitment.selected == 2
	var focused: Control = get_viewport().gui_get_focus_owner()
	if not use_custom and focused != null and custom_guidance.is_ancestor_of(focused):
		commitment.grab_focus()
	custom_guidance.visible = use_custom
	_link_focus(_keyboard_focus_order())
	_preview()

func _is_workout() -> bool:
	return career is Workout

func _active_horizon() -> int:
	return Workout.EPISODE_QUARTERS if _is_workout() else Career.MAX_QUARTERS

func _workout_details() -> void:
	_text_dialog("Bank workout", WORKOUT_HELP)

func _start_career(case_id: String, seed_number: int) -> void:
	_finish_follow_up("New career", false)
	var candidate = career
	var result: Dictionary
	if case_id == WORKOUT_CASE:
		candidate = Workout.new()
		var recipe: Dictionary = candidate.model.bank_workout_opening(candidate.params)
		result = candidate.start_episode(recipe.bank, recipe.requests, recipe.haircut_pct, recipe.pledgeable_share, "stagflation_bank_run", seed_number, recipe.remaining_request_index) if recipe.ok else recipe
	else:
		if _is_workout():
			candidate = Career.new()
		result = candidate.start(case_id, seed_number)
	if not result.ok:
		status_label.text = result.error
		return
	career = candidate
	clean_career = career.encode()
	outcome_drivers.clear()
	_refresh(true)
	_resize_layout()
	consequence.text = "Review current conditions, stage policy, then adopt."
	consequence.tooltip_text = ""
	consequence.accessibility_description = ""
	status_label.text = "New unsaved career · %s · seed %d" % ["Bank workout · 8 meetings" if _is_workout() else career.cases[case_id].label, seed_number]

func _refresh(reset_controls := false, update_preview := true) -> void:
	if funding_plan != null:
		funding_plan.update_plan({}, 0.0, 1.0)
	var s: Dictionary = career.state
	_committee_brief()
	var complete := career.decisions.size() >= _active_horizon()
	case_title.text = "Bank workout · unsaved laboratory" if _is_workout() else career.cases[career.scenario_id].label
	var n: float = career.model.nominal_gdp_ratio(s)
	case_detail.text = "Holdings %.1f%% · Term premium %+.3f pp · Loans %s%% · Reserves %s%% · RRP %s%%\nStocks: %% of current annual GDP" % [s.asset_stock_pct_initial_gdp / n, s.term_premium_pct, Career.funding_amount_text(s.outstanding_liquidity_pct_initial_gdp / n), Career.funding_amount_text(s.reserves_pct_initial_gdp / n), Career.funding_amount_text(s.reverse_repo_pct_initial_gdp / n)]
	quarter_label.text = "CAREER COMPLETE · %d MEETINGS" % _active_horizon() if complete else "YEAR %02d / Q%d   ·   MEETING %d" % [int(s.quarter_index / 4) + 1, int(s.quarter_index) % 4 + 1, s.quarter_index + 1]
	if _is_workout():
		quarter_label.text = "EPISODE COMPLETE · 8 MEETINGS" if complete else "BANK WORKOUT · MEETING %d / 8" % (s.quarter_index + 1)
	workout_panel.visible = _is_workout()
	city_panel.visible = not _is_workout()
	mandate_label.visible = not _is_workout()
	for button in normal_storage_buttons:
		button.disabled = _is_workout()
	if _is_workout():
		workout_board.update_snapshot((career as Workout).panel_snapshot())
		workout_fed_stock.text = "Fed: " + case_detail.text.replace("\n", " · ")
	var assessment := career.mandate_assessment()
	var recovery_mode := career.scenario_id == "stagflation_bank_run"
	objective_board.update_assessment(assessment, career.recovery_assessment() if recovery_mode else {}, recovery_mode)
	objective_panel.visible = objective_board.snapshot.ok and objective_board.snapshot.eligible
	mandate_label.text = objective_board.snapshot.title
	mandate_label.tooltip_text = "Recovery v1 is a separate fictional stabilization challenge. Open Policy review → Challenge rules for scoring." if career.scenario_id == "stagflation_bank_run" else "Fictional challenge, assessed at Q240. Open Policy review → Challenge rules for thresholds and scoring."
	mandate_label.accessibility_description = _mandate_rules_text()
	if complete and assessment.eligible:
		quarter_label.text = ("MANDATE ACHIEVED" if assessment.achieved else "MANDATE NOT MET") + " · %d MEETINGS" % _active_horizon()
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
	dispatch_event.hide()
	dispatch_event.text = ""
	dispatch_dilemma.hide()
	dispatch_dilemma.text = ""
	if complete:
		briefing.text = "Career complete at Q240. Review final outcomes in Data & journal."
		briefing.tooltip_text = "All 240 decisions are complete; there is no next meeting."
	else:
		var shock: Dictionary = career.current_briefing()
		var refinancing_request: float = shock.get("refinancing_need_pct_initial_gdp", 0.0)
		var refinancing_need := minf(refinancing_request, s.outstanding_liquidity_pct_initial_gdp)
		var collateral: float = shock.get("eligible_collateral_pct_initial_gdp", 0.0)
		var haircut: float = shock.get("collateral_haircut_pct", 0.0)
		var eligibility: float = shock.get("liquidity_eligibility_pct", 0.0)
		var lending_value := collateral * (1.0 - haircut / 100.0) * (eligibility / 100.0)
		briefing.text = "Demand impulse %+.2f pp · supply innovation %+.2f pp · output gap %+.2f%%." % [shock.get("demand_shock_pct", 0), shock.get("supply_innovation_pct", 0), s.output_gap_pct]
		if shock.get("funding_need_pct_initial_gdp", 0.0) > 0.0 or refinancing_request > 0.0 or s.outstanding_liquidity_pct_initial_gdp > 0.0 or collateral > 0.0:
			briefing.text += "\nFunding need %s (new) · Requested refinancing %s · Refinancing need %s (%% current GDP).\nMaturing principal %s (short loans) · Collateral before haircut %s · Lending value %s (%% current GDP).\nCollateral haircut %.2f%% · Eligibility %.2f%%." % [Career.funding_amount_text(shock.get("funding_need_pct_initial_gdp", 0) / n), Career.funding_amount_text(refinancing_request / n), Career.funding_amount_text(refinancing_need / n), Career.funding_amount_text(s.outstanding_liquidity_pct_initial_gdp / n), Career.funding_amount_text(collateral / n), Career.funding_amount_text(lending_value / n), haircut, eligibility]
		if shock.get("solvency_risk_innovation_pct", 0.0) != 0.0 or s.solvency_risk_wedge_pct != 0.0:
			briefing.text += "\nCurrent impairment impulse %+.2f pp · Prior impairment %.2f pp (spread proxy, not booked bank loss)." % [shock.get("solvency_risk_innovation_pct", 0.0), s.solvency_risk_wedge_pct]
		briefing.tooltip_text = "Refinancing need is capped by maturing short-loan principal. Lending value applies the current collateral haircut and eligibility. Impairment is a credit-spread proxy; liquidity lending cannot create bank capital."
		briefing.text += "\nDeferred demand %+.2f%% potential · prior release %+.2f pp." % [s.deferred_demand_pct, s.demand_release_pct]
		briefing.text += "\n\n" + career.situation_briefing()
		dispatch_details_text = briefing.text
		var previous: Dictionary = career.history[-2] if career.history.size() > 1 else s
		var view := DispatchBrief.present(s, shock, previous, n, career.current_shock_episode())
		if view.ok:
			briefing.text = view.summary
			dispatch_event.text = view.event_title
			dispatch_dilemma.text = view.event_detail
			dispatch_event.visible = not view.event_title.is_empty()
			dispatch_dilemma.visible = not view.event_detail.is_empty()
		else:
			briefing.text = "Current summary unavailable. Open Details for the current record."
		briefing.tooltip_text = "Current meeting data. Hardship memory is an index, not a percentage. Funding uses current annual GDP; settlement can constrain advances. Details shows the full calculations."
	if _is_workout():
		briefing.text = career.situation_briefing() if complete else briefing.text + "\n" + career.situation_briefing()
		briefing.tooltip_text = "Macro conditions and this bank's cash-aware funding needs. Details separates the current record from authored workout assumptions."
		dispatch_details_text += "\n\n" + WORKOUT_HELP
	if complete:
		dispatch_details_text = briefing.text
	dispatch_details_button.disabled = dispatch_details_text.is_empty()
	briefing.accessibility_description = briefing.tooltip_text
	if reset_controls:
		_reset_policy_controls()
	decision_button.disabled = complete
	decision_button.text = ("Episode complete" if _is_workout() else "Career complete") if complete else "Adopt decision  →  Next quarter"
	if follow_up_toggle != null:
		follow_up_toggle.disabled = complete or _is_workout()
		if _is_workout():
			follow_up_toggle.set_pressed_no_signal(false)
	_link_focus(_keyboard_focus_order())
	if update_preview:
		_preview()

func _reset_policy_controls() -> void:
	var s: Dictionary = career.state
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

func _policy_error(error: String) -> String:
	if error == "unrepresentable fractional refinancing advance":
		return "Loan split exceeds numeric precision. Reduce the offer and check the preview."
	if error == "infeasible mandatory settlement after simultaneous principal netting":
		return "Insufficient reserves for settlement. Enable Maintain ample reserves, or adjust purchases/runoff and check the preview."
	return error

func _preview() -> void:
	if funding_plan != null:
		funding_plan.update_plan({}, 0.0, 1.0)
	if loading_controls or forecast_label == null or career.state.is_empty():
		return
	if routine.active:
		_finish_follow_up("Policy edited", false)
		return
	if follow_up_note != null:
		follow_up_note.text = "Hold-rate preview; routine follow-up updates the staff estimate each quarter." if follow_up_toggle.button_pressed else ""
		follow_up_note.visible = follow_up_toggle.button_pressed
	if career.decisions.size() >= _active_horizon():
		forecast_label.text = "Episode complete. Review the retained bank ledger." if _is_workout() else "CAREER COMPLETE\nFinal outcomes at Q240. Compare paths is diagnostic only; no further decisions."
		return
	var policy := _policy()
	var result: Dictionary = career.forecast(policy)
	if not result.ok:
		forecast_label.text = "Preview unavailable: " + _policy_error(result.error)
		return
	var first: Dictionary = result.states[0]
	var last: Dictionary = result.states[-1]
	if _is_workout() and result.diagnostic_beyond_episode:
		forecast_label.tooltip_text = "Q+8 continues diagnostically beyond the playable eighth meeting. No future withdrawal requests are revealed."
	else:
		forecast_label.tooltip_text = ""
	var rate_text := "Rate %.2f%%" % first.policy_rate_pct
	if first.policy_rate_pct < 0.0:
		rate_text += " (effective %.2f%%)" % first.effective_policy_rate_pct
	var n: float = first.decision_nominal_gdp_ratio
	funding_plan.update_plan(first, policy.liquidity_request_pct_initial_gdp, n)
	forecast_label.text = "IF ADOPTED NOW\n%s · assets %+.2f\nRunoff %s · RMP %s · RRP %s\nUnsterilized %s\n\nCONDITIONAL Q+8\nInflation %.2f%% · unemployment %.2f%% · output gap %+.2f%%" % [rate_text, first.asset_flow_applied_pct_initial_gdp / n, Career.funding_amount_text(first.long_securities_runoff_pct_initial_gdp / n), Career.funding_amount_text(first.reserve_maintenance_purchase_pct_initial_gdp / n), Career.funding_amount_text(first.sterilization_applied_pct_initial_gdp / n), Career.funding_amount_text(first.sterilization_unfulfilled_pct_initial_gdp / n), last.four_quarter_inflation_pct, last.unemployment_rate_pct, last.output_gap_pct]

func _decision_briefing() -> String:
	comparison_series = []
	var policy := _policy()
	var selected: Dictionary = career.forecast(policy)
	var held: Dictionary = career.forecast(career.model.benchmark_policy(career.state, career.params, "hold"))
	if not selected.ok or not held.ok:
		return "Comparison unavailable: " + _policy_error(selected.error if not selected.ok else held.error)
	comparison_series = ForecastOverview.series(career.state, selected, held)
	var first: Dictionary = selected.states[0]
	var reference: Dictionary = held.states[0]
	var n: float = first.decision_nominal_gdp_ratio
	if _is_workout():
		var bank: Dictionary = selected.bank_states[0]
		return "CURRENT MEETING / BANK WORKOUT\nRate %.2f%% · Unpaid withdrawals %s · Overdue CB debt %s (%% initial GDP).\n\nFORECASTS / CONDITIONAL PATHS\nStaged policy versus holding the current rate with no new loan offer. Both include this bank's retained claims and known maturities; future withdrawal requests and shocks are excluded. Q+8 may extend beyond the playable eighth meeting.\n\nREFERENCE AND LIMITS\nLoan renewal moves no cash. Fresh advances cannot repair equity. Open Bank workout Details for the authored payment priority and valuation assumptions." % [first.policy_rate_pct, Career.funding_amount_text(bank.withdrawal_queue), Career.funding_amount_text(bank.loan_arrears)]
	var text := "CURRENT MEETING / REQUESTED AND APPLIED\nRequested rate %.2f%% · Applied rate %.2f%%\nRequested assets %+.2f · Applied assets %+.2f\nRequested lending %s · Applied lending %s\n\nNominal rates apply in full on a 1bp quote grid; arrow convenience is 25bp. Negative policy is a U.S. counterfactual with diminishing effective borrowing-rate benefits. No invented purchase, stock or lending-offer ceilings. Runoff cannot exceed principal due. Lending is limited by borrower demand, eligibility, lending value and settlement. Asset and loan amounts here use %% of current annual GDP.\n\n" % [policy.policy_rate_request_pct, first.policy_rate_pct, policy.asset_flow_request_pct_initial_gdp / n, first.asset_flow_applied_pct_initial_gdp / n, Career.funding_amount_text(policy.liquidity_request_pct_initial_gdp / n), Career.funding_amount_text(first.liquidity_applied_pct_initial_gdp / n)]
	if career.decisions.size() >= _active_horizon():
		text = "CAREER COMPLETE / DIAGNOSTIC COMPARISON\nAll paths below continue beyond Q240, not extra playable turns.\n\n" + text
	text += "PORTFOLIO AND FUNDING / CURRENT MEETING\nPrincipal due %s; runoff %s; reinvested %s\nLong runoff %s; reserve-maintenance bills %s; total-asset change %+.2f\nSterilization requested %s; applied RRP %s; unfulfilled %s\nLoan principal repaid %s; refinancing %s; new local lending %s; aggregate lending %s\nEnding reserves %s; reserve-scarcity premium %.3f pp\n\n" % [Career.funding_amount_text(first.principal_due_pct_initial_gdp / n), Career.funding_amount_text(first.principal_runoff_pct_initial_gdp / n), Career.funding_amount_text(first.principal_reinvestment_pct_initial_gdp / n), Career.funding_amount_text(first.long_securities_runoff_pct_initial_gdp / n), Career.funding_amount_text(first.reserve_maintenance_purchase_pct_initial_gdp / n), first.total_asset_change_pct_initial_gdp / n, Career.funding_amount_text(first.sterilization_requested_pct_initial_gdp / n), Career.funding_amount_text(first.sterilization_applied_pct_initial_gdp / n), Career.funding_amount_text(first.sterilization_unfulfilled_pct_initial_gdp / n), Career.funding_amount_text(first.liquidity_repayment_pct_initial_gdp / n), Career.funding_amount_text(first.liquidity_refinancing_applied_pct_initial_gdp / n), Career.funding_amount_text(first.liquidity_new_need_applied_pct_initial_gdp / n), Career.funding_amount_text(first.liquidity_aggregate_applied_pct_initial_gdp / n), Career.funding_amount_text(first.reserves_pct_initial_gdp / first.ending_nominal_gdp_ratio), first.reserve_scarcity_wedge_pct]
	text += "Lending value %s; Eligible local demand %s; aggregate demand %s\nBinding constraints: lending offer %s, collateral %s, eligibility %s; RRP uptake %s, collateral %s, reserves %s\n\n" % [Career.funding_amount_text(first.lending_collateral_capacity_pct_initial_gdp / n), Career.funding_amount_text(first.eligible_local_need_pct_initial_gdp / n), Career.funding_amount_text(first.liquidity_aggregate_need_pct_initial_gdp / n), "yes" if first.liquidity_offer_binding or first.liquidity_aggregate_offer_binding else "no", "yes" if first.liquidity_collateral_binding or first.liquidity_aggregate_collateral_binding else "no", "yes" if first.liquidity_eligibility_binding else "no", "yes" if first.sterilization_uptake_binding else "no", "yes" if first.sterilization_collateral_binding else "no", "yes" if first.sterilization_reserve_binding else "no"]
	var s: Dictionary = career.state
	text += "COMMITTEE DELIBERATION / FEASIBLE RATE ALTERNATIVES\nCompare +25bp, -25bp and today's rate; guidance and other staged tools stay fixed. Forecasts use all current model inputs, not just the dispatch summary, then no new shocks. Each path holds its applied rate.\n\n"
	for alternative in [["Selected", policy.policy_rate_request_pct], ["Tighter rate", first.policy_rate_pct + 0.25], ["Gentler rate", first.policy_rate_pct - 0.25], ["Rate continuity", s.policy_rate_pct]]:
		var other: Dictionary = policy.duplicate()
		other.policy_rate_request_pct = alternative[1]
		var path: Dictionary = selected if var_to_bytes(other) == var_to_bytes(policy) else career.forecast(other)
		if not path.ok:
			text += "%s / unavailable: %s\n\n" % [alternative[0], _policy_error(path.error)]
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
	if s.quarter_index + selected.states.size() > _active_horizon():
		text += "Beyond Q240: diagnostic continuation only, not extra playable turns.\n\n"
	var promise_follow: Dictionary = career.forecast(policy, true)
	if not promise_follow.ok:
		text += "Promise-follow unavailable: " + _policy_error(promise_follow.error) + "\n\n"
	else:
		var a: Dictionary = selected.states[1]
		var b: Dictionary = promise_follow.states[1]
		text += "Q+2 / A VS B\nNominal rate %.2f%% vs %.2f%%\nEffective borrowing rate %.3f%% vs %.3f%%\nPromise follow-through %.1f vs %.1f / 100\nStance adequacy %.1f vs %.1f / 100\n\n" % [a.policy_rate_pct, b.policy_rate_pct, a.effective_policy_rate_pct, b.effective_policy_rate_pct, 100 * a.guidance_followthrough_score, 100 * b.guidance_followthrough_score, 100 * a.stance_adequacy_score, 100 * b.stance_adequacy_score]
		a = selected.states[7]
		b = promise_follow.states[7]
		text += "Q+8 / A VS B\nNominal rate %.2f%% vs %.2f%%\nEffective borrowing rate %.3f%% vs %.3f%%\n\nB / Q+8 PROMISE-FOLLOW\nInflation %.3f%%; unemployment %.3f%%; output gap %+.3f%%\nCredibility %.1f / 100; public support %.1f / 100\n\n" % [a.policy_rate_pct, b.policy_rate_pct, a.effective_policy_rate_pct, b.effective_policy_rate_pct, b.four_quarter_inflation_pct, b.unemployment_rate_pct, b.output_gap_pct, 100 * b.credibility, b.public_support]
		text += "Q+8 / B MINUS A\nInflation %s; unemployment %s\nOutput gap %s; credibility %s; support %s\n\n" % [_change_text(b.four_quarter_inflation_pct - a.four_quarter_inflation_pct, 3, "pp"), _change_text(b.unemployment_rate_pct - a.unemployment_rate_pct, 3, "pp"), _change_text(b.output_gap_pct - a.output_gap_pct, 3, "pp"), _change_text(100 * (b.credibility - a.credibility), 2), _change_text(b.public_support - a.public_support, 2)]
	text += "Q+1 / WHY CREDIBILITY AND SUPPORT MOVE\nSELECTED vs HOLD\nCredibility %.1f vs %.1f / 100\nPublic support %.1f vs %.1f / 100\nInflation-miss memory %.3f vs %.3f pp\nEffective rate %.3f%% vs %.3f%%\nDesired real restraint %+.3f vs %+.3f pp\nEffective-stance distance %.3f vs %.3f pp\nTransmission-frontier shortfall %.3f vs %.3f pp\nStance adequacy %.1f vs %.1f / 100\nPrior-promise follow-through %.1f vs %.1f / 100\nCurrent hardship %.3f vs %.3f support points\nHardship memory %.3f vs %.3f support points\n\n" % [100 * first.credibility, 100 * reference.credibility, first.public_support, reference.public_support, first.inflation_miss_memory_pct, reference.inflation_miss_memory_pct, first.effective_policy_rate_pct, reference.effective_policy_rate_pct, first.stance_target_gap_pct, reference.stance_target_gap_pct, first.stance_distance_pct, reference.stance_distance_pct, first.stance_best_feasible_distance_pct, reference.stance_best_feasible_distance_pct, 100 * first.stance_adequacy_score, 100 * reference.stance_adequacy_score, 100 * first.guidance_followthrough_score, 100 * reference.guidance_followthrough_score, first.current_hardship, reference.current_hardship, first.public_hardship_memory, reference.public_hardship_memory]
	text += "Credibility combines 40%% inflation performance, 40%% stance, 20%% follow-through. Past inflation misses reduce performance. Stance compares effective financing restraint with the desired real gap, without capping that objective. The best-feasible comparison varies the rate continuously, holding other staged tools and guidance fixed; the 1bp quote grid can leave a residual gap. Unreachable restraint earns only partial adequacy, even at best effort. Inflation memory and the desired gap use prior observations. Financing conditions also reflect current balance-sheet, credit and neutral-rate inputs. With no prior announcement, follow-through is neutral. Credibility moves %.0f%% toward the combined score each quarter.\n\nPublic support moves %.0f%% toward its hardship-implied level each quarter. Absolute inflation distance from the %.2f%% target (including below-target positive inflation) and unemployment above the structural reference raise hardship; weighted memory prolongs its effect on support. These scores and the stance rule are game assumptions, not an optimal policy or a measured institutional reputation.\n\n" % [100 * career.params.credibility_adjustment, 100 * career.params.public_support_adjustment, career.params.inflation_target_pct]
	text += "CURRENT TRANSMISSION / SELECTED VS HOLD\nLong yield %.3f%% vs %.3f%%\nCredit spread %.3f%% vs %.3f%%\nUncovered funding %s vs %s\n\n" % [first.long_yield_pct, reference.long_yield_pct, first.credit_spread_pct, reference.credit_spread_pct, Career.funding_amount_text(first.uncovered_funding_pct_initial_gdp / n), Career.funding_amount_text(reference.uncovered_funding_pct_initial_gdp / n)]
	text += "Q+1 immediate financing gap %+.3f pp; retained %+.3f pp\n" % [first.spot_financial_gap_pct, first.financial_restraint_gap_pct]
	text += "Vs HOLD immediate %s; retained %s\n" % [_change_text(first.spot_financial_gap_pct - reference.spot_financial_gap_pct, 3, "pp"), _change_text(first.financial_restraint_gap_pct - reference.financial_restraint_gap_pct, 3, "pp")]
	text += "Immediate is current pricing; retained carries past restraint into demand. Positive is tighter than neutral, not a policy ranking.\n\n"
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
			text += "Contrast unavailable: " + _policy_error(path.error) + "\n\n"
			continue
		var reference_first: Dictionary = path.states[0]
		var reference_last: Dictionary = path.states[-1]
		text += "Q+1 long yield %s; credit spread %s\nQ+8 inflation %s; unemployment %s; credibility %s; support %s\n\n" % [_change_text(first.long_yield_pct - reference_first.long_yield_pct, 3, "pp"), _change_text(first.credit_spread_pct - reference_first.credit_spread_pct, 3, "pp"), _change_text(last.four_quarter_inflation_pct - reference_last.four_quarter_inflation_pct, 3, "pp"), _change_text(last.unemployment_rate_pct - reference_last.unemployment_rate_pct, 3, "pp"), _change_text(100 * (last.credibility - reference_last.credibility), 2), _change_text(last.public_support - reference_last.public_support, 2)]
	text += "REFERENCE AND LIMITS\nHold today's rate, guide to that rate with data dependence, and request no new asset flows or loans. Both paths use the same current shock and no new future shocks. After this meeting, each holds its own applied rate and portfolio switches, with no new asset flows or loans. Principal, short-loan repayment, reserve maintenance and policy lags still operate. The HOLD reference uses default reinvestment/maintenance and no sterilization.\n\nThese are combined effects of the staged controls, not an optimal-policy recommendation or a confidence interval. Positive differences mean a higher value, not necessarily a better outcome. Policy lags can leave first-quarter inflation unchanged even when later outcomes differ."
	return text

func _committee_selected(_index: int) -> void:
	if routine.active:
		_finish_follow_up("Committee priority changed", false)
	_committee_brief()

func _committee_brief() -> void:
	if not is_instance_valid(committee) or not is_instance_valid(committee_note):
		return
	var choices: Array = PolicyCommittee.proposals(career.state, career.params, career.current_briefing(), career.model.nominal_gdp_ratio(career.state))
	var selected: int = maxi(0, committee.selected)
	committee.clear()
	for choice in choices:
		committee.add_item("%s: %.2f%%" % [choice.label, choice.rate])
	committee.select(selected)
	committee_note.text = choices[selected].tradeoff

func _stage_committee() -> void:
	_finish_follow_up("Committee proposal requested", false)
	if career.decisions.size() >= _active_horizon():
		status_label.text = "Career complete. Start a new career to stage policy."
		return
	var choices: Array = PolicyCommittee.proposals(career.state, career.params, career.current_briefing(), career.model.nominal_gdp_ratio(career.state))
	var choice: Dictionary = choices[maxi(0, committee.selected)]
	loading_controls = true
	_apply_input(rate)
	_apply_input(guidance)
	rate.value = choice.rate
	guidance.value = choice.rate
	if choice.has("lending_offer_current_gdp"):
		_apply_input(liquidity)
		liquidity.value = choice.lending_offer_current_gdp
	commitment.select(0)
	_guidance_controls()
	loading_controls = false
	_preview()
	status_label.text = "%s proposal staged, not adopted. Compare its conditional path before deciding." % choice.label

func _staff_rule() -> void:
	_finish_follow_up("Staff estimate requested", false)
	var policy: Dictionary = Advice.policy(career.state, career.params)
	if not policy.get("ok", true):
		status_label.text = policy.error
		return
	loading_controls = true
	_apply_input(rate)
	_apply_input(guidance)
	rate.value = policy.policy_rate_request_pct
	guidance.value = policy.guidance_rate_pct
	commitment.select(0)
	_guidance_controls()
	loading_controls = false
	_preview()
	status_label.text = "Staff estimate staged; other tools unchanged."

func _change_text(change: float, decimals := 1, unit := "points") -> String:
	if change == 0:
		return "unchanged"
	var threshold := 0.5 / pow(10, decimals)
	if abs(change) < threshold:
		return ("up" if change > 0 else "down") + " <" + String.num(threshold, decimals + 1) + " " + unit
	return ("%+." + str(decimals) + "f " + unit) % change

func _advance() -> void:
	if adopting or shutting_down:
		return
	if routine.active:
		_finish_follow_up("Stopped", false, true)
		return
	_apply_policy_inputs()
	var before: Dictionary = career.state.duplicate(true)
	var include_follow_up := follow_up_toggle.button_pressed and not _is_workout()
	var first := career.decisions.size()
	var result := _commit_policy(_policy())
	if not result.ok:
		follow_up_toggle.set_pressed_no_signal(false)
		status_label.text = _policy_error(result.error) + " Last valid quarter retained."
		_preview()
		return
	_refresh(true)
	_show_outcome(before)
	if include_follow_up:
		segment_start = first
		var armed: Dictionary = routine.arm(career.state, career.params, career.decisions[-1], Engine.get_process_frames())
		if armed.ok:
			follow_up_wait_seconds = FOLLOW_UP_INTERVAL_SECONDS
			forecast_label.text = "Preview paused during routine follow-up."
			funding_plan.update_plan({}, 0.0, 1.0)
			stop_follow_up.visible = true
			status_label.text = "Routine follow-up: Q%d completed. Updates wait 2 s; Escape or Stop returns control." % career.state.quarter_index
			_link_focus(_keyboard_focus_order())
		else:
			_finish_follow_up("Routine follow-up unavailable; decision retained.", false)
	elif int(career.state.quarter_index) % 12 == 0:
		_review()

func _commit_policy(policy: Dictionary) -> Dictionary:
	if adopting:
		return {"ok": false, "error": "A decision is already being adopted."}
	adopting = true
	var result: Dictionary = career.advance(policy)
	adopting = false
	return result

func _show_outcome(before: Dictionary) -> void:
	var s: Dictionary = career.state
	var first := int(before.quarter_index) + 1
	var last := int(s.quarter_index)
	var period := "Q%d" % last if first == last else "Q%d–Q%d" % [first, last]
	consequence.text = "%s outcome · Inflation %s · Unemployment %s · Rate %.2f%%\nSupport %s · Credibility %s" % [period, _change_text(s.four_quarter_inflation_pct - before.four_quarter_inflation_pct, 2, "pp"), _change_text(s.unemployment_rate_pct - before.unemployment_rate_pct, 2, "pp"), s.policy_rate_pct, _change_text(s.public_support - before.public_support, 1, "pts"), _change_text((s.credibility - before.credibility) * 100, 1, "pts")]
	consequence.tooltip_text = "Changes cover the labelled completed interval. Rate, promise and funding refer to its final meeting. Support and credibility changes are score points; promise measures follow-through of that meeting's prior announcement."
	consequence.accessibility_description = consequence.tooltip_text
	var prior_meeting: Dictionary = career.history[-2] if career.history.size() > 1 else before
	if prior_meeting.guidance_active:
		consequence.text += " · Promise %.1f/100" % (100 * s.guidance_followthrough_score)
	if _is_workout() and not (career as Workout).settlements.is_empty():
		var settled: Dictionary = (career as Workout).settlements[-1]
		consequence.text += "\nBank advances %s · Cash repaid %s · Renewed %s (%% initial GDP)." % [Career.funding_amount_text(settled.new_cash), Career.funding_amount_text(settled.repayment), Career.funding_amount_text(settled.renewal)]
	elif s.liquidity_applied_pct_initial_gdp > 0.0 or s.uncovered_funding_pct_initial_gdp > 0.0 or s.liquidity_repayment_pct_initial_gdp > 0.0:
		var n: float = s.decision_nominal_gdp_ratio
		consequence.text += "\nFunding (%% meeting GDP): local cash %s · renewed %s · unmet %s." % [Career.funding_amount_text(s.liquidity_new_need_applied_pct_initial_gdp / n), Career.funding_amount_text(s.liquidity_refinancing_applied_pct_initial_gdp / n), Career.funding_amount_text(s.uncovered_funding_pct_initial_gdp / n)]
		if s.liquidity_aggregate_applied_pct_initial_gdp > 0.0:
			consequence.text += " Reserve loans %s." % Career.funding_amount_text(s.liquidity_aggregate_applied_pct_initial_gdp / n)
	_update_outcome_drivers(int(before.quarter_index))
	status_label.text = "Quarter %d completed. Unsaved changes · %s" % [s.quarter_index, "Bank workout" if _is_workout() else career.cases[career.scenario_id].label]

func _update_outcome_drivers(first: int) -> void:
	var last := career.decisions.size()
	var result := TransitionExplanation.segment(career.history, career.shocks, first, last, career.params)
	outcome_drivers.update_result(result, first + 1, last)
	_link_focus(_keyboard_focus_order())

func _driver_details() -> void:
	if routine.active:
		_finish_follow_up("Driver details opened", false)
	if not outcome_drivers.details_text.is_empty():
		_text_dialog("Output-gap drivers", outcome_drivers.details_text)

func _finish_follow_up(reason: String, reset_controls := true, focus_decision := false, reasons: Array[String] = []) -> void:
	var was_active: bool = routine.active
	var first := segment_start
	segment_start = -1
	follow_up_wait_seconds = 0.0
	routine.stop()
	if follow_up_toggle != null:
		follow_up_toggle.set_pressed_no_signal(false)
	if stop_follow_up != null:
		stop_follow_up.visible = false
	if follow_up_note != null:
		follow_up_note.text = ""
		follow_up_note.visible = false
	if not was_active and first < 0:
		return
	last_follow_up_reasons.assign(reasons if not reasons.is_empty() else [reason])
	_refresh(reset_controls)
	_show_outcome(career.history[first])
	status_label.text = "Q%d: %s. Unsaved changes." % [career.state.quarter_index, reason]
	if int(career.state.quarter_index) / 12 > first / 12:
		status_label.text += " Review available in Data & journal."
	if focus_decision:
		rate.get_line_edit().grab_focus()

func _follow_up_frame(delta: float = 0.0) -> void:
	if not routine.active or adopting or shutting_down:
		return
	for input in [rate, guidance, assets, liquidity, inflation_response, activity_response]:
		if input.get_line_edit().text != input.get_meta("numeric_text"):
			_finish_follow_up("Policy draft edited", false)
			return
	var frame := Engine.get_process_frames()
	var next: Dictionary = routine.proposal(career.state.duplicate(true), career.current_briefing(), career.current_shock_episode(), career.params, career.decisions.size(), career.history.size(), frame)
	if next.get("waiting", false):
		return
	if not next.ok or not next.reasons.is_empty():
		var reason := "Follow-up unavailable"
		if not next.reasons.is_empty():
			var names := {"BENCHMARK_DRIFT": "Staff estimate changed", "QUOTA_EXHAUSTED": "Four-quarter check-in", "CURRENT_PHASE": "Current event needs attention", "CURRENT_NEWS": "New economic conditions", "FUNDING_NEED": "Current funding need", "REFINANCING_NEED": "Refinancing requested", "OUTSTANDING_LOANS": "Short loans mature", "RESERVE_SCARCITY": "Reserves are scarce", "UNCOVERED_FUNDING": "Uncovered funding", "CAREER_END": "Career complete", "MALFORMED_OBSERVER": "Current information is invalid"}
			reason = names.get(next.reasons[0], next.reasons[0].replace("_", " ").capitalize())
		_finish_follow_up(reason, true, true, next.reasons)
		return
	if not routine.active or next.token.generation != routine.generation:
		return
	# A stalled frame earns no catch-up burst; input and current-state returns stay immediate.
	follow_up_wait_seconds = maxf(0.0, follow_up_wait_seconds - clampf(delta, 0.0, FOLLOW_UP_MAX_FRAME_CREDIT_SECONDS))
	if follow_up_wait_seconds > 0.0:
		return
	var before: Dictionary = career.state.duplicate(true)
	var result := _commit_policy(next.policy)
	if not result.ok:
		_stage_native_policy(next.policy)
		_finish_follow_up(_policy_error(result.error), false, true)
		return
	if not routine.committed(frame, next.token):
		_finish_follow_up("Follow-up stopped after adoption; scheduling changed.", true, true)
		return
	follow_up_wait_seconds = FOLLOW_UP_INTERVAL_SECONDS
	# Refresh completed data without requesting the policy preview that cancels permission.
	_refresh(true, false)
	_show_outcome(before)
	status_label.text = "Routine follow-up: Q%d completed. Updates wait 2 s; Escape or Stop returns control." % career.state.quarter_index

func _stage_native_policy(policy: Dictionary) -> void:
	loading_controls = true
	var n: float = career.model.nominal_gdp_ratio(career.state)
	rate.value = policy.policy_rate_request_pct
	guidance.value = policy.guidance_rate_pct
	assets.value = policy.asset_flow_request_pct_initial_gdp / n
	liquidity.value = policy.liquidity_request_pct_initial_gdp / n
	inflation_response.value = policy.guidance_inflation_sensitivity
	activity_response.value = policy.guidance_output_gap_sensitivity
	commitment.select(2)
	for pair in [[reinvestment, "reinvest_principal"], [reserve_maintenance, "maintain_ample_reserves"], [sterilization, "sterilize_purchases"]]:
		pair[0].set_pressed_no_signal(policy[pair[1]])
	_guidance_controls()
	loading_controls = false

func _input(event: InputEvent) -> void:
	if not routine.active or not event is InputEventKey or not event.pressed or event.echo or event.keycode in [KEY_SHIFT, KEY_CTRL, KEY_META, KEY_ALT]:
		return
	var focused_adopt := get_viewport().gui_get_focus_owner() in [decision_button, stop_follow_up]
	var stop_only: bool = event.keycode == KEY_ESCAPE or (event.keycode in [KEY_ENTER, KEY_KP_ENTER] and (event.is_command_or_control_pressed() or focused_adopt)) or (event.keycode == KEY_SPACE and focused_adopt)
	_finish_follow_up("Stopped for input", false, stop_only)
	if stop_only:
		get_viewport().set_input_as_handled()

func _save() -> void:
	_finish_follow_up("Save requested", false)
	var result: Dictionary = career.save_to(save_path)
	if result.ok:
		clean_career = career.encode()
	status_label.text = "Saved quarter %d. Policy-career slot updated; older saves untouched." % career.state.quarter_index if result.ok else result.error

func _load() -> void:
	if _is_workout():
		status_label.text = "Choose a normal New career before loading its save. This laboratory is unsaved."
		return
	_finish_follow_up("Load requested", false)
	var dialog := AcceptDialog.new()
	dialog.title = "Load saved career"
	var cancel := dialog.add_button("Cancel", true)
	cancel.pressed.connect(dialog.queue_free)
	dialog.dialog_text = "Load policy-career-v2.save? Unsaved decisions will be replaced. Older slots remain untouched and need their matching prior app/model; no fallback or migration."
	dialog.confirmed.connect(func():
		var result: Dictionary = career.load_from(save_path)
		if result.ok:
			clean_career = career.encode()
			outcome_drivers.clear()
			_refresh(true)
			consequence.text = "Saved career restored with its decisions, economic history and policy lags."
			consequence.tooltip_text = ""
			consequence.accessibility_description = ""
		status_label.text = "Loaded quarter %d." % career.state.quarter_index if result.ok else result.error
	)
	_show_dialog(dialog, Vector2i(740, 180), cancel)
	_link_focus([cancel, dialog.get_ok_button()])

func _request_quit() -> void:
	_finish_follow_up("Quit requested", false)
	if shutting_down:
		return
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

func _quit_app(exit_code := 0) -> void:
	if shutting_down:
		return
	shutting_down = true
	get_tree().paused = true
	music_toggle.disabled = true
	if is_instance_valid(music):
		music.free()
	# The first scene delta includes synchronous startup; use real mixer time.
	var deadline := Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	get_tree().quit(exit_code)

func _restore_keyboard_focus(invoker: WeakRef) -> void:
	for child in get_children():
		if child is Window and child.visible:
			return
	var control: Control = invoker.get_ref() if invoker != null else null
	if control != null and control.is_visible_in_tree() and not (control is BaseButton and control.disabled):
		control.grab_focus()
	else:
		rate.get_line_edit().grab_focus()

func _fit_report(dialog: Window, desired_size := Vector2i(740, 540)) -> Vector2i:
	var content: Control = dialog.get_child(0)
	var parent_size := Vector2i(get_window().get_visible_rect().size)
	var decoration := (dialog.get_size_with_decorations() - dialog.size).max(Vector2i.ZERO)
	var available := (parent_size - decoration).max(Vector2i.ONE)
	var chrome := (Vector2(dialog.get_contents_minimum_size()) - content.get_combined_minimum_size()).max(Vector2.ZERO)
	content.custom_minimum_size = Vector2(690, 450).min((Vector2(available) - chrome).max(Vector2.ONE))
	var fitted := desired_size.min(available)
	if dialog.visible:
		dialog.size = fitted
		var offset := dialog.position - dialog.get_position_with_decorations()
		dialog.position = dialog.position.clamp(offset, (parent_size - dialog.get_size_with_decorations() + offset).max(offset))
	return fitted

func _show_dialog(dialog: Window, desired_size := Vector2i(740, 540), initial: Control = null) -> void:
	_finish_follow_up("Report opened", false)
	var invoker: WeakRef = weakref(get_viewport().gui_get_focus_owner())
	add_child(dialog)
	dialog.tree_exited.connect(func(): _restore_keyboard_focus.call_deferred(invoker))
	dialog.window_input.connect(func(event: InputEvent):
		var focused := dialog.gui_get_focus_owner()
		if focused is OptionButton and focused.get_popup().visible:
			return
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
	dialog.popup_centered(_fit_report(dialog, desired_size) if dialog is ReportDialog else desired_size)
	if dialog is ReportDialog:
		_fit_report.call_deferred(dialog, desired_size)
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
	var dialog := ReportDialog.new()
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
		if case_id == Career.DEFAULT_SCENARIO:
			scenario.select(scenario.item_count - 1)
	scenario.add_item("Bank workout · 8-meeting laboratory")
	scenario.set_item_metadata(scenario.item_count - 1, WORKOUT_CASE)
	box.add_child(scenario)
	seed_input = _spin(box, "Scenario seed", 1, 2147483647, 1, "Same scenario and seed reproduce the path within the same engine and model.")
	seed_input.value = 1
	_label(box, "Default: weakly anchored inflation with recurring dilemmas.\nWeakly anchored inflation also qualifies for Mandate v1. Stagflation & bank run has Recovery v1; other cases are practice.", 13, MUTED)
	dialog.confirmed.connect(func():
		_apply_input(seed_input)
		_start_career(scenario.get_item_metadata(scenario.selected), int(seed_input.value))
	)
	_show_dialog(dialog, Vector2i(740, 240), scenario)
	_link_focus([scenario, seed_input.get_line_edit(), cancel, dialog.get_ok_button()])

func _review() -> void:
	var compared: Dictionary = career.review_comparison()
	if not compared.ok:
		_text_dialog("Policy review", compared.error)
		return
	var dialog := ReportDialog.new()
	dialog.title = "Policy review"
	dialog.get_ok_button().text = "Close review"
	var body := PolicyReview.new()
	body.build(compared, _objective_summary(career.mandate_assessment()))
	dialog.add_child(body)
	var method := dialog.add_button("Method & definitions")
	var rules := dialog.add_button("Challenge rules")
	method.pressed.connect(func():
		var details := _review_details()
		dialog.tree_exited.connect(func(): _text_dialog("Comparison method", details), CONNECT_DEFERRED | CONNECT_ONE_SHOT)
		dialog.queue_free())
	rules.pressed.connect(func():
		dialog.tree_exited.connect(func(): _text_dialog("Challenge rules", _mandate_rules_text()), CONNECT_DEFERRED | CONNECT_ONE_SHOT)
		dialog.queue_free())
	body.gui_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed:
			var bar := body.get_v_scroll_bar()
			match event.keycode:
				KEY_PAGEUP: bar.value -= bar.page
				KEY_PAGEDOWN: bar.value += bar.page
				KEY_HOME: bar.value = 0
				KEY_END: bar.value = bar.max_value
				_: return
			body.accept_event())
	_show_dialog(dialog, Vector2i(800, 650), body)
	_link_focus([body, method, rules, dialog.get_ok_button()])

func _review_details() -> String:
	var s: Dictionary = career.state
	var compared: Dictionary = career.review_comparison()
	if not compared.ok:
		return compared.error
	var paths: Array = [compared.actual, compared.held]
	var staff: Dictionary = compared.get("staff", {})
	var text := "REALIZED PATHS / Q%d–Q%d\nYour policy / Hold" % [compared.from_quarter + 1, compared.to_quarter]
	if not staff.is_empty():
		paths.append(staff)
		text += " / Model benchmark"
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
	text += "References start at your actual Q%d state and use only shocks that already occurred. Hold holds %.2f%% and guides to that rate with data dependence. Model benchmark applies the simple feedback rate rule with matching guidance and data dependence. Both request no new asset flows or loans. Default reinvestment and reserve maintenance stay on; sterilization stays off. Principal and short-loan repayments still settle. Existing stocks, expectations and policy lags carry forward. This is a hindsight comparison, not a forecast or proof of optimal policy.\n\n" % [compared.from_quarter, compared.hold_rate]
	text += BENCHMARK_HELP + "\n\n"
	text += "Lower inflation distance from 2%% and employment shortfall mean lower costs on those separate measures. Only unemployment above structural reference contributes to employment shortfall. There is no dismissal threshold. Uncovered funding is unmet need, averaged using each meeting's nominal GDP, not booked bank losses. Structural unemployment is a model assumption.\n\nCurrent inflation %.2f%%; unemployment %.2f%%; output gap %+.2f%%." % [s.four_quarter_inflation_pct, s.unemployment_rate_pct, s.output_gap_pct]
	var assessment := career.mandate_assessment()
	text += "\n\n" + _objective_summary(assessment)
	if assessment.eligible and assessment.quarters > 0:
		text += "\nCareer averages / prices %s pp; employment %s pp.\nLatest %d quarters / prices %s pp; employment %s pp.\n" % [_mandate_value_text(assessment.inflation_miss, Career.MANDATE_INFLATION_MISS_MAX), _mandate_value_text(assessment.employment_shortfall, Career.MANDATE_EMPLOYMENT_SHORTFALL_MAX), mini(Career.MANDATE_RECENT_QUARTERS, assessment.quarters), _mandate_value_text(assessment.recent_inflation_miss, Career.MANDATE_INFLATION_MISS_MAX), _mandate_value_text(assessment.recent_employment_shortfall, Career.MANDATE_RECENT_EMPLOYMENT_SHORTFALL_MAX)]
	text += "\n" + _mandate_rules_text()
	return text

static func _mandate_value_text(value: float, limit: float) -> String:
	var shown := "%.3f" % value
	if value > limit and float(shown) <= limit:
		return ">%.3f" % limit
	if value < limit and float(shown) >= limit:
		return "<%.3f" % limit
	return shown

func _objective_details() -> void:
	var assessment: Dictionary = career.mandate_assessment()
	var text := _objective_summary(assessment)
	if career.decisions.is_empty():
		text += "\n\nNo completed quarters."
	elif career.scenario_id == "stagflation_bank_run":
		var recovery: Dictionary = career.recovery_assessment()
		text += "\n\nObserved window: %d/12 quarters.\nPrice distance %.6f pp; employment shortfall %.6f pp." % [recovery.window_quarters, recovery.inflation_miss, recovery.employment_shortfall]
	else:
		text += "\n\nCareer averages: prices %.6f pp; employment %.6f pp.\nLatest %d quarters: prices %.6f pp; employment %.6f pp." % [assessment.inflation_miss, assessment.employment_shortfall, mini(career.decisions.size(), Career.MANDATE_RECENT_QUARTERS), assessment.recent_inflation_miss, assessment.recent_employment_shortfall]
	if not career.decisions.is_empty():
		text += "\nFunding totals: applied %.6f; supported need %.6f (%% initial GDP, including refinancing)." % [assessment.funding_applied, assessment.funding_coverable]
	text += "\n\n" + _mandate_rules_text()
	_text_dialog("Challenge progress", text)

func _objective_summary(assessment: Dictionary) -> String:
	if career.scenario_id != "stagflation_bank_run":
		return _mandate_summary(assessment)
	return _recovery_summary(career.recovery_assessment())

func _recovery_summary(recovery: Dictionary) -> String:
	if not recovery.eligible:
		return "Practice · Custom completed inputs; Recovery v1 unavailable."
	var funding := "n.a."
	if recovery.funding_active:
		var shown := "%.3f" % (100.0 * recovery.funding_coverage)
		if float(shown) == 100.0 * Career.MANDATE_FUNDING_COVERAGE_MIN:
			var required: float = Career.MANDATE_FUNDING_COVERAGE_MIN * recovery.funding_coverable
			if recovery.funding_applied < required:
				shown = "<" + shown
			elif recovery.funding_applied > required:
				shown = ">" + shown
		funding = shown + "/95%"
	if recovery.window_quarters < Career.MANDATE_RECENT_QUARTERS:
		return "RECOVERY v1 · Build %d/12 quarters · Prices ≤1 pp · Jobs ≤1 pp · Funding %s" % [recovery.window_quarters, funding]
	return "RECOVERY v1 · 12q prices %s/1 pp · Jobs %s/1 pp · Funding %s · %s" % [_mandate_value_text(recovery.inflation_miss, Career.MANDATE_INFLATION_MISS_MAX), _mandate_value_text(recovery.employment_shortfall, Career.MANDATE_RECENT_EMPLOYMENT_SHORTFALL_MAX), funding, "Stabilized" if recovery.stabilized else "In progress"]

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
	if _is_workout():
		return "Bank workout is an eight-meeting laboratory, without normal career awards."
	if career.scenario_id == "stagflation_bank_run":
		return "Recovery v1 is a separate fictional stabilization objective. Complete at least 12 quarters. Over the latest 12, average absolute inflation distance from 2% must be ≤1 pp and unemployment above its changing structural reference ≤1 pp. Cover ≥95% of cumulative eligible collateral-backed local funding, including refinancing; aggregate reserve loans do not count. No eligible need is n.a. New shocks can end stabilization; play continues through Q240. Only completed canonical shocks qualify. Inherited crisis inflation is not a lifetime-average penalty. Mandate v1 and its 60-year criteria are unchanged. Values are unrounded; neither score claims optimal policy or a real Federal Reserve rule."
	return "Mandate v1 is a fictional game challenge for Varied policy career and Weakly anchored inflation, with canonical completed shocks. At Q240, career-average inflation distance must be ≤%.2f pp and unemployment above its changing structural reference ≤%.2f pp. Latest %d-quarter averages must each be ≤%.2f pp. Cover ≥%.0f%% of haircut/eligibility-supported local funding, including refinancing; aggregate reserve loans and insolvency repair do not count. No eligible need is not applicable. Criteria use unrounded values. Early misses never stop play. Other laboratories and custom completed shock paths are practice. Assessment is recalculated from completed history; it is not a Federal Reserve dismissal rule or an optimal-policy claim." % [Career.MANDATE_INFLATION_MISS_MAX, Career.MANDATE_EMPLOYMENT_SHORTFALL_MAX, Career.MANDATE_RECENT_QUARTERS, Career.MANDATE_RECENT_EMPLOYMENT_SHORTFALL_MAX, 100.0 * Career.MANDATE_FUNDING_COVERAGE_MIN]

func _journal() -> void:
	var text := "%s · seed %d\nRates and changes are percentage units. Asset and lending flows below use %% of each meeting's current annual GDP; ending stocks use ending GDP.\n\n" % ["Bank workout" if _is_workout() else career.cases[career.scenario_id].label, career.seed_value]
	for s in career.history:
		text += "Q%03d | inflation %.2f%% | long expectations %.2f%% | unemployment %.2f%% | structural reference %.2f%% | rate %.2f%% | output gap %+.2f%% | credibility %.1f | support %.1f | hardship memory %.2f | assets %+.2f | loans %s\n\n" % [s.quarter_index, s.four_quarter_inflation_pct, s.expected_long_inflation_pct, s.unemployment_rate_pct, s.structural_unemployment_pct, s.policy_rate_pct, s.output_gap_pct, s.credibility * 100, s.public_support, s.public_hardship_memory, s.asset_flow_applied_pct_initial_gdp / s.decision_nominal_gdp_ratio, Career.funding_amount_text(s.liquidity_applied_pct_initial_gdp / s.decision_nominal_gdp_ratio)]
	if _is_workout():
		text += "\nBank ledger · % initial GDP\n"
		for entry in (career as Workout).settlements:
			text += "Q%d | cash repayment %s | renewal %s | fresh advances %s | withdrawals paid %s | queued %s | overdue %s | equity %+.4f\n" % [entry.state.quarter_index, Career.funding_amount_text(entry.repayment), Career.funding_amount_text(entry.renewal), Career.funding_amount_text(entry.new_cash), Career.funding_amount_text(entry.withdrawals_paid), Career.funding_amount_text(entry.remaining_queue), Career.funding_amount_text(entry.loan_arrears), entry.equity_after]
	var dialog := _text_dialog("Economic history and policy journal", text)
	var review := dialog.add_button("Review realized policy")
	review.disabled = career.decisions.is_empty() or _is_workout()
	review.visible = not _is_workout()
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
	var dialog := ReportDialog.new()
	dialog.title = "How to play"
	var guide := HelpGuide.new()
	guide.build(_help_text(), _read_only_report("How to play", ""))
	if _is_workout():
		guide.show_topic(guide.pages.size() - 1)
	dialog.add_child(guide)
	_show_dialog(dialog, Vector2i(740, 540), guide.body)
	_link_focus([guide.topics, guide.body, dialog.get_ok_button()])

func _help_text() -> String:
	return ("Bank workout\n" + WORKOUT_HELP.replace("\n\n", "\n") + "\n\n" if _is_workout() else "") + KEYBOARD_HELP + STAFF_HELP + "\nNeutral real-rate prior: %.2f%%.\n\n" % career.params.initial_r_star_pct + BENCHMARK_HELP + "\n\n" + _mandate_rules_text() + "\n\nStart a career\nSet a target-range midpoint for a simplified FOMC, not the market's effective rate; a real chair acts with the committee.\n\nEvery career includes seeded background disturbances. Varied policy career and Recurring crises draw from 50 curated exogenous events. Varied policy career starts with weakly anchored inflation, then recurring dilemmas. Weakly anchored inflation remains separately selectable. The baseline starts at equilibrium with no scheduled scenario events, not a shock-free path. The same scenario and seed reproduce a path within the same engine and model.\n\n1. Read the dispatch for current conditions, not future shocks.\n2. Set the target rate. Higher real rates gradually restrain demand; inflation reacts with a lag. A supply shock can raise prices while weakening activity.\n3. Choose guidance. A firm promise is easier to understand, but missing it reduces follow-through credit. Data dependence adjusts the prior promise for changes in inflation and the output gap.\n4. Set purchases or a runoff cap, reinvestment, reserve maintenance and sterilization. Offer secured liquidity for eligible funding, not insolvency.\n5. Inspect applied amounts and the eight-quarter preview, then adopt. The preview assumes no new future shocks.\n\nPolicy committee\nChoose Price stability, Employment or Financial stability, then Stage committee proposal (Cmd/Ctrl+K). Price and employment proposals adjust the current rate by half the published inflation miss or output gap respectively; both round to the policy grid. Financial stability holds the rate and offers today's collateral-backed funding need. These fictional priorities disagree under stagflation; none knows the neutral rate or future shocks. Rate proposals preserve other tools; funding replaces the loan offer. Stage changes controls only. Compare before adopting.\n\nRoutine follow-up (optional)\nOff by default and not saved. Adopt your staged decision, then allow up to three staff rate/guidance updates, for at most four outcomes. Portfolio switches persist; purchase and loan offers reset. Funding, current events, drift or a scheduled check-in returns control. Stop or Escape, editing, reports, New and Load cancel follow-up. Any other non-modifier keypress, including Tab and arrows, also cancels, as do Save, Quit and the staff estimate action. The preview holds a rate; it does not predict adaptive follow-up.\n\nRates and guidance\nNominal rates apply in full: 1bp increments, 25bp arrows. Negative rates are a U.S. counterfactual, with diminishing benefits. Below zero, the effective financing rate is s*tanh(i/s); above zero it is unchanged. The illustrative scale s=1 percentage point is not an estimated lower bound. Credibility prices nominal guidance before this transmission. Stance credibility compares effective restraint with an unsaturated real-gap objective, giving constrained best effort partial credit rather than full adequacy. Conditional implied quotes round to the same 1bp grid before nominal promise follow-through.\n\nSecurities and runoff\nAsset and lending offers use percent of current annual GDP, converted once at the meeting. Purchases are uncapped; their duration-premium effect diminishes with scale. A negative offer caps runoff at maturing Treasury, MBS and bill principal, without selling unmatured holdings. With a zero or positive offer, reinvestment on rolls principal; off allows natural runoff. MBS paydown responds nonlinearly to lagged financing; Treasury timing uses a source-backed maturity ladder.\n\nReserves and sterilization\nMaintain ample reserves buys short bills after all other transactions to meet the disclosed buffer. With maintenance off, currency growth, runoff or loan repayment can exhaust reserves. A rejected settlement preserves the last valid quarter; enable maintenance or adjust purchases/runoff. Bills can ease funding scarcity but are excluded from the long-duration channel: long runoff can coexist with unchanged total assets. Sterilization retains securities and duration effects while replacing reserves with overnight reverse repo liabilities. Uptake, Treasury collateral and settlement can limit absorption. Tagged principal rolls without adding a new absorption target.\n\nLiquidity\nThe offer sets desired concurrent exposure, not accumulated quarterly turnover. Quotes use 0.0001% of current GDP; arrows move 0.25. Small funding amounts show four decimals; positive amounts below 0.0001 show <0.0001. Overnight/short loans mature next quarter. New needs and requested refinancing are separate; eligible refinancing has priority. Default zero refinancing assumes private repayment funds. Eligibility and haircut-adjusted collateral limit advances; excess offers do not become loans. Lending can relieve funding scarcity, not erase losses or create capital. Inspect applied amounts, RRP, reserve-maintenance purchases (RMP) and uncovered funding before adoption. Portfolio switches persist through previews and later meetings; one-time purchase and lending offers reset.\n\nRecovery\nDeferred demand tracks postponed durable/replacement purchases, not all lost consumption. Positive stock supports catch-up spending; negative stock means purchases were brought forward. Financing restraint delays release; growth changes the denominator, and obsolete plans decay. Its unit is percent of quarterly potential output. Short expectations gradually mix observed inflation with prior long expectations according to credibility. Transitory neutral-rate deviations revert toward a structural reference; permanent structural shifts change it. Recovery impulses provide no guaranteed return to 2% under persistent restraint.\n\nCredibility affects guidance pricing and long-run inflation expectations. Public support remembers inflation/deflation hardship and unemployment, recovering gradually without term resets or a game-over threshold.\n\nSaves and access\nSave and Load use policy-career-v2.save only. Prior policy-career-v1.save and original slots career-late-compound-v1.save and career-v1.save remain untouched; use their matching prior app/model. There is no copying, migration or fallback. New career and Load ask before replacing unsaved play. Tab navigates controls; Data & journal gives exact chart values. Animation defaults off.\n\nModel limits\nNine hypothetical scenarios. Varied policy career, Recurring crises and Stagflation & bank run draw from 50 curated exogenous events: disasters, demand/supply changes, funding and credit losses, and favorable developments. Forty-eight independent profiles use a no-repeat bag; two private-bank normalization events require prior eligible stress. The dispatch names active events, not future pulses. Private normalization cannot erase old losses or loans. The 2% objective and portfolio reference observations are source-backed; behavioral coefficients, starting conditions and shock incidence are design assumptions. This is a hypothetical economy, not an empirical forecast or financial advice. No Federal Reserve affiliation. Primary sources and equations are in the repository's FED_RESEARCH and model README."

func _process(delta: float) -> void:
	_follow_up_frame(delta)
	if city != null and not reduced_motion:
		city.rotation.y += delta * 0.025

func _credits() -> void:
	var text := "THE CHAIR / FEDERAL RESERVE POLICY LAB\n\n" + FileAccess.get_file_as_string("res://licenses/THE-CHAIR.txt") + "\nSoundtrack: JRB-1 (ihearttokyo), generated with Suno.\nSystem fonts are supplied by the operating system and are not redistributed.\n\nGODOT ENGINE\n" + Engine.get_license_text()
	for component in Engine.get_copyright_info():
		text += "\n\n" + component.name + "\n"
		for part in component.parts:
			text += "\n".join(part.copyright) + "\nLicense: " + part.license + "\nFiles: " + ", ".join(part.files) + "\n"
	for license_name in Engine.get_license_info():
		text += "\n\n" + license_name + "\n" + Engine.get_license_info()[license_name]
	_text_dialog("Engine and third-party notices", text)
