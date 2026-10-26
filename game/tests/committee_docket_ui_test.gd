extends SceneTree
const Career = preload("res://play/career.gd")
const Docket = preload("res://play/policy_docket.gd")
var failures: int = 0

class CountingCareer:
	extends "res://play/career.gd"
	var calls: int = 0
	func forecast(policy: Dictionary, follow: bool = false) -> Dictionary:
		calls += 1
		return super.forecast(policy, follow)

class UnavailableCareer:
	extends "res://play/career.gd"
	func forecast(_policy: Dictionary, _follow: bool = false) -> Dictionary:
		return {"ok": false, "error": "conditional horizon unavailable"}

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for frame in range(5):
		await process_frame

func key(window: Variant, code: Key, command: bool = false, shift: bool = false) -> void:
	# Variant allows the guard to run for a freed object instead of aborting at
	# argument binding. A missing press target is a failure, never a passed skip.
	if not is_instance_valid(window) or not window is Window or window.is_queued_for_deletion():
		check(false, "key press requires a live target window: " + str(code))
		return
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.meta_pressed = command and OS.get_name() == "macOS"
	event.ctrl_pressed = command and OS.get_name() != "macOS"
	event.shift_pressed = shift
	window.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	# Escape/Stage may free the popup during the awaited frame. Release safely
	# on the surviving root instead; a release cannot activate its Adopt shortcut.
	var release_window: Window = root
	if is_instance_valid(window) and not window.is_queued_for_deletion():
		release_window = window
	release_window.push_input(event, true)
	await settle()

func check_draft(ok: bool, message: String, game: Variant, field: SpinBox, expected_text: String, expected_value: float, career_bytes: PackedByteArray) -> void:
	check(ok, message)
	if ok:
		return
	var modal: Variant = game.committee_docket
	var stages: int = modal.stage_buttons.size() if is_instance_valid(modal) else -1
	printerr("DRAFT_DIAG %s expected=%s text=%s meta=%s pending=%s value=%s expected_value=%s stages=%d career_equal=%s" % [message, var_to_str(expected_text), var_to_str(field.get_line_edit().text), var_to_str(field.get_meta("numeric_text")), str(field.get_meta("numeric_text_pending")), str(field.value), str(expected_value), stages, str(game.career.encode() == career_bytes)])

func labels(dialog: Window) -> String:
	var text: String = ""
	for label in dialog.find_children("*", "Label", true, false):
		text += label.text + "\n"
	return text

func run() -> void:
	# This isolated headless fixture starts at 64x64. Establish a desktop-sized
	# private root before Main, using compact_ui_test's native-density technique.
	var density: float = maxf(1.0, DisplayServer.screen_get_scale(root.current_screen))
	root.size = Vector2i((Vector2(1440, 960) * density).round())
	var original_root_size: Vector2i = root.size
	var original_root_scale: float = root.content_scale_factor
	var game: Variant = load("res://main.tscn").instantiate()
	root.add_child(game)
	await settle()
	check(root.get_visible_rect().size.distance_to(Vector2(1440, 960)) <= 1.5, "private headless fixture establishes a 1440x960 logical desktop before behavior checks")
	game._start_career("stagflation_bank_run", 1)
	await settle()
	var counted := CountingCareer.new()
	check(counted.start("stagflation_bank_run", 1).ok, "counted fixture starts")
	game.career = counted
	game._refresh(true)
	await settle()
	game.assets.value = 0.75
	game.liquidity.value = 0.2
	game.sterilization.set_pressed_no_signal(true)
	game.follow_up_toggle.set_pressed_no_signal(true)
	await settle()
	# Valid unsubmitted text must inform the quote without committing the control.
	game.assets.get_line_edit().text = "1.25"
	game.guidance.get_line_edit().text = "-0.25"
	game.rate.get_line_edit().grab_focus()
	var original: PackedByteArray = counted.encode()
	var original_controls: Array = game._committee_control_snapshot()
	var calls_before: int = counted.calls
	var prior_feedback: String = game.status_label.text
	await key(root, KEY_K, true)
	var dialog: Variant = game.committee_docket
	check(is_instance_valid(dialog) and dialog.visible and dialog.stage_buttons.size() == 3, "CmdK opens one graphical docket with three Stage actions")
	check(counted.calls == calls_before + 5, "opening performs exactly five real Career.forecast calls")
	check(game.status_label.text == prior_feedback, "opening with follow-up off preserves existing outcome feedback")
	check(game._committee_control_snapshot() == original_controls and counted.encode() == original, "opening preserves raw text drafts, switches and career")
	check(dialog.quote.entries[0].policy.asset_flow_request_pct_initial_gdp == 1.25 * counted.model.nominal_gdp_ratio(counted.state), "quote uses unsubmitted valid asset draft")
	var read_calls: int = counted.calls
	await settle()
	await key(dialog, KEY_TAB)
	await key(dialog, KEY_PAGEDOWN)
	await key(dialog, KEY_ENTER, true)
	check(counted.encode() == original and game._committee_control_snapshot() == original_controls and counted.calls == read_calls, "reading/Tab/scroll/modified Return neither adopts, submits nor forecasts")
	await key(dialog, KEY_ESCAPE)
	check(not is_instance_valid(dialog) and game.committee_button.has_focus() and game._committee_control_snapshot() == original_controls, "Escape cancels and returns focus to opener, preserving drafts")
	# Every advertised control must equal what staging actually places in _policy.
	for index in range(3):
		game._open_committee_docket()
		await settle()
		dialog = game.committee_docket
		var item: Dictionary = dialog.quote.entries[index + 2]
		var expected: Dictionary = item.policy.duplicate(true)
		dialog.stage_buttons[index].grab_focus()
		await key(dialog, KEY_ENTER)
		check(not is_instance_valid(dialog) and game._policy() == expected, "focused Return stages exact advertised policy: " + item.id)
		check(counted.encode() == original and game.committee_button.has_focus(), "staging closes without adoption, restores opener")
		check(game.commitment.selected == 0, "standard data-dependent settings exactly match staging")
		check(game.docket_signal_states.is_empty() and not game.rate.get_line_edit().is_blocking_signals(), "staging restores prior draft-signal flags after close")
	# Invalid numeric drafts are never silently sanitized; no quote calls at all.
	for draft in ["", "bad", "1 + 2", "nan", "1e999"]:
		var numeric_value: float = game.rate.value
		game.rate.get_line_edit().text = draft
		# Reproduce malformed text blessed by pending draw metadata.
		game.rate.set_meta("numeric_text", draft)
		game.rate.set_meta("numeric_text_pending", true)
		game.rate.get_line_edit().grab_focus()
		calls_before = counted.calls
		await key(root, KEY_K, true)
		dialog = game.committee_docket
		check_draft(not dialog.quote.ok and dialog.stage_buttons.is_empty() and counted.calls == calls_before, "invalid/nonfinite numeric draft refuses without forecasting: " + draft, game, game.rate, draft, numeric_value, original)
		check_draft(game.rate.get_line_edit().text == draft and game.rate.value == numeric_value and counted.encode() == original, "invalid draft and career remain intact", game, game.rate, draft, numeric_value, original)
		check(game.rate.get_line_edit().is_blocking_signals(), "draft suppression remains active throughout modal lifetime")
		await key(dialog, KEY_ESCAPE)
		check_draft(game.rate.get_line_edit().text == draft and game.rate.value == numeric_value, "cancel never sanitizes invalid draft", game, game.rate, draft, numeric_value, original)
		check(not game.rate.get_line_edit().is_blocking_signals() and game.docket_signal_states.is_empty(), "cancel restores prior unblocked flags and releases suppression")
	# Raw bounds are checked even when metadata calls the text canonical.
	game.rate.get_line_edit().text = "%.2f" % game.rate.value
	var loan_value: float = game.liquidity.value
	game.liquidity.get_line_edit().text = "-1"
	game.liquidity.set_meta("numeric_text", "-1")
	game.liquidity.set_meta("numeric_text_pending", true)
	calls_before = counted.calls
	await key(root, KEY_K, true)
	dialog = game.committee_docket
	check_draft(not dialog.quote.ok and dialog.message.text.contains("Liquidity") and counted.calls == calls_before and game.liquidity.value == loan_value, "negative raw loan refuses without falling back to prior value", game, game.liquidity, "-1", loan_value, original)
	await key(dialog, KEY_ESCAPE)
	check_draft(game.liquidity.get_line_edit().text == "-1" and game.liquidity.value == loan_value, "out-of-bound draft survives cancellation unchanged", game, game.liquidity, "-1", loan_value, original)
	game.liquidity.get_line_edit().text = "%.4f" % loan_value
	# Focus and settle the actual opener first: delayed SpinBox editing callbacks
	# must not turn a supposedly native pointer click into an offscreen no-op.
	game.committee_button.grab_focus()
	game._reveal_focus()
	await settle()
	game._reveal_focus()
	await settle()
	var opener_rect: Rect2 = game.committee_button.get_global_rect()
	var pointer_ready: bool = game.committee_button.has_focus() and game.get_viewport_rect().encloses(opener_rect) and game.cockpit_scroll.get_global_rect().encloses(opener_rect) and game.overflow_scroll.get_global_rect().encloses(opener_rect)
	check(pointer_ready, "native pointer target is focused, settled and fully inside viewport/scrollers")
	if not pointer_ready:
		printerr("POINTER_DIAG rect=%s viewport=%s cockpit=%s outer=%s focused=%s" % [str(opener_rect), str(game.get_viewport_rect()), str(game.cockpit_scroll.get_global_rect()), str(game.overflow_scroll.get_global_rect()), str(game.committee_button.has_focus())])
	var pointer_value: float = game.rate.value
	game.guidance.get_line_edit().set_block_signals(true)
	game.rate.get_line_edit().text = "bad"
	game.rate.set_meta("numeric_text", "bad")
	game.rate.set_meta("numeric_text_pending", true)
	# Never reuse the last (freed) popup if the pointer opener misses.
	dialog = null
	if pointer_ready:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.position = opener_rect.get_center()
		mouse.global_position = mouse.position
		mouse.pressed = true
		root.push_input(mouse, true)
		await process_frame
		mouse = mouse.duplicate()
		mouse.pressed = false
		root.push_input(mouse, true)
		await settle()
		if is_instance_valid(game.committee_docket) and game.committee_docket.visible:
			dialog = game.committee_docket
	var pointer_opened: bool = is_instance_valid(dialog)
	check_draft(pointer_opened, "native pointer opener creates a live docket", game, game.rate, "bad", pointer_value, original)
	if not pointer_opened:
		# Record the pointer failure above, then use a fresh keyboard opening so
		# preservation/cancellation are still exercised, never silently skipped.
		game.rate.get_line_edit().text = "bad"
		await key(root, KEY_K, true)
		dialog = game.committee_docket
	check_draft(is_instance_valid(dialog) and dialog.visible and not dialog.quote.ok and game.rate.get_line_edit().text == "bad" and game.rate.value == pointer_value and counted.encode() == original, "pointer opening refuses and preserves invalid draft", game, game.rate, "bad", pointer_value, original)
	await key(dialog, KEY_ESCAPE)
	check_draft(game.guidance.get_line_edit().is_blocking_signals() and not game.rate.get_line_edit().is_blocking_signals() and game.rate.get_line_edit().text == "bad" and game.rate.value == pointer_value, "pointer cancellation restores distinct prior flags without sanitizing draft", game, game.rate, "bad", pointer_value, original)
	game.guidance.get_line_edit().set_block_signals(false)
	# Restore a number explicitly, then force stale controls, quarter and identity.
	game.rate.get_line_edit().text = "3.5"
	game.rate.apply()
	await settle()
	for reason in ["control", "quarter", "case", "fresh identity"]:
		game._open_committee_docket()
		await settle()
		dialog = game.committee_docket
		var unchanged_rate: float = game.rate.value
		if reason == "control":
			game.assets.value += 0.25
		elif reason == "quarter":
			counted.state.quarter_index += 1
		elif reason == "case":
			counted.scenario_id = "base"
		else:
			counted.state = counted.state.duplicate(true)
		game._stage_docket_proposal("prices")
		check(dialog.message.text.contains("Stale") and game.rate.value == unchanged_rate and dialog.stage_buttons[0].disabled, "stale snapshot refuses before staging: " + reason)
		# Explicit refresh is the only operation that refreshes cached comparisons.
		calls_before = counted.calls
		dialog.refresh_button.pressed.emit()
		await settle()
		check(counted.calls == calls_before + 5 and not dialog.stage_buttons[0].disabled and dialog.refresh_button.has_focus(), "explicit refresh regenerates five paths, fresh snapshot and keyboard focus")
		await key(dialog, KEY_ESCAPE)
	# Wide action-first layout, followed by an explicitly resized private fixture.
	game._start_career("base", 3)
	await settle()
	game._open_committee_docket()
	await settle()
	dialog = game.committee_docket
	check(dialog.cards.columns == 3 and dialog.proposal_cards.size() == 3, "ordinary desktop opens with three side-by-side actionable cards")
	check(dialog.reference_table.get_child_count() == 12 and dialog.reference_table.get_index() > dialog.cards.get_index(), "Staged/Hold are two compact metric rows after proposals, not extra cards")
	check(not dialog.details.visible and dialog.refresh_button.size.x < dialog.scroll.size.x * 0.3, "details collapsed and Refresh is a small toolbar action")
	check(dialog.metric_values.size() == 9, "three cards expose nine atomic numeric metric labels")
	for number in dialog.metric_values:
		var font: Font = number.get_theme_font("font")
		var font_size: int = number.get_theme_font_size("font_size")
		var measured_width: float = font.get_string_size(number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		check(number.autowrap_mode == TextServer.AUTOWRAP_OFF and number.get_line_count() == 1, "metric value stays on one atomic line")
		check(number.custom_minimum_size.x >= ceilf(measured_width) and number.size.x + 0.5 >= measured_width and font_size == 20, "atomic value reserves measured width without shrinking readable font")
		check(number.size_flags_horizontal == Control.SIZE_SHRINK_END and number.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT and not number.clip_text, "atomic value is right-aligned and neither clipped nor wrapped")
	for button in dialog.stage_buttons:
		check(dialog.scroll.get_global_rect().encloses(button.get_global_rect()) and dialog.get_visible_rect().encloses(button.get_global_rect()), "all three Stage actions visible without scrolling in ordinary-desktop viewport")
	# The existing formatter bounds long finite numbers with scientific notation;
	# exercise the same atomic sizing path, then restore the original displayed text.
	var atomic: Label = dialog.metric_values[0]
	var original_number: String = atomic.text
	atomic.text = Docket.value_text(-1e300)
	dialog._size_metric_value(atomic)
	await settle()
	check(atomic.text.contains("e") and atomic.get_line_count() == 1 and atomic.size.x >= atomic.custom_minimum_size.x and atomic.size.x < atomic.get_parent().size.x, "large signed scientific notation remains complete, readable and bounded within its metric row")
	atomic.text = original_number
	dialog._size_metric_value(atomic)
	await settle()
	var card_ids: Array = []
	for card in dialog.proposal_cards:
		card_ids.append(card.get_instance_id())
	var popup_calls: int = game.docket_forecast_calls
	dialog.stage_buttons[1].grab_focus()
	# Exercise production report fitting by resizing this private headless root;
	# the docket itself must not resize its parent or replace focused controls.
	root.size = Vector2i((Vector2(800, 480) * density).round())
	var compact_root_size: Vector2i = root.size
	await settle()
	check(root.get_visible_rect().size.distance_to(Vector2(800, 480)) <= 1.5, "private compact fixture establishes an 800x480 logical viewport")
	check(dialog.get_size_with_decorations().x <= root.get_visible_rect().size.x and dialog.get_size_with_decorations().y <= root.get_visible_rect().size.y, "compact docket stays bounded by its private parent")
	check(dialog.cards.columns == 1 and dialog.stage_buttons[1].has_focus(), "800x480 private parent stacks the same cards without stealing focus")
	for index in range(3):
		check(dialog.proposal_cards[index].get_instance_id() == card_ids[index], "reflow retains original Control identities")
	check(game.docket_forecast_calls == popup_calls, "popup reflow never recomputes forecasts")
	check(dialog.scroll.get_h_scroll_bar().max_value <= dialog.scroll.size.x + 1.0, "stacked cards wrap without horizontal overflow")
	dialog.stage_buttons[2].grab_focus()
	await settle()
	check(dialog.scroll.get_global_rect().encloses(dialog.stage_buttons[2].get_global_rect()), "focus-following scroll fully reveals compact funding action")
	check(labels(dialog).contains("% initial GDP") and labels(dialog).contains("not a fixed target") and labels(dialog).contains("lower inflation is not always better"), "metric units and retained Details preserve signed/reference semantics")
	check(dialog.find_children("*", "TextEdit", true, false).is_empty(), "graphical docket never defaults to a report-text wall")
	check(root.size == compact_root_size and root.content_scale_factor == original_root_scale, "production docket preserves the configured compact parent size and density")
	root.size = original_root_size
	await settle()
	var logical: Vector2i = Vector2i(root.get_visible_rect().size)
	game._fit_report(dialog)
	await settle()
	check(dialog.get_size_with_decorations().x <= logical.x and dialog.get_size_with_decorations().y <= logical.y, "preferred docket size remains bounded by unchanged parent")
	check(dialog.cards.columns == 3 and dialog.stage_buttons[2].has_focus(), "return to preferred width restores three columns without replacing focused action")
	await key(dialog, KEY_ESCAPE)
	for case_id in [game.WORKOUT_CASE, game.PRICED_WORKOUT_CASE]:
		game._start_career(case_id, 417)
		await settle()
		var before_lab: PackedByteArray = game.career.encode()
		game._open_committee_docket()
		await settle()
		dialog = game.committee_docket
		check(dialog.quote.ok and dialog.quote.horizon == 8 and dialog.stage_buttons.size() == 3, "original/priced Main integration uses active laboratory")
		var funding: Dictionary = dialog.quote.entries[4].policy.duplicate(true)
		game._stage_docket_proposal("funding")
		await settle()
		check(game._policy() == funding and game.career.encode() == before_lab, "lab advertised controls stage exactly without normal-save routing")
		for quarter in range(7):
			var held: Dictionary = game.career.model.benchmark_policy(game.career.state, game.career.params, "hold")
			check(game.career.advance(held).ok, "actual lab meetings reach near-horizon fixture")
		game._refresh(true)
		game._open_committee_docket()
		await settle()
		dialog = game.committee_docket
		check(dialog.quote.diagnostic and labels(dialog).contains("diagnostic continuation only") and dialog.stage_buttons.size() == 3 and game.career.decisions.size() == 7, "original/priced near-horizon docket labels continuation without granting turns")
		await key(dialog, KEY_ESCAPE)
	game._start_career("base", 1)
	var unavailable := UnavailableCareer.new()
	check(unavailable.start("base", 1).ok, "failed-path UI fixture starts")
	game.career = unavailable
	game._refresh(true)
	await settle()
	game._open_committee_docket()
	await settle()
	dialog = game.committee_docket
	check(dialog.quote.ok and not dialog.stage_buttons[0].disabled and labels(dialog).contains("Conditional path unavailable"), "failed horizon leaves input-valid staging available without bogus values")
	var unavailable_policy: Dictionary = dialog.quote.entries[2].policy.duplicate(true)
	var unavailable_original: PackedByteArray = unavailable.encode()
	game._stage_docket_proposal("prices")
	await settle()
	check(game._policy() == unavailable_policy and unavailable.encode() == unavailable_original, "failed-path proposal can stage exact first controls without adoption")
	unavailable.decisions.resize(240)
	game._open_committee_docket()
	await settle()
	dialog = game.committee_docket
	check(not dialog.quote.ok and dialog.stage_buttons.is_empty(), "completed normal career has no active stage actions")
	await key(dialog, KEY_ESCAPE)
	check(root.size == original_root_size and root.content_scale_factor == original_root_scale, "production docket preserves the restored private desktop size and density")
	if failures == 0:
		print("PASS: docket drafts, exact staging, modal keys, focus, staleness, cached calls, bounds and both labs (headless mechanics only)")
	await game._quit_app(1 if failures else 0)
