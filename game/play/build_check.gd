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
	var baseline_ok := failures == 0 and checks == 164
	for signed in [false, true]:
		var career := Career.new()
		check(career.start("base", 1).ok, "guidance release fixture starts")
		career.shocks[0] = {"demand_shock_pct":1.2, "funding_need_pct_initial_gdp":2.0,
			"eligible_collateral_pct_initial_gdp":4.0, "liquidity_eligibility_pct":100.0}
		var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold")
		policy.merge({"policy_rate_request_pct":-2.0 if signed else 3.5,
			"guidance_rate_pct":-4.0 if signed else 4.5,
			"guidance_inflation_sensitivity":0.7 if signed else 0.0,
			"guidance_output_gap_sensitivity":-0.25 if signed else 0.0,
			"asset_flow_request_pct_initial_gdp":1.25, "liquidity_request_pct_initial_gdp":4.0,
			"reinvest_principal":false, "maintain_ample_reserves":false, "sterilize_purchases":true}, true)
		_check_guidance(career, policy)
	_check_report(game)
	var guidance_ok := failures == 0 and checks == 223
	_check_mandate(game)
	if baseline_ok and guidance_ok and failures == 0 and checks == 235:
		print("PASS: 164 release-safe checks; seven 20-quarter careers, lossless replay, main scene and city")
		print("PASS: bundled guidance continuation and comparison")
		print("PASS: bundled mandate assessment and realized feedback")
		print("RELEASE_CHECKS ", checks)
		print("MODEL_DIGEST ", Career.new().model_digest())
		return 0
	printerr("FAIL: build verification completed ", checks, " checks with ", failures, " failures")
	return 1

func _check_mandate(game: Control) -> void:
	var initial: Dictionary = game.career.mandate_assessment()
	check(initial.eligible and initial.quarters == 0 and not initial.achieved, "bundled default begins unassessed")
	check(game.mandate_label.text.contains("MANDATE v1") and game.mandate_label.text.contains("In progress"), "bundled objectives remain visible")
	for kind in ["hold", "feedback"]:
		var career := Career.new()
		check(career.start("unanchored_inflation", 1).ok, "bundled mandate career starts")
		var valid := true
		for q in range(Career.MAX_QUARTERS):
			var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, kind)
			if kind == "feedback":
				var pulse: Dictionary = career.current_briefing()
				policy.liquidity_request_pct_initial_gdp = float(pulse.get("funding_need_pct_initial_gdp", 0.0)) + minf(float(pulse.get("refinancing_need_pct_initial_gdp", 0.0)), career.state.outstanding_liquidity_pct_initial_gdp)
			if not career.advance(policy).ok:
				valid = false
				break
		check(valid and career.decisions.size() == Career.MAX_QUARTERS, "bundled mandate uses a complete native path")
		var before := _live_bytes(career)
		var assessment := career.mandate_assessment()
		check(assessment.eligible and assessment.complete and assessment.achieved == (kind == "feedback"), "bundled completion differs from achievement")
		check(_live_bytes(career) == before, "bundled assessment preserves all live bytes")
		var restored := Career.new()
		check(restored.restore(bytes_to_var(career.encode())).ok and var_to_bytes(restored.mandate_assessment()) == var_to_bytes(assessment), "bundled replay restores the derived assessment")

func _check_report(game: Control) -> void:
	var before: PackedByteArray = _live_bytes(game.career)
	var policy: Dictionary = game._policy()
	var controls := var_to_bytes(policy)
	var preview: String = game.forecast_label.text
	var held: Dictionary = game.career.forecast(policy)
	var followed: Dictionary = game.career.forecast(policy, true)
	var report: String = game._decision_briefing()
	check(held.ok and followed.ok and held.get("states", []).size() == 8
		and followed.get("states", []).size() == 8 and not report.contains("unavailable"), "bundled main comparison paths are available")
	if held.ok and followed.ok and held.states.size() == 8 and followed.states.size() == 8:
		var a: Dictionary = held.states[1]
		var b: Dictionary = followed.states[1]
		check(report.contains("GUIDANCE CONTINUATION / SELECTED HOLD VS PROMISE-FOLLOW\n")
			and report.contains("Q+2 / A VS B\nNominal rate %.2f%% vs %.2f%%\nEffective borrowing rate %.3f%% vs %.3f%%\nPromise follow-through %.1f vs %.1f / 100\nStance adequacy %.1f vs %.1f / 100\n" % [a.policy_rate_pct, b.policy_rate_pct, a.effective_policy_rate_pct, b.effective_policy_rate_pct, 100 * a.guidance_followthrough_score, 100 * b.guidance_followthrough_score, 100 * a.stance_adequacy_score, 100 * b.stance_adequacy_score]), "bundled Q+2 comparison values match the real paths")
		a = held.states[7]
		b = followed.states[7]
		check(report.contains("Q+8 / A VS B\nNominal rate %.2f%% vs %.2f%%\nEffective borrowing rate %.3f%% vs %.3f%%\n" % [a.policy_rate_pct, b.policy_rate_pct, a.effective_policy_rate_pct, b.effective_policy_rate_pct])
			and report.contains("B / Q+8 PROMISE-FOLLOW\nInflation %.3f%%; unemployment %.3f%%; output gap %+.3f%%\nCredibility %.1f / 100; public support %.1f / 100\n" % [b.four_quarter_inflation_pct, b.unemployment_rate_pct, b.output_gap_pct, 100 * b.credibility, b.public_support]), "bundled Q+8 comparison values match the real paths")
		check(report.contains("Q+8 / B MINUS A\nInflation %s; unemployment %s\nOutput gap %s; credibility %s; support %s\n" % [game._change_text(b.four_quarter_inflation_pct - a.four_quarter_inflation_pct, 3, "pp"), game._change_text(b.unemployment_rate_pct - a.unemployment_rate_pct, 3, "pp"), game._change_text(b.output_gap_pct - a.output_gap_pct, 3, "pp"), game._change_text(100 * (b.credibility - a.credibility), 2), game._change_text(b.public_support - a.public_support, 2)]), "bundled comparison differences match B minus A")
	check(_live_bytes(game.career) == before and var_to_bytes(game._policy()) == controls
		and game.forecast_label.text == preview, "bundled comparison preserves career, controls and preview")

func _live_bytes(career) -> PackedByteArray:
	return var_to_bytes([career.state, career.history, career.decisions, career.shocks, career._seeded_shocks,
		career.episodes, career.scenario_id, career.seed_value, career.params, career.cases, career.encode()])

func _check_guidance(career, policy: Dictionary) -> void:
	var before := _live_bytes(career)
	var input := var_to_bytes(policy)
	var held: Dictionary = career.forecast(policy)
	var followed: Dictionary = career.forecast(policy, true)
	check(var_to_bytes(held) == var_to_bytes(career.forecast(policy, false)), "bundled default hold remains unchanged")
	check(held.ok and followed.ok and held.get("states", []).size() == 8
		and followed.get("states", []).size() == 8, "bundled guidance has two eight-quarter paths")
	if held.ok and followed.ok and held.states.size() == 8 and followed.states.size() == 8:
		check(var_to_bytes(held.states[0]) == var_to_bytes(followed.states[0]), "bundled A and B share the exact current decision")
		var first: Dictionary = followed.states[0]
		var implied: float = first.guidance_rate_pct \
			+ policy.guidance_inflation_sensitivity * (first.four_quarter_inflation_pct - first.guidance_reference_inflation_pct) \
			+ policy.guidance_output_gap_sensitivity * (first.output_gap_pct - first.guidance_reference_output_gap_pct)
		var due: float = roundf(implied / career.params.minimum_rate_increment_pct) * career.params.minimum_rate_increment_pct
		check(followed.states[1].policy_rate_pct == due and followed.states[1].guidance_followthrough_score == 1.0, "bundled Q+2 delivers the nominal promise")
		check(held.states[1].policy_rate_pct == policy.policy_rate_request_pct
			and held.states[1].guidance_followthrough_score < 1.0, "bundled held rate does not deliver the differing promise")
		check(followed.states[1].effective_policy_rate_pct != due if due < 0.0
			else followed.states[1].effective_policy_rate_pct == due, "bundled effective and nominal transmission remain distinct")
		for follow in [false, true]:
			var projected: Dictionary = career.state.duplicate(true)
			var expected: Array = []
			for q in range(8):
				var choice: Dictionary = policy.duplicate(true)
				if q > 0:
					var rate: float = projected.policy_rate_pct
					if follow:
						rate = projected.guidance_rate_pct \
							+ policy.guidance_inflation_sensitivity * (projected.four_quarter_inflation_pct - projected.guidance_reference_inflation_pct) \
							+ policy.guidance_output_gap_sensitivity * (projected.output_gap_pct - projected.guidance_reference_output_gap_pct)
					choice.policy_rate_request_pct = roundf(rate / career.params.minimum_rate_increment_pct) * career.params.minimum_rate_increment_pct
					choice.guidance_rate_pct = choice.policy_rate_request_pct
					choice.guidance_inflation_sensitivity = policy.guidance_inflation_sensitivity if follow else career.params.policy_inflation_response
					choice.guidance_output_gap_sensitivity = policy.guidance_output_gap_sensitivity if follow else career.params.policy_output_gap_response
					choice.asset_flow_request_pct_initial_gdp = 0.0
					choice.liquidity_request_pct_initial_gdp = 0.0
				var result: Dictionary = career.model.step(projected, choice, career.current_briefing() if q == 0 else {}, career.params)
				check(result.ok, "bundled independent continuation transition")
				if not result.ok:
					break
				projected = result.state
				expected.append(projected.duplicate(true))
			check(var_to_bytes(expected) == var_to_bytes(followed.states if follow else held.states), "bundled full path equals independent current-only replay")
	check(_live_bytes(career) == before, "bundled forecasts preserve every live career byte")
	check(var_to_bytes(policy) == input, "bundled forecasts preserve the input policy")
