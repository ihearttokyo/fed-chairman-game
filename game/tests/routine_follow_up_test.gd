extends SceneTree

const Economy = preload("res://model/economy.gd")

class MeteredEconomy:
	extends "res://model/economy.gd"
	static var attempts := 0
	static var confirmed := 0
	static var rejected := 0
	static var known_rejects := 0
	static var unknown := 0
	static var predecessor_violations := 0
	static var context := "helpers"
	func step(state: Dictionary, policy: Dictionary, shocks: Dictionary, params: Dictionary) -> Dictionary:
		attempts += 1
		var before := var_to_bytes(state)
		var result: Dictionary = super.step(state, policy, shocks, params)
		if result.ok:
			confirmed += 1
		else:
			rejected += 1
			if context.begins_with("off_grid/") and result.error.contains("increments"):
				known_rejects += 1
			else:
				unknown += 1
		if before != var_to_bytes(state):
			predecessor_violations += 1
		print("NATIVE_CALL: ", var_to_bytes({"attempt": attempts, "context": context, "before": before, "policy": policy, "shock": shocks, "result": result, "predecessor_unchanged": before == var_to_bytes(state)}).hex_encode())
		return result

class MeteredCareer:
	extends "res://play/career.gd"
	func _init() -> void:
		model = MeteredEconomy.new()

class FollowUp:
	extends "res://play/routine_follow_up.gd"
	func _init() -> void:
		_model = MeteredEconomy.new()

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var model := Economy.new()
	var params: Dictionary = model.load_parameters().values
	var state: Dictionary = model.initial_state(params, {}).state
	# Synthetic post-adoption observer: native validation, but no economic transition.
	state.quarter_index = 1
	var policy: Dictionary = reference_policy(state, params)
	policy.merge({"reinvest_principal": false, "maintain_ample_reserves": true, "sterilize_purchases": false})
	var helper := FollowUp.new()
	var armed: Dictionary = helper.arm(state, params, policy, 10)
	check(armed.ok and helper.active and helper.automatic_left == 3, "successful attended adoption arms exactly three routine follow-ups")
	if armed.ok:
		check_helpers(model, state, params, policy)
	check(MeteredEconomy.attempts == 0, "helper assertions perform zero Economy.step calls")
	if failures == 0 and not OS.get_cmdline_user_args().has("--helpers-only"):
		check_gate()
	print("FOLLOW_UP_COUNTS: checks=%d failures=%d attempts=%d confirmed=%d known_rejects=%d unknown=%d" % [checks, failures, MeteredEconomy.attempts, MeteredEconomy.confirmed, MeteredEconomy.known_rejects, MeteredEconomy.unknown])
	if failures == 0:
		print("PASS: routine follow-up helpers" if OS.get_cmdline_user_args().has("--helpers-only") else "PASS: Gate0 exactly 18 attempts / 16 confirmed / 2 known off-grid rejects")
	quit(1 if failures else 0)

func observe(state: Dictionary, params: Dictionary, policy: Dictionary, shock: Dictionary = {}, phase: Dictionary = {}) -> Dictionary:
	var helper := FollowUp.new()
	var armed: Dictionary = helper.arm(state, params, policy, 10)
	check(armed.ok, "pure observer fixture arms")
	return helper.proposal(state, shock, phase, params, int(state.quarter_index), int(state.quarter_index) + 1, 11)

func check_helpers(model: RefCounted, state: Dictionary, params: Dictionary, policy: Dictionary) -> void:
	var original := var_to_bytes([state, params, policy])
	var helper := FollowUp.new()
	check(helper.arm(state, params, policy, 10).ok, "fresh helper arms")
	var waiting: Dictionary = helper.proposal(state, {}, {}, params, 1, 2, 10)
	check(not waiting.ok and waiting.waiting and waiting.reasons.is_empty() and waiting.policy.is_empty() and helper.active and helper.automatic_left == 3, "same-frame waiting is not an end or an adoption")
	var first: Dictionary = helper.proposal(state, {}, {}, params, 1, 2, 11)
	var expected := reference_policy(state, params)
	check(first.ok and not first.waiting and var_to_bytes(first.policy) == var_to_bytes(expected), "complete automatic actor matches independent policy bytes including false switches")
	check(first.token.is_read_only(), "issued pending token is immutable rather than shared mutable state")
	check(not helper.committed(10, first.token) and helper.automatic_left == 3, "same/incorrect frame cannot acknowledge")
	var next: Dictionary = helper.proposal(state, {}, {}, params, 1, 2, 11)
	check(not helper.committed(11, first.token), "superseded proposal token is stale")
	check(helper.committed(11, next.token) and helper.automatic_left == 2 and not helper.committed(11, next.token), "fresh acknowledgement decrements once and duplicate fails")
	var synthetic: Dictionary = state.duplicate(true)
	synthetic.quarter_index = 2
	var pending: Dictionary = helper.proposal(synthetic, {}, {}, params, 2, 3, 12)
	check(pending.ok, "next synthetic frame may propose")
	var old_generation: int = helper.generation
	helper.stop()
	check(helper.generation > old_generation and not helper.active and not helper.committed(12, pending.token), "cancellation invalidates outstanding work before fake commit sink")
	check(helper.arm(state, params, policy, 20).ok and not helper.committed(21, pending.token), "rearm cannot accept a previous segment token")
	var snapshot := var_to_bytes(helper.anchor)
	var copy_policy: Dictionary = policy.duplicate(true)
	helper.arm(state, params, copy_policy, 10)
	copy_policy.reinvest_principal = true
	check(helper.switches.reinvest_principal == false and var_to_bytes(helper.anchor) == snapshot, "arm copies switches and its fixed post-adoption anchor")
	for mask in range(8):
		var selected: Dictionary = policy.duplicate(true)
		selected.reinvest_principal = bool(mask & 1)
		selected.maintain_ample_reserves = bool(mask & 2)
		selected.sterilize_purchases = bool(mask & 4)
		var result := observe(state, params, selected)
		check(result.ok and result.policy.reinvest_principal == selected.reinvest_principal and result.policy.maintain_ample_reserves == selected.maintain_ample_reserves and result.policy.sterilize_purchases == selected.sterilize_purchases, "all three switches persist explicitly, mask %d" % mask)
	var ambient := {"demand_shock_pct": 0.18, "supply_innovation_pct": -0.04, "r_star_change_pct": 0.01, "collateral_haircut_pct": 0.0, "liquidity_eligibility_pct": 0.0, "rrp_uptake_fraction": 1.0, "potential_growth_pct": state.potential_growth_pct}
	check(observe(state, params, policy, ambient).ok and observe(state, params, policy).ok, "ambient equalities and native omitted 0/0 collateral defaults remain routine")
	for pair in [["demand_shock_pct", -0.1800001], ["supply_innovation_pct", 0.0400001], ["r_star_change_pct", -0.0100001], ["credit_risk_innovation_pct", 1e-12], ["solvency_risk_innovation_pct", 1e-12], ["r_star_reference_change_pct", 1e-12], ["structural_unemployment_change_pct", 1e-12], ["rrp_encumbered_collateral_pct_initial_gdp", 1e-12], ["rrp_uptake_fraction", 0.999], ["eligible_collateral_pct_initial_gdp", 1e-12], ["collateral_haircut_pct", 25.0], ["liquidity_eligibility_pct", 100.0], ["potential_growth_pct", state.potential_growth_pct + 0.01]]:
		check(observe(state, params, policy, {pair[0]: pair[1]}).reasons.has("CURRENT_NEWS"), "nonroutine current input: " + pair[0])
	for key in ["funding_need_pct_initial_gdp", "refinancing_need_pct_initial_gdp"]:
		var result := observe(state, params, policy, {key: 1e-12})
		check(not result.ok and result.reasons.has("FUNDING_NEED" if key.begins_with("funding") else "REFINANCING_NEED"), "tiny positive need returns without display rounding: " + key)
	for pair in [["outstanding_liquidity_pct_initial_gdp", "OUTSTANDING_LOANS"], ["reserve_scarcity_wedge_pct", "RESERVE_SCARCITY"], ["uncovered_funding_pct_initial_gdp", "UNCOVERED_FUNDING"]]:
		var changed: Dictionary = state.duplicate(true)
		changed[pair[0]] = 0.001
		if pair[0] == "outstanding_liquidity_pct_initial_gdp":
			changed.total_assets_pct_initial_gdp += 0.001
			changed.capital_other_pct_initial_gdp += 0.001
		check(observe(changed, params, policy).reasons.has(pair[1]), "current contractual/settlement return: " + pair[0])
	var phase := {"title": "Current event", "policy_dilemma": "Current decision"}
	check(observe(state, params, policy, {}, phase).reasons == ["CURRENT_PHASE"], "current phase returns before another automatic adoption")
	helper.arm(state, params, policy, 10)
	for q in range(1, 4):
		var fake: Dictionary = state.duplicate(true)
		fake.quarter_index = q
		var result: Dictionary = helper.proposal(fake, {}, {}, params, q, q + 1, 10 + q)
		check(result.ok and helper.committed(10 + q, result.token), "synthetic zero-step allowance acknowledgement %d" % q)
	var q4: Dictionary = state.duplicate(true)
	q4.quarter_index = 4
	var returned: Dictionary = helper.proposal(q4, {"supply_innovation_pct": 1.0}, phase, params, 4, 5, 14)
	check(returned.reasons == ["QUOTA_EXHAUSTED", "CURRENT_PHASE", "CURRENT_NEWS"] and not helper.active, "quota exhaustion does not conceal newly current q4 phase/news; priority is stable")
	var terminal: Dictionary = state.duplicate(true)
	terminal.quarter_index = 240
	check(observe(terminal, params, policy).reasons.has("CAREER_END"), "retirement never proposes another economic transition")
	for pair in [["four_quarter_inflation_pct", "INFLATION_DRIFT"], ["output_gap_pct", "OUTPUT_GAP_DRIFT"], ["expected_long_inflation_pct", "LONG_EXPECTATIONS_DRIFT"]]:
		for amount in [0.249, 0.25]:
			helper.arm(state, params, policy, 10)
			var changed: Dictionary = state.duplicate(true)
			changed[pair[0]] += amount
			if pair[0] == "four_quarter_inflation_pct":
				changed.price_history[0] = changed.price_index / (1.0 + changed.four_quarter_inflation_pct / 100.0)
			if pair[0] == "output_gap_pct":
				changed.actual_output_index = changed.potential_output_index * (1.0 + changed.output_gap_pct / 100.0)
			var result: Dictionary = helper.proposal(changed, {}, {}, params, 1, 2, 11)
			check(result.reasons.has(pair[1]) == (amount == 0.25), "fixed-anchor .25 boundary: %s / %s" % [pair[1], amount])
	for field in ["r_star_pct", "expected_short_inflation_pct"]:
		for amount in [0.249, 0.25]:
			helper.arm(state, params, policy, 10)
			var changed: Dictionary = state.duplicate(true)
			changed[field] += amount
			check(model._validate_state(changed, params).ok, "hidden-state control remains native-valid: " + field)
			var result: Dictionary = helper.proposal(changed, {}, {}, params, 1, 2, 11)
			check(result.ok and result.reasons.is_empty() and var_to_bytes(result.policy) == var_to_bytes(expected), "hidden neutral/short-expectation changes cannot alter gameplay advice or trigger staff drift: " + field)
			check(model.benchmark_policy(changed, params).policy_rate_request_pct != model.benchmark_policy(state, params).policy_rate_request_pct, "diagnostic oracle remains sensitive to the hidden positive control: " + field)
	for amount in [0.244, 0.246]:
		helper.arm(state, params, policy, 10)
		var changed: Dictionary = state.duplicate(true)
		changed.expected_long_inflation_pct += amount
		var result: Dictionary = helper.proposal(changed, {}, {}, params, 1, 2, 11)
		check(result.reasons.has("BENCHMARK_DRIFT") == (amount == 0.246) and not result.reasons.has("LONG_EXPECTATIONS_DRIFT"), "published staff-quote drift keeps the exact .25 grid boundary before raw observation drift")
	var promise: Dictionary = state.duplicate(true)
	promise.guidance_active = true
	promise.guidance_inflation_sensitivity = 1.0
	promise.guidance_output_gap_sensitivity = 0.0
	promise.guidance_rate_pct = expected.policy_rate_request_pct
	promise.guidance_reference_inflation_pct = promise.four_quarter_inflation_pct - 0.003
	check(model.conditional_commitment(promise, params) == expected.policy_rate_request_pct and observe(promise, params, policy).ok, "native conditional promise is rounded before the attention comparison")
	promise.guidance_rate_pct += 0.25
	check(observe(promise, params, policy).reasons.has("PROMISE_GAP"), "promise difference equal to .25 returns")
	var overflowing_promise: Dictionary = state.duplicate(true)
	overflowing_promise.guidance_active = true
	overflowing_promise.guidance_inflation_sensitivity = 2.0
	overflowing_promise.guidance_output_gap_sensitivity = 2.0
	overflowing_promise.guidance_reference_inflation_pct = 1e308
	overflowing_promise.guidance_reference_output_gap_pct = -1e308
	check(model._validate_state(overflowing_promise, params).ok, "overflow regression has finite native-valid inputs")
	check_malformed(helper, state, params, policy, overflowing_promise, {}, {}, 1, 2, "nonfinite computed promise")
	for field in ["quarter_index", "guidance_active", "price_history", "treasury_cohorts_pct_initial_gdp", "reserve_scarcity_wedge_pct"]:
		var malformed: Dictionary = {}
		for key in state:
			if key != field:
				malformed[key] = state[key]
		check_malformed(helper, state, params, policy, malformed, {}, {}, 1, 2, "missing " + field)
	for value in [NAN, INF, "2", true]:
		var malformed: Dictionary = state.duplicate(true)
		malformed.expected_long_inflation_pct = value
		check_malformed(helper, state, params, policy, malformed, {}, {}, 1, 2, "non-native/nonfinite state")
	var unknown: Dictionary = state.duplicate(true)
	unknown.future_accessor = "not a native field"
	check_malformed(helper, state, params, policy, unknown, {}, {}, 1, 2, "unknown state")
	for shock in [{"future": 1.0}, {"demand_shock_pct": NAN}, {"demand_shock_pct": true}, {"collateral_haircut_pct": 101.0}]:
		check_malformed(helper, state, params, policy, state, shock, {}, 1, 2, "invalid current shock")
	check_malformed(helper, state, params, policy, state, {}, {"title": "Missing dilemma"}, 1, 2, "malformed phase")
	check_malformed(helper, state, params, policy, state, {}, {}, 1, 1, "history count")
	check_malformed(helper, state, params, policy, state, {}, {}, 0, 2, "completed count")
	var invalid_params: Dictionary = params.duplicate(true)
	invalid_params.minimum_rate_increment_pct = 0.0
	helper.arm(state, params, policy, 10)
	var malformed_result: Dictionary = helper.proposal(state, {}, {}, invalid_params, 1, 2, 11)
	check(not malformed_result.ok and malformed_result.policy.is_empty() and not helper.active, "invalid parameters disarm before quote division")
	var implicit := {"maintain_ample_reserves": true, "sterilize_purchases": false}
	for key in Economy.POLICY_KEYS:
		implicit[key] = policy[key]
	check(not helper.arm(state, params, implicit, 10).ok and not helper.active, "arm rejects missing explicit switch rather than silently defaulting")
	implicit = policy.duplicate(true)
	implicit.maintain_ample_reserves = 1
	check(not helper.arm(state, params, implicit, 10).ok, "arm rejects truthy nonboolean switch")
	var overflow: Dictionary = state.duplicate(true)
	overflow.r_star_pct = 1e308
	overflow.expected_short_inflation_pct = 1e308
	var overflow_arm: Dictionary = helper.arm(overflow, params, policy, 10)
	check(model._validate_state(overflow, params).ok and overflow_arm.ok and helper.active and helper.anchor.benchmark_rate_pct == expected.policy_rate_request_pct, "unrepresentable hidden oracle inputs cannot contaminate a finite public staff anchor")
	var visible_overflow: Dictionary = state.duplicate(true)
	visible_overflow.expected_long_inflation_pct = 1e308
	check(model._validate_state(visible_overflow, params).ok, "public overflow fixture has finite native-valid observations")
	overflow_arm = helper.arm(visible_overflow, params, policy, 10)
	check(not overflow_arm.ok and overflow_arm.policy.is_empty() and not helper.active, "finite public inputs with unrepresentable staff quote precision cannot arm an infinite anchor")
	check(var_to_bytes([state, params, policy]) == original, "all helper checks leave caller native values byte-for-byte unchanged")
	var restore_host := MeteredCareer.new()
	var isolated = restore_host.get_script().new()
	check(isolated.model is MeteredEconomy, "restore's get_script().new() retains native-call instrumentation")
	check_future_observer()

func check_malformed(helper: RefCounted, base: Dictionary, params: Dictionary, policy: Dictionary, state: Dictionary, shock: Dictionary, phase: Dictionary, count: int, history: int, label: String) -> void:
	helper.arm(base, params, policy, 10)
	var result: Dictionary = helper.proposal(state, shock, phase, params, count, history, 11)
	check(not result.ok and result.reasons == ["MALFORMED_OBSERVER"] and result.policy.is_empty() and result.token.is_empty() and not helper.active, "malformed observer safely disarms: " + label)

func reference_policy(state: Dictionary, params: Dictionary) -> Dictionary:
	var rate: float = params.initial_r_star_pct + float("%.2f" % state.expected_long_inflation_pct) + params.policy_inflation_response * (float("%.2f" % state.four_quarter_inflation_pct) - params.inflation_target_pct) + params.policy_output_gap_response * float("%.2f" % state.output_gap_pct)
	rate = floorf(rate / params.minimum_rate_increment_pct + 0.5) * params.minimum_rate_increment_pct
	return {"policy_rate_request_pct": rate, "guidance_rate_pct": rate, "guidance_inflation_sensitivity": params.policy_inflation_response, "guidance_output_gap_sensitivity": params.policy_output_gap_response, "asset_flow_request_pct_initial_gdp": 0.0, "liquidity_request_pct_initial_gdp": 0.0, "reinvest_principal": false, "maintain_ample_reserves": true, "sterilize_purchases": false}

func tape() -> Array:
	var cycle := [[0.02, 0.005, 0.002], [-0.02, -0.005, -0.002], [0.01, -0.002, 0.001], [-0.01, 0.002, -0.001]]
	var shocks: Array = []
	for q in range(240):
		shocks.append({"demand_shock_pct": cycle[q % 4][0], "supply_innovation_pct": cycle[q % 4][1], "r_star_change_pct": cycle[q % 4][2]})
	return shocks

func make_career() -> RefCounted:
	var career := MeteredCareer.new()
	check(career.start("base", 1).ok, "Gate0 uses original base/seed1 initial state")
	career.shocks = tape()
	return career

func current_observer(career: RefCounted) -> Dictionary:
	return {"state": career.state.duplicate(true), "current_shock": career.current_briefing(), "current_phase": career.current_shock_episode(), "completed_count": career.decisions.size(), "history_count": career.history.size()}

func check_future_observer() -> void:
	var a := make_career()
	var b := make_career()
	b.shocks[4].supply_innovation_pct = 1.0
	b.episodes = [{"quarter_index": 4, "duration_quarters": 1, "phase_briefings": [{"title": "Future event", "policy_dilemma": "Future question"}]}]
	check(var_to_bytes(a.shocks) != var_to_bytes(b.shocks) and var_to_bytes(a.episodes) != var_to_bytes(b.episodes) and var_to_bytes(current_observer(a)) == var_to_bytes(current_observer(b)), "future numeric/metadata twins expose identical current observation, not identical future payloads")

# Both attended wrappers enter this same boundary; no wrapper-only off-grid rejection.
func commit(career: RefCounted, policy: Dictionary, context: String, helper: RefCounted = null, token: Dictionary = {}, frame: int = -1) -> Dictionary:
	MeteredEconomy.context = context
	var before: PackedByteArray = career.encode()
	var count := MeteredEconomy.attempts
	var completed: int = career.decisions.size()
	var result: Dictionary = career.advance(policy)
	check(MeteredEconomy.attempts == count + 1, context + " dispatches exactly one native attempt")
	if result.ok:
		check(career.decisions.size() == completed + 1 and career.history.size() == completed + 2 and career.state.quarter_index == completed + 1, context + " appends exactly one full completed transition")
		if helper != null:
			check(helper.committed(frame, token), context + " acknowledges the current successful automatic policy once")
	else:
		check(career.encode() == before and career.decisions.size() == completed, context + " rejection retains every native career byte")
		if helper != null:
			helper.stop()
	return result

func check_gate() -> void:
	var ordinary := make_career()
	var delegated := make_career()
	var twin := make_career()
	twin.shocks[4].supply_innovation_pct = 1.0
	twin.episodes = [{"quarter_index": 4, "duration_quarters": 1, "phase_briefings": [{"title": "Future event", "policy_dilemma": "Future question"}]}]
	var d := FollowUp.new()
	var t := FollowUp.new()
	for q in range(4):
		var expected := reference_policy(ordinary.state, ordinary.params)
		if q == 0:
			expected.asset_flow_request_pct_initial_gdp = 0.01
		var dp := {"policy": expected.duplicate(true), "token": {}}
		var tp: Dictionary = dp.duplicate(true)
		if q > 0:
			check(var_to_bytes(current_observer(delegated)) == var_to_bytes(current_observer(twin)), "future twins have identical pre-current complete observer at q%d" % q)
			dp = d.proposal(delegated.state, delegated.current_briefing(), delegated.current_shock_episode(), delegated.params, q, q + 1, q + 10)
			tp = t.proposal(twin.state, twin.current_briefing(), twin.current_shock_episode(), twin.params, q, q + 1, q + 10)
			check(dp.ok and tp.ok and var_to_bytes(dp) == var_to_bytes(tp), "own-state D callbacks stay routine and equal before future q4 news")
			check(var_to_bytes(dp.policy) == var_to_bytes(expected), "D generates its complete automatic policy independently of the ordinary actor")
		if failures:
			return
		if not commit(ordinary, expected, "ordinary/q%d" % q).ok or failures:
			return
		if not commit(delegated, dp.policy, "D/q%d" % q, d if q > 0 else null, dp.token, q + 10).ok or failures:
			return
		if not commit(twin, tp.policy, "twin/q%d" % q, t if q > 0 else null, tp.token, q + 10).ok or failures:
			return
		for other in [delegated, twin]:
			check(var_to_bytes([ordinary.state, ordinary.history, ordinary.decisions]) == var_to_bytes([other.state, other.history, other.decisions]), "full native state/history/decisions agree after q%d" % q)
		check(ordinary.encode() == delegated.encode(), "identical-input ordinary/D full payload parity after q%d" % q)
		if q == 0:
			check(d.arm(delegated.state, delegated.params, dp.policy, 10).ok and t.arm(twin.state, twin.params, tp.policy, 10).ok, "first attended success arms D and twin")
		if failures:
			return
	var dr: Dictionary = d.proposal(delegated.state, delegated.current_briefing(), delegated.current_shock_episode(), delegated.params, 4, 5, 14)
	var tr: Dictionary = t.proposal(twin.state, twin.current_briefing(), twin.current_shock_episode(), twin.params, 4, 5, 14)
	check(dr.reasons.has("QUOTA_EXHAUSTED") and tr.reasons.has("QUOTA_EXHAUSTED") and tr.reasons.has("CURRENT_NEWS") and not dr.reasons.has("CURRENT_NEWS"), "q4 scheduled return also evaluates newly current twin news")
	check(var_to_bytes(dr.policy) == var_to_bytes(tr.policy) and delegated.encode() != twin.encode(), "q4 advice is current-state only; differing future-tape saves are not required to match")
	if failures:
		return
	var restored := MeteredCareer.new()
	MeteredEconomy.context = "restore/four_decisions"
	var before_restore := MeteredEconomy.attempts
	var restored_result: Dictionary = restored.restore(bytes_to_var(delegated.encode()))
	check(restored_result.ok and MeteredEconomy.attempts == before_restore + 4 and restored.encode() == delegated.encode(), "restore runs exactly four metered native calls and preserves full native payload/tape")
	check(not FollowUp.new().active, "a restored career starts attended without serialized permission")
	if failures:
		return
	for career in [ordinary, delegated]:
		var off_grid := reference_policy(career.state, career.params)
		if career == delegated:
			check(d.arm(career.state, career.params, off_grid, 20).ok and d.active, "D known-rejection fixture begins armed")
			if failures:
				return
		off_grid.policy_rate_request_pct = 3.505
		var failed: Dictionary = commit(career, off_grid, "off_grid/ordinary" if career == ordinary else "off_grid/D", null if career == ordinary else d)
		check(not failed.ok and failed.error.contains("increments"), "3.505 reaches the native grid validator as a deliberate known reject")
		if failures:
			return
	check(MeteredEconomy.attempts == 18 and MeteredEconomy.confirmed == 16 and MeteredEconomy.rejected == 2 and MeteredEconomy.known_rejects == 2 and MeteredEconomy.unknown == 0 and MeteredEconomy.predecessor_violations == 0 and not d.active, "Gate0 exact ledger: 18 attempts, 16 confirmed, two known native rejects, zero unknown or predecessor mutation")
