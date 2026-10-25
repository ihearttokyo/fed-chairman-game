extends SceneTree

const WrappedTooltip = preload("res://play/wrapped_tooltip.gd")
const Chart = preload("res://play/history_chart.gd")
const LONG_TEXT := "The full-information benchmark uses the true neutral rate, short inflation expectations, inflation and output gap from the current model state. It does not know future shocks or identify an optimal policy. The rate formula does not directly adjust for credit spreads, term premiums or weaker negative-rate transmission."
var failures := 0

class ExistingControl:
	extends Button
	var retained := 42

class LifecycleRoot:
	extends Control
	var ready_count := 0
	func _ready() -> void:
		# Same production-root integration, without starting audio or a career.
		ready_count += 1
		preload("res://play/wrapped_tooltip.gd").install(self)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for frame in range(6):
		await process_frame

func run() -> void:
	root.size = Vector2i(800, 480)
	root.content_scale_size = Vector2i.ZERO
	root.gui_embed_subwindows = true
	var scope := Control.new()
	root.add_child(scope)
	var button := Button.new()
	button.text = "Benchmark"
	button.tooltip_text = LONG_TEXT
	button.accessibility_description = LONG_TEXT
	button.position = Vector2(20, 20)
	button.size = Vector2(140, 40)
	var activations := [0]
	button.pressed.connect(func(): activations[0] += 1)
	scope.add_child(button)
	var spin := SpinBox.new()
	spin.position = Vector2(20, 90)
	spin.size = Vector2(140, 40)
	spin.tooltip_text = LONG_TEXT
	spin.get_line_edit().tooltip_text = LONG_TEXT
	scope.add_child(spin)
	var custom := ExistingControl.new()
	scope.add_child(custom)
	var custom_script: Script = custom.get_script()
	var chart := Chart.new()
	chart.position = Vector2(200, 20)
	chart.history = [{"four_quarter_inflation_pct": 2.5, "expected_long_inflation_pct": 2.0}]
	scope.add_child(chart)
	var connections_before := get_signal_connection_list("node_added").size()
	WrappedTooltip.install(scope)
	WrappedTooltip.install(scope)
	check(get_signal_connection_list("node_added").size() == connections_before + 1, "repeated installation does not duplicate the scene-tree watcher")
	check(button.get_script() == WrappedTooltip and spin.get_line_edit().get_script() == WrappedTooltip, "ordinary native controls and SpinBox's internal LineEdit get wrapped tooltips")
	check(custom.get_script() == custom_script and custom.retained == 42, "installer does not replace existing scripts")
	check(chart.get_script() == Chart, "installer preserves chart behavior")
	button.pressed.emit()
	check(activations[0] == 1 and button.accessibility_description == LONG_TEXT and button.tooltip_text == LONG_TEXT, "installer preserves signals and accessible descriptions")
	var late := Label.new()
	scope.add_child(late)
	late.tooltip_text = LONG_TEXT
	check(late.get_script() == WrappedTooltip, "later-added controls are covered without another integration call")
	check(float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec")) == 0.0, "native tooltip delay remains zero")
	await check_body(button, LONG_TEXT, 800, true)
	await check_body(button, LONG_TEXT, 240, true)
	await check_body(button, "A".repeat(140), 240, true)
	await check_body(button, "First paragraph.\n\nSecond paragraph.", 800, true)
	await check_body(button, "Short", 800, false)
	root.size = Vector2i(800, 480)
	chart._inspect(0)
	var accessible := chart.accessibility_description
	var chart_tip: Control = chart._make_custom_tooltip(chart.tooltip_text)
	check(chart_tip is PanelContainer and chart_tip.get_child(0).text == chart.tooltip_text, "chart uses the shared wrapped native tooltip factory")
	check(chart.hovered == 0 and chart.accessibility_description == accessible and accessible.contains("Left and Right"), "chart retains inspection and keyboard accessibility")
	chart_tip.free()
	await check_native_popup(button, 800)
	await check_native_popup(button, 240)
	await check_native_popup(spin.get_line_edit(), 800)
	await check_native_popup(chart, 800)
	scope.free()
	await settle()
	check(get_signal_connection_list("node_added").size() == connections_before, "freeing the installed scene removes its tree watcher")
	await check_install_lifecycle()
	if failures == 0:
		print("PASS: native zero-delay wrapped tooltips preserve controls, scripts, accessibility and viewport-sensitive bounds")
	quit(1 if failures else 0)

func check_install_lifecycle() -> void:
	var initial := get_signal_connection_list("node_added").size()
	var first := LifecycleRoot.new()
	var second := LifecycleRoot.new()
	root.add_child(first)
	root.add_child(second)
	await settle()
	check(get_signal_connection_list("node_added").size() == initial + 2, "simultaneous independently scripted roots retain distinct watchers")
	for scope in [first, second]:
		var late := Button.new()
		scope.add_child(late)
		check(late.get_script() == WrappedTooltip, "each simultaneous root wraps its own later-created controls")
	root.remove_child(first)
	check(get_signal_connection_list("node_added").size() == initial + 1, "removing one root disconnects only its watcher")
	var detached_child := Button.new()
	first.add_child(detached_child)
	root.add_child(first)
	check(first.ready_count == 1, "ordinary reentry does not rerun ready")
	check(detached_child.get_script() == WrappedTooltip, "reentry wraps controls added while the root was detached")
	var reentered := Button.new()
	first.add_child(reentered)
	check(reentered.get_script() == WrappedTooltip, "a removed and re-added root resumes watching without rerunning ready")
	root.remove_child(first)
	first.request_ready()
	root.add_child(first)
	first._ready()
	check(first.ready_count == 3 and get_signal_connection_list("node_added").size() == initial + 2, "requested ready and direct ready reentry retain exactly one watcher per root")
	var rerun := Button.new()
	first.add_child(rerun)
	check(rerun.get_script() == WrappedTooltip, "ready reentry retains coverage for newly added controls")
	var watcher_ref: WeakRef = weakref(first.get_meta(WrappedTooltip.INSTALL_KEY))
	second.free()
	first.free()
	await settle()
	check(get_signal_connection_list("node_added").size() == initial, "all independent lifecycle watchers clean up after free")
	check(watcher_ref.get_ref() == null, "freeing the scene releases its watcher object as well as its connection")

func check_body(owner: Control, text: String, width: int, multiline: bool) -> void:
	root.size = Vector2i(width, 480)
	await settle()
	var tip: Control = owner._make_custom_tooltip(text)
	root.add_child(tip)
	await settle()
	var body: Label = tip.get_child(0)
	check(tip.size.x <= minf(WrappedTooltip.MAX_WIDTH, width - WrappedTooltip.VIEWPORT_INSET) + 1, "tooltip body fits its logical viewport at width %d" % width)
	check(body.get_line_count() > 1 if multiline else body.get_line_count() == 1, "long text and explicit paragraphs wrap; short text stays compact")
	check(body.text == text and body.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "wrapping retains the complete exact tooltip text")
	check(tip.size.y >= body.size.y + WrappedTooltip.PADDING * 2 and body.get_theme_font_size("font_size") >= 14, "tooltip has legible text and vertical padding")
	tip.free()

func check_native_popup(owner: Control, width: int) -> void:
	var outside := InputEventMouseMotion.new()
	outside.position = Vector2(-10, -10)
	root.push_input(outside)
	root.size = Vector2i(width, 480)
	await settle()
	var motion := InputEventMouseMotion.new()
	# Near the right edge also exercises native popup placement, not just sizing.
	motion.position = owner.get_global_rect().get_center() if width == 800 else Vector2(155, 40)
	root.push_input(motion)
	await settle()
	var windows: Array[Node] = root.find_children("*", "PopupPanel", true, false)
	var visible_popups := 0
	for popup in windows:
		if not popup.visible:
			continue
		visible_popups += 1
		check(popup.size.x <= minf(WrappedTooltip.MAX_WIDTH, width - WrappedTooltip.VIEWPORT_INSET) + 1, "actual native tooltip includes its outer frame within the width budget")
		check(root.get_visible_rect().encloses(Rect2(Vector2(popup.position), Vector2(popup.size))), "actual native tooltip remains inside the logical viewport")
		var bodies := popup.find_children("*", "Label", true, false)
		check(bodies.size() == 1 and bodies[0].text == owner.tooltip_text and bodies[0].autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "actual native hover requests the wrapped body for %s" % owner.get_class())
	check(visible_popups == 1, "zero-delay native hover displays exactly one tooltip for %s" % owner.get_class())
