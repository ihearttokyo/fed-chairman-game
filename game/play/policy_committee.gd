extends RefCounted

# Fictional competing mandates, not estimated reaction functions or optimal policy.
# Current published inflation/activity and funding only: no neutral-rate oracle,
# future shock tape, forecast outcome, or mutation of the player's decision.
static func proposals(state: Dictionary, params: Dictionary, shock: Dictionary, nominal_gdp: float) -> Array:
	var increment: float = params.minimum_rate_increment_pct
	var current: float = state.policy_rate_pct
	var inflation_miss: float = state.four_quarter_inflation_pct - params.inflation_target_pct
	var gap: float = state.output_gap_pct
	var prices: float = snappedf(current + 0.5 * inflation_miss, increment)
	var jobs: float = snappedf(current + 0.5 * gap, increment)
	var need: float = maxf(0.0, shock.get("funding_need_pct_initial_gdp", 0.0))
	need += minf(maxf(0.0, shock.get("refinancing_need_pct_initial_gdp", 0.0)), state.outstanding_liquidity_pct_initial_gdp)
	var collateral: float = maxf(0.0, shock.get("eligible_collateral_pct_initial_gdp", 0.0))
	var lending_value: float = collateral * (1.0 - shock.get("collateral_haircut_pct", 0.0) / 100.0) * shock.get("liquidity_eligibility_pct", 0.0) / 100.0
	var eligible_need: float = need * shock.get("liquidity_eligibility_pct", 0.0) / 100.0
	var coverable: float = minf(eligible_need, lending_value)
	var offer: float = ceilf(coverable / nominal_gdp / 0.0001) * 0.0001
	return [
		{"id":"prices", "label":"Price stability", "rate":prices,
			"tradeoff":"Respond to the inflation miss. Existing restraint can still push employment lower; supply damage is not repaired by a rate increase."},
		{"id":"jobs", "label":"Employment", "rate":jobs,
			"tradeoff":"Respond to the output gap. Easing into supply inflation can prolong price pressure and weaken expectations."},
		{"id":"funding", "label":"Financial stability", "rate":current, "lending_offer_current_gdp":offer,
			"tradeoff":"Hold the rate and offer secured funding against today's eligible need. Loans do not recapitalize insolvent borrowers or remove the inflation problem."}
	]
