import XCTest

final class NativeCockpitUITests: XCTestCase {
    private func configureFailureHandling() {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(windowSize: String? = nil, reduceMotion: Bool = false) -> XCUIApplication {
        configureFailureHandling()
        let app = XCUIApplication()
        app.launchEnvironment["FED_CHAIRMAN_TEST_WINDOW_SIZE"] = windowSize ?? "1180x700"
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
        app.activate()
        waitForWindow(in: app, toSettleAt: windowSize ?? "1180x700")
        return app
    }

    @MainActor
    private func waitForWindow(in app: XCUIApplication, toSettleAt windowSize: String, file: StaticString = #filePath, line: UInt = #line) {
        let parts = windowSize.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else {
            return
        }
        let target = CGSize(width: parts[0], height: parts[1])
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let frame = app.windows.firstMatch.frame
            if abs(frame.width - target.width) <= 80,
               abs(frame.height - target.height) <= 80
            {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        XCTAssertFalse(app.windows.firstMatch.frame.isEmpty, "Window should exist before frame assertions", file: file, line: line)
    }

    @MainActor
    private func assertElement(_ element: XCUIElement, staysInside windowFrame: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 2), "Element should exist", file: file, line: line)
        let frame = element.frame
        XCTAssertGreaterThanOrEqual(frame.minX, windowFrame.minX + 8, "Element should not clip left", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, windowFrame.minY + 8, "Element should not clip top", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, windowFrame.maxX - 8, "Element should not clip right", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, windowFrame.maxY - 8, "Element should not clip bottom", file: file, line: line)
    }

    @MainActor
    private func assertNoOverlap(_ first: XCUIElement, _ second: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(first.waitForExistence(timeout: 2), "\(first.label) should exist", file: file, line: line)
        XCTAssertTrue(second.waitForExistence(timeout: 2), "\(second.label) should exist", file: file, line: line)
        assertNoOverlap(first.frame, first.label, second.frame, second.label, file: file, line: line)
    }

    private func assertNoOverlap(_ firstFrame: CGRect, _ firstLabel: String, _ secondFrame: CGRect, _ secondLabel: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(firstFrame.insetBy(dx: 2, dy: 2).intersects(secondFrame.insetBy(dx: 2, dy: 2)), "\(firstLabel) should not overlap \(secondLabel)", file: file, line: line)
    }

    @MainActor
    private func captureVisualSmoke(_ app: XCUIApplication, name: String) throws {
        app.activate()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func newspaperButton(in app: XCUIApplication) -> XCUIElement {
        let openButton = app.buttons["Open newspaper panel"]
        if openButton.waitForExistence(timeout: 1) {
            return openButton
        }
        return app.buttons["Close newspaper panel"]
    }

    @MainActor
    private func panelElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func closePanelsWithEscape(in app: XCUIApplication) {
        app.typeKey(.escape, modifierFlags: [])
        let closed = expectation(
            for: NSPredicate(format: "exists == true"),
            evaluatedWith: app.buttons["Open newspaper panel"],
        )
        wait(for: [closed], timeout: 2)
    }

    @MainActor
    func testPolicyLeverDoesNotShiftAfterRateDecisionAndBriefingStaysClosed() {
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
        XCTAssertTrue(app.buttons["Open newspaper panel"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["newspaper-panel"].exists)
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
        XCTAssertTrue(app.buttons["Open newspaper panel"].waitForExistence(timeout: 2))
        XCTAssertFalse(panelElement("newspaper-panel", in: app).exists)
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
            XCTAssertGreaterThanOrEqual(frame.height, 50, "\(button.label) should leave room for a tappable icon")
        }
    }

    @MainActor
    func testLaunchStartsWithDockPanelsClosedAndPrimarySurfacesClear() {
        let app = launchApp(windowSize: "1600x1000")
        defer { app.terminate() }

        XCTAssertTrue(app.buttons["Open newspaper panel"].waitForExistence(timeout: 2))
        XCTAssertFalse(panelElement("newspaper-panel", in: app).exists)
        XCTAssertFalse(panelElement("help-panel", in: app).exists)
        XCTAssertFalse(panelElement("settings-panel", in: app).exists)

        let dashboard = panelElement("mandate-dashboard", in: app)
        let policyLever = panelElement("policy-lever", in: app)
        let metrics = panelElement("macro-metrics", in: app)
        let review = panelElement("quarter-review", in: app)
        let dockCluster = panelElement("dock-button-cluster", in: app)
        XCTAssertTrue(dashboard.waitForExistence(timeout: 2))
        XCTAssertTrue(policyLever.waitForExistence(timeout: 2))
        XCTAssertTrue(metrics.waitForExistence(timeout: 2))
        XCTAssertTrue(review.waitForExistence(timeout: 2))
        XCTAssertTrue(dockCluster.waitForExistence(timeout: 2))
        assertNoOverlap(dockCluster.frame, "Dock button cluster", policyLever.frame, "Policy Lever")
    }

    @MainActor
    func testCompactCockpitKeepsPolicyControlsUsableAboveDock() {
        let app = launchApp(windowSize: "1180x700")
        defer { app.terminate() }
        let windowFrame = app.windows.firstMatch.frame
        XCTAssertFalse(windowFrame.isEmpty)

        let policyButtons = ["-150 bps", "-100 bps", "-75 bps", "-50 bps", "-25 bps", "Hold", "+25 bps", "+50 bps", "+75 bps", "+100 bps", "+150 bps"]
            .map { app.buttons[$0] }
        let dockButtons = [newspaperButton(in: app), app.buttons["Open help panel"], app.buttons["Open settings panel"]]
        let dockFrames = dockButtons.map { button -> (CGRect, String) in
            XCTAssertTrue(button.waitForExistence(timeout: 2), "\(button.label) should exist")
            return (button.frame, button.label)
        }
        for button in policyButtons {
            assertElement(button, staysInside: windowFrame)
            for (dockFrame, dockLabel) in dockFrames {
                assertNoOverlap(button.frame, button.label, dockFrame, dockLabel)
            }
        }

        app.activate()
        app.buttons["+25 bps"].click()
        XCTAssertTrue(app.buttons["Open newspaper panel"].waitForExistence(timeout: 2))
        XCTAssertFalse(panelElement("newspaper-panel", in: app).exists)
        XCTAssertTrue(app.staticTexts["Quarter Review"].waitForExistence(timeout: 2))
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
            assertElement(panelElement("newspaper-panel", in: app), staysInside: windowFrame)
            closePanelsWithEscape(in: app)

            app.buttons["Open help panel"].click()
            assertElement(panelElement("help-panel", in: app), staysInside: windowFrame)
            app.buttons["Open settings panel"].click()
            let settingsPanel = panelElement("settings-panel", in: app)
            assertElement(settingsPanel, staysInside: windowFrame)
            for label in ["Save", "Load", "CSV", "JSON", "Markdown"] {
                assertElement(app.buttons[label], staysInside: settingsPanel.frame)
            }
        }
    }

    @MainActor
    func testOpenDockPanelsDoNotCoverPolicyLeverAtTargetSizes() {
        for size in ["1180x700", "1360x860", "1600x1000"] {
            let app = launchApp(windowSize: size)
            defer { app.terminate() }

            let policyLever = panelElement("policy-lever", in: app)
            XCTAssertTrue(policyLever.waitForExistence(timeout: 2))
            let policyButtons = ["-150 bps", "-100 bps", "-75 bps", "-50 bps", "-25 bps", "Hold", "+25 bps", "+50 bps", "+75 bps", "+100 bps", "+150 bps"]
                .map { app.buttons[$0] }

            let panelCases = [
                ("Open newspaper panel", "newspaper-panel"),
                ("Open help panel", "help-panel"),
                ("Open settings panel", "settings-panel"),
            ]
            for (buttonLabel, panelIdentifier) in panelCases {
                app.buttons[buttonLabel].click()
                let panel = panelElement(panelIdentifier, in: app)
                XCTAssertTrue(panel.waitForExistence(timeout: 2))
                assertNoOverlap(panel.frame, panelIdentifier, policyLever.frame, "Policy Lever")
                for button in policyButtons {
                    assertNoOverlap(panel.frame, panelIdentifier, button.frame, button.label)
                }
            }
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
        XCTAssertTrue(app.buttons["Open newspaper panel"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.descendants(matching: .any)["newspaper-panel"].exists)
        try captureVisualSmoke(app, name: "1360x860-after-decision")
    }
}
