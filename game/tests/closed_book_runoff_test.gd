extends SceneTree
const Summary = preload("res://play/closed_book_runoff.gd")
const Career = preload("res://play/career.gd")
var checks := 0
var failures := 0
class CountingModel:
	extends "res://model/economy.gd"
	var transitions := 0
	func bank_workout_transition(state: Dictionary, policy: Dictionary, shocks: Dictionary, params: Dictionary, bank: Variant, order: Variant, credit: Dictionary = {}) -> Dictionary:
		transitions += 1
		return super.bank_workout_transition(state, policy, shocks, params, bank, order, credit)
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", text)
func settle() -> void:
	for frame in range(5): await process_frame
func key(code: Key, window: Window = null) -> void:
	var target: Window = root if window == null else window
	var receiver: Window = root if target.is_embedded() else target
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
func pure_cases() -> void:
	var history: Array = []
	var banks: Array = []
	var credit: Array = []
	for index in range(21):
		history.append({"quarter_index": index, "four_quarter_inflation_pct": 4.0 if index <= 8 else 8.0, "unemployment_rate_pct": 6.0 if index <= 8 else 9.0, "structural_unemployment_pct": 5.0 if index <= 8 else 6.0})
		banks.append({"quarter_index": index, "central_bank_loan": 2.0 if index <= 8 else 1.0, "withdrawal_queue": 0.5, "equity": 99.0})
		if index > 0: credit.append({"bank_equity_after": -0.1 if index <= 8 else -0.7})
	var frozen := var_to_bytes([history, banks, credit])
	var checkpoint := Summary.present(history.slice(0, 9), banks.slice(0, 9), credit.slice(0, 8), 8, 2.0)
	var ending := Summary.present(history, banks, credit, 20, 2.0)
	check(checkpoint.ok and checkpoint.early_prices == 2.0 and checkpoint.early_jobs == 1.0 and checkpoint.late_prices == null, "Q8 checkpoint exposes only actual first interval, never unplayed later outcomes")
	check(ending.ok and ending.late_prices == 6.0 and ending.late_jobs == 3.0 and ending.capital8 == -0.1 and ending.capital_now == -0.7, "actual intervals use their own8/12 denominators and native all-in capital, not raw bank mark")
	check(ending.debt8 == 2.0 and ending.debt_now == 1.0 and ending.queue_now == 0.5, "bank principal/queue compare ending snapshots rather than repeated-claim totals")
	check(var_to_bytes([history, banks, credit]) == frozen, "actual presenter never mutates history")
	var panel := Summary.new()
	panel.update_actual(history, banks, credit, 20, 2.0)
	history[18].four_quarter_inflation_pct = NAN
	panel.update_actual(history, banks, credit, 20, 2.0)
	check(panel.visible and not panel.snapshot.ok and panel.bank.text.is_empty() and panel.prices.text.is_empty() and not panel.price_bars.visible, "invalid actual source clears stale text and graphics with unavailable state")
	panel.update_actual([], [], [], 0, 2.0, false)
	check(not panel.visible and panel.bank.text.is_empty(), "leaving mode clears the checkpoint")
	panel.free()
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	pure_cases()
	root.size = Vector2i(1440, 960)
	var game: Control = load("res://main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.save_path = "user://runoff-preserved.save"
	game._save()
	var saved := FileAccess.get_file_as_bytes(game.save_path)
	var original: PackedByteArray = game.career.encode()
	game.rate.get_line_edit().text = "not a number"
	game._new_dialog()
	await settle()
	var picker: Window = game.career_opening_picker
	check(picker.primary_ids.slice(0, 4) == ["policy_career", "stagflation_bank_run", "__priced_bank_workout", "__bank_workout"] and picker.primary_ids[4] == game.RUNOFF_CASE, "firstfour IDs/order/default remain; runoff is a separate explicit fifth opening")
	picker.primary_buttons[4].grab_focus()
	await key(KEY_ENTER, picker)
	check(game.career.encode() == original and game.rate.get_line_edit().text == "not a number" and game.scenario.get_item_metadata(game.scenario.selected) == game.RUNOFF_CASE, "Return selects runoff without starting or submitting policy drafts")
	game.seed_input.value = 417
	await settle()
	picker.get_ok_button().grab_focus()
	await key(KEY_ENTER, picker)
	await settle()
	check(game._is_runoff() and game._is_priced_workout() and game._active_horizon() == 20 and game.career.seed_value == 417, "explicit Start enters priced20 only")
	var recipe: Dictionary = game.career.model.bank_workout_opening(game.career.params)
	check(game.career.withdrawal_requests.slice(0, 8) == recipe.requests and game.career.withdrawal_requests.slice(8).size() == 12 and game.career.withdrawal_requests.slice(8).all(func(value): return value == 0.0) and game.career.remaining_request_index == 3, "native first8 request tape plus exactly12zero entries, no new withdrawal waves")
	var native := Career.new()
	check(native.start("stagflation_bank_run", 417).ok and native.shocks == game.career.shocks, "entire native seeded macro-shock tape is unchanged, not silently zeroed")
	check(game.normal_storage_buttons.all(func(button): return button.disabled) and game.follow_up_toggle.disabled, "runoff retains lab save and automatic-followup exclusions")
	game._save()
	game._load()
	check(FileAccess.get_file_as_bytes(game.save_path) == saved, "runoff Save/Load attempts cannot touch normal save")
	game.career.model = CountingModel.new()
	for meeting in range(20):
		game.loading_controls = true
		game.rate.value = 4.0
		game.guidance.value = 4.0
		game.liquidity.value = 2.0 if meeting == 0 else 0.0
		game.loading_controls = false
		var steps: int = game.career.model.transitions
		game._preview()
		check(game.career.model.transitions == steps + 8 and game.bank_outlook.snapshot.values.size() == mini(8, 20 - meeting) and game.bank_outlook.snapshot.last_quarter == mini(20, meeting + 8), "preview stays8steps and labels its actual forecast endpoint")
		if meeting == 19:
			check(game.bank_outlook.path.values.size() == 1 and game.bank_outlook.summary.text.contains("through Q20"), "Q19 displays exactlyone Q20quote, not diagnostic later capital")
		game._advance()
		check(game.career.decisions.size() == meeting + 1, "actual Main adoption reaches meeting%d" % (meeting + 1))
		check(not game.get_children().any(func(child): return child is Window and child.visible), "no unsupported normal-review popup interrupts the20-meeting lab")
		if meeting == 7:
			check(not game.decision_button.disabled and not game.workout_debrief_panel.visible and game.runoff_context.snapshot.ok and game.runoff_context.snapshot.late_prices == null and game.bank_outlook.snapshot.last_quarter == 16, "Q8 is an actual checkpoint with Q9–16 quote, not false completion or full-Q20 forecast")
			check(game.runoff_context.context.text.contains("Q20") and game.runoff_context.context.text.contains("12 meetings left"), "checkpoint makes the known final-maturity purpose explicit")
		if meeting in [7, 19]:
			for size in [Vector2i(800, 480), Vector2i(1440, 960)]:
				root.size = size
				await settle()
				var target: Control = game.bank_outlook.path if meeting == 7 else game.workout_debrief.timeline
				var order: Array = game._keyboard_focus_order()
				check(target in order, "visible forecast/terminal20timeline is in the actual keyboard cycle")
				order[(order.find(target) - 1 + order.size()) % order.size()].grab_focus()
				await key(KEY_TAB)
				await settle()
				check(target.has_focus() and root.get_visible_rect().grow(1).encloses(target.get_global_rect()), "Tab reveals the full active graph after compact/desktop reflow")
				check(game.runoff_context.get_combined_minimum_size().x < 420 and game.runoff_context.size.x <= game.runoff_context.get_parent().size.x + 1, "actual checkpoint does not force a horizontal minimum trap")
				var before: PackedByteArray = game.career.encode()
				steps = game.career.model.transitions
				await key(KEY_HOME)
				await key(KEY_END)
				if meeting == 19:
					check(target.selected == 19 and game.workout_debrief.inspection.text.begins_with("Q20") and target.accessibility_description.contains("Q20"), "20-bar timeline exposes selected end values visibly and accessibly, not tiny-hover-only")
				check(game.career.encode() == before and game.career.model.transitions == steps, "graph inspection/resize does not adopt, forecast or step")
	check(game.decision_button.disabled and game.workout_debrief.snapshot.ok and game.workout_debrief.snapshot.quarters.size() == 20 and game.runoff_context.snapshot.quarter == 20 and game.runoff_context.snapshot.capital_now == game.career.credit_results[-1].bank_equity_after, "Q20 actual debrief and checkpoint use all20 records and all-in terminal capital")
	check(game.bank_outlook.path.values.is_empty() and not game.bank_outlook.visible, "terminal forecast clears")
	var final_state: PackedByteArray = game.career.encode()
	game._advance()
	check(game.career.encode() == final_state and game.career.decisions.size() == 20 and FileAccess.get_file_as_bytes(game.save_path) == saved, "21st decision refuses and normal save bytes remain untouched")
	for id in [game.WORKOUT_CASE, game.PRICED_WORKOUT_CASE]:
		game._start_career(id, 417)
		check(game._active_horizon() == 8 and not game._is_runoff() and not game.runoff_context.visible, "each existing8-meeting lab remains separately available and clears runoff context")
	game._start_career("policy_career", 1)
	check(game._active_horizon() == 240 and not game.runoff_context.visible and not game.workout_debrief_panel.visible and FileAccess.get_file_as_bytes(game.save_path) == saved, "normal careers clear all runoff/debrief state without changing their save")
	if failures == 0: print("PASS: closed-book runoff UI candidate ", checks, " checks; headless mechanics, not native acceptance")
	await game._quit_app(1 if failures else 0)
