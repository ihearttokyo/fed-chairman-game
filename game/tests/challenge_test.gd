extends SceneTree

const Career = preload("res://play/career.gd")
const SEEDS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
	101, 137, 211, 307, 401, 509, 613, 719, 823, 929, 1031, 1151, 1277, 1429, 1559, 1723]
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func recovered_state(s: Dictionary) -> bool:
	return abs(s.four_quarter_inflation_pct - 2.0) <= 1.0 and abs(s.output_gap_pct) <= 1.0 \
		and s.unemployment_rate_pct <= s.structural_unemployment_pct + 1.5

func run() -> void:
	var boundary := {"four_quarter_inflation_pct": 3.0, "output_gap_pct": -1.0,
		"unemployment_rate_pct": 6.0, "structural_unemployment_pct": 4.5}
	check(recovered_state(boundary), "established recovery bands include their boundaries")
	boundary.unemployment_rate_pct += 0.000001
	check(not recovered_state(boundary), "balanced prices and output cannot hide excess unemployment")
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	check(game.career.scenario_id == "policy_career", "startup uses the varied inflation-credibility career, not a quiet lab")
	var preserved: PackedByteArray = game.career.encode()
	game._new_dialog()
	check(game.scenario.get_item_metadata(game.scenario.selected) == "policy_career", "New defaults to the challenge without replacing active play")
	var offered: Array = []
	for index in range(game.scenario.item_count):
		offered.append(game.scenario.get_item_metadata(index))
	var expected: Array = game.career.cases.keys()
	expected.append(game.WORKOUT_CASE)
	offered.sort()
	expected.sort()
	check(offered == expected and game.career.cases.has("base"), "all original scenarios and exactly one optional workout remain available")
	check(game.career.encode() == preserved, "opening the chooser preserves unsaved play")
	var dialog: AcceptDialog = game.get_child(game.get_child_count() - 1)
	dialog.get_ok_button().pressed.emit()
	check(game.career.scenario_id == "policy_career" and game.career.seed_value == 1, "untouched New commits the actual seed1 challenge")
	await process_frame
	game.free()

	var costs := {"hold": [], "feedback": []}
	var recovered := {"hold": 0, "feedback": 0}
	for seed_number in SEEDS:
		var paths := [Career.new(), Career.new()]
		for career in paths:
			check(career.start("unanchored_inflation", seed_number).ok, "legacy weak-anchor case starts seed%d" % seed_number)
		check(paths[0].shocks == paths[1].shocks, "paired policies face identical seeded shocks")
		for index in range(paths.size()):
			var career = paths[index]
			var kind: String = "hold" if index == 0 else "feedback"
			var cost := 0.0
			for quarter in range(96):
				var result: Dictionary = career.advance(career.model.benchmark_policy(career.state, career.params, kind))
				if not result.ok:
					check(false, "%s seed%d Q%d: %s" % [kind, seed_number, quarter + 1, result.error])
					break
				cost += abs(career.state.four_quarter_inflation_pct - 2.0) + maxf(0.0, career.state.unemployment_rate_pct - career.state.structural_unemployment_pct)
			check(career.state.quarter_index == 96 and is_finite(cost), "both strategies reach96 without resets or numerical failure")
			var inside := recovered_state(career.state)
			recovered[kind] += int(inside)
			costs[kind].append(cost)
			print("CHALLENGE seed%d %s cumulative_miss=%.6f recovered=%s inflation=%.6f gap=%.6f" % [seed_number, kind, cost, inside, career.state.four_quarter_inflation_pct, career.state.output_gap_pct])
			if seed_number == 1:
				check(inside if kind == "feedback" else not inside, "seed1 is recoverable with active policy, not passive advance")
				var replay := Career.new()
				check(replay.restore(bytes_to_var(career.encode())).ok and replay.history == career.history, "both seed1 paths replay losslessly")
				var before: PackedByteArray = career.encode()
				var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, kind)
				var preview: Dictionary = career.forecast(policy)
				career.shocks[100].supply_innovation_pct = 9.0
				check(career.forecast(policy) == preview and career.state == replay.state, "challenge forecast cannot inspect unknown future inputs or mutate the economy")
				check(career.restore(bytes_to_var(before)).ok, "forecast probe restores exactly without save-file writes")
	for kind in costs:
		costs[kind].sort()
	var held_median: float = (costs.hold[15] + costs.hold[16]) / 2.0
	var active_median: float = (costs.feedback[15] + costs.feedback[16]) / 2.0
	check(held_median > 96.0, "passive median mandate miss is material, not roundoff or quiet equilibrium")
	check(active_median < 0.8 * held_median, "active policy reduces median cumulative mandate miss by at least20percent")
	check(recovered.feedback >= 16 and recovered.hold <= 8, "challenge is recoverable without rewarding passive advance")
	print("CHALLENGE SUMMARY seeds=32 quarters=96 hold_median=%.6f feedback_median=%.6f recovered=%s" % [held_median, active_median, recovered])
	if failures == 0:
		print("PASS: varied-default startup and32 legacy weak-anchor paired careers, policy-sensitive recovery and exact replay")
	quit(1 if failures else 0)
