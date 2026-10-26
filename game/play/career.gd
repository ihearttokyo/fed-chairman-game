extends RefCounted

const Economy = preload("res://model/economy.gd")
const DEFAULT_SCENARIO := "policy_career"
const MAX_QUARTERS := 240
# Fictional outcome thresholds, not empirical welfare or dismissal standards.
const MANDATE_INFLATION_MISS_MAX := 1.0
const MANDATE_EMPLOYMENT_SHORTFALL_MAX := 0.5
const MANDATE_RECENT_EMPLOYMENT_SHORTFALL_MAX := 1.0
const MANDATE_FUNDING_COVERAGE_MIN := 0.95
const MANDATE_RECENT_QUARTERS := 12
var model := Economy.new()
var params: Dictionary = model.load_parameters().values
var cases: Dictionary = model.load_scenarios().scenarios
var scenario_id := "base"
var seed_value := 1
var state: Dictionary = {}
var history: Array = []
var decisions: Array = []
var shocks: Array = []
var _seeded_shocks: Array = []
var episodes: Array = []

func start(case_id: String, seed_number: int) -> Dictionary:
	if seed_number < -2147483647 or seed_number > 2147483647:
		return {"ok": false, "error": "Seed must be between -2147483647 and 2147483647."}
	if not cases.has(case_id):
		return {"ok": false, "error": "Unknown scenario"}
	var initial: Dictionary = model.initial_state(params, cases[case_id].initial)
	if not initial.ok:
		return initial
	var generated := model.seeded_campaign(seed_number, cases[case_id], MAX_QUARTERS)
	if not generated.ok:
		return generated
	scenario_id = case_id
	seed_value = seed_number
	state = initial.state
	history = [state.duplicate(true)]
	decisions = []
	shocks = generated.shocks
	_seeded_shocks = generated.shocks.duplicate(true)
	for pulse in _seeded_shocks:
		pulse.make_read_only()
	_seeded_shocks.make_read_only()
	episodes = generated.episodes
	return {"ok": true}

func advance(policy: Dictionary) -> Dictionary:
	if state.is_empty() or decisions.size() >= MAX_QUARTERS:
		return {"ok": false, "error": "This 60-year career is complete. Start another scenario to explore a different path."}
	var result: Dictionary = model.step(state, policy, shocks[decisions.size()], params)
	if not result.ok:
		return result
	state = result.state
	history.append(state.duplicate(true))
	decisions.append(policy.duplicate(true))
	return result

func current_briefing() -> Dictionary:
	return shocks[decisions.size()].duplicate(true) if decisions.size() < shocks.size() else {}

func current_shock_episode() -> Dictionary:
	var current := current_briefing()
	# Realized save inputs may be edited, but only the exact seeded pulse supports
	# its authored event label. This reference is rebuilt at start/restore, not saved.
	if decisions.size() >= _seeded_shocks.size() or current != _seeded_shocks[decisions.size()]:
		return {}
	for episode in episodes:
		var phase: int = decisions.size() - int(episode.quarter_index)
		if phase < 0 or phase >= int(episode.duration_quarters) or decisions.size() >= shocks.size():
			continue
		return episode.phase_briefings[phase].duplicate(true)
	return {}

static func funding_amount_text(amount: float) -> String:
	if amount > 0.0 and amount < 0.0001:
		return "<0.0001"
	return ("%.4f" if amount > 0.0 and amount < 0.01 else "%.2f") % amount

func situation_briefing() -> String:
	if state.is_empty():
		return ""
	var previous: Dictionary = history[-2] if history.size() > 1 else state
	var current: Dictionary = current_briefing()
	var market := "Long expectations %.2f%%; credibility %.0f/100." % [state.expected_long_inflation_pct, 100 * state.credibility]
	var credit: float = current.get("credit_risk_innovation_pct", 0.0)
	if credit > 0.0:
		var amount := "up <0.01 pp" if credit < 0.01 else "%+.2f pp" % credit
		market += " Credit-risk impulse %s (spread pricing)." % amount
	if previous.guidance_active:
		market += " Last evaluated promise: %.1f/100 follow-through." % (100 * state.guidance_followthrough_score)
	elif state.guidance_active:
		market += " Your first announcement awaits its follow-through meeting."
	var public := "Hardship memory is building." if state.public_hardship_memory > previous.public_hardship_memory else "Hardship memory is easing." if state.public_hardship_memory < previous.public_hardship_memory else "Hardship memory is steady."
	public += " Support %.1f/100; remembered burden %.2f points." % [state.public_support, state.public_hardship_memory]
	var refinancing_need := minf(current.get("refinancing_need_pct_initial_gdp", 0.0), state.outstanding_liquidity_pct_initial_gdp)
	var funding := "No major new funding pressure."
	if current.get("funding_need_pct_initial_gdp", 0.0) > 0.1:
		var recurring: bool = not decisions.is_empty() and shocks[decisions.size() - 1].get("funding_need_pct_initial_gdp", 0.0) > 0.1
		funding = "Funding pressure continues." if recurring else "New funding pressure."
	elif refinancing_need > 0.1:
		funding = "Refinancing pressure: prior short loans mature at this settlement."
	elif current.get("solvency_risk_innovation_pct", 0.0) > 0.0:
		funding = "New credit impairment: spread pressure; lending cannot create bank capital."
	elif state.solvency_risk_wedge_pct > 0.1:
		funding = "Funding aftermath: credit impairment remains; lending cannot repair capital."
	elif state.outstanding_liquidity_pct_initial_gdp > 0.1:
		funding = "Funding aftermath: prior short loans mature at the next settlement."
	if not decisions.is_empty():
		funding += " Last decision: lending %s; uncovered %s (%% meeting GDP)." % [funding_amount_text(state.liquidity_applied_pct_initial_gdp / state.decision_nominal_gdp_ratio), funding_amount_text(state.uncovered_funding_pct_initial_gdp / state.decision_nominal_gdp_ratio)]
	var text := "MARKETS / %s\nPUBLIC / %s\nFUNDING / %s" % [market, public, funding]
	var episode := current_shock_episode()
	if not episode.is_empty():
		text += "\nEXOGENOUS / %s · %s" % [episode.title, episode.policy_dilemma]
	return text

func forecast(policy: Dictionary, follow_guidance: bool = false) -> Dictionary:
	var projected: Dictionary = state.duplicate(true)
	var states: Array = []
	for q in range(8):
		var choice: Dictionary = policy if q == 0 else model.benchmark_policy(projected, params, "hold")
		if q > 0:
			if follow_guidance:
				var due: float = model.conditional_commitment(projected, params)
				choice.policy_rate_request_pct = due
				choice.guidance_rate_pct = due
				choice.guidance_inflation_sensitivity = policy.guidance_inflation_sensitivity
				choice.guidance_output_gap_sensitivity = policy.guidance_output_gap_sensitivity
			for key in Economy.POLICY_SWITCHES:
				choice[key] = policy.get(key, Economy.POLICY_SWITCHES[key])
		var result: Dictionary = model.step(projected, choice, current_briefing() if q == 0 else {}, params)
		if not result.ok:
			return result
		projected = result.state
		states.append(projected.duplicate(true))
	return {"ok": true, "states": states}

func review_comparison() -> Dictionary:
	if decisions.is_empty():
		return {"ok": false, "error": "Complete a decision before reviewing its outcome."}
	var start := maxi(0, decisions.size() - 12)
	var reference_paths: Array = [[], []]
	var staff_error := ""
	for index in range(2):
		var reference: Dictionary = history[start].duplicate(true)
		for q in range(start, decisions.size()):
			var result: Dictionary = model.step(reference, model.benchmark_policy(reference, params, "hold" if index == 0 else "feedback"), shocks[q], params)
			if not result.ok:
				if index == 0:
					return {"ok": false, "error": "Hold reference unavailable: " + result.error}
				staff_error = "Staff reference unavailable: " + result.error
				reference_paths[index] = []
				break
			reference = result.state
			reference_paths[index].append(reference)
	var summaries: Array = []
	for path in [history.slice(start + 1), reference_paths[0], reference_paths[1]]:
		if path.is_empty():
			summaries.append({})
			continue
		var summary := _outcome_averages(path)
		summary["credibility"] = path[-1].credibility
		summary["public_support"] = path[-1].public_support
		summary.uncovered_funding = 0.0
		for outcome in path:
			summary.uncovered_funding += outcome.uncovered_funding_pct_initial_gdp / outcome.decision_nominal_gdp_ratio / path.size()
		summaries.append(summary)
	var compared := {"ok": true, "from_quarter": start, "to_quarter": decisions.size(),
		"hold_rate": history[start].policy_rate_pct, "actual": summaries[0], "held": summaries[1], "staff": summaries[2]}
	if not staff_error.is_empty():
		compared.staff_error = staff_error
	return compared

func _outcome_averages(path: Array) -> Dictionary:
	var summary := {"inflation_miss": 0.0, "employment_shortfall": 0.0}
	for outcome in path:
		summary.inflation_miss += abs(outcome.four_quarter_inflation_pct - params.inflation_target_pct) / path.size()
		summary.employment_shortfall += max(0.0, outcome.unemployment_rate_pct - outcome.structural_unemployment_pct) / path.size()
	return summary

func mandate_assessment() -> Dictionary:
	var count := decisions.size()
	var completed := history.slice(1, count + 1)
	var averages := _outcome_averages(completed)
	var recent := _outcome_averages(history.slice(maxi(1, count - MANDATE_RECENT_QUARTERS + 1), count + 1))
	var assessment := {"eligible": scenario_id in [DEFAULT_SCENARIO, "unanchored_inflation"], "complete": count == MAX_QUARTERS, "quarters": count,
		"inflation_miss": averages.inflation_miss, "employment_shortfall": averages.employment_shortfall,
		"recent_inflation_miss": recent.inflation_miss, "recent_employment_shortfall": recent.employment_shortfall,
		"funding_coverable": 0.0, "funding_applied": 0.0, "funding_active": false, "funding_coverage": 0.0,
		"prices_met": false, "employment_met": false, "funding_met": false, "achieved": false}
	for q in range(count):
		if shocks[q] != _seeded_shocks[q]:
			assessment.eligible = false
		var outcome: Dictionary = completed[q]
		# Common initial-GDP settlement flows include refinancing, not aggregate loans.
		assessment.funding_coverable += minf(outcome.eligible_local_need_pct_initial_gdp, outcome.lending_collateral_capacity_pct_initial_gdp)
		assessment.funding_applied += outcome.liquidity_local_applied_pct_initial_gdp
	assessment.funding_active = assessment.funding_coverable > 0.0
	assessment.funding_coverage = assessment.funding_applied / assessment.funding_coverable if assessment.funding_active else 0.0
	assessment.prices_met = count > 0 and assessment.inflation_miss <= MANDATE_INFLATION_MISS_MAX and recent.inflation_miss <= MANDATE_INFLATION_MISS_MAX
	assessment.employment_met = count > 0 and assessment.employment_shortfall <= MANDATE_EMPLOYMENT_SHORTFALL_MAX and recent.employment_shortfall <= MANDATE_RECENT_EMPLOYMENT_SHORTFALL_MAX
	assessment.funding_met = assessment.funding_active and assessment.funding_applied >= MANDATE_FUNDING_COVERAGE_MIN * assessment.funding_coverable
	assessment.achieved = assessment.eligible and assessment.complete and assessment.prices_met and assessment.employment_met and (not assessment.funding_active or assessment.funding_met)
	return assessment

# Recovery is a separate current stabilization objective, not a relaxed Mandate.
# Reuse its disclosed recent-window thresholds and cumulative settlement ledger.
func recovery_assessment() -> Dictionary:
	var mandate: Dictionary = mandate_assessment()
	var eligible := scenario_id == "stagflation_bank_run"
	for q in range(decisions.size()):
		if shocks[q] != _seeded_shocks[q]:
			eligible = false
	var window: int = mini(decisions.size(), MANDATE_RECENT_QUARTERS)
	var prices_met: bool = window == MANDATE_RECENT_QUARTERS and mandate.recent_inflation_miss <= MANDATE_INFLATION_MISS_MAX
	var jobs_met: bool = window == MANDATE_RECENT_QUARTERS and mandate.recent_employment_shortfall <= MANDATE_RECENT_EMPLOYMENT_SHORTFALL_MAX
	var funding_met: bool = not mandate.funding_active or mandate.funding_met
	return {"eligible":eligible, "quarters":decisions.size(), "window_quarters":window,
		"inflation_miss":mandate.recent_inflation_miss, "employment_shortfall":mandate.recent_employment_shortfall,
		"funding_active":mandate.funding_active, "funding_coverable":mandate.funding_coverable,
		"funding_applied":mandate.funding_applied, "funding_coverage":mandate.funding_coverage,
		"prices_met":prices_met, "employment_met":jobs_met, "funding_met":funding_met,
		"stabilized":eligible and prices_met and jobs_met and funding_met}

func model_digest() -> String:
	return (FileAccess.get_sha256("res://model/economy.gd") + FileAccess.get_sha256("res://model/parameters.json") + FileAccess.get_sha256("res://model/scenarios.json") + FileAccess.get_sha256("res://model/exogenous_shocks.json") + FileAccess.get_sha256("res://model/portfolio_reference.json")).sha256_text()

# Exact accepted-path compatibility only. Workout settlement stays optional;
# the fractional-advance repair changes formerly invalid transitions, not valid
# histories. Genuine pre-edit nine-scenario Q240 replay is separately qualified.
# Optional priced credit leaves ordinary calls unchanged; genuine Alpha616/617
# saves replay byte-identically through this exact source, without file rewrites.
# Future source drift disables these bridges; older eight-only scope is retained.
func _compatible_saved_model(data: Dictionary) -> bool:
	if model_digest() != "525f6c2e96c0b77e8260064d829604102a8b8c153e435874a9b942709e38f30f":
		return false
	var prior: Variant = data.get("model_digest")
	if prior in ["48de589c689eb84f54893cd8b96e3d26b08ce9690d80b166532f8cea4e646419", "f88f562b3039ed35b9af8740fdf6509d1c44ff03a2b4f9dbf642fec9c9709725", "06714dc18908afbd2805c5f2ed0f97bc9ede6ab53c111ee73aa0413724ca49a6"]:
		return data.get("scenario_id") in ["base", "demand_boom", "supply_shock", "funding_stress", "unanchored_inflation", "lower_bound_slump", "mixed_crises", "policy_career", "stagflation_bank_run"]
	return prior == "ff431fc6f24cbc90339055340ede21cc1db7677a8a5f4011633ca59016205cdc" \
		and data.get("scenario_id") in ["base", "demand_boom", "supply_shock", "funding_stress", "unanchored_inflation", "lower_bound_slump", "mixed_crises", "policy_career"]

func payload() -> Dictionary:
	return {"version": 1, "model_digest": model_digest(), "scenario_id": scenario_id,
		"seed": seed_value, "shocks": shocks.duplicate(true), "episodes": episodes.duplicate(true), "decisions": decisions.duplicate(true)}

func encode() -> PackedByteArray:
	# Godot's native values retain exact floats; JSON parsing can move a value by one ULP.
	return var_to_bytes(payload())

func restore(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY or data.get("version") != 1 or (data.get("model_digest") != model_digest() and not _compatible_saved_model(data)):
		return {"ok": false, "error": "Save is invalid or belongs to another model version. Current career is unchanged."}
	if typeof(data.get("scenario_id")) != TYPE_STRING or not cases.has(data.scenario_id):
		return {"ok": false, "error": "Save has an unknown scenario."}
	if typeof(data.get("seed")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(data.seed)) or float(data.seed) != int(data.seed) or abs(float(data.seed)) > 2147483647:
		return {"ok": false, "error": "Save has an invalid seed."}
	if typeof(data.get("shocks")) != TYPE_ARRAY or data.shocks.size() != MAX_QUARTERS or typeof(data.get("decisions")) != TYPE_ARRAY or data.decisions.size() > MAX_QUARTERS:
		return {"ok": false, "error": "Save has an invalid career length."}
	for shock in data.shocks:
		if typeof(shock) != TYPE_DICTIONARY or not model._validate_shocks(shock).ok:
			return {"ok": false, "error": "Save contains invalid economic inputs."}
	# Replay in isolation. Never install a partial or externally supplied state.
	var replay = get_script().new()
	var begun: Dictionary = replay.start(data.scenario_id, int(data.seed))
	if not begun.ok:
		return begun
	if data.get("episodes") != replay.episodes:
		return {"ok":false,"error":"Save has inconsistent exogenous episode context. Current career is unchanged."}
	replay.shocks = data.shocks.duplicate(true)
	for policy in data.decisions:
		if typeof(policy) != TYPE_DICTIONARY:
			return {"ok": false, "error": "Save contains an invalid decision."}
		var result: Dictionary = replay.advance(policy)
		if not result.ok:
			return {"ok": false, "error": "Save decision rejected: " + result.error}
	scenario_id = replay.scenario_id
	seed_value = replay.seed_value
	state = replay.state
	history = replay.history
	decisions = replay.decisions
	shocks = replay.shocks
	_seeded_shocks = replay._seeded_shocks
	episodes = replay.episodes
	return {"ok": true}

func save_to(path: String) -> Dictionary:
	var pending := path + ".pending"
	var file := FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not create save. Previous save is unchanged."}
	file.store_buffer(encode())
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return {"ok": false, "error": "Save write failed. Previous save is unchanged."}
	var renamed := DirAccess.rename_absolute(pending, path)
	return {"ok": true} if renamed == OK else {"ok": false, "error": "Could not finish save. Previous save is unchanged."}

func load_from(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "No readable saved career found."}
	if file.get_length() > 2000000:
		return {"ok": false, "error": "Save exceeds the supported size."}
	return restore(bytes_to_var(file.get_buffer(file.get_length())))
