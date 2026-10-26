extends "res://play/report_dialog.gd"
## Cached comparisons. Reflow changes only GridContainer.columns, never controls.
signal stage_requested(id: String)
signal refresh_requested
const Docket = preload("res://play/policy_docket.gd")
const METRIC_NAMES := ["Q+8 inflation (%)", "Q+8 unemployment (%)", "Q+1–8 peak unmet funding (% initial GDP)"]
const CARD_MIN_WIDTH := 280.0
var quote: Dictionary = {}
var stage_buttons: Array[Button] = []
var proposal_cards: Array[PanelContainer] = []
var metric_values: Array[Label] = []
var cards: GridContainer
var reference_table: GridContainer
var scroll: ScrollContainer
var content: VBoxContainer
var message: Label
var refresh_button: Button
var details_button: Button
var details: Label
var build_count: int = 0

class MetricPlot:
	extends Control
	var value: float
	var reference: float
	var low: float
	var high: float
	var magnitude: float = 1.0
	var funding: bool = false
	func position_for(number: float) -> float:
		# Divide before subtracting: large finite signed values remain drawable.
		var a: float = low / magnitude
		var b: float = high / magnitude
		return 8.0 + (number / magnitude - a) / (b - a) * maxf(1.0, size.x - 16.0)
	func _draw() -> void:
		var y: float = 9.0
		draw_line(Vector2(8, y), Vector2(size.x - 8, y), Color("8da5ac"), 2.0)
		var x: float = position_for(reference)
		draw_line(Vector2(x, y - 6), Vector2(x, y + 6), Color("e9b76e"), 2.0)
		draw_circle(Vector2(position_for(value), y), 4.0, Color("e7eee9"))
		var font: Font = get_theme_default_font()
		var left: String = Docket.value_text(low, funding)
		var right: String = Docket.value_text(high, funding)
		draw_string(font, Vector2(0, 29), left, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("a4babe"))
		var width: float = font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, Vector2(maxf(0.0, size.x - width), 29), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("a4babe"))

func _init() -> void:
	title = "Compare priorities"
	dialog_hide_on_ok = false
	get_ok_button().text = "Cancel"
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	scroll.resized.connect(_reflow_cards)

func label_in(parent: Node, text: String, font_size: int = 14) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.accessibility_name = text
	parent.add_child(label)
	return label

static func columns_for_width(width: float, separation: float = 10.0) -> int:
	return 3 if width >= 3.0 * CARD_MIN_WIDTH + 2.0 * separation else 1

func _reflow_cards() -> void:
	if is_instance_valid(cards):
		var columns: int = columns_for_width(scroll.size.x - scroll.get_v_scroll_bar().get_combined_minimum_size().x, cards.get_theme_constant("h_separation"))
		if cards.columns != columns:
			cards.columns = columns
			_reveal_card_focus.call_deferred()

func _reveal_card_focus() -> void:
	var focused: Control = gui_get_focus_owner()
	if focused != null and scroll.is_ancestor_of(focused):
		scroll.ensure_control_visible(focused)

func _size_metric_value(number: Label) -> void:
	# Values are atomic. Reserve their full themed width; descriptive labels
	# take the remaining space and wrap, including beside scientific notation.
	number.autowrap_mode = TextServer.AUTOWRAP_OFF
	number.clip_text = false
	number.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	number.size_flags_horizontal = Control.SIZE_SHRINK_END
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font: Font = number.get_theme_font("font")
	var font_size: int = number.get_theme_font_size("font_size")
	number.custom_minimum_size.x = ceilf(font.get_string_size(number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x) + 2.0

func _card(item: Dictionary, scales: Array, references: Array) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("14282f")
	style.border_color = Color("46626a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	cards.add_child(panel)
	proposal_cards.append(panel)
	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", 6)
	panel.add_child(card)
	var heading: Label = label_in(card, item.label, 18)
	heading.add_theme_color_override("font_color", Color("e9b76e"))
	var policy: Dictionary = item.policy
	var n: float = quote.nominal_gdp
	label_in(card, "Rate %s%% · guide %s%%\nLoan offer %s%% current GDP" % [Docket.value_text(policy.policy_rate_request_pct), Docket.value_text(policy.guidance_rate_pct), Docket.value_text(policy.liquidity_request_pct_initial_gdp / n, true)], 13)
	if not item.projection.ok:
		var error_label: Label = label_in(card, "Conditional path unavailable.\n" + ("Controls remain stageable." if item.valid else "Invalid controls."), 13)
		error_label.tooltip_text = item.projection.error + "\n" + item.validation_error
		error_label.accessibility_description = error_label.tooltip_text
	else:
		for metric in range(3):
			var row := HBoxContainer.new()
			card.add_child(row)
			label_in(row, METRIC_NAMES[metric], 12)
			var value: float = item.projection.values[metric]
			var number: Label = label_in(row, Docket.value_text(value, metric == 2), 20)
			_size_metric_value(number)
			metric_values.append(number)
			number.accessibility_name = "%s: %s" % [METRIC_NAMES[metric], number.text]
			var plot := MetricPlot.new()
			plot.value = value
			plot.reference = references[metric]
			plot.low = scales[metric][0]
			plot.high = scales[metric][1]
			plot.magnitude = scales[metric][2]
			plot.funding = metric == 2
			plot.custom_minimum_size = Vector2(0, 32)
			plot.accessibility_name = "%s; shared scale %s to %s" % [number.accessibility_name, Docket.value_text(plot.low, plot.funding), Docket.value_text(plot.high, plot.funding)]
			plot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(plot)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(spacer)
	var button := Button.new()
	button.text = "Stage " + {"prices": "price", "jobs": "jobs", "funding": "funding"}[item.id]
	button.disabled = not item.valid
	button.tooltip_text = item.details + " Matching guidance and standard data dependence. Other tools preserved; funding alone replaces lending."
	button.accessibility_description = button.tooltip_text
	var id: String = item.id
	button.pressed.connect(func(): stage_requested.emit(id))
	card.add_child(button)
	stage_buttons.append(button)

func present(data: Dictionary) -> void:
	quote = data
	build_count += 1
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	stage_buttons.clear()
	proposal_cards.clear()
	metric_values.clear()
	var toolbar := HBoxContainer.new()
	content.add_child(toolbar)
	label_in(toolbar, "Conditional 8-quarter comparison. No new shocks or withdrawal requests. Stage does not adopt.", 13)
	refresh_button = Button.new()
	refresh_button.text = "Refresh"
	refresh_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	refresh_button.pressed.connect(func(): refresh_requested.emit())
	toolbar.add_child(refresh_button)
	message = label_in(content, data.get("error", ""), 13)
	message.visible = not data.get("ok", false)
	if not data.get("ok", false):
		return
	if data.diagnostic:
		label_in(content, "Beyond Q%d: diagnostic continuation only; no extra turns." % data.horizon, 13)
	cards = GridContainer.new()
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("h_separation", 10)
	cards.add_theme_constant_override("v_separation", 10)
	content.add_child(cards)
	var scales: Array = []
	for metric in range(3):
		var low: float = minf(0.0, data.references[metric])
		var high: float = maxf(0.0, data.references[metric])
		for item in data.entries:
			if item.projection.ok:
				low = minf(low, item.projection.values[metric])
				high = maxf(high, item.projection.values[metric])
		if low == high:
			high = low + 1.0
		scales.append([low, high, maxf(1.0, maxf(absf(low), absf(high)))])
	# Keep all five source entries; only the three actionable proposals are cards.
	for item in data.entries.slice(2):
		_card(item, scales, data.references)
	var legend: Label = label_in(content, "Gold ticks: inflation objective %s%% / structural unemployment %s%%. Shared scales." % [Docket.value_text(data.references[0]), Docket.value_text(data.references[1])], 12)
	legend.add_theme_color_override("font_color", Color("e9b76e"))
	reference_table = GridContainer.new()
	reference_table.columns = 4
	reference_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reference_table.add_theme_constant_override("h_separation", 12)
	content.add_child(reference_table)
	for header in ["Reference", "Q+8 inflation %", "Q+8 unemployment %", "Peak unmet % initial GDP"]:
		label_in(reference_table, header, 12)
	for item in data.entries.slice(0, 2):
		var row_name: Label = label_in(reference_table, "Staged" if item.id == "staged" else "Hold", 13)
		row_name.tooltip_text = item.summary
		row_name.accessibility_description = item.summary
		for metric in range(3):
			var value: String = Docket.value_text(item.projection.values[metric], metric == 2) if item.projection.ok else "unavailable"
			var cell: Label = label_in(reference_table, value, 13)
			cell.accessibility_name = "%s: %s %s" % [item.label, METRIC_NAMES[metric], value]
	details_button = Button.new()
	details_button.text = "Details · assumptions and tradeoffs"
	details_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	content.add_child(details_button)
	var details_text: String = "Q%d now; Q+1–8 are quarters ahead. Signed inflation includes deflation; lower inflation is not always better. Today's structural unemployment reference is not a fixed target or welfare ranking. Funding is unmet need, not bank losses; units are %% initial annual GDP.\n\nAll paths use the same current information and known shock/request, with no new future shocks or withdrawal requests. After Q1 each holds its applied rate; new asset/loan offers are zero and its portfolio switches persist. Existing principal, repayments, maturities, expectations and lags continue. These are conditional model paths, not accurate forecasts or optimal policies.\n\nPrice/jobs retain staged assets, lending and portfolio switches. Funding replaces only lending while holding today's rate. All proposals set matching guidance and standard data-dependent responses (inflation / output-gap pp per pp). Hold uses default reinvestment/reserve maintenance on and sterilization off. Projection failure need not invalidate stageable first controls; adoption still validates settlement. Reading/cancelling preserves drafts. Opening stops active routine follow-up.\n" % data.quarter
	for item in data.entries:
		details_text += "\n" + item.label + "\n" + item.summary + ("\n" + item.details if not item.details.is_empty() else "")
		if not item.projection.ok:
			details_text += "\nPath unavailable: " + item.projection.error
	details = label_in(content, details_text, 13)
	details.visible = false
	details_button.pressed.connect(func(): details.visible = not details.visible)
	var order: Array[Control] = []
	for button in stage_buttons:
		if not button.disabled:
			order.append(button)
	order.append(refresh_button)
	order.append(details_button)
	order.append(get_ok_button())
	order.append(scroll)
	scroll.focus_mode = Control.FOCUS_ALL
	for index in range(order.size()):
		order[index].focus_next = order[index].get_path_to(order[(index + 1) % order.size()])
		order[index].focus_previous = order[index].get_path_to(order[(index - 1 + order.size()) % order.size()])
	_reflow_cards()
	_reflow_cards.call_deferred()

func refuse(reason: String) -> void:
	message.text = reason
	message.accessibility_name = reason
	message.visible = true
	for button in stage_buttons:
		button.disabled = true
	refresh_button.grab_focus()

func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed:
		return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and (event.is_command_or_control_pressed() or event.alt_pressed or event.shift_pressed):
		# Never let modified Return reach the main-window Adopt shortcut.
		set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE:
		set_input_as_handled()
		queue_free()
		return
	if event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END] and not event.is_command_or_control_pressed():
		var bar := scroll.get_v_scroll_bar()
		match event.keycode:
			KEY_PAGEUP: bar.value -= bar.page
			KEY_PAGEDOWN: bar.value += bar.page
			KEY_HOME: bar.value = 0
			KEY_END: bar.value = bar.max_value
		set_input_as_handled()
		return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not event.echo:
		var focused: Control = gui_get_focus_owner()
		if focused is Button and not focused.disabled:
			set_input_as_handled()
			focused.pressed.emit()
