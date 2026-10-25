extends SceneTree
const Guide = preload("res://play/help_guide.gd")
class NoForecastMain:
	extends "res://play/main.gd"
	func _preview() -> void:
		pass
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1440, 960)
	var game = NoForecastMain.new()
	root.add_child(game)
	await process_frame
	for scenario in ["policy_career", "stagflation_bank_run"]:
		game._start_career(scenario, 417)
		var before: PackedByteArray = game.career.encode()
		var policy: Dictionary = game._policy()
		var original: String = game._help_text()
		game._help()
		await process_frame
		var dialog = game.get_child(game.get_child_count() - 1)
		var guide = dialog.get_child(0)
		check(guide is Guide and guide.topics.item_count == 6, "six named help topics")
		check(guide.reference_text == original, "complete scenario-specific source retained verbatim")
		check(dialog.gui_get_focus_owner() == guide.body, "help opens on readable native content")
		check(not guide.body.editable and guide.body.wrap_mode == TextEdit.LINE_WRAPPING_BOUNDARY and not guide.body.tab_input_mode, "native help is read-only, wrapped and keyboard escapable")
		check(guide.body.text.begins_with("Play a quarter") and not guide.body.text.contains("Keyboard controls") and not guide.body.text.contains("Mandate v1 is"), "opening viewport starts with play rather than the rulebook")
		check(guide.body.text.length() < original.length() / 3, "opening content is materially shorter than the original wall")
		var flattened: Array = []
		for index in range(guide.pages.size()):
			guide.topics.select(index)
			guide.topics.item_selected.emit(index)
			await process_frame
			for block in guide.pages[index].blocks:
				flattened.append(block)
				check(guide.body.text.contains(block), "actual selected topic exposes complete source paragraph")
			check(guide.body.accessibility_description == guide.body.text, "assistive text matches current topic")
			check(guide.body.scroll_vertical == 0 and guide.body.scroll_horizontal == 0, "topic changes reset reading position")
		var expected: Array = Array(original.split("\n\n", false))
		expected.sort()
		flattened.sort()
		check(flattened == expected, "every original paragraph appears exactly once across topics")
		check(guide.body.text.contains("Recovery v1 is a separate") if scenario == "stagflation_bank_run" else guide.body.text.contains("Mandate v1 is a fictional"), "scenario-appropriate scoring remains accessible")
		for size in [Vector2i(640, 480), Vector2i(320, 480)]:
			root.size = size
			game.size = Vector2(size)
			game._fit_report(dialog)
			await process_frame
			check(dialog.size.x <= root.size.x and dialog.size.y <= root.size.y, "help window fits small parent")
			check(guide.body.size.x <= dialog.size.x and guide.topics.size.x <= dialog.size.x, "topic chooser and readable text fit the report")
		dialog.get_ok_button().pressed.emit()
		await process_frame
		check(game.career.encode() == before and game._policy() == policy, "browsing and resizing help preserves career and staged policy")
		root.size = Vector2i(1440, 960)
		game.size = Vector2(root.size)
	var future := Guide.partition("Future detail\n[b]literal text[/b]")
	check(future[5].blocks == ["Future detail\n[b]literal text[/b]"], "unknown future content remains reachable without interpreting markup")
	game.music.free()
	game.queue_free()
	await process_frame
	var deadline := Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < deadline:
		await process_frame
	print("%s: help guide %d checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
