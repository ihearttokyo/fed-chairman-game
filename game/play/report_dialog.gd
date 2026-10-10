extends AcceptDialog

func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.alt_pressed or event.shift_pressed:
		return
	if event.keycode not in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]:
		return
	# Reports have no destructive acceptance; consume before the focused body.
	set_input_as_handled()
	if not event.echo:
		queue_free()
