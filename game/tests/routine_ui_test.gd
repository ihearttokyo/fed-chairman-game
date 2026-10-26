extends SceneTree

class NoForecastMain:
	extends "res://play/main.gd"
	var reject_staged := false
	func _policy() -> Dictionary:
		var policy := super._policy()
		if reject_staged:
			policy.policy_rate_request_pct = 3.505
		return policy
	func _preview() -> void:
		if get("routine") != null and get("routine").active and not loading_controls:
			call("_finish_follow_up", "Policy edited", false)

class CountedEconomy:
	extends "res://model/economy.gd"
	var attempts := 0
	var confirmed := 0
	var known_rejects := 0
	func step(state: Dictionary, policy: Dictionary, shock: Dictionary, params: Dictionary) -> Dictionary:
		attempts += 1
		var result: Dictionary = super.step(state, policy, shock, params)
		if result.ok:
			confirmed += 1
		elif policy.policy_rate_request_pct == 3.505 and result.error.contains("increments"):
			known_rejects += 1
		return result

var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1440, 960)
	var game = NoForecastMain.new()
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	game.set_process(false) # Drive production frame timing; do not bypass pacing.
	check(game.get("follow_up_toggle") != null, "optional routine-follow-up control exists")
	if game.get("follow_up_toggle") != null:
		check(game.follow_up_toggle.get_parent() == game.decision_button.get_parent(), "routine follow-up is next to Adopt, not below the forecast fold")
	if game.get("follow_up_toggle") == null:
		game.music.free()
		game.queue_free()
		await process_frame
		await mixer_release()
		quit(1)
		return
	game._start_career("base", 1)
	var model := CountedEconomy.new()
	game.career.model = model
	var cycle := [[0.02, 0.005, 0.002], [-0.02, -0.005, -0.002], [0.01, -0.002, 0.001], [-0.01, 0.002, -0.001]]
	for index in range(240):
		var pulse: Array = cycle[index % 4]
		game.career.shocks[index] = {"demand_shock_pct": pulse[0], "supply_innovation_pct": pulse[1], "r_star_change_pct": pulse[2]}
	game._refresh(true)
	game.career.shocks[4].supply_innovation_pct = 1.0
	check(not game.follow_up_toggle.button_pressed, "new career starts attended")
	game._staff_rule()
	game.assets.value = 0.01
	game.reinvestment.button_pressed = false
	game.follow_up_toggle.button_pressed = true
	var first: Dictionary = game._policy()
	game._advance()
	check(game.career.decisions.size() == 1 and game.career.decisions[0] == first, "first adoption preserves every staged field")
	for _frame in range(3):
		game._process(1.0 / 60.0)
		await process_frame
	check(game.career.decisions.size() == 1 and game.stop_follow_up.visible, "three ordinary frames leave a visible input opportunity before the first automatic quarter")
	var before_stall: PackedByteArray = game.career.encode()
	game._process(3600.0)
	check(game.career.encode() == before_stall and game.career.decisions.size() == 1 and game.routine.active, "a stalled frame cannot consume the human input interval or catch up multiple quarters")
	var saw_current_feedback := false
	for _frame in range(90):
		game._process(0.1)
		await process_frame
		if game.career.decisions.size() == 2:
			saw_current_feedback = game.quarter_label.text.contains("MEETING 3") and game.consequence.text.contains("Q2 outcome") and game.forecast_label.text.contains("paused")
		if not game.routine.active:
			break
	check(saw_current_feedback, "paced automatic quarter refreshes current data and outcomes without leaving a stale conditional preview")
	check(game.career.decisions.size() == 4 and not game.routine.active, "quiet follow-up stops after four total outcomes")
	check(not game.follow_up_toggle.button_pressed and not game.stop_follow_up.visible, "return requires a fresh delegation choice")
	check(game.last_follow_up_reasons == ["QUOTA_EXHAUSTED", "CURRENT_NEWS"], "scheduled return retains simultaneous current-news reasons")
	for index in range(1, game.career.decisions.size()):
		var policy: Dictionary = game.career.decisions[index]
		check(policy.asset_flow_request_pct_initial_gdp == 0 and policy.liquidity_request_pct_initial_gdp == 0 and not policy.reinvest_principal, "one-shots reset while false portfolio switches persist")
		var observed: Dictionary = game.career.history[index]
		var params: Dictionary = game.career.params
		var rate: float = params.initial_r_star_pct + float("%.2f" % observed.expected_long_inflation_pct) + params.policy_inflation_response * (float("%.2f" % observed.four_quarter_inflation_pct) - params.inflation_target_pct) + params.policy_output_gap_response * float("%.2f" % observed.output_gap_pct)
		rate = floorf(rate / params.minimum_rate_increment_pct + 0.5) * params.minimum_rate_increment_pct
		check(policy.policy_rate_request_pct == rate and policy.guidance_rate_pct == rate and policy.guidance_inflation_sensitivity == params.policy_inflation_response and policy.guidance_output_gap_sensitivity == params.policy_output_gap_response, "actual paced automatic decisions match independently calculated public-data staff advice and guidance")
	check(game.consequence.text.begins_with("Q1–Q4 outcome") and game.consequence.text.contains("Promise %.1f/100" % (100 * game.career.state.guidance_followthrough_score)) and game.outcome_drivers.visible and game.outcome_drivers.details_text.contains("Q1–Q4") and game.outcome_drivers.details_text.contains("not isolated policy effects") and not game.consequence.text.contains("Equation contributions"), "returned graphic covers the whole completed segment and keeps reconciliation behind Details")
	game.follow_up_toggle.button_pressed = true
	game._advance()
	var adopted: int = game.career.decisions.size()
	game.rate.value = -1.25
	check(not game.routine.active and game.rate.value == -1.25, "editing stops automation without erasing the signed quote")
	await process_frame
	check(game.career.decisions.size() == adopted, "edit prevents another automatic adoption")
	game.follow_up_toggle.button_pressed = true
	game._advance()
	adopted = game.career.decisions.size()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	game.get_viewport().push_input(escape)
	await process_frame
	check(not game.routine.active and game.career.decisions.size() == adopted, "Escape stops before the next automatic quarter")
	check(game.rate.get_line_edit().has_focus(), "Escape returns focus to the current decision")
	game.follow_up_toggle.button_pressed = true
	game._advance()
	adopted = game.career.decisions.size()
	game._advance()
	check(game.career.decisions.size() == adopted and not game.routine.active, "repeated adoption while following up stops rather than double-adopts")
	game.follow_up_toggle.button_pressed = true
	game._advance()
	adopted = game.career.decisions.size()
	game._journal()
	check(not game.routine.active, "opening a report cancels follow-up")
	var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	dialog.queue_free()
	await process_frame
	check(game.career.decisions.size() == adopted, "closing a report does not resume automatic permission")
	game.follow_up_toggle.button_pressed = true
	game._advance()
	adopted = game.career.decisions.size()
	var modifier := InputEventKey.new()
	modifier.keycode = KEY_META
	modifier.pressed = true
	game._input(modifier)
	check(game.routine.active, "bare Command does not disarm before modified Return can be consumed")
	var modified_return := InputEventKey.new()
	modified_return.keycode = KEY_ENTER
	modified_return.meta_pressed = true
	modified_return.pressed = true
	game._input(modified_return)
	check(not game.routine.active and game.career.decisions.size() == adopted, "modified Return during follow-up stops without another adoption")
	game.follow_up_toggle.button_pressed = true
	game._advance()
	adopted = game.career.decisions.size()
	var prior_rate: float = game.rate.value
	game.rate.get_line_edit().set_block_signals(true)
	game.rate.get_line_edit().text = "-2.37"
	game.rate.get_line_edit().set_block_signals(false)
	check(game.routine.active and game.rate.value == prior_rate and game.rate.get_line_edit().text != game.rate.get_meta("numeric_text"), "raw edit fixture changes only text, without key or value-change signals")
	game._follow_up_frame()
	await process_frame
	await process_frame
	check(not game.routine.active and game.career.decisions.size() == adopted and game.rate.get_line_edit().text == "-2.37", "text-only numeric draft stops before adoption and remains unsubmitted")
	game.follow_up_toggle.button_pressed = true
	game._advance()
	adopted = game.career.decisions.size()
	game.decision_button.grab_focus()
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	game.get_viewport().push_input(enter)
	check(not game.routine.active and game.career.decisions.size() == adopted, "dispatched Return on Adopt is stop-only during follow-up")
	game.follow_up_toggle.button_pressed = true
	game._advance()
	adopted = game.career.decisions.size()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = game.decision_button.get_global_rect().get_center()
	check(game.get_viewport().get_visible_rect().has_point(click.position), "dispatched mouse activation targets the actual viewport")
	click.pressed = true
	game.get_viewport().push_input(click)
	var release := click.duplicate()
	release.pressed = false
	game.get_viewport().push_input(release)
	check(not game.routine.active and game.career.decisions.size() == adopted, "dispatched click on Adopt is stop-only during follow-up")
	game.follow_up_toggle.button_pressed = true
	game._advance()
	adopted = game.career.decisions.size()
	game.stop_follow_up.grab_focus()
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	game.get_viewport().push_input(space)
	check(not game.routine.active and game.career.decisions.size() == adopted and game.rate.get_line_edit().has_focus(), "keyboard Stop returns decision focus without adoption")
	var preserved: PackedByteArray = game.career.encode()
	var staged: Dictionary = game._policy()
	game.reject_staged = true
	game.follow_up_toggle.button_pressed = true
	game._advance()
	game.reject_staged = false
	check(game.career.encode() == preserved and not game.routine.active and not game.follow_up_toggle.button_pressed, "native failed adoption preserves the complete career and clears follow-up")
	check(game._policy() == staged and game.status_label.text.contains("Last valid quarter retained"), "native failed adoption preserves the user's draft and reports recovery")
	check(model.attempts == 14 and model.confirmed == 13 and model.known_rejects == 1, "interaction fixture counts thirteen adoptions and one deliberate native rejection, with zero forecasts")
	game.music.free()
	game.queue_free()
	await process_frame
	var timing_game = NoForecastMain.new()
	root.add_child(timing_game)
	timing_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	timing_game.set_process(false)
	timing_game._start_career("base", 1)
	var timing_model := CountedEconomy.new()
	timing_game.career.model = timing_model
	for index in range(8):
		timing_game.career.shocks[index] = {"demand_shock_pct": 0.0, "supply_innovation_pct": 0.0, "r_star_change_pct": 0.0}
	timing_game._refresh(true)
	timing_game._staff_rule()
	timing_game.assets.value = 0.01
	timing_game.reinvestment.button_pressed = false
	timing_game.follow_up_toggle.button_pressed = true
	timing_game._advance()
	var timing_before: PackedByteArray = timing_game.career.encode()
	for _frame in range(5):
		timing_game._process(0.1)
		await process_frame
	check(timing_game.routine.active and timing_game.career.decisions.size() == 1 and timing_game.stop_follow_up.visible, "quiet timing fixture stays interruptible halfway through its input interval")
	var timed_escape := InputEventKey.new()
	timed_escape.keycode = KEY_ESCAPE
	timed_escape.pressed = true
	timing_game.get_viewport().push_input(timed_escape)
	check(not timing_game.routine.active and timing_game.career.encode() == timing_before and timing_game.rate.get_line_edit().has_focus(), "Window-dispatched Escape after a partial interval stops without another transition")
	timed_escape.pressed = false
	timing_game.get_viewport().push_input(timed_escape)
	for _frame in range(25):
		timing_game._process(0.1)
		await process_frame
	check(timing_game.career.encode() == timing_before and timing_model.attempts == 1 and timing_model.confirmed == 1, "cancelled pacing cannot resume later; separate timing fixture has exactly one confirmed native transition")
	# The single committee opener replaces priority selection and stops active follow-up.
	check(timing_game.routine.arm(timing_game.career.state, timing_game.career.params, timing_game._policy(), Engine.get_process_frames()).ok, "committee-open fixture re-arms without another economic transition")
	timing_game.segment_start = 0
	timing_game.follow_up_toggle.set_pressed_no_signal(true)
	var priority_policy: Dictionary = timing_game._policy()
	var priority_draft: String = timing_game.rate.get_line_edit().text
	var before_docket_attempts: int = timing_model.attempts
	var before_docket_confirmed: int = timing_model.confirmed
	timing_game.committee_button.pressed.emit()
	check(not timing_game.routine.active and not timing_game.follow_up_toggle.button_pressed, "pointer committee opener cancels active routine follow-up")
	check(timing_game.committee_docket.visible and timing_game.career.encode() == timing_before and timing_game._policy() == priority_policy and timing_game.rate.get_line_edit().text == priority_draft, "opening docket preserves policy and numeric draft without adopting or staging")
	check(timing_game.docket_forecast_calls == 5 and timing_model.attempts == before_docket_attempts + 40 and timing_model.confirmed == before_docket_confirmed + 40, "explicit docket open records five eight-quarter native forecasts, not economic adoptions")
	timing_game.committee_docket.queue_free()
	for _frame in range(25):
		timing_game._process(0.1)
		await process_frame
	check(timing_game.career.encode() == timing_before and timing_model.attempts == before_docket_attempts + 40, "docket-cancelled follow-up cannot resume or recompute on later frames")
	timing_game.follow_up_toggle.set_pressed_no_signal(true)
	timing_game.committee_button.pressed.emit()
	check(timing_game.follow_up_toggle.button_pressed and timing_game._policy() == priority_policy and timing_game.career.encode() == timing_before, "inactive docket opening preserves the player's next-adoption follow-up preference and policy")
	check(timing_game.docket_forecast_calls == 10 and timing_model.attempts == before_docket_attempts + 80 and timing_model.confirmed == before_docket_confirmed + 80, "two explicit docket opens account exactly for eighty projected transitions")
	timing_game.music.free()
	timing_game.queue_free()
	await process_frame
	await mixer_release()
	print("TIMING_INPUT: simulated frame time, native Window Escape, two explicit docket forecasts; attempts=%d confirmed=%d" % [timing_model.attempts, timing_model.confirmed])
	print("%s: routine UI %d checks, %d failures; attempts=%d confirmed=%d known_rejects=%d unknown=%d; ordinary preview forecasts disabled" % ["PASS" if failures == 0 else "FAIL", checks, failures, model.attempts, model.confirmed, model.known_rejects, model.attempts - model.confirmed - model.known_rejects])
	quit(0 if failures == 0 else 1)

func mixer_release() -> void:
	var deadline := Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < deadline:
		await process_frame
