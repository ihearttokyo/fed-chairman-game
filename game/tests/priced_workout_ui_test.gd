extends SceneTree
## Actual Main integration in isolated test HOME; not pixels/human play evidence.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game: Control = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.save_path = "user://priced-preserved-normal.bin"
	check(game.career.save_to(game.save_path).ok, "Private normal save exists before priced mode")
	var original := FileAccess.get_file_as_bytes(game.save_path)
	game._new_dialog()
	var chooser: AcceptDialog = game.get_child(game.get_child_count() - 1)
	var index := -1
	for i in range(game.scenario.item_count):
		if game.scenario.get_item_metadata(i) == game.PRICED_WORKOUT_CASE:
			index = i
	check(index >= 0, "Actual New menu exposes the explicitly priced optional lab")
	if index < 0:
		await game._quit_app(1)
		return
	game.scenario.select(index)
	game.seed_input.value = 417
	chooser.get_ok_button().pressed.emit()
	await process_frame
	check(game._is_priced_workout() and game._is_workout() and game._active_horizon() == 8, "Main binds the priced controller with the existing eight-meeting restrictions")
	check(game.priced_credit_panel.visible and game.workout_panel.visible, "Bank ledger and separate borrowing-cost panel are visible")
	check(game.normal_storage_buttons.all(func(button): return button.disabled), "Priced mode cannot enable ordinary save/load")
	check(game._workout_help().contains("collectible") and game._workout_help().contains("counterfactual") and not game._workout_help().contains("zero loan interest"), "Help explains actual authored credit terms, not the parent zero-interest assumptions")
	game.loading_controls = true
	game.rate.value = 4.0
	game.guidance.value = 4.0
	game.liquidity.value = 0.0001
	game.loading_controls = false
	var frozen: PackedByteArray = game.career.encode()
	game._preview()
	check(game.career.encode() == frozen, "Staged credit display does not adopt or modify any ledger")
	game._advance()
	check(game.career.decisions.size() == 1 and game.career.bank_state.central_bank_loan > 0.0, "First actual UI adoption originates small supported principal")
	game.loading_controls = true
	game.rate.value = -1.0
	game.guidance.value = -1.0
	game.liquidity.value = 4.0
	game.loading_controls = false
	game._preview()
	var expected_preview: Dictionary = game.career.forecast(game._policy())
	var shown: Dictionary = game.priced_credit_board.snapshot
	check(expected_preview.ok and shown.actual.ok and shown.staged.ok, "Actual Main cost board receives both valid actual and staged records")
	check(shown.actual.basis.contains("4.00% APR") and shown.actual.basis.contains("90d/365") and shown.staged.basis.contains("-1.00% APR") and shown.staged.basis.contains("91d/365"), "Visible board distinguishes actual4percent/90days from stagednegative1percent/91days")
	check(shown.staged.paid_negative == expected_preview.credit_results[0].paid_negative and shown.staged.paid_negative > 0.0 and shown.staged.payable == expected_preview.credit_states[0].payable, "Visible reverse payment and separate unpaid claim match the independently read first conditional step")
	check(shown.staged.purpose_text.contains(game.career.funding_amount_text(expected_preview.credit_results[0].new_cash_for_interest)) and shown.staged.purpose_text.contains(game.career.funding_amount_text(expected_preview.credit_results[0].new_cash_for_withdrawals)), "Visible loan-purpose split binds to actual first-step diagnostics")
	var actual_lane := var_to_bytes(shown.actual)
	var before_refresh: PackedByteArray = game.career.encode()
	game._refresh(false, false)
	check(not game.priced_credit_board.snapshot.staged.ok and var_to_bytes(game.priced_credit_board.snapshot.actual) == actual_lane and game.career.encode() == before_refresh, "Refresh without a recomputed preview clears stale staged figures without changing actuals or ledgers")
	game._preview()
	check(game.priced_credit_board.snapshot.staged.ok and var_to_bytes(game.priced_credit_board.snapshot.actual) == actual_lane, "Restaging updates only the prospective lane")
	var report: String = game._decision_briefing()
	check(report.contains("Bank pays") and report.contains("Fed pays") and report.contains("staged / held"), "Comparison distinguishes actual opposite cash flows without netting")
	game._advance()
	check(game.career.decisions.size() == 2 and game.career.credit_results[-1].paid_negative > 0.0, "Explicit negative-APR staged policy produces the native reverse-interest payment")
	check(game.priced_credit_board.snapshot.actual.basis.contains("-1.00% APR") and game.priced_credit_board.snapshot.actual.basis.contains("91d/365") and game.priced_credit_board.snapshot.actual.paid_negative == game.career.credit_results[-1].paid_negative, "Actual lane advances to the negative-rate payment only after adoption")
	var combined_equity: float = game.career.credit_results[-1].bank_equity_after
	var equity_label: String = ("+" if combined_equity > 0.0 else "") + game.workout_board._amount(combined_equity)
	check(game.career.panel_snapshot().equity == combined_equity and game.workout_board.snapshot.equity_text == equity_label, "Current bank board reports combined model equity with its existing signed display convention")
	game._save()
	game._load()
	check(FileAccess.get_file_as_bytes(game.save_path) == original, "Priced Save/Load attempts preserve the existing normal save")
	for quarter in range(2, 8):
		game._advance()
	check(game.career.decisions.size() == 8 and game.decision_button.disabled, "Priced UI reaches all eight settlements without a frozen continuation")
	check(game.workout_debrief.snapshot.ok and game.workout_debrief.snapshot.includes_interest and game.workout_debrief.snapshot.ending_equity == game.career.credit_results[-1].bank_equity_after, "Terminal debrief reports combined equity from the real credit ledger")
	game._journal()
	var journal: AcceptDialog = game.get_child(game.get_child_count() - 1)
	check(journal.get_child(0).text.contains("Borrowing costs") and journal.get_child(0).text.contains("equity incl. interest") and journal.get_child(0).text.contains("Unpaid to Fed"), "Journal retains separate actual credit claims and the correct equity basis")
	journal.get_ok_button().pressed.emit()
	await process_frame
	game._start_career(game.WORKOUT_CASE, 417)
	check(game._is_workout() and not game._is_priced_workout() and not game.priced_credit_panel.visible, "Original zero-interest laboratory remains separately available")
	game._start_career("policy_career", 1)
	check(not game._is_workout() and not game.priced_credit_panel.visible and game.normal_storage_buttons.all(func(button): return not button.disabled), "Normal career controls restore and borrowing-cost UI does not leak across modes")
	check(FileAccess.get_file_as_bytes(game.save_path) == original, "Every mode transition preserves the prior normal-save bytes")
	if failures == 0:
		print("PASS: priced workout Main integration ", checks, " checks; headless, not live usability evidence")
	await game._quit_app(1 if failures else 0)
