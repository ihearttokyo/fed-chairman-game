extends VBoxContainer
## Realized Q8 checkpoint versus the later realized interval. No forecasts/score.
const Amount = preload("res://play/bank_workout_panel.gd")
const Exact = preload("res://play/bank_outlook.gd")
var snapshot: Dictionary = {}
var heading := Label.new()
var context := Label.new()
var prices := Label.new()
var jobs := Label.new()
var bank := Label.new()
var price_bars := PeriodBars.new()
var job_bars := PeriodBars.new()

class PeriodBars:
	extends Control
	var early := 0.0
	var late: Variant = null
	func _init() -> void:
		custom_minimum_size = Vector2(0, 18)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		var radius: float = maxf(early, late if late != null else 0.0)
		for index in range(2):
			var y := float(index * 9)
			draw_rect(Rect2(0, y, size.x, 5), Color("243c44"))
			var value: Variant = early if index == 0 else late
			if value != null and radius > 0:
				var width: float = value / radius * size.x
				# Subpixel nonzero bars are omitted, never inflated to a fake value.
				if width >= 1:
					draw_rect(Rect2(0, y, width, 5), Color("e9b76e") if index == 0 else Color("91c9e8"))

static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT and value >= -9007199254740992 and value <= 9007199254740992) or (typeof(value) == TYPE_FLOAT and is_finite(value))

static func present(history: Array, banks: Array, credit: Array, quarter: int, target: float, active: bool = true) -> Dictionary:
	var unavailable := {"visible": active and quarter >= 8, "ok": false}
	if not unavailable.visible or quarter > 20 or not is_finite(target) or history.size() != quarter + 1 or banks.size() != quarter + 1 or credit.size() != quarter:
		return unavailable
	var early := [0.0, 0.0]
	var late := [0.0, 0.0]
	for index in range(quarter + 1):
		if not history[index] is Dictionary or typeof(history[index].get("quarter_index")) != TYPE_INT or history[index].quarter_index != index or not banks[index] is Dictionary or typeof(banks[index].get("quarter_index")) != TYPE_INT or banks[index].quarter_index != index:
			return unavailable
		if index == 0: continue
		var state: Dictionary = history[index]
		for key in ["four_quarter_inflation_pct", "unemployment_rate_pct", "structural_unemployment_pct"]:
			if not _number(state.get(key)): return unavailable
		if not credit[index - 1] is Dictionary or not _number(credit[index - 1].get("bank_equity_after")):
			return unavailable
		for key in ["central_bank_loan", "withdrawal_queue"]:
			if not _number(banks[index].get(key)) or banks[index][key] < 0: return unavailable
		var totals: Array = early if index <= 8 else late
		totals[0] += absf(state.four_quarter_inflation_pct - target)
		totals[1] += maxf(0, state.unemployment_rate_pct - state.structural_unemployment_pct)
		if not is_finite(totals[0]) or not is_finite(totals[1]): return unavailable
	return {"visible": true, "ok": true, "quarter": quarter, "early_prices": early[0] / 8, "early_jobs": early[1] / 8,
		"late_prices": late[0] / (quarter - 8) if quarter > 8 else null, "late_jobs": late[1] / (quarter - 8) if quarter > 8 else null,
		"capital8": credit[7].bank_equity_after, "capital_now": credit[quarter - 1].bank_equity_after,
		"debt8": banks[8].central_bank_loan, "debt_now": banks[quarter].central_bank_loan,
		"queue8": banks[8].withdrawal_queue, "queue_now": banks[quarter].withdrawal_queue}

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 3)
	for label in [heading, context, prices, jobs, bank]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 13 if label == heading else 12)
		add_child(label)
	add_child(price_bars)
	move_child(price_bars, 3)
	add_child(job_bars)
	move_child(job_bars, 5)
	preload("res://play/wrapped_tooltip.gd").install(self)
	update_actual([], [], [], 0, 2.0, false)

func _label(label: Label, text: String, hint: String = "") -> void:
	label.text = text
	label.accessibility_name = text
	label.accessibility_description = hint
	label.tooltip_text = hint

func update_actual(history: Array, banks: Array, credit: Array, quarter: int, target: float, active: bool = true) -> void:
	snapshot = present(history, banks, credit, quarter, target, active)
	visible = snapshot.visible
	for label in [heading, context, prices, jobs, bank]: _label(label, "")
	for plot in [price_bars, job_bars]:
		plot.hide()
		plot.early = 0
		plot.late = null
		plot.queue_redraw()
	if not visible: return
	_label(heading, "Runoff actuals · Q8 checkpoint" if quarter == 8 else "Runoff actuals · Q%d%s" % [quarter, " complete" if quarter == 20 else ""])
	if not snapshot.ok:
		_label(context, "Checkpoint unavailable")
		return
	_label(context, "Final security maturity Q20 · %d meetings left" % (20 - quarter) if quarter < 20 else "Final maturity reached; retained claims are not forgiven.")
	var late_period := "Q9–%d" % quarter if quarter > 8 else "Q9–20 not yet realized"
	var hint := "Actual unweighted per-meeting averages, not a score or causal policy estimate. Gold Q1–8; blue " + late_period + ". Each row has its own shared scale; subpixel bars are omitted."
	_label(prices, "Inflation distance (pp) · Q1–8 %s · %s%s" % [Amount._amount(snapshot.early_prices), late_period, " " + Amount._amount(snapshot.late_prices) if snapshot.late_prices != null else ""], hint + " Absolute distance from the inflation objective. Unrounded Q1–8 " + Exact.unrounded_amount(snapshot.early_prices) + "; later " + (Exact.unrounded_amount(snapshot.late_prices) if snapshot.late_prices != null else "not realized"))
	_label(jobs, "Jobs shortfall (pp) · Q1–8 %s · %s%s" % [Amount._amount(snapshot.early_jobs), late_period, " " + Amount._amount(snapshot.late_jobs) if snapshot.late_jobs != null else ""], hint + " Positive unemployment minus each meeting's structural reference. Unrounded Q1–8 " + Exact.unrounded_amount(snapshot.early_jobs) + "; later " + (Exact.unrounded_amount(snapshot.late_jobs) if snapshot.late_jobs != null else "not realized"))
	for row in [[price_bars, snapshot.early_prices, snapshot.late_prices], [job_bars, snapshot.early_jobs, snapshot.late_jobs]]:
		row[0].early = row[1]
		row[0].late = row[2]
		row[0].show()
		row[0].queue_redraw()
	var bank_text := "Bank Q8 · capital %s · principal %s · queued %s" % [Exact.signed_amount(snapshot.capital8), Amount._amount(snapshot.debt8), Amount._amount(snapshot.queue8)]
	if quarter > 8:
		bank_text += "\nBank Q%d · capital %s · principal %s · queued %s" % [quarter, Exact.signed_amount(snapshot.capital_now), Amount._amount(snapshot.debt_now), Amount._amount(snapshot.queue_now)]
	_label(bank, bank_text + "\nBank amounts: % initial GDP", "Actual interest-inclusive equity; principal and queued withdrawals are ending snapshots, not sums across meetings. No legal-resolution or solvency grade. Unrounded Q8/current capital: %s / %s." % [Exact.unrounded_amount(snapshot.capital8), Exact.unrounded_amount(snapshot.capital_now)])
