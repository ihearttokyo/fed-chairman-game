extends SceneTree
const Board = preload("res://play/objective_board.gd")
const Advice = preload("res://play/policy_advice.gd")
const Committee = preload("res://play/policy_committee.gd")
const Career = preload("res://play/career.gd")
class NoForecastMain:
	extends "res://play/main.gd"
	func _preview() -> void: pass
	func real_preview() -> void: super._preview()
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func _initialize() -> void: call_deferred("run")
func key(window: Window, code: Key) -> void:
	var receiver: Window = root if window.is_embedded() else window
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	receiver.window_input.emit(event)
	receiver.push_input(event)
	event = event.duplicate()
	event.pressed = false
	receiver.window_input.emit(event)
	receiver.push_input(event)
	await process_frame
	await process_frame
func run() -> void:
	var career := Career.new()
	check(career.start("policy_career", 1).ok, "scored career starts")
	var m: Dictionary = career.mandate_assessment()
	var initial := var_to_bytes(m)
	var shown := Board.present(m, {}, false)
	check(shown.ok and shown.metrics.size() == 3 and shown.title.contains("Q0/240") and shown.title.contains("In progress"), "initial objective is progress, never a victory")
	check(shown.metrics[0].status == "Building" and shown.metrics[2].status == "No scored need", "no observations and no funding need are neutral")
	check(shown.metrics[0].value_text.begins_with("—"), "zero observations are not presented as measured perfect performance")
	check(var_to_bytes(m) == initial, "presenter does not mutate authoritative assessment")
	m.quarters = 24
	m.inflation_miss = 0.4
	m.recent_inflation_miss = 1.0000001
	m.employment_shortfall = 0.1
	m.recent_employment_shortfall = 0.8
	m.prices_met = false
	m.employment_met = true
	shown = Board.present(m, {}, false)
	check(shown.metrics[0].label == "Inflation miss 12q" and shown.metrics[0].value_text.begins_with(">1.000") and shown.metrics[0].status == "Above", "recent-only price miss cannot hide in a career average or rounding")
	check(shown.metrics[1].label == "Job shortfall 12q" and shown.metrics[1].limit == 1.0, "jobs selects the more binding normalized constraint, not larger raw unit alone")
	m.employment_shortfall = 0.6
	m.employment_met = false
	shown = Board.present(m, {}, false)
	check(shown.metrics[1].label == "Job shortfall avg" and shown.metrics[1].limit == 0.5 and shown.metrics[1].status == "Above", "stricter career employment limit remains visible")
	for need in [3.0, 82.0]:
		m.funding_active = true
		m.funding_coverable = need
		var required: float = Career.MANDATE_FUNDING_COVERAGE_MIN * need
		for delta in [-0.00000001, 0.0, 0.00000001]:
			m.funding_applied = required + delta
			m.funding_coverage = m.funding_applied / need
			m.funding_met = m.funding_applied >= required
			shown = Board.present(m, {}, false)
			var prefix := "<" if delta < 0 else ">" if delta > 0 else ""
			check(shown.metrics[2].value_text == prefix + "95.000 / 95%", "funding boundary follows exact applied-versus-required scoring")
			check(shown.metrics[2].met == m.funding_met and shown.metrics[2].status == ("Target met" if m.funding_met else "Below"), "funding color/status uses authoritative unrounded result")
	check(Board.boundary_text(0.9999999, 1) == "<1.000" and Board.boundary_text(1.0000001, 1) == ">1.000", "strict boundaries retain direction")
	check(Board.boundary_text(1e30, 1).length() < 20, "extreme values stay readable without capping their data")
	var practice := m.duplicate(true)
	practice.eligible = false
	shown = Board.present(practice, {}, false)
	check(shown.title.contains("Practice") and shown.metrics.is_empty(), "unscored practice never shows an earned challenge")
	career.start("stagflation_bank_run", 417)
	var r: Dictionary = career.recovery_assessment()
	shown = Board.present({}, r, true)
	check(shown.title.begins_with("RECOVERY v1") and shown.metrics[0].status == "Building" and shown.metrics[0].label.contains("0q"), "recovery discloses incomplete observed window")
	r.quarters = 12
	r.window_quarters = 12
	r.inflation_miss = 1.0000001
	shown = Board.present({}, r, true)
	check(shown.metrics[0].ready and shown.metrics[0].status == "Above" and shown.metrics[0].value_text.begins_with(">1.000"), "mature recovery uses inclusive 1pp window target")
	root.size = Vector2i(1440, 960)
	var game = NoForecastMain.new()
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	check(game.objective_panel.visible and game.objective_board.snapshot.metrics.size() == 3, "actual HUD contains graphical challenge progress")
	var saved: PackedByteArray = game.career.encode()
	var staged: Dictionary = game._policy()
	game.objective_board.details_button.pressed.emit()
	await process_frame
	var dialog = game.get_child(game.get_child_count() - 1)
	check(dialog.title == "Challenge progress" and dialog.get_child(0).text.contains("No completed quarters.") and not dialog.get_child(0).text.contains("Career averages: prices 0.") and dialog.get_child(0).text.contains("fictional") and dialog.get_child(0).text.contains("95%"), "real Details exposes exact measures and full scoring qualification")
	dialog.get_ok_button().pressed.emit()
	await process_frame
	check(game.career.encode() == saved and game._policy() == staged, "reading graphics/details preserves career and staged tools")
	var board = game.objective_board
	for index in range(3):
		check(not board.values[index].text.is_empty() and board.values[index].accessibility_description.contains(board.values[index].text), "numbers/status accompany color in assistive output")
	game._start_career("stagflation_bank_run", 417)
	for quarter in range(12):
		var policy: Dictionary = Advice.policy(game.career.state, game.career.params)
		var n: float = game.career.model.nominal_gdp_ratio(game.career.state)
		policy.liquidity_request_pct_initial_gdp = Committee.proposals(game.career.state, game.career.params, game.career.current_briefing(), n)[2].lending_offer_current_gdp * n
		check(game.career.advance(policy).ok, "graph layout fixture uses a real native current-information career")
	game._refresh(true)
	root.size = Vector2i(1280, 840)
	game.size = Vector2(root.size)
	game.cockpit_scroll.scroll_vertical = 0
	for frame in range(4): await process_frame
	check(game.cockpit_scroll.get_global_rect().encloses(board.get_global_rect()), "completed score cards fit the ordinary viewport without hiding behind the action bar")
	for index in range(3):
		check(board.get_global_rect().encloses(board.states[index].get_global_rect()) and board.get_global_rect().encloses(board.names[index].get_global_rect()), "score status stays inside its graphic panel")
	game.real_preview()
	for frame in range(3): await process_frame
	game.cockpit_scroll.grab_focus()
	await key(root, KEY_END)
	check(game.cockpit_scroll.get_global_rect().encloses(game.forecast_label.get_global_rect()), "real conditional projection is reachable by keyboard scrolling above the pinned action bar")
	await key(root, KEY_HOME)
	game.set_process(false) # Drive the real clock explicitly below.
	game.follow_up_toggle.set_pressed_no_signal(true)
	game._advance()
	check(game.routine.active and game.career.decisions.size() == 13, "real attended adoption arms routine before opening objective details")
	var armed_state: PackedByteArray = game.career.encode()
	board.details_button.grab_focus()
	await key(root, KEY_ENTER)
	dialog = game.get_child(game.get_child_count() - 1)
	check(dialog is AcceptDialog and dialog.title == "Challenge progress" and not game.routine.active, "native Enter opens objective details and cancels active follow-up")
	check(dialog.get_child(0).text.contains("Observed window: 12/12") and not dialog.get_child(0).text.contains("Career averages:"), "recovery details use its rolling criterion, not a lifetime penalty")
	await key(dialog, KEY_ESCAPE)
	check(game.get_viewport().gui_get_focus_owner() == board.details_button, "native Escape restores the invoking objective button")
	game._process(10.0)
	check(game.career.encode() == armed_state and not game.follow_up_toggle.button_pressed, "objective report cancellation prevents any later automatic adoption")
	var invalid: Dictionary = game.career.mandate_assessment().duplicate(true)
	invalid.inflation_miss = NAN
	board.update_assessment(invalid, {}, false)
	check(not board.snapshot.ok and board.details_button.disabled and board.values[0].text.is_empty() and board.values[0].accessibility_description.is_empty(), "invalid data clears stale rendered/assistive values")
	game._start_career("base", 1)
	check(not game.objective_panel.visible and game.mandate_label.text.contains("Practice"), "practice hides unnecessary score cards but keeps explicit status")
	game.music.free()
	game.queue_free()
	await process_frame
	var deadline := Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < deadline: await process_frame
	print("%s: graphical objective board %d checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
