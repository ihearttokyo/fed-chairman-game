extends SceneTree

# Root executes only after Gate0/review closure. --check-only executes no code.
const Explanation = preload("res://play/transition_explanation.gd")
const ORIGINAL_MODEL_DIGEST := "ff431fc6f24cbc90339055340ede21cc1db7677a8a5f4011633ca59016205cdc"
const SOURCES := ["res://tests/routine_pilot_test.gd", "res://play/routine_follow_up.gd", "res://play/transition_explanation.gd", "res://play/career.gd", "res://model/economy.gd", "res://model/parameters.json", "res://model/scenarios.json", "res://model/exogenous_shocks.json", "res://model/portfolio_reference.json"]

class MeteredEconomy:
	extends "res://model/economy.gd"
	static var attempts := 0
	static var confirmed := 0
	static var actual := 0
	static var replay := 0
	static var unknown := 0
	static var known_rejects := 0
	static var hidden_calls := 0
	static var native_usec := 0
	static var max_native_usec := 0
	static var explanation_usec := 0
	static var emitted_bytes := 0
	static var context := "unassigned"
	static var phase := "callback"
	static var stop_error := ""
	static var pins: Dictionary = {}
	static var binding := ""

	static func sources_match() -> bool:
		for path in pins:
			if FileAccess.get_sha256(path) != pins[path]:
				return false
		return true

	func step(state: Dictionary, policy: Dictionary, shocks: Dictionary, params: Dictionary) -> Dictionary:
		if not stop_error.is_empty() or attempts >= 480 or not sources_match():
			stop_error = "Native dispatch held: previous failure, 480-attempt ceiling or source drift."
			return {"ok": false, "error": stop_error}
		attempts += 1
		if phase == "actual":
			actual += 1
		elif phase == "restore":
			replay += 1
		else:
			hidden_calls += 1
			stop_error = "Unexpected native call outside actual/restore boundary."
		var before := var_to_bytes(state)
		# An orphan BEGIN is an unknown attempt, not a missing success, on process error.
		var begun := var_to_bytes({"attempt": attempts, "context": context, "phase": phase, "source_binding": binding, "before": before, "policy": policy, "shock": shocks, "params": params}).hex_encode()
		emitted_bytes += begun.length() + 13
		print("PILOT_BEGIN: ", begun)
		var started := Time.get_ticks_usec()
		var result: Dictionary = super.step(state, policy, shocks, params)
		var elapsed := Time.get_ticks_usec() - started
		native_usec += elapsed
		max_native_usec = maxi(max_native_usec, elapsed)
		var trace: Dictionary = {}
		if result.ok:
			confirmed += 1
			started = Time.get_ticks_usec()
			trace = Explanation.explain(state, result.state, shocks, params)
			explanation_usec += Time.get_ticks_usec() - started
			if not trace.ok or not _validate_state(result.state, params).ok:
				stop_error = "Completed native state/explanation failed validation."
		else:
			known_rejects += 1
			stop_error = "Unplanned native rejection: " + result.error
		if before != var_to_bytes(state) or not sources_match():
			stop_error = "Native predecessor mutation or source drift."
		var record := var_to_bytes({"attempt": attempts, "context": context, "phase": phase, "source_binding": binding, "before": before, "policy": policy, "shock": shocks, "params": params, "result": result, "trace": trace, "native_usec": elapsed, "technical_stop": stop_error}).hex_encode()
		emitted_bytes += record.length() + 15
		print("PILOT_NATIVE: ", record)
		if emitted_bytes > 60 * 1024 * 1024:
			stop_error = "Native evidence exceeded 60 MiB; stop before further dispatch."
		return result

class PilotCareer:
	extends "res://play/career.gd"
	func _init() -> void:
		model = MeteredEconomy.new()

class PilotFollowUp:
	extends "res://play/routine_follow_up.gd"
	func _init() -> void:
		_model = MeteredEconomy.new()

var checks := 0
var failures := 0
var callback_usec := 0
var started_usec := 0
var summaries: Dictionary = {}
var statuses: Dictionary = {}

func require(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)
	return value

func emit_record(label: String, value: Dictionary) -> void:
	print(label, ": ", var_to_bytes(value).hex_encode())

func _initialize() -> void:
	print("PILOT_START_NATIVE_RUN")
	started_usec = Time.get_ticks_usec()
	for context in ["Q", "M", "F"]:
		for script in ["A", "B"]:
			statuses[context + "/" + script] = {"status": "not_started", "planned_actual": 64, "planned_restore": 32 if script == "A" else 0}
	for path in SOURCES:
		MeteredEconomy.pins[path] = FileAccess.get_sha256(path)
		if not require(not MeteredEconomy.pins[path].is_empty(), "source binding exists: " + path):
			finish()
			return
	var identity := {"sources": MeteredEconomy.pins, "engine": Engine.get_version_info(), "runtime_path": OS.get_executable_path(), "runtime_sha256": FileAccess.get_sha256(OS.get_executable_path()), "platform": OS.get_name(), "planned_statuses": statuses.duplicate(true), "planned_actual": 384, "planned_restore": 96, "Gate0_included": false, "previews": 0, "whole_app_RSS": "root external monitor; not measured by this script"}
	MeteredEconomy.binding = var_to_bytes(identity).hex_encode().sha256_text()
	emit_record("PILOT_IDENTITY", identity)
	for context in ["Q", "M", "F"]:
		for script in ["A", "B"]:
			if not run_pair(context, script):
				statuses[context + "/" + script].status = "failed"
				finish()
				return
	require(MeteredEconomy.attempts == 480 and MeteredEconomy.confirmed == 480 and MeteredEconomy.actual == 384 and MeteredEconomy.replay == 96 and MeteredEconomy.known_rejects == 0 and MeteredEconomy.unknown == 0 and MeteredEconomy.hidden_calls == 0, "pilot exact ledger: 384 actual + 96 restore = 480 confirmed, no rejects/unknown/hidden calls")
	require(MeteredEconomy.sources_match(), "source bindings remain fixed at completion")
	finish()

func finish() -> void:
	MeteredEconomy.unknown = MeteredEconomy.attempts - MeteredEconomy.confirmed - MeteredEconomy.known_rejects
	var report := {"complete": failures == 0 and MeteredEconomy.attempts == 480 and MeteredEconomy.stop_error.is_empty(), "checks": checks, "failures": failures, "attempts": MeteredEconomy.attempts, "confirmed": MeteredEconomy.confirmed, "known_rejects": MeteredEconomy.known_rejects, "unknown": MeteredEconomy.unknown, "hidden_calls": MeteredEconomy.hidden_calls, "actual": MeteredEconomy.actual, "restore": MeteredEconomy.replay, "statuses": statuses, "summaries": summaries, "technical_stop": MeteredEconomy.stop_error, "wall_usec": Time.get_ticks_usec() - started_usec, "native_step_usec": MeteredEconomy.native_usec, "callback_usec": callback_usec, "explanation_usec": MeteredEconomy.explanation_usec, "native_stdout_bytes": MeteredEconomy.emitted_bytes, "previews": 0, "economic_depth_or_fun_claim": false}
	report.max_native_step_usec = MeteredEconomy.max_native_usec
	emit_record("PILOT_REPORT_NATIVE", report)
	print("PILOT_REPORT_JSON: ", JSON.stringify(report))
	if report.complete:
		print("PASS: bounded D474 pilot 480/480; original-economy parity and registered quiet attendance only")
	quit(0 if report.complete else 1)

func fixture(context: String) -> Array:
	var shocks: Array = []
	var cycle := [[0.02, 0.005, 0.002], [-0.02, -0.005, -0.002], [0.01, -0.002, 0.001], [-0.01, 0.002, -0.001]]
	for q in range(240):
		var shock: Dictionary = {}
		if context == "Q" and q < 32:
			shock = {"demand_shock_pct": cycle[q % 4][0], "supply_innovation_pct": cycle[q % 4][1], "r_star_change_pct": cycle[q % 4][2]}
		elif context == "M" and q < 2:
			shock = {"supply_innovation_pct": 0.35 if q == 0 else 0.25}
		elif context == "F" and q in [4, 5]:
			shock = {"funding_need_pct_initial_gdp": 3.0 if q == 4 else 2.0, "eligible_collateral_pct_initial_gdp": 6.0 if q == 4 else 4.0, "collateral_haircut_pct": 25.0, "liquidity_eligibility_pct": 100.0}
			if q == 4:
				shock.solvency_risk_innovation_pct = 0.6
		shocks.append(shock)
	return shocks

func new_career(context: String) -> RefCounted:
	var career := PilotCareer.new()
	var scenario := "unanchored_inflation" if context == "M" else "funding_stress" if context == "F" else "base"
	var begun: Dictionary = career.start(scenario, 1)
	if not require(begun.ok, "canonical initial scenario starts without native transition: " + scenario):
		return null
	var expected_initial := {"annualized_quarterly_inflation_pct": 4.5, "expected_short_inflation_pct": 4.8, "expected_long_inflation_pct": 3.8, "credibility": 0.25, "policy_rate_pct": 3.5} if context == "M" else {}
	if not require(career.cases[scenario].initial == expected_initial and career.model_digest() == ORIGINAL_MODEL_DIGEST, "exact authored initial overrides and original economic digest"):
		return null
	career.shocks = fixture(context)
	if not require(career.shocks.size() == 240 and career.decisions.is_empty() and career.history.size() == 1, "valid 240-entry synthetic tape and fresh career"):
		return null
	for q in range(240):
		if not require(career.model._validate_shocks(career.shocks[q]).ok and (q < 32 or career.shocks[q].is_empty()), "valid frozen tape, empty after q31"):
			return null
	# Native start's canonical episodes and seeded reference are not replaced.
	emit_record("PILOT_INITIAL", {"context": context, "scenario": scenario, "model_digest": career.model_digest(), "initial": career.state, "params": career.params, "tape": career.shocks, "episodes": career.episodes, "source_binding": MeteredEconomy.binding})
	return career

# The actor/controller receive only detached current data, not this live Career.
func observer(career: RefCounted) -> Dictionary:
	var state: Dictionary = career.state.duplicate(true)
	for key in state:
		if state[key] is Array:
			state[key].make_read_only()
	state.make_read_only()
	var shock: Dictionary = career.current_briefing()
	var phase: Dictionary = career.current_shock_episode()
	var params: Dictionary = career.params.duplicate(true)
	shock.make_read_only()
	phase.make_read_only()
	params.make_read_only()
	return {"state": state, "shock": shock, "phase": phase, "params": params, "completed": career.decisions.size(), "history": career.history.size()}

func independent_policy(state: Dictionary, shock: Dictionary, params: Dictionary, context: String, script: String, q: int) -> Dictionary:
	var rate: float = state.r_star_pct + state.expected_short_inflation_pct + params.policy_inflation_response * (state.four_quarter_inflation_pct - params.inflation_target_pct) + params.policy_output_gap_response * state.output_gap_pct
	rate = roundf(rate / params.minimum_rate_increment_pct) * params.minimum_rate_increment_pct
	var policy := {"policy_rate_request_pct": rate, "guidance_rate_pct": rate, "guidance_inflation_sensitivity": params.policy_inflation_response, "guidance_output_gap_sensitivity": params.policy_output_gap_response, "asset_flow_request_pct_initial_gdp": 0.0, "liquidity_request_pct_initial_gdp": shock.get("funding_need_pct_initial_gdp", 0.0) + minf(shock.get("refinancing_need_pct_initial_gdp", 0.0), state.outstanding_liquidity_pct_initial_gdp), "reinvest_principal": true, "maintain_ample_reserves": true, "sterilize_purchases": false}
	if script == "B":
		if context == "Q" and q == 0:
			policy.policy_rate_request_pct += 0.25
			policy.guidance_rate_pct += 0.25
		elif context == "M" and q == 0:
			policy.policy_rate_request_pct = 3.5
			policy.guidance_rate_pct = 3.5
		elif context == "F" and q == 4:
			policy.liquidity_request_pct_initial_gdp = 0.0
	return policy

func independent_anchor(state: Dictionary, params: Dictionary) -> Dictionary:
	var policy := independent_policy(state, {}, params, "Q", "A", -1)
	return {"four_quarter_inflation_pct": state.four_quarter_inflation_pct, "output_gap_pct": state.output_gap_pct, "expected_long_inflation_pct": state.expected_long_inflation_pct, "benchmark_rate_pct": policy.policy_rate_request_pct}

func independent_reasons(obs: Dictionary, anchor: Dictionary, left: int) -> Array[String]:
	var s: Dictionary = obs.state
	var z: Dictionary = obs.shock
	var reasons: Array[String] = []
	if obs.completed >= 240:
		reasons.append("CAREER_END")
	if left == 0:
		reasons.append("QUOTA_EXHAUSTED")
	if not obs.phase.is_empty():
		reasons.append("CURRENT_PHASE")
	for condition in [[z.get("funding_need_pct_initial_gdp", 0.0) > 0.0, "FUNDING_NEED"], [z.get("refinancing_need_pct_initial_gdp", 0.0) > 0.0, "REFINANCING_NEED"], [s.outstanding_liquidity_pct_initial_gdp > 0.0, "OUTSTANDING_LOANS"], [s.reserve_scarcity_wedge_pct > 0.0, "RESERVE_SCARCITY"], [s.uncovered_funding_pct_initial_gdp > 0.0, "UNCOVERED_FUNDING"]]:
		if condition[0]:
			reasons.append(condition[1])
	var news: bool = abs(z.get("demand_shock_pct", 0.0)) > 0.18 or abs(z.get("supply_innovation_pct", 0.0)) > 0.04 or abs(z.get("r_star_change_pct", 0.0)) > 0.01
	for key in ["credit_risk_innovation_pct", "solvency_risk_innovation_pct", "r_star_reference_change_pct", "structural_unemployment_change_pct"]:
		news = news or z.get(key, 0.0) != 0.0
	news = news or z.get("potential_growth_pct", s.potential_growth_pct) != s.potential_growth_pct or z.get("rrp_encumbered_collateral_pct_initial_gdp", 0.0) > 0.0 or z.get("rrp_uptake_fraction", 1.0) != 1.0 or z.get("eligible_collateral_pct_initial_gdp", 0.0) > 0.0 or z.get("collateral_haircut_pct", 0.0) != 0.0 or z.get("liquidity_eligibility_pct", 0.0) != 0.0
	if news:
		reasons.append("CURRENT_NEWS")
	for entry in [["four_quarter_inflation_pct", "INFLATION_DRIFT"], ["output_gap_pct", "OUTPUT_GAP_DRIFT"], ["expected_long_inflation_pct", "LONG_EXPECTATIONS_DRIFT"]]:
		if abs(s[entry[0]] - anchor[entry[0]]) >= 0.25:
			reasons.append(entry[1])
	var rate: float = independent_policy(s, {}, obs.params, "Q", "A", -1).policy_rate_request_pct
	if abs(rate - anchor.benchmark_rate_pct) >= 0.25:
		reasons.append("BENCHMARK_DRIFT")
	if s.guidance_active:
		var promise: float = s.guidance_rate_pct + s.guidance_inflation_sensitivity * (s.four_quarter_inflation_pct - s.guidance_reference_inflation_pct) + s.guidance_output_gap_sensitivity * (s.output_gap_pct - s.guidance_reference_output_gap_pct)
		promise = roundf(promise / obs.params.minimum_rate_increment_pct) * obs.params.minimum_rate_increment_pct
		if not is_finite(promise):
			return ["MALFORMED_OBSERVER"]
		if abs(rate - promise) >= 0.25:
			reasons.append("PROMISE_GAP")
	return reasons

func accounts_hold(state: Dictionary) -> bool:
	var securities: float = state.mbs_stock_pct_initial_gdp
	for key in ["treasury_cohorts_pct_initial_gdp", "bill_cohorts_pct_initial_gdp"]:
		for principal in state[key]:
			securities += principal
	var assets: float = securities + state.outstanding_liquidity_pct_initial_gdp
	var liabilities: float = state.reserves_pct_initial_gdp + state.reverse_repo_pct_initial_gdp + state.currency_pct_initial_gdp + state.treasury_account_pct_initial_gdp
	var tolerance: float = 1e-7 + 1e-12 * maxf(assets, maxf(liabilities, abs(state.capital_other_pct_initial_gdp)))
	return abs(assets - state.total_assets_pct_initial_gdp) <= tolerance and abs(securities - state.asset_stock_pct_initial_gdp) <= tolerance and abs(assets - liabilities - state.capital_other_pct_initial_gdp) <= tolerance

func advance_once(career: RefCounted, policy: Dictionary, label: String) -> bool:
	var before: PackedByteArray = career.encode()
	var count: int = career.decisions.size()
	var attempts := MeteredEconomy.attempts
	MeteredEconomy.context = label
	MeteredEconomy.phase = "actual"
	var result: Dictionary = career.advance(policy)
	if not require(result.ok and MeteredEconomy.attempts == attempts + 1 and MeteredEconomy.stop_error.is_empty(), label + ": exactly one successful native transition"):
		emit_record("PILOT_FAILED_PREFIX", {"label": label, "before_payload": before, "after_payload": career.encode(), "result": result})
		return false
	return require(career.decisions.size() == count + 1 and career.history.size() == count + 2 and career.state.quarter_index == count + 1 and var_to_bytes(career.decisions[-1]) == var_to_bytes(policy) and accounts_hold(career.state), label + ": count, exact policy and native ledger identities")

func explain_completed_segment(career: RefCounted, first: int, last: int, reasons: Array) -> bool:
	if not require(last > first and last - first <= 4, "completed receipt is bounded to one through four transitions"):
		return false
	var attempts := MeteredEconomy.attempts
	var result := Explanation.segment(career.history.slice(first, last + 1), career.shocks.slice(first, last), 0, last - first, career.params)
	emit_record("PILOT_SEGMENT", {"context": MeteredEconomy.context, "first_meeting": first, "last_completed_exclusive": last, "return_reasons": reasons, "explanation": result})
	return require(result.ok and MeteredEconomy.attempts == attempts, "completed-path segment reconstructs without any economic transition")

func run_pair(context: String, script: String) -> bool:
	var job := context + "/" + script
	statuses[job].status = "incomplete"
	var ordinary := new_career(context)
	var delegated := new_career(context)
	if ordinary == null or delegated == null:
		return false
	var helper := PilotFollowUp.new()
	var anchor: Dictionary = {}
	var left := 0
	var segment_first := 0
	var attended := 0
	var scheduled := 0
	var early := 0
	var automatic := 0
	var reason_counts: Dictionary = {}
	var prefix := var_to_bytes([ordinary.state, ordinary.history, ordinary.decisions])
	if not require(prefix == var_to_bytes([delegated.state, delegated.history, delegated.decisions]), job + ": identical whole initial economic path"):
		return false
	for q in range(32):
		var obs := observer(delegated)
		var obs_bytes := var_to_bytes(obs)
		var expected := independent_policy(ordinary.state, ordinary.current_briefing(), ordinary.params, context, script, q)
		var counter := MeteredEconomy.attempts
		var next: Dictionary = {}
		var reasons: Array[String] = ["FIRST_ATTENDED"]
		var use_automatic := false
		if q > 0:
			var expected_reasons := independent_reasons(obs, anchor, left)
			MeteredEconomy.phase = "callback"
			MeteredEconomy.context = job + "/callback/q%d" % q
			var callback_start := Time.get_ticks_usec()
			next = helper.proposal(obs.state, obs.shock, obs.phase, obs.params, obs.completed, obs.history, q + 100)
			callback_usec += Time.get_ticks_usec() - callback_start
			if not require(not next.waiting and next.reasons == expected_reasons and next.ok == expected_reasons.is_empty() and MeteredEconomy.attempts == counter and MeteredEconomy.stop_error.is_empty(), job + ": no missed/reordered current trigger or hidden callback transition at q%d" % q):
				emit_record("PILOT_CALLBACK_FAILURE", {"job": job, "q": q, "observer": obs, "independent_anchor": anchor, "independent_left": left, "expected_reasons": expected_reasons, "actual_proposal": next})
				return false
			reasons = next.reasons
			use_automatic = next.ok
			if not use_automatic:
				if not explain_completed_segment(delegated, segment_first, q, reasons):
					return false
				if reasons.has("QUOTA_EXHAUSTED"):
					scheduled += 1
				else:
					early += 1
				for reason in reasons:
					reason_counts[reason] = reason_counts.get(reason, 0) + 1
		var chosen: Dictionary = next.policy if use_automatic else independent_policy(obs.state, obs.shock, obs.params, context, script, q)
		if not require(var_to_bytes(chosen) == var_to_bytes(expected) and var_to_bytes(obs) == obs_bytes, job + ": own D actor matches independent complete ordinary policy without mutation at q%d" % q):
			return false
		if script == "B":
			var a := independent_policy(obs.state, obs.shock, obs.params, context, "A", q)
			var changed: Array[String] = []
			for key in a:
				if var_to_bytes(a[key]) != var_to_bytes(chosen[key]):
					changed.append(key)
			var allowed: Array[String] = []
			if q == 0 and context in ["Q", "M"]:
				allowed = ["policy_rate_request_pct", "guidance_rate_pct"]
			elif q == 4 and context == "F":
				allowed = ["liquidity_request_pct_initial_gdp"]
			if not require(changed == allowed, job + ": only registered first-action fields differ from A at q%d" % q):
				return false
			if not allowed.is_empty():
				var exact_change: bool = (context == "Q" and chosen.policy_rate_request_pct == a.policy_rate_request_pct + 0.25 and chosen.guidance_rate_pct == a.guidance_rate_pct + 0.25) or (context == "M" and chosen.policy_rate_request_pct == 3.5 and chosen.guidance_rate_pct == 3.5) or (context == "F" and a.liquidity_request_pct_initial_gdp == 3.0 and chosen.liquidity_request_pct_initial_gdp == 0.0)
				if not require(exact_change, job + ": exact registered first-action magnitude, not merely changed field names"):
					return false
				emit_record("PILOT_FIRST_ACTION", {"job": job, "meeting": q, "A_on_same_state": a, "B": chosen, "changed_fields": changed})
		emit_record("PILOT_ATTENTION", {"job": job, "meeting": q, "attended": not use_automatic, "reasons": reasons, "policy": chosen, "anchor": anchor, "left_before": left, "observer": obs, "token": next.get("token", {}), "source_binding": MeteredEconomy.binding})
		if not advance_once(ordinary, expected, job + "/ordinary/q%d" % q) or not advance_once(delegated, chosen, job + "/D/q%d" % q):
			return false
		if not require(var_to_bytes([ordinary.state, ordinary.history, ordinary.decisions]) == var_to_bytes([delegated.state, delegated.history, delegated.decisions]) and ordinary.encode() == delegated.encode(), job + ": exact whole native state/history/policy/payload parity after q%d" % q):
			return false
		MeteredEconomy.phase = "callback"
		if use_automatic:
			if not require(helper.committed(q + 100, next.token), job + ": fresh automatic acknowledgement"):
				return false
			left -= 1
			automatic += 1
		else:
			attended += 1
			segment_first = q
			anchor = independent_anchor(delegated.state, delegated.params)
			left = 3
			if not require(helper.arm(delegated.state, delegated.params, chosen, q + 100).ok and helper.anchor == anchor, job + ": post-attended fixed independent anchor"):
				return false
		if not require(helper.automatic_left == left and MeteredEconomy.attempts == counter + 2, job + ": only two actual calls this paired quarter; no bootstrap/preview"):
			return false
	if not explain_completed_segment(delegated, segment_first, 32, ["WINDOW_END"]):
		return false
	helper.stop()
	if not require(attended + automatic == 32 and (context != "Q" or script != "A" or attended <= 16), job + ": complete own horizon; frozen quiet-A needs <=16 attended of 32, actual attended=%d automatic=%d" % [attended, automatic]):
		return false
	var metrics := complete_metrics(delegated.history, context)
	if not require(not metrics.is_empty(), job + ": metrics require exactly 32 own outcomes"):
		return false
	summaries[job] = {"ordinary_attended": 32, "D_attended": attended, "D_automatic": automatic, "scheduled_returns": scheduled, "early_returns": early, "reason_counts": reason_counts, "missed_triggers": 0, "metrics": metrics, "actual_complete": true, "restore": "not_planned"}
	if script == "A":
		var restored := PilotCareer.new()
		var count := MeteredEconomy.attempts
		MeteredEconomy.context = job + "/restore"
		MeteredEconomy.phase = "restore"
		var saved: PackedByteArray = delegated.encode()
		var result: Dictionary = restored.restore(bytes_to_var(saved))
		if not require(result.ok and MeteredEconomy.attempts == count + 32 and restored.encode() == saved and var_to_bytes([restored.state, restored.history, restored.decisions]) == var_to_bytes([delegated.state, delegated.history, delegated.decisions]) and not PilotFollowUp.new().active and MeteredEconomy.stop_error.is_empty(), job + ": 32 metered replay calls, full native state/history/policy/save/tape parity, starts attended"):
				summaries[job].restore = "failed"
				return false
		summaries[job].restore = "complete"
	statuses[job].status = "complete"
	emit_record("PILOT_PAIR_COMPLETE", {"job": job, "summary": summaries[job], "source_binding": MeteredEconomy.binding})
	return true

func mean_misses(history: Array, first: int, count: int) -> Dictionary:
	var inflation := 0.0
	var unemployment := 0.0
	for q in range(first, first + count):
		var state: Dictionary = history[q + 1]
		inflation += abs(state.four_quarter_inflation_pct - 2.0)
		unemployment += maxf(0.0, state.unemployment_rate_pct - state.structural_unemployment_pct)
	return {"I": inflation / count, "U": unemployment / count}

func activity_sum(history: Array, first: int) -> float:
	var total := 0.0
	for q in range(first, first + 8):
		total += abs(history[q + 1].output_gap_pct)
	return total

func complete_metrics(history: Array, context: String) -> Dictionary:
	if history.size() != 33 or history[0].quarter_index != 0 or history[-1].quarter_index != 32:
		return {}
	for q in range(33):
		if history[q].quarter_index != q:
			return {}
	var first24 := mean_misses(history, 0, 24)
	var last8 := mean_misses(history, 24, 8)
	var result := {"q0_A8_pp_quarters": activity_sum(history, 0), "q0_I24_pp": first24.I, "q0_U24_pp": first24.U, "final8_I_pp": last8.I, "final8_U_pp": last8.U, "endpoint_q32": history[-1], "definitions": "A8=sum abs(output gap); I=mean abs(pi4-2); U=mean max(0,u-current structural u). Outcomes q0..q31; endpoint after 32 transitions. Descriptive original-economy diagnostics, no recovery/depth/frontier claim."}
	if context == "F":
		var relative := mean_misses(history, 4, 24)
		result.F_q4_q11_A8_pp_quarters = activity_sum(history, 4)
		result.F_q4_q27_I24_pp = relative.I
		result.F_q4_q27_U24_pp = relative.U
	return result
