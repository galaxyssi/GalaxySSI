import XCTest
@testable import SignalASI

final class AgentIOSPr2639CognitionMatrixRecorderTests: XCTestCase {
  func testReplacesOneThousandVisibleCognitionConversationsAndPreservesUserHistory() throws {
    let fixture = makeFixture()
    defer { fixture.cleanup() }
    let unrelated = AgentConversation(id: "user-history", title: "User history", createdAt: 1, updatedAt: 1)
    let unrelatedMessage = ChatMessage(
      id: UUID(uuidString: "26390000-0000-4000-8000-999999999999")!,
      contactId: "hermes",
      content: "Keep this message",
      isMine: true,
      conversationId: unrelated.id
    )
    XCTAssertTrue(fixture.conversations.upsert(unrelated))
    XCTAssertTrue(fixture.messages.upsert(unrelatedMessage))

    let first = try fixture.recorder.replace(AgentIOSPr2639CognitionMatrix.outcomes(detail: "first run"))
    XCTAssertEqual(first.deletedConversations, 0)
    XCTAssertEqual(first.visibleConversations, 1_000)
    XCTAssertEqual(first.visibleMessages, 2_000)
    XCTAssertEqual(first.passed, 1_000)
    XCTAssertEqual(first.failed, 0)

    let second = try fixture.recorder.replace(AgentIOSPr2639CognitionMatrix.outcomes(detail: "second run"))
    XCTAssertEqual(second.deletedConversations, 1_000)
    XCTAssertEqual(second.visibleConversations, 1_000)
    XCTAssertEqual(second.visibleMessages, 2_000)
    XCTAssertEqual(fixture.conversations.count(), 1_001)
    XCTAssertEqual(fixture.conversations.read(unrelated.id), unrelated)
    XCTAssertEqual(fixture.messages.messages(conversationId: unrelated.id), [unrelatedMessage])
    XCTAssertTrue(fixture.messages.messages(conversationId: "ios-pr2639-matrix-1000").last?.content.contains("second run") == true)
  }

  func testMatrixMatchesAndroidGroupDistribution() {
    let outcomes = AgentIOSPr2639CognitionMatrix.outcomes(detail: "distribution")
    XCTAssertEqual(outcomes.count, 1_000)
    XCTAssertEqual(Dictionary(grouping: outcomes, by: \.group).mapValues(\.count), [
      "foreground_core_memory": 100,
      "foreground_prompt_compiler": 100,
      "background_scheduler_and_ingestion": 80,
      "background_memory_evolution": 160,
      "background_graph_memory": 120,
      "background_knowledge_index": 100,
      "background_skills": 100,
      "background_knowledge_gap_and_research": 80,
      "proactive_cognition_loop": 80,
      "background_memory_critic": 40,
      "obsidian_knowledge_projection": 40
    ])
  }

  @MainActor
  func testCreatesPrivateSessionBeforeItsFirstMessage() {
    let suiteName = "AgentIOSPr2639PrivateSession-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SignalASIStore(defaults: defaults, secrets: InMemorySecretStore())

    let conversation = store.createAgentSession(title: "Private matrix", privateMode: true)

    XCTAssertTrue(conversation.privateMode)
    XCTAssertTrue(store.agentSession(id: conversation.id)?.privateMode == true)
  }

  func testPrivateDeletionLifecycleCannotEnterGlobalCognition() {
    let normalized = GlobalConversationEventPolicy.normalize(GlobalConversationEvent(
      id: "private-delete",
      type: .conversationDeleted,
      conversationId: "private-conversation",
      actor: .system,
      content: "private content",
      conversationTitle: "private title",
      topicHints: ["private topic"],
      sensitivity: .sessionPrivate
    ))

    XCTAssertNil(normalized)
  }

  func testClearsOnlyRequestedConversationModelSelections() {
    let suiteName = "AgentIOSPr2639ModelSelections-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    for id in ["matrix-a", "matrix-b", "user-history"] {
      AgentModelSelectionSettings.selectManual(
        for: id,
        targetId: "local",
        modelId: "model",
        displayName: "Model",
        defaults: defaults
      )
    }

    AgentModelSelectionSettings.clearConversations(["matrix-a", "matrix-b"], defaults: defaults)

    XCTAssertFalse(AgentModelSelectionSettings.hasStoredSelection(for: "matrix-a", defaults: defaults))
    XCTAssertFalse(AgentModelSelectionSettings.hasStoredSelection(for: "matrix-b", defaults: defaults))
    XCTAssertTrue(AgentModelSelectionSettings.hasStoredSelection(for: "user-history", defaults: defaults))
  }

  private func makeFixture() -> Pr2639Fixture {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentIOSPr2639-\(UUID().uuidString)", isDirectory: true)
    let secrets = InMemorySecretStore()
    let conversations = AgentConversationDatabase(
      fileURL: root.appendingPathComponent("conversations.sqlite"),
      secrets: secrets
    )
    let messages = SignalASIChatHistoryDatabase(
      fileURL: root.appendingPathComponent("messages.sqlite"),
      secrets: secrets
    )
    return Pr2639Fixture(
      conversations: conversations,
      messages: messages,
      recorder: AgentIOSPr2639CognitionMatrixRecorder(conversations: conversations, messages: messages),
      cleanup: { try? FileManager.default.removeItem(at: root) }
    )
  }
}

private struct Pr2639Fixture {
  var conversations: AgentConversationDatabase
  var messages: SignalASIChatHistoryDatabase
  var recorder: AgentIOSPr2639CognitionMatrixRecorder
  var cleanup: () -> Void
}
