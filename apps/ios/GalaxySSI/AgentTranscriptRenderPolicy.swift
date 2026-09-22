import CryptoKit
import Foundation

struct AgentTranscriptRenderDiff: Codable, Equatable {
  var reset: Bool
  var replacementIndices: [Int]
  var appendFromIndex: Int
}

enum AgentProcessClockPolicy {
  static func sameTurn(_ process: AgentTranscriptEntry, _ candidate: AgentTranscriptEntry) -> Bool {
    guard process.conversationId == candidate.conversationId else { return false }
    if !process.turnId.isBlank { return process.turnId == candidate.turnId }
    if !process.taskId.isBlank { return process.taskId == candidate.taskId }
    return false
  }

  static func finalReplyTimestamp(
    for process: AgentTranscriptEntry,
    in entries: [AgentTranscriptEntry]
  ) -> Int64? {
    entries
      .filter { $0.role == .assistant && !AgentTranscriptRenderPolicy.isLiveStream($0) && sameTurn(process, $0) }
      .map(\.timestampMillis)
      .max()
  }
}

final class AgentProcessClock {
  let startedAtMillis: Int64
  private(set) var completedAtMillis: Int64?

  init(startedAtMillis: Int64, completedAtMillis: Int64? = nil) {
    self.startedAtMillis = startedAtMillis
    self.completedAtMillis = completedAtMillis.map { max($0, startedAtMillis) }
  }

  func observe(completedAtMillis: Int64?) {
    guard self.completedAtMillis == nil, let completedAtMillis else { return }
    self.completedAtMillis = max(completedAtMillis, startedAtMillis)
  }

  func elapsed(at nowMillis: Int64) -> Int64 {
    max(0, (completedAtMillis ?? nowMillis) - startedAtMillis)
  }
}

enum AgentTranscriptRenderPolicy {
  static func identity(_ entry: AgentTranscriptEntry) -> String {
    entry.dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(entry.id)
  }

  static func signature(_ entry: AgentTranscriptEntry) -> Int {
    var fields = [
      entry.role.rawValue,
      String(entry.id.hasPrefix("agent-stream-preview-")),
      entry.turnId,
      entry.taskId,
      entry.textSha256.ifBlank(entry.text),
      String(entry.text.count),
      String(entry.textChunkCount),
      String(entry.textLength),
      entry.richOutputSha256.ifBlank(entry.richOutputJson),
      String(entry.richOutputJson.count),
      String(entry.richOutputChunkCount),
      String(entry.richOutputLength),
      entry.sourceConversationId,
      entry.sourceConversationTitle,
      entry.sourceEntryId
    ]
    if entry.role != .assistant {
      fields.insert(String(entry.timestampMillis), at: 1)
    }
    return stableSignature(fields)
  }

  static func isLiveStream(_ entry: AgentTranscriptEntry) -> Bool {
    entry.role == .assistant && entry.id.hasPrefix("agent-stream-")
  }

  static func processGroupSignatures(_ entries: [AgentTranscriptEntry]) -> [String: Int] {
    let finalReplies = Dictionary(grouping: entries.filter {
      $0.role == .assistant && !isLiveStream($0)
    }) {
      AgentTranscriptPresentationPolicy.processGroupKey($0)
    }
    return Dictionary(uniqueKeysWithValues: Dictionary(grouping: entries.filter { $0.role == .process }) {
      AgentTranscriptPresentationPolicy.processGroupKey($0)
    }.map { key, groupEntries in
      let visibleNarration = AgentTranscriptPresentationPolicy.narrationSegments(
        groupEntries
          .sorted { $0.timestampMillis < $1.timestampMillis }
          .uniquedByProcessNarrationIdentity()
      ).flatMap(\.entries)
      let narrationSignature = visibleNarration.reduce(1) { result, entry in
        31 &* result &+ sourceProcessSignature(entry)
      }
      let signature = (finalReplies[key] ?? []).reduce(narrationSignature) { result, entry in
        31 &* result &+ stableSignature([identity(entry), String(entry.timestampMillis)])
      }
      return (key, signature)
    })
  }

  private static func sourceProcessSignature(_ entry: AgentTranscriptEntry) -> Int {
    stableSignature([
      AgentTranscriptPresentationPolicy.processNarrationIdentity(entry.text),
      entry.richOutputJson,
      entry.textSha256,
      entry.richOutputSha256
    ])
  }

  private static func stableSignature(_ fields: [String]) -> Int {
    let hash = Data(SHA256.hash(data: Data(fields.joined(separator: "\u{001f}").utf8)))
    let value = hash.prefix(8).reduce(UInt64(0)) { partial, byte in
      (partial << 8) | UInt64(byte)
    }
    return Int(truncatingIfNeeded: value)
  }

  static func diff(
    renderedIds: [String],
    renderedSignatures: [String: Int],
    incoming: [AgentTranscriptEntry]
  ) -> AgentTranscriptRenderDiff {
    let incomingIds = incoming.map(identity)
    let hasStablePrefix = renderedIds.count <= incomingIds.count &&
      Array(incomingIds.prefix(renderedIds.count)) == renderedIds
    guard hasStablePrefix else {
      return AgentTranscriptRenderDiff(reset: true, replacementIndices: [], appendFromIndex: 0)
    }
    let signatureReplacements = renderedIds.indices.filter { index in
      let entry = incoming[index]
      return renderedSignatures[identity(entry)] != signature(entry)
    }
    let changedAssistantGroups = Set(incoming.enumerated().compactMap { index, entry -> String? in
      guard entry.role == .assistant,
        index >= renderedIds.count ||
          (!isLiveStream(entry) && signatureReplacements.contains(index)) else {
        return nil
      }
      return AgentTranscriptPresentationPolicy.processGroupKey(entry)
    })
    let processCompletionReplacements = renderedIds.indices.filter { index in
      let entry = incoming[index]
      return entry.role == .process &&
        changedAssistantGroups.contains(AgentTranscriptPresentationPolicy.processGroupKey(entry))
    }
    let replacements = Array(Set(signatureReplacements + processCompletionReplacements)).sorted()
    return AgentTranscriptRenderDiff(
      reset: false,
      replacementIndices: replacements,
      appendFromIndex: renderedIds.count
    )
  }
}

private extension Array where Element == AgentTranscriptEntry {
  func uniquedByProcessNarrationIdentity() -> [AgentTranscriptEntry] {
    var seen = Set<String>()
    return filter {
      seen.insert(AgentTranscriptPresentationPolicy.processNarrationIdentity($0.text)).inserted
    }
  }
}
