@testable import FedChairmanCore
import Foundation
import Testing

@Test func cockpitModeProvidesSelectionAccessibilityLabels() {
    for mode in CockpitMode.allCases {
        #expect(mode.accessibilityLabel.contains("\(mode.title) mode"))
        #expect(mode.accessibilityLabel.contains(mode.subtitle))
        #expect(mode.selectionAccessibilityLabel == "Show \(mode.title.lowercased()) mode")
        #expect(!mode.accessibilityLabel.localizedCaseInsensitiveContains("route"))
        #expect(!mode.accessibilityLabel.localizedCaseInsensitiveContains("web"))
    }
}

@Test func cockpitModeCodableUsesRawModeNames() throws {
    let encoded = try JSONEncoder().encode(CockpitMode.allCases)
    let encodedText = try #require(String(data: encoded, encoding: .utf8))

    #expect(encodedText == "[\"overview\",\"briefing\",\"mandate\",\"policy\",\"preferences\",\"history\"]")
    #expect(try JSONDecoder().decode([CockpitMode].self, from: encoded) == CockpitMode.allCases)
}
