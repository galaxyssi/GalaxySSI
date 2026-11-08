import Foundation

@MainActor
struct MqttDesktopConnectorProjection {
  struct TaskOwner {
    let message: ChatMessage
    var team: AgentTeamReplyOwner? = nil
    var teamID: String? = nil
    var maySend = true

    var projectsAttachmentToTranscript: Bool { team?.deliveryMode != .observe }

    func matches(_ payload: [String: Any]) -> Bool {
      guard let team else { return payload["agent_team_message"] as? Bool != true }
      guard let teamID else { return false }
      let run = team.deliveryMode == .respond ? team.supervisorRunId :
        AgentControlPlaneActionExecutor.stableRunId(conversationId: teamID, turnId: team.supervisorRunId,
          actionId: "agent-team-member", agentId: team.memberId)
      return payload["agent_team_message"] as? Bool == true && payload.string("agent_instance_id") == team.memberId &&
        payload.string("team_id") == teamID && payload.string("delivery_mode") == team.deliveryMode.rawValue &&
        payload.string("run_id") == run
    }
  }

  let store: GalaxySSIStore
  let identities: AgentTaskIdentityStore
  let commitResponse: (AgentConnectorResponse, [String: Any]) throws -> Void
  var terminalResult: (([String: Any], AgentResultReceipt) throws -> Void)? = nil
  var resultRecovery: (() -> AgentDesktopResultRecovery?)? = nil
  var receiveRecoveryControl: (([String: Any], String) throws -> Void)? = nil
  var recoveryQueries: (((AgentDesktopReplyBinding) -> Bool) -> [[String: Any]])? = nil
  var resumeEvidenceJobs: ((MqttBusinessTransportRuntime) -> Void)? = nil
  var resolveTeamOwner: ((String, GalaxySSIContact, AgentTaskIdentity, MqttPeerChatProjection.Destination) throws -> TaskOwner?)? = nil
  var recordTeamAttachmentFailure: ((AgentTeamReplyOwner) throws -> Void)? = nil
  var recordTeamProgress: (([String: Any], AgentTeamReplyOwner) throws -> Bool)? = nil

  static func handles(_ payload: [String: Any]) -> Bool {
    payload["peer_chat"] as? Bool != true &&
      ["agent_task_event", "text", "agent_response", "agent_task_result_receipt_confirmed",
       "agent_task_recovery_result", "agent_task_result_page"].contains(payload.string("type"))
  }

  private func contact(_ payload: [String: Any], target: MqttPeerChatProjection.Destination) throws -> GalaxySSIContact {
    let desktop = target.peer.remoteSignalName
    guard target.desktop, let contact = store.contact(id: payload.string("contact_id")),
          contact.id == payload.string("contact_id"), contact.isCommunicable, !contact.isDesktopDeviceContact,
          contact.deliveryMode.isGalaxySSILinkFamily, contact.desktopId == desktop, !contact.connectorAgentId.isBlank,
          payload.string("desktop_id").ifBlank(desktop) == desktop,
          payload.string("agent_id").ifBlank(payload.string("connector_id")) == contact.connectorAgentId,
          payload.string("client_route_id") == target.routeId, identities.matchesRegistered(payload: payload),
          !GalaxySSITransportPrivacyPolicy.isLocalOnly(payload) else { throw MqttRouteError.identityChanged }
    return contact
  }

  func outgoingRequest(_ payload: [String: Any], target: MqttPeerChatProjection.Destination) throws -> MqttSignalSendRequest {
    guard let request = try outgoingRequests(payload, target: target, attachments: [], blobTransfers: []).last
    else { throw MqttRouteError.invalidPayload }
    return request
  }

  func outgoingCancellation(_ payload: [String: Any],
                            target: MqttPeerChatProjection.Destination) throws -> MqttSignalSendRequest {
    let fields: Set<String> = ["type", "task_id", "client_route_id", "conversation_id", "turn_id", "contact_id",
      "source_message_id", "agent_id", "desktop_id", "time"]
    let source = payload.string("source_message_id")
    guard Set(payload.keys) == fields, payload.string("type") == "agent_task_cancel",
          payload.string("desktop_id") == target.peer.remoteSignalName,
          try MqttRouteProtocol.integer(payload, "time") > 0,
          (Int64(source) ?? 0) > 0 || UUID(uuidString: source) != nil else { throw MqttRouteError.invalidPayload }
    let contact = try contact(payload, target: target)
    guard contact.trustState == .verified,
          let registered = identities.identity(contactId: contact.id, sourceMessageId: source),
          registered.isComplete, registered.clientRouteId == target.routeId,
          registered.conversationId == payload.string("conversation_id"), registered.turnId == payload.string("turn_id"),
          registered.taskId == payload.string("task_id") else { throw MqttRouteError.identityChanged }
    let identity = try MqttBusinessIdentity(target.peer.binding)
    var application = payload
    application["source_message_id"] = source
    let digest = MqttRouteProtocol.digest(try MqttBusinessStorage.payload(application))
    application["message_id"] = try MqttPeerChatProjection.stableID([identity.binding, "desktop-task-cancel", digest])
    // Route ownership remains with the paired device even when the task's authorization was revoked.
    return try MqttSignalSendRequest(identity: identity, payload: application, remoteName: target.peer.remoteSignalName,
      topic: target.peer.binding.sendTopic, clientRouteID: target.routeId, traffic: .control, contactID: target.contactId)
  }

  func outgoingRequests(_ payload: [String: Any], target: MqttPeerChatProjection.Destination,
                        attachments: [AgentPreparedOutboundAttachment], blobTransfers: Set<String>,
                        ownerContactID: String? = nil) throws -> [MqttSignalSendRequest] {
    let contact = try contact(payload, target: target)
    let ids = Set(attachments.map(\.transferId))
    guard payload.string("type") == "text", Self.handles(payload), attachments.count <= 10,
          ids.count == attachments.count, blobTransfers.isSubset(of: ids),
          !attachments.isEmpty || payload["attachments"] == nil || (payload["attachments"] as? [Any])?.isEmpty == true else {
      throw MqttRouteError.invalidPayload
    }
    var application = payload
    let source = payload.string("source_message_id").ifBlank(payload.string("client_message_id"))
    let messageID = payload.string("message_id")
    guard let uuid = UUID(uuidString: messageID), !source.isBlank else { throw MqttRouteError.invalidPayload }
    if let sourceID = UUID(uuidString: source) {
      guard let owner = try taskOwner(source: source, id: sourceID, contact: contact, target: target,
        requiresTeam: payload["agent_team_message"] as? Bool == true), owner.maySend,
            owner.matches(payload), ownerContactID == nil || owner.message.contactId == ownerContactID else {
        throw MqttRouteError.identityChanged
      }
      if !attachments.isEmpty, uuid != sourceID { throw MqttRouteError.invalidPayload }
    } else if !attachments.isEmpty || payload["agent_team_message"] as? Bool == true || (Int64(source) ?? 0) <= 0 {
      throw MqttRouteError.invalidPayload
    }
    application["message_id"] = uuid.uuidString
    let identity = try MqttBusinessIdentity(target.peer.binding)
    let declarations = try attachments.compactMap { attachment -> MqttSignalSendRequest? in
      guard matchesAttachment(attachment, payload: application, target: target, contactID: contact.id, source: source)
      else { throw MqttRouteError.identityChanged }
      if blobTransfers.contains(attachment.transferId) { return nil }
      let at = try MqttRouteProtocol.integer(payload, "time")
      var manifest = attachment.manifestPayload(resume: false, nowMillis: at)
      manifest["message_id"] = try MqttPeerChatProjection.stableID([identity.binding, source, attachment.transferId, "agent-manifest"])
      return try MqttSignalSendRequest(identity: identity, payload: manifest, remoteName: target.peer.remoteSignalName,
        topic: target.peer.binding.sendTopic, clientRouteID: target.routeId, traffic: .control,
        requiresValidatedNetwork: attachment.requiresValidatedNetwork, attachmentTransferID: attachment.transferId,
        sourceMessageID: source, contactID: contact.id)
    }
    if !attachments.isEmpty { application["attachments"] = attachments.map { $0.descriptor() } }
    let body = try MqttSignalSendRequest(identity: identity, payload: application,
      remoteName: target.peer.remoteSignalName, topic: target.peer.binding.sendTopic, clientRouteID: target.routeId,
      requiresValidatedNetwork: attachments.contains { $0.requiresValidatedNetwork },
      attachmentDependencies: Array(ids), sourceMessageID: source, contactID: contact.id,
      blobAttachmentDependencies: Array(blobTransfers))
    return declarations + [body]
  }

  private func sourceMessage(_ id: UUID, contactID: String, conversation: String, turn: String) -> ChatMessage? {
    guard let saved = store.persistedOutboundTransportSource(id: id), saved.turnId.ifBlank(id.uuidString) == turn,
          AgentTaskIdentityPolicy.conversationId(contactId: contactID, requested: saved.conversationId) == conversation
    else { return nil }
    if let session = store.agentSession(id: conversation) {
      guard !session.privateMode, !session.trackingPaused, session.mergedIntoConversationId.isBlank else { return nil }
    } else if saved.contactId != contactID || conversation.hasPrefix("ios-agent-") {
      return nil
    }
    guard ![id.uuidString, turn].contains(where: {
      guard let task = store.agentTask(id: $0) else { return false }
      return task.sessionId == conversation && task.phase == .cancelled
    }) else { return nil }
    return saved
  }

  private func matchesAttachment(_ attachment: AgentPreparedOutboundAttachment, payload: [String: Any],
                                 target: MqttPeerChatProjection.Destination, contactID: String, source: String) -> Bool {
    let scope = attachment.scope
    return scope.attachmentRequestId == nil && scope.clientMessageId == source &&
      scope.contactId == contactID && scope.desktopId == target.peer.remoteSignalName &&
      scope.clientRouteId == target.routeId && scope.conversationId == payload.string("conversation_id") &&
      scope.taskId == payload.string("task_id") && scope.turnId == payload.string("turn_id")
  }

  private func taskOwner(source: String, id: UUID, contact: GalaxySSIContact,
                         target: MqttPeerChatProjection.Destination, requiresTeam: Bool = false) throws -> TaskOwner? {
    guard let identity = identities.identity(contactId: contact.id, sourceMessageId: source),
          identity.clientRouteId == target.routeId else { return nil }
    if !requiresTeam, let ordinary = sourceMessage(id, contactID: contact.id,
      conversation: identity.conversationId, turn: identity.turnId) { return TaskOwner(message: ordinary) }
    return try resolveTeamOwner?(source, contact, identity, target)
  }

  func attachmentOwner(_ attachment: AgentPreparedOutboundAttachment, body: MqttSignalSendRequest,
                       target: MqttPeerChatProjection.Destination) throws -> TaskOwner? {
    let payload = try body.applicationPayload()
    let contact = try contact(payload, target: target)
    guard body.contactID == contact.id, let id = UUID(uuidString: body.sourceMessageID), body.messageID == id.uuidString,
          matchesAttachment(attachment, payload: payload, target: target, contactID: contact.id, source: body.sourceMessageID)
    else { throw MqttRouteError.identityChanged }
    guard let owner = try taskOwner(source: body.sourceMessageID, id: id, contact: contact, target: target,
      requiresTeam: payload["agent_team_message"] as? Bool == true),
          owner.matches(payload) else { return nil }
    return owner
  }

  func isCurrentSendOwner(contactID: String, source: String, target: MqttPeerChatProjection.Destination) -> Bool {
    guard target.desktop, let contact = store.contact(id: contactID), contact.id == contactID, contact.isCommunicable,
          !contact.isDesktopDeviceContact, contact.desktopId == target.peer.remoteSignalName,
          contact.deliveryMode.isGalaxySSILinkFamily, !contact.connectorAgentId.isBlank,
          let identity = identities.identity(contactId: contactID, sourceMessageId: source),
          identity.clientRouteId == target.routeId else { return false }
    guard let id = UUID(uuidString: source) else { return (Int64(source) ?? 0) > 0 }
    return (try? taskOwner(source: source, id: id, contact: contact, target: target))?.maySend == true
  }

  func project(_ item: MqttBusinessInbox.Pending, payload: [String: Any],
               target: MqttPeerChatProjection.Destination) throws {
    guard try MqttBusinessIdentity(target.peer.binding) == item.identity,
          item.key == (try item.identity.key(messageID: item.messageID)),
          payload.string("message_id") == item.messageID, Self.handles(payload) else {
      throw MqttRouteError.invalidPayload
    }
    if ["agent_task_recovery_result", "agent_task_result_page"].contains(payload.string("type")) {
      guard target.desktop, payload.string("client_route_id") == target.routeId,
            payload.string("desktop_id").ifBlank(target.peer.remoteSignalName) == target.peer.remoteSignalName,
            let receiveRecoveryControl else { throw MqttRouteError.identityChanged }
      let fields: [String: Any]
      if payload.string("type") == "agent_task_recovery_result" {
        guard let items = payload["items"] as? [[String: Any]], items.count == 1,
              let item = items.first else { throw MqttRouteError.invalidPayload }
        fields = item
      } else { fields = payload }
      _ = try contact(fields, target: target)
      try receiveRecoveryControl(payload, target.peer.remoteSignalName)
      return
    }
    let contact = try contact(payload, target: target)
    if payload.string("type") == "agent_task_result_receipt_confirmed" {
      guard let recovery = resultRecovery?(),
            let receipt = AgentResultReceipt.confirmedPayload(payload, desktopId: target.peer.remoteSignalName),
            let state = recovery.receipts.recordedState(receipt) else { throw MqttRouteError.unsolicitedAcknowledgement }
      if state == .pending, !recovery.receipts.confirm(receipt) { throw MqttChunkStorageError.databaseFailure }
      return
    }
    if payload.string("type") == "agent_task_event" {
      let source = payload.string("source_message_id")
      guard let id = UUID(uuidString: source), let owner = try taskOwner(source: source, id: id, contact: contact, target: target),
            owner.maySend else { throw MqttRouteError.invalidPayload }
      if let team = owner.team {
        guard let recordTeamProgress, try recordTeamProgress(payload, team) else { return }
        if team.deliveryMode == .observe { return }
      }
      let saved = owner.message
      guard
            saved.conversationId == payload.string("conversation_id"),
            saved.turnId.ifBlank(saved.id.uuidString) == payload.string("turn_id"),
            let session = store.agentSession(id: saved.conversationId),
            !session.privateMode, !session.trackingPaused else { throw MqttRouteError.invalidPayload }
      let updates = AgentConnectorPublicProgress.entries(payload) { key, fallback in
        GalaxySSILocalization.string(key, fallback: fallback, language: store.languagePolicy.interfaceLanguage)
      }
      guard !updates.isEmpty else { throw MqttRouteError.invalidPayload }
      guard store.persistConnectorProgress(sourceId: saved.id, conversationId: saved.conversationId,
        turnId: payload.string("turn_id"), updates: updates) == true else { throw MqttChunkStorageError.databaseFailure }
      return
    }
    if payload.string("type") == "text", AgentDesktopReplyRecovery.terminalStatuses.contains(payload.string("task_status")),
       let receipt = AgentResultReceipt.fromPayload(payload, desktopId: target.peer.remoteSignalName),
       let terminalResult {
      try terminalResult(payload, receipt)
      return
    }
    let source = payload.string("source_message_id")
    if let id = UUID(uuidString: source),
       try taskOwner(source: source, id: id, contact: contact, target: target)?.team != nil {
      throw MqttRouteError.invalidPayload
    }
    guard payload["result_recovery"] == nil,
          AgentResultReceipt.fromPayload(payload, desktopId: target.peer.remoteSignalName) == nil,
          let response = AgentConnectorResponse.fromPayload(payload, nowMillis: item.createdAt) else {
      throw MqttRouteError.invalidPayload
    }
    try commitResponse(response, payload)
  }

  func validateResultReceipt(_ receipt: AgentResultReceipt, target: MqttPeerChatProjection.Destination) throws {
    guard receipt.desktopId == target.peer.remoteSignalName else { throw MqttRouteError.identityChanged }
    _ = try contact(receipt.payload, target: target)
  }

  func recoveryQueryRequest(_ payload: [String: Any], target: MqttPeerChatProjection.Destination) throws -> MqttSignalSendRequest {
    guard target.desktop, payload.string("desktop_id") == target.peer.remoteSignalName,
          payload.string("client_route_id") == target.routeId,
          let id = UUID(uuidString: payload.string("request_id")), id.uuidString == payload.string("request_id") else {
      throw MqttRouteError.identityChanged
    }
    switch payload.string("type") {
    case "agent_task_recovery_request":
      guard let items = payload["items"] as? [[String: Any]], items.count == 1, let item = items.first else {
        throw MqttRouteError.invalidPayload
      }
      _ = try contact(item, target: target)
    case "agent_task_result_page_request":
      _ = try contact(payload, target: target)
    default: throw MqttRouteError.invalidPayload
    }
    var application = payload
    application["message_id"] = id.uuidString
    return try MqttSignalSendRequest(identity: MqttBusinessIdentity(target.peer.binding), payload: application,
      remoteName: target.peer.remoteSignalName, topic: target.peer.binding.sendTopic, clientRouteID: target.routeId,
      traffic: .control, contactID: target.contactId)
  }

  func evidenceQueryRequest(_ request: AgentDesktopToolEvidenceWire.Request, payload: [String: Any],
                            target: MqttPeerChatProjection.Destination) throws -> MqttSignalSendRequest {
    guard target.desktop, request.binding.desktopId == target.peer.remoteSignalName,
          request.binding.matches(payload), request.nonce == payload.string("request_id"),
          UUID(uuidString: request.nonce)?.uuidString == request.nonce,
          payload.string("type") == "agent_task_evidence_request",
          payload.string("contract") == AgentDesktopToolEvidenceWire.contract,
          ["index", "page"].contains(payload.string("mode")),
          AgentDesktopReplyRecovery.integer(payload["execution_generation"], minimum: 1) == request.generation
    else { throw MqttRouteError.invalidPayload }
    _ = try contact(payload, target: target)
    var application = payload
    application["message_id"] = request.nonce
    return try MqttSignalSendRequest(identity: MqttBusinessIdentity(target.peer.binding), payload: application,
      remoteName: target.peer.remoteSignalName, topic: target.peer.binding.sendTopic, clientRouteID: target.routeId,
      traffic: .control, contactID: target.contactId)
  }

  func resultReceiptRequest(_ work: AgentResultReceiptWork, target: MqttPeerChatProjection.Destination) throws -> MqttSignalSendRequest {
    let receipt = work.receipt
    guard work.state == .pending, (0...30).contains(work.attempts) else { throw MqttRouteError.invalidPayload }
    try validateResultReceipt(receipt, target: target)
    let identity = try MqttBusinessIdentity(target.peer.binding)
    var payload = receipt.payload
    payload["message_id"] = try MqttPeerChatProjection.stableID(
      [identity.binding, receipt.id, String(work.attempts), String(work.dueAtMillis), "result-receipt"])
    return try MqttSignalSendRequest(identity: identity, payload: payload, remoteName: target.peer.remoteSignalName,
      topic: target.peer.binding.sendTopic, clientRouteID: target.routeId, traffic: .control, contactID: target.contactId)
  }

  func projectCompletion(_ event: MqttDeliveryCompletions.Event, target: MqttPeerChatProjection.Destination) throws {
    guard target.desktop, let contact = store.contact(id: event.contactID), contact.id == event.contactID,
          contact.isCommunicable, !contact.isDesktopDeviceContact,
          contact.desktopId == target.peer.remoteSignalName, contact.deliveryMode.isGalaxySSILinkFamily,
          event.traffic == MqttMultipathPolicy.Traffic.message.rawValue, event.attachmentTransferID.isEmpty,
          let identity = identities.identity(contactId: contact.id, sourceMessageId: event.sourceMessageID),
          identity.clientRouteId == target.routeId else { throw MqttRouteError.identityChanged }
    guard let id = UUID(uuidString: event.sourceMessageID) else { return }
    guard let owner = try taskOwner(source: event.sourceMessageID, id: id, contact: contact, target: target),
          owner.team == nil
    else { return }
    do { try store.persistTransportDelivery(event, messageContactID: owner.message.contactId) }
    catch GalaxySSIChatHistoryError.locallyDeleted { }
  }
}
