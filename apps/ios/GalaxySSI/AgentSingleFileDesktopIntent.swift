import UIKit

struct AgentSingleFileDesktopIntent: Codable, Equatable {
  static let ownerPrefix = "ios-single-file-read-v1:"
  static func isInferenceOwner(_ owner: String) -> Bool {
    owner.hasPrefix(ownerPrefix) || owner.hasPrefix(AgentPairedPhonePlannerRoute.ownerPrefix)
  }
  let source: Int64
  let owner: String
  let contact: String
  let agent: String
  let model: String
  let effort: AgentModelReasoningEffort
  let desktop: String
  let identity: AgentTaskIdentity
  let binding: String
  let attachment: String
  let transfer: String
  let originalRichSHA: String
  let promptSHA: String
  let descriptorsSHA: String
  let invocationSHA: String

  var valid: Bool {
    guard let parameters = AgentInvocationRequestJsonCodec.encode(modelId: model, reasoningEffort: effort),
      Self.digest(parameters) == invocationSHA else { return false }
    return (1...Int64(0x1fffffffffffff)).contains(source) && owner.hasPrefix(Self.ownerPrefix) &&
      MqttRouteProtocol.hex(String(owner.dropFirst(Self.ownerPrefix.count)), count: 64) && identity.isComplete &&
      UUID(uuidString: identity.taskId) != nil && UUID(uuidString: identity.turnId) != nil &&
      [identity.clientRouteId, identity.conversationId].allSatisfy { !$0.isBlank && $0.utf8.count <= 512 } &&
      [contact, agent, desktop, attachment].allSatisfy { !$0.isBlank && $0.utf8.count <= 512 } &&
      model.utf8.count <= 512 &&
      [binding, transfer, originalRichSHA, promptSHA, descriptorsSHA, invocationSHA].allSatisfy { MqttRouteProtocol.hex($0, count: 64) }
  }
  static func digest(_ value: Any) -> String? {
    guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return nil }
    return AgentBlobProtocol.sha256(data)
  }
  func matches(_ payload: [String: Any]) -> Bool {
    let fields: Set<String> = ["type", "message_id", "content", "contact_id", "desktop_id", "agent_id", "sender",
      "client_route_id", "conversation_id", "turn_id", "task_id", "source_message_id", "client_message_id", "time",
      "connector_task_mode", "execution_mode", "_galaxyssi_task_execution_mode", "_galaxyssi_long_term_write_allowed",
      "agent_invocation", "response_language", "request_kind", "execution_generation", "attachments"]
    guard valid, Set(payload.keys) == fields, payload.string("type") == "text",
      payload.string("message_id") == identity.taskId, payload.string("contact_id") == contact,
      payload.string("desktop_id") == desktop, payload.string("agent_id") == agent,
      payload.string("client_route_id") == identity.clientRouteId, payload.string("conversation_id") == identity.conversationId,
      payload.string("turn_id") == identity.turnId, payload.string("task_id") == identity.taskId,
      payload.string("source_message_id") == String(source), payload.string("client_message_id") == String(source),
      payload.string("connector_task_mode") == AgentPairedPhonePlannerRoute.connectorMode,
      payload.string("execution_mode") == AgentTaskExecutionMode.planOnly.rawValue,
      payload.string("_galaxyssi_task_execution_mode") == AgentTaskExecutionMode.planOnly.rawValue,
      payload.string("_galaxyssi_long_term_write_allowed") == "false",
      payload.string("request_kind") == AgentRequestKind.screenAnalysis.rawValue,
      AgentDesktopReplyRecovery.integer(payload["execution_generation"], minimum: 1) == 1,
      AgentDesktopReplyRecovery.integer(payload["time"], minimum: 1) != nil,
      AgentTurnReceiptEvidence.hash(payload.string("content")) == promptSHA,
      let descriptors = payload["attachments"] as? [[String: Any]], descriptors.count == 1,
      descriptors[0].string("id") == attachment, descriptors[0].string("transfer_id") == transfer,
      Self.digest(descriptors) == descriptorsSHA,
      let invocation = payload["agent_invocation"] as? [String: String], Self.digest(invocation) == invocationSHA else { return false }
    return true
  }
}

extension MessageCoordinator {
  func currentFileReadDesktopContext(source: String, contact: GalaxySSIContact, identity: AgentTaskIdentity,
    routes: GalaxySSILinkRoutes) -> (intent: AgentSingleFileDesktopIntent, message: ChatMessage)? {
    guard UIApplication.shared.applicationState == .active, UIApplication.shared.isProtectedDataAvailable,
      store.canReadAgentTranscript, fileReadOwners[identity.turnId] == store.profile.identityFingerprint,
      store.activeAgentConversationId == identity.conversationId, contact.isCommunicable,
      contact.deliveryMode.isGalaxySSILinkFamily,
      let session = store.agentSession(id: identity.conversationId), session.status == .active,
      !session.privateMode, !session.trackingPaused, session.mergedIntoConversationId.isBlank, session.globalTopicKey.isBlank,
      let childID = UUID(uuidString: identity.turnId), let child = store.persistedMessage(id: childID, contactId: "hermes"),
      child.isMine, child.readOnlyAnalysis, child.deliveryTrace.first?.stage == AgentSingleFileRead.stage,
      child.conversationId == identity.conversationId, child.turnId == identity.turnId,
      let key = store.turnReceiptKey(conversation: identity.conversationId, turn: identity.turnId),
      let row = store.turnReceiptStore.read(key), let parent = row.fileReadSource, let intent = row.fileReadDesktop,
      intent.valid, intent.source.description == source, intent.contact == contact.id, intent.agent == contact.connectorAgentId,
      intent.desktop == contact.desktopId, intent.identity == identity,
      (intent.model.isBlank || contact.connectorInvocationProfile.models.contains(where: { $0.id == intent.model })),
      (intent.effort == .automatic || contact.connectorInvocationProfile.reasoningEfforts.contains(intent.effort)),
      identity.clientRouteId == routes.clientRouteId,
      intent.binding == GalaxySSITransportReceiptJournal.binding(peerId: contact.desktopId, routes: routes),
      !healthDisclosureStore.blockedDestinationIds().contains(contact.id), store.agentSafetySettings.connectorCallsAllowed,
      let originalID = UUID(uuidString: parent.turn), let original = store.persistedMessage(id: originalID, contactId: "hermes"),
      original.conversationId == identity.conversationId, original.turnId == parent.turn,
      AgentTurnReceiptEvidence.hash(original.richOutputJson) == intent.originalRichSHA,
      AgentFileReceipt.originals(original).count >= 2, AgentFileReceipt.originals(original).contains(where: { $0.id == intent.attachment }),
      AgentFileReceipt.originals(child).map(\.id) == [intent.attachment], parent.digest == AgentTurnReceiptEvidence.hash(intent.attachment),
      let parentKey = store.turnReceiptKey(conversation: identity.conversationId, turn: parent.turn),
      store.turnReceiptStore.read(parentKey)?.files?[parent.digest]?.readTurn == identity.turnId else { return nil }
    return (intent, child)
  }

  func fileReadOutboxAllowed(_ item: PendingLinkMessage) -> Bool? {
    guard let scope = item.fileReadScope else { return nil }
    guard let identity = fileReadRegisteredIdentity(contact: item.contactId, source: item.clientSourceMessageId),
      identity.turnId == scope else { return false }
    let key = AgentTurnReceiptStore.Key(owner: store.profile.identityFingerprint, conversation: identity.conversationId, turn: identity.turnId)
    guard let intent = store.turnReceiptStore.read(key)?.fileReadDesktop else { return false }
    guard let contact = store.contact(id: item.contactId),
      let link = store.serverLinks.first(where: { $0.paired && $0.desktopId == intent.desktop }),
      item.topic == link.routes.upTopic,
      item.attachmentTransferId.isEmpty || item.attachmentTransferId == intent.transfer else { return false }
    return currentFileReadDesktopContext(source: item.clientSourceMessageId, contact: contact, identity: identity, routes: link.routes) != nil
  }
}
