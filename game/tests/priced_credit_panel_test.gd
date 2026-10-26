extends SceneTree
## Independent synthetic presenter/schema fixtures. No model/forecast/save calls.
const CreditPanel = preload("res://play/priced_credit_panel.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures <= 15:
			printerr("FAIL: " + message)

func actual() -> Dictionary:
	return {"ok": true, "has_settlement": true, "quarter_index": 1, "payable": 0.2, "receivable": 0.1,
		"annual_rate_pct": 2.0, "days": 90, "accrued_positive": 0.3, "accrued_negative": 0.0,
		"paid_positive": 0.1, "paid_negative": 0.2, "new_cash_for_interest": 0.05, "new_cash_for_withdrawals": 0.4,
		"held_annual_rate_pct": 2.0, "next_days": 91}

func preview() -> Dictionary:
	return {"ok": true,
		"credit_contexts": [{"annual_rate_pct": -1.0, "days": 91}, {"annual_rate_pct": NAN}],
		"credit_results": [{"accrued_positive": 0.0, "accrued_negative": 0.01, "paid_positive": 0.2, "paid_negative": 0.11,
			"new_cash_for_interest": 0.1, "new_cash_for_withdrawals": 0.4}, {"paid_positive": INF}],
		"credit_states": [{"payable": 0.05, "receivable": 0.03}, {"payable": NAN}],
		"states": [{"quarter_index": 2}, {}], "diagnostic_beyond_episode": true}

func opening() -> Dictionary:
	var source := actual()
	source.has_settlement = false
	source.quarter_index = 0
	source.payable = 0.0
	source.receivable = 0.0
	for key in CreditPanel.FLOW_FIELDS + ["annual_rate_pct", "days"]:
		source[key] = null
	return source

func _initialize() -> void:
	var a := actual()
	var p := preview()
	var frozen := var_to_bytes([a, p])
	var shown := CreditPanel.present(a, p)
	check(shown.ok and shown.visible and shown.actual.ok and shown.staged.ok, "Independent actual and staged inputs are accepted")
	check(shown.staged.basis == "Staged Q2 · -1.00% APR · 91d/365" and shown.actual.basis == "Last actual Q1 · 2.00% APR · 90d/365", "Staged APR/day basis is not the current held rate or last actual rate")
	check(shown.staged.bank_text == "Bank pays 0.20" and shown.staged.fed_text == "Fed pays 0.11", "Coexisting opposite cash flows are not netted")
	check(shown.actual.bank_text == "Bank pays 0.10" and shown.actual.fed_text == "Fed pays 0.20", "Last actual cash remains distinct from the preview")
	check(shown.staged.unpaid_text.contains("to Fed 0.05") and shown.staged.unpaid_text.contains("from Fed 0.03") and shown.actual.unpaid_text.contains("to Fed 0.20"), "Separate closing interest claims come directly from their supplied ledgers")
	check(shown.staged.purpose_text.contains("interest 0.10") and shown.staged.purpose_text.contains("withdrawals 0.40"), "Fresh-loan purposes are copied, not inferred from payments")
	check(shown.staged.detail.contains("Accrued to Fed 0.00; from Fed 0.01"), "Accrual and paid cash are never confused")
	var changed_future := p.duplicate(true)
	for key in ["credit_contexts", "credit_results", "credit_states", "states"]:
		changed_future[key][1] = "untrusted future sentinel"
		changed_future[key].append({"arbitrary_future": INF})
	changed_future.diagnostic_beyond_episode = false
	check(var_to_bytes(CreditPanel.present(a, changed_future)) == var_to_bytes(shown), "No future conditional values or metadata affect the first staged readout")
	a.held_annual_rate_pct = 999.0
	check(CreditPanel.present(a, p).staged.basis == shown.staged.basis, "Held-rate metadata cannot impersonate staged controls")
	a = actual()
	var opened := opening()
	var first := preview()
	first.states[0].quarter_index = 1
	var initial := CreditPanel.present(opened, first)
	check(initial.actual.ok and not initial.actual.settled and not initial.actual.has("bank_text") and initial.actual.basis.contains("no settlement yet"), "Opening null flows are not fabricated prior cash or income")
	var stale := CreditPanel.present(a, {"ok": false, "error": "unavailable"})
	check(stale.actual.ok and not stale.staged.ok and stale.staged.basis == "Staged unavailable" and not stale.staged.has("bank_text"), "Failed preview clears staged values while retaining correctly labelled actuals")
	check(not CreditPanel.present({}, {}).visible, "Leaving the mode hides an empty panel")
	for sign in [-1.0, 0.0, 1.0]:
		var signed := preview()
		signed.credit_contexts[0].annual_rate_pct = sign
		check(CreditPanel.present(a, signed).staged.ok, "Both APR signs and zero are displayable without an invented rate floor")
	var tiny := preview()
	for field in CreditPanel.FLOW_FIELDS:
		tiny.credit_results[0][field] = 1e-9
	tiny.credit_states[0] = {"payable": 1e-9, "receivable": 2e-9}
	var small := CreditPanel.present(a, tiny)
	check(small.staged.bank_text == "Bank pays <0.0001" and small.staged.fed_text == "Fed pays <0.0001" and small.staged.unpaid_text.contains("<0.0001"), "Nonzero subprecision payments and claims never show false zero")
	for field in CreditPanel.FLOW_FIELDS:
		for invalid in [NAN, INF, -INF, -0.1, true, "1", null, 9007199254740993]:
			var bad := preview()
			bad.credit_results[0][field] = invalid
			check(not CreditPanel.present(a, bad).staged.ok and CreditPanel.present(a, bad).actual.ok, "Bad staged flow refuses independently: " + field)
		var missing := preview()
		missing.credit_results[0].erase(field)
		check(not CreditPanel.present(a, missing).staged.ok, "Missing staged flow does not become zero")
	for key in ["credit_contexts", "credit_results", "credit_states", "states"]:
		for value in [[], {}, [null]]:
			var bad := preview()
			bad[key] = value
			check(not CreditPanel.present(a, bad).staged.ok, "Malformed first-entry container refuses")
	for field in ["annual_rate_pct", "days"]:
		var missing := preview()
		missing.credit_contexts[0].erase(field)
		check(not CreditPanel.present(a, missing).staged.ok, "Missing staged basis refuses")
	for days in [-1, 1.5, true, NAN, 9007199254740993]:
		var bad := preview()
		bad.credit_contexts[0].days = days
		check(not CreditPanel.present(a, bad).staged.ok, "Invalid whole-day basis refuses")
	for rate in [NAN, INF, -INF, true, "1"]:
		var bad := preview()
		bad.credit_contexts[0].annual_rate_pct = rate
		check(not CreditPanel.present(a, bad).staged.ok, "Invalid staged APR refuses without a fabricated rate")
	var disconnected := preview()
	disconnected.states[0].quarter_index = 3
	check(not CreditPanel.present(a, disconnected).staged.ok, "A stale or disconnected first preview cannot claim to be current")
	for field in ["payable", "receivable", "quarter_index", "has_settlement", "annual_rate_pct", "days"] + CreditPanel.FLOW_FIELDS:
		var bad := actual()
		bad.erase(field)
		check(not CreditPanel.present(bad, p).actual.ok and CreditPanel.present(bad, p).staged.ok, "Malformed actual readout clears independently: " + field)
	for field in ["payable", "receivable", "annual_rate_pct", "days"] + CreditPanel.FLOW_FIELDS:
		for value in [NAN, INF, true, "1"]:
			var bad := actual()
			bad[field] = value
			check(not CreditPanel.present(bad, p).actual.ok, "Nonfinite or wrongly typed actual value refuses independently: " + field)
	var impossible_opening := opening()
	impossible_opening.paid_positive = 0.0
	check(not CreditPanel.present(impossible_opening, first).actual.ok, "Opening zero is not accepted in place of an explicitly unknown prior flow")
	check(var_to_bytes([a, p]) == frozen, "Presenter preserves the original inputs exactly")
	shown.staged.payable = 999
	check(var_to_bytes([a, p]) == frozen, "Returned views retain no mutable input containers")
	_test_component(a, p)
	if failures == 0:
		print("PASS: priced credit panel ", checks, " checks; synthetic presentation only")
	else:
		printerr("FAIL: priced credit panel ", failures, " of ", checks)
	quit(0 if failures == 0 else 1)

func _test_component(a: Dictionary, p: Dictionary) -> void:
	var panel := CreditPanel.new()
	check(not panel.visible, "Panel begins empty")
	panel.update_credit(a, p)
	check(panel.visible and panel.staged_flow.visible and panel.actual_flow.visible, "Actual and staged cash lanes display independently")
	check(panel.staged_claims.get_theme_color("font_color") == CreditPanel.GOLD and panel.actual_claims.get_theme_color("font_color") == CreditPanel.GOLD, "Unpaid bank interest uses the funding-warning color, not neutral cash-flow styling")
	check(panel.staged_flow.arrows[0].rightward and not panel.staged_flow.arrows[1].rightward and panel.staged_flow.destinations[0].text == "Fed" and panel.staged_flow.destinations[1].text == "Bank", "Both lanes use the same Bank-left/Fed-right anchors")
	check(panel.staged_flow.get_child(0).get_child(0) == panel.staged_flow.labels[0] and panel.staged_flow.get_child(1).get_child(0) == panel.staged_flow.destinations[1], "Recipient and sender labels match the arrows spatially")
	check(panel.has_method("_make_custom_tooltip") and panel.staged_flow.has_method("_make_custom_tooltip") and panel.staged_flow.arrows[0].has_method("_make_custom_tooltip"), "All scripted roots retain wrapped tooltip hooks")
	check(panel.staged_flow.arrows[0].accessibility_name.contains("Bank pays 0.20") and panel.staged_flow.arrows[1].accessibility_name.contains("Fed pays 0.11"), "Meaningful graphic lanes have distinct accessible numeric readings")
	check(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec") == 0.0, "Existing project zero-delay tooltip policy is retained")
	_check_controls(panel)
	panel.update_credit(a, {"ok": false})
	check(panel.visible and panel.staged_basis.text == "Staged unavailable" and not panel.staged_flow.visible and panel.staged_claims.text == "" and panel.staged_purpose.text == "", "Preview failure visibly clears stale staged values")
	check(not panel.staged_claims.visible and not panel.staged_purpose.visible, "Unavailable staged rows take no empty layout space")
	check(panel.actual_basis.text.begins_with("Last actual") and panel.actual_flow.labels[0].text == "Bank pays 0.10", "Correctly labelled actual values survive a preview failure")
	panel.update_credit(opening(), {})
	check(not panel.actual_flow.visible and panel.actual_basis.text.contains("no settlement yet") and panel.actual_flow.labels[0].text == "", "Opening replacement clears previous actual flow rather than inventing zero")
	panel.update_credit({}, {})
	check(not panel.visible and panel.heading.text == "" and panel.actual_claims.text == "" and panel.staged_flow.arrows[0].accessibility_description == "" and panel.actual_flow.tooltip_text == "", "Leaving mode clears all stale values, tooltip and graphic accessibility data")
	panel.free()

func _check_controls(node: Node) -> void:
	if node is Control:
		check(node.focus_mode == Control.FOCUS_NONE, "Read-only panel adds no action or keyboard trap")
	if node is Label:
		check(node.get_theme_font_size("font_size") >= 12 and node.text.length() <= 80, "Visible primary labels are at least 12px and concise")
	for child in node.get_children():
		_check_controls(child)
