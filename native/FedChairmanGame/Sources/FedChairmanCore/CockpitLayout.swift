import Foundation

public enum CockpitLayoutMode: String, Codable, CaseIterable, Sendable {
    case compact
    case standard
    case expanded
}

public struct CockpitLayoutMetrics: Equatable, Sendable {
    public var mode: CockpitLayoutMode
    public var spacing: Double
    public var panelPadding: Double
    public var chartHeight: Double
    public var policyKeyWidth: Double
    public var policyKeyHeight: Double
    public var policyKeySpacing: Double
    public var customFieldWidth: Double
    public var metricsColumns: Int
    public var quarterReviewHeight: Double
    public var dockButtonWidth: Double
    public var dockButtonHeight: Double
    public var dockTrayWidth: Double
    public var dockTrayHeight: Double
    public var dockOuterPadding: Double
    public var dockBottomLift: Double
    public var dockVerticalOffset: Double
    public var newspaperPanelWidth: Double
    public var helpPanelWidth: Double
    public var dockPanelMaxHeight: Double
    public var compressedDensity: Bool

    public var isCompactNotebookLayout: Bool {
        mode == .compact || (mode == .standard && compressedDensity)
    }
}

public func cockpitLayoutMode(width: Double, height: Double) -> CockpitLayoutMode {
    if width >= 1500, height >= 900 {
        return .expanded
    }
    if width >= 1300, height >= 800 {
        return .standard
    }
    return .compact
}

public func cockpitLayoutMetrics(width: Double, height: Double) -> CockpitLayoutMetrics {
    let mode = cockpitLayoutMode(width: width, height: height)
    let sideMargin = mode == .compact ? 18.0 : 26.0
    let safeWidth = max(0, width - sideMargin * 2)
    let panelWidth = max(320, safeWidth - 28)
    let maxPanelHeight = max(172, min(height - 230, mode == .expanded ? 260 : 224))
    let compactPanelHeight = max(150, min(height - 408, 190))
    let standardDensityCompact = height < 900

    switch mode {
    case .compact:
        return CockpitLayoutMetrics(
            mode: mode,
            spacing: 6,
            panelPadding: 7,
            chartHeight: 130,
            policyKeyWidth: 64,
            policyKeyHeight: 32,
            policyKeySpacing: 6,
            customFieldWidth: 78,
            metricsColumns: 5,
            quarterReviewHeight: 44,
            dockButtonWidth: 50,
            dockButtonHeight: 50,
            dockTrayWidth: 176,
            dockTrayHeight: 58,
            dockOuterPadding: 16,
            dockBottomLift: 0,
            dockVerticalOffset: 0,
            newspaperPanelWidth: panelWidth,
            helpPanelWidth: panelWidth,
            dockPanelMaxHeight: compactPanelHeight,
            compressedDensity: true,
        )
    case .standard:
        let spacing: Double = standardDensityCompact ? 8 : 12
        let panelPadding: Double = standardDensityCompact ? 10 : 12
        let chartHeight: Double = standardDensityCompact ? 170 : 210
        let policyKeyHeight: Double = standardDensityCompact ? 34 : 40
        let policyKeySpacing: Double = standardDensityCompact ? 6 : 8
        let dockPanelMaxHeight: Double = standardDensityCompact
            ? min(172, max(132, maxPanelHeight))
            : min(174, maxPanelHeight)

        return CockpitLayoutMetrics(
            mode: mode,
            spacing: spacing,
            panelPadding: panelPadding,
            chartHeight: chartHeight,
            policyKeyWidth: 76,
            policyKeyHeight: policyKeyHeight,
            policyKeySpacing: policyKeySpacing,
            customFieldWidth: 90,
            metricsColumns: 5,
            quarterReviewHeight: 52,
            dockButtonWidth: 52,
            dockButtonHeight: 52,
            dockTrayWidth: 190,
            dockTrayHeight: 62,
            dockOuterPadding: 20,
            dockBottomLift: 0,
            dockVerticalOffset: 0,
            newspaperPanelWidth: panelWidth,
            helpPanelWidth: panelWidth,
            dockPanelMaxHeight: dockPanelMaxHeight,
            compressedDensity: standardDensityCompact,
        )
    case .expanded:
        return CockpitLayoutMetrics(
            mode: mode,
            spacing: 10,
            panelPadding: 12,
            chartHeight: 260,
            policyKeyWidth: 78,
            policyKeyHeight: 38,
            policyKeySpacing: 9,
            customFieldWidth: 96,
            metricsColumns: 5,
            quarterReviewHeight: 76,
            dockButtonWidth: 54,
            dockButtonHeight: 54,
            dockTrayWidth: 196,
            dockTrayHeight: 64,
            dockOuterPadding: 22,
            dockBottomLift: 0,
            dockVerticalOffset: 0,
            newspaperPanelWidth: panelWidth,
            helpPanelWidth: panelWidth,
            dockPanelMaxHeight: min(214, maxPanelHeight),
            compressedDensity: false,
        )
    }
}
