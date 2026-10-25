extends ScrollContainer
## Read-only comparison: each metric has a shared, zero-based scale across paths.
const COLORS := [Color("75d4c0"), Color("a4babe"), Color("e9b76e")]
const METRICS := [
	["Inflation distance", "inflation_miss", 1.0, "pp", "Lower is better · distance from 2%"],
	["Employment shortfall", "employment_shortfall", 1.0, "pp", "Lower is better · unemployment above structural reference"],
	["Uncovered funding", "uncovered_funding", 1.0, "% GDP", "Lower is better · unmet need, not bank losses"],
	["Credibility", "credibility", 100.0, "/100", "Higher is better · ending value"],
	["Public support", "public_support", 1.0, "/100", "Higher is better · ending value"]]
var bars: Array[ProgressBar] = []

func build(compared: Dictionary, objective: String = "") -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = true
	focus_mode = Control.FOCUS_ALL
	accessibility_name = "Realized policy comparison"
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	_label(box, "Q%d–Q%d  Policy paths" % [compared.from_quarter + 1, compared.to_quarter], 22)
	_label(box, "Completed shocks · hindsight, not a forecast.", 14)
	if not objective.is_empty():
		_label(box, objective, 14)
	var paths: Array = [compared.actual, compared.held]
	var names := ["Your policy", "Hold"]
	if not compared.get("staff", {}).is_empty():
		paths.append(compared.staff)
		names.append("Model benchmark")
		_label(box, "Benchmark vs you: inflation distance %+.2f pp; job shortfall %+.2f pp." % [compared.staff.inflation_miss - compared.actual.inflation_miss, compared.staff.employment_shortfall - compared.actual.employment_shortfall], 14)
	else:
		_label(box, compared.get("staff_error", "Model benchmark unavailable."), 14)
	for metric in METRICS:
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation", 3)
		box.add_child(group)
		_label(group, metric[0], 17)
		_label(group, metric[4], 12)
		var ceiling := 0.001
		for path in paths:
			ceiling = maxf(ceiling, float(path[metric[1]]) * metric[2])
		for i in paths.size():
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			group.add_child(row)
			var name_label := _label(row, names[i], 13)
			name_label.custom_minimum_size.x = 125
			var value: float = float(paths[i][metric[1]]) * metric[2]
			var bar := ProgressBar.new()
			bar.step = 0.0
			bar.min_value = 0.0
			bar.max_value = ceiling
			bar.value = value
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(24, 12)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var fill := StyleBoxFlat.new()
			fill.bg_color = COLORS[i]
			fill.set_corner_radius_all(2)
			bar.add_theme_stylebox_override("fill", fill)
			var track := StyleBoxFlat.new()
			track.bg_color = Color("243c44")
			bar.add_theme_stylebox_override("background", track)
			bar.accessibility_name = "%s: %s %.3f %s" % [metric[0], names[i], value, metric[3]]
			row.add_child(bar)
			bars.append(bar)
			var displayed := "%.1f" % value if metric[3] == "/100" else "%.2f" % value
			if value > 0.0 and float(displayed) == 0.0:
				displayed = "<0.1" if metric[3] == "/100" else "<0.01"
			var number := _label(row, "%s %s" % [displayed, metric[3]], 13)
			number.custom_minimum_size.x = 108
			number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label(box, "First three measures are period averages; credibility and support are ending values.", 13)

func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label
