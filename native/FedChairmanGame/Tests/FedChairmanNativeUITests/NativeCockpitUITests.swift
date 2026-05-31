import XCTest

final class NativeCockpitUITests: XCTestCase {
    private func configureFailureHandling() {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(windowSize: String? = nil, reduceMotion: Bool = false) -> XCUIApplication {
        configureFailureHandling()
        let app = XCUIApplication()
        if let windowSize {
            app.launchEnvironment["FED_CHAIRMAN_TEST_WINDOW_SIZE"] = windowSize
        }
        if reduceMotion {
            app.launchEnvironment["FED_CHAIRMAN_TEST_REDUCE_MOTION"] = "1"
        }
        app.terminate()
        app.launch()
        if !app.staticTexts["Policy Lever"].waitForExistence(timeout: 3) {
            app.menuBars.menuBarItems["File"].click()
            app.menuItems["New Fed Chairman Game Window"].click()
        }
        XCTAssertTrue(app.staticTexts["Policy Lever"].waitForExistence(timeout: 6))
        return app
    }

    private func assertElement(_ element: XCUIElement, staysInside windowFrame: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 2), "Element should exist", file: file, line: line)
        let frame = element.frame
        XCTAssertGreaterThanOrEqual(frame.minX, windowFrame.minX + 8, "Element should not clip left", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, windowFrame.minY + 8, "Element should not clip top", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, windowFrame.maxX - 8, "Element should not clip right", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, windowFrame.maxY - 8, "Element should not clip bottom", file: file, line: line)
    }

    private func captureVisualSmoke(_ app: XCUIApplication, name: String) throws {
        app.activate()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func newspaperButton(in app: XCUIApplication) -> XCUIElement {
        let openButton = app.buttons["Open newspaper panel"]
        if openButton.exists {
            return openButton
        }
        return app.buttons["Close newspaper panel"]
    }

    private func closePanelsWithEscape(in app: XCUIApplication) {
        app.typeKey(.escape, modifierFlags: [])
        let closed = expectation(
            for: NSPredicate(format: "exists == true"),
            evaluatedWith: app.buttons["Open newspaper panel"],
        )
        wait(for: [closed], timeout: 2)
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
        let helpPanel = app.staticTexts["Policy Notebook"]
        XCTAssertTrue(helpPanel.waitForExistence(timeout: 2))

        app.buttons["Open settings panel"].click()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 2))
        XCTAssertFalse(helpPanel.waitForExistence(timeout: 1))

        app.buttons["Open newspaper panel"].click()
        XCTAssertTrue(app.staticTexts["THE MANDATE DESK"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Save"].waitForExistence(timeout: 1))
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

        for button in [newspaperButton(in: app), app.buttons["Open help panel"], app.buttons["Open settings panel"]] {
            XCTAssertTrue(button.waitForExistence(timeout: 2), "\(button.label) should exist")
            let frame = button.frame
            XCTAssertGreaterThanOrEqual(frame.minX, windowFrame.minX + 8, "\(button.label) should not clip left")
            XCTAssertGreaterThanOrEqual(frame.minY, windowFrame.minY + 8, "\(button.label) should not clip top")
            XCTAssertLessThanOrEqual(frame.maxX, windowFrame.maxX - 8, "\(button.label) should not clip right")
            XCTAssertLessThanOrEqual(frame.maxY, windowFrame.maxY - 8, "\(button.label) should not clip bottom")
            XCTAssertGreaterThanOrEqual(frame.height, 96, "\(button.label) should leave room for icon plus label")
        }
    }

    @MainActor
    func testResponsiveDockAndPanelsStayInsideWindowAtTargetSizes() {
        for size in ["1180x700", "1360x860", "1600x1000"] {
            let app = launchApp(windowSize: size)
            defer { app.terminate() }
            let windowFrame = app.windows.firstMatch.frame
            XCTAssertFalse(windowFrame.isEmpty)

            assertElement(newspaperButton(in: app), staysInside: windowFrame)
            assertElement(app.buttons["Open help panel"], staysInside: windowFrame)
            assertElement(app.buttons["Open settings panel"], staysInside: windowFrame)

            app.buttons["Open newspaper panel"].click()
            assertElement(app.staticTexts["THE MANDATE DESK"], staysInside: windowFrame)
            closePanelsWithEscape(in: app)

            app.buttons["Open help panel"].click()
            assertElement(app.staticTexts["Policy Notebook"], staysInside: windowFrame)
            app.buttons["Open settings panel"].click()
            assertElement(app.buttons["Save"], staysInside: windowFrame)
        }
    }

    @MainActor
    func testPanelTogglesDoNotMovePrimaryCockpitSurfacesAndEscapeCloses() {
        let app = launchApp(windowSize: "1360x860")
        defer { app.terminate() }
        let leverBefore = app.staticTexts["Policy Lever"].frame
        let dashboardBefore = app.staticTexts["Mandate Dashboard"].frame

        app.buttons["Open newspaper panel"].click()
        XCTAssertTrue(app.staticTexts["THE MANDATE DESK"].waitForExistence(timeout: 2))
        XCTAssertLessThanOrEqual(abs(app.staticTexts["Policy Lever"].frame.minY - leverBefore.minY), 4)
        XCTAssertLessThanOrEqual(abs(app.staticTexts["Mandate Dashboard"].frame.minY - dashboardBefore.minY), 4)

        closePanelsWithEscape(in: app)
        XCTAssertFalse(app.staticTexts["THE MANDATE DESK"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testReducedMotionLaunchExposesReducedMotionMode() {
        let app = launchApp(windowSize: "1180x700", reduceMotion: true)
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["motion-mode-reduced"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testVisualSmokeScreenshotsAtResponsiveSizes() throws {
        for size in ["1180x700", "1360x860", "1600x1000"] {
            let app = launchApp(windowSize: size)
            try captureVisualSmoke(app, name: "\(size)-closed")
            app.buttons["Open newspaper panel"].click()
            XCTAssertTrue(app.staticTexts["THE MANDATE DESK"].waitForExistence(timeout: 2))
            try captureVisualSmoke(app, name: "\(size)-newspaper")
            if size == "1180x700" {
                app.buttons["Open help panel"].click()
                XCTAssertTrue(app.staticTexts["Policy Notebook"].waitForExistence(timeout: 2))
                try captureVisualSmoke(app, name: "\(size)-help")
                app.buttons["Open settings panel"].click()
                XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 2))
                try captureVisualSmoke(app, name: "\(size)-settings")
            }
            app.terminate()
        }

        let app = launchApp(windowSize: "1360x860")
        defer { app.terminate() }
        app.buttons["+25 bps"].click()
        XCTAssertTrue(app.buttons["Close newspaper panel"].waitForExistence(timeout: 2))
        try captureVisualSmoke(app, name: "1360x860-after-decision")
        let retracts = expectation(
            for: NSPredicate(format: "exists == true"),
            evaluatedWith: app.buttons["Open newspaper panel"],
        )
        wait(for: [retracts], timeout: 6)
    }
}
