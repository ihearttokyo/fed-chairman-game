extends SceneTree
## Pure presentation fixtures plus eight native bank steps; no GUI/save/forecast.
const Debrief = preload("res://play/workout_debrief.gd")
const Economy = preload("res://model/economy.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures <= 15:
			printerr("FAIL: " + message)

func fixture(no_due: bool = false) -> Dictionary:
	var history: Array = []
	var settlements: Array = []
	for quarter in range(9):
		history.append({"quarter_index": quarter, "cash": 0.0, "deposits": 1.0,
			"withdrawal_queue": 0.0 if no_due or quarter == 0 else 1.0,
			"central_bank_loan": 0.5, "loan_arrears": 0.0 if quarter == 0 else 0.25,
			"annual_yield_pct": 0.0, "claims": [], "initial_face": 0.0, "matured_face": 0.0})
		if quarter > 0:
			settlements.append({"ok": true, "state": history[quarter].duplicate(true),
				"deposit_due": 0.0 if no_due else 1.0, "withdrawals_paid": 0.0,
				"remaining_queue": history[quarter].withdrawal_queue, "loan_arrears": 0.25,
				"equity_before": -1.5, "equity_after": -1.5})
	return {"history": history, "settlements": settlements}

func sync_history(source: Dictionary, quarter: int) -> void:
	if quarter > 0:
		source.settlements[quarter - 1].state = source.history[quarter].duplicate(true)

func reject(source: Dictionary, message: String) -> void:
	var result := Debrief.present(source.history, source.settlements, true)
	check(not result.ok and not result.visible, message)

func _initialize() -> void:
	var source := fixture()
	var frozen := var_to_bytes(source)
	var shown := Debrief.present(source.history, source.settlements, true)
	check(shown.ok and shown.visible and shown.quarters.size() == 8, "Exactly eight completed payment bars")
	check(shown.ending_queue == 1 and shown.ending_arrears == 0.25, "Ending queue is one retained claim, not eight repeated claims")
	check(shown.ending_equity == -1.5 and shown.equity_text.contains("-1.50"), "Signed mark-to-market equity remains separate from payments")
	check(not shown.has("score") and not shown.has("grade") and not shown.has("coverage") and not shown.has("total_due"), "No invented grade or aggregate ratio of repeated claims")
	for row in shown.quarters:
		check(row.applicable and row.short and row.fraction == 0 and row.description.length() <= 80, "Unpaid quarter has a distinct shortfall and concise reading")
	var no_due := fixture(true)
	shown = Debrief.present(no_due.history, no_due.settlements, true)
	for row in shown.quarters:
		check(not row.applicable and not row.short and row.fraction == 0 and row.description.contains("n.a."), "No payments due is n.a., never perfect coverage")
	var partial := fixture()
	partial.settlements[7].withdrawals_paid = 0.75
	partial.settlements[7].remaining_queue = 0.25
	partial.history[8].withdrawal_queue = 0.25
	partial.history[8].deposits = 0.25
	sync_history(partial, 8)
	shown = Debrief.present(partial.history, partial.settlements, true)
	check(shown.ok and shown.quarters[7].fraction == 0.75 and shown.quarters[7].short, "Partial final payment preserves the raw meeting ratio")
	check(shown.ending_queue == 0.25 and shown.queue_text.contains("0.25"), "Only the retained ending queue is reported")
	for pair in [[1.0, 0.9999999999999], [2e-9, 1e-9], [1e-300, 0.0]]:
		var tiny := fixture()
		tiny.settlements[7].deposit_due = pair[0]
		tiny.settlements[7].withdrawals_paid = pair[1]
		tiny.settlements[7].remaining_queue = pair[0] - pair[1]
		tiny.history[8].withdrawal_queue = pair[0] - pair[1]
		tiny.settlements[7].equity_after = -1e-9
		sync_history(tiny, 8)
		shown = Debrief.present(tiny.history, tiny.settlements, true)
		check(shown.ok and shown.quarters[7].short and shown.quarters[7].description.contains("short <0.0001"), "Tiny shortfall never becomes met after display rounding")
		check(shown.queue_text.contains("<0.0001") and shown.equity_text.contains("-<0.0001"), "Tiny positive retained claims and negative equity never display false zero")
	var met := fixture()
	met.settlements[7].withdrawals_paid = 1.0
	met.settlements[7].remaining_queue = 0.0
	met.history[8].withdrawal_queue = 0.0
	sync_history(met, 8)
	shown = Debrief.present(met.history, met.settlements, true)
	check(shown.ok and not shown.quarters[7].short and shown.quarters[7].fraction == 1 and shown.ending_equity < 0, "Met payments are not converted into a solvency win")
	check(not Debrief.present(source.history, source.settlements, false).ok, "Incomplete episode is never shown")
	check(not Debrief.present(source.history.slice(0, 8), source.settlements, true).ok, "Partial history refuses")
	check(not Debrief.present(source.history, source.settlements.slice(0, 7), true).ok, "Partial settlements refuse")
	check(not Debrief.present(source.history + [source.history[8]], source.settlements, true).ok, "Extra history cannot masquerade as an eight-meeting episode")
	for field in Debrief.SETTLEMENT_AMOUNTS:
		var missing := fixture()
		missing.settlements[3].erase(field)
		reject(missing, "Missing settlement " + field + " refuses")
		for invalid in [NAN, INF, -INF, true, "1", null]:
			var bad := fixture()
			bad.settlements[3][field] = invalid
			reject(bad, "Invalid settlement " + field + " refuses")
	for field in Debrief.BANK_AMOUNTS:
		for invalid in [NAN, INF, -1.0, true, "1", 9007199254740993]:
			var bad := fixture()
			bad.history[5][field] = invalid
			sync_history(bad, 5)
			reject(bad, "Invalid bank history " + field + " refuses")
	for mutation in ["quarter", "state", "ok", "overpaid", "queue", "arrears", "claim", "yield", "row"]:
		var bad := fixture()
		match mutation:
			"quarter": bad.history[4].quarter_index = 5
			"state": bad.settlements[3].state = {}
			"ok": bad.settlements[3].ok = 1
			"overpaid": bad.settlements[3].withdrawals_paid = 2.0
			"queue": bad.settlements[3].remaining_queue = 0.5
			"arrears": bad.history[4].loan_arrears = 1.0; sync_history(bad, 4)
			"claim": bad.history[4].claims = [{"maturity_quarter": 4, "face": 1.0}]; sync_history(bad, 4)
			"yield": bad.history[4].annual_yield_pct = NAN; sync_history(bad, 4)
			"row": bad.settlements[3] = []
		reject(bad, "Disconnected or malformed " + mutation + " refuses")
	check(var_to_bytes(source) == frozen, "Presentation never mutates the caller histories or settlements")
	var detached := Debrief.present(source.history, source.settlements, true)
	detached.quarters[0].due = 999
	check(var_to_bytes(source) == frozen, "Presentation rows do not retain mutable source containers")
	_test_native_episode()
	_test_component(source)
	if failures == 0:
		print("PASS: workout debrief ", checks, " checks, 0 failures")
	quit(0 if failures == 0 else 1)

func _test_native_episode() -> void:
	var model := Economy.new()
	var loaded: Dictionary = model.load_parameters()
	check(loaded.ok, "Native parameters load for source-shaped fixture")
	if not loaded.ok:
		return
	var opening: Dictionary = Economy.bank_workout_opening(loaded.values)
	check(opening.ok, "Native authored opening is available")
	if not opening.ok:
		return
	var history: Array = [opening.bank.duplicate(true)]
	var settlements: Array = []
	for index in range(8):
		var bank: Dictionary = history[-1]
		var request: float = opening.requests[index]
		if index == opening.remaining_request_index:
			var remaining: Dictionary = Economy.bank_workout_remaining_request(bank)
			check(remaining.ok, "Native final request is the actual remaining amount")
			if not remaining.ok:
				return
			request = remaining.request
		var result: Dictionary = Economy.bank_workout_step(bank, {"annual_yield_pct": 4.0, "new_withdrawals": request,
			"liquidity_offer": 0.0, "haircut_pct": opening.haircut_pct, "pledgeable_share": opening.pledgeable_share})
		check(result.ok, "Native bank progresses through each valid distress meeting")
		if not result.ok:
			return
		history.append(result.state.duplicate(true))
		settlements.append(result.duplicate(true))
	var frozen := var_to_bytes([history, settlements])
	var shown := Debrief.present(history, settlements, true)
	check(shown.ok and shown.quarters.size() == 8, "Actual eight-step native settlement schema is accepted")
	if shown.ok:
		check(shown.ending_queue == history[8].withdrawal_queue and shown.ending_arrears == history[8].loan_arrears and shown.ending_equity == settlements[7].equity_after, "Ending readouts use actual retained claims and the native equity mark")
		for index in range(8):
			var row: Dictionary = shown.quarters[index]
			var actual: Dictionary = settlements[index]
			check(row.quarter == index + 1 and row.due == actual.deposit_due and row.paid == actual.withdrawals_paid, "Every plotted quarter retains its own native payment amounts and order")
			check(row.short == (actual.withdrawals_paid < actual.deposit_due) and row.applicable == (actual.deposit_due > 0), "Each native quarter determines its own shortfall and applicability")
			check(row.fraction == (actual.withdrawals_paid / actual.deposit_due if actual.deposit_due > 0 else 0.0), "Each native bar uses that quarter's ratio, not a stale neighboring value")
	check(var_to_bytes([history, settlements]) == frozen, "Actual native fixture remains byte-identical")

func _test_component(source: Dictionary) -> void:
	var component := Debrief.new()
	check(not component.visible and component.snapshot.ok == false, "Component starts empty and hidden")
	component.update_episode(source.history, source.settlements, true)
	check(component.visible and component.timeline.quarters.size() == 8, "Completed source populates the eight-bar timeline")
	check(component.has_method("_make_custom_tooltip") and component.timeline.has_method("_make_custom_tooltip"), "Both scripted roots preserve the wrapped tooltip hook")
	check(component.focus_mode == Control.FOCUS_NONE and component.timeline.focus_mode == Control.FOCUS_NONE, "Read-only debrief adds no keyboard tab stops")
	check(component.custom_minimum_size.x == 0 and component.timeline.custom_minimum_size.x == 0, "No fixed minimum width forces cockpit overflow")
	check(component.legend.text.begins_with("Paid / due per meeting") and not component.legend.text.contains("GDP") and component.note.text.contains("% initial GDP"), "Ratio chart and ending-balance units are distinct")
	check(component.timeline.accessibility_description.contains("Q1") and component.timeline.accessibility_description.contains("Q8"), "All eight numeric quarter readings are available accessibly")
	for label in [component.heading, component.legend, component.queue_label, component.arrears_label, component.equity_label, component.note]:
		check(label.focus_mode == Control.FOCUS_NONE and label.get_theme_font_size("font_size") >= 12 and label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and label.text.length() <= 80, "Primary readout is concise, wrapped, >=12px and not a tab stop")
	component.update_episode(source.history, source.settlements, false)
	check(not component.visible and component.timeline.quarters.is_empty() and component.timeline.tooltip_text == "" and component.timeline.accessibility_description == "", "Partial replacement clears stale graphics and accessible data")
	for label in [component.heading, component.legend, component.queue_label, component.arrears_label, component.equity_label, component.note]:
		check(label.text == "" and label.tooltip_text == "" and label.accessibility_description == "", "Partial replacement clears every stale readout")
	component.update_episode(source.history, source.settlements, true)
	component.update_episode([], [], true)
	check(not component.visible and component.snapshot.ok == false and component.accessibility_description == "", "Invalid completed data also clears a prior valid episode")
	component.free()
