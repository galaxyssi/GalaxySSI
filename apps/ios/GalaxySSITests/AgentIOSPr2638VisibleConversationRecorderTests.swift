import XCTest
@testable import GalaxySSI

final class AgentIOSPr2638VisibleConversationRecorderTests: XCTestCase {
  func testPersistsOneThousandVisiblePrivateConversationsIdempotently() throws {
    let fixture = makeFixture()
    defer { fixture.cleanup() }
    let unrelated = AgentConversation(
      id: "unrelated-user-conversation",
      title: "Existing user conversation",
      createdAt: 1,
      updatedAt: 1
    )
    XCTAssertTrue(fixture.conversations.upsert(unrelated))
    XCTAssertTrue(fixture.transcripts.insert(entry(
      id: "unrelated-entry",
      conversationID: unrelated.id,
      text: "Existing user message"
    )))

    let initial = results(detail: "first run")
    let first = try fixture.recorder.persist(initial)

    XCTAssertEqual(first.conversationsBefore, 0)
    XCTAssertEqual(first.conversationsAfter, 1_000)
    XCTAssertEqual(first.persistedCount, 1_000)
    XCTAssertEqual(first.passedCount, 1_000)
    XCTAssertEqual(fixture.conversations.count(), 1_001)
    assertVisibleConversation(ordinal: 1, fixture: fixture)
    assertVisibleConversation(ordinal: 500, fixture: fixture)
    assertVisibleConversation(ordinal: 1_000, fixture: fixture)

    let rerun = try fixture.recorder.persist(results(detail: "second run"))

    XCTAssertEqual(rerun.conversationsBefore, 1_000)
    XCTAssertEqual(rerun.conversationsAfter, 1_000)
    XCTAssertEqual(fixture.conversations.count(), 1_001)
    XCTAssertEqual(fixture.conversations.read(unrelated.id), unrelated)
    XCTAssertEqual(fixture.transcripts.listConversation(unrelated.id).map(\.text), ["Existing user message"])
    let lastID = AgentIOSPr2627To2633RegressionCorpus.cases[999].conversationID
    XCTAssertTrue(fixture.transcripts.listConversation(lastID).last?.text.contains("second run") == true)
  }

  func testRejectsIncompleteCorpusWithoutWriting() {
    let fixture = makeFixture()
    defer { fixture.cleanup() }

    XCTAssertThrowsError(try fixture.recorder.persist(Array(results(detail: "partial").prefix(999)))) {
      XCTAssertEqual($0 as? AgentIOSPr2638PersistenceError, .incompleteCorpus(999))
    }
    XCTAssertEqual(fixture.conversations.count(), 0)
    XCTAssertTrue(fixture.transcripts.listAll(limit: 500).isEmpty)
  }

  private func assertVisibleConversation(ordinal: Int, fixture: Fixture) {
    let testCase = AgentIOSPr2627To2633RegressionCorpus.cases[ordinal - 1]
    let conversation = fixture.conversations.read(testCase.conversationID)
    XCTAssertEqual(conversation?.privateMode, true)
    XCTAssertEqual(conversation?.trackingPaused, true)
    XCTAssertEqual(conversation?.status, .active)
    XCTAssertEqual(fixture.transcripts.listConversation(testCase.conversationID).count, 2)
  }

  private func results(detail: String) -> [AgentIOSPr2638ExecutionResult] {
    AgentIOSPr2627To2633RegressionCorpus.cases.map {
      AgentIOSPr2638ExecutionResult(
        testCase: $0,
        passed: true,
        durationMillis: Int64($0.variantIndex + 1),
        detail: detail
      )
    }
  }

  private func entry(id: String, conversationID: String, text: String) -> AgentTranscriptEntry {
    AgentTranscriptEntry(
      id: id,
      role: .user,
      text: text,
      timestampMillis: 1,
      conversationId: conversationID
    )
  }

  private func makeFixture() -> Fixture {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentIOSPr2638-\(UUID().uuidString)", isDirectory: true)
    let suiteName = "AgentIOSPr2638-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let secrets = InMemorySecretStore()
    let conversations = AgentConversationDatabase(
      fileURL: root.appendingPathComponent("conversations.sqlite"),
      secrets: secrets
    )
    let transcripts = UserDefaultsAgentTranscriptEntryStore(
      defaults: defaults,
      key: "pr2638-transcripts",
      secrets: secrets
    )
    return Fixture(
      conversations: conversations,
      transcripts: transcripts,
      recorder: AgentIOSPr2638VisibleConversationRecorder(
        conversations: conversations,
        transcripts: transcripts
      ),
      cleanup: {
        UserDefaultsAgentTranscriptEntryStore.destroyPersistentStore(
          defaults: defaults,
          key: "pr2638-transcripts",
          secrets: secrets
        )
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
      }
    )
  }
}

private struct Fixture {
  var conversations: AgentConversationDatabase
  var transcripts: UserDefaultsAgentTranscriptEntryStore
  var recorder: AgentIOSPr2638VisibleConversationRecorder
  var cleanup: () -> Void
}
