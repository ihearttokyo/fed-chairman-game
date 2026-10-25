extends SceneTree
const Career = preload("res://play/career.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var career := Career.new()
	for seed in [0, 1, 417, -2147483647, 2147483647]:
		check(career.start("stagflation_bank_run", seed).ok, "boundary seed starts crisis")
		check(career.state.four_quarter_inflation_pct > 6.9 and career.state.output_gap_pct == -3.0 and career.current_briefing().funding_need_pct_initial_gdp == 2.4, "crisis has immediate conflicting objectives and funding need")
		var first: Dictionary = career.model.seeded_campaign(seed, career.cases.stagflation_bank_run, 32)
		check(first.ok and first.shocks == career.shocks.slice(0, 32), "generation is horizon-prefix deterministic")
		var independent := -1
		var ending := -1
		for episode in career.episodes:
			check(episode.quarter_index > ending, "episodes and conditional recoveries cannot overlap")
			ending = episode.quarter_index + episode.duration_quarters - 1
			if episode.trigger_id.is_empty():
				check(episode.quarter_index >= 1 and episode.quarter_index <= 3 if independent < 0 else episode.quarter_index - independent >= 8 and episode.quarter_index - independent <= 10, "explicit crisis cadence")
				independent = episode.quarter_index
		for q in range(12):
			check(career.advance(career.model.benchmark_policy(career.state, career.params)).ok, "crisis transitions are valid, not forced failure")
		var restored := Career.new()
		check(restored.restore(bytes_to_var(career.encode())).ok and restored.encode() == career.encode(), "exact save/replay of crisis career")
	if failures == 0:
		print("PASS: crisis boundary seeds, immediate tradeoffs, cadence, no overlap and exact replay")
	quit(1 if failures else 0)
