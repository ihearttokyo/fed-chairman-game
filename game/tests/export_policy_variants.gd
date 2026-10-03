extends SceneTree

const Economy = preload("res://model/economy.gd")
const Exporter = preload("res://tests/export_reference.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var price_boundaries := args.size() == 3 and args[2] == "--price-boundaries"
	var balance_boundaries := args.size() == 3 and args[2] == "--balance-boundaries"
	var rate_boundaries := args.size() == 3 and args[2] == "--rate-boundaries"
	if (args.size() != 2 and not price_boundaries and not rate_boundaries and not balance_boundaries) or args[0] != "--output":
		printerr("usage: --output /absolute/path/outside/repository.json [--price-boundaries|--rate-boundaries|--balance-boundaries]")
		quit(1)
		return
	var output_path := args[1].simplify_path()
	if not Exporter.output_is_outside_repository(output_path, ProjectSettings.globalize_path("res://")) or FileAccess.file_exists(output_path):
		printerr("output must be a new absolute file outside the repository")
		quit(1)
		return
	var model := Economy.new()
	var parameters := model.load_parameters()
	var scenarios := model.load_scenarios()
	var portfolio := model.load_portfolio_reference()
	if not parameters.ok or not scenarios.ok or not portfolio.ok:
		printerr("model inputs failed validation")
		quit(1)
		return
	var variants := [
		{"name": "rate_zero", "case": "supply_shock", "quarter": 0, "control": "policy_rate_request_pct", "value": 0.0, "cell": "E6"},
		{"name": "asset_purchase", "case": "base", "quarter": 0, "control": "asset_flow_request_pct_initial_gdp", "value": 2.0, "cell": "E10"},
		{"name": "liquidity", "case": "funding_stress", "quarter": 4, "control": "liquidity_request_pct_initial_gdp", "value": 3.0, "cell": "I11"},
		{"name": "guidance", "case": "base", "quarter": 0, "control": "guidance_rate_pct", "value": 4.25, "cell": "E7"},
	]
	if price_boundaries:
		variants = []
		for supply in [-5.0, 0.0, 5.0]:
			variants.append({"name": "price_boundary_supply_%.0f" % supply, "case": "base",
				"initial": {"annualized_quarterly_inflation_pct": -99.9, "expected_short_inflation_pct": -99.9, "output_gap_pct": 20.0},
				"policy_kind": "hold", "shocks": [{"supply_innovation_pct": supply}]})
	if rate_boundaries:
		variants = [
			{"name":"signed_crossing","case":"base","initial":{"policy_rate_pct":-0.5,"credibility":0.2},
				"shocks":[{},{},{}],"policy_overrides":[{"policy_rate_request_pct":-0.5,"guidance_rate_pct":-1.0},{"policy_rate_request_pct":0.0,"guidance_rate_pct":0.0},{"policy_rate_request_pct":0.01,"guidance_rate_pct":-0.01}]},
			{"name":"deep_constraint","case":"base","initial":{"annualized_quarterly_inflation_pct":-4.0,"expected_short_inflation_pct":-4.0,"expected_long_inflation_pct":-4.0},
				"shocks":[{},{}],"policy_overrides":[{"policy_rate_request_pct":-30.0,"guidance_rate_pct":-30.0},{"policy_rate_request_pct":-40.0,"guidance_rate_pct":-40.0}]},
			{"name":"zero_loading","case":"base","initial":{"credibility":1.0,"annualized_quarterly_inflation_pct":4.0,"expected_short_inflation_pct":4.0,"expected_long_inflation_pct":4.0},
				"parameter_overrides":{"real_rate_short_weight":0.0,"long_yield_current_rate_weight":0.0},
				"shocks":[{},{}],"policy_overrides":[{"policy_rate_request_pct":-25.0,"guidance_rate_pct":3.5},{"policy_rate_request_pct":25.0,"guidance_rate_pct":3.5}]},
			{"name":"untrusted_guidance","case":"base","initial":{"credibility":0.0},
				"shocks":[{}],"policy_overrides":[{"policy_rate_request_pct":0.0,"guidance_rate_pct":-5.0}]},
			{"name":"conditional_positive","case":"base","initial":{},
				"shocks":[{"demand_shock_pct":1.2},{}],"policy_overrides":[{"policy_rate_request_pct":3.5,"guidance_rate_pct":3.65}],"deliver_conditional":true},
			{"name":"conditional_negative","case":"base","initial":{},
				"shocks":[{},{}],"policy_overrides":[{"policy_rate_request_pct":0.0,"guidance_rate_pct":-0.3}],"deliver_conditional":true},
			{"name":"unrestricted_positive","case":"base","initial":{},
				"shocks":[{},{}],"policy_overrides":[{"policy_rate_request_pct":25.0,"guidance_rate_pct":30.0},{"policy_rate_request_pct":30.0,"guidance_rate_pct":25.0}]},
		]
	if balance_boundaries:
		variants = [
			{"name":"omitted_liquidity_eligibility","case":"base","shocks":[{"funding_need_pct_initial_gdp":3.0,"eligible_collateral_pct_initial_gdp":6.0}],"policy_overrides":[{"liquidity_request_pct_initial_gdp":3.0}]},
			{"name":"natural_runoff","case":"base","shocks":[{}],"policy_overrides":[{"reinvest_principal":false,"maintain_ample_reserves":false}]},
			{"name":"negative_cap_on","case":"base","shocks":[{}],"policy_overrides":[{"asset_flow_request_pct_initial_gdp":-0.25,"reinvest_principal":true,"maintain_ample_reserves":false}]},
			{"name":"negative_cap_off","case":"base","shocks":[{}],"policy_overrides":[{"asset_flow_request_pct_initial_gdp":-0.25,"reinvest_principal":false,"maintain_ample_reserves":false}]},
			{"name":"uncapped_purchase","case":"base","shocks":[{}],"policy_overrides":[{"asset_flow_request_pct_initial_gdp":150.0}]},
			{"name":"uncapped_loan_refinancing","case":"base",
				"shocks":[{"funding_need_pct_initial_gdp":100.0,"eligible_collateral_pct_initial_gdp":100.0,"collateral_haircut_pct":10.0,"liquidity_eligibility_pct":100.0},{"refinancing_need_pct_initial_gdp":90.0,"funding_need_pct_initial_gdp":5.0,"eligible_collateral_pct_initial_gdp":100.0,"liquidity_eligibility_pct":100.0},{}],
				"policy_overrides":[{"liquidity_request_pct_initial_gdp":400.0},{"liquidity_request_pct_initial_gdp":400.0},{}]},
			{"name":"encumbered_collateral","case":"base","shocks":[{"rrp_encumbered_collateral_pct_initial_gdp":1000000.0}],"policy_overrides":[{"asset_flow_request_pct_initial_gdp":2.0,"sterilize_purchases":true}]},
			{"name":"initial_gap_gdp","case":"base","initial":{"output_gap_pct":-5.0},"shocks":[{},{},{}],"policy_overrides":[{}, {"asset_flow_request_pct_initial_gdp":2.0},{}]},
		]
		for uptake in [1.0, 0.25, 0.0]:
			variants.append({"name":"sterilization_uptake_%s" % str(uptake),"case":"base","shocks":[{"rrp_uptake_fraction":uptake}],"policy_overrides":[{"asset_flow_request_pct_initial_gdp":2.0,"sterilize_purchases":true}]})
		var tag_shocks: Array = []
		var tag_policies: Array = []
		for q in range(26):
			tag_shocks.append({})
			tag_policies.append({"asset_flow_request_pct_initial_gdp":2.0 if q == 0 else 0.0,"sterilize_purchases":true})
		variants.append({"name":"tagged_reinvestment_26","case":"base","shocks":tag_shocks,"policy_overrides":tag_policies})
		for maintain in [false, true]:
			variants.append({"name":"joint_maintenance" if maintain else "joint_aggregate_scarcity","case":"base",
				"parameter_overrides":{"initial_reserves_pct_initial_gdp":6.0},"shocks":[{"eligible_collateral_pct_initial_gdp":100.0,"liquidity_eligibility_pct":100.0}],
				"policy_overrides":[{"asset_flow_request_pct_initial_gdp":1.0,"reinvest_principal":false,"sterilize_purchases":true,"maintain_ample_reserves":maintain,"liquidity_request_pct_initial_gdp":0.25}]})
		var runoff_shocks: Array = []
		var runoff_policies: Array = []
		for q in range(27):
			runoff_shocks.append({})
			runoff_policies.append({"asset_flow_request_pct_initial_gdp":2.0 if q == 0 else -1.0 if q == 23 else 0.0,"sterilize_purchases":q < 25})
		variants.append({"name":"tagged_runoff_release","case":"base","shocks":runoff_shocks,"policy_overrides":runoff_policies})

	for variant in variants:
		var scenario: Dictionary = scenarios.scenarios[variant.case]
		var params: Dictionary = parameters.values.duplicate(true)
		params.merge(variant.get("parameter_overrides", {}), true)
		var initial := model.initial_state(params, variant.get("initial", scenario.initial))
		if not initial.ok:
			printerr(initial.error)
			quit(1)
			return
		var state: Dictionary = initial.state
		variant.initial = variant.get("initial", scenario.initial).duplicate(true)
		variant.initial_state = state.duplicate(true)
		variant.parameters = parameters.records
		variant.portfolio_reference = portfolio.value
		variant.portfolio_reference_json = FileAccess.get_file_as_string("res://model/portfolio_reference.json")
		variant.portfolio_reference_sha256 = FileAccess.get_sha256("res://model/portfolio_reference.json")
		var states: Array = [state.duplicate(true)]
		var shocks: Array = variant.get("shocks", model.seeded_shock_path(1, scenario, 48))
		var policies: Array = []
		var traces: Array = []
		for quarter in range(shocks.size()):
			var policy := model.benchmark_policy(state, params, variant.get("policy_kind", "feedback"))
			if quarter == variant.get("quarter", -1):
				policy[variant.control] = variant.value
			var overrides: Array = variant.get("policy_overrides", [])
			if quarter < overrides.size():
				policy.merge(overrides[quarter], true)
			if quarter == 1 and variant.get("deliver_conditional", false):
				policy.policy_rate_request_pct = model.conditional_commitment(state, params)
				policy.guidance_rate_pct = policy.policy_rate_request_pct
			var transition := model.step(state, policy, shocks[quarter], params)
			if not transition.ok:
				printerr(transition.error)
				quit(1)
				return
			state = transition.state
			states.append(state.duplicate(true))
			policies.append(policy.duplicate(true))
			traces.append(transition.trace.duplicate(true))
		variant.states = states
		variant.policies = policies
		variant.shocks = shocks
		variant.traces = traces
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	if directory_error != OK:
		printerr("could not create export directory")
		quit(1)
		return
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		printerr("could not open export destination")
		quit(1)
		return
	# Near -100% inflation needs full precision for its large initial price-history levels.
	output.store_string(JSON.stringify(variants, "\t", true, true))
	output.close()
	print("EXPORTED fifteen balance-sheet boundary traces" if balance_boundaries else "EXPORTED seven signed-rate boundary traces" if rate_boundaries else ("EXPORTED three physical price boundary traces" if price_boundaries else "EXPORTED four one-variable policy traces"))
	quit(0)
