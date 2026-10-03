extends SceneTree

const Economy = preload("res://model/economy.gd")
var model := Economy.new()
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func close(actual: float, expected: float, message: String) -> void:
	check(is_finite(actual) and abs(actual - expected) < 1e-8, "%s: got %.10f, expected %.10f" % [message, actual, expected])

func policy() -> Dictionary:
	return {"policy_rate_request_pct": 3.5, "guidance_rate_pct": 3.5,
		"guidance_inflation_sensitivity": 1.5, "guidance_output_gap_sensitivity": 0.5,
		"asset_flow_request_pct_initial_gdp": 0.0, "liquidity_request_pct_initial_gdp": 0.0}

func _initialize() -> void:
	var params: Dictionary = model.load_parameters().values
	var state: Dictionary = model.initial_state(params).state
	check(state.has("deferred_demand_pct") and state.has("demand_release_pct"), "initial state exposes signed deferred-demand stock and applied release")
	check(state.has("r_star_reference_pct"), "neutral rate has a separate structural reference")
	check(params.has("short_expectation_anchor_weight"), "short expectations expose a disclosed credibility-dependent long-anchor weight")
	var contraction: Dictionary = model.step(state, policy(), {"demand_shock_pct": -2.0}, params)
	check(contraction.ok and contraction.state.get("deferred_demand_pct", 0.0) > 0.0, "temporary contraction accumulates deferred durable/replacement spending")
	var transient: Dictionary = model.step(state, policy(), {"r_star_change_pct": 0.2}, params)
	var unforced: Dictionary = model.step(transient.state, policy(), {}, params)
	check(unforced.ok and unforced.state.r_star_pct < transient.state.r_star_pct and unforced.state.r_star_pct > state.r_star_pct, "temporary neutral-rate innovation decays gradually toward structural centre")
	var permanent: Dictionary = model.step(state, policy(), {"r_star_reference_change_pct": 0.5}, params)
	check(permanent.ok and permanent.state.get("r_star_reference_pct", 0.0) == 2.0, "permanent structural shift changes reference rather than being erased")
	if state.has("deferred_demand_pct") and params.has("short_expectation_anchor_weight"):
		_test_stock(params, state)
		_test_expectations(params)
		_test_equilibrium_and_domains(params, state)
	for failure in failures:
		printerr("FAIL: " + failure)
	if failures.is_empty():
		print("PASS: deferred-demand conservation, financing-dependent release, structural centres and gradual anchoring")
	quit(0 if failures.is_empty() else 1)

func _test_stock(params: Dictionary, state: Dictionary) -> void:
	var original := state.duplicate(true)
	var p := params.duplicate(true)
	p.deferred_demand_share = 0.0
	for backlog in [-4.0, 4.0]:
		var staged := state.duplicate(true)
		staged.deferred_demand_pct = backlog
		var result: Dictionary = model.step(staged, policy(), {}, p)
		check(result.ok, "both signed backlog states are admissible")
		if not result.ok:
			continue
		var available: float = backlog / pow(1.0 + state.potential_growth_pct / 100.0, 0.25)
		var fraction: float = p.demand_release_base_fraction + (p.demand_release_max_fraction - p.demand_release_base_fraction) * abs(available) / (p.demand_release_backlog_scale_pct + abs(available))
		var release: float = fraction * available
		close(result.state.demand_release_pct, release, "unconstrained release uses prior stock")
		close(result.state.output_gap_pct, release, "signed release affects activity exactly once")
		close(result.state.deferred_demand_pct, (1.0 - p.demand_cancellation_fraction) * available - release, "released/cancelled spending leaves the backlog once")
		var stressed := staged.duplicate(true)
		stressed.financial_restraint_gap_pct = 10.0
		var impaired: Dictionary = model.step(stressed, policy(), {}, p)
		check(impaired.ok and abs(impaired.state.demand_release_pct) < abs(release), "financial restraint delays catch-up without clipping the demand stock")
		p.demand_release_base_fraction = 0.0
		p.demand_release_max_fraction = 0.0
		var cancelled: Dictionary = model.step(staged, policy(), {}, p)
		check(cancelled.ok, "zero release endpoint is supported")
		if cancelled.ok:
			close(cancelled.state.output_gap_pct, 0.0, "cancellation itself does not spend")
			close(cancelled.state.deferred_demand_pct, (1.0 - p.demand_cancellation_fraction) * available, "obsolete plans decay with either sign")
		p = params.duplicate(true)
		p.deferred_demand_share = 0.0
	var shock: Dictionary = model.step(state, policy(), {"demand_shock_pct": -2.0}, params)
	close(shock.state.demand_release_pct, 0.0, "same-quarter contraction cannot release a future backlog")
	close(shock.state.deferred_demand_pct, 2.0 * params.deferred_demand_share, "only the deferred share enters stock")
	var recovered: Dictionary = model.step(shock.state, policy(), {}, params)
	check(recovered.ok and recovered.state.demand_release_pct > 0.0, "prior deferred spending supplies an endogenous recovery impulse")
	close(recovered.state.deferred_demand_pct,
		(1.0 - params.demand_cancellation_fraction) * shock.state.deferred_demand_pct / pow(1.0 + shock.state.potential_growth_pct / 100.0, 0.25) - params.deferred_demand_share * (recovered.state.output_gap_pct - recovered.state.demand_release_pct) - recovered.state.demand_release_pct,
		"ongoing contraction and depletion conserve the stock")
	for growth in [-20.0, 20.0]:
		var staged := state.duplicate(true)
		staged.deferred_demand_pct = 4.0
		var result: Dictionary = model.step(staged, policy(), {"potential_growth_pct": growth}, params)
		check(result.ok, "stock conservation accepts both growth-domain endpoints")
		if result.ok:
			var available: float = 4.0 * state.potential_output_index / result.state.potential_output_index
			close(result.state.deferred_demand_pct + result.state.demand_release_pct,
				(1.0 - params.demand_cancellation_fraction) * available,
				"potential growth changes units, not the quantity of deferred spending")
	check(state == original, "all stock experiments preserve their input")

func _test_expectations(params: Dictionary) -> void:
	var state: Dictionary = model.initial_state(params, {"annualized_quarterly_inflation_pct": -4.0, "expected_short_inflation_pct": -4.0, "expected_long_inflation_pct": 2.0}).state
	var previous := state.duplicate(true)
	var result: Dictionary = model.step(state, policy(), {}, params)
	check(result.ok, "deflationary gross expectations remain admissible")
	if not result.ok:
		return
	var anchor: float = params.short_expectation_anchor_weight * state.credibility
	var recent: float = (1.0 - anchor) * (1.0 + state.four_quarter_inflation_pct / 100.0) + anchor * (1.0 + state.expected_long_inflation_pct / 100.0)
	var expected: float = 100.0 * ((1.0 - params.short_expectation_recent_weight) * (1.0 + state.expected_short_inflation_pct / 100.0) + params.short_expectation_recent_weight * recent - 1.0)
	close(result.state.expected_short_inflation_pct, expected, "short anchoring uses prior observations, long expectation and credibility")
	check(result.state.expected_short_inflation_pct > -4.0 and result.state.expected_short_inflation_pct < 2.0, "anchoring is gradual, not an instantaneous target reset")
	var no_trust := state.duplicate(true)
	no_trust.credibility = 0.0
	var adaptive: Dictionary = model.step(no_trust, policy(), {}, params)
	close(adaptive.state.expected_short_inflation_pct, -4.0, "zero credibility preserves fully adaptive expectations")
	check(state == previous, "expectation transitions preserve input histories")

func _test_equilibrium_and_domains(params: Dictionary, state: Dictionary) -> void:
	var next := state.duplicate(true)
	for q in range(240):
		var result: Dictionary = model.step(next, policy(), {}, params)
		check(result.ok, "240-quarter unforced equilibrium remains valid")
		if not result.ok:
			return
		next = result.state
	close(next.output_gap_pct, 0.0, "stock channels do not manufacture activity at equilibrium")
	close(next.deferred_demand_pct, 0.0, "equilibrium has no hidden backlog drift")
	close(next.four_quarter_inflation_pct, 2.0, "target equilibrium remains unchanged")
	for field in ["deferred_demand_pct", "demand_release_pct", "r_star_reference_pct"]:
		var broken := state.duplicate(true)
		broken[field] = NAN
		check(not model.step(broken, policy(), {}, params).ok, "nonfinite new state rejected: " + field)
	for field in ["deferred_demand_share", "demand_cancellation_fraction", "demand_release_base_fraction", "demand_release_max_fraction", "r_star_reversion_persistence", "short_expectation_anchor_weight"]:
		var broken := params.duplicate(true)
		broken[field] = 1.1
		check(not model.step(state, policy(), {}, broken).ok, "invalid new fraction rejected: " + field)
	var inconsistent := params.duplicate(true)
	inconsistent.demand_release_base_fraction = 0.4
	inconsistent.demand_release_max_fraction = 0.2
	check(not model.step(state, policy(), {}, inconsistent).ok, "base release cannot exceed maximum release")
	inconsistent = params.duplicate(true)
	inconsistent.demand_cancellation_fraction = 0.9
	check(not model.step(state, policy(), {}, inconsistent).ok, "release and cancellation cannot overdraw prior stock")
