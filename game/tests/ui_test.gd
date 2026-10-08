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
		var bodies := dialog.find_children("*", "TextEdit", true, false)
		check(choosers.size() == 1 and bodies.size() == 1, "comparison provides native section navigation and a selectable complete report")
		if choosers.size() == 1 and bodies.size() == 1:
			var chooser: OptionButton = choosers[0]
			var body: TextEdit = bodies[0]
			check(body.text == expected and body.accessibility_description == expected, "section navigation preserves every report byte and warning")
			check(body.selecting_enabled and not body.editable and body.focus_mode == Control.FOCUS_ALL, "comparison report supports read-only native text selection and keyboard focus")
			check(chooser.accessibility_name == "Comparison section" and chooser.item_count == destinations.size(), "section chooser has a distinct accessible name and all seven destinations")
			for index in range(mini(chooser.item_count, destinations.size())):
				check(chooser.get_item_text(index) == destinations[index][0], "comparison sections retain their named order")
				var paragraph := expected.substr(0, expected.find(destinations[index][1])).count("\n")
				chooser.select(index)
				chooser.item_selected.emit(index)
				await process_frame
				check(body.get_line(paragraph).begins_with(destinations[index][1]) and paragraph >= body.get_first_visible_line() and paragraph <= body.get_last_full_visible_line(), "selecting %s brings its actual heading into view" % destinations[index][0])
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
		var reset_bodies := reopened.find_children("*", "TextEdit", true, false)
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

func run() -> void:
	var window_size_before := root.size
	var window_position_before := root.position
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
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
	check(game.career.seed_value == 1 and game.career.scenario_id == "unanchored_inflation", "untouched new-career dialog uses its default seed and challenge")
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
	check(help_text.text.contains("1bp increments") and help_text.text.contains("U.S. counterfactual") and help_text.text.contains("diminishing benefits") and help_text.text.contains("Conditional implied quotes"), "help explains quote precision, negative-rate transmission and nominal promise accountability")
	check(help_text.text.contains("draws from 50 curated exogenous events") and not help_text.text.contains("precomputes50"), "help describes the event pool, not fifty events in every career")
	check(help_text.text.contains("Deferred demand") and help_text.text.contains("not all lost consumption") and help_text.text.contains("no guaranteed return to 2%"), "help distinguishes catch-up spending from forced recovery")
	check(help_text.text.contains("structural reference") and help_text.text.to_lower().contains("short expectations") and help_text.text.contains("prior long"), "help explains separate structural and expectation restoration channels")
	check(game.briefing.text.contains("Deferred demand") and game.briefing.text.contains("% potential"), "dispatch exposes the known deferred-demand stock with its unit")
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
