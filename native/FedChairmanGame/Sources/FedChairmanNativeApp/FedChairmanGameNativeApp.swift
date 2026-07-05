import AppKit
import FedChairmanCore
import SwiftUI

// swiftlint:disable file_length

@main
struct FedChairmanGameNativeApp: App {
    @NSApplicationDelegateAdaptor(GameWindowDelegate.self) private var gameWindowDelegate
    @StateObject private var store: GameSessionStore

    init() {
        _store = StateObject(wrappedValue: fedChairmanSharedStore)
        PolicyShortcutDispatcher.shared.start()
    }

    var body: some Scene {
        WindowGroup("Fed Chairman Game") {
            NativeCockpitView()
                .environmentObject(store)
                .frame(minWidth: 1180, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Policy") {
                ForEach(policyShortcutBindings, id: \.key) { binding in
                    Button(binding.title) {
                        dispatchPolicyShortcut(binding.action)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(binding.key)), modifiers: [])
                }
            }
        }
    }

    private func dispatchPolicyShortcut(_ action: PolicyAction) {
        if store.session.status == .notStarted {
            store.start()
        }
        NotificationCenter.default.post(name: .policyShortcutAction, object: action.rawValue)
    }
}

// swiftlint:disable:next type_body_length
struct NativeCockpitView: View {
    @EnvironmentObject private var store: GameSessionStore
    @State private var dockState = CockpitDockState()
    @State private var autoBriefingKey: String?
    @State private var customBps = ""
    @State private var decisionPulse = false
    @State private var pendingPolicySelection: PendingPolicySelection?
    @State private var panelMessage: String?
    @State private var inspectedChartIndex: Int?
    @State private var didApplyValidationProgression = false
    @State private var cheatConsoleOpen = false
    @State private var cheatConsoleCommand = ""
    @State private var cheatConsoleMessage = "Enter cheat code."
    @State private var lastCheatConsoleToggle = Date.distantPast
    @FocusState private var cheatConsoleFieldFocused: Bool
    @AppStorage("FedChairman.fastCommit") private var fastCommit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var session: GameSession {
        store.session
    }

    private var briefing: CockpitBriefing {
        buildCockpitBriefing(session: session)
    }

    private var debrief: NativeDebrief {
        buildNativeDebrief(session: session)
    }

    private var decisionFeedback: DecisionFeedback {
        buildDecisionFeedback(session: session)
    }

    private var boardWatch: BoardWatch {
        buildBoardWatch(session: session)
    }

    private var inflationMetricTargetText: String {
        let cap = activeInflationUpperBound(ui: session.ui, currentCareerQuarter: session.totalCareerQuarters)
        return cap > 4 ? "cap \(String(format: "%.1f", cap))%" : "2.0%"
    }

    private var careerDecisions: [PolicyDecision] {
        session.completedTerms.flatMap(\.decisions) + session.decisions
    }

    private var chartInspection: ChartInspection? {
        buildChartInspection(
            history: session.careerHistory,
            decisions: careerDecisions,
            selectedIndex: inspectedChartIndex,
        )
    }

    private var briefingVisible: Bool {
        dockState.isOpen(.newspaper, briefingVisible: autoBriefingKey == briefingKey)
    }

    private var motionMode: CockpitMotionMode {
        cockpitMotionMode(reduceMotion: reduceMotion, ui: session.ui)
    }

    private var briefingKey: String {
        "\(session.termNumber)-\(session.current.quarterIndex)-\(session.latestTriggeredShocks.map(\.id).joined(separator: "."))"
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = cockpitLayoutMetrics(width: proxy.size.width, height: proxy.size.height)
            ZStack(alignment: .top) {
                CommandDeskBackground()
                VStack(spacing: layout.spacing.cg) {
                    statusRail(layout: layout)
                    dockPanels(layout: layout)
                    metricsGrid(layout: layout)
                    dashboard(layout: layout)
                    policyDecisionCenter(layout: layout)
                    if shouldShowQuarterReview(layout: layout) {
                        quarterReview(layout: layout)
                    }
                }
                .padding(layout.panelPadding.cg)
                .padding(.top, cockpitContentTopInset(layout).cg)

                debriefOverlay
                cheatConsoleOverlay
                Text(motionMode == .reduced ? "Reduced motion mode" : "Spring motion mode")
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .accessibilityLabel("motion-mode-\(motionMode == .reduced ? "reduced" : "spring")")
                    .accessibilityIdentifier("motion-mode-\(motionMode == .reduced ? "reduced" : "spring")")
                    .frame(width: 1, height: 1)
            }
        }
        .onAppear {
            dockState.closeAll()
            autoBriefingKey = nil
            if session.status == .notStarted {
                store.start()
            }
            applyValidationProgressionIfNeeded()
            configureUITestStateIfNeeded()
            autoPeekBriefing()
        }
        .onReceive(NotificationCenter.default.publisher(for: .policyShortcutAction)) { notification in
            guard let rawAction = notification.object as? String,
                  let action = PolicyAction(rawValue: rawAction)
            else {
                return
            }
            handlePolicyShortcut(action)
        }
        .onReceive(NotificationCenter.default.publisher(for: .commitPendingPolicySelection)) { _ in
            commitPendingPolicySelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearPendingPolicySelection)) { _ in
            clearPolicySelectionOrCloseOverlays()
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeCockpitOverlays)) { _ in
            clearPolicySelectionOrCloseOverlays()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleCheatConsole)) { _ in
            toggleCheatConsole()
        }
        .onChange(of: briefingKey) {
            autoPeekBriefing()
        }
        .onExitCommand {
            closeOverlays()
        }
    }

    private func statusRail(layout: CockpitLayoutMetrics) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fed Chairman")
                    .font(.system(size: layout.mode == .compact ? 16 : 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                if layout.mode != .compact {
                    Text("Policy command")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
            .frame(width: layout.mode == .compact ? 132 : 168, alignment: .leading)

            HStack(spacing: layout.mode == .compact ? 8 : 14) {
                Text("Term \(session.termNumber)")
                Text("Q\(session.current.quarterIndex)/16")
                if layout.mode != .compact {
                    Text("\(session.totalCareerQuarters) career Q")
                    QuarterPips(current: session.current.quarterIndex, total: 16)
                }
            }
            .lineLimit(1)
            .padding(.vertical, 7)
            .padding(.horizontal, 11)
            .background(.white.opacity(0.055), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12)))
            BoardWatchRailView(watch: boardWatch, layout: layout)
            Spacer(minLength: 0)
            dockButtons(layout: layout)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.82))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: (layout.mode == .compact ? 50 : max(58, layout.dockTrayHeight)).cg)
    }

    private func dashboard(layout: CockpitLayoutMetrics) -> some View {
        CommandPanel(padding: layout.panelPadding.cg, tone: .monitor) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: layout.mode == .compact ? 1 : 4) {
                    Text("Mandate Dashboard")
                        .font(.system(size: layout.mode == .compact ? 18 : 21, weight: .bold, design: .rounded))
                    if layout.mode != .compact {
                        Text("Inflation, labor, funds rate, and credibility trace")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                Spacer()
                if layout.mode != .compact {
                    Text("Latest Q\(session.current.quarterIndex)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white.opacity(0.58))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(.white.opacity(0.055), in: Capsule())
                }
            }
            .padding(.bottom, layout.mode == .compact ? 3 : 6)
            if layout.mode != .compact {
                ChartInspectionStrip(
                    inspection: chartInspection,
                    isInspecting: inspectedChartIndex != nil,
                    compact: false,
                )
                .padding(.bottom, 6)
            }
            SpriteKitChart(
                history: session.careerHistory,
                reducedMotion: reduceMotion || session.ui.reducedMotion,
                inflationUpperBound: activeInflationUpperBound(ui: session.ui, currentCareerQuarter: session.totalCareerQuarters),
                onInspectionIndexChanged: { inspectedChartIndex = $0 },
            )
            .frame(height: layout.chartHeight.cg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.16)))
            .shadow(color: .black.opacity(0.28), radius: 10, y: 6)
        }
        .accessibilityIdentifier("mandate-dashboard")
    }

    private func policyDecisionCenter(layout: CockpitLayoutMetrics) -> some View {
        PolicyDecisionCenter(
            session: session,
            pendingSelection: pendingPolicySelection,
            customBps: $customBps,
            decisionPulse: decisionPulse,
            motionMode: motionMode,
            layout: layout,
            selectAction: handlePolicyButton,
            commit: commitPendingPolicySelection,
            clear: clearPendingPolicySelection,
        )
    }

    private func metricsGrid(layout: CockpitLayoutMetrics) -> some View {
        CommandPanel(padding: max(6, layout.panelPadding - 4).cg, tone: .instrument) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: layout.metricsColumns), spacing: 8) {
                MandateMetricCard(
                    label: "Inflation",
                    value: session.current.inflation,
                    target: inflationMetricTargetText,
                    suffix: "%",
                    color: .orange,
                    layout: layout,
                )
                MandateMetricCard(label: "Unemployment", value: session.current.unemployment, target: "5.0%", suffix: "%", color: .blue, layout: layout)
                MandateMetricCard(label: "Fed Funds", value: session.current.fedFundsRate, target: "policy", suffix: "%", color: .green, layout: layout)
                MandateMetricCard(label: "Expectations", value: session.current.expectedInflation, target: "anchor", suffix: "%", color: .mint, layout: layout)
                MandateMetricCard(label: "Credibility", value: session.current.credibility, target: "80+", suffix: "", color: .yellow, layout: layout)
            }
        }
        .accessibilityIdentifier("macro-metrics")
    }

    private func quarterReview(layout: CockpitLayoutMetrics) -> some View {
        CommandPanel(padding: layout.panelPadding.cg, tone: .instrument) {
            VStack(alignment: .leading, spacing: layout.mode == .compact ? 4 : 12) {
                if let transmission = buildTransmissionBriefing(session: session) {
                    if layout.mode != .expanded {
                        CompactQuarterReview(transmission: transmission)
                    } else {
                        Text(transmission.receipt.headline)
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(trendColor(transmission.receipt.tone))
                        Text(transmission.summary)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.74))
                        HStack(spacing: 8) {
                            ForEach(Array(transmission.path.enumerated()), id: \.offset) { index, leg in
                                Text("STEP \(index + 1)  \(leg)")
                                    .font(.caption.weight(.black))
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .background(.white.opacity(0.08), in: Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(transmission.steps) { step in
                                transmissionStepCard(step)
                            }
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(transmission.changes) { change in
                                transmissionChangeCard(change)
                            }
                        }
                        Text(transmission.decisionMemo.nextBias)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                } else {
                    Text("Make the first policy decision to generate a native trace readout.")
                        .font(layout.mode == .compact ? .caption.weight(.semibold) : .body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: layout.quarterReviewHeight.cg, alignment: .top)
        .accessibilityIdentifier("quarter-review")
    }

    private func shouldShowQuarterReview(layout: CockpitLayoutMetrics) -> Bool {
        guard dockState.openPanels.isEmpty else {
            return false
        }
        guard session.current.quarterIndex > 0 || session.totalCareerQuarters > 0 else {
            return false
        }
        guard buildTransmissionBriefing(session: session) != nil else {
            return false
        }
        return layout.mode != .compact || session.current.quarterIndex >= 8
    }

    private func transmissionStepCard(_ step: TransmissionStep) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(step.month.uppercased())
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white.opacity(0.56))
                Spacer()
                Text("\(step.intensity)%")
                    .font(.caption.weight(.black))
                    .foregroundStyle(trendColor(step.trend))
            }
            Text(step.title)
                .font(.caption.weight(.black))
            Text(step.driver)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))
            ProgressView(value: Double(step.intensity), total: 100)
                .tint(trendColor(step.trend))
            Text(step.detail)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(3)
        }
        .padding(10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08)))
    }

    private func transmissionChangeCard(_ change: TransmissionChange) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(change.label.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.56))
            Text(change.delta)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(trendColor(change.tone))
            Text("\(change.previous) -> \(change.current)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08)))
    }

    private func trendColor(_ trend: TransmissionTrend) -> Color {
        switch trend {
        case .cooling:
            .cyan
        case .heating:
            .orange
        case .stabilizing:
            .green
        case .stress:
            .red
        }
    }

    private func dockPanels(layout: CockpitLayoutMetrics) -> some View {
        let isDrawerOpen = dockState.openPanels.last != nil
        let panelHeight = isDrawerOpen ? layout.dockPanelMaxHeight : briefingPreviewHeight(layout)
        let panelInset = (layout.mode == .compact ? 8 : 12).cg

        return ZStack(alignment: .topLeading) {
            if let panel = dockState.openPanels.last {
                dockPanel(panel, layout: layout, maxHeight: panelHeight)
                    .padding(.horizontal, panelInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(motionMode == .reduced ? .opacity : .move(edge: .top).combined(with: .opacity))
            } else {
                briefingPreview(layout: layout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: panelHeight.cg, alignment: .top)
        .clipped()
        .animation(motionMode == .reduced ? nil : .smooth(duration: 0.28), value: dockState.openPanels)
    }

    private func briefingPreviewHeight(_ layout: CockpitLayoutMetrics) -> Double {
        switch layout.mode {
        case .compact:
            78
        case .standard:
            104
        case .expanded:
            100
        }
    }

    private func briefingPreview(layout: CockpitLayoutMetrics) -> some View {
        CommandPanel(padding: max(6, layout.panelPadding - 2).cg, tone: .glass) {
            HStack(alignment: .center, spacing: layout.mode == .compact ? 10 : 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("LATEST BRIEFING")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.orange)
                        Text(briefing.metadata)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.50))
                    }
                    Text(briefing.headline)
                        .font(.system(size: layout.mode == .compact ? 15 : 20, weight: .black, design: .rounded))
                        .lineLimit(layout.mode == .compact ? 2 : 3)
                        .minimumScaleFactor(0.86)
                    if layout.mode != .compact {
                        Text(briefing.body)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                if layout.mode != .compact {
                    VStack(alignment: .leading, spacing: 6) {
                        previewChip("Risk", briefing.riskCalendar)
                        previewChip("Policy", briefing.policyImplication)
                    }
                    .frame(width: 330)
                }
            }
        }
    }

    private func previewChip(_ label: String, _ body: String) -> some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.46))
            Text(body)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(2)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }

    private func dockButtons(layout: CockpitLayoutMetrics) -> some View {
        let compact = true
        return HStack(spacing: compact ? 6 : 10) {
            ForEach(CockpitDockPanel.allCases) { panel in
                Button {
                    toggle(panel)
                } label: {
                    DockIcon(panel: panel, compact: compact)
                }
                .buttonStyle(DockButtonStyle(
                    isOpen: dockState.isOpen(panel, briefingVisible: briefingVisible),
                    width: layout.dockButtonWidth.cg,
                    height: layout.dockButtonHeight.cg,
                ))
                .accessibilityLabel("\(dockState.isOpen(panel, briefingVisible: briefingVisible) ? "Close" : "Open") \(panel.title.lowercased()) panel")
                .accessibilityIdentifier("dock-\(panel.rawValue)")
            }
        }
        .padding(5)
        .background(alignment: .bottomTrailing) {
            dockTray(layout: layout)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dock-button-cluster")
    }

    private func dockTray(layout: CockpitLayoutMetrics) -> some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(.ultraThinMaterial)
            .frame(width: layout.dockTrayWidth.cg, height: layout.dockTrayHeight.cg)
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.16),
                                Color.cyan.opacity(0.08),
                                Color.green.opacity(0.06),
                                .black.opacity(0.16),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing,
                        ),
                    )
            }
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.24)))
            .shadow(color: .black.opacity(0.24), radius: 14, y: 7)
            .accessibilityHidden(true)
    }

    private func dockPanelWidth(_ panel: CockpitDockPanel, layout: CockpitLayoutMetrics) -> CGFloat {
        switch panel {
        case .newspaper:
            layout.newspaperPanelWidth.cg
        case .help:
            layout.helpPanelWidth.cg
        case .settings:
            layout.settingsPanelWidth.cg
        }
    }

    private func dockPanel(_ panel: CockpitDockPanel, layout: CockpitLayoutMetrics, maxHeight: Double) -> some View {
        let panelInset = (layout.mode == .compact ? 8 : 12).cg
        return Group {
            if panel == .newspaper {
                NewspaperPanelView(briefing: briefing, layout: layout)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(panel.title)
            } else if panel == .help {
                HelpDrawerView(topics: buildHelpTopics(session: session), layout: layout)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Policy Notebook")
            } else {
                SettingsDrawerView(
                    fastCommit: $fastCommit,
                    reducedMotion: Binding(
                        get: { session.ui.reducedMotion },
                        set: { store.setReducedMotion($0) },
                    ),
                    soundEnabled: Binding(
                        get: { session.ui.soundEnabled },
                        set: { store.setSoundEnabled($0) },
                    ),
                    reducedNoise: Binding(
                        get: { session.ui.reducedNoise },
                        set: { store.setReducedNoise($0) },
                    ),
                    panelMessage: panelMessage,
                    layout: layout,
                    save: savePortableSession,
                    load: loadPortableSession,
                    exportCsv: exportCsv,
                    exportJson: exportJson,
                    exportMarkdown: exportMarkdown,
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel(panel.title)
            }
        }
        .frame(
            width: max(240.cg, dockPanelWidth(panel, layout: layout) - (panelInset * 2)),
            height: maxHeight.cg,
            alignment: .top,
        )
        .clipped()
        .accessibilityIdentifier("\(panel.rawValue)-panel")
    }

    private func toggle(_ panel: CockpitDockPanel) {
        playDockClick()
        dockState.toggle(panel)
        if panel == .newspaper, !dockState.isOpen(.newspaper) {
            autoBriefingKey = nil
        }
    }

    private func playDockClick() {
        guard shouldPlayCockpitSound(ui: session.ui) else {
            return
        }
        let sound = NSSound(named: "Pop") ?? NSSound(named: "Tink")
        sound?.volume = Float(cockpitSoundVolume(ui: session.ui) * 0.72)
        sound?.play()
    }

    private func closeOverlays() {
        dockState.closeAll()
        autoBriefingKey = nil
        cheatConsoleOpen = false
        cheatConsoleFieldFocused = false
    }

    private func clearPolicySelectionOrCloseOverlays() {
        if pendingPolicySelection != nil || !customBps.isEmpty {
            clearPendingPolicySelection()
        } else {
            closeOverlays()
        }
    }

    private func toggleCheatConsole() {
        let now = Date()
        guard now.timeIntervalSince(lastCheatConsoleToggle) > 0.15 else {
            return
        }
        lastCheatConsoleToggle = now
        let shouldOpen = !cheatConsoleOpen
        cheatConsoleOpen = shouldOpen
        if shouldOpen {
            cheatConsoleCommand = ""
            cheatConsoleMessage = "Enter cheat code."
            DispatchQueue.main.async {
                cheatConsoleFieldFocused = true
            }
        } else {
            cheatConsoleFieldFocused = false
        }
    }

    private func runCheatConsoleCommand() {
        let command = cheatConsoleCommand.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard command == "TRUMP" else {
            cheatConsoleMessage = "Unknown code."
            NSSound.beep()
            return
        }
        store.activateTrumpCheat()
        cheatConsoleMessage = "TRUMP event active."
        dockState.open(.newspaper, pinned: true)
        autoBriefingKey = briefingKey
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            cheatConsoleOpen = false
            cheatConsoleFieldFocused = false
        }
    }

    private func autoPeekBriefing() {
        guard session.current.quarterIndex > 0 else {
            autoBriefingKey = nil
            return
        }
        guard dockState.isOpen(.newspaper) else {
            autoBriefingKey = nil
            return
        }
        autoBriefingKey = briefingKey
    }

    private func commit(_ action: PolicyAction) {
        guard session.status == .inProgress else {
            return
        }
        do {
            try store.commit(action: action)
            clearPendingPolicySelection()
            pulse()
            playPolicyClick()
        } catch {
            NSSound.beep()
        }
    }

    private func handlePolicyButton(_ action: PolicyAction) {
        guard session.status == .inProgress else {
            return
        }
        if fastCommit {
            if action == .custom {
                commitCustom()
            } else {
                commit(action)
            }
        } else {
            selectPendingPolicyAction(action)
        }
    }

    private func handlePolicyShortcut(_ action: PolicyAction) {
        guard session.status == .inProgress else {
            return
        }
        if fastCommit {
            commit(action)
        } else {
            selectPendingPolicyAction(action)
        }
    }

    private func selectPendingPolicyAction(_ action: PolicyAction) {
        let delta = action == .custom ? customDelta : policyActions[action]?.delta
        guard let delta else {
            NSSound.beep()
            return
        }
        let resultingRate = session.current.fedFundsRate + delta
        guard resultingRate >= 0, resultingRate <= 20 else {
            NSSound.beep()
            return
        }
        let customBasisPoints = action == .custom ? Int((delta * 100).rounded()) : nil
        pendingPolicySelection = PendingPolicySelection(action: action, customBasisPoints: customBasisPoints)
    }

    private func clearPendingPolicySelection() {
        pendingPolicySelection = nil
        customBps = ""
    }

    private func commitPendingPolicySelection() {
        guard session.status == .inProgress else {
            return
        }
        guard let pendingPolicySelection else {
            NSSound.beep()
            return
        }
        if pendingPolicySelection.action == .custom {
            commitCustom(rateChange: pendingPolicySelection.rateChange)
        } else {
            commit(pendingPolicySelection.action)
        }
    }

    private func commitCustom() {
        guard let customDelta else {
            return
        }
        commitCustom(rateChange: customDelta)
    }

    private func commitCustom(rateChange: Double) {
        guard session.status == .inProgress else {
            return
        }
        do {
            try store.commitCustom(rateChange: rateChange)
            clearPendingPolicySelection()
            pulse()
            playPolicyClick()
        } catch {
            NSSound.beep()
        }
    }

    private func playPolicyClick() {
        guard shouldPlayCockpitSound(ui: session.ui) else {
            return
        }
        let sound = NSSound(named: "Tink") ?? NSSound(named: "Pop")
        sound?.volume = Float(cockpitSoundVolume(ui: session.ui))
        sound?.play()
    }

    private func savePortableSession() {
        do {
            let text = try createSaveFile(session: session)
            try saveText(text, suggestedName: "fed-chairman-career.fedchair-save.json")
            panelMessage = "Portable save written."
        } catch {
            panelMessage = "Save failed: \(error.localizedDescription)"
            NSSound.beep()
        }
    }

    private func loadPortableSession() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a Fed Chairman portable save file."
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let loaded = try parseSaveFile(text)
            try store.load(session: loaded)
            panelMessage = "Loaded \(summarizeSaveSession(loaded).label)."
        } catch {
            panelMessage = "Load failed: \(error.localizedDescription)"
            NSSound.beep()
        }
    }

    private func exportCsv() {
        do {
            try saveText(sessionToCsv(session), suggestedName: "fed-chairman-career.csv")
            panelMessage = "CSV export written."
        } catch {
            panelMessage = "CSV export failed: \(error.localizedDescription)"
            NSSound.beep()
        }
    }

    private func exportJson() {
        do {
            try saveText(sessionToJson(session), suggestedName: "fed-chairman-career.json")
            panelMessage = "JSON export written."
        } catch {
            panelMessage = "JSON export failed: \(error.localizedDescription)"
            NSSound.beep()
        }
    }

    private func exportMarkdown() {
        do {
            try saveText(sessionToMarkdown(session), suggestedName: "fed-chairman-career.md")
            panelMessage = "Markdown export written."
        } catch {
            panelMessage = "Markdown export failed: \(error.localizedDescription)"
            NSSound.beep()
        }
    }

    private func saveText(_ text: String, suggestedName: String) throws {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func pulse() {
        guard !reduceMotion else {
            return
        }
        decisionPulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            decisionPulse = false
        }
    }

    private func configureUITestStateIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        if environment["FED_CHAIRMAN_TEST_REDUCE_MOTION"] == "1" {
            store.setReducedMotion(true)
        }
        if let rawPanel = environment["FED_CHAIRMAN_TEST_OPEN_PANEL"],
           let panel = CockpitDockPanel(rawValue: rawPanel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        {
            dockState.open(panel, pinned: panel == .newspaper)
        }
        guard let rawSize = environment["FED_CHAIRMAN_TEST_WINDOW_SIZE"] else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            applyWindowSize(rawSize)
        }
    }

    private func applyValidationProgressionIfNeeded() {
        guard !didApplyValidationProgression,
              let rawQuarterCount = ProcessInfo.processInfo.environment["FED_CHAIRMAN_TEST_QUARTERS"],
              let requestedQuarterCount = Int(rawQuarterCount)
        else {
            return
        }
        didApplyValidationProgression = true
        let quarterCount = max(0, min(15, requestedQuarterCount))
        let sequence: [PolicyAction] = [
            .hold, .raise25, .hold, .cut25, .raise50,
            .hold, .cut50, .raise25, .hold, .raise75,
            .cut25, .hold, .raise50, .cut25, .hold,
        ]
        for index in 0 ..< quarterCount {
            do {
                try store.commit(action: sequence[index % sequence.count])
            } catch {
                break
            }
        }
    }

    private func applyWindowSize(_ rawSize: String) {
        let parts = rawSize.lowercased().split(separator: "x")
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width.isFinite,
              height.isFinite,
              width >= 320,
              height >= 260,
              let window = NSApp.windows.first(where: { $0.canBecomeKey })
        else {
            return
        }
        var frame = window.frame
        frame.size = CGSize(width: width, height: height)
        if let visibleFrame = NSScreen.main?.visibleFrame {
            frame.origin.x = min(80, visibleFrame.maxX - width - 12)
            frame.origin.y = min(max(40, visibleFrame.maxY - height - 40), visibleFrame.maxY - 40)
        } else {
            frame.origin.x = 80
        }
        window.setFrame(frame, display: true, animate: false)
    }

    private var customDelta: Double? {
        guard let bps = Int(customBps.trimmingCharacters(in: .whitespacesAndNewlines)), abs(bps) <= 150 else {
            return nil
        }
        let delta = Double(bps) / 100
        let resulting = session.current.fedFundsRate + delta
        return resulting >= 0 && resulting <= 20 ? delta : nil
    }
}

private extension NativeCockpitView {
    var cheatConsoleOverlay: some View {
        CheatConsoleOverlay(
            isOpen: cheatConsoleOpen,
            command: $cheatConsoleCommand,
            message: cheatConsoleMessage,
            motionMode: motionMode,
            isCommandFieldFocused: $cheatConsoleFieldFocused,
            close: toggleCheatConsole,
            run: runCheatConsoleCommand,
        )
    }

    var debriefOverlay: some View {
        Group {
            if session.status == .termDebrief || session.status == .notReappointed || session.status == .retired {
                ZStack {
                    Color.black.opacity(0.38)
                        .ignoresSafeArea()
                    CommandPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(debriefTitle)
                                .font(.system(size: 28, weight: .black, design: .rounded))
                            Text(debrief.boardVerdict)
                                .font(.body.weight(.semibold))
                            Text(debrief.gateStatus)
                                .foregroundStyle(.white.opacity(0.78))
                            HStack(spacing: 10) {
                                scoreBadge("Score", value: String(format: "%.0f", session.score.score))
                                scoreBadge("Grade", value: session.score.grade.rawValue)
                                scoreBadge("Career Q", value: "\(session.totalCareerQuarters)")
                            }
                            VStack(alignment: .leading, spacing: 7) {
                                debriefLine("Term", debrief.termStanding)
                                debriefLine("Style", debrief.policyStyle)
                                debriefLine("Best stretch", debrief.bestStretch)
                                debriefLine("Decision mix", debrief.decisionMix)
                                debriefLine("Handoff", debrief.termHandoff)
                                debriefLine("Next", debrief.nextTermBrief)
                                debriefLine("Focus", debrief.coachingFocus)
                            }
                            HStack(spacing: 8) {
                                ForEach(debrief.termHandoffMetrics.prefix(4)) { metric in
                                    handoffMetric(metric)
                                }
                            }
                            Text(debrief.gateChoice)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.64))
                            HStack {
                                if session.status == .termDebrief {
                                    Button("Continue next term") {
                                        do {
                                            try store.continueNextTerm()
                                            autoPeekBriefing()
                                        } catch {
                                            NSSound.beep()
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    if session.completedTerms.count >= 2 {
                                        Button("Retire career") {
                                            store.retireCareer()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                } else {
                                    Button("Start new career") {
                                        store.start(seed: "classic-2026")
                                        autoPeekBriefing()
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                        .frame(width: 720, alignment: .leading)
                    }
                }
                .transition(motionMode == .reduced ? .opacity : .scale(scale: 0.88).combined(with: .opacity))
            }
        }
        .animation(motionMode == .reduced ? nil : .bouncy(duration: 0.42, extraBounce: 0.18), value: session.status)
    }

    func scoreBadge(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(.green)
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
        }
        .frame(width: 120, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    func debriefLine(_ label: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(.green.opacity(0.9))
            Text(body)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    func handoffMetric(_ metric: TermHandoffMetric) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.label.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(handoffToneColor(metric.tone))
            Text(metric.end)
                .font(.system(size: 15, weight: .black, design: .rounded))
            Text(metric.delta)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }

    func handoffToneColor(_ tone: TermHandoffMetric.Tone) -> Color {
        switch tone {
        case .better:
            .green
        case .worse:
            .orange
        case .steady:
            .white.opacity(0.7)
        }
    }

    var debriefTitle: String {
        switch session.status {
        case .termDebrief:
            "Reappointment Granted"
        case .notReappointed:
            "Term Ended"
        case .retired:
            "Career Retired"
        case .inProgress, .notStarted:
            ""
        }
    }
}

private extension Notification.Name {
    static let policyShortcutAction = Notification.Name("FedChairmanPolicyShortcutAction")
    static let commitPendingPolicySelection = Notification.Name("FedChairmanCommitPendingPolicySelection")
    static let clearPendingPolicySelection = Notification.Name("FedChairmanClearPendingPolicySelection")
    static let closeCockpitOverlays = Notification.Name("FedChairmanCloseCockpitOverlays")
    static let toggleCheatConsole = Notification.Name("FedChairmanToggleCheatConsole")
}

private struct PolicyShortcutBinding {
    var key: String
    var action: PolicyAction

    var title: String {
        "\(key)  \(policyActions[action]?.label ?? action.rawValue)"
    }
}

private let policyShortcutBindings: [PolicyShortcutBinding] = [
    PolicyShortcutBinding(key: "1", action: .cut150),
    PolicyShortcutBinding(key: "2", action: .cut100),
    PolicyShortcutBinding(key: "3", action: .cut75),
    PolicyShortcutBinding(key: "4", action: .cut50),
    PolicyShortcutBinding(key: "5", action: .cut25),
    PolicyShortcutBinding(key: "6", action: .hold),
    PolicyShortcutBinding(key: "7", action: .raise25),
    PolicyShortcutBinding(key: "8", action: .raise50),
    PolicyShortcutBinding(key: "9", action: .raise75),
    PolicyShortcutBinding(key: "0", action: .raise100),
]

private struct CheatConsoleOverlay: View {
    var isOpen: Bool
    @Binding var command: String
    var message: String
    var motionMode: CockpitMotionMode
    @FocusState.Binding var isCommandFieldFocused: Bool
    var close: () -> Void
    var run: () -> Void

    var body: some View {
        Group {
            if isOpen {
                ZStack {
                    Color.black.opacity(0.32)
                        .ignoresSafeArea()
                    CommandPanel {
                        consoleBody
                            .frame(width: 420, alignment: .leading)
                    }
                }
                .accessibilityIdentifier("cheat-console")
                .transition(motionMode == .reduced ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(motionMode == .reduced ? nil : .bouncy(duration: 0.24, extraBounce: 0.12), value: isOpen)
    }

    private var consoleBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Console")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                Spacer()
                Button("Close", action: close)
                    .buttonStyle(.borderless)
            }
            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.68))
            HStack(spacing: 8) {
                Text("`")
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .foregroundStyle(.green)
                TextField("code", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .focused($isCommandFieldFocused)
                    .accessibilityIdentifier("cheat-console-command-field")
                    .onSubmit(run)
                Button("Run", action: run)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

@MainActor
private final class PolicyShortcutDispatcher {
    static let shared = PolicyShortcutDispatcher()

    private var monitor: Any?

    private init() {}

    func start() {
        guard monitor == nil else {
            return
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard NSApp.isActive else {
                return event
            }
            if event.keyCode == 53 {
                NotificationCenter.default.post(name: .closeCockpitOverlays, object: nil)
                return nil
            }
            if event.keyCode == 50 || event.charactersIgnoringModifiers == "`" {
                NotificationCenter.default.post(name: .toggleCheatConsole, object: nil)
                return nil
            }
            guard !Self.isTextInputFocused else {
                return event
            }
            if event.keyCode == 36 || event.keyCode == 76 {
                NotificationCenter.default.post(name: .commitPendingPolicySelection, object: nil)
                return nil
            }
            guard let action = Self.action(for: event) else {
                return event
            }
            NotificationCenter.default.post(name: .policyShortcutAction, object: action.rawValue)
            return nil
        }
    }

    private static var isTextInputFocused: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else {
            return false
        }
        return responder is NSTextView || responder is NSTextField
    }

    private static func action(for event: NSEvent) -> PolicyAction? {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased() else {
            return nil
        }
        return policyShortcutBindings.first { $0.key == key }?.action
    }
}

private struct QuarterPips: View {
    var current: Int
    var total: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0 ..< total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < current ? Color.green : Color.white.opacity(0.18))
                    .frame(width: 7, height: 20)
            }
        }
        .padding(6)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }
}
