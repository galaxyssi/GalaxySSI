import XCTest
@testable import GalaxySSI

// Journal native-delivery acceptance fixtures; source only unless executed by XCTest.
extension GalaxySSIStoreTests {
  private struct NativeDeliveryFixture {
    var action: AgentAction
    var pending: AgentActionResult
    var managed: AgentManagedResponseRecord
    var event: MqttDeliveryCompletions.Event
    var identity: AgentTaskIdentity
    var business: MqttBusinessIdentity
    var topic: String

    func apply() throws -> AgentActionResult? {
      try AgentNativeConnectorTransportAcceptance.apply(action: action, pending: pending, managed: managed,
        event: event, taskIdentity: identity, expectedIdentity: business, expectedTopic: topic, expectedRouteID: "route")
    }

    mutating func changeEvent(_ key: String, _ value: Any) throws {
      var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
      object[key] = value
      event = try JSONDecoder().decode(MqttDeliveryCompletions.Event.self, from: JSONSerialization.data(withJSONObject: object))
    }
  }

  private func nativeDeliveryFixture(attachments: Bool = false) throws -> NativeDeliveryFixture {
    let action = actionExecutorConnectorAction(parameters: ["_galaxyssi_task_id": "turn",
      "_galaxyssi_session_id": "conversation", AgentIOSConnectorDispatch.sourceKey: UUID().uuidString,
      AgentIOSConnectorDispatch.profileKey: "profile", AgentIOSConnectorDispatch.permissionKey: "approved-mode"])
    var pending = AgentIOSConnectorDispatch.prepare(action)
    pending.metadata.removeValue(forKey: "remote_task_status")
    pending.metadata["resource_started_at"] = "1000"
    pending.metadata["control_plane_agent_id"] = "codex"
    let owner = AgentControlPlaneActionExecutor.connectorRunId(action: action, agentId: "codex")
    pending.metadata["control_plane_run_id"] = owner
    let task = try XCTUnwrap(pending.metadata["task_id"])
    let source = try XCTUnwrap(pending.metadata["source_message_id"].flatMap(Int64.init))
    if attachments {
      pending.metadata["has_attachments"] = "true"
      pending.metadata["native_connector_attachment_body_id"] = try XCTUnwrap(UUID(uuidString: task)).uuidString
    }
    let managed = AgentManagedResponseRecord(ownerRunId: owner, supervisorRunId: "parent", agentId: "codex",
      deliveryMode: .respond, sourceMessageId: source, contactId: "codex", conversationId: "conversation",
      turnId: "turn", taskId: task, executionGeneration: 1, createdAtMillis: 1_000)
    let topic = String(repeating: "A", count: 43)
    let business = try MqttBusinessIdentity(MqttPeerBinding(scope: "native-delivery-test",
      sender: String(repeating: "a", count: 64), receiver: String(repeating: "b", count: 64),
      secret: Data(repeating: 7, count: 32).base64URLEncodedString(), sendTopic: topic,
      sendTopics: [topic], receiveTopics: [topic]))
    let message = try XCTUnwrap(UUID(uuidString: attachments ? task : owner)).uuidString
    let event = MqttDeliveryCompletions.Event(identity: business, messageID: message,
      wireHash: String(repeating: "c", count: 64), traffic: MqttMultipathPolicy.Traffic.message.rawValue,
      requestHash: String(repeating: "d", count: 64), sourceMessageID: String(source), contactID: "codex",
      attachmentTransferID: "", receivedAt: 2_000, consumedAt: nil, topic: topic)
    return NativeDeliveryFixture(action: action, pending: pending, managed: managed, event: event,
      identity: AgentTaskIdentity(clientRouteId: "route", conversationId: "conversation", taskId: task, turnId: "turn"),
      business: business, topic: topic)
  }

  func testNativeJournalDeliveryAcceptsOnlyTheWaitingReceiptWithoutCompletingIt() throws {
    var f = try nativeDeliveryFixture()
    for key in ["effect_outcome_unknown", "non_retriable", "native_connector_dispatch_uncertain"] { f.pending.metadata[key] = "true" }
    let accepted = try XCTUnwrap(f.apply())
    XCTAssertEqual(accepted.metadata["remote_task_status"], "accepted")
    XCTAssertEqual(accepted.metadata["transport_accepted_at"], "2000")
    XCTAssertEqual(accepted.metadata["remote_task_status_updated_at"], "2000")
    for key in ["awaiting_response", "completion_verified", "control_plane_run_id", "source_message_id",
      "effect_outcome_unknown", "non_retriable", "native_connector_dispatch_uncertain"] {
      XCTAssertEqual(accepted.metadata[key], f.pending.metadata[key], key)
    }
    XCTAssertEqual(accepted.success, f.pending.success)
    XCTAssertEqual(accepted.actionId, f.pending.actionId)
    XCTAssertEqual(try JSONDecoder().decode(AgentActionResult.self, from: JSONEncoder().encode(accepted)), accepted)
  }

  func testNativeJournalDeliveryReplayDoesNotRefreshAcceptance() throws {
    var f = try nativeDeliveryFixture()
    f.pending = try XCTUnwrap(f.apply())
    XCTAssertNil(try f.apply())
    try f.changeEvent("receivedAt", 10_000)
    XCTAssertNil(try f.apply())
    XCTAssertEqual(f.pending.metadata["transport_accepted_at"], "2000")
  }

  func testNativeJournalDeliveryPreservesLaterRemoteStatusAndItsClock() throws {
    for status in ["queued", "running", "completed", "failed"] {
      var f = try nativeDeliveryFixture()
      f.pending.metadata["remote_task_status"] = status
      f.pending.metadata["remote_task_status_updated_at"] = "5000"
      f.pending.metadata["remote_task_status_seq"] = "4"
      let accepted = try XCTUnwrap(f.apply())
      XCTAssertEqual(accepted.metadata["remote_task_status"], status)
      XCTAssertEqual(accepted.metadata["remote_task_status_updated_at"], "5000")
      XCTAssertEqual(accepted.metadata["remote_task_status_seq"], "4")
      XCTAssertEqual(accepted.metadata["transport_accepted_at"], "2000")
      XCTAssertEqual(accepted.metadata["awaiting_response"], "true")
    }
  }

  func testNativeJournalDeliveryRejectsForeignOrNonMessageCompletions() throws {
    let mutations: [(String, Any)] = [("sourceMessageID", "123"), ("contactID", "foreign"),
      ("messageID", UUID().uuidString), ("traffic", MqttMultipathPolicy.Traffic.control.rawValue),
      ("attachmentTransferID", String(repeating: "e", count: 64)), ("wireHash", "invalid"),
      ("requestHash", NSNull()), ("topic", "foreign"), ("receivedAt", 999), ("consumedAt", 3_000)]
    for (key, value) in mutations {
      var f = try nativeDeliveryFixture()
      try f.changeEvent(key, value)
      XCTAssertThrowsError(try f.apply(), key)
    }
    var foreign = try nativeDeliveryFixture()
    try foreign.changeEvent("identity", ["scope": "other", "binding": String(repeating: "e", count: 64),
      "local": foreign.business.local, "remote": foreign.business.remote])
    XCTAssertThrowsError(try foreign.apply())
  }

  func testNativeJournalDeliveryRejectsForeignManagedAndTaskScopes() throws {
    for field in ["owner", "agent", "source", "contact", "conversation", "turn", "task", "generation", "state"] {
      var f = try nativeDeliveryFixture()
      switch field {
      case "owner": f.managed.ownerRunId = "foreign"
      case "agent": f.managed.agentId = "foreign"
      case "source": f.managed.sourceMessageId += 1
      case "contact": f.managed.contactId = "foreign"
      case "conversation": f.managed.conversationId = "foreign"
      case "turn": f.managed.turnId = "foreign"
      case "task": f.managed.taskId = "foreign"
      case "generation": f.managed.executionGeneration += 1
      default: f.managed.state = .completed
      }
      XCTAssertThrowsError(try f.apply(), field)
    }
    for field in ["route", "conversation", "turn", "task"] {
      var f = try nativeDeliveryFixture()
      switch field {
      case "route": f.identity.clientRouteId = "foreign"
      case "conversation": f.identity.conversationId = "foreign"
      case "turn": f.identity.turnId = "foreign"
      default: f.identity.taskId = "foreign"
      }
      XCTAssertThrowsError(try f.apply(), field)
    }
  }

  func testNativeJournalAttachmentDeliveryRequiresTheSavedFinalBody() throws {
    var f = try nativeDeliveryFixture(attachments: true)
    XCTAssertNotNil(try f.apply())
    try f.changeEvent("messageID", try XCTUnwrap(UUID(uuidString: f.managed.ownerRunId)).uuidString)
    XCTAssertThrowsError(try f.apply())
    f = try nativeDeliveryFixture(attachments: true)
    f.pending.metadata.removeValue(forKey: "native_connector_attachment_body_id")
    XCTAssertThrowsError(try f.apply())
  }

  @MainActor
  func testNativeNumericCompletionInvokesTheRegisteredWriterAndPropagatesFailure() throws {
    let store = makeStore()
    let link = try store.addServerLink(from: makePairingQRCode())
    store.markServerPaired(desktopId: link.desktopId)
    let desktop = try XCTUnwrap(store.contacts.first { $0.isDesktopDeviceContact && $0.desktopId == link.desktopId })
    let agent = try XCTUnwrap(store.contact(id: "\(link.desktopId):codex"))
    let projection = MqttPeerChatProjection(store: store, localFingerprint: link.routes.localFingerprint)
    let target = try XCTUnwrap(projection.destination(for: desktop))
    let identity = AgentTaskIdentity(clientRouteId: target.routeId, conversationId: "conversation", taskId: "task", turnId: "turn")
    let identities = AgentTaskIdentityStore(defaults: store.defaults, storageKeyPrefix: "native-completion-fixture")
    XCTAssertTrue(identities.register(contactId: agent.id, sourceMessageId: "123", identity: identity))
    let event = MqttDeliveryCompletions.Event(identity: try MqttBusinessIdentity(target.peer.binding),
      messageID: UUID().uuidString, wireHash: String(repeating: "c", count: 64), traffic: "message",
      requestHash: String(repeating: "d", count: 64), sourceMessageID: "123", contactID: agent.id,
      attachmentTransferID: "", receivedAt: 2_000, consumedAt: nil, topic: target.peer.binding.sendTopic)
    var connector = MqttDesktopConnectorProjection(store: store, identities: identities, commitResponse: { _, _ in })
    XCTAssertThrowsError(try connector.projectCompletion(event, target: target))
    var calls = 0
    var reject = true
    connector.recordManagedTransportAccepted = { received, registered, destination in
      calls += 1
      XCTAssertEqual(received, event)
      XCTAssertEqual(registered, identity)
      XCTAssertEqual(destination.routeId, target.routeId)
      if reject { throw MqttChunkStorageError.databaseFailure }
    }
    XCTAssertThrowsError(try connector.projectCompletion(event, target: target))
    XCTAssertEqual(calls, 1)
    reject = false
    try connector.projectCompletion(event, target: target)
    XCTAssertEqual(calls, 2)
  }
}

final class AgentConnectorTransportReceiptRecorderTests: XCTestCase {
  func testRecorderStoresTransportAcceptedMetadata() {
    let pending = AgentActionResult(
      actionId: "action",
      success: true,
      message: "Waiting",
      metadata: [
        "awaiting_response": "true",
        "source_message_id": "91",
        "contact_id": "codex"
      ]
    )

    let updated = AgentConnectorTransportReceiptRecorder.recordAccepted(
      pending: pending,
      sourceMessageId: 91,
      contactId: "codex",
      nowMillis: 6000
    )

    XCTAssertEqual(updated?.success, true)
    XCTAssertEqual(updated?.metadata["awaiting_response"], "true")
    XCTAssertEqual(updated?.metadata["remote_task_status"], "accepted")
    XCTAssertEqual(updated?.metadata["remote_task_status_updated_at"], "6000")
    XCTAssertEqual(updated?.metadata["transport_accepted_at"], "6000")
  }

  func testRecorderPreservesExistingRemoteTaskStatusAndRejectsWrongContact() {
    let pending = AgentActionResult(
      actionId: "action",
      success: true,
      message: "Waiting",
      metadata: [
        "awaiting_response": "true",
        "source_message_id": "91",
        "contact_id": "codex",
        "remote_task_status": "running"
      ]
    )

    let wrongContact = AgentConnectorTransportReceiptRecorder.recordAccepted(
      pending: pending,
      sourceMessageId: 91,
      contactId: "other",
      nowMillis: 6000
    )
    let accepted = AgentConnectorTransportReceiptRecorder.recordAccepted(
      pending: pending,
      sourceMessageId: 91,
      contactId: "codex",
      nowMillis: 7000
    )

    XCTAssertNil(wrongContact)
    XCTAssertEqual(accepted?.metadata["remote_task_status"], "running")
    XCTAssertEqual(accepted?.metadata["remote_task_status_updated_at"], "7000")
    XCTAssertEqual(accepted?.metadata["transport_accepted_at"], "7000")
  }
}

extension GalaxySSIStoreTests {
  func testActionExecutorAgentProviderRecordsConnectorTransportAccepted() async throws {
    let registration = actionExecutorRegistration()
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Waiting",
        metadata: [
          "awaiting_response": "true",
          "source_message_id": "91",
          "contact_id": "codex"
        ]
      )
    }
    let provider = ActionExecutorAgentProvider(
      registrationSource: { [registration] },
      delegate: delegate
    )
    let adapter = try XCTUnwrap(try await provider.adapter(agentId: "codex"))
    let request = AgentRunRequest(
      conversationId: "conversation",
      messageId: "turn",
      taskId: "turn",
      runId: "run-transport-accepted",
      goal: "Inspect project",
      context: ["managed_team": .bool(true)],
      idempotencyKey: "run-transport-accepted"
    )
    provider.prepare(
      agentId: "codex",
      request: request,
      action: actionExecutorConnectorAction(),
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")
    )

    _ = try await adapter.startRun(request)
    let accepted = provider.recordConnectorTransportAccepted(
      sourceMessageId: 91,
      contactId: "codex",
      nowMillis: 6000
    )
    let running = provider.recordConnectorTaskStatus(
      sourceMessageId: 91,
      contactId: "codex",
      taskId: "task-91",
      taskStatus: "running",
      statusSeq: 2,
      nowMillis: 7000
    )

    XCTAssertEqual(accepted?.metadata["remote_task_status"], "accepted")
    XCTAssertEqual(accepted?.metadata["transport_accepted_at"], "6000")
    XCTAssertEqual(running?.metadata["remote_task_status"], "running")
    XCTAssertEqual(running?.metadata["transport_accepted_at"], "6000")
  }
}
