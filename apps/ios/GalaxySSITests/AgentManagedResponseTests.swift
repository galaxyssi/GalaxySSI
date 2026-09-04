import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
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
