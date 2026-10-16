extends SceneTree

const Music = preload("res://play/music.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var home := OS.get_environment("FED_GAME_TEST_HOME")
	check(home.is_absolute_path() and home.get_file().begins_with("fed-game-home.") and home == OS.get_environment("HOME") and OS.get_user_data_dir().begins_with(home + "/"), "atomic preference fixture verifies private storage before access")
	if failures:
		quit(1)
		return
	var original := FileAccess.get_file_as_bytes(Music.SETTINGS_PATH)
	check(original.size() > 65536 and FileAccess.get_sha256(Music.SETTINGS_PATH) == OS.get_environment("FED_MUSIC_FIXTURE_SHA256"), "atomic fault fixture matches the parent's existing large preference")
	if failures:
		quit(1)
		return
	var music := Music.new()
	root.add_child(music)
	check(not music.music_enabled and not music.playing, "fault fixture loads its selected off state without playback")
	var error: Error = music.set_enabled(false)
	check(error != OK and not music.music_enabled and not music.playing, "a native mid-write failure returns an error while applying session off")
	check(FileAccess.get_file_as_bytes(Music.SETTINGS_PATH) == original, "a native mid-write failure preserves every prior preference byte and unrelated key")
	music.free()
	if failures == 0:
		print("PASS: native size-limited preference update preserves the previous file and reports failure")
	quit(1 if failures else 0)
