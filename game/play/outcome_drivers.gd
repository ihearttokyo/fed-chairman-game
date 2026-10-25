extends VBoxContainer
## Completed equation contributions, not isolated policy effects or welfare scores.

signal details_requested

const Explanation = preload("res://play/transition_explanation.gd")
const SHORT_LABELS := ["Persistence", "Financing", "Demand", "Supply", "Release"]
const MINT := Color("75d4c0")
const GOLD := Color("e9b76e")
const MUTED := Color("a4babe")
const HINT := "Equation contributions, not isolated policy effects. Signs show gap direction, not welfare."

class DriverBar:
	extends Control
	var value := 0.0
	var shared_scale := 0.0

	func signed_fraction() -> float:
		return value / shared_scale if shared_scale > 0 else 0.0

	func fill_rect() -> Rect2:
		var centre := size.x / 2.0
		var extent := absf(signed_fraction()) * maxf(0, centre - 1)
		return Rect2(Vector2(centre - extent if value < 0 else centre, 2), Vector2(extent, maxf(0, size.y - 4)))

	func _draw() -> void:
		draw_rect(Rect2(Vector2(0, 2), Vector2(size.x, maxf(0, size.y - 4))), Color("243c44"))
		if value != 0:
			draw_rect(fill_rect(), Color("75d4c0") if value > 0 else Color("e9b76e"))
		draw_line(Vector2(size.x / 2, 0), Vector2(size.x / 2, size.y), Color("a4babe"), 1)

var details_button: Button
var details_text := ""
var heading: Label
var scale_label: Label
var flow: HFlowContainer
var bars: Array[DriverBar] = []
var values: Array[float] = []
var value_labels: Array[Label] = []
var shared_scale := 0.0

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	accessibility_name = "Completed output-gap drivers"
	accessibility_description = "Five equal, zero-centered bars share one absolute scale in percentage points. " + HINT
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	add_child(header)
	heading = _label(header, "", 13, Color("e7eee9"))
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scale_label = _label(header, "", 11, MUTED)
	scale_label.mouse_filter = Control.MOUSE_FILTER_PASS
	scale_label.tooltip_text = "All five bars share this scale and a centered zero. Values are rounded for display."
	details_button = Button.new()
	details_button.text = "Details"
	details_button.add_theme_font_size_override("font_size", 12)
	details_button.tooltip_text = "Read the completed-quarter equation explanation and its limits."
	details_button.accessibility_name = "Outcome driver details"
	details_button.accessibility_description = details_button.tooltip_text
	details_button.pressed.connect(func():
		if not details_text.is_empty():
			details_requested.emit())
	header.add_child(details_button)
	flow = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 8)
	add_child(flow)
	for index in range(SHORT_LABELS.size()):
		var column := VBoxContainer.new()
		column.custom_minimum_size.x = 104
		column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		column.add_theme_constant_override("separation", 2)
		flow.add_child(column)
		var name_label := _label(column, SHORT_LABELS[index], 12, MUTED)
		name_label.accessibility_name = Explanation.TERM_LABELS[index]
		name_label.tooltip_text = HINT
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		var bar := DriverBar.new()
		bar.custom_minimum_size = Vector2(104, 14)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.accessibility_description = HINT
		column.add_child(bar)
		bars.append(bar)
		value_labels.append(_label(column, "", 12, Color("e7eee9")))
	clear()

func update_result(result: Dictionary, first_quarter: int, last_quarter: int) -> void:
	if not _valid_result(result, first_quarter, last_quarter):
		clear()
		return
	# A valid refresh must not hide/disable Details: an active-routine stop can
	# refresh this snapshot while its focused button is opening the disclosure.
	values.clear()
	shared_scale = 0.0
	for amount in result.terms:
		values.append(float(amount))
		shared_scale = maxf(shared_scale, absf(float(amount)))
	if shared_scale > 0:
		shared_scale = maxf(0.01, shared_scale)
	details_text = result.text
	var period := "Q%d" % first_quarter if first_quarter == last_quarter else "Q%d–Q%d" % [first_quarter, last_quarter]
	heading.text = "%s  Output-gap change %s pp" % [period, _signed(result.change)]
	scale_label.text = "±%.3f pp" % shared_scale
	scale_label.accessibility_name = "Shared scale: %s percentage points in each direction, centered at zero" % str(shared_scale)
	heading.accessibility_name = "Q%d through Q%d total output-gap change: %s percentage points" % [first_quarter, last_quarter, _signed(result.change)]
	for index in range(bars.size()):
		var amount: float = values[index]
		bars[index].value = amount
		bars[index].shared_scale = shared_scale
		bars[index].accessibility_name = "%s: %s percentage points" % [Explanation.TERM_LABELS[index], _signed(amount)]
		bars[index].queue_redraw()
		value_labels[index].text = _signed(amount) + " pp"
		value_labels[index].accessibility_name = bars[index].accessibility_name
		value_labels[index].add_theme_color_override("font_color", MINT if amount > 0 else GOLD if amount < 0 else MUTED)
	details_button.disabled = false
	show()

static func _valid_result(result: Dictionary, first_quarter: int, last_quarter: int) -> bool:
	if typeof(result.get("ok")) != TYPE_BOOL or not result.ok:
		return false
	if first_quarter < 1 or last_quarter < first_quarter or last_quarter - first_quarter > 3:
		return false
	if not result.get("terms") is Array or result.terms.size() != Explanation.TERM_LABELS.size() or not result.get("text") is String or result.text.is_empty():
		return false
	if not _finite_number(result.get("change")):
		return false
	var sum := 0.0
	var scale := 0.0
	for amount in result.terms:
		if not _finite_number(amount):
			return false
		sum += float(amount)
		scale += absf(float(amount))
	# Same scale-aware reconciliation tolerance as TransitionExplanation.
	return is_finite(sum) and is_finite(scale) and absf(float(result.change) - sum) <= 1e-9 * maxf(scale, maxf(1.0, absf(float(result.change))))

func clear() -> void:
	hide()
	details_text = ""
	values.clear()
	shared_scale = 0.0
	heading.text = ""
	heading.accessibility_name = ""
	scale_label.text = ""
	scale_label.accessibility_name = ""
	details_button.disabled = true
	for index in range(bars.size()):
		bars[index].value = 0.0
		bars[index].shared_scale = 0.0
		bars[index].accessibility_name = ""
		bars[index].queue_redraw()
		value_labels[index].text = ""
		value_labels[index].accessibility_name = ""

static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func _signed(value: float) -> String:
	if value == 0:
		return "+0.000"
	var text := "%+.3f" % value
	# Keep small nonzero contributions visible, never relabel them as zero.
	return ("up" if value > 0 else "down") + " <0.001" if float(text) == 0 else text

func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
