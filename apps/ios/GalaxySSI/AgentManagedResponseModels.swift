import Foundation

enum AgentManagedResponseState: String, Codable, CaseIterable, Identifiable {
  case pending = "PENDING"
  case completed = "COMPLETED"
  case applied = "APPLIED"

  var id: String { rawValue }
}

struct AgentManagedResponseRecord: Codable, Equatable {
  var ownerRunId: String
  var supervisorRunId: String
  var agentId: String
  var deliveryMode: AgentDeliveryMode
  var sourceMessageId: Int64
  var contactId: String
  var conversationId: String
  var turnId: String
  var taskId: String
  var state: AgentManagedResponseState
  var response: AgentConnectorResponse?
  var createdAtMillis: Int64
  var completedAtMillis: Int64

  init(
    ownerRunId: String,
    supervisorRunId: String,
    agentId: String,
    deliveryMode: AgentDeliveryMode,
    sourceMessageId: Int64,
    contactId: String,
    conversationId: String = "",
    turnId: String = "",
    taskId: String = "",
    state: AgentManagedResponseState = .pending,
    response: AgentConnectorResponse? = nil,
    createdAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
    completedAtMillis: Int64 = 0
  ) {
    self.ownerRunId = ownerRunId
    self.supervisorRunId = supervisorRunId
    self.agentId = agentId
    self.deliveryMode = deliveryMode
    self.sourceMessageId = max(sourceMessageId, 0)
    self.contactId = contactId
    self.conversationId = conversationId
    self.turnId = turnId
    self.taskId = taskId
    self.state = state
    self.response = response
    self.createdAtMillis = max(createdAtMillis, 0)
    self.completedAtMillis = max(completedAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case ownerRunId = "owner_run_id"
    case supervisorRunId = "supervisor_run_id"
    case agentId = "agent_id"
    case deliveryMode = "delivery_mode"
    case sourceMessageId = "source_message_id"
    case contactId = "contact_id"
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case taskId = "task_id"
    case state
    case response
    case createdAtMillis = "created_at_millis"
    case completedAtMillis = "completed_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      ownerRunId: try container.decodeIfPresent(String.self, forKey: .ownerRunId) ?? "",
      supervisorRunId: try container.decodeIfPresent(String.self, forKey: .supervisorRunId) ?? "",
      agentId: try container.decodeIfPresent(String.self, forKey: .agentId) ?? "",
      deliveryMode: try container.decodeIfPresent(AgentDeliveryMode.self, forKey: .deliveryMode) ?? .observe,
      sourceMessageId: try container.decodeIfPresent(Int64.self, forKey: .sourceMessageId) ?? 0,
      contactId: try container.decodeIfPresent(String.self, forKey: .contactId) ?? "",
      conversationId: try container.decodeIfPresent(String.self, forKey: .conversationId) ?? "",
      turnId: try container.decodeIfPresent(String.self, forKey: .turnId) ?? "",
      taskId: try container.decodeIfPresent(String.self, forKey: .taskId) ?? "",
      state: try container.decodeIfPresent(AgentManagedResponseState.self, forKey: .state) ?? .pending,
      response: try container.decodeIfPresent(AgentConnectorResponse.self, forKey: .response),
      createdAtMillis: try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? 0,
      completedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .completedAtMillis) ?? 0
    )
  }

  func correlates(_ response: AgentConnectorResponse) -> Bool {
    sourceMessageId == response.sourceMessageId &&
      (contactId.isEmpty || response.contactId.isEmpty || contactId == response.contactId) &&
      AgentTaskIdentityPolicy.matchesResponseIdentity(
        expectedConversationId: conversationId,
        expectedTurnId: turnId,
        expectedTaskId: taskId,
        actualConversationId: response.conversationId,
        actualTurnId: response.turnId,
        actualTaskId: response.taskId
      )
  }

  func isStale(nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)) -> Bool {
    max(createdAtMillis, completedAtMillis) < nowMillis - Self.maxAgeMillis
  }

  static let maxAgeMillis: Int64 = 7 * 24 * 60 * 60 * 1_000
}

protocol AgentManagedResponseLedger: AnyObject {
  func register(_ record: AgentManagedResponseRecord) throws
  func complete(_ response: AgentConnectorResponse) -> AgentManagedResponseRecord?
  func acknowledge(_ response: AgentConnectorResponse) -> AgentManagedResponseRecord?
  func pendingForSupervisor(_ supervisorRunId: String) -> [AgentManagedResponseRecord]
  func completedUnapplied() -> [AgentManagedResponseRecord]
  func markApplied(ownerRunId: String)
  func removeOwner(_ ownerRunId: String)
  func clear()
}

final class InMemoryAgentManagedResponseLedger: AgentManagedResponseLedger {
  private let lock = NSRecursiveLock()
  private var records: [String: AgentManagedResponseRecord] = [:]

  func register(_ record: AgentManagedResponseRecord) throws {
    guard !record.ownerRunId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      record.sourceMessageId > 0 else {
      throw AgentRuntimeCapabilityError.invalid("Managed response records require owner run id and source message id")
    }
    lock.lock()
    defer { lock.unlock() }
    records[record.ownerRunId] = record
  }

  func complete(_ response: AgentConnectorResponse) -> AgentManagedResponseRecord? {
    lock.lock()
    defer { lock.unlock() }
    guard let key = records.first(where: { $0.value.correlates(response) })?.key else {
      return nil
    }
    let current = records[key]!
    guard current.state == .pending else {
      return current
    }
    let completed = AgentManagedResponseRecord(
      ownerRunId: current.ownerRunId,
      supervisorRunId: current.supervisorRunId,
      agentId: current.agentId,
      deliveryMode: current.deliveryMode,
      sourceMessageId: current.sourceMessageId,
      contactId: current.contactId,
      conversationId: current.conversationId,
      turnId: current.turnId,
      taskId: current.taskId,
      state: .completed,
      response: response,
      createdAtMillis: current.createdAtMillis,
      completedAtMillis: response.receivedAtMillis
    )
    records[key] = completed
    AgentLateManagedResponseBus.shared.publish(completed)
    return completed
  }

  func acknowledge(_ response: AgentConnectorResponse) -> AgentManagedResponseRecord? {
    lock.lock()
    defer { lock.unlock() }
    guard let key = records.first(where: { $0.value.correlates(response) })?.key else {
      return nil
    }
    let current = records[key]!
    let acknowledged = AgentManagedResponseRecord(
      ownerRunId: current.ownerRunId,
      supervisorRunId: current.supervisorRunId,
      agentId: current.agentId,
      deliveryMode: current.deliveryMode,
      sourceMessageId: current.sourceMessageId,
      contactId: current.contactId,
      conversationId: current.conversationId,
      turnId: current.turnId,
      taskId: current.taskId,
      state: .applied,
      response: response,
      createdAtMillis: current.createdAtMillis,
      completedAtMillis: response.receivedAtMillis
    )
    records[key] = acknowledged
    return acknowledged
  }

  func pendingForSupervisor(_ supervisorRunId: String) -> [AgentManagedResponseRecord] {
    lock.lock()
    defer { lock.unlock() }
    return records.values
      .filter { $0.supervisorRunId == supervisorRunId && $0.state == .pending }
      .sorted { $0.createdAtMillis < $1.createdAtMillis }
  }

  func completedUnapplied() -> [AgentManagedResponseRecord] {
    lock.lock()
    defer { lock.unlock() }
    return records.values
      .filter { $0.state == .completed && $0.response != nil }
      .sorted { $0.completedAtMillis < $1.completedAtMillis }
  }

  func markApplied(ownerRunId: String) {
    lock.lock()
    defer { lock.unlock() }
    guard var record = records[ownerRunId] else {
      return
    }
    record.state = .applied
    records[ownerRunId] = record
  }

  func removeOwner(_ ownerRunId: String) {
    lock.lock()
    defer { lock.unlock() }
    records.removeValue(forKey: ownerRunId)
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    records.removeAll()
  }
}

final class AgentLateManagedResponseBus {
  static let shared = AgentLateManagedResponseBus()

  private let lock = NSRecursiveLock()
  private var listeners: [UUID: (AgentManagedResponseRecord) -> Void] = [:]

  @discardableResult
  func addListener(_ listener: @escaping (AgentManagedResponseRecord) -> Void) -> UUID {
    lock.lock()
    defer { lock.unlock() }
    let token = UUID()
    listeners[token] = listener
    return token
  }

  func removeListener(_ token: UUID) {
    lock.lock()
    defer { lock.unlock() }
    listeners.removeValue(forKey: token)
  }

  func publish(_ record: AgentManagedResponseRecord) {
    let callbacks: [(AgentManagedResponseRecord) -> Void]
    lock.lock()
    callbacks = Array(listeners.values)
    lock.unlock()
    callbacks.forEach { $0(record) }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    listeners.removeAll()
  }
}

enum AgentManagedResponseCodec {
  static func encode(_ records: [AgentManagedResponseRecord]) -> String {
    AgentMcpJSONCodec.stringify(.array(records.map(recordObject)))
  }

  static func decode(_ raw: String) -> [AgentManagedResponseRecord] {
    guard let data = raw.data(using: .utf8),
      let values = try? JSONDecoder().decode([AgentMcpJSONValue].self, from: data) else {
      return []
    }
    return values.compactMap { value in
      guard case .object(let object) = value else {
        return nil
      }
      let ownerRunId = object.string("owner_run_id")
      let sourceMessageId = object.int64("source_message_id")
      guard !ownerRunId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        sourceMessageId > 0 else {
        return nil
      }
      return AgentManagedResponseRecord(
        ownerRunId: ownerRunId,
        supervisorRunId: object.string("supervisor_run_id"),
        agentId: object.string("agent_id"),
        deliveryMode: AgentDeliveryMode(rawValue: object.string("delivery_mode")) ?? .observe,
        sourceMessageId: sourceMessageId,
        contactId: object.string("contact_id"),
        conversationId: object.string("conversation_id"),
        turnId: object.string("turn_id"),
        taskId: object.string("task_id"),
        state: AgentManagedResponseState(rawValue: object.string("state")) ?? .pending,
        response: decodeResponse(object.object("response")),
        createdAtMillis: object.int64("created_at_millis"),
        completedAtMillis: object.int64("completed_at_millis")
      )
    }
  }

  private static func recordObject(_ record: AgentManagedResponseRecord) -> AgentMcpJSONValue {
    .object([
      "owner_run_id": .string(record.ownerRunId),
      "supervisor_run_id": .string(record.supervisorRunId),
      "agent_id": .string(record.agentId),
      "delivery_mode": .string(record.deliveryMode.rawValue),
      "source_message_id": .int(record.sourceMessageId),
      "contact_id": .string(record.contactId),
      "conversation_id": .string(record.conversationId),
      "turn_id": .string(record.turnId),
      "task_id": .string(record.taskId),
      "state": .string(record.state.rawValue),
      "response": record.response.map { .object(responseObject($0)) } ?? .null,
      "created_at_millis": .int(record.createdAtMillis),
      "completed_at_millis": .int(record.completedAtMillis)
    ])
  }

  private static func responseObject(_ response: AgentConnectorResponse) -> AgentMcpJSONObject {
    [
      "source_message_id": .int(response.sourceMessageId),
      "contact_id": .string(response.contactId),
      "content": .string(String(response.content.prefix(AgentConnectorResponse.maxContentCharacters))),
      "conversation_id": .string(response.conversationId),
      "turn_id": .string(response.turnId),
      "task_id": .string(response.taskId),
      "success": .bool(response.success),
      "input_tokens": .int(response.inputTokens),
      "output_tokens": .int(response.outputTokens),
      "cost_micros": .int(response.costMicros),
      "rich_output": .string(String(response.richOutputJson.prefix(AgentConnectorResponse.maxRichOutputCharacters))),
      "received_at_millis": .int(response.receivedAtMillis)
    ]
  }

  private static func decodeResponse(_ object: AgentMcpJSONObject?) -> AgentConnectorResponse? {
    guard let object else {
      return nil
    }
    let sourceMessageId = object.int64("source_message_id")
    let content = object.string("content")
    let richOutput = object.string("rich_output")
    guard sourceMessageId > 0,
      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !richOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return AgentConnectorResponse(
      sourceMessageId: sourceMessageId,
      contactId: object.string("contact_id"),
      content: content,
      conversationId: object.string("conversation_id"),
      turnId: object.string("turn_id"),
      taskId: object.string("task_id"),
      success: object["success"] == nil ? true : object.bool("success"),
      inputTokens: object.int64("input_tokens"),
      outputTokens: object.int64("output_tokens"),
      costMicros: object.int64("cost_micros"),
      richOutputJson: richOutput,
      receivedAtMillis: object.int64("received_at_millis")
    )
  }
}
