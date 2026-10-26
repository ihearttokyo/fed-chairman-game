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

func exact_decimal(value: float) -> String:
	return String.num(value, 17) + " [" + var_to_bytes(value).hex_encode() + "]"

func decimal_diagnostic(game: Variant, phase: String, captured_assets: float, captured_liquidity: float, advertised: Dictionary) -> void:
	# Failure-only, bounded output: current-GDP controls versus initial-GDP policy
	# flows, with exact serialized floats so a last-bit resnap is distinguishable.
	var n: float = game.career.model.nominal_gdp_ratio(game.career.state)
	var actual: Dictionary = game._policy()
	var differences: Array[String] = []
	for key in advertised:
		if actual.get(key) != advertised[key]:
			differences.append(key)
	printerr("DECIMAL_DIAG phase=%s GDP=%s policy_diff_keys=%s" % [phase, exact_decimal(n), str(differences)])
	for pair in [["assets", game.assets, captured_assets], ["liquidity", game.liquidity, captured_liquidity]]:
		var input: SpinBox = pair[1]
		var quoted: float = game.docket_controls[pair[0]]
		printerr("DECIMAL_CONTROL %s native=%s captured=%s quoted=%s resnap_native=%s text=%s meta=%s pending=%s" % [pair[0], exact_decimal(input.value), exact_decimal(pair[2]), exact_decimal(quoted), exact_decimal(snappedf(input.value, input.step)), var_to_str(input.get_line_edit().text), var_to_str(input.get_meta("numeric_text")), str(input.get_meta("numeric_text_pending"))])
	for pair in [["asset_flow_request_pct_initial_gdp", captured_assets], ["liquidity_request_pct_initial_gdp", captured_liquidity]]:
		printerr("DECIMAL_FLOW %s actual=%s advertised=%s captured_current_GDP_times_n=%s" % [pair[0], exact_decimal(actual[pair[0]]), exact_decimal(advertised[pair[0]]), exact_decimal(pair[1] * n)])

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
	# No frame/wait: old canonical text may still be displayed after the setters.
	var asset_text: String = game.assets.get_line_edit().text
	var asset_canonical: String = game.assets.get_meta("numeric_text")
	var asset_pending: bool = game.assets.get_meta("numeric_text_pending")
	check(asset_pending and asset_text == asset_canonical and asset_text.to_float() != game.assets.value, "fixture exercises canonical old text pending an immediate Range redraw")
	var immediate: Dictionary = game._committee_draft()
	check(immediate.ok and immediate.controls.assets == 0.75 and immediate.controls.liquidity == 0.2, "immediate setters preserve committed Range offers before native redraw")
	game.assets.get_line_edit().text = "1.25"
	var edited: Dictionary = game._committee_draft()
	check(edited.ok and edited.controls.assets == 1.25 and edited.controls.liquidity == 0.2 and game.assets.value == 0.75, "genuine valid raw draft overrides pending committed value without submission")
	for malformed in ["", "garbage", "1 + 2", "nan", "1e999"]:
		game.assets.get_line_edit().text = malformed
		game.assets.set_meta("numeric_text", malformed)
		game.assets.set_meta("numeric_text_pending", true)
		var refused: Dictionary = game._committee_draft()
		check(not refused.ok and game.assets.get_line_edit().text == malformed and game.assets.value == 0.75 and game.liquidity.value == 0.2 and game.career.encode() == before, "malformed canonical/pending raw text never falls back or mutates offers/career")
	game.assets.get_line_edit().text = asset_text
	game.assets.set_meta("numeric_text", asset_canonical)
	game.assets.set_meta("numeric_text_pending", asset_pending)
	await command_key(root, KEY_K)
	check(game.rate.value == 3.5, "opening docket never stages")
	game._stage_docket_proposal("prices")
	await process_frame
	check(game.rate.value > 3.5 and game.assets.value == 0.75 and game.liquidity.value == 0.2, "price proposal preserves other tool offers")
	var staged: Dictionary = game._policy().duplicate(true)
	var report: AcceptDialog = game._text_dialog("Committee modal guard", "Current policy must remain staged.")
	await command_key(report, KEY_K)
	check(game._policy() == staged, "committee accelerator cannot stage behind a modal report")
	report.queue_free()
	await process_frame
	game._open_committee_docket()
	game._stage_docket_proposal("jobs")
	await process_frame
	check(game.rate.value < 3.5, "employment priority stages opposing rate")
	game._open_committee_docket()
	game._stage_docket_proposal("funding")
	await process_frame
	check(game.rate.value == 3.5 and is_equal_approx(game.liquidity.value, 2.4) and game.assets.value == 0.75, "funding priority stages current-GDP secured offer without changing assets")
	check(game.career.encode() == before and game.career.decisions.is_empty(), "every proposal stages only: no adoption or save mutation")
	# A committed decimal can be 0.35000000000000003 while native text is 0.35.
	# Open immediately, then prove the snapshot survives deferred canonical draw.
	game.assets.value = 0.35
	game.liquidity.value = 0.2
	var decimal_assets: float = game.assets.value
	var decimal_liquidity: float = game.liquidity.value
	game._open_committee_docket()
	var decimal_snapshot: PackedByteArray = game.docket_snapshot.duplicate()
	var decimal_advertised: Dictionary = game.committee_docket.quote.entries[2].policy.duplicate(true)
	var decimal_offers_preserved: bool = game.docket_controls.assets == decimal_assets and game.docket_controls.liquidity == decimal_liquidity
	check(decimal_offers_preserved, "immediate non-binary decimal setter retains committed offers in docket")
	if not decimal_offers_preserved:
		decimal_diagnostic(game, "immediate quote", decimal_assets, decimal_liquidity, decimal_advertised)
	for frame in range(3):
		await process_frame
	check(not game.assets.get_meta("numeric_text_pending") and snappedf(game.assets.get_line_edit().text.to_float(), game.assets.step) == snappedf(decimal_assets, game.assets.step), "decimal fixture reaches native canonical text on the declared numeric grid")
	check(not game._committee_has_raw_draft(game.assets) and game._committee_snapshot() == decimal_snapshot, "0.35 canonical redraw keeps snapshot classification and bytes stable")
	game._stage_docket_proposal("prices")
	for frame in range(3):
		await process_frame
	var decimal_staged_exactly: bool = game._policy() == decimal_advertised and game.assets.value == decimal_assets and game.liquidity.value == decimal_liquidity
	check(decimal_staged_exactly, "decimal redraw permits exact advertised staging while preserving other offers")
	if not decimal_staged_exactly:
		decimal_diagnostic(game, "after Stage price", decimal_assets, decimal_liquidity, decimal_advertised)
	check(game.career.encode() == before and game.career.decisions.is_empty(), "decimal staging neither adopts nor mutates career")
	# A genuine unsubmitted decimal draft must quote the exact native setter
	# representation too, not merely match to a tolerance or after GDP rounding.
	game.assets.value = 0.75
	for frame in range(3):
		await process_frame
	var raw_other_tools: Dictionary = game._policy().duplicate(true)
	var raw_career: PackedByteArray = game.career.encode()
	game.assets.get_line_edit().text = "0.35"
	check(game.assets.get_line_edit().text != game.assets.get_meta("numeric_text") and game.assets.value == 0.75, "unsubmitted 0.35 is a genuine raw edit, not a canonical setter update")
	game._open_committee_docket()
	var raw_advertised: Dictionary = game.committee_docket.quote.entries[2].policy.duplicate(true)
	var decimal_gdp: float = game.career.model.nominal_gdp_ratio(game.career.state)
	var raw_quote_exact: bool = game.docket_controls.assets == decimal_assets and raw_advertised.asset_flow_request_pct_initial_gdp == decimal_assets * decimal_gdp
	check(raw_quote_exact and game.assets.value == 0.75 and game.assets.get_line_edit().text == "0.35", "raw 0.35 quotes the independently captured native Range representation without committing it")
	if not raw_quote_exact:
		decimal_diagnostic(game, "unsubmitted raw 0.35 quote", decimal_assets, decimal_liquidity, raw_advertised)
	for frame in range(3):
		await process_frame
	game._stage_docket_proposal("prices")
	for frame in range(3):
		await process_frame
	var raw_staged_exact: bool = game._policy() == raw_advertised and game.assets.value == decimal_assets
	check(raw_staged_exact, "unsubmitted raw 0.35 stages exactly the advertised policy and native decimal value")
	if not raw_staged_exact:
		decimal_diagnostic(game, "after Stage raw 0.35", decimal_assets, decimal_liquidity, raw_advertised)
	for key in ["liquidity_request_pct_initial_gdp", "reinvest_principal", "maintain_ample_reserves", "sterilize_purchases"]:
		check(game._policy()[key] == raw_other_tools[key], "raw decimal staging preserves other tools: " + key)
	check(game.career.encode() == raw_career and game.career.encode() == before and game.career.decisions.is_empty(), "raw decimal staging never adopts or mutates the career")
	if failures == 0:
		print("PASS: opposing committee priorities, current-only information and nonmutating UI staging")
	await game._quit_app(1 if failures else 0)
