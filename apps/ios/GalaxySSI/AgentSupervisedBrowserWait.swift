import Foundation

struct AgentSupervisedBrowserWait: Codable, Equatable, Identifiable {
  static let toolID = AgentManagedBrowserToolExecution.toolID
  static let requestReceiptKey = "_galaxyssi_observed_browser_request_receipt"
  static let observationKey = "_galaxyssi_observed_browser_event"

  enum Resolution: Codable, Equatable {
    case returned(AgentManagedBrowserHandoff.Observation)
    case interrupted(AgentManagedBrowserHandoff.Interruption)

    var output: AgentMcpJSONObject {
      switch self {
      case .returned(let observation): return observation.toolOutput
      case .interrupted(let interruption): return interruption.output
      }
    }
  }

  let id: UUID
  let profileID: String
  let taskID: String
  let conversationID: String
  let turnID: String
  let contactID: String
  let outgoingID: UUID
  let planID: String
  let revision: Int
  let actionID: String
  let actionDigest: String
  let address: String
  let hostProcessID: String
  var resolution: Resolution?

  static func isHandoff(_ action: AgentAction) -> Bool {
    action.kind == .callNativeTool && (action.parameters["tool_id"] ?? action.target) == toolID
  }

  init?(task: AgentTaskRecord, outgoing: ChatMessage, action: AgentAction,
        profileID: String, hostProcessID: String = AgentOwnedOperationContext.processId) {
    guard !profileID.isBlank, !hostProcessID.isBlank, outgoing.isMine, !outgoing.readOnlyAnalysis,
          !task.taskId.isBlank, task.sessionId == outgoing.conversationId,
          task.taskId == outgoing.turnId.ifBlank(outgoing.id.uuidString),
          let plan = task.activePlan, !plan.planId.isBlank, plan.revision > 0,
          plan.executionMode != .planOnly, Self.isHandoff(action), action.risk != .blocked,
          !action.id.isBlank, task.pendingAction?.id == action.id,
          let input = Self.input(action), let persisted = plan.actions.first(where: { $0.id == action.id }),
          Self.fingerprint(persisted) == Self.fingerprint(action),
          AgentPlanContinuationScope(conversationId: outgoing.conversationId, turnId: task.taskId).owns(action)
    else { return nil }
    id = UUID()
    self.profileID = profileID
    taskID = task.taskId
    conversationID = task.sessionId
    turnID = task.taskId
    contactID = outgoing.contactId
    outgoingID = outgoing.id
    planID = plan.planId
    revision = plan.revision
    actionID = action.id
    actionDigest = Self.fingerprint(action)
    address = input
    self.hostProcessID = hostProcessID
  }

  func action(in task: AgentTaskRecord, outgoing: ChatMessage, profileID: String) -> AgentAction? {
    guard profileID == self.profileID, task.taskId == taskID, task.sessionId == conversationID,
          task.supervisedBrowserWait == self, outgoing.isMine, !outgoing.readOnlyAnalysis, outgoing.id == outgoingID,
          outgoing.contactId == contactID, outgoing.conversationId == conversationID,
          outgoing.turnId.ifBlank(outgoing.id.uuidString) == turnID,
          let plan = task.activePlan, plan.planId == planID, plan.revision == revision,
          let action = plan.actions.first(where: { $0.id == actionID }),
          Self.fingerprint(action) == actionDigest,
          action.parameters[Self.requestReceiptKey] == AgentMcpJSONCodec.stringify(requestReceipt) else { return nil }
    if let resolution {
      guard action.status == .failed,
            action.parameters[Self.observationKey] == AgentMcpJSONCodec.stringify(resolution.output) else { return nil }
    } else {
      guard action.status == .waitingResponse, let pending = task.pendingAction,
            pending.id == actionID, Self.fingerprint(pending) == actionDigest else { return nil }
    }
    return action
  }

  var requestReceipt: AgentMcpJSONObject {
    ["handoff_id": .string(id.uuidString), "state": .string("awaiting_user"),
     "request_only": .bool(true), "business_success_verified": .bool(false)]
  }

  func accepts(_ resolution: Resolution) -> Bool {
    guard self.resolution == nil else { return false }
    switch resolution {
    case .returned(let observation): return observation.isValid
    case .interrupted: return true
    }
  }

  private static func input(_ action: AgentAction) -> String? {
    guard isHandoff(action), let raw = action.parameters["input_json"], raw.utf8.count <= 8_192,
          let args = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8)),
          Set(args.keys) == ["url"], let address = args["url"]?.strictStringValue,
          address.utf8.count <= 4_096, AgentManagedBrowserHandoff.url(address) != nil else { return nil }
    return address
  }

  private static func fingerprint(_ action: AgentAction) -> String {
    AgentMcpJSONCodec.sha256([
      "id": .string(action.id), "tool": .string(action.parameters["tool_id"] ?? action.target),
      "input": .string(input(action) ?? ""), "risk": .string(action.risk.rawValue),
      "confirmation": .bool(action.requiresConfirmation),
      "scope": .object(action.parameters.filter { $0.key.hasPrefix("_galaxyssi_") &&
        !$0.key.hasPrefix("_galaxyssi_observed_") }.mapValues(AgentMcpJSONValue.string))
    ])
  }
}
