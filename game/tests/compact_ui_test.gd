extends SceneTree
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
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
	game.free()
	if failures == 0:
		print("PASS: compact task-only cockpit, retained detail and zero-delay tooltip setting")
	quit(1 if failures else 0)
