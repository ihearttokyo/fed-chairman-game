import FedChairmanCore
import SwiftUI

struct DecisionTapeView: View {
    var feedback: DecisionFeedback
    var pulse: Bool
    var motionMode: CockpitMotionMode

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(receiptHeading)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(toneColor)
                Text(feedback.moveLabel)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(feedback.ratePath)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.66))
            }
            .frame(width: 150, alignment: .leading)

            Divider()
                .frame(height: 32)
                .overlay(.white.opacity(0.18))

            VStack(alignment: .leading, spacing: 3) {
                Text(feedback.headline)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(toneColor)
                Text(feedback.mandateLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 48)
        .padding(.vertical, 5)
        .padding(.horizontal, 9)
        .background(background)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(toneColor.opacity(pulse ? 0.62 : 0.30)))
        .shadow(color: toneColor.opacity(pulse ? 0.18 : 0.06), radius: pulse ? 18 : 10, y: 4)
        .scaleEffect(pulse && motionMode == .spring ? 1.012 : 1)
        .animation(motionMode == .reduced ? nil : .bouncy(duration: 0.3, extraBounce: 0.16), value: pulse)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("decision-tape")
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.black.opacity(0.18))
            .overlay(
                LinearGradient(
                    colors: [toneColor.opacity(pulse ? 0.30 : 0.14), .white.opacity(0.035), .clear],
                    startPoint: .leading,
                    endPoint: .trailing,
                )
                .clipShape(RoundedRectangle(cornerRadius: 10)),
            )
    }

    private var accessibilityText: String {
        "Decision tape. \(feedback.headline). \(feedback.moveLabel). \(feedback.ratePath). \(feedback.mandateLine)."
    }

    private var receiptHeading: String {
        feedback.headline == "Awaiting first vote" ? feedback.headline.uppercased() : "LATEST DECISION"
    }

    private var toneColor: Color {
        switch feedback.tone {
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
}
