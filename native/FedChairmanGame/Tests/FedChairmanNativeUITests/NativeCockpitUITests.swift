import XCTest

final class NativeCockpitUITests: XCTestCase {
    private func configureFailureHandling() {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        configureFailureHandling()
        let app = XCUIApplication()
        app.terminate()
        app.launch()
        if !app.staticTexts["Policy Lever"].waitForExistence(timeout: 3) {
            app.menuBars.menuBarItems["File"].click()
            app.menuItems["New Fed Chairman Game Window"].click()
        }
        XCTAssertTrue(app.staticTexts["Policy Lever"].waitForExistence(timeout: 6))
        return app
    }

    @MainActor
    func testPolicyLeverDoesNotShiftAfterRateDecisionAndBriefingAutoRetracts() {
        let app = launchApp()
        defer { app.terminate() }
        let policyLever = app.staticTexts["Policy Lever"]
        let dashboard = app.staticTexts["Mandate Dashboard"]
        XCTAssertTrue(dashboard.exists)

        let leverBefore = policyLever.frame
        let dashboardBefore = dashboard.frame
        app.buttons["+25 bps"].click()

        let leverAfter = app.staticTexts["Policy Lever"].frame
        let dashboardAfter = app.staticTexts["Mandate Dashboard"].frame
        XCTAssertLessThanOrEqual(abs(leverBefore.minY - leverAfter.minY), 4)
        XCTAssertLessThanOrEqual(abs(dashboardBefore.minY - dashboardAfter.minY), 4)
        XCTAssertTrue(app.staticTexts["Quarter Review"].waitForExistence(timeout: 2))
        let decisionTape = app.descendants(matching: .any)["decision-tape"]
        XCTAssertTrue(decisionTape.waitForExistence(timeout: 2))
        XCTAssertTrue(decisionTape.label.contains("+25 bps"))
        XCTAssertTrue(decisionTape.label.contains("4.00% -> 4.25%"))
        XCTAssertTrue(app.buttons["Close newspaper panel"].waitForExistence(timeout: 2))

        let retracts = expectation(
            for: NSPredicate(format: "exists == true"),
            evaluatedWith: app.buttons["Open newspaper panel"],
        )
        wait(for: [retracts], timeout: 6)
        XCTAssertTrue(app.buttons["Open newspaper panel"].exists)
    }

    @MainActor
    func testDockPanelsToggleExclusivelyAndPolicyCommandsRemainUsable() {
        let app = launchApp()
        defer { app.terminate() }
        let helpButton = app.buttons["Open help panel"]
        XCTAssertTrue(helpButton.waitForExistence(timeout: 3))
        helpButton.click()
        let helpPanel = app.descendants(matching: .any)["help-panel"]
        XCTAssertTrue(helpPanel.waitForExistence(timeout: 2))

        app.buttons["Open settings panel"].click()
        XCTAssertTrue(app.descendants(matching: .any)["settings-panel"].waitForExistence(timeout: 2))
        XCTAssertFalse(helpPanel.waitForExistence(timeout: 1))

        app.buttons["Open newspaper panel"].click()
        XCTAssertTrue(app.descendants(matching: .any)["newspaper-panel"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.descendants(matching: .any)["settings-panel"].waitForExistence(timeout: 1))
        app.buttons["Close newspaper panel"].click()

        app.staticTexts["Mandate Dashboard"].click()
        app.menuBars.menuBarItems["Policy"].click()
        app.menuItems["Raise 25 bps"].click()
        XCTAssertTrue(app.buttons["Close newspaper panel"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testDockButtonsStayFullyVisibleInTheWindow() {
        let app = launchApp()
        defer { app.terminate() }
        let windowFrame = app.windows.firstMatch.frame
        XCTAssertFalse(windowFrame.isEmpty)

        for identifier in ["dock-newspaper", "dock-help", "dock-settings"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 2), "\(identifier) should exist")
            let frame = button.frame
            XCTAssertGreaterThanOrEqual(frame.minX, windowFrame.minX + 8, "\(identifier) should not clip left")
            XCTAssertGreaterThanOrEqual(frame.minY, windowFrame.minY + 8, "\(identifier) should not clip top")
            XCTAssertLessThanOrEqual(frame.maxX, windowFrame.maxX - 8, "\(identifier) should not clip right")
            XCTAssertLessThanOrEqual(frame.maxY, windowFrame.maxY - 8, "\(identifier) should not clip bottom")
            XCTAssertGreaterThanOrEqual(frame.height, 104, "\(identifier) should leave room for icon plus label")
        }
    }
}
