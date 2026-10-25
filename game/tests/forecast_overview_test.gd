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
	var frozen: PackedByteArray = game.career.encode()
	var policy: Dictionary = game._policy()
	var a: Dictionary = game.career.forecast(policy)
	var b: Dictionary = game.career.forecast(game.career.model.benchmark_policy(game.career.state, game.career.params, "hold"))
	var data := Overview.series(game.career.state, a, b)
	check(data.size() == 9, "Current point and eight forecast quarters")
	for index in range(9):
		for field in ["four_quarter_inflation_pct", "unemployment_rate_pct"]:
			check(data[index]["selected_" + field] == (game.career.state if index == 0 else a.states[index - 1])[field], "Exact selected data")
			check(data[index]["held_" + field] == (game.career.state if index == 0 else b.states[index - 1])[field], "Exact reference data")
	check(Overview.series({}, {"ok": true}, b).is_empty(), "Missing path fails closed")
	var broken := a.duplicate(true)
	broken.states[0].four_quarter_inflation_pct = NAN
	check(Overview.series(game.career.state, broken, b).is_empty(), "Nonfinite path fails closed")
	game._compare()
	await process_frame
	await process_frame
	var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	var tabs: TabContainer = dialog.find_children("*", "TabContainer", true, false)[0]
	var body: TextEdit = dialog.find_children("*", "TextEdit", true, false)[0]
	var pane = tabs.get_child(0)
	check(tabs.current_tab == 0 and pane.is_visible_in_tree() and not body.is_visible_in_tree(), "Paths replace opening text wall")
	check(tabs.get_tab_bar().has_focus() and pane.get_v_scroll_bar().value == 0.0, "Opening focus preserves the forecast heading and assumptions")
	check(pane.charts.size() == 2 and pane.charts[0].history == data and pane.charts[1].history == data, "Both charts use captured forecast series")
	check(pane.charts[0].keys == ["selected_four_quarter_inflation_pct", "held_four_quarter_inflation_pct"] and pane.charts[1].keys == ["selected_unemployment_rate_pct", "held_unemployment_rate_pct"], "Each chart selects the correct paired metric")
	for chart in pane.charts:
		check(chart.labels == ["Staged policy", "Hold reference"], "Both chart legends identify the same policy pair")
	pane.charts[0].grab_focus()
	await key(dialog, KEY_END)
	check(pane.charts[0].hovered == 8 and pane.charts[0].accessibility_description.contains("Conditional model path"), "Keyboard inspection retains future context")
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
