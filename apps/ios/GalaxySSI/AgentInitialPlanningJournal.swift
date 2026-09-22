import Foundation

struct AgentInitialPlanningReference: Codable, Equatable {
  var sessionId: String
  var conversationId: String
  var turnId: String
  var inputSha256: String

  var scope: AgentModelLoopScope {
    AgentModelLoopScope(
      sessionId: sessionId,
      conversationId: conversationId,
      turnId: turnId,
      taskId: turnId,
      workspaceId: AgentWorkspaceScope.id(conversationId: conversationId, sessionId: sessionId),
      callerId: "ios-initial-planner",
      loopId: "initial-planning-intent"
    )
  }

  enum CodingKeys: String, CodingKey {
    case sessionId = "session_id"
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case inputSha256 = "input_sha256"
  }
}

struct AgentInitialPlanningInput: Codable, Equatable {
  var goal: String
  var conversation: AgentConversationContext
  var turnId: String
  var executionMode: AgentTaskExecutionMode
  var hasAttachments: Bool
  var allowsDirectResponse: Bool
  var completionRequirements: AgentCompletionRequirements?
  var plannerConfigurationSha256: String

  enum CodingKeys: String, CodingKey {
    case goal
    case conversation
    case turnId = "turn_id"
    case executionMode = "execution_mode"
    case hasAttachments = "has_attachments"
    case allowsDirectResponse = "allows_direct_response"
    case completionRequirements = "completion_requirements"
    case plannerConfigurationSha256 = "planner_configuration_sha256"
  }
}

final class AgentInitialPlanningJournal {
  private static let operation = "initial-planning-input"
  private let journal: AgentModelLoopJournal

  init(journal: AgentModelLoopJournal = EncryptedAgentModelLoopJournal()) {
    self.journal = journal
  }

  func begin<T>(
    sessionId: String,
    input: AgentInitialPlanningInput,
    operation: (AgentInitialPlanningReference) async throws -> T
  ) async throws -> T {
    let reference = AgentInitialPlanningReference(
      sessionId: sessionId,
      conversationId: input.conversation.conversationId,
      turnId: input.turnId,
      inputSha256: AgentModelLoopRecoveryIdentity.sha256(input)
    )
    guard !reference.sessionId.isBlank,
          !reference.conversationId.isBlank,
          !reference.turnId.isBlank else {
      throw AgentModelLoopRecoveryError(code: "initial_planning_scope_invalid")
    }
    return try await journal.withLease(scope: reference.scope) { records in
      let data = try Self.encode(input)
      try records.write(Self.operation, data: data)
      return try await operation(reference)
    }
  }

  func restore<T>(
    _ reference: AgentInitialPlanningReference,
    operation: (AgentInitialPlanningInput) async throws -> T
  ) async throws -> T {
    try await journal.withLease(scope: reference.scope) { records in
      guard let data = try records.read(Self.operation) else {
        throw AgentModelLoopRecoveryError(code: "initial_planning_input_missing")
      }
      let input = try Self.decode(data)
      guard AgentModelLoopRecoveryIdentity.sha256(input) == reference.inputSha256 else {
        throw AgentModelLoopRecoveryError(code: "initial_planning_input_changed")
      }
      guard input.turnId == reference.turnId,
            input.conversation.conversationId == reference.conversationId else {
        throw AgentModelLoopRecoveryError(code: "initial_planning_scope_changed")
      }
      return try await operation(input)
    }
  }

  private static func encode(_ input: AgentInitialPlanningInput) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    do {
      return try encoder.encode(input)
    } catch {
      throw AgentModelLoopRecoveryError(code: "initial_planning_input_invalid")
    }
  }

  private static func decode(_ data: Data) throws -> AgentInitialPlanningInput {
    do {
      return try JSONDecoder().decode(AgentInitialPlanningInput.self, from: data)
    } catch {
      throw AgentModelLoopRecoveryError(code: "initial_planning_input_invalid")
    }
  }
}

extension AgentModelLoopScope {
  init(
    sessionId: String,
    conversationId: String,
    turnId: String,
    taskId: String,
    workspaceId: String,
    callerId: String,
    loopId: String
  ) {
    self.sessionId = sessionId
    self.conversationId = conversationId
    self.turnId = turnId
    self.taskId = taskId
    self.workspaceId = workspaceId
    self.callerId = callerId
    self.loopId = loopId
  }
}
