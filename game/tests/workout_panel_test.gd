extends SceneTree
## Synthetic presentation/layout fixtures; no forecast, bank step or save access.
const WorkoutPanel = preload("res://play/bank_workout_panel.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for frame in range(6):
		await process_frame

func fixture() -> Dictionary:
	return {"quarter_index": 37, "cash": 1.25, "securities_value": 9.0, "deposits": 8.0, "central_bank_loan": 3.0, "withdrawal_queue": 0.75, "loan_arrears": 0.2, "equity": -0.75, "payment_due": 1.0, "payments_made": 0.8}

func run() -> void:
	var source := fixture()
	var frozen := var_to_bytes(source)
	var shown := WorkoutPanel.present(source)
	check(shown.ok and shown.title.contains("Q37"), "absolute simulation quarter is displayed")
	check(shown.cash_text == "1.25" and shown.securities_text == "9.00" and shown.deposits_text == "8.00" and shown.loan_text == "3.00", "asset and liability legs remain separate, without adding subset balances")
	check(shown.queue_text == "0.75" and shown.arrears_text == "0.20", "queued withdrawals and overdue central-bank principal remain distinct")
	check(shown.equity_text == "-0.75" and shown.equity_status == "Negative equity", "negative capital is visible independently of payment progress")
	check(shown.payment_text == "Depositor payments made 0.80 / due 1.00" and shown.payment_status == "Depositor payments short" and is_equal_approx(shown.payment_fraction, 0.8), "payment amounts and graphical ratio use actual due/made")
	var no_due := source.duplicate(true)
	no_due.payment_due = 0
	no_due.payments_made = 0
	shown = WorkoutPanel.present(no_due)
	check(not shown.payment_applicable and shown.payment_fraction == 0 and shown.payment_status == "No depositor payments due" and shown.payment_text.contains("n.a."), "no payments due is n.a., never fabricated full coverage")
	var paid := source.duplicate(true)
	paid.payments_made = 1.0
	shown = WorkoutPanel.present(paid)
	check(shown.equity_status == "Negative equity" and shown.payment_status == "Depositor payments met", "met payments never become a solvency guarantee")
	var extreme := source.duplicate(true)
	extreme.payment_due = 1e-300
	extreme.payments_made = 1e300
	shown = WorkoutPanel.present(extreme)
	check(shown.ok and shown.payment_fraction == null and not shown.payment_fraction_representable and shown.payment_meter_fraction == 1.0 and shown.payment_text.contains(String.num_scientific(1e300)), "finite extreme amounts remain readable and meter division never overflows")
	var overpaid := source.duplicate(true)
	overpaid.payments_made = 2.0
	shown = WorkoutPanel.present(overpaid)
	check(shown.payment_fraction == 2.0 and shown.payment_meter_fraction == 1.0 and shown.payment_text.contains("made 2.00 / due 1.00"), "source fraction and amounts stay uncapped while only meter fraction is bounded")
	var near_full := source.duplicate(true)
	near_full.payments_made = 0.9999
	shown = WorkoutPanel.present(near_full)
	check(shown.payment_text == "Depositor payments made <1.00 / due 1.00" and shown.payment_short and shown.payment_status == "Depositor payments short", "near-full payment cannot round into apparent equality")
	var rounded_down := source.duplicate(true)
	rounded_down.payments_made = 1.003
	rounded_down.payment_due = 1.004
	shown = WorkoutPanel.present(rounded_down)
	check(shown.payment_text.contains("made <due (~1.00) / due 1.00") and shown.payment_short, "rounded-down near-equality never claims the actual payment is below a lower rounded number")
	var bounded_tiny := source.duplicate(true)
	bounded_tiny.payment_due = 2e-9
	bounded_tiny.payments_made = 1e-9
	shown = WorkoutPanel.present(bounded_tiny)
	check(shown.payment_text == "Depositor payments made <0.0001 / due <0.0001" and shown.payment_short and not shown.payment_text.contains("<<"), "already-bounded tiny payments retain one bound and explicit short status")
	paid.equity = 0.0
	check(WorkoutPanel.present(paid).equity_status == "Zero equity", "zero capital is not called positive or solvent")
	for pair in [[1e-9, "<0.0001"], [0.004, "0.0040"], [0.0, "0.00"]]:
		var tiny := source.duplicate(true)
		for field in ["cash", "securities_value", "deposits", "central_bank_loan", "withdrawal_queue", "loan_arrears", "payment_due", "payments_made"]:
			tiny[field] = pair[0]
		tiny.equity = -pair[0]
		shown = WorkoutPanel.present(tiny)
		check(shown.cash_text == pair[1] and shown.queue_text == pair[1] and shown.arrears_text == pair[1], "tiny positive amounts use existing funding precision: " + str(pair[0]))
		check(shown.equity_text == ("-" if pair[0] > 0 else "") + pair[1], "tiny negative equity preserves its sign")
	for field in source:
		var missing := source.duplicate(true)
		missing.erase(field)
		check(not WorkoutPanel.present(missing).ok, "missing " + field + " is unavailable, not an invented zero")
		for invalid in [NAN, INF, -INF, "1", true]:
			var bad := source.duplicate(true)
			bad[field] = invalid
			check(not WorkoutPanel.present(bad).ok, "invalid " + field + " rejects nonnumeric/nonfinite data")
		if field != "equity":
			var negative := source.duplicate(true)
			negative[field] = -0.001
			check(not WorkoutPanel.present(negative).ok, "negative " + field + " is invalid")
	for mismatch in [{"withdrawal_queue": 8.1}, {"loan_arrears": 3.1}, {"quarter_index": 1.5}]:
		var bad := source.duplicate(true)
		bad.merge(mismatch, true)
		check(not WorkoutPanel.present(bad).ok, "subset or whole-quarter contract is validated")
	root.size = Vector2i(600, 720)
	root.content_scale_size = Vector2i.ZERO
	var host := VBoxContainer.new()
	host.size = Vector2(root.size)
	root.add_child(host)
	var panel := WorkoutPanel.new()
	host.add_child(panel)
	check(panel.heading.text == "Bank data unavailable" and panel.details_button.disabled, "cold panel states unavailable explicitly")
	panel.update_snapshot(source)
	await settle()
	check(panel.units_label.text == "Amounts: % initial GDP" and panel.payment_meter.visible, "one fixed units line and payment graphic are visible")
	check(panel.payment_meter.step == 0.0, "actual native Range meter uses continuous fractions, not integer snapping")
	for amount in [1.0 / 3.0, 0.9999, 1e-9]:
		var fractional := source.duplicate(true)
		fractional.payments_made = amount
		panel.update_snapshot(fractional)
		await process_frame
		check(absf(panel.payment_meter.value - amount) <= maxf(1e-15, amount * 1e-12) and panel.payment_meter.value > 0 and panel.payment_meter.value < 1, "instantiated native meter retains exact positive short fraction: " + str(amount))
		check(panel.payment_label.text.contains("Depositor payments short") and panel.payment_meter.accessibility_name == panel.payment_label.text, "actual fraction retains visible and assistive short status")
		if amount == 0.9999:
			check(panel.payment_label.text.contains("made <1.00 / due 1.00"), "actual near-full readout preserves boundary instead of rounded equality")
	panel.update_snapshot(overpaid)
	check(panel.snapshot.payment_fraction == 2.0 and panel.payment_meter.value == 1.0, "actual meter caps the graphic without capping source ratio")
	panel.update_snapshot(extreme)
	check(panel.payment_meter.value == 1.0 and is_finite(panel.payment_meter.value), "actual meter remains finite for overflow-scale source ratio")
	panel.update_snapshot(source)
	check(panel.queue_label.text.contains("included in deposits") and panel.arrears_label.text.contains("included in CB loan"), "visible subset labels prevent double counting")
	check(panel.securities_label.tooltip_text.contains("Market value") and panel.securities_label.tooltip_text.contains("dated"), "securities clearly show market value of dated claims")
	check(panel.equity_label.text.contains("Mark-to-market equity") and panel.equity_label.tooltip_text.contains("not regulatory capital"), "equity is mark-to-market, never mislabeled regulatory capital")
	check(panel.payment_label.text.begins_with("Depositor payments") and panel.payment_label.tooltip_text.contains("prior queue plus new requests") and panel.payment_label.tooltip_text.contains("not central-bank refinancing"), "payment readout separates depositor withdrawals from CB renewal principal")
	check(panel.equity_label.text.contains("Negative equity") and panel.payment_label.text.contains("Depositor payments short"), "capital and payment distress have independent visible words, not color alone")
	for control in [panel.cash_label, panel.securities_label, panel.deposits_label, panel.loan_label, panel.queue_label, panel.arrears_label, panel.equity_label, panel.payment_label]:
		check(not control.accessibility_name.is_empty() and not control.tooltip_text.is_empty() and control.accessibility_description == control.tooltip_text, "native amount has readable text and assistive explanation")
		check(control.get_theme_font_size("font_size") >= 12 and control.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "amounts preserve readable native fonts and wrap")
	check(panel.details_button.focus_mode == Control.FOCUS_ALL and not panel.details_button.accessibility_name.is_empty(), "Details is a named native keyboard control")
	var received := [0]
	panel.details_requested.connect(func(): received[0] += 1)
	panel.details_button.pressed.emit()
	check(received[0] == 1, "Details emits the integration signal")
	panel.details_button.grab_focus()
	var identity := panel.details_button.get_instance_id()
	panel.update_snapshot(paid)
	await settle()
	check(panel.details_button.has_focus() and panel.details_button.get_instance_id() == identity, "valid refresh preserves focused Details control")
	for width in [280, 600]:
		root.size = Vector2i(width, 720)
		host.size.x = width
		await settle()
		check(panel.size.x <= width and panel.get_global_rect().encloses(panel.details_button.get_global_rect()), "native header fits width " + str(width))
		for control in [panel.assets_column, panel.liabilities_column, panel.queue_label, panel.arrears_label, panel.equity_label, panel.payment_label, panel.payment_meter]:
			check(panel.get_global_rect().grow(1).encloses(control.get_global_rect()) and root.get_visible_rect().grow(1).encloses(control.get_global_rect()), "native balance/payment content fits width " + str(width))
		check(panel.assets_column.global_position.y < panel.liabilities_column.global_position.y if width == 280 else panel.assets_column.global_position.y == panel.liabilities_column.global_position.y, "balance columns wrap only when needed")
	panel.update_snapshot(no_due)
	check(not panel.payment_meter.visible and panel.payment_label.text.contains("n.a.") and panel.payment_meter.value == 0, "no-due refresh removes misleading payment meter")
	panel.update_snapshot({})
	panel.details_button.pressed.emit()
	check(panel.heading.text == "Bank data unavailable" and not panel.body.visible and panel.details_button.disabled and received[0] == 1, "unavailable refresh disables stale disclosure and hides stale data")
	check(panel.cash_label.text.is_empty() and panel.cash_label.accessibility_name.is_empty() and panel.cash_label.tooltip_text.is_empty() and panel.payment_meter.value == 0, "unavailable data clears stale visual and assistive amounts")
	check(var_to_bytes(source) == frozen, "presenting, refreshing, disclosing and resizing leave authoritative input unchanged")
	host.free()
	print("%s: bank workout presentation %d checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
