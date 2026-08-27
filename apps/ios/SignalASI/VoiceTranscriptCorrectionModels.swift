import Foundation

enum VoiceCommandRisk: String, Codable, CaseIterable, Comparable {
  case conversation = "CONVERSATION"
  case low = "LOW"
  case medium = "MEDIUM"
  case high = "HIGH"
  case critical = "CRITICAL"

  static func < (left: VoiceCommandRisk, right: VoiceCommandRisk) -> Bool {
    left.rank < right.rank
  }

  private var rank: Int {
    switch self {
    case .conversation: return 0
    case .low: return 1
    case .medium: return 2
    case .high: return 3
    case .critical: return 4
    }
  }
}

enum VoiceEntityType: String, Codable, CaseIterable {
  case recipient = "RECIPIENT"
  case phoneNumber = "PHONE_NUMBER"
  case amount = "AMOUNT"
  case dateTime = "DATE_TIME"
  case filePath = "FILE_PATH"
  case application = "APPLICATION"
  case device = "DEVICE"
  case negation = "NEGATION"
  case action = "ACTION"
}

struct VoiceEntity: Codable, Equatable {
  var type: VoiceEntityType
  var value: String
  var canonicalValue: String

  enum CodingKeys: String, CodingKey {
    case type
    case value
    case canonicalValue = "canonical_value"
  }
}

struct VoiceEntityDifference: Codable, Equatable {
  var type: VoiceEntityType
  var fastValues: [String]
  var accurateValues: [String]

  enum CodingKeys: String, CodingKey {
    case type
    case fastValues = "fast_values"
    case accurateValues = "accurate_values"
  }
}

struct TranscriptDiff: Codable, Equatable {
  var fastText: String
  var accurateText: String
  var normalizedFastText: String
  var normalizedAccurateText: String
  var entityDifferences: [VoiceEntityDifference]

  var changed: Bool {
    normalizedFastText != normalizedAccurateText
  }

  var hasCriticalEntityChange: Bool {
    entityDifferences.contains { Self.criticalEntityTypes.contains($0.type) }
  }

  func compactSummary() -> String {
    let summary = entityDifferences.map { difference in
      let fast = difference.fastValues.joined(separator: "|")
      let accurate = difference.accurateValues.joined(separator: "|")
      return "\(difference.type.rawValue.lowercased()): \(fast.isEmpty ? "-" : fast) -> \(accurate.isEmpty ? "-" : accurate)"
    }.joined(separator: "; ")
    return summary.isEmpty ? "transcript wording changed" : summary
  }

  enum CodingKeys: String, CodingKey {
    case fastText = "fast_text"
    case accurateText = "accurate_text"
    case normalizedFastText = "normalized_fast_text"
    case normalizedAccurateText = "normalized_accurate_text"
    case entityDifferences = "entity_differences"
  }

  private static let criticalEntityTypes: Set<VoiceEntityType> = [
    .recipient,
    .phoneNumber,
    .amount,
    .dateTime,
    .filePath,
    .application,
    .device,
    .negation,
    .action,
  ]
}

struct VoiceTranscriptCorrectionReview: Codable, Equatable {
  var sessionId: String
  var diff: TranscriptDiff
  var modelProfileId: String
  var revision: Int
  var completedAtMillis: Int64

  init(
    sessionId: String,
    diff: TranscriptDiff,
    modelProfileId: String = "",
    revision: Int = 1,
    completedAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) {
    self.sessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.diff = diff
    self.modelProfileId = modelProfileId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.revision = max(revision, 1)
    self.completedAtMillis = max(completedAtMillis, 0)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      sessionId: try container.decode(String.self, forKey: .sessionId),
      diff: try container.decode(TranscriptDiff.self, forKey: .diff),
      modelProfileId: try container.decodeIfPresent(String.self, forKey: .modelProfileId) ?? "",
      revision: try container.decodeIfPresent(Int.self, forKey: .revision) ?? 1,
      completedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .completedAtMillis) ?? 0
    )
  }

  var fastText: String { diff.fastText }
  var accurateText: String { diff.accurateText }

  enum CodingKeys: String, CodingKey {
    case sessionId
    case diff
    case modelProfileId
    case revision
    case completedAtMillis
  }
}

struct SignalASIVoiceTranscriptSubmission: Equatable {
  var text: String
  var correctionReview: VoiceTranscriptCorrectionReview?
  var sessionId: String
  var audioData: Data?
  var audioDurationMillis: Int64
  var audioMimeType: String
  var audioFileExtension: String
  var audioSourceURL: URL?

  init(
    text: String,
    correctionReview: VoiceTranscriptCorrectionReview?,
    sessionId: String = "",
    audioData: Data? = nil,
    audioDurationMillis: Int64 = 0,
    audioMimeType: String = "audio/wav",
    audioFileExtension: String = "wav",
    audioSourceURL: URL? = nil
  ) {
    self.text = text
    self.correctionReview = correctionReview
    self.sessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(correctionReview?.sessionId ?? "")
    self.audioData = audioData
    self.audioDurationMillis = max(audioDurationMillis, 0)
    self.audioMimeType = audioMimeType.ifBlank("audio/wav")
    self.audioFileExtension = audioFileExtension.ifBlank("wav")
    self.audioSourceURL = audioSourceURL
  }
}

enum VoiceRiskConfirmationMessageFormatter {
  typealias Localizer = (_ key: String, _ fallback: String) -> String

  static func message(
    text: String,
    riskLabel: String,
    correctionReview: VoiceTranscriptCorrectionReview?,
    localize: Localizer
  ) -> String {
    guard let correctionReview else {
      return String(
        format: localize(
          "signalasi.voice.risk_confirmation_message",
          "Review this %@ risk command before execution:\n\n%@"
        ),
        riskLabel,
        text
      )
    }
    return String(
      format: localize(
        "signalasi.voice.correction_confirmation_comparison_message",
        "Fast transcription:\n%@\n\nAccurate transcription:\n%@\n\nDifferences: %@\nRisk: %@"
      ),
      correctionReview.fastText,
      correctionReview.accurateText,
      differenceSummary(correctionReview.diff, localize: localize),
      riskLabel
    )
  }

  private static func differenceSummary(
    _ diff: TranscriptDiff,
    localize: Localizer
  ) -> String {
    guard !diff.entityDifferences.isEmpty else {
      return localize(
        "signalasi.voice.correction_wording_changed",
        "Transcript wording changed"
      )
    }
    return diff.entityDifferences.map { difference in
      let fast = difference.fastValues.joined(separator: " | ").ifBlank("-")
      let accurate = difference.accurateValues.joined(separator: " | ").ifBlank("-")
      return "\(entityLabel(difference.type, localize: localize)): \(fast) -> \(accurate)"
    }.joined(separator: "\n")
  }

  private static func entityLabel(
    _ type: VoiceEntityType,
    localize: Localizer
  ) -> String {
    switch type {
    case .recipient:
      return localize("signalasi.voice.entity.recipient", "Recipient")
    case .phoneNumber:
      return localize("signalasi.voice.entity.phone_number", "Phone number")
    case .amount:
      return localize("signalasi.voice.entity.amount", "Amount")
    case .dateTime:
      return localize("signalasi.voice.entity.date_time", "Date or time")
    case .filePath:
      return localize("signalasi.voice.entity.file_path", "File path")
    case .application:
      return localize("signalasi.voice.entity.application", "Application")
    case .device:
      return localize("signalasi.voice.entity.device", "Device")
    case .negation:
      return localize("signalasi.voice.entity.negation", "Negation")
    case .action:
      return localize("signalasi.voice.entity.action", "Action")
    }
  }
}

struct EntityConsistencyResult: Codable, Equatable {
  var fastEntities: [VoiceEntity]
  var accurateEntities: [VoiceEntity]
  var differences: [VoiceEntityDifference]

  var consistent: Bool {
    differences.isEmpty
  }

  enum CodingKeys: String, CodingKey {
    case fastEntities = "fast_entities"
    case accurateEntities = "accurate_entities"
    case differences
  }
}

struct VoiceSecondPassTrigger: Codable, Equatable {
  var requested: Bool
  var reasons: Set<String>
}

struct VoiceExecutionRecord: Codable, Equatable {
  var sessionId: String
  var idempotencyKey: String
  var fastTranscriptHash: String
  var fastRevision: Int
  var risk: VoiceCommandRisk
  var primaryDispatchClaimed: Bool
  var externalSideEffectCount: Int
  var agentRunCount: Int
  var ttsCorrectionCount: Int
  var highestCorrectionRevision: Int
  var userEdited: Bool
  var updatedAtMillis: Int64

  init(
    sessionId: String,
    idempotencyKey: String,
    fastTranscriptHash: String,
    fastRevision: Int,
    risk: VoiceCommandRisk,
    primaryDispatchClaimed: Bool = false,
    externalSideEffectCount: Int = 0,
    agentRunCount: Int = 0,
    ttsCorrectionCount: Int = 0,
    highestCorrectionRevision: Int = 0,
    userEdited: Bool = false,
    updatedAtMillis: Int64 = VoiceExecutionRecord.defaultNowMillis()
  ) {
    self.sessionId = sessionId
    self.idempotencyKey = idempotencyKey
    self.fastTranscriptHash = fastTranscriptHash
    self.fastRevision = max(fastRevision, 1)
    self.risk = risk
    self.primaryDispatchClaimed = primaryDispatchClaimed
    self.externalSideEffectCount = min(max(externalSideEffectCount, 0), 1)
    self.agentRunCount = min(max(agentRunCount, 0), 1)
    self.ttsCorrectionCount = min(max(ttsCorrectionCount, 0), 1)
    self.highestCorrectionRevision = max(highestCorrectionRevision, 0)
    self.userEdited = userEdited
    self.updatedAtMillis = max(updatedAtMillis, 0)
  }

  var executionStarted: Bool {
    primaryDispatchClaimed || externalSideEffectCount > 0 || agentRunCount > 0
  }

  enum CodingKeys: String, CodingKey {
    case sessionId = "session_id"
    case idempotencyKey = "idempotency_key"
    case fastTranscriptHash = "fast_transcript_hash"
    case fastRevision = "fast_revision"
    case risk
    case primaryDispatchClaimed = "primary_dispatch_claimed"
    case externalSideEffectCount = "external_side_effect_count"
    case agentRunCount = "agent_run_count"
    case ttsCorrectionCount = "tts_correction_count"
    case highestCorrectionRevision = "highest_correction_revision"
    case userEdited = "user_edited"
    case updatedAtMillis = "updated_at_millis"
  }

  private static func defaultNowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }
}

enum CorrectionDecision: Equatable {
  case noMaterialChange
  case displayOnly(TranscriptDiff)
  case updateFutureContext(TranscriptDiff)
  case warnUser(TranscriptDiff, reason: String)
  case requireConfirmationBeforeExecution(corrected: TranscriptHypothesis, reason: String)
}

protocol TranscriptCorrectionController {
  func compare(
    fast: TranscriptHypothesis,
    accurate: TranscriptHypothesis,
    executionRecord: VoiceExecutionRecord
  ) -> CorrectionDecision
}
