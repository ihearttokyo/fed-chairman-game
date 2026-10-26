extends SceneTree
const Career = preload("res://play/career.gd")
const PRIOR := "48de589c689eb84f54893cd8b96e3d26b08ce9690d80b166532f8cea4e646419"
class FutureCareer:
	extends "res://play/career.gd"
	func model_digest() -> String:
		return "unqualified-future-source"
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func hashed(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()
func _initialize() -> void:
	var dir := OS.get_environment("FED_CREDIT_COMPATIBILITY")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("manifest.json"))) if not dir.is_empty() else null
	if not manifest is Dictionary or manifest.get("model_digest") != PRIOR or manifest.get("cases", {}).size() != 9:
		printerr("FAIL: genuine nine-case Alpha616/617 fixtures required")
		quit(2)
		return
	var probe := Career.new()
	check(probe.model_digest() != PRIOR, "Current candidate has a distinct source digest")
	for id in manifest.cases:
		var path: String = dir.path_join(id + "-alpha616.bin")
		var original := FileAccess.get_file_as_bytes(path)
		var payload: Variant = bytes_to_var(original)
		check(hashed(original) == manifest.cases[id].payload_sha256 and payload is Dictionary and payload.get("model_digest") == PRIOR and payload.get("scenario_id") == id, "Original fixture is genuine and unmodified: " + id)
		if not payload is Dictionary: continue
		var c := Career.new()
		var restored := c.restore(payload)
		check(restored.ok, "Original Q240 save restores: " + id)
		if restored.ok:
			check(hashed(var_to_bytes([c.state, c.history, c.decisions, c.shocks])) == manifest.cases[id].history_sha256, "All restored states, policies and shocks byte-identical: " + id)
			check(c.history.size() == 241 and c.decisions.size() == 240, "Full history is retained: " + id)
			check(bytes_to_var(c.encode()).model_digest == probe.model_digest(), "Explicit new encoding uses current header without modifying the old file")
		check(FileAccess.get_file_as_bytes(path) == original, "Load never rewrites original bytes: " + id)
		check(not FutureCareer.new()._compatible_saved_model(payload), "Future source drift closes the bridge")
	for id in ["workout_lab", "__bank_workout", "__priced_bank_workout", "unknown", "", 1]:
		check(not probe._compatible_saved_model({"model_digest": PRIOR, "scenario_id": id}), "Unknown and laboratory cases cannot use the normal-career bridge")
	check(not probe._compatible_saved_model({"model_digest": "unknown", "scenario_id": "base"}), "Unknown source header refuses")
	if failures == 0: print("PASS: original nine-career save compatibility ", checks, " checks")
	quit(0 if failures == 0 else 1)
