extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._advance()
	var saved: PackedByteArray = game.career.encode()
	var comparison: Dictionary = game.career.review_comparison()
	game._review()
	await process_frame
	var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	var graph = dialog.get_child(0)
	check(graph is ScrollContainer, "review is graphical and scrollable")
	check(graph.bars.size() == 15, "all five measures display all three policy paths")
	for i in range(5):
		var metric: Array = graph.METRICS[i]
		for j in range(3):
			var path: Dictionary = [comparison.actual, comparison.held, comparison.staff][j]
			var bar: ProgressBar = graph.bars[i * 3 + j]
			check(is_equal_approx(bar.value, float(path[metric[1]]) * metric[2]), "graph retains exact source values")
			check(bar.max_value == graph.bars[i * 3].max_value, "paths share a scale within each metric")
	check(graph.find_children("*", "TextEdit", true, false).is_empty(), "no methodology wall in the default review")
	var method: Button
	var rules: Button
	for button in dialog.find_children("*", "Button", true, false):
		if button.text == "Method & definitions": method = button
		if button.text == "Challenge rules": rules = button
	check(method != null and rules != null, "method and rules remain keyboard-accessible disclosures")
	method.pressed.emit()
	await process_frame
	await process_frame
	var details: AcceptDialog = game.get_child(game.get_child_count() - 1)
	check(details.get_child(0).text.contains("hindsight") and details.get_child(0).text.contains("full-information"), "model limitations retained in method")
	details.queue_free()
	await process_frame
	check(game.career.encode() == saved, "review and disclosures do not mutate career")
	var tiny = comparison.duplicate(true)
	for key in ["actual", "held", "staff"]:
		tiny[key].credibility = 0.0004
		tiny[key].public_support = 0.04
	var tiny_graph = load("res://play/policy_review.gd").new()
	tiny_graph.build(tiny)
	root.add_child(tiny_graph)
	var tiny_scores := 0
	for label in tiny_graph.find_children("*", "Label", true, false):
		if label.text == "<0.1 /100": tiny_scores += 1
	check(tiny_scores == 6, "positive scores rounded to zero use the correct one-decimal bound")
	tiny_graph.free()
	if not failures: print("PASS: graphical review parity, scales, disclosure and read-only state")
	await game._quit_app(1 if failures else 0)
