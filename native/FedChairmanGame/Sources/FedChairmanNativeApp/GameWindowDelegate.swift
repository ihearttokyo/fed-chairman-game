import AppKit
import FedChairmanCore
import SwiftUI

@MainActor
let fedChairmanSharedStore = GameSessionStore()

@MainActor
final class GameWindowDelegate: NSObject, NSApplicationDelegate {
    private static let maxWindowOpenAttempts = 4
    private var windowRequestScheduled = false
    private var windowOpenAttempts = 0
    private var fallbackWindow: NSWindow?

    func applicationWillFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
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
                Self.normalizeVisibleWindows()
                windowOpenAttempts = 0
                return
            }
            windowOpenAttempts += 1
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            Self.normalizeVisibleWindows()
            let requestSent = Self.requestNewWindow()
            if Self.hasVisibleGameWindow() {
                windowOpenAttempts = 0
                return
            }
            if requestSent, windowOpenAttempts < Self.maxWindowOpenAttempts {
                ensurePlayableWindow()
            } else {
                openFallbackWindow()
            }
        }
    }

    private func openFallbackWindow() {
        if let fallbackWindow, fallbackWindow.isVisible {
            fallbackWindow.makeKeyAndOrderFront(nil)
            return
        }
        let hostingController = NSHostingController(
            rootView: NativeCockpitView()
                .environmentObject(fedChairmanSharedStore),
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1180, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        window.title = "Fed Chairman Game"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = CGSize(width: 1180, height: 700)
        window.contentViewController = hostingController
        if let visibleFrame = NSScreen.main?.visibleFrame {
            let targetWidth = max(320.0, visibleFrame.width - 40)
            let targetHeight = max(260.0, visibleFrame.height - 40)
            window.setFrame(
                CGRect(
                    x: visibleFrame.midX - 590,
                    y: visibleFrame.midY - 350,
                    width: min(1180, targetWidth),
                    height: min(700, targetHeight),
                ),
                display: true,
                animate: false,
            )
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        fallbackWindow = window
        NSApp.activate(ignoringOtherApps: true)
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

    private static func normalizeVisibleWindows() {
        for window in NSApp.windows where window.isVisible && window.canBecomeKey {
            if let visibleFrame = NSScreen.main?.visibleFrame {
                let testWindowSize = preferredUITestWindowSize()
                let safeVisibleWidth = max(320.0, visibleFrame.width - 40)
                let safeVisibleHeight = max(260.0, visibleFrame.height - 40)
                let restoredFrameIsOversized = window.frame.width > visibleFrame.width - 80 || window.frame.height > visibleFrame.height - 80
                let requestedWidth = testWindowSize?.width ?? (restoredFrameIsOversized ? 1180 : max(window.frame.width, 1180))
                let requestedHeight = testWindowSize?.height ?? (restoredFrameIsOversized ? 700 : max(window.frame.height, 700))
                let width = min(max(320, requestedWidth), safeVisibleWidth)
                let height = min(max(260, requestedHeight), safeVisibleHeight)
                let frame = CGRect(
                    x: visibleFrame.midX - width / 2,
                    y: visibleFrame.midY - height / 2,
                    width: width,
                    height: height,
                )
                window.setFrame(frame, display: true, animate: false)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    private static func preferredUITestWindowSize() -> CGSize? {
        guard let rawSize = ProcessInfo.processInfo.environment["FED_CHAIRMAN_TEST_WINDOW_SIZE"] else {
            return nil
        }
        let parts = rawSize.lowercased().split(separator: "x")
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width.isFinite,
              height.isFinite,
              width > 0,
              height > 0
        else {
            return nil
        }
        return CGSize(width: width, height: height)
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
