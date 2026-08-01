import CryptoKit
import Foundation

struct AgentTranscriptRenderDiff: Codable, Equatable {
  var reset: Bool
  var replacementIndices: [Int]
  var appendFromIndex: Int
}

enum AgentTranscriptRenderPolicy {
  static func signature(_ entry: AgentTranscriptEntry) -> Int {
    let fields = [
      entry.id,
      entry.role.rawValue,
      entry.text,
      String(entry.timestampMillis),
      entry.dedupeKey,
      entry.conversationId,
      entry.turnId,
      entry.taskId,
      entry.richOutputJson,
      entry.sourceConversationId,
      entry.sourceConversationTitle,
      entry.sourceEntryId
    ]
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
    let incomingIds = incoming.map(\.id)
    let hasStablePrefix = renderedIds.count <= incomingIds.count &&
      Array(incomingIds.prefix(renderedIds.count)) == renderedIds
    guard hasStablePrefix else {
      return AgentTranscriptRenderDiff(reset: true, replacementIndices: [], appendFromIndex: 0)
    }
    let signatureReplacements = renderedIds.indices.filter { index in
      let entry = incoming[index]
      return renderedSignatures[entry.id] != signature(entry)
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
