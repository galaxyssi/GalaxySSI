import XCTest
@testable import GalaxySSI

final class GlobalConversationEventPolicyTests: XCTestCase {
  func testEveryGlobalEventTypeHasExactlyOneCanonicalPublisher() {
    let audit = GlobalEventPublisherContract.audit()

    XCTAssertTrue(audit.complete, "\(audit)")
    XCTAssertEqual(
      Set(GlobalConversationEventType.allCases),
      Set(GlobalEventPublisherContract.descriptors.flatMap { Array($0.eventTypes) })
    )
  }

  func testRequiredSemanticInputsAreRepresentedByTheContract() {
    let semanticClasses = Set(GlobalEventPublisherContract.descriptors.map(\.semanticClass))

    XCTAssertTrue(semanticClasses.contains(.message))
    XCTAssertTrue(semanticClasses.contains(.file))
    XCTAssertTrue(semanticClasses.contains(.decision))
    XCTAssertTrue(semanticClasses.contains(.task))
    XCTAssertTrue(semanticClasses.contains(.tool))
    XCTAssertTrue(semanticClasses.contains(.feedback))
  }

  func testHostAddsCanonicalPublisherMetadataAndRejectsSpoofing() throws {
    let normalized = try XCTUnwrap(GlobalConversationEventPolicy.normalize(event().withMetadata([
      GlobalEventPublisherContract.metadataPublisherId: "untrusted.publisher",
      GlobalEventPublisherContract.metadataSemanticClass: "untrusted",
      "origin": "transcript"
    ])))

    XCTAssertEqual(normalized.metadata[GlobalEventPublisherContract.metadataPublisherId], "conversation.message")
    XCTAssertEqual(normalized.metadata[GlobalEventPublisherContract.metadataSemanticClass], "message")
    XCTAssertEqual(normalized.metadata[GlobalEventPublisherContract.metadataSchemaVersion], GlobalEventPublisherContract.schemaVersion)
    XCTAssertEqual(normalized.metadata["origin"], "transcript")
  }

  func testEveryEventTypeHasAValidBoundedEnvelope() {
    let normalized = GlobalConversationEventType.allCases.map { type in
      GlobalConversationEventPolicy.normalize(event(type: type))
    }

    XCTAssertTrue(normalized.allSatisfy { $0 != nil })
    XCTAssertEqual(Set(GlobalConversationEventType.allCases), Set(normalized.compactMap { $0?.type }))
  }

  func testSessionPrivateEnvelopeRetainsOnlyLifecycleIdentity() throws {
    let normalized = try XCTUnwrap(GlobalConversationEventPolicy.normalize(
      event(type: .conversationUpdated)
        .withSensitivity(.sessionPrivate)
        .withContent("private content")
        .withContentRef("file:///private/item.txt?token=secret")
        .withTitle("Private project")
        .withTopicHints(["Private project"])
        .withMetadata([
          "global_visibility": "excluded",
          "private_mode": "true",
          "resource_name": "private-item.txt",
          "api_key": "secret"
        ])
    ))

    XCTAssertEqual(normalized.content, "")
    XCTAssertEqual(normalized.contentRef, "")
    XCTAssertEqual(normalized.conversationTitle, "")
    XCTAssertTrue(normalized.topicHints.isEmpty)
    XCTAssertEqual(normalized.metadata, ["global_visibility": "excluded", "private_mode": "true"])
  }

  func testSessionPrivateContentEventsAreRejectedBeforeGlobalPersistence() {
    let privateTypes: Set<GlobalConversationEventType> = [
      .messageCreated,
      .attachmentAdded,
      .toolResult,
      .artifactCreated
    ]

    for type in privateTypes {
      XCTAssertNil(GlobalConversationEventPolicy.normalize(
        event(type: type).withSensitivity(.sessionPrivate)
      ))
    }
  }

  func testPrivateAndTrackingPausedDeletionEventsAreRejectedBeforeGlobalPersistence() throws {
    XCTAssertNil(GlobalConversationEventPolicy.normalize(
      event(type: .conversationDeleted).withSensitivity(.sessionPrivate)
    ))
    XCTAssertNil(GlobalConversationEventPolicy.normalize(
      event(type: .conversationDeleted).withMetadata(["tracking_paused": "true"])
    ))

    let visibleDeletion = try XCTUnwrap(GlobalConversationEventPolicy.normalize(
      event(type: .conversationDeleted).withTitle("Visible conversation")
    ))
    XCTAssertEqual(visibleDeletion.sensitivity, .personal)
    XCTAssertEqual(visibleDeletion.conversationTitle, "Visible conversation")
  }

  func testPausedOrExcludedLifecycleIsSanitizedEvenWhenProducerMarksItPersonal() throws {
    let normalized = try XCTUnwrap(GlobalConversationEventPolicy.normalize(
      event(type: .conversationUpdated)
        .withContent("Private renamed topic")
        .withContentRef("encrypted://private/conversation")
        .withTitle("Private renamed topic")
        .withTopicHints(["Private renamed topic"])
        .withMetadata([
          "tracking_paused": "true",
          "global_visibility": "excluded",
          "origin": "conversation_lifecycle"
        ])
    ))

    XCTAssertEqual(normalized.sensitivity, .sessionPrivate)
    XCTAssertEqual(normalized.content, "")
    XCTAssertEqual(normalized.contentRef, "")
    XCTAssertEqual(normalized.conversationTitle, "")
    XCTAssertTrue(normalized.topicHints.isEmpty)
    XCTAssertEqual(normalized.metadata["tracking_paused"], "true")
    XCTAssertNil(normalized.metadata[GlobalEventPublisherContract.metadataPublisherId])
  }

  func testCredentialMetadataIsRemovedWithoutHidingAuthorizationState() throws {
    let normalized = try XCTUnwrap(GlobalConversationEventPolicy.normalize(event().withMetadata([
      "authorization_scope": "microphone",
      "authorization_state": "granted",
      "api_key": "secret-key",
      "provider_access_token": "secret-token",
      "password": "secret-password",
      "origin": "capability"
    ])))

    XCTAssertEqual(normalized.metadata["authorization_scope"], "microphone")
    XCTAssertEqual(normalized.metadata["authorization_state"], "granted")
    XCTAssertEqual(normalized.metadata["origin"], "capability")
    XCTAssertNil(normalized.metadata["api_key"])
    XCTAssertNil(normalized.metadata["provider_access_token"])
    XCTAssertNil(normalized.metadata["password"])
  }

  func testDeniedContentNeverEntersTheGlobalStreamButRevocationEventsDo() throws {
    XCTAssertNil(GlobalConversationEventPolicy.normalize(event().withMetadata([
      "authorization_state": "denied"
    ])))
    XCTAssertNil(GlobalConversationEventPolicy.normalize(event().withMetadata([
      "tracking_paused": "true"
    ])))

    let revocation = try XCTUnwrap(GlobalConversationEventPolicy.normalize(
      event(type: .authorizationRevoked, actor: .system).withMetadata([
        "authorization_state": "revoked",
        "api_key": "secret"
      ])
    ))
    XCTAssertEqual(revocation.metadata[GlobalEventPublisherContract.metadataPublisherId], "authorization.lifecycle")
    XCTAssertNil(revocation.metadata["api_key"])
  }

  func testEventPayloadAndEvidenceSetsAreBoundedDeterministically() throws {
    let normalized = try XCTUnwrap(GlobalConversationEventPolicy.normalize(
      event()
        .withId(String(repeating: "i", count: 700))
        .withConversationId(String(repeating: "c", count: 700))
        .withContent(String(repeating: "x", count: 13_000))
        .withTitle(String(repeating: "t", count: 300))
        .withTopicHints(Set((1...30).map { "topic-\($0)" }))
        .withMetadata(Dictionary(uniqueKeysWithValues: (1...70).map { ("key-\($0)", String(repeating: "v", count: 1_200)) }))
        .withCausalEventIds(Set((1...150).map { "cause-\($0)" }))
        .withRetractedEventIds(Set((1...150).map { "retracted-\($0)" }))
    ))

    XCTAssertEqual(normalized.id.count, 512)
    XCTAssertEqual(normalized.conversationId.count, 512)
    XCTAssertEqual(normalized.content.count, 12_000)
    XCTAssertEqual(normalized.conversationTitle.count, 160)
    XCTAssertEqual(normalized.topicHints.count, 16)
    XCTAssertEqual(normalized.metadata.count, 48)
    XCTAssertEqual(normalized.metadata[GlobalEventPublisherContract.metadataPublisherId], "conversation.message")
    XCTAssertEqual(normalized.metadata[GlobalEventPublisherContract.metadataSchemaVersion], GlobalEventPublisherContract.schemaVersion)
    XCTAssertTrue(normalized.metadata.values.allSatisfy { $0.count <= 1_024 })
    XCTAssertEqual(normalized.causalEventIds.count, 128)
    XCTAssertEqual(normalized.retractedEventIds.count, 128)
  }

  func testNonEncryptedContentReferenceDropsQueryCredentials() throws {
    let normalized = try XCTUnwrap(GlobalConversationEventPolicy.normalize(
      event().withContentRef("https://example.test/report.pdf?token=secret#page=2")
    ))

    XCTAssertEqual(normalized.contentRef, "https://example.test/report.pdf")
  }

  func testInvalidIdentityIsRejectedBeforePersistence() {
    XCTAssertNil(GlobalConversationEventPolicy.normalize(event().withId("")))
    XCTAssertNil(GlobalConversationEventPolicy.normalize(event().withConversationId("")))
  }

  private func event(
    type: GlobalConversationEventType = .messageCreated,
    actor: GlobalConversationActor = .user
  ) -> GlobalConversationEvent {
    GlobalConversationEvent(
      id: "event-id",
      type: type,
      conversationId: "conversation-id",
      messageId: "message-id",
      actor: actor,
      content: "content",
      contentRef: "encrypted://event/content",
      conversationTitle: "Topic",
      topicHints: ["Topic"]
    )
  }
}

private extension GlobalConversationEvent {
  func withId(_ value: String) -> GlobalConversationEvent {
    var copy = self
    copy.id = value
    return copy
  }

  func withConversationId(_ value: String) -> GlobalConversationEvent {
    var copy = self
    copy.conversationId = value
    return copy
  }

  func withSensitivity(_ value: GlobalConversationSensitivity) -> GlobalConversationEvent {
    var copy = self
    copy.sensitivity = value
    return copy
  }

  func withContent(_ value: String) -> GlobalConversationEvent {
    var copy = self
    copy.content = value
    return copy
  }

  func withContentRef(_ value: String) -> GlobalConversationEvent {
    var copy = self
    copy.contentRef = value
    return copy
  }

  func withTitle(_ value: String) -> GlobalConversationEvent {
    var copy = self
    copy.conversationTitle = value
    return copy
  }

  func withTopicHints(_ value: Set<String>) -> GlobalConversationEvent {
    var copy = self
    copy.topicHints = value
    return copy
  }

  func withMetadata(_ value: [String: String]) -> GlobalConversationEvent {
    var copy = self
    copy.metadata = value
    return copy
  }

  func withCausalEventIds(_ value: Set<String>) -> GlobalConversationEvent {
    var copy = self
    copy.causalEventIds = value
    return copy
  }

  func withRetractedEventIds(_ value: Set<String>) -> GlobalConversationEvent {
    var copy = self
    copy.retractedEventIds = value
    return copy
  }
}
