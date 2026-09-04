import Foundation

enum AgentSubagentStatus: String, Codable, CaseIterable, Identifiable {
  case pending = "PENDING"
  case queued = "QUEUED"
  case running = "RUNNING"
  case succeeded = "SUCCEEDED"
  case failed = "FAILED"
  case cancelled = "CANCELLED"
  case skipped = "SKIPPED"
  case interrupted = "INTERRUPTED"

  var id: String { rawValue }

  var isTerminal: Bool {
    [.succeeded, .failed, .cancelled, .skipped, .interrupted].contains(self)
  }
}

enum AgentTeamExecutionState: String, Codable, CaseIterable, Identifiable {
  case queued = "QUEUED"
  case created = "CREATED"
  case running = "RUNNING"
  case waitingResponse = "WAITING_RESPONSE"
  case succeeded = "SUCCEEDED"
  case completedWithFailures = "COMPLETED_WITH_FAILURES"
  case failed = "FAILED"
  case cancelled = "CANCELLED"
  case interrupted = "INTERRUPTED"

  var id: String { rawValue }

  var isTerminal: Bool {
    [.succeeded, .completedWithFailures, .failed, .cancelled, .interrupted].contains(self)
  }

  var deliverable: Bool {
    [.succeeded, .completedWithFailures, .failed, .cancelled].contains(self)
  }
}

struct AgentTeamProgressProjection: Codable, Equatable {
  var state: AgentTeamExecutionState
  var primaryAgentId: String
  var finalOutput: String
  var members: [AgentTeamMemberSnapshot]
  var memberDetailsVisible: Bool
}

enum AgentTeamProgressPolicy {
  static func project(_ snapshot: AgentTeamExecutionSnapshot, expanded: Bool) -> AgentTeamProgressProjection {
    let showMembers = expanded || snapshot.visibilityMode == .visible
    return AgentTeamProgressProjection(
      state: snapshot.state,
      primaryAgentId: snapshot.primaryAgentId,
      finalOutput: snapshot.finalOutput,
      members: showMembers ? snapshot.members : [],
      memberDetailsVisible: showMembers
    )
  }
}

struct AgentTeamMemberSnapshot: Codable, Equatable {
  static let maxErrorCharacters = 1_000

  var agentId: String
  var role: String
  var deliveryMode: AgentDeliveryMode
  var status: AgentSubagentStatus
  var output: String
  var errorMessage: String
  var updatedAtMillis: Int64
  var instanceId: String

  var memberId: String { instanceId.ifBlank(agentId) }

  init(
    agentId: String,
    role: String = "",
    deliveryMode: AgentDeliveryMode = .observe,
    status: AgentSubagentStatus = .pending,
    output: String = "",
    errorMessage: String = "",
    updatedAtMillis: Int64 = 0,
    instanceId: String = ""
  ) {
    self.agentId = agentId
    self.role = role
    self.deliveryMode = deliveryMode
    self.status = status
    self.output = String(output.prefix(AgentConnectorResponse.maxContentCharacters))
    self.errorMessage = String(errorMessage.prefix(Self.maxErrorCharacters))
    self.updatedAtMillis = max(updatedAtMillis, 0)
    self.instanceId = instanceId.ifBlank(agentId)
  }

  enum CodingKeys: String, CodingKey {
    case agentId = "agent_id"
    case role
    case deliveryMode = "delivery_mode"
    case status
    case output
    case errorMessage = "error_message"
    case updatedAtMillis = "updated_at_millis"
    case instanceId = "instance_id"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let agentId = try container.decodeIfPresent(String.self, forKey: .agentId) ?? ""
    self.init(
      agentId: agentId,
      role: try container.decodeIfPresent(String.self, forKey: .role) ?? "",
      deliveryMode: try container.decodeIfPresent(AgentDeliveryMode.self, forKey: .deliveryMode) ?? .observe,
      status: try container.decodeIfPresent(AgentSubagentStatus.self, forKey: .status) ?? .pending,
      output: try container.decodeIfPresent(String.self, forKey: .output) ?? "",
      errorMessage: try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? "",
      updatedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ?? 0,
      instanceId: try container.decodeIfPresent(String.self, forKey: .instanceId) ?? agentId
    )
  }
}

struct AgentTeamExecutionSnapshot: Codable, Equatable {
  var supervisorRunId: String
  var teamId: String
  var conversationId: String
  var taskId: String
  var primaryAgentId: String
  var goal: String
  var visibilityMode: AgentTeamVisibilityMode
  var state: AgentTeamExecutionState
  var members: [AgentTeamMemberSnapshot]
  var finalOutput: String
  var createdAtMillis: Int64
  var updatedAtMillis: Int64
  var interruptedAtMillis: Int64
  var primaryInstanceId: String

  var primaryMemberId: String { primaryInstanceId.ifBlank(primaryAgentId) }

  init(
    supervisorRunId: String,
    teamId: String,
    conversationId: String = "",
    taskId: String = "",
    primaryAgentId: String,
    goal: String = "",
    visibilityMode: AgentTeamVisibilityMode = .background,
    state: AgentTeamExecutionState,
    members: [AgentTeamMemberSnapshot] = [],
    finalOutput: String = "",
    createdAtMillis: Int64 = 0,
    updatedAtMillis: Int64 = 0,
    interruptedAtMillis: Int64 = 0,
    primaryInstanceId: String = ""
  ) {
    self.supervisorRunId = supervisorRunId
    self.teamId = teamId
    self.conversationId = conversationId
    self.taskId = taskId
    self.primaryAgentId = primaryAgentId
    self.goal = goal
    self.visibilityMode = visibilityMode
    self.state = state
    self.members = members
    self.finalOutput = String(finalOutput.prefix(AgentConnectorResponse.maxContentCharacters))
    self.createdAtMillis = max(createdAtMillis, 0)
    self.updatedAtMillis = max(updatedAtMillis, 0)
    self.interruptedAtMillis = max(interruptedAtMillis, 0)
    self.primaryInstanceId = primaryInstanceId.ifBlank(primaryAgentId)
  }

  enum CodingKeys: String, CodingKey {
    case supervisorRunId = "supervisor_run_id"
    case teamId = "team_id"
    case conversationId = "conversation_id"
    case taskId = "task_id"
    case primaryAgentId = "primary_agent_id"
    case goal
    case visibilityMode = "visibility_mode"
    case state
    case members
    case finalOutput = "final_output"
    case createdAtMillis = "created_at_millis"
    case updatedAtMillis = "updated_at_millis"
    case interruptedAtMillis = "interrupted_at_millis"
    case primaryInstanceId = "primary_instance_id"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      supervisorRunId: try container.decodeIfPresent(String.self, forKey: .supervisorRunId) ?? "",
      teamId: try container.decodeIfPresent(String.self, forKey: .teamId) ?? "",
      conversationId: try container.decodeIfPresent(String.self, forKey: .conversationId) ?? "",
      taskId: try container.decodeIfPresent(String.self, forKey: .taskId) ?? "",
      primaryAgentId: try container.decodeIfPresent(String.self, forKey: .primaryAgentId) ?? "",
      goal: try container.decodeIfPresent(String.self, forKey: .goal) ?? "",
      visibilityMode: try container.decodeIfPresent(AgentTeamVisibilityMode.self, forKey: .visibilityMode) ?? .background,
      state: try container.decodeIfPresent(AgentTeamExecutionState.self, forKey: .state) ?? .queued,
      members: try container.decodeIfPresent([AgentTeamMemberSnapshot].self, forKey: .members) ?? [],
      finalOutput: try container.decodeIfPresent(String.self, forKey: .finalOutput) ?? "",
      createdAtMillis: try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? 0,
      updatedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ?? 0,
      interruptedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .interruptedAtMillis) ?? 0,
      primaryInstanceId: try container.decodeIfPresent(String.self, forKey: .primaryInstanceId) ??
        (try container.decodeIfPresent(String.self, forKey: .primaryAgentId) ?? "")
    )
  }
}

protocol AgentTeamCompletionSink: AnyObject {
  @discardableResult
  func publish(_ snapshot: AgentTeamExecutionSnapshot) -> Bool
  func remove(supervisorRunId: String)
  func clear()
}

extension AgentTeamCompletionSink {
  func remove(supervisorRunId: String) {}
  func clear() {}
}

final class AgentConnectorTeamCompletionSink: AgentTeamCompletionSink {
  static let maxErrorCharacters = AgentTeamMemberSnapshot.maxErrorCharacters

  private let responseStore: AgentConnectorResponseSink
  private let ledger: AgentTeamCompletionDeliveryLedger
  private let historyStore: AgentTeamExecutionHistoryStore
  private let nowMillis: () -> Int64

  init(
    responseStore: AgentConnectorResponseSink,
    ledger: AgentTeamCompletionDeliveryLedger = AgentTeamCompletionDeliveryLedger(),
    historyStore: AgentTeamExecutionHistoryStore = .shared,
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.responseStore = responseStore
    self.ledger = ledger
    self.historyStore = historyStore
    self.nowMillis = nowMillis
  }

  @discardableResult
  func publish(_ snapshot: AgentTeamExecutionSnapshot) -> Bool {
    historyStore.upsert(snapshot)
    guard snapshot.state.deliverable,
      !ledger.contains(snapshot.supervisorRunId) else {
      return false
    }
    let output = snapshot.finalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    let successful = !output.isEmpty && [.succeeded, .completedWithFailures].contains(snapshot.state)
    let content: String
    if successful {
      content = output
    } else if let error = snapshot.members.map(\.errorMessage).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
      content = "Agent team failed: \(String(error.prefix(Self.maxErrorCharacters)))"
    } else {
      content = "Agent team failed."
    }
    responseStore.publish(AgentConnectorResponse(
      sourceMessageId: AgentTeamDispatchIds.sourceMessageId(supervisorRunId: snapshot.supervisorRunId),
      contactId: AgentTeamDispatchIds.responseContactId(teamId: snapshot.teamId),
      content: content,
      conversationId: snapshot.conversationId,
      turnId: snapshot.taskId,
      taskId: snapshot.taskId,
      success: successful,
      receivedAtMillis: max(snapshot.updatedAtMillis, nowMillis())
    ))
    ledger.mark(snapshot.supervisorRunId)
    return true
  }

  func remove(supervisorRunId: String) {
    ledger.remove(supervisorRunId)
    historyStore.remove(supervisorRunId: supervisorRunId)
  }

  func clear() {
    ledger.clear()
    historyStore.clear()
  }
}

final class AgentTeamCompletionDeliveryLedger {
  private let lock = NSRecursiveLock()
  private var delivered: [String]
  private let maximumRecords: Int

  init(delivered: [String] = [], maxRecords: Int = 512) {
    let limit = Swift.max(maxRecords, 1)
    let cleaned = delivered
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    self.delivered = Self.stableDistinct(cleaned)
      .suffix(limit)
      .map { $0 }
    self.maximumRecords = limit
  }

  private static func stableDistinct(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }

  func contains(_ supervisorRunId: String) -> Bool {
    let clean = supervisorRunId.trimmingCharacters(in: .whitespacesAndNewlines)
    lock.lock()
    defer { lock.unlock() }
    return delivered.contains(clean)
  }

  func mark(_ supervisorRunId: String) {
    let clean = supervisorRunId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
      return
    }
    lock.lock()
    defer { lock.unlock() }
    delivered = delivered.filter { $0 != clean } + [clean]
    if delivered.count > maximumRecords {
      delivered = Array(delivered.suffix(maximumRecords))
    }
  }

  func remove(_ supervisorRunId: String) {
    let clean = supervisorRunId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
      return
    }
    lock.lock()
    defer { lock.unlock() }
    delivered.removeAll { $0 == clean }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    delivered.removeAll()
  }

  func snapshot() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return delivered
  }
}
