extends SceneTree

const Economy = preload("res://model/economy.gd")
const Exporter = preload("res://tests/export_reference.gd")
const SCENARIO := "unanchored_inflation"
const SEED := 1
const WARMUP := 120
const ENDPOINTS := [168, 216, 240]


func _initialize() -> void:
	print("REFERENCE_USER_DATA %s" % OS.get_user_data_dir())
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--output":
		_fail("usage: --output /absolute/new/file/outside/repository.json")
		return
	var output_path := args[1].simplify_path()
	if not Exporter.output_is_outside_repository(output_path, ProjectSettings.globalize_path("res://")) or FileAccess.file_exists(output_path):
		_fail("output must be a new absolute file outside the repository")
		return
	var model := Economy.new()
	var parameters := model.load_parameters()
	var scenarios := model.load_scenarios()
	var portfolio := model.load_portfolio_reference()
	if not parameters.ok or not scenarios.ok or not portfolio.ok:
		_fail("model inputs failed validation")
		return
	var scenario: Dictionary = scenarios.scenarios[SCENARIO]
	var initial := model.initial_state(parameters.values, scenario.initial)
	var campaign := model.seeded_campaign(SEED, scenario, ENDPOINTS[-1])
	if not initial.ok or not campaign.ok:
		_fail(initial.get("error", campaign.get("error", "campaign initialization failed")))
		return
	var state: Dictionary = initial.state
	for q in range(WARMUP):
		var policy := model.benchmark_policy(state, parameters.values, "feedback")
		var result := model.step(state, policy, campaign.shocks[q], parameters.values)
		if not result.ok:
			_fail("warmup Q%d: %s" % [q + 1, result.error])
			return
		state = result.state
	var common := state.duplicate(true)
	var source_hashes := {}
	for path in ["model/economy.gd", "model/parameters.json", "model/scenarios.json", "model/exogenous_shocks.json", "model/portfolio_reference.json", "tests/export_reference.gd", "tests/export_late_checkpoint_reference.gd"]:
		source_hashes[path] = FileAccess.get_sha256("res://" + path)
	var segments: Array = []
	for branch in ["hold", "responsive"]:
		state = common.duplicate(true)
		var start := WARMUP
		for endpoint in ENDPOINTS:
			var checkpoint := state.duplicate(true)
			var checked := model._validate_state(checkpoint, parameters.values)
			if not checked.ok:
				_fail(checked.error)
				return
			var rows: Array = []
			for q in range(start, endpoint):
				var shock: Dictionary = campaign.shocks[q]
				var policy := model.benchmark_policy(state, parameters.values, "hold" if branch == "hold" else "feedback")
				if branch == "responsive":
					policy.liquidity_request_pct_initial_gdp += float(shock.get("funding_need_pct_initial_gdp", 0.0)) + minf(float(shock.get("refinancing_need_pct_initial_gdp", 0.0)), state.outstanding_liquidity_pct_initial_gdp)
				var result := model.step(state, policy, shock, parameters.values)
				if not result.ok:
					_fail("%s Q%d: %s" % [branch, q + 1, result.error])
					return
				state = result.state
				rows.append({"quarter_index": state.quarter_index, "policy": policy.duplicate(true), "shock": shock.duplicate(true), "trace": result.trace.duplicate(true), "state": state.duplicate(true)})
			# Replay the saved segment directly, without rebuilding or rebasing its checkpoint.
			var replay := checkpoint.duplicate(true)
			for row in rows:
				var result := model.step(replay, row.policy, row.shock, parameters.values)
				if not result.ok or result.state != row.state or result.trace != row.trace:
					_fail("segment replay mismatch: %s Q%d" % [branch, row.quarter_index])
					return
				replay = result.state
			segments.append({
				"schema": "fed-economic-reference-v1", "name": "late_%s_%d_%d" % [branch, start, endpoint],
				"parameters": parameters.records, "scenario": scenario, "seed": SEED,
				"policy_kind": branch, "warmup_policy_kind": "feedback", "start_quarter": start, "end_quarter": endpoint,
				"portfolio_reference": portfolio.value,
				"portfolio_reference_json": FileAccess.get_file_as_string("res://model/portfolio_reference.json"),
				"portfolio_reference_sha256": FileAccess.get_sha256("res://model/portfolio_reference.json"),
				"source_sha256": source_hashes, "initial_state": checkpoint,
				"shock_path": campaign.shocks.slice(start, endpoint), "episodes": campaign.episodes, "quarters": rows,
			})
			start = endpoint
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	if directory_error != OK:
		_fail("could not create export directory: %s" % error_string(directory_error))
		return
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		_fail("could not open export destination: %s" % error_string(FileAccess.get_open_error()))
		return
	output.store_string(JSON.stringify(segments, "\t", true, true))
	output.close()
	print("EXPORTED six full-state late checkpoint segments (49/49/25 states per branch); exact native replay")
	quit(0)


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
