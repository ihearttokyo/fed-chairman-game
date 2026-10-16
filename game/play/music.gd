extends AudioStreamPlayer

const SETTINGS_PATH := "user://policy-lab-audio-v1.cfg"
var music_enabled := true

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var preference: Variant = config.get_value("audio", "music_enabled", true)
		if typeof(preference) == TYPE_BOOL:
			music_enabled = preference
	_apply_enabled()

func set_enabled(enabled: bool) -> Error:
	music_enabled = enabled
	_apply_enabled()
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		return error
	config.set_value("audio", "music_enabled", enabled)
	var permissions := -1
	if error == OK:
		# Atomic replacement must still respect a read-only existing preference.
		var existing := FileAccess.open(SETTINGS_PATH, FileAccess.READ_WRITE)
		if existing == null:
			return FileAccess.get_open_error()
		permissions = FileAccess.get_unix_permissions(SETTINGS_PATH)
		existing.close()
	var directory := DirAccess.open("user://")
	if directory == null:
		return DirAccess.get_open_error()
	var pending := SETTINGS_PATH + ".pending-%d-%d" % [OS.get_process_id(), get_instance_id()]
	if FileAccess.file_exists(pending) or DirAccess.dir_exists_absolute(pending) or directory.is_link(pending.get_file()):
		return ERR_ALREADY_EXISTS
	var file := FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	error = OK
	if permissions >= 0:
		error = FileAccess.set_unix_permissions(pending, permissions)
		if error == ERR_UNAVAILABLE:
			error = OK
	var payload := config.encode_to_text().to_utf8_buffer()
	if error == OK:
		var stored := file.store_buffer(payload)
		file.flush()
		error = file.get_error()
		if error == OK and not stored:
			error = ERR_FILE_CANT_WRITE
	file.close()
	if error == OK:
		var verified := FileAccess.open(pending, FileAccess.READ)
		if verified == null:
			error = FileAccess.get_open_error()
		else:
			if verified.get_length() != payload.size() or verified.get_buffer(payload.size()) != payload:
				error = ERR_FILE_CANT_WRITE
			verified.close()
	if error == OK:
		error = DirAccess.rename_absolute(pending, SETTINGS_PATH)
	if error != OK:
		var cleanup := DirAccess.remove_absolute(pending)
		if cleanup != OK:
			return cleanup
	return error

func _apply_enabled() -> void:
	if not music_enabled:
		stop()
	elif not playing:
		play()
