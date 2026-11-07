import XCTest
@testable import GalaxySSI

final class CloudConversationStreamEngineTests: XCTestCase {
  func testFormatRepairBudgetDoesNotLimitToolProgressOrCitationRepair() {
    let progress = CloudWebToolLoopProgress()
    XCTAssertTrue(progress.requestFormatRepair("protocol"))
    XCTAssertFalse(progress.requestFormatRepair("protocol"))
    XCTAssertTrue(progress.requestFormatRepair("arguments:first"))
    XCTAssertTrue(progress.requestFormatRepair("arguments:second"))
    XCTAssertFalse(progress.requestFormatRepair("arguments:third"))
    XCTAssertFalse(progress.requestPartialSynthesisRepair(after: "citations"))
    XCTAssertTrue(progress.requestRepair("citations"))
    XCTAssertTrue(progress.requestPartialSynthesisRepair(after: "citations"))
    XCTAssertFalse(progress.requestPartialSynthesisRepair(after: "citations"))
    for index in 0..<12 {
      XCTAssertTrue(progress.record(toolName: "web_search", arguments: ["query": .string("source \(index)")],
                                    output: "new evidence"))
    }
  }

  @MainActor
  func testOnePartialCitationRepairPreservesSupportedProse() async throws {
    let fixture = try makeFixture()
    let pack = AgentIOSWebEvidencePack.build(query: "report", status: "completed",
      documents: [["url": .string("https://example.test/report"), "content": .string("A supported conclusion")]],
      results: [], receipts: [], generatedAtMillis: 1)
    let item = try XCTUnwrap(pack["items"]?.arrayValue?.first?.objectValue)
    let marker = "[[cite:\(item.string("citation_id"))]]"
    func answer(_ text: String) -> [ModelStreamEvent] {
      [.textDelta(.init(requestId: "r", sequence: 1, text: text, receivedAtElapsedMs: 1)),
       .completed(.init(requestId: "r", finishReason: "stop", completedAtElapsedMs: 2))]
    }
    let stream = RecordingModelStreamClient(eventBatches: [
      [.toolCallDelta(.init(requestId: "r", sequence: 1, payload: .init(callId: "search", index: 0,
          nameDelta: "web_search", argumentsDelta: #"{"query":"report"}"#))),
       .completed(.init(requestId: "r", finishReason: "tool_calls", completedAtElapsedMs: 2))],
      answer("Unsupported [Foreign](https://foreign.test/a)."),
      answer("Still unsupported [[cite:missing]]."),
      answer("Supported \(marker).\n\nThe other claim is unverified.")
    ])
    let executor = RecordingConversationToolExecutor(result: AgentMcpJSONCodec.stringify(["evidence_pack": .object(pack)]))
    let engine = CloudConversationStreamEngine(streamClient: stream, toolExecutor: executor,
      disclosureStore: InMemoryAgentDataDisclosureStore())
    let events = try await collect(engine.streamConversation(contact: fixture.contact, store: fixture.store,
      turns: fixture.turns, requestId: "partial-citations"))
    XCTAssertEqual(stream.requests.count, 4)
    XCTAssertEqual(executor.calls.count, 1)
    let repairedRequest = try XCTUnwrap(stream.requests.last)
    XCTAssertTrue(repairedRequest.bodyJson.contains("concise partial answer"))
    XCTAssertNil(try object(repairedRequest.bodyJson)["tools"])
    let final = textDeltas(events).map(\.text).joined()
    XCTAssertTrue(final.contains("Supported [1](<https://example.test/report>)"))
    XCTAssertTrue(final.contains("other claim is unverified"))
    XCTAssertFalse(final.contains("foreign.test"))
    XCTAssertFalse(final.contains("[[cite:"))
    XCTAssertNotNil(completed(events))
  }

  @MainActor
  func testCloudColdBootSettlesOnlyExactOrphanAndPreservesCommittedReply() throws {
    let suite = "cloud-dispatch-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let secrets = InMemorySecretStore()
    let initial = GalaxySSIStore(defaults: defaults, secrets: secrets)
    let session = initial.createAgentSession(title: "Recovery")
    let orphan = initial.appendOutgoing("request", to: "hermes", status: .sent, turnId: "orphan")
    let committed = initial.appendOutgoing("request", to: "hermes", status: .sent, turnId: "committed")
    let live = initial.appendOutgoing("request", to: "hermes", status: .sent, turnId: "live")
    XCTAssertEqual(orphan.conversationId, session.id)
    func receipt(_ message: ChatMessage) -> AgentCloudDispatchReceipt {
      AgentCloudDispatchReceipt(sourceId: message.id, contactId: message.contactId,
        conversationId: message.conversationId, turnId: message.turnId, providerId: "cloud:provider", modelId: "original")
    }
    for source in [orphan, committed, live] {
      XCTAssertTrue(initial.chatHistoryDatabase.registerCloudDispatch(receipt(source)))
      XCTAssertFalse(initial.chatHistoryDatabase.registerCloudDispatch(receipt(source)))
    }
    let partial = initial.appendIncoming("Draft", from: "hermes", remoteMessageId: receipt(orphan).previewId,
      status: .sent, traceStage: "cloud_citation_preview", conversationId: session.id, turnId: orphan.turnId)
    let final = initial.appendIncoming("Complete", from: "hermes", remoteMessageId: committed.turnId,
      status: .delivered, traceStage: "cloud_reply_received", conversationId: session.id, turnId: committed.turnId)
    var foreign = final
    foreign.id = UUID()
    foreign.conversationId = "unrelated"
    foreign.turnId = orphan.turnId
    foreign.remoteMessageId = orphan.turnId
    XCTAssertTrue(initial.chatHistoryDatabase.upsert(foreign))

    let registry = AgentCloudDispatchRegistry.shared
    let liveIdentity = receipt(live).identity
    let lease = try XCTUnwrap(registry.register(liveIdentity))
    defer { registry.release(liveIdentity, lease: lease) }
    let reopened = GalaxySSIStore(defaults: defaults, secrets: secrets)
    XCTAssertEqual(reopened.chatHistoryDatabase.pendingCloudDispatches(sourceId: orphan.id), [receipt(orphan)])
    XCTAssertEqual(reopened.reconcileCloudDispatches(), 2)
    XCTAssertEqual(reopened.persistedMessage(id: orphan.id, contactId: "hermes")?.deliveryStatus, .failed)
    XCTAssertEqual(reopened.persistedMessage(id: partial.id, contactId: "hermes")?.deliveryStatus, .failed)
    XCTAssertEqual(reopened.persistedMessage(id: committed.id, contactId: "hermes")?.deliveryStatus, .delivered)
    XCTAssertEqual(reopened.persistedMessage(id: final.id, contactId: "hermes")?.deliveryStatus, .delivered)
    XCTAssertEqual(reopened.persistedMessage(id: foreign.id, contactId: "hermes")?.deliveryStatus, .delivered)
    XCTAssertEqual(reopened.persistedMessage(id: live.id, contactId: "hermes")?.deliveryStatus, .sent)
    XCTAssertEqual(reopened.chatHistoryDatabase.pendingCloudDispatches(), [receipt(live)])
    XCTAssertEqual(reopened.reconcileCloudDispatches(), 0)
  }

  func testRuleRecallCountsOnlyNewAuthenticCharacters() throws {
    let tool = CloudModelStreamMutableConversation.collaborationRecallName
    let progress = CloudWebToolLoopProgress()
    let args: AgentMcpJSONObject = ["mode": .string("evolution_rules")]
    let page = try XCTUnwrap(AgentCollaborationRuleTopics.page(topic: "all", offset: 0))
    let output = AgentMcpJSONCodec.stringify(page)
    XCTAssertTrue(progress.record(toolName: tool, arguments: args, output: output))
    XCTAssertFalse(progress.record(toolName: tool, arguments: [
      "mode": .string("evolution_rules"), "topic": .string("all"), "offset": .int(0)
    ], output: output))
    let suffix = try XCTUnwrap(AgentCollaborationRuleTopics.page(topic: "all", offset: 4))
    XCTAssertFalse(progress.record(toolName: tool, arguments: [
      "mode": .string("evolution_rules"), "offset": .int(4)
    ], output: AgentMcpJSONCodec.stringify(suffix)))
    var forged = page
    forged["content"] = .string("Not the host contract")
    XCTAssertFalse(CloudWebToolLoopProgress().record(toolName: tool, arguments: args,
      output: AgentMcpJSONCodec.stringify(forged)))
  }

  func testCloudDispatchCancellationIsScopedToExactOwner() throws {
    let registry = AgentCloudDispatchRegistry()
    let first = AgentCloudDispatchIdentity(
      sourceMessageId: "message-1",
      contactId: "cloud-a",
      conversationId: "conversation-a",
      turnId: "turn-a",
      taskId: "task-a",
      actionId: "action-a"
    )
    let second = AgentCloudDispatchIdentity(
      sourceMessageId: "message-2",
      contactId: "cloud-b",
      conversationId: "conversation-b",
      turnId: "turn-b",
      taskId: "task-b",
      actionId: "action-b"
    )
    let firstLease = try XCTUnwrap(registry.register(first))
    let secondLease = try XCTUnwrap(registry.register(second))
    var firstCancellationCount = 0
    var secondCancellationCount = 0
    firstLease.bindCancellation { firstCancellationCount += 1 }
    secondLease.bindCancellation { secondCancellationCount += 1 }

    XCTAssertTrue(registry.cancel(first))
    XCTAssertFalse(registry.cancel(first))
    XCTAssertTrue(firstLease.isCancelled)
    XCTAssertFalse(firstLease.claimCompletion())
    XCTAssertFalse(secondLease.isCancelled)
    XCTAssertTrue(secondLease.claimCompletion())
    XCTAssertEqual(firstCancellationCount, 1)
    XCTAssertEqual(secondCancellationCount, 0)

    registry.release(first, lease: firstLease)
    registry.release(second, lease: secondLease)
    XCTAssertEqual(registry.activeCount, 0)
  }

  func testCloudDispatchTaskCancellationDoesNotCrossConversations() throws {
    let registry = AgentCloudDispatchRegistry()
    let first = AgentCloudDispatchIdentity(
      sourceMessageId: "message-1",
      contactId: "cloud-a",
      conversationId: "conversation-a",
      turnId: "turn-a",
      taskId: "shared-task",
      actionId: "action-a"
    )
    let second = AgentCloudDispatchIdentity(
      sourceMessageId: "message-2",
      contactId: "cloud-b",
      conversationId: "conversation-b",
      turnId: "turn-b",
      taskId: "shared-task",
      actionId: "action-b"
    )
    let firstLease = try XCTUnwrap(registry.register(first))
    let secondLease = try XCTUnwrap(registry.register(second))

    XCTAssertEqual(registry.cancel(taskId: "shared-task", conversationId: "conversation-a"), 1)
    XCTAssertTrue(firstLease.isCancelled)
    XCTAssertFalse(secondLease.isCancelled)
  }

  func testToolLoopProgressUsesCanonicalArgumentsAndCachesResults() {
    let progress = CloudWebToolLoopProgress()
    let first: AgentMcpJSONObject = [
      "query": .string("GalaxySSI"),
      "options": .object(["safe": .bool(true), "count": .int(2)])
    ]
    let reordered: AgentMcpJSONObject = [
      "options": .object(["count": .int(2), "safe": .bool(true)]),
      "query": .string("GalaxySSI")
    ]

    XCTAssertEqual(
      progress.semanticKey(toolName: " Web_Search ", arguments: first),
      progress.semanticKey(toolName: "web_search", arguments: reordered)
    )
    XCTAssertTrue(progress.record(toolName: "web_search", arguments: first, output: "result"))
    XCTAssertFalse(progress.record(toolName: "WEB_SEARCH", arguments: reordered, output: "replacement"))
    XCTAssertEqual(progress.cached(toolName: "web_search", arguments: reordered), "result")
  }

  func testToolLoopProgressReusesOnlyEquivalentRetrievedPageBodies() {
    let progress = CloudWebToolLoopProgress()
    let arguments: AgentMcpJSONObject = ["url": .string("https://example.test/page")]
    let body = AgentMcpJSONCodec.stringify([
      "status": .string("completed"),
      "evidence_pack": .object([
        "items": .array([.object([
          "url": .string("https://example.test/page"),
          "evidence_level": .string("retrieved_body"),
          "excerpt": .string("The actual page body.")
        ])])
      ])
    ])

    XCTAssertTrue(progress.record(toolName: "web_fetch", arguments: arguments, output: body))
    XCTAssertEqual(progress.cached(toolName: "web_extract", arguments: arguments), body)
    XCTAssertNil(progress.cached(
      toolName: "web_extract",
      arguments: ["url": .string("https://example.test/page"), "fields": .array([.string("date")])]
    ))
    XCTAssertNil(progress.cached(
      toolName: "web_fetch",
      arguments: ["url": .string("https://example.test/page"), "force": .bool(true)]
    ))
    XCTAssertNil(progress.cached(
      toolName: "web_fetch",
      arguments: ["url": .string("https://example.test/page"), "focus": .string("counterexample")]
    ))
  }

  func testToolLoopProgressAllowsOneRepairAndOneFinalizationRequest() {
    let progress = CloudWebToolLoopProgress()

    XCTAssertTrue(progress.requestRepair("arguments:web_search"))
    XCTAssertFalse(progress.requestRepair("arguments:web_search"))
    XCTAssertFalse(progress.finalizationRequested)
    XCTAssertTrue(progress.requestFinalization())
    XCTAssertTrue(progress.finalizationRequested)
    XCTAssertFalse(progress.requestFinalization())
  }

  func testToolLoopProgressDoesNotImposeAnApplicationCountBudget() {
    let progress = CloudWebToolLoopProgress()

    for index in 0..<1_000 {
      XCTAssertTrue(
        progress.record(
          toolName: "web_search",
          arguments: ["query": .string("evidence-\(index)")],
          output: "result-\(index)"
        )
      )
    }

    XCTAssertEqual(
      progress.cached(toolName: "web_search", arguments: ["query": .string("evidence-999")]),
      "result-999"
    )
    XCTAssertFalse(progress.finalizationRequested)
  }

  @MainActor
  func testConversationStreamRewritesProviderRoundIdsAndSequences() async throws {
    let fixture = try makeFixture()
    let streamClient = RecordingModelStreamClient(events: [
      .connected(ModelStreamConnected(requestId: "round", httpStatus: 200, connectedAtElapsedMs: 10)),
      .textDelta(ModelStreamTextDelta(requestId: "round", sequence: 99, text: "Hel", receivedAtElapsedMs: 11)),
      .textDelta(ModelStreamTextDelta(requestId: "round", sequence: 100, text: "lo", receivedAtElapsedMs: 12)),
      .usage(ModelStreamUsage(requestId: "round", usage: ModelUsage(inputTokens: 3, outputTokens: 2))),
      .completed(ModelStreamCompleted(requestId: "round", finishReason: "stop", completedAtElapsedMs: 13))
    ])
    let disclosureStore = InMemoryAgentDataDisclosureStore()
    let engine = CloudConversationStreamEngine(
      streamClient: streamClient,
      disclosureStore: disclosureStore,
      elapsedMillis: { 99 }
    )

    let events = try await collect(
      engine.streamConversation(
        contact: fixture.contact,
        store: fixture.store,
        turns: fixture.turns,
        requestId: "conversation-1"
      )
    )

    XCTAssertEqual(streamClient.requests.first?.requestId, "conversation-1:r0")
    XCTAssertEqual(events.map(\.requestId), Array(repeating: "conversation-1", count: 5))
    XCTAssertEqual(textDeltas(events).map(\.sequence), [1, 2])
    XCTAssertEqual(textDeltas(events).map(\.text), ["Hel", "lo"])
    XCTAssertEqual(completed(events)?.finishReason, "stop")
    XCTAssertEqual(completed(events)?.completedAtElapsedMs, 99)
    XCTAssertEqual(disclosureStore.list().first?.status, .sent)
  }

  @MainActor
  func testStreamUnsupportedFallsBackToLegacyConversation() async throws {
    let fixture = try makeFixture()
    let streamClient = RecordingModelStreamClient(events: [
      .failed(
        ModelStreamFailed(
          requestId: "round",
          error: ModelStreamError(code: "STREAM_UNSUPPORTED", message: "no stream")
        )
      )
    ])
    let legacySender = RecordingLegacyConversationSender(reply: "compatibility reply")
    let disclosureStore = InMemoryAgentDataDisclosureStore()
    let engine = CloudConversationStreamEngine(
      streamClient: streamClient,
      legacySender: legacySender,
      disclosureStore: disclosureStore,
      elapsedMillis: { 42 }
    )

    let events = try await collect(
      engine.streamConversation(
        contact: fixture.contact,
        store: fixture.store,
        turns: fixture.turns,
        requestId: "conversation-2"
      )
    )

    XCTAssertEqual(legacySender.calls.count, 1)
    XCTAssertEqual(textDeltas(events).map(\.text), ["compatibility reply"])
    XCTAssertEqual(completed(events)?.finishReason, "compatibility")
    XCTAssertNil(failed(events))
    XCTAssertEqual(disclosureStore.list().first?.status, .sent)
  }

  @MainActor
  func testDisclosureBlockPreventsProviderRequest() async throws {
    let fixture = try makeFixture()
    let disclosureStore = InMemoryAgentDataDisclosureStore()
    disclosureStore.setDestinationBlocked(destinationId: fixture.contact.id, blocked: true)
    let streamClient = RecordingModelStreamClient(events: [])
    let engine = CloudConversationStreamEngine(
      streamClient: streamClient,
      disclosureStore: disclosureStore
    )

    let events = try await collect(
      engine.streamConversation(
        contact: fixture.contact,
        store: fixture.store,
        turns: fixture.turns,
        requestId: "blocked"
      )
    )

    XCTAssertTrue(streamClient.requests.isEmpty)
    XCTAssertEqual(failed(events)?.error.code, "DISCLOSURE_BLOCKED")
    XCTAssertEqual(disclosureStore.list().first?.status, .blocked)
  }

  @MainActor
  func testToolCallRoundExecutesToolAndContinuesWithAugmentedConversation() async throws {
    let fixture = try makeFixture()
    let streamClient = RecordingModelStreamClient(eventBatches: [
      [
        .connected(ModelStreamConnected(requestId: "round-0", httpStatus: 200, connectedAtElapsedMs: 10)),
        .toolCallDelta(
          ModelStreamToolCallDelta(
            requestId: "round-0",
            sequence: 1,
            payload: ToolCallPayload(
              callId: "call-1",
              index: 0,
              nameDelta: "web_search",
              argumentsDelta: #"{"query":"GalaxySSI"}"#
            )
          )
        ),
        .completed(ModelStreamCompleted(requestId: "round-0", finishReason: "tool_calls", completedAtElapsedMs: 11))
      ],
      [
        .textDelta(ModelStreamTextDelta(requestId: "round-1", sequence: 1, text: "grounded", receivedAtElapsedMs: 12)),
        .completed(ModelStreamCompleted(requestId: "round-1", finishReason: "stop", completedAtElapsedMs: 13))
      ]
    ])
    let toolExecutor = RecordingConversationToolExecutor(result: #"{"results":[{"url":"https://galaxyssi.example"}]}"#)
    let engine = CloudConversationStreamEngine(
      streamClient: streamClient,
      toolExecutor: toolExecutor,
      disclosureStore: InMemoryAgentDataDisclosureStore(),
      elapsedMillis: { 99 }
    )

    let events = try await collect(
      engine.streamConversation(
        contact: fixture.contact,
        store: fixture.store,
        turns: fixture.turns,
        requestId: "conversation-tool"
      )
    )
    let secondBody = try object(streamClient.requests[1].bodyJson)
    let messages = try XCTUnwrap(secondBody["messages"] as? [[String: Any]])
    let toolMessage = try XCTUnwrap(messages.last)

    XCTAssertEqual(streamClient.requests.map(\.requestId), ["conversation-tool:r0", "conversation-tool:r1"])
    XCTAssertEqual(toolExecutor.calls.map(\.call.name), ["web_search"])
    XCTAssertEqual(toolExecutor.calls.first?.context.conversationId, "conversation")
    XCTAssertEqual(toolExecutor.calls.first?.context.turnId, "turn")
    XCTAssertEqual(toolDeltas(events).map(\.sequence), [1])
    XCTAssertEqual(textDeltas(events).map(\.sequence), [2])
    XCTAssertEqual(textDeltas(events).map(\.text), ["grounded"])
    XCTAssertEqual(toolMessage["role"] as? String, "tool")
    XCTAssertEqual(toolMessage["tool_call_id"] as? String, "call-1")
    XCTAssertTrue((toolMessage["content"] as? String)?.contains("GALAXYSSI_UNTRUSTED_EVIDENCE") == true)
    XCTAssertEqual(completed(events)?.finishReason, "stop")
  }

  @MainActor
  func testUniqueToolProgressContinuesBeyondPreviousFourRoundLimit() async throws {
    let fixture = try makeFixture()
    let toolRounds = (0..<5).map { index in
      toolRound(index: index, callId: "call-\(index)", query: "query-\(index)")
    }
    let streamClient = RecordingModelStreamClient(eventBatches: toolRounds + [[
      .textDelta(
        ModelStreamTextDelta(
          requestId: "final",
          sequence: 1,
          text: "Answer [source](https://galaxyssi.example)",
          receivedAtElapsedMs: 20
        )
      ),
      .completed(ModelStreamCompleted(requestId: "final", finishReason: "stop", completedAtElapsedMs: 21))
    ]])
    let toolExecutor = RecordingConversationToolExecutor(
      result: #"{"results":[{"url":"https://galaxyssi.example"}]}"#
    )
    let engine = CloudConversationStreamEngine(
      streamClient: streamClient,
      toolExecutor: toolExecutor,
      disclosureStore: InMemoryAgentDataDisclosureStore()
    )

    let events = try await collect(
      engine.streamConversation(
        contact: fixture.contact,
        store: fixture.store,
        turns: fixture.turns,
        requestId: "long-tool-loop"
      )
    )

    XCTAssertEqual(toolExecutor.calls.count, 5)
    XCTAssertEqual(streamClient.requests.count, 6)
    XCTAssertEqual(streamClient.requests.last?.requestId, "long-tool-loop:r5")
    XCTAssertEqual(textDeltas(events).last?.text, "Answer [source](https://galaxyssi.example)")
    XCTAssertNil(failed(events))
    XCTAssertNotNil(completed(events))
  }

  @MainActor
  func testRepeatedSemanticToolCallReusesResultThenRequestsFinalAnswer() async throws {
    let fixture = try makeFixture()
    let streamClient = RecordingModelStreamClient(eventBatches: [
      toolRound(index: 0, callId: "call-original", query: "same-query"),
      toolRound(index: 1, callId: "call-repeated", query: "same-query"),
      [
        .textDelta(
          ModelStreamTextDelta(
            requestId: "final",
            sequence: 1,
            text: "Answer [source](https://galaxyssi.example)",
            receivedAtElapsedMs: 20
          )
        ),
        .completed(ModelStreamCompleted(requestId: "final", finishReason: "stop", completedAtElapsedMs: 21))
      ]
    ])
    let toolExecutor = RecordingConversationToolExecutor(
      result: #"{"results":[{"url":"https://galaxyssi.example"}]}"#
    )
    let engine = CloudConversationStreamEngine(
      streamClient: streamClient,
      toolExecutor: toolExecutor,
      disclosureStore: InMemoryAgentDataDisclosureStore()
    )

    let events = try await collect(
      engine.streamConversation(
        contact: fixture.contact,
        store: fixture.store,
        turns: fixture.turns,
        requestId: "repeated-tool-loop"
      )
    )
    let finalBody = try object(try XCTUnwrap(streamClient.requests.last?.bodyJson))
    let secondBody = try object(streamClient.requests[1].bodyJson)
    let secondMessages = try XCTUnwrap(secondBody["messages"] as? [[String: Any]])
    let finalMessages = try XCTUnwrap(finalBody["messages"] as? [[String: Any]])

    XCTAssertEqual(toolExecutor.calls.count, 1)
    XCTAssertEqual(streamClient.requests.count, 3)
    XCTAssertNil(finalBody["tools"])
    XCTAssertEqual(secondMessages.last?["tool_call_id"] as? String, "call-original")
    XCTAssertTrue(finalMessages.contains { ($0["tool_call_id"] as? String) == "call-repeated" })
    XCTAssertNil(failed(events))
    XCTAssertNotNil(completed(events))
  }

  @MainActor
  func testSupervisedResearchReturnsOnlyFinalRawControlResponse() async throws {
    let request = ModelStreamRequest(requestId: "plan", provider: .openAICompatible,
      endpoint: "https://api.deepseek.com/chat/completions", headers: [:], bodyJson: #"{"messages":[]}"#)
    let final = #"{"disposition":"respond","final_response":"Verified public source"}"#
    let stream = RecordingModelStreamClient(eventBatches: [
      [
        .textDelta(.init(requestId: "0", sequence: 1, text: "intermediate prose", receivedAtElapsedMs: 1)),
        .toolCallDelta(.init(requestId: "0", sequence: 2, payload: .init(
          callId: "image", index: 0, nameDelta: "web_image_search", argumentsDelta: #"{"query":"public diagrams"}"#))),
        .completed(.init(requestId: "0", finishReason: "tool_calls", completedAtElapsedMs: 2,
          providerReasoning: "provider-only fixture"))
      ],
      [
        .textDelta(.init(requestId: "1", sequence: 1, text: final, receivedAtElapsedMs: 3)),
        .completed(.init(requestId: "1", finishReason: "stop", completedAtElapsedMs: 4))
      ]
    ])
    let executor = RecordingConversationToolExecutor(result: #"{"status":"completed","results":[]}"#)
    let result = try await CloudSupervisedResearch.run(request: request,
      conversationId: "conversation", turnId: "turn", stream: stream, executor: executor)
    XCTAssertEqual(result, final)
    XCTAssertEqual(executor.calls.map(\.call.name), ["web_search"])
    XCTAssertTrue(executor.calls.first?.call.argumentsJson.contains(#""verticals":["image"]"#) == true)
    XCTAssertEqual(executor.calls.first?.context.conversationId, "conversation")
    XCTAssertTrue(executor.calls.first?.context.readOnlyAnalysis == true)
    let first = try object(stream.requests[0].bodyJson)
    let tools = try XCTUnwrap(first["tools"] as? [[String: Any]])
    let names = tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
    XCTAssertEqual(Set(names), CloudSupervisedResearch.allowedTools)
    XCTAssertNil(first["thinking"])
    XCTAssertTrue(stream.requests[0].preserveProviderReasoning)
    let second = try object(stream.requests[1].bodyJson)
    let messages = try XCTUnwrap(second["messages"] as? [[String: Any]])
    XCTAssertEqual(messages.first?["reasoning_content"] as? String, "provider-only fixture")
    XCTAssertTrue(stream.requests[1].bodyJson.contains("GALAXYSSI_UNTRUSTED_EVIDENCE"))
  }

  func testSupervisedResearchRejectsWholeBatchBeforeAnyDispatch() async throws {
    let request = ModelStreamRequest(requestId: "plan", provider: .openAICompatible,
      endpoint: "https://api.deepseek.com/chat/completions", headers: [:], bodyJson: #"{"messages":[]}"#)
    let calls = ["web_search", "web_watch"].enumerated().map { index, name in
      ModelStreamEvent.toolCallDelta(.init(requestId: "0", sequence: Int64(index + 1),
        payload: .init(callId: "call-\(index)", index: index, nameDelta: name, argumentsDelta: "{}")))
    }
    let stream = RecordingModelStreamClient(events: calls + [
      .completed(.init(requestId: "0", finishReason: "tool_calls", completedAtElapsedMs: 1))
    ])
    let executor = RecordingConversationToolExecutor(result: "{}")
    do {
      _ = try await CloudSupervisedResearch.run(request: request,
        conversationId: "conversation", turnId: "turn", stream: stream, executor: executor)
      XCTFail("Expected the whole batch to be rejected")
    } catch CloudSupervisedResearch.Error.invalidToolBatch {
      XCTAssertTrue(executor.calls.isEmpty)
    }
  }

  func testSupervisedControlDoesNotPresentUnexecutedDSMLAsAReply() {
    XCTAssertTrue(CloudSupervisedResearch.hasUnexecutedMarkup("<\u{FF5C}DSML\u{FF5C}function_calls>"))
    XCTAssertNil(AgentModelDirectResponseCodec.answer("<\u{FF5C}DSML\u{FF5C}function_calls>"))
    XCTAssertNotNil(AgentModelDirectResponseCodec.answer("The reply describes function calls without invoking one."))
    let plan = #"{"execution_location":"phone","actions":[]}"#
    let user = ChatMessage(contactId: "hermes", content: plan, isMine: true)
    let leaked = ChatMessage(contactId: "hermes", content: plan, isMine: false)
    XCTAssertFalse(CloudSupervisedResearch.isTranscriptControlReply(user))
    XCTAssertTrue(CloudSupervisedResearch.isTranscriptControlReply(leaked))
    XCTAssertFalse(CloudSupervisedResearch.isControlPayload("The field execution_location is optional in this example."))
  }

  func testProviderReasoningIsNotSerializedOrEnabledOnProxyEndpoints() throws {
    let frame = ModelStreamCompleted(requestId: "r", finishReason: "tool_calls",
      completedAtElapsedMs: 1, providerReasoning: "provider-only fixture")
    let encoded = try JSONEncoder().encode(frame)
    XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("provider-only fixture"))
    XCTAssertNil(try JSONDecoder().decode(ModelStreamCompleted.self, from: encoded).providerReasoning)
    let proxy = ModelStreamRequest(requestId: "r", provider: .openAICompatible,
      endpoint: "https://api.deepseek.com.example.test/chat/completions", headers: [:], bodyJson: "{}")
    XCTAssertFalse(proxy.isDirectDeepSeekChatEndpoint)
  }

  private func makeFixture() throws -> Fixture {
    let secrets = InMemorySecretStore()
    let store = makeStore(secrets: secrets)
    let contact = try store.addCloudModelContact(
      displayName: "Model A",
      provider: "OpenAI",
      modelId: "model-a",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "sk-live",
      apiStyle: .openAICompatible
    )
    let turns = [
      ChatMessage(
        contactId: contact.id,
        content: "hello",
        isMine: true,
        conversationId: "conversation",
        turnId: "turn"
      )
    ]
    return Fixture(contact: contact, store: store, turns: turns)
  }

  @MainActor
  private func makeStore(secrets: GalaxySSISecretStore) -> GalaxySSIStore {
    let suite = "CloudConversationStreamEngineTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return GalaxySSIStore(defaults: defaults, secrets: secrets)
  }

  private func collect(_ stream: AsyncThrowingStream<ModelStreamEvent, Error>) async throws -> [ModelStreamEvent] {
    var events: [ModelStreamEvent] = []
    for try await event in stream {
      events.append(event)
    }
    return events
  }

  private func textDeltas(_ events: [ModelStreamEvent]) -> [ModelStreamTextDelta] {
    events.compactMap {
      if case .textDelta(let value) = $0 { return value }
      return nil
    }
  }

  private func toolDeltas(_ events: [ModelStreamEvent]) -> [ModelStreamToolCallDelta] {
    events.compactMap {
      if case .toolCallDelta(let value) = $0 { return value }
      return nil
    }
  }

  private func completed(_ events: [ModelStreamEvent]) -> ModelStreamCompleted? {
    events.compactMap {
      if case .completed(let value) = $0 { return value }
      return nil
    }.first
  }

  private func failed(_ events: [ModelStreamEvent]) -> ModelStreamFailed? {
    events.compactMap {
      if case .failed(let value) = $0 { return value }
      return nil
    }.first
  }

  private struct Fixture {
    var contact: GalaxySSIContact
    var store: GalaxySSIStore
    var turns: [ChatMessage]
  }

  private func object(_ bodyJson: String) throws -> [String: Any] {
    let data = try XCTUnwrap(bodyJson.data(using: .utf8))
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func toolRound(index: Int, callId: String, query: String) -> [ModelStreamEvent] {
    let requestId = "tool-round-\(index)"
    return [
      .toolCallDelta(
        ModelStreamToolCallDelta(
          requestId: requestId,
          sequence: 1,
          payload: ToolCallPayload(
            callId: callId,
            index: 0,
            nameDelta: "web_search",
            argumentsDelta: "{\"query\":\"\(query)\"}"
          )
        )
      ),
      .completed(
        ModelStreamCompleted(
          requestId: requestId,
          finishReason: "tool_calls",
          completedAtElapsedMs: Int64(10 + index)
        )
      )
    ]
  }
}

private final class RecordingModelStreamClient: CloudModelStreamClient {
  var requests: [ModelStreamRequest] = []
  var cancellations: [(requestId: String, reason: ModelStreamCancelReason)] = []
  private var eventBatches: [[ModelStreamEvent]]

  init(events: [ModelStreamEvent]) {
    self.eventBatches = [events]
  }

  init(eventBatches: [[ModelStreamEvent]]) {
    self.eventBatches = eventBatches
  }

  func stream(_ request: ModelStreamRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
    requests.append(request)
    let events = eventBatches.isEmpty ? [] : eventBatches.removeFirst()
    return AsyncThrowingStream { continuation in
      events.forEach { continuation.yield($0) }
      continuation.finish()
    }
  }

  func cancel(requestId: String, reason: ModelStreamCancelReason) async {
    cancellations.append((requestId: requestId, reason: reason))
  }
}

private final class RecordingConversationToolExecutor: CloudConversationToolExecuting {
  struct Call {
    var call: AssembledToolCall
    var context: CloudConversationToolExecutionContext
  }

  var result: String
  var calls: [Call] = []

  init(result: String) {
    self.result = result
  }

  func executeTool(call: AssembledToolCall, context: CloudConversationToolExecutionContext) throws -> String {
    calls.append(Call(call: call, context: context))
    return result
  }
}

private final class RecordingLegacyConversationSender: CloudConversationLegacySending {
  struct Call {
    var contact: GalaxySSIContact
    var turns: [ChatMessage]
  }

  var reply: String
  var calls: [Call] = []

  init(reply: String) {
    self.reply = reply
  }

  func send(contact: GalaxySSIContact, store: GalaxySSIStore, turns: [ChatMessage]) async throws -> String {
    calls.append(Call(contact: contact, turns: turns))
    return reply
  }
}
