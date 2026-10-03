extends RefCounted

const Economy = preload("res://model/economy.gd")
const MAX_QUARTERS := 240
var model := Economy.new()
var params: Dictionary = model.load_parameters().values
var cases: Dictionary = model.load_scenarios().scenarios
var scenario_id := "base"
var seed_value := 1
var state: Dictionary = {}
var history: Array = []
var decisions: Array = []
var shocks: Array = []
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
	for episode in episodes:
		var phase: int = decisions.size() - int(episode.quarter_index)
		if phase < 0 or phase >= int(episode.duration_quarters) or decisions.size() >= shocks.size():
			continue
		# Saved realized inputs remain authoritative after an audit edit. Attribute
		# only the current pulse, allowing the disclosed background innovations.
		var keys := current.keys()
		for key in episode.shock_profile[phase]:
			if not keys.has(key):
				keys.append(key)
		for key in keys:
			var tolerance := 0.18000000001 if key == "demand_shock_pct" else 0.04000000001 if key == "supply_innovation_pct" else 0.01000000001 if key == "r_star_change_pct" else 0.0
			if abs(current.get(key, 0.0) - episode.shock_profile[phase].get(key, 0.0)) > tolerance:
				return {}
		return {"title":episode.title,"policy_dilemma":episode.policy_dilemma}
	return {}

func situation_briefing() -> String:
	if state.is_empty():
		return ""
	var previous: Dictionary = history[-2] if history.size() > 1 else state
	var market := "Long expectations %.2f%%; credibility %.0f/100." % [state.expected_long_inflation_pct, 100 * state.credibility]
	if previous.guidance_active:
		market += " Last evaluated promise: %.1f/100 follow-through." % (100 * state.guidance_followthrough_score)
	elif state.guidance_active:
		market += " Your first announcement awaits its follow-through meeting."
	var public := "Hardship memory is building." if state.public_hardship_memory > previous.public_hardship_memory else "Hardship memory is easing." if state.public_hardship_memory < previous.public_hardship_memory else "Hardship memory is steady."
	public += " Support %.1f/100; remembered burden %.2f points." % [state.public_support, state.public_hardship_memory]
	var current: Dictionary = current_briefing()
	var funding := "No major new funding pressure."
	if current.get("funding_need_pct_initial_gdp", 0.0) > 0.1:
		var recurring: bool = not decisions.is_empty() and shocks[decisions.size() - 1].get("funding_need_pct_initial_gdp", 0.0) > 0.1
		funding = "Funding pressure continues." if recurring else "New funding pressure."
	elif state.solvency_risk_wedge_pct > 0.1:
		funding = "Funding aftermath: credit impairment remains; lending cannot repair capital."
	elif state.outstanding_liquidity_pct_initial_gdp > 0.1:
		funding = "Funding aftermath: outstanding loans still unwind through repayment."
	if not decisions.is_empty():
		funding += " Last decision: lending %.2f; uncovered %.2f (%% initial GDP)." % [state.liquidity_applied_pct_initial_gdp, state.uncovered_funding_pct_initial_gdp]
	var text := "MARKETS / %s\nPUBLIC / %s\nFUNDING / %s" % [market, public, funding]
	var episode := current_shock_episode()
	if not episode.is_empty():
		text += "\nEXOGENOUS / %s · %s" % [episode.title, episode.policy_dilemma]
	return text

func forecast(policy: Dictionary) -> Dictionary:
	var projected: Dictionary = state.duplicate(true)
	var states: Array = []
	for q in range(8):
		var choice: Dictionary = policy if q == 0 else model.benchmark_policy(projected, params, "hold")
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
	var reference: Dictionary = history[start].duplicate(true)
	var held_states: Array = []
	for q in range(start, decisions.size()):
		var result: Dictionary = model.step(reference, model.benchmark_policy(reference, params, "hold"), shocks[q], params)
		if not result.ok:
			return {"ok": false, "error": "Hold reference unavailable: " + result.error}
		reference = result.state
		held_states.append(reference)
	var summaries: Array = []
	for path in [history.slice(start + 1), held_states]:
		var summary := {"inflation_miss": 0.0, "employment_shortfall": 0.0,
			"credibility": path[-1].credibility, "public_support": path[-1].public_support}
		for outcome in path:
			summary.inflation_miss += abs(outcome.four_quarter_inflation_pct - params.inflation_target_pct) / path.size()
			summary.employment_shortfall += max(0.0, outcome.unemployment_rate_pct - outcome.structural_unemployment_pct) / path.size()
		summaries.append(summary)
	return {"ok": true, "from_quarter": start, "to_quarter": decisions.size(),
		"hold_rate": history[start].policy_rate_pct, "actual": summaries[0], "held": summaries[1]}

func model_digest() -> String:
	return (FileAccess.get_sha256("res://model/economy.gd") + FileAccess.get_sha256("res://model/parameters.json") + FileAccess.get_sha256("res://model/scenarios.json") + FileAccess.get_sha256("res://model/exogenous_shocks.json")).sha256_text()

func payload() -> Dictionary:
	return {"version": 1, "model_digest": model_digest(), "scenario_id": scenario_id,
		"seed": seed_value, "shocks": shocks.duplicate(true), "episodes": episodes.duplicate(true), "decisions": decisions.duplicate(true)}

func encode() -> PackedByteArray:
	# Godot's native values retain exact floats; JSON parsing can move a value by one ULP.
	return var_to_bytes(payload())

func restore(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY or data.get("version") != 1 or data.get("model_digest") != model_digest():
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
