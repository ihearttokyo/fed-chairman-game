extends SceneTree

# Recovery v1 is distinct from the unchanged lifetime Mandate v1. The rejected
# attempt to apply that award to the crisis is retained in external evidence.
const Career = preload("res://play/career.gd")
const Committee = preload("res://play/policy_committee.gd")
var failures := 0
var advances := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func fixture(count: int):
	var career := Career.new()
	career.start("stagflation_bank_run", 1)
	career.decisions.resize(count)
	career.history = [career.state.duplicate(true)]
	for q in range(count):
		var outcome: Dictionary = career.state.duplicate(true)
		outcome.quarter_index = q + 1
		outcome.four_quarter_inflation_pct = career.params.inflation_target_pct + 1.0
		outcome.unemployment_rate_pct = outcome.structural_unemployment_pct + 1.0
		outcome.eligible_local_need_pct_initial_gdp = 20.0 if q == 0 else 0.0
		outcome.lending_collateral_capacity_pct_initial_gdp = 20.0 if q == 0 else 0.0
		outcome.liquidity_local_applied_pct_initial_gdp = 19.0 if q == 0 else 0.0
		career.history.append(outcome)
	return career

func _initialize() -> void:
	check(not Career.new().recovery_assessment().eligible, "unstarted and other cases cannot qualify")
	var partial = fixture(11)
	check(not partial.recovery_assessment().stabilized, "eleven good quarters cannot substitute for twelve")
	var boundary = fixture(12)
	check(boundary.recovery_assessment().stabilized, "all three exact inclusive thresholds qualify")
	boundary.history[12].four_quarter_inflation_pct += 0.000001
	check(not boundary.recovery_assessment().stabilized, "unrounded inflation beyond the threshold refuses")
	boundary = fixture(12)
	boundary.history[12].unemployment_rate_pct += 0.000001
	check(not boundary.recovery_assessment().stabilized, "unrounded employment beyond the threshold refuses")
	boundary = fixture(12)
	boundary.history[1].liquidity_local_applied_pct_initial_gdp = 18.9999
	check(not boundary.recovery_assessment().stabilized, "underfunding is not rounded into ninety-five percent")
	boundary = fixture(12)
	boundary.shocks[200].demand_shock_pct += 1.0
	check(boundary.recovery_assessment().stabilized, "unknown future shocks cannot enter the score")
	boundary.shocks[0].demand_shock_pct += 0.01
	check(not boundary.recovery_assessment().eligible, "custom completed shocks cannot earn recovery")
	boundary = fixture(13)
	boundary.history[1].four_quarter_inflation_pct = 1000.0
	boundary.history[1].unemployment_rate_pct = 1000.0
	check(boundary.recovery_assessment().stabilized, "expired hardship is not a lifetime-average penalty")
	boundary.history[1].liquidity_local_applied_pct_initial_gdp = 0.0
	check(not boundary.recovery_assessment().stabilized, "eligible funding history does not disappear outside the price window")
	boundary = fixture(12)
	check(boundary.recovery_assessment().stabilized, "initial current stabilization")
	var renewed: Dictionary = boundary.history[-1].duplicate(true)
	renewed.four_quarter_inflation_pct = 20.0
	renewed.eligible_local_need_pct_initial_gdp = 0.0
	renewed.lending_collateral_capacity_pct_initial_gdp = 0.0
	renewed.liquidity_local_applied_pct_initial_gdp = 0.0
	boundary.history.append(renewed)
	boundary.decisions.resize(13)
	check(not boundary.recovery_assessment().stabilized, "new stress can end current stabilization without ending play")
	for seed in [1, 417]:
		var results := {}
		for kind in ["hold", "feedback", "feedback_funding"]:
			var career := Career.new()
			check(career.start("stagflation_bank_run", seed).ok, "canonical crisis starts")
			check(not career.mandate_assessment().eligible, "original Mandate eligibility is not widened")
			var first_recovery := -1
			for q in range(Career.MAX_QUARTERS):
				var policy: Dictionary = career.model.benchmark_policy(career.state, career.params, "hold" if kind == "hold" else "feedback")
				if kind == "feedback_funding":
					var n: float = career.model.nominal_gdp_ratio(career.state)
					var proposals: Array = Committee.proposals(career.state, career.params, career.current_briefing(), n)
					policy.liquidity_request_pct_initial_gdp = proposals[2].lending_offer_current_gdp * n
				var predecessor: Dictionary = career.state
				var before: PackedByteArray = var_to_bytes(predecessor)
				advances += 1
				var outcome: Dictionary = career.advance(policy)
				check(outcome.ok and var_to_bytes(predecessor) == before, "valid transition preserves predecessor")
				if not outcome.ok:
					quit(1)
					return
				if first_recovery < 0 and career.recovery_assessment().stabilized:
					first_recovery = q + 1
			var state_before: PackedByteArray = var_to_bytes(career.state)
			var history_before: PackedByteArray = var_to_bytes(career.history)
			var unchanged: PackedByteArray = career.encode()
			var assessment: Dictionary = career.recovery_assessment()
			check(assessment.eligible and career.encode() == unchanged and var_to_bytes(career.state) == state_before and var_to_bytes(career.history) == history_before, "recovery is current-prefix pure")
			var restored := Career.new()
			check(restored.restore(bytes_to_var(unchanged)).ok and restored.recovery_assessment() == assessment, "save replay retains recovery")
			check((first_recovery >= 0) == (kind == "feedback_funding"), "only funded policy ever stabilizes in these fixed careers")
			results[kind] = assessment
			print("RECOVERY_RESULT seed=",seed," policy=",kind," first=",first_recovery," ",JSON.stringify(assessment))
		check(not results.hold.stabilized and not results.feedback.stabilized, "hold and repeated rate-rule-only play cannot satisfy all objectives")
		check(results.feedback.funding_active and not results.feedback.funding_met, "rate advice cannot replace local funding")
		check(results.feedback_funding.stabilized, "a current-information multi-tool policy can stabilize the economy")
	check(advances == 1440, "exactly six fixed full careers, not a coefficient search")
	if failures == 0:
		print("PASS: Recovery v1 boundaries, unchanged Mandate, six full careers and exact replay")
	quit(1 if failures else 0)
