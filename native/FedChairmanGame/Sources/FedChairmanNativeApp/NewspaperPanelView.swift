import FedChairmanCore
import SwiftUI

struct NewspaperPanelView: View {
    var briefing: CockpitBriefing
    var layout: CockpitLayoutMetrics

    var body: some View {
        ZStack(alignment: .topLeading) {
            backgroundArt
            broadsheetContent
        }
        .frame(height: min(layout.dockPanelMaxHeight, panelHeight).cg)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.26)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(red: 0.22, green: 0.13, blue: 0.06).opacity(0.42)))
        .shadow(color: .black.opacity(0.52), radius: 28, y: 16)
        .shadow(color: .white.opacity(0.06), radius: 16, y: -4)
    }

    private var panelHeight: Double {
        switch layout.mode {
        case .compact:
            292
        case .standard:
            330
        case .expanded:
            390
        }
    }

    private var backgroundArt: some View {
        Group {
            if let image = NativeImageLoader.image(named: "newspaper-panel") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .saturation(0.90)
                    .brightness(0.03)
                    .accessibilityHidden(true)
            }
        }
    }

    private var broadsheetContent: some View {
        VStack(alignment: .leading, spacing: layout.mode == .compact ? 7 : 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("THE MANDATE DESK")
                    .font(.system(size: layout.mode == .compact ? 18 : 24, weight: .black, design: .serif))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(briefing.metadata.uppercased())
                    Text(briefing.severity.rawValue.uppercased())
                }
                .font(.system(size: 10, weight: .black, design: .serif))
            }
            .foregroundStyle(newspaperInk)
            rule()
            HStack(alignment: .top, spacing: layout.mode == .compact ? 12 : 18) {
                leadColumn
                sideColumn
            }
        }
        .padding(.horizontal, layout.mode == .compact ? 46 : 62)
        .padding(.vertical, layout.mode == .compact ? 30 : 40)
    }

    private var leadColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(briefing.headline)
                .font(.system(size: layout.mode == .compact ? 23 : 30, weight: .black, design: .serif))
                .foregroundStyle(newspaperInk)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            rule(opacity: 0.42)
            Text(briefing.body)
                .font(.system(size: layout.mode == .compact ? 13 : 15, weight: .semibold, design: .serif))
                .foregroundStyle(newspaperInk.opacity(0.86))
                .lineLimit(layout.mode == .compact ? 4 : 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            newspaperDateline("RISK CALENDAR", briefing.riskCalendar)
            newspaperDateline("POLICY IMPLICATION", briefing.policyImplication)
            newspaperDateline("WATCH", "Labor, credibility, and lagged policy")
        }
        .frame(width: layout.mode == .compact ? 210 : 250, alignment: .leading)
    }

    private var newspaperInk: Color {
        Color(red: 0.095, green: 0.058, blue: 0.030)
    }

    private func rule(opacity: Double = 0.65) -> some View {
        Rectangle()
            .fill(newspaperInk.opacity(opacity))
            .frame(height: 1)
    }

    private func newspaperDateline(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .black, design: .serif))
                .foregroundStyle(newspaperInk.opacity(0.76))
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .foregroundStyle(newspaperInk.opacity(0.88))
                .lineLimit(3)
            rule(opacity: 0.28)
        }
    }
}
