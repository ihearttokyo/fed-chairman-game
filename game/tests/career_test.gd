extends SceneTree
const Career = preload("res://play/career.gd")
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
func _initialize() -> void:
	check_recurring_crises()
	if OS.get_cmdline_user_args().has("--campaign-only"):
		if failures == 0:
			print("PASS: recurring offline crises, bounded variety, exact replay and current-only forecasts")
		quit(1 if failures else 0)
		return
	check_situation_briefing()
	if OS.get_cmdline_user_args().has("--situation-only"):
		if failures == 0:
			print("PASS: offline situation continuity, replay and no future spoilers")
		quit(1 if failures else 0)
		return
	var career := Career.new()
	check(career.start("supply_shock", 417).ok, "scenario starts")
	var initial: Dictionary = career.state.duplicate(true)
	var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, "feedback")
	check(career.advance(policy).ok, "valid decision advances")
	check(career.state.quarter_index == 1, "advancing increments the quarter")
	check(career.history.size() == 2 and career.decisions.size() == 1, "decision and state retained")
	check(career.history[0] == initial, "previous state preserved")
	var seed_probe := Career.new()
	seed_probe.start("supply_shock", 1)
	check(not seed_probe.start("base", 2147483648).ok, "out-of-range seed is rejected before starting")
	check(seed_probe.scenario_id == "supply_shock", "invalid seed cannot replace an active career")
	var before: Dictionary = career.state.duplicate(true)
	var projection: Dictionary = career.forecast(policy)
	check(projection.ok and projection.states.size() == 8, "forecast has eight quarters")
	check(career.state == before, "forecast cannot mutate live state")
	var serialized: Dictionary = career.payload()
	var loaded := Career.new()
	check(loaded.restore(bytes_to_var(career.encode())).ok, "save replays after lossless native-value round-trip")
	check(loaded.state == career.state, "loaded state matches every field")
	check(not loaded.restore({"version": 999}).ok, "unsupported save rejected")
	check(loaded.state == career.state, "bad save leaves active state intact")
	serialized.shocks[200] = {"funding_need_pct_initial_gdp": -1.0}
	check(not loaded.restore(serialized).ok, "invalid future shock rejected at load")
	check(loaded.state == career.state, "late invalid input cannot partially replace career")
	var clean: Dictionary = career.payload()
	clean.decisions[0].policy_rate_request_pct = -1.001
	check(not loaded.restore(clean).ok, "off-grid decision rejected during replay")
	check(loaded.state == career.state, "off-grid replay cannot replace the active career")
	var signed := Career.new()
	signed.start("base", 417)
	var signed_policy: Dictionary = signed.model.benchmark_policy(signed.state, signed.params, "hold")
	signed_policy.policy_rate_request_pct = -1.0
	signed_policy.guidance_rate_pct = -1.0
	check(signed.advance(signed_policy).ok, "signed nominal policy advances a career")
	var signed_replay := Career.new()
	check(signed_replay.restore(bytes_to_var(signed.encode())).ok and signed_replay.state == signed.state, "negative rates survive full validated replay")
	var forecast_before: Dictionary = career.forecast(policy)
	career.shocks[2].demand_shock_pct = 10.0
	check(career.forecast(policy) == forecast_before, "preview cannot inspect future shocks")
	career.shocks[2] = loaded.shocks[2].duplicate(true)
	var briefing: Dictionary = career.current_briefing()
	briefing.demand_shock_pct = 99.0
	check(career.current_briefing() != briefing, "briefing is a copy")
	var temporary := OS.get_environment("TMPDIR")
	if temporary.is_empty():
		temporary = "/tmp" # macOS and Linux test runners; never write fixtures into the repository.
	var path := temporary.path_join("fed-career-%s.save" % OS.get_process_id())
	if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".pending"):
		check(false, "career save fixture collision; existing final and pending files preserved")
		quit(1)
		return
	check(career.save_to(path).ok, "native file save succeeds")
	check(loaded.load_from(path).ok and loaded.state == career.state, "native file load is lossless")
	for q in range(48):
		check(career.advance(career.model.benchmark_policy(career.state, career.params, "feedback")).ok, "multi-term decision is valid")
	check(career.history.size() == 50 and career.state.quarter_index == 49, "chart and lag history survive multiple reviews")
	check(career.save_to(path).ok, "atomic replacement succeeds")
	check(loaded.load_from(path).ok and loaded.state == career.state, "replaced save replays full history")
	check(not career.save_to(path.path_join("missing/save")).ok, "failed write reported")
	check(loaded.load_from(path).ok and loaded.state == career.state, "failed write preserves last save")
	check(career.has_method("review_comparison"), "completed periods expose a same-shock policy comparison")
	if career.has_method("review_comparison"):
		var held := Career.new()
		held.start("supply_shock", 17)
		check(not held.review_comparison().ok, "review requires a completed decision")
		for q in range(24):
			held.advance(held.model.benchmark_policy(held.state, held.params, "hold"))
		var identical: Dictionary = held.review_comparison()
		check(identical.ok and identical.from_quarter == 12 and identical.to_quarter == 24, "review uses only the last twelve completed quarters")
		check(identical.actual == identical.held, "holding policy equals its same-realized-shock reference")
		var preserved := career.encode()
		var state_before_review: Dictionary = career.state.duplicate(true)
		var history_before: Array = career.history.duplicate(true)
		var result: Dictionary = career.review_comparison()
		var baseline: Dictionary = career.history[37].duplicate(true)
		var inflation_miss := 0.0
		var employment_shortfall := 0.0
		for q in range(37, 49):
			baseline = career.model.step(baseline, career.model.benchmark_policy(baseline, career.params, "hold"), career.shocks[q], career.params).state
			inflation_miss += abs(baseline.four_quarter_inflation_pct - career.params.inflation_target_pct) / 12.0
			employment_shortfall += max(0.0, baseline.unemployment_rate_pct - baseline.structural_unemployment_pct) / 12.0
		check(is_equal_approx(result.held.inflation_miss, inflation_miss) and is_equal_approx(result.held.employment_shortfall, employment_shortfall), "review reports realized path costs, not endpoint-only changes")
		check(result.held.credibility == baseline.credibility and result.held.public_support == baseline.public_support, "review carries expectations and hardship memory through the reference")
		check(result.actual.credibility == career.state.credibility and result.actual.public_support == career.state.public_support, "actual review ends at the player's committed outcome")
		check(not is_equal_approx(result.actual.inflation_miss, result.held.inflation_miss), "different realized policies remain distinct in the comparison")
		check(career.encode() == preserved and career.history == history_before and career.state == state_before_review, "review cannot mutate the career or save")
		career.shocks[49].demand_shock_pct = 10.0
		check(career.review_comparison() == result, "review cannot inspect the current or future unrealized briefing")
	if failures == 0:
		print("PASS: career progression, forecast isolation, validated lossless saves and 49-quarter continuity")
	quit(1 if failures else 0)

func check_recurring_crises() -> void:
	var career := Career.new()
	check(career.cases.has("mixed_crises"), "recurring crisis campaign is selectable")
	# This candidate also proves the generator behavior before the selector exists.
	var scenario: Dictionary = career.cases.get("mixed_crises", {"id": "mixed_crises", "initial": {}, "events": []})
	var original: Dictionary = career.cases.duplicate(true)
	var parameters: Dictionary = career.params.duplicate(true)
	var signatures := {}
	var polarities := {"demand": {}, "supply": {}}
	var strengths := {}
	for seed_number in [0, 1, 17, 41, 417, -2147483647, 2147483647, -9223372036854775807, 9223372036854775807]:
		var path: Array = career.model.seeded_shock_path(seed_number, scenario, 240)
		var background: Array = career.model.seeded_shock_path(seed_number, {"id": "base", "events": []}, 240)
		check(path == career.model.seeded_shock_path(seed_number, scenario, 240), "same seed exactly reproduces all campaign shocks")
		check(path.slice(0, 48) == career.model.seeded_shock_path(seed_number, scenario, 48), "short campaign is an exact horizon prefix")
		check(path == career.model.seeded_shock_path(seed_number, scenario, 1000).slice(0, 240), "exporter horizon preserves the campaign prefix")
		var onsets: Array = []
		var types: Array = []
		var bag := {}
		var q := 0
		while q < path.size():
			check(career.model._validate_shocks(path[q]).ok, "campaign shock stays within native input bounds")
			var demand: float = path[q].demand_shock_pct - background[q].demand_shock_pct
			var supply: float = path[q].supply_innovation_pct - background[q].supply_innovation_pct
			var funding: float = path[q].get("funding_need_pct_initial_gdp", 0.0)
			check(path[q].r_star_change_pct == background[q].r_star_change_pct, "episode RNG does not perturb background neutral-rate innovations")
			if abs(demand) < 0.2 and abs(supply) < 0.05 and funding == 0.0:
				check(path[q] == background[q], "non-episode quarter retains the exact background path")
				q += 1
				continue
			var kind := "demand" if abs(demand) >= 0.2 else "supply" if abs(supply) >= 0.05 else "funding"
			check(q >= 12 and q <= 20 if onsets.is_empty() else q - onsets[-1] >= 12 and q - onsets[-1] <= 20, "first and recurring onsets are 12 to 20 quarters apart")
			check(not bag.has(kind), "each crisis type appears once before the bag refills")
			bag[kind] = true
			if bag.size() == 3:
				bag.clear()
			onsets.append(q)
			types.append(kind)
			var strength: float = abs(demand) / 1.2 if kind == "demand" else abs(supply) / 1.8 if kind == "supply" else funding / 3.0
			check(strength >= 0.75 - 1e-6 and strength <= 1.25 + 1e-6, "episode strength is 0.75 to 1.25 times its existing template")
			strengths[snappedf(strength, 0.001)] = true
			if kind != "funding":
				polarities[kind][signf(demand if kind == "demand" else supply)] = true
			if q + 1 < path.size():
				var next: Dictionary = path[q + 1]
				check(career.model._validate_shocks(next).ok and next.r_star_change_pct == background[q + 1].r_star_change_pct, "second episode quarter has valid, unchanged background inputs")
				if kind == "demand":
					check(is_equal_approx(next.demand_shock_pct - background[q + 1].demand_shock_pct, demand / 2.0) and supply == 0.0, "paired demand pulses preserve their sign and template ratio")
				elif kind == "supply":
					check(is_equal_approx(next.supply_innovation_pct - background[q + 1].supply_innovation_pct, supply * 0.5 / 1.8) and demand == 0.0, "paired supply pulses preserve their sign and template ratio")
				else:
					check(is_equal_approx(next.funding_need_pct_initial_gdp, 2.0 * strength) and demand == 0.0 and supply == 0.0, "funding episode retains its paired financing needs")
					check(is_equal_approx(path[q].eligible_collateral_pct_initial_gdp, 6.0 * strength) and is_equal_approx(next.eligible_collateral_pct_initial_gdp, 4.0 * strength), "funding collateral scales with the existing template")
					check(path[q].collateral_haircut_pct == 25.0 and next.collateral_haircut_pct == 25.0 and path[q].liquidity_eligibility_pct == 100.0 and next.liquidity_eligibility_pct == 100.0 and is_equal_approx(path[q].solvency_risk_innovation_pct, 0.6 * strength), "liquidity safeguards and separate solvency impairment remain intact")
			q += 2
		check(onsets.size() >= 11 and onsets[-1] > 200, "major crises continue through the late career")
		signatures[str(onsets) + str(types)] = true
	check(signatures.size() >= 8, "seeds materially vary episode timing and order")
	check(polarities.demand.size() == 2 and polarities.supply.size() == 2 and strengths.size() >= 20, "demand and supply include both signs and varied episode strengths")
	check(career.cases == original and career.params == parameters, "campaign generation cannot mutate templates or parameters")
	seed(1729)
	var global_first := randi()
	var global_second := randi()
	seed(1729)
	check(randi() == global_first, "global RNG fixture starts consistently")
	career.model.seeded_shock_path(417, scenario, 240)
	check(randi() == global_second, "campaign generation does not consume global randomness")
	if not career.cases.has("mixed_crises"):
		return
	check(career.start("mixed_crises", 417).ok, "actual campaign career starts")
	var preserved := career.encode()
	var choice: Dictionary = career.model.benchmark_policy(career.state, career.params, "feedback")
	var forecast: Dictionary = career.forecast(choice)
	var briefing := career.situation_briefing()
	check(career.encode() == preserved, "campaign forecast and narrative are read-only")
	career.shocks[200].funding_need_pct_initial_gdp = 99.0
	check(career.forecast(choice) == forecast and career.situation_briefing() == briefing, "campaign preview and narrative cannot inspect an unknown future crisis")
	check(career.restore(bytes_to_var(preserved)).ok and career.encode() == preserved, "forecast inspection and future-input fixture leave no persistent mutation")
	var old_model: Dictionary = career.payload()
	old_model.model_digest = "5736a1b7d39bebe2ddc436a4b92d0a8762afe03e1c5e5001ed4fe2a1c3be2edd"
	check(not career.restore(old_model).ok and career.encode() == preserved, "previous model save is rejected without replacing the active campaign")
	var funding_quarter := 0
	while funding_quarter < Career.MAX_QUARTERS and career.shocks[funding_quarter].get("funding_need_pct_initial_gdp", 0.0) <= 0.1:
		check(career.advance(career.model.benchmark_policy(career.state, career.params, "feedback")).ok, "actual prefix advances toward a recurring funding episode")
		funding_quarter += 1
	check(funding_quarter < Career.MAX_QUARTERS, "actual career contains a recurring funding episode")
	if funding_quarter == Career.MAX_QUARTERS:
		return
	var assisted := Career.new()
	check(assisted.restore(bytes_to_var(career.encode())).ok, "late funding prefix exactly replays")
	choice = career.model.benchmark_policy(career.state, career.params, "hold")
	check(career.situation_briefing().contains("New funding pressure"), "late campaign crisis is disclosed only at its current meeting")
	check(career.advance(choice).ok, "unassisted late funding decision advances")
	choice.liquidity_request_pct_initial_gdp = 5.0
	check(assisted.advance(choice).ok, "paired late lending decision advances")
	check(assisted.state.uncovered_funding_pct_initial_gdp < career.state.uncovered_funding_pct_initial_gdp and assisted.state.credit_spread_pct < career.state.credit_spread_pct, "late eligible lending lowers uncovered need and the funding spread")
	check(assisted.state.solvency_risk_wedge_pct == career.state.solvency_risk_wedge_pct and assisted.state.solvency_risk_wedge_pct > 0.0, "lending cannot erase late credit impairment")
	for kind in ["hold", "feedback"]:
		var completed := Career.new()
		completed.start("mixed_crises", 417)
		for quarter in range(Career.MAX_QUARTERS):
			check(completed.advance(completed.model.benchmark_policy(completed.state, completed.params, kind)).ok, "full campaign advances without a forced reset")
		var replay := Career.new()
		check(replay.restore(bytes_to_var(completed.encode())).ok and replay.state == completed.state and replay.history == completed.history and replay.shocks == completed.shocks and replay.decisions == completed.decisions, "complete campaign exactly replays every state and input")
		preserved = completed.encode()
		check(not completed.advance(choice).ok and completed.encode() == preserved, "campaign terminal rejection is pure")

func check_situation_briefing() -> void:
	var untreated := Career.new()
	untreated.start("funding_stress", 41)
	check(untreated.has_method("situation_briefing"), "career exposes current-only market/public/funding interpretation")
	if not untreated.has_method("situation_briefing"):
		return
	var preserved := untreated.encode()
	var initial_state: Dictionary = untreated.state.duplicate(true)
	var initial_history: Array = untreated.history.duplicate(true)
	var initial: String = untreated.call("situation_briefing")
	check(initial.contains("MARKETS /") and initial.contains("PUBLIC /") and initial.contains("FUNDING /"), "situation distinguishes markets, households and funding")
	check(untreated.encode() == preserved and untreated.state == initial_state and untreated.history == initial_history, "reading interpretation cannot mutate live state, history or the save")
	untreated.shocks[200].funding_need_pct_initial_gdp = 9.0
	check(untreated.call("situation_briefing") == initial, "interpretation cannot inspect unknown future events")
	untreated.restore(bytes_to_var(preserved))
	for q in range(4):
		untreated.advance(untreated.model.benchmark_policy(untreated.state, untreated.params, "hold"))
	check(untreated.call("situation_briefing").contains("New funding pressure"), "first disclosed large need begins the funding storyline")
	var assisted := Career.new()
	check(assisted.restore(bytes_to_var(untreated.encode())).ok, "paired funding career replays actual decisions")
	var policy: Dictionary = untreated.model.benchmark_policy(untreated.state, untreated.params, "hold")
	untreated.advance(policy)
	policy.liquidity_request_pct_initial_gdp = 5.0
	assisted.advance(policy)
	var no_lending: String = untreated.call("situation_briefing")
	var lending: String = assisted.call("situation_briefing")
	check(no_lending.contains("Funding pressure continues") and lending.contains("Funding pressure continues"), "recurring disclosed needs retain the crisis rather than restarting it")
	check(no_lending != lending and lending.contains("uncovered %.2f" % assisted.state.uncovered_funding_pct_initial_gdp), "actual lending and collateral constraints change the funding interpretation")
	for campaign in [untreated, assisted]:
		campaign.advance(campaign.model.benchmark_policy(campaign.state, campaign.params, "hold"))
		var aftermath: String = campaign.call("situation_briefing")
		check(aftermath.contains("Funding aftermath") and aftermath.contains("credit impairment"), "credit impairment survives the end of large scheduled needs")
		var replay := Career.new()
		check(replay.restore(bytes_to_var(campaign.encode())).ok and replay.call("situation_briefing") == aftermath, "story continuity derives losslessly from replay without new save fields")
		var encoded: PackedByteArray = campaign.encode()
		var state_before: Dictionary = campaign.state.duplicate(true)
		var history_before: Array = campaign.history.duplicate(true)
		campaign.forecast(campaign.model.benchmark_policy(campaign.state, campaign.params, "feedback"))
		check(campaign.encode() == encoded and campaign.state == state_before and campaign.history == history_before and campaign.call("situation_briefing") == aftermath, "preview cannot mutate live state, history or the storyline")
	var recovery := Career.new()
	recovery.start("base", 1)
	var initial_recovery: Dictionary = recovery.model.initial_state(recovery.params, {"public_hardship_memory": 10.0, "public_support": 35.0})
	check(initial_recovery.ok, "public recovery fixture uses validated model initialization")
	if initial_recovery.ok:
		recovery.state = initial_recovery.state
		recovery.history = [recovery.state.duplicate(true)]
		recovery.shocks[0] = {}
		recovery.advance(recovery.model.benchmark_policy(recovery.state, recovery.params, "hold"))
		check(recovery.call("situation_briefing").contains("Hardship memory is easing"), "forgiveness follows actual decaying hardship memory")
