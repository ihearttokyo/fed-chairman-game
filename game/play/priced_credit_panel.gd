extends PanelContainer
## Read-only first-staged-meeting credit display. No ledger/policy calculations.
const MINT := Color("75d4c0")
const GOLD := Color("e9b76e")
const MUTED := Color("a4babe")
const INK := Color("e7eee9")
const FLOW_FIELDS := ["accrued_positive", "accrued_negative", "paid_positive", "paid_negative", "new_cash_for_interest", "new_cash_for_withdrawals"]

class CashArrow:
	extends Control
	var rightward := true
	var tint := MUTED
	func _make_custom_tooltip(for_text: String) -> Object:
		return preload("res://play/wrapped_tooltip.gd").create(self, for_text)
	func _draw() -> void:
		if size.x < 12:
			return
		var start := Vector2(4, size.y / 2)
		var end := Vector2(size.x - 4, size.y / 2)
		if not rightward:
			var swap := start
			start = end
			end = swap
		draw_line(start, end, tint, 2)
		var direction := -1.0 if rightward else 1.0
		draw_line(end, end + Vector2(direction * 5, -4), tint, 2)
		draw_line(end, end + Vector2(direction * 5, 4), tint, 2)

class CashFlows:
	extends VBoxContainer
	var labels: Array[Label] = []
	var destinations: Array[Label] = []
	var arrows: Array[CashArrow] = []
	func _make_custom_tooltip(for_text: String) -> Object:
		return preload("res://play/wrapped_tooltip.gd").create(self, for_text)
	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		add_theme_constant_override("separation", 1)
		for index in range(2):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			add_child(row)
			var label := Label.new()
			label.add_theme_font_size_override("font_size", 12)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.size_flags_stretch_ratio = 3.0
			label.focus_mode = Control.FOCUS_NONE
			label.mouse_filter = Control.MOUSE_FILTER_PASS
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if index == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			labels.append(label)
			var destination := Label.new()
			destination.add_theme_font_size_override("font_size", 12)
			destination.add_theme_color_override("font_color", MUTED)
			destination.focus_mode = Control.FOCUS_NONE
			destination.mouse_filter = Control.MOUSE_FILTER_PASS
			destinations.append(destination)
			var arrow := CashArrow.new()
			arrow.rightward = index == 0
			arrow.custom_minimum_size.y = 12
			arrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			arrow.focus_mode = Control.FOCUS_NONE
			arrow.mouse_filter = Control.MOUSE_FILTER_PASS
			row.add_child(label if index == 0 else destination)
			row.add_child(arrow)
			row.add_child(destination if index == 0 else label)
			arrows.append(arrow)
	func clear() -> void:
		hide()
		tooltip_text = ""
		accessibility_name = ""
		accessibility_description = ""
		for index in range(2):
			labels[index].text = ""
			labels[index].tooltip_text = ""
			labels[index].accessibility_name = ""
			labels[index].accessibility_description = ""
			destinations[index].text = ""
			destinations[index].tooltip_text = ""
			destinations[index].accessibility_name = ""
			destinations[index].accessibility_description = ""
			arrows[index].tint = MUTED
			arrows[index].tooltip_text = ""
			arrows[index].accessibility_name = ""
			arrows[index].accessibility_description = ""
			arrows[index].queue_redraw()
	func display(view: Dictionary, context: String) -> void:
		var hint: String = context + ". " + view.detail + " Arrows show direction, not magnitude. Opposite payments are not netted."
		for index in range(2):
			var text: String = view.bank_text if index == 0 else view.fed_text
			var amount: float = view.paid_positive if index == 0 else view.paid_negative
			var tint: Color = (GOLD if index == 0 else MINT) if amount > 0 else MUTED
			labels[index].text = text
			labels[index].add_theme_color_override("font_color", tint)
			labels[index].tooltip_text = hint
			labels[index].accessibility_name = context + ": " + text
			labels[index].accessibility_description = hint
			destinations[index].text = "Fed" if index == 0 else "Bank"
			destinations[index].tooltip_text = hint
			destinations[index].accessibility_name = context + ": recipient " + destinations[index].text
			destinations[index].accessibility_description = hint
			arrows[index].tint = tint
			arrows[index].tooltip_text = hint
			arrows[index].accessibility_name = context + ": " + text + (" to Fed" if index == 0 else " to bank")
			arrows[index].accessibility_description = hint
			arrows[index].queue_redraw()
		tooltip_text = hint
		accessibility_name = context + ": " + view.bank_text + "; " + view.fed_text
		accessibility_description = hint
		show()

var heading := Label.new()
var units := Label.new()
var staged_basis := Label.new()
var staged_flow := CashFlows.new()
var staged_claims := Label.new()
var staged_purpose := Label.new()
var actual_basis := Label.new()
var actual_flow := CashFlows.new()
var actual_claims := Label.new()
var snapshot: Dictionary = {}

func _make_custom_tooltip(for_text: String) -> Object:
	return preload("res://play/wrapped_tooltip.gd").create(self, for_text)

static func _number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= -9007199254740992 and value <= 9007199254740992
	return typeof(value) == TYPE_FLOAT and is_finite(value)

static func _physical(value: Variant) -> bool:
	return _number(value) and value >= 0

static func _days(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0 and value <= 9007199254740992

static func _amount(value: float) -> String:
	var magnitude := absf(value)
	var text := "<0.0001" if magnitude > 0 and magnitude < 0.0001 else String.num_scientific(magnitude) if magnitude >= 1000000 else ("%.4f" if magnitude > 0 and magnitude < 0.01 else "%.2f") % magnitude
	return ("-" if value < 0 else "") + text

static func _view(data: Dictionary, claims: Dictionary, prefix: String, rate: float, days: int) -> Dictionary:
	return {"ok": true, "settled": true, "paid_positive": float(data.paid_positive), "paid_negative": float(data.paid_negative),
		"payable": float(claims.payable), "receivable": float(claims.receivable),
		"basis": "%s · %s%% APR · %dd/365" % [prefix, _amount(rate), days],
		"bank_text": "Bank pays " + _amount(data.paid_positive), "fed_text": "Fed pays " + _amount(data.paid_negative),
		"unpaid_text": "Unpaid interest · to Fed %s · from Fed %s" % [_amount(claims.payable), _amount(claims.receivable)],
		"purpose_text": "Fresh loan · interest %s · withdrawals %s" % [_amount(data.new_cash_for_interest), _amount(data.new_cash_for_withdrawals)],
		"detail": "Accrued to Fed %s; from Fed %s. Fresh loan cash: interest %s; withdrawals %s. Unpaid interest is separate from CB principal." % [_amount(data.accrued_positive), _amount(data.accrued_negative), _amount(data.new_cash_for_interest), _amount(data.new_cash_for_withdrawals)]}

static func _actual(source: Dictionary) -> Dictionary:
	var unavailable := {"ok": false, "basis": "Actual unavailable"}
	if typeof(source.get("ok")) != TYPE_BOOL or not source.ok or typeof(source.get("has_settlement")) != TYPE_BOOL or not _days(source.get("quarter_index")) or not _physical(source.get("payable")) or not _physical(source.get("receivable")):
		return unavailable
	for key in FLOW_FIELDS + ["annual_rate_pct", "days"]:
		if not source.has(key):
			return unavailable
		if not source.has_settlement and source[key] != null:
			return unavailable
	if not source.has_settlement:
		return {"ok": true, "settled": false, "basis": "Actual · no settlement yet",
			"unpaid_text": "Unpaid interest · to Fed %s · from Fed %s" % [_amount(source.payable), _amount(source.receivable)]}
	if not _number(source.annual_rate_pct) or not _days(source.days):
		return unavailable
	for key in FLOW_FIELDS:
		if not _physical(source[key]):
			return unavailable
	return _view(source, source, "Last actual Q%d" % source.quarter_index, source.annual_rate_pct, source.days)

static func _staged(preview: Dictionary, actual: Dictionary) -> Dictionary:
	var unavailable := {"ok": false, "basis": "Staged unavailable"}
	if typeof(preview.get("ok")) != TYPE_BOOL or not preview.ok:
		return unavailable
	for key in ["credit_contexts", "credit_results", "credit_states", "states"]:
		if typeof(preview.get(key)) != TYPE_ARRAY or preview[key].is_empty() or typeof(preview[key][0]) != TYPE_DICTIONARY:
			return unavailable
	var context: Dictionary = preview.credit_contexts[0]
	var result: Dictionary = preview.credit_results[0]
	var claims: Dictionary = preview.credit_states[0]
	var first: Dictionary = preview.states[0]
	if not _number(context.get("annual_rate_pct")) or not _days(context.get("days")) or not _days(first.get("quarter_index")) or not _physical(claims.get("payable")) or not _physical(claims.get("receivable")):
		return unavailable
	if actual.get("ok", false) and first.quarter_index != actual.quarter_index + 1:
		return unavailable
	for key in FLOW_FIELDS:
		if not _physical(result.get(key)):
			return unavailable
	return _view(result, claims, "Staged Q%d" % first.quarter_index, context.annual_rate_pct, context.days)

static func present(actual: Dictionary, preview: Dictionary) -> Dictionary:
	var last := _actual(actual)
	var staged := _staged(preview, actual if last.ok else {})
	return {"ok": last.ok or staged.ok, "visible": not actual.is_empty() or not preview.is_empty(), "actual": last, "staged": staged}

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_NONE
	accessibility_name = "Borrowing cost: staged and actual interest"
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("142d35")
	panel.set_content_margin_all(8)
	add_theme_stylebox_override("panel", panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	add_child(body)
	for label in [heading, units, staged_basis, staged_claims, staged_purpose, actual_basis, actual_claims]:
		label.add_theme_font_size_override("font_size", 13 if label == heading else 12)
		label.add_theme_color_override("font_color", INK if label in [heading, staged_basis] else MUTED)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.focus_mode = Control.FOCUS_NONE
		label.mouse_filter = Control.MOUSE_FILTER_PASS
	var header := HFlowContainer.new()
	header.add_theme_constant_override("h_separation", 10)
	body.add_child(header)
	header.add_child(heading)
	header.add_child(units)
	for item in [staged_basis, staged_flow, staged_claims, staged_purpose, actual_basis, actual_flow, actual_claims]:
		body.add_child(item)
	preload("res://play/wrapped_tooltip.gd").install(self)
	update_credit({}, {})

func _label(label: Label, text: String, hint: String = "") -> void:
	label.visible = not text.is_empty()
	label.text = text
	label.accessibility_name = text
	label.tooltip_text = hint
	label.accessibility_description = hint

func update_credit(actual: Dictionary, preview: Dictionary) -> void:
	snapshot = present(actual, preview)
	for label in [heading, units, staged_basis, staged_claims, staged_purpose, actual_basis, actual_claims]:
		_label(label, "")
	staged_flow.clear()
	actual_flow.clear()
	accessibility_description = ""
	tooltip_text = ""
	visible = snapshot.visible
	if not snapshot.visible:
		return
	_label(heading, "Borrowing cost")
	_label(units, "% initial GDP", "Cash and unpaid interest amounts; APR is an annual percentage, not a GDP share.")
	_label(staged_basis, snapshot.staged.basis, "First staged meeting only. APR follows staged policy controls under an authored rule; negative APR is a counterfactual. Day count uses a 365-day year. Later conditional meetings are not used here.")
	if snapshot.staged.ok:
		staged_flow.display(snapshot.staged, "Staged interest cash")
		_label(staged_claims, snapshot.staged.unpaid_text, "After the first staged settlement, separate from CB principal. No automatic setoff.")
		staged_claims.add_theme_color_override("font_color", GOLD if snapshot.staged.payable > 0.0 else MINT if snapshot.staged.receivable > 0.0 else MUTED)
		_label(staged_purpose, snapshot.staged.purpose_text, snapshot.staged.detail)
	_label(actual_basis, snapshot.actual.basis, "Last adopted settlement only, never the current held-rate quote or staged controls.")
	if snapshot.actual.ok:
		_label(actual_claims, snapshot.actual.unpaid_text, "Current actual unpaid interest, separate from CB principal; not a new liability added to principal.")
		actual_claims.add_theme_color_override("font_color", GOLD if actual.payable > 0.0 else MINT if actual.receivable > 0.0 else MUTED)
		if snapshot.actual.settled:
			actual_flow.display(snapshot.actual, "Last actual interest cash")
	accessibility_description = snapshot.staged.basis + "; " + snapshot.actual.basis
