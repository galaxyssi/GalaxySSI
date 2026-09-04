import Foundation

enum AgentNativeToolLifecycleStage: String, Codable, CaseIterable, Identifiable {
  case started = "STARTED"
  case progress = "PROGRESS"
  case finished = "FINISHED"

  var id: String { rawValue }
}

struct AgentNativeToolLifecycleEvent: Codable, Equatable {
  var stage: AgentNativeToolLifecycleStage
  var toolId: String
  var invocationId: String
  var stepId: String
  var conversationId: String
  var turnId: String
  var status: AgentNativeToolResultStatus?
  var progressStage: String
  var message: String
  var percent: Int?
  var sequence: Int64
  var timestampMillis: Int64

  init(
    stage: AgentNativeToolLifecycleStage,
    toolId: String,
    invocationId: String,
    stepId: String,
    conversationId: String,
    turnId: String,
    status: AgentNativeToolResultStatus? = nil,
    progressStage: String = "",
    message: String = "",
    percent: Int? = nil,
    sequence: Int64 = 0,
    timestampMillis: Int64
  ) {
    self.stage = stage
    self.toolId = toolId
    self.invocationId = invocationId
    self.stepId = stepId
    self.conversationId = conversationId
    self.turnId = turnId
    self.status = status
    self.progressStage = String(progressStage.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
    self.message = String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
    self.percent = percent.map { min(max($0, 0), 100) }
    self.sequence = max(sequence, 0)
    self.timestampMillis = max(timestampMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case stage
    case toolId = "tool_id"
    case invocationId = "invocation_id"
    case stepId = "step_id"
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case status
    case progressStage = "progress_stage"
    case message
    case percent
    case sequence
    case timestampMillis = "timestamp_millis"
  }
}

struct AgentNativeToolLifecycleEventSink {
  var onEvent: (AgentNativeToolLifecycleEvent) -> Void

  init(_ onEvent: @escaping (AgentNativeToolLifecycleEvent) -> Void = { _ in }) {
    self.onEvent = onEvent
  }

  func emit(_ event: AgentNativeToolLifecycleEvent) {
    onEvent(event)
  }

  static let none = AgentNativeToolLifecycleEventSink()
}
