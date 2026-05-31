import AppKit

@MainActor
final class GameWindowDelegate: NSObject, NSApplicationDelegate {
    private static let maxWindowOpenAttempts = 4
    private var windowRequestScheduled = false
    private var windowOpenAttempts = 0

    func applicationDidFinishLaunching(_: Notification) {
        ensurePlayableWindow()
    }

    func applicationDidBecomeActive(_: Notification) {
        ensurePlayableWindow()
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            ensurePlayableWindow()
        }
        return true
    }

    private func ensurePlayableWindow() {
        guard !windowRequestScheduled else {
            return
        }
        windowRequestScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else {
                return
            }
            windowRequestScheduled = false
            guard !Self.hasVisibleGameWindow() else {
                windowOpenAttempts = 0
                return
            }
            windowOpenAttempts += 1
            NSApp.activate(ignoringOtherApps: true)
            let requestSent = Self.requestNewWindow()
            guard !requestSent || !Self.hasVisibleGameWindow(),
                  windowOpenAttempts < Self.maxWindowOpenAttempts
            else {
                return
            }
            ensurePlayableWindow()
        }
    }

    private static func requestNewWindow() -> Bool {
        let selectors = [
            Selector(("newWindow:")),
            #selector(NSWindow.newWindowForTab(_:)),
        ]
        return selectors.contains { selector in
            NSApp.sendAction(selector, to: nil, from: nil)
        }
    }

    private static func hasVisibleGameWindow() -> Bool {
        NSApp.windows.contains { window in
            window.isVisible
                && !window.isMiniaturized
                && window.canBecomeKey
                && window.contentViewController != nil
        }
    }
}
