import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testResultReceiptBindsIdentityGenerationDigestAndConfirmation() throws {
    let payload: [String: Any] = [
      "client_route_id": "route-1",
      "conversation_id": "conversation-1",
      "task_id": "task-1",
      "turn_id": "turn-1",
      "contact_id": "agent-1",
      "source_message_id": "901",
      "agent_id": "agent-1",
      "execution_generation": 3,
      "sha256": String(repeating: "a", count: 64)
    ]
    let receipt = try XCTUnwrap(AgentResultReceipt.fromPayload(payload, desktopId: "desktop-1"))
    XCTAssertEqual(receipt.payload["receipt_id"] as? String, receipt.id)

    var confirmed = receipt.payload
    confirmed["type"] = "agent_task_result_receipt_confirmed"
    XCTAssertEqual(
      AgentResultReceipt.confirmedPayload(confirmed, desktopId: "desktop-1"),
      receipt
    )
    confirmed["execution_generation"] = 4
    XCTAssertNil(AgentResultReceipt.confirmedPayload(confirmed, desktopId: "desktop-1"))
  }

  func testEncryptedResultReceiptJournalRequiresApplicationConfirmationBeforeCleanup() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("receipts.sqlite3")
    let secrets = InMemorySecretStore()
    let receipt = try XCTUnwrap(AgentResultReceipt.fromPayload([
      "client_route_id": "route-1",
      "conversation_id": "conversation-1",
      "task_id": "task-1",
      "turn_id": "turn-1",
      "contact_id": "agent-1",
      "source_message_id": "902",
      "agent_id": "agent-1",
      "execution_generation": 2,
      "sha256": String(repeating: "b", count: 64)
    ], desktopId: "desktop-1"))

    var journal: AgentResultReceiptJournal? = AgentResultReceiptJournal(
      fileURL: fileURL,
      secrets: secrets
    )
    XCTAssertTrue(journal?.insert(receipt) ?? false)
    let initial = try XCTUnwrap(journal?.due(nowMillis: 10_000).first)
    XCTAssertEqual(initial.state, .pending)
    XCTAssertTrue(journal?.claim(initial, nowMillis: 10_000) ?? false)
    XCTAssertFalse(journal?.claim(initial, nowMillis: 10_000) ?? true)
    XCTAssertEqual(journal?.nextWakeMillis, 15_000)
    journal = nil

    let reopened = AgentResultReceiptJournal(fileURL: fileURL, secrets: secrets)
    XCTAssertTrue(reopened.due(nowMillis: 14_999).isEmpty)
    XCTAssertEqual(reopened.due(nowMillis: 15_000).first?.receipt, receipt)
    XCTAssertTrue(reopened.confirm(receipt))
    XCTAssertEqual(reopened.due(nowMillis: 15_000).first?.state, .confirmed)
    XCTAssertTrue(reopened.markCleaned(receipt))
    XCTAssertTrue(reopened.due(nowMillis: Int64.max).isEmpty)
  }

  func testTerminalFailureNeverAcceptsLateResult() {
    let messages = [connectorPolicyMessage(isMine: true, turnId: "turn-1")]

    XCTAssertFalse(AgentLateConnectorResponsePolicy.canAccept(
      sourceIsTerminal: true,
      exactTurnId: "turn-1",
      conversationMessages: messages
    ))
  }

  func testOrphanResponseWithoutExactIdentityNeverGuessesLatestTurn() {
    let messages = [connectorPolicyMessage(isMine: true, turnId: "turn-1")]

    XCTAssertNil(AgentLateConnectorResponsePolicy.exactTurnId(
      explicitTurnId: "",
      taskTurnId: "",
      indexedTurnId: "",
      conversationMessages: messages
    ))
  }

  func testExactUnansweredTurnAcceptsResponse() throws {
    let messages = [connectorPolicyMessage(isMine: true, turnId: "turn-1")]
    let turnId = AgentLateConnectorResponsePolicy.exactTurnId(
      explicitTurnId: "turn-1",
      taskTurnId: "",
      indexedTurnId: "",
      conversationMessages: messages
    )

    XCTAssertEqual(turnId, "turn-1")
    XCTAssertTrue(AgentLateConnectorResponsePolicy.canAccept(
      sourceIsTerminal: false,
      exactTurnId: turnId,
      conversationMessages: messages
    ))
  }

  func testAlreadyAnsweredTurnRejectsDuplicateLateResult() {
    let messages = [
      connectorPolicyMessage(isMine: true, turnId: "turn-1"),
      connectorPolicyMessage(isMine: false, turnId: "turn-1")
    ]

    XCTAssertFalse(AgentLateConnectorResponsePolicy.canAccept(
      sourceIsTerminal: false,
      exactTurnId: "turn-1",
      conversationMessages: messages
    ))
  }

  func testResponseCannotBindToUserTurnFromAnotherConversation() {
    let messages = [connectorPolicyMessage(isMine: true, turnId: "turn-2")]

    XCTAssertNil(AgentLateConnectorResponsePolicy.exactTurnId(
      explicitTurnId: "turn-1",
      taskTurnId: "",
      indexedTurnId: "",
      conversationMessages: messages
    ))
  }

  func testTerminalDeliveryStoreBoundsRecordsAndBusDropsQueuedLateResponse() {
    let terminals = InMemoryAgentTerminalDeliveryStore()
    for sourceMessageId in 1...520 {
      terminals.mark(AgentTerminalDelivery(
        sourceMessageId: Int64(sourceMessageId),
        terminalAtMillis: Int64(sourceMessageId)
      ))
    }
    XCTAssertEqual(terminals.records().count, InMemoryAgentTerminalDeliveryStore.maxRecords)
    XCTAssertNil(terminals.find(sourceMessageId: 1))
    XCTAssertEqual(terminals.find(sourceMessageId: 520)?.sourceMessageId, 520)

    let responses = AgentConnectorResponseStore(nowMillis: { 10_000 })
    responses.publish(AgentConnectorResponse(sourceMessageId: 520, content: "queued"))
    let bus = AgentConnectorResponseBus(
      registry: AgentManagedConnectorResponseRegistry(),
      managedLedger: nil,
      store: responses,
      terminalStore: terminals,
      nowMillis: { 10_000 }
    )
    var notifications = 0
    _ = bus.addListener { _ in notifications += 1 }

    XCTAssertTrue(bus.publish(AgentConnectorResponse(sourceMessageId: 520, content: "late")))
    XCTAssertTrue(responses.pending().isEmpty)
    XCTAssertEqual(notifications, 0)
  }

  func testIdentityTerminalRecordBlocksUnknownSourceForFailedIOSTurn() {
    let terminals = InMemoryAgentTerminalDeliveryStore()
    terminals.mark(AgentTerminalDelivery(
      sourceMessageId: 0,
      conversationId: "conversation-1",
      turnId: "turn-1",
      taskId: "task-1",
      contactId: "codex"
    ))

    XCTAssertTrue(terminals.isTerminal(AgentConnectorResponse(
      sourceMessageId: 99,
      contactId: "codex",
      conversationId: "conversation-1",
      turnId: "turn-1",
      taskId: "task-1",
      content: "late"
    )))
    XCTAssertFalse(terminals.isTerminal(AgentConnectorResponse(
      sourceMessageId: 100,
      contactId: "codex",
      conversationId: "conversation-2",
      turnId: "turn-1",
      taskId: "task-1",
      content: "different conversation"
    )))
  }

  func testTerminalDeliveryStorePersistsEncryptedRecords() {
    let suiteName = "AgentTerminalDeliveryStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let secrets = InMemorySecretStore()
    let storageKey = "terminal-test"
    defer {
      UserDefaultsAgentTerminalDeliveryStore(
        defaults: defaults,
        storageKey: storageKey,
        secrets: secrets
      ).clear()
      defaults.removePersistentDomain(forName: suiteName)
    }

    UserDefaultsAgentTerminalDeliveryStore(
      defaults: defaults,
      storageKey: storageKey,
      secrets: secrets
    ).mark(AgentTerminalDelivery(
      sourceMessageId: 81,
      conversationId: "conversation-1",
      turnId: "turn-1",
      reason: "transport failed"
    ))

    XCTAssertNil(defaults.object(forKey: storageKey))
    XCTAssertEqual(UserDefaultsAgentTerminalDeliveryStore(
      defaults: defaults,
      storageKey: storageKey,
      secrets: secrets
    ).find(sourceMessageId: 81)?.reason, "transport failed")
  }

  func testTerminalDeliveryStoreDestroyRemovesEncryptedRecords() {
    let suiteName = "AgentTerminalDeliveryDestroyTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let secrets = InMemorySecretStore()
    let storageKey = "terminal-destroy-test"
    defer { defaults.removePersistentDomain(forName: suiteName) }

    UserDefaultsAgentTerminalDeliveryStore(
      defaults: defaults,
      storageKey: storageKey,
      secrets: secrets
    ).mark(AgentTerminalDelivery(sourceMessageId: 82, reason: "cancelled"))

    UserDefaultsAgentTerminalDeliveryStore.destroyPersistentStore(
      defaults: defaults,
      storageKey: storageKey,
      secrets: secrets
    )

    XCTAssertNil(UserDefaultsAgentTerminalDeliveryStore(
      defaults: defaults,
      storageKey: storageKey,
      secrets: secrets
    ).find(sourceMessageId: 82))
  }

  func testAgentConnectorResponseBusInterceptsManagedResponsesOnce() throws {
    let registry = AgentManagedConnectorResponseRegistry()
    let store = AgentConnectorResponseStore(nowMillis: { 10_000 })
    let bus = AgentConnectorResponseBus(registry: registry, store: store, nowMillis: { 10_000 })
    var intercepted: [AgentConnectorResponse] = []
    try registry.register(
      sourceMessageId: 73,
      contactId: "codex",
      ownerId: "managed-run"
    ) { response in
      intercepted.append(response)
      return true
    }
    let response = AgentConnectorResponse(
      sourceMessageId: 73,
      contactId: "codex",
      content: "Reviewed result",
      inputTokens: 10,
      outputTokens: 4
    )

    XCTAssertTrue(bus.publish(response))
    XCTAssertFalse(registry.consume(response))
    XCTAssertEqual(intercepted.map(\.content), ["Reviewed result"])
    XCTAssertTrue(store.pending().isEmpty)

    XCTAssertFalse(bus.publish(response))
    XCTAssertEqual(store.pending().map(\.content), ["Reviewed result"])
  }

  func testManagedResponseRegistryAcceptsUnambiguousContactAlias() throws {
    let registry = AgentManagedConnectorResponseRegistry()
    var consumed = false
    try registry.register(
      sourceMessageId: 45,
      contactId: "desktop:codex",
      ownerId: "managed-child",
      conversationId: "managed-conversation",
      turnId: "managed-turn",
      taskId: "managed-task"
    ) { _ in
      consumed = true
      return true
    }
    let response = AgentConnectorResponse(
      sourceMessageId: 45,
      contactId: "desktop",
      content: "managed result",
      conversationId: "managed-conversation",
      turnId: "managed-turn",
      taskId: "managed-task"
    )

    XCTAssertTrue(registry.contains(response))
    XCTAssertTrue(registry.consume(response))
    XCTAssertTrue(consumed)
    XCTAssertFalse(registry.contains(response))
  }

  func testAgentConnectorResponseBusCompletesManagedLedgerBeforeStore() throws {
    let ledger = InMemoryAgentManagedResponseLedger()
    try ledger.register(AgentManagedResponseRecord(
      ownerRunId: "child-primary",
      supervisorRunId: "supervisor",
      agentId: "primary",
      deliveryMode: .respond,
      sourceMessageId: 9001,
      contactId: "primary",
      createdAtMillis: 1_000
    ))
    let store = AgentConnectorResponseStore(nowMillis: { 10_000 })
    let bus = AgentConnectorResponseBus(
      registry: AgentManagedConnectorResponseRegistry(),
      managedLedger: ledger,
      store: store,
      nowMillis: { 10_000 }
    )

    XCTAssertTrue(bus.publish(AgentConnectorResponse(
      sourceMessageId: 9001,
      contactId: "primary",
      content: "durable final answer",
      receivedAtMillis: 9_000
    )))
    XCTAssertTrue(store.pending().isEmpty)
    XCTAssertEqual(ledger.completedUnapplied().map(\.ownerRunId), ["child-primary"])

    XCTAssertTrue(bus.publish(AgentConnectorResponse(
      sourceMessageId: 9001,
      contactId: "primary",
      content: "duplicate",
      receivedAtMillis: 9_500
    )))
    XCTAssertTrue(store.pending().isEmpty)
  }

  func testAgentConnectorResponseBusFallbacksRichOutputAndNotifiesListeners() {
    let store = AgentConnectorResponseStore(nowMillis: { 10_000 })
    let bus = AgentConnectorResponseBus(
      registry: AgentManagedConnectorResponseRegistry(),
      store: store,
      nowMillis: { 10_000 }
    )
    let rich = #"{"version":1,"blocks":[{"type":"text","text":"Rendered rich answer","title":"","fallback_text":"","uri":""}]}"#
    var notified: [AgentConnectorResponse] = []
    let token = bus.addListener { notified.append($0) }
    defer { bus.removeListener(token) }

    XCTAssertFalse(bus.publish(AgentConnectorResponse(
      sourceMessageId: 501,
      contactId: "codex",
      content: "",
      richOutputJson: rich
    )))

    XCTAssertEqual(store.pending().map(\.content), ["Rendered rich answer"])
    XCTAssertEqual(notified.map(\.content), ["Rendered rich answer"])
    XCTAssertFalse(store.pending().first?.richOutputJson.isEmpty ?? true)
    XCTAssertFalse(bus.publish(AgentConnectorResponse(sourceMessageId: 0, content: "invalid")))
    XCTAssertFalse(bus.publish(AgentConnectorResponse(sourceMessageId: 502, content: "", richOutputJson: "{}")))
  }

  func testUnmanagedAgentResponseIsDurablyRecordedWithoutManagedConsumption() {
    let store = AgentConnectorResponseStore(nowMillis: { 10_000 })
    let bus = AgentConnectorResponseBus(
      registry: AgentManagedConnectorResponseRegistry(),
      managedLedger: nil,
      store: store,
      nowMillis: { 10_000 }
    )
    let response = AgentConnectorResponse(
      sourceMessageId: 503,
      contactId: "codex",
      content: "Background result",
      conversationId: "conversation-a",
      turnId: "turn-a",
      taskId: "task-a",
      receivedAtMillis: 9_000
    )

    XCTAssertFalse(bus.publish(response))
    XCTAssertTrue(bus.wasRecorded(response))
    XCTAssertEqual(store.pending(), [response])
    bus.remove(response)
    XCTAssertTrue(bus.wasRecorded(response))
  }

  func testAgentConnectorResponseStoreBoundsDedupeExpiryAndAndroidWireNames() throws {
    let store = AgentConnectorResponseStore(nowMillis: { 100_000 })
    for index in 0..<35 {
      store.append(AgentConnectorResponse(
        sourceMessageId: Int64(index + 1),
        contactId: "codex",
        content: "answer-\(index)",
        receivedAtMillis: Int64(index + 1)
      ))
    }
    XCTAssertEqual(store.pending().count, AgentConnectorResponseStore.maxResponses)
    XCTAssertEqual(store.pending().first?.sourceMessageId, 6)

    store.append(AgentConnectorResponse(
      sourceMessageId: 35,
      contactId: "codex",
      content: "replacement",
      receivedAtMillis: 101_000
    ))
    XCTAssertEqual(store.pending().filter { $0.sourceMessageId == 35 && $0.contactId == "codex" }.count, 1)
    XCTAssertEqual(store.pending().last?.content, "replacement")

    let encoded = store.serializedSnapshot()
    let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [[String: Any]])
    let object = try XCTUnwrap(array.last)
    XCTAssertEqual(object["source_message_id"] as? Int, 35)
    XCTAssertEqual(object["received_at"] as? Int, 101_000)
    XCTAssertNil(object["received_at_millis"])
    XCTAssertNil(object["sourceMessageId"])

    let stale = AgentConnectorResponseStoreCodec.encode([
      AgentConnectorResponse(
        sourceMessageId: 900,
        contactId: "codex",
        content: "old",
        receivedAtMillis: 100_000 - AgentConnectorResponseStore.maxResponseAgeMillis - 1
      )
    ])
    XCTAssertTrue(AgentConnectorResponseStore(serialized: stale, nowMillis: { 100_000 }).pending().isEmpty)

    store.remove(AgentConnectorResponse(sourceMessageId: 35, contactId: "codex", content: ""))
    XCTAssertFalse(store.pending().contains { $0.sourceMessageId == 35 && $0.contactId == "codex" })
  }

  func testAgentConnectorResponseStoreRetainsPendingBodiesAndUsesFullIdentity() {
    let store = AgentConnectorResponseStore(nowMillis: { 100_000 })
    let first = AgentConnectorResponse(
      sourceMessageId: 71,
      contactId: "codex",
      content: "first answer",
      conversationId: "conversation-a",
      turnId: "turn-a",
      taskId: "task-a",
      receivedAtMillis: 90_000
    )
    let second = AgentConnectorResponse(
      sourceMessageId: 71,
      contactId: "codex",
      content: "second answer",
      conversationId: "conversation-b",
      turnId: "turn-b",
      taskId: "task-b",
      receivedAtMillis: 91_000
    )

    XCTAssertTrue(store.append(first))
    XCTAssertTrue(store.append(second))
    XCTAssertEqual(store.pending().map(\.content), ["first answer", "second answer"])

    store.remove(first)
    XCTAssertEqual(store.pending().map(\.content), ["second answer"])
    XCTAssertTrue(store.hasReceivedDelivery(AgentTerminalDelivery(
      sourceMessageId: 0,
      conversationId: first.conversationId,
      turnId: first.turnId,
      taskId: first.taskId,
      contactId: first.contactId
    )))
    XCTAssertFalse(store.hasReceivedDelivery(AgentTerminalDelivery(
      sourceMessageId: 0,
      conversationId: "conversation-other",
      turnId: first.turnId,
      taskId: first.taskId,
      contactId: first.contactId
    )))
  }

  func testLateTransportFailureCannotReplaceConsumedReply() {
    let store = AgentConnectorResponseStore(nowMillis: { 100_000 })
    let terminals = InMemoryAgentTerminalDeliveryStore()
    let bus = AgentConnectorResponseBus(
      registry: AgentManagedConnectorResponseRegistry(),
      managedLedger: nil,
      store: store,
      terminalStore: terminals,
      nowMillis: { 100_000 }
    )
    let response = AgentConnectorResponse(
      sourceMessageId: 72,
      contactId: "codex",
      content: "durable answer",
      conversationId: "conversation",
      turnId: "turn",
      taskId: "task",
      receivedAtMillis: 99_000
    )
    XCTAssertFalse(bus.publish(response))
    bus.remove(response)

    XCTAssertFalse(bus.markTransportFailure(AgentTerminalDelivery(
      sourceMessageId: response.sourceMessageId,
      conversationId: response.conversationId,
      turnId: response.turnId,
      taskId: response.taskId,
      contactId: response.contactId,
      reason: "delivery_retry_exhausted"
    )))
    XCTAssertNil(terminals.find(sourceMessageId: response.sourceMessageId))
  }

  func testReceivedDeliveryProofSurvivesConsumptionAndStoreReopen() {
    let suite = "AgentConnectorResponseTests.received.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = "responses"
    let response = AgentConnectorResponse(
      sourceMessageId: 73,
      contactId: "codex",
      content: "persisted answer",
      conversationId: "conversation",
      turnId: "turn",
      taskId: "task",
      receivedAtMillis: 99_000
    )
    let store = UserDefaultsAgentConnectorResponseStore(
      defaults: defaults,
      storageKey: key,
      nowMillis: { 100_000 }
    )
    XCTAssertTrue(store.publish(response))
    store.remove(response)
    XCTAssertTrue(store.pending().isEmpty)

    let reopened = UserDefaultsAgentConnectorResponseStore(
      defaults: defaults,
      storageKey: key,
      nowMillis: { 100_000 }
    )
    XCTAssertTrue(reopened.hasReceivedDelivery(AgentTerminalDelivery(
      sourceMessageId: response.sourceMessageId,
      conversationId: response.conversationId,
      turnId: response.turnId,
      taskId: response.taskId,
      contactId: response.contactId
    )))
  }

  func testAgentConnectorFinalResultPersistsBeforeLiveStreamRetires() {
    var calls: [String] = []

    let result: Bool? = AgentConnectorStreamHandoff.persistThenRetire(
      persistFinal: {
        calls.append("persist")
        return true
      },
      retireLiveStream: { calls.append("retire") }
    )

    XCTAssertEqual(result, true)
    XCTAssertEqual(calls, ["persist", "retire"])
  }

  func testAgentConnectorFailedPersistenceKeepsLiveStreamVisible() {
    var retired = false

    let result: Bool? = AgentConnectorStreamHandoff.persistThenRetire(
      persistFinal: { nil },
      retireLiveStream: { retired = true }
    )

    XCTAssertNil(result)
    XCTAssertFalse(retired)
  }

  private func connectorPolicyMessage(isMine: Bool, turnId: String) -> ChatMessage {
    ChatMessage(
      contactId: "hermes",
      content: isMine ? "USER" : "ASSISTANT",
      isMine: isMine,
      conversationId: "conversation-1",
      turnId: turnId
    )
  }
}
