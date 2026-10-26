extends SceneTree
## Unshipped experiment. Replays a frozen parent-policy tape, not an optimizer.
const Economy = preload("res://model/economy.gd")
const Advice = preload("res://play/policy_advice.gd")
const DAYS := [90, 91, 92, 92]
const POLICIES := ["hold", "zero", "tight", "very_tight", "negative", "no_support", "partial", "public_staff"]
var failures := 0
var checks := 0
var finance_interest := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func same_legacy(expected: Variant, actual: Variant) -> bool:
	if typeof(expected) != typeof(actual): return false
	if expected is Dictionary:
		for key in expected:
			if not actual.has(key) or not same_legacy(expected[key], actual[key]): return false
		for key in actual:
			if not expected.has(key) and key not in ["credit_state", "credit_result"]: return false
		return true
	if expected is Array:
		if expected.size() != actual.size(): return false
		for i in range(expected.size()):
			if not same_legacy(expected[i], actual[i]): return false
		return true
	return var_to_bytes(expected) == var_to_bytes(actual)

func request_for(model: Object, bank: Dictionary, recipe: Dictionary, quarter: int) -> float:
	if quarter == recipe.remaining_request_index:
		var left: Dictionary = model.bank_workout_remaining_request(bank)
		check(left.ok, "Remaining request is physically valid")
		return left.get("request", NAN)
	return recipe.requests[quarter]

func order_for(model: Object, bank: Dictionary, recipe: Dictionary, quarter: int) -> Dictionary:
	return {"new_withdrawals": request_for(model, bank, recipe, quarter),
		"haircut_pct": recipe.haircut_pct, "pledgeable_share": recipe.pledgeable_share}

func parent_tape(model: Object, initial: Dictionary, recipe: Dictionary, params: Dictionary, shocks: Array, policy_id: String) -> Dictionary:
	var state := initial.duplicate(true)
	var bank: Dictionary = recipe.bank.duplicate(true)
	var tape: Array = []
	var frames: Array = []
	for q in range(8):
		var policy: Dictionary = Advice.policy(state, params) if policy_id == "public_staff" else model.benchmark_policy(state, params, "hold")
		if policy_id != "public_staff":
			var rate: float = {"hold": 3.5, "zero": 0.0, "tight": 6.0, "very_tight": 10.0, "negative": -2.0, "no_support": 6.0, "partial": 6.0}[policy_id]
			policy.policy_rate_request_pct = rate
			policy.guidance_rate_pct = rate
		policy.liquidity_request_pct_initial_gdp = 0.0 if policy_id == "no_support" else 0.6 if policy_id == "partial" else 4.0
		var result: Dictionary = model.bank_workout_transition(state, policy, shocks[q], params, bank, order_for(model, bank, recipe, q))
		if not result.ok: return {"ok": false, "error": "Parent: " + result.error}
		tape.append(policy.duplicate(true))
		frames.append(result.duplicate(true))
		state = result.state
		bank = result.bank_state
	return {"ok": true, "policies": tape, "frames": frames}

func replay(model: Object, initial: Dictionary, recipe: Dictionary, params: Dictionary, shocks: Array, tape: Array, treatment: String) -> Dictionary:
	var frozen := var_to_bytes([initial, recipe, params, shocks, tape])
	var state := initial.duplicate(true)
	var bank: Dictionary = recipe.bank.duplicate(true)
	var claims := {"payable": 0.0, "receivable": 0.0}
	var frames: Array = []
	var inflation_cost := 0.0
	var employment_cost := 0.0
	var mean_unpaid_withdrawals := 0.0
	var mean_uncovered_funding := 0.0
	var accrued := 0.0
	var cash_paid := 0.0
	var gross_cash_interest := 0.0
	var last: Dictionary = {}
	for q in range(8):
		var policy: Dictionary = tape[q].duplicate(true)
		var order := order_for(model, bank, recipe, q)
		var result: Dictionary
		var credit: Dictionary = {}
		if treatment == "legacy":
			result = model.bank_workout_transition(state, policy, shocks[q], params, bank, order)
		else:
			credit = {"annual_rate_pct": policy.policy_rate_request_pct if treatment in ["priced", "cash_only"] else 0.0,
				"days": DAYS[q % 4], "payable": claims.payable, "receivable": claims.receivable,
				"collectible": true, "allow_negative": true}
			if finance_interest and treatment != "cash_only":
				credit.finance_interest = true
			result = model.bank_workout_transition(state, policy, shocks[q], params, bank, order, credit)
		if not result.ok:
			check(var_to_bytes([initial, recipe, params, shocks, tape]) == frozen, "Refused replay preserves supplied inputs")
			return {"ok": false, "error": result.error, "meeting": q + 1, "treatment": treatment,
				"native_inputs_base64": Marshalls.raw_to_base64(var_to_bytes([state, policy, shocks[q], params, bank, order, credit]))}
		if treatment != "legacy":
			if not result.has("credit_state") or not result.has("credit_result"):
				return {"ok": false, "error": "Coupled credit diagnostics missing", "meeting": q + 1}
			var cost: Dictionary = result.credit_result
			for key in ["accrued_positive", "accrued_negative", "paid_positive", "paid_negative", "net_cash_to_bank", "bank_equity_before", "bank_equity_after", "fed_interest_income"]:
				if not cost.has(key) or not is_finite(float(cost[key])):
					return {"ok": false, "error": "Finite credit diagnostic required: " + key, "meeting": q + 1}
			claims = result.credit_state.duplicate(true)
			var net_accrual: float = cost.accrued_positive - cost.accrued_negative
			check(cost.fed_interest_income == net_accrual, "Fed recognizes accrual, not a second income at cash settlement")
			check(absf((cost.bank_equity_after - cost.bank_equity_before) - (result.bank_result.expected_equity_change - cost.net_cash_to_bank - net_accrual)) <= 1e-10, "Combined bank equity bridge separates valuation from interest expense")
			accrued += cost.accrued_positive - cost.accrued_negative
			cash_paid += cost.paid_positive - cost.paid_negative
			gross_cash_interest += cost.paid_positive + cost.paid_negative
		frames.append(result.duplicate(true))
		state = result.state
		bank = result.bank_state
		last = result
		inflation_cost += absf(state.four_quarter_inflation_pct - 2.0) / 8.0
		employment_cost += maxf(0.0, state.unemployment_rate_pct - state.structural_unemployment_pct) / 8.0
		mean_unpaid_withdrawals += bank.withdrawal_queue / 8.0
		mean_uncovered_funding += state.uncovered_funding_pct_initial_gdp / 8.0
	check(var_to_bytes([initial, recipe, params, shocks, tape]) == frozen, "Replay never rewrites its frozen policy/shock/opening inputs")
	var equity: float = last.bank_result.equity_after if treatment == "legacy" else last.credit_result.bank_equity_after
	if treatment != "legacy":
		check(absf((state.capital_other_pct_initial_gdp - initial.capital_other_pct_initial_gdp) - cash_paid) <= 1e-10, "Core Fed capital contains only actually settled net interest")
		check(absf((state.capital_other_pct_initial_gdp + claims.payable - claims.receivable - initial.capital_other_pct_initial_gdp) - accrued) <= 1e-10, "Combined Fed capital recognizes accrued claims exactly once")
	return {"ok": true, "frames": frames, "metrics": {"inflation_distance_pp": inflation_cost,
		"employment_shortfall_pp": employment_cost, "ending_queue": bank.withdrawal_queue,
		"mean_unpaid_withdrawals": mean_unpaid_withdrawals, "mean_uncovered_funding": mean_uncovered_funding,
		"ending_cb_principal": bank.central_bank_loan, "ending_uncovered_funding": state.uncovered_funding_pct_initial_gdp,
		"ending_principal_arrears": bank.loan_arrears, "ending_equity": equity,
		"net_accrued_interest": accrued, "net_cash_interest": cash_paid, "gross_cash_interest": gross_cash_interest, "ending_interest": claims}}

func _initialize() -> void:
	var baseline_path := OS.get_environment("FED_PRICED_BASELINE_MODEL")
	var output := OS.get_environment("FED_PRICED_REPORT")
	if baseline_path.is_empty() or not FileAccess.file_exists(baseline_path) or output.is_empty() or FileAccess.file_exists(output):
		printerr("FAIL: original model and new external report path required; existing reports never replaced")
		quit(2)
		return
	var original = load(baseline_path).new()
	var candidate := Economy.new()
	finance_interest = OS.get_environment("FED_PRICED_FINANCE_INTEREST") == "1"
	var cohort := OS.get_environment("FED_PRICED_COHORT")
	if cohort not in ["", "development", "holdout_B"]:
		printerr("FAIL: unknown study cohort")
		quit(2)
		return
	var candidate_hash := FileAccess.get_sha256("res://model/economy.gd")
	var original_hash := FileAccess.get_sha256(baseline_path)
	var loaded: Dictionary = original.load_parameters()
	var scenarios: Dictionary = original.load_scenarios()
	if not loaded.ok or not scenarios.ok:
		printerr("FAIL: baseline source inputs unavailable")
		quit(2)
		return
	var params: Dictionary = loaded.values
	var rows: Array = []
	var refused := 0
	var changed_cash_or_funding := 0
	var variants: Array = ["heldout_B_ladder", "heldout_B_deposits"] if cohort == "holdout_B" else ["original", "cash_buffer", "heldout_maturity", "heldout_withdrawals"]
	for variant in variants:
		var heldout: bool = variant.begins_with("heldout_B") if finance_interest else variant.begins_with("heldout")
		var seeds: Array = [2017, 2999] if cohort == "holdout_B" else [910, 1013] if variant.begins_with("heldout") else [417, 618]
		for seed_number in seeds:
			var initialized: Dictionary = original.initial_state(params, scenarios.scenarios.stagflation_bank_run.initial)
			var campaign: Dictionary = original.seeded_campaign(seed_number, scenarios.scenarios.stagflation_bank_run, 240)
			var recipe: Dictionary = original.bank_workout_opening(params)
			check(initialized.ok and campaign.ok and recipe.ok, "Frozen scenario and authored bank opening initialize")
			if not initialized.ok or not campaign.ok or not recipe.ok:
				refused += 1
				continue
			if variant == "cash_buffer": recipe.bank.cash = 0.4
			if variant == "heldout_maturity": recipe.bank.claims[2].maturity_quarter = 8
			if variant == "heldout_withdrawals": recipe.requests[0] = 0.8
			if variant == "heldout_B_ladder":
				recipe.bank.claims[0].maturity_quarter = 3
				recipe.bank.claims[1].maturity_quarter = 6
				recipe.bank.claims[2].maturity_quarter = 18
			if variant == "heldout_B_deposits": recipe.bank.deposits = 2.95
			for policy_id in POLICIES:
				var parent := parent_tape(original, initialized.state, recipe, params, campaign.shocks, policy_id)
				check(parent.ok, "Original frozen model path completes")
				if not parent.ok:
					refused += 1
					rows.append({"variant": variant, "seed": seed_number, "policy": policy_id, "parent_refusal": parent.error})
					continue
				var legacy := replay(candidate, initialized.state, recipe, params, campaign.shocks, parent.policies, "legacy")
				var zero := replay(candidate, initialized.state, recipe, params, campaign.shocks, parent.policies, "zero")
				var priced := replay(candidate, initialized.state, recipe, params, campaign.shocks, parent.policies, "priced")
				var cash_only: Dictionary = replay(candidate, initialized.state, recipe, params, campaign.shocks, parent.policies, "cash_only") if finance_interest else priced
				if legacy.ok:
					check(var_to_bytes(legacy.frames) == var_to_bytes(parent.frames), "Default full frames remain byte-exact to original source")
				if legacy.ok and zero.ok:
					check(same_legacy(legacy.frames, zero.frames), "Zero APR/claims preserves every legacy field")
				check(legacy.ok and zero.ok and priced.ok, "Candidate legacy/zero/priced paths complete")
				check(cash_only.ok, "Cash-only comparison path completes")
				if not legacy.ok or not zero.ok or not priced.ok or not cash_only.ok:
					refused += 1
					rows.append({"variant": variant, "seed": seed_number, "policy": policy_id,
						"refusal": [legacy.get("error"), zero.get("error"), priced.get("error"), cash_only.get("error")],
						"failed_replays": [legacy, zero, priced, cash_only].filter(func(trial): return not trial.ok)})
					continue
				# Predeclared display-resolution screen, not a model clamp or welfare score.
				# Keep raw metrics so sub-threshold effects remain inspectable.
				var changed: bool = priced.metrics.gross_cash_interest >= 0.0001 or absf(priced.metrics.ending_queue - legacy.metrics.ending_queue) >= 0.0001 or absf(priced.metrics.inflation_distance_pp - legacy.metrics.inflation_distance_pp) >= 0.01
				if changed: changed_cash_or_funding += 1
				rows.append({"variant": variant, "heldout": heldout, "seed": seed_number, "policy": policy_id,
					"parent": legacy.metrics, "priced": priced.metrics, "cash_only_A": cash_only.metrics, "cash_or_funding_changed": changed})
	var source_frozen: bool = candidate_hash == FileAccess.get_sha256("res://model/economy.gd") and original_hash == FileAccess.get_sha256(baseline_path)
	check(source_frozen, "Both source files remain frozen from study start through completion")
	var report := {"candidate_model_sha256": candidate_hash,
		"original_model_sha256": original_hash, "source_start_end_unchanged": source_frozen, "rows": rows,
		"refused_paths": refused, "changed_cash_or_funding_paths": changed_cash_or_funding,
		"checks": checks, "failures": failures, "adopted": false, "finance_interest": finance_interest, "cohort": cohort,
		"scope": "Authored collectible-credit quarterly experiment; frozen parent policies/shocks; not empirical calibration or enjoyment qualification"}
	var f := FileAccess.open(output, FileAccess.WRITE)
	if f == null:
		printerr("FAIL: cannot save report")
		quit(2)
		return
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	if failures == 0:
		print("PASS: priced-workout paired study ", checks, " checks; cases=", rows.size(), "; refusals=", refused, "; changed cash/funding=", changed_cash_or_funding)
	quit(0 if failures == 0 else 1)
