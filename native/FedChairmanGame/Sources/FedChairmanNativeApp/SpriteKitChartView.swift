import FedChairmanCore
import SpriteKit
import SwiftUI

struct SpriteKitChart: NSViewRepresentable {
    var history: [MacroState]
    var reducedMotion: Bool
    var inflationUpperBound: Double
    var onInspectionIndexChanged: (Int?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onInspectionIndexChanged: onInspectionIndexChanged)
    }

    func makeNSView(context: Context) -> ChartTrackingView {
        let view = ChartTrackingView()
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 30
        view.shouldCullNonVisibleNodes = false
        view.isAsynchronous = false
        view.setAccessibilityIdentifier("mandate-chart")
        view.setAccessibilityLabel("Interactive mandate chart")
        view.onBoundsChanged = {
            context.coordinator.render(into: view)
        }
        view.onMouseMoved = { point in
            if context.coordinator.updateInspectionIndex(for: point.x, viewSize: view.bounds.size) {
                context.coordinator.render(into: view)
            }
        }
        view.onMouseExited = {
            if context.coordinator.setInspectionIndex(nil) {
                context.coordinator.render(into: view)
            }
        }
        view.presentScene(CockpitScene(size: CGSize(width: 900, height: 320)))
        return view
    }

    func updateNSView(_ view: ChartTrackingView, context: Context) {
        context.coordinator.update(history: history, reducedMotion: reducedMotion, inflationUpperBound: inflationUpperBound)
        DispatchQueue.main.async {
            context.coordinator.render(into: view)
        }
    }

    @MainActor
    final class Coordinator {
        private let onInspectionIndexChanged: (Int?) -> Void
        private var inspectionIndex: Int?
        private var history: [MacroState] = []
        private var reducedMotion = false
        private var inflationUpperBound = 4.0

        init(onInspectionIndexChanged: @escaping (Int?) -> Void) {
            self.onInspectionIndexChanged = onInspectionIndexChanged
        }

        func update(history: [MacroState], reducedMotion: Bool, inflationUpperBound: Double) {
            let historyChanged = self.history.count != history.count || self.history.last != history.last
            self.history = history
            self.reducedMotion = reducedMotion
            self.inflationUpperBound = inflationUpperBound
            if historyChanged {
                setInspectionIndex(nil)
            } else if let inspectionIndex, inspectionIndex >= history.count {
                setInspectionIndex(history.isEmpty ? nil : history.count - 1)
            }
        }

        func render(into view: SKView) {
            view.window?.acceptsMouseMovedEvents = true
            let scene = (view.scene as? CockpitScene) ?? CockpitScene(size: view.bounds.size)
            scene.size = view.bounds.size == .zero ? CGSize(width: 900, height: 320) : view.bounds.size
            scene.render(history: history, reducedMotion: reducedMotion, inflationUpperBound: inflationUpperBound, hoverIndex: inspectionIndex)
            if view.scene !== scene {
                view.presentScene(scene)
            }
        }

        @discardableResult
        func updateInspectionIndex(for x: CGFloat, viewSize: CGSize) -> Bool {
            let historyCount = history.count
            guard historyCount > 0 else {
                setInspectionIndex(nil)
                return false
            }
            let frame = CockpitScene.chartFrame(for: viewSize == .zero ? CGSize(width: 900, height: 320) : viewSize)
            let clampedX = min(frame.maxX, max(frame.minX, x))
            let progress = (clampedX - frame.minX) / max(1, frame.width)
            let index = min(historyCount - 1, max(0, Int(round(progress * CGFloat(max(1, historyCount - 1))))))
            guard inspectionIndex != index else {
                return false
            }
            setInspectionIndex(index)
            return true
        }

        @discardableResult
        func setInspectionIndex(_ index: Int?) -> Bool {
            guard inspectionIndex != index else {
                return false
            }
            inspectionIndex = index
            onInspectionIndexChanged(index)
            return true
        }
    }
}

final class ChartTrackingView: SKView {
    var onMouseMoved: ((CGPoint) -> Void)?
    var onMouseExited: (() -> Void)?
    var onBoundsChanged: (() -> Void)?
    private var chartTrackingArea: NSTrackingArea?
    private var lastRenderedBounds: CGRect = .zero

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onBoundsChanged?()
        }
    }

    override func layout() {
        super.layout()
        guard bounds.size != lastRenderedBounds.size else {
            return
        }
        lastRenderedBounds = bounds
        onBoundsChanged?()
    }

    override func updateTrackingAreas() {
        if let chartTrackingArea {
            removeTrackingArea(chartTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil,
        )
        addTrackingArea(area)
        chartTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMouseMoved?(point)
    }

    override func mouseExited(with _: NSEvent) {
        onMouseExited?()
    }
}
