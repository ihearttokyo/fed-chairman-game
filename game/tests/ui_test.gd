extends SceneTree
var failures := 0
var pending_review: Button
func _process(_delta: float) -> bool:
	if pending_review != null:
		var action := pending_review
		pending_review = null
		action.pressed.emit()
	return false
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
func _initialize() -> void:
	call_deferred("run")
func check_cancel_window(dialog: AcceptDialog) -> void:
	check(dialog.visible, "cancel keeps the window registered through deferred accessibility focus")
func check_report_body(dialog: AcceptDialog, markers: Array[String]) -> void:
	await process_frame
	await process_frame
	var bodies := dialog.find_children("*", "TextEdit", true, false)
	check(bodies.size() == 1, "shared report provides a keyboard-focusable selectable native text body")
	if bodies.size() != 1:
		return
	var body: TextEdit = bodies[0]
	check(body.focus_mode == Control.FOCUS_ALL and body.selecting_enabled, "report body supports keyboard focus and native selection")
	check(not body.editable and body.wrap_mode == TextEdit.LINE_WRAPPING_BOUNDARY and not body.tab_input_mode, "report is read-only, wrapped and permits keyboard focus to leave")
	check(body.accessibility_name == dialog.title and body.custom_minimum_size == Vector2(690, 450), "report retains its accessible title and existing dimensions")
	check(body.accessibility_description == body.text, "native assistive description retains the entire report including wrapped paragraphs")
	for marker in markers:
		check(body.text.contains(marker), "complete report retains " + marker)
	body.select_all()
	check(body.get_selected_text() == body.text, "native selection includes the entire report, including its tail")
	body.grab_focus()
	var original_text := body.text
	var typed := InputEventKey.new()
	typed.keycode = KEY_X
	typed.unicode = 120
	typed.pressed = true
	dialog.push_input(typed)
	await process_frame
	check(body.text == original_text, "typing cannot replace selected report text or interpret markup")
	body.deselect()
	check(body.has_focus(), "native report body can receive keyboard focus")
	var scrollbar := body.get_v_scroll_bar()
	if scrollbar.max_value > scrollbar.page:
		var page_down := InputEventKey.new()
		page_down.keycode = KEY_PAGEDOWN
		page_down.pressed = true
		dialog.push_input(page_down)
		await process_frame
		check(scrollbar.value > 0, "native Page Down scrolls a long focused report")
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	dialog.push_input(tab)
	await process_frame
	check(not body.has_focus(), "Tab leaves the report body rather than trapping keyboard navigation")
func check_text_reports(game: Control) -> void:
	game._start_career("mixed_crises", 417)
	var preserved: PackedByteArray = game.career.encode()
	var staged: Dictionary = game._policy()
	var literal := "Plain [b]brackets[/b] stay literal.\n\nFinal warning remains intact."
	var dialog: AcceptDialog = game._text_dialog("Literal report", literal)
	await check_report_body(dialog, [literal])
	dialog.get_ok_button().pressed.emit()
	await process_frame
	for method in ["_help", "_credits", "_journal", "_review"]:
		game.call(method)
		dialog = game.get_child(game.get_child_count() - 1)
		await check_report_body(dialog, [])
		dialog.get_ok_button().pressed.emit()
		check(dialog.visible and dialog.is_queued_for_deletion(), "text reports preserve deferred accessibility closing")
		await process_frame
		check(game.career.encode() == preserved and game._policy() == staged, "shared text report cannot change career or staged tools")
	check(game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "feedback")).ok, "completed review setup uses a real model decision")
	game._refresh(true)
	preserved = game.career.encode()
	game._review()
	dialog = game.get_child(game.get_child_count() - 1)
	await check_report_body(dialog, ["REALIZED PATHS / Q1–Q1", "There is no dismissal threshold."])
	dialog.get_ok_button().pressed.emit()
	await process_frame
	check(game.career.encode() == preserved, "completed keyboard review is pure")
	for q in range(1, game.career.MAX_QUARTERS):
		check(game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "feedback")).ok, "long journal setup uses actual campaign decisions")
	game._refresh(true)
	preserved = game.career.encode()
	game._journal()
	dialog = game.get_child(game.get_child_count() - 1)
	var journal_markers: Array[String] = ["Recurring crises (advanced) · seed 417"]
	for state in game.career.history:
		journal_markers.append("Q%03d |" % state.quarter_index)
	await check_report_body(dialog, journal_markers)
	dialog.get_ok_button().pressed.emit()
	await process_frame
	check(game.career.encode() == preserved, "reading full completed history is pure")
	game._start_career("supply_shock", 1)
func check_score_feedback(game: Control) -> void:
	game._start_career("funding_stress", 42)
	var before: Dictionary = game.career.state.duplicate(true)
	var expected: Dictionary = game.career.model.step(before, game._policy(), game.career.current_briefing(), game.career.params)
	game._advance()
	check(expected.ok and game.career.state == expected.state, "score wording preserves the exact adopted economic state")
	var support_change: float = game.career.state.public_support - before.public_support
	check(support_change < 0 and abs(support_change) < 0.05, "real Funding stress decision exercises a small negative support change")
	check(game.consequence.text.contains("Public support down <0.05 points"), "real small support changes disclose their direction instead of negative zero")
	var credibility_change: float = 100 * (game.career.state.credibility - before.credibility)
	check(game.consequence.text.contains("credibility %+.1f points" % credibility_change), "credibility changes use score points, not the zero-to-one internal scale")
	check(game.consequence.accessibility_live == AccessibilityServer.LIVE_POLITE, "score feedback retains assistive announcements")
	check(game.has_method("_score_change"), "both outcome scores use one shared formatter")
	if game.has_method("_score_change"):
		var preserved: PackedByteArray = game.career.encode()
		for sample in [[0.0, "unchanged"], [-0.0, "unchanged"], [0.000001, "up <0.05 points"], [-0.000001, "down <0.05 points"], [0.049999, "up <0.05 points"], [-0.049999, "down <0.05 points"], [0.05, "+0.1 points"], [-0.05, "-0.1 points"], [1.25, "+1.2 points"], [-1.25, "-1.2 points"]]:
			check(game.call("_score_change", sample[0]) == sample[1], "score formatter preserves zero, small-change direction, precision threshold and signed points")
		check(game.career.encode() == preserved, "formatting score changes cannot change the career")
	game._start_career("supply_shock", 1)
func check_persistent_actions(game: Control) -> void:
	var actions: Array[Button] = []
	for button in game.find_children("*", "Button", true, false):
		if button.text in ["Compare policy paths", "Adopt decision  →  Next quarter"]:
			actions.append(button)
			var ancestor: Node = button.get_parent()
			while ancestor != game:
				check(not ancestor is ScrollContainer, "policy actions remain outside the scrolling cockpit")
				ancestor = ancestor.get_parent()
	check(actions.size() == 2, "comparison and adoption each have one action")
	for feedback in [game.status_label, game.consequence]:
		var feedback_ancestor: Node = feedback.get_parent()
		while feedback_ancestor != game:
			check(not feedback_ancestor is ScrollContainer, "career status and economic outcome remain outside the scrolling cockpit")
			feedback_ancestor = feedback_ancestor.get_parent()
	game._advance()
	game._advance()
	check(game.consequence.text.contains("Q2 OUTCOME") and game.consequence.text.contains("Previous promise follow-through"), "persistent feedback retains real outcome and prior promise explanation")
	var original_size := root.size
	var original_status: String = game.status_label.text
	game._staff_rule()
	game.commitment.select(2)
	game.commitment.item_selected.emit(2)
	for dimensions in [original_size, Vector2i(1180, 700)]:
		root.size = dimensions
		await process_frame
		await process_frame
		for button in actions:
			check(button.get_global_rect().position.y >= 0 and button.get_global_rect().end.y <= game.get_viewport_rect().end.y, "expanded guidance keeps actions within the viewport")
		check(game.status_label.get_global_rect().position.y >= 0 and game.status_label.get_global_rect().end.y <= game.get_viewport_rect().end.y, "long staff feedback remains within the viewport with expanded guidance")
		check(game.consequence.get_global_rect().position.y >= 0 and game.consequence.get_global_rect().end.y <= game.get_viewport_rect().end.y, "complete adopted outcome stays within the viewport with expanded guidance")
	root.size = original_size
	game.status_label.text = original_status
	game.commitment.select(0)
	game.commitment.item_selected.emit(0)
	await process_frame
func check_terminal_career(game: Control) -> void:
	game._start_career("base", 41)
	for q in range(game.career.MAX_QUARTERS - 1):
		check(game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "hold")).ok, "terminal setup uses valid decisions")
	game._refresh(true)
	check(game.quarter_label.text == "YEAR 60 / Q4   ·   MEETING 240" and not game.decision_button.disabled, "last supported meeting remains playable")
	game._advance()
	await process_frame
	check(game.career.state.quarter_index == 240, "UI adopts the final supported decision")
	check(game.quarter_label.text == "CAREER COMPLETE · 240 MEETINGS", "completion never advertises Year61 or meeting241")
	check(game.decision_button.disabled and game.decision_button.text == "Career complete", "terminal action explains why no next quarter is available")
	var review: AcceptDialog = game.get_child(game.get_child_count() - 1)
	check(review.title == "Your 12-quarter policy review", "completion retains the final realized policy review")
	review.get_ok_button().pressed.emit()
	await process_frame
	var preserved: PackedByteArray = game.career.encode()
	check(game.career.restore(bytes_to_var(preserved)).ok, "completed career restores through real replay")
	game._refresh(true)
	check(game.quarter_label.text == "CAREER COMPLETE · 240 MEETINGS" and game.decision_button.disabled, "restored completion uses the same shared refresh")
	check(game._decision_briefing().contains("CURRENT MEETING / REQUESTED AND APPLIED") and game.career.encode() == preserved, "terminal comparison remains available without changing completed history")
	game._start_career("supply_shock", 1)
	check(game.quarter_label.text == "YEAR 01 / Q1   ·   MEETING 1" and not game.decision_button.disabled and game.decision_button.text == "Adopt decision  →  Next quarter", "new career restores ordinary meeting and action labels")
func check_situation_ui(game: Control) -> void:
	check(game.briefing.text.contains("MARKETS /") and game.briefing.text.contains("PUBLIC /") and game.briefing.text.contains("FUNDING /"), "shared cockpit refresh exposes offline situation interpretation")
	game._start_career("funding_stress", 41)
	for q in range(4):
		game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "hold"))
	game._refresh(true)
	check(game.briefing.text.contains("New funding pressure") and game.briefing.text.contains("Funding need"), "interpretation retains the exact numerical dispatch")
	game.liquidity.value = 5.0
	game._advance()
	check(game.briefing.text.ends_with(game.career.situation_briefing()) and game.briefing.text.contains("Funding pressure continues"), "actual UI adoption advances the ongoing crisis readout")
	var text: String = game.briefing.text
	check(game.career.restore(bytes_to_var(game.career.encode())).ok, "UI readout uses real replay restoration")
	game._refresh(true)
	check(game.briefing.text == text, "shared load refresh restores identical situation text")
	game._start_career("base", 41)
	check(game.briefing.text.contains("No major new funding pressure") and not game.briefing.text.contains("Funding pressure continues"), "new career cannot retain the previous crisis storyline")
	game._start_career("supply_shock", 1)
func check_custom_guidance(game: Control) -> void:
	check(game.commitment.item_count == 3, "player can choose custom conditional guidance")
	if game.commitment.item_count != 3:
		return
	game._start_career("base", 417)
	game.career.shocks[0] = {"demand_shock_pct": 1.2}
	game.rate.value = 3.5
	game.guidance.value = 3.65
	var preset: Dictionary = game.career.forecast(game._policy())
	game.commitment.select(2)
	game.commitment.item_selected.emit(2)
	check(game.custom_guidance.visible, "custom conditions are visible only when selected")
	check(game.inflation_response.min_value == -game.career.params.guidance_sensitivity_limit and game.activity_response.max_value == game.career.params.guidance_sensitivity_limit, "custom conditions use model-defined bounds")
	game.inflation_response.value = 1.0
	game.activity_response.value = -0.25
	var preserved: PackedByteArray = game.career.encode()
	var preview: Dictionary = game.career.forecast(game._policy())
	check(preview.states[0].credibility == preset.states[0].credibility and preview.states[0].long_yield_pct == preset.states[0].long_yield_pct, "new conditions do not invent an immediate credibility or market-pricing bonus")
	check(game.career.encode() == preserved, "custom preview cannot change the career")
	game._advance()
	check(game.career.decisions[0].guidance_inflation_sensitivity == 1.0 and game.career.decisions[0].guidance_output_gap_sensitivity == -0.25, "custom coefficients reach the committed policy")
	check(game.commitment.selected == 2 and game._policy().guidance_output_gap_sensitivity == -0.25, "custom conditions persist after adoption")
	var replay = game.career.get_script().new()
	check(replay.restore(bytes_to_var(game.career.encode())).ok and replay.state == game.career.state, "custom communication survives lossless replay")
	var s: Dictionary = game.career.state
	var promise: float = s.guidance_rate_pct + s.guidance_inflation_sensitivity * (s.four_quarter_inflation_pct - s.guidance_reference_inflation_pct) + s.guidance_output_gap_sensitivity * (s.output_gap_pct - s.guidance_reference_output_gap_pct)
	game.rate.value = promise
	game.guidance.value = 4.0
	var follows: Dictionary = game.career.forecast(game._policy())
	var report: String = game._decision_briefing()
	check(report.contains("Adjusted prior promise %.3f%%" % promise), "comparison reveals the previous condition-adjusted promise")
	check(report.contains("Projected follow-through %.1f / 100" % (100 * follows.states[0].guidance_followthrough_score)), "comparison uses the actual model's projected follow-through")
	check(report.contains("new announcement does not erase"), "comparison distinguishes new communication from the previous obligation")
	game.rate.value = s.guidance_rate_pct
	var breaks: Dictionary = game.career.forecast(game._policy())
	check(follows.states[0].guidance_followthrough_score > breaks.states[0].guidance_followthrough_score and follows.states[0].credibility > breaks.states[0].credibility, "honoring the custom condition improves subsequent follow-through and credibility")
	game.commitment.select(1)
	game.commitment.item_selected.emit(1)
	check(not game.custom_guidance.visible and game._policy().guidance_inflation_sensitivity == 0.0 and game._policy().guidance_output_gap_sensitivity == 0.0, "firm preset cannot leak custom conditions")
	game.commitment.select(0)
	game.commitment.item_selected.emit(0)
	check(game._policy().guidance_inflation_sensitivity == game.career.params.policy_inflation_response and game._policy().guidance_output_gap_sensitivity == game.career.params.policy_output_gap_response, "data-dependent preset keeps its original coefficients")
	game.assets.value = 1.25
	game.liquidity.value = 2.0
	game._staff_rule()
	check(game.commitment.selected == 0 and game.assets.value == 1.25 and game.liquidity.value == 2.0, "staff selection restores its guidance rule without changing other tools")
	game._start_career("base", 417)
	check(game.commitment.selected == 0 and game.inflation_response.value == game.career.params.policy_inflation_response, "new career restores known guidance defaults")
	game.commitment.select(1)
	game.commitment.item_selected.emit(1)
	game.guidance.value = 15.0
	game._advance()
	check(game._decision_briefing().contains("outside this meeting's feasible rate range"), "comparison warns when an earlier pledge cannot be delivered")
	game._start_career("supply_shock", 1)
func check_pending_policy(game: Control) -> void:
	var fields := [game.rate, game.guidance, game.assets, game.liquidity, game.inflation_response, game.activity_response]
	var keys := ["policy_rate_request_pct", "guidance_rate_pct", "asset_flow_request_pct_initial_gdp", "liquidity_request_pct_initial_gdp", "guidance_inflation_sensitivity", "guidance_output_gap_sensitivity"]
	var texts := ["8.00", "7.25", "1.25", "2.50", "9.00", "-0.25"]
	var values := [8.0, 7.25, 1.25, 2.5, 2.0, -0.25]
	var descriptions := ["Requested rate 8.00%", "New quote 7.25%", "Requested assets +1.25", "Requested lending 2.50", "inflation response 2.00", "output-gap response -0.25"]
	for compare in [true, false]:
		for index in range(fields.size()):
			game._start_career("base", 41)
			game.commitment.select(2)
			game.commitment.item_selected.emit(2)
			await process_frame
			await process_frame
			var prior: Dictionary = game._policy()
			var preserved: PackedByteArray = game.career.encode()
			var edit: LineEdit = fields[index].get_line_edit()
			edit.grab_focus()
			edit.text = texts[index]
			check(edit.has_focus() and game._policy() == prior, "pending focused text leaves the preview policy uncommitted")
			var expected: Dictionary = prior.duplicate()
			expected[keys[index]] = values[index]
			var projected: Dictionary = game.career.forecast(expected)
			if compare:
				for button in game.find_children("*", "Button", true, false):
					if button.text == "Compare policy paths":
						button.pressed.emit()
				await process_frame
				await process_frame
				var comparison: AcceptDialog = game.get_child(game.get_child_count() - 1)
				var report: RichTextLabel = comparison.find_children("*", "RichTextLabel", true, false)[0]
				check(game._policy() == expected and report.text.contains(descriptions[index]), "Compare submits pending %s without Return" % keys[index])
				check(edit.text.to_float() == values[index], "Compare visibly normalizes bounded native input")
				check(game.forecast_label.text.contains("Rate %.2f%%" % projected.states[0].policy_rate_pct) and game.career.encode() == preserved, "Compare refreshes applied preview without changing the career")
				comparison.get_ok_button().pressed.emit()
				await process_frame
			else:
				game.decision_button.pressed.emit()
				check(game.career.decisions[0] == expected, "Adopt submits pending %s without Compare or Return" % keys[index])
				check(game.career.state == projected.states[0], "pending adoption matches the real model forecast")
	game._start_career("supply_shock", 1)
func check_unfocused_inputs(game: Control) -> void:
	var fields := [game.rate, game.guidance, game.assets, game.liquidity, game.inflation_response, game.activity_response]
	var keys := ["policy_rate_request_pct", "guidance_rate_pct", "asset_flow_request_pct_initial_gdp", "liquidity_request_pct_initial_gdp", "guidance_inflation_sensitivity", "guidance_output_gap_sensitivity"]
	var texts := ["8.00", "7.25", "1.25", "2.50", "9.00", "-0.25"]
	var values := [8.0, 7.25, 1.25, 2.5, 2.0, -0.25]
	for compare in [true, false]:
		game._start_career("base", 41)
		game.commitment.select(2)
		game.commitment.item_selected.emit(2)
		await process_frame
		await process_frame
		game.decision_button.grab_focus()
		var prior: Dictionary = game._policy()
		var preserved: PackedByteArray = game.career.encode()
		var expected: Dictionary = prior.duplicate()
		for index in range(fields.size()):
			var edit: LineEdit = fields[index].get_line_edit()
			# Godot's accessible set-value handler uses set_text, without focus or submit.
			edit.text = texts[index]
			check(not edit.has_focus(), "accessible policy edit remains unfocused")
			expected[keys[index]] = values[index]
		check(game._policy() == prior, "unfocused text remains pending until submission")
		var projected: Dictionary = game.career.forecast(expected)
		if compare:
			game._compare()
			await process_frame
			await process_frame
			var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
			var report: RichTextLabel = dialog.find_children("*", "RichTextLabel", true, false)[0]
			check(game._policy() == expected and report.text.contains("Requested rate 8.00%") and report.text.contains("Requested assets +1.25"), "Compare submits all unfocused accessible fields without Return")
			check(game.career.encode() == preserved and game.forecast_label.text.contains("Rate %.2f%%" % projected.states[0].policy_rate_pct), "accessible comparison uses the real model without advancing")
			for index in range(fields.size()):
				check(fields[index].get_line_edit().text.to_float() == values[index], "accessible submission visibly normalizes each native bound")
			dialog.get_ok_button().pressed.emit()
			await process_frame
		else:
			game.decision_button.pressed.emit()
			check(game.career.decisions[0] == expected and game.career.state == projected.states[0], "Adopt submits all unfocused accessible fields without Compare or Return")
	game._start_career("base", 41)
	game.commitment.select(2)
	game.commitment.item_selected.emit(2)
	await process_frame
	await process_frame
	game.decision_button.grab_focus()
	for index in range(fields.size()):
		fields[index].value = values[index]
	var programmed: Dictionary = game._policy()
	game._apply_policy_inputs()
	check(game._policy() == programmed, "same-frame programmatic policy updates survive stale unfocused text")
	await process_frame
	await process_frame
	var settled: Dictionary = game._policy()
	check(game.rate.get_meta("numeric_text") == game.rate.get_line_edit().text, "native draw synchronizes the numeric display baseline")
	game.rate.get_line_edit().text = "3.50"
	game._apply_policy_inputs()
	settled.policy_rate_request_pct = 3.5
	check(game._policy() == settled, "accessible edit can return to the earlier displayed rate after a numeric update")
	game.rate.get_line_edit().text = "4 + 4"
	game._apply_policy_inputs()
	check(game.rate.value == 8.0, "unfocused expression uses the native SpinBox parser")
	var native_text: String = game.rate.get_line_edit().text
	game.rate.get_line_edit().text = "not a number"
	game._apply_policy_inputs()
	check(game.rate.value == 8.0 and game.rate.get_line_edit().text == native_text, "invalid accessible text retains and normalizes the native numeric value")
	for seed_case in [["42", 42], ["0", 1], ["2147483648", 2147483647]]:
		game._new_dialog()
		await process_frame
		var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
		dialog.get_ok_button().grab_focus()
		game.seed_input.get_line_edit().text = seed_case[0]
		check(not game.seed_input.get_line_edit().has_focus() and game.seed_input.value == 1, "accessible seed remains unfocused and pending")
		dialog.get_ok_button().pressed.emit()
		check(game.career.seed_value == seed_case[1], "new-career confirmation submits unfocused accessible seed with native bounds")
		await process_frame
	game._new_dialog()
	await process_frame
	var programmatic_dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	programmatic_dialog.get_ok_button().grab_focus()
	game.seed_input.value = 42
	check(game.seed_input.get_line_edit().text == "1", "programmatic seed keeps queued native display before draw")
	programmatic_dialog.get_ok_button().pressed.emit()
	check(game.career.seed_value == 42, "shared submission preserves the same-frame programmatic seed")
	await process_frame
	game._start_career("supply_shock", 1)
func check_pending_overwrites(game: Control) -> void:
	var fields := [game.rate, game.guidance, game.assets, game.liquidity, game.inflation_response, game.activity_response]
	var texts := ["8.00", "7.25", "1.25", "2.50", "9.00", "-0.25"]
	game._start_career("base", 41)
	await process_frame
	await process_frame
	game.decision_button.grab_focus()
	var defaults: Dictionary = game._policy()
	for index in range(fields.size()):
		fields[index].get_line_edit().text = texts[index]
	game._start_career("base", 42)
	game._apply_policy_inputs()
	check(game._policy() == defaults, "explicit new-career reset discards all pending text even when numeric defaults are unchanged")
	await process_frame
	await process_frame
	game._apply_policy_inputs()
	check(game._policy() == defaults and game.rate.get_line_edit().text.to_float() == defaults.policy_rate_request_pct, "reset numeric policy and visible rate remain default after native draw")
	game.commitment.select(2)
	game.commitment.item_selected.emit(2)
	await process_frame
	await process_frame
	check(game.inflation_response.get_line_edit().text.to_float() == game.career.params.policy_inflation_response and game.activity_response.get_line_edit().text.to_float() == game.career.params.policy_output_gap_response, "reset also clears pending text in hidden custom conditions")
	game._start_career("base", 41)
	await process_frame
	await process_frame
	game.decision_button.grab_focus()
	var preserved: PackedByteArray = game.career.encode()
	game.rate.get_line_edit().text = "8.00"
	game.guidance.get_line_edit().text = "7.25"
	game.assets.get_line_edit().text = "1.25"
	game._staff_rule()
	check(game.career.encode() == preserved and game.assets.value == 0.0 and game.assets.get_line_edit().text == "1.25", "staff rule preserves career and other pending tools")
	game._apply_policy_inputs()
	check(game.rate.value == 3.5 and game.guidance.value == 3.5 and game.assets.value == 1.25, "same-value staff rule overrides pending rate and quote without discarding other tools")
	await process_frame
	await process_frame
	check(game.rate.get_line_edit().text.to_float() == 3.5 and game.guidance.get_line_edit().text.to_float() == 3.5, "staff-selected rate and quote stay visible after native draw")
	game._start_career("supply_shock", 1)
func check_review_access(game: Control) -> void:
	for quarters in [0, 1, 13]:
		game._start_career("base", 41)
		for q in range(quarters):
			game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "hold"))
		check(game.career.restore(bytes_to_var(game.career.encode())).ok, "restored careers retain realized review inputs")
		game._refresh(true)
		var preserved: PackedByteArray = game.career.encode()
		var staged: Dictionary = game._policy()
		game._journal()
		await process_frame
		var journal: AcceptDialog = game.get_child(game.get_child_count() - 1)
		var action: Button
		for button in journal.find_children("*", "Button", true, false):
			if button.text == "Review realized policy":
				action = button
		check(action != null, "journal provides on-demand realized review access")
		if action == null or quarters == 0:
			if action != null:
				check(action.disabled, "review action waits for a completed decision")
			journal.get_ok_button().pressed.emit()
		else:
			check(not action.disabled, "completed decisions enable realized review")
			if quarters == 13:
				# MainLoop processing runs just before SceneTree's process_frame,
				# without an intervening deletion flush.
				pending_review = action
				await process_frame
			else:
				action.pressed.emit()
			check(journal.visible and journal.is_queued_for_deletion(), "review replaces the journal without hiding its accessibility window prematurely")
			await process_frame
			await process_frame
			var review: AcceptDialog = game.get_child(game.get_child_count() - 1)
			var reviews := 0
			for child in game.get_children():
				if child is AcceptDialog and child.visible:
					reviews += 1
			check(reviews == 1 and not is_instance_valid(journal), "only one review remains after actual journal exit")
			var text: TextEdit = review.get_child(0)
			check(review.title == "Your %d-quarter policy review" % mini(12, quarters), "on-demand review title uses actual interval length")
			check(text.text.contains("REALIZED PATHS / Q%d–Q%d" % [maxi(0, quarters - 12) + 1, quarters]), "on-demand review reports only the latest completed interval")
			review.get_ok_button().pressed.emit()
		await process_frame
		check(game.career.encode() == preserved and game._policy() == staged, "opening and closing realized review preserves career and controls")
	game._start_career("supply_shock", 1)
func check_comparison_navigation(game: Control) -> void:
	var destinations := [["Meeting", "CURRENT MEETING /"], ["Deliberation", "COMMITTEE DELIBERATION /"], ["Guidance", "GUIDANCE /"], ["Scores", "Q+1 / WHY"], ["Forecasts", "CURRENT TRANSMISSION /"], ["Tools", "ONE-CONTROL CONTRASTS /"], ["Limits", "REFERENCE AND LIMITS"]]
	for case_id in ["funding_stress", "base"]:
		game._start_career(case_id, 11)
		if case_id == "funding_stress":
			for q in range(4):
				game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "hold"))
			game._refresh(true)
			game.rate.value = 8.0
			game.guidance.value = 8.0
			game.assets.value = 2.0
			game.liquidity.value = 5.0
		await process_frame
		var preserved: PackedByteArray = game.career.encode()
		var staged: Dictionary = game._policy()
		var expected: String = game._decision_briefing()
		game._compare()
		await process_frame
		await process_frame
		var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
		var choosers := dialog.find_children("*", "OptionButton", true, false)
		var bodies := dialog.find_children("*", "RichTextLabel", true, false)
		check(choosers.size() == 1 and bodies.size() == 1, "comparison provides native section navigation and a selectable complete report")
		if choosers.size() == 1 and bodies.size() == 1:
			var chooser: OptionButton = choosers[0]
			var body: RichTextLabel = bodies[0]
			check(body.text == expected and body.get_parsed_text() == expected, "section navigation preserves every report byte and warning")
			check(body.selection_enabled and body.focus_mode == Control.FOCUS_ALL, "comparison report supports native text selection and keyboard focus")
			check(chooser.accessibility_name == "Comparison section" and chooser.item_count == destinations.size(), "section chooser has a distinct accessible name and all seven destinations")
			for index in range(mini(chooser.item_count, destinations.size())):
				check(chooser.get_item_text(index) == destinations[index][0], "comparison sections retain their named order")
				var paragraph := expected.substr(0, expected.find(destinations[index][1])).count("\n")
				chooser.select(index)
				chooser.item_selected.emit(index)
				await process_frame
				var position: float = body.get_paragraph_offset(paragraph) - body.get_v_scroll_bar().value
				check(position >= -1 and position < body.size.y - body.get_theme_font("normal_font").get_height(), "selecting %s brings its actual heading into view" % destinations[index][0])
				check(chooser.get_global_rect().end.y <= body.get_global_rect().position.y and chooser.is_visible_in_tree(), "section navigation remains above the scrolling report")
			check(game.career.encode() == preserved and game._policy() == staged, "section changes cannot mutate the career or staged decision")
			body.select_all()
			check(body.get_selected_text() == expected, "the full comparison remains available to native selection")
		dialog.get_ok_button().pressed.emit()
		check(dialog.visible and dialog.is_queued_for_deletion(), "comparison navigation preserves deferred accessibility closing")
		await process_frame
		game._compare()
		await process_frame
		await process_frame
		var reopened: AcceptDialog = game.get_child(game.get_child_count() - 1)
		var reset_bodies := reopened.find_children("*", "RichTextLabel", true, false)
		if reset_bodies.size() == 1:
			check(reset_bodies[0].get_v_scroll_bar().value == 0, "reopening comparison starts at the meeting rather than a stale section")
		reopened.get_ok_button().pressed.emit()
		await process_frame
		check(game.career.encode() == preserved and game._policy() == staged, "closing and reopening comparison preserves the unsaved decision")
	game._start_career("supply_shock", 1)
func check_rate_deliberation(game: Control) -> void:
	for edge in ["ordinary", "middle", "floor", "ceiling"]:
		game._start_career("funding_stress", 41)
		var target := 0.0 if edge == "floor" else 15.0
		for q in range(4 if edge in ["middle", "ordinary"] else 16):
			var choice: Dictionary = game.career.model.benchmark_policy(game.career.state, game.career.params, "hold")
			if edge not in ["middle", "ordinary"]:
				choice.policy_rate_request_pct = target
			check(game.career.advance(choice).ok, "deliberation boundary setup uses real valid decisions")
		game._refresh(true)
		game.rate.value = 8.0 if edge == "middle" else game.career.state.policy_rate_pct
		game.guidance.value = 4.0
		game.assets.value = 1.25
		game.liquidity.value = 2.5
		game.commitment.select(2)
		game.commitment.item_selected.emit(2)
		game.inflation_response.value = 0.7
		game.activity_response.value = -0.25
		var preserved: PackedByteArray = game.career.encode()
		var staged: Dictionary = game._policy()
		var selected: Dictionary = game.career.forecast(staged)
		var applied: float = selected.states[0].policy_rate_pct
		var low: float = max(game.career.params.policy_rate_min_pct, game.career.state.policy_rate_pct - game.career.params.policy_rate_change_limit_pct)
		var high: float = min(game.career.params.policy_rate_max_pct, game.career.state.policy_rate_pct + game.career.params.policy_rate_change_limit_pct)
		var report: String = game._decision_briefing()
		check(report.contains("COMMITTEE DELIBERATION / FEASIBLE RATE ALTERNATIVES"), "comparison exposes nearby offline rate deliberation")
		for alternative in [["Selected", applied], ["Tighter rate", clampf(applied + 0.25, low, high)], ["Gentler rate", clampf(applied - 0.25, low, high)], ["Rate continuity", game.career.state.policy_rate_pct]]:
			var other: Dictionary = staged.duplicate()
			other.policy_rate_request_pct = alternative[1]
			var path: Dictionary = selected if alternative[0] == "Selected" else game.career.forecast(other)
			var last: Dictionary = path.states[-1]
			check(report.contains("%s / applied %.2f%%\nQ+8 inflation %.3f%%; unemployment %.3f%%; credibility %.1f/100; support %.1f/100" % [alternative[0], path.states[0].policy_rate_pct, last.four_quarter_inflation_pct, last.unemployment_rate_pct, 100 * last.credibility, last.public_support]), "deliberation uses real capped forecasts with every other staged tool preserved")
		check(report.contains("Fictional viewpoints, not votes or advice"), "deliberation labels fictional viewpoints")
		check(report.contains("no extra feasible rate move") == (applied == low or applied == high), "only saturated rate directions receive a limit warning")
		check(game.career.encode() == preserved and game._policy() == staged, "deliberation cannot adopt or replace staged tools")
		var future: Dictionary = game.career.shocks[game.career.decisions.size() + 1].duplicate(true)
		game.career.shocks[game.career.decisions.size() + 1].demand_shock_pct = 8.0
		check(game._decision_briefing() == report, "deliberation cannot read undisclosed future shocks")
		game.career.shocks[game.career.decisions.size() + 1] = future
	game._start_career("supply_shock", 1)
func check_city_framing(game: Control, viewport: SubViewport) -> void:
	var camera := viewport.get_camera_3d()
	var horizontal_axes := [Vector3(camera.global_basis.x.x, 0, camera.global_basis.x.z).normalized(), Vector3(camera.global_basis.y.x, 0, camera.global_basis.y.z).normalized()]
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var count := 0
	for node in game.city.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = node
		for surface in range(instance.mesh.get_surface_count()):
			var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point: Vector3 = instance.global_transform * vertex
				var radius := Vector2(point.x, point.z).length()
				for axis in horizontal_axes:
					for sign_value in [-1, 1]:
						var pixel := camera.unproject_position(Vector3(axis.x * radius * sign_value, point.y, axis.z * radius * sign_value))
						minimum = minimum.min(pixel)
						maximum = maximum.max(pixel)
				count += 1
	print("CITY_FRAME size=", camera.size, " viewport=", viewport.size, " min=", minimum, " max=", maximum, " vertices=", count)
	check(count > 0 and minimum.x >= 0 and minimum.y >= 0 and maximum.x <= viewport.size.x and maximum.y <= viewport.size.y, "complete native city fits the camera through every rotation")
func check_city_redraw(game: Control, viewport: SubViewport) -> void:
	var motion: CheckButton
	for button in game.find_children("*", "CheckButton", true, false):
		if button.text == "Animate city":
			motion = button
	check(motion != null, "city motion remains an explicit control")
	if motion == null:
		return
	check(game.reduced_motion and viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "static city requests one native render, not perpetual redraw")
	var rotation: float = game.city.rotation.y
	game._process(1.0)
	check(game.city.rotation.y == rotation, "static city keeps its orientation")
	motion.button_pressed = true
	check(not game.reduced_motion and viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "enabled motion restores continuous native rendering")
	game._process(1.0)
	check(is_equal_approx(game.city.rotation.y, rotation + 0.025), "animation retains its existing speed")
	motion.button_pressed = false
	check(game.reduced_motion and viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "disabling motion rearms its final static frame")
	var container: SubViewportContainer = viewport.get_parent()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.size_changed.emit()
	check(viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "native size notification rearms static texture")
	var original_size := viewport.size
	container.stretch_shrink = 2
	check(viewport.size == original_size / 2 and viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "real native size change requests a new static frame")
	container.stretch_shrink = 1
	check(viewport.size == original_size and viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "restored native size rearms the full-quality city")
	container.hide()
	check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "hidden city does not request a redraw")
	container.show()
	await process_frame
	check(viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "visible static city overrides container's continuous-mode reset")
	motion.button_pressed = true
	container.hide()
	container.show()
	await process_frame
	check(viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "visible animated city continues after visibility change")
	motion.button_pressed = false
	game.city.rotation.y = rotation
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	check_score_feedback(game)
	if OS.get_cmdline_user_args().has("--score-feedback-only"):
		if failures == 0:
			print("PASS: meaningful score-change direction and units")
		game.free()
		quit(1 if failures else 0)
		return
	if OS.get_cmdline_user_args().has("--text-reports-only"):
		await check_text_reports(game)
		if failures == 0:
			print("PASS: complete selectable keyboard text reports")
		game.free()
		quit(1 if failures else 0)
		return
	if OS.get_cmdline_user_args().has("--inputs-only"):
		await check_pending_policy(game)
		await check_unfocused_inputs(game)
		await check_pending_overwrites(game)
		if failures == 0:
			print("PASS: focused, accessible and programmatic native input submission")
		game.free()
		quit(1 if failures else 0)
		return
	var city_viewports: Array = game.find_children("*", "SubViewport", true, false)
	check(city_viewports.size() == 1 and city_viewports[0].msaa_3d == Viewport.MSAA_4X, "miniature city uses bounded four-sample native edge antialiasing")
	if city_viewports.size() == 1:
		check_city_framing(game, city_viewports[0])
		await check_city_redraw(game, city_viewports[0])
	if OS.get_cmdline_user_args().has("--city-only"):
		if failures == 0:
			print("PASS: native miniature antialiasing")
		game.free()
		quit(1 if failures else 0)
		return
	if OS.get_cmdline_user_args().has("--feedback-only"):
		await check_persistent_actions(game)
		if failures == 0:
			print("PASS: persistent policy actions and outcome feedback")
		game.free()
		quit(1 if failures else 0)
		return
	check_rate_deliberation(game)
	if OS.get_cmdline_user_args().has("--deliberation-only"):
		if failures == 0:
			print("PASS: offline feasible rate deliberation")
		game.free()
		quit(1 if failures else 0)
		return
	check_situation_ui(game)
	if OS.get_cmdline_user_args().has("--situation-only"):
		if failures == 0:
			print("PASS: situation briefing in shared cockpit")
		game.free()
		quit(1 if failures else 0)
		return
	await check_terminal_career(game)
	if OS.get_cmdline_user_args().has("--terminal-only"):
		if failures == 0:
			print("PASS: terminal career and restart labels")
		game.free()
		quit(1 if failures else 0)
		return
	var unemployment_heading: Label = game.stats[1][0].get_parent().get_child(0)
	check(unemployment_heading.text == "UNEMPLOYMENT", "cockpit card names the unemployment rate it displays")
	check(game.charts[1].heading == "UNEMPLOYMENT & STRUCTURAL REFERENCE" and game.charts[1].accessibility_name == game.charts[1].heading, "chart heading and accessibility name identify unemployment")
	check(game.stats[1][0].text == "%.2f%%" % game.career.state.unemployment_rate_pct and game.charts[1].keys == ["unemployment_rate_pct", "structural_unemployment_pct"] and game.charts[1].labels == ["Unemployment", "Structural reference"], "unemployment naming retains values, units, series and reference")
	await check_comparison_navigation(game)
	await check_pending_policy(game)
	await check_unfocused_inputs(game)
	await check_pending_overwrites(game)
	await check_review_access(game)
	await check_text_reports(game)
	check_custom_guidance(game)
	await check_persistent_actions(game)
	var compare_button: Button
	for button in game.find_children("*", "Button", true, false):
		if button.text == "Compare policy paths":
			compare_button = button
	check(compare_button != null, "player can compare selected policy with holding policy")
	if compare_button != null:
		game._start_career("funding_stress", 11)
		for q in range(4):
			game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "hold"))
		game._refresh(true)
		game.rate.value = 8.0
		game.guidance.value = 8.0
		game.assets.value = 2.0
		game.liquidity.value = 5.0
		var preserved: Dictionary = game.career.payload()
		var selected: Dictionary = game.career.forecast(game._policy())
		var held: Dictionary = game.career.forecast(game.career.model.benchmark_policy(game.career.state, game.career.params, "hold"))
		var report: String = game._decision_briefing()
		check(report.contains("Requested rate 8.00%"), "briefing shows the requested instrument")
		check(report.contains("Applied rate %.2f%%" % selected.states[0].policy_rate_pct), "briefing shows actual capped rate")
		check(report.contains("Applied lending %.2f" % selected.states[0].liquidity_applied_pct_initial_gdp), "briefing shows collateral-constrained lending")
		check(report.contains("ONE-CONTROL CONTRASTS / SELECTED MINUS ALTERNATIVE"), "comparison isolates staged tools")
		var alternatives := [
			["Rate / alternative request today's rate", "policy_rate_request_pct", game.career.state.policy_rate_pct, "%"],
			["Guidance quote / alternative quote applied rate", "guidance_rate_pct", selected.states[0].policy_rate_pct, "%"],
			["Asset flow / alternative no new flow", "asset_flow_request_pct_initial_gdp", 0.0, "% of initial annual GDP"],
			["Lending / alternative no new loans", "liquidity_request_pct_initial_gdp", 0.0, "% of initial annual GDP"],
		]
		for alternative in alternatives:
			var other: Dictionary = game._policy().duplicate()
			other[alternative[1]] = alternative[2]
			var path: Dictionary = game.career.forecast(other)
			var first: Dictionary = selected.states[0]
			var last: Dictionary = selected.states[7]
			var reference_first: Dictionary = path.states[0]
			var reference_last: Dictionary = path.states[7]
			var row := "%s: %.2f%s\nQ+1 long yield %+.3f pp; credit spread %+.3f pp\nQ+8 inflation %+.3f pp; unemployment %+.3f pp; credibility %+.2f points; support %+.2f points" % [alternative[0], alternative[2], alternative[3], first.long_yield_pct - reference_first.long_yield_pct, first.credit_spread_pct - reference_first.credit_spread_pct, last.four_quarter_inflation_pct - reference_last.four_quarter_inflation_pct, last.unemployment_rate_pct - reference_last.unemployment_rate_pct, 100 * (last.credibility - reference_last.credibility), last.public_support - reference_last.public_support]
			check(report.contains(row), "named tool contrast matches its real one-input alternative at both horizons")
		check(report.contains("only its named input") and report.contains("not additive") and report.contains("conditional coefficients unchanged"), "tool contrasts disclose matched controls and interpretation limits")
		check(report.contains("Inflation %+.3f pp" % (selected.states[7].four_quarter_inflation_pct - held.states[7].four_quarter_inflation_pct)), "comparison uses the actual paired Q8 paths")
		check(report.contains("Credibility %.1f vs %.1f" % [100 * selected.states[7].credibility, 100 * held.states[7].credibility]), "comparison exposes credibility consequences")
		for staged_rate in [8.0, game.career.state.policy_rate_pct]:
			game.rate.value = staged_rate
			selected = game.career.forecast(game._policy())
			var first: Dictionary = selected.states[0]
			var reference: Dictionary = held.states[0]
			var diagnostics: String = game._decision_briefing()
			check(diagnostics.contains("Q+1 / WHY CREDIBILITY AND SUPPORT MOVE"), "comparison identifies the diagnostic horizon")
			check(diagnostics.contains("Credibility %.1f vs %.1f / 100\nPublic support %.1f vs %.1f / 100" % [100 * first.credibility, 100 * reference.credibility, first.public_support, reference.public_support]), "diagnostics show paired first-quarter scores")
			check(diagnostics.contains("Inflation-miss memory %.3f vs %.3f pp" % [first.inflation_miss_memory_pct, reference.inflation_miss_memory_pct]), "diagnostics show the model's inflation memory")
			check(diagnostics.contains("Model stance target %.3f%% vs %.3f%%\nApplied-rate distance %.3f vs %.3f pp" % [first.reaction_function_target_pct, reference.reaction_function_target_pct, abs(first.policy_rate_pct - first.reaction_function_target_pct), abs(reference.policy_rate_pct - reference.reaction_function_target_pct)]), "diagnostics show the target and applied rather than requested stance")
			check(diagnostics.contains("Prior-promise follow-through %.1f vs %.1f / 100" % [100 * first.guidance_followthrough_score, 100 * reference.guidance_followthrough_score]), "diagnostics show paired follow-through")
			check(diagnostics.contains("Current hardship %.3f vs %.3f support points\nHardship memory %.3f vs %.3f support points" % [first.current_hardship, reference.current_hardship, first.public_hardship_memory, reference.public_hardship_memory]), "diagnostics distinguish current hardship from memory")
			check(diagnostics.contains("40% inflation performance, 40% stance, 20% follow-through") and diagnostics.contains("game assumptions, not an optimal policy or a measured institutional reputation"), "diagnostics disclose weights and interpretation limits")
			check(game.career.payload() == preserved and game.rate.value == staged_rate, "diagnostics cannot alter the career or staged controls")
		game.rate.value = 8.0
		check(report.contains("no new asset flows or loans") and report.contains("same current shock"), "reference policy and shock assumptions are explicit")
		check(game.career.payload() == preserved and game.rate.value == 8.0, "comparison cannot alter the career or controls")
		game.career.shocks[6].demand_shock_pct = 10.0
		check(game._decision_briefing() == report, "comparison cannot peek at future realized shocks")
		compare_button.pressed.emit()
		await process_frame
		var comparison: AcceptDialog = game.get_child(game.get_child_count() - 1)
		check(comparison.title == "Compare policy paths", "comparison button opens its briefing")
		comparison.get_ok_button().pressed.emit()
		await process_frame
		game._start_career("supply_shock", 1)
		var neutral_report: String = game._decision_briefing()
		check(neutral_report.count("Q+1 long yield +0.000 pp; credit spread +0.000 pp") == 4 and neutral_report.count("Q+8 inflation +0.000 pp; unemployment +0.000 pp; credibility +0.00 points; support +0.00 points") == 4, "unused-tool contrasts truthfully report zero effect")
	game.rate.value = 4.25
	game.guidance.value = 4.25
	await process_frame # SpinBox updates its visible text on the next frame.
	check(game.rate.get_line_edit().text == "4.25", "rate field must display its actual 4.25 decision")
	check(game.guidance.get_line_edit().text == "4.25", "guidance field must display its actual 4.25 promise")
	check(game.forecast_label.text.contains("Rate 4.25%"), "preview reflects staged rate")
	game._advance()
	check(game.career.state.quarter_index == 1 and game.career.state.policy_rate_pct == 4.25, "UI adopts the displayed policy")
	check(game.charts[0].history.size() == 2 and game.consequence.text.contains("Q1 OUTCOME"), "adoption updates chart and feedback")
	check(game.consequence.accessibility_live == AccessibilityServer.LIVE_POLITE, "quarterly outcome is announced to assistive technology")
	game.career.state.four_quarter_inflation_pct = 2.0
	game.career.state.output_gap_pct = 0.0
	game.career.state.unemployment_rate_pct = 9.0
	game._review()
	await process_frame
	var review: AcceptDialog = game.get_child(game.get_child_count() - 1)
	var review_text: TextEdit = review.get_child(0)
	check(review.title == "Your 1-quarter policy review", "short completed review does not claim twelve quarters")
	check(not review_text.text.contains("employment are close"), "review cannot infer employment from the output gap")
	check(review_text.text.contains("REALIZED PATHS") and review_text.text.contains("unemployment above structural reference"), "review exposes realized inflation and employment tradeoffs")
	check(review_text.text.contains("already occurred") and review_text.text.contains("not a forecast"), "review distinguishes hindsight from a conditional future preview")
	review.get_ok_button().pressed.emit()
	await process_frame
	var before_new: PackedByteArray = game.career.encode()
	var staged_before_new: Dictionary = game._policy()
	game._new_dialog()
	await process_frame
	var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	var opening_text := ""
	for label in dialog.find_children("*", "Label", true, false):
		opening_text += label.text + "\n"
	check(opening_text.contains("Every career includes seeded background disturbances") and opening_text.contains("even the baseline"), "new-career disclosure distinguishes seeded baseline play from a no-shock equilibrium")
	check(game.seed_input.tooltip_text.contains("scenario and seed") and game.seed_input.tooltip_text.contains("same engine and model"), "seed tooltip qualifies every input needed to reproduce the path")
	check(game.career.encode() == before_new and game._policy() == staged_before_new, "opening seeded disclosure leaves the active career and staged policy unchanged")
	dialog.get_ok_button().pressed.emit()
	check(game.career.seed_value == 1 and game.career.scenario_id == "base", "untouched new-career dialog uses its default seed and scenario")
	check(dialog.visible and dialog.is_queued_for_deletion(), "dialog stays valid until the accessibility action finishes")
	await process_frame
	game._new_dialog()
	await process_frame
	var programmatic_dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	programmatic_dialog.get_ok_button().grab_focus()
	game.seed_input.value = 42
	check(not game.seed_input.get_line_edit().has_focus() and game.seed_input.get_line_edit().text == "1", "unfocused seed display can still be queued after a programmatic change")
	programmatic_dialog.get_ok_button().pressed.emit()
	check(game.career.seed_value == 42, "unfocused stale display cannot overwrite the seed value")
	await process_frame
	for seed_case in [["11", 11], ["0", 1], ["2147483648", 2147483647]]:
		game._new_dialog()
		await process_frame
		var seed_dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
		for index in range(game.scenario.item_count):
			if game.scenario.get_item_metadata(index) == "funding_stress":
				game.scenario.select(index)
		var edit: LineEdit = game.seed_input.get_line_edit()
		edit.grab_focus()
		edit.text = seed_case[0]
		check(edit.has_focus() and game.seed_input.value == 1, "typed seed remains pending before confirmation")
		seed_dialog.get_ok_button().pressed.emit()
		check(game.career.seed_value == seed_case[1] and game.status_label.text.contains("seed %d" % seed_case[1]), "OK submits the focused seed without Return using native bounds")
		check(game.career.scenario_id == "funding_stress" and game.career.shocks == game.career.model.seeded_shock_path(seed_case[1], game.career.cases.funding_stress, game.career.MAX_QUARTERS), "confirmed seed selects the actual reproducible shock path")
		check(seed_dialog.visible and seed_dialog.is_queued_for_deletion(), "seed submission retains the deferred accessibility window lifecycle")
		await process_frame
	var before_cancel: PackedByteArray = game.career.encode()
	var staged_before_cancel: Dictionary = game._policy()
	game._new_dialog()
	await process_frame
	var cancel_dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	game.seed_input.get_line_edit().grab_focus()
	game.seed_input.get_line_edit().text = "99"
	var cancel_button: Button
	for button in cancel_dialog.get_ok_button().get_parent().get_children():
		if button is Button and button.text == "Cancel":
			cancel_button = button
	cancel_button.pressed.emit()
	check(game.career.encode() == before_cancel and game._policy() == staged_before_cancel, "canceling a pending seed preserves the career and staged policy")
	# Deferred calls run before deletion. Cancel must not hide the embedded window
	# before an assistive action's deferred focus request completes.
	call_deferred("check_cancel_window", cancel_dialog)
	await process_frame
	game._help()
	await process_frame
	var help: AcceptDialog = game.get_child(game.get_child_count() - 1)
	var help_text: TextEdit = help.get_child(0)
	check(help_text.text.contains("Every career includes seeded background disturbances") and help_text.text.contains("baseline starts at equilibrium") and help_text.text.contains("no scheduled scenario events"), "help explains the seeded baseline and scheduled-event distinction")
	check(help_text.text.contains("same scenario and seed") and help_text.text.contains("same engine and model"), "help qualifies every input needed to reproduce the path")
	check(game.career.encode() == before_cancel and game._policy() == staged_before_cancel, "reading seeded help leaves the active career and staged policy unchanged")
	help.get_ok_button().pressed.emit()
	await process_frame
	game._credits()
	await process_frame
	var credits: AcceptDialog = game.get_child(game.get_child_count() - 1)
	var notices: TextEdit = credits.get_child(0)
	check(notices.text.contains(Engine.get_license_info()["FTL"]), "bundled component license is preserved verbatim")
	credits.get_ok_button().pressed.emit()
	await process_frame
	game.free()
	if failures == 0:
		print("PASS: exact rate display and UI adoption path")
	quit(1 if failures else 0)
