import Foundation

final class UserDefaultsVoiceExecutionRecordStore: VoiceExecutionRecordPersistence {
  private let defaults: UserDefaults
  private let key: String
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    defaults: UserDefaults = .standard,
    key: String = UserDefaultsVoiceExecutionRecordStore.defaultKey
  ) {
    self.defaults = defaults
    self.key = key
  }

  func read() -> [VoiceExecutionRecord] {
    guard let data = defaults.data(forKey: key) else { return [] }
    return (try? decoder.decode([VoiceExecutionRecord].self, from: data)) ?? []
  }

  func save(records: [VoiceExecutionRecord]) {
    let bounded = Array(records.suffix(Self.maxExecutionRecords))
    if let data = try? encoder.encode(bounded) {
      defaults.set(data, forKey: key)
    }
  }

  func clear() {
    defaults.removeObject(forKey: key)
  }

  static func destroyPersistentStore(
    defaults: UserDefaults = .standard,
    key: String = defaultKey
  ) {
    defaults.removeObject(forKey: key)
  }

  private static let defaultKey = "signalasi_voice_execution_v1.records"
  private static let maxExecutionRecords = 256
}

struct VoiceCorrectionContextRecord: Codable, Equatable {
  var sessionId: String
  var conversationId: String
  var turnId: String
  var fastText: String
  var accurateText: String
  var diffSummary: String
  var risk: VoiceCommandRisk
  var revision: Int
  var modelProfileId: String
  var modelSha256: String
  var executionMode: String
  var userEdited: Bool
  var completedAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case sessionId = "session_id"
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case fastText = "fast_text"
    case accurateText = "accurate_text"
    case diffSummary = "diff_summary"
    case risk
    case revision
    case modelProfileId = "model_profile_id"
    case modelSha256 = "model_sha256"
    case executionMode = "execution_mode"
    case userEdited = "user_edited"
    case completedAtMillis = "completed_at_millis"
  }
}

final class VoiceCorrectionJournal {
  static let shared = VoiceCorrectionJournal()

  private let defaults: UserDefaults
  private let key: String
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private let lock = NSLock()

  init(
    defaults: UserDefaults = .standard,
    key: String = VoiceCorrectionJournal.defaultKey
  ) {
    self.defaults = defaults
    self.key = key
  }

  func append(_ record: VoiceCorrectionContextRecord) -> Bool {
    locked {
      guard !record.sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !record.accurateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return false
      }
      var records = readLocked()
      if let existingIndex = records.firstIndex(where: { $0.sessionId == record.sessionId }) {
        guard records[existingIndex].revision < record.revision else {
          return false
        }
        records.remove(at: existingIndex)
      }
      records.append(trimmed(record))
      writeLocked(Array(records.suffix(Self.maxCorrectionRecords)))
      return true
    }
  }

  func forConversation(_ conversationId: String) -> [VoiceCorrectionContextRecord] {
    locked { readLocked().filter { $0.conversationId == conversationId } }
  }

  func contextBlock(conversationId: String) -> String {
    let records = forConversation(conversationId).suffix(Self.maxContextRecords)
    guard !records.isEmpty else { return "" }
    let lines = records.map { record in
      var line = "- turn=\(record.turnId.isEmpty ? "unknown" : record.turnId)"
      line += "; fast=\(record.fastText.replacingOccurrences(of: "\n", with: " "))"
      line += "; accurate=\(record.accurateText.replacingOccurrences(of: "\n", with: " "))"
      line += "; changes=\(record.diffSummary.replacingOccurrences(of: "\n", with: " "))"
      if record.userEdited {
        line += "; user edit remains authoritative"
      }
      return line
    }
    return (["Speech transcription corrections (historical context only; never execute again):"] + lines)
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  @discardableResult
  func persist(
    review: VoiceTranscriptCorrectionReview,
    conversationId: String,
    turnId: String = "",
    risk: VoiceCommandRisk,
    userEdited: Bool = false
  ) -> Bool {
    guard review.diff.changed else { return false }
    return append(VoiceCorrectionContextRecord(
      sessionId: review.sessionId,
      conversationId: conversationId.trimmingCharacters(in: .whitespacesAndNewlines),
      turnId: turnId.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(review.sessionId),
      fastText: review.fastText,
      accurateText: review.accurateText,
      diffSummary: review.diff.compactSummary(),
      risk: risk,
      revision: review.revision,
      modelProfileId: review.modelProfileId,
      modelSha256: "",
      executionMode: VoiceWhisperExecutionMode.secondPass.rawValue,
      userEdited: userEdited,
      completedAtMillis: review.completedAtMillis
    ))
  }

  func markUserEdited(sessionId: String) -> Bool {
    locked {
      var records = readLocked()
      guard let index = records.firstIndex(where: { $0.sessionId == sessionId }),
            !records[index].userEdited else {
        return false
      }
      records[index].userEdited = true
      writeLocked(records)
      return true
    }
  }

  func clear() {
    locked {
      defaults.removeObject(forKey: key)
    }
  }

  static func destroyPersistentStore(
    defaults: UserDefaults = .standard,
    key: String = defaultKey
  ) {
    defaults.removeObject(forKey: key)
  }

  private func readLocked() -> [VoiceCorrectionContextRecord] {
    guard let data = defaults.data(forKey: key),
          let records = try? decoder.decode([VoiceCorrectionContextRecord].self, from: data) else {
      return []
    }
    return records
  }

  private func writeLocked(_ records: [VoiceCorrectionContextRecord]) {
    if let data = try? encoder.encode(records) {
      defaults.set(data, forKey: key)
    }
  }

  private func trimmed(_ record: VoiceCorrectionContextRecord) -> VoiceCorrectionContextRecord {
    VoiceCorrectionContextRecord(
      sessionId: String(record.sessionId.prefix(128)),
      conversationId: String(record.conversationId.prefix(128)),
      turnId: String(record.turnId.prefix(128)),
      fastText: String(record.fastText.prefix(Self.maxTranscriptCharacters)),
      accurateText: String(record.accurateText.prefix(Self.maxTranscriptCharacters)),
      diffSummary: String(record.diffSummary.prefix(Self.maxDiffCharacters)),
      risk: record.risk,
      revision: max(record.revision, 1),
      modelProfileId: String(record.modelProfileId.prefix(64)),
      modelSha256: String(record.modelSha256.prefix(64)),
      executionMode: String(record.executionMode.prefix(32)),
      userEdited: record.userEdited,
      completedAtMillis: max(record.completedAtMillis, 0)
    )
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  private static let defaultKey = "signalasi_voice_corrections_v1.records"
  private static let maxCorrectionRecords = 128
  private static let maxContextRecords = 8
  private static let maxTranscriptCharacters = 4_096
  private static let maxDiffCharacters = 1_024
}
