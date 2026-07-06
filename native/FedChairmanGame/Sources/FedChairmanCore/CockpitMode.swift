import Foundation

public enum CockpitMode: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
    case overview
    case briefing
    case mandate
    case policy
    case preferences
    case history

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .overview:
            "Overview"
        case .briefing:
            "Briefing"
        case .mandate:
            "Mandate"
        case .policy:
            "Policy"
        case .preferences:
            "Preferences"
        case .history:
            "History"
        }
    }

    public var shortTitle: String {
        switch self {
        case .overview:
            "Desk"
        case .briefing:
            "Brief"
        case .mandate:
            "Chart"
        case .policy:
            "Policy"
        case .preferences:
            "Prefs"
        case .history:
            "History"
        }
    }

    public var subtitle: String {
        switch self {
        case .overview:
            "Full cockpit"
        case .briefing:
            "Risk read"
        case .mandate:
            "Chart focus"
        case .policy:
            "Decision desk"
        case .preferences:
            "Setup/export"
        case .history:
            "Career trail"
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
