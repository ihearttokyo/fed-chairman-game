extends VBoxContainer
## Completed-episode readout only; never forecasts, settles, grades or saves.
const MINT := Color("75d4c0")
const GOLD := Color("e9b76e")
const MUTED := Color("a4babe")
const INK := Color("e7eee9")
const BANK_AMOUNTS := ["cash", "deposits", "withdrawal_queue", "central_bank_loan", "loan_arrears", "initial_face", "matured_face"]
const SETTLEMENT_AMOUNTS := ["deposit_due", "withdrawals_paid", "remaining_queue", "loan_arrears", "equity_before", "equity_after"]
const TIMELINE_HINT := "Each bar is that meeting's paid / due. Queued claims repeat until paid; do not add the bars. Gold marks a shortfall; a dash is no payments due."

class PaymentTimeline:
	extends Control
	var quarters: Array = []

	func _make_custom_tooltip(for_text: String) -> Object:
		return preload("res://play/wrapped_tooltip.gd").create(self, for_text)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion and quarters.size() == 8 and size.x > 0:
			var index := clampi(int(event.position.x / (size.x / 8.0)), 0, 7)
			tooltip_text = quarters[index].description

	func _draw() -> void:
		if quarters.size() != 8 or size.x <= 0:
			return
		var font := get_theme_default_font()
		var step := size.x / 8.0
		var height := maxf(1.0, size.y - 24.0)
		for index in range(8):
			var quarter: Dictionary = quarters[index]
			var left := step * index + step * 0.22
			var rect := Rect2(left, 2.0, step * 0.56, height - 4.0)
			if not quarter.applicable:
				draw_line(Vector2(rect.position.x, rect.get_center().y), Vector2(rect.end.x, rect.get_center().y), MUTED, 2.0)
			else:
				draw_rect(rect, Color("493f30") if quarter.short else Color("243c44"))
				var paid_height := rect.size.y * float(quarter.fraction)
				draw_rect(Rect2(rect.position.x, rect.end.y - paid_height, rect.size.x, paid_height), MINT)
				if quarter.short:
					# Keep even a subpixel shortfall visibly different from full payment.
					draw_rect(rect, GOLD, false, 1.0)
					draw_line(rect.position, Vector2(rect.end.x, rect.position.y), GOLD, 2.0)
			var text := "Q%d" % (index + 1) if step >= 24 else str(index + 1)
			if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= step:
				draw_string(font, Vector2(step * index, size.y - 4), text, HORIZONTAL_ALIGNMENT_CENTER, step, 12, MUTED)

var heading := Label.new()
var timeline := PaymentTimeline.new()
var legend := Label.new()
var queue_label := Label.new()
var arrears_label := Label.new()
var equity_label := Label.new()
var note := Label.new()
var snapshot: Dictionary = {"ok": false, "visible": false}

func _make_custom_tooltip(for_text: String) -> Object:
	return preload("res://play/wrapped_tooltip.gd").create(self, for_text)

static func _number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= -9007199254740992 and value <= 9007199254740992
	return typeof(value) == TYPE_FLOAT and is_finite(value)

static func _bank_valid(value: Variant, quarter: int) -> bool:
	if typeof(value) != TYPE_DICTIONARY or typeof(value.get("quarter_index")) != TYPE_INT or value.quarter_index != quarter:
		return false
	for key in BANK_AMOUNTS:
		if not _number(value.get(key)) or value[key] < 0:
			return false
	if value.withdrawal_queue > value.deposits or value.loan_arrears > value.central_bank_loan or not _number(value.get("annual_yield_pct")) or value.annual_yield_pct <= -200 or typeof(value.get("claims")) != TYPE_ARRAY:
		return false
	for claim in value.claims:
		if typeof(claim) != TYPE_DICTIONARY or typeof(claim.get("maturity_quarter")) != TYPE_INT or claim.maturity_quarter <= quarter or not _number(claim.get("face")) or claim.face < 0:
			return false
	return true

static func _amount(value: float) -> String:
	var amount := absf(value)
	var text := ""
	if amount > 0 and amount < 0.0001:
		text = "<0.0001"
	elif amount >= 1000000:
		text = String.num_scientific(amount)
	else:
		text = ("%.4f" if amount > 0 and amount < 0.01 else "%.2f") % amount
	return ("-" if value < 0 else "") + text

static func present(bank_history: Array, settlements: Array, completed: bool) -> Dictionary:
	var unavailable := {"ok": false, "visible": false}
	if not completed or bank_history.size() != 9 or settlements.size() != 8:
		return unavailable
	for quarter in range(9):
		if not _bank_valid(bank_history[quarter], quarter):
			return unavailable
	var quarters: Array = []
	var descriptions: Array[String] = []
	for index in range(8):
		var source: Variant = settlements[index]
		if typeof(source) != TYPE_DICTIONARY or typeof(source.get("ok")) != TYPE_BOOL or not source.ok or source.get("state") != bank_history[index + 1]:
			return unavailable
		for key in SETTLEMENT_AMOUNTS:
			if not _number(source.get(key)) or (not key.begins_with("equity_") and source[key] < 0):
				return unavailable
		var due: float = source.deposit_due
		var paid: float = source.withdrawals_paid
		if paid > due or source.remaining_queue != bank_history[index + 1].withdrawal_queue or source.loan_arrears != bank_history[index + 1].loan_arrears or due - paid != source.remaining_queue:
			return unavailable
		var applicable := due > 0
		var shortfall := applicable and paid < due
		var description := "Q%d · n.a. (no payments due)" % (index + 1)
		if applicable:
			description = "Q%d · paid %s / due %s" % [index + 1, _amount(paid), _amount(due)]
			description += " · short " + _amount(due - paid) if shortfall else " · met"
		descriptions.append(description)
		quarters.append({"quarter": index + 1, "due": due, "paid": paid, "applicable": applicable, "short": shortfall,
			"fraction": paid / due if applicable else 0.0, "description": description})
	var ending: Dictionary = bank_history[8]
	var equity: float = settlements[7].equity_after
	return {"ok": true, "visible": true, "title": "Eight-meeting debrief", "quarters": quarters,
		"ending_queue": ending.withdrawal_queue, "ending_arrears": ending.loan_arrears, "ending_equity": equity,
		"queue_text": "Queued %s (within deposits)" % _amount(ending.withdrawal_queue),
		"arrears_text": "Overdue CB principal %s (within loan)" % _amount(ending.loan_arrears),
		"equity_text": "Mark-to-market equity %s%s" % ["+" if equity > 0 else "", _amount(equity)],
		"timeline_description": "\n".join(descriptions)}

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_NONE
	add_theme_constant_override("separation", 4)
	accessibility_name = "Bank workout eight-meeting debrief"
	for label in [heading, legend, queue_label, arrears_label, equity_label, note]:
		label.add_theme_font_size_override("font_size", 13 if label == heading else 12)
		label.add_theme_color_override("font_color", INK if label in [heading, equity_label] else MUTED)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.focus_mode = Control.FOCUS_NONE
		label.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(heading)
	timeline.custom_minimum_size = Vector2(0, 96)
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline.focus_mode = Control.FOCUS_NONE
	timeline.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(timeline)
	for label in [legend, note, queue_label, arrears_label, equity_label]:
		add_child(label)
	_clear_display()

func _set_label(label: Label, text: String, hint: String) -> void:
	label.text = text
	label.accessibility_name = text
	label.accessibility_description = hint
	label.tooltip_text = hint

func _clear_display() -> void:
	hide()
	for label in [heading, legend, queue_label, arrears_label, equity_label, note]:
		_set_label(label, "", "")
	timeline.quarters = []
	timeline.tooltip_text = ""
	timeline.accessibility_name = ""
	timeline.accessibility_description = ""
	timeline.queue_redraw()
	accessibility_description = ""
	tooltip_text = ""

func update_episode(bank_history: Array, settlements: Array, completed: bool) -> void:
	snapshot = present(bank_history, settlements, completed)
	if not snapshot.ok:
		_clear_display()
		return
	_set_label(heading, snapshot.title, "Completed eight-meeting episode, not a grade or solvency assessment.")
	_set_label(legend, "Paid / due per meeting · mint paid · gold short · dash n.a.", TIMELINE_HINT)
	_set_label(queue_label, snapshot.queue_text, "Ending queued withdrawals only; included in deposits. Repeated quarterly queues are not added.")
	_set_label(arrears_label, snapshot.arrears_text, "Ending overdue CB principal only; included in the CB loan, not extra debt.")
	_set_label(equity_label, snapshot.equity_text, "Signed ending mark-to-market equity; separate from depositor payments, not regulatory capital. Lending does not create equity.")
	_set_label(note, "Ending balances · % initial GDP", "The ending retained claims are not summed across repeated meetings.")
	queue_label.add_theme_color_override("font_color", GOLD if snapshot.ending_queue > 0 else MUTED)
	arrears_label.add_theme_color_override("font_color", GOLD if snapshot.ending_arrears > 0 else MUTED)
	equity_label.add_theme_color_override("font_color", GOLD if snapshot.ending_equity < 0 else INK)
	timeline.quarters = snapshot.quarters.duplicate(true)
	timeline.tooltip_text = TIMELINE_HINT
	timeline.accessibility_name = "Depositor payments, Q1 through Q8"
	timeline.accessibility_description = snapshot.timeline_description + "\n" + TIMELINE_HINT
	timeline.queue_redraw()
	accessibility_description = "%s. %s. %s." % [snapshot.queue_text, snapshot.arrears_text, snapshot.equity_text]
	show()
