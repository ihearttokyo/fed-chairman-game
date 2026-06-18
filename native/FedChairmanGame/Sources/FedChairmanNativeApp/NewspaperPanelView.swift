import FedChairmanCore
import SwiftUI

struct NewspaperPanelView: View {
    var briefing: CockpitBriefing
    var layout: CockpitLayoutMetrics

    var body: some View {
        HStack(spacing: layout.mode == .compact ? 12 : 16) {
            if layout.mode != .compact {
                mastheadTile
            }
            briefingContent
            Spacer(minLength: 0)
            riskStack
        }
        .padding(layout.mode == .compact ? 10 : 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(panelFill)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.26)))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
    }

    private var panelFill: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(.ultraThinMaterial)
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.15),
                        Color(red: 0.18, green: 0.16, blue: 0.12).opacity(0.24),
                        Color.black.opacity(0.18),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                )
                .clipShape(RoundedRectangle(cornerRadius: 18)),
            )
    }

    private var mastheadTile: some View {
        ZStack {
            if let image = NativeImageLoader.image(named: "newspaper-panel") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .saturation(0.72)
                    .brightness(-0.04)
                    .contrast(0.92)
                    .accessibilityHidden(true)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.42)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Spacer()
                Text("MANDATE")
                Text("DESK")
            }
            .font(.system(size: layout.mode == .compact ? 15 : 18, weight: .black, design: .serif))
            .foregroundStyle(.white.opacity(0.88))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .frame(width: layout.mode == .compact ? 116 : 144)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
    }

    private var briefingContent: some View {
        VStack(alignment: .leading, spacing: layout.mode == .compact ? 6 : 8) {
            HStack(spacing: 8) {
                Text(layout.mode == .compact ? "Briefing" : "Latest Briefing")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.orange)
                Text(briefing.metadata)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.54))
            }
            .lineLimit(1)
            Text(briefing.headline)
                .font(.system(size: layout.mode == .compact ? 15 : 25, weight: .black, design: .rounded))
                .lineLimit(layout.mode == .compact ? 1 : 2)
                .minimumScaleFactor(0.82)
            if layout.mode != .compact {
                Text(briefing.body)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var riskStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            briefingChip("Risk", briefing.riskCalendar)
            briefingChip("Policy", briefing.policyImplication)
            if layout.mode != .compact {
                briefingChip("Watch", "Labor, credibility, lagged policy")
            }
        }
        .frame(width: layout.mode == .compact ? 300 : 310, alignment: .topLeading)
    }

    private func briefingChip(_ label: String, _ body: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.52))
            Text(body)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(layout.mode == .compact ? 1 : 2)
        }
        .padding(layout.mode == .compact ? 7 : 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.10)))
    }
}
