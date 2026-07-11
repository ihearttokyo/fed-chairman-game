import CryptoKit
import Foundation

public struct SaveFileEnvelope: Codable, Equatable, Sendable {
    public var version: Int
    public var payload: GameSession
    public var digest: String
}

public struct SaveFileSummary: Equatable, Sendable {
    public var sessionId: String
    public var seed: String
    public var status: CareerStatus
    public var termNumber: Int
    public var currentTermQuarter: Int
    public var totalCareerQuarters: Int
    public var completedTerms: Int
    public var careerScore: Double
    public var careerGrade: Grade
    public var label: String
}

private let saveFileVersion = 1
private let saveFileNamespace = "fed-chairman-game-save-v1"

private enum CanonicalJSON {
    static func stringify(_ value: Any) -> String {
        if value is NSNull {
            return "null"
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        if let string = value as? String {
            return String(data: try! JSONEncoder().encode(string), encoding: .utf8)!
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let array = value as? [Any] {
            return "[\(array.map { stringify($0) }.joined(separator: ","))]"
        }
        if let dictionary = value as? [String: Any] {
            let fields = dictionary.keys.sorted().map { key in
                "\(stringify(key)):\(stringify(dictionary[key] ?? NSNull()))"
            }
            return "{\(fields.joined(separator: ","))}"
        }
        return "null"
    }
}

private func jsonObject(_ value: some Encodable) throws -> Any {
    let encoder = JSONEncoder()
    encoder.outputFormatting = []
    let data = try encoder.encode(value)
    return try JSONSerialization.jsonObject(with: data)
}

private func sha256Hex(_ input: String) -> String {
    let digest = SHA256.hash(data: Data(input.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

func digestPayload(_ payload: GameSession) throws -> String {
    let canonical = try CanonicalJSON.stringify(jsonObject(payload))
    return sha256Hex("\(saveFileNamespace):\(canonical)")
}

public func recomputeSessionScores(_ session: GameSession) throws -> GameSession {
    let scenario = try getScenario(id: session.scenarioId)
    let completedTerms = session.completedTerms.map { term in
        let score = evaluateScore(history: term.history, scenario: scenario)
        return CompletedTermSummary(
            termNumber: term.termNumber,
            startingState: term.startingState,
            endingState: term.endingState,
            history: term.history,
            decisions: term.decisions,
            traces: term.traces,
            score: score,
            reappointed: score.reappointed,
        )
    }
    let currentTermScore: ScoreState = if session.status == .inProgress || session.status == .notStarted {
        evaluateScore(history: session.history, scenario: scenario, inflationUpperBound: reappointmentInflationUpperBound)
    } else {
        completedTerms.last?.score ?? evaluateScore(history: session.history, scenario: scenario)
    }
    let careerScore = evaluateScore(history: session.careerHistory, scenario: scenario)
    var next = session
    next.completedTerms = completedTerms
    next.score = session.status == .retired ? careerScore : currentTermScore
    next.careerScore = careerScore
    return next
}

public func createSaveFile(session: GameSession) throws -> String {
    let payload = try recomputeSessionScores(session)
    // Save envelope v1 and its digest remain compatible; mechanics versions gate resume behavior separately.
    guard payload.engineModelVersion == GameSession.currentEngineModelVersion else {
        throw NativeEngineError.unsupportedSaveFile
    }
    let envelope = try SaveFileEnvelope(version: saveFileVersion, payload: payload, digest: digestPayload(payload))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try String(data: encoder.encode(envelope), encoding: .utf8) ?? "{}"
}

public func parseSaveFile(_ text: String) throws -> GameSession {
    guard let data = text.data(using: .utf8) else {
        throw NativeEngineError.unsupportedSaveFile
    }
    let envelope = try JSONDecoder().decode(SaveFileEnvelope.self, from: data)
    guard envelope.version == saveFileVersion else {
        throw NativeEngineError.unsupportedSaveFile
    }
    guard try digestPayload(envelope.payload) == envelope.digest else {
        throw NativeEngineError.tamperedSaveFile
    }
    // Verify integrity before reporting an unsupported legacy or future mechanics model.
    guard envelope.payload.engineModelVersion == GameSession.currentEngineModelVersion else {
        throw NativeEngineError.unsupportedSaveFile
    }
    return try recomputeSessionScores(envelope.payload)
}

private func describeStatus(_ session: GameSession) -> String {
    switch session.status {
    case .retired:
        "retired career"
    case .termDebrief:
        "term \(session.termNumber) debrief"
    case .notReappointed:
        "not reappointed"
    case .notStarted:
        "not started"
    case .inProgress:
        "term \(session.termNumber) quarter \(session.currentTermQuarter)"
    }
}

public func summarizeSaveSession(_ session: GameSession) -> SaveFileSummary {
    let label = "\(describeStatus(session)); \(session.totalCareerQuarters) career quarters; career \(session.careerScore.score) (\(session.careerScore.grade.rawValue))"
    return SaveFileSummary(
        sessionId: session.sessionId,
        seed: session.seed,
        status: session.status,
        termNumber: session.termNumber,
        currentTermQuarter: session.currentTermQuarter,
        totalCareerQuarters: session.totalCareerQuarters,
        completedTerms: session.completedTerms.count,
        careerScore: session.careerScore.score,
        careerGrade: session.careerScore.grade,
        label: label,
    )
}

public func inspectSaveFile(_ text: String) throws -> SaveFileSummary {
    try summarizeSaveSession(parseSaveFile(text))
}
