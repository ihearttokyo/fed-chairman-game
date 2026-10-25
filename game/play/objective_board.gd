extends VBoxContainer
## Derived score graphics only. The Career scorer remains authoritative.
signal details_requested
const Career = preload("res://play/career.gd")
const MINT := Color("75d4c0")
const GOLD := Color("e9b76e")
const MUTED := Color("a4babe")
class TargetMeter:
	extends Control
	var fraction := 0.0
	var marker := 0.5
	var tint := Color("a4babe")
	func _draw() -> void:
		draw_rect(Rect2(Vector2(0, 3), Vector2(size.x, 8)), Color("243c44"))
		draw_rect(Rect2(Vector2(0, 3), Vector2(size.x * clampf(fraction, 0, 1), 8)), tint)
		draw_line(Vector2(size.x * marker, 0), Vector2(size.x * marker, 14), Color("e7eee9"), 1)
var heading := Label.new()
var details_button := Button.new()
var flow := HFlowContainer.new()
var columns: Array = []
var meters: Array = []
var names: Array = []
var values: Array = []
var states: Array = []
var snapshot: Dictionary = {}
static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value >= 0
static func _valid(a: Dictionary, recovery: bool) -> bool:
	var flags := ["eligible", "prices_met", "employment_met", "funding_active", "funding_met"]
	flags.append_array(["stabilized"] if recovery else ["complete", "achieved"])
	for key in flags:
		if typeof(a.get(key)) != TYPE_BOOL: return false
	for key in ["quarters", "inflation_miss", "employment_shortfall", "funding_coverable", "funding_applied", "funding_coverage"]:
		if not _number(a.get(key)): return false
	if a.quarters > Career.MAX_QUARTERS or a.quarters != floorf(a.quarters): return false
	if recovery:
		if not _number(a.get("window_quarters")) or a.window_quarters > 12 or a.window_quarters != floorf(a.window_quarters): return false
	else:
		for key in ["recent_inflation_miss", "recent_employment_shortfall"]:
			if not _number(a.get(key)): return false
	return a.funding_active == (a.funding_coverable > 0) and is_finite(100.0 * a.funding_coverage)
static func boundary_text(value: float, limit: float) -> String:
	if absf(value) >= 10000.0: return String.num_scientific(value)
	var shown := "%.3f" % value
	if value > limit and float(shown) <= limit: return ">%.3f" % limit
	if value < limit and float(shown) >= limit: return "<%.3f" % limit
	return shown
static func _cost(label: String, value: float, limit: float, met: bool, ready: bool, observed: bool = true) -> Dictionary:
	return {"label":label,"value":value,"limit":limit,"value_text":(boundary_text(value, limit) if observed else "—") + " / " + String.num(limit) + " pp","status":"Building" if not ready else "Within" if met else "Above","met":met,"ready":ready,"fraction":clampf(value / (2.0 * limit), 0, 1),"marker":0.5,"hint":"Completed outcomes only. Lower is better. Marker is the limit; plot ends at twice that limit, not a data cap. Scoring uses unrounded values."}
static func present(mandate: Dictionary, recovery: Dictionary, is_recovery: bool) -> Dictionary:
	var a: Dictionary = recovery if is_recovery else mandate
	if not _valid(a, is_recovery): return {"ok":false,"eligible":false,"title":"Objective unavailable","metrics":[]}
	if not a.eligible: return {"ok":true,"eligible":false,"title":"Practice · No scored objective","metrics":[]}
	var count: int = int(a.quarters)
	var title := ""
	var metrics: Array = []
	if is_recovery:
		var ready: bool = a.window_quarters == Career.MANDATE_RECENT_QUARTERS
		var period := "Latest 12q" if ready else "Build %d/12 quarters" % a.window_quarters
		title = "RECOVERY v1 · %s · %s" % [period, "Stabilized" if a.stabilized else "In progress"]
		metrics.append(_cost("Inflation miss · %dq" % a.window_quarters, a.inflation_miss, Career.MANDATE_INFLATION_MISS_MAX, a.prices_met, ready, a.window_quarters > 0))
		metrics.append(_cost("Job shortfall · %dq" % a.window_quarters, a.employment_shortfall, Career.MANDATE_RECENT_EMPLOYMENT_SHORTFALL_MAX, a.employment_met, ready, a.window_quarters > 0))
	else:
		title = "MANDATE v1 · Q%d/240 · %s" % [count, "Mandate achieved" if a.achieved else "Mandate not met" if a.complete else "In progress"]
		var recent_price: bool = a.recent_inflation_miss > a.inflation_miss
		var recent_jobs: bool = a.recent_employment_shortfall / Career.MANDATE_RECENT_EMPLOYMENT_SHORTFALL_MAX > a.employment_shortfall / Career.MANDATE_EMPLOYMENT_SHORTFALL_MAX
		metrics.append(_cost("Inflation miss 12q" if recent_price else "Inflation miss avg", a.recent_inflation_miss if recent_price else a.inflation_miss, Career.MANDATE_INFLATION_MISS_MAX, a.prices_met, count > 0, count > 0))
		metrics.append(_cost("Job shortfall 12q" if recent_jobs else "Job shortfall avg", a.recent_employment_shortfall if recent_jobs else a.employment_shortfall, Career.MANDATE_RECENT_EMPLOYMENT_SHORTFALL_MAX if recent_jobs else Career.MANDATE_EMPLOYMENT_SHORTFALL_MAX, a.employment_met, count > 0, count > 0))
	var coverage := "n.a."
	if a.funding_active:
		coverage = boundary_text(100.0 * a.funding_coverage, 100.0 * Career.MANDATE_FUNDING_COVERAGE_MIN)
		if absf(100.0 * a.funding_coverage - 100.0 * Career.MANDATE_FUNDING_COVERAGE_MIN) < 0.0005:
			coverage = "95.000"
			var required: float = Career.MANDATE_FUNDING_COVERAGE_MIN * a.funding_coverable
			if a.funding_applied < required: coverage = "<" + coverage
			elif a.funding_applied > required: coverage = ">" + coverage
		coverage += " / 95%"
	metrics.append({"label":"Funding coverage","value":a.funding_coverage,"limit":Career.MANDATE_FUNDING_COVERAGE_MIN,"value_text":coverage,"status":"No scored need" if not a.funding_active else "Target met" if a.funding_met else "Below","met":a.funding_met,"ready":a.funding_active,"fraction":clampf(a.funding_coverage, 0, 1) if a.funding_active else 0.0,"marker":Career.MANDATE_FUNDING_COVERAGE_MIN,"hint":"Completed settlements only. Higher coverage is better. Marker is 95%; plot spans 0–100%. Counts collateral/eligibility-supported local funding, including refinancing; not aggregate reserve loans. Scoring uses applied versus required amounts."})
	metrics[0].hint = "Average absolute distance from the 2% inflation target. " + metrics[0].hint
	metrics[1].hint = "Average unemployment above its changing structural reference. " + metrics[1].hint
	return {"ok":true,"eligible":true,"title":title,"metrics":metrics}
func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	var header := HBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", 13)
	header.add_child(heading)
	details_button.text = "Details"
	details_button.accessibility_name = "Challenge progress details"
	details_button.add_theme_font_size_override("font_size", 12)
	details_button.pressed.connect(func(): details_requested.emit())
	header.add_child(details_button)
	add_child(header)
	flow.add_theme_constant_override("h_separation", 16)
	flow.add_theme_constant_override("v_separation", 8)
	add_child(flow)
	for index in range(3):
		var column := VBoxContainer.new()
		column.custom_minimum_size.x = 150
		column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		flow.add_child(column)
		columns.append(column)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 12)
		column.add_child(label)
		names.append(label)
		var value := Label.new()
		value.add_theme_font_size_override("font_size", 13)
		value.mouse_filter = Control.MOUSE_FILTER_PASS
		column.add_child(value)
		values.append(value)
		var bar := TargetMeter.new()
		bar.custom_minimum_size = Vector2(150, 14)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(bar)
		meters.append(bar)
		var status := Label.new()
		status.add_theme_font_size_override("font_size", 11)
		column.add_child(status)
		states.append(status)
func update_assessment(mandate: Dictionary, recovery: Dictionary, is_recovery: bool) -> void:
	snapshot = present(mandate, recovery, is_recovery)
	heading.text = snapshot.title
	var available: bool = snapshot.ok and snapshot.eligible
	details_button.disabled = not available
	for index in range(3):
		columns[index].visible = available
		if not available:
			names[index].text = ""
			values[index].text = ""
			values[index].tooltip_text = ""
			values[index].accessibility_description = ""
			states[index].text = ""
			meters[index].fraction = 0
			meters[index].queue_redraw()
			continue
		var metric: Dictionary = snapshot.metrics[index]
		var tint: Color = MUTED if not metric.ready else MINT if metric.met else GOLD
		names[index].text = metric.label
		values[index].text = metric.value_text
		values[index].tooltip_text = metric.hint
		values[index].accessibility_name = metric.label
		values[index].accessibility_description = metric.label + ": " + metric.value_text + ", " + metric.status + ". " + metric.hint
		states[index].text = metric.status
		states[index].add_theme_color_override("font_color", tint)
		meters[index].fraction = metric.fraction
		meters[index].marker = metric.marker
		meters[index].tint = tint
		meters[index].queue_redraw()
