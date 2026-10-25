extends ScrollContainer
## Presentation of already-computed conditional paths; never runs a forecast.
const PathChart = preload("res://play/forecast_chart.gd")
const Career = preload("res://play/career.gd")
var charts: Array = []
var funding_note: Label

static func series(current: Dictionary, selected: Dictionary, held: Dictionary) -> Array:
	if not selected.get("ok", false) or not held.get("ok", false):
		return []
	if not selected.get("states") is Array or not held.get("states") is Array:
		return []
	if selected.states.size() != 8 or held.states.size() != 8:
		return []
	var result: Array = []
	for index in range(9):
		if index > 0 and (not selected.states[index - 1] is Dictionary or not held.states[index - 1] is Dictionary):
			return []
		var a: Dictionary = current if index == 0 else selected.states[index - 1]
		var b: Dictionary = current if index == 0 else held.states[index - 1]
		var row := {}
		for field in ["four_quarter_inflation_pct", "unemployment_rate_pct", "uncovered_funding_pct_initial_gdp"]:
			for source in [["selected_", a], ["held_", b]]:
				if not source[1].has(field) or not (source[1][field] is float or source[1][field] is int) or not is_finite(float(source[1][field])):
					return []
				if field == "uncovered_funding_pct_initial_gdp" and source[1][field] < 0.0:
					return []
				row[source[0] + field] = float(source[1][field])
		result.append(row)
	return result

func build(points: Array, complete: bool, beyond_career: bool = false, playable_horizon: int = 240) -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = true
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var note := Label.new()
	note.text = "Conditional paths · Q0 now; legend values are Q8\nSame current shock; no new shocks. Each path holds its applied rate.\nLater asset/loan offers are zero; portfolio switches persist.\nNot confidence bands. See Details for the Hold baseline."
	if complete:
		note.text = "Career complete · diagnostic continuation only\n" + note.text
	elif beyond_career:
		note.text = "Includes post-Q%d diagnostic points · no extra playable turns\n" % playable_horizon + note.text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	if points.is_empty():
		note.text = "Policy paths unavailable. Open Details for the error."
		return
	var metrics := [["Inflation (%, four-quarter)", "four_quarter_inflation_pct"], ["Unemployment (%)", "unemployment_rate_pct"]]
	var funding_shortfall := false
	for point in points:
		if point.selected_uncovered_funding_pct_initial_gdp > 0.0 or point.held_uncovered_funding_pct_initial_gdp > 0.0:
			funding_shortfall = true
	if funding_shortfall:
		metrics.append(["Unmet funding (% initial GDP)", "uncovered_funding_pct_initial_gdp"])
	for metric in metrics:
		var chart := PathChart.new()
		chart.page_requested.connect(func(direction: int):
			var bar := get_v_scroll_bar()
			bar.value += direction * bar.page)
		chart.heading = metric[0]
		chart.keys = ["selected_" + metric[1], "held_" + metric[1]]
		chart.labels = ["Staged policy", "Hold reference"]
		chart.history = points.duplicate(true)
		chart.inspection_context = "Conditional model path. Q0 is now; Q8 is eight quarters ahead."
		chart.inspection_help = "Details defines continuation and the hold reference."
		if metric[1] == "uncovered_funding_pct_initial_gdp":
			chart.inspection_context += " Funding is % initial GDP."
		chart.minimum_plot_size = Vector2(0, 170)
		chart.compact_legend = true
		chart.zero_floor = metric[1] == "uncovered_funding_pct_initial_gdp"
		if chart.zero_floor:
			chart.value_formatter = Career.funding_amount_text
		box.add_child(chart)
		charts.append(chart)
		chart.accessibility_description = chart.inspection_context + " Left and Right inspect; Home and End jump. Details defines continuation and the hold reference."
	funding_note = Label.new()
	if funding_shortfall:
		var staged_peak := 0.0
		var held_peak := 0.0
		for point in points.slice(1): # Q0 is inherited, not a future policy outcome.
			staged_peak = maxf(staged_peak, point.selected_uncovered_funding_pct_initial_gdp)
			held_peak = maxf(held_peak, point.held_uncovered_funding_pct_initial_gdp)
		funding_note.text = "Q1–Q8 peak: Staged %s%% · Hold %s%% initial GDP.\nUnmet need, not bank losses." % [Career.funding_amount_text(staged_peak), Career.funding_amount_text(held_peak)]
	else:
		funding_note.text = "No funding shortfall in either conditional path."
	funding_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(funding_note)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.alt_pressed and not event.is_command_or_control_pressed():
		var bar := get_v_scroll_bar()
		match event.keycode:
			KEY_PAGEUP: bar.value -= bar.page
			KEY_PAGEDOWN: bar.value += bar.page
			_: return
		accept_event()
