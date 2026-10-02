extends Control

const Career = preload("res://play/career.gd")
const Chart = preload("res://play/history_chart.gd")
const SAVE_PATH := "user://career-v1.save"
const GOLD := Color("e9b76e")
const MINT := Color("75d4c0")
const MUTED := Color("a4babe")
var career := Career.new()
var stats: Array = []
var charts: Array = []
var quarter_label: Label
var case_title: Label
var case_detail: Label
var briefing: Label
var consequence: Label
var forecast_label: Label
var status_label: Label
var rate: SpinBox
var guidance: SpinBox
var assets: SpinBox
var liquidity: SpinBox
var commitment: OptionButton
var custom_guidance: VBoxContainer
var inflation_response: SpinBox
var activity_response: SpinBox
var scenario: OptionButton
var seed_input: SpinBox
var city: Node3D
var reduced_motion := true
var decision_button: Button
var loading_controls := false

func _ready() -> void:
	_apply_theme()
	var background := ColorRect.new()
	background.color = Color("0c191f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var action_margin := MarginContainer.new()
	for side in ["left", "right"]:
		action_margin.add_theme_constant_override("margin_" + side, 24)
	action_margin.add_theme_constant_override("margin_top", 8)
	action_margin.add_theme_constant_override("margin_bottom", 16)
	layout.add_child(action_margin)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	action_margin.add_child(actions)
	var feedback := _vbox(actions, 5)
	feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	consequence = _label(feedback, "", 14, MINT)
	consequence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	consequence.accessibility_live = AccessibilityServer.LIVE_POLITE
	status_label = _label(feedback, "", 13, MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.accessibility_live = AccessibilityServer.LIVE_POLITE
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)
	_build_header(root)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	root.add_child(cards)
	for heading in ["INFLATION", "UNEMPLOYMENT", "CREDIBILITY", "PUBLIC SUPPORT"]:
		var panel := _panel(cards)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var box := _vbox(panel, 5)
		_label(box, heading, 12, MUTED)
		var value := _label(box, "", 29, GOLD if stats.size() == 0 else Color("e7eee9"))
		var note := _label(box, "", 12, MUTED)
		stats.append([value, note])
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	root.add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	left.custom_minimum_size.x = 630
	body.add_child(left)
	_build_city(left)
	var brief_box := _vbox(_panel(left), 5)
	_label(brief_box, "MEETING DISPATCH  /  INFORMATION AVAILABLE NOW", 12, GOLD)
	briefing = _label(brief_box, "", 14)
	briefing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var chart_row := HBoxContainer.new()
	chart_row.add_theme_constant_override("separation", 20)
	left.add_child(chart_row)
	for n in range(2):
		var chart := Chart.new()
		chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if n == 1:
			chart.heading = "UNEMPLOYMENT & STRUCTURAL REFERENCE"
			chart.keys = ["unemployment_rate_pct", "structural_unemployment_pct"]
			chart.labels = ["Unemployment", "Structural reference"]
		chart_row.add_child(chart)
		charts.append(chart)
	_build_policy(body, actions)
	_label(root, "A research-informed strategy game. Hypothetical economy, disclosed design coefficients. No Federal Reserve affiliation.", 11, MUTED)
	_start_career("supply_shock", 1)
	if "--verify-build" in OS.get_cmdline_user_args():
		get_tree().quit(load("res://play/build_check.gd").new().run(self))

func _apply_theme() -> void:
	var design := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Avenir Next", "DejaVu Sans"])
	design.default_font = font
	design.default_font_size = 14
	design.set_color("font_color", "Label", Color("e7eee9"))
	for node_type in ["Button", "OptionButton", "LineEdit", "SpinBox"]:
		design.set_color("font_color", node_type, Color("e7eee9"))
		design.set_color("font_hover_color", node_type, Color.WHITE)
		for state_name in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("203740") if state_name == "normal" else Color("34505a")
			style.set_corner_radius_all(5)
			style.set_content_margin_all(9)
			style.border_color = GOLD if state_name == "focus" else Color("46626a")
			style.set_border_width_all(2 if state_name == "focus" else 1)
			design.set_stylebox(state_name, node_type, style)
	var dialog_style := StyleBoxFlat.new()
	dialog_style.bg_color = Color("14282f")
	dialog_style.set_content_margin_all(18)
	dialog_style.set_border_width_all(1)
	dialog_style.border_color = Color("527078")
	design.set_stylebox("panel", "AcceptDialog", dialog_style)
	theme = design

func _panel(parent: Node) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("14282f")
	style.border_color = Color("2c454c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _vbox(parent: Node, separation := 10) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box

func _label(parent: Node, text: String, size_px := 14, color := Color("e7eee9")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	return button

func _build_header(parent: Node) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var brand := _vbox(row, 0)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _label(brand, "THE CHAIR", 31)
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "Liberation Serif"])
	title.add_theme_font_override("font", serif)
	_label(brand, "FEDERAL RESERVE  /  POLICY LAB", 11, GOLD)
	quarter_label = _label(row, "", 15, MINT)
	_button(row, "New career", _new_dialog)
	_button(row, "Save", _save)
	_button(row, "Load", _load)
	_button(row, "Data & journal", _journal)
	_button(row, "How to play", _help)
	_button(row, "Credits", _credits)

func _build_city(parent: Node) -> void:
	var panel := _panel(parent)
	var box := _vbox(panel, 3)
	var top := HBoxContainer.new()
	box.add_child(top)
	var title := _label(top, "THE ECONOMY IS YOUR RESPONSIBILITY", 12, MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var motion := CheckButton.new()
	motion.text = "Animate city"
	top.add_child(motion)
	var scene_row := HBoxContainer.new()
	box.add_child(scene_row)
	var context := _vbox(scene_row, 12)
	context.custom_minimum_size.x = 230
	context.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	case_title = _label(context, "", 24, GOLD)
	case_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	case_detail = _label(context, "", 14)
	case_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(0, 215)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_stretch_ratio = 2.0
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_row.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(750, 215)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.transparent_bg = true
	container.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	city = load("res://assets/policy_city.glb").instantiate()
	world.add_child(city)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18
	camera.position = Vector3(17, 19, 23)
	world.add_child(camera)
	camera.look_at(Vector3(0, 0.8, 0))
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -30, 0)
	key.light_color = Color("ffdfab")
	key.light_energy = 1.6
	key.shadow_enabled = true
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 150, 0)
	fill.light_color = Color("83bbcf")
	fill.light_energy = 0.8
	world.add_child(fill)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("14282f")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b8d7db")
	environment.environment.ambient_light_energy = 0.6
	world.add_child(environment)
	var redraw := func():
		viewport.render_target_update_mode = (SubViewport.UPDATE_ONCE if reduced_motion else SubViewport.UPDATE_ALWAYS) if container.is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	viewport.size_changed.connect(redraw)
	# The container resets the native mode after its visibility signal.
	container.visibility_changed.connect(redraw, CONNECT_DEFERRED)
	motion.toggled.connect(func(enabled: bool):
		reduced_motion = not enabled
		redraw.call())
	redraw.call()
	_label(box, "Original Blender miniature · illustrative city, not a regional model", 10, MUTED)

func _spin(parent: Node, title: String, low: float, high: float, step_size: float, tip: String) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(row, title, 14)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var input := SpinBox.new()
	input.min_value = low
	input.max_value = high
	input.step = 0.01 if step_size < 1 else step_size
	input.custom_arrow_step = step_size
	input.custom_minimum_size.x = 105
	input.accessibility_name = title
	input.tooltip_text = tip
	# Numeric setters update the visible text on draw; accessible setters only edit text.
	input.set_meta("numeric_text", input.get_line_edit().text)
	input.set_meta("numeric_text_pending", true)
	input.value_changed.connect(func(_v: float):
		input.set_meta("numeric_text", input.get_line_edit().text)
		input.set_meta("numeric_text_pending", true)
		_preview())
	input.draw.connect(func():
		if input.get_meta("numeric_text_pending"):
			input.set_meta("numeric_text", input.get_line_edit().text)
			input.set_meta("numeric_text_pending", false))
	row.add_child(input)
	return input

func _build_policy(parent: Node, actions: Node) -> void:
	var panel := _panel(parent)
	panel.custom_minimum_size.x = 380
	var box := _vbox(panel, 13)
	_label(box, "FOMC DECISION", 18, GOLD)
	_label(box, "Set a path. Allow time for it to work.", 13, MUTED)
	rate = _spin(box, "Target midpoint (%)", 0, 15, 0.25, "Applied change is limited to 75 basis points per quarter.")
	guidance = _spin(box, "Next-quarter guidance (%)", 0, 15, 0.25, "Markets price this promise according to credibility. Broken promises reduce follow-through.")
	commitment = OptionButton.new()
	commitment.add_item("Data-dependent guidance")
	commitment.add_item("Firm rate pledge")
	commitment.add_item("Custom conditional guidance")
	commitment.tooltip_text = "Data dependence adjusts your promise by %.2f × the change in inflation and %.2f × the change in output gap. A firm pledge does not adjust." % [career.params.policy_inflation_response, career.params.policy_output_gap_response]
	commitment.item_selected.connect(func(_i: int): _guidance_controls())
	box.add_child(commitment)
	custom_guidance = _vbox(box, 6)
	var bound: float = career.params.guidance_sensitivity_limit
	inflation_response = _spin(custom_guidance, "Inflation response", -bound, bound, 0.1, "Adjust the announced rate by this many percentage points for each 1 pp change in four-quarter inflation since the announcement.")
	activity_response = _spin(custom_guidance, "Output-gap response", -bound, bound, 0.1, "Adjust the announced rate by this many percentage points for each 1 pp change in the output gap since the announcement.")
	var units := _label(custom_guidance, "Rate pp per 1 pp change since your announcement. Negative responses reverse the direction; these are game-design choices.", 11, MUTED)
	units.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	assets = _spin(box, "Asset purchases / runoff", -2, 2, 0.25, "Percent of initial annual GDP. Purchases lower the term premium; runoff raises it. Stock capacity applies.")
	liquidity = _spin(box, "New liquidity lending", 0, 5, 0.25, "Percent of initial annual GDP. New loans are limited by funding need, eligibility and collateral. They do not cure insolvency.")
	_label(box, "Asset and loan units: % of initial annual GDP", 11, MUTED)
	_button(box, "Use staff rate rule", _staff_rule)
	forecast_label = _label(box, "", 13, MINT)
	forecast_label.custom_minimum_size.y = 114
	forecast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(actions, "Compare policy paths", _compare)
	decision_button = _button(actions, "Adopt decision  →  Next quarter", _advance)
	decision_button.custom_minimum_size = Vector2(380, 48)
	var explanation := _label(box, "Preview: this decision, then hold the rate for eight quarters. No new future shocks. This is a conditional path, not a confidence interval.", 11, MUTED)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _policy() -> Dictionary:
	return {"policy_rate_request_pct": rate.value, "guidance_rate_pct": guidance.value,
		"guidance_inflation_sensitivity": inflation_response.value if commitment.selected == 2 else (career.params.policy_inflation_response if commitment.selected == 0 else 0.0),
		"guidance_output_gap_sensitivity": activity_response.value if commitment.selected == 2 else (career.params.policy_output_gap_response if commitment.selected == 0 else 0.0),
		"asset_flow_request_pct_initial_gdp": assets.value, "liquidity_request_pct_initial_gdp": liquidity.value}

func _apply_policy_inputs() -> void:
	loading_controls = true
	for input in [rate, guidance, assets, liquidity, inflation_response, activity_response]:
		_apply_input(input)
	loading_controls = false

func _apply_input(input: SpinBox) -> void:
	var edit := input.get_line_edit()
	if edit.has_focus() or edit.text != input.get_meta("numeric_text"):
		input.apply()

func _compare() -> void:
	_apply_policy_inputs()
	_preview()
	var text := _decision_briefing()
	var dialog := AcceptDialog.new()
	dialog.title = "Compare policy paths"
	var box := _vbox(dialog)
	box.custom_minimum_size = Vector2(690, 450)
	_label(box, "Jump to section", 13, MUTED)
	var chooser := OptionButton.new()
	chooser.accessibility_name = "Comparison section"
	chooser.tooltip_text = "Jump within the complete report. All calculations, explanations and limits remain available."
	box.add_child(chooser)
	var body := RichTextLabel.new()
	body.text = text
	body.selection_enabled = true
	body.focus_mode = Control.FOCUS_ALL
	body.accessibility_name = "Policy comparison report"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_color_override("default_color", Color("e7eee9"))
	box.add_child(body)
	for section in [["Meeting", "CURRENT MEETING /"], ["Deliberation", "COMMITTEE DELIBERATION /"], ["Guidance", "GUIDANCE /"], ["Scores", "Q+1 / WHY"], ["Forecasts", "CURRENT TRANSMISSION /"], ["Tools", "ONE-CONTROL CONTRASTS /"], ["Limits", "REFERENCE AND LIMITS"]]:
		var offset := text.find(section[1])
		if offset >= 0:
			chooser.add_item(section[0])
			chooser.set_item_metadata(chooser.item_count - 1, text.substr(0, offset).count("\n"))
	chooser.disabled = chooser.item_count == 0
	chooser.item_selected.connect(func(index): body.scroll_to_paragraph(chooser.get_item_metadata(index)))
	_show_dialog(dialog)

func _guidance_controls() -> void:
	custom_guidance.visible = commitment.selected == 2
	_preview()

func _start_career(case_id: String, seed_number: int) -> void:
	var result: Dictionary = career.start(case_id, seed_number)
	if not result.ok:
		status_label.text = result.error
		return
	_refresh(true)
	consequence.text = "Your first meeting: read the dispatch, compare the policy preview, then adopt a decision. There is no arbitrary unemployment or popularity game-over."
	status_label.text = "New unsaved career · %s · seed %d" % [career.cases[case_id].label, seed_number]

func _refresh(reset_controls := false) -> void:
	var s: Dictionary = career.state
	var complete := career.decisions.size() >= Career.MAX_QUARTERS
	case_title.text = career.cases[career.scenario_id].label
	case_detail.text = "Balance price stability with employment. Expectations, policy lags and public memory carry forward.\n\nAsset holdings: %.1f%% of initial GDP\nOutstanding loans: %.2f%%" % [s.asset_stock_pct_initial_gdp, s.outstanding_liquidity_pct_initial_gdp]
	quarter_label.text = "CAREER COMPLETE · %d MEETINGS" % Career.MAX_QUARTERS if complete else "YEAR %02d / Q%d   ·   MEETING %d" % [int(s.quarter_index / 4) + 1, int(s.quarter_index) % 4 + 1, s.quarter_index + 1]
	stats[0][0].text = "%.2f%%" % s.four_quarter_inflation_pct
	stats[0][1].text = "2.00% target · 4-quarter change"
	stats[1][0].text = "%.2f%%" % s.unemployment_rate_pct
	stats[1][1].text = "%.2f%% structural reference" % s.structural_unemployment_pct
	stats[2][0].text = "%.0f / 100" % (100 * s.credibility)
	stats[2][1].text = "Long expectations %.2f%%" % s.expected_long_inflation_pct
	stats[3][0].text = "%.0f / 100" % s.public_support
	stats[3][1].text = "Hardship memory %.2f" % s.public_hardship_memory
	for chart in charts:
		chart.history = career.history
		chart.queue_redraw()
	var shock: Dictionary = career.current_briefing()
	briefing.text = "Demand impulse %+.2f pp · supply innovation %+.2f pp.\nFunding need %.2f; eligible collateral %.2f (%% initial GDP). Current output gap %+.2f%%. %s" % [shock.get("demand_shock_pct", 0), shock.get("supply_innovation_pct", 0), shock.get("funding_need_pct_initial_gdp", 0), shock.get("eligible_collateral_pct_initial_gdp", 0), s.output_gap_pct, "Lending cannot erase solvency risk." if shock.get("funding_need_pct_initial_gdp", 0) > 0.1 else "Policy works through a lagged real-rate channel."]
	briefing.text += "\n\n" + career.situation_briefing()
	if reset_controls:
		loading_controls = true
		for input in [rate, guidance, assets, liquidity, inflation_response, activity_response]:
			_apply_input(input)
		rate.value = s.policy_rate_pct
		guidance.value = s.policy_rate_pct
		assets.value = 0
		liquidity.value = 0
		inflation_response.value = s.guidance_inflation_sensitivity if s.guidance_active else career.params.policy_inflation_response
		activity_response.value = s.guidance_output_gap_sensitivity if s.guidance_active else career.params.policy_output_gap_response
		commitment.select(0)
		if s.guidance_active:
			if inflation_response.value == 0.0 and activity_response.value == 0.0:
				commitment.select(1)
			elif inflation_response.value != career.params.policy_inflation_response or activity_response.value != career.params.policy_output_gap_response:
				commitment.select(2)
		_guidance_controls()
		loading_controls = false
	decision_button.disabled = complete
	decision_button.text = "Career complete" if complete else "Adopt decision  →  Next quarter"
	_preview()

func _preview() -> void:
	if loading_controls or forecast_label == null or career.state.is_empty():
		return
	var result: Dictionary = career.forecast(_policy())
	if not result.ok:
		forecast_label.text = "Preview unavailable: " + result.error
		return
	var first: Dictionary = result.states[0]
	var last: Dictionary = result.states[-1]
	forecast_label.text = "APPLIED NOW\nRate %.2f%% · assets %+.2f · lending %.2f\n\nCONDITIONAL Q+8\nInflation %.2f%% · unemployment %.2f%%\nOutput gap %+.2f%%" % [first.policy_rate_pct, first.asset_flow_applied_pct_initial_gdp, first.liquidity_applied_pct_initial_gdp, last.four_quarter_inflation_pct, last.unemployment_rate_pct, last.output_gap_pct]

func _decision_briefing() -> String:
	var policy := _policy()
	var selected: Dictionary = career.forecast(policy)
	var held: Dictionary = career.forecast(career.model.benchmark_policy(career.state, career.params, "hold"))
	if not selected.ok or not held.ok:
		return "Comparison unavailable: " + (selected.error if not selected.ok else held.error)
	var first: Dictionary = selected.states[0]
	var reference: Dictionary = held.states[0]
	var text := "CURRENT MEETING / REQUESTED AND APPLIED\nRequested rate %.2f%% · Applied rate %.2f%%\nRequested assets %+.2f · Applied assets %+.2f\nRequested lending %.2f · Applied lending %.2f\n\nRates can change at most %.2f percentage points each quarter. Asset flows are limited by quarterly capacity and holdings. Lending is limited by funding need, eligible collateral after haircuts, existing loans and quarterly capacity. Asset and lending units are %% of initial annual GDP.\n\n" % [policy.policy_rate_request_pct, first.policy_rate_pct, policy.asset_flow_request_pct_initial_gdp, first.asset_flow_applied_pct_initial_gdp, policy.liquidity_request_pct_initial_gdp, first.liquidity_applied_pct_initial_gdp, career.params.policy_rate_change_limit_pct]
	var s: Dictionary = career.state
	var low: float = max(career.params.policy_rate_min_pct, s.policy_rate_pct - career.params.policy_rate_change_limit_pct)
	var high: float = min(career.params.policy_rate_max_pct, s.policy_rate_pct + career.params.policy_rate_change_limit_pct)
	text += "COMMITTEE DELIBERATION / FEASIBLE RATE ALTERNATIVES\nFictional viewpoints, not votes or advice. Test a higher rate for inflation risk, a lower rate for employment risk, and continuity while past decisions work. Every other staged tool and the new quote stay unchanged. Each path uses the disclosed current shock, then no new shocks and its own applied-rate hold.\n\n"
	for alternative in [["Selected", policy.policy_rate_request_pct], ["Tighter rate", clampf(first.policy_rate_pct + 0.25, low, high)], ["Gentler rate", clampf(first.policy_rate_pct - 0.25, low, high)], ["Rate continuity", s.policy_rate_pct]]:
		var other: Dictionary = policy.duplicate()
		other.policy_rate_request_pct = alternative[1]
		var path: Dictionary = selected if alternative[0] == "Selected" else career.forecast(other)
		if not path.ok:
			text += "%s / unavailable: %s\n\n" % [alternative[0], path.error]
			continue
		var outcome: Dictionary = path.states[-1]
		text += "%s / applied %.2f%%\nQ+8 inflation %.3f%%; unemployment %.3f%%; credibility %.1f/100; support %.1f/100\n" % [alternative[0], path.states[0].policy_rate_pct, outcome.four_quarter_inflation_pct, outcome.unemployment_rate_pct, 100 * outcome.credibility, outcome.public_support]
		if alternative[0] in ["Tighter rate", "Gentler rate"] and path.states[0].policy_rate_pct == first.policy_rate_pct:
			text += "At the current rate limit: no extra feasible rate move in this direction.\n"
		text += "\n"
	text += "GUIDANCE / COMMITMENT AND FLEXIBILITY\n"
	if s.guidance_active:
		var prior_promise: float = s.guidance_rate_pct + s.guidance_inflation_sensitivity * (s.four_quarter_inflation_pct - s.guidance_reference_inflation_pct) + s.guidance_output_gap_sensitivity * (s.output_gap_pct - s.guidance_reference_output_gap_pct)
		text += "Previous quote %.2f%%; inflation response %.2f, output-gap response %.2f.\nReference inflation %.3f%%, output gap %+.3f%%.\nAdjusted prior promise %.3f%%\nProjected follow-through %.1f / 100\n" % [s.guidance_rate_pct, s.guidance_inflation_sensitivity, s.guidance_output_gap_sensitivity, s.guidance_reference_inflation_pct, s.guidance_reference_output_gap_pct, prior_promise, 100 * first.guidance_followthrough_score]
		if prior_promise < low or prior_promise > high:
			text += "The adjusted prior promise is outside this meeting's feasible rate range %.2f–%.2f%%. The rate cap prevents full delivery this meeting.\n" % [low, high]
	else:
		text += "No previous announcement to evaluate at this meeting.\n"
	text += "\nNew quote %.2f%%; inflation response %.2f, output-gap response %.2f.\nA new announcement does not erase the previous obligation. Conditions affect next meeting's follow-through, not an immediate credibility bonus. Follow-through is one component of credibility, alongside inflation performance and policy stance.\n\n" % [policy.guidance_rate_pct, policy.guidance_inflation_sensitivity, policy.guidance_output_gap_sensitivity]
	text += "Q+1 / WHY CREDIBILITY AND SUPPORT MOVE\nSELECTED vs HOLD\nCredibility %.1f vs %.1f / 100\nPublic support %.1f vs %.1f / 100\nInflation-miss memory %.3f vs %.3f pp\nModel stance target %.3f%% vs %.3f%%\nApplied-rate distance %.3f vs %.3f pp\nPrior-promise follow-through %.1f vs %.1f / 100\nCurrent hardship %.3f vs %.3f support points\nHardship memory %.3f vs %.3f support points\n\n" % [100 * first.credibility, 100 * reference.credibility, first.public_support, reference.public_support, first.inflation_miss_memory_pct, reference.inflation_miss_memory_pct, first.reaction_function_target_pct, reference.reaction_function_target_pct, abs(first.policy_rate_pct - first.reaction_function_target_pct), abs(reference.policy_rate_pct - reference.reaction_function_target_pct), 100 * first.guidance_followthrough_score, 100 * reference.guidance_followthrough_score, first.current_hardship, reference.current_hardship, first.public_hardship_memory, reference.public_hardship_memory]
	text += "Credibility combines 40%% inflation performance, 40%% stance, 20%% follow-through. Larger remembered inflation misses and applied-rate distances lower the first two components. Inflation memory and the stance target use the information available before this decision. Without a prior announcement, follow-through is neutral. Credibility closes %.0f%% of the distance to its combined score each quarter.\n\nPublic support closes %.0f%% of the distance to its hardship-implied level each quarter. Current inflation/deflation and employment hardship reduce that level; weighted hardship memory prolongs the effect after conditions improve. These scores and the stance rule are game assumptions, not an optimal policy or a measured institutional reputation.\n\n" % [100 * career.params.credibility_adjustment, 100 * career.params.public_support_adjustment]
	text += "CURRENT TRANSMISSION / SELECTED VS HOLD\nLong yield %.3f%% vs %.3f%%\nCredit spread %.3f%% vs %.3f%%\nUncovered funding %.2f vs %.2f\n\n" % [first.long_yield_pct, reference.long_yield_pct, first.credit_spread_pct, reference.credit_spread_pct, first.uncovered_funding_pct_initial_gdp, reference.uncovered_funding_pct_initial_gdp]
	text += "DIFFERENCE FROM HOLD / SELECTED MINUS REFERENCE\n"
	for index in [0, 3, 7]:
		var choice: Dictionary = selected.states[index]
		var baseline: Dictionary = held.states[index]
		text += "Q+%d: Inflation %+.3f pp · unemployment %+.3f pp\nOutput gap %+.3f pp\n\n" % [index + 1, choice.four_quarter_inflation_pct - baseline.four_quarter_inflation_pct, choice.unemployment_rate_pct - baseline.unemployment_rate_pct, choice.output_gap_pct - baseline.output_gap_pct]
	var last: Dictionary = selected.states[-1]
	var baseline: Dictionary = held.states[-1]
	text += "Q+8 / SELECTED VS HOLD\nCredibility %.1f vs %.1f / 100\nPublic support %.1f vs %.1f / 100\n\n" % [100 * last.credibility, 100 * baseline.credibility, last.public_support, baseline.public_support]
	text += "ONE-CONTROL CONTRASTS / SELECTED MINUS ALTERNATIVE\nEach alternative changes only its named input. Guidance keeps conditional coefficients unchanged. Each path uses the same current shock, then no new shocks and its own applied-rate hold. Existing stocks, loans, prior promises and lags remain. These conditional differences are not additive or estimated U.S. effects; zero can mean an unused or constrained tool.\n\n"
	var alternatives := [
		["Rate / alternative request today's rate", "policy_rate_request_pct", s.policy_rate_pct, "%"],
		["Guidance quote / alternative quote applied rate", "guidance_rate_pct", first.policy_rate_pct, "%"],
		["Asset flow / alternative no new flow", "asset_flow_request_pct_initial_gdp", 0.0, "% of initial annual GDP"],
		["Lending / alternative no new loans", "liquidity_request_pct_initial_gdp", 0.0, "% of initial annual GDP"],
	]
	for alternative in alternatives:
		var other: Dictionary = policy.duplicate()
		other[alternative[1]] = alternative[2]
		var path: Dictionary = career.forecast(other)
		text += "%s: %.2f%s\n" % [alternative[0], alternative[2], alternative[3]]
		if not path.ok:
			text += "Contrast unavailable: " + path.error + "\n\n"
			continue
		var reference_first: Dictionary = path.states[0]
		var reference_last: Dictionary = path.states[-1]
		text += "Q+1 long yield %+.3f pp; credit spread %+.3f pp\nQ+8 inflation %+.3f pp; unemployment %+.3f pp; credibility %+.2f points; support %+.2f points\n\n" % [first.long_yield_pct - reference_first.long_yield_pct, first.credit_spread_pct - reference_first.credit_spread_pct, last.four_quarter_inflation_pct - reference_last.four_quarter_inflation_pct, last.unemployment_rate_pct - reference_last.unemployment_rate_pct, 100 * (last.credibility - reference_last.credibility), last.public_support - reference_last.public_support]
	text += "REFERENCE AND LIMITS\nHold today's rate, guide to that rate with data dependence, and request no new asset flows or loans. Both paths use the same current shock and no new future shocks. After this meeting, each holds its own applied rate and makes no new asset flows or loans. Existing holdings, loans and policy lags carry forward.\n\nThese are combined effects of the staged controls, not an optimal-policy recommendation or a confidence interval. Positive differences mean a higher value, not necessarily a better outcome. Policy lags can leave first-quarter inflation unchanged even when later outcomes differ."
	return text

func _staff_rule() -> void:
	var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, "feedback")
	loading_controls = true
	_apply_input(rate)
	_apply_input(guidance)
	rate.value = policy.policy_rate_request_pct
	guidance.value = policy.guidance_rate_pct
	commitment.select(0)
	_guidance_controls()
	loading_controls = false
	_preview()
	status_label.text = "Staff benchmark selected. This simple rule is a comparison, not an optimal policy. Other tools are unchanged."

func _score_change(change: float) -> String:
	if change == 0:
		return "unchanged"
	if abs(change) < 0.05:
		return ("up" if change > 0 else "down") + " <0.05 points"
	return "%+.1f points" % change

func _advance() -> void:
	_apply_policy_inputs()
	var before: Dictionary = career.state.duplicate(true)
	var result: Dictionary = career.advance(_policy())
	if not result.ok:
		status_label.text = result.error + " Last valid quarter retained."
		return
	_refresh(true)
	var s: Dictionary = career.state
	consequence.text = "Q%d OUTCOME  ·  Inflation %+.2f pp; unemployment %+.2f pp.\nApplied rate %.2f%%. Public support %s; credibility %s. Your earlier decisions remain in the transmission pipeline." % [s.quarter_index, s.four_quarter_inflation_pct - before.four_quarter_inflation_pct, s.unemployment_rate_pct - before.unemployment_rate_pct, s.policy_rate_pct, _score_change(s.public_support - before.public_support), _score_change((s.credibility - before.credibility) * 100)]
	if before.guidance_active:
		consequence.text += "\nPrevious promise follow-through: %.1f / 100." % (100 * s.guidance_followthrough_score)
	status_label.text = "Quarter %d completed. Unsaved changes · %s" % [s.quarter_index, career.cases[career.scenario_id].label]
	if int(s.quarter_index) % 12 == 0:
		_review()

func _save() -> void:
	var result: Dictionary = career.save_to(SAVE_PATH)
	status_label.text = "Saved quarter %d. The legacy game's saves are untouched." % career.state.quarter_index if result.ok else result.error

func _load() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Load saved career"
	dialog.add_button("Cancel", true).pressed.connect(dialog.queue_free)
	dialog.dialog_text = "Load the saved career? Unsaved decisions in this session will be replaced."
	dialog.confirmed.connect(func():
		var result: Dictionary = career.load_from(SAVE_PATH)
		if result.ok:
			_refresh(true)
			consequence.text = "Saved career restored with its decisions, economic history and policy lags."
		status_label.text = "Loaded quarter %d." % career.state.quarter_index if result.ok else result.error
	)
	_show_dialog(dialog, Vector2i(740, 180))

func _show_dialog(dialog: Window, desired_size := Vector2i(740, 540)) -> void:
	add_child(dialog)
	dialog.close_requested.connect(dialog.queue_free)
	if dialog is AcceptDialog:
		# AccessKit finishes the button action with a focus request. Keep its window
		# registered until queue_free runs at frame end, instead of hiding immediately.
		dialog.dialog_hide_on_ok = false
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(desired_size)

func _text_dialog(title: String, text: String) -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.title = title
	var body := TextEdit.new()
	body.text = text
	body.custom_minimum_size = Vector2(690, 450)
	body.editable = false
	body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	body.tab_input_mode = false
	body.accessibility_name = title
	body.accessibility_description = text
	body.add_theme_color_override("font_readonly_color", Color("e7eee9"))
	dialog.add_child(body)
	_show_dialog(dialog)
	return dialog

func _new_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.add_button("Cancel", true).pressed.connect(dialog.queue_free)
	dialog.title = "Start a new career · unsaved decisions will be replaced"
	var box := _vbox(dialog)
	_label(box, "Choose a hypothetical economy, not a historical forecast.\nEvery career includes seeded background disturbances, even the baseline.")
	scenario = OptionButton.new()
	for case_id in career.cases:
		scenario.add_item(career.cases[case_id].label)
		scenario.set_item_metadata(scenario.item_count - 1, case_id)
	box.add_child(scenario)
	seed_input = _spin(box, "Scenario seed", 1, 2147483647, 1, "Same scenario and seed reproduce the path within the same engine and model.")
	seed_input.value = 1
	_label(box, "Start with the baseline or supply shock. Weakly anchored inflation is a long recovery. Recurring crises adds unpredictable later episodes.", 13, MUTED)
	dialog.confirmed.connect(func():
		_apply_input(seed_input)
		_start_career(scenario.get_item_metadata(scenario.selected), int(seed_input.value))
	)
	_show_dialog(dialog, Vector2i(740, 240))

func _review() -> void:
	var s: Dictionary = career.state
	var compared: Dictionary = career.review_comparison()
	if not compared.ok:
		_text_dialog("Policy review", compared.error)
		return
	var actual: Dictionary = compared.actual
	var held: Dictionary = compared.held
	var text := "REALIZED PATHS / Q%d–Q%d\nYOUR POLICY vs HOLD REFERENCE\n\nAverage absolute distance from 2%% inflation: %.3f vs %.3f pp\nAverage unemployment above structural reference: %.3f vs %.3f pp\nEnding credibility: %.1f vs %.1f / 100\nEnding public support: %.1f vs %.1f / 100\n\n" % [compared.from_quarter + 1, compared.to_quarter, actual.inflation_miss, held.inflation_miss, actual.employment_shortfall, held.employment_shortfall, 100 * actual.credibility, 100 * held.credibility, actual.public_support, held.public_support]
	text += "Both paths start at your actual Q%d state and use only shocks that already occurred. The reference holds %.2f%%, guides to that rate with data dependence, and makes no new asset flows or loans. Existing stocks, loans, expectations and policy lags carry forward. This is a hindsight comparison, not a forecast or proof of optimal policy.\n\n" % [compared.from_quarter, compared.hold_rate]
	text += "Lower average inflation distance and employment shortfall mean lower costs on those measures. There is no single combined score: reducing one cost can increase the other. Structural unemployment is a model assumption, not a known real-world employment target.\n\nCurrent inflation %.2f%%; unemployment %.2f%%; output gap %+.2f%%.\n\nThere is no dismissal threshold. Credibility and public forgiveness are gradual, and earlier decisions keep working after this review." % [s.four_quarter_inflation_pct, s.unemployment_rate_pct, s.output_gap_pct]
	_text_dialog("Your %d-quarter policy review" % (compared.to_quarter - compared.from_quarter), text)

func _journal() -> void:
	var text := "%s · seed %d\nRates and changes are percentage units. Asset and lending flows use %% of initial annual GDP.\n\n" % [career.cases[career.scenario_id].label, career.seed_value]
	for s in career.history:
		text += "Q%03d | inflation %.2f%% | unemployment %.2f%% | rate %.2f%% | output gap %+.2f%%\nCredibility %.1f | support %.1f | assets %+.2f | loans %.2f\n\n" % [s.quarter_index, s.four_quarter_inflation_pct, s.unemployment_rate_pct, s.policy_rate_pct, s.output_gap_pct, s.credibility * 100, s.public_support, s.asset_flow_applied_pct_initial_gdp, s.liquidity_applied_pct_initial_gdp]
	var dialog := _text_dialog("Economic history and policy journal", text)
	var review := dialog.add_button("Review realized policy")
	review.disabled = career.decisions.is_empty()
	review.tooltip_text = "Compare the latest up to twelve completed quarters with holding policy. Complete a decision first."
	review.pressed.connect(func():
		# A frame signal can precede deletion. Wait for the exclusive journal to
		# actually exit, then deliver after its AccessKit action has finished.
		dialog.tree_exited.connect(_review, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
		dialog.queue_free()
	)

func _help() -> void:
	_text_dialog("How to play", "Your role\nGuide a simplified FOMC policy decision. The target-rate midpoint is an abstraction; a real chair does not unilaterally set the market rate.\n\nEvery career includes seeded background disturbances. The baseline starts at equilibrium with no scheduled scenario events, but its playable path is not shock-free. The same scenario and seed reproduce the path within the same engine and model.\n\n1. Read the dispatch. It describes current conditions, not future shocks.\n2. Set the target rate. Higher real rates restrain demand gradually; inflation reacts with a lag. A supply shock can raise prices while weakening activity.\n3. Choose guidance. A firm promise is easier to understand but costly to break. Data dependence adjusts the prior promise when inflation and the output gap change.\n4. Use asset purchases or runoff to change the term premium. Liquidity lending addresses eligible funding needs, not insolvency.\n5. Inspect applied amounts and the eight-quarter preview, then adopt. The preview assumes no new future shocks and no later rate changes.\n\nCredibility changes how markets price guidance and long-run inflation expectations. Public support remembers both inflation/deflation hardship and unemployment. It recovers gradually, without term resets or a game-over threshold.\n\nSave preserves a career in this game's separate storage. New career and Load ask before replacing unsaved play. Tab navigates controls; charts also have exact values in Data & journal. Animation is off by default.\n\nModel limits\nSeven hypothetical scenarios. Recurring crises precomputes paired demand, supply and funding episodes throughout a 60-year career; future episodes stay unknown. Incidence and behavioral coefficients are design assumptions. Only the 2% objective is source-defined. No empirical forecast, financial advice or Federal Reserve affiliation. See the repository's FED_RESEARCH and model README for primary sources and equations.\n\nCredits\nOriginal procedural Blender city by the project. Godot Engine is MIT-licensed.\n\n" + Engine.get_license_text())

func _process(delta: float) -> void:
	if city != null and not reduced_motion:
		city.rotation.y += delta * 0.025

func _credits() -> void:
	var text := "THE CHAIR / FEDERAL RESERVE POLICY LAB\n\nOriginal game and procedural Blender city © 2026 Jared Bland.\nSystem fonts are supplied by the operating system and are not redistributed.\n\nGODOT ENGINE\n" + Engine.get_license_text()
	for component in Engine.get_copyright_info():
		text += "\n\n" + component.name + "\n"
		for part in component.parts:
			text += "\n".join(part.copyright) + "\nLicense: " + part.license + "\nFiles: " + ", ".join(part.files) + "\n"
	for license_name in Engine.get_license_info():
		text += "\n\n" + license_name + "\n" + Engine.get_license_info()[license_name]
	_text_dialog("Engine and third-party notices", text)
