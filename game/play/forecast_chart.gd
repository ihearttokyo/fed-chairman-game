extends "res://play/history_chart.gd"
signal page_requested(direction: int)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.alt_pressed and not event.is_command_or_control_pressed() and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		page_requested.emit(-1 if event.keycode == KEY_PAGEUP else 1)
		accept_event()
	else:
		super._gui_input(event)
