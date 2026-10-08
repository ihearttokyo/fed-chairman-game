extends SceneTree
const Career = preload("res://play/career.gd")
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--current-signals-only"):
		check_current_signals()
		if failures == 0:
			print("PASS: current refinancing/impairment distinction, settlement constraints and read-only causality")
		quit(1 if failures else 0)
		return
	check_recurring_crises()
	if OS.get_cmdline_user_args().has("--campaign-only"):
		if failures == 0:
			print("PASS: recurring offline crises, bounded variety, exact replay and current-only forecasts")
		quit(1 if failures else 0)
		return
	check_situation_briefing()
	check_current_signals()
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

func check_current_signals() -> void:
	var career := Career.new()
	check(career.start("base", 17).ok, "current-signal fixture starts without new scenario IDs")
	career.shocks[0] = {"funding_need_pct_initial_gdp": 2.0, "eligible_collateral_pct_initial_gdp": 4.0, "liquidity_eligibility_pct": 100.0}
	var choice: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold")
	choice.liquidity_request_pct_initial_gdp = 2.0
	check(career.advance(choice).ok and career.state.outstanding_liquidity_pct_initial_gdp == 2.0, "refinancing fixture creates actual short-loan principal")
	career.shocks[1] = {"refinancing_need_pct_initial_gdp": 6.0, "eligible_collateral_pct_initial_gdp": 2.0, "collateral_haircut_pct": 50.0, "liquidity_eligibility_pct": 50.0}
	var preserved := career.encode()
	var state_bytes := var_to_bytes(career.state)
	var history_bytes := var_to_bytes(career.history)
	var dispatch := career.situation_briefing()
	check(career.encode() == preserved and var_to_bytes(career.state) == state_bytes and var_to_bytes(career.history) == history_bytes, "refinancing dispatch preserves career, state and history bytes")
	check(dispatch.contains("Refinancing pressure") and not dispatch.contains("New funding pressure") and not dispatch.contains("No major new funding pressure"), "refinancing-only current need is distinct from new funding and quiet conditions")
	choice = career.model.benchmark_policy(career.state, career.params, "hold")
	choice.liquidity_request_pct_initial_gdp = 5.0
	var preview: Dictionary = career.forecast(choice)
	check(career.encode() == preserved and var_to_bytes(career.state) == state_bytes and var_to_bytes(career.history) == history_bytes, "refinancing preview preserves career, state and history bytes")
	check(preview.ok, "current refinancing preview is valid")
	if preview.ok:
		var first: Dictionary = preview.states[0]
		check(first.refinancing_request_pct_initial_gdp == 6.0 and first.liquidity_repayment_pct_initial_gdp == 2.0 and first.refinancing_need_pct_initial_gdp == 2.0, "requested refinancing cannot exceed actual maturing principal")
		check(first.eligible_local_need_pct_initial_gdp == 1.0 and first.lending_collateral_capacity_pct_initial_gdp == 0.5 and first.liquidity_refinancing_applied_pct_initial_gdp == 0.5 and first.liquidity_new_need_applied_pct_initial_gdp == 0.0, "haircut and eligibility constrain refinancing separately from new funding")
	career.shocks[200] = {"funding_need_pct_initial_gdp": 9.0, "refinancing_need_pct_initial_gdp": 9.0, "solvency_risk_innovation_pct": 5.0, "collateral_haircut_pct": 99.0, "liquidity_eligibility_pct": 0.0}
	preserved = career.encode()
	check(career.situation_briefing() == dispatch and career.encode() == preserved and var_to_bytes(career.state) == state_bytes and var_to_bytes(career.history) == history_bytes, "future funding/refinancing/impairment changes cannot affect or be mutated by current dispatch")
	check(career.forecast(choice) == preview and career.encode() == preserved and var_to_bytes(career.state) == state_bytes and var_to_bytes(career.history) == history_bytes, "future funding/refinancing/impairment changes cannot affect preview or current state")
	check(career.start("base", 17).ok, "new impairment fixture starts through the unchanged entry point")
	career.shocks[0] = {"solvency_risk_innovation_pct": 0.7}
	preserved = career.encode()
	state_bytes = var_to_bytes(career.state)
	history_bytes = var_to_bytes(career.history)
	dispatch = career.situation_briefing()
	check(career.encode() == preserved and var_to_bytes(career.state) == state_bytes and var_to_bytes(career.history) == history_bytes, "first-quarter impairment dispatch preserves every career/state/history byte")
	check(dispatch.contains("New credit impairment") and not dispatch.contains("Funding aftermath"), "first-quarter new impairment impulse is distinct from prior settled impairment")
	choice = career.model.benchmark_policy(career.state, career.params, "hold")
	preview = career.forecast(choice)
	check(preview.ok and preview.states[0].solvency_risk_wedge_pct == 0.7 and preview.states[0].capital_other_pct_initial_gdp == career.state.capital_other_pct_initial_gdp, "impairment impulse is a pp spread proxy, not a booked dollar capital loss")
	check(career.encode() == preserved and var_to_bytes(career.state) == state_bytes and var_to_bytes(career.history) == history_bytes, "first-quarter impairment preview preserves every career/state/history byte")
	check(career.advance(choice).ok, "new impairment settles only through adoption")
	career.shocks[1] = {}
	preserved = career.encode()
	state_bytes = var_to_bytes(career.state)
	history_bytes = var_to_bytes(career.history)
	dispatch = career.situation_briefing()
	check(dispatch.contains("credit impairment remains") and not dispatch.contains("New credit impairment"), "settled impairment remains distinct after its new impulse ends")
	check(career.encode() == preserved and var_to_bytes(career.state) == state_bytes and var_to_bytes(career.history) == history_bytes, "settled impairment dispatch preserves every career/state/history byte")
	check(career.start("base", 17).ok, "zero-maturity boundary uses an ordinary fresh career")
	career.shocks[0] = {"refinancing_need_pct_initial_gdp": 6.0, "eligible_collateral_pct_initial_gdp": 2.0, "liquidity_eligibility_pct": 100.0}
	preserved = career.encode()
	state_bytes = var_to_bytes(career.state)
	history_bytes = var_to_bytes(career.history)
	dispatch = career.situation_briefing()
	check(not dispatch.contains("Refinancing pressure"), "raw refinancing request without maturing principal is not current refinancing pressure")
	check(career.encode() == preserved and var_to_bytes(career.state) == state_bytes and var_to_bytes(career.history) == history_bytes, "zero-maturity readout preserves every career/state/history byte")

func check_recurring_crises() -> void:
	var career := Career.new()
	check(career.cases.has("mixed_crises"), "recurring crisis campaign is selectable")
	# This candidate also proves the generator behavior before the selector exists.
	var scenario: Dictionary = career.cases.get("mixed_crises", {"id": "mixed_crises", "initial": {}, "events": []})
	var original: Dictionary = career.cases.duplicate(true)
	var parameters: Dictionary = career.params.duplicate(true)
	var signatures := {}
	for seed_number in [0, 1, 17, 41, 417, -2147483647, 2147483647, -9223372036854775807, 9223372036854775807]:
		var generated: Dictionary = career.model.seeded_campaign(seed_number, scenario, 240)
		check(generated.ok, "curated campaign generation succeeds")
		var path: Array = generated.shocks
		var background: Array = career.model.seeded_shock_path(seed_number, {"id":"base","events":[]}, 240)
		check(path == career.model.seeded_shock_path(seed_number, scenario, 240), "same seed exactly reproduces all campaign shocks")
		check(path.slice(0, 48) == career.model.seeded_shock_path(seed_number, scenario, 48), "short campaign is an exact horizon prefix")
		check(path == career.model.seeded_shock_path(seed_number, scenario, 1000).slice(0, 240), "exporter horizon preserves the campaign prefix")
		var occupied := {}
		for episode in generated.episodes:
			for q in range(int(episode.quarter_index), mini(240, int(episode.quarter_index + episode.duration_quarters))):
				occupied[q] = true
		for q in range(path.size()):
			check(career.model._validate_shocks(path[q]).ok, "curated profile plus background stays within native shock domains")
			if not occupied.has(q):
				check(path[q] == background[q], "non-episode quarter retains the exact background path")
		check(generated.episodes.size() >= 11 and generated.episodes[-1].quarter_index > 200, "named episodes continue through the late career")
		signatures[var_to_bytes(path).hex_encode().sha256_text()] = true
	check(signatures.size() >= 8, "seeds materially vary episode timing and order")
	check(career.cases == original and career.params == parameters, "campaign generation cannot mutate concepts or parameters")
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
	while funding_quarter < Career.MAX_QUARTERS and (career.shocks[funding_quarter].get("funding_need_pct_initial_gdp", 0.0) <= 0.1 or career.shocks[funding_quarter].get("eligible_collateral_pct_initial_gdp", 0.0) <= 0.0 or career.shocks[funding_quarter].get("liquidity_eligibility_pct", 0.0) <= 0.0):
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
	check(assisted.state.solvency_risk_wedge_pct == career.state.solvency_risk_wedge_pct, "lending neither creates nor erases existing credit impairment")
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
