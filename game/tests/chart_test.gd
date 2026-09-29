extends SceneTree
const Chart = preload("res://play/history_chart.gd")
func _initialize() -> void:
	var ok := Chart.tick_quarters(1) == [0] and Chart.tick_quarters(2) == [0, 1] and Chart.tick_quarters(49) == [0, 24, 48]
	if ok:
		print("PASS: unique quarter ticks across short and multi-term careers")
	else:
		printerr("FAIL: chart ticks must not repeat at Q0/Q1 and must retain full career extent")
	quit(0 if ok else 1)
