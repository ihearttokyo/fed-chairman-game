extends AcceptDialog

func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.alt_pressed or event.shift_pressed:
		return
	if event.keycode not in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]:
		return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not event.is_command_or_control_pressed():
		var focused := gui_get_focus_owner()
		if focused != get_ok_button() and not focused is TextEdit:
			return
	# Dismiss text/OK, but let plain Return activate other report controls.
	set_input_as_handled()
	if not event.echo:
		queue_free()
