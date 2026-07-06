import Foundation

public enum CockpitMode: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
    case desk
    case charts
    case records

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .desk:
            "Desk"
        case .charts:
            "Charts"
        case .records:
            "Records"
        }
    }

    public var shortTitle: String {
        switch self {
        case .desk:
            "Desk"
        case .charts:
            "Chart"
        case .records:
            "Records"
        }
    }

    public var subtitle: String {
        switch self {
        case .desk:
            "Briefing, chart, policy"
        case .charts:
            "Mandate detail"
        case .records:
            "History and preferences"
        }
    }

    public var accessibilityIdentifier: String {
        "cockpit-mode-\(rawValue)"
    }

    public var accessibilityLabel: String {
        "\(title) mode. \(subtitle)"
    }

    public var selectionAccessibilityLabel: String {
        "Show \(title.lowercased()) mode"
    }
}
