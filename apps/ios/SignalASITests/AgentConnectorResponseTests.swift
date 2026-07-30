import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
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
}
