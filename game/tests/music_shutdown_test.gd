extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var home := OS.get_environment("FED_GAME_TEST_HOME")
	check(home.is_absolute_path() and home.get_file().begins_with("fed-game-home.") and home == OS.get_environment("HOME") and OS.get_user_data_dir().begins_with(home + "/"), "shutdown fixture verifies private user storage before writes")
	if failures:
		quit(1)
		return
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.music_toggle.button_pressed = true
	check(game.music.playing and game.career.encode() == game.clean_career, "shutdown begins with playing music and a clean career")
	if failures:
		quit(1)
		return
	var before: PackedByteArray = game.career.encode()
	var path := "user://policy-lab-audio-v1.cfg"
	var preference: Variant = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	game._request_quit()
	check(paused and not game.can_process() and game.music_toggle.disabled and not is_instance_valid(game.music), "production shutdown pauses gameplay and disposes its native player")
	if failures:
		return # The production shutdown still completes; the wrapper rejects FAIL.
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.command_or_control_autoremap = true
		event.pressed = pressed
		game.get_window().push_input(event)
	await process_frame
	game._request_quit()
	game._quit_app(19)
	check(game.career.encode() == before and game.quit_dialog == null, "keyboard adoption and repeated close cannot change a closing career")
	var after: Variant = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	check(after == preference, "shutdown does not rewrite the selected music preference")
	if failures == 0:
		print("PASS: production shutdown rejects keyboard adoption and reentry; first exit0 and preferences preserved")
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		await process_frame
	printerr("FAIL: production shutdown did not exit before the real-time deadline")
	quit(1)
