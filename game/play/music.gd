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
	return config.save(SETTINGS_PATH)

func _apply_enabled() -> void:
	if not music_enabled:
		stop()
	elif not playing:
		play()
