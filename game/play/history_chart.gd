extends Control

var history: Array = []
var keys := ["four_quarter_inflation_pct", "expected_long_inflation_pct"]
var labels := ["Inflation · 4-quarter", "Long expectations"]
var colors := [Color("e9b76e"), Color("75d4c0")]
var heading := "PRICES & EXPECTATIONS"
var hovered := -1

func _make_custom_tooltip(for_text: String) -> Object:
	return preload("res://play/wrapped_tooltip.gd").create(self, for_text)

static func tick_quarters(count: int) -> Array:
	return [0] if count <= 1 else [0, 1] if count == 2 else [0, roundi((count - 1) / 2.0), count - 1]

func _ready() -> void:
	custom_minimum_size = Vector2(310, 190)
	focus_mode = Control.FOCUS_ALL
	focus_entered.connect(func(): _inspect(history.size() - 1))
	focus_exited.connect(func(): hovered = -1; queue_redraw())
	mouse_exited.connect(func():
		if not has_focus():
			hovered = -1
			queue_redraw())
	accessibility_name = heading
	accessibility_description = "Historical chart. Exact values are available in the Data and journal button."

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

func _inspect(quarter: int) -> void:
	if history.is_empty():
		return
	hovered = clampi(quarter, 0, history.size() - 1)
	tooltip_text = "Q%d | %s %.2f%% | %s %.2f%%" % [hovered, labels[0], history[hovered][keys[0]], labels[1], history[hovered][keys[1]]]
	accessibility_description = tooltip_text + ". Left and Right inspect quarters; Home and End jump to the first and latest."
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	draw_string(font, Vector2(0, 18), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("b5c9cc"))
	if history.is_empty():
		return
	if has_focus():
		draw_rect(Rect2(Vector2.ZERO, size), Color("e9b76e"), false, 2)
	if hovered >= 0 and hovered < history.size():
		draw_string(font, Vector2(42, 33), "Q%d · %.2f%% / %.2f%%" % [hovered, history[hovered][keys[0]], history[hovered][keys[1]]], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("e9b76e"))
	var plot := Rect2(42, 38, size.x - 58, size.y - 108)
	var low := INF
	var high := -INF
	for state in history:
		for key in keys:
			low = minf(low, float(state[key]))
			high = maxf(high, float(state[key]))
	low = floor(low - 0.3)
	high = ceil(high + 0.3)
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
		var y := size.y - 22 + series * 17
		draw_line(Vector2(0, y - 4), Vector2(14, y - 4), colors[series], 3)
		draw_string(font, Vector2(22, y), "%s  %.2f%%" % [labels[series], history[-1][keys[series]]], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, colors[series])
	for q in tick_quarters(history.size()):
		draw_string(font, Vector2(plot.position.x + plot.size.x * q / maxf(1, history.size() - 1) - 8, plot.end.y + 18), "Q%d" % q, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("9bb3b9"))
	if hovered >= 0 and hovered < history.size():
		var x := plot.position.x + plot.size.x * hovered / maxf(1, history.size() - 1)
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color("dce7df"), 1)
