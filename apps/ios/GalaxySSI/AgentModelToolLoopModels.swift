import Foundation

struct AgentModelRequest {
  var sessionId: String
  var conversationId: String
  var turnId: String
  var taskId: String
  var workspaceId: String
  var round: Int
  var messages: [AgentModelMessage]
  var toolManifestJson: String
  var toolManifestSha256: String
  var remainingToolCalls: Int
  var remainingTokens: Int64
  var remainingTimeMillis: Int64
  var maxDepth: Int
  var cancellationToken: AgentModelToolLoopCancellationToken
}

protocol AgentModelAdapter {
  func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse
}

struct AgentModelToolLoopBudget: Codable, Equatable {
  var maxRounds: Int
  var maxToolCalls: Int
  var maxDepth: Int
  var maxTokens: Int64
  var maxDurationMillis: Int64
  var maxRetriesPerCall: Int
  var maxRepeatedCallSignatures: Int
  var approvalTtlMillis: Int64

  init(
    maxRounds: Int = 8,
    maxToolCalls: Int = 32,
    maxDepth: Int = 4,
    maxTokens: Int64 = 32_000,
    maxDurationMillis: Int64 = 120_000,
    maxRetriesPerCall: Int = 1,
    maxRepeatedCallSignatures: Int = 1,
    approvalTtlMillis: Int64 = 60_000
  ) {
    precondition(maxRounds > 0)
    precondition(maxToolCalls > 0)
    precondition(maxDepth > 0)
    precondition(maxTokens > 0)
    precondition(maxDurationMillis > 0)
    precondition(maxRetriesPerCall >= 0)
    precondition(maxRepeatedCallSignatures > 0)
    precondition(approvalTtlMillis > 0)
    self.maxRounds = maxRounds
    self.maxToolCalls = maxToolCalls
    self.maxDepth = maxDepth
    self.maxTokens = maxTokens
    self.maxDurationMillis = maxDurationMillis
    self.maxRetriesPerCall = maxRetriesPerCall
    self.maxRepeatedCallSignatures = maxRepeatedCallSignatures
    self.approvalTtlMillis = approvalTtlMillis
  }

  enum CodingKeys: String, CodingKey {
    case maxRounds = "max_rounds"
    case maxToolCalls = "max_tool_calls"
    case maxDepth = "max_depth"
    case maxTokens = "max_tokens"
    case maxDurationMillis = "max_duration_millis"
    case maxRetriesPerCall = "max_retries_per_call"
    case maxRepeatedCallSignatures = "max_repeated_call_signatures"
    case approvalTtlMillis = "approval_ttl_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      maxRounds: try container.decodeIfPresent(Int.self, forKey: .maxRounds) ?? 8,
      maxToolCalls: try container.decodeIfPresent(Int.self, forKey: .maxToolCalls) ?? 32,
      maxDepth: try container.decodeIfPresent(Int.self, forKey: .maxDepth) ?? 4,
      maxTokens: try container.decodeIfPresent(Int64.self, forKey: .maxTokens) ?? 32_000,
      maxDurationMillis: try container.decodeIfPresent(Int64.self, forKey: .maxDurationMillis) ?? 120_000,
      maxRetriesPerCall: try container.decodeIfPresent(Int.self, forKey: .maxRetriesPerCall) ?? 1,
      maxRepeatedCallSignatures: try container.decodeIfPresent(Int.self, forKey: .maxRepeatedCallSignatures) ?? 1,
      approvalTtlMillis: try container.decodeIfPresent(Int64.self, forKey: .approvalTtlMillis) ?? 60_000
    )
  }
}

struct AgentModelToolLoopCancellationToken {
  static let none = AgentModelToolLoopCancellationToken { false }

  private let isCancelled: () -> Bool

  init(_ isCancelled: @escaping () -> Bool) {
    self.isCancelled = isCancelled
  }

  var isCancellationRequested: Bool {
    isCancelled()
  }
}

final class AgentModelToolLoopCancellationSource {
  private let lock = NSLock()
  private var cancelled = false

  var token: AgentModelToolLoopCancellationToken {
    AgentModelToolLoopCancellationToken { [weak self] in
      guard let self else { return true }
      self.lock.lock()
      defer { self.lock.unlock() }
      return self.cancelled
    }
  }

  func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }
}

struct AgentModelToolLoopEventSink {
  static let none = AgentModelToolLoopEventSink { _ in }

  var onEvent: (AgentModelToolLoopEvent) -> Void

  init(_ onEvent: @escaping (AgentModelToolLoopEvent) -> Void) {
    self.onEvent = onEvent
  }
}

struct AgentModelToolLoopRequest {
  var sessionId: String
  var conversationId: String
  var turnId: String
  var taskId: String
  var workspaceId: String
  var responseLanguage: String
  var messages: [AgentModelMessage]
  var budget: AgentModelToolLoopBudget
  var callerId: String
  var grantedPermissions: Set<String>
  var grantedConsents: Set<String>
  var cancellationToken: AgentModelToolLoopCancellationToken
  var eventSink: AgentModelToolLoopEventSink

  init(
    sessionId: String,
    conversationId: String,
    turnId: String,
    taskId: String,
    workspaceId: String,
    messages: [AgentModelMessage],
    budget: AgentModelToolLoopBudget = AgentModelToolLoopBudget(),
    callerId: String = "galaxyssi.mobile_model_tool_loop",
    responseLanguage: String = LanguagePolicySettings.auto,
    grantedPermissions: Set<String> = [],
    grantedConsents: Set<String> = [],
    cancellationToken: AgentModelToolLoopCancellationToken = .none,
    eventSink: AgentModelToolLoopEventSink = .none
  ) {
    AgentModelToolLoopValidation.validateBoundId("Session", sessionId)
    AgentModelToolLoopValidation.validateBoundId("Conversation", conversationId)
    AgentModelToolLoopValidation.validateBoundId("Turn", turnId)
    AgentModelToolLoopValidation.validateBoundId("Task", taskId)
    AgentModelToolLoopValidation.validateBoundId("Workspace", workspaceId)
    precondition(!messages.isEmpty)
    precondition(!callerId.isBlank)
    precondition(grantedPermissions.allSatisfy { !$0.isBlank })
    precondition(grantedConsents.allSatisfy { !$0.isBlank })
    self.sessionId = sessionId
    self.conversationId = conversationId
    self.turnId = turnId
    self.taskId = taskId
    self.workspaceId = workspaceId
    self.responseLanguage = LanguagePolicySettings.normalizeVoice(responseLanguage)
    self.messages = messages
    self.budget = budget
    self.callerId = callerId
    self.grantedPermissions = grantedPermissions
    self.grantedConsents = grantedConsents
    self.cancellationToken = cancellationToken
    self.eventSink = eventSink
  }

  static func forUserMessage(
    sessionId: String,
    conversationId: String,
    turnId: String,
    taskId: String,
    workspaceId: String,
    userMessage: String,
    budget: AgentModelToolLoopBudget = AgentModelToolLoopBudget(),
    grantedPermissions: Set<String> = [],
    grantedConsents: Set<String> = [],
    cancellationToken: AgentModelToolLoopCancellationToken = .none,
    eventSink: AgentModelToolLoopEventSink = .none
  ) -> AgentModelToolLoopRequest {
    AgentModelToolLoopRequest(
      sessionId: sessionId,
      conversationId: conversationId,
      turnId: turnId,
      taskId: taskId,
      workspaceId: workspaceId,
      messages: [.user(userMessage)],
      budget: budget,
      grantedPermissions: grantedPermissions,
      grantedConsents: grantedConsents,
      cancellationToken: cancellationToken,
      eventSink: eventSink
    )
  }
}

enum AgentModelToolLoopEventType: String, Codable, CaseIterable, Identifiable {
  case loopStarted = "LOOP_STARTED"
  case modelRequested = "MODEL_REQUESTED"
  case modelResponded = "MODEL_RESPONDED"
  case toolCallProposed = "TOOL_CALL_PROPOSED"
  case toolCallRejected = "TOOL_CALL_REJECTED"
  case approvalRequired = "APPROVAL_REQUIRED"
  case approvalDecided = "APPROVAL_DECIDED"
  case loopResumed = "LOOP_RESUMED"
  case toolStarted = "TOOL_STARTED"
  case toolFinished = "TOOL_FINISHED"
  case toolRetryScheduled = "TOOL_RETRY_SCHEDULED"
  case budgetExceeded = "BUDGET_EXCEEDED"
  case loopDetected = "LOOP_DETECTED"
  case loopCancelled = "LOOP_CANCELLED"
  case loopFailed = "LOOP_FAILED"
  case loopCompleted = "LOOP_COMPLETED"

  var id: String { rawValue }
}

struct AgentModelToolLoopEvent: Codable, Equatable {
  var sequence: Int64
  var type: AgentModelToolLoopEventType
  var occurredAtEpochMillis: Int64
  var sessionId: String
  var turnId: String
  var taskId: String
  var toolManifestSha256: String
  var round: Int
  var toolCallId: String?
  var invocationId: String?
  var details: AgentMcpJSONObject

  enum CodingKeys: String, CodingKey {
    case sequence
    case type
    case occurredAtEpochMillis = "occurred_at_epoch_ms"
    case sessionId = "session_id"
    case turnId = "turn_id"
    case taskId = "task_id"
    case toolManifestSha256 = "tool_manifest_sha256"
    case round
    case toolCallId = "tool_call_id"
    case invocationId = "invocation_id"
    case details
  }
}

enum AgentModelToolApprovalDecision: String, Codable, CaseIterable, Identifiable {
  case approved
  case rejected
  case expired

  var id: String { rawValue }
}

struct AgentModelToolApprovalHandle: Codable, Equatable {
  var confirmationId: String
  var sessionId: String
  var turnId: String
  var taskId: String
  var toolCallId: String
  var toolId: String
  var toolVersion: String
  var argumentsSha256: String
  var toolManifestSha256: String
  var requiredConsentIds: Set<String>
  var targetSummary: String
  var expiresAtEpochMillis: Int64
  var nonce: String

  enum CodingKeys: String, CodingKey {
    case confirmationId = "confirmation_id"
    case sessionId = "session_id"
    case turnId = "turn_id"
    case taskId = "task_id"
    case toolCallId = "tool_call_id"
    case toolId = "tool_id"
    case toolVersion = "tool_version"
    case argumentsSha256 = "arguments_sha256"
    case toolManifestSha256 = "tool_manifest_sha256"
    case requiredConsentIds = "required_consent_ids"
    case targetSummary = "target_summary"
    case expiresAtEpochMillis = "expires_at_epoch_ms"
    case nonce
  }
}

enum AgentModelToolLoopStatus: String, Codable, CaseIterable, Identifiable {
  case completed = "COMPLETED"
  case waitingForApproval = "WAITING_FOR_APPROVAL"
  case budgetExceeded = "BUDGET_EXCEEDED"
  case loopDetected = "LOOP_DETECTED"
  case cancelled = "CANCELLED"
  case modelFailed = "MODEL_FAILED"

  var id: String { rawValue }
}

struct AgentModelToolLoopError: Codable, Equatable, Error {
  var code: String
  var message: String
  var details: AgentMcpJSONObject

  init(code: String, message: String, details: AgentMcpJSONObject = [:]) {
    self.code = code
    self.message = message
    self.details = details
  }
}

struct AgentModelToolLoopUsage: Codable, Equatable {
  var rounds: Int
  var toolCallAttempts: Int
  var retries: Int
  var inputTokens: Int64
  var outputTokens: Int64
  var durationMillis: Int64

  var totalTokens: Int64 {
    AgentModelToolLoopValidation.safeTokenSum(inputTokens, outputTokens)
  }

  enum CodingKeys: String, CodingKey {
    case rounds
    case toolCallAttempts = "tool_call_attempts"
    case retries
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
    case durationMillis = "duration_millis"
  }
}

struct AgentModelToolLoopOutcome: Codable, Equatable {
  var status: AgentModelToolLoopStatus
  var assistantText: String
  var messages: [AgentModelMessage]
  var events: [AgentModelToolLoopEvent]
  var usage: AgentModelToolLoopUsage
  var toolManifestJson: String
  var toolManifestSha256: String
  var approval: AgentModelToolApprovalHandle?
  var error: AgentModelToolLoopError?

  var isTerminal: Bool {
    status != .waitingForApproval
  }

  enum CodingKeys: String, CodingKey {
    case status
    case assistantText = "assistant_text"
    case messages
    case events
    case usage
    case toolManifestJson = "tool_manifest_json"
    case toolManifestSha256 = "tool_manifest_sha256"
    case approval
    case error
  }
}

struct AgentModelToolLoopClock {
  static let system = AgentModelToolLoopClock {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }

  var nowEpochMillis: () -> Int64

  init(_ nowEpochMillis: @escaping () -> Int64) {
    self.nowEpochMillis = nowEpochMillis
  }
}

struct AgentModelToolLoopIdFactory {
  static let uuids = AgentModelToolLoopIdFactory { _ in UUID().uuidString }

  private let makeId: (String) -> String

  init(_ makeId: @escaping (String) -> String) {
    self.makeId = makeId
  }

  func newId(_ purpose: String) -> String {
    makeId(purpose)
  }
}

enum AgentModelToolLoopValidation {
  static let maximumIdCharacters = 160

  static func validateBoundId(_ label: String, _ value: String) {
    precondition(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(label) id must not be blank")
    precondition(value.count <= maximumIdCharacters, "\(label) id must not exceed \(maximumIdCharacters) characters")
  }

  static func safeTokenSum(_ left: Int64, _ right: Int64) -> Int64 {
    if right > 0 && left > Int64.max - right {
      return Int64.max
    }
    return left + right
  }

  static func safeAdd(_ left: Int64, _ right: Int64) -> Int64 {
    if right > 0 && left > Int64.max - right {
      return Int64.max
    }
    return left + right
  }

  static func jsonCompatible(_ value: AgentMcpJSONValue) -> Bool {
    switch value {
    case .double(let double):
      return double.isFinite
    case .array(let values):
      return values.allSatisfy(jsonCompatible)
    case .object(let object):
      return object.values.allSatisfy(jsonCompatible)
    case .string, .int, .bool, .null:
      return true
    }
  }
}
