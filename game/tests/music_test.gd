extends SceneTree

const Music = preload("res://play/music.gd")
const MALFORMED_LOG := "user://music-malformed-probe.log"
const MALFORMED_ENGINE_LOG := "user://music-malformed-engine.log"
const MALFORMED_ERROR := "ERROR: ConfigFile parse error at user://policy-lab-audio-v1.cfg:0: Unexpected EOF while parsing simple tag."
const MALFORMED_SUCCESS := "PASS: isolated malformed music preferences preserve bytes and refuse overwrite"
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func _drain_audio() -> void:
	var deadline := Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < deadline:
		await process_frame

func _music() -> AudioStreamPlayer:
	var song := AudioStreamWAV.new()
	song.format = AudioStreamWAV.FORMAT_8_BITS
	song.mix_rate = 8000
	song.data = PackedByteArray()
	var samples := PackedByteArray()
	samples.resize(8000)
	samples.fill(128)
	song.data = samples
	song.loop_mode = AudioStreamWAV.LOOP_FORWARD
	song.loop_end = samples.size()
	var music := Music.new()
	music.stream = song
	root.add_child(music)
	return music

func _fixture(value: Variant) -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "music_enabled", value)
	config.set_value("audio", "unrelated_volume", 0.375)
	config.set_value("other", "sentinel", "retain this setting")
	check(config.save(Music.SETTINGS_PATH) == OK, "write isolated preference fixture")

func _malformed_config_probe() -> void:
	var corrupt := FileAccess.open(Music.SETTINGS_PATH, FileAccess.WRITE)
	check(corrupt != null, "open isolated malformed preference fixture")
	if corrupt == null:
		quit(1)
		return
	corrupt.store_string("[audio\nmusic_enabled=false\n")
	corrupt.close()
	var original := FileAccess.get_file_as_bytes(Music.SETTINGS_PATH)
	print("EXPECTED_CONFIG_PARSE_DIAGNOSTICS_BEGIN")
	var music = _music()
	check(music.music_enabled and music.playing, "malformed preferences default on without rewriting")
	check(FileAccess.get_file_as_bytes(Music.SETTINGS_PATH) == original, "malformed startup preserves every existing byte")
	check(music.set_enabled(false) != OK and not music.playing, "malformed preferences refuse persistence but apply playback off")
	print("EXPECTED_CONFIG_PARSE_DIAGNOSTICS_END")
	check(FileAccess.get_file_as_bytes(Music.SETTINGS_PATH) == original, "a toggle cannot truncate malformed preferences")
	music.free()

	await _drain_audio()
	if failures == 0:
		print(MALFORMED_SUCCESS)
	quit(1 if failures else 0)

func _check_malformed_probe() -> void:
	check(not FileAccess.file_exists(MALFORMED_LOG) and not DirAccess.dir_exists_absolute(MALFORMED_LOG) and not FileAccess.file_exists(MALFORMED_ENGINE_LOG) and not DirAccess.dir_exists_absolute(MALFORMED_ENGINE_LOG), "malformed probe refuses existing raw or engine log targets")
	if failures:
		return
	var output := []
	var child_exit := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--max-fps", "60", "--quit-after", "600", "--log-file", ProjectSettings.globalize_path(MALFORMED_ENGINE_LOG), "--script", "res://tests/music_test.gd", "--", "--malformed-config-only"], output, true)
	var child_output := "".join(output)
	var log := FileAccess.open(MALFORMED_LOG, FileAccess.WRITE)
	check(log != null, "retain full unmodified malformed-probe stdout and stderr")
	if log == null:
		return
	log.store_string(child_output)
	log.close()
	check(FileAccess.get_file_as_string(MALFORMED_LOG) == child_output, "retained malformed-probe log matches captured output exactly")
	var lines := child_output.split("\n")
	var valid := child_exit == 0 and lines.has(MALFORMED_SUCCESS)
	var parse_errors := 0
	for line in lines:
		if line == MALFORMED_ERROR:
			parse_errors += 1
		elif line.contains("ERROR:") or line.contains("FAIL:") or line.contains("WARNING:") or line.to_lower().contains("leak"):
			valid = false
	valid = valid and parse_errors == 2
	if not valid:
		printerr(child_output)
	check(valid, "native malformed probe exits successfully with exactly two known parse errors and no other diagnostics")

func _retained_wav_probe() -> void:
	var song := ResourceLoader.load("res://assets/audio/jrb-1.wav") as AudioStreamWAV
	check(song != null, "retained soundtrack loads through the native WAV resource importer")
	if song == null:
		quit(1)
		return
	var length := song.get_length()
	var frames := roundi(length * song.mix_rate)
	check(song.format == AudioStreamWAV.FORMAT_16_BITS and song.stereo and song.mix_rate == 48000 and frames == 9197448, "retained soundtrack preserves the complete official PCM16 stereo 48 kHz source")
	if failures:
		quit(1)
		return
	song.loop_mode = AudioStreamWAV.LOOP_FORWARD
	song.loop_begin = 0
	song.loop_end = frames
	var music := Music.new()
	music.stream = song
	root.add_child(music)
	check(music.music_enabled and music.playing and music.get_stream_playback() != null, "retained WAV defaults on with native inherited playback")
	check(song.loop_mode == AudioStreamWAV.LOOP_FORWARD and song.loop_begin == 0 and song.loop_end == frames, "retained WAV loops over native sample-frame bounds")
	await create_timer(0.05).timeout
	music.seek(length - 0.5)
	var near_end := -1.0
	var wrapped := -1.0
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 3000 and music.playing:
		var position := music.get_playback_position()
		if position >= length - 0.75:
			near_end = position
		elif near_end >= 0.0 and position >= 0.0 and position < 1.0:
			wrapped = position
			break
		await create_timer(0.01).timeout
	check(near_end >= length - 0.75, "retained WAV seek reaches the end of the actual soundtrack")
	check(wrapped >= 0.0 and music.playing, "retained WAV playback wraps and remains playing within the monotonic deadline")
	print("MUSIC_WAV_LOOP: length_seconds=%.6f sample_frames=%d near_end=%.6f wrapped=%.6f elapsed_ms=%d" % [length, frames, near_end, wrapped, Time.get_ticks_msec() - started])
	check(music.set_enabled(false) == OK and not music.music_enabled and not music.playing, "retained WAV stops immediately and reports persisted off")
	var saved := ConfigFile.new()
	check(saved.load(Music.SETTINGS_PATH) == OK and saved.get_value("audio", "music_enabled", true) == false, "retained WAV off is stored in the dedicated preference")
	music.free()
	await _drain_audio()
	if failures == 0:
		print("PASS: retained JRB-1 WAV native playback, near-end seek, wrap and persisted off")
	quit(1 if failures else 0)

func run() -> void:
	var home := OS.get_environment("FED_GAME_TEST_HOME")
	var project := ProjectSettings.globalize_path("res://")
	var private_home := home.get_file().begins_with("fed-music-home.") or home.get_file().begins_with("fed-game-home.")
	check(private_home and home.is_absolute_path() and home == OS.get_environment("HOME") and not home.begins_with(project) and OS.get_user_data_dir().begins_with(home + "/") and ProjectSettings.globalize_path(Music.SETTINGS_PATH).begins_with(home + "/"), "verify private external HOME and user:// before any fixture write")
	check(OS.get_cache_dir().begins_with(home + "/") and DirAccess.dir_exists_absolute(OS.get_cache_dir()) and OS.get_environment("TMPDIR").begins_with(home + "/"), "cache and temporary storage stay inside the private HOME")
	print("TEST_STORAGE: HOME=%s user_data=%s settings=%s" % [home, OS.get_user_data_dir(), ProjectSettings.globalize_path(Music.SETTINGS_PATH)])
	if failures:
		quit(1)
		return
	if OS.get_cmdline_user_args().has("--storage-only"):
		print("PASS: isolated music user storage verified before fixture writes")
		quit()
		return
	if OS.get_cmdline_user_args().has("--malformed-config-only"):
		await _malformed_config_probe()
		return
	if OS.get_cmdline_user_args().has("--relaunch-off"):
		var before := FileAccess.get_file_as_bytes(Music.SETTINGS_PATH)
		var restored = _music()
		check(not restored.music_enabled and not restored.playing, "stored off survives a fresh Godot process without starting playback")
		check(FileAccess.get_file_as_bytes(Music.SETTINGS_PATH) == before, "process relaunch preserves preference bytes")
		restored.free()
		await process_frame
		if failures == 0:
			print("PASS: persisted music off survives process relaunch")
		quit(1 if failures else 0)
		return
	check(not FileAccess.file_exists(Music.SETTINGS_PATH) and not DirAccess.dir_exists_absolute(Music.SETTINGS_PATH), "fresh music test refuses an existing preference target")
	if failures:
		quit(1)
		return
	if OS.get_cmdline_user_args().has("--retained-wav-only"):
		await _retained_wav_probe()
		return
	# Reproduce a first scene delta inflated by synchronous model startup.
	OS.delay_msec(250)
	var cleanup_started := Time.get_ticks_msec()
	await _drain_audio()
	check(Time.get_ticks_msec() - cleanup_started >= 100, "native audio cleanup waits for real elapsed time after synchronous startup")
	if failures:
		quit(1)
		return
	var music = _music()
	check(music.music_enabled and music.playing, "missing preference defaults on and starts the supplied stream")
	check(music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and music.stream.loop_begin == 0 and music.stream.loop_end == music.stream.data.size(), "synthetic stream has native whole-resource looping configured")
	check(not FileAccess.file_exists(Music.SETTINGS_PATH), "default startup does not create preferences")
	music.free()

	_fixture(false)
	var original := FileAccess.get_file_as_bytes(Music.SETTINGS_PATH)
	music = _music()
	check(not music.music_enabled and not music.playing, "stored Boolean false never autostarts")
	check(FileAccess.get_file_as_bytes(Music.SETTINGS_PATH) == original, "loading off preserves all existing preference bytes")
	var other := AudioStreamPlayer.new()
	other.stream = music.stream
	root.add_child(other)
	other.play()
	var master := AudioServer.get_bus_index("Master")
	var muted := AudioServer.is_bus_mute(master)
	var volume := AudioServer.get_bus_volume_db(master)
	check(music.set_enabled(true) == OK and music.music_enabled and music.playing, "enabling starts music and reports a successful save")
	var playback: AudioStreamPlayback = music.get_stream_playback()
	check(playback != null, "enabled music owns a native playback")
	check(music.set_enabled(true) == OK and music.get_stream_playback() == playback, "repeated on preserves the current native playback instead of restarting")
	var saved := ConfigFile.new()
	check(saved.load(Music.SETTINGS_PATH) == OK and saved.get_value("audio", "music_enabled") == true, "successful enable persists Boolean true")
	check(saved.get_value("audio", "unrelated_volume") == 0.375 and saved.get_value("other", "sentinel") == "retain this setting", "saving preserves unrelated keys and sections")
	check(music.set_enabled(false) == OK and not music.music_enabled and not music.playing, "disabling immediately stops this player and saves off")
	check(other.playing and AudioServer.is_bus_mute(master) == muted and AudioServer.get_bus_volume_db(master) == volume, "music toggles preserve other players and the Master bus")
	var restored = _music()
	check(not restored.music_enabled and not restored.playing, "persisted off survives controller recreation")
	restored.free()
	other.free()
	music.free()

	for value in ["false", "true", 0, 1, 1.0, [], {"enabled": false}, null, true]:
		_fixture(value)
		original = FileAccess.get_file_as_bytes(Music.SETTINGS_PATH)
		music = _music()
		check(music.music_enabled and music.playing, "only a Boolean false disables startup; value type %s" % typeof(value))
		check(FileAccess.get_file_as_bytes(Music.SETTINGS_PATH) == original, "startup never normalizes or rewrites loaded values")
		music.free()

	_fixture(true)
	original = FileAccess.get_file_as_bytes(Music.SETTINGS_PATH)
	music = _music()
	var permissions := FileAccess.get_unix_permissions(Music.SETTINGS_PATH)
	check(FileAccess.set_unix_permissions(Music.SETTINGS_PATH, FileAccess.UNIX_READ_OWNER) == OK, "deny writes to the isolated preference file for a real save failure")
	var save_error: Error = music.set_enabled(false)
	check(FileAccess.set_unix_permissions(Music.SETTINGS_PATH, permissions) == OK, "restore fixture permissions after the denied write")
	check(save_error != OK and not music.music_enabled and not music.playing, "failed save returns an error while immediately applying playback off")
	check(FileAccess.get_file_as_bytes(Music.SETTINGS_PATH) == original, "failed save cannot claim persisted off or alter the prior preference")
	var private_permissions := FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER
	check(FileAccess.set_unix_permissions(Music.SETTINGS_PATH, private_permissions) == OK, "restrict the existing preference before testing atomic replacement")
	check(music.set_enabled(false) == OK and not music.music_enabled and not music.playing, "a failed preference write can retry after permissions are restored")
	var retried := ConfigFile.new()
	check(retried.load(Music.SETTINGS_PATH) == OK and retried.get_value("audio", "music_enabled") == false and retried.get_value("other", "sentinel") == "retain this setting", "successful atomic replacement retains off and unrelated configuration")
	check(FileAccess.get_unix_permissions(Music.SETTINGS_PATH) == private_permissions, "atomic replacement preserves the existing Unix permission bits")
	var directory := DirAccess.open("user://")
	var pending := Music.SETTINGS_PATH + ".pending-%d-%d" % [OS.get_process_id(), music.get_instance_id()]
	for kind in ["file", "directory", "link"]:
		var available := not FileAccess.file_exists(pending) and not DirAccess.dir_exists_absolute(pending) and not directory.is_link(pending.get_file())
		check(available, "atomic collision fixture refuses an existing pending target")
		if not available:
			break
		var sentinel := "unowned pending content".to_utf8_buffer()
		var missing_target := ProjectSettings.globalize_path(pending + ".absent")
		if kind == "file":
			var collision := FileAccess.open(pending, FileAccess.WRITE)
			check(collision != null, "create an isolated unknown pending-file fixture")
			if collision == null:
				break
			collision.store_buffer(sentinel)
			collision.close()
		elif kind == "directory":
			check(DirAccess.make_dir_absolute(pending) == OK, "create an isolated unknown pending-directory fixture")
		else:
			check(directory.create_link(missing_target, ProjectSettings.globalize_path(pending)) == OK, "create an isolated dangling pending-link fixture")
		if failures:
			break
		original = FileAccess.get_file_as_bytes(Music.SETTINGS_PATH)
		check(music.set_enabled(true) != OK and music.music_enabled and music.playing, "a pending collision refuses persistence while applying session on: " + kind)
		check(FileAccess.get_file_as_bytes(Music.SETTINGS_PATH) == original, "a pending collision preserves every prior preference byte: " + kind)
		if kind == "file":
			check(FileAccess.get_file_as_bytes(pending) == sentinel, "an unknown pending file remains byte-identical")
		elif kind == "directory":
			check(DirAccess.dir_exists_absolute(pending), "an unknown pending directory remains in place")
		else:
			check(directory.is_link(pending.get_file()) and directory.read_link(pending.get_file()) == missing_target, "an unknown dangling pending link remains unchanged")
		check(DirAccess.remove_absolute(pending) == OK, "remove only the test-owned collision fixture")
		check(music.set_enabled(false) == OK and not music.music_enabled and not music.playing, "a preference transaction retries after its collision is removed")
		check(not FileAccess.file_exists(pending) and not DirAccess.dir_exists_absolute(pending) and not directory.is_link(pending.get_file()), "a successful preference replacement leaves no pending transient")
	check(FileAccess.set_unix_permissions(Music.SETTINGS_PATH, permissions) == OK, "restore the original preference permissions after atomic boundary checks")
	music.free()

	playback = null
	# Native audio releases stopped playbacks on its next mix, not the next scene frame.
	await _drain_audio()
	_check_malformed_probe()

	_fixture(false)
	if failures == 0:
		print("PASS: native music startup, Boolean boundaries, idempotent toggles, isolated playback, persistence and real save failure")
	quit(1 if failures else 0)
