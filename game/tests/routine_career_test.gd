extends SceneTree

# Exploratory integration coverage, separate from the frozen D474 pilot.
const Explanation = preload("res://play/transition_explanation.gd")
const CASES := ["base", "demand_boom", "funding_stress", "lower_bound_slump", "mixed_crises", "policy_career", "supply_shock", "unanchored_inflation"]
const SEEDS := [1, 17]
const EXPECTED_STEPS := 11520 # 16 pairs × (480 actual + 240 replay).

class CountedEconomy:
	extends "res://model/economy.gd"
	static var attempts := 0
	static var confirmed := 0
	static var rejected := 0
	static var unexpected := 0
	static var phase := "observer"
	static var actual := 0
	static var replay := 0
	func step(state: Dictionary, policy: Dictionary, shocks: Dictionary, params: Dictionary) -> Dictionary:
		attempts += 1
		if phase == "actual":
			actual += 1
		elif phase == "replay":
			replay += 1
		else:
			unexpected += 1
		var before := var_to_bytes(state)
		var result := super.step(state, policy, shocks, params)
		if result.ok:
			confirmed += 1
		else:
			rejected += 1
		if before != var_to_bytes(state):
			unexpected += 1
		return result

class CountedCareer:
	extends "res://play/career.gd"
	func _init() -> void:
		model = CountedEconomy.new()

class CountedFollowUp:
	extends "res://play/routine_follow_up.gd"
	func _init() -> void:
		_model = CountedEconomy.new()

var checks := 0
var failures := 0
var rows: Array = []

func require(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
	return condition

func _initialize() -> void:
	var inventory := CountedCareer.new().cases.keys()
	inventory.sort()
	if require(inventory == CASES, "cover every shipped starting scenario, not a silently reduced subset"):
		for case_id in CASES:
			for seed_number in SEEDS:
				if not run_pair(case_id, seed_number):
					finish()
					return
	require(rows.size() == 16 and CountedEconomy.attempts == EXPECTED_STEPS and CountedEconomy.confirmed == EXPECTED_STEPS and CountedEconomy.actual == 7680 and CountedEconomy.replay == 3840 and CountedEconomy.rejected == 0 and CountedEconomy.unexpected == 0, "complete exact native ledger; no rejected, unknown or hidden transitions")
	finish()

func finish() -> void:
	print("ROUTINE_CAREER_REPORT: ", JSON.stringify({"checks": checks, "failures": failures, "attempts": CountedEconomy.attempts, "confirmed": CountedEconomy.confirmed, "actual": CountedEconomy.actual, "replay": CountedEconomy.replay, "rejected": CountedEconomy.rejected, "unknown": CountedEconomy.attempts - CountedEconomy.confirmed - CountedEconomy.rejected, "unexpected": CountedEconomy.unexpected, "rows": rows, "scope": "fixed development seeds; not held-out, human fun or Main input timing evidence"}))
	if failures == 0:
		print("PASS: all eight starting scenarios / two seeds / 240 quarters; routine parity and full Career replay")
	quit(0 if failures == 0 else 1)

# Independent actor: detached current data only; no Career or future tape.
func ordinary_policy(state: Dictionary, shock: Dictionary, params: Dictionary) -> Dictionary:
	var rate: float = state.r_star_pct + state.expected_short_inflation_pct + params.policy_inflation_response * (state.four_quarter_inflation_pct - params.inflation_target_pct) + params.policy_output_gap_response * state.output_gap_pct
	rate = roundf(rate / params.minimum_rate_increment_pct) * params.minimum_rate_increment_pct
	return {"policy_rate_request_pct": rate, "guidance_rate_pct": rate, "guidance_inflation_sensitivity": params.policy_inflation_response, "guidance_output_gap_sensitivity": params.policy_output_gap_response, "asset_flow_request_pct_initial_gdp": 0.0, "liquidity_request_pct_initial_gdp": shock.get("funding_need_pct_initial_gdp", 0.0) + minf(shock.get("refinancing_need_pct_initial_gdp", 0.0), state.outstanding_liquidity_pct_initial_gdp), "reinvest_principal": true, "maintain_ample_reserves": true, "sterilize_purchases": false}

func observe(career: RefCounted) -> Dictionary:
	var state: Dictionary = career.state.duplicate(true)
	for value in state.values():
		if value is Array:
			value.make_read_only()
	var shock: Dictionary = career.current_briefing()
	var phase: Dictionary = career.current_shock_episode()
	var params: Dictionary = career.params.duplicate(true)
	for dictionary in [state, shock, phase, params]:
		dictionary.make_read_only()
	return {"state": state, "shock": shock, "phase": phase, "params": params, "completed": career.decisions.size(), "history": career.history.size()}

func explain_segment(career: RefCounted, first: int, last: int) -> bool:
	var attempts := CountedEconomy.attempts
	var result := Explanation.segment(career.history.slice(first, last + 1), career.shocks.slice(first, last), 0, last - first, career.params)
	return require(last > first and last - first <= 4 and result.ok and CountedEconomy.attempts == attempts, "completed 1–4-quarter segment explains without native transitions")

func advance_once(career: RefCounted, policy: Dictionary) -> bool:
	var attempts := CountedEconomy.attempts
	var q: int = career.decisions.size()
	CountedEconomy.phase = "actual"
	var result: Dictionary = career.advance(policy)
	CountedEconomy.phase = "observer"
	return require(result.ok and CountedEconomy.attempts == attempts + 1 and career.decisions.size() == q + 1 and career.history.size() == q + 2 and career.state.quarter_index == q + 1 and var_to_bytes(career.decisions[-1]) == var_to_bytes(policy), "exactly one successful atomic Career adoption")

func run_pair(case_id: String, seed_number: int) -> bool:
	var label := "%s/%d" % [case_id, seed_number]
	var ordinary := CountedCareer.new()
	var delegated := CountedCareer.new()
	if not require(ordinary.start(case_id, seed_number).ok and delegated.start(case_id, seed_number).ok and ordinary.encode() == delegated.encode(), label + ": exact canonical seeded starts"):
		return false
	var tape := var_to_bytes([delegated.shocks, delegated.episodes])
	var helper := CountedFollowUp.new()
	var automatic := 0
	var automatic_late := 0
	var attended := 0
	var segment_first := 0
	var reasons: Dictionary = {}
	for q in range(240):
		if not require(q == 0 or helper.active, label + ": permission remains armed until the next current-information check"):
			return false
		var obs := observe(delegated)
		var before_observer := var_to_bytes(obs)
		var attempts := CountedEconomy.attempts
		var proposal: Dictionary = helper.proposal(obs.state, obs.shock, obs.phase, obs.params, obs.completed, obs.history, q + 1) if helper.active else {"ok": false, "reasons": ["FIRST_ATTENDED"]}
		if not require(CountedEconomy.attempts == attempts and var_to_bytes(obs) == before_observer and not proposal.get("waiting", false), label + ": pure detached current observer at q%d" % q):
			return false
		if not require(proposal.ok or (not proposal.reasons.is_empty() and not proposal.reasons.has("MALFORMED_OBSERVER") and not proposal.reasons.has("INACTIVE")), label + ": controller faults cannot masquerade as ordinary attendance"):
			return false
		var expected := ordinary_policy(ordinary.state, ordinary.current_briefing(), ordinary.params)
		var chosen: Dictionary = proposal.policy if proposal.ok else ordinary_policy(obs.state, obs.shock, obs.params)
		if not require(var_to_bytes(chosen) == var_to_bytes(expected), label + ": ordinary and delegated policy bytes at q%d" % q):
			return false
		if proposal.ok:
			var funding_clear: bool = obs.shock.get("funding_need_pct_initial_gdp", 0.0) == 0.0 and obs.shock.get("refinancing_need_pct_initial_gdp", 0.0) == 0.0 and obs.state.outstanding_liquidity_pct_initial_gdp == 0.0 and obs.state.reserve_scarcity_wedge_pct == 0.0 and obs.state.uncovered_funding_pct_initial_gdp == 0.0
			if not require(obs.phase.is_empty() and funding_clear, label + ": no automatic adoption through a current episode or funding return"):
				return false
		if not proposal.ok:
			if q > 0 and not explain_segment(delegated, segment_first, q):
				return false
			segment_first = q
			attended += 1
			for reason in proposal.reasons:
				reasons[reason] = reasons.get(reason, 0) + 1
		else:
			automatic += 1
			if q >= 120:
				automatic_late += 1
		if not advance_once(ordinary, expected) or not advance_once(delegated, chosen):
			return false
		if not require(var_to_bytes(ordinary.state) == var_to_bytes(delegated.state), label + ": exact realized state at q%d" % q):
			return false
		if proposal.ok:
			if not require(helper.committed(q + 1, proposal.token), label + ": acknowledge current generation once"):
				return false
		elif not require(helper.arm(delegated.state, delegated.params, chosen, q + 1).ok, label + ": attended adoption arms a new bounded segment"):
			return false
	if not require(case_id != "base" or automatic_late > 0, label + ": late-career baseline must exercise automatic adoption, not only attended fallback"):
		return false
	if not explain_segment(delegated, segment_first, 240):
		return false
	var attempts := CountedEconomy.attempts
	var terminal := helper.proposal(delegated.state.duplicate(true), {}, {}, delegated.params.duplicate(true), 240, 241, 241)
	if not require(not terminal.ok and terminal.reasons.has("CAREER_END") and not helper.active and not delegated.advance(ordinary_policy(delegated.state, {}, delegated.params)).ok and CountedEconomy.attempts == attempts, label + ": terminal career cannot adopt or retain permission"):
		return false
	if not require(var_to_bytes(ordinary.history) == var_to_bytes(delegated.history) and ordinary.encode() == delegated.encode() and tape == var_to_bytes([delegated.shocks, delegated.episodes]), label + ": full history, policy and unmodified seeded tape parity"):
		return false
	var restored := CountedCareer.new()
	CountedEconomy.phase = "replay"
	var replay: Dictionary = restored.restore(bytes_to_var(delegated.encode()))
	CountedEconomy.phase = "observer"
	if not require(replay.ok and CountedEconomy.attempts == attempts + 240 and restored.encode() == delegated.encode() and var_to_bytes(restored.history) == var_to_bytes(delegated.history), label + ": native production restore replays all 240 decisions exactly"):
		return false
	rows.append({"scenario": case_id, "seed": seed_number, "quarters": 240, "attended": attended, "automatic": automatic, "automatic_q120_onward": automatic_late, "reasons": reasons, "episodes": delegated.episodes.size(), "final_payload_sha256": delegated.encode().hex_encode().sha256_text()})
	print("ROUTINE_CAREER_COMPLETE: ", label)
	return true
