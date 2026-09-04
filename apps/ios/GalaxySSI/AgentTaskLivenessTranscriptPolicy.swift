import Foundation

enum AgentTaskLivenessTranscriptOperationKind: String, Codable, CaseIterable, Identifiable {
  case upsert = "UPSERT"
  case append = "APPEND"
  case delete = "DELETE"

  var id: String { rawValue }
}

struct AgentTaskLivenessTranscriptOperation: Codable, Equatable {
  var kind: AgentTaskLivenessTranscriptOperationKind
  var role: AgentTranscriptRole
  var text: String
  var dedupeKey: String
  var conversationId: String
  var turnId: String
  var taskId: String
  var timestampMillis: Int64

  init(
    kind: AgentTaskLivenessTranscriptOperationKind,
    role: AgentTranscriptRole = .process,
    text: String = "",
    dedupeKey: String,
    conversationId: String,
    turnId: String,
    taskId: String,
    timestampMillis: Int64 = 0
  ) {
    self.kind = kind
    self.role = role
    self.text = text
    self.dedupeKey = dedupeKey
    self.conversationId = conversationId
    self.turnId = turnId
    self.taskId = taskId
    self.timestampMillis = max(timestampMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case kind
    case role
    case text
    case dedupeKey = "dedupe_key"
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case taskId = "task_id"
    case timestampMillis = "timestamp_millis"
  }
}

enum AgentTaskLivenessTranscriptPolicy {
  static func operations(
    for signal: AgentTaskLivenessSignal,
    existingEntries: [AgentTranscriptEntry],
    stalledText: String = "The task has not reported progress recently.",
    timedOutText: String = "Checking whether the task should continue."
  ) -> [AgentTaskLivenessTranscriptOperation] {
    let workspace = signal.workspace
    let conversationId = clean(workspace.conversationId)
    let taskId = clean(workspace.taskId)
    guard !conversationId.isEmpty, !taskId.isEmpty else {
      return []
    }
    if AgentTaskTerminalReplyPolicy.hasTerminalReply(entries: existingEntries, turnId: taskId) {
      return clearOperations(conversationId: conversationId, taskId: taskId)
    }
    let warningKey = warningDedupeKey(taskId: taskId)
    switch signal.kind {
    case .stalled:
      return [
        AgentTaskLivenessTranscriptOperation(
          kind: .upsert,
          role: .process,
          text: clean(stalledText).isEmpty ? "The task has not reported progress recently." : stalledText,
          dedupeKey: warningKey,
          conversationId: conversationId,
          turnId: taskId,
          taskId: taskId,
          timestampMillis: signal.observedAtMillis
        )
      ]
    case .recovered:
      return [
        deleteOperation(dedupeKey: warningKey, conversationId: conversationId, taskId: taskId),
        deleteOperation(
          dedupeKey: assessmentDedupeKey(taskId: taskId),
          conversationId: conversationId,
          taskId: taskId
        )
      ]
    case .assessmentRequired:
      return [
        deleteOperation(dedupeKey: warningKey, conversationId: conversationId, taskId: taskId),
        AgentTaskLivenessTranscriptOperation(
          kind: .upsert,
          role: .process,
          text: clean(timedOutText).isEmpty ? "Checking whether the task should continue." : timedOutText,
          dedupeKey: assessmentDedupeKey(taskId: taskId),
          conversationId: conversationId,
          turnId: taskId,
          taskId: taskId,
          timestampMillis: signal.observedAtMillis
        )
      ]
    }
  }

  static func warningDedupeKey(taskId: String) -> String {
    "task-watchdog:\(clean(taskId))"
  }

  static func timeoutDedupeKey(taskId: String) -> String {
    "task-watchdog-timeout:\(clean(taskId))"
  }

  static func assessmentDedupeKey(taskId: String) -> String {
    "task-liveness-assessment:\(clean(taskId))"
  }

  static func clearOperations(
    conversationId: String,
    taskId: String
  ) -> [AgentTaskLivenessTranscriptOperation] {
    let cleanConversationId = clean(conversationId)
    let cleanTaskId = clean(taskId)
    guard !cleanConversationId.isEmpty, !cleanTaskId.isEmpty else {
      return []
    }
    return [
      deleteOperation(
        dedupeKey: warningDedupeKey(taskId: cleanTaskId),
        conversationId: cleanConversationId,
        taskId: cleanTaskId
      ),
      deleteOperation(
        dedupeKey: timeoutDedupeKey(taskId: cleanTaskId),
        conversationId: cleanConversationId,
        taskId: cleanTaskId
      ),
      deleteOperation(
        dedupeKey: assessmentDedupeKey(taskId: cleanTaskId),
        conversationId: cleanConversationId,
        taskId: cleanTaskId
      )
    ]
  }

  private static func deleteOperation(
    dedupeKey: String,
    conversationId: String,
    taskId: String
  ) -> AgentTaskLivenessTranscriptOperation {
    AgentTaskLivenessTranscriptOperation(
      kind: .delete,
      dedupeKey: dedupeKey,
      conversationId: conversationId,
      turnId: taskId,
      taskId: taskId
    )
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
