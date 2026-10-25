extends RefCounted
## Read-only current-meeting copy. nominal_gdp is current / initial annual GDP;
## funding inputs are percentages of initial GDP, converted only for display.

const Career = preload("res://play/career.gd")
const CURRENT_NUMBERS := ["demand_shock_pct", "supply_innovation_pct", "funding_need_pct_initial_gdp", "refinancing_need_pct_initial_gdp", "eligible_collateral_pct_initial_gdp", "collateral_haircut_pct", "liquidity_eligibility_pct", "solvency_risk_innovation_pct", "credit_risk_innovation_pct"]

static func present(state: Dictionary, current: Dictionary, previous: Dictionary, nominal_gdp: float, episode: Dictionary = {}) -> Dictionary:
	var output := {"ok": false, "summary": "", "event_title": "", "event_detail": ""}
	if not is_finite(nominal_gdp) or nominal_gdp <= 0:
		return output
	for key in ["output_gap_pct", "expected_long_inflation_pct", "public_hardship_memory"]:
		if not _number(state.get(key)):
			return output
	for key in ["outstanding_liquidity_pct_initial_gdp", "solvency_risk_wedge_pct", "deferred_demand_pct"]:
		if not _number(state.get(key, 0.0)):
			return output
	for key in CURRENT_NUMBERS:
		if not _number(current.get(key, 0.0)):
			return output
	if typeof(state.get("guidance_active", false)) != TYPE_BOOL or typeof(previous.get("guidance_active", false)) != TYPE_BOOL:
		return output
	if previous.get("guidance_active", false) and (not _number(state.get("guidance_followthrough_score")) or state.guidance_followthrough_score < 0 or state.guidance_followthrough_score > 1):
		return output
	if typeof(episode.get("title", "")) != TYPE_STRING or typeof(episode.get("policy_dilemma", "")) != TYPE_STRING:
		return output
	var new_need: float = current.get("funding_need_pct_initial_gdp", 0.0)
	var requested_refi: float = current.get("refinancing_need_pct_initial_gdp", 0.0)
	var outstanding: float = state.get("outstanding_liquidity_pct_initial_gdp", 0.0)
	var collateral: float = current.get("eligible_collateral_pct_initial_gdp", 0.0)
	var haircut: float = current.get("collateral_haircut_pct", 0.0)
	var eligibility: float = current.get("liquidity_eligibility_pct", 0.0)
	var prior_wedge: float = state.get("solvency_risk_wedge_pct", 0.0)
	if minf(minf(new_need, requested_refi), minf(outstanding, collateral)) < 0 or haircut < 0 or haircut > 100 or eligibility < 0 or eligibility > 100 or prior_wedge < 0 or state.public_hardship_memory < 0:
		return output
	var true_refi := minf(requested_refi, outstanding)
	var eligible_need := (new_need + true_refi) * (eligibility / 100.0)
	var secured_value := collateral * (1.0 - haircut / 100.0) * (eligibility / 100.0)
	for amount in [new_need, true_refi, eligible_need, secured_value]:
		if not is_finite(amount / nominal_gdp):
			return output
	var lines: Array[String] = []
	lines.append("Demand impulse %s pp · Supply innovation %s pp · Output gap %s%%" % [_signed(current.get("demand_shock_pct", 0.0)), _signed(current.get("supply_innovation_pct", 0.0)), _signed(state.output_gap_pct)])
	var context := "Long expectations %.2f%% · Hardship memory %.2f index" % [state.expected_long_inflation_pct, state.public_hardship_memory]
	if previous.get("guidance_active", false):
		context += " · Promise %.1f/100" % (100 * state.guidance_followthrough_score)
	elif state.get("guidance_active", false):
		context += " · Promise pending"
	lines.append(context)
	if new_need != 0 or requested_refi != 0 or outstanding != 0 or collateral != 0:
		lines.append("Funding (%% current GDP): new %s · refi need %s · eligible need %s · secured value %s" % [Career.funding_amount_text(new_need / nominal_gdp), Career.funding_amount_text(true_refi / nominal_gdp), Career.funding_amount_text(eligible_need / nominal_gdp), Career.funding_amount_text(secured_value / nominal_gdp)])
	var impairment: float = current.get("solvency_risk_innovation_pct", 0.0)
	if impairment != 0 or prior_wedge != 0:
		lines.append("Impairment pulse %s pp · Prior wedge %.2f pp (spread proxy)" % [_signed(impairment), prior_wedge])
	var credit: float = current.get("credit_risk_innovation_pct", 0.0)
	if credit != 0:
		lines.append("Credit-risk pulse %s pp" % _signed(credit))
	var backlog: float = state.get("deferred_demand_pct", 0.0)
	if backlog != 0:
		lines.append("Backlog %s%% potential" % _signed(backlog))
	output.ok = true
	output.summary = "\n".join(lines)
	output.event_title = episode.get("title", "")
	output.event_detail = episode.get("policy_dilemma", "")
	return output

static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func _signed(value: float) -> String:
	if value != 0 and absf(value) < 0.01:
		return ("up" if value > 0 else "down") + " <0.01"
	return "%+.2f" % (0.0 if value == 0 else value)
