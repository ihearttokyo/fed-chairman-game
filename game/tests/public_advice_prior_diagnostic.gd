extends SceneTree
## Opt-in comparison. No tuning, adoption, future-shock access or save writes.
const Career = preload("res://play/career.gd")
const Committee = preload("res://play/policy_committee.gd")
var failures := 0
var transitions := 0
var rows: Array = []
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func _initialize() -> void:
	call_deferred("run")
static func reference_rate(state: Dictionary, params: Dictionary, prior_bias: float = 0.0) -> float:
	var published := {}
	for key in ["expected_long_inflation_pct", "four_quarter_inflation_pct", "output_gap_pct"]:
		published[key] = float("%.2f" % state[key])
	var target: float = params.initial_r_star_pct + prior_bias + published.expected_long_inflation_pct + params.policy_inflation_response * (published.four_quarter_inflation_pct - params.inflation_target_pct) + params.policy_output_gap_response * published.output_gap_pct
	return snappedf(target, params.minimum_rate_increment_pct)

func information_checks(career) -> void:
	var current: Dictionary = career.current_briefing()
	var n: float = career.model.nominal_gdp_ratio(career.state)
	var before := var_to_bytes([career.state, career.params, current])
	var choices: Array = Committee.proposals(career.state, career.params, current, n)
	for hidden_key in ["r_star_pct", "expected_short_inflation_pct"]:
		var altered: Dictionary = career.state.duplicate(true)
		altered[hidden_key] += 1.0
		check(career.model._validate_state(altered, career.params).ok, "observer twin remains a valid native state")
		check(reference_rate(altered, career.params) == reference_rate(career.state, career.params), "public reference excludes " + hidden_key)
		check(Committee.proposals(altered, career.params, current, n) == choices, "committee excludes " + hidden_key)
		var oracle_a: Dictionary = career.model.benchmark_policy(career.state, career.params)
		var oracle_b: Dictionary = career.model.benchmark_policy(altered, career.params)
		check(not is_equal_approx(oracle_a.policy_rate_request_pct, oracle_b.policy_rate_request_pct), "oracle positive control detects " + hidden_key)
	check(var_to_bytes([career.state, career.params, current]) == before, "information controls preserve all inputs")

func run() -> void:
	if OS.get_cmdline_user_args().has("--controls-only"):
		for scenario in ["policy_career", "supply_shock", "stagflation_bank_run"]:
			var career := Career.new()
			check(career.start(scenario, 1).ok, "information-control scenario starts")
			information_checks(career)
		if not failures: print("PASS: separate valid-state latent-input controls, oracle positive controls and input purity; zero transitions")
		quit(1 if failures else 0)
		return
	for scenario in ["policy_career", "supply_shock", "stagflation_bank_run"]:
		for seed_value in [63239, 90389]:
			for kind in ["hold", "oracle", "public_reference", "public_low_prior", "public_high_prior"]:
				var career := Career.new()
				check(career.start(scenario, seed_value).ok, "scenario starts")
				if failures: quit(1); return
				var initial_rate: float = career.state.policy_rate_pct
				var price_cost := 0.0
				var jobs_cost := 0.0
				var unmet := 0.0
				for quarter in range(Career.MAX_QUARTERS):
					var n: float = career.model.nominal_gdp_ratio(career.state)
					var current: Dictionary = career.current_briefing()
					var choices: Array = Committee.proposals(career.state, career.params, current, n)
					if quarter == 0: information_checks(career)
					var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, "feedback" if kind == "oracle" else "hold")
					if kind == "hold":
						policy.policy_rate_request_pct = initial_rate
						policy.guidance_rate_pct = initial_rate
					elif kind in ["public_reference", "public_low_prior", "public_high_prior"]:
						# Frozen hypothesis: disclosed initial neutral-rate prior and published
						# long expectations, not the true evolving neutral/short expectations.
						policy.policy_rate_request_pct = reference_rate(career.state, career.params, -1.0 if kind == "public_low_prior" else (1.0 if kind == "public_high_prior" else 0.0))
						policy.guidance_rate_pct = policy.policy_rate_request_pct
					elif kind in ["prices", "jobs"]:
						var choice: Dictionary = choices[0 if kind == "prices" else 1]
						policy.policy_rate_request_pct = choice.rate
						policy.guidance_rate_pct = choice.rate
					# Match liquidity, guidance sensitivities and portfolio settings across arms.
					policy.liquidity_request_pct_initial_gdp = choices[2].lending_offer_current_gdp * n
					policy.reinvest_principal = true
					policy.maintain_ample_reserves = true
					policy.sterilize_purchases = false
					var result: Dictionary = career.advance(policy)
					check(result.ok, "%s %s seed%d Q%d: %s" % [scenario, kind, seed_value, quarter, result.get("error", "")])
					if not result.ok: quit(1); return
					transitions += 1
					price_cost += absf(career.state.four_quarter_inflation_pct - career.params.inflation_target_pct)
					jobs_cost += maxf(0.0, career.state.unemployment_rate_pct - career.state.structural_unemployment_pct)
					unmet += career.state.uncovered_funding_pct_initial_gdp / career.state.decision_nominal_gdp_ratio
				var row := {"scenario":scenario, "seed":seed_value, "policy":kind,
					"average_inflation_distance_pp":price_cost / Career.MAX_QUARTERS,
					"average_employment_shortfall_pp":jobs_cost / Career.MAX_QUARTERS,
					"average_uncovered_funding_pct_meeting_gdp":unmet / Career.MAX_QUARTERS,
					"ending_credibility":100.0 * career.state.credibility, "ending_support":career.state.public_support,
					"mandate_achieved":career.mandate_assessment().get("achieved", false),
					"recovery_stabilized":career.recovery_assessment().get("stabilized", false)}
				for key in ["average_inflation_distance_pp", "average_employment_shortfall_pp", "average_uncovered_funding_pct_meeting_gdp", "ending_credibility", "ending_support"]:
					check(is_finite(row[key]), "finite summary " + key)
				rows.append(row)
				print("ADVICE_RESULT ", JSON.stringify(row))
	check(rows.size() == 30 and transitions == 7200, "exact bounded diagnostic coverage")
	print("ADVICE_COUNTS careers=%d transitions=%d failures=%d" % [rows.size(), transitions, failures])
	if not failures: print("PASS: public-advice information controls and matched-tool career diagnostic; frozen rounded-observation held-out screen; not adoption or whole-game qualification")
	quit(1 if failures else 0)
