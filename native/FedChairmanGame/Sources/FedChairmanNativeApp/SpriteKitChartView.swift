import FedChairmanCore
import SpriteKit
import SwiftUI

struct SpriteKitChart: NSViewRepresentable {
    var history: [MacroState]
    var reducedMotion: Bool
    var onInspectionIndexChanged: (Int?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onInspectionIndexChanged: onInspectionIndexChanged)
    }

    func makeNSView(context: Context) -> ChartTrackingView {
        let view = ChartTrackingView()
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.setAccessibilityIdentifier("mandate-chart")
        view.setAccessibilityLabel("Interactive mandate chart")
        view.onBoundsChanged = {
            context.coordinator.render(into: view)
        }
        view.onMouseMoved = { point in
            context.coordinator.hoverX = point.x
            context.coordinator.updateInspectionIndex(for: point.x, viewSize: view.bounds.size)
            context.coordinator.render(into: view)
        }
        view.onMouseExited = {
            context.coordinator.hoverX = nil
            context.coordinator.setInspectionIndex(nil)
            context.coordinator.render(into: view)
        }
        view.presentScene(CockpitScene(size: CGSize(width: 900, height: 320)))
        return view
    }

    func updateNSView(_ view: ChartTrackingView, context: Context) {
        context.coordinator.update(history: history, reducedMotion: reducedMotion)
        context.coordinator.render(into: view)
    }

    @MainActor
    final class Coordinator {
        private let onInspectionIndexChanged: (Int?) -> Void
        var hoverX: CGFloat?
        private var inspectionIndex: Int?
        private var history: [MacroState] = []
        private var reducedMotion = false

        init(onInspectionIndexChanged: @escaping (Int?) -> Void) {
            self.onInspectionIndexChanged = onInspectionIndexChanged
        }

        func update(history: [MacroState], reducedMotion: Bool) {
            let historyChanged = self.history.count != history.count || self.history.last != history.last
            self.history = history
            self.reducedMotion = reducedMotion
            if historyChanged {
                hoverX = nil
                setInspectionIndex(nil)
            } else if let inspectionIndex, inspectionIndex >= history.count {
                setInspectionIndex(history.isEmpty ? nil : history.count - 1)
            }
        }

        func render(into view: SKView) {
            view.window?.acceptsMouseMovedEvents = true
            let scene = (view.scene as? CockpitScene) ?? CockpitScene(size: view.bounds.size)
            scene.size = view.bounds.size == .zero ? CGSize(width: 900, height: 320) : view.bounds.size
            scene.render(history: history, reducedMotion: reducedMotion, hoverX: hoverX)
            if view.scene !== scene {
                view.presentScene(scene)
            }
        }

        func updateInspectionIndex(for x: CGFloat, viewSize: CGSize) {
            let historyCount = history.count
            guard historyCount > 0 else {
                setInspectionIndex(nil)
                return
            }
            let frame = CockpitScene.chartFrame(for: viewSize == .zero ? CGSize(width: 900, height: 320) : viewSize)
            let clampedX = min(frame.maxX, max(frame.minX, x))
            let progress = (clampedX - frame.minX) / max(1, frame.width)
            let index = min(historyCount - 1, max(0, Int(round(progress * CGFloat(max(1, historyCount - 1))))))
            setInspectionIndex(index)
        }

        func setInspectionIndex(_ index: Int?) {
            guard inspectionIndex != index else {
                return
            }
            inspectionIndex = index
            onInspectionIndexChanged(index)
        }
    }
}

final class ChartTrackingView: SKView {
    var onMouseMoved: ((CGPoint) -> Void)?
    var onMouseExited: (() -> Void)?
    var onBoundsChanged: (() -> Void)?
    private var chartTrackingArea: NSTrackingArea?
    private var lastRenderedBounds: CGRect = .zero

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
