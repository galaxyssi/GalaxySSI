import XCTest
@testable import SignalASI

final class CloudConversationStreamEngineTests: XCTestCase {
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
              argumentsDelta: #"{"query":"SignalASI"}"#
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
    let toolExecutor = RecordingConversationToolExecutor(result: #"{"results":[{"url":"https://signalasi.example"}]}"#)
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
    XCTAssertTrue((toolMessage["content"] as? String)?.contains("SIGNALASI_UNTRUSTED_EVIDENCE") == true)
    XCTAssertEqual(completed(events)?.finishReason, "stop")
  }

  @MainActor
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
  private func makeStore(secrets: SignalASISecretStore) -> SignalASIStore {
    let suite = "CloudConversationStreamEngineTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return SignalASIStore(defaults: defaults, secrets: secrets)
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
    var contact: SignalASIContact
    var store: SignalASIStore
    var turns: [ChatMessage]
  }

  private func object(_ bodyJson: String) throws -> [String: Any] {
    let data = try XCTUnwrap(bodyJson.data(using: .utf8))
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
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
    var contact: SignalASIContact
    var turns: [ChatMessage]
  }

  var reply: String
  var calls: [Call] = []

  init(reply: String) {
    self.reply = reply
  }

  func send(contact: SignalASIContact, store: SignalASIStore, turns: [ChatMessage]) async throws -> String {
    calls.append(Call(contact: contact, turns: turns))
    return reply
  }
}
