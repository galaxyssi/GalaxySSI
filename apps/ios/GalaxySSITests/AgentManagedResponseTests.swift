import XCTest
@testable import GalaxySSI

// Native query ownership fixtures; these do not publish MQTT or start a connector.
extension GalaxySSIStoreTests {
  private func nativeQueryRecord() -> AgentManagedResponseRecord {
    AgentManagedResponseRecord(ownerRunId: "native-owner", supervisorRunId: "parent", agentId: "agent",
      deliveryMode: .respond, sourceMessageId: 73, contactId: "desktop:codex", conversationId: "conversation",
      turnId: "turn", taskId: "remote-task", nativeQueryScope: AgentNativeConnectorQueryScope(
        profile: "profile-a", actionId: "action", outgoingId: UUID()))
  }

  func testNativeQueryScopeRoundTripsBothRecordCodecs() throws {
    let record = nativeQueryRecord()
    XCTAssertEqual(try JSONDecoder().decode(AgentManagedResponseRecord.self,
      from: JSONEncoder().encode(record)), record)
    XCTAssertEqual(AgentManagedResponseCodec.decode(AgentManagedResponseCodec.encode([record])), [record])
  }

  func testLegacyManagedRecordHasNoInventedNativeScope() throws {
    var record = nativeQueryRecord()
    record.nativeQueryScope = nil
    let data = try JSONEncoder().encode(record)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertNil(object["native_query_scope"])
    XCTAssertNil(try JSONDecoder().decode(AgentManagedResponseRecord.self, from: data).nativeQueryScope)
    XCTAssertEqual(AgentManagedResponseCodec.decode(AgentManagedResponseCodec.encode([record])), [record])
  }

  func testMalformedNativeScopeCannotDecodeAsLegacyOwner() throws {
    let record = nativeQueryRecord()
    let encoded = try JSONEncoder().encode(record)
    let initial = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let invalidValues: [Any] = [NSNull(), ["profile": "", "actionId": "action", "outgoingId": UUID().uuidString],
      ["profile": "profile-a", "actionId": "action", "outgoingId": "invalid"]]
    for value in invalidValues {
      var object = initial
      object["native_query_scope"] = value
      let data = try JSONSerialization.data(withJSONObject: object)
      XCTAssertThrowsError(try JSONDecoder().decode(AgentManagedResponseRecord.self, from: data))
      let array = try JSONSerialization.data(withJSONObject: [object])
      XCTAssertTrue(AgentManagedResponseCodec.decode(try XCTUnwrap(String(data: array, encoding: .utf8))).isEmpty)
    }
  }

  func testNativeQueryScopeSurvivesLateCompletionAndAcknowledgement() throws {
    let record = nativeQueryRecord()
    let ledger = InMemoryAgentManagedResponseLedger()
    try ledger.register(record)
    let response = AgentConnectorResponse(sourceMessageId: record.sourceMessageId, contactId: record.contactId,
      content: "Original late result", conversationId: record.conversationId, turnId: record.turnId,
      taskId: record.taskId, success: true)
    XCTAssertEqual(ledger.complete(response)?.nativeQueryScope, record.nativeQueryScope)
    XCTAssertEqual(ledger.acknowledge(response)?.nativeQueryScope, record.nativeQueryScope)
  }

  func testPersistedNativeQueryScopeRejectsSameGenerationOwnerSubstitution() throws {
    let suite = "native-query-owner-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("managed.sqlite"), secrets = InMemorySecretStore()
    let record = nativeQueryRecord()
    do {
      let ledger = UserDefaultsAgentManagedResponseLedger(defaults: defaults, fileURL: file, secrets: secrets)
      try ledger.register(record)
      var substituted = record
      substituted.nativeQueryScope = AgentNativeConnectorQueryScope(profile: "other-profile",
        actionId: "action", outgoingId: UUID())
      XCTAssertThrowsError(try ledger.register(substituted))
      substituted.nativeQueryScope = nil
      XCTAssertThrowsError(try ledger.register(substituted))
    }
    let reopened = UserDefaultsAgentManagedResponseLedger(defaults: defaults, fileURL: file, secrets: secrets)
    XCTAssertEqual(try reopened.recoveryRecord(owner: record.ownerRunId), record)
  }

  func testNativeQueryScopeCaptureRequiresHostBoundDispatchOwner() throws {
    let outgoing = UUID()
    let action = AgentAction(id: "action", kind: .callConnector, target: "desktop:codex", risk: .low,
      status: .running, description: "Request", parameters: ["connector_id": "desktop:codex", "prompt": "Hello",
        "_galaxyssi_conversation_id": "conversation", "_galaxyssi_turn_id": "turn", "_galaxyssi_task_id": "turn",
        "_galaxyssi_session_id": "session", AgentIOSConnectorDispatch.sourceKey: outgoing.uuidString,
        AgentIOSConnectorDispatch.profileKey: "profile-a", AgentIOSConnectorDispatch.permissionKey: "approved"],
      requiresConfirmation: false)
    var receipt = AgentIOSConnectorDispatch.prepare(action)
    receipt.metadata["control_plane_agent_id"] = "agent"
    receipt.metadata["control_plane_run_id"] = AgentControlPlaneActionExecutor.connectorRunId(action: action, agentId: "agent")
    let scope = try XCTUnwrap(AgentNativeConnectorQueryScope.capture(action: action, receipt: receipt))
    XCTAssertEqual(scope.outgoingId, outgoing)
    XCTAssertEqual(scope.profile, "profile-a")
    receipt.metadata["control_plane_run_id"] = "substituted-owner"
    XCTAssertNil(AgentNativeConnectorQueryScope.capture(action: action, receipt: receipt))
  }
}

extension GalaxySSIStoreTests {
  func testManagedCollaborationRepliesRecoverAfterExtendedOfflineReopen() throws {
    let suite = "offline-managed-response-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("managed.sqlite")
    let secrets = InMemorySecretStore()
    let start: Int64 = 1_000
    let reconnect = start + AgentManagedResponseRecord.maxAgeMillis + 10_000
    let reply = AgentConnectorResponse(sourceMessageId: 41, contactId: "observer",
      content: "Original evidence", conversationId: "group", turnId: "turn",
      taskId: "task-41", receivedAtMillis: start + 1, executionGeneration: 2)
    do {
      let ledger = UserDefaultsAgentManagedResponseLedger(defaults: defaults, nowMillis: { start },
        fileURL: file, secrets: secrets)
      for source in [Int64(41), 42] {
        try ledger.register(AgentManagedResponseRecord(ownerRunId: "run-\(source)", supervisorRunId: "team",
          agentId: "observer", deliveryMode: .observe, sourceMessageId: source, contactId: "observer",
          conversationId: "group", turnId: "turn", taskId: "task-\(source)", executionGeneration: 2,
          createdAtMillis: start))
      }
      XCTAssertEqual(ledger.complete(reply)?.state, .completed)
    }
    let reopened = UserDefaultsAgentManagedResponseLedger(defaults: defaults, nowMillis: { reconnect },
      fileURL: file, secrets: secrets)
    XCTAssertEqual(reopened.completedUnapplied().compactMap(\.response), [reply])
    XCTAssertEqual(reopened.pendingForSupervisor("team").map(\.sourceMessageId), [42])

    var wrongGeneration = AgentConnectorResponse(sourceMessageId: 42, contactId: "observer",
      content: "Delayed evidence", conversationId: "group", turnId: "turn",
      taskId: "task-42", receivedAtMillis: reconnect, executionGeneration: 1)
    XCTAssertNil(reopened.complete(wrongGeneration))
    wrongGeneration.executionGeneration = 2
    XCTAssertEqual(reopened.complete(wrongGeneration)?.state, .completed)
    var duplicate = reply
    duplicate.content = "Duplicate must not overwrite evidence"
    XCTAssertEqual(reopened.complete(duplicate)?.response, reply)
    XCTAssertEqual(reopened.acknowledge(reply)?.state, .applied)
    XCTAssertEqual(reopened.completedUnapplied().compactMap(\.response), [wrongGeneration])
  }

  func testOfflineUnappliedResponsesDoNotExpire() {
    var record = AgentManagedResponseRecord(ownerRunId: "member", supervisorRunId: "team",
      agentId: "observer", deliveryMode: .observe, sourceMessageId: 42, contactId: "observer",
      createdAtMillis: 1)
    let now = AgentManagedResponseRecord.maxAgeMillis + 10_000
    XCTAssertFalse(record.isStale(nowMillis: now))
    record.state = .completed
    XCTAssertFalse(record.isStale(nowMillis: now))
    record.state = .applied
    XCTAssertTrue(record.isStale(nowMillis: now))
  }

  func testAgentManagedResponseLedgerCompletesAcknowledgesAndPublishesLateResponses() throws {
    let ledger = InMemoryAgentManagedResponseLedger()
    AgentLateManagedResponseBus.shared.clear()
    var lateResponses: [AgentManagedResponseRecord] = []
    let token = AgentLateManagedResponseBus.shared.addListener { lateResponses.append($0) }
    defer {
      AgentLateManagedResponseBus.shared.removeListener(token)
    }

    try ledger.register(AgentManagedResponseRecord(
      ownerRunId: "child-old",
      supervisorRunId: "supervisor",
      agentId: "observer",
      deliveryMode: .observe,
      sourceMessageId: 41,
      contactId: "observer",
      createdAtMillis: 1_000
    ))
    try ledger.register(AgentManagedResponseRecord(
      ownerRunId: "child-primary",
      supervisorRunId: "supervisor",
      agentId: "primary",
      deliveryMode: .respond,
      sourceMessageId: 42,
      contactId: "primary",
      createdAtMillis: 2_000
    ))

    XCTAssertEqual(ledger.pendingForSupervisor("supervisor").map(\.ownerRunId), ["child-old", "child-primary"])
    XCTAssertNil(ledger.complete(AgentConnectorResponse(sourceMessageId: 42, contactId: "other", content: "wrong")))

    let response = AgentConnectorResponse(
      sourceMessageId: 42,
      contactId: "",
      content: "durable final answer",
      receivedAtMillis: 9_000
    )
    let completed = try XCTUnwrap(ledger.complete(response))

    XCTAssertEqual(completed.state, .completed)
    XCTAssertEqual(completed.completedAtMillis, 9_000)
    XCTAssertEqual(lateResponses.map(\.ownerRunId), ["child-primary"])
    XCTAssertEqual(ledger.completedUnapplied().map(\.ownerRunId), ["child-primary"])

    _ = ledger.complete(AgentConnectorResponse(sourceMessageId: 42, contactId: "primary", content: "duplicate"))
    XCTAssertEqual(lateResponses.count, 1)

    let acknowledged = try XCTUnwrap(ledger.acknowledge(response))
    XCTAssertEqual(acknowledged.state, .applied)
    XCTAssertTrue(ledger.completedUnapplied().isEmpty)
    ledger.removeOwner("child-primary")
    XCTAssertEqual(ledger.pendingForSupervisor("supervisor").map(\.ownerRunId), ["child-old"])
  }

  func testAgentManagedResponseCodecUsesAndroidWireNamesAndBoundsPayloads() throws {
    let content = String(repeating: "a", count: AgentConnectorResponse.maxContentCharacters + 50)
    let rich = String(repeating: "b", count: AgentConnectorResponse.maxRichOutputCharacters + 50)
    let record = AgentManagedResponseRecord(
      ownerRunId: "child",
      supervisorRunId: "supervisor",
      agentId: "primary",
      deliveryMode: .respond,
      sourceMessageId: 77,
      contactId: "primary",
      state: .completed,
      response: AgentConnectorResponse(
        sourceMessageId: 77,
        contactId: "primary",
        content: content,
        conversationId: "conversation",
        turnId: "turn",
        taskId: "task",
        inputTokens: 11,
        outputTokens: 22,
        costMicros: 33,
        richOutputJson: rich,
        receivedAtMillis: 4_000
      ),
      createdAtMillis: 1_000,
      completedAtMillis: 4_000
    )

    let encoded = AgentManagedResponseCodec.encode([record])
    let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [[String: Any]])
    let object = try XCTUnwrap(array.first)
    let response = try XCTUnwrap(object["response"] as? [String: Any])
    let decoded = AgentManagedResponseCodec.decode(encoded)

    XCTAssertEqual(object["owner_run_id"] as? String, "child")
    XCTAssertEqual(object["supervisor_run_id"] as? String, "supervisor")
    XCTAssertEqual(object["delivery_mode"] as? String, "RESPOND")
    XCTAssertEqual(object["source_message_id"] as? Int, 77)
    XCTAssertEqual(response["source_message_id"] as? Int, 77)
    XCTAssertEqual(response["conversation_id"] as? String, "conversation")
    XCTAssertEqual(response["turn_id"] as? String, "turn")
    XCTAssertEqual(response["input_tokens"] as? Int, 11)
    XCTAssertEqual((response["content"] as? String)?.count, AgentConnectorResponse.maxContentCharacters)
    XCTAssertEqual((response["rich_output"] as? String)?.count, AgentConnectorResponse.maxRichOutputCharacters)
    XCTAssertNil(object["ownerRunId"])
    XCTAssertEqual(decoded.first?.response?.content.count, AgentConnectorResponse.maxContentCharacters)
    XCTAssertEqual(decoded.first?.response?.richOutputJson.count, AgentConnectorResponse.maxRichOutputCharacters)
    XCTAssertTrue(AgentManagedResponseCodec.decode(#"[{"owner_run_id":"","source_message_id":0}]"#).isEmpty)
  }
}
