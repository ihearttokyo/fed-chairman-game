extends SceneTree

const Career = preload("res://play/career.gd")
const FIRST_SEED := 40000
const SEED_COUNT := 32
const WINDOWS := [128, 176, 224]
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func inside(s: Dictionary) -> bool:
	return abs(s.four_quarter_inflation_pct - 2.0) <= 1.0 and abs(s.output_gap_pct) <= 1.0 \
		and s.unemployment_rate_pct <= s.structural_unemployment_pct + 1.5

func policy(career, kind: String, s: Dictionary = {}) -> Dictionary:
	var state: Dictionary = career.state if s.is_empty() else s
	var p: Dictionary = career.model.benchmark_policy(state, career.params, "feedback" if kind == "responsive" else kind)
	if kind == "responsive" and s.is_empty():
		var shock: Dictionary = career.current_briefing()
		p.liquidity_request_pct_initial_gdp = float(shock.get("funding_need_pct_initial_gdp", 0.0)) \
			+ minf(float(shock.get("refinancing_need_pct_initial_gdp", 0.0)), state.outstanding_liquidity_pct_initial_gdp)
	return p

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var boundary := {"four_quarter_inflation_pct":3.0,"output_gap_pct":-1.0,
		"unemployment_rate_pct":6.0,"structural_unemployment_pct":4.5}
	check(inside(boundary), "inclusive late recovery bands")
	boundary.unemployment_rate_pct += 0.000001
	check(not inside(boundary), "late recovery cannot hide unemployment excess")
	var costs := {"hold": [], "responsive": []}
	var material := {"hold": 0, "responsive": 0}
	var ending := {"hold": 0, "responsive": 0}
	var quiet := {"hold": 0, "responsive": 0}
	for seed_number in range(FIRST_SEED, FIRST_SEED + SEED_COUNT):
		var warmed := Career.new()
		if not warmed.start("unanchored_inflation", seed_number).ok:
			check(false, "late source career starts")
			continue
		for q in range(120):
			var result: Dictionary = warmed.advance(policy(warmed, "feedback"))
			if not result.ok:
				check(false, "warmup transition: " + String(result.error))
				break
			if q >= 112:
				check(inside(warmed.state), "Q113..120 already recovered; no seed exclusion")
		check(warmed.state.quarter_index == 120, "warmup reaches the actual common Q120 state")
		if warmed.state.quarter_index != 120:
			continue
		var encoded: PackedByteArray = warmed.encode()
		var warm_state := var_to_bytes(warmed.state)
		var shared_shocks := var_to_bytes(warmed.shocks)
		for kind in ["hold", "responsive"]:
			var career := Career.new()
			var restored: Dictionary = career.restore(bytes_to_var(encoded))
			if not restored.ok:
				check(false, "exact warmup restore: " + String(restored.error))
				continue
			check(var_to_bytes(career.state) == warm_state and var_to_bytes(career.shocks) == shared_shocks,
				"both late strategies start at byte-identical recovered state and realized inputs")
			var cost := 0.0
			var outside_quarters := 0
			var window_outside := [0, 0, 0]
			var complete := true
			for q in range(120, 240):
				var result: Dictionary = career.advance(policy(career, kind))
				if not result.ok:
					check(false, "late transition: " + String(result.error))
					complete = false
					break
				var s: Dictionary = career.state
				cost += abs(s.four_quarter_inflation_pct - 2.0) + maxf(0.0, s.unemployment_rate_pct - s.structural_unemployment_pct)
				var missed := not inside(s)
				outside_quarters += int(missed)
				for index in range(WINDOWS.size()):
					if q >= WINDOWS[index] and q <= mini(WINDOWS[index] + 39, 239):
						window_outside[index] += int(missed)
			if not complete:
				continue
			var missed_windows := 0
			for count in window_outside:
				missed_windows += int(count > 0)
			material[kind] += int(outside_quarters >= 12 and missed_windows >= 2)
			ending[kind] += int(inside(career.state))
			costs[kind].append(cost)
			var replay := Career.new()
			var saved: PackedByteArray = career.encode()
			check(replay.restore(bytes_to_var(saved)).ok and var_to_bytes(replay.history) == var_to_bytes(career.history),
				"complete late source career and all decisions replay exactly")
			var s: Dictionary = career.state.duplicate(true)
			var sustained := true
			for q in range(96):
				var result: Dictionary = career.model.step(s, policy(career, kind, s), {}, career.params)
				if not result.ok:
					check(false, "hypothetical quiet model step: " + String(result.error))
					sustained = false
					break
				s = result.state
				if q >= 88:
					sustained = sustained and inside(s)
			quiet[kind] += int(sustained)
			check(career.encode() == saved and career.state.quarter_index == 240,
				"quiet model probe never advances or mutates the completed playable career")
			print("LATE seed%d %s miss=%.6f outside=%d windows=%s endpoint=%s quiet8=%s" % [seed_number, kind, cost, outside_quarters, window_outside, inside(career.state), sustained])
	for kind in costs:
		check(costs[kind].size() == SEED_COUNT, "all predeclared source paths completed without exclusion")
		costs[kind].sort()
	if costs.hold.size() == SEED_COUNT and costs.responsive.size() == SEED_COUNT:
		var passive: float = (costs.hold[15] + costs.hold[16]) / 2.0
		var active: float = (costs.responsive[15] + costs.responsive[16]) / 2.0
		check(material.hold >= 8, "recovered passive paths face material misses in at least two late response windows")
		check(active <= 0.8 * passive, "responsive toolkit reduces median late diagnostic miss by at least20percent")
		check(ending.responsive == SEED_COUNT and quiet.responsive == SEED_COUNT,
			"every responsive source path ends inside bands and recovers in the separate hypothetical quiet tail")
		print("LATE SUMMARY hold=%.6f responsive=%.6f material=%s endpoint=%s quiet=%s" % [passive, active, material, ending, quiet])
	if failures == 0:
		print("PASS: late challenge after recovered warmup,32 paired source careers and exact replay; diagnostic not fun or welfare")
	quit(1 if failures else 0)
