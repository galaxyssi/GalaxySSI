import Foundation

enum AgentFinalResponseIdentity {
  static func dedupeKey(
    turnId: String,
    sourceMessageId: Int64 = 0,
    taskId: String = ""
  ) -> String {
    let identity: String
    if !isBlank(turnId) {
      identity = "turn:\(trim(turnId))"
    } else if sourceMessageId > 0 {
      identity = "source:\(sourceMessageId)"
    } else if !isBlank(taskId) {
      identity = "task:\(trim(taskId))"
    } else {
      return ""
    }
    return "assistant-final:\(identity)"
  }

  static func resolveTurnId(
    explicitTurnId: String,
    taskId: String,
    turnIdForTask: (String) -> String?
  ) -> String {
    let explicit = trim(explicitTurnId)
    if !explicit.isEmpty {
      return explicit
    }
    let cleanTaskId = trim(taskId)
    guard !cleanTaskId.isEmpty else { return "" }
    return trim(turnIdForTask(cleanTaskId) ?? "")
  }

  static func coalesce(_ entries: [AgentTranscriptEntry]) -> [AgentTranscriptEntry] {
    let candidates = entries.filter(isCanonicalFinalCandidate)
    guard candidates.count >= 2 else { return entries }

    let retainedIds = Set(
      Dictionary(grouping: candidates, by: duplicateKey)
        .values
        .compactMap { duplicates in
          duplicates.reduce(nil as AgentTranscriptEntry?) { best, entry in
            guard let best else { return entry }
            return isBetterCanonicalEntry(entry, than: best) ? entry : best
          }?.id
        }
    )

    return entries.filter { entry in
      !isCanonicalFinalCandidate(entry) || retainedIds.contains(entry.id)
    }
  }

  private static func isCanonicalFinalCandidate(_ entry: AgentTranscriptEntry) -> Bool {
    entry.role == .assistant &&
      entry.dedupeKey.hasPrefix("assistant-final:") &&
      !isBlank(entry.taskId) &&
      !isBlank(entry.text)
  }

  private static func duplicateKey(_ entry: AgentTranscriptEntry) -> String {
    [
      entry.conversationId,
      trim(entry.taskId),
      trim(entry.text)
    ].joined(separator: "\u{001f}")
  }

  private static func isBetterCanonicalEntry(
    _ candidate: AgentTranscriptEntry,
    than current: AgentTranscriptEntry
  ) -> Bool {
    let candidateScore = canonicalScore(candidate)
    let currentScore = canonicalScore(current)
    if candidateScore != currentScore {
      return candidateScore.lexicographicallyPrecedes(currentScore) == false
    }
    return false
  }

  private static func canonicalScore(_ entry: AgentTranscriptEntry) -> [Int64] {
    [
      isBlank(entry.turnId) ? 0 : 1,
      isBlank(entry.richOutputJson) ? 0 : 1,
      entry.timestampMillis
    ]
  }

  private static func trim(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isBlank(_ value: String) -> Bool {
    trim(value).isEmpty
  }
}
