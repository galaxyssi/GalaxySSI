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

  func testReplaceBatchUpdatesRequestedEntriesAndPreservesUnrelatedEntries() {
    let store = makeStore()
    XCTAssertTrue(store.insert(entry("batch-a", conversationId: "conversation-a", timestampMillis: 1, text: "old")))
    XCTAssertTrue(store.insert(entry("unrelated", conversationId: "conversation-b", timestampMillis: 1, text: "keep")))

    XCTAssertTrue(store.replaceBatch([
      entry("batch-a", conversationId: "conversation-a", timestampMillis: 2, text: "updated"),
      entry("batch-c", conversationId: "conversation-c", timestampMillis: 3, text: "new")
    ]))

    XCTAssertEqual(store.findById("batch-a")?.text, "updated")
    XCTAssertEqual(store.findById("batch-c")?.text, "new")
    XCTAssertEqual(store.findById("unrelated")?.text, "keep")
  }

  func testReplaceBatchRejectsDuplicateIdsWithoutMutatingExistingEntries() {
    let store = makeStore()
    XCTAssertTrue(store.insert(entry("existing", conversationId: "conversation", timestampMillis: 1, text: "keep")))

    XCTAssertFalse(store.replaceBatch([
      entry("duplicate", conversationId: "conversation", timestampMillis: 2),
      entry("duplicate", conversationId: "conversation", timestampMillis: 3)
    ]))

    XCTAssertEqual(store.listConversation("conversation").map(\.id), ["existing"])
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

final class AgentConversationDatabaseTests: XCTestCase {
  func testStoresAndKeysetPagesMoreThanTenThousandEncryptedConversations() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentConversationDatabaseTests-\(UUID().uuidString)", isDirectory: true)
    let file = root.appendingPathComponent("conversations.sqlite")
    defer { try? FileManager.default.removeItem(at: root) }
    let database = AgentConversationDatabase(fileURL: file, secrets: InMemorySecretStore())
    let conversations = (0..<10_025).map { index in
      AgentConversation(
        id: String(format: "conversation-%05d", index),
        title: "private-title-\(index)",
        createdAt: Int64(index),
        updatedAt: Int64(index),
        pinned: index.isMultiple(of: 1_000)
      )
    }

    XCTAssertTrue(database.upsertAll(conversations))
    XCTAssertEqual(10_025, database.count())

    var cursor: AgentConversationPageCursor?
    var ids: [String] = []
    repeat {
      let page = database.page(status: .active, cursor: cursor, pageSize: 137)
      ids += page.items.map(\.id)
      cursor = page.nextCursor
      if !page.hasMore { break }
    } while true

    XCTAssertEqual(10_025, ids.count)
    XCTAssertEqual(10_025, Set(ids).count)
    XCTAssertNil(try Data(contentsOf: file).range(of: Data("private-title-10024".utf8)))
  }

  func testPersistsActiveSelectionAndSupportsArchiveCounts() {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentConversationDatabaseTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let database = AgentConversationDatabase(
      fileURL: root.appendingPathComponent("conversations.sqlite"),
      secrets: InMemorySecretStore()
    )
    let active = AgentConversation(id: "active", title: "Active", createdAt: 1, updatedAt: 2)
    let archived = AgentConversation(
      id: "archived",
      title: "Archived",
      createdAt: 1,
      updatedAt: 1,
      status: .archived
    )

    XCTAssertTrue(database.upsertAll([active, archived]))
    database.setActiveConversationId(active.id)

    XCTAssertEqual(active.id, database.activeConversationId)
    XCTAssertEqual(1, database.count(status: .active))
    XCTAssertEqual(1, database.count(status: .archived))
    XCTAssertEqual(archived, database.read(archived.id))
  }
}

final class SignalASIChatHistoryDatabaseTests: XCTestCase {
  func testEncryptedHistoryPagesWithoutDroppingMessages() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("SignalASIChatHistoryDatabaseTests-\(UUID().uuidString)", isDirectory: true)
    let file = root.appendingPathComponent("history.sqlite")
    defer { try? FileManager.default.removeItem(at: root) }
    let database = SignalASIChatHistoryDatabase(fileURL: file, secrets: InMemorySecretStore())
    let messages = (0..<2_105).map { index in
      ChatMessage(
        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
        contactId: "contact",
        content: "private-message-\(index)",
        isMine: index.isMultiple(of: 2),
        createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
        remoteMessageId: "remote-\(index)"
      )
    }

    XCTAssertTrue(database.upsertAll(messages))
    XCTAssertEqual(messages.count, database.count)
    var cursor: SignalASIChatHistoryCursor?
    var loaded: [ChatMessage] = []
    repeat {
      let page = database.page(contactId: "contact", before: cursor, pageSize: 137)
      loaded += page.messages
      cursor = page.nextCursor
      if !page.hasMore { break }
    } while true

    XCTAssertEqual(messages.count, loaded.count)
    XCTAssertEqual(messages.count, Set(loaded.map(\.id)).count)
    XCTAssertTrue(database.containsIncoming(contactId: "contact", remoteMessageId: "remote-2103"))
    XCTAssertNil(try Data(contentsOf: file).range(of: Data("private-message-2104".utf8)))
  }

  func testConversationQueriesUpdatesDeletesAndUnreadSummary() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("SignalASIChatHistoryDatabaseTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let database = SignalASIChatHistoryDatabase(
      fileURL: root.appendingPathComponent("history.sqlite"),
      secrets: InMemorySecretStore()
    )
    var first = ChatMessage(
      contactId: "contact",
      content: "first",
      isMine: false,
      createdAt: Date(timeIntervalSince1970: 1),
      conversationId: "session"
    )
    let second = ChatMessage(
      contactId: "contact",
      content: "second",
      isMine: true,
      createdAt: Date(timeIntervalSince1970: 2),
      conversationId: "session"
    )
    XCTAssertTrue(database.upsertAll([first, second]))
    first.content = "updated"
    XCTAssertTrue(database.upsert(first))

    XCTAssertEqual(["updated", "second"], database.messages(conversationId: "session").map(\.content))
    XCTAssertEqual(1, database.unreadCount(contactId: "contact", after: .distantPast))
    XCTAssertEqual("second", database.latestMessage(contactId: "contact")?.content)
    XCTAssertEqual(first, database.deleteMessage(id: first.id))
    XCTAssertEqual(1, database.count)
  }
}

private extension Array {
  func single(file: StaticString = #filePath, line: UInt = #line) -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    return self[0]
  }
}
