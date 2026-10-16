extends SceneTree

const Career = preload("res://play/career.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var career := Career.new()
	check(career.cases.has("policy_career"), "fresh default has a distinct varied policy career")
	if not career.cases.has("policy_career"):
		quit(1)
		return
	check(career.cases.policy_career.initial == career.cases.unanchored_inflation.initial and career.cases.policy_career.events.is_empty(), "new case keeps weak anchoring, without copying late legacy pulses")
	var original := var_to_bytes(career.cases)
	for seed_number in [0, 1, 417, -2147483647, 2147483647]:
		check(career.start("policy_career", seed_number).ok, "new career starts every boundary fixture")
		var long_path: Dictionary = career.model.seeded_campaign(seed_number, career.cases.policy_career, 1000)
		var short_path: Dictionary = career.model.seeded_campaign(seed_number, career.cases.policy_career, 32)
		check(long_path.ok and short_path.ok and short_path.shocks == long_path.shocks.slice(0,32), "curated pulses preserve native horizon prefix")
		var prior_onset := -1
		var prior_end := -1
		var independent_opening := 0
		for episode in long_path.episodes:
			check(episode.quarter_index > prior_end, "conditional episodes never overlap the next event")
			prior_end = episode.quarter_index + episode.duration_quarters - 1
			if episode.trigger_id.is_empty():
				check(episode.quarter_index >= 4 and episode.quarter_index <= 8 if prior_onset < 0 else episode.quarter_index-prior_onset >= 8 and episode.quarter_index-prior_onset <= 14, "first event at meeting5..9; independent spacing8..14")
				prior_onset = episode.quarter_index
				independent_opening += int(episode.quarter_index < 32)
		check(independent_opening >= 2, "opening32 meetings include at least two independent dilemmas")
		var quoted: Dictionary = career.model.benchmark_policy(career.state, career.params)
		var preview := career.forecast(quoted)
		var briefing := career.situation_briefing()
		career.shocks[200].supply_innovation_pct += 1.0
		check(career.forecast(quoted) == preview and career.situation_briefing() == briefing, "future random events never leak through preview or briefing")
		check(career.start("policy_career", seed_number).ok, "fixture reset is deterministic without touching saves")
		check(career.mandate_assessment().eligible, "new canonical challenge receives unchanged disclosed Mandate criteria")
		for q in range(20):
			check(career.advance(career.model.benchmark_policy(career.state,career.params)).ok, "new case native early transitions remain valid")
		var replay := Career.new()
		check(replay.restore(bytes_to_var(career.encode())).ok and var_to_bytes(replay.history) == var_to_bytes(career.history), "new case exact native save/history replay")
	check(var_to_bytes(career.cases) == original, "generation preserves all source scenarios")
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	check(game.career.scenario_id == "policy_career", "fresh startup selects varied default")
	check(game.SAVE_PATH != "user://policy-career-v1.save" and game.SAVE_PATH != "user://career-late-compound-v1.save" and game.SAVE_PATH != "user://career-v1.save", "new model cannot overwrite any of the three prior save slots")
	var unchanged: PackedByteArray = game.career.encode()
	game._new_dialog()
	check(game.scenario.get_item_metadata(game.scenario.selected) == "policy_career" and game.career.encode() == unchanged, "New defaults to variety without replacing unsaved play")
	if failures == 0:
		print("PASS: varied default, boundary seeds, cadence, episode isolation, exact replay and new save slot")
	await game._quit_app(1 if failures else 0)
