extends SceneTree

const Economy = preload("res://model/economy.gd")


static func output_is_outside_repository(output_path: String, project_root: String) -> bool:
	var target := output_path.simplify_path()
	var root := project_root.simplify_path().trim_suffix("/").get_base_dir()
	# macOS may resolve case-only aliases to the same protected directory.
	if OS.get_name() == "macOS":
		target = target.to_lower()
		root = root.to_lower()
	return target.is_absolute_path() and target != root and not target.begins_with(root + "/")


func _initialize() -> void:
	var options := _parse_options(OS.get_cmdline_user_args())
	if not options.ok:
		printerr(options.error)
		quit(1)
		return
	var output_path: String = options.values.output.simplify_path()
	var root: String = ProjectSettings.globalize_path("res://").simplify_path()
	if not output_is_outside_repository(output_path, root) or FileAccess.file_exists(output_path):
		printerr("--output must be a new absolute file outside the project/Git tree")
		quit(1)
		return
	var model := Economy.new()
	var parameters: Dictionary = model.load_parameters()
	var scenarios_result: Dictionary = model.load_scenarios()
	var portfolio := model.load_portfolio_reference()
	if not parameters.ok or not scenarios_result.ok or not portfolio.ok:
		printerr(parameters.get("error", scenarios_result.get("error", "model inputs failed validation")))
		quit(1)
		return
	var scenario_id: String = options.values.get("scenario", "base")
	if not scenarios_result.scenarios.has(scenario_id):
		printerr("unknown scenario: %s" % scenario_id)
		quit(1)
		return
	var scenario: Dictionary = scenarios_result.scenarios[scenario_id]
	var initial: Dictionary = model.initial_state(parameters.values, scenario.initial)
	if not initial.ok:
		printerr(initial.error)
		quit(1)
		return
	var seed: int = int(options.values.get("seed", "1"))
	var quarters: int = int(options.values.get("quarters", "48"))
	var policy_kind: String = options.values.get("policy", "feedback")
	var generated := model.seeded_campaign(seed, scenario, quarters)
	if not generated.ok:
		printerr(generated.error)
		quit(1)
		return
	var shocks: Array = generated.shocks
	var state: Dictionary = initial.state
	var rows: Array = []
	for q in range(quarters):
		var policy: Dictionary = model.benchmark_policy(state, parameters.values, policy_kind)
		if policy.has("error"):
			printerr(policy.error)
			quit(1)
			return
		var transition: Dictionary = model.step(state, policy, shocks[q], parameters.values)
		if not transition.ok:
			printerr("quarter %d: %s" % [q + 1, transition.error])
			quit(1)
			return
		state = transition.state
		rows.append({
			"quarter_index": state.quarter_index,
			"policy": policy,
			"shock": shocks[q],
			"trace": transition.trace,
			"state": state.duplicate(true),
		})
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	if directory_error != OK:
		printerr("could not create export directory: %s" % error_string(directory_error))
		quit(1)
		return
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		printerr("could not open export destination: %s" % error_string(FileAccess.get_open_error()))
		quit(1)
		return
	var document := {
		"schema": "fed-economic-reference-v1",
		"parameters": parameters.records,
		"portfolio_reference": portfolio.value,
		"portfolio_reference_json": FileAccess.get_file_as_string("res://model/portfolio_reference.json"),
		"portfolio_reference_sha256": FileAccess.get_sha256("res://model/portfolio_reference.json"),
		"scenario": scenario,
		"seed": seed,
		"policy_kind": policy_kind,
		"initial_state": initial.state,
		"shock_path": shocks,
		"episodes": generated.episodes,
		"quarters": rows,
	}
	output.store_string(JSON.stringify(document, "\t", true, true))
	output.close()
	print("EXPORTED %s scenario=%s seed=%d policy=%s quarters=%d" % [output_path, scenario_id, seed, policy_kind, quarters])
	quit(0)


func _parse_options(args: PackedStringArray) -> Dictionary:
	var values := {}
	var allowed := ["output", "scenario", "quarters", "seed", "policy"]
	var index := 0
	while index < args.size():
		var name: String = args[index].trim_prefix("--")
		if name == args[index] or name not in allowed or index + 1 >= args.size() or values.has(name):
			return {"ok": false, "error": "usage: --output /absolute/path --scenario ID --quarters N --seed N --policy hold|feedback|neutral"}
		values[name] = args[index + 1]
		index += 2
	if not values.has("output"):
		return {"ok": false, "error": "required: --output /absolute/path outside the repository"}
	for key in ["quarters", "seed"]:
		if values.has(key) and str(int(values[key])) != values[key]:
			return {"ok": false, "error": "--%s must be an integer" % key}
	if values.has("quarters") and (int(values.quarters) < 1 or int(values.quarters) > 1000):
		return {"ok": false, "error": "--quarters must be between 1 and 1000"}
	if values.get("policy", "feedback") not in ["hold", "feedback", "neutral"]:
		return {"ok": false, "error": "--policy must be hold, feedback or neutral"}
	return {"ok": true, "values": values}
