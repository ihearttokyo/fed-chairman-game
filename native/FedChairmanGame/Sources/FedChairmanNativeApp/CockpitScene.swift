import FedChairmanCore
import SpriteKit

final class CockpitScene: SKScene {
    private var yMin = 0.0
    private var yMax = 10.0
    private let staticLayer = SKNode()
    private let hoverLayer = SKNode()
    private var lastRenderSignature: RenderSignature?
    private var lastHoverSignature: HoverSignature?

    private struct RenderSignature: Equatable {
        let historyCount: Int
        let historyDigest: Int
        let frameWidth: Int
        let frameHeight: Int
        let reducedMotion: Bool
        let inflationUpperBound: Int
    }

    private struct HoverSignature: Equatable {
        let hoverIndex: Int?
        let frameWidth: Int
        let frameHeight: Int
    }

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        addChild(staticLayer)
        addChild(hoverLayer)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func render(history: [MacroState], reducedMotion: Bool, inflationUpperBound: Double = 4.0, hoverIndex: Int? = nil) {
        let frame = chartFrame
        let signature = RenderSignature(
            historyCount: history.count,
            historyDigest: Self.historyDigest(for: history),
            frameWidth: Int(frame.width.rounded()),
            frameHeight: Int(frame.height.rounded()),
            reducedMotion: reducedMotion,
            inflationUpperBound: Self.quantized(inflationUpperBound),
        )

        if signature != lastRenderSignature {
            staticLayer.removeAllChildren()
            configureDomain(for: history)
            addGrid(in: frame, to: staticLayer)
            addBands(in: frame, inflationUpperBound: inflationUpperBound, to: staticLayer)
            addAxisLabels(in: frame, to: staticLayer)
            addLegend(in: frame, to: staticLayer)
            addSeries(history: history, keyPath: \.inflation, label: "INF", color: SKColor.systemOrange, to: staticLayer)
            addSeries(history: history, keyPath: \.unemployment, label: "U", color: SKColor.systemBlue, to: staticLayer)
            addSeries(history: history, keyPath: \.fedFundsRate, label: "FFR", color: SKColor.systemGreen, to: staticLayer)
            addLatestEndpointLabels(history: history, in: frame, to: staticLayer)
            addLatestReadout(history: history, in: frame, to: staticLayer)
            lastRenderSignature = signature
        }

        let hoverSignature = HoverSignature(
            hoverIndex: hoverIndex,
            frameWidth: Int(frame.width.rounded()),
            frameHeight: Int(frame.height.rounded()),
        )
        if hoverSignature != lastHoverSignature {
            hoverLayer.removeAllChildren()
            addHoverReadout(history: history, hoverIndex: hoverIndex, in: frame)
            lastHoverSignature = hoverSignature
        }
    }

    private static func historyDigest(for history: [MacroState]) -> Int {
        var hasher = Hasher()
        for state in history {
            hasher.combine(state.quarterIndex)
            hasher.combine(state.quartersRemaining)
            hasher.combine(Self.quantized(state.inflation))
            hasher.combine(Self.quantized(state.unemployment))
            hasher.combine(Self.quantized(state.fedFundsRate))
        }
        return hasher.finalize()
    }

    static func chartFrame(for size: CGSize) -> CGRect {
        let horizontalInset: CGFloat = size.width < 720 ? 50 : 62
        let bottomInset: CGFloat = size.height < 130 ? 25 : (size.height < 170 ? 34 : 46)
        let topInset: CGFloat = size.height < 130 ? 25 : (size.height < 170 ? 34 : 50)
        return CGRect(
            x: horizontalInset,
            y: bottomInset,
            width: max(1, size.width - horizontalInset * 2 - 10),
            height: max(1, size.height - bottomInset - topInset),
        )
    }

    private var chartFrame: CGRect {
        Self.chartFrame(for: size)
    }

    private func configureDomain(for _: [MacroState]) {
        yMin = 0
        yMax = 10
    }

    private func addGrid(in frame: CGRect, to layer: SKNode) {
        let plotWash = SKShapeNode(rect: frame, cornerRadius: 6)
        plotWash.fillColor = SKColor.black.withAlphaComponent(0.018)
        plotWash.strokeColor = .clear
        layer.addChild(plotWash)

        for index in 0 ... 4 {
            let y = frame.minY + frame.height * CGFloat(index) / 4
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: frame.minX, y: y))
            path.addLine(to: CGPoint(x: frame.maxX, y: y))
            line.path = path
            line.strokeColor = SKColor.white.withAlphaComponent(index == 0 ? 0.20 : 0.10)
            line.lineWidth = 1
            layer.addChild(line)
        }

        for index in 0 ... 4 {
            let x = frame.minX + frame.width * CGFloat(index) / 4
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: frame.minY))
            path.addLine(to: CGPoint(x: x, y: frame.maxY))
            line.path = path
            line.strokeColor = SKColor.white.withAlphaComponent(index == 0 ? 0.14 : 0.06)
            line.lineWidth = 1
            layer.addChild(line)
        }
    }

    private func addBands(in frame: CGRect, inflationUpperBound: Double, to layer: SKNode) {
        let inflationBand = SKShapeNode(rect: bandRect(from: 1.5, to: inflationUpperBound, in: frame))
        inflationBand.fillColor = SKColor.systemOrange.withAlphaComponent(0.075)
        inflationBand.strokeColor = .clear
        layer.addChild(inflationBand)

        let laborBand = SKShapeNode(rect: bandRect(from: 4.2, to: 5.8, in: frame))
        laborBand.fillColor = SKColor.systemBlue.withAlphaComponent(0.065)
        laborBand.strokeColor = .clear
        layer.addChild(laborBand)
    }

    private func addAxisLabels(in frame: CGRect, to layer: SKNode) {
        let tickStep = (yMax - yMin) / 4
        for index in 0 ... 4 {
            let value = yMin + tickStep * Double(index)
            let label = labelNode(String(format: "%.0f%%", value), size: 10, color: SKColor.white.withAlphaComponent(0.50), alignment: .right)
            label.position = CGPoint(x: frame.minX - 12, y: yPosition(Double(value), in: frame) - 4)
            layer.addChild(label)
        }

        let axisTicks = [0, 4, 8, 12, 16]
        for tick in axisTicks {
            let alignment: SKLabelHorizontalAlignmentMode = tick == 0 ? .left : (tick == 16 ? .right : .center)
            let label = labelNode("Q\(tick)", size: 10, color: SKColor.white.withAlphaComponent(0.48), alignment: alignment)
            label.position = CGPoint(x: xPosition(index: tick, count: 17, in: frame), y: frame.minY - 23)
            layer.addChild(label)
        }
    }

    private func addLegend(in frame: CGRect, to layer: SKNode) {
        let compact = size.width < 640
        let items: [(String, SKColor)] = [
            (compact ? "INF" : "Inflation", .systemOrange),
            (compact ? "U" : "Unemployment", .systemBlue),
            (compact ? "FFR" : "Fed funds", .systemGreen),
        ]
        for (index, item) in items.enumerated() {
            let itemSpacing: CGFloat = compact ? 54 : 96
            let x = max(frame.minX, frame.maxX - itemSpacing * 3) + CGFloat(index) * itemSpacing
            let y = min(size.height - 18, frame.maxY + 27)
            let swatch = SKShapeNode(circleOfRadius: 4)
            swatch.position = CGPoint(x: x, y: y + 3)
            swatch.fillColor = item.1
            swatch.strokeColor = SKColor.white.withAlphaComponent(0.75)
            swatch.lineWidth = 1
            layer.addChild(swatch)

            let label = labelNode(item.0, size: 10, color: SKColor.white.withAlphaComponent(0.72), alignment: .left)
            label.position = CGPoint(x: x + 10, y: y)
            layer.addChild(label)
        }
    }

    private func addSeries(history: [MacroState], keyPath: KeyPath<MacroState, Double>, label _: String, color: SKColor, to layer: SKNode) {
        guard !history.isEmpty else {
            return
        }
        let frame = chartFrame
        let points = history.enumerated().map { index, state in
            let x = xPosition(index: index, count: history.count, in: frame)
            let y = yPosition(state[keyPath: keyPath], in: frame)
            return CGPoint(x: x, y: y)
        }
        let path = CGMutablePath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        let line = SKShapeNode(path: path)
        line.strokeColor = color
        line.lineWidth = 3
        line.lineCap = .round
        line.lineJoin = .round
        layer.addChild(line)
        for point in points {
            let pip = SKShapeNode(circleOfRadius: history.count == 1 ? 4.5 : 3.2)
            pip.position = point
            pip.fillColor = color
            pip.strokeColor = SKColor.white.withAlphaComponent(0.70)
            pip.lineWidth = 1
            layer.addChild(pip)
        }
        if let latest = points.last {
            let latestPip = SKShapeNode(circleOfRadius: history.count == 1 ? 6 : 5)
            latestPip.position = latest
            latestPip.fillColor = color
            latestPip.strokeColor = SKColor.white.withAlphaComponent(0.82)
            latestPip.lineWidth = 1.5
            layer.addChild(latestPip)
        }
    }

    private func addLatestEndpointLabels(history: [MacroState], in frame: CGRect, to layer: SKNode) {
        guard let latest = history.last, history.count >= 6 else {
            return
        }
        let labels: [(String, Double, SKColor, CGFloat)] = [
            ("U", latest.unemployment, .systemBlue, frame.maxY - 28),
            ("FFR", latest.fedFundsRate, .systemGreen, frame.midY + 2),
            ("INF", latest.inflation, .systemOrange, frame.minY + 24),
        ]
        let x = min(frame.maxX - 90, xPosition(index: history.count - 1, count: history.count, in: frame) + 14)
        for (label, value, color, y) in labels {
            let valueLabel = labelNode("\(label) \(String(format: "%.2f", value))%", size: 10, color: color.withAlphaComponent(0.94), alignment: .left)
            valueLabel.position = CGPoint(x: x, y: y)
            layer.addChild(valueLabel)
        }
    }

    private func addLatestReadout(history: [MacroState], in frame: CGRect, to layer: SKNode) {
        guard let latest = history.last else {
            return
        }
        let readout = [
            "Latest",
            "INF \(String(format: "%.2f", latest.inflation))%",
            "U \(String(format: "%.2f", latest.unemployment))%",
            "FFR \(String(format: "%.2f", latest.fedFundsRate))%",
        ].joined(separator: "  ")
        let label = labelNode(readout, size: 10, color: SKColor.white.withAlphaComponent(0.66), alignment: .left)
        label.position = CGPoint(x: frame.minX, y: min(size.height - 18, frame.maxY + 27))
        layer.addChild(label)
    }

    private func addHoverReadout(history: [MacroState], hoverIndex: Int?, in frame: CGRect) {
        guard let hoverIndex else {
            return
        }
        guard history.indices.contains(hoverIndex) else {
            return
        }
        let state = history[hoverIndex]
        let pointX = xPosition(index: hoverIndex, count: history.count, in: frame)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: pointX, y: frame.minY))
        path.addLine(to: CGPoint(x: pointX, y: frame.maxY))
        let marker = SKShapeNode(path: path)
        marker.strokeColor = SKColor.white.withAlphaComponent(0.40)
        marker.lineWidth = 1
        hoverLayer.addChild(marker)

        let quarterLabel = hoverIndex == 0 ? "Career start" : "Career Q\(hoverIndex)"
        let values = [
            (state.inflation, SKColor.systemOrange),
            (state.unemployment, SKColor.systemBlue),
            (state.fedFundsRate, SKColor.systemGreen),
        ]
        for (value, color) in values {
            let highlight = SKShapeNode(circleOfRadius: 6)
            highlight.position = CGPoint(x: pointX, y: yPosition(value, in: frame))
            highlight.fillColor = color.withAlphaComponent(0.28)
            highlight.strokeColor = SKColor.white.withAlphaComponent(0.78)
            highlight.lineWidth = 1.5
            hoverLayer.addChild(highlight)
        }
        if hoverIndex > 0 {
            let label = labelNode(quarterLabel, size: 10, color: SKColor.white.withAlphaComponent(0.68), alignment: .center)
            label.position = CGPoint(x: pointX, y: frame.minY - 22)
            hoverLayer.addChild(label)
        }
    }

    private func yPosition(_ value: Double, in frame: CGRect) -> CGFloat {
        let clamped = min(yMax, max(yMin, value))
        return frame.minY + frame.height * CGFloat((clamped - yMin) / max(0.01, yMax - yMin))
    }

    private func xPosition(index: Int, count: Int, in frame: CGRect) -> CGFloat {
        if count <= 1 {
            return frame.minX + min(30, max(18, frame.width * 0.035))
        }
        let domainSegments = max(16, count - 1)
        let paddedWidth = max(1, frame.width - 18)
        return frame.minX + 9 + paddedWidth * CGFloat(index) / CGFloat(domainSegments)
    }

    private static func quantized(_ value: Double) -> Int {
        Int((value * 1000).rounded())
    }

    private func bandRect(from lower: Double, to upper: Double, in frame: CGRect) -> CGRect {
        let minY = yPosition(lower, in: frame)
        let maxY = yPosition(upper, in: frame)
        return CGRect(x: frame.minX, y: minY, width: frame.width, height: max(1, maxY - minY))
    }

    private func labelNode(_ text: String, size: CGFloat, color: SKColor, alignment: SKLabelHorizontalAlignmentMode) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: NSFont.systemFont(ofSize: size, weight: .semibold).fontName)
        label.text = text
        label.fontSize = size
        label.fontColor = color
        label.horizontalAlignmentMode = alignment
        label.verticalAlignmentMode = .baseline
        return label
    }
}
