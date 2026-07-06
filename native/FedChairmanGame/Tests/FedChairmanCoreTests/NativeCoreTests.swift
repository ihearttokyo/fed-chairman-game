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

@Test func holdDecisionMatchesNativeGoldenQuarterOne() throws {
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

@Test func targetRestoringPolicyDefendsCredibilityWithoutPoliticalGrace() throws {
    var overheated = classicScenario.startingState
    overheated.inflation = 4.2
    overheated.unemployment = 5
    overheated.expectedInflation = 3.1
    overheated.credibility = 55
    let hike = createDecision(action: .raise50, current: overheated, timestamp: "test")
    let cut = createDecision(action: .cut50, current: overheated, timestamp: "test")

    let targetRestoringHike = try advanceQuarter(history: [overheated], decision: hike, scenario: classicScenario, activeShocks: [], seed: "unit-seed", termNumber: 2)
    let termOneHike = try advanceQuarter(history: [overheated], decision: hike, scenario: classicScenario, activeShocks: [], seed: "unit-seed", termNumber: 1)
    let wrongWayCut = try advanceQuarter(history: [overheated], decision: cut, scenario: classicScenario, activeShocks: [], seed: "unit-seed", termNumber: 2)

    #expect(targetRestoringHike.trace.credibilityReappointmentGrace == 0)
    #expect((targetRestoringHike.trace.credibilityDelta ?? 0) > (wrongWayCut.trace.credibilityDelta ?? 0))
    #expect(targetRestoringHike.trace.credibilityDelta == termOneHike.trace.credibilityDelta)
    #expect(termOneHike.trace.credibilityReappointmentGrace == 0)
    #expect(wrongWayCut.trace.credibilityReappointmentGrace == 0)
}

@Test func shockDeckIsDeterministicPerSeedAndTerm() {
    #expect(buildTermShockDeck(seed: "classic-2026", termNumber: 3) == buildTermShockDeck(seed: "classic-2026", termNumber: 3))
    #expect(buildTermShockDeck(seed: "classic-2026", termNumber: 3) != buildTermShockDeck(seed: "classic-2026", termNumber: 4))
}

@Test func firstTermShockDeckIsGentlerForNewPlayers() {
    let firstTerm = buildTermShockDeck(seed: "classic-2026", termNumber: 1)
    let laterTerm = buildTermShockDeck(seed: "classic-2026", termNumber: 2)

    #expect(firstTerm.count == 4)
    #expect(firstTerm.allSatisfy { abs($0.magnitude) <= 1.0 })
    #expect(firstTerm.map { abs($0.magnitude) }.max() ?? 0 < laterTerm.map { abs($0.magnitude) }.max() ?? 0)
}

@Test func cockpitBriefingsVaryDeterministicallyAcrossSeeds() {
    let headlines = Set((0 ..< 8).map { index in
        let store = GameSessionStore()
        store.start(seed: "briefing-variant-\(index)")
        return buildCockpitBriefing(session: store.session).headline
    })

    #expect(headlines.count > 1)
    let store = GameSessionStore()
    store.start(seed: "briefing-stable")
    #expect(buildCockpitBriefing(session: store.session) == buildCockpitBriefing(session: store.session))
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
    state.toggle(.newspaper)
    state.toggle(.help)

    #expect(state.openPanels == [.help])
    #expect(state.isOpen(.help))
    #expect(!state.isOpen(.newspaper))

    let placements = state.cascadePlacements()
    #expect(placements.map(\.panel) == [.help])
    #expect(placements[0].xOffset == 0)
    #expect(placements[0].yOffset == 0)

    state.toggle(.newspaper)
    #expect(state.openPanels == [.newspaper])
    #expect(state.pinnedBriefing)
    #expect(state.isOpen(.newspaper))
    #expect(!state.isOpen(.help))
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

@Test func boardWatchSummarizesLiveReappointmentGate() throws {
    let store = GameSessionStore()
    store.start(seed: "board-watch")
    try store.commit(action: .hold)

    let openingWatch = buildBoardWatch(session: store.session)
    #expect(openingWatch.tone == .onTrack)
    #expect(openingWatch.headline == "On track for renewal")
    #expect(openingWatch.gateLabel == "3/3 gates")
    #expect(openingWatch.scoreDetail.contains("needs 70"))
    #expect(openingWatch.riskLabel == "Protect the glide path")
    #expect(openingWatch.accessibilityLabel.contains("Board Watch"))

    var stressedSession = store.session
    stressedSession.current.inflation = 5.2
    stressedSession.current.unemployment = 8.1
    stressedSession.score = ScoreState(
        score: 58,
        grade: .f,
        reappointed: false,
        meanAbsInflationGap: 2.2,
        meanAbsUnemploymentGap: 2.9,
        volatilityIndex: 1.1,
        recessionQuarterShare: 0.4,
        credibilityBonus: 0,
        biggestMiss: "recession risk",
        takeaway: "Stabilize the mandate before the gate.",
    )

    let stressedWatch = buildBoardWatch(session: stressedSession)
    #expect(stressedWatch.tone == .danger)
    #expect(stressedWatch.headline == "Renewal at risk")
    #expect(stressedWatch.gateLabel == "0/3 gates")
    #expect(stressedWatch.riskLabel == "Raise score above 70")
}

@Test func fixedTwoPercentInflationTargetShapesBriefingAndBoardWatch() {
    var session = makeInitialSession(seed: "fixed-target")
    session.status = .inProgress
    session.current.inflation = 4.4
    session.score = evaluateScore(history: [session.current], scenario: classicScenario)

    let briefing = buildCockpitBriefing(session: session)
    #expect(briefing.kicker != "Cheat Event")
    #expect(briefing.policyImplication.localizedCaseInsensitiveContains("tighter"))

    let watch = buildBoardWatch(session: session)
    #expect(watch.inflationDetail.contains("renewal gate 4.00%"))
    #expect(watch.riskLabel == "Cool inflation below the renewal gate")
}

@Test func credibilityIsSymmetricAroundTwoPercentTargetAndDefendsForcefulMoves() throws {
    let highInflation = MacroState(
        quarterIndex: 0,
        quartersRemaining: 16,
        inflation: 5.8,
        unemployment: 5.1,
        fedFundsRate: 4.5,
        outputGap: 0.35,
        gdpGrowth: 1.9,
        expectedInflation: 4.9,
        credibility: 70,
    )
    let decision = createDecision(action: .hold, current: highInflation, timestamp: "test")

    let normal = try advanceQuarter(
        history: [highInflation],
        decision: decision,
        scenario: classicScenario,
        activeShocks: [],
        seed: "credibility-engine-compare",
    )

    let defendingHike = try advanceQuarter(
        history: [highInflation],
        decision: createDecision(action: .raise150, current: highInflation, timestamp: "test"),
        scenario: classicScenario,
        activeShocks: [],
        seed: "credibility-engine-compare",
    )

    let lowInflation = MacroState(
        quarterIndex: 0,
        quartersRemaining: 16,
        inflation: 0.2,
        unemployment: 6.2,
        fedFundsRate: 4.5,
        outputGap: -0.25,
        gdpGrowth: 1.2,
        expectedInflation: 1.1,
        credibility: 70,
    )
    let lowMiss = try advanceQuarter(
        history: [lowInflation],
        decision: createDecision(action: .hold, current: lowInflation, timestamp: "test"),
        scenario: classicScenario,
        activeShocks: [],
        seed: "credibility-engine-low",
    )

    #expect((normal.trace.credibilityDelta ?? 0) < 0)
    #expect((defendingHike.trace.credibilityDelta ?? 0) >= (normal.trace.credibilityDelta ?? 0))
    #expect((lowMiss.trace.credibilityDelta ?? 0) < 0)
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
    #expect(compact.metricsColumns == 5)
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
    #expect(feedback.credibilityLine.contains("policy signal"))
    #expect(!feedback.credibilityLine.contains("rate cost"))
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

@Test func mandateChartFocusExposesRailTargetsAndRiskInsight() throws {
    let store = GameSessionStore()
    store.start(seed: "mandate-chart-focus")
    try store.commit(action: .raise25)

    let snapshot = buildTermSnapshot(session: store.session)
    let focus = buildMandateChartFocus(snapshot: snapshot)

    #expect(focus.railItems.map(\.metric) == [.inflation, .unemployment, .fedFunds])
    #expect(focus.railItems[0].target == "Target 2.0%")
    #expect(focus.railItems[1].target == "Target 5.0%")
    #expect(focus.railItems[2].target == "Policy rate")
    #expect(focus.insightHeadline == snapshot.riskDrivers.first?.title)
    #expect(focus.accessibilityLabel.contains("Inflation"))
    #expect(focus.accessibilityLabel.contains("Unemployment"))
}

@Test func mandateChartFocusKeepsSnapshotDrivenHierarchyAccessible() {
    var stressed = makeInitialSession(seed: "mandate-hierarchy")
    stressed.current.inflation = 4.2
    stressed.current.unemployment = 7.3
    stressed.current.fedFundsRate = 5.5
    stressed.current.credibility = 57

    let snapshot = buildTermSnapshot(session: stressed)
    let focus = buildMandateChartFocus(snapshot: snapshot)

    #expect(focus.insightHeadline == snapshot.riskDrivers[0].title)
    #expect(focus.insightDetail == snapshot.riskDrivers[0].detail)
    #expect(focus.railItems.map(\.label) == ["Inflation", "Unemployment", "Fed funds"])
    #expect(focus.railItems.map(\.state).contains(.critical))
    #expect(focus.accessibilityLabel.contains(focus.insightHeadline))
    #expect(focus.accessibilityLabel.contains("gap +2.20 pp"))
    #expect(focus.accessibilityLabel.contains("gap +2.30 pp"))
}

@Test func termSnapshotIsDeterministicAndDoesNotMutateSession() throws {
    let store = GameSessionStore()
    store.start(seed: "snapshot-determinism")
    try store.commit(action: .raise25)
    let original = store.session

    let first = buildTermSnapshot(session: store.session)
    let second = buildTermSnapshot(session: store.session)

    #expect(first == second)
    #expect(store.session == original)
    #expect(first.latestMetrics.inflation == original.current.inflation)
    #expect(first.latestMetrics.unemployment == original.current.unemployment)
    #expect(first.latestMetrics.fedFundsRate == original.current.fedFundsRate)
}

@Test func termSnapshotCarriesStableHierarchyModelsFromSingleSession() throws {
    let store = GameSessionStore()
    store.start(seed: "snapshot-hierarchy")
    try store.commit(action: .raise25)

    let snapshot = buildTermSnapshot(session: store.session)

    #expect(snapshot.sourceSessionId == store.session.sessionId)
    #expect(snapshot.status == store.session.status)
    #expect(snapshot.termNumber == store.session.termNumber)
    #expect(snapshot.currentTermQuarter == store.session.currentTermQuarter)
    #expect(snapshot.totalCareerQuarters == store.session.totalCareerQuarters)
    #expect(snapshot.boardWatch == buildBoardWatch(session: store.session))
    #expect(snapshot.briefing == buildCockpitBriefing(session: store.session))
    #expect(snapshot.decisionFeedback == buildDecisionFeedback(session: store.session))
    #expect(snapshot.chartInspection == buildChartInspection(
        history: store.session.careerHistory,
        decisions: store.session.completedTerms.flatMap(\.decisions) + store.session.decisions,
    ))
    #expect(snapshot.riskDrivers == buildRiskDrivers(session: store.session))
    #expect(snapshot.semanticState != .disabled)
    #expect(snapshot.chartInspection?.policy == "+25 bps")
}

@Test func riskDriversRankKnownPolicyStates() throws {
    let baseline = makeInitialSession(seed: "risk-baseline")
    #expect(buildTermSnapshot(session: baseline).riskDrivers.first?.kind == .inflationGap)

    var inflationRisk = baseline
    inflationRisk.current.inflation = 4.8
    inflationRisk.current.expectedInflation = 3.6
    inflationRisk.current.unemployment = 4.7
    inflationRisk.current.credibility = 82
    #expect(buildTermSnapshot(session: inflationRisk).riskDrivers.first?.kind == .inflationGap)

    var laborRisk = baseline
    laborRisk.current.inflation = 2.1
    laborRisk.current.unemployment = 7.4
    laborRisk.current.credibility = 82
    #expect(buildTermSnapshot(session: laborRisk).riskDrivers.first?.kind == .laborGap)

    var lowCredibility = baseline
    lowCredibility.current.inflation = 2.1
    lowCredibility.current.unemployment = 5.0
    lowCredibility.current.credibility = 48
    #expect(buildTermSnapshot(session: lowCredibility).riskDrivers.first?.kind == .credibility)

    let store = GameSessionStore()
    store.start(seed: "risk-lag-pressure")
    try store.commit(action: .raise150)
    try store.commit(action: .raise150)
    #expect(buildTermSnapshot(session: store.session).riskDrivers.first?.kind == .laggedPolicy)
}

@Test func policyPreviewSignsAndNoMutation() throws {
    let store = GameSessionStore()
    store.start(seed: "policy-preview")
    let original = store.session

    let cut = try #require(buildPolicyPreview(session: store.session, action: .cut50))
    let hold = try #require(buildPolicyPreview(session: store.session, action: .hold))
    let hike = try #require(buildPolicyPreview(session: store.session, action: .raise50))
    let custom = try #require(buildPolicyPreview(session: store.session, customBasisPoints: 75))

    #expect(cut.inflationPressure > 0)
    #expect(cut.unemploymentPressure < 0)
    #expect(hold.moveLabel == "Hold")
    #expect(hold.estimatedInflationPressure == .steady)
    #expect(hike.inflationPressure < 0)
    #expect(hike.unemploymentPressure > 0)
    #expect(custom.resultingFedFundsRate == 4.75)
    #expect(store.session == original)
}

@Test func commitAfterPreviewMatchesCurrentCommitPath() throws {
    let previewStore = GameSessionStore()
    previewStore.start(seed: "preview-commit-match")
    let preview = try #require(buildPolicyPreview(session: previewStore.session, action: .raise25))
    #expect(preview.resultingFedFundsRate == 4.25)
    try previewStore.commit(action: .raise25)

    let directStore = GameSessionStore()
    directStore.start(seed: "preview-commit-match")
    try directStore.commit(action: .raise25)

    #expect(previewStore.session.current == directStore.session.current)
    #expect(previewStore.session.traces == directStore.session.traces)
    #expect(previewStore.session.decisions.map(\.action) == directStore.session.decisions.map(\.action))
    #expect(previewStore.session.decisions.map(\.rateChange) == directStore.session.decisions.map(\.rateChange))
}

@Test func invalidCustomBpsOutsideV1RangeIsNotPreviewableOrCommitted() {
    let store = GameSessionStore()
    store.start(seed: "custom-bps-v1-range")
    let original = store.session

    #expect(buildPolicyPreview(session: store.session, customBasisPoints: -151) == nil)
    #expect(buildPolicyPreview(session: store.session, customBasisPoints: 151) == nil)
    #expect(store.session == original)
    #expect(buildPolicyPreview(session: original, customBasisPoints: -150) != nil)
    #expect(buildPolicyPreview(session: original, customBasisPoints: 150) != nil)
}
