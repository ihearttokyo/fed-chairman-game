extends RefCounted

const Economy = preload("res://model/economy.gd")
const TERM_LABELS := ["Inherited gap", "Financial restraint", "Demand impulse", "Supply pressure", "Deferred-demand release"]

static func _finite_fields(record: Dictionary, keys: Array) -> bool:
	for key in keys:
		if not record.has(key) or typeof(record[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(record[key])):
			return false
	return true

static func _matches(actual: float, predicted: float, scale: float = 1.0) -> bool:
	return is_finite(actual) and is_finite(predicted) and abs(actual - predicted) <= 1e-9 * maxf(scale, maxf(1.0, abs(actual)))

static func explain(before: Dictionary, after: Dictionary, completed_shock: Dictionary, params: Dictionary) -> Dictionary:
	var model := Economy.new()
	if not model._validate_parameters(params).ok or not model._validate_shocks(completed_shock).ok:
		return {"ok": false, "error": "Explanation inputs are invalid."}
	var common := ["quarter_index", "output_gap_pct", "potential_output_index", "actual_output_index", "price_index", "deferred_demand_pct"]
	if not _finite_fields(before, common + ["annualized_quarterly_inflation_pct", "expected_short_inflation_pct"]) or not _finite_fields(after, common + ["financial_restraint_gap_pct", "supply_pressure_pct", "demand_release_pct"]):
		return {"ok": false, "error": "Completed state is missing finite explanation fields."}
	for state in [before, after]:
		if state.potential_output_index <= 0 or state.actual_output_index <= 0 or state.price_index <= 0 or state.output_gap_pct <= -100:
			return {"ok": false, "error": "Completed levels cannot be explained."}
		if not _matches(state.actual_output_index, state.potential_output_index * (1 + state.output_gap_pct / 100)):
			return {"ok": false, "error": "Completed output level does not match its gap."}
	if before.quarter_index < 0 or before.quarter_index != floor(before.quarter_index) or after.quarter_index != before.quarter_index + 1:
		return {"ok": false, "error": "Explanation requires adjacent completed quarters."}
	var backlog: float = before.deferred_demand_pct * before.potential_output_index / after.potential_output_index
	var restraint: float = after.financial_restraint_gap_pct
	var release_fraction: float = (params.demand_release_base_fraction + (params.demand_release_max_fraction - params.demand_release_base_fraction) * abs(backlog) / (params.demand_release_backlog_scale_pct + abs(backlog))) / (1 + pow(maxf(0, restraint) / params.demand_release_financing_scale_pct, 2))
	var release: float = release_fraction * backlog
	var terms: Array[float] = [
		(params.output_gap_persistence - 1) * before.output_gap_pct,
		-params.real_rate_output_sensitivity * restraint,
		completed_shock.get("demand_shock_pct", 0.0),
		-params.supply_output_gap_sensitivity * after.supply_pressure_pct,
		release,
	]
	var predicted := 0.0
	var scale := 0.0
	for term in terms:
		predicted += term
		scale += abs(term)
	var change: float = after.output_gap_pct - before.output_gap_pct
	var underlying: float = before.output_gap_pct + predicted - release
	var expected_backlog: float = (1 - params.demand_cancellation_fraction) * backlog - params.deferred_demand_share * underlying - release
	var price_base: float = params.inflation_persistence * (1 + before.annualized_quarterly_inflation_pct / 100) + (1 - params.inflation_persistence) * (1 + before.expected_short_inflation_pct / 100)
	if price_base <= 0:
		return {"ok": false, "error": "Completed inflation base is invalid."}
	var price_terms: Array[float] = [log(price_base) / params.quarters_per_year, (params.inflation_output_gap_sensitivity * before.output_gap_pct + params.inflation_supply_sensitivity * after.supply_pressure_pct) / (params.quarters_per_year * (100 + params.inflation_target_pct))]
	var output_terms: Array[float] = [log(after.potential_output_index / before.potential_output_index), log((1 + after.output_gap_pct / 100) / (1 + before.output_gap_pct / 100))]
	if not _matches(change, predicted, scale) or not _matches(after.demand_release_pct, release) or not _matches(after.deferred_demand_pct, expected_backlog) or not _matches(log(after.price_index / before.price_index), price_terms[0] + price_terms[1]) or not _matches(log(after.actual_output_index / before.actual_output_index), output_terms[0] + output_terms[1]):
		return {"ok": false, "error": "Completed path does not reconcile; explanation unavailable."}
	return {"ok": true, "terms": terms, "change": change, "residual": change - predicted, "backlog_change": after.deferred_demand_pct - backlog, "price_log_terms": price_terms, "output_log_terms": output_terms}

static func segment(history: Array, shocks: Array, first: int, last: int, params: Dictionary) -> Dictionary:
	if first < 0 or last <= first or last - first > 4 or last >= history.size() or last > shocks.size():
		return {"ok": false, "error": "Explanation needs one to four completed quarters."}
	var terms: Array[float] = [0, 0, 0, 0, 0]
	for index in range(first, last):
		if not history[index] is Dictionary or not history[index + 1] is Dictionary or not shocks[index] is Dictionary:
			return {"ok": false, "error": "Completed record is invalid."}
		var result := explain(history[index], history[index + 1], shocks[index], params)
		if not result.ok:
			return result
		for term in range(terms.size()):
			terms[term] += result.terms[term]
	var change: float = history[last].output_gap_pct - history[first].output_gap_pct
	var sum := 0.0
	var scale := 0.0
	for term in terms:
		sum += term
		scale += abs(term)
	if not _matches(change, sum, scale):
		return {"ok": false, "error": "Completed segment does not reconcile; explanation unavailable."}
	var text := "Q%d–Q%d gap change %+.3f pp: " % [history[first].quarter_index + 1, history[last].quarter_index, change]
	for index in range(terms.size()):
		text += ("; " if index > 0 else "") + "%s %+.3f" % [TERM_LABELS[index], terms[index]]
	text += ". Equation contributions, not isolated policy effects. Inflation uses the prior gap."
	return {"ok": true, "terms": terms, "change": change, "residual": change - sum, "text": text}
