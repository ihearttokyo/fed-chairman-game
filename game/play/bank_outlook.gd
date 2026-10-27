extends PanelContainer
## Presentation only: consumes the same forecast already computed by Main.
const Amounts = preload("res://play/bank_workout_panel.gd")
const LIMITS := "Rate held after adoption; today’s withdrawals only. Later requests unknown; no later loan offers or shocks assumed."
const INK := Color("e7eee9")
const MUTED := Color("a4babe")
const GOLD := Color("e9b76e")
var snapshot: Dictionary = {}
var heading := Label.new()
var summary := Label.new()
var resolution := Label.new()
var payment := Label.new()
var carryover := Label.new()
var limits := Label.new()
var meter := ProgressBar.new()
var path := CapitalPath.new()

class CapitalPath:
	extends Control
	var values: Array = []
	var first_quarter := 1
	var selected := 0
	var formatter: Callable
	var unrounded_formatter: Callable
	var basis := ""
	func _make_custom_tooltip(text: String) -> Object:
		return preload("res://play/wrapped_tooltip.gd").create(self, text)
	func _init() -> void:
		custom_minimum_size = Vector2(0, 86)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		focus_mode = Control.FOCUS_ALL
		accessibility_name = "Conditional bank capital path"
		focus_entered.connect(func(): inspect(selected))
		resized.connect(queue_redraw)
	func set_values(points: Array, start: int, description: String) -> void:
		values = points.duplicate()
		first_quarter = start
		basis = description
		selected = clampi(selected, 0, maxi(0, points.size() - 1))
		visible = not points.is_empty()
		focus_mode = Control.FOCUS_ALL if visible else Control.FOCUS_NONE
		tooltip_text = ""
		accessibility_description = ""
		if visible:
			inspect(selected)
		queue_redraw()
	func inspect(index: int) -> void:
		if values.is_empty():
			return
		selected = clampi(index, 0, values.size() - 1)
		tooltip_text = "Conditional Q%d capital %s; unrounded %s. %s Left/Right inspect meetings; Home/End select endpoints." % [first_quarter + selected, formatter.call(values[selected]), unrounded_formatter.call(values[selected]), basis]
		if render_state(selected) == "below_resolution":
			tooltip_text += " Nonzero below plot resolution; not drawn."
		accessibility_description = tooltip_text
		queue_redraw()
	func _gui_input(event: InputEvent) -> void:
		if values.is_empty():
			return
		if event is InputEventMouseMotion:
			inspect(roundi(clampf((event.position.x - 18) / maxf(1, size.x - 36), 0, 1) * (values.size() - 1)))
		if event is InputEventKey and event.pressed and not event.alt_pressed and not event.is_command_or_control_pressed():
			match event.keycode:
				KEY_LEFT: inspect(selected - 1)
				KEY_RIGHT: inspect(selected + 1)
				KEY_HOME: inspect(0)
				KEY_END: inspect(values.size() - 1)
				_: return
			accept_event()
	func point_at(index: int) -> Vector2:
		var radius := scale_radius()
		var x: float = size.x * 0.5 if values.size() == 1 else 18 + maxf(1, size.x - 36) * index / (values.size() - 1)
		return Vector2(x, 44 - (float(values[index]) / radius) * 20)
	func scale_radius() -> float:
		var radius := 0.0
		for value in values:
			radius = maxf(radius, absf(value))
		return 1.0 if radius == 0.0 else radius
	func scale_text() -> String:
		# Three significant digits for the axis domain, never for inspected data.
		var mantissa := scale_radius()
		var exponent := 0
		while mantissa >= 10.0:
			mantissa /= 10.0
			exponent += 1
		while mantissa < 1.0:
			mantissa *= 10.0
			exponent -= 1
		var text := String.num(mantissa, 2)
		if text.to_float() >= 10.0:
			text = "1.00"
			exponent += 1
		return text + "e" + str(exponent) if exponent < -2 or exponent > 2 else String.num(scale_radius(), maxi(0, 2 - exponent))
	func render_state(index: int) -> String:
		if values[index] == 0.0:
			return "zero"
		return "below_resolution" if absf(point_at(index).y - 44.0) < 1.0 else "point"
	func drawable_samples() -> Array[int]:
		var indices: Array[int] = []
		for index in range(values.size()):
			if render_state(index) != "below_resolution":
				indices.append(index)
		return indices
	func resolution_caption() -> String:
		var labels: PackedStringArray = []
		for index in range(values.size()):
			if render_state(index) == "below_resolution":
				labels.append("Q%d %s" % [first_quarter + index, "−" if values[index] < 0 else "+"])
		return "Not plotted (<1 px): " + ", ".join(labels) if not labels.is_empty() else ""
	func _draw() -> void:
		if values.is_empty():
			return
		var font := get_theme_default_font()
		if has_focus():
			draw_rect(Rect2(Vector2.ZERO, size), Color("e9b76e"), false, 2)
		draw_string(font, Vector2(4, 14), "Q%d capital %s" % [first_quarter + selected, formatter.call(values[selected])], HORIZONTAL_ALIGNMENT_LEFT, maxf(1, size.x - 8), 12, Color("e7eee9"))
		draw_line(Vector2(18, 44), Vector2(size.x - 18, 44), Color("8da5ac"), 1)
		draw_string(font, Vector2(2, 48), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("a4babe"))
		var segment := PackedVector2Array()
		var drawable := drawable_samples()
		for index in range(values.size()):
			if index in drawable:
				segment.append(point_at(index))
			else:
				if segment.size() > 1:
					draw_polyline(segment, Color("e9b76e"), 2, true)
				segment.clear()
		if segment.size() > 1:
			draw_polyline(segment, Color("e9b76e"), 2, true)
		for index in drawable:
			draw_circle(point_at(index), 2, Color("e9b76e"))
		if selected in drawable:
			draw_circle(point_at(selected), 3.5, Color("e7eee9"))
		draw_string(font, Vector2(18, 81), "Q%d" % first_quarter, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("a4babe"))
		if values.size() > 1:
			var last := "Q%d" % (first_quarter + values.size() - 1)
			var width := font.get_string_size(last, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(font, Vector2(size.x - 18 - width, 81), last, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("a4babe"))

static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT and value >= -9007199254740992 and value <= 9007199254740992) or (typeof(value) == TYPE_FLOAT and is_finite(value))

static func signed_amount(value: float) -> String:
	return ("+" if value > 0 else "") + Amounts._amount(value)

static func unrounded_amount(value: float) -> String:
	return JSON.stringify(value, "", true, true)

static func present(preview: Dictionary, quarter: int, priced: bool, active: bool = true) -> Dictionary:
	var unavailable := {"visible": active and quarter < 8, "ok": false, "values": []}
	if not unavailable.visible or quarter < 0 or typeof(preview.get("ok")) != TYPE_BOOL or not preview.ok:
		return unavailable
	var count := 8 - quarter
	for key in ["states", "bank_results"] + (["credit_results"] if priced else []):
		if typeof(preview.get(key)) != TYPE_ARRAY or preview[key].size() < count:
			return unavailable
	var values: Array = []
	var queued := 0.0
	var overdue := 0.0
	for index in range(count):
		var state: Variant = preview.states[index]
		var bank: Variant = preview.bank_results[index]
		if typeof(state) != TYPE_DICTIONARY or typeof(state.get("quarter_index")) != TYPE_INT or state.quarter_index != quarter + index + 1 or typeof(bank) != TYPE_DICTIONARY:
			return unavailable
		for key in ["remaining_queue", "loan_arrears"]:
			if not _number(bank.get(key)) or bank[key] < 0:
				return unavailable
		queued = maxf(queued, bank.remaining_queue)
		overdue = maxf(overdue, bank.loan_arrears)
		var capital: Variant = bank.get("equity_after")
		if priced:
			if typeof(preview.credit_results[index]) != TYPE_DICTIONARY:
				return unavailable
			capital = preview.credit_results[index].get("bank_equity_after")
		if not _number(capital):
			return unavailable
		values.append(float(capital))
	var first: Dictionary = preview.bank_results[0]
	for key in ["deposit_due", "withdrawals_paid"]:
		if not _number(first.get(key)) or first[key] < 0:
			return unavailable
	var due: float = first.deposit_due
	var paid: float = first.withdrawals_paid
	if paid > due:
		return unavailable
	var paid_text: String = Amounts._amount(paid)
	var due_text: String = Amounts._amount(due)
	if paid < due and paid_text == due_text:
		paid_text = "<due (~%s)" % paid_text
	return {"visible": true, "ok": true, "values": values, "first_quarter": quarter + 1, "last_quarter": 8,
		"first": values[0], "minimum": values.min(), "paid": paid, "due": due,
		"payment_fraction": minf(paid, due) / due if due > 0 else 0.0,
		"payment_text": "Q+1 withdrawals paid %s / due %s" % [paid_text, due_text] if due > 0 else "Q+1 withdrawals: none due",
		"queued_peak": queued, "overdue_peak": overdue,
		"basis": "Interest-inclusive equity, not regulatory capital." if priced else "Mark-to-market equity, not regulatory capital."}

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("14282f")
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	add_child(body)
	for label in [heading, summary, resolution, payment, carryover, limits]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 13 if label in [heading, summary] else 12)
		label.add_theme_color_override("font_color", INK if label in [heading, summary, payment] else MUTED)
		body.add_child(label)
	body.move_child(payment, 2)
	body.add_child(path)
	body.move_child(path, 2)
	body.move_child(resolution, 3)
	body.add_child(meter)
	body.move_child(meter, 5)
	meter.custom_minimum_size.y = 8
	meter.max_value = 1.0
	meter.step = 0.0
	meter.show_percentage = false
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("91c9e8")
	meter.add_theme_stylebox_override("fill", fill)
	path.formatter = signed_amount
	path.unrounded_formatter = unrounded_amount
	preload("res://play/wrapped_tooltip.gd").install(self)
	update_forecast({}, 0, false, false)

func _label(label: Label, text: String, hint: String = "") -> void:
	label.visible = not text.is_empty()
	label.text = text
	label.accessibility_name = text
	label.accessibility_description = hint
	label.tooltip_text = hint

func update_forecast(preview: Dictionary, quarter: int, priced: bool, active: bool = true) -> void:
	snapshot = present(preview, quarter, priced, active)
	visible = snapshot.visible
	for label in [heading, summary, resolution, payment, carryover, limits]:
		_label(label, "")
	carryover.hide()
	meter.value = 0
	meter.hide()
	meter.accessibility_name = ""
	meter.accessibility_description = ""
	if not visible:
		path.set_values([], quarter + 1, "")
		return
	_label(heading, "Bank decision outlook · conditional · % initial GDP")
	_label(limits, LIMITS)
	if not snapshot.ok:
		path.set_values([], quarter + 1, "")
		_label(summary, "Outlook unavailable", "No staged capital or payments are shown without a complete finite playable path.")
		return
	var hint: String = snapshot.basis + " Playable meetings only; diagnostic continuation excluded. " + LIMITS
	_label(summary, "Q+1 capital %s · minimum through Q8 %s" % [signed_amount(snapshot.first), signed_amount(snapshot.minimum)], hint + " Unrounded first %s; minimum %s." % [unrounded_amount(snapshot.first), unrounded_amount(snapshot.minimum)])
	path.set_values(snapshot.values, snapshot.first_quarter, hint)
	var below: String = path.resolution_caption()
	_label(resolution, "Capital scale ±" + path.scale_text() + (" · " + below if not below.is_empty() else ""), "Symmetric capital axis; extent rounded to three significant digits. These signed nonzero samples are omitted from the line and points, never drawn as zero. Inspect their unrounded values with Left/Right.")
	_label(payment, snapshot.payment_text, "First staged meeting only: native withdrawal cash paid / queue plus today's requests due. Never a sum of repeated queued dues. A paid withdrawal does not establish solvency.")
	meter.visible = snapshot.due > 0
	meter.value = snapshot.payment_fraction
	meter.accessibility_name = snapshot.payment_text
	meter.accessibility_description = payment.tooltip_text
	if snapshot.queued_peak > 0 or snapshot.overdue_peak > 0:
		carryover.show()
		_label(carryover, "Peak carryover: queued %s · overdue principal %s" % [Amounts._amount(snapshot.queued_peak), Amounts._amount(snapshot.overdue_peak)], "Separate maxima through playable Q8; queue is included in deposits, overdue principal in CB loans. They are not additional liabilities or a sum across meetings.")
