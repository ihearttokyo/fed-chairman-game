extends SceneTree

const Economy = preload("res://model/economy.gd")
const Career = preload("res://play/career.gd")
var failures: Array[String] = []
var model := Economy.new()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _initialize() -> void:
	for method in ["load_shock_catalogue", "validate_shock_catalogue", "seeded_campaign"]:
		check(model.has_method(method), "curated campaign requires %s" % method)
	if failures.is_empty():
		_test_catalogue()
		_test_schedule()
		_test_conditional_relief()
		_test_career()
	for failure in failures:
		printerr("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: 150 concepts, exact top50, seeded profiles, conditional triggers, current-only attribution and replay")
	quit(0 if failures.is_empty() else 1)

func _test_catalogue() -> void:
	var loaded: Dictionary = model.call("load_shock_catalogue")
	check(loaded.ok, "resident catalogue loads")
	if not loaded.ok:
		return
	check(loaded.records.size() == 150 and loaded.accepted.size() == 50, "only the top50 of150 are executable")
	for i in range(50):
		check(loaded.accepted[i] == loaded.records[i] and loaded.accepted[i].rank == i + 1, "accepted prefix retains strict reviewed rank")
	for defect in ["count", "id", "rank", "accepted", "score", "order", "title", "profile", "duration", "funding", "url", "category"]:
		var bad: Array = loaded.records.duplicate(true)
		match defect:
			"count": bad.pop_back()
			"id": bad[1].id = bad[0].id
			"rank": bad[0].rank = 1.5
			"accepted": bad[50].accepted = true
			"score": bad[0].total -= 1
			"order": bad[0].policy_tradeoff = 0; bad[0].total -= 5
			"title": bad[0].title = ""
			"profile": bad[0].shock_profile[0].supply_innovation_pct = NAN
			"duration": bad[0].duration_quarters = 2
			"funding": bad[7].shock_profile[0].erase("liquidity_eligibility_pct")
			"url": bad[0].source_urls = ["http://example.com"]
			"category": bad[0].category = "invented"
		check(not model.call("validate_shock_catalogue", bad).ok, "malformed catalogue rejects %s" % defect)

func _test_schedule() -> void:
	var cases: Dictionary = model.load_scenarios().scenarios
	var original := cases.duplicate(true)
	var previous_paths := {
		"base":"8581f63f489067234636bb925b3a59a0524fb3ce94b10d2822984c973a8dc9ba",
		"demand_boom":"1e84402f5fc461fe8d8db99141ae0865339f258be15abdd73dea7a7b9e5225e0",
		"supply_shock":"5c8bcda2d224cb9d1ff7361a8fe4a9ac066cafbf9d603bac5e4c3fc481792d39",
		"funding_stress":"8a6fbf976ac45747c31f1719c9ddfbb95b0fc93646e8973c7be0d5774b0936be",
		"unanchored_inflation":"137d4da346fb11e1a3e66b39f2925456f735640b31c651c3510138f8219d7bf0",
		"lower_bound_slump":"efcc593a7c955294b487029f7d5fdc29ef3e8d1773682abcf4debf830018a329",
	}
	for id in previous_paths:
		check(var_to_bytes(model.seeded_shock_path(417, cases[id], 240)).hex_encode().sha256_text() == previous_paths[id], "first six scenario paths remain byte-exact")
	var reached := {}
	for seed in [0, 1, 417, -2147483647, 2147483647, -9223372036854775807, 9223372036854775807]:
		var full: Dictionary = model.call("seeded_campaign", seed, cases.mixed_crises, 1000)
		check(full.ok and full.shocks.size() == 1000, "long campaign generates valid input and named context")
		if not full.ok:
			continue
		var short: Dictionary = model.call("seeded_campaign", seed, cases.mixed_crises, 48)
		check(short.shocks == full.shocks.slice(0, 48), "partial multiquarter events preserve exact horizon prefix")
		check(short == model.call("seeded_campaign", seed, cases.mixed_crises, 48), "same seed reproduces both numeric path and event context")
		var prior_end := -1
		var prior_onset := -1
		var independent := {}
		for episode in full.episodes:
			check(episode.quarter_index > prior_end, "episodes never overlap")
			prior_end = episode.quarter_index + episode.duration_quarters - 1
			reached[episode.id] = true
			if episode.trigger_id.is_empty():
				check(episode.quarter_index >= 12 and episode.quarter_index <= 20 if prior_onset < 0 else episode.quarter_index - prior_onset >= 12 and episode.quarter_index - prior_onset <= 20, "ordinary onsets retain disclosed spacing")
				if independent.size() == 48:
					independent.clear()
				check(not independent.has(episode.id), "48 independent concepts occur once before refill")
				independent[episode.id] = true
				prior_onset = episode.quarter_index
			else:
				check(episode.id in ["private_bank_recapitalization", "stable_private_deposits_return"], "only conditional finance uses a trigger")
				var trigger: Dictionary = full.episodes[full.episodes.find(episode) - 1]
				check(trigger.id == episode.trigger_id and episode.quarter_index == trigger.quarter_index + trigger.duration_quarters + 1, "conditional relief follows actual prior bank stress and one quiet quarter")
				check(trigger.id in ["office_property_credit_losses", "mortgage_lien_documentation_failure"] if episode.id == "private_bank_recapitalization" else trigger.id in ["sound_bank_uninsured_run", "bank_payment_float_failure", "bank_dollar_rollover_squeeze"], "nonbank events cannot trigger bank normalization")
		for shock in full.shocks:
			check(model._validate_shocks(shock).ok, "realized profile plus background stays in native shock domains")
	check(reached.size() == 50, "all accepted concepts are reachable; none of the100 excluded concepts runs")
	check(cases == original, "generation preserves source scenarios")
	seed(417)
	var global_first := randi()
	var global_second := randi()
	seed(417)
	check(randi() == global_first, "global random baseline is reproducible")
	model.call("seeded_campaign", 417, cases.mixed_crises, 240)
	check(randi() == global_second, "campaign never consumes global randomness")

func _test_career() -> void:
	var career := Career.new()
	check(career.start("mixed_crises", 417).ok, "curated career starts")
	var preserved := career.encode()
	var policy: Dictionary = career.model.benchmark_policy(career.state, career.params)
	var preview := career.forecast(policy)
	var briefing := career.situation_briefing()
	career.shocks[200].demand_shock_pct = 9.0
	check(career.forecast(policy) == preview and career.situation_briefing() == briefing, "future changes cannot leak through forecast or event context")
	check(career.restore(bytes_to_var(preserved)).ok, "realized input and context restore losslessly")
	var malformed: Dictionary = career.payload()
	malformed.episodes[0].title = "Different event"
	check(not career.restore(malformed).ok and career.encode() == preserved, "altered event identity rejects before replacing the active career")
	var named := 0
	for q in range(240):
		var text := career.situation_briefing()
		if text.contains("EXOGENOUS /"):
			named += 1
			check(not text.contains("shock_profile") and not text.contains("next episode"), "dispatch supplies current dilemma, not its hidden future schedule")
			if named == 1:
				var before_edit := career.encode()
				career.shocks[q].credit_risk_innovation_pct = career.shocks[q].get("credit_risk_innovation_pct", 0.0) + 1.0
				check(career.current_shock_episode().is_empty(), "unexpected added current input suppresses unsupported event attribution")
				check(career.restore(bytes_to_var(before_edit)).ok, "audit-edited attribution fixture restores without save writes")
		check(career.advance(career.model.benchmark_policy(career.state, career.params)).ok, "curated full career advances without resets")
	check(named > 20, "actual multiquarter named episodes are playable throughout a career")
	var replay := Career.new()
	check(replay.restore(bytes_to_var(career.encode())).ok and replay.history == career.history and replay.situation_briefing() == career.situation_briefing(), "complete curated state and context replay exactly")

func _test_conditional_relief() -> void:
	var records: Array = model.load_shock_catalogue().accepted
	var concepts := {}
	for record in records:
		concepts[record.id] = record
	var params: Dictionary = model.load_parameters().values
	for pair in [["office_property_credit_losses","private_bank_recapitalization"], ["sound_bank_uninsured_run","stable_private_deposits_return"]]:
		var state: Dictionary = model.initial_state(params).state
		var policy: Dictionary = model.benchmark_policy(state, params, "hold")
		policy.liquidity_request_pct_initial_gdp = 5.0
		for pulse in concepts[pair[0]].shock_profile:
			state = model.step(state, policy, pulse, params).state
		policy.liquidity_request_pct_initial_gdp = 0.0
		var prior_loans: float = state.outstanding_liquidity_pct_initial_gdp
		var quiet := model.step(state, policy, {}, params)
		check(quiet.ok and quiet.state.liquidity_repayment_pct_initial_gdp == prior_loans and quiet.state.outstanding_liquidity_pct_initial_gdp == 0.0, "quiet interval records full short-loan maturity, not shock-driven forgiveness")
		if pair[1] == "stable_private_deposits_return":
			check(prior_loans > 0.0, "funding normalization fixture really begins with funded principal")
		state = quiet.state
		var continuing := state.duplicate(true)
		var normalized := state.duplicate(true)
		var profile: Array = concepts[pair[1]].shock_profile
		for pulse in profile:
			var repaired := model.step(normalized, policy, pulse, params)
			var stressed := model.step(continuing, policy, profile[0], params)
			check(repaired.ok and stressed.ok, "conditional relief and matched continuing stress remain valid")
			if not repaired.ok or not stressed.ok:
				return
			normalized = repaired.state
			continuing = stressed.state
		check(normalized.credit_spread_pct < continuing.credit_spread_pct, "normalization relieves spreads relative to continuing stress, not an empty-shock baseline")
		check(normalized.solvency_risk_wedge_pct == continuing.solvency_risk_wedge_pct, "private-finance profile never subtracts accumulated solvency impairment")
		if pair[1] == "private_bank_recapitalization":
			check(normalized.solvency_risk_wedge_pct > 0.0, "old bank losses remain after reduced new credit pressure")
		else:
			check(normalized.outstanding_liquidity_pct_initial_gdp == 0.0 and continuing.outstanding_liquidity_pct_initial_gdp == 0.0, "private normalization cannot change recorded repayment or manufacture new loan exposure")
