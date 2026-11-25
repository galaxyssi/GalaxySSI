import Foundation
import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthCareDiscussionRecoveryTests: XCTestCase {
  func testExactApprovalAndFinalReceiptSurviveReopenBeforeLocalApplication() throws {
    let f = try HealthDiscussionRecoveryFixture()
    let initial = try XCTUnwrap(f.turn().execution)
    XCTAssertEqual(initial.state, .prepared)
    XCTAssertEqual(initial.approval, f.approval)
    XCTAssertEqual(initial.approval.credentialDigest?.count, 32)
    XCTAssertEqual(initial.startedAt, f.now)
    XCTAssertNil(initial.response)
    XCTAssertFalse(String(decoding: try JSONEncoder().encode(initial), as: UTF8.self).contains("fixture-api-key"))
    try f.records.dispatchLocalCareDiscussionTurn(f.approval, now: f.now)
    XCTAssertThrowsError(try f.records.dispatchLocalCareDiscussionTurn(f.approval, now: f.now))
    let reply = try f.response("Retained synthetic final answer")
    try f.records.retainLocalCareDiscussionResponse(f.approval, response: reply, now: f.now)
    try f.records.retainLocalCareDiscussionResponse(f.approval, response: reply, now: f.now)
    XCTAssertThrowsError(try f.records.retainLocalCareDiscussionResponse(f.approval,
      response: f.response("Conflicting answer"), now: f.now))
    XCTAssertNil(try f.turn().answer)
    XCTAssertNil(try Data(contentsOf: f.file).range(of: reply))
    let reopened = GalaxySSIHealthRecords(owner: f.records.owner, secrets: f.secrets, isolatedFile: f.file)
    let saved = try XCTUnwrap(reopened.load().localCareDiscussions?[f.concern.id.uuidString]?.turns.last?.execution)
    XCTAssertEqual(saved.approval, f.approval)
    XCTAssertEqual(saved.response, reply)
    try reopened.applySavedLocalCareDiscussionReply(saved.approval, now: f.now)
    let turn = try XCTUnwrap(reopened.load().localCareDiscussions?[f.concern.id.uuidString]?.turns.last)
    XCTAssertEqual(turn.id, f.approval.id)
    XCTAssertEqual(turn.answer, "Retained synthetic final answer")
    XCTAssertEqual(turn.execution?.state, .applied)
    XCTAssertEqual(turn.execution?.response, reply)
    XCTAssertThrowsError(try reopened.applySavedLocalCareDiscussionReply(saved.approval, now: f.now))
    XCTAssertEqual(try reopened.load().localCareDiscussions?[f.concern.id.uuidString]?.turns.last, turn)
  }

  func testSerializedHistoryAndQuestionCursorsRetainExactOpaqueTokensAndScope() throws {
    let f = try HealthDiscussionRecoveryFixture(history: true)
    var review = f.approval
    XCTAssertNotNil(review.history?.recent.cursor)
    let page = GalaxySSIHealthCareQuestions.Page(rows: [], basis: "synthetic-basis", ledgerVersion: "version-1",
      known: [:], next: UUID())
    review.questions = page
    review.questionCursor = .init(page, remaining: 4)
    review.feedbackHistoryAllowed = true
    var related = try XCTUnwrap(review.history)
    related.entryToken = UUID().uuidString
    review.relatedHistory = ["glucose": related]
    let restored = try JSONDecoder().decode(GalaxySSIHealthCareDiscussion.Approval.self,
      from: JSONEncoder().encode(review))
    XCTAssertEqual(restored, review)
    XCTAssertEqual(restored.questionCursor?.arguments(turn: review.id), review.questionCursor?.arguments(turn: review.id))
    XCTAssertEqual(restored.history?.recent, review.history?.recent)
    XCTAssertEqual(restored.relatedHistory["glucose"]?.entryToken, related.entryToken)
    XCTAssertEqual(restored.feedbackCursor?.arguments, review.feedbackCursor?.arguments)
    XCTAssertEqual(restored.computedDestinationDigest, review.destinationDigest)
    XCTAssertEqual(try restored.providerPayload(now: f.now), try review.providerPayload(now: f.now))
  }

  func testCancellationPreservesReceiptButPreventsItsApplicationOrRedispatch() throws {
    let f = try HealthDiscussionRecoveryFixture()
    try f.records.dispatchLocalCareDiscussionTurn(f.approval, now: f.now)
    let response = try f.response("Do not apply a cancelled reply")
    try f.records.retainLocalCareDiscussionResponse(f.approval, response: response, now: f.now)
    try f.records.interruptLocalCareDiscussionExecution(f.approval)
    try f.records.interruptLocalCareDiscussionExecution(f.approval)
    XCTAssertEqual(try f.turn().execution?.state, .interrupted)
    XCTAssertEqual(try f.turn().execution?.response, response)
    XCTAssertNil(try f.turn().answer)
    XCTAssertThrowsError(try f.records.applySavedLocalCareDiscussionReply(f.approval, now: f.now))
    XCTAssertThrowsError(try f.records.dispatchLocalCareDiscussionTurn(f.approval, now: f.now))
    XCTAssertThrowsError(try f.records.finishLocalCareDiscussionTurn(f.approval, answer: "A late answer", now: f.now))
  }

  func testRecoveryRejectsExpiryRevocationAndChangedConversationBinding() throws {
    let f = try HealthDiscussionRecoveryFixture()
    try f.records.dispatchLocalCareDiscussionTurn(f.approval, now: f.now)
    try f.records.retainLocalCareDiscussionResponse(f.approval, response: f.response("Pending reply"), now: f.now)
    XCTAssertThrowsError(try f.records.applySavedLocalCareDiscussionReply(f.approval,
      now: f.now.addingTimeInterval(GalaxySSIHealthCareDiscussion.approvalLifetime + 1)))
    try f.records.setHealthOnlinePermission(false)
    XCTAssertThrowsError(try f.records.applySavedLocalCareDiscussionReply(f.approval, now: f.now))
    try f.records.interruptLocalCareDiscussionExecution(f.approval)
    XCTAssertEqual(try f.turn().execution?.state, .interrupted)
    let other = try HealthDiscussionRecoveryFixture()
    try other.records.dispatchLocalCareDiscussionTurn(other.approval, now: other.now)
    try other.records.retainLocalCareDiscussionResponse(other.approval, response: other.response("Wrong conversation"), now: other.now)
    try other.records.bindLocalCareAgentDiscussion(id: other.concern.id, metric: .glucose,
      threadID: other.approval.threadID, expectedConversationID: nil, conversationID: "different-conversation")
    XCTAssertThrowsError(try other.records.applySavedLocalCareDiscussionReply(other.approval, now: other.now))
    XCTAssertNil(try other.turn().answer)
  }

  func testChangedGrantAndOversizedOrUndispatchedReceiptsCannotEnterRecovery() throws {
    let f = try HealthDiscussionRecoveryFixture()
    var forged = f.approval
    forged.includesActionFeedback.toggle()
    XCTAssertThrowsError(try f.records.dispatchLocalCareDiscussionTurn(forged, now: f.now))
    XCTAssertThrowsError(try f.records.retainLocalCareDiscussionResponse(f.approval,
      response: f.response("Unsolicited receipt"), now: f.now))
    try f.records.dispatchLocalCareDiscussionTurn(f.approval, now: f.now)
    XCTAssertThrowsError(try f.records.retainLocalCareDiscussionResponse(f.approval, response: Data(), now: f.now))
    XCTAssertThrowsError(try f.records.retainLocalCareDiscussionResponse(f.approval,
      response: Data(repeating: 65, count: 65_537), now: f.now))
    XCTAssertNil(try f.turn().execution?.response)
    XCTAssertEqual(try f.turn().execution?.state, .dispatched)
  }

  func testRecoveredControlEnvelopeRemainsAnInterruptionNotAnAnswer() throws {
    let f = try HealthDiscussionRecoveryFixture()
    let control = #"{"actions":[{"kind":"native_tool","target":"fixture-only"}]}"#
    try f.records.dispatchLocalCareDiscussionTurn(f.approval, now: f.now)
    try f.records.retainLocalCareDiscussionResponse(f.approval, response: f.response(control), now: f.now)
    try f.records.applySavedLocalCareDiscussionReply(f.approval, now: f.now)
    XCTAssertEqual(try f.turn().interruptedReply, control)
    XCTAssertEqual(try f.turn().execution?.state, .interrupted)
    XCTAssertNil(try f.turn().retainedAnswer)
    XCTAssertTrue(try f.records.load().localCarePlans?.isEmpty ?? true)
  }
}

@MainActor
final class HealthDiscussionRecoveryFixture {
  let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let secrets = InMemorySecretStore()
  let records: GalaxySSIHealthRecords
  let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
  let concern: GalaxySSIHealthCare.Concern
  let approval: GalaxySSIHealthCareDiscussion.Approval

  init(history: Bool = false, asksQuestions: Bool = false, style: GalaxySSICloudAPIStyle = .openAICompatible) throws {
    let records = GalaxySSIHealthRecords(owner: "discussion-recovery-fixture", secrets: secrets, isolatedFile: file)
    self.records = records
    for index in 0..<(history ? 36 : 1) {
      try records.write(.init(metric: .glucose, measuredAt: now.addingTimeInterval(Double(-120 - index * 60)),
        value: 110, unitOverride: "mg/dL"))
    }
    try records.setPrivacy(.localCare, enabled: true)
    try records.setHealthOnlinePermission(true)
    try records.reconcileLocalCare(now: now)
    concern = try XCTUnwrap(records.load().localCare?.current["glucose"])
    _ = try records.openLocalCareDiscussion(id: concern.id, metric: .glucose)
    let endpoint = style == .gemini ? "https://example.test/v1beta/models/model:generateContent" :
      (style == .anthropic ? "https://example.test/v1/messages" : "https://example.test/v1/chat/completions")
    let model = CloudModelConfig(id: "fixture", displayName: "Fixture", provider: "Custom", modelId: "model",
      endpoint: endpoint, apiStyle: style, keychainAccount: "", updatedAt: now)
    approval = try records.prepareLocalCareDiscussion(id: concern.id, metric: .glucose, question: "Synthetic recovery question",
      destinationID: "provider", model: model, credential: "fixture-api-key", allowsHistory: history,
      asksQuestions: asksQuestions, now: now)
    try records.beginLocalCareDiscussionTurn(approval, persistExecution: true, now: now)
  }

  func turn() throws -> GalaxySSIHealthCareDiscussion.Turn {
    try XCTUnwrap(records.load().localCareDiscussions?[concern.id.uuidString]?.turns.last)
  }

  func response(_ text: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop",
      "message": ["content": text]]]])
  }

  deinit {
    try? FileManager.default.removeItem(at: file)
    try? FileManager.default.removeItem(at: file.appendingPathExtension("care-tasks"))
  }
}
