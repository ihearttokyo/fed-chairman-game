extends SceneTree
const Committee = preload("res://play/policy_committee.gd")
const Career = preload("res://play/career.gd")
var failures := 0
class ChangedModel:
	extends "res://play/career.gd"
	func model_digest() -> String:
		return "changed-source-must-not-admit-old-saves"

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func command_key(window: Window, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.meta_pressed = OS.get_name() == "macOS"
	event.ctrl_pressed = OS.get_name() != "macOS"
	event.pressed = true
	window.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	window.push_input(event, true)
	await process_frame

func run() -> void:
	var career := Career.new()
	check(career.start("stagflation_bank_run", 1).ok, "crisis starts")
	var original: PackedByteArray = career.encode()
	var choices: Array = Committee.proposals(career.state, career.params, career.current_briefing(), career.model.nominal_gdp_ratio(career.state))
	check(choices.size() == 3 and choices[0].rate > career.state.policy_rate_pct and choices[1].rate < career.state.policy_rate_pct, "stagflation produces opposing rate priorities")
	check(choices[2].rate == career.state.policy_rate_pct and is_equal_approx(choices[2].lending_offer_current_gdp, 2.4), "funding separates secured lending from rate policy")
	var partial := {"funding_need_pct_initial_gdp":2.0, "eligible_collateral_pct_initial_gdp":10.0, "collateral_haircut_pct":0.0, "liquidity_eligibility_pct":50.0}
	check(is_equal_approx(Committee.proposals(career.state, career.params, partial, 1.0)[2].lending_offer_current_gdp, 1.0), "eligibility constrains need as well as collateral")
	check(is_equal_approx(Committee.proposals(career.state, career.params, partial, 2.0)[2].lending_offer_current_gdp, 0.5), "current GDP conversion happens once")
	var old_header := {"model_digest":"ff431fc6f24cbc90339055340ede21cc1db7677a8a5f4011633ca59016205cdc", "scenario_id":"base"}
	check(Career.new()._compatible_saved_model(old_header), "exact reviewed prior model is explicitly compatible")
	check(not ChangedModel.new()._compatible_saved_model(old_header), "future source changes disable the compatibility bridge")
	var legacy_path := OS.get_environment("FED_COMMITTEE_LEGACY_FIXTURE")
	if legacy_path.is_empty():
		print("NOT RUN: actual pre-feature save replay (set FED_COMMITTEE_LEGACY_FIXTURE)")
	if not legacy_path.is_empty():
		var legacy_bytes := FileAccess.get_file_as_bytes(legacy_path)
		var legacy: Dictionary = bytes_to_var(legacy_bytes)
		var restored := Career.new()
		check(restored.restore(legacy.payload).ok and var_to_bytes(restored.history) == var_to_bytes(legacy.history), "actual prior-source career loads and replays exactly")
		check(FileAccess.get_file_as_bytes(legacy_path) == legacy_bytes, "compatibility load never rewrites the original")
		var forged: Dictionary = legacy.payload.duplicate(true)
		forged.model_digest = "unknown"
		check(not Career.new().restore(forged).ok, "unknown model digests still refuse")
		forged = legacy.payload.duplicate(true)
		forged.scenario_id = "stagflation_bank_run"
		check(not Career.new().restore(forged).ok, "legacy digest cannot authorize the new scenario")
	var altered: Dictionary = career.state.duplicate(true)
	altered.r_star_pct += 50.0
	check(Committee.proposals(altered, career.params, career.current_briefing(), career.model.nominal_gdp_ratio(career.state)) == choices, "committee cannot use the hidden neutral-rate oracle")
	career.shocks[200].demand_shock_pct += 1.0
	check(Committee.proposals(career.state, career.params, career.current_briefing(), career.model.nominal_gdp_ratio(career.state)) == choices, "future tape cannot alter current proposals")
	check(career.start("stagflation_bank_run", 1).ok and career.encode() == original, "proposal generation preserves state and deterministic reset")
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._start_career("stagflation_bank_run", 1)
	check(game.mandate_label.text.begins_with("RECOVERY v1") and game.mandate_label.tooltip_text.contains("separate fictional stabilization"), "crisis HUD exposes its distinct objective and rules")
	var recovery: Dictionary = game.career.recovery_assessment()
	check(game._recovery_summary(recovery).contains("Build 0/12") and game._recovery_summary(recovery).contains("Funding n.a."), "empty window and absent eligible funding are explicit")
	recovery.window_quarters = 1
	recovery.funding_active = true
	recovery.funding_coverable = 20.0
	recovery.funding_applied = 0.0
	check(game._recovery_summary(recovery).contains("Funding 0.000/95%"), "early funding failure is visible before the window fills")
	recovery.window_quarters = 12
	recovery.inflation_miss = 1.0
	recovery.employment_shortfall = 1.0
	for coverable in [3.0, 82.0]:
		recovery.funding_coverable = coverable
		var required: float = game.career.MANDATE_FUNDING_COVERAGE_MIN * coverable
		for delta in [-0.00000001, 0.0, 0.00000001]:
			recovery.funding_applied = required + delta
			recovery.funding_coverage = recovery.funding_applied / coverable
			recovery.stabilized = recovery.funding_applied >= required
			var relation := "<" if delta < 0.0 else ">" if delta > 0.0 else ""
			check(game._recovery_summary(recovery).contains("Funding %s95.000/95%%" % relation), "recovery funding display uses principal comparison, not rounded division")
	for delta in [-0.0000001, 0.0, 0.0000001]:
		recovery.inflation_miss = 1.0 + delta
		recovery.employment_shortfall = 1.0 + delta
		var relation := "<" if delta < 0.0 else ">" if delta > 0.0 else ""
		check(game._recovery_summary(recovery).contains("prices %s1.000/1 pp" % relation) and game._recovery_summary(recovery).contains("Jobs %s1.000/1 pp" % relation), "recovery display preserves sub-display price and job threshold distinctions")
	var before: PackedByteArray = game.career.encode()
	game.assets.value = 0.75
	game.liquidity.value = 0.2
	game.committee.select(0)
	await command_key(root, KEY_K)
	check(game.rate.value > 3.5 and game.assets.value == 0.75 and game.liquidity.value == 0.2, "price proposal preserves other tool offers")
	var staged: Dictionary = game._policy().duplicate(true)
	var report: AcceptDialog = game._text_dialog("Committee modal guard", "Current policy must remain staged.")
	game.committee.select(1)
	await command_key(report, KEY_K)
	check(game._policy() == staged, "committee accelerator cannot stage behind a modal report")
	report.queue_free()
	await process_frame
	game.committee.select(1)
	game._stage_committee()
	check(game.rate.value < 3.5, "employment priority stages opposing rate")
	game.committee.select(2)
	game._stage_committee()
	check(game.rate.value == 3.5 and is_equal_approx(game.liquidity.value, 2.4) and game.assets.value == 0.75, "funding priority stages current-GDP secured offer without changing assets")
	check(game.career.encode() == before and game.career.decisions.is_empty(), "every proposal stages only: no adoption or save mutation")
	if failures == 0:
		print("PASS: opposing committee priorities, current-only information and nonmutating UI staging")
	await game._quit_app(1 if failures else 0)
