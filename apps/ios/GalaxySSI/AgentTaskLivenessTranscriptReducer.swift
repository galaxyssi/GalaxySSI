import Foundation

enum AgentTaskLivenessTranscriptReducer {
  static func apply(
    _ operations: [AgentTaskLivenessTranscriptOperation],
    to entries: [AgentTranscriptEntry],
    idGenerator: () -> String = { UUID().uuidString }
  ) -> [AgentTranscriptEntry] {
    var output = entries
    for operation in operations {
      switch operation.kind {
      case .delete:
        guard !clean(operation.dedupeKey).isEmpty else { continue }
        if let index = output.firstIndex(where: {
          $0.conversationId == operation.conversationId &&
            $0.dedupeKey == clean(operation.dedupeKey)
        }) {
          output.remove(at: index)
        }
      case .append:
        guard let entry = makeEntry(operation: operation, idGenerator: idGenerator) else {
          continue
        }
        if !entry.dedupeKey.isEmpty &&
          output.contains(where: { $0.conversationId == entry.conversationId && $0.dedupeKey == entry.dedupeKey }) {
          continue
        }
        output.append(entry)
      case .upsert:
        guard let entry = makeEntry(operation: operation, idGenerator: idGenerator) else {
          continue
        }
        guard !entry.dedupeKey.isEmpty else {
          continue
        }
        if let index = output.firstIndex(where: { $0.conversationId == entry.conversationId && $0.dedupeKey == entry.dedupeKey }) {
          let previous = output[index]
          if previous.role == entry.role && clean(previous.text) == entry.text {
            continue
          }
          output[index] = AgentTranscriptEntry(
            id: entry.id,
            role: entry.role,
            text: entry.text,
            timestampMillis: entry.timestampMillis,
            dedupeKey: entry.dedupeKey,
            conversationId: entry.conversationId,
            turnId: entry.turnId.isEmpty ? previous.turnId : entry.turnId,
            taskId: entry.taskId.isEmpty ? previous.taskId : entry.taskId,
            richOutputJson: previous.richOutputJson,
            sourceConversationId: previous.sourceConversationId,
            sourceConversationTitle: previous.sourceConversationTitle,
            sourceEntryId: previous.sourceEntryId
          )
        } else {
          output.append(entry)
        }
      }
    }
    return output
  }

  private static func makeEntry(
    operation: AgentTaskLivenessTranscriptOperation,
    idGenerator: () -> String
  ) -> AgentTranscriptEntry? {
    let text = clean(operation.text)
    let conversationId = clean(operation.conversationId)
    guard !text.isEmpty, !conversationId.isEmpty else {
      return nil
    }
    return AgentTranscriptEntry(
      id: idGenerator(),
      role: operation.role,
      text: text,
      timestampMillis: operation.timestampMillis,
      dedupeKey: clean(operation.dedupeKey),
      conversationId: conversationId,
      turnId: clean(operation.turnId),
      taskId: clean(operation.taskId)
    )
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
