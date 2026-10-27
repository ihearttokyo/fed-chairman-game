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
var delta_values: Array[Label] = []
var metric_plots: Array[Control] = []
var delta_scales: Array = []
var cards: GridContainer
var reference_table: GridContainer
var scroll: ScrollContainer
var content: VBoxContainer
var context_footer: VBoxContainer
var message: Label
var refresh_button: Button
var details_button: Button
var details: Label
var build_count: int = 0
var focus_reveal_pending := false

class MetricPlot:
	extends Control
	const NEGATIVE_COLOR := Color("91c9e8")
	const POSITIVE_COLOR := Color("e9b76e")
	const TIE_COLOR := Color("e7eee9")
	var value: float
	var held_value: float
	var delta: float
	var delta_scale: Dictionary
	func position_for(number: float) -> float:
		var center: float = size.x * 0.5
		if delta_scale.radius == 0.0:
			return center
		# Divide before multiplying: finite deltas up to DBL_MAX stay drawable.
		return center + (number / delta_scale.radius) * maxf(0.0, size.x * 0.5 - 8.0)
	func render_state() -> String:
		if delta_scale.overflow:
			return "overflow"
		if value == held_value:
			return "tie"
		# A nonzero double may underflow in normalization or disappear when its
		# coordinate becomes a Vector2. Never turn that into a zero/tie marker.
		var center: float = position_for(0.0)
		var x: float = position_for(delta)
		if absf(x - center) < 1.0 or Vector2(x, 0).x == Vector2(center, 0).x:
			return "below_resolution"
		return "point"
	func direction_color() -> Color:
		return TIE_COLOR if value == held_value else (NEGATIVE_COLOR if value < held_value else POSITIVE_COLOR)
	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
	func _caption(text: String, y: float) -> void:
		var font: Font = get_theme_default_font()
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, Vector2(maxf(0.0, (size.x - width) * 0.5), y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("a4babe"))
	func axis_labels() -> PackedStringArray:
		if not delta_scale.available or delta_scale.overflow or not is_finite(delta_scale.radius) or delta_scale.radius < 0.0:
			return PackedStringArray()
		var radius: float = delta_scale.radius
		if radius == 0.0:
			return PackedStringArray(["0"])
		# Three significant digits for ticks only. Exact raw data and the shared
		# mathematical domain stay untouched in the plot, tooltip and AX detail.
		var extent: String
		if radius >= 0.01 and radius < 1000.0:
			var decimals := 0 if radius >= 100.0 else 1 if radius >= 10.0 else 2 if radius >= 1.0 else 3 if radius >= 0.1 else 4
			extent = String.num(radius, decimals)
		else:
			# Normalize by safe steps: pow(10,-324) underflows and log-based
			# normalization can overflow at the opposite finite-double boundary.
			var mantissa := radius
			var exponent := 0
			while mantissa >= 10.0:
				mantissa /= 10.0
				exponent += 1
			while mantissa < 1.0:
				mantissa *= 10.0
				exponent -= 1
			extent = String.num(mantissa, 2)
			if extent.to_float() >= 10.0:
				extent = "1"
				exponent += 1
			extent += "e" + str(exponent)
		return PackedStringArray(["−" + extent, "0", "+" + extent])
	func _draw() -> void:
		var state: String = render_state()
		if state == "overflow":
			_caption("Shared Δ scale overflow; not plotted", 15)
			return
		var y: float = 7.0
		var center: float = position_for(0.0)
		if state == "below_resolution":
			_caption("Nonzero; below plot resolution", 13)
		else:
			draw_line(Vector2(8, y), Vector2(size.x - 8, y), Color("8da5ac"), 1.0)
			draw_line(Vector2(center, y - 5), Vector2(center, y + 5), TIE_COLOR, 1.0)
			if state == "tie":
				draw_arc(Vector2(center, y), 4.0, 0.0, TAU, 20, TIE_COLOR, 1.5, true)
			else:
				var x: float = position_for(delta)
				draw_line(Vector2(center, y), Vector2(x, y), direction_color(), 2.0)
				draw_circle(Vector2(x, y), 3.5, direction_color())
		var ticks := axis_labels()
		if ticks.is_empty():
			return
		if ticks.size() == 1:
			_caption(ticks[0], 28)
			return
		var font: Font = get_theme_default_font()
		var left: String = ticks[0]
		var right: String = ticks[2]
		draw_string(font, Vector2(0, 28), left, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("a4babe"))
		var width: float = font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, Vector2(maxf(0.0, size.x - width), 28), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("a4babe"))
		_caption("0", 28)

static func hold_projection(entries: Array) -> Dictionary:
	for item in entries:
		if item.id == "hold":
			return item.projection
	return {"ok": false}

static func delta_text(value: float, held: float) -> String:
	# Exact equality only: neither display rounding nor approximate equality can
	# establish a tie. Signs describe arithmetic direction, never welfare.
	if value == held:
		return "Same as Hold · Δ 0 pp"
	var sign_text: String = "−" if value < held else "+"
	var delta: float = value - held
	if not is_finite(delta):
		return "Δ " + sign_text + "overflow vs Hold"
	var amount: String = "<0.005" if absf(delta) < 0.005 else Docket.value_text(absf(delta))
	if amount == "0.00":
		# Guard a formatter's half-step rounding without declaring a false zero.
		amount = String.num_scientific(absf(delta))
	return sign_text + amount + " pp vs Hold"

static func comparison_scales(entries: Array) -> Array:
	var held: Dictionary = hold_projection(entries)
	var scales: Array = []
	for metric in range(3):
		var scale: Dictionary = {"available": held.ok, "overflow": false, "radius": 0.0}
		if held.ok:
			for item in entries:
				if item.projection.ok:
					var delta: float = item.projection.values[metric] - held.values[metric]
					if is_finite(delta):
						scale.radius = maxf(scale.radius, absf(delta))
					else:
						# A clipped/saturated endpoint would fabricate a magnitude.
						# Keep text/absolutes, but withhold this metric's shared plot.
						scale.overflow = true
		scales.append(scale)
	return scales

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
	# Reuse the native Cancel row for a bounded interpretation caption. Its
	# native centering spacers stay in place but no longer consume the caption's
	# width. Neither caption participates in focus order or scrolls off screen.
	var footer: HBoxContainer = get_ok_button().get_parent()
	for child in footer.get_children(true):
		if child is Control and not child is BaseButton:
			child.size_flags_horizontal = Control.SIZE_FILL
	context_footer = VBoxContainer.new()
	context_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context_footer.add_theme_constant_override("separation", 2)
	footer.add_child(context_footer)
	footer.move_child(context_footer, 0)
	get_ok_button().size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.minimum_size_changed.connect(_refit_context_footer, CONNECT_DEFERRED)
	scroll.resized.connect(_reflow_cards)
	content.sort_children.connect(_schedule_card_focus)
	context_footer.sort_children.connect(_schedule_card_focus)
	gui_focus_changed.connect(func(_control: Control): _schedule_card_focus())
	visibility_changed.connect(_schedule_card_focus)

func _refit_context_footer() -> void:
	# Wrapped footer chrome can acquire its final minimum after popup fitting.
	# Reuse Main's bounded report fit, independently of cancellable focus work.
	if is_inside_tree() and visible and not is_queued_for_deletion():
		var parent := get_parent()
		if parent.has_method("_fit_report"):
			parent._fit_report(self)

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
		_schedule_card_focus()

func _schedule_card_focus() -> void:
	if focus_reveal_pending or not is_inside_tree() or not visible or is_queued_for_deletion():
		return
	focus_reveal_pending = true
	# Reflow and wrapped minimum heights can settle after call_deferred. Each
	# actual sort/focus change coalesces into the next frame, without refocusing.
	get_tree().process_frame.connect(_reveal_settled_card_focus, CONNECT_ONE_SHOT)

func _cancel_pending_card_focus() -> void:
	# Explicit navigation wins over an older automatic reveal. Disconnect it
	# rather than leaving a stale callback that could consume a newer request.
	if focus_reveal_pending:
		if get_tree().process_frame.is_connected(_reveal_settled_card_focus):
			get_tree().process_frame.disconnect(_reveal_settled_card_focus)
		focus_reveal_pending = false

func _reveal_settled_card_focus() -> void:
	focus_reveal_pending = false
	if is_inside_tree() and visible and not is_queued_for_deletion():
		_reveal_card_focus()

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

func _card(item: Dictionary, scales: Array, held: Dictionary) -> void:
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
			var metric_group := VBoxContainer.new()
			metric_group.add_theme_constant_override("separation", 0)
			card.add_child(metric_group)
			var row := HBoxContainer.new()
			metric_group.add_child(row)
			label_in(row, METRIC_NAMES[metric], 12)
			var value: float = item.projection.values[metric]
			var number: Label = label_in(row, Docket.value_text(value, metric == 2), 20)
			_size_metric_value(number)
			metric_values.append(number)
			number.accessibility_name = "%s: %s" % [METRIC_NAMES[metric], number.text]
			var change: Label = label_in(metric_group, delta_text(value, held.values[metric]) if held.ok else "Δ unavailable · Hold unavailable", 12)
			delta_values.append(change)
			change.accessibility_name = METRIC_NAMES[metric] + ": " + change.text
			if not held.ok:
				continue
			var plot := MetricPlot.new()
			plot.value = value
			plot.held_value = held.values[metric]
			plot.delta = value - plot.held_value
			plot.delta_scale = scales[metric]
			plot.custom_minimum_size = Vector2(0, 30)
			plot.accessibility_name = change.accessibility_name + "; shared symmetric scale centered on Hold zero"
			plot.accessibility_description = "Nonzero changes below one plot point are labelled, not drawn as zero. Overflow withholds the shared plot. Colors show direction, not welfare."
			change.add_theme_color_override("font_color", plot.direction_color())
			change.tooltip_text = "Raw value: %s; Hold: %s; difference: %s pp. No significance threshold is implied." % [var_to_str(value), var_to_str(plot.held_value), var_to_str(plot.delta)]
			change.tooltip_text += " Shared Δ radius: %s pp; axis ticks are rounded." % var_to_str(scales[metric].radius)
			change.accessibility_description = change.tooltip_text
			plot.accessibility_description += " " + change.tooltip_text
			plot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			metric_group.add_child(plot)
			metric_plots.append(plot)
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
	for parent in [content, context_footer]:
		for child in parent.get_children():
			parent.remove_child(child)
			child.queue_free()
	stage_buttons.clear()
	proposal_cards.clear()
	metric_values.clear()
	delta_values.clear()
	metric_plots.clear()
	delta_scales.clear()
	var toolbar := HBoxContainer.new()
	content.add_child(toolbar)
	label_in(context_footer, "Conditional Q+1–8 · No new shocks/withdrawal requests · Stage does not adopt.", 13)
	var toolbar_space := Control.new()
	toolbar_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toolbar_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(toolbar_space)
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
	delta_scales = comparison_scales(data.entries)
	var held: Dictionary = hold_projection(data.entries)
	# Keep all five source entries; only the three actionable proposals are cards.
	for item in data.entries.slice(2):
		_card(item, delta_scales, held)
	var legend: Label = label_in(context_footer, "Δ vs Hold (pp): direction, not welfare. Inflation objective %s%%; structural unemployment ref %s%% — references, not bar zero." % [Docket.value_text(data.references[0]), Docket.value_text(data.references[1])], 12)
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
	for container in content.find_children("*", "Container", true, false):
		if not container is ScrollContainer:
			container.sort_children.connect(_schedule_card_focus)
	_reflow_cards()
	_reflow_cards.call_deferred()
	_schedule_card_focus()

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
		_cancel_pending_card_focus()
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
