extends SceneTree
## Presentation + actual Main/cached forecast integration; no live GUI claim.
const Outlook = preload("res://play/bank_outlook.gd")
var checks := 0
var failures := 0

class CountingModel:
	extends "res://model/economy.gd"
	var steps := 0
	func bank_workout_transition(state: Dictionary, policy: Dictionary, shocks: Dictionary, params: Dictionary, bank: Variant, order: Variant, credit: Dictionary = {}) -> Dictionary:
		steps += 1
		return super.bank_workout_transition(state, policy, shocks, params, bank, order, credit)

class CountingWorkout:
	extends "res://play/workout_career.gd"
	var calls := 0
	var last: Dictionary = {}
	var fail_next := false
	func forecast(policy: Dictionary, follow: bool = false) -> Dictionary:
		calls += 1
		last = {"ok": false, "error": "test unavailable"} if fail_next else super.forecast(policy, follow)
		return last

class CountingPriced:
	extends "res://play/priced_workout_career.gd"
	var calls := 0
	var last: Dictionary = {}
	var fail_next := false
	func forecast(policy: Dictionary, follow: bool = false) -> Dictionary:
		calls += 1
		last = {"ok": false, "error": "test unavailable"} if fail_next else super.forecast(policy, follow)
		return last

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", text)

func fixture(quarter := 0) -> Dictionary:
	var data := {"ok": true, "states": [], "bank_results": [], "credit_results": []}
	for index in range(8):
		data.states.append({"quarter_index": quarter + index + 1})
		data.bank_results.append({"equity_after": 5.0 + index, "deposit_due": 2.0, "withdrawals_paid": 0.5, "remaining_queue": 1.5, "loan_arrears": float(index) * 0.1})
		data.credit_results.append({"bank_equity_after": -0.2 - index})
	return data

func pure_cases() -> void:
	var data := fixture()
	var frozen := var_to_bytes(data)
	var priced := Outlook.present(data, 0, true)
	var ordinary := Outlook.present(data, 0, false)
	check(priced.ok and priced.first == -0.2 and priced.minimum == -7.2 and ordinary.first == 5.0 and ordinary.minimum == 5.0, "priced uses interest-inclusive credit capital despite conflicting positive raw bank equity")
	check(priced.values.size() == 8 and priced.due == 2.0 and priced.paid == 0.5 and priced.payment_fraction == 0.25, "payment meter consumes only the first native due/payment, never sums repeated queued dues")
	check(priced.queued_peak == 1.5 and is_equal_approx(priced.overdue_peak, 0.7), "persistent queues/overdue principal remain visible as separate peaks, not summed liabilities")
	check(var_to_bytes(data) == frozen, "presentation does not mutate supplied forecast arrays")
	var late := fixture(7)
	late.credit_results[1].bank_equity_after = -10000.0
	late.bank_results[1].equity_after = -10000.0
	var q7 := Outlook.present(late, 7, true)
	check(Outlook.present(late, 7, false).values == [5.0] and Outlook.present(late, 7, false).minimum == 5.0, "ordinary Q7 also excludes worse diagnostic continuation")
	check(q7.ok and q7.values == [-0.2] and q7.minimum == -0.2 and q7.first_quarter == 8, "Q7 keeps one playable point and excludes the worse diagnostic Q9 from capital minimum")
	late.states[1] = null
	late.credit_results[1] = NAN
	late.bank_results[1] = null
	check(Outlook.present(late, 7, true) == q7, "unread diagnostic continuation cannot corrupt the playable panel")
	for priced_mode in [false, true]:
		check(not Outlook.present(data, 8, priced_mode).visible and not Outlook.present(data, 0, priced_mode, false).visible, "complete and normal modes clear/hide rather than retain stale values")
	var no_due := fixture()
	no_due.bank_results[0].deposit_due = 0.0
	no_due.bank_results[0].withdrawals_paid = 0.0
	check(Outlook.present(no_due, 0, false).payment_text == "Q+1 withdrawals: none due" and Outlook.present(no_due, 0, false).payment_fraction == 0, "no withdrawals due is not a fabricated 100-percent payment bar")
	var rounded := fixture()
	rounded.bank_results[0].deposit_due = 1.0
	rounded.bank_results[0].withdrawals_paid = 0.999999
	check(Outlook.present(rounded, 0, false).payment_text.contains("<due"), "subprecision short payment cannot display rounded equality")
	# Retained actual priced-path capital fixtures from the parent's seed1729
	# evidence, not a new forecast or a synthetic realized path.
	for precise in [1e-300, -1e-300, 0.12345678901234567, 0.00202744087937889, -0.0082828843882653, -0.000766071548965963]:
		check(JSON.parse_string(Outlook.unrounded_amount(precise)) == precise, "actual unrounded formatter round-trips the exact source float")
	for tiny in [-1e-12, -1e-300, 1e-12]:
		check(Outlook.signed_amount(tiny).contains("<0.0001") and Outlook.signed_amount(tiny).begins_with("-" if tiny < 0 else "+"), "small capital retains its true nonzero sign")
	var plot := Outlook.CapitalPath.new()
	plot.size = Vector2(388, 86)
	plot.values = [1.0, -1e-12, 1e-12, 0.0]
	check(plot.point_at(1).y == 44.0 and plot.point_at(2).y == 44.0, "negative control: native Vector2 really collapses tiny signed capital onto zero")
	check(plot.render_state(1) == "below_resolution" and plot.render_state(2) == "below_resolution" and plot.render_state(3) == "zero" and plot.drawable_samples() == [0, 3], "renderer omits subpixel nonzero samples/segments, retaining only genuine zero and resolvable points")
	check(plot.resolution_caption().contains("Q2 −") and plot.resolution_caption().contains("Q3 +"), "visible below-resolution caption identifies affected samples and their true signs")
	plot.values = [-1e-300]
	check(plot.render_state(0) == "point" and plot.point_at(0).y > 44, "small all-negative capital remains a real negative point when its own domain resolves it")
	for extent in [1e-300, 0.0, 0.012345, 1000.0, 1.7e308]:
		plot.values = [extent]
		check(plot.scale_text().length() <= 11 and plot.scale_text().to_float() > 0 and is_finite(plot.scale_text().to_float()), "axis extent is concise, finite and nonzero, including true-zero domain and float extremes")
	plot.free()
	for key in ["states", "bank_results", "credit_results"]:
		for invalid in [[], {}, [null]]:
			var bad := fixture()
			bad[key] = invalid
			check(not Outlook.present(bad, 0, true).ok, "missing/malformed playable array fails closed: " + key)
	for field in ["equity_after", "remaining_queue", "loan_arrears", "deposit_due", "withdrawals_paid"]:
		for invalid in [NAN, INF, -INF, true, null, "1", 9007199254740993]:
			var bad := fixture()
			bad.bank_results[0][field] = invalid
			check(not Outlook.present(bad, 0, false).ok, "nonfinite/non-numeric native field refuses: " + field)
		var missing := fixture()
		missing.bank_results[0].erase(field)
		check(not Outlook.present(missing, 0, false).ok, "missing native field never becomes zero: " + field)
	for invalid in [NAN, INF, true, null, "1"]:
		var bad := fixture()
		bad.credit_results[3].bank_equity_after = invalid
		check(not Outlook.present(bad, 0, true).ok, "invalid all-in capital cannot fall back to raw bank mark")
	var gap := fixture()
	gap.states[2].quarter_index = 5
	check(not Outlook.present(gap, 0, false).ok, "wrong quarter path cannot impersonate the playable horizon")
	var bad_due := fixture()
	bad_due.bank_results[0].withdrawals_paid = 3.0
	check(not Outlook.present(bad_due, 0, false).ok, "paid above due is not a valid meter")

func settle() -> void:
	for frame in range(5):
		await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame
	await process_frame

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	pure_cases()
	root.size = Vector2i(1440, 960)
	var game: Control = load("res://main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.save_path = "user://bank-outlook-normal.save"
	game._save()
	var saved := FileAccess.get_file_as_bytes(game.save_path)
	check(not game.bank_outlook.visible and game.bank_outlook.path not in game._keyboard_focus_order(), "normal career never exposes the bank forecast panel or chart focus route")
	for priced_mode in [false, true]:
		var career: Variant = CountingPriced.new() if priced_mode else CountingWorkout.new()
		var recipe: Dictionary = career.model.bank_workout_opening(career.params)
		check(career.start_episode(recipe.bank, recipe.requests, recipe.haircut_pct, recipe.pledgeable_share, "stagflation_bank_run", 417, recipe.remaining_request_index).ok, "real authored lab starts")
		career.model = CountingModel.new()
		game.career = career
		game._refresh(true)
		await settle()
		var calls: int = career.calls
		var steps: int = career.model.steps
		var frozen: PackedByteArray = career.encode()
		game._preview()
		check(career.calls == calls + 1 and career.model.steps == steps + 8, "Main preview adds exactly one forecast and its existing eight transitions")
		check(game.bank_outlook.snapshot == Outlook.present(career.last, 0, priced_mode) and game.bank_outlook.snapshot.ok, "Main consumes that exact cached forecast in each lab mode")
		check(career.encode() == frozen and FileAccess.get_file_as_bytes(game.save_path) == saved, "new outlook neither adopts nor writes the normal save")
		check(game.bank_outlook.path in game._keyboard_focus_order(), "valid lab graph participates in the real keyboard cycle")
		var retained: Dictionary = career.last.duplicate(true)
		var closest: float = INF
		for value in game.bank_outlook.snapshot.values:
			if absf(value) < absf(closest):
				closest = value
		check(JSON.parse_string(Outlook.unrounded_amount(closest)) == closest, "unrounded formatter exactly round-trips closest-to-zero actual cached capital")
		check(game.bank_outlook.resolution.text.begins_with("Capital scale ±") and game.bank_outlook.path.accessibility_description.contains(Outlook.unrounded_amount(game.bank_outlook.path.values[game.bank_outlook.path.selected])), "visible numeric extent and inspected full precision use the renderer's actual data")
		# Actual native first settlement is the passthrough forecast's same result.
		var actual: Dictionary = career.advance(game._policy())
		check(actual.ok and actual.bank_result == retained.bank_results[0], "ordinary/priced forecast bank_result passthrough has exact first-step parity with actual adoption")
		if priced_mode:
			check(actual.credit_result.bank_equity_after == retained.credit_results[0].bank_equity_after, "priced capital retains the actual interest-inclusive settlement basis")
		game._refresh(false)
		await settle()
		var path: Control = game.bank_outlook.path
		var path_id := path.get_instance_id()
		calls = career.calls
		steps = career.model.steps
		frozen = career.encode()
		path.grab_focus()
		await settle()
		game.assets.get_line_edit().text = "3 + 1"
		var controls: Array = game._committee_control_snapshot()
		var cached_bytes := var_to_bytes(career.last)
		for logical in [Vector2i(1440, 960), Vector2i(800, 480), Vector2i(1440, 960)]:
			root.size = logical
			await settle()
			var order: Array = game._keyboard_focus_order()
			var previous: Control = order[(order.find(path) - 1 + order.size()) % order.size()]
			previous.grab_focus()
			await key(KEY_TAB)
			await settle()
			check(path.has_focus() and root.get_visible_rect().grow(1).encloses(path.get_global_rect()) and game.cockpit_scroll.get_global_rect().grow(1).encloses(path.get_global_rect()), "actual Tab reaches a fully visible bank path after responsive reflow")
			check(game.bank_outlook.size.x <= game.bank_outlook.get_parent().size.x + 1 and game.bank_outlook.get_combined_minimum_size().x < 420, "new panel has no horizontal minimum-width trap")
			await key(KEY_HOME)
			await key(KEY_RIGHT)
			check(path.selected == 1 and path.accessibility_description.contains("Q3") and path.accessibility_description.contains("unrounded"), "Left/Right chart inspection exposes exact conditional sample values")
			await key(KEY_LEFT)
			check(path.selected == 0 and path.accessibility_description.contains("Q2"), "Left returns to the first still-playable point")
			check(game.bank_outlook.limits.text == Outlook.LIMITS and game.bank_outlook.limits.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "short conditional limits remain visibly wrapped native text")
		check(career.calls == calls and career.model.steps == steps and career.encode() == frozen and game._committee_control_snapshot() == controls and path.get_instance_id() == path_id and var_to_bytes(career.last) == cached_bytes, "focus, drawing and resize do not forecast, step, rebuild, adopt, save or submit typed controls")
		game._preview()
		check(path.has_focus(), "reusing a valid preview preserves chart focus rather than hiding/recreating it")
		game._refresh(false, false)
		check(game.bank_outlook.visible and not game.bank_outlook.snapshot.ok and path.values.is_empty() and not path.visible, "refresh without a quote clears stale staged bank values")
		career.fail_next = true
		game._preview()
		check(game.bank_outlook.visible and game.bank_outlook.summary.text == "Outlook unavailable" and game.bank_outlook.path not in game._keyboard_focus_order() and game.bank_outlook.payment.text.is_empty() and game.bank_outlook.carryover.text.is_empty() and game.bank_outlook.meter.value == 0, "invalid quote shows unavailable and removes stale chart/focus entry")
		career.fail_next = false
		for meeting in range(1, 7):
			check(career.advance(career.model.benchmark_policy(career.state, career.params, "hold")).ok, "real remaining playable meetings advance")
		game._refresh(true)
		check(game.bank_outlook.snapshot.ok and game.bank_outlook.path.values.size() == 1, "Main Q7 displays one point, excluding seven diagnostic continuation points")
		var endpoint: Dictionary = career.last.states[0]
		check(game.forecast_label.text.contains("CONDITIONAL Q+1 · Q8") and game.forecast_label.text.contains("Inflation %.2f%% · unemployment %.2f%% · output gap %+.2f%%" % [endpoint.four_quarter_inflation_pct, endpoint.unemployment_rate_pct, endpoint.output_gap_pct]) and game.preview_hint.text.contains("this decision only, through Q8"), "both default8 labs clip primary macro values/assumptions to cachedQ8 atQ7")
		check(career.advance(career.model.benchmark_policy(career.state, career.params, "hold")).ok, "real final settlement advances")
		game._refresh(true)
		check(not game.bank_outlook.visible and path.values.is_empty() and path not in game._keyboard_focus_order(), "Q8 completion clears bank outlook without a stale diagnostic capital minimum")
		check(game.workout_debrief.timeline.caption_height == 0 and game.workout_debrief.timeline.custom_minimum_size.y == 96 and not game.workout_debrief.inspection.visible, "default8 debrief keeps its original96-point geometry without a numeric caption")
	game._start_career("policy_career", 1)
	check(not game.bank_outlook.visible and game.bank_outlook.path.values.is_empty() and FileAccess.get_file_as_bytes(game.save_path) == saved, "leaving both labs clears outlook and preserves normal save bytes")
	if failures == 0:
		print("PASS: bank decision outlook ", checks, " checks; cached forecast presentation and Main mechanics, not GUI acceptance")
	await game._quit_app(1 if failures else 0)
