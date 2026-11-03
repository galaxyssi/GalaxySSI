import XCTest
@testable import GalaxySSI

final class MessageCoordinatorCloudStreamingTests: XCTestCase {
  @MainActor
  func testScreenAnalysisStopTargetsOwnedTurnAndPreservesPartialOutput() async throws {
    let fixture = try makeFixture()
    let stream = RecordingCloudConversationStream(events: [])
    let coordinator = MessageCoordinator(store: fixture.store, cloudStreamEngine: stream,
      disclosureStore: InMemoryAgentDataDisclosureStore())
    let owned = fixture.store.appendOutgoing("Analyze screenshot", to: fixture.contact.id, turnId: "owned")
    let unrelated = fixture.store.appendOutgoing("Other request", to: fixture.contact.id, turnId: "other")
    let partial = fixture.store.appendIncoming("Partial answer", from: fixture.contact.id,
      remoteMessageId: "partial", status: .sent, conversationId: owned.conversationId, turnId: owned.turnId)

    let cancelled = await coordinator.cancelScreenAnalysis([owned])
    XCTAssertTrue(cancelled)
    XCTAssertEqual(stream.cancelledRequestIDs, ["owned"])
    let messages = fixture.store.messages(for: fixture.contact.id)
    let stopped = try XCTUnwrap(messages.first { $0.id == owned.id })
    XCTAssertTrue(stopped.deliveryTrace.contains { $0.stage == "screen_analysis_cancelled" })
    XCTAssertEqual(messages.first { $0.id == partial.id }?.content, "Partial answer")
    XCTAssertEqual(messages.first { $0.id == unrelated.id }?.deliveryStatus, unrelated.deliveryStatus)
    var payload: [String: Any] = ["type": "agent_task_event", "source_message_id": owned.id.uuidString,
      "conversation_id": owned.conversationId, "turn_id": owned.turnId]
    XCTAssertTrue(AgentScreenAnalysisReplyPolicy.isStopped(payload, messages: messages))
    payload["source_message_id"] = unrelated.id.uuidString
    XCTAssertFalse(AgentScreenAnalysisReplyPolicy.isStopped(payload, messages: messages))
    payload["source_message_id"] = owned.id.uuidString
    payload["turn_id"] = "other"
    XCTAssertFalse(AgentScreenAnalysisReplyPolicy.isStopped(payload, messages: messages))
    payload["turn_id"] = owned.turnId
    payload["conversation_id"] = "foreign"
    XCTAssertFalse(AgentScreenAnalysisReplyPolicy.isStopped(payload, messages: messages))
    payload["conversation_id"] = owned.conversationId
    payload["type"] = "delivery_ack"
    XCTAssertFalse(AgentScreenAnalysisReplyPolicy.isStopped(payload, messages: messages))
  }

  @MainActor
  func testScreenAnalysisStopDoesNotInvalidateCompletedAnswer() async throws {
    let fixture = try makeFixture()
    let stream = RecordingCloudConversationStream(events: [])
    let coordinator = MessageCoordinator(store: fixture.store, cloudStreamEngine: stream,
      disclosureStore: InMemoryAgentDataDisclosureStore())
    let outgoing = fixture.store.appendOutgoing("Analyze", to: fixture.contact.id, turnId: "finished")
    _ = fixture.store.appendIncoming("Final answer", from: fixture.contact.id,
      remoteMessageId: "final", status: .delivered, conversationId: outgoing.conversationId, turnId: outgoing.turnId)
    let before = fixture.store.messages(for: fixture.contact.id)
    let cancelled = await coordinator.cancelScreenAnalysis([outgoing])
    XCTAssertTrue(cancelled)
    XCTAssertTrue(stream.cancelledRequestIDs.isEmpty)
    XCTAssertEqual(fixture.store.messages(for: fixture.contact.id), before)
  }

  @MainActor
  func testCitationPreviewIsReplacedInTheSameSilentAssistantRow() async throws {
    let fixture = try makeFixture()
    let stream = RecordingCloudConversationStream(events: [
      .citationPreview(ModelStreamCitationPreview(
        requestId: "turn",
        text: "Preview [source](https://example.com)",
        receivedAtElapsedMs: 1
      )),
      .textDelta(ModelStreamTextDelta(
        requestId: "turn",
        sequence: 1,
        text: "Final answer [source](https://example.com)",
        receivedAtElapsedMs: 2
      )),
      .completed(ModelStreamCompleted(requestId: "turn", finishReason: "stop", completedAtElapsedMs: 3))
    ])
    let coordinator = MessageCoordinator(
      store: fixture.store,
      cloudStreamEngine: stream,
      disclosureStore: InMemoryAgentDataDisclosureStore()
    )
    var deltas: [ChatMessage] = []
    coordinator.onIncomingMessageDelta = { deltas.append($0) }

    await coordinator.send("hello", to: fixture.contact)

    let messages = fixture.store.messages(for: fixture.contact.id)
    XCTAssertEqual(messages.count, 2)
    XCTAssertEqual(deltas.count, 2)
    XCTAssertEqual(deltas[0].id, deltas[1].id)
    XCTAssertNil(AgentReplySpeechPresentationPolicy.target(deltas[0]))
    XCTAssertNotNil(AgentReplySpeechPresentationPolicy.target(deltas[1]))
    XCTAssertEqual(messages.last?.content, "Final answer [source](https://example.com)")
  }

  @MainActor
  func testCloudAPISendBuildsSingleStreamingIncomingMessage() async throws {
    let fixture = try makeFixture()
    let stream = RecordingCloudConversationStream(events: [
      .connected(ModelStreamConnected(requestId: "turn", httpStatus: 200, connectedAtElapsedMs: 1)),
      .textDelta(ModelStreamTextDelta(requestId: "turn", sequence: 1, text: "Hel", receivedAtElapsedMs: 2)),
      .textDelta(ModelStreamTextDelta(requestId: "turn", sequence: 2, text: "lo", receivedAtElapsedMs: 3)),
      .completed(ModelStreamCompleted(requestId: "turn", finishReason: "stop", completedAtElapsedMs: 4))
    ])
    let coordinator = MessageCoordinator(
      store: fixture.store,
      cloudStreamEngine: stream,
      disclosureStore: InMemoryAgentDataDisclosureStore()
    )
    var incomingCallbacks: [ChatMessage] = []
    coordinator.onIncomingMessage = { incomingCallbacks.append($0) }

    await coordinator.send("hello", to: fixture.contact)

    let messages = fixture.store.messages(for: fixture.contact.id)
    XCTAssertEqual(stream.calls.count, 1)
    XCTAssertEqual(messages.count, 2)
    XCTAssertEqual(messages[0].content, "hello")
    XCTAssertEqual(messages[0].deliveryStatus, .delivered)
    XCTAssertEqual(messages[0].deliveryTrace.map(\.stage), ["queued", "cloud_request", "cloud_reply"])
    XCTAssertEqual(messages[1].content, "Hello")
    XCTAssertEqual(messages[1].deliveryStatus, .delivered)
    XCTAssertEqual(messages[1].deliveryTrace.map(\.stage), ["cloud_reply", "cloud_reply_received"])
    XCTAssertEqual(incomingCallbacks.map(\.content), ["Hello"])
  }

  @MainActor
  func testCloudAPIFailureMarksPartialStreamingReplyFailed() async throws {
    let fixture = try makeFixture()
    let stream = RecordingCloudConversationStream(events: [
      .textDelta(ModelStreamTextDelta(requestId: "turn", sequence: 1, text: "partial", receivedAtElapsedMs: 2)),
      .failed(
        ModelStreamFailed(
          requestId: "turn",
          error: ModelStreamError(code: "STREAM_INTERRUPTED", message: "broken", partialResponse: true)
        )
      )
    ])
    let coordinator = MessageCoordinator(
      store: fixture.store,
      cloudStreamEngine: stream,
      disclosureStore: InMemoryAgentDataDisclosureStore()
    )

    await coordinator.send("hello", to: fixture.contact)

    let messages = fixture.store.messages(for: fixture.contact.id)
    XCTAssertEqual(messages.count, 3)
    XCTAssertEqual(messages[1].content, "partial")
    XCTAssertEqual(messages[1].deliveryStatus, .failed)
    XCTAssertEqual(messages[1].deliveryTrace.map(\.stage), ["cloud_reply", "cloud_error"])
    XCTAssertEqual(messages[2].isSystem, true)
    XCTAssertTrue(messages[2].content.contains("broken"))
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
    return Fixture(contact: contact, store: store)
  }

  @MainActor
  private func makeStore(secrets: GalaxySSISecretStore) -> GalaxySSIStore {
    let suite = "MessageCoordinatorCloudStreamingTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return GalaxySSIStore(defaults: defaults, secrets: secrets)
  }

  private struct Fixture {
    var contact: GalaxySSIContact
    var store: GalaxySSIStore
  }
}

private final class RecordingCloudConversationStream: CloudConversationStreaming {
  struct Call {
    var contact: GalaxySSIContact
    var turns: [ChatMessage]
    var requestId: String
  }

  var calls: [Call] = []
  var events: [ModelStreamEvent]
  var cancelledRequestIDs: [String] = []

  func cancel(requestId: String, reason: ModelStreamCancelReason) async {
    cancelledRequestIDs.append(requestId)
  }

  init(events: [ModelStreamEvent]) {
    self.events = events
  }

  func streamConversation(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    turns: [ChatMessage],
    requestId: String
  ) -> AsyncThrowingStream<ModelStreamEvent, Error> {
    calls.append(Call(contact: contact, turns: turns, requestId: requestId))
    return AsyncThrowingStream { continuation in
      events.forEach { continuation.yield($0) }
      continuation.finish()
    }
  }
}
