import SQLite3
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

  func testUnreadIndexUsesTokenPrecedenceAndKeepsLegacyRowsUntilIndexed() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("unread.sqlite")
    let history = GalaxySSIChatHistoryDatabase(fileURL: file, secrets: secrets)
    var first = reply(turn: "turn-wins")
    first.remoteMessageId = "remote-ignored"
    var second = reply(turn: "")
    second.remoteMessageId = "remote-wins"
    let third = reply(turn: "")
    var streaming = reply(turn: "stream-ignored")
    streaming.deliveryStatus = .sent
    let other = reply(conversation: "two", turn: "other-conversation")
    for message in [first, second, third, streaming, other] { XCTAssertTrue(history.upsert(message)) }
    let missing: Set<String> = ["remote-ignored", "stream-ignored", first.id.uuidString, "other-conversation"]
    let all = missing.union(["turn-wins", "remote-wins", third.id.uuidString])
    XCTAssertEqual(history.missingUnreadTokens(conversationId: "one", candidates: all), missing)

    var raw: OpaquePointer?
    XCTAssertEqual(sqlite3_open_v2(file.path, &raw, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
    defer { sqlite3_close_v2(raw) }
    XCTAssertEqual(sqlite3_exec(raw, "UPDATE chat_messages SET agent_unread_key = NULL WHERE conversation_id = 'one'",
      nil, nil, nil), SQLITE_OK)
    XCTAssertNil(history.missingUnreadTokens(conversationId: "one", candidates: all))
    history.prepareLegacyUnreadIndex(conversationId: "one")
    XCTAssertEqual(history.missingUnreadTokens(conversationId: "one", candidates: all), missing)
  }

  func testUnreadDiscardUsesSnapshotWithoutClearingNewOrRecreatedMarkers() {
    let ledger = makeLedger()
    let old = reply(turn: "old")
    ledger.record(old, previous: nil)
    let checked = ledger.pendingSnapshot()
    ledger.removeConversations(["one"])
    var recreated = reply(turn: "old")
    recreated.createdAt = old.createdAt.addingTimeInterval(1)
    ledger.record(recreated, previous: nil)
    ledger.record(reply(turn: "new-arrival"), previous: nil)
    ledger.discardMissing(checked)
    XCTAssertEqual(ledger.count(conversationId: "one"), 2)
  }

  @MainActor
  func testReconciliationAndSingleDeletePreserveOtherUnreadReplies() async {
    let store = GalaxySSIStore(defaults: defaults, secrets: secrets)
    let session = store.createAgentSession(title: "Unread")
    let removed = store.appendIncoming("First", from: "hermes", conversationId: session.id, turnId: "first")
    _ = store.appendIncoming("Second", from: "hermes", conversationId: session.id, turnId: "second")
    let orphan = reply(conversation: session.id, turn: "orphan")
    makeLedger().record(orphan, previous: nil)
    XCTAssertEqual(store.agentReplyUnreadCount(conversationId: session.id), 3)
    await store.reconcileAgentReplyUnread()
    XCTAssertEqual(store.agentReplyUnreadCount(conversationId: session.id), 2)
    XCTAssertTrue(store.deleteMessage(removed.id, contactId: "hermes"))
    XCTAssertEqual(store.agentReplyUnreadCount(conversationId: session.id), 1)
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

  @MainActor
  func testQuietScheduleCompletionClearsPersistedUnreadOnlyInItsDestination() async throws {
    let store = GalaxySSIStore(defaults: defaults, secrets: secrets)
    let owner = store.createAgentSession(title: "Scheduled")
    let other = store.createAgentSession(title: "Other")
    let start: Int64 = 1_000_000
    _ = try store.saveConversationSchedule(conversationId: owner.id, id: nil, prompt: "Check the phone",
      trigger: AgentProactiveTrigger(kind: .interval, intervalSeconds: 60), frequency: "Every minute", nowMillis: start)
    XCTAssertEqual(store.claimDueAutomationTasks(nowMillis: start), 1)
    let run = try XCTUnwrap(store.queuedAutomationRuns().first)
    XCTAssertNotNil(store.beginAutomationRun(id: run.runId, nowMillis: start))
    let quiet = store.appendIncoming("The phone observation could not be verified.", from: "hermes",
      conversationId: owner.id, turnId: run.runId)
    _ = store.appendIncoming("Visible reply", from: "hermes", conversationId: other.id, turnId: run.runId)
    _ = store.appendIncoming("Other turn", from: "hermes", conversationId: owner.id, turnId: "ordinary")
    XCTAssertEqual(store.agentReplyUnreadCount(conversationId: owner.id), 2)
    XCTAssertTrue(store.finishAutomationRun(id: run.runId, status: .unverified, resultSummary: "Unverified",
      errorCode: "phone_observation_unverified", nowMillis: start + 1))
    XCTAssertEqual(store.agentReplyUnreadCount(conversationId: owner.id), 1)
    XCTAssertEqual(store.agentReplyUnreadCount(conversationId: other.id), 1)
    XCTAssertEqual(store.persistedMessage(id: quiet.id, contactId: "hermes")?.turnId, run.runId)
    _ = store.appendIncoming("Late quiet result", from: "hermes", conversationId: owner.id, turnId: run.runId)
    XCTAssertEqual(store.agentReplyUnreadCount(conversationId: owner.id), 1)

    // Simulate an upgrade with an older persisted marker for the quiet reply.
    let legacy = makeLedger()
    legacy.removeConversations([owner.id])
    legacy.record(quiet, previous: nil)
    await store.reconcileAgentReplyUnread()
    XCTAssertEqual(store.agentReplyUnreadCount(conversationId: owner.id), 0)
    XCTAssertEqual(store.agentReplyUnreadCount(conversationId: other.id), 1)
  }

  @MainActor
  func testQuietRepeatCannotDiscardARichReplySharingItsTurn() throws {
    let store = GalaxySSIStore(defaults: defaults, secrets: secrets)
    let session = store.createAgentSession(title: "Scheduled")
    let task = try store.saveConversationSchedule(conversationId: session.id, id: nil, prompt: "Check weather",
      trigger: AgentProactiveTrigger(kind: .interval, intervalSeconds: 60), frequency: "Every minute", nowMillis: 1_000)
    let first = try AgentProactiveRun(runId: "first", taskId: task.taskId, scheduledForMillis: 1_000,
      status: .completed, resultSummary: "Same result")
    let repeatRun = try AgentProactiveRun(runId: "repeat", taskId: task.taskId, scheduledForMillis: 61_000,
      status: .completed, resultSummary: "Same result")
    let visibility = AgentScheduledReplyVisibility(tasks: [task], runs: [repeatRun, first])
    let plain = reply(conversation: session.id, turn: repeatRun.runId)
    var rich = reply(conversation: session.id, turn: repeatRun.runId)
    rich.richOutputJson = "[]"
    XCTAssertTrue(visibility.hides(plain))
    XCTAssertFalse(visibility.hides(rich))
    let history = store.chatHistoryDatabase
    XCTAssertTrue(history.upsert(plain))
    XCTAssertEqual(history.quietScheduledUnreadTokens(conversationId: session.id,
      candidates: [repeatRun.runId], visibility: visibility), [repeatRun.runId])
    XCTAssertTrue(history.upsert(rich))
    XCTAssertTrue(history.quietScheduledUnreadTokens(conversationId: session.id,
      candidates: [repeatRun.runId], visibility: visibility).isEmpty)
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
