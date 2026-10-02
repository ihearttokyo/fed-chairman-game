extends RefCounted

# Release templates prohibit external script/path overrides. This fixed, read-only
# check exercises the actual bundled resources without weakening that restriction.
const Career = preload("res://play/career.gd")
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func run(game: Control) -> int:
	check(not FileAccess.get_sha256("res://model/economy.gd").is_empty(), "bundled model source fingerprint")
	for case_id in Career.new().cases:
		var career := Career.new()
		check(career.start(case_id, 417).ok, "scenario starts: " + case_id)
		for q in range(20):
			check(career.advance(career.model.benchmark_policy(career.state, career.params, "feedback")).ok, "quarter transition")
		var restored := Career.new()
		check(restored.restore(bytes_to_var(career.encode())).ok, "native save replay")
		check(restored.state == career.state, "exact replay state")
	check(game.career.state.quarter_index == 0, "main scene starts")
	check(game.city.get_child_count() > 0, "original city resource loads")
	if failures == 0 and checks == 164:
		print("PASS: 164 release-safe checks; seven 20-quarter careers, lossless replay, main scene and city")
		print("MODEL_DIGEST ", Career.new().model_digest())
		return 0
	printerr("FAIL: build verification completed ", checks, " checks with ", failures, " failures")
	return 1
