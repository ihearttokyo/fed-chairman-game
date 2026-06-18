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

            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 4) {
                    Text(pressureLabel)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(toneColor)
                    Text("\(feedback.intensity)%")
                        .font(.caption2.monospacedDigit().weight(.black))
                        .foregroundStyle(.white.opacity(0.72))
                }
                pressureMeter
                HStack(spacing: 2) {
                    Text("calm")
                    Spacer(minLength: 0)
                    Text("stress")
                }
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
            }
            .frame(width: 96, alignment: .trailing)
        }
        .frame(height: 48)
        .padding(.vertical, 6)
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

    private var pressureMeter: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 2) {
                ForEach(0 ..< 5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index < pressureSegments ? toneColor.opacity(0.88) : Color.white.opacity(0.12))
                }
            }
            .frame(width: 92, height: 9)
            RoundedRectangle(cornerRadius: 2)
                .stroke(.white.opacity(0.16), lineWidth: 1)
                .frame(width: 92, height: 9)
        }
    }

    private var pressureSegments: Int {
        max(1, min(5, Int(ceil(Double(feedback.intensity) / 20.0))))
    }

    private var pressureLabel: String {
        switch feedback.intensity {
        case 0 ..< 35:
            "Low"
        case 35 ..< 70:
            "Watch"
        default:
            "High"
        }
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
