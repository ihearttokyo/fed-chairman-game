extends SceneTree
const Career = preload("res://play/career.gd")
const Docket = preload("res://play/policy_docket.gd")
const CommitteeDialog = preload("res://play/committee_docket.gd")
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

func key(window: Variant, code: Key, command: bool = false, shift: bool = false, alt: bool = false) -> void:
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
	event.alt_pressed = alt
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

func delta_source_cases() -> void:
	check(CommitteeDialog.delta_text(4.5, 4.53).begins_with("−0.03"), "inflation displays a signed change from Hold, not the objective")
	check(CommitteeDialog.delta_text(4.44, 4.34).begins_with("+0.10"), "unemployment displays its positive change in pp")
	check(CommitteeDialog.delta_text(4.53, 4.53) == "Same as Hold · Δ 0 pp", "only an exact numeric tie says Same")
	check(CommitteeDialog.delta_text(4.53 + 1e-30, 4.53).contains("Same"), "a difference already lost in source-number representation cannot be invented")
	# A 5e-324 source literal rounded to zero in the first native run. Decode
	# the actual IEEE754 value instead: retain, do not delete, this boundary.
	var least_positive: float = PackedByteArray([1, 0, 0, 0, 0, 0, 0, 0]).decode_double(0)
	check(least_positive > 0.0 and is_finite(least_positive), "subnormal fixture is genuinely nonzero before formatting")
	for pair in [[4.530001, 4.53], [4.529999, 4.53], [1e-300, 0.0], [-1e-300, 0.0], [least_positive, 0.0], [-least_positive, 0.0]]:
		var text: String = CommitteeDialog.delta_text(pair[0], pair[1])
		check(text.contains("<0.005 pp") and not text.contains("Same") and not text.contains("Δ 0 pp"), "small nonzero changes never masquerade as rounded zero: " + str(pair))
		check(text.begins_with("+" if pair[0] > pair[1] else "−"), "small nonzero changes retain their direction")
	for boundary in [0.005, -0.005]:
		var text: String = CommitteeDialog.delta_text(boundary, 0.0)
		check(not text.contains("Same") and not text.contains("0.00 pp"), "half-step formatting cannot create a false zero")
	check(CommitteeDialog.delta_text(-2.5, -2.0).begins_with("−0.50"), "deflation retains arithmetic direction without a welfare claim")
	check(CommitteeDialog.delta_text(1e300, 0.0).contains("e"), "large finite deltas retain bounded scientific notation")
	check(CommitteeDialog.delta_text(1.7e308, -1.7e308).contains("+overflow"), "positive subtraction overflow is explicit, not a fake finite magnitude")
	check(CommitteeDialog.delta_text(-1.7e308, 1.7e308).contains("−overflow"), "negative subtraction overflow retains its known direction")

func axis_tick_cases() -> void:
	var plot := CommitteeDialog.MetricPlot.new()
	plot.size = Vector2(240, 30)
	if not plot.has_method("axis_labels"):
		check(false, "axis ticks require bounded rounded/scientific display instead of full raw double strings")
		plot.free()
		return
	var least_positive: float = PackedByteArray([1, 0, 0, 0, 0, 0, 0, 0]).decode_double(0)
	var raw_caption := "+" + String.num_scientific(0.032788887974732894)
	var raw_width := plot.get_theme_default_font().get_string_size(raw_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	check(raw_caption.length() > 11 and raw_width > plot.size.x * 0.5, "old full-precision axis negative control genuinely overlaps the center at desktop-card width")
	for radius in [0.032788887974732894, 0.09163598523005057, 0.0, least_positive, 1e-300, 1.7976931348623157e308]:
		plot.delta_scale = {"available": true, "overflow": false, "radius": radius}
		plot.held_value = -2.0
		plot.value = -2.5
		plot.delta = -0.5
		var raw := var_to_bytes([plot.delta_scale, plot.value, plot.held_value, plot.delta, plot.size])
		var coordinates := [plot.position_for(-radius), plot.position_for(0.0), plot.position_for(radius)]
		var ticks: PackedStringArray = plot.call("axis_labels")
		if radius == 0.0:
			check(ticks == PackedStringArray(["0"]), "true zero scale has only its genuine zero tick")
		else:
			check(ticks.size() == 3 and ticks[0].begins_with("−") and ticks[1] == "0" and ticks[2].begins_with("+"), "nonzero axis endpoints retain both arithmetic signs around Hold zero")
			check(ticks[2].length() <= 11 and ticks[2].substr(1).get_slice("e", 0).to_float() > 0.0, "smallest subnormal through largest finite extent never formats as false zero or cumbersome precision")
			var font: Font = plot.get_theme_default_font()
			var left_width := font.get_string_size(ticks[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var zero_width := font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var right_width := font.get_string_size(ticks[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			check(left_width < (plot.size.x - zero_width) * 0.5 and plot.size.x - right_width > (plot.size.x + zero_width) * 0.5, "native-size axis endpoints do not overlap zero or neighboring card at desktop card width")
			if radius in [0.032788887974732894, 0.09163598523005057]:
				check(not ticks[2].contains(var_to_str(radius)) and absf(ticks[2].substr(1).to_float() - radius) <= radius * 0.005, "ordinary axis endpoints are concise truthful rounding, not raw 17-digit captions")
		check(raw == var_to_bytes([plot.delta_scale, plot.value, plot.held_value, plot.delta, plot.size]) and coordinates == [plot.position_for(-radius), plot.position_for(0.0), plot.position_for(radius)], "tick formatting cannot change raw input, shared domain or plot coordinates")
	for unavailable in [{"available": false, "overflow": false, "radius": 0.0}, {"available": true, "overflow": true, "radius": 1.7e308}]:
		plot.delta_scale = unavailable
		check(plot.call("axis_labels").is_empty(), "unavailable/overflow scale never invents finite axis ticks")
	plot.free()

func check_stage_visible(dialog: Variant, index: int, context: String) -> void:
	var button: Button = dialog.stage_buttons[index]
	check(button.has_focus() and dialog.scroll.get_global_rect().grow(0.5).encloses(button.get_global_rect()) and dialog.get_visible_rect().grow(0.5).encloses(button.get_global_rect()), context)

func press_without_frame(window: Window, code: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.shift_pressed = shift
	event.pressed = true
	window.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	window.push_input(event, true)

func pending_navigation_cases(game: Variant, dialog: Variant) -> void:
	var saved := FileAccess.file_exists(game.save_path)
	var save_bytes := FileAccess.get_file_as_bytes(game.save_path) if saved else PackedByteArray()
	var cached := var_to_bytes([dialog.quote, dialog.build_count, game.career.encode(), game._committee_control_snapshot(), game.docket_forecast_calls, dialog.stage_buttons.map(func(button: Button): return button.get_instance_id())])
	var bar: VScrollBar = dialog.scroll.get_v_scroll_bar()
	for code in [KEY_PAGEDOWN, KEY_END, KEY_PAGEUP, KEY_HOME]:
		# Start with a genuinely visible focused Price button and idle layout.
		dialog.stage_buttons[1].grab_focus()
		dialog.stage_buttons[0].grab_focus()
		await settle()
		check_stage_visible(dialog, 0, "pending-navigation fixture starts with visible Stage price")
		check(not dialog.focus_reveal_pending, "pending-navigation fixture begins after layout is idle")
		dialog._schedule_card_focus()
		check(dialog.focus_reveal_pending, "manual key is deliberately delivered before the queued automatic reveal callback")
		var before := bar.value
		press_without_frame(dialog, code)
		var manual := bar.value
		check(manual != before, "pending-navigation key genuinely moves the scrollbar: " + str(code))
		await settle()
		check(bar.value == manual and dialog.stage_buttons[0].has_focus(), "pending automatic reveal cannot undo explicit Page/Home/End: " + str(code))
		check(not dialog.focus_reveal_pending, "manual-navigation cancellation leaves no automatic callback polling")
		print("PENDING_NAVIGATION: key=%d before=%s manual=%s settled=%s" % [code, before, manual, bar.value])
	# Fresh real focus transitions still request automatic visibility after a
	# cancellation. Multiple changes before one callback must reveal latest Jobs.
	dialog.stage_buttons[0].grab_focus()
	dialog._schedule_card_focus()
	for shift in [false, true, false]:
		press_without_frame(dialog, KEY_TAB, shift)
	check(dialog.stage_buttons[1].has_focus(), "rapid Tab/ShiftTab/Tab ends on Jobs before the pending callback")
	await settle()
	check_stage_visible(dialog, 1, "rapid pending focus transitions reveal the current Jobs action, not stale Funding")
	var settled := bar.value
	dialog._reveal_card_focus()
	dialog._reveal_card_focus()
	dialog._schedule_card_focus()
	await settle()
	check(bar.value == settled and not dialog.focus_reveal_pending, "repeated current-focus reveal is idempotent after rapid transitions")
	# A later actual Container sort is allowed to schedule fresh work too.
	bar.value = 0
	dialog.content.queue_sort()
	await settle()
	check_stage_visible(dialog, 1, "fresh container layout after manual cancellation can reveal current focus")
	check(not dialog.focus_reveal_pending, "fresh layout reveal returns to idle")
	check(var_to_bytes([dialog.quote, dialog.build_count, game.career.encode(), game._committee_control_snapshot(), game.docket_forecast_calls, dialog.stage_buttons.map(func(button: Button): return button.get_instance_id())]) == cached and FileAccess.file_exists(game.save_path) == saved and (not saved or FileAccess.get_file_as_bytes(game.save_path) == save_bytes), "pending navigation and rapid focus preserve quote cache, builds, controls, drafts, career, forecast count and save bytes")

func compact_context_cases(game: Variant, dialog: Variant) -> void:
	var cache := var_to_bytes([dialog.quote, dialog.build_count, game._committee_control_snapshot(), game.career.encode(), game.docket_forecast_calls])
	for index in range(3):
		if index > 0:
			await key(dialog, KEY_TAB)
		check_stage_visible(dialog, index, "compact context remains beside the current keyboard-focused Stage action")
		var conditional: Label
		var reference: Label
		for label in dialog.find_children("*", "Label", true, false):
			if not dialog.scroll.is_ancestor_of(label) and label.is_visible_in_tree():
				if label.text.contains("Conditional") and label.text.contains("No new shocks") and label.text.contains("withdrawal"):
					conditional = label
				if label.text.contains("direction, not welfare") and label.text.contains("Inflation objective"):
					reference = label
		check(conditional != null and reference != null, "compact decisions retain conditional/no-new-events and direction/reference context outside the scrolling cards")
		if conditional != null and reference != null:
			for label in [conditional, reference]:
				check(dialog.get_visible_rect().grow(0.5).encloses(label.get_global_rect()) and not label.get_global_rect().intersects(dialog.scroll.get_global_rect()), "concise decision context is fully visible in existing dialog chrome, not clipped inside scrolling content")
				check(label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and label.accessibility_name == label.text, "pinned decision context retains native wrapping and exact readable accessibility text")
			check(conditional.get_theme_font_size("font_size") == 13 and reference.get_theme_font_size("font_size") == 12, "context reuses existing header/legend font sizes without shrinking")
			check(conditional.text.contains("Stage does not adopt") and conditional.text.contains("Q+1–8") and reference.text.contains("Δ vs Hold (pp)") and reference.text.contains("not bar zero"), "visible context retains conditional horizon, staging semantics and Hold zero distinct from references")
			check(reference.text.contains(Docket.value_text(dialog.quote.references[0]) + "%") and reference.text.contains(Docket.value_text(dialog.quote.references[1]) + "%") and reference.text.contains("unemployment"), "pinned objective and current structural reference use actual quote data")
			check(conditional.get_line_count() <= 2 and reference.get_line_count() <= 3, "compact interpretation stays bounded rather than becoming a sticky prose panel")
			check(conditional.get_parent().size.y <= 80, "pinned caption uses a bounded compact footer instead of a large sticky text wall")
		check(dialog.get_visible_rect().grow(0.5).encloses(dialog.get_ok_button().get_global_rect()), "Cancel stays fully visible beside compact decision context")
		check(dialog.get_ok_button().size.y >= dialog.get_ok_button().get_combined_minimum_size().y, "Cancel retains its complete native target height")
		check(var_to_bytes([dialog.quote, dialog.build_count, game._committee_control_snapshot(), game.career.encode(), game.docket_forecast_calls]) == cache, "compact context/Tab preserves quote, drafts, career, build count and cached forecast calls")
	var order: Array = [dialog.stage_buttons[0], dialog.stage_buttons[1], dialog.stage_buttons[2], dialog.refresh_button, dialog.details_button, dialog.get_ok_button(), dialog.scroll]
	for index in range(order.size()):
		check(order[index].get_node(order[index].focus_next) == order[(index + 1) % order.size()] and order[index].get_node(order[index].focus_previous) == order[(index - 1 + order.size()) % order.size()], "pinned noninteractive context leaves the complete existing keyboard cycle unchanged")
	# Restore Price for the existing pending-navigation and reopen regressions.
	dialog.stage_buttons[0].grab_focus()
	await settle()

func compact_initial_focus_cases(game: Variant, density: float) -> void:
	var original_size := root.size
	var career_bytes: PackedByteArray = game.career.encode()
	var controls: Array = game._committee_control_snapshot()
	root.size = Vector2i((Vector2(800, 480) * density).round())
	await settle()
	for opening in range(2):
		var calls_before: int = game.docket_forecast_calls
		await key(root, KEY_K, true)
		var dialog: Variant = game.committee_docket
		check_stage_visible(dialog, 0, "compact CmdK initial Stage price is visible after popup fit, including Escape/reopen")
		check(not dialog.focus_reveal_pending, "popup settled focus scheduling becomes idle instead of polling")
		if opening == 0:
			await compact_context_cases(game, dialog)
		var cached := var_to_bytes(dialog.quote)
		var builds: int = dialog.build_count
		var ids: Array = dialog.stage_buttons.map(func(button: Button): return button.get_instance_id())
		for logical in [Vector2i(1440, 960), Vector2i(800, 480)]:
			root.size = Vector2i((Vector2(logical) * density).round())
			await settle()
			check_stage_visible(dialog, 0, "popup resize/reflow keeps its existing focused Stage price fully visible")
			check(dialog.stage_buttons.map(func(button: Button): return button.get_instance_id()) == ids and dialog.build_count == builds and var_to_bytes(dialog.quote) == cached, "settled popup focus reveal preserves controls and quote cache")
		check(game.docket_forecast_calls == calls_before + 5 and game.career.encode() == career_bytes and game._committee_control_snapshot() == controls, "initial/resize focus visibility does not forecast again, adopt or submit drafts")
		var before_page: float = dialog.scroll.get_v_scroll_bar().value
		await key(dialog, KEY_PAGEDOWN)
		check(dialog.scroll.get_v_scroll_bar().value > before_page and dialog.stage_buttons[0].has_focus(), "settled reveal does not undo explicit popup Page Down while a Stage button retains focus")
		if opening == 0:
			await pending_navigation_cases(game, dialog)
		await key(dialog, KEY_ESCAPE)
		check(game.committee_button.has_focus(), "closing a docket with scheduled reveal restores opener, not a dead Stage button")
	root.size = original_size
	await settle()

func delta_ui_cases(dialog: Variant) -> void:
	# Synthetic projections exercise display only; no additional economic forecast.
	var original_quote: Dictionary = dialog.quote
	var fixture: Dictionary = original_quote.duplicate(true)
	fixture.entries[0].projection = {"ok": true, "values": [-1.0, 4.0, 1e300]}
	fixture.entries[1].projection = {"ok": true, "values": [-2.0, 4.0, 0.0]}
	fixture.entries[2].projection = {"ok": true, "values": [-2.5, 4.000001, 1e-300]}
	fixture.entries[3].projection = {"ok": true, "values": [-2.0, 4.0, 0.0]}
	fixture.entries[4].projection = {"ok": true, "values": [-1.75, 4.25, 1e300]}
	var raw: PackedByteArray = var_to_bytes(fixture)
	dialog.present(fixture)
	await settle()
	check(var_to_bytes(fixture) == raw, "comparison presentation preserves every raw projection, proposal and quote byte")
	check(dialog.metric_plots.size() == 9 and dialog.delta_values.size() == 9, "available proposals expose absolute values, signed deltas and plots")
	check(dialog.delta_scales[0].radius == 1.0 and dialog.delta_scales[1].radius == 0.25 and dialog.delta_scales[2].radius == 1e300, "one shared symmetric range per metric includes Staged and the actual Hold entry")
	for index in range(9):
		var plot: Variant = dialog.metric_plots[index]
		var metric: int = index % 3
		var value: float = fixture.entries[2 + floori(index / 3.0)].projection.values[metric]
		var held: float = fixture.entries[1].projection.values[metric]
		check(plot.value == value and plot.held_value == held and plot.delta == value - held, "plot keeps exact raw absolute and Hold-derived difference")
		check(dialog.metric_values[index].text == Docket.value_text(value, metric == 2), "absolute value formatter and units remain unchanged")
		check(plot.delta_scale == dialog.delta_scales[metric], "all cards share the identical metric scale")
		for raw_value in [value, held, value - held, plot.delta_scale.radius]:
			check(dialog.delta_values[index].tooltip_text.contains(var_to_str(raw_value)) and dialog.delta_values[index].accessibility_description.contains(var_to_str(raw_value)) and plot.accessibility_description.contains(var_to_str(raw_value)), "rounded ticks retain exact raw value, Hold, difference and shared radius in tooltip/AX detail")
		check(plot.axis_labels().size() == 3 and plot.axis_labels()[2].length() <= 11, "negative-inflation and extreme live synthetic plots retain compact signed axes")
		check(absf((plot.position_for(-plot.delta_scale.radius) + plot.position_for(plot.delta_scale.radius)) * 0.5 - plot.position_for(0.0)) < 1e-7, "each graphical scale is symmetric about Hold zero")
		check(is_finite(plot.position_for(plot.delta)), "finite extremes never produce nonfinite plot coordinates")
	check(dialog.metric_plots[2].render_state() == "below_resolution" and dialog.delta_values[2].text.begins_with("+<"), "a nonzero delta that cannot survive normalization is explicitly not plotted, never shown as a tie")
	check(dialog.metric_plots[3].render_state() == "tie" and dialog.delta_values[3].text.contains("Same"), "exact ties have a distinct zero marker and text")
	check(dialog.metric_plots[0].direction_color() == Color("91c9e8") and dialog.metric_plots[7].direction_color() == Color("e9b76e"), "negative inflation uses the negative-direction color, not a lower-is-better judgment")
	check(dialog.metric_plots[0].position_for(dialog.metric_plots[0].delta) < dialog.metric_plots[0].position_for(0.0) and dialog.metric_plots[6].position_for(dialog.metric_plots[6].delta) > dialog.metric_plots[6].position_for(0.0), "negative and positive changes lie on opposite sides of the shared Hold zero")
	check(labels(dialog).contains("not welfare") and labels(dialog).contains("Inflation objective") and labels(dialog).contains("structural unemployment"), "visible context distinguishes direction from welfare and retains objective/structural references")
	# Resolve Hold by ID, never by a target or a positional shortcut.
	var moved: Dictionary = fixture.duplicate(true)
	var held_entry: Dictionary = moved.entries.pop_at(1)
	moved.entries.append(held_entry)
	check(CommitteeDialog.comparison_scales(moved.entries) == dialog.delta_scales, "Hold lookup is ID-based even when entries are reordered")
	fixture.entries[1].projection = {"ok": false, "error": "Hold unavailable"}
	raw = var_to_bytes(fixture)
	dialog.present(fixture)
	await settle()
	check(dialog.metric_values.size() == 9 and dialog.metric_plots.is_empty() and dialog.delta_values[0].text.contains("Hold unavailable"), "unavailable Hold retains absolute proposals but never substitutes an objective or zero baseline")
	check(var_to_bytes(fixture) == raw and not dialog.stage_buttons[0].disabled, "unavailable Hold preserves raw data and stageable control validity")
	fixture.entries[1].projection = {"ok": true, "values": [-2.0, 4.0, 0.0]}
	fixture.entries[3].projection = {"ok": false, "error": "Individual path unavailable"}
	dialog.present(fixture)
	await settle()
	check(dialog.metric_values.size() == 6 and dialog.metric_plots.size() == 6 and not dialog.stage_buttons[1].disabled, "individual projection failure omits only its metrics and keeps stage validity separate")
	fixture.entries[1].projection.values[0] = -1.7e308
	fixture.entries[2].projection.values[0] = 1.7e308
	raw = var_to_bytes(fixture)
	dialog.present(fixture)
	await settle()
	check(dialog.delta_scales[0].overflow and dialog.metric_plots[0].render_state() == "overflow" and dialog.metric_plots[3].render_state() == "overflow", "overflow disables the shared metric scale honestly for every card, without saturated endpoints")
	check(dialog.delta_values[0].text.contains("+overflow") and var_to_bytes(fixture) == raw, "overflow preserves signed fallback and exact raw quotes")
	# An entirely tied metric is genuinely flat, not an invented ±1 outcome range.
	for item in fixture.entries:
		if item.projection.ok:
			item.projection.values = [4.0, 4.0, 0.0]
	dialog.present(fixture)
	await settle()
	check(dialog.delta_scales[0].radius == 0.0 and dialog.metric_plots[0].render_state() == "tie", "all-exact-tie paths keep a zero-radius scale")
	fixture.entries[1].projection.values[0] = 0.0
	for item in fixture.entries:
		if item.id != "hold" and item.projection.ok:
			item.projection.values[0] = 1e-300
	dialog.present(fixture)
	await settle()
	check(dialog.delta_scales[0].radius == 1e-300 and dialog.metric_plots[0].render_state() == "point", "tiny finite deltas remain fully drawable when their shared scale can represent them")
	check(dialog.metric_plots[0].position_for(1e-300) > dialog.metric_plots[0].position_for(0.0) and dialog.delta_values[0].text.begins_with("+<"), "sub-precision text retains direction even when tiny deltas span the plot")
	dialog.present(original_quote)
	await settle()

func run() -> void:
	delta_source_cases()
	axis_tick_cases()
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
	for enter_key in [KEY_ENTER, KEY_KP_ENTER]:
		await key(dialog, enter_key, true)
		await key(dialog, enter_key, false, true)
		await key(dialog, enter_key, false, false, true)
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
	for index in range(2):
		var left: Rect2 = dialog.proposal_cards[index].get_global_rect()
		var right: Rect2 = dialog.proposal_cards[index + 1].get_global_rect()
		check(left.end.x <= right.position.x and absf(left.position.y - right.position.y) < 1.0, "desktop cards occupy three nonoverlapping columns on the same row")
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
	var plot_ids: Array = []
	for plot in dialog.metric_plots:
		plot_ids.append(plot.get_instance_id())
	var popup_builds: int = dialog.build_count
	var cached_quote: PackedByteArray = var_to_bytes(dialog.quote)
	var popup_calls: int = game.docket_forecast_calls
	dialog.stage_buttons[1].grab_focus()
	# Exercise production report fitting by resizing this private headless root;
	# the docket itself must not resize its parent or replace focused controls.
	root.size = Vector2i((Vector2(800, 480) * density).round())
	var compact_root_size: Vector2i = root.size
	await settle()
	check(root.get_visible_rect().size.distance_to(Vector2(800, 480)) <= 1.5, "private compact fixture establishes an 800x480 logical viewport")
	check(dialog.get_size_with_decorations().x <= root.get_visible_rect().size.x and dialog.get_size_with_decorations().y <= root.get_visible_rect().size.y, "compact docket stays bounded by its private parent")
	print("CONTEXT_FIT: root=", root.get_visible_rect(), " dialog=", dialog.size, " decorated=", dialog.get_size_with_decorations(), " min=", dialog.get_contents_minimum_size(), " scroll_min=", dialog.scroll.get_combined_minimum_size(), " footer=", dialog.context_footer.get_global_rect(), " footer_min=", dialog.context_footer.get_combined_minimum_size())
	check(dialog.cards.columns == 1 and dialog.stage_buttons[1].has_focus(), "800x480 private parent stacks the same cards without stealing focus")
	check_stage_visible(dialog, 1, "settled compact resize reveals the still-focused Stage jobs without Tab")
	for index in range(3):
		check(dialog.proposal_cards[index].get_instance_id() == card_ids[index], "reflow retains original Control identities")
	for index in range(9):
		check(dialog.metric_plots[index].get_instance_id() == plot_ids[index], "reflow retains original signed-delta plots")
	check(dialog.build_count == popup_builds and var_to_bytes(dialog.quote) == cached_quote, "stacked reflow neither rebuilds nor rewrites cached projections")
	check(game.docket_forecast_calls == popup_calls, "popup reflow never recomputes forecasts")
	check(dialog.scroll.get_h_scroll_bar().max_value <= dialog.scroll.size.x + 1.0, "stacked cards wrap without horizontal overflow")
	for index in range(2):
		var upper: Rect2 = dialog.proposal_cards[index].get_global_rect()
		var lower: Rect2 = dialog.proposal_cards[index + 1].get_global_rect()
		check(upper.end.y <= lower.position.y and absf(upper.position.x - lower.position.x) < 1.0, "compact cards form one ordered, nonoverlapping stack")
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
	check(dialog.build_count == popup_builds and var_to_bytes(dialog.quote) == cached_quote and game.docket_forecast_calls == popup_calls, "desktop reflow retains the same cache without a rebuild or forecast")
	var calls_before_display_cases: int = game.docket_forecast_calls
	var career_before_display_cases: PackedByteArray = game.career.encode()
	var controls_before_display_cases: Array = game._committee_control_snapshot()
	await delta_ui_cases(dialog)
	check(game.docket_forecast_calls == calls_before_display_cases and game.career.encode() == career_before_display_cases and game._committee_control_snapshot() == controls_before_display_cases, "synthetic display coverage preserves forecast count, career and drafts")
	await key(dialog, KEY_ESCAPE)
	await compact_initial_focus_cases(game, density)
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
