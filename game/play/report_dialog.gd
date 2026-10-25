extends AcceptDialog
const Chart = preload("res://play/history_chart.gd")

func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.alt_pressed or event.shift_pressed:
		return
	var focused := gui_get_focus_owner()
	if focused is OptionButton and focused.get_popup().visible:
		return
	if event.keycode not in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]:
		return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not event.is_command_or_control_pressed():
		if focused != get_ok_button() and not focused is TextEdit and not focused is ScrollContainer and not focused is Chart:
			return
	# Dismiss reading surfaces/OK; plain Return activates other report controls.
	set_input_as_handled()
	if not event.echo:
		queue_free()
