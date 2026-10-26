extends VBoxContainer
## Read-only allocation of the existing first forecast; no model or policy calls.
const MINT := Color("75d4c0")
const GOLD := Color("e9b76e")
const INK := Color("e7eee9")
const MUTED := Color("a4babe")
const FIELDS := ["liquidity_refinancing_applied_pct_initial_gdp", "liquidity_new_need_applied_pct_initial_gdp", "liquidity_aggregate_applied_pct_initial_gdp", "liquidity_applied_pct_initial_gdp", "uncovered_funding_pct_initial_gdp"]
const NAMES := ["Renew", "Fresh cash", "Reserve loans"]
const TINTS := [GOLD, MINT, MUTED]
const HINTS := ["Existing local loan principal renewed, not fresh cash. Amount is % of meeting GDP.", "Fresh local cash advances, not bank capital. Amount is % of meeting GDP.", "Aggregate reserve loans, not local withdrawal payments. Amount is % of meeting GDP."]
const SCALE_HINT := "Allocation of applied lending; renewal is not cash. Reserve loans are not local withdrawal payments. Unused offer is not booked."
const UNMET_HINT := "Uncovered local funding, including unrenewed principal; not capital repair. Amount is % of meeting GDP."

class AllocationBar:
	extends Control
	var fractions: Array = [0.0, 0.0, 0.0]

	func _make_custom_tooltip(for_text: String) -> Object:
		return preload("res://play/wrapped_tooltip.gd").create(self, for_text)

	func segment_rect(index: int) -> Rect2:
		var start := 0.0
		for earlier in range(index):
			start += float(fractions[earlier])
		return Rect2(Vector2(size.x * start, 0), Vector2(size.x * float(fractions[index]), size.y))

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("243c44"))
		for index in range(fractions.size()):
			if fractions[index] > 0:
				draw_rect(segment_rect(index), TINTS[index])

var heading := Label.new()
var bar := AllocationBar.new()
var legend := HFlowContainer.new()
var legend_labels: Array[Label] = []
var unmet_label := Label.new()
var snapshot: Dictionary = {"ok": false, "visible": false}

static func _physical(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value >= 0

static func _amount(value: float, positive_source: bool = false) -> String:
	# Career's funding precision, including positive quantities below precision
	# (or below representable converted precision), without displaying false zero.
	if (value > 0 and value < 0.0001) or (value == 0 and positive_source):
		return "<0.0001"
	if value >= 1000000:
		return String.num_scientific(value)
	return ("%.4f" if value > 0 and value < 0.01 else "%.2f") % value

static func present(first_state: Dictionary, offer_initial_gdp: float, meeting_gdp_ratio: float) -> Dictionary:
	var unavailable := {"ok": false, "visible": false}
	if not _physical(offer_initial_gdp) or not is_finite(meeting_gdp_ratio) or meeting_gdp_ratio <= 0:
		return unavailable
	for field in FIELDS:
		if not _physical(first_state.get(field)):
			return unavailable
	var amounts: Array = []
	for index in range(3):
		amounts.append(float(first_state[FIELDS[index]]))
	var applied: float = first_state.liquidity_applied_pct_initial_gdp
	var unmet: float = first_state.uncovered_funding_pct_initial_gdp
	# Compare normalized finite quantities instead of overflowing a gross sum.
	var scale := maxf(applied, maxf(amounts[0], maxf(amounts[1], amounts[2])))
	var normalized: Array = [0.0, 0.0, 0.0]
	var total := 0.0
	if scale > 0:
		for index in range(3):
			normalized[index] = float(amounts[index]) / scale
			total += float(normalized[index])
		if absf(total - applied / scale) > 1e-9:
			return unavailable
	var offer_scale := maxf(applied, offer_initial_gdp)
	if offer_scale > 0 and applied / offer_scale - offer_initial_gdp / offer_scale > 1e-9:
		return unavailable
	var converted: Array = []
	for amount in amounts:
		var current := float(amount) / meeting_gdp_ratio
		if not is_finite(current):
			return unavailable
		converted.append(current)
	var applied_current := applied / meeting_gdp_ratio
	var offered_current := offer_initial_gdp / meeting_gdp_ratio
	var unmet_current := unmet / meeting_gdp_ratio
	if not is_finite(applied_current) or not is_finite(offered_current) or not is_finite(unmet_current):
		return unavailable
	var fractions: Array = [0.0, 0.0, 0.0]
	var labels: Array = []
	for index in range(3):
		if total > 0:
			fractions[index] = float(normalized[index]) / total
		labels.append(NAMES[index] + " " + _amount(converted[index], amounts[index] > 0))
	return {
		"ok": true, "visible": offer_initial_gdp > 0 or applied > 0 or unmet > 0,
		"applied_initial_gdp": applied, "offered_initial_gdp": offer_initial_gdp, "unmet_initial_gdp": unmet,
		"amounts_initial_gdp": amounts, "amounts_meeting_gdp": converted,
		"applied_meeting_gdp": applied_current, "offered_meeting_gdp": offered_current, "unmet_meeting_gdp": unmet_current,
		"fractions": fractions, "labels": labels,
		"heading": "Lending plan · %s applied / %s offered (%% meeting GDP)" % [_amount(applied_current, applied > 0), _amount(offered_current, offer_initial_gdp > 0)],
		"unmet_text": "Unmet local " + _amount(unmet_current, true) if unmet > 0 else "",
	}

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_NONE
	add_theme_constant_override("separation", 3)
	accessibility_name = "Lending plan"
	_style_label(heading, 13, INK)
	add_child(heading)
	bar.custom_minimum_size.y = 10
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.focus_mode = Control.FOCUS_NONE
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(bar)
	legend.add_theme_constant_override("h_separation", 10)
	legend.add_theme_constant_override("v_separation", 3)
	add_child(legend)
	for index in range(3):
		var label := Label.new()
		_style_label(label, 12, TINTS[index])
		label.custom_minimum_size.x = 124 if index == 2 else 100
		label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		legend.add_child(label)
		legend_labels.append(label)
	_style_label(unmet_label, 12, GOLD)
	add_child(unmet_label)
	_clear_display()

func _style_label(label: Label, font_size: int, tint: Color) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.focus_mode = Control.FOCUS_NONE
	label.mouse_filter = Control.MOUSE_FILTER_PASS

func _set_label(label: Label, text: String, hint: String) -> void:
	label.text = text
	label.accessibility_name = text
	label.tooltip_text = hint
	label.accessibility_description = hint

func _clear_display() -> void:
	hide()
	_set_label(heading, "", "")
	_set_label(unmet_label, "", "")
	unmet_label.hide()
	for label in legend_labels:
		_set_label(label, "", "")
	bar.fractions = [0.0, 0.0, 0.0]
	bar.accessibility_name = ""
	bar.accessibility_description = ""
	bar.tooltip_text = ""
	bar.queue_redraw()

func update_plan(first_state: Dictionary, offer_initial_gdp: float, meeting_gdp_ratio: float) -> void:
	snapshot = present(first_state, offer_initial_gdp, meeting_gdp_ratio)
	if not snapshot.ok or not snapshot.visible:
		_clear_display()
		return
	_set_label(heading, snapshot.heading, "First conditional forecast meeting only. Amounts are % of current meeting GDP. Offers are not guaranteed advances or capital repair.")
	for index in range(3):
		_set_label(legend_labels[index], snapshot.labels[index], HINTS[index])
	bar.fractions = snapshot.fractions.duplicate()
	bar.accessibility_name = "Allocation of applied lending: " + "; ".join(snapshot.labels) + " (% meeting GDP)"
	bar.tooltip_text = SCALE_HINT
	bar.accessibility_description = SCALE_HINT
	bar.queue_redraw()
	_set_label(unmet_label, snapshot.unmet_text, UNMET_HINT)
	unmet_label.visible = snapshot.unmet_initial_gdp > 0
	show()
