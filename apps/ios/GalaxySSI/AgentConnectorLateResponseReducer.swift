import Foundation

struct AgentTerminalDelivery: Codable, Equatable {
  var sourceMessageId: Int64
  var conversationId: String
  var turnId: String
  var taskId: String
  var contactId: String
  var reason: String
  var terminalAtMillis: Int64

  init(
    sourceMessageId: Int64,
    conversationId: String = "",
    turnId: String = "",
    taskId: String = "",
    contactId: String = "",
    reason: String = "",
    terminalAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) {
    self.sourceMessageId = max(sourceMessageId, 0)
    self.conversationId = Self.clean(conversationId)
    self.turnId = Self.clean(turnId)
    self.taskId = Self.clean(taskId)
    self.contactId = Self.clean(contactId)
    self.reason = String(reason.prefix(1_000))
    self.terminalAtMillis = max(terminalAtMillis, 0)
  }

  var hasIdentity: Bool {
    sourceMessageId > 0 || (!conversationId.isEmpty && !turnId.isEmpty)
  }

  func matches(_ response: AgentConnectorResponse) -> Bool {
    if sourceMessageId > 0, sourceMessageId == response.sourceMessageId {
      return true
    }
    guard sourceMessageId == 0,
          !conversationId.isEmpty,
          !turnId.isEmpty,
          conversationId == Self.clean(response.conversationId),
          turnId == Self.clean(response.turnId) else {
      return false
    }
    let responseTaskId = Self.clean(response.taskId)
    let responseContactId = Self.clean(response.contactId)
    return (taskId.isEmpty || taskId == responseTaskId) &&
      (contactId.isEmpty || contactId == responseContactId)
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

protocol AgentTerminalDeliveryStoring: AnyObject {
  func mark(_ delivery: AgentTerminalDelivery)
  func find(sourceMessageId: Int64) -> AgentTerminalDelivery?
  func isTerminal(_ response: AgentConnectorResponse) -> Bool
  func records() -> [AgentTerminalDelivery]
  func clear()
}

final class InMemoryAgentTerminalDeliveryStore: AgentTerminalDeliveryStoring {
  static let maxRecords = 512

  private let lock = NSRecursiveLock()
  private var values: [AgentTerminalDelivery]

  init(records: [AgentTerminalDelivery] = []) {
    values = Self.normalized(records)
  }

  func mark(_ delivery: AgentTerminalDelivery) {
    guard delivery.hasIdentity else { return }
    lock.lock()
    defer { lock.unlock() }
    values.removeAll { existing in
      if delivery.sourceMessageId > 0 {
        return existing.sourceMessageId == delivery.sourceMessageId
      }
      return existing.sourceMessageId == 0 &&
        existing.conversationId == delivery.conversationId &&
        existing.turnId == delivery.turnId
    }
    values = Self.normalized(values + [delivery])
  }

  func find(sourceMessageId: Int64) -> AgentTerminalDelivery? {
    guard sourceMessageId > 0 else { return nil }
    lock.lock()
    defer { lock.unlock() }
    return values.first { $0.sourceMessageId == sourceMessageId }
  }

  func isTerminal(_ response: AgentConnectorResponse) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return values.contains { $0.matches(response) }
  }

  func records() -> [AgentTerminalDelivery] {
    lock.lock()
    defer { lock.unlock() }
    return values
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    values.removeAll()
  }

  private static func normalized(_ records: [AgentTerminalDelivery]) -> [AgentTerminalDelivery] {
    records
      .filter(\.hasIdentity)
      .sorted { $0.terminalAtMillis > $1.terminalAtMillis }
      .prefix(maxRecords)
      .map { $0 }
  }
}

enum AgentLateConnectorResponsePolicy {
  static func exactTurnId(
    explicitTurnId: String,
    taskTurnId: String,
    indexedTurnId: String,
    conversationMessages: [ChatMessage]
  ) -> String? {
    var seen = Set<String>()
    let candidates = [explicitTurnId, taskTurnId, indexedTurnId]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && seen.insert($0).inserted }
    return candidates.first { candidate in
      conversationMessages.contains {
        $0.isMine && !$0.isSystem && $0.turnId == candidate
      }
    }
  }

  static func canAccept(
    sourceIsTerminal: Bool,
    exactTurnId: String?,
    conversationMessages: [ChatMessage]
  ) -> Bool {
    guard !sourceIsTerminal,
          let exactTurnId,
          !exactTurnId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return false
    }
    return !conversationMessages.contains { message in
      !message.isMine &&
        !message.isSystem &&
        message.turnId == exactTurnId &&
        !isApprovalMessage(message)
    }
  }

  private static func isApprovalMessage(_ message: ChatMessage) -> Bool {
    AgentRichContentCodec.decode(message.richOutputJson).contains { block in
      block.type == .approval && block.actions.contains {
        ["decide_task_permission", "decide_remote_task_permission"].contains($0.verb)
      }
    }
  }
}

struct AgentConnectorLateResponseReduction: Codable, Equatable {
  var workspace: AgentWorkspace?
  var changed: Bool
  var accepted: Bool
  var sourceMessageId: Int64

  init(
    workspace: AgentWorkspace?,
    changed: Bool = false,
    accepted: Bool = false,
    sourceMessageId: Int64
  ) {
    self.workspace = workspace
    self.changed = changed
    self.accepted = accepted
    self.sourceMessageId = max(sourceMessageId, 0)
  }

  enum CodingKeys: String, CodingKey {
    case workspace
    case changed
    case accepted
    case sourceMessageId = "source_message_id"
  }
}

enum AgentConnectorLateResponseReducer {
  static let defaultMessage = "Authenticated connector response received after local timeout"
  static let defaultMaxEventCount = 100

  static func reconcile(
    workspace: AgentWorkspace,
    sourceMessageId: Int64,
    observedAtMillis: Int64,
    maxEventCount: Int = defaultMaxEventCount
  ) -> AgentConnectorLateResponseReduction {
    guard sourceMessageId > 0 else {
      return AgentConnectorLateResponseReduction(workspace: nil, sourceMessageId: sourceMessageId)
    }
    guard workspace.status == .failed,
      !workspace.cancellationRequested else {
      return AgentConnectorLateResponseReduction(
        workspace: workspace.cancellationRequested ? nil : workspace,
        sourceMessageId: sourceMessageId
      )
    }
    guard handoffMatches(workspace: workspace, sourceMessageId: sourceMessageId) else {
      return AgentConnectorLateResponseReduction(workspace: nil, sourceMessageId: sourceMessageId)
    }
    var updated = appendEvent(
      to: workspace,
      kind: AgentTaskEventKinds.lateResponse,
      message: defaultMessage,
      payloadJson: AgentMcpJSONCodec.stringify(["source_message_id": .int(sourceMessageId)]),
      timestampMillis: observedAtMillis,
      maxEventCount: maxEventCount
    )
    updated.status = .waitingResponse
    updated.errorMessage = ""
    return AgentConnectorLateResponseReduction(
      workspace: updated,
      changed: true,
      accepted: true,
      sourceMessageId: sourceMessageId
    )
  }

  private static func handoffMatches(
    workspace: AgentWorkspace,
    sourceMessageId: Int64
  ) -> Bool {
    let source = String(sourceMessageId)
    let sourceSuffix = ":\(source)"
    return workspace.handoffIds.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(sourceSuffix) } ||
      workspace.remoteRunId.trimmingCharacters(in: .whitespacesAndNewlines) == source
  }

  private static func appendEvent(
    to workspace: AgentWorkspace,
    kind: String,
    message: String,
    payloadJson: String,
    timestampMillis: Int64,
    maxEventCount: Int
  ) -> AgentWorkspace {
    let cleanKind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
    precondition(!cleanKind.isEmpty, "event kind must not be blank")
    precondition(workspace.eventSequence < Int64.max, "Agent workspace event sequence exhausted")
    let timestamp = max(timestampMillis, 0)
    let nextSequence = workspace.eventSequence + 1
    let event = AgentWorkspaceEvent(
      sequence: nextSequence,
      kind: cleanKind,
      message: message,
      payloadJson: payloadJson,
      timestampMillis: timestamp
    )
    var updated = workspace
    updated.eventSequence = nextSequence
    updated.eventJournal = Array((workspace.eventJournal + [event]).suffix(max(maxEventCount, 1)))
    updated.updatedAtMillis = max(workspace.updatedAtMillis, timestamp)
    return updated
  }
}
