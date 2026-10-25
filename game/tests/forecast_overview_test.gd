extends SceneTree
const Overview = preload("res://play/forecast_overview.gd")
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)
func _initialize() -> void:
	call_deferred("run")
func key(dialog: Window, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	dialog.push_input(event)
	await process_frame
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._start_career("stagflation_bank_run", 417)
	game.liquidity.value = 2.4 / game.career.model.nominal_gdp_ratio(game.career.state)
	var frozen: PackedByteArray = game.career.encode()
	var policy: Dictionary = game._policy()
	var a: Dictionary = game.career.forecast(policy)
	var b: Dictionary = game.career.forecast(game.career.model.benchmark_policy(game.career.state, game.career.params, "hold"))
	var data := Overview.series(game.career.state, a, b)
	check(data.size() == 9, "Current point and eight forecast quarters")
	check(data[1].selected_uncovered_funding_pct_initial_gdp == 0.0 and data[1].held_uncovered_funding_pct_initial_gdp > 0.0, "Actual lending choice separates covered staged funding from an uncovered Hold reference")
	for index in range(9):
		for field in ["four_quarter_inflation_pct", "unemployment_rate_pct", "uncovered_funding_pct_initial_gdp"]:
			check(data[index]["selected_" + field] == (game.career.state if index == 0 else a.states[index - 1])[field], "Exact selected data")
			check(data[index]["held_" + field] == (game.career.state if index == 0 else b.states[index - 1])[field], "Exact reference data")
	check(Overview.series({}, {"ok": true}, b).is_empty(), "Missing path fails closed")
	var broken := a.duplicate(true)
	broken.states[0].four_quarter_inflation_pct = NAN
	check(Overview.series(game.career.state, broken, b).is_empty(), "Nonfinite path fails closed")
	for malformed in [-0.1, NAN, INF]:
		var invalid_funding := a.duplicate(true)
		invalid_funding.states[0].uncovered_funding_pct_initial_gdp = malformed
		check(Overview.series(game.career.state, invalid_funding, b).is_empty(), "Invalid funding cannot become an optimistic zero chart")
	var missing_funding := a.duplicate(true)
	missing_funding.states[0].erase("uncovered_funding_pct_initial_gdp")
	check(Overview.series(game.career.state, missing_funding, b).is_empty(), "Missing funding fails closed")
	var zero_data := data.duplicate(true)
	for point in zero_data:
		point.selected_uncovered_funding_pct_initial_gdp = 0.0
		point.held_uncovered_funding_pct_initial_gdp = 0.0
	var quiet := Overview.new()
	root.add_child(quiet)
	quiet.build(zero_data, false)
	check(quiet.charts.size() == 2 and quiet.funding_note.text.contains("No funding shortfall"), "Quiet paths use one short status line rather than an empty chart")
	quiet.free()
	var tiny_data := zero_data.duplicate(true)
	tiny_data[1].selected_uncovered_funding_pct_initial_gdp = 0.00001
	tiny_data[1].held_uncovered_funding_pct_initial_gdp = 0.001
	var tiny_pane := Overview.new()
	root.add_child(tiny_pane)
	tiny_pane.build(tiny_data, false)
	check(tiny_pane.charts.size() == 3, "Even subprecision positive funding need adds its chart")
	var funding_chart = tiny_pane.charts[2]
	funding_chart._inspect(1)
	check(funding_chart.tooltip_text.contains("<0.0001%") and funding_chart.tooltip_text.contains("0.0010%"), "Positive tiny funding is not formatted as zero in keyboard inspection")
	check(funding_chart.accessibility_description.contains("<0.0001%") and funding_chart.accessibility_description.contains("0.0010%"), "Assistive funding inspection preserves the same positive-small distinction")
	check(funding_chart.value_text(0.0) == "0.00" and funding_chart.value_text(0.0001) == "0.0001", "True zero and a small residual remain distinguishable in graph labels")
	check(tiny_pane.charts[0].value_text(0.001) == "0.00" and not tiny_pane.charts[0].value_formatter.is_valid(), "Macro chart display precision remains unchanged")
	tiny_pane.free()
	var inherited_data := zero_data.duplicate(true)
	inherited_data[0].selected_uncovered_funding_pct_initial_gdp = 5.0
	inherited_data[0].held_uncovered_funding_pct_initial_gdp = 5.0
	var inherited := Overview.new()
	root.add_child(inherited)
	inherited.build(inherited_data, false)
	check(inherited.charts.size() == 3 and inherited.funding_note.text.begins_with("Q1–Q8 peak: Staged 0.00% · Hold 0.00%"), "Shared inherited Q0 stress is plotted but never attributed to a future policy peak")
	inherited.free()
	var unavailable := Overview.new()
	root.add_child(unavailable)
	unavailable.build([], false)
	check(unavailable.charts.is_empty() and unavailable.get_child(0).get_child(0).text.contains("unavailable"), "Unavailable paths cannot show a falsely reassuring funding status")
	unavailable.free()
	game._compare()
	await process_frame
	await process_frame
	var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	var tabs: TabContainer = dialog.find_children("*", "TabContainer", true, false)[0]
	var body: TextEdit = dialog.find_children("*", "TextEdit", true, false)[0]
	var pane = tabs.get_child(0)
	check(tabs.current_tab == 0 and pane.is_visible_in_tree() and not body.is_visible_in_tree(), "Paths replace opening text wall")
	check(tabs.get_tab_bar().has_focus() and pane.get_v_scroll_bar().value == 0.0, "Opening focus preserves the forecast heading and assumptions")
	check(pane.charts.size() == 3 and pane.charts[0].history == data and pane.charts[1].history == data and pane.charts[2].history == data, "Funding stress adds the third chart using the same captured paths")
	check(pane.charts[2].keys == ["selected_uncovered_funding_pct_initial_gdp", "held_uncovered_funding_pct_initial_gdp"] and pane.charts[2].zero_floor, "Funding graph selects unmet need with a nonnegative display scale")
	check(pane.funding_note.text == "Q1–Q8 peak: Staged 0.00% · Hold 2.40% initial GDP.\nUnmet need, not bank losses.", "Funding chart does not conflate unmet needs with bank losses")
	check(pane.charts[0].keys == ["selected_four_quarter_inflation_pct", "held_four_quarter_inflation_pct"] and pane.charts[1].keys == ["selected_unemployment_rate_pct", "held_unemployment_rate_pct"], "Each chart selects the correct paired metric")
	for chart in pane.charts:
		check(chart.labels == ["Staged policy", "Hold reference"], "Both chart legends identify the same policy pair")
	pane.charts[0].grab_focus()
	await key(dialog, KEY_END)
	check(pane.charts[0].hovered == 8 and pane.charts[0].accessibility_description.contains("Conditional model path"), "Keyboard inspection retains future context")
	pane.charts[1].grab_focus()
	await key(dialog, KEY_TAB)
	check(pane.charts[2].has_focus(), "Tab reaches the funding graph through the actual modal focus chain")
	await key(dialog, KEY_TAB)
	check(dialog.get_ok_button().has_focus(), "Tab leaves the last graph for Close")
	await key(dialog, KEY_TAB)
	check(tabs.get_tab_bar().has_focus(), "Focus wraps within the report")
	pane.charts[2].grab_focus()
	await key(dialog, KEY_END)
	check(pane.charts[2].hovered == 8 and pane.charts[2].accessibility_name.contains("funding"), "Funding graph supports keyboard inspection with explicit metric identity")
	pane.charts[2]._inspect(1)
	check(pane.charts[2].accessibility_description.contains("%.2f%%" % data[1].selected_uncovered_funding_pct_initial_gdp), "Funding inspection announces the actual selected shortfall")
	tabs.get_tab_bar().grab_focus()
	await key(dialog, KEY_RIGHT)
	check(tabs.current_tab == 1 and body.is_visible_in_tree(), "Native tab keyboard opens full report")
	check(body.text == game._decision_briefing() and body.accessibility_description == body.text, "Full report bytes and accessibility retained")
	for dimensions in [Vector2i(800, 240), Vector2i(240, 600)]:
		root.size = dimensions
		await process_frame
		for index in [0, 1]:
			tabs.current_tab = index
			game._fit_report(dialog)
			await process_frame
			await process_frame
			check(dialog.size.x <= root.size.x and dialog.size.y <= root.size.y, "Both comparison panes fit short and narrow parents")
			if dimensions.y == 240 and index == 0:
				pane.charts[0].grab_focus()
				await process_frame
				var before_page: float = pane.get_v_scroll_bar().value
				await key(dialog, KEY_PAGEDOWN)
				var after_page: float = pane.get_v_scroll_bar().value
				check(after_page > before_page, "PageDown scrolls an overflowing forecast pane from chart focus")
				await key(dialog, KEY_PAGEUP)
				check(pane.get_v_scroll_bar().value <= before_page, "PageUp reverses forecast paging")
	await key(dialog, KEY_ESCAPE)
	await process_frame
	check(game.career.encode() == frozen, "Inspection and dismissal preserve all career bytes")
	game._compare()
	await process_frame
	await process_frame
	var reading: AcceptDialog = game.get_child(game.get_child_count() - 1)
	await key(reading, KEY_TAB)
	await key(reading, KEY_ENTER)
	await process_frame
	check(not is_instance_valid(reading) and game.career.encode() == frozen, "Return dismisses a focused reading chart without adopting")
	# Force a real native forecast rejection in this PRIVATE fixture; inspect the
	# still-selectable empty Paths tab rather than merely testing its builder.
	game.career.shocks[0]["comparison_fixture_unknown_input"] = 1.0
	game.rate.get_line_edit().grab_focus()
	var invalid_bytes: PackedByteArray = game.career.encode()
	game._compare()
	await process_frame
	await process_frame
	var rejected: AcceptDialog = game.get_child(game.get_child_count() - 1)
	var rejected_tabs: TabContainer = rejected.find_children("*", "TabContainer", true, false)[0]
	check(rejected_tabs.current_tab == 1 and game.comparison_series.is_empty(), "Actual failed Compare opens error Details with no stale successful series")
	rejected_tabs.get_tab_bar().grab_focus()
	await key(rejected, KEY_LEFT)
	check(rejected_tabs.current_tab == 0 and rejected_tabs.get_child(0).charts.is_empty(), "Keyboard can inspect the unavailable Paths tab without false funding claims")
	await key(rejected, KEY_TAB)
	check(rejected.get_ok_button().has_focus(), "Zero-chart focus route goes directly from tabs to Close")
	await key(rejected, KEY_ESCAPE)
	await process_frame
	check(not is_instance_valid(rejected) and game.rate.get_line_edit().has_focus(), "Failed comparison Escape restores the actual invoking input")
	check(game.career.encode() == invalid_bytes, "Failed comparison and keyboard dismissal do not mutate the private career")
	game.career.shocks[0].erase("comparison_fixture_unknown_input")
	check(game.career.encode() == frozen, "Removing only the intentional invalid fixture restores exact original career bytes")
	root.size = Vector2i(1280, 840)
	game._start_career("base", 1)
	for checkpoint in [232, 233, 240]:
		while game.career.decisions.size() < checkpoint:
			var advanced: Dictionary = game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "hold"))
			check(advanced.ok, "Native late-career fixture")
			if not advanced.ok:
				await game._quit_app(1)
				return
		game._refresh(true)
		game._compare()
		await process_frame
		await process_frame
		var late: AcceptDialog = game.get_child(game.get_child_count() - 1)
		var late_tabs: TabContainer = late.find_children("*", "TabContainer", true, false)[0]
		var caption: Label = late_tabs.get_child(0).find_children("*", "Label", true, false)[0]
		check(caption.text.contains("diagnostic") == (checkpoint > 232), "Default graph warns exactly when its horizon crosses Q240")
		check(caption.text.contains("Career complete") == (checkpoint == 240), "Completed status is not shown prematurely")
		late.queue_free()
		await process_frame
		await process_frame
	if failures == 0:
		print("PASS: forecast graph parity, fail-closed data, native tab keys, inspection and read-only report; ", checks, " checks")
	await game._quit_app(1 if failures else 0)
