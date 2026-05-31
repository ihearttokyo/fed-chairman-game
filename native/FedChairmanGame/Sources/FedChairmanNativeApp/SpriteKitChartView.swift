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
        view.onMouseMoved = { point in
            context.coordinator.hoverX = point.x
            context.coordinator.updateInspectionIndex(for: point.x, viewWidth: view.bounds.width, historyCount: history.count)
            context.coordinator.render(into: view, history: history, reducedMotion: reducedMotion)
        }
        view.onMouseExited = {
            context.coordinator.hoverX = nil
            context.coordinator.setInspectionIndex(nil)
            context.coordinator.render(into: view, history: history, reducedMotion: reducedMotion)
        }
        view.presentScene(CockpitScene(size: CGSize(width: 900, height: 320)))
        return view
    }

    func updateNSView(_ view: ChartTrackingView, context: Context) {
        context.coordinator.render(into: view, history: history, reducedMotion: reducedMotion)
    }

    @MainActor
    final class Coordinator {
        private let onInspectionIndexChanged: (Int?) -> Void
        var hoverX: CGFloat?
        private var inspectionIndex: Int?

        init(onInspectionIndexChanged: @escaping (Int?) -> Void) {
            self.onInspectionIndexChanged = onInspectionIndexChanged
        }

        func render(into view: SKView, history: [MacroState], reducedMotion: Bool) {
            view.window?.acceptsMouseMovedEvents = true
            let scene = (view.scene as? CockpitScene) ?? CockpitScene(size: view.bounds.size)
            scene.size = view.bounds.size == .zero ? CGSize(width: 900, height: 320) : view.bounds.size
            scene.render(history: history, reducedMotion: reducedMotion, hoverX: hoverX)
            if view.scene !== scene {
                view.presentScene(scene)
            }
        }

        func updateInspectionIndex(for x: CGFloat, viewWidth: CGFloat, historyCount: Int) {
            guard historyCount > 0 else {
                setInspectionIndex(nil)
                return
            }
            let frameMinX: CGFloat = 64
            let frameWidth = max(1, viewWidth - 148)
            let clampedX = min(frameMinX + frameWidth, max(frameMinX, x))
            let progress = (clampedX - frameMinX) / frameWidth
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
    private var chartTrackingArea: NSTrackingArea?

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
