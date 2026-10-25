extends SceneTree
class NoForecastMain:
	extends "res://play/main.gd"
	func _preview() -> void:
		pass
var failures := 0
var rows: Array = []
var transitions := 0
var reference: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/public_advice_production_reference.json"))
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	for scenario in ["policy_career", "lower_bound_slump", "stagflation_bank_run"]:
		for seed_value in [72341, 98117]:
			for kind in ["public"]:
				var game = NoForecastMain.new()
				root.add_child(game)
				await process_frame
				game.set_process(false)
				game._start_career(scenario, seed_value)
				check(game.career.state.quarter_index == 0, "starts at initial state")
				var attended := 0
				var automatic := 0
				var price := 0.0
				var jobs := 0.0
				var funding := 0.0
				while game.career.decisions.size() < 60 and failures == 0:
					var before: int = game.career.decisions.size()
					game._staff_rule()
					game.follow_up_toggle.set_pressed_no_signal(true)
					game._advance()
					check(game.career.decisions.size() == before + 1, "attended native adoption exactly once")
					attended += 1
					transitions += 1
					price += absf(game.career.state.four_quarter_inflation_pct - game.career.params.inflation_target_pct)
					jobs += maxf(0.0, game.career.state.unemployment_rate_pct - game.career.state.structural_unemployment_pct)
					funding += game.career.state.uncovered_funding_pct_initial_gdp / game.career.state.decision_nominal_gdp_ratio
					for frame in range(300):
						if not game.routine.active or game.career.decisions.size() >= 60:
							break
						var count: int = game.career.decisions.size()
						game._process(0.1)
						await process_frame
						var added: int = game.career.decisions.size() - count
						check(added in [0, 1], "production clock at most one adoption per frame")
						if added == 1:
							automatic += 1
							transitions += 1
							price += absf(game.career.state.four_quarter_inflation_pct - game.career.params.inflation_target_pct)
							jobs += maxf(0.0, game.career.state.unemployment_rate_pct - game.career.state.structural_unemployment_pct)
							funding += game.career.state.uncovered_funding_pct_initial_gdp / game.career.state.decision_nominal_gdp_ratio
					check(not game.routine.active or game.career.decisions.size() == 60, "routine returns within bounded frame budget")
				check(game.career.decisions.size() == 60, "exact 60-quarter screen")
				var row := {"scenario":scenario,"seed":seed_value,"policy":kind,"attended":attended,"automatic":automatic,"price_distance":price / 60.0,"employment_shortfall":jobs / 60.0,"uncovered_funding":funding / 60.0}
				check(JSON.stringify(row) == reference[rows.size()], "canonical logged summary matches frozen reference; not full trajectory equality")
				rows.append(row)
				print("PRODUCTION_SCREEN ", JSON.stringify(row))
				game.routine.stop()
				game.music.free()
				game.queue_free()
				await process_frame
				var release_deadline := Time.get_ticks_msec() + 100
				while Time.get_ticks_msec() < release_deadline:
					await process_frame
				if failures: quit(1); return
	check(rows.size() == 6 and transitions == 360, "6 paths and 360 confirmed native adoptions")
	print("%s: public advice integration paths=%d transitions=%d failures=%d; simulated input, no player save" % ["PASS" if failures == 0 else "FAIL", rows.size(), transitions, failures])
	quit(0 if failures == 0 else 1)
