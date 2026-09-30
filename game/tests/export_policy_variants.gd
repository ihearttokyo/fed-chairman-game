extends SceneTree

const Economy = preload("res://model/economy.gd")
const Exporter = preload("res://tests/export_reference.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--output":
		printerr("usage: --output /absolute/path/outside/repository.json")
		quit(1)
		return
	var output_path := args[1].simplify_path()
	if not Exporter.output_is_outside_repository(output_path, ProjectSettings.globalize_path("res://")) or FileAccess.file_exists(output_path):
		printerr("output must be a new absolute file outside the repository")
		quit(1)
		return
	var model := Economy.new()
	var parameters := model.load_parameters()
	var scenarios := model.load_scenarios()
	if not parameters.ok or not scenarios.ok:
		printerr("model inputs failed validation")
		quit(1)
		return
	var variants := [
		{"name": "rate_zero", "case": "supply_shock", "quarter": 0, "control": "policy_rate_request_pct", "value": 0.0, "cell": "E6"},
		{"name": "asset_purchase", "case": "base", "quarter": 0, "control": "asset_flow_request_pct_initial_gdp", "value": 2.0, "cell": "E10"},
		{"name": "liquidity", "case": "funding_stress", "quarter": 4, "control": "liquidity_request_pct_initial_gdp", "value": 3.0, "cell": "I11"},
		{"name": "guidance", "case": "base", "quarter": 0, "control": "guidance_rate_pct", "value": 4.25, "cell": "E7"},
	]
	for variant in variants:
		var scenario: Dictionary = scenarios.scenarios[variant.case]
		var initial := model.initial_state(parameters.values, scenario.initial)
		if not initial.ok:
			printerr(initial.error)
			quit(1)
			return
		var state: Dictionary = initial.state
		var states: Array = [state.duplicate(true)]
		var shocks := model.seeded_shock_path(1, scenario, 48)
		for quarter in range(48):
			var policy := model.benchmark_policy(state, parameters.values, "feedback")
			if quarter == variant.quarter:
				policy[variant.control] = variant.value
			var transition := model.step(state, policy, shocks[quarter], parameters.values)
			if not transition.ok:
				printerr(transition.error)
				quit(1)
				return
			state = transition.state
			states.append(state.duplicate(true))
		variant.states = states
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	if directory_error != OK:
		printerr("could not create export directory")
		quit(1)
		return
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		printerr("could not open export destination")
		quit(1)
		return
	output.store_string(JSON.stringify(variants, "\t"))
	output.close()
	print("EXPORTED four one-variable policy traces")
	quit(0)
