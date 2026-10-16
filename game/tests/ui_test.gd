extends SceneTree

class RecordingQuitMain:
	extends "res://play/main.gd"
	var exit_requests := 0
	func _quit_app(_exit_code := 0) -> void:
		exit_requests += 1

class RecordingReleaseCheck:
	extends "res://play/build_check.gd"
	func check(condition: bool, _message: String) -> void:
		checks += 1
		if not condition:
			failures += 1

class CorruptComparisonMain:
	extends "res://play/main.gd"
	var fragment := ""
	func _decision_briefing() -> String:
		if fragment == "headings only":
			return "GUIDANCE CONTINUATION / SELECTED HOLD VS PROMISE-FOLLOW\nQ+2 / A VS B\nB / Q+8 PROMISE-FOLLOW\nQ+8 / B MINUS A\n"
		return super._decision_briefing().replace(fragment, fragment + "9999 ")

class UnavailableContinuationCareer:
	extends "res://play/career.gd"
	var continuation_forecasts := 0
	var reject_reference := false

	func forecast(policy: Dictionary, follow_guidance: bool = false) -> Dictionary:
		if follow_guidance:
			continuation_forecasts += 1
		if follow_guidance or (reject_reference and policy.policy_rate_request_pct == state.policy_rate_pct):
			var invalid: Dictionary = policy.duplicate()
			invalid.guidance_rate_pct = NAN
			return super.forecast(invalid, follow_guidance)
		return super.forecast(policy)

class UnavailableReviewReferenceModel:
	extends "res://model/economy.gd"
	var rejected_kind := ""
	func benchmark_policy(state: Dictionary, params: Dictionary, kind: String = "feedback") -> Dictionary:
		var policy: Dictionary = super.benchmark_policy(state, params, kind)
		if kind == rejected_kind:
			policy.guidance_rate_pct = NAN
		return policy

var failures := 0
var checks := 0
var pending_review: Button
func _process(_delta: float) -> bool:
	if pending_review != null:
		var action := pending_review
		pending_review = null
		action.pressed.emit()
	return false
func check(condition: bool, message: String) -> void:
	checks += 1
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
		if method == "_help":
			var help_text: TextEdit = dialog.get_child(0)
			check(help_text.text.contains("R model benchmark") and help_text.text.contains("full-information") and help_text.text.contains("true neutral rate") and help_text.text.contains("short inflation expectations"), "help identifies the benchmark shortcut and its model-only information assumptions")
			check(help_text.text.contains("inflation reacts with a lag"), "help retains the inflation transmission lag explanation")
			check(help_text.text.contains("2% objective and portfolio reference observations are source-backed") and help_text.text.contains("behavioral coefficients, starting conditions and shock incidence are design assumptions") and not help_text.text.contains("Only the 2% objective"), "help distinguishes source-backed portfolio observations from assumed behavior")
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
func check_funding_outcome(game: Control) -> void:
	game._start_career("funding_stress", 1)
	for q in range(4):
		check(game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "feedback")).ok, "funding feedback setup reaches the real Q5 shock")
	game._refresh(true)
	game.liquidity.value = 10.0
	var before: Dictionary = game.career.state.duplicate(true)
	var policy: Dictionary = game._policy()
	var expected: Dictionary = game.career.model.step(before, policy, game.career.current_briefing(), game.career.params)
	game._advance()
	check(expected.ok and game.career.state == expected.state, "funding outcome copy preserves the exact adopted native state")
	check(not game.consequence.text.contains("Your earlier decisions remain in the transmission pipeline."), "quarterly outcome omits repeated pipeline boilerplate")
	var s: Dictionary = game.career.state
	var n: float = s.decision_nominal_gdp_ratio
	check(s.liquidity_applied_pct_initial_gdp > 0.0 and s.liquidity_applied_pct_initial_gdp < policy.liquidity_request_pct_initial_gdp and s.uncovered_funding_pct_initial_gdp == 0.0, "oversized offer fixture distinguishes requested and applied loans with zero uncovered funding")
	var expected_line := "Funding (%% meeting GDP): lent %.2f · uncovered %.2f · repaid %.2f." % [s.liquidity_applied_pct_initial_gdp / n, s.uncovered_funding_pct_initial_gdp / n, s.liquidity_repayment_pct_initial_gdp / n]
	check(game.consequence.text.contains(expected_line), "immediate funding outcome uses realized flows and meeting GDP")
	check("%.2f" % (s.liquidity_applied_pct_initial_gdp / n) != "%.2f" % s.liquidity_applied_pct_initial_gdp and "%.2f" % (s.liquidity_applied_pct_initial_gdp / n) != "%.2f" % (s.liquidity_applied_pct_initial_gdp / s.ending_nominal_gdp_ratio), "loan fixture distinguishes meeting, initial and ending GDP at displayed precision")
	check(game.liquidity.value == 0.0 and game.consequence.text.contains("Q5 OUTCOME") and game.consequence.text.contains("Previous promise follow-through") and game.consequence.accessibility_live == AccessibilityServer.LIVE_POLITE, "loan outcome retains offer reset, existing feedback and assistive announcements")
	var prior_loan: float = s.outstanding_liquidity_pct_initial_gdp
	game._advance()
	s = game.career.state
	n = s.decision_nominal_gdp_ratio
	check(s.liquidity_applied_pct_initial_gdp == 0.0 and s.liquidity_repayment_pct_initial_gdp == prior_loan and s.uncovered_funding_pct_initial_gdp > 0.0, "next real meeting repays prior short loans and retains new unmet need")
	expected_line = "Funding (%% meeting GDP): lent %.2f · uncovered %.2f · repaid %.2f." % [s.liquidity_applied_pct_initial_gdp / n, s.uncovered_funding_pct_initial_gdp / n, s.liquidity_repayment_pct_initial_gdp / n]
	check(game.consequence.text.contains(expected_line), "repayment feedback reports completed meeting rather than next preview")
	game._start_career("base", 1)
	game.career.shocks[0] = {}
	game._advance()
	s = game.career.state
	check(s.liquidity_applied_pct_initial_gdp == 0.0 and s.uncovered_funding_pct_initial_gdp == 0.0 and s.liquidity_repayment_pct_initial_gdp == 0.0, "explicit quiet fixture has no funding flows")
	check(not game.consequence.text.contains("Funding (") and game.consequence.text.contains("Q1 OUTCOME"), "zero-flow adoption omits an unnecessary funding line")

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
	check(game.has_method("_change_text"), "both outcome scores use one shared formatter")
	if game.has_method("_change_text"):
		var preserved: PackedByteArray = game.career.encode()
		for sample in [[0.0, "unchanged"], [-0.0, "unchanged"], [0.000001, "up <0.05 points"], [-0.000001, "down <0.05 points"], [0.049999, "up <0.05 points"], [-0.049999, "down <0.05 points"], [0.05, "+0.1 points"], [-0.05, "-0.1 points"], [1.25, "+1.2 points"], [-1.25, "-1.2 points"]]:
			check(game.call("_change_text", sample[0]) == sample[1], "score formatter preserves zero, small-change direction, precision threshold and signed points")
		for sample in [[0.0, "unchanged"], [-0.0, "unchanged"], [0.000001, "up <0.005 pp"], [-0.000001, "down <0.005 pp"], [0.004999, "up <0.005 pp"], [-0.004999, "down <0.005 pp"], [0.005, "+0.01 pp"], [-0.005, "-0.01 pp"], [1.23, "+1.23 pp"], [-1.23, "-1.23 pp"]]:
			check(game.call("_change_text", sample[0], 2, "pp") == sample[1], "macro formatter preserves zero, direction, two-decimal threshold and percentage-point units")
		for sample in [[0.0, "unchanged"], [-0.0, "unchanged"], [0.000001, "up <0.0005 pp"], [-0.000001, "down <0.0005 pp"], [0.0004999, "up <0.0005 pp"], [-0.0004999, "down <0.0005 pp"], [0.0005, "+0.001 pp"], [-0.0005, "-0.001 pp"], [1.234, "+1.234 pp"], [-1.234, "-1.234 pp"]]:
			check(game.call("_change_text", sample[0], 3, "pp") == sample[1], "forecast formatter preserves zero, direction, three-decimal threshold and percentage-point units")
		check(game.call("_change_text", -0.000001, 2) == "down <0.005 points" and game.call("_change_text", 1.23, 2) == "+1.23 points", "forecast score precision retains score-point units")
		check(game.career.encode() == preserved, "formatting score changes cannot change the career")
	game._start_career("supply_shock", 1)
func expected_change(change: float, decimals: int, unit: String) -> String:
	if change == 0:
		return "unchanged"
	var bounds := {1: 0.05, 2: 0.005, 3: 0.0005}
	var labels := {1: "0.05", 2: "0.005", 3: "0.0005"}
	var formats := {1: "%+.1f", 2: "%+.2f", 3: "%+.3f"}
	if abs(change) < bounds[decimals]:
		return ("up" if change > 0 else "down") + " <" + labels[decimals] + " " + unit
	return (formats[decimals] % change) + " " + unit
func check_change_precision(game: Control) -> void:
	game._start_career("funding_stress", 42)
	for quarter in [1, 2]:
		game.rate.value = 8.0
		game.guidance.value = 8.0
		game.assets.value = 1.25
		game.liquidity.value = 5.0
		var before: Dictionary = game.career.state.duplicate(true)
		var expected: Dictionary = game.career.model.step(before, game._policy(), game.career.current_briefing(), game.career.params)
		game._advance()
		check(expected.ok and game.career.state == expected.state and game.career.state.quarter_index == quarter, "change precision preserves each real Funding42 adopted state")
		var pi_change: float = game.career.state.four_quarter_inflation_pct - before.four_quarter_inflation_pct
		var unemployment_change: float = game.career.state.unemployment_rate_pct - before.unemployment_rate_pct
		check(game.consequence.text.contains("Inflation " + expected_change(pi_change, 2, "pp") + "; unemployment " + expected_change(unemployment_change, 2, "pp")), "real macro outcomes disclose direction and bounds instead of rounded zero")
		if quarter == 2:
			check(pi_change < 0 and abs(pi_change) < 0.005, "actual Funding42 Q2 exercises a negative subprecision inflation move")
	var preserved: PackedByteArray = game.career.encode()
	var report: String = game._decision_briefing()
	var selected: Dictionary = game.career.forecast(game._policy())
	var held: Dictionary = game.career.forecast(game.career.model.benchmark_policy(game.career.state, game.career.params, "hold"))
	for index in [0, 3, 7]:
		var choice: Dictionary = selected.states[index]
		var baseline: Dictionary = held.states[index]
		var row := "Q+%d: Inflation %s · unemployment %s\nOutput gap %s" % [index + 1, expected_change(choice.four_quarter_inflation_pct - baseline.four_quarter_inflation_pct, 3, "pp"), expected_change(choice.unemployment_rate_pct - baseline.unemployment_rate_pct, 3, "pp"), expected_change(choice.output_gap_pct - baseline.output_gap_pct, 3, "pp")]
		check(report.contains(row), "paired forecast differences preserve real direction, precision and units")
	check(game.career.encode() == preserved, "formatted comparisons preserve every career byte")
	game._start_career("supply_shock", 1)
	var neutral_report: String = game._decision_briefing()
	check(neutral_report.count("Q+1 long yield unchanged; credit spread unchanged") == 4 and neutral_report.count("Q+8 inflation unchanged; unemployment unchanged; credibility unchanged; support unchanged") == 4, "exactly unused tools say unchanged rather than imply a signed effect")
func check_persistent_actions(game: Control) -> void:
	var actions: Array[Button] = []
	for button in game.find_children("*", "Button", true, false):
		if button.text in ["Compare policy paths", "Adopt decision  →  Next quarter"]:
			actions.append(button)
			var ancestor: Node = button.get_parent()
			while ancestor != game:
				check(ancestor != game.cockpit_scroll, "policy actions remain outside the scrolling cockpit")
				ancestor = ancestor.get_parent()
	check(actions.size() == 2, "comparison and adoption each have one action")
	for feedback in [game.status_label, game.consequence]:
		var feedback_ancestor: Node = feedback.get_parent()
		while feedback_ancestor != game:
			check(feedback_ancestor != game.cockpit_scroll, "career status and economic outcome remain outside the scrolling cockpit")
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
		check(game.overflow_scroll.get_v_scroll_bar().max_value <= game.overflow_scroll.get_v_scroll_bar().page + 0.5 and game.overflow_scroll.get_h_scroll_bar().max_value <= game.overflow_scroll.get_h_scroll_bar().page + 0.5, "normal and expanded-guidance layouts genuinely pin actions and feedback without any whole-content overflow")
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
	check_terminal_cockpit(game, "final adoption")
	var preserved: PackedByteArray = game.career.encode()
	check(game.career.restore(bytes_to_var(preserved)).ok, "completed career restores through real replay")
	game._refresh(true)
	check(game.quarter_label.text == "CAREER COMPLETE · 240 MEETINGS" and game.decision_button.disabled, "restored completion uses the same shared refresh")
	check_terminal_cockpit(game, "replay restore")
	var terminal_report: String = game._decision_briefing()
	check(terminal_report.contains("CURRENT MEETING / REQUESTED AND APPLIED") and game.career.encode() == preserved, "terminal comparison remains available without changing completed history")
	check(terminal_report.contains("Beyond Q240: diagnostic continuation only, not extra playable turns."), "continuation beyond retirement cannot advertise extra playable meetings")
	check(terminal_report.begins_with("CAREER COMPLETE / DIAGNOSTIC COMPARISON\n"), "terminal comparison labels its entire continuation as diagnostic")
	game.rate.get_line_edit().text = "9.25"
	var pending: String = game.rate.get_line_edit().text
	var numeric: float = game.rate.value
	game._preview()
	game._refresh()
	game._compare()
	await process_frame
	await process_frame
	check(game.rate.get_line_edit().text == pending and game.rate.value == numeric and game.career.encode() == preserved, "terminal preview, refresh and comparison preserve pending edits and completed career bytes")
	var comparison: AcceptDialog = game.get_child(game.get_child_count() - 1)
	comparison.get_ok_button().pressed.emit()
	await process_frame
	game._start_career("supply_shock", 1)
	check(game.quarter_label.text == "YEAR 01 / Q1   ·   MEETING 1" and not game.decision_button.disabled and game.decision_button.text == "Adopt decision  →  Next quarter", "new career restores ordinary meeting and action labels")
func check_terminal_cockpit(game: Control, context: String) -> void:
	check(game.briefing.text.begins_with("Career complete at Q240.") and not game.briefing.text.contains("Demand impulse") and not game.briefing.text.contains("Funding need"), context + " replaces phantom meeting inputs with completed-career context")
	check(game.forecast_label.text.begins_with("CAREER COMPLETE\n") and not game.forecast_label.text.contains("APPLIED NOW") and not game.forecast_label.text.contains("CONDITIONAL Q+8"), context + " suppresses the nonexistent playable forecast")

func check_backaudit_readouts(game: Control) -> void:
	var premiums: Array[float] = []
	for flow in [4.0, -4.0]:
		game._start_career("base", 417)
		var initial_premium: float = game.career.state.term_premium_pct
		game.assets.value = flow
		game._advance()
		check(game.career.state.quarter_index == 1, "matched purchase/runoff fixture adopts one actual quarter")
		var current: Dictionary = game.career.state
		var holdings := "Holdings %.1f%%" % (current.asset_stock_pct_initial_gdp / game.career.model.nominal_gdp_ratio(current))
		check(game.case_detail.text.contains(holdings + " · Term premium %+.3f pp" % current.term_premium_pct), "purchase/runoff displays the actual current term premium beside holdings")
		premiums.append(current.term_premium_pct)
		check(current.term_premium_pct < initial_premium if flow > 0.0 else current.term_premium_pct > initial_premium, "matched purchases lower and runoff raises the separately displayed term premium")
	check(premiums[0] < premiums[1], "matched purchase/runoff produces distinguishable term-premium values")
	game._start_career("base", 417)
	var initial: Dictionary = game.career.model.initial_state(game.career.params, {"annualized_quarterly_inflation_pct": 1.0, "expected_short_inflation_pct": 1.0, "expected_long_inflation_pct": 1.0})
	check(initial.ok, "below-target positive-inflation fixture uses validated model initialization")
	if initial.ok:
		game.career.state = initial.state
		game.career.history = [initial.state.duplicate(true)]
		game._refresh(true)
		var selected: Dictionary = game.career.forecast(game._policy())
		check(selected.ok, "positive below-target inflation has a valid native forecast")
		if selected.ok:
			var first: Dictionary = selected.states[0]
			check(first.four_quarter_inflation_pct > 0.0 and first.four_quarter_inflation_pct < game.career.params.inflation_target_pct, "hardship explanation fixture remains positive and below target")
			var burden: float = game.career.params.public_inflation_burden_weight * abs(first.four_quarter_inflation_pct - game.career.params.inflation_target_pct)
			var employment: float = game.career.params.public_unemployment_burden_weight * maxf(0.0, first.unemployment_rate_pct - first.structural_unemployment_pct)
			check(burden > 0.0 and abs(first.current_hardship - burden - employment) < 1e-10, "below-target positive inflation contributes target-distance hardship, not deflation")
			var report: String = game._decision_briefing()
			check(report.contains("Absolute inflation distance from the %.2f%% target (including below-target positive inflation)" % game.career.params.inflation_target_pct) and report.contains("Current hardship %.3f" % first.current_hardship), "comparison explains absolute target distance beside the actual hardship calculation")

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
	game._start_career("mixed_crises", 417)
	check(not game.briefing.text.contains("EXOGENOUS /"), "initial cockpit cannot reveal the upcoming curated event")
	while game.career.current_shock_episode().is_empty() and game.career.decisions.size() < 24:
		game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params))
	game._refresh(true)
	var episode: Dictionary = game.career.current_shock_episode()
	check(not episode.is_empty() and game.briefing.text.contains("EXOGENOUS / %s · %s" % [episode.get("title", "missing"), episode.get("policy_dilemma", "missing")]), "actual cockpit refresh names the known event and concise policy dilemma")
	check(not game.briefing.text.contains("shock_profile") and not game.briefing.text.contains("duration_quarters"), "event readout omits hidden future metadata")
	game._start_career("supply_shock", 1)

func check_current_signals_ui(game: Control) -> void:
	check(game.briefing.mouse_filter == Control.MOUSE_FILTER_PASS and not game.briefing.tooltip_text.is_empty(), "current signal explanation accepts immediate tooltip hover")
	game._start_career("base", 17)
	game.career.shocks[0] = {}
	game._refresh()
	check(not game.briefing.text.contains("Requested refinancing") and not game.briefing.text.contains("Current impairment impulse"), "quiet current dispatch omits zero-only funding and impairment rows")
	game._start_career("base", 17)
	game.career.shocks[0] = {"funding_need_pct_initial_gdp": 2.0, "eligible_collateral_pct_initial_gdp": 4.0, "liquidity_eligibility_pct": 100.0}
	var choice: Dictionary = game.career.model.benchmark_policy(game.career.state, game.career.params, "hold")
	choice.liquidity_request_pct_initial_gdp = 2.0
	check(game.career.advance(choice).ok and game.career.state.outstanding_liquidity_pct_initial_gdp == 2.0, "current UI fixture creates actual maturing principal")
	game.career.shocks[1] = {"refinancing_need_pct_initial_gdp": 6.0, "eligible_collateral_pct_initial_gdp": 2.0, "collateral_haircut_pct": 50.0, "liquidity_eligibility_pct": 50.0, "solvency_risk_innovation_pct": 0.7}
	var n: float = game.career.model.nominal_gdp_ratio(game.career.state)
	check(n != 1.0, "current signal fixture distinguishes current GDP from initial GDP")
	var preserved: PackedByteArray = game.career.encode()
	var state_bytes := var_to_bytes(game.career.state)
	var history_bytes := var_to_bytes(game.career.history)
	game._refresh(true)
	check(game.career.encode() == preserved and var_to_bytes(game.career.state) == state_bytes and var_to_bytes(game.career.history) == history_bytes, "current dispatch refresh preserves every career/state/history byte")
	for reading in ["Funding need 0.00", "Requested refinancing %.2f" % (6.0 / n), "Maturing principal %.2f" % (2.0 / n), "Refinancing need %.2f" % (2.0 / n), "Lending value %.2f" % (0.5 / n), "Collateral haircut 50.00%", "Eligibility 50.00%", "Current impairment impulse +0.70 pp", "Prior impairment 0.00 pp"]:
		check(game.briefing.text.contains(reading), "current dispatch discloses " + reading)
	check(game.briefing.text.contains("% current GDP") and game.briefing.text.to_lower().contains("spread proxy"), "funding flows use current GDP while impairment is a pp spread proxy")
	game.liquidity.value = 5.0
	game._preview()
	check(game.career.encode() == preserved and var_to_bytes(game.career.state) == state_bytes and var_to_bytes(game.career.history) == history_bytes, "current-signal UI preview preserves every career/state/history byte")
	var report: String = game._decision_briefing()
	check(report.contains("Loan principal repaid %.2f; refinancing %.2f; new local lending 0.00" % [2.0 / n, 0.5 / n]), "comparison shows principal repaid and haircut/eligibility-constrained refinancing, not the raw request")
	check(game.career.encode() == preserved and var_to_bytes(game.career.state) == state_bytes and var_to_bytes(game.career.history) == history_bytes, "current-signal comparison preserves every career/state/history byte")
	var dispatch: String = game.briefing.text
	var preview: String = game.forecast_label.text
	game.career.shocks[200] = {"funding_need_pct_initial_gdp": 9.0, "refinancing_need_pct_initial_gdp": 9.0, "solvency_risk_innovation_pct": 5.0, "collateral_haircut_pct": 99.0, "liquidity_eligibility_pct": 0.0}
	preserved = game.career.encode()
	game._refresh()
	check(game.briefing.text == dispatch and game.forecast_label.text == preview and game.career.encode() == preserved and var_to_bytes(game.career.state) == state_bytes and var_to_bytes(game.career.history) == history_bytes, "future funding/refinancing/impairment edits cannot change or be mutated by dispatch, preview or current state")
	check(game._decision_briefing() == report and game.career.encode() == preserved and var_to_bytes(game.career.state) == state_bytes and var_to_bytes(game.career.history) == history_bytes, "comparison cannot inspect future current-risk inputs or mutate their bytes")
	game._start_career("base", 17)
	game.career.shocks[0] = {"solvency_risk_innovation_pct": 1.25}
	preserved = game.career.encode()
	state_bytes = var_to_bytes(game.career.state)
	history_bytes = var_to_bytes(game.career.history)
	game._refresh()
	check(game.briefing.text.contains("Current impairment impulse +1.25 pp") and game.briefing.text.contains("Prior impairment 0.00 pp") and not game.briefing.text.contains("Funding aftermath"), "first-quarter impairment is disclosed before any settled impairment exists")
	check(game.career.encode() == preserved and var_to_bytes(game.career.state) == state_bytes and var_to_bytes(game.career.history) == history_bytes, "first-quarter impairment readout preserves every career/state/history byte")
	check(game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "hold")).ok, "UI impairment fixture settles through real adoption")
	game.career.shocks[1] = {}
	preserved = game.career.encode()
	state_bytes = var_to_bytes(game.career.state)
	history_bytes = var_to_bytes(game.career.history)
	game._refresh()
	check(game.briefing.text.contains("Current impairment impulse +0.00 pp") and game.briefing.text.contains("Prior impairment 1.25 pp") and game.briefing.text.contains("credit impairment remains"), "settled spread proxy is not mislabeled as a new impairment impulse")
	check(game.career.encode() == preserved and var_to_bytes(game.career.state) == state_bytes and var_to_bytes(game.career.history) == history_bytes, "settled impairment readout preserves every career/state/history byte")
	game._start_career("supply_shock", 1)

func check_unrestricted_rate_controls(game: Control) -> void:
	var preserved: PackedByteArray = game.career.encode()
	var original: Dictionary = game._policy()
	check(game.rate.allow_lesser and game.rate.allow_greater and game.guidance.allow_lesser and game.guidance.allow_greater, "native nominal controls allow signed values beyond former bounds")
	check(game.rate.step == 0.01 and game.rate.custom_arrow_step == 0.25 and game.guidance.step == 0.01 and game.guidance.custom_arrow_step == 0.25, "native controls retain1bp typed precision and25bp arrow convenience")
	for quote in [-0.5, 25.0]:
		game.rate.value = quote
		game.guidance.value = quote
		check(game.rate.value == quote and game.guidance.value == quote, "native controls do not clamp signed or large nominal quotes")
		var preview: Dictionary = game.career.forecast(game._policy())
		check(preview.ok and preview.states[0].policy_rate_pct == quote, "actual UI policy and forecast apply the full nominal choice")
		game._preview()
		if quote < 0.0:
			check(game.forecast_label.text.contains("Rate -0.50% (effective -0.46%)"), "main preview distinguishes negative nominal choice from effective financing transmission")
		else:
			check(not game.forecast_label.text.contains("effective"), "unchanged positive transmission adds no duplicate metric to the cockpit")
	game.rate.value = original.policy_rate_request_pct
	game.guidance.value = original.guidance_rate_pct
	check(game.career.encode() == preserved and game._policy() == original, "native quote inspection restores controls without mutating the career")

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
	var promise: float = game.career.model.conditional_commitment(s, game.career.params)
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
	var benchmark_buttons: Array = game.keyboard_controls.filter(func(control): return control is Button and control.text == "Stage model benchmark")
	check(benchmark_buttons.size() == 1, "the action names a staged model benchmark rather than operational staff advice")
	if benchmark_buttons.size() == 1:
		check(benchmark_buttons[0].tooltip_text.contains("full-information") and benchmark_buttons[0].tooltip_text.contains("true neutral rate") and benchmark_buttons[0].tooltip_text.contains("short inflation expectations"), "benchmark tooltip exposes the exact hidden inputs without adding dashboard prose")
		check(benchmark_buttons[0].accessibility_description == benchmark_buttons[0].tooltip_text, "native assistive help exposes the same benchmark assumptions as its tooltip")
	check(game.status_label.text.contains("Full-information benchmark staged"), "keyboard and pointer staging feedback disclose the full-information assumption")
	check(game.commitment.selected == 0 and game.assets.value == 1.25 and game.liquidity.value == 2.0, "staff selection restores its guidance rule without changing other tools")
	game._start_career("base", 417)
	check(game.commitment.selected == 0 and game.inflation_response.value == game.career.params.policy_inflation_response, "new career restores known guidance defaults")
	game.commitment.select(1)
	game.commitment.item_selected.emit(1)
	game.guidance.value = 15.0
	game._advance()
	var pledge_report: String = game._decision_briefing()
	check(pledge_report.contains("Adjusted prior promise 15.000%") and pledge_report.contains("Projected follow-through 0.0 / 100"), "comparison discloses a genuinely broken nominal pledge")
	game.rate.value = 15.0
	check(game._decision_briefing().contains("Projected follow-through 100.0 / 100"), "any on-grid nominal pledge can be delivered without a ramp cap")
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
				var report: TextEdit = comparison.find_children("*", "TextEdit", true, false)[0]
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
			var report: TextEdit = dialog.find_children("*", "TextEdit", true, false)[0]
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
func review_staff_snapshot(game: Control) -> PackedByteArray:
	var inputs: Array = []
	for field in [game.rate, game.guidance, game.assets, game.liquidity, game.inflation_response, game.activity_response]:
		inputs.append([field.value, field.get_line_edit().text])
	return var_to_bytes([game.career.encode(), game.career.state, game.career.history, game.career.decisions, game.career.shocks, game.career._seeded_shocks, game.career.episodes, game.career.params, game._policy(), game.commitment.selected, inputs, game.forecast_label.text])
func check_review_staff_metrics(body: TextEdit, compared: Dictionary) -> void:
	var summaries: Array = [compared.get("actual", {}), compared.get("held", {})]
	var staff: Dictionary = compared.get("staff", {})
	if not staff.is_empty():
		summaries.append(staff)
	var number := RegEx.new()
	number.compile("[-+]?[0-9]+\\.[0-9]+")
	for metric in [["Avg inflation distance", "inflation_miss", "%.3f", "pp", 1.0],
		["Avg employment shortfall", "employment_shortfall", "%.3f", "pp", 1.0],
		["Avg uncovered funding", "uncovered_funding", "%.3f", "% meeting GDP", 1.0],
		["Ending credibility", "credibility", "%.1f", "/ 100", 100.0],
		["Ending public support", "public_support", "%.1f", "/ 100", 1.0]]:
		var rows: PackedStringArray = []
		for line in body.text.split("\n"):
			if line.begins_with(metric[0] + ":"):
				rows.append(line)
		check(rows.size() == 1, "realized review exposes one numeric " + metric[0] + " row")
		if rows.size() != 1:
			continue
		check(rows[0].contains(metric[3]), "realized review labels " + metric[0] + " units")
		var values := number.search_all(rows[0])
		check(values.size() == summaries.size(), "realized review has exactly one value per available reference for " + metric[0])
		for index in range(mini(values.size(), summaries.size())):
			check(summaries[index].has(metric[1]), "available review summary includes " + metric[1])
			if summaries[index].has(metric[1]):
				check(values[index].get_string() == metric[2] % (metric[4] * summaries[index][metric[1]]), "realized review prints actual, hold, then staff values for " + metric[0])
func check_review_staff_dialog(game: Control) -> void:
	for funding in [false, true]:
		game._start_career("base" if funding else "unanchored_inflation", 41)
		for q in range(4 if funding else 12):
			var policy: Dictionary = game.career.model.benchmark_policy(game.career.state, game.career.params, "feedback")
			if funding:
				game.career.shocks[q] = {"funding_need_pct_initial_gdp": 2.0, "eligible_collateral_pct_initial_gdp": 4.0, "liquidity_eligibility_pct": 100.0, "potential_growth_pct": 20.0}
				policy.liquidity_request_pct_initial_gdp = 1.0
			var advanced: Dictionary = game.career.advance(policy)
			check(advanced.ok, "staff review fixture commits a real completed policy")
			if not advanced.ok:
				return
		game._refresh(true)
		game.rate.value += 0.25
		game.assets.value = 0.75
		game.liquidity.value = 0.5
		await process_frame
		await process_frame
		var preserved := review_staff_snapshot(game)
		var compared: Dictionary = game.career.review_comparison()
		check(compared.get("ok", false), "completed policy retains its usable realized comparison")
		if not compared.get("ok", false):
			return
		var staff: Dictionary = compared.get("staff", {})
		check(not staff.is_empty(), "realized comparison includes the completed-history staff reference")
		if not funding:
			check(not staff.is_empty() and compared.get("actual", {}) == staff, "staff-only actual play equals the staff reference without requiring it to beat hold")
		elif not staff.is_empty() and staff.has("uncovered_funding") and compared.actual.has("uncovered_funding"):
			var uncovered := 0.0
			for state in game.career.history.slice(1):
				uncovered += state.uncovered_funding_pct_initial_gdp / state.decision_nominal_gdp_ratio / game.career.decisions.size()
			check(compared.actual.uncovered_funding == uncovered and uncovered < staff.uncovered_funding, "eligible actual lending exposes less uncovered funding than the no-loan staff reference in meeting-GDP units")
			check(not is_equal_approx(uncovered, 1.0), "funding fixture distinguishes meeting GDP from initial GDP")
		game.rate.get_line_edit().grab_focus()
		game._review()
		var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
		await check_report_body(dialog, ["Your policy / Hold / Model benchmark", "Avg inflation distance", "Avg employment shortfall", "Avg uncovered funding", "Ending credibility", "Ending public support"])
		var bodies := dialog.find_children("*", "TextEdit", true, false)
		if bodies.size() == 1:
			var body: TextEdit = bodies[0]
			check_review_staff_metrics(body, compared)
			check(dialog.title == "Your %d-quarter policy review" % game.career.decisions.size() and body.text.contains("REALIZED PATHS / Q1–Q%d" % game.career.decisions.size()), "realized staff review labels the completed interval, not a future horizon")
			check(body.text.contains("your actual Q0 state") and body.text.contains("already occurred"), "all realized references disclose their matched starting state and completed shocks")
			check(body.text.contains("full-information") and body.text.contains("true neutral rate") and body.text.contains("short inflation expectations") and body.text.to_lower().contains("feedback") and body.text.contains("data dependence"), "benchmark reference discloses its hidden inputs, feedback rate and data-dependent guidance")
			check(body.text.contains("holds %.2f%%" % compared.hold_rate) and body.text.contains("no new asset flows or loans"), "hold and staff references disclose passive discretionary tools")
			check(body.text.contains("Default reinvestment and reserve maintenance stay on; sterilization stays off") and body.text.contains("Principal and short-loan repayments still settle"), "realized references disclose default switches and settlement timing")
			check(body.text.contains("not a forecast or proof of optimal policy"), "realized staff comparison makes no forecast or optimality claim")
		check(review_staff_snapshot(game) == preserved, "calculating and navigating the staff review preserves state, history, shocks, parameters, save bytes and staged inputs")
		dialog.get_ok_button().pressed.emit()
		check(dialog.visible and dialog.is_queued_for_deletion(), "staff review OK preserves the deferred native accessibility window lifecycle")
		await process_frame
		await process_frame
		check(not is_instance_valid(dialog) and game.rate.get_line_edit().has_focus(), "closing staff review restores the original cockpit keyboard focus")
		check(review_staff_snapshot(game) == preserved, "closing staff review cannot adopt or replace the staged policy")

	var available: Dictionary = game.career.review_comparison()
	var original_model = game.career.model
	var rejecting := UnavailableReviewReferenceModel.new()
	game.career.model = rejecting
	rejecting.rejected_kind = "feedback"
	var invalid: Dictionary = original_model.benchmark_policy(game.career.history[0], game.career.params, "feedback")
	invalid.guidance_rate_pct = NAN
	var rejected: Dictionary = original_model.step(game.career.history[0], invalid, game.career.shocks[0], game.career.params)
	check(not rejected.ok, "staff-only failure fixture uses the native nonfinite-policy rejection")
	var failure_preserved := review_staff_snapshot(game)
	var unavailable: Dictionary = game.career.review_comparison()
	var expected_error: String = "Staff reference unavailable: " + rejected.get("error", "")
	check(unavailable.get("ok", false) and unavailable.get("staff", {}) == {} and unavailable.get("staff_error", "") == expected_error, "staff-only rejection retains usable actual/hold summaries and its exact prefixed native error")
	check(unavailable.get("actual", {}) == available.get("actual", {}) and unavailable.get("held", {}) == available.get("held", {}), "staff-only failure preserves every usable actual/hold summary value")
	game._review()
	var failure_dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	await check_report_body(failure_dialog, ["Your policy / Hold", expected_error])
	var failure_bodies := failure_dialog.find_children("*", "TextEdit", true, false)
	if failure_bodies.size() == 1:
		check_review_staff_metrics(failure_bodies[0], unavailable)
		check(not failure_bodies[0].text.begins_with(expected_error), "unavailable staff does not replace the usable realized metrics with an error-only report")
	failure_dialog.canceled.emit()
	check(failure_dialog.visible and failure_dialog.is_queued_for_deletion(), "unavailable staff review cancellation preserves its native window until deferred deletion")
	call_deferred("check_cancel_window", failure_dialog)
	await process_frame
	check(review_staff_snapshot(game) == failure_preserved, "staff reference failure and native cancellation preserve live career and pending controls")
	rejecting.rejected_kind = "hold"
	var hold_error: String = "Hold reference unavailable: " + rejected.get("error", "")
	check(game.career.review_comparison() == {"ok": false, "error": hold_error}, "hold reference failure retains its original early rejection")
	game._review()
	failure_dialog = game.get_child(game.get_child_count() - 1)
	await check_report_body(failure_dialog, [hold_error])
	failure_bodies = failure_dialog.find_children("*", "TextEdit", true, false)
	if failure_bodies.size() == 1:
		check(failure_dialog.title == "Policy review" and failure_bodies[0].text == hold_error, "hold failure preserves the original explicit error dialog")
	failure_dialog.get_ok_button().pressed.emit()
	await process_frame
	check(review_staff_snapshot(game) == failure_preserved, "hold failure cannot mutate the career or staged inputs")
	game.career.model = original_model
	game._start_career("supply_shock", 1)
func activate_comparison_section(chooser: OptionButton, index: int) -> void:
	chooser.show_popup()
	await process_frame
	await process_frame
	check(chooser.get_popup().visible, "section activation opens the actual native popup")
	chooser.get_popup().set_focused_item(index)
	await quit_key(chooser.get_popup(), KEY_ENTER)
	check(chooser.selected == index and not chooser.get_popup().visible, "native popup Return activates the requested section")

func check_comparison_navigation(game: Control) -> void:
	var destinations := [["Meeting", "CURRENT MEETING /"], ["Deliberation", "COMMITTEE DELIBERATION /"], ["Guidance", "GUIDANCE /"], ["Guidance continuation", "GUIDANCE CONTINUATION /"], ["Scores", "Q+1 / WHY"], ["Forecasts", "CURRENT TRANSMISSION /"], ["Tools", "ONE-CONTROL CONTRASTS /"], ["Limits", "REFERENCE AND LIMITS"]]
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
		var bodies := dialog.find_children("*", "TextEdit", true, false)
		check(choosers.size() == 1 and bodies.size() == 1, "comparison provides native section navigation and a selectable complete report")
		if choosers.size() == 1 and bodies.size() == 1:
			var chooser: OptionButton = choosers[0]
			var body: TextEdit = bodies[0]
			check(body.text == expected and body.accessibility_description == expected, "section navigation preserves every report byte and warning")
			check(body.selecting_enabled and not body.editable and body.focus_mode == Control.FOCUS_ALL, "comparison report supports read-only native text selection and keyboard focus")
			check(chooser.accessibility_name == "Comparison section" and chooser.item_count == destinations.size(), "section chooser has a distinct accessible name and all eight destinations")
			for index in range(mini(chooser.item_count, destinations.size())):
				check(chooser.get_item_text(index) == destinations[index][0], "comparison sections retain their named order")
				var paragraph := expected.substr(0, expected.find(destinations[index][1])).count("\n")
				await activate_comparison_section(chooser, index)
				await process_frame
				check(body.get_line(paragraph).begins_with(destinations[index][1]) and paragraph >= body.get_first_visible_line() and paragraph <= body.get_last_full_visible_line(), "selecting %s brings its actual heading into view" % destinations[index][0])
				check(chooser.get_global_rect().end.y <= body.get_global_rect().position.y and chooser.is_visible_in_tree(), "section navigation remains above the scrolling report")
			check(game.career.encode() == preserved and game._policy() == staged, "section changes cannot mutate the career or staged decision")
			body.select_all()
			check(body.get_selected_text() == expected, "the full comparison remains available to native selection")
			body.deselect()
			await activate_comparison_section(chooser, 0)
			body.grab_focus()
			var page_down := InputEventKey.new()
			page_down.keycode = KEY_PAGEDOWN
			page_down.pressed = true
			dialog.push_input(page_down)
			await process_frame
			check(body.has_focus() and body.get_v_scroll_bar().value > 0, "comparison retains native keyboard scrolling after a section jump")
			await activate_comparison_section(chooser, 0)
			check(body.get_first_visible_line() == 0, "reselecting the already-selected Meeting through native popup input restores its heading after independent scrolling")
			body.grab_focus()
			var tab := InputEventKey.new()
			tab.keycode = KEY_TAB
			tab.pressed = true
			dialog.push_input(tab)
			await process_frame
			check(not body.has_focus(), "Tab leaves the complete comparison body")
		dialog.get_ok_button().pressed.emit()
		check(dialog.visible and dialog.is_queued_for_deletion(), "comparison navigation preserves deferred accessibility closing")
		await process_frame
		game._compare()
		await process_frame
		await process_frame
		var reopened: AcceptDialog = game.get_child(game.get_child_count() - 1)
		var reset_bodies := reopened.find_children("*", "TextEdit", true, false)
		if reset_bodies.size() == 1:
			check(reset_bodies[0].get_v_scroll_bar().value == 0, "reopening comparison starts at the meeting rather than a stale section")
		reopened.get_ok_button().pressed.emit()
		await process_frame
		check(game.career.encode() == preserved and game._policy() == staged, "closing and reopening comparison preserves the unsaved decision")
	game._start_career("supply_shock", 1)
func check_guidance_continuation(game: Control) -> void:
	var heading := "GUIDANCE CONTINUATION / SELECTED HOLD VS PROMISE-FOLLOW"
	for sample in [[3.5, 4.5, 0.0, 0.0], [-2.0, -4.0, 0.7, -0.25]]:
		game._start_career("base", 417)
		game.career.shocks[0] = {"demand_shock_pct": 1.2}
		game.rate.value = sample[0]
		game.guidance.value = sample[1]
		game.commitment.select(2)
		game.commitment.item_selected.emit(2)
		game.inflation_response.value = sample[2]
		game.activity_response.value = sample[3]
		game.reinvestment.button_pressed = false
		game.reserve_maintenance.button_pressed = false
		game.sterilization.button_pressed = true
		var staged: Dictionary = game._policy()
		var selected: Dictionary = game.career.forecast(staged)
		var held: Dictionary = game.career.forecast(game.career.model.benchmark_policy(game.career.state, game.career.params, "hold"))
		var following: Dictionary = game.career.forecast(staged, true)
		check(selected.ok and held.ok and following.ok, "continuation report setup uses valid real forecasts")
		if not selected.ok or not held.ok or not following.ok:
			continue
		check(var_to_bytes(selected.states[0]) == var_to_bytes(following.states[0]), "promise-follow has the identical current decision and no immediate credibility bonus")
		var preserved: PackedByteArray = var_to_bytes([game.career.encode(), game.career.state, game.career.history, staged, selected, held, following])
		var report: String = game._decision_briefing()
		check(report.find(heading) > report.find("GUIDANCE / COMMITMENT") and report.find(heading) < report.find("Q+1 / WHY"), "continuation sits between guidance and existing score diagnostics")
		var a: Dictionary = selected.states[1]
		var b: Dictionary = following.states[1]
		if sample[0] > 0:
			check(a.policy_rate_pct == 3.5 and b.policy_rate_pct == 4.5 and b.guidance_followthrough_score == 1.0, "firm continuation displays delivery instead of silently holding the selected rate")
		else:
			check(b.policy_rate_pct < 0 and b.effective_policy_rate_pct > b.policy_rate_pct, "signed continuation distinguishes the nominal promise from diminishing effective transmission")
		check(report.contains("Q+2 / A VS B\nNominal rate %.2f%% vs %.2f%%\nEffective borrowing rate %.3f%% vs %.3f%%\nPromise follow-through %.1f vs %.1f / 100\nStance adequacy %.1f vs %.1f / 100" % [a.policy_rate_pct, b.policy_rate_pct, a.effective_policy_rate_pct, b.effective_policy_rate_pct, 100 * a.guidance_followthrough_score, 100 * b.guidance_followthrough_score, 100 * a.stance_adequacy_score, 100 * b.stance_adequacy_score]), "first continuation meeting uses paired nominal, effective, delivery and stance values")
		a = selected.states[7]
		b = following.states[7]
		check(report.contains("Q+8 / A VS B\nNominal rate %.2f%% vs %.2f%%\nEffective borrowing rate %.3f%% vs %.3f%%" % [a.policy_rate_pct, b.policy_rate_pct, a.effective_policy_rate_pct, b.effective_policy_rate_pct]), "eighth-quarter nominal and effective rates remain separately labelled")
		check(report.contains("B / Q+8 PROMISE-FOLLOW\nInflation %.3f%%; unemployment %.3f%%; output gap %+.3f%%\nCredibility %.1f / 100; public support %.1f / 100" % [b.four_quarter_inflation_pct, b.unemployment_rate_pct, b.output_gap_pct, 100 * b.credibility, b.public_support]), "promise-follow outcomes come from the actual eighth-quarter state")
		check(report.contains("Q+8 / B MINUS A\nInflation %s; unemployment %s\nOutput gap %s; credibility %s; support %s" % [expected_change(b.four_quarter_inflation_pct - a.four_quarter_inflation_pct, 3, "pp"), expected_change(b.unemployment_rate_pct - a.unemployment_rate_pct, 3, "pp"), expected_change(b.output_gap_pct - a.output_gap_pct, 3, "pp"), expected_change(100 * (b.credibility - a.credibility), 2, "points"), expected_change(b.public_support - a.public_support, 2, "points")]), "continuation differences use B minus selected A with actual direction and units")
		for assumption in ["A: selected-rate hold", "B: follow the implied nominal promise", "originally chosen conditions", "identical current decision and shock", "no future shocks", "Portfolio switches persist", "future asset/lending offers are zero", "No automatic player decision", "Fulfillment need not improve stance adequacy or credibility"]:
			check(report.contains(assumption), "continuation discloses " + assumption)
		game._preview()
		check(var_to_bytes([game.career.encode(), game.career.state, game.career.history, game._policy(), selected, held, following]) == preserved, "comparison preserves selected/reference forecasts, live career and staged controls")
		var preview: String = game.forecast_label.text
		check(game._decision_briefing() == report and game.forecast_label.text == preview, "repeated continuation report leaves the default rate-hold preview unchanged")
	game._start_career("base", 417)
	var original = game.career
	var failing := UnavailableContinuationCareer.new()
	check(failing.restore(bytes_to_var(original.encode())).ok, "continuation failure fixture restores a real career")
	game.career = failing
	game._refresh(true)
	game.rate.value = game.career.state.policy_rate_pct + 0.5
	game.guidance.value = game.rate.value + 0.75
	await process_frame
	var invalid: Dictionary = game._policy().duplicate()
	invalid.guidance_rate_pct = NAN
	var rejected: Dictionary = original.forecast(invalid)
	check(not rejected.ok, "continuation failure uses the native invalid-policy error")
	var failure_preserved: PackedByteArray = var_to_bytes([failing.encode(), failing.state, failing.history, game._policy()])
	var unavailable: String = game._decision_briefing()
	check(failing.continuation_forecasts == 1 and unavailable.contains(heading + "\n") and unavailable.contains("Promise-follow unavailable: " + rejected.error), "only B fails explicitly after exactly one continuation forecast")
	for marker in ["CURRENT MEETING /", "GUIDANCE /", "Q+1 / WHY", "CURRENT TRANSMISSION /", "ONE-CONTROL CONTRASTS /", "REFERENCE AND LIMITS"]:
		check(unavailable.contains(marker), "B failure retains valid existing report section " + marker)
	check(not unavailable.contains("Q+2 / A VS B") and not unavailable.begins_with("Comparison unavailable:"), "failed B states are not displayed or allowed to obscure valid selected/reference paths")
	game._compare()
	await process_frame
	await process_frame
	var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	var bodies := dialog.find_children("*", "TextEdit", true, false)
	check(bodies.size() == 1, "B failure retains the native complete report body")
	if bodies.size() == 1:
		var body: TextEdit = bodies[0]
		check(body.text == unavailable and body.accessibility_description == unavailable, "B failure keeps the complete native accessible report")
	dialog.get_ok_button().pressed.emit()
	await process_frame
	check(var_to_bytes([failing.encode(), failing.state, failing.history, game._policy()]) == failure_preserved, "opening and closing unavailable B preserves selected policy and live state")
	failing.continuation_forecasts = 0
	failing.reject_reference = true
	check(game._decision_briefing() == "Comparison unavailable: " + rejected.error and failing.continuation_forecasts == 0, "invalid reference retains the original early error without computing B")
	failing.reject_reference = false
	failing.shocks[0] = {"continuation_fixture_unknown_input": 1.0}
	check(game._decision_briefing() == "Comparison unavailable: unknown exogenous input: continuation_fixture_unknown_input" and failing.continuation_forecasts == 0, "invalid selected/current path retains the original early error without computing B")
	game.career = original
	game._start_career("supply_shock", 1)
func check_financing_readout(game: Control) -> void:
	var readout_matches := true
	for sample in [[3.5, 3.5, 4.0, {}], [3.5, 3.5, 0.0, {"credit_risk_innovation_pct": 0.03}], [-0.5, -0.75, 0.0, {}], [3.5, 3.5, 0.01, {}]]:
		game._start_career("base", 417)
		game.career.shocks[0] = sample[3].duplicate(true)
		game.rate.value = sample[0]
		game.guidance.value = sample[1]
		game.assets.value = sample[2]
		await process_frame
		var params: Dictionary = game.career.params
		var staged: Dictionary = game._policy()
		check(game.career.state.quarter_index == 0 and game.career.model._validate_state(game.career.state, params).ok and game.career.model._validate_policy(staged, params).ok and game.career.model._validate_shocks(game.career.current_briefing()).ok, "financing readout fixtures use valid native initial state, policy and current shock")
		check(staged.policy_rate_request_pct == sample[0] and staged.guidance_rate_pct == sample[1] and abs(staged.asset_flow_request_pct_initial_gdp - float(sample[2])) < 1e-12, "financing readout preserves signed quotes and current-GDP asset offers within native decimal representation")
		var preserved: PackedByteArray = review_staff_snapshot(game)
		var selected: Dictionary = game.career.forecast(staged)
		var held: Dictionary = game.career.forecast(game.career.model.benchmark_policy(game.career.state, params, "hold"))
		check(selected.ok and held.ok, "financing readout setup has valid real selected and same-current-shock HOLD forecasts")
		if not selected.ok or not held.ok:
			continue
		var first: Dictionary = selected.states[0]
		var reference: Dictionary = held.states[0]
		check(game.career.model._validate_state(first, params).ok and game.career.model._validate_state(reference, params).ok and first.quarter_index == 1 and reference.quarter_index == 1, "financing readout uses validated Q+1 native states")
		var spot_delta: float = first.spot_financial_gap_pct - reference.spot_financial_gap_pct
		var retained_delta: float = first.financial_restraint_gap_pct - reference.financial_restraint_gap_pct
		check(abs(first.financial_restraint_gap_pct - (0.85 * game.career.state.financial_restraint_gap_pct + 0.15 * first.spot_financial_gap_pct)) < 1e-10, "retained financing follows the independent original quarterly recurrence")
		if sample[2] == 4.0:
			var premium_delta: float = -1.5 * tanh(4.0 / 60.0)
			check(params.portfolio_premium_max_shift_pct == 1.5 and params.portfolio_premium_scale_pct_gdp == 60.0 and params.real_rate_short_weight == 0.5 and params.real_rate_gap_persistence == 0.85 and params.real_rate_output_sensitivity == 0.12, "neutral purchase arithmetic binds the frozen original coefficients")
			check(first.asset_flow_applied_pct_initial_gdp == 4.0 and first.decision_nominal_gdp_ratio == 1.0, "neutral purchase applies four percent of current and initial annual GDP once")
			check(abs(first.term_premium_pct - reference.term_premium_pct - premium_delta) < 1e-10 and abs(spot_delta - 0.5 * premium_delta) < 1e-10 and abs(retained_delta - 0.15 * spot_delta) < 1e-10, "neutral purchase premium, immediate gap and retained gap match independent arithmetic")
			check(abs(first.output_gap_pct - reference.output_gap_pct + 0.12 * retained_delta) < 1e-10 and first.four_quarter_inflation_pct == reference.four_quarter_inflation_pct, "neutral purchase moves next output through retained restraint without immediate inflation repair")
		elif sample[0] < 0.0:
			check(abs(first.effective_policy_rate_pct - tanh(float(sample[0]))) < 1e-10 and first.spot_financial_gap_pct < 0.0 and first.financial_restraint_gap_pct < 0.0, "valid signed financing preserves effective-rate and gap signs")
		elif sample[2] == 0.0:
			check(spot_delta == 0.0 and retained_delta == 0.0 and abs(first.spot_financial_gap_pct - 0.03) < 1e-10, "HOLD has no policy effect while both paths price the same authored current credit innovation")
		else:
			check(spot_delta < 0.0 and abs(spot_delta) < 0.0005 and retained_delta < 0.0 and abs(retained_delta) < 0.0005, "tiny valid asset offer produces real sub-rounding financing effects")
		var immediate_change: String = expected_change(spot_delta, 3, "pp")
		var retained_change: String = expected_change(retained_delta, 3, "pp")
		check(game._change_text(spot_delta, 3, "pp") == immediate_change and game._change_text(retained_delta, 3, "pp") == retained_change, "existing formatter preserves financing zero, sign and sub-rounding pp direction")
		var report: String = game._decision_briefing()
		readout_matches = readout_matches and report.contains("Q+1 immediate financing gap %+.3f pp; retained %+.3f pp" % [first.spot_financial_gap_pct, first.financial_restraint_gap_pct]) and report.contains("Vs HOLD immediate %s; retained %s" % [immediate_change, retained_change])
		readout_matches = readout_matches and report.contains("tighter than neutral") and report.contains("not a policy ranking") and report.contains("current pricing") and report.contains("past restraint")
		check(review_staff_snapshot(game) == preserved, "financing comparison preserves career, history, raw and seeded shocks, parameters, staged controls and preview")
		if sample[2] == 4.0:
			var future: Dictionary = game.career.shocks[1].duplicate(true)
			game.career.shocks[1].demand_shock_pct = 10.0
			check(game._decision_briefing() == report, "financing readout cannot inspect an undisclosed future shock")
			game.career.shocks[1] = future
			check(review_staff_snapshot(game) == preserved, "future-information fixture restores the complete original comparison inputs")
			game._compare()
			var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
			await process_frame
			await process_frame
			var bodies: Array = dialog.find_children("*", "TextEdit", true, false)
			check(bodies.size() == 1, "financing comparison has one native accessible text body")
			if bodies.size() == 1:
				var body: TextEdit = bodies[0]
				check(body.accessibility_name == "Policy comparison report" and body.accessibility_description == report and body.focus_mode == Control.FOCUS_ALL and body.selecting_enabled and not body.editable and body.wrap_mode == TextEdit.LINE_WRAPPING_BOUNDARY, "financing comparison preserves its selectable, wrapped, read-only accessible report")
				check(body.text == report, "native selectable accessible comparison retains the complete financing report")
			dialog.get_ok_button().pressed.emit()
			await process_frame
			check(review_staff_snapshot(game) == preserved, "reading and closing financing comparison never adopts or changes inputs")
	game.career.shocks[0] = {"financing_readout_unknown_input": 1.0}
	var rejected: Dictionary = game.career.forecast(game._policy())
	check(not rejected.ok, "unavailable financing fixture uses the original native unknown-shock rejection")
	if not rejected.ok:
		var preserved: PackedByteArray = review_staff_snapshot(game)
		check(game._decision_briefing() == "Comparison unavailable: " + rejected.error, "financing readout retains the original early comparison error instead of fabricated values")
		check(review_staff_snapshot(game) == preserved, "unavailable comparison preserves invalid inputs and staged controls")
	check(readout_matches, "FINANCING_READOUT: actual Q+1 immediate/retained pp values, paired HOLD differences and interpretation must be exposed")
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
		var report: String = game._decision_briefing()
		check(report.contains("COMMITTEE DELIBERATION / FEASIBLE RATE ALTERNATIVES"), "comparison exposes nearby offline rate deliberation")
		for alternative in [["Selected", applied], ["Tighter rate", applied + 0.25], ["Gentler rate", applied - 0.25], ["Rate continuity", game.career.state.policy_rate_pct]]:
			var other: Dictionary = staged.duplicate()
			other.policy_rate_request_pct = alternative[1]
			var path: Dictionary = selected if alternative[0] == "Selected" else game.career.forecast(other)
			var last: Dictionary = path.states[-1]
			check(report.contains("%s / applied %.2f%%\nQ+8 inflation %.3f%%; unemployment %.3f%%; credibility %.1f/100; support %.1f/100" % [alternative[0], path.states[0].policy_rate_pct, last.four_quarter_inflation_pct, last.unemployment_rate_pct, 100 * last.credibility, last.public_support]), "deliberation uses real unrestricted nominal forecasts with every other staged tool preserved")
		check(report.contains("Fictional viewpoints, not votes or advice"), "deliberation labels fictional viewpoints")
		check(not report.contains("no extra feasible rate move"), "former zero/15-percent boundaries do not invent nominal rate limits")
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
func check_city_density(game: Control) -> void:
	check(game.has_method("_city_texture_size"), "city allocation follows physical canvas density")
	if not game.has_method("_city_texture_size"):
		return
	var logical := Vector2(1440, 960)
	var area := Vector2(634, 215)
	for sample in [
		[area, Vector2i(1440, 960), logical, Vector2i(634, 215)],
		[area, Vector2i(2880, 1920), logical, Vector2i(1268, 430)],
		[area, Vector2i(2160, 1440), logical, Vector2i(951, 323)],
		[area, Vector2i(2880, 2200), logical, Vector2i(1268, 430)],
		[area, Vector2i(1440, 2500), logical, Vector2i(634, 215)],
		[area, Vector2i(800, 600), logical, Vector2i(634, 215)],
		[area, Vector2i(5760, 3840), logical, Vector2i(1268, 430)],
		[area, Vector2i(2880, 1920), Vector2.ZERO, Vector2i(634, 215)],
		[Vector2.ZERO, Vector2i(2880, 1920), logical, Vector2i(2, 2)],
		[Vector2(4000, 100), Vector2i(2880, 1920), logical, Vector2i(2048, 52)],
		[Vector2(100, 4000), Vector2i(2880, 1920), logical, Vector2i(52, 2048)],
		[Vector2(2000, 300), Vector2i(2880, 1920), logical, Vector2i(2048, 308)],
	]:
		check(game._city_texture_size(sample[0], sample[1], sample[2]) == sample[3], "bounded uniform native city dimensions: " + str(sample))

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
	var container: TextureRect = viewport.get_parent()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.size_changed.emit()
	check(viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "native size notification rearms static texture")
	check(container.expand_mode == TextureRect.EXPAND_IGNORE_SIZE and container.stretch_mode == TextureRect.STRETCH_SCALE and container.mouse_filter == Control.MOUSE_FILTER_IGNORE, "physical texture keeps layout independent and does not intercept policy input")
	var original_size := viewport.size
	var original_control_size := container.size
	container.size = Vector2(original_control_size.x / 2, original_control_size.y)
	check(viewport.size == Vector2i(ceili(original_size.x / 2.0), original_size.y) and viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "real native size change requests a new static frame")
	container.size = original_control_size
	check(viewport.size == original_size and viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "restored native size rearms the full-quality city")
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.size_changed.emit()
	check(viewport.size == original_size and viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "window canvas-size notification rearms physical static texture")
	container.hide()
	check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "hidden city does not request a redraw")
	container.show()
	await process_frame
	check(viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "visible static city retains its one-shot mode")
	motion.button_pressed = true
	container.hide()
	container.show()
	await process_frame
	check(viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "visible animated city continues after visibility change")
	motion.button_pressed = false
	game.city.rotation.y = rotation
func check_initial_window_size(game: Control, window_size_before: Vector2i, window_position_before: Vector2i) -> void:
	check(game.has_method("_initial_window_size"), "shared startup sizing exists")
	if not game.has_method("_initial_window_size"):
		return
	var design := Vector2i(1440, 960)
	check(game._initial_window_size(design, 2.0, Vector2i(3420, 2082)) == Vector2i(2880, 1920), "Retina startup preserves intended logical design size")
	check(game._initial_window_size(design, 1.0, Vector2i(1920, 1048)) == design, "standard-density startup retains its existing dimensions")
	check(game._initial_window_size(design, 2.0, Vector2i(2560, 1536)) == Vector2i(2304, 1536), "smaller usable screens uniformly fit without changing aspect or omitting titlebar space")
	check(game._initial_window_size(design, 2.0, Vector2i(2000, 2000)) == Vector2i(2000, 1333), "width-limited startup rounds within the usable screen")
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--preserve-startup-window"):
		check(root.size == window_size_before, "headless or explicitly configured startup preserves initial size")
		check(root.position == window_position_before, "headless or explicitly configured startup preserves initial position")

func check_release_comparison(game: Control) -> void:
	var checker := RecordingReleaseCheck.new()
	checker._check_report(game)
	check(checker.checks == 5 and checker.failures == 0, "bundled comparison check accepts genuine report values")
	for fragment in ["headings only", "Q+2 / A VS B\nNominal rate ",
		"B / Q+8 PROMISE-FOLLOW\nInflation ", "Q+8 / B MINUS A\nInflation "]:
		var mutant := CorruptComparisonMain.new()
		mutant.fragment = fragment
		root.add_child(mutant)
		await process_frame
		checker = RecordingReleaseCheck.new()
		checker._check_report(mutant)
		check(checker.failures > 0, "bundled comparison check rejects corrupt " + fragment)
		mutant.free()

func quit_key(window: Window, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	var receiver: Window = root if window.is_embedded() else window
	receiver.window_input.emit(event)
	receiver.push_input(event)
	event = event.duplicate()
	event.pressed = false
	receiver.window_input.emit(event)
	receiver.push_input(event)
	await process_frame
	await process_frame

func request_app_close() -> void:
	check(not auto_accept_quit, "native app quit disables SceneTree auto_accept_quit before any root close event")
	if auto_accept_quit:
		return
	root.notification(Window.NOTIFICATION_WM_CLOSE_REQUEST)
	root.close_requested.emit()
	await process_frame
	await process_frame

func app_quit_dialog(game: Control) -> AcceptDialog:
	var dialogs: Array[Window] = []
	for child in game.get_children():
		if child is Window and child.visible:
			dialogs.append(child)
	check(dialogs.size() == 1 and dialogs[0] is AcceptDialog, "dirty root close opens exactly one native confirmation")
	if dialogs.size() != 1 or not dialogs[0] is AcceptDialog:
		return null
	var dialog: AcceptDialog = dialogs[0]
	check(dialog.get_ok_button().text.to_lower() == "quit without saving", "quit confirmation names the explicit discard action")
	var focused := dialog.gui_get_focus_owner() as Button
	check(focused != null and focused.text == "Cancel", "quit confirmation initially focuses Cancel")
	return dialog

func app_quit_snapshot(game: Control) -> PackedByteArray:
	var metadata: Array = []
	for field in [game.rate, game.guidance, game.assets, game.liquidity, game.inflation_response, game.activity_response]:
		metadata.append([field.get_meta("numeric_text"), field.get_meta("numeric_text_pending")])
	return var_to_bytes([review_staff_snapshot(game), metadata, game.status_label.text, game.consequence.text])

func check_dirty_quit_cancel(game: Control, context: String) -> void:
	game.rate.get_line_edit().grab_focus()
	# A real adoption redraws SpinBox text before the next user quit request.
	await process_frame
	await process_frame
	var preserved := app_quit_snapshot(game)
	var exits: int = game.exit_requests
	await request_app_close()
	var dialog := app_quit_dialog(game)
	check(game.exit_requests == exits, context + " retains dirty quit protection")
	if dialog != null:
		await quit_key(dialog, KEY_ESCAPE)
		await process_frame
		check(not is_instance_valid(dialog) and game.rate.get_line_edit().has_focus(), context + " cancels back to its invoking field")
	check(app_quit_snapshot(game) == preserved and game.exit_requests == exits, context + " cancellation preserves career, controls, raw text, metadata and preview")

func check_unsaved_app_quit() -> void:
	var home := OS.get_environment("FED_GAME_TEST_HOME")
	var temporary_dir := OS.get_environment("TMPDIR").simplify_path()
	var private_home := home.begins_with("/private/tmp/fed-game-home.") or home.begins_with("/tmp/fed-game-home.")
	var isolated := private_home and home == OS.get_environment("HOME") and OS.get_user_data_dir().begins_with(home + "/") and temporary_dir == home.path_join("tmp") and DirAccess.dir_exists_absolute(temporary_dir)
	check(isolated, "quit fixture requires verified private HOME, user storage and TMPDIR before any write")
	if not isolated:
		return
	var temporary := temporary_dir.path_join("fed-unsaved-quit-%d.save" % OS.get_process_id())
	if FileAccess.file_exists(temporary) or DirAccess.dir_exists_absolute(temporary) or FileAccess.file_exists(temporary + ".pending") or DirAccess.dir_exists_absolute(temporary + ".pending"):
		check(false, "quit fixture collision; existing final and pending paths preserved")
		return
	var game = load("res://main.tscn").instantiate()
	# Keep scene properties and real startup; intercept only the final process exit.
	game.set_script(RecordingQuitMain)
	game.save_path = temporary
	root.add_child(game)
	await process_frame
	await process_frame
	check(not auto_accept_quit, "native app quit disables SceneTree auto_accept_quit before any root close event")
	if auto_accept_quit:
		game.free()
		return
	await request_app_close()
	check(game.exit_requests == 1 and game.find_children("*", "AcceptDialog", true, false).is_empty(), "fresh career root close requests exactly one immediate exit without confirmation")
	check(not FileAccess.file_exists(temporary) and not FileAccess.file_exists(temporary + ".pending"), "fresh close never creates a save")
	game._start_career("base", 41)
	game.rate.value = 4.25
	game.guidance.value = 4.25
	for quarter in range(3):
		game._advance()
	check(game.career.state.quarter_index == 3 and game.career.decisions.size() == 3, "dirty quit fixture adopts three quarters through real Main and Career")
	game.rate.value = 5.25
	game.guidance.value = 6.25
	game.assets.value = 1.25
	await process_frame
	await process_frame
	for dismissal in ["Cancel", "Escape", "WM close"]:
		var invoker: LineEdit = game.rate.get_line_edit()
		invoker.grab_focus()
		invoker.text = "-0.37"
		check(game.rate.value == 5.25 and invoker.text != str(game.rate.get_meta("numeric_text")), "quit fixture retains unsubmitted raw numeric text distinct from staged policy and draw metadata")
		var preserved := app_quit_snapshot(game)
		var exits: int = game.exit_requests
		await request_app_close()
		var dialog := app_quit_dialog(game)
		check(game.exit_requests == exits and not FileAccess.file_exists(temporary) and not FileAccess.file_exists(temporary + ".pending"), "dirty root close neither exits nor writes any save")
		if dialog == null:
			game.free()
			return
		await request_app_close()
		await request_app_close()
		check(app_quit_dialog(game) == dialog and game.exit_requests == exits, "repeated root close retains the same single Cancel-first confirmation")
		if dismissal == "WM close":
			var canceled := [0]
			dialog.canceled.connect(func(): canceled[0] += 1)
			dialog.notification(Window.NOTIFICATION_WM_CLOSE_REQUEST)
			check(canceled[0] == 1 and dialog.is_queued_for_deletion(), "native quit-modal WM notification cancels once and queues accessibility-safe disposal")
			dialog.close_requested.emit()
			await process_frame
			await process_frame
			check(canceled[0] == 1, "native quit-modal close signal does not repeat WM cancellation")
		else:
			await quit_key(dialog, KEY_SPACE if dismissal == "Cancel" else KEY_ESCAPE)
		await process_frame
		check(not is_instance_valid(dialog) and invoker.has_focus(), dismissal + " disposes the quit modal and restores invoking focus")
		check(app_quit_snapshot(game) == preserved and game.exit_requests == exits, dismissal + " preserves complete career, staged policy, pending raw text/metadata and preview without exit")
		check(not FileAccess.file_exists(temporary) and not FileAccess.file_exists(temporary + ".pending"), dismissal + " never writes a save")
	var preserved := app_quit_snapshot(game)
	var exits: int = game.exit_requests
	await request_app_close()
	var discard := app_quit_dialog(game)
	if discard == null:
		game.free()
		return
	await quit_key(discard, KEY_TAB)
	check(discard.gui_get_focus_owner() == discard.get_ok_button(), "Tab reaches Quit without saving from Cancel")
	await quit_key(discard, KEY_SPACE)
	await process_frame
	check(game.exit_requests == exits + 1 and not is_instance_valid(discard), "explicit keyboard discard requests exactly one exit and disposes its modal")
	check(app_quit_snapshot(game) == preserved and not FileAccess.file_exists(temporary) and not FileAccess.file_exists(temporary + ".pending"), "discard does not adopt pending text, mutate play or save automatically")
	if FileAccess.file_exists(temporary) or DirAccess.dir_exists_absolute(temporary) or FileAccess.file_exists(temporary + ".pending") or DirAccess.dir_exists_absolute(temporary + ".pending"):
		check(false, "quit fixture refuses to overwrite any unexpected final or pending path before explicit Save")
		game.free()
		return
	var saved: PackedByteArray = game.career.encode()
	game._save()
	check(FileAccess.file_exists(temporary) and FileAccess.get_file_as_bytes(temporary) == saved and game.status_label.text.begins_with("Saved quarter 3."), "real successful Save writes the private fixture")
	if not FileAccess.file_exists(temporary):
		game.free()
		return
	exits = game.exit_requests
	preserved = app_quit_snapshot(game)
	await request_app_close()
	check(game.exit_requests == exits + 1 and game.find_children("*", "AcceptDialog", true, false).is_empty() and app_quit_snapshot(game) == preserved, "successful Save establishes a clean baseline despite staged and pending policy edits")
	game._advance()
	check(game.career.state.quarter_index == 4 and game.career.encode() != saved, "a later real adoption differs from the saved clean baseline")
	await check_dirty_quit_cancel(game, "adoption after Save")
	var dirty: PackedByteArray = game.career.encode()
	# A regular fixture file cannot be a parent directory: deterministic real I/O failure.
	game.save_path = temporary.path_join("missing.save")
	game._save()
	check(game.status_label.text == "Could not create save. Previous save is unchanged." and game.career.encode() == dirty, "failed real Save preserves adopted unsaved play")
	game.save_path = temporary
	await check_dirty_quit_cancel(game, "failed Save")
	game._load()
	await process_frame
	await process_frame
	var replacement: AcceptDialog = game.get_child(game.get_child_count() - 1)
	await quit_key(replacement, KEY_SPACE)
	check(game.career.encode() == dirty, "cancelled real Load retains the dirty career")
	await check_dirty_quit_cancel(game, "cancelled Load")
	game.save_path = temporary.path_join("missing.save")
	game._load()
	await process_frame
	await process_frame
	replacement = game.get_child(game.get_child_count() - 1)
	await quit_key(replacement, KEY_TAB)
	await quit_key(replacement, KEY_SPACE)
	check(game.status_label.text == "No readable saved career found." and game.career.encode() == dirty, "failed real Load retains the dirty career")
	game.save_path = temporary
	await check_dirty_quit_cancel(game, "failed Load")
	check(FileAccess.get_file_as_bytes(temporary) == saved and not FileAccess.file_exists(temporary + ".pending"), "dirty cancellations and failed operations never replace the saved fixture")
	game._load()
	await process_frame
	await process_frame
	replacement = game.get_child(game.get_child_count() - 1)
	await quit_key(replacement, KEY_TAB)
	await quit_key(replacement, KEY_SPACE)
	check(game.career.encode() == saved and game.status_label.text == "Loaded quarter 3.", "successful real Load restores the exact saved career")
	exits = game.exit_requests
	await request_app_close()
	check(game.exit_requests == exits + 1 and game.find_children("*", "AcceptDialog", true, false).is_empty(), "successful Load resets the clean quit baseline")
	game._advance()
	await check_dirty_quit_cancel(game, "adoption after Load")
	game._new_dialog()
	await process_frame
	await process_frame
	replacement = game.get_child(game.get_child_count() - 1)
	await quit_key(replacement, KEY_ESCAPE)
	await check_dirty_quit_cancel(game, "cancelled New")
	dirty = game.career.encode()
	game._start_career("unknown-quit-test-case", 41)
	check(game.career.encode() == dirty, "invalid New retains the prior career")
	await check_dirty_quit_cancel(game, "invalid New")
	game._new_dialog()
	await process_frame
	await process_frame
	replacement = game.get_child(game.get_child_count() - 1)
	replacement.get_ok_button().pressed.emit()
	await process_frame
	await process_frame
	check(game.career.state.quarter_index == 0 and game.career.decisions.is_empty(), "valid New starts a fresh real career")
	exits = game.exit_requests
	await request_app_close()
	check(game.exit_requests == exits + 1 and game.find_children("*", "AcceptDialog", true, false).is_empty(), "valid New resets the clean quit baseline")
	check(FileAccess.get_file_as_bytes(temporary) == saved and not FileAccess.file_exists(temporary + ".pending"), "Load, New and all quit intentions leave the saved fixture unchanged")
	game.free()
	await process_frame
	await process_frame

func run() -> void:
	# Headless script roots default to 64x64; functional fixtures need a real wide canvas.
	if DisplayServer.get_name() == "headless" and not OS.get_cmdline_user_args().has("--window-size-only"):
		root.size = Vector2i(1440, 960)
	var window_size_before := root.size
	var window_position_before := root.position
	if OS.get_cmdline_user_args().has("--unsaved-quit-only"):
		await check_unsaved_app_quit()
		if failures == 0:
			print("PASS: unsaved native root quit, keyboard cancellation/discard and clean Save/Load/New baselines")
		quit(1 if failures else 0)
		return
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	if OS.get_cmdline_user_args().has("--backaudit-ui-only"):
		await check_terminal_career(game)
		check_backaudit_readouts(game)
		await check_comparison_navigation(game)
		print("BACKAUDIT_UI_COUNTS: checks=%d failures=%d" % [checks, failures])
		if failures == 0:
			print("PASS: four backaudit UI regressions, actual popup input and terminal replay/purity")
		game.free()
		quit(1 if failures else 0)
		return
	if OS.get_cmdline_user_args().is_empty() or OS.get_cmdline_user_args().has("--release-check-only"):
		await check_release_comparison(game)
	if OS.get_cmdline_user_args().has("--release-check-only"):
		game.free()
		if failures == 0:
			print("PASS: bundled comparison checks reject headings-only and corrupt Q+2/Q+8/delta values")
		quit(1 if failures else 0)
		return
	if OS.get_cmdline_user_args().has("--review-staff-only"):
		await check_review_staff_dialog(game)
		await check_review_access(game)
		if failures == 0:
			print("PASS: realized staff/funding review values, native accessibility, purity and modal lifecycle")
		game.free()
		quit(1 if failures else 0)
		return
	if OS.get_cmdline_user_args().has("--financing-readout-only"):
		await check_financing_readout(game)
		if failures == 0:
			print("PASS: Q+1 immediate/retained financing readout, independent native arithmetic, boundaries and purity")
		game.free()
		quit(1 if failures else 0)
		return
	if OS.get_cmdline_user_args().has("--guidance-continuation-only"):
		await check_guidance_continuation(game)
		await check_comparison_navigation(game)
		if failures == 0:
			print("PASS: report-only guidance continuation, native navigation and explicit failures")
		game.free()
		quit(1 if failures else 0)
		return
	if OS.get_cmdline_user_args().has("--current-signals-only"):
		check_current_signals_ui(game)
		if failures == 0:
			print("PASS: current-only refinancing/impairment UI, units, constraints and read-only previews")
		game.free()
		quit(1 if failures else 0)
		return
	check_initial_window_size(game, window_size_before, window_position_before)
	if OS.get_cmdline_user_args().has("--window-size-only"):
		print("STARTUP_WINDOW: " + JSON.stringify({"pid": OS.get_process_id(), "display": DisplayServer.get_name(), "arguments": OS.get_cmdline_args(), "size_before": str(window_size_before), "size_after": str(root.size), "position_before": str(window_position_before), "position_after": str(root.position)}))
		if failures == 0:
			print("PASS: DPI-aware startup sizing and explicit/headless preservation")
		game.free()
		quit(1 if failures else 0)
		return
	check_funding_outcome(game)
	check_score_feedback(game)
	check_change_precision(game)
	if OS.get_cmdline_user_args().has("--score-feedback-only"):
		if failures == 0:
			print("PASS: meaningful outcome and comparison change direction and units")
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
	check_unrestricted_rate_controls(game)
	var city_viewports: Array = game.find_children("*", "SubViewport", true, false)
	check(city_viewports.size() == 1 and city_viewports[0].msaa_3d == Viewport.MSAA_4X, "miniature city uses bounded four-sample native edge antialiasing")
	check_city_density(game)
	if city_viewports.size() == 1:
		check_city_framing(game, city_viewports[0])
		await check_city_redraw(game, city_viewports[0])
	if OS.get_cmdline_user_args().has("--city-only"):
		if failures == 0:
			print("PASS: bounded physical-density native miniature and redraw lifecycle")
		game.free()
		root.size_changed.emit()
		await process_frame
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
	check_current_signals_ui(game)
	if OS.get_cmdline_user_args().has("--situation-only"):
		if failures == 0:
			print("PASS: situation briefing in shared cockpit")
		game.free()
		quit(1 if failures else 0)
		return
	check_backaudit_readouts(game)
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
	await check_financing_readout(game)
	await check_guidance_continuation(game)
	await check_pending_policy(game)
	await check_unfocused_inputs(game)
	await check_pending_overwrites(game)
	await check_review_access(game)
	await check_review_staff_dialog(game)
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
		check(report.contains("Applied rate %.2f%%" % selected.states[0].policy_rate_pct), "briefing shows the fully applied nominal rate")
		check(report.contains("Applied lending %.2f" % (selected.states[0].liquidity_applied_pct_initial_gdp / selected.states[0].decision_nominal_gdp_ratio)), "briefing shows collateral-constrained lending")
		check(report.contains("ONE-CONTROL CONTRASTS / SELECTED MINUS ALTERNATIVE"), "comparison isolates staged tools")
		var alternatives := [
			["Rate / alternative request today's rate", "policy_rate_request_pct", game.career.state.policy_rate_pct, "%"],
			["Guidance quote / alternative quote applied rate", "guidance_rate_pct", selected.states[0].policy_rate_pct, "%"],
			["Asset flow / alternative no new flow", "asset_flow_request_pct_initial_gdp", 0.0, "% of current annual GDP"],
			["Lending / alternative no new loans", "liquidity_request_pct_initial_gdp", 0.0, "% of current annual GDP"],
		]
		for alternative in alternatives:
			var other: Dictionary = game._policy().duplicate()
			other[alternative[1]] = alternative[2]
			var path: Dictionary = game.career.forecast(other)
			var first: Dictionary = selected.states[0]
			var last: Dictionary = selected.states[7]
			var reference_first: Dictionary = path.states[0]
			var reference_last: Dictionary = path.states[7]
			var row := "%s: %.2f%s\nQ+1 long yield %s; credit spread %s\nQ+8 inflation %s; unemployment %s; credibility %s; support %s" % [alternative[0], alternative[2], alternative[3], expected_change(first.long_yield_pct - reference_first.long_yield_pct, 3, "pp"), expected_change(first.credit_spread_pct - reference_first.credit_spread_pct, 3, "pp"), expected_change(last.four_quarter_inflation_pct - reference_last.four_quarter_inflation_pct, 3, "pp"), expected_change(last.unemployment_rate_pct - reference_last.unemployment_rate_pct, 3, "pp"), expected_change(100 * (last.credibility - reference_last.credibility), 2, "points"), expected_change(last.public_support - reference_last.public_support, 2, "points")]
			check(report.contains(row), "named tool contrast matches its real one-input alternative at both horizons")
		check(report.contains("only its named input") and report.contains("not additive") and report.contains("conditional coefficients unchanged"), "tool contrasts disclose matched controls and interpretation limits")
		check(report.contains("Inflation " + expected_change(selected.states[7].four_quarter_inflation_pct - held.states[7].four_quarter_inflation_pct, 3, "pp")), "comparison uses the actual paired Q8 paths")
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
			check(diagnostics.contains("Effective rate %.3f%% vs %.3f%%\nDesired real restraint %+.3f vs %+.3f pp\nEffective-stance distance %.3f vs %.3f pp\nTransmission-frontier shortfall %.3f vs %.3f pp\nStance adequacy %.1f vs %.1f / 100" % [first.effective_policy_rate_pct, reference.effective_policy_rate_pct, first.stance_target_gap_pct, reference.stance_target_gap_pct, first.stance_distance_pct, reference.stance_distance_pct, first.stance_best_feasible_distance_pct, reference.stance_best_feasible_distance_pct, 100 * first.stance_adequacy_score, 100 * reference.stance_adequacy_score]), "diagnostics show actual effective transmission and economically feasible stance, not nominal-rule alignment")
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
		check(neutral_report.count("Q+1 long yield unchanged; credit spread unchanged") == 4 and neutral_report.count("Q+8 inflation unchanged; unemployment unchanged; credibility unchanged; support unchanged") == 4, "unused-tool contrasts truthfully report zero effect")
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
	check(game.career.seed_value == 1 and game.career.scenario_id == "policy_career", "untouched new-career dialog uses its default seed and challenge")
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
	var soundtrack: Variant = game.get_node_or_null("Soundtrack")
	var music_toggle: CheckBox = game.find_child("MusicToggle", true, false) as CheckBox
	check(soundtrack is AudioStreamPlayer and music_toggle != null, "main cockpit exposes a native soundtrack player and Music checkbox")
	if soundtrack is AudioStreamPlayer and music_toggle != null:
		check(soundtrack.stream is AudioStreamWAV and soundtrack.stream.get_length() > 190.0 and soundtrack.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and soundtrack.stream.loop_begin == 0 and soundtrack.stream.loop_end == roundi(soundtrack.stream.get_length() * soundtrack.stream.mix_rate), "actual JRB-1 recording loops through its complete native WAV frame range")
		check(music_toggle.focus_mode == Control.FOCUS_ALL and game.keyboard_controls.has(music_toggle) and music_toggle.button_pressed == soundtrack.music_enabled, "Music is registered in keyboard navigation and reflects loaded preference")
		music_toggle.button_pressed = true
		check(soundtrack.music_enabled and soundtrack.playing and music_toggle.button_pressed, "Music keyboard fixture begins on even after a saved-off prior test")
		var music_career_before: PackedByteArray = game.career.encode()
		music_toggle.grab_focus()
		var music_key := InputEventKey.new()
		music_key.keycode = KEY_SPACE
		music_key.pressed = true
		game.get_window().push_input(music_key)
		music_key = InputEventKey.new()
		music_key.keycode = KEY_SPACE
		music_key.pressed = false
		game.get_window().push_input(music_key)
		await process_frame
		check(not soundtrack.music_enabled and not soundtrack.playing and not music_toggle.button_pressed and game.career.encode() == music_career_before, "focused Space turns music off without adopting or changing the career")
		music_key = InputEventKey.new()
		music_key.keycode = KEY_ENTER
		music_key.pressed = true
		game.get_window().push_input(music_key)
		music_key = InputEventKey.new()
		music_key.keycode = KEY_ENTER
		music_key.pressed = false
		game.get_window().push_input(music_key)
		await process_frame
		check(soundtrack.music_enabled and soundtrack.playing and music_toggle.button_pressed and game.career.encode() == music_career_before, "focused Return turns music on without adopting or changing the career")
		var music_settings_path: String = soundtrack.SETTINGS_PATH
		var music_permissions := FileAccess.get_unix_permissions(music_settings_path)
		check(FileAccess.set_unix_permissions(music_settings_path, FileAccess.UNIX_READ_OWNER) == OK, "Music recovery fixture denies only the private preference write")
		music_toggle.button_pressed = false
		check(not soundtrack.playing and game.status_label.text.contains("Music off; preference not saved"), "Music reports a failed preference write while stopping playback")
		check(FileAccess.set_unix_permissions(music_settings_path, music_permissions) == OK, "Music recovery fixture restores its private preference permissions")
		music_toggle.button_pressed = true
		var music_saved := ConfigFile.new()
		check(soundtrack.playing and game.status_label.text == "Music on." and music_saved.load(music_settings_path) == OK and music_saved.get_value("audio", "music_enabled", false) == true and game.career.encode() == music_career_before, "Music successful recovery clears the stale failure and persists current playback without career mutation")
		music_toggle.button_pressed = false
		check(not soundtrack.playing and game.status_label.text == "Music off." and music_saved.load(music_settings_path) == OK and music_saved.get_value("audio", "music_enabled", true) == false and game.career.encode() == music_career_before, "Music remains truthful on the next successful toggle after recovery")
	game._help()
	await process_frame
	var help: AcceptDialog = game.get_child(game.get_child_count() - 1)
	var help_text: TextEdit = help.get_child(0)
	check(help_text.text.contains("Every career includes seeded background disturbances") and help_text.text.contains("baseline starts at equilibrium") and help_text.text.contains("no scheduled scenario events"), "help explains the seeded baseline and scheduled-event distinction")
	check(help_text.text.contains("same scenario and seed") and help_text.text.contains("same engine and model"), "help qualifies every input needed to reproduce the path")
	check(help_text.text.contains("1bp increments") and help_text.text.contains("U.S. counterfactual") and help_text.text.contains("diminishing benefits") and help_text.text.contains("Conditional implied quotes"), "help explains quote precision, negative-rate transmission and nominal promise accountability")
	check(help_text.text.contains("Varied policy career and Recurring crises draw from 50 curated exogenous events") and not help_text.text.contains("precomputes50"), "help describes the event pool, not fifty events in every career")
	check(help_text.text.contains("Deferred demand") and help_text.text.contains("not all lost consumption") and help_text.text.contains("no guaranteed return to 2%"), "help distinguishes catch-up spending from forced recovery")
	check(help_text.text.contains("structural reference") and help_text.text.to_lower().contains("short expectations") and help_text.text.contains("prior long"), "help explains separate structural and expectation restoration channels")
	check(not help_text.text.contains(Engine.get_license_text()), "help omits only the duplicated engine license, retained in Credits")
	check(game.briefing.text.contains("Deferred demand") and game.briefing.text.contains("% potential"), "dispatch exposes the known deferred-demand stock with its unit")
	check(game.career.encode() == before_cancel and game._policy() == staged_before_cancel, "reading seeded help leaves the active career and staged policy unchanged")
	help.get_ok_button().pressed.emit()
	await process_frame
	game._credits()
	await process_frame
	var credits: AcceptDialog = game.get_child(game.get_child_count() - 1)
	var notices: TextEdit = credits.get_child(0)
	var source_license_path := ProjectSettings.globalize_path("res://../LICENSE")
	var source_license := FileAccess.get_file_as_string(source_license_path) if FileAccess.file_exists(source_license_path) else ""
	var packaged_license := FileAccess.get_file_as_string("res://licenses/THE-CHAIR.txt") if FileAccess.file_exists("res://licenses/THE-CHAIR.txt") else ""
	check(source_license.contains("Copyright (c) 2026 Jared Bland. All rights reserved.") and source_license.contains("to the") and source_license.contains("intellectual-property rights subsist") and source_license.contains("personal, noncommercial use"), "project license attributes personal qualified ownership and noncommercial binary play")
	check(not source_license.is_empty() and packaged_license == source_license, "bundled original-project license matches the authoritative repository license")
	check(not source_license.is_empty() and notices.text.contains(source_license), "Credits displays the full original-project license alongside component notices")
	check(notices.text.contains(Engine.get_license_text()), "canonical Credits retains the complete engine license")
	check(notices.text.contains(Engine.get_license_info()["FTL"]), "bundled component license is preserved verbatim")
	credits.get_ok_button().pressed.emit()
	await process_frame
	game.free()
	await process_frame
	await process_frame
	await check_unsaved_app_quit()
	# Native audio releases stopped playbacks on its next mix, not a scene frame.
	var audio_release_deadline := Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < audio_release_deadline:
		await process_frame
	if failures == 0:
		print("PASS: exact rate display and UI adoption path")
	quit(1 if failures else 0)
