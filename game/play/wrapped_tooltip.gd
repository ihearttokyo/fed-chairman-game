extends Control
## Native hover timing/placement, with a readable, bounded multiline body.
## Install once on the scene root; scripted controls retain their own behavior.

const MAX_WIDTH := 340.0
const VIEWPORT_INSET := 24.0
const PADDING := 12.0
const INSTALL_KEY := &"wrapped_tooltips_installed"

class ScopeWatcher:
	extends RefCounted
	var scope_id: int
	var install_branch: Callable

	func _init(id: int, branch: Callable) -> void:
		scope_id = id
		install_branch = branch

	func start() -> void:
		var scope := instance_from_id(scope_id) as Node
		if scope == null or not scope.is_inside_tree():
			return
		var tree := scope.get_tree()
		if not tree.node_added.is_connected(node_added):
			tree.node_added.connect(node_added)
		# Children may have been added while the root was outside the tree.
		install_branch.call(scope)

	func stop() -> void:
		var scope := instance_from_id(scope_id) as Node
		if scope == null:
			return
		var tree := scope.get_tree()
		if tree != null and tree.node_added.is_connected(node_added):
			tree.node_added.disconnect(node_added)

	func node_added(node: Node) -> void:
		var scope := instance_from_id(scope_id) as Node
		if scope != null and scope.is_ancestor_of(node):
			install_branch.call(node)

static func install(scope: Node) -> void:
	if not scope.has_meta(INSTALL_KEY):
		# A distinct receiver matters: Godot conflates differently-bound static
		# callbacks on node_added when multiple scene roots coexist.
		var watcher := ScopeWatcher.new(scope.get_instance_id(), _install_branch)
		scope.set_meta(INSTALL_KEY, watcher)
		scope.tree_entered.connect(watcher.start)
		scope.tree_exiting.connect(watcher.stop)
	_install_branch(scope)
	var watcher: ScopeWatcher = scope.get_meta(INSTALL_KEY)
	watcher.start()

static func _install_branch(node: Node) -> void:
	# Never replace a custom script (notably the chart). Native properties and
	# existing signal connections survive attaching this otherwise-empty script.
	if node is Control and node.get_script() == null:
		node.set_script(load("res://play/wrapped_tooltip.gd"))
	for child in node.get_children(true):
		_install_branch(child)

static func create(owner: Control, for_text: String) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("10242b")
	style.border_color = Color("69868e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(PADDING)
	panel.add_theme_stylebox_override("panel", style)
	var body := Label.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.text = for_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var font := owner.get_theme_default_font()
	var font_size := maxi(14, owner.get_theme_default_font_size())
	body.add_theme_font_override("font", font)
	body.add_theme_font_size_override("font_size", font_size)
	body.add_theme_color_override("font_color", Color("edf4f0"))
	# Godot wraps custom bodies in its native TooltipPanel; budget that frame too.
	var native_frame := owner.get_theme_stylebox("panel", "TooltipPanel").get_minimum_size().x
	var available := maxf(1.0, minf(MAX_WIDTH, owner.get_viewport_rect().size.x - VIEWPORT_INSET) - native_frame - PADDING * 2)
	var natural := font.get_multiline_string_size(for_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	body.custom_minimum_size.x = minf(available, maxf(1.0, ceilf(natural)))
	panel.add_child(body)
	return panel

func _make_custom_tooltip(for_text: String) -> Object:
	return create(self, for_text)
