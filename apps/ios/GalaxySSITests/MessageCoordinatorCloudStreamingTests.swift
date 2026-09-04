import XCTest
@testable import GalaxySSI

final class MessageCoordinatorCloudStreamingTests: XCTestCase {
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
