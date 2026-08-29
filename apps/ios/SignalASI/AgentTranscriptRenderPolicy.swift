import CryptoKit
import Foundation

struct AgentTranscriptRenderDiff: Codable, Equatable {
  var reset: Bool
  var replacementIndices: [Int]
  var appendFromIndex: Int
}

enum AgentTranscriptRenderPolicy {
  static func identity(_ entry: AgentTranscriptEntry) -> String {
    entry.dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(entry.id)
  }

  static func signature(_ entry: AgentTranscriptEntry) -> Int {
    var fields = [
      entry.role.rawValue,
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
        index >= renderedIds.count || signatureReplacements.contains(index) else {
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
