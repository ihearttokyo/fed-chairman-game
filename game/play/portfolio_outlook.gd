extends VBoxContainer
## Read-only maturity timeline using Main's already-computed conditional forecast.
const INK := Color("e7eee9")
const MUTED := Color("a4babe")
const GOLD := Color("e9b76e")
const MINT := Color("75d4c0")
const LIMITS := "All amounts are % of initial annual GDP. Conditional: adopt the current staged decision, then hold its applied rate; later asset/loan offers are zero, portfolio switches persist, and no new future shocks are assumed. Known maturities are not future macro news."

var timeline: Timeline
var detail := Label.new()
var status := Label.new()
var _rows: Array[Dictionary] = []

class Timeline:
	extends Control
	signal selection_changed(index: int)
	var rows: Array[Dictionary] = []
	var selected := 0
	var peak := 0.0
	func _init() -> void:
		custom_minimum_size = Vector2(0, 156)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		focus_mode = Control.FOCUS_ALL
		accessibility_name = "Conditional principal maturity timeline"
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		focus_entered.connect(func(): inspect(selected))
		resized.connect(queue_redraw)
	func set_rows(points: Array[Dictionary]) -> void:
		rows = points.duplicate(true)
		peak = 0.0
		for row in rows:
			peak = maxf(peak, float(row.due))
		selected = clampi(selected, 0, maxi(0, rows.size() - 1))
		visible = not rows.is_empty()
		focus_mode = Control.FOCUS_ALL if visible else Control.FOCUS_NONE
		tooltip_text = ""
		accessibility_description = ""
		if visible:
			inspect(selected)
		queue_redraw()
	func inspect(index: int) -> void:
		if rows.is_empty():
			return
		selected = clampi(index, 0, rows.size() - 1)
		var row: Dictionary = rows[selected]
		var exact := "%s: principal due %s; runoff %s; reinvested %s. " % [
			row.quarter_label, amount(row.due), amount(row.runoff), amount(row.reinvested)]
		tooltip_text = exact + LIMITS + " Left/Right inspect quarters; Home/End select endpoints."
		accessibility_description = tooltip_text
		selection_changed.emit(selected)
		queue_redraw()
	func _gui_input(event: InputEvent) -> void:
		if rows.is_empty():
			return
		if event is InputEventMouseMotion or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			var margin := 22.0
			var span := maxf(1.0, size.x - margin * 2.0)
			inspect(roundi(clampf((event.position.x - margin) / span, 0.0, 1.0) * (rows.size() - 1)))
			if event is InputEventMouseButton:
				accept_event()
		if event is InputEventKey and event.pressed and not event.alt_pressed and not event.is_command_or_control_pressed():
			match event.keycode:
				KEY_LEFT: inspect(selected - 1)
				KEY_RIGHT: inspect(selected + 1)
				KEY_HOME: inspect(0)
				KEY_END: inspect(rows.size() - 1)
				_: return
			accept_event()
	static func amount(value: float) -> String:
		if value > 0.0 and value < 0.0001:
			return "<0.0001"
		return "%.4f" % value if value > 0.0 and value < 0.01 else "%.2f" % value
	func _draw() -> void:
		if rows.is_empty():
			return
		var font := get_theme_default_font()
		draw_string(font, Vector2(4, 14), "Principal due split · % of initial annual GDP", HORIZONTAL_ALIGNMENT_LEFT, maxf(1.0, size.x - 8.0), 12, INK)
		draw_rect(Rect2(Vector2(8, 24), Vector2(10, 10)), GOLD)
		draw_string(font, Vector2(22, 33), "Runoff", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MUTED)
		draw_rect(Rect2(Vector2(88, 24), Vector2(10, 10)), MINT)
		draw_string(font, Vector2(102, 33), "Reinvested", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MUTED)
		var baseline := size.y - 24.0
		var top := 44.0
		var available := maxf(8.0, baseline - top)
		draw_line(Vector2(18, baseline), Vector2(size.x - 18, baseline), Color("597078"), 1)
		var interval := maxf(1.0, (size.x - 40.0) / float(rows.size()))
		var bar_width := clampf(interval * 0.48, 6.0, 30.0)
		for index in range(rows.size()):
			var row: Dictionary = rows[index]
			var x := 20.0 + interval * (index + 0.5)
			var due: float = float(row.due)
			var total_height := available * due / (peak if peak > 0.0 else 1.0)
			var runoff_height := total_height * float(row.runoff) / due if due > 0.0 else 0.0
			var reinvested_height := total_height - runoff_height
			var bar := Rect2(x - bar_width * 0.5, baseline - total_height, bar_width, total_height)
			if runoff_height > 0.0:
				draw_rect(Rect2(bar.position.x, baseline - runoff_height, bar_width, runoff_height), GOLD)
			if reinvested_height > 0.0:
				draw_rect(Rect2(bar.position.x, baseline - total_height, bar_width, reinvested_height), MINT)
			if due == 0.0:
				draw_line(Vector2(x - bar_width * 0.5, baseline - 1.0), Vector2(x + bar_width * 0.5, baseline - 1.0), MUTED, 2)
			if index == selected:
				draw_rect(Rect2(x - interval * 0.46, top - 4.0, interval * 0.92, baseline - top + 8.0), GOLD, false, 1)
			var short_label := "Q+%d" % row.offset
			var label_width: float = font.get_string_size(short_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string(font, Vector2(x - label_width * 0.5, size.y - 3.0), short_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, INK if index == selected else MUTED)

static func _number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value))

static func _close(a: float, b: float) -> bool:
	return absf(a - b) <= 1e-10 * maxf(1.0, maxf(absf(a), absf(b)))

static func present(preview: Dictionary, quarter: int, horizon: int = 240) -> Dictionary:
	var unavailable := {"ok": false, "rows": [], "visible": false, "error": "No complete playable portfolio path is available."}
	if quarter < 0 or horizon < 1 or horizon > 240 or quarter >= horizon or typeof(preview.get("ok")) != TYPE_BOOL or not preview.ok:
		return unavailable
	var count := mini(8, horizon - quarter)
	if typeof(preview.get("states")) != TYPE_ARRAY or preview.states.size() < count:
		return unavailable
	var rows: Array[Dictionary] = []
	for index in range(count):
		var state: Variant = preview.states[index]
		if typeof(state) != TYPE_DICTIONARY or typeof(state.get("quarter_index")) != TYPE_INT or state.quarter_index != quarter + index + 1:
			return unavailable
		var required := [
			"treasury_redemption_pct_initial_gdp", "mbs_repayment_pct_initial_gdp", "bill_redemption_pct_initial_gdp",
			"principal_due_pct_initial_gdp", "principal_runoff_pct_initial_gdp", "principal_reinvestment_pct_initial_gdp",
			"long_securities_runoff_pct_initial_gdp", "reserve_maintenance_purchase_pct_initial_gdp",
			"reserves_pct_initial_gdp", "asset_stock_pct_initial_gdp", "reverse_repo_pct_initial_gdp", "term_premium_pct"]
		for key in required:
			if not _number(state.get(key)):
				return unavailable
		for key in required.slice(0, 11):
			if float(state[key]) < 0.0:
				return unavailable
		var treasury := float(state.treasury_redemption_pct_initial_gdp)
		var mbs := float(state.mbs_repayment_pct_initial_gdp)
		var bills := float(state.bill_redemption_pct_initial_gdp)
		var due := float(state.principal_due_pct_initial_gdp)
		var runoff := float(state.principal_runoff_pct_initial_gdp)
		var reinvested := float(state.principal_reinvestment_pct_initial_gdp)
		if not _close(treasury + mbs + bills, due) or runoff > due and not _close(runoff, due) or not _close(runoff + reinvested, due):
			return unavailable
		var row := {
			"quarter_index": state.quarter_index,
			"offset": index + 1,
			"quarter_label": "Q%d" % state.quarter_index,
			"treasury_due": treasury,
			"mbs_due": mbs,
			"bill_due": bills,
			"due": due,
			"runoff": runoff,
			"reinvested": reinvested,
			"long_runoff": float(state.long_securities_runoff_pct_initial_gdp),
			"reserve_maintenance": float(state.reserve_maintenance_purchase_pct_initial_gdp),
			"reserves": float(state.reserves_pct_initial_gdp),
			"securities": float(state.asset_stock_pct_initial_gdp),
			"reverse_repo": float(state.reverse_repo_pct_initial_gdp),
			"term_premium": float(state.term_premium_pct),
		}
		rows.append(row)
	return {"ok": true, "visible": true, "rows": rows, "first_quarter": rows[0].quarter_index,
		"last_quarter": rows[-1].quarter_index, "basis": "Percent of initial annual GDP.", "limits": LIMITS}

func build(snapshot: Dictionary) -> void:
	add_theme_constant_override("separation", 8)
	timeline = Timeline.new()
	add_child(timeline)
	var split_legend := Label.new()
	split_legend.text = "Each bar is principal due; its split is runoff vs reinvestment. Reserve-maintenance bills are shown separately below."
	split_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	split_legend.add_theme_color_override("font_color", MUTED)
	split_legend.accessibility_name = split_legend.text
	add_child(split_legend)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 13)
	detail.add_theme_color_override("font_color", INK)
	detail.accessibility_live = AccessibilityServer.LIVE_POLITE
	add_child(detail)
	status.text = LIMITS if snapshot.get("ok", false) else "Maturity outlook unavailable; no stale or partial values are shown."
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override("font_color", MUTED)
	status.accessibility_name = status.text
	add_child(status)
	if not snapshot.get("ok", false):
		timeline.set_rows([])
		detail.text = "No playable conditional path is available."
		detail.accessibility_name = detail.text
		return
	_rows = snapshot.rows.duplicate(true)
	timeline.selection_changed.connect(_show_row)
	timeline.set_rows(_rows)
	_show_row(timeline.selected)

func _show_row(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	var row: Dictionary = _rows[index]
	var formatter: Callable = Timeline.amount
	detail.text = "%s · principal due %s\nTreasuries %s · MBS %s · bills %s\nReinvested %s · runoff %s (long securities %s)\nReserve-maintenance bill purchases %s · reserves %s · securities incl. bills %s · reverse repos %s\nTerm premium %+.3f pp" % [
		row.quarter_label, formatter.call(row.due), formatter.call(row.treasury_due), formatter.call(row.mbs_due), formatter.call(row.bill_due),
		formatter.call(row.reinvested), formatter.call(row.runoff), formatter.call(row.long_runoff), formatter.call(row.reserve_maintenance),
		formatter.call(row.reserves), formatter.call(row.securities), formatter.call(row.reverse_repo), row.term_premium]
	detail.accessibility_name = "%s portfolio maturity detail" % row.quarter_label
	detail.accessibility_description = detail.text
