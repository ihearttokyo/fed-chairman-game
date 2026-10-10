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
	var game = load("res://main.tscn").instantiate()
	game.career = ResizeCareer.new()
	root.add_child(game)
	await process_frame
	await process_frame
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
	if failures == 0:
		print("PASS: compact task-only cockpit, retained detail, production responsive resize and zero-delay tooltips")
	quit(1 if failures else 0)

func resize_snapshot(game: Control) -> PackedByteArray:
	var inputs: Array = []
	for spin in [game.rate, game.guidance, game.assets, game.liquidity, game.inflation_response, game.activity_response]:
		var edit: LineEdit = spin.get_line_edit()
		inputs.append([spin.value, edit.text, edit.caret_column, edit.get_selection_from_column() if edit.has_selection() else -1, edit.get_selection_to_column() if edit.has_selection() else -1])
	var semantics: Array = []
	for control in game.find_children("*", "Control", true, false):
		semantics.append([control.accessibility_name, control.accessibility_description, control.tooltip_text, control.get_theme_font_size("font_size")])
	return var_to_bytes([game.career.encode(), game.clean_career, game._policy(), inputs, semantics,
		game.forecast_label.text, game.quarter_label.text, game.consequence.text, game.mandate_label.text,
		game.status_label.text, game.custom_guidance.visible, game.reduced_motion, game.city.rotation if game.reduced_motion else null,
		game.career.forecast_calls, game.find_children("*", "", true, false).size()])

func settle_layout() -> void:
	for frame in range(6):
		await process_frame

func check_resize_bounds(game: Control, logical: Vector2i, density: float) -> void:
	var visible: Rect2 = game.get_viewport_rect()
	var scale := root.get_stretch_transform().get_scale()
	check(scale.x >= density - 0.01 and scale.y >= density - 0.01, "production resize retains native text-density floor at " + str(logical))
	check(visible.size.distance_to(Vector2(logical)) <= 1.5, "production logical viewport follows window aspect without extra shrinking at " + str(logical))
	for control in game.find_children("*", "Control", true, false):
		if control.is_visible_in_tree():
			var rect: Rect2 = control.get_global_rect()
			check(rect.position.x >= -0.5 and rect.end.x <= visible.end.x + 0.5, "no horizontal clipping: " + str(control.get_path()) + " at " + str(logical))
	for control in [game.consequence, game.mandate_label, game.status_label, game.decision_button]:
		check(visible.grow(0.5).encloses(control.get_global_rect()), "complete footer stays within the client: " + str(control.get_path()) + " at " + str(logical))
	for control in game.keyboard_controls:
		if control is Button and control.text == "Compare policy paths":
			check(visible.grow(0.5).encloses(control.get_global_rect()), "Compare remains within the client at " + str(logical))
	check(game.cockpit_scroll.size.y >= 200, "expanded guidance retains a usable vertical cockpit at " + str(logical))
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
		check(game._responsive_canvas_size(Vector2i(64, 64), 1.0) == Vector2i(960, 960), "below readable support the uniform fallback keeps the complete cockpit reachable")
		for factor in [1.0, 2.0]:
			check(game._responsive_canvas_size(Vector2i(Vector2(960, 640) * factor), factor) == Vector2i(960, 640), "native-density sizing retains logical 960x640 at " + str(factor) + "x")
	game._advance()
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
	var layout_breakpoint := ceili(body.get_child(0).get_combined_minimum_size().x + body.get_child(1).get_combined_minimum_size().x + body.get_theme_constant("separation") + 48 + game.cockpit_scroll.get_v_scroll_bar().get_combined_minimum_size().x)
	var sizes := [Vector2i(960, 640), Vector2i(1180, 700), Vector2i(1440, 960), Vector2i(1920, 640), Vector2i(960, 1200),
		Vector2i(layout_breakpoint - 1, 700), Vector2i(layout_breakpoint, 700), Vector2i(layout_breakpoint + 1, 700), Vector2i(960, 640), Vector2i(1440, 960)]
	for logical in sizes:
		var physical := Vector2i((Vector2(logical) * density).round())
		root.size = physical
		await settle_layout()
		check(root.size == physical and root.position == original_position and root.mode == original_mode, "resize never resets requested geometry, position or mode")
		check_resize_bounds(game, logical, density)
		check(resize_snapshot(game) == preserved, "resize preserves career, numeric values/drafts/selection, semantics, fonts, preview, motion and nodes without forecasts")
		check(root.gui_get_focus_owner() == edit, "numeric draft keeps focus through every layout_breakpoint crossing")
		check(bool(body.get("vertical")) == (logical.x < layout_breakpoint), "body stacks only below its measured combined minimum")
		var footer: Container = game.consequence.get_parent().get_parent()
		check(bool(footer.get("vertical")) == bool(body.get("vertical")), "footer and body share the responsive orientation")
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
	game._help()
	var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	await settle_layout()
	var modal_focus: Control = dialog.gui_get_focus_owner()
	preserved = resize_snapshot(game)
	root.size = Vector2i((Vector2(960, 1200) * density).round())
	await settle_layout()
	check(dialog.visible and dialog.gui_get_focus_owner() == modal_focus, "resize leaves an open modal and its focus intact")
	check(resize_snapshot(game) == preserved, "resize under a modal preserves state and node identity")
	dialog.get_ok_button().pressed.emit()
	await settle_layout()
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
