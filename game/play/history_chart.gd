extends Control

var history: Array = []
var keys := ["four_quarter_inflation_pct", "expected_long_inflation_pct"]
var labels := ["Inflation · 4-quarter", "Long expectations"]
var colors := [Color("e9b76e"), Color("75d4c0")]
var heading := "PRICES & EXPECTATIONS"
var hovered := -1
var inspection_context := "Historical chart."
var inspection_help := "Exact values are available in the Data and journal button."
var minimum_plot_size := Vector2(310, 190)
var compact_legend := false
var zero_floor := false
var value_formatter: Callable

func _make_custom_tooltip(for_text: String) -> Object:
	return preload("res://play/wrapped_tooltip.gd").create(self, for_text)

static func tick_quarters(count: int) -> Array:
	return [0] if count <= 1 else [0, 1] if count == 2 else [0, roundi((count - 1) / 2.0), count - 1]

func _ready() -> void:
	custom_minimum_size = minimum_plot_size
	focus_mode = Control.FOCUS_ALL
	focus_entered.connect(func(): _inspect(history.size() - 1))
	focus_exited.connect(func(): hovered = -1; queue_redraw())
	mouse_exited.connect(func():
		if not has_focus():
			hovered = -1
			queue_redraw())
	accessibility_name = heading
	accessibility_description = inspection_context + " " + inspection_help

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not history.is_empty():
		_inspect(roundi((event.position.x - 42) / maxf(1, size.x - 58) * (history.size() - 1)))
	if event is InputEventKey and event.pressed and not history.is_empty() and not event.alt_pressed and not event.is_command_or_control_pressed():
		match event.keycode:
			KEY_LEFT: _inspect(maxi(0, hovered - 1))
			KEY_RIGHT: _inspect(mini(history.size() - 1, hovered + 1))
			KEY_HOME: _inspect(0)
			KEY_END: _inspect(history.size() - 1)
			_: return
		accept_event()

func value_text(value: float) -> String:
	return value_formatter.call(value) if value_formatter.is_valid() else "%.2f" % value

func _inspect(quarter: int) -> void:
	if history.is_empty():
		return
	hovered = clampi(quarter, 0, history.size() - 1)
	tooltip_text = "Q%d | %s %s%% | %s %s%%" % [hovered, labels[0], value_text(history[hovered][keys[0]]), labels[1], value_text(history[hovered][keys[1]])]
	accessibility_description = inspection_context + " " + tooltip_text + ". Left and Right inspect quarters; Home and End jump to the first and latest."
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	var heading_extra := 0.0
	if compact_legend:
		var height := font.get_multiline_string_size(heading, HORIZONTAL_ALIGNMENT_LEFT, size.x, 13).y
		heading_extra = maxf(0.0, height - font.get_height(13))
		draw_multiline_string(font, Vector2(0, 18), heading, HORIZONTAL_ALIGNMENT_LEFT, size.x, 13, -1, Color("b5c9cc"))
	else:
		draw_string(font, Vector2(0, 18), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("b5c9cc"))
	if history.is_empty():
		return
	if has_focus():
		draw_rect(Rect2(Vector2.ZERO, size), Color("e9b76e"), false, 2)
	var inspection_extra := 0.0
	if hovered >= 0 and hovered < history.size():
		var reading := "Q%d · %s%% / %s%%" % [hovered, value_text(history[hovered][keys[0]]), value_text(history[hovered][keys[1]])]
		if compact_legend:
			var height := font.get_multiline_string_size(reading, HORIZONTAL_ALIGNMENT_LEFT, size.x, 12).y
			inspection_extra = maxf(0.0, height - font.get_height(12))
			draw_multiline_string(font, Vector2(0, 33 + heading_extra), reading, HORIZONTAL_ALIGNMENT_LEFT, size.x, 12, -1, Color("e9b76e"))
		else:
			draw_string(font, Vector2(42, 33), reading, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("e9b76e"))
	var one_line_legend := compact_legend and size.x >= 460.0
	var plot := Rect2(42, 38 + heading_extra + inspection_extra, size.x - 58, maxf(1.0, size.y - (91 if one_line_legend else 108) - heading_extra - inspection_extra))
	var low := INF
	var high := -INF
	for state in history:
		for key in keys:
			low = minf(low, float(state[key]))
			high = maxf(high, float(state[key]))
	low = 0.0 if zero_floor else floor(low - 0.3)
	high = maxf(1.0, ceil(high + 0.3)) if zero_floor else ceil(high + 0.3)
	for i in range(4):
		var y := plot.position.y + plot.size.y * i / 3.0
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color("2a4048"), 1)
		draw_string(font, Vector2(0, y + 4), "%.1f" % lerpf(high, low, i / 3.0), HORIZONTAL_ALIGNMENT_LEFT, 38, 11, Color("9bb3b9"))
	for series in range(keys.size()):
		var points := PackedVector2Array()
		for q in range(history.size()):
			points.append(Vector2(plot.position.x + plot.size.x * q / maxf(1, history.size() - 1), plot.end.y - (float(history[q][keys[series]]) - low) / (high - low) * plot.size.y))
		if points.size() > 1:
			draw_polyline(points, colors[series], 2.3, true)
		draw_circle(points[-1], 3.2, colors[series])
		var y := size.y - 10 if one_line_legend else size.y - 22 + series * 17
		var x := size.x * series / 2.0 if one_line_legend else 0.0
		draw_line(Vector2(x, y - 4), Vector2(x + 14, y - 4), colors[series], 3)
		var legend_label: String = labels[series]
		if compact_legend and size.x < 260.0:
			legend_label = legend_label.trim_suffix(" policy").trim_suffix(" reference")
		draw_string(font, Vector2(x + 22, y), "%s  %s%%" % [legend_label, value_text(history[-1][keys[series]])], HORIZONTAL_ALIGNMENT_LEFT, size.x / 2.0 - 22 if one_line_legend else -1, 12, colors[series])
	for q in tick_quarters(history.size()):
		draw_string(font, Vector2(plot.position.x + plot.size.x * q / maxf(1, history.size() - 1) - 8, plot.end.y + 18), "Q%d" % q, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("9bb3b9"))
	if hovered >= 0 and hovered < history.size():
		var x := plot.position.x + plot.size.x * hovered / maxf(1, history.size() - 1)
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color("dce7df"), 1)
