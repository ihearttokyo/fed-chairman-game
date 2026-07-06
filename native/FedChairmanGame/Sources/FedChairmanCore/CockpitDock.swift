import Foundation

public enum CockpitDockPanel: String, Codable, CaseIterable, Identifiable, Sendable {
    case newspaper
    case help

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .newspaper: "Newspaper"
        case .help: "Help"
        }
    }

    public var iconName: String {
        switch self {
        case .newspaper: "newspaper-icon"
        case .help: "help-icon"
        }
    }
}

public enum CockpitMotionMode: Equatable, Sendable {
    case spring
    case reduced
}

public struct CockpitPanelPlacement: Equatable, Sendable, Identifiable {
    public var panel: CockpitDockPanel
    public var index: Int
    public var xOffset: Double
    public var yOffset: Double

    public var id: String {
        panel.id
    }
}

public struct CockpitDockState: Equatable, Sendable {
    public private(set) var openPanels: [CockpitDockPanel]
    public private(set) var pinnedBriefing: Bool

    public init(openPanels: [CockpitDockPanel] = [], pinnedBriefing: Bool = false) {
        self.openPanels = openPanels.uniqued()
        self.pinnedBriefing = pinnedBriefing
    }

    public func isOpen(_ panel: CockpitDockPanel, briefingVisible: Bool = false) -> Bool {
        panel == .newspaper ? pinnedBriefing || briefingVisible || openPanels.contains(panel) : openPanels.contains(panel)
    }

    public mutating func toggle(_ panel: CockpitDockPanel) {
        if panel == .newspaper {
            if pinnedBriefing || openPanels.contains(panel) {
                pinnedBriefing = false
                openPanels.removeAll { $0 == panel }
            } else {
                pinnedBriefing = true
                openPanels = [panel]
            }
            return
        }
        if openPanels.contains(panel) {
            openPanels.removeAll { $0 == panel }
        } else {
            pinnedBriefing = false
            openPanels = [panel]
        }
    }

    public mutating func open(_ panel: CockpitDockPanel, pinned: Bool = false) {
        pinnedBriefing = panel == .newspaper ? pinned : false
        openPanels = [panel]
    }

    public mutating func close(_ panel: CockpitDockPanel) {
        if panel == .newspaper {
            pinnedBriefing = false
        }
        openPanels.removeAll { $0 == panel }
    }

    public mutating func closeAll() {
        pinnedBriefing = false
        openPanels.removeAll()
    }

    public func cascadePlacements(excluding excludedPanels: Set<CockpitDockPanel> = []) -> [CockpitPanelPlacement] {
        openPanels
            .filter { !excludedPanels.contains($0) }
            .enumerated()
            .map { index, panel in
                CockpitPanelPlacement(
                    panel: panel,
                    index: index,
                    xOffset: Double(index) * -24,
                    yOffset: Double(index) * -18,
                )
            }
    }
}

public func cockpitMotionMode(reduceMotion: Bool, ui: UiState) -> CockpitMotionMode {
    reduceMotion || ui.reducedMotion ? .reduced : .spring
}

private extension Array where Element: Equatable {
    func uniqued() -> [Element] {
        reduce(into: []) { result, element in
            if !result.contains(element) {
                result.append(element)
            }
        }
    }
}
