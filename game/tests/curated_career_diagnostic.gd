extends SceneTree

# New current-source diagnostic, not a replay of the unavailable historical sweep.
const Career = preload("res://play/career.gd")
const COLUMNS := ["inflation_miss_pp", "absolute_gap_pct", "unemployment_excess_pp",
	"final_credibility", "final_support", "minimum_credibility", "minimum_support",
	"maximum_assets_pct_current_gdp", "maximum_loans_pct_current_gdp",
	"maximum_reserves_pct_current_gdp", "severe_quarters"]
const CONDITIONAL := ["private_bank_recapitalization", "stable_private_deposits_return"]
var failures := 0
var transitions := 0
var attempted := 0
var completed := 0
var coverage := {}
var groups := {"feedback": [], "matched_feedback": [], "hold": []}
var differences: Array = []

func check(condition: bool, message: String) -> bool:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
	return condition

func median(sorted: Array) -> float:
	var middle := sorted.size() / 2
	return (float(sorted[(sorted.size() - 1) / 2]) + float(sorted[middle])) / 2.0

func quantile(sorted: Array, p: float) -> float:
	return float(sorted[maxi(0, int(ceil(p * sorted.size())) - 1)])

func severe(s: Dictionary, target: float) -> bool:
	return abs(s.four_quarter_inflation_pct - target) > 5.0 or abs(s.output_gap_pct) > 10.0 \
		or s.unemployment_rate_pct > 12.0 or s.public_support < 20.0 or s.solvency_risk_wedge_pct > 5.0

func endpoint_causes(s: Dictionary, target: float) -> Array:
	return [abs(s.four_quarter_inflation_pct - target) > 1.0, abs(s.output_gap_pct) > 1.0,
		s.unemployment_rate_pct > s.structural_unemployment_pct + 1.5]

func method_checks() -> void:
	check(median([1, 2, 3, 4]) == 2.5 and median([1, 2, 3]) == 2.0, "odd/even median")
	check(quantile([1], 0.95) == 1 and quantile([1, 2, 3, 4], 0.9) == 4, "nearest-rank tails")
	var known: Array = range(1, 101)
	check(quantile(known, 0.9) == 90 and quantile(known, 0.95) == 95, "known100 quantiles")
	var boundary := {"four_quarter_inflation_pct":7.0,"output_gap_pct":10.0,
		"unemployment_rate_pct":12.0,"structural_unemployment_pct":10.5,
		"public_support":20.0,"solvency_risk_wedge_pct":5.0}
	check(not severe(boundary, 2), "severity thresholds are strict")
	for key in ["four_quarter_inflation_pct", "output_gap_pct", "unemployment_rate_pct", "solvency_risk_wedge_pct"]:
		var outside: Dictionary = boundary.duplicate()
		outside[key] += 0.001
		check(severe(outside, 2), "severity outside " + key)
	boundary.public_support = 19.999
	check(severe(boundary, 2), "low support severity")
	boundary.four_quarter_inflation_pct = 3.0
	boundary.output_gap_pct = -1.0
	check(endpoint_causes(boundary, 2) == [false, false, false], "endpoint band boundaries")
	boundary.four_quarter_inflation_pct = 3.001
	boundary.output_gap_pct = -1.001
	boundary.unemployment_rate_pct = 12.001
	check(endpoint_causes(boundary, 2) == [true, true, true], "endpoint outside causes")

func extrema(career) -> Array:
	var s: Dictionary = career.state
	var n: float = career.model.nominal_gdp_ratio(s)
	return [100.0 * s.credibility, s.public_support, s.asset_stock_pct_initial_gdp / n,
		s.outstanding_liquidity_pct_initial_gdp / n, s.reserves_pct_initial_gdp / n, 0]

func observe(career, values: Array) -> void:
	var current := extrema(career)
	values[0] = minf(values[0], current[0])
	values[1] = minf(values[1], current[1])
	for index in range(2, 5):
		values[index] = maxf(values[index], current[index])
	values[5] += int(severe(career.state, career.params.inflation_target_pct))

func record(career, seed: int, kind: String, values: Array, quarters: int) -> Array:
	var s: Dictionary = career.state
	check(s.quarter_index == quarters and career.decisions.size() == quarters
		and career.history.size() == quarters + 1, "%s seed%d horizon/history/decisions" % [kind, seed])
	var row: Array = [abs(s.four_quarter_inflation_pct - career.params.inflation_target_pct),
		abs(s.output_gap_pct), maxf(0, s.unemployment_rate_pct - s.structural_unemployment_pct),
		100.0 * s.credibility, s.public_support]
	row.append_array(values)
	for value in row:
		check(is_finite(float(value)), "%s seed%d finite endpoint/extremum" % [kind, seed])
	var causes := endpoint_causes(s, career.params.inflation_target_pct)
	# Only the printed record is rounded. Statistical aggregation retains native values.
	var printed: Array = []
	for value in row:
		printed.append(snappedf(value, 0.000001))
	print("CAREER %d %s %s causes=%s" % [seed, kind, JSON.stringify(printed), JSON.stringify(causes)])
	completed += 1
	return [seed, row, causes]

func run_seed(seed: int, paired: bool, quarters: int) -> void:
	var careers: Array = [Career.new()]
	var kinds: Array = ["feedback"]
	if paired:
		careers.append(Career.new())
		kinds.append("hold")
	for career in careers:
		attempted += 1
		if not check(career.start("mixed_crises", seed).ok, "career starts seed%d" % seed):
			return
	if paired:
		check(var_to_bytes(careers[0].shocks) == var_to_bytes(careers[1].shocks)
			and var_to_bytes(careers[0].episodes) == var_to_bytes(careers[1].episodes),
			"byte-identical paired exogenous inputs seed%d" % seed)
	for episode in careers[0].episodes:
		if episode.quarter_index >= quarters:
			continue
		coverage[episode.id] = coverage.get(episode.id, 0) + 1
		check(not CONDITIONAL.has(episode.id) or not episode.trigger_id.is_empty(), "conditional profile has trigger")
	var extremes: Array = []
	for career in careers:
		extremes.append(extrema(career))
	for quarter in range(quarters):
		for index in range(careers.size()):
			var career = careers[index]
			var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, kinds[index])
			var advanced: Dictionary = career.advance(policy)
			if not check(advanced.ok, "%s seed%d q%d: %s" % [kinds[index], seed, quarter + 1, advanced.get("error", "")]):
				return # Keep failure visible; do not manufacture a completed career.
			transitions += 1
			observe(career, extremes[index])
	var rows: Array = []
	for index in range(careers.size()):
		var row := record(careers[index], seed, kinds[index], extremes[index], quarters)
		groups[kinds[index]].append(row)
		rows.append(row)
	if paired:
		groups.matched_feedback.append(rows[0])
		var delta: Array = []
		for index in range(COLUMNS.size()):
			delta.append(rows[0][1][index] - rows[1][1][index])
		differences.append([seed, delta, []])

func summarize(label: String, records: Array) -> void:
	if not check(not records.is_empty(), "nonempty summary " + label):
		return
	var causes := [0, 0, 0]
	for row in records:
		for index in range(row[2].size()):
			causes[index] += int(row[2][index])
	var bands := " endpoint_outside_bands_pi_gap_u=" + JSON.stringify(causes) if not records[0][2].is_empty() else ""
	print("GROUP %s n=%d%s" % [label, records.size(), bands])
	for index in range(COLUMNS.size()):
		var values: Array = []
		var worst: Array = records[0]
		for row in records:
			values.append(row[1][index])
			# Low support/trust is the adverse tail; costs/ratios use their high tail.
			var low_tail := index in [3, 4, 5, 6]
			if (low_tail and row[1][index] < worst[1][index]) or (not low_tail and row[1][index] > worst[1][index]):
				worst = row
		values.sort()
		print("METRIC %s %s median=%.6f p90=%.6f p95=%.6f min=%.6f max=%.6f adverse=%.6f@seed%d" % [label, COLUMNS[index], median(values), quantile(values, 0.9), quantile(values, 0.95), values[0], values[-1], worst[1][index], worst[0]])

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	method_checks()
	if failures:
		quit(1)
		return
	var pilot := OS.get_cmdline_user_args().has("--pilot")
	var feedback_n := 4 if pilot else 1000
	var paired_n := 3 if pilot else 100
	var quarters := 24 if pilot else 240
	var source := Career.new()
	print("PROTOCOL current-source-curated-v1 mode=%s model_digest=%s columns=%s" % ["pilot" if pilot else "full", source.model_digest(), JSON.stringify(COLUMNS)])
	print("REPORT-METADATA records/aggregates displayed6decimals; statistics use unrounded native values; credibility/support are score points0–100; low trust/support versus high misses/gaps/ratios define diagnostic extrema, not welfare or optimal policy")
	print("LIMITS severity=abs_pi_miss>5|abs_gap>10|u>12|support<20|solvency>5; endpoint=abs_pi_miss>1|abs_gap>1|u>structural+1.5; continuing-crisis endpoint bands are not equilibrium/optimality proof; HOLD keeps the prior nominal rate with data-dependent guidance; changed conditions can lower follow-through")
	for seed in range(feedback_n):
		run_seed(seed, seed < paired_n, quarters)
	check(attempted == feedback_n + paired_n and completed == attempted,
		"all requested careers attempted/completed")
	check(transitions == (feedback_n + paired_n) * quarters, "all requested transitions completed")
	check(groups.feedback.size() == feedback_n and groups.hold.size() == paired_n
		and groups.matched_feedback.size() == paired_n and differences.size() == paired_n, "matched group sizes reconcile")
	var catalogue: Dictionary = source.model.load_shock_catalogue()
	if check(catalogue.ok, "current catalogue validates"):
		check(catalogue.accepted.size() == 50, "fifty current accepted concepts")
		for concept in catalogue.accepted:
			if not pilot:
				check(coverage.get(concept.id, 0) > 0, "full coverage " + concept.id)
			print("COVERAGE %s onsets=%d conditional=%s" % [concept.id, coverage.get(concept.id, 0), CONDITIONAL.has(concept.id)])
	for label in groups:
		summarize(label, groups[label])
	summarize("paired_feedback_minus_hold", differences)
	print("COUNTS mode=%s attempted=%d completed=%d transitions=%d paired=%d seen=%d failures=%d" % ["pilot" if pilot else "full", attempted, completed, transitions, differences.size(), coverage.size(), failures])
	if failures == 0:
		print("PASS: current-source curated career diagnostic %s" % ("pilot" if pilot else "full"))
	quit(0 if failures == 0 else 1)
