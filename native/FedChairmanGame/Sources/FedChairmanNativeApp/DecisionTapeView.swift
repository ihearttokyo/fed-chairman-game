import FedChairmanCore
import SwiftUI

struct DecisionTapeView: View {
    var feedback: DecisionFeedback
    var pulse: Bool
    var motionMode: CockpitMotionMode

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(feedback.headline.uppercased())
                    .font(.caption2.weight(.black))
                    .foregroundStyle(toneColor)
                Text(feedback.moveLabel)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(feedback.ratePath)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.66))
            }
            .frame(width: 178, alignment: .leading)

            Divider()
                .frame(height: 42)
                .overlay(.white.opacity(0.18))

            VStack(alignment: .leading, spacing: 4) {
                Text(feedback.mandateLine)
                    .lineLimit(1)
                Text(feedback.credibilityLine)
                    .lineLimit(1)
                Text(feedback.traceLine)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.58))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.74))
            .frame(maxWidth: .infinity, alignment: .leading)

            Gauge(value: Double(feedback.intensity), in: 0 ... 100) {
                Text("Pressure")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(toneColor)
            .frame(width: 58)
        }
        .frame(height: 58)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(background)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(toneColor.opacity(pulse ? 0.62 : 0.30)))
        .shadow(color: toneColor.opacity(pulse ? 0.18 : 0.06), radius: pulse ? 18 : 10, y: 4)
        .scaleEffect(pulse && motionMode == .spring ? 1.012 : 1)
        .animation(motionMode == .reduced ? nil : .bouncy(duration: 0.3, extraBounce: 0.16), value: pulse)
        .accessibilityElement(children: .combine)
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
