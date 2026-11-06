import XCTest
@testable import GalaxySSI

final class AgentReplyUnreadTests: XCTestCase {
  private var suite = ""
  private var defaults: UserDefaults!
  private var secrets = InMemorySecretStore()

  override func setUp() {
    super.setUp()
    suite = "AgentReplyUnreadTests-\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)!
    secrets = InMemorySecretStore()
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suite)
    super.tearDown()
  }

  func testStreamingToFinalCreatesOnePersistentUnreadReply() {
    let ledger = makeLedger()
    var stream = reply()
    stream.remoteMessageId = "agent-stream-source"
    stream.deliveryStatus = .sent
    ledger.record(stream, previous: nil)
    XCTAssertEqual(ledger.count(), 0)
    var final = stream
    final.remoteMessageId = "source"
    final.deliveryStatus = .delivered
    ledger.record(final, previous: stream)
    XCTAssertEqual(makeLedger().count(conversationId: "one"), 1)
    var edit = final
    edit.content = "Edited final answer"
    ledger.record(edit, previous: final)
    XCTAssertEqual(ledger.count(), 1)
    ledger.read(conversationId: "one", rendered: [final])
    makeLedger().record(edit, previous: nil)
    XCTAssertEqual(ledger.count(), 0)
  }

  func testCloudSentDeltasAndProcessEntriesAreNotUnread() {
    var message = reply()
    message.deliveryStatus = .sent
    XCTAssertNil(AgentReplyUnreadPolicy.token(message))
    message.deliveryStatus = .delivered
    message.isSystem = true
    XCTAssertNil(AgentReplyUnreadPolicy.token(message))
    message.isSystem = false
    message.isMine = true
    XCTAssertNil(AgentReplyUnreadPolicy.token(message))
    message.isMine = false
    message.remoteMessageId = "remote-approval:task"
    XCTAssertNil(AgentReplyUnreadPolicy.token(message))
    message.remoteMessageId = "source"
    message.contactId = "phone-contact"
    XCTAssertNil(AgentReplyUnreadPolicy.token(message))
  }

  func testOnlyRenderedRepliesInMatchingConversationAreRead() {
    let ledger = makeLedger()
    let first = reply()
    let older = reply(turn: "older")
    let other = reply(conversation: "two")
    [first, older, other].forEach { ledger.record($0, previous: nil) }
    ledger.read(conversationId: "one", rendered: [first, other])
    XCTAssertEqual(ledger.count(conversationId: "one"), 1)
    XCTAssertEqual(ledger.count(conversationId: "two"), 1)
  }

  func testLatestPageClearsOffscreenRepliesWithoutClearingNewerOrForeignReplies() throws {
    let ledger = makeLedger()
    var boundaryRow = reply(turn: "process")
    boundaryRow.isSystem = true
    boundaryRow.createdAt = Date(timeIntervalSince1970: 2_000)
    boundaryRow.id = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    for index in 0..<110 {
      var old = reply(turn: "old-\(index)")
      old.createdAt = Date(timeIntervalSince1970: Double(index))
      ledger.record(old, previous: nil)
    }
    var beforeTie = reply(turn: "same-time-before")
    beforeTie.createdAt = boundaryRow.createdAt
    beforeTie.id = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    var afterTie = reply(turn: "same-time-after")
    afterTie.createdAt = boundaryRow.createdAt
    afterTie.id = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
    let foreign = reply(conversation: "two")
    [beforeTie, afterTie, foreign].forEach { ledger.record($0, previous: nil) }
    let rendered = [boundaryRow, foreign]
    XCTAssertNil(AgentReplyUnreadPolicy.boundary(conversationId: "one", rendered: rendered, isAtLatest: false))
    let boundary = try XCTUnwrap(AgentReplyUnreadPolicy.boundary(
      conversationId: "one", rendered: rendered, isAtLatest: true
    ))
    makeLedger().read(conversationId: boundary.conversationId, rendered: rendered, through: boundary.cursor)
    XCTAssertEqual(ledger.count(conversationId: "one"), 1)
    XCTAssertEqual(ledger.count(conversationId: "two"), 1)
    ledger.read(conversationId: "one", rendered: [afterTie])
    XCTAssertEqual(ledger.count(conversationId: "one"), 0)
  }

  @MainActor
  func testLegacyUnreadIsReadThroughIndexedPagesWithoutClearingNewerLegacyMarkers() async throws {
    let store = GalaxySSIStore(defaults: defaults, secrets: secrets)
    let session = store.createAgentSession(title: "Legacy unread")
    let old = store.appendIncoming(
      "Offscreen", from: "hermes", status: .delivered, conversationId: session.id, turnId: "old"
    )
    for index in 1...49 {
      var filler = reply(conversation: session.id, turn: "filler-\(index)")
      filler.isSystem = true
      filler.createdAt = old.createdAt.addingTimeInterval(Double(index))
      XCTAssertTrue(store.chatHistoryDatabase.upsert(filler))
    }
    var newest = reply(conversation: session.id, turn: "newer")
    newest.createdAt = old.createdAt.addingTimeInterval(60)
    XCTAssertTrue(store.chatHistoryDatabase.upsert(newest))
    let legacy = ["seen": [session.id: ["old", "newer"]], "pending": [session.id: ["old", "newer"]],
                  "contactReadAt": [String: [String]]()]
    XCTAssertTrue(GalaxySSIEncryptedUserDefaultsStore.write(
      try JSONEncoder().encode(legacy), defaults: defaults, key: AgentReplyUnreadStore.key, secrets: secrets
    ))
    var boundaryRow = newest
    boundaryRow.createdAt = old.createdAt.addingTimeInterval(55)
    let boundary = AgentReplyUnreadPolicy.Boundary(
      conversationId: session.id, cursor: GalaxySSIChatHistoryCursor(boundaryRow)
    )
    await store.markLegacyAgentRepliesRead(through: boundary)
    XCTAssertEqual(store.agentReplyUnreadCount(conversationId: session.id), 1)
    store.markAgentRepliesRead(conversationId: session.id, rendered: [newest])
    XCTAssertEqual(store.agentReplyUnreadCount(conversationId: session.id), 0)
  }

  func testDuplicateReplyWithDifferentLocalIDDoesNotReopenUnread() {
    let ledger = makeLedger()
    let first = reply()
    ledger.record(first, previous: nil)
    ledger.read(conversationId: "one", rendered: [first])
    ledger.record(reply(), previous: nil)
    XCTAssertEqual(ledger.count(), 0)
    ledger.record(reply(conversation: "two"), previous: nil)
    XCTAssertEqual(ledger.count(), 1)
  }

  func testEditingPreexistingFinalDoesNotCreateUnread() {
    let final = reply()
    var edited = final
    edited.content = "Corrected answer"
    let ledger = makeLedger()
    ledger.record(edited, previous: final)
    XCTAssertEqual(ledger.count(), 0)
  }

  func testIndependentWindowsShareReadAndRecordState() {
    let left = makeLedger()
    let right = makeLedger()
    let first = reply()
    let second = reply(conversation: "two")
    left.record(first, previous: nil)
    right.record(second, previous: nil)
    left.read(conversationId: "one", rendered: [first])
    XCTAssertEqual(right.count(), 1)
    right.removeConversations(["two"])
    XCTAssertEqual(left.count(), 0)
  }

  func testContactReadWatermarkIsSharedAndCannotMoveBackwards() {
    let left = makeLedger()
    let right = makeLedger()
    left.markContactRead("contact-a", at: Date(timeIntervalSince1970: 200))
    right.markContactRead("contact-a", at: Date(timeIntervalSince1970: 100))
    XCTAssertEqual(left.contactReadAt("contact-a"), Date(timeIntervalSince1970: 200))
    XCTAssertEqual(right.contactReadAt("contact-b"), .distantPast)
  }

  func testDeletionAndResetClearUnreadWithoutReopeningEditedReply() {
    let ledger = makeLedger()
    let first = reply()
    ledger.record(first, previous: nil)
    ledger.remove(first)
    ledger.record(first, previous: nil)
    XCTAssertEqual(ledger.count(), 0)
    ledger.record(reply(conversation: "two"), previous: nil)
    ledger.clear()
    XCTAssertEqual(makeLedger().count(), 0)
  }

  func testBackgroundHiddenAndUnfocusedWindowsCannotMarkRead() {
    for visible in [false, true] {
      for active in [false, true] {
        for focused in [false, true] {
          XCTAssertEqual(AgentReplyUnreadPolicy.canRead(visible: visible, active: active, focused: focused),
                         visible && active && focused)
        }
      }
    }
  }

  func testUnreadIdentifiersAreEncrypted() throws {
    let message = reply()
    makeLedger().record(message, previous: nil)
    XCTAssertNil(defaults.data(forKey: AgentReplyUnreadStore.key))
    let disk = try XCTUnwrap(defaults.data(forKey: AgentReplyUnreadStore.key + ".encrypted.v1"))
    XCTAssertNil(disk.range(of: Data(message.turnId.utf8)))
    XCTAssertNil(disk.range(of: Data(message.content.utf8)))
  }

  @MainActor
  func testMessagePersistenceRecordsFinalAndDeletesConversationUnread() {
    let store = GalaxySSIStore(defaults: defaults, secrets: secrets)
    let session = store.createAgentSession(title: "Unread test")
    let stream = store.appendIncoming(
      "Partial", from: "hermes", remoteMessageId: "agent-stream-source", status: .sent,
      conversationId: session.id, turnId: "turn-1"
    )
    XCTAssertEqual(store.agentReplyUnreadCount(), 0)
    _ = store.updateMessageContent(stream.id, contactId: "hermes", content: "Final",
                                   status: .delivered, remoteMessageId: "source")
    XCTAssertEqual(store.agentReplyUnreadCount(conversationId: session.id), 1)
    XCTAssertTrue(store.deleteAgentSession(id: session.id))
    XCTAssertEqual(store.agentReplyUnreadCount(), 0)
  }

  private func makeLedger() -> AgentReplyUnreadStore {
    AgentReplyUnreadStore(defaults: defaults, secrets: secrets)
  }

  private func reply(conversation: String = "one", turn: String = "stable-reply-token") -> ChatMessage {
    ChatMessage(contactId: "hermes", content: "Final answer", isMine: false,
                deliveryStatus: .delivered, conversationId: conversation, turnId: turn)
  }
}
