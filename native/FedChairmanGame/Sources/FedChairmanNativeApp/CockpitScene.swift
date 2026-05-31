import FedChairmanCore
import SpriteKit

final class CockpitScene: SKScene {
    private let gridNode = SKNode()
    private let pathNode = SKShapeNode()
    private var pulseNode = SKShapeNode()
    private let yMax = 10.0

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        addChild(gridNode)
        addChild(pathNode)
        addChild(pulseNode)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func render(history: [MacroState], reducedMotion: Bool, hoverX: CGFloat? = nil) {
        removeAllChildren()
        addInstrumentPlate()
        let frame = chartFrame
        addGrid(in: frame)
        addBands()
        addAxisLabels(in: frame)
        addLegend()
        addSeries(history: history, keyPath: \.inflation, label: "Inflation", color: SKColor.systemOrange)
        addSeries(history: history, keyPath: \.unemployment, label: "Unemployment", color: SKColor.systemBlue)
        addSeries(history: history, keyPath: \.fedFundsRate, label: "Fed funds", color: SKColor.systemGreen)
        addLatestReadout(history: history)
        addHoverReadout(history: history, hoverX: hoverX, in: frame)
        if !reducedMotion {
            addPulse()
        }
    }

    private var chartFrame: CGRect {
        CGRect(x: 64, y: 48, width: max(1, size.width - 148), height: max(1, size.height - 102))
    }

    private func addInstrumentPlate() {
        let plate = SKShapeNode(rect: CGRect(x: 16, y: 12, width: max(1, size.width - 32), height: max(1, size.height - 24)), cornerRadius: 14)
        plate.fillColor = SKColor.black.withAlphaComponent(0.1)
        plate.strokeColor = SKColor.white.withAlphaComponent(0.08)
        plate.lineWidth = 1
        addChild(plate)
    }

    private func addGrid(in frame: CGRect) {
        let border = SKShapeNode(rect: frame, cornerRadius: 8)
        border.strokeColor = SKColor.white.withAlphaComponent(0.28)
        border.lineWidth = 1
        border.fillColor = SKColor.black.withAlphaComponent(0.08)
        addChild(border)

        for index in 0 ... 4 {
            let y = frame.minY + frame.height * CGFloat(index) / 4
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: frame.minX, y: y))
            path.addLine(to: CGPoint(x: frame.maxX, y: y))
            line.path = path
            line.strokeColor = SKColor.white.withAlphaComponent(index == 0 ? 0.32 : 0.16)
            line.lineWidth = 1
            addChild(line)
        }

        for index in 0 ... 8 {
            let x = frame.minX + frame.width * CGFloat(index) / 8
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: frame.minY))
            path.addLine(to: CGPoint(x: x, y: frame.maxY))
            line.path = path
            line.strokeColor = SKColor.white.withAlphaComponent(index == 0 ? 0.22 : 0.08)
            line.lineWidth = 1
            addChild(line)
        }
    }

    private func addBands() {
        let frame = chartFrame
        let inflationBand = SKShapeNode(rect: CGRect(x: frame.minX, y: yPosition(1.5, in: frame), width: frame.width, height: frame.height * 0.1))
        inflationBand.fillColor = SKColor.systemOrange.withAlphaComponent(0.13)
        inflationBand.strokeColor = .clear
        addChild(inflationBand)

        let laborBand = SKShapeNode(rect: CGRect(x: frame.minX, y: yPosition(4.2, in: frame), width: frame.width, height: frame.height * 0.16))
        laborBand.fillColor = SKColor.systemBlue.withAlphaComponent(0.12)
        laborBand.strokeColor = .clear
        addChild(laborBand)
    }

    private func addAxisLabels(in frame: CGRect) {
        for value in stride(from: 0, through: 10, by: 2) {
            let label = labelNode("\(value)%", size: 11, color: SKColor.white.withAlphaComponent(0.56), alignment: .right)
            label.position = CGPoint(x: frame.minX - 10, y: yPosition(Double(value), in: frame) - 4)
            addChild(label)

            let rightLabel = labelNode("\(value)%", size: 11, color: SKColor.white.withAlphaComponent(0.56), alignment: .left)
            rightLabel.position = CGPoint(x: frame.maxX + 12, y: yPosition(Double(value), in: frame) - 4)
            addChild(rightLabel)
        }

        let left = labelNode("Career start", size: 10, color: SKColor.white.withAlphaComponent(0.45), alignment: .left)
        left.position = CGPoint(x: frame.minX, y: frame.minY - 24)
        addChild(left)
        let right = labelNode("Latest quarter", size: 10, color: SKColor.white.withAlphaComponent(0.58), alignment: .right)
        right.position = CGPoint(x: frame.maxX, y: frame.minY - 24)
        addChild(right)
    }

    private func addLegend() {
        let items: [(String, SKColor)] = [
            ("Inflation", .systemOrange),
            ("Unemployment", .systemBlue),
            ("Fed funds", .systemGreen),
        ]
        for (index, item) in items.enumerated() {
            let x = size.width - 292 + CGFloat(index) * 96
            let y = size.height - 24
            let swatch = SKShapeNode(circleOfRadius: 4)
            swatch.position = CGPoint(x: x, y: y + 3)
            swatch.fillColor = item.1
            swatch.strokeColor = SKColor.white.withAlphaComponent(0.75)
            swatch.lineWidth = 1
            addChild(swatch)

            let label = labelNode(item.0, size: 10, color: SKColor.white.withAlphaComponent(0.72), alignment: .left)
            label.position = CGPoint(x: x + 10, y: y)
            addChild(label)
        }
    }

    private func addSeries(history: [MacroState], keyPath: KeyPath<MacroState, Double>, label _: String, color: SKColor) {
        guard !history.isEmpty else {
            return
        }
        let frame = chartFrame
        let points = history.enumerated().map { index, state in
            let x = frame.minX + frame.width * CGFloat(index) / CGFloat(max(1, history.count - 1))
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
        line.lineWidth = 4
        line.lineCap = .round
        addChild(line)
        for point in points {
            let pip = SKShapeNode(circleOfRadius: 4)
            pip.position = point
            pip.fillColor = color
            pip.strokeColor = SKColor.white.withAlphaComponent(0.85)
            pip.lineWidth = 1
            addChild(pip)
        }
        if let latest = points.last {
            let latestPip = SKShapeNode(circleOfRadius: 6)
            latestPip.position = latest
            latestPip.fillColor = color
            latestPip.strokeColor = SKColor.white.withAlphaComponent(0.95)
            latestPip.lineWidth = 2
            addChild(latestPip)
        }
    }

    private func addLatestReadout(history: [MacroState]) {
        guard let latest = history.last else {
            return
        }
        let readout = [
            "Latest",
            "INF \(String(format: "%.2f", latest.inflation))%",
            "U \(String(format: "%.2f", latest.unemployment))%",
            "FFR \(String(format: "%.2f", latest.fedFundsRate))%",
        ].joined(separator: "  ")
        let label = labelNode(readout, size: 11, color: SKColor.white.withAlphaComponent(0.72), alignment: .left)
        label.position = CGPoint(x: chartFrame.minX, y: size.height - 24)
        addChild(label)
    }

    private func addHoverReadout(history: [MacroState], hoverX: CGFloat?, in frame: CGRect) {
        guard let hoverX, !history.isEmpty else {
            return
        }
        let x = min(frame.maxX, max(frame.minX, hoverX))
        let progress = (x - frame.minX) / max(1, frame.width)
        let index = min(history.count - 1, max(0, Int(round(progress * CGFloat(max(1, history.count - 1))))))
        let state = history[index]
        let pointX = frame.minX + frame.width * CGFloat(index) / CGFloat(max(1, history.count - 1))

        let path = CGMutablePath()
        path.move(to: CGPoint(x: pointX, y: frame.minY))
        path.addLine(to: CGPoint(x: pointX, y: frame.maxY))
        let marker = SKShapeNode(path: path)
        marker.strokeColor = SKColor.white.withAlphaComponent(0.58)
        marker.lineWidth = 1.5
        addChild(marker)

        let readoutRect = CGRect(
            x: min(frame.maxX - 214, max(frame.minX + 8, pointX + 14)),
            y: frame.maxY - 92,
            width: 206,
            height: 74,
        )
        let plate = SKShapeNode(rect: readoutRect, cornerRadius: 8)
        plate.fillColor = SKColor(calibratedRed: 0.04, green: 0.032, blue: 0.025, alpha: 0.96)
        plate.strokeColor = SKColor(calibratedRed: 0.72, green: 0.46, blue: 0.22, alpha: 0.62)
        plate.lineWidth = 1
        addChild(plate)

        let quarterLabel = index == 0 ? "Career start" : "Career Q\(index)"
        let rows = [
            quarterLabel,
            "INF \(String(format: "%.2f", state.inflation))%    U \(String(format: "%.2f", state.unemployment))%",
            "FFR \(String(format: "%.2f", state.fedFundsRate))%    CRED \(String(format: "%.0f", state.credibility))",
        ]
        for (rowIndex, row) in rows.enumerated() {
            let label = labelNode(row, size: rowIndex == 0 ? 12 : 11, color: rowIndex == 0 ? .systemOrange : SKColor.white.withAlphaComponent(0.82), alignment: .left)
            label.position = CGPoint(x: readoutRect.minX + 12, y: readoutRect.maxY - 22 - CGFloat(rowIndex * 20))
            addChild(label)
        }
    }

    private func addPulse() {
        let pulse = SKShapeNode(rectOf: CGSize(width: size.width - 48, height: size.height - 38), cornerRadius: 12)
        pulse.position = CGPoint(x: size.width / 2, y: size.height / 2)
        pulse.strokeColor = SKColor.systemGreen.withAlphaComponent(0.24)
        pulse.lineWidth = 3
        pulse.fillColor = .clear
        pulse.run(.sequence([
            .group([.fadeOut(withDuration: 0.42), .scale(to: 1.025, duration: 0.42)]),
            .removeFromParent(),
        ]))
        addChild(pulse)
    }

    private func yPosition(_ value: Double, in frame: CGRect) -> CGFloat {
        frame.minY + frame.height * CGFloat(min(yMax, max(0, value)) / yMax)
    }

    private func labelNode(_ text: String, size: CGFloat, color: SKColor, alignment: SKLabelHorizontalAlignmentMode) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "SF Pro Rounded")
        label.text = text
        label.fontSize = size
        label.fontColor = color
        label.horizontalAlignmentMode = alignment
        label.verticalAlignmentMode = .baseline
        return label
    }
}
