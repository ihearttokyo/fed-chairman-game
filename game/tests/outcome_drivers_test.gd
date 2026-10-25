extends SceneTree

const Drivers = preload("res://play/outcome_drivers.gd")
const Explanation = preload("res://play/transition_explanation.gd")
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for frame in range(6):
		await process_frame

func run() -> void:
	root.size = Vector2i(600, 480)
	root.content_scale_size = Vector2i.ZERO
	var host := VBoxContainer.new()
	host.size = Vector2(600, 480)
	root.add_child(host)
	var drivers := Drivers.new()
	host.add_child(drivers)
	check(not drivers.visible and drivers.details_text.is_empty() and drivers.values.is_empty(), "new component is hidden with no disclosure or sample")
	var result := {"ok": true, "terms": [0.28, -0.28, 0.2, -0.06, 0.0], "change": 0.14, "residual": 0.0, "text": "Q38–Q41 gap change +0.140 pp: exact full explanation. Equation contributions, not isolated policy effects. Inflation uses the prior gap."}
	var frozen := var_to_bytes(result)
	drivers.update_result(result, 38, 41)
	await settle()
	check(drivers.visible and drivers.values == result.terms and drivers.bars.size() == 5, "all five signed contributions retain exact source floats")
	check(drivers.scale_label.text == "±0.280 pp" and drivers.scale_label.accessibility_name.contains("centered at zero"), "shared scale and zero reference are visibly disclosed")
	check(drivers.shared_scale == 0.28 and drivers.details_text == result.text, "shared absolute scale and full disclosure retain source data")
	check(drivers.heading.text.contains("Q38–Q41") and drivers.heading.text.contains("+0.140 pp"), "heading names actual completed interval and total gap change")
	check(drivers.size.y >= 65 and drivers.size.y <= 90, "wide component remains a compact graphical strip")
	for index in range(5):
		var bar = drivers.bars[index]
		check(bar.value == result.terms[index] and bar.shared_scale == drivers.shared_scale, "bar %d uses exact signed data and common scale" % index)
		check(bar.accessibility_name.contains(Explanation.TERM_LABELS[index]) and drivers.value_labels[index].text.ends_with(" pp"), "bar %d retains exact term name and visible pp units" % index)
		check(bar.accessibility_description.contains("not welfare") and drivers.get_global_rect().encloses(bar.get_global_rect()), "bar %d has neutral sign disclosure and stays inside native bounds" % index)
		check(drivers.value_labels[index].get_theme_font_size("font_size") >= 12, "driver values remain readable")
	check(drivers.value_labels[0].text.begins_with("+") and drivers.value_labels[1].text.begins_with("-") and drivers.value_labels[4].text == "+0.000 pp", "positive, negative and explicit zero values are visible")
	check(drivers.bars[0].fill_rect().size.x == drivers.bars[1].fill_rect().size.x and drivers.bars[0].signed_fraction() == 1 and drivers.bars[1].signed_fraction() == -1, "equal opposite terms occupy equal lengths on the same absolute scale")
	check(drivers.bars[0].fill_rect().position.x == drivers.bars[0].size.x / 2 and drivers.bars[1].fill_rect().end.x == drivers.bars[1].size.x / 2, "positive extends right and negative extends left from the zero centre")
	check(drivers.bars[4].fill_rect().size.x == 0, "zero has a centre mark but no misleading fill")
	var ids: Array = []
	for node in [drivers, drivers.flow, drivers.details_button] + drivers.bars + drivers.value_labels:
		ids.append(node.get_instance_id())
	var received := [0]
	drivers.details_requested.connect(func(): received[0] += 1)
	drivers.details_button.pressed.emit()
	check(received[0] == 1 and not drivers.details_button.tooltip_text.contains(result.text), "Details explicitly signals disclosure without putting full equations in a tooltip")
	drivers.details_button.grab_focus()
	await settle()
	check(drivers.details_button.has_focus(), "native Details can be the refresh invoker")
	var focus_exits := [0]
	var visibility_changes := [0]
	drivers.details_button.focus_exited.connect(func(): focus_exits[0] += 1)
	drivers.visibility_changed.connect(func(): visibility_changes[0] += 1)
	var refreshed := result.duplicate(true)
	refreshed.text += " Refreshed completed snapshot."
	drivers.update_result(refreshed, 38, 41)
	check(drivers.details_button.has_focus() and not drivers.details_button.disabled and drivers.details_text == refreshed.text, "valid refresh replaces disclosure in place without losing its focused invoker")
	await settle()
	check(drivers.details_button.has_focus() and focus_exits[0] == 0 and visibility_changes[0] == 0, "valid refresh causes no transient hide, focus exit or later focus loss")
	for width in [320, 600]:
		root.size = Vector2i(width, 480)
		host.size.x = width
		await settle()
		check(drivers.size.x <= width and drivers.get_global_rect().encloses(drivers.details_button.get_global_rect()), "header and Details stay inside width %d" % width)
		for bar in drivers.bars:
			check(drivers.get_global_rect().encloses(bar.get_global_rect()) and root.get_visible_rect().encloses(bar.get_global_rect()), "native flow keeps every bar inside %dpx viewport" % width)
		check(drivers.bars[0].size == drivers.bars[4].size, "all five tracks retain equal dimensions after wrapping")
		check(drivers.bars[0].global_position.y < drivers.bars[4].global_position.y if width == 320 else drivers.bars[0].global_position.y == drivers.bars[4].global_position.y, "flow wraps only when needed")
	var after_ids: Array = []
	for node in [drivers, drivers.flow, drivers.details_button] + drivers.bars + drivers.value_labels:
		after_ids.append(node.get_instance_id())
	check(ids == after_ids and var_to_bytes(result) == frozen, "resizing preserves controls and never mutates result data")
	var zero := result.duplicate(true)
	zero.terms = [0, 0, 0, 0, 0]
	zero.change = 0
	drivers.update_result(zero, 1, 1)
	check(drivers.visible and drivers.shared_scale == 0 and drivers.bars[0].signed_fraction() == 0, "all-zero result uses explicit zero values without divide-by-zero")
	var tiny := result.duplicate(true)
	tiny.terms = [0.000000001, -0.000000001, 0, 0, 0]
	tiny.change = 0
	drivers.update_result(tiny, 1, 1)
	check(drivers.values[0] == tiny.terms[0] and drivers.values[1] == tiny.terms[1] and drivers.shared_scale == 0.01 and absf(drivers.bars[0].signed_fraction() - 0.0000001) < 1e-20, "tiny contributions retain exact data without numerical dust becoming a full-scale bar")
	check(drivers.value_labels[0].text == "up <0.001 pp" and drivers.value_labels[1].text == "down <0.001 pp", "tiny contributions show readable direction and magnitude bounds, not false zero or scientific notation")
	for invalid in [{"ok": false}, {}, {"ok": "true"}, {"ok": true, "terms": [1], "change": 1, "text": "bad"}, {"ok": true, "terms": [1, 2, NAN, 4, 5], "change": 1, "text": "bad"}, {"ok": true, "terms": [1, 2, 3, 4, 5], "change": INF, "text": "bad"}, {"ok": true, "terms": [1, 2, 3, 4, 5], "change": 14, "text": "unreconciled"}]:
		drivers.update_result(result, 38, 41)
		drivers.update_result(invalid, 38, 41)
		check(not drivers.visible and drivers.details_text.is_empty() and drivers.values.is_empty() and drivers.details_button.disabled, "invalid result hides and clears stale disclosure and values")
		check(drivers.bars[0].value == 0 and drivers.shared_scale == 0 and drivers.value_labels[0].text.is_empty(), "invalid result clears stale graphical and numeric samples")
	drivers.update_result(result, 41, 38)
	check(not drivers.visible, "invalid completed interval cannot display a mislabeled result")
	drivers.update_result(result, 38, 41)
	drivers.clear()
	drivers.details_button.pressed.emit()
	check(not drivers.visible and received[0] == 1 and drivers.heading.text.is_empty(), "clear hides the strip and disables stale disclosure signaling")
	check(var_to_bytes(result) == frozen, "updates and clears leave caller's result unchanged")
	host.free()
	if failures == 0:
		print("PASS: outcome drivers %d checks; exact signed values, shared zero scale, responsive native bounds and disclosure" % checks)
	quit(1 if failures else 0)
