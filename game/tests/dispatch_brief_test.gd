extends SceneTree

const Brief = preload("res://play/dispatch_brief.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var state := {"output_gap_pct": -1.25, "expected_long_inflation_pct": 2.4, "public_hardship_memory": 1.25, "guidance_active": false, "guidance_followthrough_score": 0.875, "outstanding_liquidity_pct_initial_gdp": 0.0, "solvency_risk_wedge_pct": 0.0, "deferred_demand_pct": 0.0, "four_quarter_inflation_pct": 4.5, "unemployment_rate_pct": 5.0, "credibility": 0.5, "public_support": 60.0}
	var current := {"demand_shock_pct": 0.2, "supply_innovation_pct": -0.1, "future": {"title": "NEVER DISPLAY FUTURE"}}
	var previous := {"guidance_active": false, "solvency_risk_wedge_pct": 999.0}
	var episode := {"title": "Current event — exact", "policy_dilemma": "A current dilemma.\nA complete second paragraph — retained exactly.", "future_title": "NEVER DISPLAY FUTURE"}
	var frozen := var_to_bytes([state, current, previous, episode])
	var result := Brief.present(state, current, previous, 2.0, episode)
	check(result.ok and result.summary.contains("Demand impulse +0.20 pp · Supply innovation -0.10 pp · Output gap -1.25%"), "current shock impulses and observed gap retain their signs and units")
	check(result.summary.contains("Long expectations 2.40% · Hardship memory 1.25 index"), "expectations and hardship use concise labeled scalar units")
	check(result.event_title == episode.title and result.event_detail == episode.policy_dilemma, "supplied current title and full multiline dilemma are returned exactly")
	check(not result.summary.contains(episode.title) and not result.summary.contains("NEVER DISPLAY FUTURE"), "event copy is separate and unrelated supplied metadata is never interpreted")
	check(result.summary.split("\n").size() == 2 and result.summary.length() < 200, "quiet dispatch is two concise lines, not a word wall")
	for forbidden in ["Inflation", "Unemployment", "Credibility", "Support", "Funding", "Impairment", "Credit-risk", "Backlog", "Promise"]:
		check(not result.summary.contains(forbidden), "quiet summary omits duplicate or irrelevant " + forbidden)
	check(result.summary.count("Output gap") == 1 and result.summary.count("Hardship memory") == 1, "essential quantities are not repeated")
	var none := Brief.present(state, current, previous, 2.0)
	check(none.ok and none.event_title.is_empty() and none.event_detail.is_empty(), "no supplied current episode means no invented event")
	var promised := state.duplicate(true)
	var active_previous := previous.duplicate(true)
	active_previous.guidance_active = true
	var evaluated := Brief.present(promised, current, active_previous, 2.0)
	check(evaluated.summary.contains("Promise 87.5/100") and not evaluated.summary.contains("pending"), "prior active promise displays the completed current-state evaluation")
	promised.guidance_active = true
	var awaiting := Brief.present(promised, current, previous, 2.0)
	check(awaiting.summary.contains("Promise pending") and not awaiting.summary.contains("87.5/100"), "first active announcement awaits evaluation instead of claiming a prior score")
	var stressed := state.duplicate(true)
	stressed.outstanding_liquidity_pct_initial_gdp = 3.0
	stressed.solvency_risk_wedge_pct = 0.3
	stressed.deferred_demand_pct = -0.7
	var funding := current.duplicate(true)
	funding.merge({"funding_need_pct_initial_gdp": 2.0, "refinancing_need_pct_initial_gdp": 6.0, "eligible_collateral_pct_initial_gdp": 10.0, "collateral_haircut_pct": 20.0, "liquidity_eligibility_pct": 50.0, "solvency_risk_innovation_pct": 0.12, "credit_risk_innovation_pct": -0.2})
	var funding_frozen := var_to_bytes([stressed, funding])
	var stress := Brief.present(stressed, funding, previous, 2.0)
	check(stress.ok and stress.summary.contains("Funding (% current GDP): new 1.00 · refi need 1.50 · eligible need 1.25 · secured value 2.00"), "true refinancing caps request at outstanding principal before eligibility and current-GDP conversion")
	check(stress.summary.contains("Impairment pulse +0.12 pp · Prior wedge 0.30 pp (spread proxy)") and not stress.summary.contains("999"), "impairment combines current pulse with this meeting's carried wedge, not the older history wedge")
	check(stress.summary.contains("Credit-risk pulse -0.20 pp") and stress.summary.contains("Backlog -0.70% potential"), "negative credit-risk news and signed current backlog remain visible")
	check(stress.summary.split("\n").size() <= 6 and stress.summary.length() < 550, "even a funding/impairment dispatch remains bounded concise copy")
	var initial_gdp := Brief.present(stressed, funding, previous, 1.0)
	check(initial_gdp.summary.contains("new 2.00 · refi need 3.00 · eligible need 2.50 · secured value 4.00"), "every displayed funding amount uses the same supplied current/initial GDP ratio")
	var no_eligibility := funding.duplicate(true)
	no_eligibility.liquidity_eligibility_pct = 0.0
	var ineligible := Brief.present(stressed, no_eligibility, previous, 2.0)
	check(ineligible.summary.contains("new 1.00 · refi need 1.50 · eligible need 0.00 · secured value 0.00"), "zero eligibility removes eligible demand and collateral capacity without hiding true need")
	var full_eligibility := funding.duplicate(true)
	full_eligibility.liquidity_eligibility_pct = 100.0
	full_eligibility.collateral_haircut_pct = 100.0
	check(Brief.present(stressed, full_eligibility, previous, 2.0).summary.contains("eligible need 2.50 · secured value 0.00"), "a full haircut leaves eligible demand but no secured value")
	var no_principal := state.duplicate(true)
	check(Brief.present(no_principal, funding, previous, 2.0).summary.contains("refi need 0.00 · eligible need 0.50"), "refinancing requests alone cannot create maturing principal")
	var tiny := {"funding_need_pct_initial_gdp": 0.000001, "eligible_collateral_pct_initial_gdp": 0.001, "liquidity_eligibility_pct": 100.0}
	var precise := Brief.present(state, tiny, previous, 1.0)
	check(precise.summary.contains("new <0.0001") and precise.summary.contains("eligible need <0.0001") and precise.summary.contains("secured value 0.0010"), "small positive funding uses existing precision rules rather than false zero or scientific notation")
	for pulse in [0.2, -0.2, 0.00001, -0.00001]:
		var credit := Brief.present(state, {"credit_risk_innovation_pct": pulse}, previous, 1.0)
		var display: String = {0.2: "+0.20", -0.2: "-0.20", 0.00001: "up <0.01", -0.00001: "down <0.01"}[pulse]
		check(credit.summary.contains("Credit-risk pulse " + display + " pp"), "current credit-risk pulse preserves signed small/large news")
	for trigger in ["new", "refi", "outstanding", "collateral"]:
		var trigger_state := state.duplicate(true)
		var trigger_current := {}
		if trigger == "outstanding":
			trigger_state.outstanding_liquidity_pct_initial_gdp = 0.1
		else:
			trigger_current[{"new": "funding_need_pct_initial_gdp", "refi": "refinancing_need_pct_initial_gdp", "collateral": "eligible_collateral_pct_initial_gdp"}[trigger]] = 0.1
		check(Brief.present(trigger_state, trigger_current, previous, 1.0).summary.contains("Funding (% current GDP)"), "nonzero %s independently retains essential funding context" % trigger)
	for bad_gdp in [0.0, -1.0, NAN, INF]:
		var invalid := Brief.present(stressed, funding, previous, bad_gdp, episode)
		check(not invalid.ok and invalid.summary.is_empty() and invalid.event_title.is_empty() and invalid.event_detail.is_empty(), "invalid GDP fails closed without misleading converted amounts or stale event copy")
	var malformed := funding.duplicate(true)
	malformed.liquidity_eligibility_pct = 101.0
	check(not Brief.present(stressed, malformed, previous, 1.0).ok, "out-of-domain eligibility cannot imply invented capacity")
	malformed = funding.duplicate(true)
	malformed.credit_risk_innovation_pct = NAN
	check(not Brief.present(stressed, malformed, previous, 1.0).ok and not Brief.present({}, {}, {}, 1.0).ok, "nonfinite or missing essential observations fail safely")
	check(var_to_bytes([state, current, previous, episode]) == frozen and var_to_bytes([stressed, funding]) == funding_frozen, "all formatting leaves supplied canonical inputs byte-for-byte unchanged")
	state.make_read_only()
	current.make_read_only()
	previous.make_read_only()
	episode.make_read_only()
	check(Brief.present(state, current, previous, 2.0, episode) == result, "read-only canonical inputs reproduce the same deterministic output")
	if failures == 0:
		print("PASS: dispatch brief %d checks; pure current-only concise copy, true refinancing, eligibility, units and precision" % checks)
	quit(1 if failures else 0)
