import FedChairmanCore
import SwiftUI

struct PendingPolicySelection: Equatable {
    var action: PolicyAction
    var customBasisPoints: Int?

    var rateChange: Double {
        if action == .custom {
            return Double(customBasisPoints ?? 0) / 100
        }
        return policyActions[action]?.delta ?? 0
    }

    var label: String {
        if action == .custom {
            return "Custom \(formatRateChangeBps(rateChange))"
        }
        return policyActions[action]?.label ?? action.rawValue
    }

    var previewInput: PolicyPreviewInput {
        if action == .custom {
            return .customBasisPoints(customBasisPoints ?? 0)
        }
        return .action(action)
    }
}

struct PolicyDecisionCenter: View {
    var session: GameSession
    var pendingSelection: PendingPolicySelection?
    @Binding var customBps: String
    var decisionPulse: Bool
    var motionMode: CockpitMotionMode
    var layout: CockpitLayoutMetrics
    var selectAction: (PolicyAction) -> Void
    var commit: () -> Void
    var clear: () -> Void

    private var cutActions: [PolicyAction] {
        [.cut150, .cut100, .cut75, .cut50, .cut25]
    }

    private var raiseActions: [PolicyAction] {
        [.raise25, .raise50, .raise75, .raise100, .raise150]
    }

    private var preview: PolicyPreview? {
        guard let pendingSelection else {
            return nil
        }
        return buildPolicyPreview(session: session, input: pendingSelection.previewInput)
    }

    private var canCommit: Bool {
        pendingSelection != nil
    }

    var body: some View {
        CommandPanel(padding: layout.panelPadding.cg, tone: .keyboard) {
            VStack(spacing: max(5, layout.spacing - 1).cg) {
                header
                decisionControls
                DecisionTapeView(feedback: buildDecisionFeedback(session: session), pulse: decisionPulse, motionMode: motionMode)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("policy-decision-center")
    }

    private var decisionControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: layout.policyKeySpacing.cg) {
                actionControls
                customControl
                previewPanel
            }
            VStack(alignment: .leading, spacing: max(7, layout.policyKeySpacing).cg) {
                actionControls
                HStack(alignment: .top, spacing: layout.policyKeySpacing.cg) {
                    customControl
                    previewPanel
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionControls: some View {
        HStack(alignment: .top, spacing: layout.policyKeySpacing.cg) {
            actionCluster(title: "CUT", actions: cutActions, tint: .cyan)
            actionCluster(title: "HOLD", actions: [.hold], tint: .green)
            actionCluster(title: "RAISE", actions: raiseActions, tint: .orange)
        }
    }

    private var header: some View {
        HStack {
            Text("Policy Decision Center")
                .font(.system(size: layout.mode == .compact ? 17 : 20, weight: .black, design: .rounded))
            Spacer()
            Text("Fed funds \(session.current.fedFundsRate, format: .number.precision(.fractionLength(2)))%")
                .font(.system(size: layout.mode == .compact ? 14 : 16, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
                .padding(.vertical, layout.mode == .compact ? 4 : 5)
                .padding(.horizontal, layout.mode == .compact ? 8 : 10)
                .background(.green.opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(.green.opacity(0.22)))
        }
    }

    private func actionCluster(title: String, actions: [PolicyAction], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.black))
                .foregroundStyle(tint.opacity(0.78))
            HStack(spacing: layout.policyKeySpacing.cg) {
                ForEach(actions, id: \.self) { action in
                    let valid = isValid(action: action)
                    Button(policyActions[action]?.label ?? action.rawValue) {
                        selectAction(action)
                    }
                    .buttonStyle(PolicyButtonStyle(
                        pulse: decisionPulse,
                        selected: pendingSelection?.action == action,
                        width: layout.policyKeyWidth.cg,
                        height: layout.policyKeyHeight.cg,
                    ))
                    .disabled(!valid)
                    .help(resultingRateHelp(for: action))
                    .accessibilityLabel(policyAccessibilityLabel(for: action, valid: valid))
                    .accessibilityIdentifier(policyAccessibilityIdentifier(for: action, valid: valid))
                }
            }
        }
    }

    private var customControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CUSTOM")
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.46))
            HStack(spacing: 6) {
                TextField("bps", text: $customBps)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: layout.customFieldWidth.cg)
                    .accessibilityLabel("Custom basis point move")
                    .accessibilityIdentifier("policy-custom-bps-field")
                    .onSubmit {
                        if customDelta != nil {
                            selectAction(.custom)
                        }
                    }
                Button("Preview") {
                    selectAction(.custom)
                }
                .buttonStyle(PolicyButtonStyle(
                    pulse: decisionPulse,
                    selected: pendingSelection?.action == .custom,
                    width: max(68, layout.policyKeyWidth).cg,
                    height: layout.policyKeyHeight.cg,
                ))
                .disabled(customDelta == nil)
                .accessibilityLabel(customDelta == nil ? "Preview custom policy move disabled" : "Preview custom policy move")
                .accessibilityIdentifier(customDelta == nil ? "policy-custom-preview-disabled" : "policy-custom-preview")
            }
            Text("-150 to +150 bps")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(customBps.isEmpty || customDelta != nil ? .white.opacity(0.45) : .red.opacity(0.82))
        }
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PREVIEW")
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.48))
            if let preview {
                Text("\(preview.moveLabel) to \(preview.resultingFedFundsRate, format: .number.precision(.fractionLength(2)))%")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                previewRow("Inflation", preview.estimatedInflationPressure.displayLabel)
                previewRow("Labor", preview.estimatedUnemploymentPressure.displayLabel)
                previewRow("Credibility", preview.credibilityCost == 0 ? "None" : String(format: "%.2f pts", preview.credibilityCost))
                previewRow("Mandate", preview.mandateGapDirection.displayLabel)
                previewRow("Confidence", preview.confidence.displayLabel)
                Text(preview.primaryDriver)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
            } else {
                Text("Select a move to stage a non-mutating estimate before committing.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(3)
            }
            HStack(spacing: 8) {
                Button("Commit", action: commit)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCommit)
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityLabel(canCommit ? "Commit selected policy move" : "Commit selected policy move disabled")
                    .accessibilityIdentifier(canCommit ? "policy-commit" : "policy-commit-disabled")
                Button("Clear", action: clear)
                    .buttonStyle(.bordered)
                    .disabled(pendingSelection == nil && customBps.isEmpty)
                    .accessibilityLabel(pendingSelection == nil && customBps.isEmpty ? "Clear policy selection disabled" : "Clear policy selection")
                    .accessibilityIdentifier(pendingSelection == nil && customBps.isEmpty ? "policy-clear-disabled" : "policy-clear")
            }
        }
        .padding(8)
        .frame(minWidth: layout.mode == .compact ? 250 : 320, maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.13)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(previewAccessibilityLabel)
        .accessibilityIdentifier(preview == nil ? "policy-preview-empty" : "policy-preview-ready")
    }

    private func previewRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.white.opacity(0.48))
            Spacer()
            Text(value)
                .foregroundStyle(.white.opacity(0.82))
        }
        .font(.caption2.weight(.bold))
    }

    private func isValid(action: PolicyAction) -> Bool {
        let resulting = session.current.fedFundsRate + (policyActions[action]?.delta ?? 0)
        return resulting >= 0 && resulting <= 20
    }

    private func resultingRateHelp(for action: PolicyAction) -> String {
        let resulting = session.current.fedFundsRate + (policyActions[action]?.delta ?? 0)
        return String(format: "Preview resulting fed funds rate %.2f percent", resulting)
    }

    private func policyAccessibilityLabel(for action: PolicyAction, valid: Bool) -> String {
        let actionLabel = policyActions[action]?.label ?? action.rawValue
        let state = pendingSelection?.action == action ? "selected" : "not selected"
        return valid ? "\(actionLabel), \(state), selects for preview." : "\(actionLabel) disabled. Resulting rate out of bounds."
    }

    private func policyAccessibilityIdentifier(for action: PolicyAction, valid: Bool) -> String {
        if !valid {
            return "policy-action-\(action.rawValue)-disabled"
        }
        if pendingSelection?.action == action {
            return "policy-action-\(action.rawValue)-selected"
        }
        return "policy-action-\(action.rawValue)-available"
    }

    private var previewAccessibilityLabel: String {
        guard let preview else {
            return "Policy preview empty. Select a move to stage a non-mutating estimate before committing."
        }
        return "Policy preview ready. \(preview.moveLabel) to \(String(format: "%.2f", preview.resultingFedFundsRate)) percent. \(preview.primaryDriver)"
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

private extension PolicyPreviewPressure {
    var displayLabel: String {
        switch self {
        case .lower:
            "Lower"
        case .steady:
            "Steady"
        case .higher:
            "Higher"
        }
    }
}

private extension PolicyPreviewMandateGapDirection {
    var displayLabel: String {
        switch self {
        case .narrowing:
            "Narrowing"
        case .mixed:
            "Mixed"
        case .widening:
            "Widening"
        case .littleChanged:
            "Little changed"
        }
    }
}

private extension PolicyPreviewConfidence {
    var displayLabel: String {
        switch self {
        case .high:
            "High"
        case .medium:
            "Medium"
        case .low:
            "Low"
        }
    }
}
