import Foundation
import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthCareLegacyReplyTests: XCTestCase {
  typealias Policy = GalaxySSIHealthCareLegacyReplyPresentation
  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  func testMarkerPreservesIdentityAndStopsAtOriginalReceiptWithoutChangingInputs() throws {
    let (session, source, reply) = fixture()
    let beforeSource = source
    let beforeReply = reply
    let marker = try XCTUnwrap(project(reply, source, session))
    XCTAssertEqual(marker.id, reply.id)
    XCTAssertEqual(marker.turn, source.id)
    XCTAssertEqual(marker.source, source.id)
    XCTAssertEqual(marker.seconds, 16)
    XCTAssertEqual(source, beforeSource)
    XCTAssertEqual(reply, beforeReply)
    XCTAssertEqual(marker, project(reply, source, session, now: start.addingTimeInterval(1_000)))
  }

  func testInvalidOrNonprivateHealthSessionIsNotARecoveryCandidate() {
    let (session, source, reply) = fixture()
    var changed = session
    changed.privateMode = false
    XCTAssertNil(project(reply, source, changed))
    changed = session
    changed.trackingPaused = false
    XCTAssertNil(project(reply, source, changed))
    changed = session
    changed.globalTopicKey = GalaxySSIHealthCareAgentScope.prefix + "malformed"
    XCTAssertNil(project(reply, source, changed))
  }

  func testForeignSourceConversationAndMergedCopiesCannotSupplyLegacyMarkers() {
    let (session, source, reply) = fixture()
    var changed = reply
    changed.turnId = UUID().uuidString
    XCTAssertNil(project(changed, source, session))
    changed = reply
    changed.conversationId = "foreign"
    XCTAssertNil(project(changed, source, session))
    changed = reply
    changed.sourceConversationId = "merged-source"
    XCTAssertNil(project(changed, source, session))
    changed = reply
    changed.contactId = "other-agent"
    XCTAssertNil(project(changed, source, session))
  }

  func testPartialOrUncommittedReplyCannotBeCalledAnInterruption() {
    let (session, source, reply) = fixture()
    for status in [ChatDeliveryStatus.sent, .queued, .failed, .local] {
      var changed = reply
      changed.deliveryStatus = status
      XCTAssertNil(project(changed, source, session))
    }
    var changed = reply
    changed.deliveryTrace = [.init(stage: "connector_interim", createdAt: start.addingTimeInterval(16))]
    XCTAssertNil(project(changed, source, session))
    changed = reply
    changed.remoteMessageId = "agent-stream-" + source.id.uuidString
    XCTAssertNil(project(changed, source, session))
  }

  func testRecoveryContextDomainTurnOrNormalAnswerPreventsLegacyClassification() {
    let (session, source, reply) = fixture()
    XCTAssertNil(Policy.marker(receipt: reply, original: source, conversation: session, hasRecovery: true,
      domainTurns: [], hasAnswer: false, now: start.addingTimeInterval(60)))
    XCTAssertNil(Policy.marker(receipt: reply, original: source, conversation: session, hasRecovery: false,
      domainTurns: [source.id], hasAnswer: false, now: start.addingTimeInterval(60)))
    XCTAssertNil(Policy.marker(receipt: reply, original: source, conversation: session, hasRecovery: false,
      domainTurns: [], hasAnswer: true, now: start.addingTimeInterval(60)))
  }

  func testFinalStreamUsesPersistedFinalTraceInsteadOfStreamStart() throws {
    let (session, source, reply) = fixture()
    var final = reply
    final.remoteMessageId = "agent-stream-" + source.id.uuidString
    final.createdAt = start.addingTimeInterval(2)
    final.deliveryTrace = [.init(stage: "agent_reply_received", createdAt: start.addingTimeInterval(25))]
    XCTAssertEqual(try XCTUnwrap(project(final, source, session)).seconds, 25)
    final.deliveryTrace = [.init(stage: "agent_reply_received", createdAt: start.addingTimeInterval(200))]
    XCTAssertNil(project(final, source, session))
  }

  func testOrdinaryProseAndUnboundOrOversizedControlDataAreNotCandidates() {
    let (session, source, reply) = fixture()
    var changed = reply
    changed.content = "A synthetic ordinary answer"
    XCTAssertNil(project(changed, source, session))
    changed = reply
    changed.remoteMessageId = ""
    XCTAssertNil(project(changed, source, session))
    changed = reply
    changed.content = String(repeating: "a", count: 128_001)
    XCTAssertNil(project(changed, source, session))
    changed = reply
    changed.createdAt = start.addingTimeInterval(-1)
    XCTAssertNil(project(changed, source, session))
  }

  func testRichControlIsClassifiedButNeverCopiedIntoMarker() throws {
    let (session, source, reply) = fixture()
    var changed = reply
    changed.content = ""
    changed.richOutputJson = #"{"execution_location":"phone","actions":[]}"#
    let marker = try XCTUnwrap(project(changed, source, session))
    XCTAssertEqual(marker.seconds, 16)
    XCTAssertEqual(changed.richOutputJson, reply.content)
  }

  func testStrictWindowReopensOriginalEncryptedRowsAndIncludesLaterAnswers() throws {
    let (session, source, reply) = fixture()
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
    defer { try? FileManager.default.removeItem(at: file) }
    let secrets = InMemorySecretStore()
    let database = GalaxySSIChatHistoryDatabase(fileURL: file, secrets: secrets)
    XCTAssertTrue(database.upsert(source))
    XCTAssertTrue(database.upsert(reply))
    let answer = ChatMessage(contactId: "hermes", content: "Synthetic final answer", isMine: false,
      createdAt: start.addingTimeInterval(30), deliveryStatus: .delivered, conversationId: session.id,
      turnId: source.id.uuidString, remoteMessageId: "later-answer")
    XCTAssertTrue(database.upsert(answer))
    let reopened = GalaxySSIChatHistoryDatabase(fileURL: file, secrets: secrets)
    let window = try reopened.verifiedHealthLegacyWindow(conversationId: session.id)
    XCTAssertEqual(window, [answer, reply, source])
    XCTAssertEqual(reopened.message(id: reply.id), reply)
    XCTAssertTrue(window.contains { !$0.isMine && !Policy.isControl($0) })
    XCTAssertTrue(try reopened.verifiedHealthLegacyWindow(conversationId: "different-conversation").isEmpty)
  }

  func testStrictWindowIsBoundedAndCannotImplyAnOmittedOriginalWasVerified() throws {
    let (session, source, _) = fixture()
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
    defer { try? FileManager.default.removeItem(at: file) }
    let database = GalaxySSIChatHistoryDatabase(fileURL: file, secrets: InMemorySecretStore())
    XCTAssertTrue(database.upsert(source))
    for index in 1...501 {
      XCTAssertTrue(database.upsert(ChatMessage(contactId: "hermes", content: "Synthetic window fixture", isMine: true,
        createdAt: start.addingTimeInterval(Double(index)), conversationId: session.id)))
    }
    let window = try database.verifiedHealthLegacyWindow(conversationId: session.id)
    XCTAssertEqual(window.count, 500)
    XCTAssertFalse(window.contains { $0.id == source.id })
  }

  private func fixture() -> (AgentConversation, ChatMessage, ChatMessage) {
    let session = AgentConversation(id: "health-legacy-agent", title: "Fixture", createdAt: 0, updatedAt: 0,
      privateMode: true, trackingPaused: true,
      globalTopicKey: GalaxySSIHealthCareAgentScope.prefix + UUID().uuidString.lowercased())
    let id = UUID()
    let source = ChatMessage(id: id, contactId: "hermes", content: "Synthetic original health question", isMine: true,
      createdAt: start, deliveryStatus: .delivered, conversationId: session.id, turnId: id.uuidString)
    let reply = ChatMessage(contactId: "hermes", content: #"{"execution_location":"phone","actions":[]}"#, isMine: false,
      createdAt: start.addingTimeInterval(16), deliveryStatus: .delivered,
      conversationId: session.id, turnId: id.uuidString, remoteMessageId: "synthetic-reply")
    return (session, source, reply)
  }

  private func project(_ reply: ChatMessage, _ source: ChatMessage, _ session: AgentConversation,
      now: Date? = nil) -> Policy.Marker? {
    Policy.marker(receipt: reply, original: source, conversation: session, hasRecovery: false,
      domainTurns: [], hasAnswer: false, now: now ?? start.addingTimeInterval(60))
  }
}
