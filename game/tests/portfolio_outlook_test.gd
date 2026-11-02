extends SceneTree
const Career = preload("res://play/career.gd")
const Outlook = preload("res://play/portfolio_outlook.gd")
var checks := 0
var failures := 0

class CountingCareer:
	extends "res://play/career.gd"
	var forecast_calls := 0
	func forecast(policy: Dictionary, follow_guidance: bool = false) -> Dictionary:
		forecast_calls += 1
		return super.forecast(policy, follow_guidance)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func settle() -> void:
	for frame in range(5):
		await process_frame

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var career := Career.new()
	check(career.start("base", 11).ok, "Native baseline begins")
	var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold")
	var frozen: PackedByteArray = career.encode()
	var forecast: Dictionary = career.forecast(policy)
	var expected := Outlook.present(forecast, 0, 240)
	check(expected.ok and expected.rows.size() == 8 and expected.first_quarter == 1 and expected.last_quarter == 8,
		"Full normal career presents exactly the existing eight playable preview states")
	check(career.encode() == frozen, "Building an outlook never mutates a career or save payload")
	if expected.ok:
		for index in range(expected.rows.size()):
			var row: Dictionary = expected.rows[index]
			var state: Dictionary = forecast.states[index]
			check(row.quarter_index == state.quarter_index and row.due == state.principal_due_pct_initial_gdp,
				"Timeline row is source-exact for principal due at Q%d" % state.quarter_index)
			check(row.runoff + row.reinvested == row.due and row.runoff <= row.due,
				"Maturity split reconciles at Q%d" % state.quarter_index)
			check(row.securities == state.asset_stock_pct_initial_gdp and row.reserves == state.reserves_pct_initial_gdp,
				"Stock readout retains native projected values at Q%d" % state.quarter_index)
		var late := forecast.duplicate(true)
		for index in range(late.states.size()):
			late.states[index].quarter_index = 240 + index
		var last := Outlook.present(late, 239, 240)
		check(last.ok and last.rows.size() == 1 and last.rows[0].quarter_index == 240,
			"Final decision exposes only Q240 and excludes diagnostic continuation")
		check(not Outlook.present(late, 240, 240).visible, "Completed career cannot present a next-quarter maturity path")
	var no_reinvest: Dictionary = policy.duplicate(true)
	no_reinvest.reinvest_principal = false
	var natural: Dictionary = career.forecast(no_reinvest)
	var natural_snapshot := Outlook.present(natural, 0, 240)
	check(natural_snapshot.ok, "Natural-runoff forecast can be inspected")
	if natural_snapshot.ok:
		for row in natural_snapshot.rows:
			check(row.runoff == row.due and row.reinvested == 0.0, "Reinvestment-off path shows the native full natural runoff")
	var clipped := Outlook.present({}, 0, 240)
	check(not clipped.ok and clipped.rows.is_empty(), "Failed forecast clears the outlook instead of retaining stale values")
	for field in ["principal_due_pct_initial_gdp", "principal_reinvestment_pct_initial_gdp", "reserves_pct_initial_gdp"]:
		var bad := forecast.duplicate(true)
		bad.states[0][field] = NAN
		check(not Outlook.present(bad, 0, 240).ok, "Nonfinite %s fails closed" % field)
	var missing := forecast.duplicate(true)
	missing.states[0].erase("treasury_redemption_pct_initial_gdp")
	check(not Outlook.present(missing, 0, 240).ok, "Missing maturity component fails closed")
	var shifted := forecast.duplicate(true)
	shifted.states[1].quarter_index = 99
	check(not Outlook.present(shifted, 0, 240).ok, "Misaligned quarter cannot appear as an outlook")
	var panes := Outlook.new()
	root.add_child(panes)
	panes.build(expected)
	check(panes.timeline.visible and panes.timeline.rows.size() == 8 and panes.detail.accessibility_description.contains("principal due"),
		"Built timeline exposes readable selected-quarter details")
	panes.timeline.inspect(7)
	check(panes.detail.text.begins_with("Q8") and panes.timeline.accessibility_description.contains("no new future shocks"),
		"Keyboard selection readout explains the selected quarter and conditional assumptions")
	panes.free()
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await settle()
	var counted := CountingCareer.new()
	game.career = counted
	game._start_career("base", 11)
	game._refresh(true)
	await settle()
	check(game.portfolio_outlook_button.visible and not game.portfolio_outlook_button.disabled,
		"Normal career exposes an enabled balance-sheet maturity outlook")
	var calls: int = counted.forecast_calls
	var before: PackedByteArray = counted.encode()
	game._portfolio_outlook()
	await settle()
	var dialog: Window = game.get_child(game.get_child_count() - 1)
	var pane = dialog.get_child(0) if dialog.get_child_count() > 0 else null
	check(dialog is AcceptDialog and counted.forecast_calls == calls,
		"Opening the outlook reads the cached path without invoking another forecast")
	if dialog is Window and pane != null and pane is Outlook:
		pane.timeline.grab_focus()
		var end_key := InputEventKey.new()
		end_key.keycode = KEY_END
		end_key.pressed = true
		pane.timeline._gui_input(end_key)
		check(pane.timeline.has_focus() and pane.timeline.selected == 7 and pane.detail.text.begins_with("Q8"),
			"Timeline keyboard handler selects the endpoint and updates the actual report readout")
		check(dialog.visible, "Inspecting a maturity bar leaves the read-only report open")
		dialog.queue_free()
		await settle()
	check(counted.encode() == before and counted.decisions.is_empty(), "Inspecting, navigating and dismissing the outlook never adopts or saves")
	check(not game.portfolio_outlook_button.disabled and not game._is_workout(), "Read-only report returns to the normal staged decision")
	if failures == 0:
		print("PASS: cached maturity path, principal reconciliation, horizon clipping, fail-closed presentation and read-only keyboard inspection; ", checks, " checks")
	await game._quit_app(1 if failures else 0)
