extends SceneTree
const Career = preload("res://play/career.gd")
const PRIOR_CURRENT := "06714dc18908afbd2805c5f2ed0f97bc9ede6ab53c111ee73aa0413724ca49a6"
const PRIOR_EIGHT := "ff431fc6f24cbc90339055340ede21cc1db7677a8a5f4011633ca59016205cdc"
const CASES := ["base", "demand_boom", "supply_shock", "funding_stress", "unanchored_inflation", "lower_bound_slump", "mixed_crises", "policy_career", "stagflation_bank_run"]
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
		print("FAIL: ", label)
func _initialize() -> void:
	var base := OS.get_environment("FED_WORKOUT_EVIDENCE")
	if base.is_empty():
		printerr("FAIL: genuine pre-edit fixtures required via FED_WORKOUT_EVIDENCE; no full compatibility pass claimed")
		quit(2)
		return
	var probe := Career.new()
	check(probe.model_digest() != PRIOR_CURRENT, "Compatibility qualification uses the genuinely changed source digest")
	for id in CASES:
		var input_path := base.path_join("baseline").path_join(id + ".bin")
		var history_path := base.path_join("baseline-history").path_join(id + ".bin")
		var original := FileAccess.get_file_as_bytes(input_path)
		var old_history := FileAccess.get_file_as_bytes(history_path)
		check(not original.is_empty() and not old_history.is_empty(), "Genuine pre-edit payload and complete history exist: " + id)
		if original.is_empty() or old_history.is_empty():
			continue
		var payload: Variant = bytes_to_var(original)
		check(payload is Dictionary and payload.get("model_digest") == PRIOR_CURRENT and payload.get("scenario_id") == id, "Original header binds this known model/scenario")
		if not payload is Dictionary:
			continue
		var c := Career.new()
		check(c._compatible_saved_model(payload), "Exact prior current source admits this explicit scenario")
		var restored := c.restore(payload)
		check(restored.ok, "Genuine prior Q240 career replays: " + id)
		if restored.ok:
			check(c.history.size() == 241 and c.decisions.size() == 240, "Complete career, not endpoint-only replay")
			check(var_to_bytes([c.state, c.history, c.decisions, c.shocks]) == old_history, "Every pre-edit state/history/decision/shock byte is preserved: " + id)
			check(c.payload().model_digest == c.model_digest(), "Explicit new encoding binds the new source, not a forged old header")
		check(FileAccess.get_file_as_bytes(input_path) == original and FileAccess.get_file_as_bytes(history_path) == old_history, "Loading never rewrites either original evidence file")
		var old_header := {"model_digest": PRIOR_EIGHT, "scenario_id": id}
		check(c._compatible_saved_model(old_header) == (id != "stagflation_bank_run"), "Older compatibility remains eight-only")
		check(not FutureCareer.new()._compatible_saved_model(payload) and not FutureCareer.new()._compatible_saved_model(old_header), "Future source drift disables both bridges")
	for id in ["workout_lab", "unknown", "", 1]:
		check(not probe._compatible_saved_model({"model_digest": PRIOR_CURRENT, "scenario_id": id}), "Prior digest cannot authorize a lab or unknown scenario")
	check(not probe._compatible_saved_model({"model_digest": "unknown", "scenario_id": "base"}), "Unknown model digest remains rejected")
	check(probe.start("base", 417).ok, "Rejection purity fixture starts")
	var frozen := probe.encode()
	check(not probe.restore({"version": 1, "model_digest": "unknown"}).ok and probe.encode() == frozen, "Unqualified load leaves current career bytes intact")
	if failures == 0:
		print("PASS: genuine nine-scenario Q240 compatibility, complete history byte parity, original-file protection and fail-closed headers; ", checks, " checks")
	quit(1 if failures else 0)
