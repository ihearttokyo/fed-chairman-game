import AppKit
import FedChairmanCore
import SpriteKit
import SwiftUI

@main
struct FedChairmanGameNativeApp: App {
    @NSApplicationDelegateAdaptor(GameWindowDelegate.self) private var gameWindowDelegate
    @StateObject private var store = GameSessionStore()

    init() {
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
                Button("Raise 25 bps") {
                    commitShortcut(.raise25)
                }
                .keyboardShortcut("r", modifiers: [])
                Button("Hold") {
                    commitShortcut(.hold)
                }
                .keyboardShortcut("h", modifiers: [])
                Button("Cut 25 bps") {
                    commitShortcut(.cut25)
                }
                .keyboardShortcut("c", modifiers: [])
            }
        }
    }

    private func commitShortcut(_ action: PolicyAction) {
        if store.session.status == .notStarted {
            store.start()
        }
        do {
            try store.commit(action: action)
        } catch {
            NSSound.beep()
        }
    }
}

struct NativeCockpitView: View {
    @EnvironmentObject private var store: GameSessionStore
    @State private var dockState = CockpitDockState()
    @State private var autoBriefingKey: String?
    @State private var customBps = ""
    @State private var decisionPulse = false
    @State private var panelMessage: String?
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
        ZStack(alignment: .top) {
            commandDeskBackground
            VStack(spacing: 12) {
                statusRail
                dashboard
                policyLever
                metricsGrid
                quarterReview
            }
            .padding(18)

            debriefOverlay
            cockpitDock
        }
        .onAppear {
            dockState.closeAll()
            autoBriefingKey = nil
            if session.status == .notStarted {
                store.start()
            }
            autoPeekBriefing()
        }
        .onReceive(NotificationCenter.default.publisher(for: .policyShortcutAction)) { notification in
            guard let rawAction = notification.object as? String,
                  let action = PolicyAction(rawValue: rawAction)
            else {
                return
            }
            commit(action)
        }
        .onChange(of: briefingKey) {
            autoPeekBriefing()
        }
        .onExitCommand {
            closeOverlays()
        }
    }

    private var commandDeskBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.025, blue: 0.012),
                Color(red: 0.13, green: 0.065, blue: 0.03),
                Color(red: 0.018, green: 0.035, blue: 0.03),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing,
        )
        .ignoresSafeArea()
        .overlay {
            RadialGradient(colors: [Color.orange.opacity(0.24), .clear], center: .topLeading, startRadius: 30, endRadius: 520)
                .ignoresSafeArea()
        }
        .overlay {
            RadialGradient(colors: [Color.green.opacity(0.18), .clear], center: .bottomTrailing, startRadius: 80, endRadius: 760)
                .ignoresSafeArea()
        }
    }

    private var statusRail: some View {
        HStack(spacing: 14) {
            Text("Classic Normal Cycle")
            Text("Term \(session.termNumber)")
            Text("Quarter \(session.current.quarterIndex) of 16")
            Text("\(session.totalCareerQuarters) career quarters")
            QuarterPips(current: session.current.quarterIndex, total: 16)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.76))
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var dashboard: some View {
        CommandPanel {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mandate Dashboard")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Animated native SpriteKit trace")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                mandateBadge("Inflation", value: session.current.inflation, target: 2, color: .orange)
                mandateBadge("Labor", value: session.current.unemployment, target: 5, color: .blue)
                mandateBadge("Credibility", value: session.current.credibility, target: 80, color: .green)
            }
            .padding(.bottom, 8)
            SpriteKitChart(history: session.careerHistory, reducedMotion: reduceMotion || session.ui.reducedMotion)
                .frame(height: 270)
        }
        .accessibilityIdentifier("mandate-dashboard")
    }

    private func mandateBadge(_ label: String, value: Double, target: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(color)
            Text(value, format: .number.precision(.fractionLength(label == "Credibility" ? 0 : 2)))
                .font(.system(size: 18, weight: .black, design: .rounded))
            Text("Target \(target, format: .number.precision(.fractionLength(label == "Credibility" ? 0 : 1)))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.52))
        }
        .frame(width: 104, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.08)))
    }

    private var policyLever: some View {
        CommandPanel {
            VStack(spacing: 12) {
                HStack {
                    Text("Policy Lever")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                    Spacer()
                    Text("Fed funds \(session.current.fedFundsRate, format: .number.precision(.fractionLength(2)))%")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                }
                HStack(spacing: 8) {
                    ForEach(fixedActions, id: \.self) { action in
                        Button(policyActions[action]?.label ?? action.rawValue) {
                            commit(action)
                        }
                        .buttonStyle(PolicyButtonStyle(pulse: decisionPulse))
                        .disabled(resultingRate(for: action) < 0 || resultingRate(for: action) > 20)
                    }
                    TextField("Custom bps", text: $customBps)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 92)
                    Button("Commit") {
                        commitCustom()
                    }
                    .buttonStyle(PolicyButtonStyle(pulse: decisionPulse))
                    .disabled(customDelta == nil)
                }
                DecisionTapeView(feedback: decisionFeedback, pulse: decisionPulse, motionMode: motionMode)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("policy-lever")
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
            metric("Inflation", value: session.current.inflation, suffix: "%", color: .orange)
            metric("Unemployment", value: session.current.unemployment, suffix: "%", color: .blue)
            metric("Fed Funds", value: session.current.fedFundsRate, suffix: "%", color: .green)
            metric("Expectations", value: session.current.expectedInflation, suffix: "%", color: .mint)
            metric("Credibility", value: session.current.credibility, suffix: "", color: .yellow)
        }
        .accessibilityIdentifier("macro-metrics")
    }

    private func metric(_ label: String, value: Double, suffix: String, color: Color) -> some View {
        CommandPanel {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.68))
                Text("\(value, format: .number.precision(.fractionLength(suffix.isEmpty ? 0 : 2)))\(suffix)")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var quarterReview: some View {
        CommandPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quarter Review")
                    .font(.headline.weight(.black))
                if let transmission = buildTransmissionBriefing(session: session) {
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
                } else {
                    Text("Make the first policy decision to generate a native trace readout.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 165, alignment: .top)
        .clipped()
        .accessibilityIdentifier("quarter-review")
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
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
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
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
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

    private var cockpitDock: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: 10) {
                Spacer()
                ForEach(dockState.cascadePlacements()) { placement in
                    dockPanel(placement.panel)
                        .frame(width: dockPanelWidth(placement.panel))
                        .offset(x: placement.xOffset, y: placement.yOffset)
                        .transition(motionMode == .reduced ? .opacity : .scale(scale: 0.62, anchor: .bottomTrailing).combined(with: .opacity))
                }
                ForEach(CockpitDockPanel.allCases) { panel in
                    Button {
                        toggle(panel)
                    } label: {
                        DockIcon(panel: panel)
                    }
                    .buttonStyle(DockButtonStyle(isOpen: dockState.isOpen(panel, briefingVisible: briefingVisible)))
                    .accessibilityLabel("\(dockState.isOpen(panel, briefingVisible: briefingVisible) ? "Close" : "Open") \(panel.title.lowercased()) panel")
                    .accessibilityIdentifier("dock-\(panel.rawValue)")
                }
            }
            .padding(.horizontal, CockpitDockLayout.outerPadding)
            .padding(.top, 14)
            .padding(.bottom, CockpitDockLayout.bottomLift)
            .background(alignment: .bottomTrailing) {
                dockTray
                    .padding(.trailing, CockpitDockLayout.outerPadding - 4)
                    .padding(.bottom, 16)
            }
            .offset(y: -44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(motionMode == .reduced ? nil : .bouncy(duration: 0.36, extraBounce: 0.28), value: dockState.openPanels)
    }

    private var dockTray: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(.ultraThinMaterial)
            .frame(width: 314, height: 126)
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.18),
                                Color.green.opacity(0.1),
                                Color(red: 0.11, green: 0.06, blue: 0.03).opacity(0.5),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing,
                        ),
                    )
            }
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.22)))
            .shadow(color: Color.green.opacity(0.14), radius: 22, y: 8)
            .shadow(color: .black.opacity(0.42), radius: 26, y: 12)
            .accessibilityHidden(true)
    }

    private func dockPanelWidth(_ panel: CockpitDockPanel) -> CGFloat {
        switch panel {
        case .newspaper:
            820
        case .help:
            800
        case .settings:
            340
        }
    }

    private var debriefOverlay: some View {
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

    private func dockPanel(_ panel: CockpitDockPanel) -> some View {
        CommandPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text(panel == .help ? "Policy Notebook" : panel.title)
                    .font(.headline.weight(.black))
                if panel == .newspaper {
                    newspaperPanelContent
                } else if panel == .help {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                        alignment: .leading,
                        spacing: 8,
                    ) {
                        ForEach(buildHelpTopics(session: session)) { topic in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topic.title)
                                    .font(topic.isPrimary ? .caption.weight(.black) : .caption2.weight(.black))
                                    .foregroundStyle(topic.isPrimary ? .green : .white.opacity(0.7))
                                Text(topic.body)
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                } else {
                    Toggle("Reduced motion", isOn: Binding(
                        get: { session.ui.reducedMotion },
                        set: { store.setReducedMotion($0) },
                    ))
                    Toggle("Sound", isOn: Binding(
                        get: { session.ui.soundEnabled },
                        set: { store.setSoundEnabled($0) },
                    ))
                    Toggle("Reduced noise", isOn: Binding(
                        get: { session.ui.reducedNoise },
                        set: { store.setReducedNoise($0) },
                    ))
                    HStack {
                        Button("Save") { savePortableSession() }
                        Button("Load") { loadPortableSession() }
                        Button("CSV") { exportCsv() }
                        Button("JSON") { exportJson() }
                        Button("Markdown") { exportMarkdown() }
                    }
                    .buttonStyle(.borderedProminent)
                    if let panelMessage {
                        Text(panelMessage)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.66))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(panel == .help ? "Policy Notebook" : panel.title)
        .accessibilityIdentifier("\(panel.rawValue)-panel")
    }

    private var newspaperPanelContent: some View {
        ZStack(alignment: .topLeading) {
            if let image = NativeImageLoader.image(named: "newspaper-panel") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .saturation(0.82)
                    .brightness(-0.05)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("THE MANDATE DESK")
                        .font(.system(size: 13, weight: .black, design: .serif))
                        .foregroundStyle(Color(red: 0.19, green: 0.13, blue: 0.07))
                    Spacer()
                    Text(briefing.metadata)
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color(red: 0.22, green: 0.16, blue: 0.09))
                }
                Rectangle()
                    .fill(Color(red: 0.22, green: 0.15, blue: 0.08))
                    .frame(height: 1)
                VStack(alignment: .leading, spacing: 8) {
                    Text(briefing.headline)
                        .font(.system(size: 24, weight: .black, design: .serif))
                        .foregroundStyle(Color(red: 0.08, green: 0.05, blue: 0.03))
                        .lineLimit(2)
                    Text(briefing.body)
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(Color(red: 0.13, green: 0.085, blue: 0.05))
                        .lineLimit(3)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.95, green: 0.84, blue: 0.64), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.24, green: 0.16, blue: 0.08).opacity(0.38)))
                HStack(spacing: 10) {
                    newspaperChip(briefing.severity.rawValue.uppercased())
                    newspaperChip(briefing.riskCalendar)
                    newspaperChip("Policy implication: \(briefing.policyImplication)")
                }
            }
            .padding(.horizontal, 54)
            .padding(.vertical, 38)
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func newspaperChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.black))
            .lineLimit(2)
            .foregroundStyle(Color(red: 0.1, green: 0.07, blue: 0.04))
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color(red: 0.96, green: 0.84, blue: 0.58).opacity(0.72), in: Capsule())
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
    }

    private func autoPeekBriefing() {
        guard session.current.quarterIndex > 0 else {
            autoBriefingKey = nil
            return
        }
        autoBriefingKey = briefingKey
        dockState.open(.newspaper)
        guard !dockState.pinnedBriefing else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if autoBriefingKey == briefingKey, !dockState.pinnedBriefing {
                autoBriefingKey = nil
                dockState.close(.newspaper)
            }
        }
    }

    private func commit(_ action: PolicyAction) {
        do {
            try store.commit(action: action)
            pulse()
            playPolicyClick()
        } catch {
            NSSound.beep()
        }
    }

    private func commitCustom() {
        guard let customDelta else {
            return
        }
        do {
            try store.commitCustom(rateChange: customDelta)
            customBps = ""
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

    private func scoreBadge(_ label: String, value: String) -> some View {
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

    private func debriefLine(_ label: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(.green.opacity(0.9))
            Text(body)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private func handoffMetric(_ metric: TermHandoffMetric) -> some View {
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

    private func handoffToneColor(_ tone: TermHandoffMetric.Tone) -> Color {
        switch tone {
        case .better:
            .green
        case .worse:
            .orange
        case .steady:
            .white.opacity(0.7)
        }
    }

    private var debriefTitle: String {
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

    private func pulse() {
        guard !reduceMotion else {
            return
        }
        decisionPulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            decisionPulse = false
        }
    }

    private var fixedActions: [PolicyAction] {
        [.cut150, .cut100, .cut75, .cut50, .cut25, .hold, .raise25, .raise50, .raise75, .raise100, .raise150]
    }

    private func resultingRate(for action: PolicyAction) -> Double {
        session.current.fedFundsRate + (policyActions[action]?.delta ?? 0)
    }

    private var customDelta: Double? {
        guard let bps = Int(customBps.trimmingCharacters(in: .whitespacesAndNewlines)), abs(bps) <= 300 else {
            return nil
        }
        let delta = Double(bps) / 100
        let resulting = session.current.fedFundsRate + delta
        return resulting >= 0 && resulting <= 20 ? delta : nil
    }
}

private struct CommandPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.18, green: 0.085, blue: 0.035).opacity(0.92),
                                Color(red: 0.025, green: 0.035, blue: 0.032).opacity(0.98),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing,
                        ),
                    )
                    .overlay(
                        LinearGradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.18)], startPoint: .top, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 12)),
                    ),
            )
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.22)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.65, green: 0.34, blue: 0.12).opacity(0.25)).padding(1))
            .shadow(color: .black.opacity(0.36), radius: 22, y: 12)
    }
}

private extension Notification.Name {
    static let policyShortcutAction = Notification.Name("FedChairmanPolicyShortcutAction")
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
            guard let action = Self.action(for: event) else {
                return event
            }
            NotificationCenter.default.post(name: .policyShortcutAction, object: action.rawValue)
            return nil
        }
    }

    private static func action(for event: NSEvent) -> PolicyAction? {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased() else {
            return nil
        }
        switch key {
        case "r": return .raise25
        case "h": return .hold
        case "c": return .cut25
        default: return nil
        }
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

private struct SpriteKitChart: NSViewRepresentable {
    var history: [MacroState]
    var reducedMotion: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ChartTrackingView {
        let view = ChartTrackingView()
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.onMouseMoved = { point in
            context.coordinator.hoverX = point.x
            context.coordinator.render(into: view, history: history, reducedMotion: reducedMotion)
        }
        view.onMouseExited = {
            context.coordinator.hoverX = nil
            context.coordinator.render(into: view, history: history, reducedMotion: reducedMotion)
        }
        view.presentScene(CockpitScene(size: CGSize(width: 900, height: 320)))
        return view
    }

    func updateNSView(_ view: ChartTrackingView, context: Context) {
        context.coordinator.render(into: view, history: history, reducedMotion: reducedMotion)
    }

    @MainActor
    final class Coordinator {
        var hoverX: CGFloat?

        func render(into view: SKView, history: [MacroState], reducedMotion: Bool) {
            view.window?.acceptsMouseMovedEvents = true
            let scene = (view.scene as? CockpitScene) ?? CockpitScene(size: view.bounds.size)
            scene.size = view.bounds.size == .zero ? CGSize(width: 900, height: 320) : view.bounds.size
            scene.render(history: history, reducedMotion: reducedMotion, hoverX: hoverX)
            if view.scene !== scene {
                view.presentScene(scene)
            }
        }
    }
}

private final class ChartTrackingView: SKView {
    var onMouseMoved: ((CGPoint) -> Void)?
    var onMouseExited: (() -> Void)?
    private var chartTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let chartTrackingArea {
            removeTrackingArea(chartTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil,
        )
        addTrackingArea(area)
        chartTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMouseMoved?(point)
    }

    override func mouseExited(with _: NSEvent) {
        onMouseExited?()
    }
}

private struct PolicyButtonStyle: ButtonStyle {
    var pulse: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .black, design: .rounded))
            .frame(minWidth: 72, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: configuration.isPressed
                                ? [Color(red: 0.10, green: 0.26, blue: 0.18), Color(red: 0.035, green: 0.055, blue: 0.05)]
                                : [Color(red: 0.18, green: 0.18, blue: 0.17), Color(red: 0.045, green: 0.045, blue: 0.044)],
                            startPoint: .top,
                            endPoint: .bottom,
                        ),
                    ),
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(configuration.isPressed ? 0.26 : 0.14)))
            .shadow(color: .black.opacity(configuration.isPressed ? 0.18 : 0.38), radius: configuration.isPressed ? 2 : 7, y: configuration.isPressed ? 1 : 5)
            .scaleEffect(configuration.isPressed ? 0.92 : (pulse ? 1.025 : 1))
            .animation(.bouncy(duration: 0.22, extraBounce: 0.24), value: configuration.isPressed)
            .animation(.bouncy(duration: 0.28, extraBounce: 0.18), value: pulse)
    }
}

private struct DockButtonStyle: ButtonStyle {
    var isOpen: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(width: CockpitDockLayout.buttonWidth, height: CockpitDockLayout.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [
                                .white.opacity(isOpen ? 0.3 : 0.16),
                                Color.green.opacity(isOpen ? 0.2 : 0.05),
                                .black.opacity(0.16),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing,
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 22)),
                    ),
            )
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(isOpen ? 0.42 : 0.2)))
            .shadow(color: Color.green.opacity(isOpen ? 0.24 : 0.07), radius: isOpen ? 20 : 10, y: 7)
            .shadow(color: .black.opacity(0.32), radius: 15, y: 8)
            .scaleEffect(configuration.isPressed ? 0.84 : 1)
            .animation(.bouncy(duration: 0.28, extraBounce: 0.34), value: configuration.isPressed)
    }
}

private enum CockpitDockLayout {
    static let buttonWidth: CGFloat = 92
    static let buttonHeight: CGFloat = 112
    static let outerPadding: CGFloat = 24
    static let bottomLift: CGFloat = 112
}

private struct DockIcon: View {
    var panel: CockpitDockPanel

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.thinMaterial)
                    .overlay {
                        LinearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.08), .black.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing,
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.3)))
                    .shadow(color: .black.opacity(0.34), radius: 7, y: 4)

                if let image = NativeImageLoader.image(named: panel.iconName) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                        .accessibilityHidden(true)
                } else {
                    Text(String(panel.rawValue.prefix(1)))
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 58, height: 58)

            Text(panel.title)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: 82, height: 14)
                .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
    }
}

private enum NativeImageLoader {
    static func image(named name: String) -> NSImage? {
        if let image = NSImage(named: name) {
            return image
        }
        let candidateURLs = [
            Bundle.main.url(forResource: name, withExtension: "png"),
            Bundle.main.resourceURL?
                .appendingPathComponent("FedChairmanGame_FedChairmanNativeApp.bundle")
                .appendingPathComponent("\(name).png"),
            Bundle.main.bundleURL
                .appendingPathComponent("FedChairmanGame_FedChairmanNativeApp.bundle")
                .appendingPathComponent("\(name).png"),
        ].compactMap(\.self)
        #if SWIFT_PACKAGE
            if let packageURL = Bundle.module.url(forResource: name, withExtension: "png"),
               let image = NSImage(contentsOf: packageURL)
            {
                return image
            }
        #endif
        return candidateURLs.lazy.compactMap(NSImage.init(contentsOf:)).first
    }
}
