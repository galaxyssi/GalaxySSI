import CryptoKit
import Foundation

protocol VoiceExecutionRecordPersistence {
  func save(records: [VoiceExecutionRecord])
}

final class VoiceExecutionLedger {
  static let shared: VoiceExecutionLedger = {
    let persistence = UserDefaultsVoiceExecutionRecordStore()
    return VoiceExecutionLedger(
      initialRecords: persistence.read(),
      persistence: persistence
    )
  }()

  private let persistence: VoiceExecutionRecordPersistence?
  private let clock: () -> Int64
  private let maxRecords: Int
  private let lock = NSLock()
  private var records: [String: VoiceExecutionRecord] = [:]
  private var order: [String] = []

  init(
    initialRecords: [VoiceExecutionRecord] = [],
    persistence: VoiceExecutionRecordPersistence? = nil,
    clock: @escaping () -> Int64 = VoiceExecutionLedger.defaultNowMillis,
    maxRecords: Int = 256
  ) {
    precondition(maxRecords >= 16)
    self.persistence = persistence
    self.clock = clock
    self.maxRecords = maxRecords
    initialRecords
      .sorted { $0.updatedAtMillis < $1.updatedAtMillis }
      .forEach { record in
        let sessionId = record.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionId.isEmpty else { return }
        if records[sessionId] == nil {
          order.append(sessionId)
        }
        records[sessionId] = record
      }
    trimLocked()
  }

  func begin(
    sessionId: String,
    idempotencyKey: String,
    fast: TranscriptHypothesis,
    risk: VoiceCommandRisk
  ) -> VoiceExecutionRecord {
    let cleanSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    precondition(!cleanSessionId.isEmpty)
    return locked {
      if let existing = records[cleanSessionId] {
        return existing
      }
      let record = VoiceExecutionRecord(
        sessionId: cleanSessionId,
        idempotencyKey: idempotencyKey,
        fastTranscriptHash: Self.sha256(fast.text.trimmingCharacters(in: .whitespacesAndNewlines)),
        fastRevision: fast.revision,
        risk: risk,
        updatedAtMillis: clock()
      )
      records[cleanSessionId] = record
      order.append(cleanSessionId)
      persistLocked()
      return record
    }
  }

  func snapshot(sessionId: String) -> VoiceExecutionRecord? {
    locked { records[sessionId] }
  }

  func all() -> [VoiceExecutionRecord] {
    locked { order.compactMap { records[$0] } }
  }

  func claimPrimaryDispatch(sessionId: String) -> Bool {
    updateIf(sessionId: sessionId) { record in
      record.primaryDispatchClaimed ? nil : Self.copy(record, primaryDispatchClaimed: true)
    }
  }

  func claimExternalSideEffect(sessionId: String) -> Bool {
    updateIf(sessionId: sessionId) { record in
      record.externalSideEffectCount >= 1 ? nil : Self.copy(record, externalSideEffectCount: 1)
    }
  }

  func claimAgentRun(sessionId: String) -> Bool {
    updateIf(sessionId: sessionId) { record in
      record.agentRunCount >= 1 ? nil : Self.copy(record, agentRunCount: 1)
    }
  }

  func claimTtsCorrection(sessionId: String) -> Bool {
    updateIf(sessionId: sessionId) { record in
      record.ttsCorrectionCount >= 1 ? nil : Self.copy(record, ttsCorrectionCount: 1)
    }
  }

  func acceptCorrectionRevision(sessionId: String, revision: Int) -> Bool {
    updateIf(sessionId: sessionId) { record in
      revision <= record.highestCorrectionRevision ? nil : Self.copy(record, highestCorrectionRevision: revision)
    }
  }

  func markUserEdited(sessionId: String) -> Bool {
    updateIf(sessionId: sessionId) { record in
      record.userEdited ? nil : Self.copy(record, userEdited: true)
    }
  }

  func remove(sessionId: String) {
    locked {
      if records.removeValue(forKey: sessionId) != nil {
        order.removeAll { $0 == sessionId }
        persistLocked()
      }
    }
  }

  func clear() {
    locked {
      guard !records.isEmpty else { return }
      records.removeAll()
      order.removeAll()
      persistLocked()
    }
  }

  private func updateIf(
    sessionId: String,
    transform: (VoiceExecutionRecord) -> VoiceExecutionRecord?
  ) -> Bool {
    locked {
      guard let current = records[sessionId],
            var updated = transform(current) else {
        return false
      }
      updated.updatedAtMillis = clock()
      records[sessionId] = updated
      persistLocked()
      return true
    }
  }

  private func persistLocked() {
    trimLocked()
    persistence?.save(records: order.compactMap { records[$0] })
  }

  private func trimLocked() {
    while order.count > maxRecords {
      let removed = order.removeFirst()
      records.removeValue(forKey: removed)
    }
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  private static func copy(
    _ record: VoiceExecutionRecord,
    primaryDispatchClaimed: Bool? = nil,
    externalSideEffectCount: Int? = nil,
    agentRunCount: Int? = nil,
    ttsCorrectionCount: Int? = nil,
    highestCorrectionRevision: Int? = nil,
    userEdited: Bool? = nil
  ) -> VoiceExecutionRecord {
    VoiceExecutionRecord(
      sessionId: record.sessionId,
      idempotencyKey: record.idempotencyKey,
      fastTranscriptHash: record.fastTranscriptHash,
      fastRevision: record.fastRevision,
      risk: record.risk,
      primaryDispatchClaimed: primaryDispatchClaimed ?? record.primaryDispatchClaimed,
      externalSideEffectCount: externalSideEffectCount ?? record.externalSideEffectCount,
      agentRunCount: agentRunCount ?? record.agentRunCount,
      ttsCorrectionCount: ttsCorrectionCount ?? record.ttsCorrectionCount,
      highestCorrectionRevision: highestCorrectionRevision ?? record.highestCorrectionRevision,
      userEdited: userEdited ?? record.userEdited,
      updatedAtMillis: record.updatedAtMillis
    )
  }

  private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private static func defaultNowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }
}

enum VoiceExecutionLedgerBridge {
  @discardableResult
  static func register(
    sessionId: String,
    text: String,
    correctionReview: VoiceTranscriptCorrectionReview?,
    risk: VoiceCommandRisk
  ) -> String {
    let cleanSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(correctionReview?.sessionId ?? "")
      .ifBlank("ios-voice-\(UUID().uuidString.lowercased())")
    let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanSessionId.isEmpty, !cleanText.isEmpty else { return "" }
    let fastText = (correctionReview?.fastText ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(cleanText)
    _ = VoiceExecutionLedger.shared.begin(
      sessionId: cleanSessionId,
      idempotencyKey: "\(cleanSessionId):primary-dispatch",
      fast: TranscriptHypothesis(
        text: fastText,
        revision: 1,
        provider: correctionReview == nil ? "ios_speech" : "whisper.cpp",
        modelProfileId: correctionReview?.modelProfileId ?? "",
        transcriptId: cleanSessionId,
        isFinal: true
      ),
      risk: risk
    )
    if let correctionReview {
      _ = VoiceExecutionLedger.shared.acceptCorrectionRevision(
        sessionId: cleanSessionId,
        revision: correctionReview.revision
      )
    }
    return cleanSessionId
  }

  static func claimPrimaryDispatch(sessionId: String) -> Bool {
    let cleanSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanSessionId.isEmpty else { return true }
    return VoiceExecutionLedger.shared.claimPrimaryDispatch(sessionId: cleanSessionId)
  }

  static func markUserEdited(sessionId: String) {
    let cleanSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanSessionId.isEmpty else { return }
    _ = VoiceExecutionLedger.shared.markUserEdited(sessionId: cleanSessionId)
  }

  static func recordRoute(sessionId: String, decision: VoiceRouteDecision) {
    let cleanSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanSessionId.isEmpty else { return }
    switch decision.kind {
    case .localAction:
      _ = VoiceExecutionLedger.shared.claimExternalSideEffect(sessionId: cleanSessionId)
    case .remoteAgent:
      _ = VoiceExecutionLedger.shared.claimAgentRun(sessionId: cleanSessionId)
    case .cloudModel:
      break
    }
  }
}
