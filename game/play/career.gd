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

func start(case_id: String, seed_number: int) -> Dictionary:
	if seed_number < -2147483647 or seed_number > 2147483647:
		return {"ok": false, "error": "Seed must be between -2147483647 and 2147483647."}
	if not cases.has(case_id):
		return {"ok": false, "error": "Unknown scenario"}
	var initial: Dictionary = model.initial_state(params, cases[case_id].initial)
	if not initial.ok:
		return initial
	scenario_id = case_id
	seed_value = seed_number
	state = initial.state
	history = [state.duplicate(true)]
	decisions = []
	shocks = model.seeded_shock_path(seed_number, cases[case_id], MAX_QUARTERS)
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

func model_digest() -> String:
	return (FileAccess.get_sha256("res://model/economy.gd") + FileAccess.get_sha256("res://model/parameters.json") + FileAccess.get_sha256("res://model/scenarios.json")).sha256_text()

func payload() -> Dictionary:
	return {"version": 1, "model_digest": model_digest(), "scenario_id": scenario_id,
		"seed": seed_value, "shocks": shocks.duplicate(true), "decisions": decisions.duplicate(true)}

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
