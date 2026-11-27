import XCTest
@testable import GalaxySSI

final class GalaxySSILocalMessageSearchTests: XCTestCase {
  typealias Search = GalaxySSILocalMessageSearch
  let source = Search.Source(kind: .agent, id: "ordinary", title: "Fixture", archived: false)

  func testQueryBoundUsesUTF16AndRejectsBlankInput() {
    XCTAssertEqual(Search.query("  needle\n"), "needle")
    XCTAssertNil(Search.query(" \n"))
    XCTAssertNotNil(Search.query(String(repeating: "x", count: 256)))
    XCTAssertNil(Search.query(String(repeating: "x", count: 257)))
    XCTAssertNotNil(Search.query(String(repeating: "\u{1F680}", count: 128)))
    XCTAssertNil(Search.query(String(repeating: "\u{1F680}", count: 129)))
  }
  func testLiteralCaseInsensitiveExcerptIsBoundedAndHandlesUnicode() {
    let body = String(repeating: "prefix ", count: 20) + "NeEdLe\n" + String(repeating: "tail ", count: 20)
    let result = Search.excerpt(body, query: "needle")
    XCTAssertTrue(result?.contains("NeEdLe") == true)
    XCTAssertFalse(result?.contains("\n") == true)
    XCTAssertLessThan(result?.count ?? 0, 90)
    XCTAssertNotNil(Search.excerpt("a.*b", query: ".*"))
    XCTAssertNil(Search.excerpt("anything", query: ""))
    XCTAssertNotNil(Search.excerpt("\u{1F680}Needle\u{1F680}", query: "needle"))
  }
  func testFilenameSearchDoesNotSearchAttachmentURIsOrMetadata() throws {
    var row = message("No matching body")
    row.richOutputJson = AgentRichContentCodec.encode([.init(id: "file", type: .file,
      title: "budget-needle.pdf", uri: "https://metadata-only.example/hidden")])
    XCTAssertTrue(try XCTUnwrap(Search.hit(row, source: source, owner: "owner", query: "needle")).filename)
    XCTAssertNil(Search.hit(row, source: source, owner: "owner", query: "metadata-only"))
    row.content = "needle in the message"
    XCTAssertFalse(try XCTUnwrap(Search.hit(row, source: source, owner: "owner", query: "needle")).filename)
  }
  func testPrivatePausedTopicBoundAndMergedConversationsAreExcluded() {
    let original = conversation("ordinary")
    XCTAssertTrue(Search.ordinary(original))
    var privateRow = original; privateRow.privateMode = true
    var paused = original; paused.trackingPaused = true
    var health = original; health.globalTopicKey = "health-care:fixture"
    var merged = original; merged.mergedIntoConversationId = "target"
    for row in [privateRow, paused, health, merged] { XCTAssertFalse(Search.ordinary(row)) }
  }
  func testProcessPreviewAndMergedSourceRowsCannotProduceHitsOrReaderLines() {
    var system = message("needle"); system.isSystem = true
    var merged = message("needle"); merged.sourceConversationId = "private-source"
    var preview = message("needle"); preview.remoteMessageId = "agent-stream-preview-1"
    var foreign = message("needle"); foreign.conversationId = "different"
    for row in [system, merged, preview, foreign] {
      XCTAssertNil(Search.hit(row, source: source, owner: "owner", query: "needle"))
      XCTAssertNil(Search.line(row, source: source))
    }
  }
  func testScannerPassesConversationAndMessagePageBoundariesAndFindsDeepBody() async throws {
    let f = Fixture()
    for index in 0..<70 { XCTAssertTrue(f.conversations.upsert(conversation("session-\(index)", time: Int64(index)))) }
    for index in 0..<100 {
      var row = message(index == 5 ? String(repeating: "x", count: 131_070) + "needle" : "ordinary text", time: Double(index))
      row.conversationId = "session-0"
      XCTAssertTrue(f.messages.upsert(row))
    }
    let batch = try await f.scanner(query: "needle").next(limit: 24)
    XCTAssertEqual(batch.hits.count, 1)
    XCTAssertEqual(batch.hits.first?.source.id, "session-0")
    XCTAssertTrue(batch.hits.first?.snippet.contains("needle") == true)
    XCTAssertFalse(batch.more)
  }
  func testArchivedSearchDoesNotRestoreTheConversationOrCrossStatus() async throws {
    let f = Fixture()
    var archived = conversation("ordinary"); archived.status = .archived
    XCTAssertTrue(f.conversations.upsert(archived))
    XCTAssertTrue(f.messages.upsert(message("needle")))
    let active = try await f.scanner(query: "needle").next(limit: 24)
    let saved = try await f.scanner(query: "needle", archived: true).next(limit: 24)
    XCTAssertTrue(active.hits.isEmpty)
    XCTAssertEqual(saved.hits.count, 1)
    XCTAssertEqual(f.conversations.read("ordinary")?.status, .archived)
  }
  func testContextReturnsExactOriginalAndBothNeighborsWithoutChangingStorage() throws {
    let f = Fixture()
    XCTAssertTrue(f.conversations.upsert(conversation("ordinary")))
    var target: ChatMessage?
    for index in 0..<60 {
      let row = message(index == 30 ? "needle original" : "neighbor \(index)", time: Double(index))
      XCTAssertTrue(f.messages.upsert(row)); if index == 30 { target = row }
    }
    let exact = try XCTUnwrap(target)
    let hit = try XCTUnwrap(Search.hit(exact, source: source, owner: "owner", query: "needle"))
    let before = f.conversations.read("ordinary")
    let page = try GalaxySSILocalMessageSearchScanner.context(hit, query: "needle", conversations: f.conversations, messages: f.messages)
    XCTAssertEqual(page.lines.count, 25)
    XCTAssertEqual(page.lines[12].id, target?.id)
    XCTAssertEqual(page.lines[12].text, "needle original")
    XCTAssertNotNil(page.older); XCTAssertNotNil(page.newer)
    XCTAssertEqual(f.conversations.read("ordinary"), before)
    let older = try GalaxySSILocalMessageSearchScanner.context(hit, query: "needle", conversations: f.conversations,
      messages: f.messages, older: page.older)
    XCTAssertTrue(Set(older.lines.map(\.id)).isDisjoint(with: Set(page.lines.map(\.id))))
  }
  func testContextRechecksRevocationAndWrongMessageOwnership() throws {
    let f = Fixture()
    var session = conversation("ordinary")
    XCTAssertTrue(f.conversations.upsert(session))
    let row = message("needle"); XCTAssertTrue(f.messages.upsert(row))
    let hit = try XCTUnwrap(Search.hit(row, source: source, owner: "owner", query: "needle"))
    session.privateMode = true; XCTAssertTrue(f.conversations.upsert(session))
    XCTAssertThrowsError(try GalaxySSILocalMessageSearchScanner.context(hit, query: "needle", conversations: f.conversations, messages: f.messages))
    f.messages.setRowCachingEnabled(false)
    XCTAssertThrowsError(try f.messages.localSearchPage(contactId: nil, conversationId: "ordinary"))
  }
  func testCancelledScanDoesNotReturnAnyPlaintextBatch() async throws {
    let f = Fixture()
    let scanner = f.scanner(query: "needle")
    let work = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await scanner.next(limit: 24)
    }
    do { _ = try await work.value; XCTFail("Cancelled read returned a batch") } catch is CancellationError {} catch { XCTFail("Unexpected failure") }
  }
  func testEncryptedRowsDoNotCreateAPlaintextSearchIndex() throws {
    let f = Fixture()
    XCTAssertTrue(f.conversations.upsert(conversation("ordinary")))
    let marker = "synthetic-secret-search-marker-948213"
    XCTAssertTrue(f.messages.upsert(message(marker)))
    _ = try f.messages.localSearchPage(contactId: nil, conversationId: "ordinary")
    XCTAssertFalse(String(decoding: try Data(contentsOf: f.messageFile), as: UTF8.self).contains(marker))
    let names = try FileManager.default.contentsOfDirectory(atPath: f.directory.path)
    XCTAssertFalse(names.contains { $0.contains("search") || $0.contains("index") })
  }
  func testDirectPeerHistoryUsesItsOwnContactAndExcludesAgentAndDeletedContacts() async throws {
    let f = Fixture()
    var contact = GalaxySSIContact.hermes()
    XCTAssertNil(Search.peer(contact, archived: false))
    contact.id = "peer-fixture"; contact.type = "person"; contact.deleted = false
    let peer = try XCTUnwrap(Search.peer(contact, archived: false))
    var row = message("needle in peer history"); row.contactId = contact.id; row.conversationId = "peer-route"
    XCTAssertTrue(f.messages.upsert(row))
    let scanner = GalaxySSILocalMessageSearchScanner(owner: "owner", query: "needle", archived: false,
      peers: [peer], conversations: f.conversations, messages: f.messages)
    let batch = try await scanner.next(limit: 24)
    XCTAssertEqual(batch.hits.first?.source.kind, .peer)
    XCTAssertEqual(batch.hits.first?.message, row.id)
    contact.deleted = true
    XCTAssertNil(Search.peer(contact, archived: false))
  }

  private func conversation(_ id: String, time: Int64 = 1) -> AgentConversation {
    .init(id: id, title: "Fixture", createdAt: time, updatedAt: time, latestDialogueAt: time)
  }
  private func message(_ body: String, time: TimeInterval = 1) -> ChatMessage {
    .init(contactId: "fixture", content: body, isMine: false, createdAt: Date(timeIntervalSince1970: time),
      deliveryStatus: .delivered, conversationId: "ordinary", turnId: UUID().uuidString)
  }
  private final class Fixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let conversations: AgentConversationDatabase
    let messages: GalaxySSIChatHistoryDatabase
    let messageFile: URL
    init() {
      let secrets = InMemorySecretStore()
      messageFile = directory.appendingPathComponent("messages.sqlite")
      conversations = .init(fileURL: directory.appendingPathComponent("sessions.sqlite"), secrets: secrets)
      messages = .init(fileURL: messageFile, secrets: secrets)
    }
    func scanner(query: String, archived: Bool = false) -> GalaxySSILocalMessageSearchScanner {
      .init(owner: "owner", query: query, archived: archived, peers: [], conversations: conversations, messages: messages)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
  }
}
