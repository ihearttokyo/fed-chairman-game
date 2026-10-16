extends SceneTree

const Career = preload("res://play/career.gd")
const OLD_SLOT := "user://career-v1.save"
const PREVIOUS_CAMPAIGN_SLOT := "user://career-late-compound-v1.save"
const PREVIOUS_POLICY_SLOT := "user://policy-career-v1.save"
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var home := OS.get_environment("FED_GAME_TEST_HOME")
	var user_dir := OS.get_user_data_dir()
	var cache_dir := OS.get_cache_dir()
	var project := ProjectSettings.globalize_path("res://")
	var private_home := home.begins_with("/private/tmp/fed-game-home.") or home.begins_with("/tmp/fed-game-home.")
	check(private_home and home == OS.get_environment("HOME") and not home.begins_with(project) and user_dir.begins_with(home + "/") and ProjectSettings.globalize_path(OLD_SLOT).begins_with(home + "/"), "user storage must be inside the verified external private test HOME before any fixture write")
	check(cache_dir.begins_with(home + "/") and DirAccess.dir_exists_absolute(cache_dir), "native cache storage exists inside the private HOME before keyboard fixture writes")
	print("TEST_STORAGE: HOME=%s user_data=%s" % [home, user_dir])
	if failures:
		quit(1)
		return
	if OS.get_cmdline_user_args().has("--storage-only"):
		print("PASS: isolated Godot user storage verified before fixture writes")
		quit()
		return
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	check(game.save_path == game.SAVE_PATH and game.SAVE_PATH == "user://policy-career-v2.save", "default campaign slot is exactly user://policy-career-v2.save before fixture writes")
	if failures:
		await game._quit_app(1)
		return
	var isolated: bool = ProjectSettings.globalize_path(game.save_path).begins_with(home + "/")
	check(isolated, "default campaign save target stays inside the private HOME")
	if not isolated:
		await game._quit_app(1)
		return
	if FileAccess.file_exists(PREVIOUS_POLICY_SLOT) or FileAccess.file_exists(PREVIOUS_POLICY_SLOT + ".pending") or FileAccess.file_exists(PREVIOUS_CAMPAIGN_SLOT) or FileAccess.file_exists(PREVIOUS_CAMPAIGN_SLOT + ".pending") or FileAccess.file_exists(OLD_SLOT) or FileAccess.file_exists(OLD_SLOT + ".pending") or FileAccess.file_exists(game.save_path) or FileAccess.file_exists(game.save_path + ".pending"):
		check(false, "fresh save fixture refuses to overwrite existing final or pending files")
		await game._quit_app(1)
		return
	var sentinel := Career.new()
	check(sentinel.start("base", 19).ok and sentinel.advance(sentinel.model.benchmark_policy(sentinel.state, sentinel.params, "hold")).ok, "old-slot sentinel uses a compatible current Career payload")
	var old_bytes := sentinel.encode()
	check(sentinel.save_to(OLD_SLOT).ok, "isolated old-slot sentinel is written only after the storage guard")
	check(sentinel.save_to(PREVIOUS_CAMPAIGN_SLOT).ok, "previous campaign sentinel is written only inside private storage")
	check(sentinel.save_to(PREVIOUS_POLICY_SLOT).ok, "previous policy sentinel is written only inside private storage")
	var compatible := Career.new()
	check(compatible.load_from(PREVIOUS_POLICY_SLOT).ok and compatible.encode() == old_bytes and compatible.payload().version == 1, "protected policy-career-v1 sentinel loads as a compatible current version-1 payload")
	if failures:
		await game._quit_app(1)
		return
	game._start_career("base", 41)
	var before: PackedByteArray = game.career.encode()
	check(before != old_bytes, "active career differs from the compatible protected sentinels")
	game._load()
	var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	dialog.confirmed.emit()
	dialog.queue_free()
	await process_frame
	check(game.career.encode() == before and game.status_label.text == "No readable saved career found.", "absent new-slot Load cannot fall back to a valid old-slot career")
	check(FileAccess.get_file_as_bytes(OLD_SLOT) == old_bytes and FileAccess.get_file_as_bytes(PREVIOUS_CAMPAIGN_SLOT) == old_bytes and FileAccess.get_file_as_bytes(PREVIOUS_POLICY_SLOT) == old_bytes, "absent new-slot Load preserves every byte of all three old-slot sentinels")
	check(not FileAccess.file_exists(game.save_path) and not FileAccess.file_exists(game.save_path + ".pending"), "absent Load cannot silently migrate an old slot to a final or pending new-slot file")
	game._start_career("base", 41)
	check(game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "feedback")).ok, "new-slot fixture advances through the real Career path")
	before = game.career.encode()
	var saved_state: Dictionary = game.career.state.duplicate(true)
	var saved_history: Array = game.career.history.duplicate(true)
	game._save()
	check(FileAccess.get_file_as_bytes(game.save_path) == before and game.status_label.text.begins_with("Saved quarter 1."), "Save writes the active compatible payload to its default slot")
	check(FileAccess.get_file_as_bytes(OLD_SLOT) == old_bytes and FileAccess.get_file_as_bytes(PREVIOUS_CAMPAIGN_SLOT) == old_bytes and FileAccess.get_file_as_bytes(PREVIOUS_POLICY_SLOT) == old_bytes, "new-slot Save preserves every byte of all three old-slot sentinels")
	check(game.career.advance(game.career.model.benchmark_policy(game.career.state, game.career.params, "hold")).ok and game.career.encode() != before, "roundtrip fixture mutates the active career after Save")
	game._load()
	dialog = game.get_child(game.get_child_count() - 1)
	dialog.confirmed.emit()
	dialog.queue_free()
	await process_frame
	check(game.career.encode() == before and game.career.state == saved_state and game.career.history == saved_history and game.status_label.text == "Loaded quarter 1.", "Load restores the new-slot payload, complete state and history exactly")
	check(FileAccess.get_file_as_bytes(OLD_SLOT) == old_bytes and FileAccess.get_file_as_bytes(PREVIOUS_CAMPAIGN_SLOT) == old_bytes and FileAccess.get_file_as_bytes(PREVIOUS_POLICY_SLOT) == old_bytes, "mutate-and-Load roundtrip preserves every byte of all three old-slot sentinels")
	check(game.career.payload().version == 1 and game.career.scenario_id == "base" and ProjectSettings.get_setting("application/config/custom_user_dir_name") == "FedChairmanPolicyLab", "slot isolation keeps payload version, scenario and user-directory IDs stable")
	check(FileAccess.get_file_as_bytes(PREVIOUS_CAMPAIGN_SLOT) == old_bytes, "all Save/Load actions preserve previous campaign sentinel bytes")
	if failures == 0:
		print("PASS: distinct campaign slot, no legacy fallback/migration and protected old-slot Save/Load roundtrip")
	await game._quit_app(1 if failures else 0)
