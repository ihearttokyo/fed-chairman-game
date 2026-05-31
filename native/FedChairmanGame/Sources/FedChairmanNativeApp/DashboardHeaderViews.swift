import FedChairmanCore
import SwiftUI

struct ChartInspectionStrip: View {
    var inspection: ChartInspection?
    var isInspecting: Bool

    var body: some View {
        Group {
            if let inspection {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Text(isInspecting ? "INSPECTING" : "LATEST")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.green)
                        Text(inspection.primaryLabel)
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .accessibilityIdentifier("chart-inspection-primary")
                        Text(inspection.secondaryLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        inspectionStat("INF", inspection.inflation, .orange)
                        inspectionStat("U", inspection.unemployment, .blue)
                        inspectionStat("FFR", inspection.fedFunds, .green)
                        inspectionStat("CRED", inspection.credibility, .yellow)
                    }
                    HStack(spacing: 10) {
                        Text(inspection.policy)
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                            .accessibilityIdentifier("chart-inspection-policy")
                        Text(inspection.movement)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.1)))
            }
        }
    }

    private func inspectionStat(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2.weight(.black))
                .foregroundStyle(color)
            Text(value)
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.78))
        }
    }
}

struct MandateBadge: View {
    var label: String
    var value: Double
    var target: Double
    var color: Color

    var body: some View {
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
}
