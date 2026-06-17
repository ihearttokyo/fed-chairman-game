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
            spacing: 5,
            panelPadding: 8,
            chartHeight: 118,
            policyKeyWidth: 62,
            policyKeyHeight: 34,
            policyKeySpacing: 6,
            customFieldWidth: 84,
            metricsColumns: 5,
            quarterReviewHeight: 64,
            dockButtonWidth: 54,
            dockButtonHeight: 54,
            dockTrayWidth: 188,
            dockTrayHeight: 66,
            dockOuterPadding: 18,
            dockBottomLift: 0,
            dockVerticalOffset: 0,
            newspaperPanelWidth: min(620, panelWidth),
            helpPanelWidth: min(620, panelWidth),
            settingsPanelWidth: min(340, panelWidth),
            dockPanelMaxHeight: compactPanelHeight,
        )
    case .standard:
        return CockpitLayoutMetrics(
            mode: mode,
            spacing: 11,
            panelPadding: 13,
            chartHeight: 230,
            policyKeyWidth: 72,
            policyKeyHeight: 42,
            policyKeySpacing: 7,
            customFieldWidth: 90,
            metricsColumns: 5,
            quarterReviewHeight: 150,
            dockButtonWidth: 88,
            dockButtonHeight: 106,
            dockTrayWidth: 294,
            dockTrayHeight: 112,
            dockOuterPadding: 22,
            dockBottomLift: 0,
            dockVerticalOffset: 0,
            newspaperPanelWidth: min(680, panelWidth),
            helpPanelWidth: min(680, panelWidth),
            settingsPanelWidth: min(340, panelWidth),
            dockPanelMaxHeight: maxPanelHeight,
        )
    case .expanded:
        return CockpitLayoutMetrics(
            mode: mode,
            spacing: 13,
            panelPadding: 15,
            chartHeight: 260,
            policyKeyWidth: 78,
            policyKeyHeight: 44,
            policyKeySpacing: 8,
            customFieldWidth: 96,
            metricsColumns: 5,
            quarterReviewHeight: 178,
            dockButtonWidth: 92,
            dockButtonHeight: 112,
            dockTrayWidth: 304,
            dockTrayHeight: 118,
            dockOuterPadding: 24,
            dockBottomLift: 0,
            dockVerticalOffset: 0,
            newspaperPanelWidth: min(720, panelWidth),
            helpPanelWidth: min(700, panelWidth),
            settingsPanelWidth: min(360, panelWidth),
            dockPanelMaxHeight: maxPanelHeight,
        )
    }
}
