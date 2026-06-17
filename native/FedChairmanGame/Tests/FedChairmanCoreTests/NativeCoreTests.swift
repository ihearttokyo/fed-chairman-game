@testable import FedChairmanCore
import Testing

@Test func startingScenarioMatchesClassicMode() {
    #expect(classicScenario.termQuarters == 16)
    #expect(classicScenario.startingState.inflation == 2.11)
    #expect(classicScenario.startingState.unemployment == 4.68)
    #expect(classicScenario.startingState.fedFundsRate == 4)
    #expect(classicScenario.targets.inflation == 2)
    #expect(classicScenario.targets.unemployment == 5)
}

@Test func holdDecisionMatchesTypeScriptGoldenQuarterOne() throws {
    let scenario = classicScenario
    let decision = createDecision(action: .hold, current: scenario.startingState, timestamp: "test")
    let result = try advanceQuarter(
        history: [scenario.startingState],
        decision: decision,
        scenario: scenario,
        activeShocks: [],
        seed: "unit-seed",
        termNumber: 1,
    )

    #expect(result.nextState.quarterIndex == 1)
    #expect(result.nextState.inflation == 2.07)
    #expect(result.nextState.unemployment == 4.67)
    #expect(result.nextState.fedFundsRate == 4)
    #expect(result.nextState.outputGap == 0.02)
    #expect(result.nextState.expectedInflation == 2.15)
    #expect(result.nextState.credibility == 82.6)
    #expect(result.trace.neutralRate == 3.65)
    #expect(result.trace.laggedPolicyGap == 0.35)
    #expect(result.trace.inflationDelta == -0.04)
    #expect(result.trace.unemploymentDelta == -0.01)
    #expect(result.trace.credibilityDelta == 0.6)
}

@Test func customBpsDecisionCommitsCanonicalRateChange() throws {
    let store = GameSessionStore()
    store.start(seed: "custom-bps")
    try store.commitCustom(rateChange: 0.37)

    #expect(store.session.current.quarterIndex == 1)
    #expect(store.session.decisions.first?.action == .custom)
    #expect(store.session.decisions.first?.rateChange == 0.37)
    #expect(store.session.decisions.first?.resultingFedFundsRate == 4.37)
}

@Test func reappointmentGraceAppliesOnlyForInflationRestoringPolicy() throws {
    var overheated = classicScenario.startingState
    overheated.inflation = 4.2
    overheated.unemployment = 5
    overheated.expectedInflation = 3.1
    overheated.credibility = 55
    let hike = createDecision(action: .raise50, current: overheated, timestamp: "test")
    let cut = createDecision(action: .cut50, current: overheated, timestamp: "test")

    let termTwoHike = try advanceQuarter(history: [overheated], decision: hike, scenario: classicScenario, activeShocks: [], seed: "unit-seed", termNumber: 2)
    let termOneHike = try advanceQuarter(history: [overheated], decision: hike, scenario: classicScenario, activeShocks: [], seed: "unit-seed", termNumber: 1)
    let wrongWayCut = try advanceQuarter(history: [overheated], decision: cut, scenario: classicScenario, activeShocks: [], seed: "unit-seed", termNumber: 2)

    #expect((termTwoHike.trace.credibilityReappointmentGrace ?? 0) > 0)
    #expect((termTwoHike.trace.credibilityDelta ?? 0) > 0)
    #expect((termTwoHike.trace.credibilityDelta ?? 0) <= 0.6)
    #expect(termOneHike.trace.credibilityReappointmentGrace == 0)
    #expect(wrongWayCut.trace.credibilityReappointmentGrace == 0)
}

@Test func shockDeckIsDeterministicPerSeedAndTerm() {
    #expect(buildTermShockDeck(seed: "classic-2026", termNumber: 3) == buildTermShockDeck(seed: "classic-2026", termNumber: 3))
    #expect(buildTermShockDeck(seed: "classic-2026", termNumber: 3) != buildTermShockDeck(seed: "classic-2026", termNumber: 4))
}

@Test func saveFileDetectsTamperingAndRecomputesScores() throws {
    let store = GameSessionStore()
    store.start(seed: "save-file")
    try store.commit(action: .hold)
    let saveText = try createSaveFile(session: store.session)
    let loaded = try parseSaveFile(saveText)
    #expect(loaded.currentTermQuarter == 1)

    let tampered = saveText.replacingOccurrences(of: "\"inflation\" : 2.05", with: "\"inflation\" : 3.05")
    do {
        _ = try parseSaveFile(tampered)
        Issue.record("Tampered save parsed successfully.")
    } catch let error as NativeEngineError {
        #expect(error == .tamperedSaveFile)
    }
}

@Test func exportersUseFullCareerTimelineAndDecisionLog() throws {
    let store = GameSessionStore()
    store.start(seed: "export-file")
    try store.commit(action: .cut25)
    try store.commitCustom(rateChange: 0.42)

    let csv = sessionToCsv(store.session)
    #expect(csv.contains("term,quarter,careerQuarter,label,boundary,policyAction,policyRateChange"))
    #expect(csv.contains("T1 start"))
    #expect(csv.contains("Custom +42 bps"))

    let markdown = sessionToMarkdown(store.session)
    #expect(markdown.contains("## Term Boundaries"))
    #expect(markdown.contains("## Decision Log"))
    #expect(markdown.contains("| T1 Q2 | Q2 | Custom +42 bps |"))

    let json = try sessionToJson(store.session)
    #expect(json.contains("\"careerHistory\""))
    #expect(json.contains("\"rateChange\" : 0.42"))
}

@Test func storeCanLoadAndRecomputeNativeSave() throws {
    let original = GameSessionStore()
    original.start(seed: "native-load")
    try original.commit(action: .raise25)

    let saveText = try createSaveFile(session: original.session)
    let loaded = try parseSaveFile(saveText)
    let store = GameSessionStore()
    try store.load(session: loaded)

    #expect(store.session.totalCareerQuarters == 1)
    #expect(store.session.careerScore == evaluateScore(history: store.session.careerHistory, scenario: classicScenario))
}

@Test func termEndCreatesDebriefAndCanContinueWhenReappointed() throws {
    let store = GameSessionStore()
    store.start(seed: "native-debrief")
    for _ in 0 ..< classicScenario.termQuarters {
        try store.commit(action: .hold)
    }

    #expect(store.session.currentTermQuarter == classicScenario.termQuarters)
    #expect(store.session.totalCareerQuarters == classicScenario.termQuarters)
    #expect(!store.session.completedTerms.isEmpty)
    #expect(store.session.status == .termDebrief || store.session.status == .notReappointed)

    if store.session.status == .termDebrief {
        try store.continueNextTerm()
        #expect(store.session.status == .inProgress)
        #expect(store.session.termNumber == 2)
        #expect(store.session.currentTermQuarter == 0)
        #expect(store.session.careerHistory.count == classicScenario.termQuarters + 1)
    }
}

@Test func cockpitBriefingSeparatesDynamicNewsFromStaticHelp() throws {
    let store = GameSessionStore()
    store.start(seed: "native-briefing")
    try store.commit(action: .hold)

    let briefing = buildCockpitBriefing(session: store.session)
    #expect(!briefing.headline.contains("Policy Questions"))
    #expect(!briefing.body.contains("Your Job"))
    #expect(briefing.metadata.contains("Term 1"))
    #expect(!briefing.policyImplication.isEmpty)
    #expect(!briefing.riskCalendar.isEmpty)

    let help = staticHelpTopics()
    #expect(help.contains { $0.title == "Policy Questions" })
    #expect(help.contains { $0.body.contains("unemployment") && $0.body.contains("output gap") })
}

@Test func nativeHelpTopicsMatchNotebookAndAddDynamicContext() {
    var current = classicScenario.startingState
    current.inflation = 3.4
    current.unemployment = 6.7
    current.expectedInflation = 2.6
    let trace = EngineTrace(
        neutralRate: 4.6,
        policyGap: 0.4,
        laggedPolicyGap: 0.9,
        shockContrib: ["energy": 0.5],
        credibilityBaseDrift: -1.8,
        credibilityRateMoveCost: 0,
        credibilityReappointmentGrace: 0,
        credibilityDelta: -1.8,
        inflationDelta: 0.3,
        unemploymentDelta: 0.2,
        gdpDelta: -0.1,
        explanation: "Energy shock lifted price pressure.",
    )
    let activeShock = ActiveShock(
        shock: Shock(id: "energy", quarter: .fixed(1), type: .energy, magnitude: 0.5, persistence: 2, headlineKey: "energy"),
        startedQuarter: 1,
        remaining: 2,
    )

    let topics = buildHelpTopics(current: current, scenario: classicScenario, trace: trace, activeShocks: [activeShock])
    let titles = topics.map(\.title)
    #expect(titles.starts(with: ["Your Job", "Federal Funds Rate", "Dual Mandate", "Expansionary Policy", "Contractionary Policy", "Policy Lags"]))
    #expect(titles.contains("Why Credibility Matters"))
    #expect(titles.contains("Easing With Care"))
    #expect(titles.contains("Reading Old Decisions"))
    #expect(titles.contains("Temporary Shock Or Trend?"))
    #expect(topics.first { $0.title == "Federal Funds Rate" }?.body.contains("neutral near") == true)
    #expect(topics.filter(\.isPrimary).map(\.title) == ["Your Job", "Federal Funds Rate"])
}

@Test func cockpitDockStateTogglesExclusivelyAndPlacesPanelDeterministically() {
    var state = CockpitDockState()
    state.toggle(.help)
    state.toggle(.settings)

    #expect(state.openPanels == [.settings])
    #expect(!state.isOpen(.help))
    #expect(state.isOpen(.settings))
    #expect(!state.isOpen(.newspaper))

    let placements = state.cascadePlacements()
    #expect(placements.map(\.panel) == [.settings])
    #expect(placements[0].xOffset == 0)
    #expect(placements[0].yOffset == 0)

    state.toggle(.newspaper)
    #expect(state.openPanels == [.newspaper])
    #expect(state.pinnedBriefing)
    #expect(state.isOpen(.newspaper))
    #expect(!state.isOpen(.settings))
    state.closeAll()
    #expect(state.openPanels.isEmpty)
    #expect(!state.pinnedBriefing)
}

@Test func cockpitMotionModeHonorsReducedMotionSources() {
    var ui = UiState.default
    #expect(cockpitMotionMode(reduceMotion: false, ui: ui) == .spring)
    #expect(cockpitMotionMode(reduceMotion: true, ui: ui) == .reduced)
    ui.reducedMotion = true
    #expect(cockpitMotionMode(reduceMotion: false, ui: ui) == .reduced)
}

@Test func cockpitLayoutMetricsRespondToWindowSize() {
    let compact = cockpitLayoutMetrics(width: 1180, height: 700)
    let standard = cockpitLayoutMetrics(width: 1360, height: 860)
    let expanded = cockpitLayoutMetrics(width: 1600, height: 1000)

    #expect(compact.mode == .compact)
    #expect(standard.mode == .standard)
    #expect(expanded.mode == .expanded)
    #expect(compact.policyKeyWidth < standard.policyKeyWidth)
    #expect(standard.policyKeyWidth < expanded.policyKeyWidth)
    #expect(compact.chartHeight < standard.chartHeight)
    #expect(standard.chartHeight < expanded.chartHeight)
    #expect(compact.chartHeight <= 180)
    #expect(standard.chartHeight <= 235)
    #expect(expanded.chartHeight <= 265)
    #expect(compact.metricsColumns == 3)
    #expect(compact.dockBottomLift == 0)
    #expect(standard.dockBottomLift == 0)
    #expect(expanded.dockBottomLift == 0)
    #expect(compact.dockVerticalOffset == 0)
    #expect(standard.dockVerticalOffset == 0)
    #expect(expanded.dockVerticalOffset == 0)
    #expect(compact.newspaperPanelWidth <= 1148)
    #expect(standard.newspaperPanelWidth <= 1312)
    #expect(expanded.newspaperPanelWidth <= 1552)
    #expect(compact.dockPanelMaxHeight <= 530)
}

@Test func nativeDebriefBuildsRichTermGateContent() throws {
    let store = GameSessionStore()
    store.start(seed: "native-rich-debrief")
    for _ in 0 ..< classicScenario.termQuarters {
        try store.commit(action: .hold)
    }

    let debrief = buildNativeDebrief(session: store.session)
    #expect(debrief.boardVerdict.contains("board"))
    #expect(debrief.termStanding.contains("Term 1"))
    #expect(debrief.decisionMix.contains("meetings"))
    #expect(debrief.termHandoff.contains("inherited"))
    #expect(debrief.termHandoffMetrics.count == 4)
    #expect(!debrief.policyStyle.isEmpty)
    #expect(!debrief.bestStretch.isEmpty)
    #expect(!debrief.coachingFocus.isEmpty)
    #expect(!debrief.carryoverMetrics.isEmpty)

    if store.session.status == .termDebrief {
        #expect(debrief.nextTermBrief.contains("Term 2"))
        #expect(debrief.gateStatus.contains("Retirement"))
    }
}

@Test func nativeTransmissionBriefingDerivesThreeMonthSequence() throws {
    let store = GameSessionStore()
    store.start(seed: "native-transmission")
    try store.commit(action: .raise25)

    let briefing = try #require(buildTransmissionBriefing(session: store.session))
    #expect(briefing.steps.map(\.month) == ["Month 1", "Month 2", "Month 3"])
    #expect(briefing.steps[0].traceInputs == ["latest PolicyDecision", "EngineTrace.neutralRate", "scenario inflation target"])
    #expect(briefing.steps[1].traceInputs.contains("EngineTrace.laggedPolicyGap"))
    #expect(briefing.steps[2].traceInputs.contains("EngineTrace.inflationDelta"))
    #expect(briefing.path.count == 3)
    #expect(briefing.changes.map(\.label) == ["Inflation", "Unemployment", "Output gap", "Credibility"])
    #expect(briefing.receipt.policyEcho.contains("0.25"))
    #expect(briefing.decisionMemo.assessment.contains("Before the vote"))
    #expect(buildTransmissionBriefing(session: GameSessionStore.makeInitialSession(seed: "opening")) == nil)
}

@Test func decisionFeedbackSummarizesPolicyMoveAndSoundPreferences() throws {
    let opening = GameSessionStore.makeInitialSession(seed: "decision-feedback")
    let openingFeedback = buildDecisionFeedback(session: opening)
    #expect(openingFeedback.headline == "Awaiting first vote")
    #expect(openingFeedback.moveLabel == "Choose rate move")
    #expect(openingFeedback.ratePath.contains("4.00%"))
    #expect(openingFeedback.tone == .stabilizing)

    let store = GameSessionStore()
    store.start(seed: "decision-feedback")
    try store.commit(action: .raise25)
    let feedback = buildDecisionFeedback(session: store.session)
    #expect(feedback.moveLabel == "+25 bps")
    #expect(feedback.ratePath == "4.00% -> 4.25%")
    #expect(feedback.mandateLine.contains("inflation"))
    #expect(feedback.credibilityLine.contains("rate cost"))
    #expect(feedback.traceLine.contains("neutral"))
    #expect(feedback.intensity >= 0)

    var ui = UiState.default
    #expect(!shouldPlayCockpitSound(ui: ui))
    ui.soundEnabled = true
    ui.soundVolume = 0.4
    #expect(shouldPlayCockpitSound(ui: ui))
    #expect(cockpitSoundVolume(ui: ui) == 0.4)
    ui.reducedNoise = true
    #expect(!shouldPlayCockpitSound(ui: ui))
}

@Test func chartInspectionLabelsCareerAndPolicyContext() throws {
    let opening = GameSessionStore.makeInitialSession(seed: "chart-inspection")
    let openingInspection = try #require(buildChartInspection(history: opening.careerHistory))
    #expect(openingInspection.primaryLabel == "Career start")
    #expect(openingInspection.secondaryLabel == "Before Term 1")
    #expect(openingInspection.policy == "Starting economy")
    #expect(openingInspection.movement == "Opening snapshot before the first vote.")

    let store = GameSessionStore()
    store.start(seed: "chart-inspection")
    try store.commit(action: .raise25)
    try store.commit(action: .cut50)
    let decisions = store.session.completedTerms.flatMap(\.decisions) + store.session.decisions
    let latest = try #require(buildChartInspection(history: store.session.careerHistory, decisions: decisions))
    #expect(latest.primaryLabel == "T1 Q2")
    #expect(latest.secondaryLabel == "Career Q2 | 14 left in term")
    #expect(latest.policy == "-50 bps")
    #expect(latest.movement.contains("Since prior: inflation"))
    #expect(chartInspectionAccessibilityLabel(latest).contains("Policy: -50 bps"))

    let firstQuarter = try #require(buildChartInspection(history: store.session.careerHistory, decisions: decisions, selectedIndex: 1))
    #expect(firstQuarter.primaryLabel == "T1 Q1")
    #expect(firstQuarter.policy == "+25 bps")

    let longCareer = (0 ... 17).map { index in
        var state = classicScenario.startingState
        state.quarterIndex = index == 0 ? 0 : ((index - 1) % classicScenario.termQuarters) + 1
        return state
    }
    let termTwo = try #require(buildChartInspection(history: longCareer, selectedIndex: 17))
    #expect(termTwo.primaryLabel == "T2 Q1")
    #expect(termTwo.secondaryLabel == "Career Q17 | 15 left in term")
}
