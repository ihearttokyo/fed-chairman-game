extends SceneTree
## Bounded private data export. Delegates every transition to the native careers.
const Career = preload("res://play/career.gd")
const Docket = preload("res://play/policy_docket.gd")
const Committee = preload("res://play/policy_committee.gd")
const PricedWorkout = preload("res://play/priced_workout_career.gd")
const SOURCE_COMMIT := "a91d7dfc8ee2ac04e408285b20203a047711ebd2"
const MODEL_DIGEST := "525f6c2e96c0b77e8260064d829604102a8b8c153e435874a9b942709e38f30f"
const SOURCE_HASHES := {
	"game/play/main.gd": "4b37c38d36781eb538af4442d33a3a1b86e3ad3f52369dcae2ae5c230820184d",
	"game/play/career.gd": "14cf91be15ef7108a7681df6fb7af59cdded594ca1ad6d55f9577889e7cc2d16",
	"game/play/policy_docket.gd": "cfefc2664607c5e7f6edb3602564980d58fc346baa2e828569397ca403245496",
	"game/play/policy_committee.gd": "6b4ce1988e3839469ca58de96f16c73070a0d6a444389e73dae5ff5a272c7ef4",
	"game/play/priced_workout_career.gd": "0de00775c9bf7c8df74add30f4630ef74d3da0da8d6026e0e9d05df277b7e7f9",
	"game/play/workout_career.gd": "0b6a9c7471c08bb87dea61faea47831eb9dd1ec9b80548903e2d40f4127467ae",
	"game/model/economy.gd": "0bbf3d361f4e8ad61c86c5fb27d2fc78535f759df80192ae9639fd8d918aa315",
	"game/model/parameters.json": "5d7c3d28dd27c910e8359a80beb3e4d608f1f28edbd2ef6adfe027e77b998e7a",
	"game/model/scenarios.json": "837a1db314f582f2aa8f9389928c8fe9bc7dde32565e580a78b21b1007e35197",
	"game/model/exogenous_shocks.json": "63391b29f70c4d52669cfecb5c0fbbaed1246f6369a95dfb1e38e3fa6d83e4e7",
	"game/model/portfolio_reference.json": "5e7362e82bc848e85869df0c69334f05eb68349b19bf84f7bd7d03b283b19e7e",
}
const METRICS := {
	"quarter": "quarter_index", "inflation": "four_quarter_inflation_pct",
	"unemployment": "unemployment_rate_pct", "output_gap": "output_gap_pct",
	"uncovered_funding": "uncovered_funding_pct_initial_gdp", "credibility": "credibility",
	"support": "public_support", "assets": "total_assets_pct_initial_gdp",
	"loans": "outstanding_liquidity_pct_initial_gdp",
}
const COMMON_PATHS := ["game/play/career.gd", "game/model/economy.gd", "game/model/parameters.json", "game/model/scenarios.json"]
var failure := ""
var validation_errors: Array[String] = []
var normalized_key_count := 0
var normalized_value_count := 0
const MAX_VALIDATION_ERRORS := 48

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--output":
		_refuse("Usage: -- --output /absolute/new/path/lessons.json (no default or replacement)")
		return
	var destination: String = args[1]
	var root := ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/").get_base_dir()
	if not destination.is_absolute_path() or not destination.begins_with("/") or destination != destination.simplify_path() or destination.get_extension() != "json":
		_refuse("Output must be an absolute normalized filesystem .json path.")
		return
	if destination == root or destination.begins_with(root + "/") or FileAccess.file_exists(destination) or DirAccess.dir_exists_absolute(destination):
		_refuse("Refusing repository output or replacement. Use a fresh external directory.")
		return
	for path in SOURCE_HASHES:
		if FileAccess.get_sha256("res://" + path.trim_prefix("game/")) != SOURCE_HASHES[path]:
			_refuse("Finalized source mismatch: " + path)
			return
	if not _check_roundtrip_comparator():
		_refuse("Exact-value comparator self-check failed:\n" + "\n".join(validation_errors))
		return
	var lessons := _lessons()
	if not failure.is_empty():
		_refuse(failure)
		return
	var raw := {"schema_version": 1, "source_commit": SOURCE_COMMIT, "model_digest": MODEL_DIGEST, "lessons": lessons}
	var raw_untouched := var_to_bytes(raw)
	# Dot-assigned/native dictionary keys can be StringName. Canonicalize only
	# textual representations, never numeric values; reject any key collision.
	var document: Dictionary = _json_tree(raw, "$")
	if normalized_key_count > 0 or normalized_value_count > 0:
		print("WALKTHROUGH_NORMALIZATION: StringName keys=%d values=%d; numeric values unchanged" % [normalized_key_count, normalized_value_count])
	if var_to_bytes(raw) != raw_untouched:
		_refuse("JSON normalization mutated its native input.")
		return
	if not validation_errors.is_empty():
		_refuse("JSON normalization failed:\n" + "\n".join(validation_errors))
		return
	if not _valid_document(document):
		_refuse("Native document validation failed:\n" + "\n".join(validation_errors))
		return
	# Capture native bits BEFORE serializing. Consumer proof is independent of
	# Godot's JSON parser, which is nonqualifying for exact numeric recovery.
	var untouched := var_to_bytes(document)
	var floats := {}
	_collect_native_float64(document, "", floats)
	if floats.is_empty() or var_to_bytes(document) != untouched or var_to_bytes(raw) != raw_untouched:
		_refuse("Native float64 proof collection failed or mutated its input.")
		return
	var encoded := JSON.stringify(document, "", true, true)
	if var_to_bytes(document) != untouched or var_to_bytes(raw) != raw_untouched:
		_refuse("JSON encoding mutated the original document.")
		return
	# Retain the parser's syntax/schema checks only. Its float recovery is
	# NONQUALIFYING for exact-value proof; the independent consumer checks bits.
	var parsed: Variant = JSON.parse_string(encoded)
	if not parsed is Dictionary:
		_refuse("JSON parsed syntax/shape check failed; expected Dictionary.")
		return
	if not _valid_document(parsed):
		_refuse("JSON parsed schema check failed (nonqualifying for numeric fidelity):\n" + "\n".join(validation_errors))
		return
	if var_to_bytes(document) != untouched or var_to_bytes(raw) != raw_untouched:
		_refuse("JSON schema check mutated the original document.")
		return
	var proof := {"schema_version": 1, "source_commit": SOURCE_COMMIT, "model_digest": MODEL_DIGEST,
		"endianness": "little", "float_count": floats.size(), "floats": floats,
		"json_sha256": (encoded + "\n").sha256_text()}
	var proof_untouched := var_to_bytes(proof)
	var proof_json := JSON.stringify(proof, "", true, true)
	if var_to_bytes(proof) != proof_untouched or var_to_bytes(document) != untouched or var_to_bytes(raw) != raw_untouched:
		_refuse("Native proof encoding mutated its input.")
		return
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		_refuse("Cannot create the requested output file.")
		return
	output.store_string(encoded + "\n")
	output.flush()
	var error := output.get_error()
	output.close()
	if error != OK:
		_refuse("Output write failed; inspect the destination before retrying.")
		return
	print("WALKTHROUGH_NATIVE_FLOAT64 " + proof_json)
	print("WALKTHROUGH_EXPORT_OK: 8 lessons; native conditional forecasts; " + destination)
	quit(0)

func _refuse(message: String) -> void:
	push_error(message)
	quit(1)

func _start(case_id: String, seed_number: int, held_quarters: int = 0) -> Career:
	var career := Career.new()
	var result: Dictionary = career.start(case_id, seed_number)
	if not result.ok or career.model_digest() != MODEL_DIGEST:
		failure = "Career start/digest failed: " + case_id
		return null
	for _q in range(held_quarters):
		result = career.advance(_hold(career))
		if not result.ok:
			failure = "Authored hold prelude failed: " + case_id
			return null
	return career

func _hold(career: Career) -> Dictionary:
	var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold")
	for key in career.model.POLICY_SWITCHES:
		policy[key] = career.model.POLICY_SWITCHES[key]
	return policy

func _rate(policy: Dictionary, value: float) -> Dictionary:
	var changed := policy.duplicate(true)
	changed.policy_rate_request_pct = value
	changed.guidance_rate_pct = value
	return changed

func _choice(id: String, label: String, policy: Dictionary, notes: Array = [], follow: bool = false) -> Dictionary:
	return {"id": id, "label": label, "action": label, "policy": policy, "notes": notes, "follow": follow}

func _native_entry_metadata(career: Career) -> Dictionary:
	# Capture THIS opening/decision state, never a future forecast endpoint.
	var payload_before := var_to_bytes(career.payload())
	var state_before := var_to_bytes(career.state)
	var ratio: float = career.model.nominal_gdp_ratio(career.state)
	if var_to_bytes(career.payload()) != payload_before or var_to_bytes(career.state) != state_before:
		failure = "Impure native GDP-ratio metadata lookup."
		return {}
	var quarter: Variant = career.state.get("quarter_index")
	if not is_finite(ratio) or ratio <= 0.0 or typeof(quarter) not in [TYPE_INT, TYPE_FLOAT]:
		failure = "Unavailable native entry ratio/decision quarter."
		return {}
	if not is_finite(float(quarter)) or quarter < 0 or quarter > 9007199254740991 or int(quarter) != quarter:
		failure = "Invalid native entry decision quarter."
		return {}
	# Scalar copies have no mutable state alias; document float proof covers ratio.
	return {"decision_quarter": int(quarter), "nominal_gdp_ratio": ratio}

func _lesson(career: Career, id: String, title: String, task: String, choices: Array, takeaway: String, steps: Array, paths: Array = []) -> Dictionary:
	if career == null:
		return {}
	var native_entry := _native_entry_metadata(career)
	if native_entry.is_empty():
		return {}
	var entry_untouched := var_to_bytes(native_entry)
	var before := {}
	for key in ["inflation", "unemployment", "output_gap", "credibility", "support"]:
		before[key] = career.state[METRICS[key]]
	var options: Array = []
	for choice in choices:
		var original := var_to_bytes(career.payload())
		var valid: Dictionary = career.model._validate_policy(choice.policy, career.params)
		if not valid.ok:
			failure = "Invalid native policy: " + id + "/" + choice.id + ": " + str(valid.get("error", "no native error"))
			return {}
		var forecast: Dictionary = career.forecast(choice.policy, choice.follow)
		if var_to_bytes(career.payload()) != original or var_to_bytes(native_entry) != entry_untouched:
			failure = "Impure native forecast: " + id + "/" + choice.id
			return {}
		if not forecast.get("ok", false) or not forecast.get("states") is Array or forecast.states.size() != 8:
			failure = "Unavailable native forecast: " + id + "/" + choice.id + ": " + str(forecast.get("error", "states must have eight entries"))
			return {}
		var path: Array = []
		for state in forecast.states:
			var point := {}
			for key in METRICS:
				point[key] = state[METRICS[key]]
			path.append(point)
		var notes: Array = choice.notes.duplicate()
		notes.append("Fictional conditional path: today's known shock/request only; no new future shocks/withdrawals.")
		notes.append("Q2–Q8 follow the native conditional commitment; no new asset/loan offers." if choice.follow else "Q2–Q8 hold the applied rate; no new asset/loan offers; portfolio switches persist.")
		var option := {"id": choice.id, "label": choice.label, "action": choice.action, "policy": choice.policy.duplicate(true), "path": path, "notes": notes}
		if forecast.has("bank_states"):
			option.ledger = {}
			for key in ["bank_states", "credit_states", "credit_results", "bank_results", "credit_contexts"]:
				option.ledger[key] = forecast[key].duplicate(true)
		options.append(option)
	var sources: Array = COMMON_PATHS.duplicate()
	for source in paths:
		if source not in sources:
			sources.append(source)
	return {"id": id, "title": title, "task": task, "scenario": career.scenario_id, "seed": career.seed_value, "mode": "conditional", "source_paths": sources, "before": before, "native_entry": native_entry, "options": options, "takeaway": takeaway, "native_steps": steps}

func _lessons() -> Array:
	var lessons: Array = []
	var career := _start("stagflation_bank_run", 417)
	if career == null:
		return []
	var held := _hold(career)
	var choices: Array = []
	var original := var_to_bytes(career.payload())
	# Native public-data proposals and the exact native docket policy conversion.
	var n: float = career.model.nominal_gdp_ratio(career.state)
	for proposal in Committee.proposals(career.state, career.params, career.current_briefing(), n):
		choices.append(_choice(proposal.id, proposal.label, Docket.policy_for(proposal, held, career.params, n), [proposal.tradeoff]))
	if var_to_bytes(career.payload()) != original:
		failure = "Committee quote mutated the career."
	lessons.append(_lesson(career, "committee", "Competing priorities", "Compare prices, jobs and secured funding; none is a universal winner.", choices,
		"A supply-and-funding crisis forces tradeoffs; committee proposals are fictional aids, not optimal rules.",
		["Start Stagflation & bank run, seed 417, Q0.", "Open Policy committee (Cmd/Ctrl+K); compare priorities, then Stage or Escape without adopting.", "Native Help and dispatch briefing provide context; Recovery v1 is separate from Mandate v1."],
		["game/play/policy_committee.gd", "game/play/policy_docket.gd", "game/play/dispatch_brief.gd", "game/play/objective_board.gd"]))

	career = _start("lower_bound_slump", 113)
	if career == null:
		return []
	held = _hold(career)
	lessons.append(_lesson(career, "rates", "Zero and negative rates", "Compare holding zero with a signed −2% request.",
		[_choice("zero", "Hold 0%", held), _choice("negative", "Request −2%", _rate(held, -2.0), ["Negative-rate transmission diminishes; this is a fictional US counterfactual."])],
		"Requested rates are not linear economic stimulus; financial conditions and activity adjust with lags.",
		["Start Zero-rate slump, seed 113, Q0.", "Stage a signed policy rate and matching guidance; Compare before Adopt."]))

	career = _start("unanchored_inflation", 217)
	if career == null:
		return []
	held = _hold(career)
	var contingent := held.duplicate(true)
	contingent.guidance_rate_pct = 2.5
	var fixed := contingent.duplicate(true)
	fixed.guidance_inflation_sensitivity = 0.0
	fixed.guidance_output_gap_sensitivity = 0.0
	lessons.append(_lesson(career, "guidance", "A conditional promise", "Compare a fixed announcement with the standard data-dependent responses.",
		[_choice("fixed", "Promise 2.5%, no responses", fixed, [], true), _choice("conditional", "Promise 2.5%, data-dependent", contingent, [], true)],
		"Follow-through is evaluated against the prior promise and its published conditions, not merely today's rate.",
		["Start Weakly anchored inflation, seed 217, Q0.", "Set guidance and its inflation/output-gap responses; inspect the follow-guidance comparison.", "Native routine follow-up is a separate public-data adaptive path, not this forecast."], ["game/play/routine_follow_up.gd"]))

	career = _start("base", 315)
	if career == null:
		return []
	held = _hold(career)
	var purchase := held.duplicate(true)
	purchase.asset_flow_request_pct_initial_gdp = 2.0
	var sterilized := purchase.duplicate(true)
	sterilized.sterilize_purchases = true
	var runoff := held.duplicate(true)
	runoff.reinvest_principal = false
	var reserves := purchase.duplicate(true)
	reserves.maintain_ample_reserves = false
	lessons.append(_lesson(career, "portfolio", "Assets are not the policy rate", "Separate purchases, reinvestment, sterilization and reserve maintenance.",
		[_choice("hold", "No new purchases", held), _choice("purchase", "Purchase 2% initial GDP", purchase), _choice("sterilize", "Same purchase, sterilized", sterilized), _choice("runoff", "Stop reinvesting principal", runoff), _choice("reserves", "Purchase, no reserve maintenance", reserves)],
		"Security duration and reserves are distinct native channels; switches persist, fresh purchase offers do not.",
		["Start Equilibrium baseline, seed 315, Q0.", "Stage purchases and the three portfolio switches; inspect the native balance-sheet report."]))

	career = _start("funding_stress", 419, 4)
	if career == null:
		return []
	held = _hold(career)
	var lending := held.duplicate(true)
	lending.liquidity_request_pct_initial_gdp = 3.0
	lessons.append(_lesson(career, "liquidity", "Funding is not capital", "Compare no lending with a secured 3% initial-GDP offer at the known funding event.",
		[_choice("none", "No lending offer", held), _choice("secured", "Offer secured liquidity", lending, ["Collateral and eligibility constrain actual lending; impairment is a separate wedge."])],
		"Secured loans can cover eligible payment needs; they cannot recapitalize an insolvent bank.",
		["Start Funding stress, seed 419; adopt native Hold four times to Q4.", "Read today's funding briefing, then compare loan offers without changing the rate."]))

	career = _start("unanchored_inflation", 521)
	if career == null:
		return []
	held = _hold(career)
	lessons.append(_lesson(career, "credibility", "Trust takes time", "Compare holding 3.5% with a 5% rate and matching guidance.",
		[_choice("hold", "Hold 3.5%", held), _choice("tighten", "Request 5%", _rate(held, 5.0))],
		"Short and long expectations differ; credibility reflects demonstrated consistency, while support tracks hardship. Neither is a welfare score.",
		["Start Weakly anchored inflation, seed 521, Q0.", "Inspect market expectations, credibility and public support in the native briefing.", "Use the native decision review after adoption; eight forecast quarters do not prove a 60-year Mandate award."]))

	career = _start("lower_bound_slump", 613, 4)
	if career == null:
		return []
	held = _hold(career)
	lessons.append(_lesson(career, "recovery", "Deferred demand and recovery", "After four zero-rate meetings, compare holding with a −1% request.",
		[_choice("hold", "Keep holding 0%", held), _choice("ease", "Request −1%", _rate(held, -1.0))],
		"Recovery combines inherited restraint, deferred demand, cancellation and shocks; it is not the isolated effect of the latest rate.",
		["Start Zero-rate slump, seed 613; adopt native Hold four times to Q4.", "Compare the next eight quarters; later unknown events are deliberately absent.", "Native routine follow-up and its interval explanation cover realized decisions, not this held-rate path."], ["game/play/routine_follow_up.gd", "game/play/transition_explanation.gd"]))

	var workout := PricedWorkout.new()
	var opening: Dictionary = workout.model.bank_workout_opening(workout.params)
	if not opening.ok:
		failure = "Native workout recipe unavailable."
		return []
	var started: Dictionary = workout.start_episode(opening.bank, opening.requests, opening.haircut_pct, opening.pledgeable_share, "stagflation_bank_run", 417, opening.remaining_request_index)
	if not started.ok:
		failure = "Native priced-workout start failed."
		return []
	held = _hold(workout)
	var credit := held.duplicate(true)
	credit.liquidity_request_pct_initial_gdp = 4.0
	lessons.append(_lesson(workout, "workout", "Borrowing has a cost", "Compare no offer, secured borrowing and a negative-rate counterfactual.",
		[_choice("none", "No fresh loan offer", held), _choice("loan", "Offer 4% initial GDP", credit), _choice("negative", "Same offer, request −2%", _rate(credit, -2.0), ["Negative contractual APR uses the native diminishing-transmission map; collectible claims are authored."])],
		"Maturities, cash payments, renewal, arrears and interest claims stay separate. Loans are not equity; this ledger is not GAAP or exact Fed credit governance.",
		["Start Bank workout · borrowing costs, Stagflation & bank run, seed 417, Q0; use the native parameter recipe.", "Compare the credit panel and bank ledger before Adopt; no normal save slots or awards.", "Native workout debrief reviews actual settlements; this private page is not the full browser game."],
		["game/play/priced_workout_career.gd", "game/play/workout_career.gd", "game/play/priced_credit_panel.gd", "game/play/workout_debrief.gd"]))
	return lessons

func _problem(context: String, reason: String, actual: Variant = null) -> bool:
	if validation_errors.size() < MAX_VALIDATION_ERRORS:
		# Only a bounded offending value, never whole careers or future tapes.
		validation_errors.append("%s: %s; type=%s value=%s" % [context, reason, type_string(typeof(actual)), str(actual).left(320)])
	return false

func _difference(context: String, reason: String, expected: Variant, actual: Variant) -> bool:
	if validation_errors.size() < MAX_VALIDATION_ERRORS:
		# JSON full precision makes even one-ULP numeric drift visible in the log.
		validation_errors.append("%s: %s; expected(%s)=%s; actual(%s)=%s" % [context, reason,
			type_string(typeof(expected)), JSON.stringify(expected, "", true, true).left(160),
			type_string(typeof(actual)), JSON.stringify(actual, "", true, true).left(160)])
	return false

func _same_json(expected: Variant, actual: Variant, context: String) -> bool:
	var expected_number := expected is int or expected is float
	var actual_number := actual is int or actual is float
	if expected_number or actual_number:
		if not expected_number or not actual_number:
			return _difference(context, "numeric/non-numeric type mismatch", expected, actual)
		if (expected is float and not is_finite(expected)) or (actual is float and not is_finite(actual)):
			return _difference(context, "nonfinite roundtrip number", expected, actual)
		if typeof(expected) != typeof(actual):
			# Do not let implicit int-to-float conversion conceal lost integer bits.
			# Godot ints are signed int64; +2^63 is excluded before int conversion.
			var integer: int = expected if expected is int else actual
			var floating: float = actual if actual is float else expected
			if floating < -9223372036854775808.0 or floating >= 9223372036854775808.0 or floating != floor(floating):
				return _difference(context, "numeric value drift", expected, actual)
			if int(floating) != integer:
				return _difference(context, "numeric value drift", expected, actual)
			return true
		return true if expected == actual else _difference(context, "numeric value drift", expected, actual)
	if typeof(expected) != typeof(actual):
		return _difference(context, "JSON type mismatch", expected, actual)
	var valid := true
	if expected is Array:
		if expected.size() != actual.size():
			return _difference(context, "array length differs", expected.size(), actual.size())
		for index in range(expected.size()):
			if not _same_json(expected[index], actual[index], "%s[%d]" % [context, index]):
				valid = false
		return valid
	if expected is Dictionary:
		for key in expected:
			if not actual.has(key):
				_difference(context + "." + key, "missing dictionary key", key, null)
				valid = false
			elif not _same_json(expected[key], actual[key], context + "." + key):
				valid = false
		for key in actual:
			if not expected.has(key):
				_difference(context + "." + key, "unexpected dictionary key", null, key)
				valid = false
		return valid
	if expected is String or expected is bool or expected == null:
		return true if expected == actual else _difference(context, "JSON scalar differs", expected, actual)
	return _difference(context, "unsupported JSON comparison type", expected, actual)

func _check_roundtrip_comparator() -> bool:
	# Synthetic validator cases only, not economic expected results or export data.
	var cases := [
		{"id": "int-float", "left": 1, "right": 1.0, "equal": true},
		{"id": "float-int", "left": 1.0, "right": 1, "equal": true},
		{"id": "ulp-drift", "left": 1.0, "right": 1.0000000000000002, "equal": false},
		{"id": "integer-bits", "left": 9007199254740993, "right": 9007199254740992.0, "equal": false},
		{"id": "array-order", "left": [1, 2], "right": [2, 1], "equal": false},
		{"id": "array-length", "left": [1], "right": [1, 2], "equal": false},
		{"id": "keys", "left": {"a": 1}, "right": {"b": 1}, "equal": false},
		{"id": "extra-key", "left": {"a": 1}, "right": {"a": 1, "b": null}, "equal": false},
		{"id": "key-order", "left": {"a": 1, "b": "x"}, "right": {"b": "x", "a": 1.0}, "equal": true},
		{"id": "string", "left": "x", "right": "X", "equal": false},
		{"id": "bool-number", "left": true, "right": 1, "equal": false},
		{"id": "null", "left": null, "right": null, "equal": true},
		{"id": "nonfinite", "left": INF, "right": INF, "equal": false},
	]
	for test in cases:
		validation_errors.clear()
		var original := var_to_bytes([test.left, test.right])
		var equal := _same_json(test.left, test.right, "$self_test." + test.id)
		if equal != test.equal or var_to_bytes([test.left, test.right]) != original:
			_problem("$self_test." + test.id, "unexpected comparator result or mutated input", equal)
			return false
	validation_errors.clear()
	print("WALKTHROUGH_ROUNDTRIP_GUARDS_OK: synthetic comparator tests only; NONQUALIFYING for Godot JSON parser fidelity")
	return true

func _collect_native_float64(value: Variant, pointer: String, floats: Dictionary) -> void:
	if value is float:
		# PackedByteArray.encode_double writes IEEE-754 binary64 little endian.
		var bytes := PackedByteArray()
		bytes.resize(8)
		bytes.encode_double(0, value)
		floats[pointer] = bytes.hex_encode()
	elif value is Array:
		for index in range(value.size()):
			_collect_native_float64(value[index], pointer + "/" + str(index), floats)
	elif value is Dictionary:
		for key in value:
			var token: String = key.replace("~", "~0").replace("/", "~1")
			_collect_native_float64(value[key], pointer + "/" + token, floats)

func _json_tree(value: Variant, context: String) -> Variant:
	if value is StringName:
		normalized_value_count += 1
		return String(value)
	if value is Array:
		var normalized: Array = []
		for index in range(value.size()):
			normalized.append(_json_tree(value[index], "%s[%d]" % [context, index]))
		return normalized
	if value is Dictionary:
		var normalized := {}
		for key in value:
			if not key is String and not key is StringName:
				_problem(context, "JSON key is not String/StringName", key)
				continue
			if key is StringName:
				normalized_key_count += 1
			var text_key := String(key)
			if normalized.has(text_key):
				_problem(context, "JSON key collision after textual normalization", text_key)
				continue
			normalized[text_key] = _json_tree(value[key], context + "." + text_key)
		return normalized
	return value

func _finite(value: Variant, context: String = "$") -> bool:
	if value is float:
		return true if is_finite(value) else _problem(context, "nonfinite number", value)
	if value is int or value is String or value is bool or value == null:
		return true
	var valid := true
	if value is Array:
		for index in range(value.size()):
			if not _finite(value[index], "%s[%d]" % [context, index]):
				valid = false
		return valid
	if value is Dictionary:
		for key in value:
			if not key is String:
				_problem(context, "noncanonical JSON key", key)
				valid = false
			elif not _finite(value[key], context + "." + key):
				valid = false
		return valid
	return _problem(context, "unsupported JSON value", value)

func _numeric_fields(data: Dictionary, keys: Array, context: String) -> bool:
	var valid := true
	for key in keys:
		var value: Variant = data.get(key)
		if not value is float and not value is int:
			_problem(context + "." + key, "missing/non-numeric native metric", value)
			valid = false
	return valid

func _valid_document(data: Dictionary) -> bool:
	validation_errors.clear()
	_finite(data)
	if data.get("schema_version") != 1:
		_problem("$.schema_version", "expected 1", data.get("schema_version"))
	if data.get("source_commit") != SOURCE_COMMIT:
		_problem("$.source_commit", "finalized source mismatch", data.get("source_commit"))
	if data.get("model_digest") != MODEL_DIGEST:
		_problem("$.model_digest", "native model digest mismatch", data.get("model_digest"))
	if not data.get("lessons") is Array or data.lessons.size() != 8:
		return _problem("$.lessons", "expected eight lessons", data.get("lessons", []).size() if data.get("lessons") is Array else null)
	var ids: Array = []
	for lesson_index in range(data.lessons.size()):
		var lesson: Variant = data.lessons[lesson_index]
		var context := "$.lessons[%d]" % lesson_index
		if not lesson is Dictionary or lesson.is_empty():
			_problem(context, "missing/non-dictionary lesson")
			continue
		var lesson_id: Variant = lesson.get("id")
		context += "(id=%s)" % str(lesson_id)
		if not lesson_id is String or lesson_id.is_empty() or lesson_id in ids:
			_problem(context + ".id", "empty/non-string/duplicate lesson ID", lesson_id)
		ids.append(lesson_id)
		if lesson.get("mode") != "conditional":
			_problem(context + ".mode", "expected conditional", lesson.get("mode"))
		if not lesson.get("before") is Dictionary or lesson.before.size() != 5:
			_problem(context + ".before", "expected five initial metrics")
		elif _numeric_fields(lesson.before, ["inflation", "unemployment", "output_gap", "credibility", "support"], context + ".before"):
			_check_units(lesson.before, context + ".before")
		var entry: Variant = lesson.get("native_entry")
		var entry_valid := false
		if not entry is Dictionary or entry.size() != 2:
			_problem(context + ".native_entry", "expected immutable decision quarter and nominal GDP ratio")
		elif _numeric_fields(entry, ["decision_quarter", "nominal_gdp_ratio"], context + ".native_entry"):
			entry_valid = is_finite(float(entry.nominal_gdp_ratio)) and entry.nominal_gdp_ratio > 0.0 and is_finite(float(entry.decision_quarter)) and entry.decision_quarter >= 0 and entry.decision_quarter <= 9007199254740991
			if entry_valid:
				entry_valid = int(entry.decision_quarter) == entry.decision_quarter
			if not entry_valid:
				_problem(context + ".native_entry", "expected positive finite decision GDP ratio and nonnegative integral quarter", entry)
		if not lesson.get("source_paths") is Array or lesson.source_paths.is_empty():
			_problem(context + ".source_paths", "expected nonempty source paths")
		else:
			for source in lesson.source_paths:
				if not source is String:
					_problem(context + ".source_paths", "non-string source path", source)
				elif not source.begins_with("game/") or not FileAccess.file_exists("res://" + source.trim_prefix("game/")):
					_problem(context + ".source_paths", "missing/invalid repository source path", source)
		if not lesson.get("options") is Array or lesson.options.size() < 2:
			_problem(context + ".options", "expected at least two choices")
			continue
		var policies: Array = []
		var option_ids: Array = []
		for option_index in range(lesson.options.size()):
			var option: Variant = lesson.options[option_index]
			var option_context := context + ".options[%d]" % option_index
			if not option is Dictionary:
				_problem(option_context, "non-dictionary choice")
				continue
			option_context += "(id=%s)" % str(option.get("id"))
			if not option.get("id") is String or option.id.is_empty() or option.id in option_ids:
				_problem(option_context + ".id", "empty/non-string/duplicate option ID", option.get("id"))
			option_ids.append(option.get("id"))
			if not option.get("policy") is Dictionary:
				_problem(option_context + ".policy", "missing/non-dictionary native policy")
			elif option.policy in policies:
				_problem(option_context + ".policy", "duplicate policy of option index %d" % policies.find(option.policy), option.policy)
			policies.append(option.get("policy"))
			if not option.get("path") is Array or option.path.size() != 8:
				_problem(option_context + ".path", "expected eight quarterly observations")
				continue
			var previous := -1
			for point_index in range(option.path.size()):
				var point: Variant = option.path[point_index]
				var point_context := option_context + ".path[%d]" % point_index
				if not point is Dictionary:
					_problem(point_context, "non-dictionary quarterly point")
					continue
				if point.size() != METRICS.size():
					_problem(point_context, "expected exact metric keys", point.keys())
				if not _numeric_fields(point, METRICS.keys(), point_context):
					continue
				if not is_finite(float(point.quarter)) or int(point.quarter) != point.quarter:
					_problem(point_context + ".quarter", "expected finite integer quarter", point.quarter)
					continue
				if entry_valid and point_index == 0 and point.quarter != entry.decision_quarter + 1:
					_problem(point_context + ".quarter", "expected quarter immediately after native entry decision", point.quarter)
				if previous >= 0 and point.quarter != previous + 1:
					_problem(point_context + ".quarter", "expected quarter %d" % (previous + 1), point.quarter)
				previous = int(point.quarter)
				_check_units(point, point_context)
				for stock in ["uncovered_funding", "assets", "loans"]:
					if point[stock] < 0.0:
						_problem(point_context + "." + stock, "negative native stock/funding", point[stock])
	return validation_errors.is_empty()

func _check_units(point: Dictionary, context: String) -> void:
	if point.credibility < 0.0 or point.credibility > 1.0:
		_problem(context + ".credibility", "expected raw native fraction 0..1", point.credibility)
	if point.support < 0.0 or point.support > 100.0:
		_problem(context + ".support", "expected raw native support 0..100", point.support)
