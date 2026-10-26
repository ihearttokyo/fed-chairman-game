extends SceneTree
const Career = preload("res://play/career.gd")
const PRIOR := "f88f562b3039ed35b9af8740fdf6509d1c44ff03a2b4f9dbf642fec9c9709725"
class FutureCareer:
	extends "res://play/career.gd"
	func model_digest() -> String:
		return "unqualified-future-source"
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func _initialize() -> void:
	var dir := OS.get_environment("FED_FUNDING_EVIDENCE")
	if dir.is_empty():
		printerr("FAIL: genuine Alpha615 pre-edit fixtures required via FED_FUNDING_EVIDENCE")
		quit(2)
		return
	var hashes: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("alpha615-history-hashes.json")))
	if not hashes is Dictionary or hashes.size() != 9:
		printerr("FAIL: nine genuine complete-history digests required")
		quit(2)
		return
	var probe := Career.new()
	check(probe.model_digest() != PRIOR, "qualification uses changed model source")
	for id in ["base", "demand_boom", "supply_shock", "funding_stress", "unanchored_inflation", "lower_bound_slump", "mixed_crises", "policy_career", "stagflation_bank_run"]:
		var path: String = dir.path_join(id + "-alpha615.bin")
		var original := FileAccess.get_file_as_bytes(path)
		var payload: Variant = bytes_to_var(original)
		check(payload is Dictionary and payload.get("model_digest") == PRIOR and payload.get("scenario_id") == id, "genuine model/scenario header: " + id)
		if not payload is Dictionary:
			continue
		var c := Career.new()
		var result := c.restore(payload)
		check(result.ok, "genuine Alpha615 Q240 replay: " + id)
		if result.ok:
			var h := HashingContext.new()
			h.start(HashingContext.HASH_SHA256)
			h.update(var_to_bytes([c.state, c.history, c.decisions, c.shocks]))
			check(h.finish().hex_encode() == hashes.get(id), "all states, decisions and shocks byte-exact: " + id)
			check(c.history.size() == 241 and c.decisions.size() == 240, "full history rather than endpoint only")
		check(FileAccess.get_file_as_bytes(path) == original, "fixture is never rewritten")
		check(not FutureCareer.new()._compatible_saved_model(payload), "future drift rejects bridge")
	for id in ["workout_lab", "unknown", "", 1]:
		check(not probe._compatible_saved_model({"model_digest":PRIOR, "scenario_id":id}), "unknown and lab scenario excluded")
	check(not probe._compatible_saved_model({"model_digest":"unknown", "scenario_id":"base"}), "unknown source excluded")
	if failures == 0:
		print("PASS: Alpha615 nine-career exact-history replay and fail-closed compatibility; ", checks, " checks")
	quit(1 if failures else 0)
