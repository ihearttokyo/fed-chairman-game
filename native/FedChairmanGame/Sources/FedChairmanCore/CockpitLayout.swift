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
    let sideMargin = mode == .compact ? 16.0 : 24.0
    let safeWidth = max(0, width - sideMargin * 2)
    let panelWidth = max(320, safeWidth - 20)
    let maxPanelHeight = max(220, min(height - 220, mode == .expanded ? 360 : 320))
    let compactPanelHeight = max(220, min(height - 430, 276))

    switch mode {
    case .compact:
        return CockpitLayoutMetrics(
            mode: mode,
            spacing: 7,
            panelPadding: 8,
            chartHeight: 132,
            policyKeyWidth: 62,
            policyKeyHeight: 34,
            policyKeySpacing: 6,
            customFieldWidth: 84,
            metricsColumns: 5,
            quarterReviewHeight: 64,
            dockButtonWidth: 48,
            dockButtonHeight: 48,
            dockTrayWidth: 174,
            dockTrayHeight: 58,
            dockOuterPadding: 18,
            dockBottomLift: 0,
            dockVerticalOffset: 0,
            newspaperPanelWidth: panelWidth,
            helpPanelWidth: panelWidth,
            settingsPanelWidth: panelWidth,
            dockPanelMaxHeight: min(76, compactPanelHeight),
        )
    case .standard:
        return CockpitLayoutMetrics(
            mode: mode,
            spacing: 10,
            panelPadding: 13,
            chartHeight: 214,
            policyKeyWidth: 72,
            policyKeyHeight: 42,
            policyKeySpacing: 7,
            customFieldWidth: 90,
            metricsColumns: 5,
            quarterReviewHeight: 150,
            dockButtonWidth: 58,
            dockButtonHeight: 58,
            dockTrayWidth: 210,
            dockTrayHeight: 70,
            dockOuterPadding: 22,
            dockBottomLift: 0,
            dockVerticalOffset: 0,
            newspaperPanelWidth: panelWidth,
            helpPanelWidth: panelWidth,
            settingsPanelWidth: min(760, panelWidth),
            dockPanelMaxHeight: min(136, maxPanelHeight),
        )
    case .expanded:
        return CockpitLayoutMetrics(
            mode: mode,
            spacing: 13,
            panelPadding: 15,
            chartHeight: 238,
            policyKeyWidth: 78,
            policyKeyHeight: 44,
            policyKeySpacing: 8,
            customFieldWidth: 96,
            metricsColumns: 5,
            quarterReviewHeight: 178,
            dockButtonWidth: 60,
            dockButtonHeight: 60,
            dockTrayWidth: 216,
            dockTrayHeight: 72,
            dockOuterPadding: 24,
            dockBottomLift: 0,
            dockVerticalOffset: 0,
            newspaperPanelWidth: panelWidth,
            helpPanelWidth: panelWidth,
            settingsPanelWidth: min(820, panelWidth),
            dockPanelMaxHeight: min(156, maxPanelHeight),
        )
    }
}
