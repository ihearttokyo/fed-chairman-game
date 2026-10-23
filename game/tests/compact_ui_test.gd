extends SceneTree
var failures := 0

class ResizeCareer:
	extends "res://play/career.gd"
	var forecast_calls := 0
	func forecast(policy: Dictionary, follow_guidance: bool = false) -> Dictionary:
		forecast_calls += 1
		return super.forecast(policy, follow_guidance)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var density := maxf(1.0, DisplayServer.screen_get_scale(root.current_screen))
	root.size = Vector2i((Vector2(800, 480) * density).round())
	var cold: Control = load("res://main.tscn").instantiate()
	root.add_child(cold)
	await settle_layout()
	check(root.get_visible_rect().size.distance_to(Vector2(800, 480)) <= 1.5, "cold small window keeps its native 800x480 canvas")
	check(cold.rate.get_line_edit().has_focus() and cold.cockpit_scroll.get_global_rect().encloses(cold.rate.get_line_edit().get_global_rect()) and cold.get_viewport_rect().encloses(cold.rate.get_line_edit().get_global_rect()), "cold small window exposes its focused native policy field")
	cold.free()
	root.size = Vector2i((Vector2(960, 640) * density).round())
	var game = load("res://main.tscn").instantiate()
	game.career = ResizeCareer.new()
	root.add_child(game)
	await process_frame
	await process_frame
	check(game.cockpit_scroll.get_global_rect().encloses(game.rate.get_line_edit().get_global_rect()), "cold narrow cockpit exposes the focused policy rate, not only decoration")
	check(game._keyboard_focus_order().find(game.rate.get_line_edit()) < game._keyboard_focus_order().find(game.charts[0]), "narrow keyboard order reaches policy before the lower charts")
	check(float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec")) == 0.0, "tooltips have no hover delay")
	for pair in game.stats:
		check(pair[0].accessibility_name.contains(pair[0].text), "each metric accessible name includes its current numeric value")
		check(pair[0].mouse_filter != Control.MOUSE_FILTER_IGNORE, "metric values accept hover so their tooltips can appear")
		check(pair[0].get_parent() is HBoxContainer, "metric heading, value and reference occupy a single row")
		check(pair[0].get_parent().get_parent().size.y <= 60, "metric row does not retain oversized card padding")
		check(not pair[0].tooltip_text.is_empty() and pair[0].accessibility_description == pair[0].tooltip_text, "metric detail remains in immediate tooltip and assistive description")
	var titles: Array[Label] = []
	for label in game.find_children("*", "Label", true, false):
		if label.text == "THE CHAIR":
			titles.append(label)
		check(not label.text.contains("THE ECONOMY IS YOUR RESPONSIBILITY") and not label.text.contains("Original Blender miniature") and not label.text.contains("A research-informed strategy game"), "cockpit has no slogans, provenance or legal footer")
	check(titles.size() == 1 and titles[0].get_parent() is HBoxContainer, "title and product description share one line")
	check(game.case_detail.text.ends_with("Stocks: % of current annual GDP"), "stock units are explicit without repeating the metric names")
	check(not game.case_detail.text.contains("Balance price stability") and game.case_detail.text.contains("Holdings") and game.case_detail.text.contains("Loans"), "current conditions retain stocks without introductory filler")
	game._advance()
	for pair in game.stats:
		check(pair[0].accessibility_name.contains(pair[0].text), "accessible metric names refresh after a real completed decision")
	var preserved = game.career.encode()
	game._help()
	var dialog = game.get_child(game.get_child_count() - 1)
	check(dialog.get_child(0).text.contains("No Federal Reserve affiliation"), "disclosure remains in help")
	dialog.get_ok_button().pressed.emit()
	await process_frame
	check(game.career.encode() == preserved, "reading help does not mutate the career")
	await check_responsive_resize(game)
	game.free()
	# Native audio releases stopped playbacks on its next mix, not a scene frame.
	var audio_release_deadline := Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < audio_release_deadline:
		await process_frame
	if failures == 0:
		print("PASS: compact task-only cockpit, retained detail, production responsive resize and zero-delay tooltips")
	quit(1 if failures else 0)

func resize_snapshot(game: Control) -> PackedByteArray:
	var inputs: Array = []
	for spin in [game.rate, game.guidance, game.assets, game.liquidity, game.inflation_response, game.activity_response]:
		var edit: LineEdit = spin.get_line_edit()
		inputs.append([spin.value, edit.text, edit.caret_column, edit.get_selection_from_column() if edit.has_selection() else -1, edit.get_selection_to_column() if edit.has_selection() else -1])
	var semantics: Array = []
	var controls: Array = game.find_children("*", "Control", true, false)
	# Panel order may change; verify each stable control, not traversal order.
	controls.sort_custom(func(a: Control, b: Control): return a.get_instance_id() < b.get_instance_id())
	for control in controls:
		semantics.append([control.get_instance_id(), control.get_parent().get_instance_id(), control.accessibility_name, control.accessibility_description, control.tooltip_text, control.get_theme_font_size("font_size")])
	var saved := FileAccess.file_exists(game.save_path)
	return var_to_bytes([game.career.encode(), game.clean_career, game._policy(), inputs, semantics,
		game.forecast_label.text, game.quarter_label.text, game.consequence.text, game.mandate_label.text, game.briefing.text, game.case_detail.text,
		game.status_label.text, game.custom_guidance.visible, game.reduced_motion, game.city.rotation if game.reduced_motion else null,
		game.career.forecast_calls, game.find_children("*", "", true, false).size(), saved, FileAccess.get_file_as_bytes(game.save_path) if saved else null])

func settle_layout() -> void:
	for frame in range(6):
		await process_frame

func key(window: Window, code: Key) -> void:
	var receiver: Window = root if window.is_embedded() else window
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	receiver.push_input(event)
	event = event.duplicate()
	event.pressed = false
	receiver.push_input(event)
	await process_frame
	await process_frame

func check_report_bounds(dialog: AcceptDialog) -> void:
	var decorated := Rect2(Vector2(dialog.get_position_with_decorations()), Vector2(dialog.get_size_with_decorations()))
	check(root.get_visible_rect().grow(1).encloses(decorated), "small report including native chrome remains inside its logical parent")
	for control in [dialog.find_children("*", "TextEdit", true, false)[0], dialog.get_ok_button()]:
		check(dialog.get_visible_rect().grow(1).encloses(control.get_global_rect()), "small report text and dismissal button remain inside the dialog")

func check_small_resize(game: Control, density: float, edit: LineEdit, preserved: PackedByteArray) -> void:
	var original_position := root.position
	var original_mode := root.mode
	for logical in [Vector2i(800, 480), Vector2i(800, 240), Vector2i(400, 480), Vector2i(800, 480)]:
		var physical := Vector2i((Vector2(logical) * density).round())
		root.size = physical
		await settle_layout()
		check(root.size == physical and root.position == original_position and root.mode == original_mode, "small resize preserves requested parent geometry")
		check(root.get_visible_rect().size.distance_to(Vector2(logical)) <= 1.5 and root.get_stretch_transform().get_scale().distance_to(Vector2.ONE * density) <= 0.02, "small resize retains native text and target scale")
		check(resize_snapshot(game) == preserved and edit.has_focus(), "small resize preserves parents, draft selection, career, preview, save and focus without forecasts")
		check(game.get_viewport_rect().grow(1).encloses(edit.get_global_rect()) and game.cockpit_scroll.get_global_rect().grow(1).encloses(edit.get_global_rect()), "small resize reveals the still-focused native policy field")
		var vertical: VScrollBar = game.overflow_scroll.get_v_scroll_bar()
		var horizontal: HScrollBar = game.overflow_scroll.get_h_scroll_bar()
		if logical == Vector2i(800, 240):
			check(vertical.max_value > vertical.page, "short-window fixture genuinely enables whole-content footer overflow")
		if logical == Vector2i(400, 480):
			check(horizontal.max_value > horizontal.page, "below irreducible native widths the whole window scrolls horizontally instead of shrinking text")
		if logical == Vector2i(800, 480):
			check(vertical.max_value <= vertical.page + 0.5 and horizontal.max_value <= horizontal.page + 0.5 and game.get_viewport_rect().grow(1).encloses(game.decision_button.get_global_rect()), "native 800x480 keeps the fitting footer genuinely pinned and Adopt visible")
		for viewport in game.find_children("*", "SubViewport", true, false):
			check(viewport.size.x <= 2048 and viewport.size.y <= 2048 and viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "small resize retains bounded static city rendering")
	var reserve: float = 48 + game.cockpit_scroll.get_v_scroll_bar().get_combined_minimum_size().x + game.overflow_scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var grid: GridContainer = game.metric_layout
	var cards := grid.get_children()
	var paired := ceili(maxf(cards[0].get_combined_minimum_size().x, cards[2].get_combined_minimum_size().x) + maxf(cards[1].get_combined_minimum_size().x, cards[3].get_combined_minimum_size().x) + grid.get_theme_constant("h_separation") + reserve)
	for delta in [-1, 0, 1]:
		root.size = Vector2i((Vector2(paired + delta, 700) * density).round())
		await settle_layout()
		check(grid.columns == (1 if delta < 0 else 2), "metrics cross their measured paired/single threshold exactly")
		check(resize_snapshot(game) == preserved and edit.has_focus(), "metric threshold crossings preserve the unsubmitted selected draft")
	for row in [game.charts[0].get_parent(), game.action_buttons, game.reinvestment.get_parent()]:
		var minimum: float = row.get_child(0).get_combined_minimum_size().x + row.get_child(1).get_combined_minimum_size().x + row.get_theme_constant("separation") + reserve
		if row == game.reinvestment.get_parent():
			minimum += game.policy_panel.get_theme_stylebox("panel").get_minimum_size().x
		for delta in [-1, 0, 1]:
			root.size = Vector2i((Vector2(ceili(minimum) + delta, 700) * density).round())
			await settle_layout()
			check(bool(row.get("vertical")) == (delta < 0), "native row stacks only below its measured combined minimum: " + str(row.get_path()))
			check(resize_snapshot(game) == preserved and edit.has_focus(), "row threshold crossings retain control parents, numeric draft and state")
	await check_resize_history(game, density, edit, preserved, reserve)

func check_resize_history(game: Control, density: float, edit: LineEdit, preserved: PackedByteArray, reserve: float) -> void:
	var row: BoxContainer = game.action_buttons
	var width := ceili(game._row_minimum(row) + reserve)
	root.size = Vector2i((Vector2(width, 700) * density).round())
	await settle_layout()
	check(not row.vertical, "hysteresis fixture starts with fitting horizontal actions")
	var height := ceili(game.overflow_scroll.get_child(0).get_combined_minimum_size().y)
	for logical in [Vector2i(width, height + 1), Vector2i(width, height - 1), Vector2i(width, height + 1)]:
		root.size = Vector2i((Vector2(logical) * density).round())
		await settle_layout()
	check(not row.vertical and game.overflow_scroll.get_v_scroll_bar().max_value <= game.overflow_scroll.get_v_scroll_bar().page + 0.5, "shrink/regrow returns fitting horizontal actions and pinned footer independent of resize history")
	check(resize_snapshot(game) == preserved and edit.has_focus(), "height boundary crossings preserve the selected policy draft and career")

func check_small_actions(game: Control, density: float) -> void:
	root.size = Vector2i((Vector2(800, 240) * density).round())
	await settle_layout()
	game.rate.get_line_edit().grab_focus()
	var quarter: int = game.career.state.quarter_index
	await key(root, KEY_ENTER)
	check(game.rate.value == -1.0 and game.career.state.quarter_index == quarter, "ordinary Return commits the retained -1. draft without adopting a quarter")
	game.cockpit_scroll.grab_focus()
	game.cockpit_scroll.scroll_vertical = 80
	await settle_layout()
	check(game.cockpit_scroll.scroll_vertical > 0, "nested scrolling fixture starts below the inner cockpit top")
	await key(root, KEY_END)
	check(game.overflow_scroll.scroll_vertical > 0 and game.get_viewport_rect().grow(1).encloses(game.decision_button.get_global_rect()), "focused cockpit End exposes the genuinely overflowing footer")
	check(abs(game.cockpit_scroll.scroll_vertical - (game.cockpit_scroll.get_v_scroll_bar().max_value - game.cockpit_scroll.get_v_scroll_bar().page)) <= 1.0, "End reaches both inner and outer scrolling ends")
	await key(root, KEY_HOME)
	check(game.overflow_scroll.scroll_vertical == 0, "focused cockpit Home returns whole-content overflow to its start")
	check(game.cockpit_scroll.scroll_vertical == 0, "focused cockpit Home resets inner content as well as outer overflow")
	var inner_before: int = game.cockpit_scroll.scroll_vertical
	await key(root, KEY_PAGEDOWN)
	check(game.cockpit_scroll.scroll_vertical > inner_before and game.overflow_scroll.scroll_vertical == 0, "Page Down traverses inner cockpit before moving outer overflow")
	game.cockpit_scroll.scroll_vertical = int(game.cockpit_scroll.get_v_scroll_bar().max_value)
	await settle_layout()
	await key(root, KEY_PAGEDOWN)
	check(game.overflow_scroll.scroll_vertical > 0, "Page Down at the inner bottom falls back to outer overflow")
	var outer_before: int = game.overflow_scroll.scroll_vertical
	inner_before = game.cockpit_scroll.scroll_vertical
	await key(root, KEY_PAGEUP)
	check(game.cockpit_scroll.scroll_vertical < inner_before and game.overflow_scroll.scroll_vertical == outer_before, "Page Up first traverses inner content without moving outer overflow")
	game.cockpit_scroll.scroll_vertical = 0
	await settle_layout()
	await key(root, KEY_PAGEUP)
	check(game.overflow_scroll.scroll_vertical < outer_before, "Page Up at the inner top falls back to outer overflow")


	game.rate.get_line_edit().grab_focus()
	var compare: Button
	for control in game.keyboard_controls:
		if control is Button and control.text == "Compare policy paths":
			compare = control
	var order: Array = game._keyboard_focus_order()
	var start := order.find(game.rate.get_line_edit())
	for index in range(start + 1, order.find(compare) + 1):
		await key(root, KEY_TAB)
		check(root.gui_get_focus_owner() == order[index], "small-window Tab follows the unchanged complete control order")
	check(compare != null and compare.has_focus() and game.get_viewport_rect().grow(1).encloses(compare.get_global_rect()), "Tab exposes Compare through real whole-content scrolling")
	var career_bytes: PackedByteArray = game.career.encode()
	var staged: Dictionary = game._policy().duplicate(true)
	await key(root, KEY_ENTER)
	var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	check_report_bounds(dialog)
	var body: TextEdit = dialog.find_children("*", "TextEdit", true, false)[0]
	await key(dialog, KEY_END)
	check(body.get_v_scroll_bar().value > 0, "small comparison keyboard End reaches its complete report tail")
	await key(dialog, KEY_ESCAPE)
	check(not is_instance_valid(dialog) and compare.has_focus() and game.career.encode() == career_bytes and game._policy() == staged, "small comparison Escape restores its invoker without changing career or policy")
	await key(root, KEY_TAB)
	check(game.decision_button.has_focus() and game.get_viewport_rect().grow(1).encloses(game.decision_button.get_global_rect()), "Tab exposes Adopt in an actually overflowing footer")
	await key(root, KEY_ENTER)
	check(game.career.state.quarter_index == quarter + 1 and game.consequence.text.contains("Q%d OUTCOME" % (quarter + 1)) and game.get_viewport_rect().grow(1).encloses(game.consequence.get_global_rect()), "reachable small-window Adopt produces exactly one quarter and visible outcome feedback")

func check_resize_bounds(game: Control, logical: Vector2i, density: float) -> void:
	var visible: Rect2 = game.get_viewport_rect()
	var scale := root.get_stretch_transform().get_scale()
	check(scale.x >= density - 0.01 and scale.y >= density - 0.01, "production resize retains native text-density floor at " + str(logical))
	check(visible.size.distance_to(Vector2(logical)) <= 1.5, "production logical viewport follows window aspect without extra shrinking at " + str(logical))
	for control in game.find_children("*", "Control", true, false):
		if control.is_visible_in_tree():
			var rect: Rect2 = control.get_global_rect()
			check(rect.position.x >= -0.5 and rect.end.x <= visible.end.x + 0.5, "no horizontal clipping: " + str(control.get_path()) + " at " + str(logical))
	for control in [game.consequence, game.mandate_label, game.status_label, game.decision_button, game.follow_up_toggle]:
		check(visible.grow(0.5).encloses(control.get_global_rect()), "complete footer stays within the client: " + str(control.get_path()) + " at " + str(logical))
	for control in game.keyboard_controls:
		if control is Button and control.text == "Compare policy paths":
			check(visible.grow(0.5).encloses(control.get_global_rect()), "Compare remains within the client at " + str(logical))
	check(game.cockpit_scroll.size.y >= 200, "expanded guidance retains a usable vertical cockpit at " + str(logical))
	if logical.x == 960:
		var first: Rect2 = game.stats[0][0].get_parent().get_parent().get_global_rect()
		var second: Rect2 = game.stats[1][0].get_parent().get_parent().get_global_rect()
		var third: Rect2 = game.stats[2][0].get_parent().get_parent().get_global_rect()
		var fourth: Rect2 = game.stats[3][0].get_parent().get_parent().get_global_rect()
		check(is_equal_approx(first.position.y, second.position.y) and is_equal_approx(third.position.y, fourth.position.y) and third.position.y > first.position.y, "narrow metrics form two balanced paired rows")
	var order: Array = game._keyboard_focus_order()
	var panel: Node = game.rate.get_parent().get_parent().get_parent()
	check((order.find(game.rate.get_line_edit()) < order.find(game.charts[0])) == (panel.get_index() == 0), "Tab follows the visible policy/chart panel order")
	var bar: HScrollBar = game.cockpit_scroll.get_h_scroll_bar()
	check(bar.max_value <= bar.page + 0.5, "cockpit needs no horizontal scrolling at " + str(logical))
	for viewport in game.find_children("*", "SubViewport", true, false):
		check(viewport.size.x <= 2048 and viewport.size.y <= 2048, "resize retains bounded city allocation")
		check(viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "static resize never enables perpetual city rendering")

func check_responsive_resize(game: Control) -> void:
	var original_size := root.size
	var original_position := root.position
	var original_mode := root.mode
	var density := maxf(1.0, DisplayServer.screen_get_scale(root.current_screen))
	# Pure 2x checks supplement, but do not replace, the actual display-density run.
	check(game.has_method("_responsive_canvas_size"), "shared native-density sizing exists")
	if game.has_method("_responsive_canvas_size"):
		check(game._responsive_canvas_size(Vector2i(64, 64), 1.0) == Vector2i(64, 64), "tiny native canvas never claims readability by shrinking text")
		for factor in [1.0, 2.0]:
			check(game._responsive_canvas_size(Vector2i(Vector2(800, 480) * factor), factor) == Vector2i(800, 480), "native-density sizing retains logical 800x480 at " + str(factor) + "x")
			check(game._responsive_canvas_size(Vector2i(Vector2(960, 640) * factor), factor) == Vector2i(960, 640), "native-density sizing retains logical 960x640 at " + str(factor) + "x")
	game._advance()
	game.career.shocks[game.career.decisions.size()].credit_risk_innovation_pct = 0.03
	game._refresh()
	check(game.briefing.text.contains("Credit-risk impulse +0.03 pp (spread pricing)."), "compact resize fixture retains current credit units and magnitude")
	check(game.briefing.text.contains("Credit-risk impulse +0.03 pp (spread pricing)."), "responsive matrix begins with current credit news, not a consumed pulse")
	game._staff_rule()
	game.commitment.select(2)
	game.commitment.item_selected.emit(2)
	await settle_layout()
	var edit: LineEdit = game.rate.get_line_edit()
	edit.grab_focus()
	edit.text = "-1."
	edit.caret_column = 2
	edit.select(1, 2)
	var preserved := resize_snapshot(game)
	var body: Container = game.charts[0].get_parent().get_parent().get_parent()
	var layout_breakpoint := ceili(body.get_child(0).get_combined_minimum_size().x + body.get_child(1).get_combined_minimum_size().x + body.get_theme_constant("separation") + 48 + game.cockpit_scroll.get_v_scroll_bar().get_combined_minimum_size().x + game.overflow_scroll.get_v_scroll_bar().get_combined_minimum_size().x)
	var sizes := [Vector2i(1306, 903), Vector2i(960, 640), Vector2i(1180, 700), Vector2i(1440, 960), Vector2i(1920, 640), Vector2i(960, 1200),
		Vector2i(layout_breakpoint - 1, 700), Vector2i(layout_breakpoint, 700), Vector2i(layout_breakpoint + 1, 700), Vector2i(960, 640), Vector2i(1440, 960)]
	for logical in sizes:
		var physical := Vector2i((Vector2(logical) * density).round())
		root.size = physical
		await settle_layout()
		check(root.size == physical and root.position == original_position and root.mode == original_mode, "resize never resets requested geometry, position or mode")
		check_resize_bounds(game, logical, density)
		if logical == Vector2i(1306, 903):
			var row: Control = game.case_title.get_parent().get_parent()
			check(game.case_detail.size.x >= (row.size.x - row.get_theme_constant("separation")) * 0.5 - 0.5, "current stocks receive at least half the usable city row at 1306x903")
		check(resize_snapshot(game) == preserved, "resize preserves career, numeric values/drafts/selection, semantics, fonts, preview, motion and nodes without forecasts")
		check(root.gui_get_focus_owner() == edit, "numeric draft keeps focus through every layout_breakpoint crossing")
		check(bool(body.get("vertical")) == (logical.x < layout_breakpoint), "body stacks only below its measured combined minimum")
		var footer: Container = game.consequence.get_parent().get_parent()
		check(bool(footer.get("vertical")) == bool(body.get("vertical")), "footer and body share the responsive orientation")
		check(game.overflow_scroll.get_v_scroll_bar().max_value <= game.overflow_scroll.get_v_scroll_bar().page + 0.5 and game.overflow_scroll.get_h_scroll_bar().max_value <= game.overflow_scroll.get_h_scroll_bar().page + 0.5, "supported sizes genuinely pin the complete footer without outer overflow")
	await check_small_resize(game, density, edit, preserved)
	var metric_grid: GridContainer = game.stats[0][0].get_parent().get_parent().get_parent()
	var four_columns: float = 3.0 * metric_grid.get_theme_constant("h_separation") + 48 + game.cockpit_scroll.get_v_scroll_bar().get_combined_minimum_size().x + game.overflow_scroll.get_v_scroll_bar().get_combined_minimum_size().x
	for card in metric_grid.get_children():
		four_columns += card.get_combined_minimum_size().x
	root.size = Vector2i((Vector2(ceili(four_columns) - 1, 700) * density).round())
	await settle_layout()
	check(metric_grid.columns == 2, "dynamic-metric fixture starts just below its four-column threshold")
	var metric_career: PackedByteArray = game.career.encode()
	var metric_forecasts: int = game.career.forecast_calls
	var old_support: String = game.stats[3][0].text
	game.stats[3][0].text = "9 / 100" # Synthetic display-width fixture, not a policy outcome.
	await settle_layout()
	check(metric_grid.columns == 4, "a card-only width change reflows four fitting columns without native resize")
	game.stats[3][0].text = old_support
	await settle_layout()
	check(metric_grid.columns == 2, "restored metric width returns to paired rows at the same window size")
	check(game.career.encode() == metric_career and game.career.forecast_calls == metric_forecasts, "dynamic metric reflow never mutates the career or computes a forecast")
	await check_small_actions(game, density)
	# A focused chart must keep the inspected quarter, not select latest on resize.
	game.charts[0].grab_focus()
	game.charts[0]._inspect(0)
	await settle_layout()
	preserved = resize_snapshot(game)
	for logical in [Vector2i(960, 640), Vector2i(1440, 960)]:
		root.size = Vector2i((Vector2(logical) * density).round())
		await settle_layout()
		check(root.gui_get_focus_owner() == game.charts[0] and game.charts[0].hovered == 0, "resize preserves chart focus and selected historical quarter")
		check(resize_snapshot(game) == preserved, "focused-chart resize does not refresh career or controls")
	# Fixture uses the production terminal header string without 240 extra turns.
	var original_header: String = game.quarter_label.text
	game.quarter_label.text = "MANDATE NOT MET · 240 MEETINGS"
	root.size = Vector2i((Vector2(960, 640) * density).round())
	await settle_layout()
	check_resize_bounds(game, Vector2i(960, 640), density)
	game.quarter_label.text = original_header
	var help_invoker: Control = root.gui_get_focus_owner()
	game._help()
	var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	await settle_layout()
	var modal_focus: Control = dialog.gui_get_focus_owner()
	var help_body: TextEdit = dialog.get_child(0)
	help_body.select_all()
	var help_selection := help_body.get_selected_text()
	preserved = resize_snapshot(game)
	root.size = Vector2i((Vector2(960, 1200) * density).round())
	await settle_layout()
	check(dialog.visible and dialog.gui_get_focus_owner() == modal_focus, "resize leaves an open modal and its focus intact")
	check(resize_snapshot(game) == preserved, "resize under a modal preserves state and node identity")
	for logical in [Vector2i(800, 480), Vector2i(800, 240)]:
		var physical := Vector2i((Vector2(logical) * density).round())
		root.size = physical
		await settle_layout()
		check_report_bounds(dialog)
		check(root.size == physical and root.position == original_position and root.mode == original_mode, "small open report never grows or relocates its parent")
		check(dialog.gui_get_focus_owner() == modal_focus and help_body.get_selected_text() == help_selection and resize_snapshot(game) == preserved, "open-report shrink preserves native selection, focus, parents, policy, career, preview and save")
	await key(dialog, KEY_ENTER)
	await settle_layout()
	check(not is_instance_valid(dialog) and root.gui_get_focus_owner() == help_invoker, "small Help Return dismisses and restores its exact invoking control")
	var motion: CheckButton
	for control in game.keyboard_controls:
		if control is CheckButton and control.text == "Animate city":
			motion = control
	check(motion != null, "responsive cockpit retains its motion control")
	if motion != null:
		motion.button_pressed = true
		await settle_layout()
		preserved = resize_snapshot(game)
		root.size = Vector2i((Vector2(1440, 960) * density).round())
		await settle_layout()
		check(not game.reduced_motion and resize_snapshot(game) == preserved, "resize preserves enabled motion without resetting controls or forecasts")
		for viewport in game.find_children("*", "SubViewport", true, false):
			check(viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and viewport.size.x <= 2048 and viewport.size.y <= 2048, "animated resize retains bounded continuous city rendering")
		motion.button_pressed = false
	root.size = original_size
	await settle_layout()
