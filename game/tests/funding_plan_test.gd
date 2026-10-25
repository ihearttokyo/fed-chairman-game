extends SceneTree
## Synthetic native layout fixtures; never calls an economic model or forecast.
const FundingPlan = preload("res://play/funding_plan.gd")
const WrappedTooltip = preload("res://play/wrapped_tooltip.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for frame in range(6):
		await process_frame

func fixture(renew: float = 1.98, fresh: float = 0.1, reserve: float = 0.0, unmet: float = 0.0) -> Dictionary:
	return {"liquidity_refinancing_applied_pct_initial_gdp": renew,
		"liquidity_new_need_applied_pct_initial_gdp": fresh,
		"liquidity_aggregate_applied_pct_initial_gdp": reserve,
		"liquidity_applied_pct_initial_gdp": renew + fresh + reserve,
		"uncovered_funding_pct_initial_gdp": unmet}

func run() -> void:
	var source := fixture()
	var frozen := var_to_bytes(source)
	var shown := FundingPlan.present(source, 2.08, 1.0)
	check(shown.ok and shown.visible and shown.applied_initial_gdp == 2.08 and shown.offered_initial_gdp == 2.08, "preview retains actual gross applied and offered principal")
	check(shown.amounts_initial_gdp == [1.98, 0.1, 0.0] and shown.amounts_meeting_gdp == [1.98, 0.1, 0.0], "renewed contracts, fresh cash and aggregate reserves stay separate")
	check(shown.labels == ["Renew 1.98", "Fresh cash 0.10", "Reserve loans 0.00"], "legend names economic allocation, not total lending as cash")
	check(absf(shown.fractions[0] - 1.98 / 2.08) < 1e-12 and absf(shown.fractions[1] - 0.1 / 2.08) < 1e-12 and shown.fractions[2] == 0, "bar splits 2.08 into proportional 1.98 renew and 0.1 fresh segments")
	check(shown.heading.contains("2.08 applied / 2.08 offered") and shown.heading.contains("% meeting GDP") and shown.unmet_text.is_empty(), "heading exposes applied/offered in explicit current meeting units without unnecessary warning")
	shown = FundingPlan.present(source, 2.08, 2.0)
	check(shown.applied_meeting_gdp == 1.04 and shown.offered_meeting_gdp == 1.04 and shown.amounts_meeting_gdp == [0.99, 0.05, 0.0] and shown.labels[1] == "Fresh cash 0.05", "all display amounts convert once using actual meeting GDP, fractions stay unit invariant")
	var partial := fixture(0.4, 0, 0, 1.68)
	shown = FundingPlan.present(partial, 0.4, 2.0)
	check(shown.applied_initial_gdp == 0.4 and shown.unmet_initial_gdp == 1.68 and shown.unmet_meeting_gdp == 0.84 and shown.unmet_text == "Unmet local 0.84", "low offer exposes accepted renewal plus unmet local need, never fictitious fresh cash")
	var reserves := fixture(0.4, 0.1, 0.5)
	shown = FundingPlan.present(reserves, 1.0, 1.0)
	check(shown.fractions == [0.4, 0.1, 0.5] and shown.labels[2] == "Reserve loans 0.50", "reserve loans have their own proportional segment and label")
	var quiet := fixture(0, 0, 0, 0)
	shown = FundingPlan.present(quiet, 0, 1)
	check(shown.ok and not shown.visible and shown.fractions == [0.0, 0.0, 0.0], "valid all-zero plan hides without fabricating utilization")
	check(FundingPlan.present(quiet, 1, 1).visible, "an offered but unused loan remains a visible plan")
	check(FundingPlan.present(fixture(0, 0, 0, 1), 0, 1).visible, "unmet local need remains visible even with no offer")
	for pair in [[1e-9, "<0.0001"], [0.004, "0.0040"]]:
		var tiny := fixture(0, pair[0], 0, pair[0])
		shown = FundingPlan.present(tiny, pair[0], 1)
		check(shown.heading.contains(pair[1] + " applied") and shown.labels[1] == "Fresh cash " + pair[1] and shown.unmet_text == "Unmet local " + pair[1], "tiny positive offer/applied/need never rounds to zero")
	var huge := fixture(4e307, 2e307, 4e307, 1e307)
	shown = FundingPlan.present(huge, 1e308, 1)
	check(shown.ok and is_finite(shown.applied_meeting_gdp) and absf(shown.fractions[0] - 0.4) < 1e-12 and absf(shown.fractions[1] - 0.2) < 1e-12 and absf(shown.fractions[2] - 0.4) < 1e-12, "huge finite allocation uses normalized finite ratios without an overflowing sum")
	check(not FundingPlan.present(huge, 1e308, 1e-300).ok, "unrepresentable converted amounts fail closed instead of emitting infinity")
	for field in source:
		var missing := source.duplicate(true)
		missing.erase(field)
		check(not FundingPlan.present(missing, 2.08, 1).ok, "missing " + field + " is unavailable, not zero")
		for invalid in [-0.001, NAN, INF, -INF, "1", true]:
			var bad := source.duplicate(true)
			bad[field] = invalid
			check(not FundingPlan.present(bad, 2.08, 1).ok, "physical " + field + " rejects malformed values")
	for invalid in [-1.0, NAN, INF, -INF]:
		check(not FundingPlan.present(source, invalid, 1).ok, "invalid offer fails closed")
	for invalid in [0.0, -1.0, NAN, INF, -INF]:
		check(not FundingPlan.present(source, 2.08, invalid).ok, "meeting GDP denominator must be positive and finite")
	var inconsistent := source.duplicate(true)
	inconsistent.liquidity_applied_pct_initial_gdp = 2.0
	check(not FundingPlan.present(inconsistent, 2.08, 1).ok, "unreconciled allocation cannot draw misleading proportions")
	check(not FundingPlan.present(source, 1, 1).ok, "applied principal cannot materially exceed the offer")
	var irrelevant := source.duplicate(true)
	irrelevant.balance_sheet_error = -1e-15
	check(FundingPlan.present(irrelevant, 2.08, 1).ok, "unrelated diagnostic dust is not treated as an allocation leg")
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(600, 480)
	var host := VBoxContainer.new()
	host.size = Vector2(root.size)
	root.add_child(host)
	var plan := FundingPlan.new()
	host.add_child(plan)
	check(not plan.visible and not plan.snapshot.ok, "cold plan contains no stale preview")
	plan.update_plan(source, 2.08, 1)
	await settle()
	check(plan.visible and plan.snapshot.ok and plan.snapshot.applied_initial_gdp == 2.08 and plan.bar.fractions == plan.snapshot.fractions, "actual component exposes pure snapshot and proportional native graphic")
	check(plan.size.y <= 75 and plan.bar.size.y == 10, "ordinary lending preview stays one compact strip near seventy pixels")
	# Rect2/Vector2 store native float32 geometry, unlike the pure double-valued
	# fractions checked above. Verify subpixel width accuracy plus the actual
	# 19.8:1 visual contrast, rather than imposing float64 precision on pixels.
	var renew_width := plan.bar.segment_rect(0).size.x
	var fresh_width := plan.bar.segment_rect(1).size.x
	var pixel_tolerance := 0.001
	check(absf(renew_width - plan.bar.size.x * (1.98 / 2.08)) <= pixel_tolerance and absf(fresh_width - plan.bar.size.x * (0.1 / 2.08)) <= pixel_tolerance, "actual segment widths match exact allocation within one-thousandth of a native pixel")
	check(fresh_width > 0 and renew_width > 19.7 * fresh_width and renew_width < 19.9 * fresh_width, "actual drawn allocation retains meaningful 19.8-to-one contrast, not equal status bars")
	check(plan.bar.segment_rect(2).size.x == 0 and is_equal_approx(plan.bar.segment_rect(1).end.x, plan.bar.size.x), "zero reserve leg has no false fill and applied allocations span the bar")
	for label in plan.legend_labels:
		check(not label.accessibility_name.is_empty() and not label.tooltip_text.is_empty() and label.accessibility_description == label.tooltip_text and label.get_theme_font_size("font_size") == 12, "legend remains readable and native assistive text includes its meaning")
	check(plan.legend_labels[0].tooltip_text.contains("not fresh cash") and plan.legend_labels[2].tooltip_text.contains("not local withdrawal payments"), "renewal and aggregate reserves cannot be mistaken for local cash payments")
	check(plan.unmet_label.tooltip_text.contains("not capital repair") and not plan.unmet_label.visible, "unmet warning distinguishes funding from capital and hides when not needed")
	check(plan.bar.accessibility_name.contains("Renew 1.98") and plan.bar.accessibility_name.contains("Fresh cash 0.10") and plan.bar.tooltip_text.contains("applied lending"), "graph exposes exact allocation labels and its scale without color")
	var bar_script: Script = plan.bar.get_script()
	WrappedTooltip.install(host)
	check(plan.bar.get_script() == bar_script and plan.bar.has_method("_make_custom_tooltip"), "global installer preserves scripted allocation bar with its own wrapped tooltip hook")
	var ids := [plan.get_instance_id(), plan.bar.get_instance_id(), plan.legend_labels[0].get_instance_id()]
	for width in [280, 600]:
		root.size = Vector2i(width, 480)
		host.size.x = width
		plan.update_plan(reserves, 1, 1)
		await settle()
		check(plan.size.x <= width and plan.get_global_rect().grow(1).encloses(plan.bar.get_global_rect()), "native lending graphic fits width " + str(width))
		for label in plan.legend_labels:
			check(plan.get_global_rect().grow(1).encloses(label.get_global_rect()) and root.get_visible_rect().grow(1).encloses(label.get_global_rect()), "legend stays inside narrow native viewport")
		check(plan.legend_labels[0].global_position.y < plan.legend_labels[2].global_position.y if width == 280 else plan.legend_labels[0].global_position.y == plan.legend_labels[2].global_position.y, "allocation legend wraps only when required")
		await check_bar_tooltip(plan.bar, width)
	check(ids == [plan.get_instance_id(), plan.bar.get_instance_id(), plan.legend_labels[0].get_instance_id()], "resize/updates preserve native controls")
	for control in [plan, plan.heading, plan.bar, plan.legend, plan.unmet_label] + plan.legend_labels:
		check(control.focus_mode == Control.FOCUS_NONE, "read-only lending preview adds no Tab stops")
	plan.update_plan(partial, 0.4, 1)
	check(plan.unmet_label.visible and plan.unmet_label.text == "Unmet local 1.68", "actual partial plan exposes a separate short unmet warning")
	plan.update_plan({}, 0, 1)
	check(not plan.visible and not plan.snapshot.ok and plan.heading.text.is_empty() and plan.bar.fractions == [0.0, 0.0, 0.0], "reused invalid projection clears and hides prior amounts and graphic")
	check(plan.bar.accessibility_name.is_empty() and plan.bar.tooltip_text.is_empty() and plan.legend_labels[0].text.is_empty() and plan.legend_labels[0].accessibility_name.is_empty() and plan.unmet_label.text.is_empty(), "invalid refresh removes stale assistive descriptions and warnings")
	plan.update_plan(source, 2.08, 1)
	plan.update_plan(quiet, 0, 1)
	check(not plan.visible and plan.snapshot.ok and not plan.snapshot.visible and plan.heading.text.is_empty(), "all-zero refresh hides and clears display while retaining valid zero snapshot")
	check(var_to_bytes(source) == frozen, "presenting, updating and resizing never mutate authoritative forecast")
	host.free()
	print("%s: funding plan %d checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func check_bar_tooltip(owner: Control, width: int) -> void:
	# Invoke the custom control's actual native tooltip hook, not the shared
	# factory directly: the installer intentionally skips scripted controls.
	var tip: Control = owner._make_custom_tooltip(owner.tooltip_text)
	check(tip is PanelContainer, "allocation bar supplies the shared native wrapped tooltip panel")
	root.add_child(tip)
	await settle()
	var body: Label = tip.get_child(0)
	check(body.text == owner.tooltip_text and body.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and body.get_line_count() > 1, "custom bar tooltip wraps the full exact allocation explanation at width " + str(width))
	check(tip.size.x <= minf(WrappedTooltip.MAX_WIDTH, width - WrappedTooltip.VIEWPORT_INSET) + 1, "custom bar tooltip remains within the logical viewport width budget")
	check(body.get_theme_font_size("font_size") >= 14 and tip.size.y >= body.size.y + WrappedTooltip.PADDING * 2, "custom bar tooltip preserves fourteen-pixel minimum type and padded height")
	tip.free()
