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
    public var settingsPanelWidth: Double
    public var dockPanelMaxHeight: Double
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
    let maxPanelHeight = max(184, min(height - 236, mode == .expanded ? 292 : 244))
    let compactPanelHeight = max(164, min(height - 438, 210))

    switch mode {
    case .compact:
        return CockpitLayoutMetrics(
            mode: mode,
            spacing: 8,
            panelPadding: 9,
            chartHeight: 116,
            policyKeyWidth: 62,
            policyKeyHeight: 34,
            policyKeySpacing: 7,
            customFieldWidth: 84,
            metricsColumns: 5,
            quarterReviewHeight: 44,
            dockButtonWidth: 44,
            dockButtonHeight: 44,
            dockTrayWidth: 158,
            dockTrayHeight: 52,
            dockOuterPadding: 16,
            dockBottomLift: 0,
            dockVerticalOffset: 0,
            newspaperPanelWidth: panelWidth,
            helpPanelWidth: panelWidth,
            settingsPanelWidth: panelWidth,
            dockPanelMaxHeight: min(64, compactPanelHeight),
        )
    case .standard:
        return CockpitLayoutMetrics(
            mode: mode,
            spacing: 12,
            panelPadding: 12,
            chartHeight: 166,
            policyKeyWidth: 72,
            policyKeyHeight: 40,
            policyKeySpacing: 8,
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
            settingsPanelWidth: min(760, panelWidth),
            dockPanelMaxHeight: min(96, maxPanelHeight),
        )
    case .expanded:
        return CockpitLayoutMetrics(
            mode: mode,
            spacing: 14,
            panelPadding: 14,
            chartHeight: 190,
            policyKeyWidth: 78,
            policyKeyHeight: 42,
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
            settingsPanelWidth: min(820, panelWidth),
            dockPanelMaxHeight: min(112, maxPanelHeight),
        )
    }
}
