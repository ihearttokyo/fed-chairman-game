extends SceneTree
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func close_report(game) -> void:
	var report: AcceptDialog = game.get_child(game.get_child_count() - 1)
	report.get_ok_button().pressed.emit()
	await process_frame

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	check(game.get("mandate_label") is Label, "Persistent mandate assessment exists independently of transient status")
	if failures:
		game.free(); quit(1); return
	check(game.mandate_label.text.contains("MANDATE") and game.mandate_label.text.contains("In progress"), "Default challenge begins with explicit objectives, not an earned victory")
	check(game.mandate_label.accessibility_description.contains("fictional") and game.mandate_label.accessibility_description.contains("95%"), "Accessible description discloses the complete fictional criteria")
	var original: String = game.mandate_label.text
	var saved: PackedByteArray = game.career.encode()
	game.rate.value = -0.5
	game._preview()
	check(game.mandate_label.text == original and game.career.encode() == saved, "Staged signed policy cannot change realized assessment")
	game._advance()
	await process_frame
	check(game.career.state.quarter_index == 1 and game.mandate_label.text != original, "Real UI adoption refreshes objective progress")
	original = game.mandate_label.text
	game.status_label.text = "Transient save notification"
	check(game.mandate_label.text == original, "Save/status feedback cannot erase objectives")
	check(game._mandate_value_text(1.0000001,1.0) == ">1.000" and game._mandate_value_text(0.9999999,1.0) == "<1.000" and game._mandate_value_text(1.0,1.0) == "1.000", "Rounded equality cannot conceal a strict objective miss or improvement")
	# Summary fixtures exercise display arithmetic, not simulated careers.
	var summary: Dictionary = game.career.mandate_assessment().duplicate(true)
	summary["inflation_miss"] = 0.5
	summary["employment_shortfall"] = 0.1
	summary["recent_inflation_miss"] = 1.0000001
	summary["recent_employment_shortfall"] = 0.2
	summary["quarters"] = 23
	check(game._mandate_summary(summary).contains("Prices 12q >1.000/1 pp") and not game._mandate_summary(summary).contains("12q warning"), "Recent-only price miss is visible without a premature Q23 warning")
	summary["quarters"] = 24
	check(game._mandate_summary(summary).contains("In progress") and game._mandate_summary(summary).contains("12q warning"), "Q24 warning is advisory, not an early loss")
	summary["recent_inflation_miss"] = 0.5
	summary["recent_employment_shortfall"] = 1.0000001
	check(game._mandate_summary(summary).contains("Jobs 12q >1.000/1 pp") and game._mandate_summary(summary).contains("12q warning"), "Recent-only employment miss cannot hide behind a good lifetime mean")
	summary["recent_inflation_miss"] = 1.0
	summary["recent_employment_shortfall"] = 1.0
	check(not game._mandate_summary(summary).contains("12q warning"), "Inclusive recent boundaries produce no warning")
	summary["funding_active"] = true
	for coverable in [3.0, 82.0]:
		summary["funding_coverable"] = coverable
		var required: float = game.career.MANDATE_FUNDING_COVERAGE_MIN * coverable
		for delta in [0.0, -0.00000001, 0.00000001]:
			summary["funding_applied"] = required + delta
			summary["funding_coverage"] = summary.funding_applied / coverable
			summary["funding_met"] = summary.funding_applied >= required
			var relation := "<" if delta < 0.0 else ">" if delta > 0.0 else ""
			check(game._mandate_summary(summary).contains("Funding %s95.000/95%%" % relation), "Funding boundary text agrees with applied-versus-required scoring despite division rounding")
	game._help()
	await process_frame
	var help: AcceptDialog = game.get_child(game.get_child_count() - 1)
	check(help.get_child(0).text.contains("Mandate v1") and help.get_child(0).text.contains("95%"), "How to play explains how default achievement differs from career completion")
	await close_report(game)
	game.save_path = ProjectSettings.globalize_path("user://mandate-ui-fixture.save")
	game._save()
	saved = game.career.encode()
	original = game.mandate_label.text
	game._start_career("base",1)
	check(game.mandate_label.text.contains("Practice"), "Equilibrium laboratory is explicitly practice")
	game._load()
	await process_frame
	var loading: AcceptDialog = game.get_child(game.get_child_count() - 1)
	loading.get_ok_button().pressed.emit()
	await process_frame
	check(game.career.encode() == saved and game.mandate_label.text == original, "Actual Save/Load confirmation restores derived objectives without a saved award")
	for mode in ["hold","funded"]:
		game._start_career("unanchored_inflation",1)
		for q in range(239):
			var policy: Dictionary = game.career.model.benchmark_policy(game.career.state,game.career.params,"hold" if mode == "hold" else "feedback")
			if mode == "funded":
				var pulse: Dictionary = game.career.current_briefing()
				policy.liquidity_request_pct_initial_gdp = float(pulse.get("funding_need_pct_initial_gdp",0.0)) + minf(float(pulse.get("refinancing_need_pct_initial_gdp",0.0)),game.career.state.outstanding_liquidity_pct_initial_gdp)
			var advanced: Dictionary = game.career.advance(policy)
			check(advanced.ok,"Real native terminal setup remains valid")
			if not advanced.ok:
				game.free(); quit(1); return
		game._refresh(true)
		check(not game.decision_button.disabled and game.mandate_label.text.contains("In progress"), "Q239 is not an early award or forced ending")
		if mode == "funded":
			game._staff_rule()
			var pulse: Dictionary = game.career.current_briefing()
			game.liquidity.value = (float(pulse.get("funding_need_pct_initial_gdp",0.0)) + minf(float(pulse.get("refinancing_need_pct_initial_gdp",0.0)),game.career.state.outstanding_liquidity_pct_initial_gdp)) / game.career.model.nominal_gdp_ratio(game.career.state)
		game._advance()
		await process_frame
		var expected := "Mandate achieved" if mode == "funded" else "Mandate not met"
		check(game.career.state.quarter_index == 240 and game.decision_button.disabled and game.mandate_label.text.contains(expected), "Completion visibly separates achievement from merely surviving")
		var review: AcceptDialog = game.get_child(game.get_child_count() - 1)
		check(review.get_child(0).text.contains(expected) and review.get_child(0).text.contains("Mandate v1"), "Terminal review explains the actual achievement result")
		await close_report(game)
		saved = game.career.encode()
		check(game.career.restore(bytes_to_var(saved)).ok,"Terminal native replay remains accepted")
		game._refresh(true)
		check(game.mandate_label.text.contains(expected) and game.career.encode() == saved,"Restored completion computes the same visible achievement")
	game.free()
	if failures == 0:
		print("PASS: mandate UI persistence, realized feedback, precision, help, private Save/Load and both actual terminal outcomes; ",checks," checks")
	quit(1 if failures else 0)
