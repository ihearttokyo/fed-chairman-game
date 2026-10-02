extends SceneTree
const Career = preload("res://play/career.gd")
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
func _initialize() -> void:
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
	clean.decisions[0].policy_rate_request_pct = -1
	check(not loaded.restore(clean).ok, "invalid decision rejected during replay")
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
