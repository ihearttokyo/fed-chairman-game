extends SceneTree

const Career = preload("res://play/career.gd")
const MainScene = preload("res://main.tscn")
const MAIN_PATH := "res://play/main.gd"
const REUSE := "\t\tvar path: Dictionary = selected if other == policy else career.forecast(other)\n"
const PREFIXES := [
	"\t\tother.policy_rate_request_pct = alternative[1]\n",
	"\t\tother[alternative[1]] = alternative[2]\n",
]
const ORIGINALS := [
	"\t\tvar path: Dictionary = selected if alternative[0] == \"Selected\" else career.forecast(other)\n",
	"\t\tvar path: Dictionary = career.forecast(other)\n",
]

class CountEconomy:
	extends "res://model/economy.gd"
	var steps := 0

	func step(state: Dictionary, policy: Dictionary,
			shocks: Dictionary, params: Dictionary) -> Dictionary:
		steps += 1
		return super.step(state, policy, shocks, params)

class CountCareer:
	extends "res://play/career.gd"
	var forecasts := 0

	func _init() -> void:
		model = CountEconomy.new()

	func forecast(policy: Dictionary) -> Dictionary:
		forecasts += 1
		return super.forecast(policy)

var failures := 0

func check(condition: bool, message: String) -> bool:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
	return condition

func _initialize() -> void:
	call_deferred("run")

func control_script(source: String) -> GDScript:
	var sites: Array = []
	var edits := 0
	for index in range(PREFIXES.size()):
		var original: String = PREFIXES[index] + ORIGINALS[index]
		var candidate: String = PREFIXES[index] + REUSE
		if not check(source.count(original) + source.count(candidate) == 1,
				"exactly one known comparison site %d" % index):
			return null
		edits += source.count(candidate)
		sites.append([original, candidate])
	if not check(edits in [0, 2] and source.count(REUSE) == edits,
			"control transformation recognizes zero or both known reuse sites"):
		return null
	var baseline := source
	for site in sites:
		baseline = baseline.replace(site[1], site[0])
	var reconstructed := baseline
	if edits == 2:
		for site in sites:
			reconstructed = reconstructed.replace(site[0], site[1])
	if not check(reconstructed.to_utf8_buffer() == source.to_utf8_buffer(),
			"reversible known-site transformation preserves every other byte"):
		return null
	var script := GDScript.new()
	script.source_code = baseline
	if not check(script.reload() == OK, "native control script compiles"):
		return null
	print("PROVENANCE control_sha256=%s candidate_sha256=%s reverted_sites=%d"
		% [baseline.sha256_text(), source.sha256_text(), edits])
	return script

func live_bytes(career) -> PackedByteArray:
	return var_to_bytes([career.state, career.history, career._seeded_shocks])

func snapshot(game: Control) -> Dictionary:
	return {
		"encoded": game.career.encode(),
		"live": live_bytes(game.career),
		"policy": var_to_bytes(game._policy()),
	}

func generated_fixture(spec: Dictionary) -> Dictionary:
	var career := Career.new()
	var begun: Dictionary = career.start(spec.scenario, spec.seed)
	if not check(begun.ok, "generated career starts: %s" % str(begun)):
		return {}
	for quarter in range(spec.quarter):
		var policy: Dictionary = career.model.benchmark_policy(
			career.state, career.params, "feedback")
		var advanced: Dictionary = career.advance(policy)
		if not check(advanced.ok,
				"feedback setup Q%d succeeds: %s" % [quarter, str(advanced)]):
			return {}
	if not check(career.state.quarter_index == spec.quarter
			and career.decisions.size() == spec.quarter
			and career.history.size() == spec.quarter + 1,
			"generated fixture reaches the requested completed-quarter horizon"):
		return {}
	var encoded: PackedByteArray = career.encode()
	return {
		"payload": bytes_to_var(encoded),
		"encoded": encoded,
		"live": live_bytes(career),
	}

func install_fixture(game: Control, generated: Dictionary,
		spec: Dictionary, counted: bool) -> bool:
	game.career = CountCareer.new() if counted else Career.new()
	var restored: Dictionary = game.career.restore(generated.payload)
	if not check(restored.ok, "generated fixture replays: %s" % str(restored)):
		return false
	if not check(game.career.encode() == generated.encoded
			and live_bytes(game.career) == generated.live,
			"real replay exactly preserves generated inputs, state and history"):
		return false
	game._refresh(true)
	game.loading_controls = true
	var current: float = game.career.state.policy_rate_pct
	game.rate.value = current + 0.5 if spec.rich else current
	game.guidance.value = game.rate.value + 0.75 if spec.rich else current
	game.assets.value = 1.25 if spec.rich else 0.0
	game.liquidity.value = 2.5 if spec.rich else 0.0
	game.reinvestment.button_pressed = true
	game.reserve_maintenance.button_pressed = true
	game.sterilization.button_pressed = false
	game.commitment.select(2 if spec.rich else 0)
	game.inflation_response.value = 0.7 if spec.rich else game.career.params.policy_inflation_response
	game.activity_response.value = -0.25 if spec.rich else game.career.params.policy_output_gap_response
	game._guidance_controls()
	game.loading_controls = false
	game._apply_policy_inputs()
	await process_frame
	await process_frame
	var policy: Dictionary = game._policy()
	var eligible: bool = policy.policy_rate_request_pct == current \
		and policy.guidance_rate_pct == current \
		and policy.asset_flow_request_pct_initial_gdp == 0.0 \
		and policy.liquidity_request_pct_initial_gdp == 0.0
	var distinct: bool = policy.policy_rate_request_pct != current \
		and policy.guidance_rate_pct != policy.policy_rate_request_pct \
		and policy.asset_flow_request_pct_initial_gdp != 0.0 \
		and policy.liquidity_request_pct_initial_gdp != 0.0
	if not check(distinct if spec.rich else eligible,
			"staged controls satisfy the intended reuse eligibility"):
		return false
	if spec.invalid:
		game.career.shocks[spec.quarter]["comparison_fixture_unknown_input"] = 1.0
	var forecast: Dictionary = game.career.forecast(policy)
	if not check(not forecast.ok if spec.invalid else forecast.ok,
			"setup forecast has the intended validity: %s"
			% str(forecast.get("error", "valid"))):
		return false
	if spec.invalid and not check(forecast.error
			== "unknown exogenous input: comparison_fixture_unknown_input",
			"invalid fixture rejects the deliberately unknown current shock"):
		return false
	game._preview()
	return true

func reports(game: Control) -> Array[AcceptDialog]:
	var found: Array[AcceptDialog] = []
	for child in game.get_children():
		if child is AcceptDialog:
			found.append(child)
	return found

func close_reports(game: Control) -> void:
	for dialog in reports(game):
		dialog.get_ok_button().pressed.emit()
		check(dialog.visible and dialog.is_queued_for_deletion(),
			"OK retains the existing queued accessibility disposal")
	await process_frame
	await process_frame
	check(reports(game).is_empty(), "two frames dispose all comparison modals")

func reset_counts(game: Control) -> void:
	if game.career is CountCareer:
		game.career.forecasts = 0
		game.career.model.steps = 0

func compare_sample(game: Control, expected: Dictionary,
		label: String, timed: bool) -> Dictionary:
	if not check(reports(game).is_empty() and snapshot(game) == expected,
			label + ": clean modal and unchanged starting fixture"):
		return {}
	reset_counts(game)
	# Only the real synchronous Compare action lies inside this interval.
	var started := Time.get_ticks_usec() if timed else 0
	game._compare()
	var elapsed := Time.get_ticks_usec() - started if timed else 0
	var counts: Array = []
	if game.career is CountCareer:
		counts = [game.career.forecasts, game.career.model.steps]
	await process_frame
	await process_frame
	var dialogs := reports(game)
	if not check(dialogs.size() == 1, label + ": exactly one displayed report"):
		await close_reports(game)
		return {}
	var dialog: AcceptDialog = dialogs[0]
	var bodies := dialog.find_children("*", "TextEdit", true, false)
	if not check(bodies.size() == 1, label + ": complete native report body"):
		await close_reports(game)
		return {}
	var body: TextEdit = bodies[0]
	check(dialog.visible and body.is_visible_in_tree(),
		label + ": report is displayed")
	check(body.accessibility_description == body.text,
		label + ": accessibility retains the complete displayed report")
	var output: Array = [
		dialog.title, body.text, body.accessibility_name,
		body.accessibility_description, game.forecast_label.text,
	]
	check(snapshot(game) == expected,
		label + ": opening preserves encoded career, live state/history and policy")
	await close_reports(game)
	check(snapshot(game) == expected, label + ": closing is also pure")
	return {"output": output, "counts": counts, "usec": elapsed}

func statistics(values: Array) -> Dictionary:
	# Exactly 21 samples: median index 10; nearest-rank p95 index 19.
	var ordered := values.duplicate()
	ordered.sort()
	var median: float = ordered[10]
	var deviations: Array = []
	for value in ordered:
		deviations.append(absf(float(value) - median))
	deviations.sort()
	return {"median": median, "p95": ordered[19], "mad": deviations[10]}

func run_case(games: Array[Control], spec: Dictionary) -> bool:
	var label := "%s/seed%d/Q%d/%s" % [
		spec.scenario, spec.seed, spec.quarter,
		"invalid" if spec.invalid else ("rich" if spec.rich else "neutral"),
	]
	var generated := generated_fixture(spec)
	if generated.is_empty():
		return false
	var expected: Array[Dictionary] = []
	for game in games:
		var installed: bool = await install_fixture(game, generated, spec, true)
		if not installed:
			return false
		expected.append(snapshot(game))
	if not check(expected[0] == expected[1],
			label + ": control and treatment have identical generated fixtures"):
		return false

	var golden: Array = []
	for index in range(2):
		var result: Dictionary = await compare_sample(
			games[index], expected[index], label, false)
		if result.is_empty():
			return false
		golden.append(result.output)
		var forecasts: int = 3 if spec.invalid else (
			10 if index == 0 or spec.rich else 5)
		var steps: int = forecasts if spec.invalid else forecasts * 8
		var wanted := [forecasts, steps]
		print("COUNTS %s %s observed=%s expected=%s" % [
			label, "C" if index == 0 else "T", str(result.counts), str(wanted)])
		# Intentional RED on unmodified source: neutral T observes [10, 80].
		check(result.counts == wanted,
			"%s %s count gate: expected %s, observed %s" % [
				label, "C" if index == 0 else "T", str(wanted), str(result.counts)])
		var report: String = result.output[1]
		if spec.invalid:
			check(report.begins_with("Comparison unavailable: ")
				and String(result.output[4]).begins_with("Preview unavailable: "),
				label + ": rejected paths retain both visible error messages")
		else:
			for marker in ["CURRENT MEETING /", "COMMITTEE DELIBERATION /",
					"GUIDANCE /", "Q+1 / WHY", "CURRENT TRANSMISSION /",
					"ONE-CONTROL CONTRASTS /", "REFERENCE AND LIMITS"]:
				check(report.contains(marker), label + ": complete report retains " + marker)
			check(not report.contains(" / unavailable:")
				and not report.contains("Contrast unavailable:"),
				label + ": every representative alternative remains available")
		# Direct repeated previews remain fresh, real and outside timing.
		for _repeat in range(2):
			reset_counts(games[index])
			games[index]._preview()
			check([games[index].career.forecasts, games[index].career.model.steps]
				== [1, 1 if spec.invalid else 8],
				label + ": standalone preview executes one real forecast")
			check(games[index].forecast_label.text == result.output[4]
				and snapshot(games[index]) == expected[index],
				label + ": repeated previews preserve exact text and fixture")
	check(golden[0] == golden[1], label + ": exact control/treatment output parity")

	# Replace counting subclasses with ordinary production instances for timing.
	for index in range(2):
		var installed: bool = await install_fixture(
			games[index], generated, spec, false)
		if not installed:
			return false
		if not check(not games[index].career is CountCareer
				and not games[index].career.model is CountEconomy
				and snapshot(games[index]) == expected[index],
				label + ": ordinary timing fixture matches the count fixture"):
			return false
		var warm: Dictionary = await compare_sample(
			games[index], expected[index], label, false)
		if warm.is_empty():
			return false
		check(warm.output == golden[0], label + ": ordinary warm-up parity")

	var samples: Array = [[], []]
	# C = native control; T = current-source treatment.
	# Seven pairs per block produce 21 samples per variant: C/T, T/C, C/T.
	for block in range(3):
		var order: Array = [1, 0] if block == 1 else [0, 1]
		for _pair in range(7):
			for index in order:
				var result: Dictionary = await compare_sample(
					games[index], expected[index], label, true)
				if result.is_empty():
					return false
				check(result.output == golden[0],
					label + ": every timed opening has exact baseline output")
				samples[index].append(result.usec)
	if not check(samples[0].size() == 21 and samples[1].size() == 21,
			label + ": complete paired timing sample"):
		return false
	var control := statistics(samples[0])
	var treatment := statistics(samples[1])
	print("TIMING %s n=21/variant orders=C/T,T/C,C/T "
		% label
		+ "C median=%.1f us p95=%.1f us MAD=%.1f us; "
		% [control.median, control.p95, control.mad]
		+ "T median=%.1f us p95=%.1f us; T-C median=%+.1f us"
		% [treatment.median, treatment.p95, treatment.median - control.median])
	# Positive T-C is a measured regression; latency has no flaky pass threshold.
	return true

func run() -> void:
	var version := Engine.get_version_info()
	if not check(version.major == 4 and version.minor == 7 and version.patch == 2,
			"fixture requires Godot 4.7.2"):
		quit(1)
		return
	var bytes := FileAccess.get_file_as_bytes(MAIN_PATH)
	var source := bytes.get_string_from_utf8()
	if not check(not bytes.is_empty() and source.to_utf8_buffer() == bytes,
			"current main source is readable and byte-exact UTF-8"):
		quit(1)
		return
	var baseline := control_script(source)
	if baseline == null:
		quit(1)
		return
	print("RUNTIME engine=%s platform=%s; same-process exact parity"
		% [version.string, OS.get_name()])
	var control: Control = MainScene.instantiate()
	var treatment: Control = MainScene.instantiate()
	control.set_script(baseline) # Must precede add_child and _ready.
	if not check(treatment.get_script().source_code == source,
			"actual main.tscn treatment uses the inspected current source"):
		control.free()
		treatment.free()
		quit(1)
		return
	root.add_child(control)
	root.add_child(treatment)
	await process_frame
	await process_frame
	var games: Array[Control] = [control, treatment]
	var cases: Array[Dictionary] = []
	for scenario in [["base", 41], ["mixed_crises", 417]]:
		for quarter in [0, 120, 239]:
			for rich in [false, true]:
				cases.append({"scenario": scenario[0], "seed": scenario[1],
					"quarter": quarter, "rich": rich, "invalid": false})
	cases.append({"scenario": "base", "seed": 41,
		"quarter": 0, "rich": false, "invalid": true})
	for spec in cases:
		var setup_ok: bool = await run_case(games, spec)
		if not setup_ok:
			break
	for game in games:
		game.queue_free()
	await process_frame
	await process_frame
	print("%s: comparison count, exact parity and paired timing fixture; failures=%d"
		% ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures else 0)
