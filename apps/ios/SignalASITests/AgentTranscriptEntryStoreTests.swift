import XCTest

@testable import SignalASI

final class AgentTranscriptEntryStoreTests: XCTestCase {
  func testRetainsAndPagesEveryEntryWithoutCountLimits() throws {
    let store = makeStore()
    let expectedIds = (0..<2_105).map { "entry-\($0)" }
    for (index, id) in expectedIds.enumerated() {
      XCTAssertTrue(store.insert(entry(id, conversationId: "conversation-main", timestampMillis: Int64(index))))
    }

    let complete = store.listConversation("conversation-main")
    XCTAssertEqual(expectedIds, complete.map(\.id))

    var pagedIds: [String] = []
    var cursor: Int64?
    var hasMore = true
    while hasMore {
      let page = store.listConversationPage(
        conversationId: "conversation-main",
        beforeSequenceExclusive: cursor,
        pageSize: 137
      )
      pagedIds += page.entries.map(\.id)
      cursor = page.nextBeforeSequence
      hasMore = page.hasMore
    }

    XCTAssertEqual(expectedIds.count, pagedIds.count)
    XCTAssertEqual(Set(expectedIds), Set(pagedIds))
    XCTAssertEqual(expectedIds.count, Set(pagedIds).count)
  }

  func testStoresLongMessageContentAsPreviewAndHydratesWithoutTruncation() throws {
    let store = makeStore()
    let marker = "private-transcript-marker"
    let text = String(repeating: "content ", count: 4_000) + marker
    XCTAssertTrue(
      store.insert(
        entry("long-entry", conversationId: "long-conversation", timestampMillis: 1, text: text)
      )
    )

    let preview = try XCTUnwrap(
      store.listConversationPage(conversationId: "long-conversation", pageSize: 1).entries.first
    )
    XCTAssertTrue(AgentLargeOutputPolicy.hasDeferredContent(preview))
    XCTAssertLessThan(preview.text.utf16.count, text.utf16.count)
    XCTAssertFalse(preview.text.contains(marker))
    XCTAssertEqual(text.utf16.count, preview.textLength)
    XCTAssertEqual(text, store.listConversation("long-conversation").single().text)

    var reconstructed: [String] = []
    var offset = 0
    var done = false
    while !done {
      let page = try XCTUnwrap(store.textChunkPage(entryId: "long-entry", offset: offset, pageSize: 2))
      reconstructed += page.chunks
      offset = page.nextOffset
      done = page.done
    }
    XCTAssertEqual(text, reconstructed.joined())
  }

  func testStoresRichOutputChunksWithoutInlinePreview() throws {
    let store = makeStore()
    let rich = #"{"blocks":["# + String(repeating: #""item","#, count: 4_000) + #""tail"]}"#
    XCTAssertTrue(store.insert(
      entry(
        "rich-entry",
        conversationId: "rich-conversation",
        timestampMillis: 1,
        text: "Result",
        richOutputJson: rich
      )
    ))

    let preview = try XCTUnwrap(
      store.listConversationPage(conversationId: "rich-conversation", pageSize: 1).entries.first
    )
    XCTAssertTrue(preview.richOutputJson.isEmpty)
    XCTAssertGreaterThan(preview.richOutputChunkCount, 0)
    XCTAssertEqual(rich, store.findById("rich-entry")?.richOutputJson)

    let firstPage = try XCTUnwrap(store.richOutputChunkPage(entryId: "rich-entry", offset: 0, pageSize: 1))
    XCTAssertFalse(firstPage.done)
    XCTAssertEqual(String(rich.prefix(firstPage.chunks.joined().count)), firstPage.chunks.joined())
  }

  func testReadsOnlyEntriesAddedAfterVisibleWindowCursor() {
    let store = makeStore()
    for index in 0..<5 {
      XCTAssertTrue(store.insert(entry("entry-\(index)", conversationId: "conversation-main", timestampMillis: Int64(index))))
    }
    let initial = store.listConversationPage(conversationId: "conversation-main", pageSize: 2)
    XCTAssertEqual(["entry-3", "entry-4"], initial.entries.map(\.id))

    XCTAssertTrue(store.insert(entry("entry-5", conversationId: "conversation-main", timestampMillis: 5)))
    XCTAssertTrue(store.insert(entry("entry-6", conversationId: "conversation-main", timestampMillis: 6)))
    let delta = store.listConversationAfter(
      conversationId: "conversation-main",
      afterSequenceExclusive: initial.newestSequence ?? 0,
      pageSize: 10
    )

    XCTAssertEqual(["entry-5", "entry-6"], delta.entries.map(\.id))
    XCTAssertEqual(2, delta.entries.count)
    XCTAssertFalse(delta.hasMore)
  }

  func testFindsHydratedEntryByDedupeKeyAndRejectsDuplicateIds() {
    let store = makeStore()
    let text = String(repeating: "memo ", count: 4_000)
    let stored = entry(
      "dedupe-entry",
      conversationId: "conversation",
      timestampMillis: 1,
      text: text,
      dedupeKey: "agent-loop:turn:PLAN:1"
    )
    XCTAssertTrue(store.insert(stored))
    XCTAssertFalse(store.insert(stored))

    let found = store.findByDedupeKey(conversationId: "conversation", dedupeKey: "agent-loop:turn:PLAN:1")

    XCTAssertEqual(text, found?.text)
  }

  func testInlineShortContentReturnsSingleSyntheticChunkPage() throws {
    let store = makeStore()
    XCTAssertTrue(store.insert(entry("short", conversationId: "conversation", timestampMillis: 1, text: "hello")))

    let page = try XCTUnwrap(store.textChunkPage(entryId: "short", offset: 0, pageSize: 2))

    XCTAssertEqual(["hello"], page.chunks)
    XCTAssertEqual(1, page.totalChunks)
    XCTAssertTrue(page.done)
    XCTAssertEqual(AgentLargeOutputPolicy.digest("hello"), page.sha256)
  }

  private func makeStore() -> UserDefaultsAgentTranscriptEntryStore {
    let suiteName = "AgentTranscriptEntryStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    addTeardownBlock {
      UserDefaultsAgentTranscriptEntryStore.destroyPersistentStore(defaults: defaults, key: "transcript-test")
      defaults.removePersistentDomain(forName: suiteName)
    }
    return UserDefaultsAgentTranscriptEntryStore(defaults: defaults, key: "transcript-test")
  }

  private func entry(
    _ id: String,
    conversationId: String,
    timestampMillis: Int64,
    text: String = "message",
    richOutputJson: String = "",
    dedupeKey: String = ""
  ) -> AgentTranscriptEntry {
    AgentTranscriptEntry(
      id: id,
      role: .assistant,
      text: text,
      timestampMillis: timestampMillis,
      dedupeKey: dedupeKey,
      conversationId: conversationId,
      richOutputJson: richOutputJson
    )
  }
}

private extension Array {
  func single(file: StaticString = #filePath, line: UInt = #line) -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    return self[0]
  }
}
