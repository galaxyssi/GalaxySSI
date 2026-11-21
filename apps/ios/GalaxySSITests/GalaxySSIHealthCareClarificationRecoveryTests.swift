import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthCareClarificationRecoveryTests: XCTestCase {
  private var question: AgentMcpJSONObject {
    ["questions": .array([.object(["key": .string("context.fasting_hours"),
      "question": .string("How long before this sample did you last consume calories?"),
      "purpose": .string("The sample's fasting duration is not recorded")])])]
  }

  func testModelQuestionsDoNotInvalidateTheirOwnFrozenTurnOrInventAnswers() throws {
    let f = try HealthModelReviewFixture(questionFollowUp: true)
    XCTAssertTrue(f.approval.canProposeAutomaticQuestions)
    let before = try f.approval.providerPayload(now: f.now)
    let result = try f.records.retainAutomaticCareQuestions(f.approval, arguments: question, now: f.now)
    let receipt = try XCTUnwrap(result.receipt["questions"]?.arrayValue?.first?.objectValue)
    XCTAssertNotNil(UUID(uuidString: receipt.string("question_id")))
    XCTAssertEqual(receipt["state"], .string("open"))
    XCTAssertEqual(result.receipt["answers_invented"], .bool(false))
    XCTAssertEqual(try result.approval.providerPayload(now: f.now), before)
    try f.records.validateLocalCareDiscussionTurn(f.approval, now: f.now)
    let rows = try f.records.localCareQuestionPage(id: f.concern.id, metric: .glucose, now: f.now).rows
    XCTAssertEqual(rows.count, 1); XCTAssertNil(rows.first?.answer)
    XCTAssertEqual(try f.records.retainAutomaticCareQuestions(f.approval, arguments: question, now: f.now).receipt, result.receipt)
    _ = try f.records.recordLocalCareModelReview(f.approval, arguments: f.arguments(), now: f.now)
    try f.records.finishLocalCareDiscussionTurn(f.approval, answer: "Synthetic question retained", now: f.now)
    XCTAssertThrowsError(try f.records.retainAutomaticCareQuestions(f.approval, arguments: question, now: f.now))
  }

  func testReviewedAnswerResumesTheOriginalPairedConversationAcrossArchiveReopen() throws {
    let f = try HealthModelReviewFixture(paired: true, questionFollowUp: true)
    let originalReadings = try f.records.load().current
    let originalAuth = try XCTUnwrap(f.records.load().localCareResearch?.authorizations[f.concern.id.uuidString])
    try GalaxySSIHealthDesktopResearch.retainStructuredReview(envelope(f, questions: question["questions"] ?? .array([])),
      approval: f.approval, records: f.records, now: f.now)
    let row = try XCTUnwrap(f.records.localCareQuestionPage(id: f.concern.id, metric: .glucose, now: f.now).rows.first)
    let nextAt = f.now.addingTimeInterval(1)
    try f.records.reviewLocalCareQuestion(id: f.concern.id, metric: .glucose, row: row,
      state: .answered, answer: "Synthetic user report: ten hours without calories", now: nextAt)
    let queued = try XCTUnwrap(f.records.reconcileLocalCareResearch(now: nextAt).first?.1)
    XCTAssertNotEqual(queued.id, f.approval.id)
    XCTAssertEqual(queued.authorization, originalAuth.id)
    let preparing = try f.records.transitionLocalCareResearch(queued, concern: f.concern.id, to: .preparing)
    let route = try XCTUnwrap(f.approval.pairedDesktop)
    let followup = try f.records.prepareLocalCareDesktopDiscussion(id: f.concern.id, metric: .glucose,
      question: "Review the saved answer", route: route, research: preparing, now: nextAt)
    XCTAssertEqual(followup.threadID, f.approval.threadID)
    let context = try followup.providerPayload(now: nextAt)
    XCTAssertTrue(context.contains("ten hours without calories"))
    XCTAssertTrue(context.contains("reviewed_question_answer"))
    XCTAssertEqual(followup.questions?.payload["items"]?.arrayValue?.first?.objectValue?["ask_again"], .bool(false))
    try f.records.beginLocalCareDiscussionTurn(followup, now: nextAt)
    let binding = try f.records.bindLocalCareDesktopResearch(originalAuth, job: followup.id, sender: "synthetic-phone",
      reviewedAt: nextAt, now: nextAt)
    let reopened = GalaxySSIHealthRecords(owner: f.records.owner, secrets: f.secrets, isolatedFile: f.file)
    let (_, restoredJob, restoredBinding) = try XCTUnwrap(reopened.dispatchedLocalCareDesktopResearch().first)
    XCTAssertEqual(restoredBinding, binding)
    let restored = try reopened.prepareLocalCareDesktopDiscussion(id: f.concern.id, metric: .glucose,
      question: "", route: route, research: restoredJob, resume: restoredBinding, now: nextAt)
    XCTAssertEqual(try restored.providerPayload(now: nextAt), context)
    let reply = AgentMcpJSONCodec.stringify(["assessment": .object(try f.arguments()), "plan": .null,
      "questions": .array([]), "answer": .string("Synthetic follow-up uses the reviewed answer")])
    try GalaxySSIHealthDesktopResearch.retainStructuredReview(reply, approval: restored, records: reopened, now: nextAt)
    let answered = try XCTUnwrap(reopened.localCareQuestionPage(id: f.concern.id, metric: .glucose, now: nextAt).rows.first)
    let before = try XCTUnwrap(reopened.load().localCare?.current["glucose"])
    try reopened.reviewLocalCareQuestion(id: f.concern.id, metric: .glucose, row: answered,
      state: .answered, answer: answered.answer, now: nextAt.addingTimeInterval(1))
    XCTAssertEqual(try reopened.load().localCare?.current["glucose"], before)
    XCTAssertTrue(try reopened.reconcileLocalCareResearch(now: nextAt.addingTimeInterval(1)).isEmpty)
    let archive = try reopened.load()
    XCTAssertEqual(archive.current, originalReadings)
    XCTAssertEqual(archive.localCareDiscussions?[f.concern.id.uuidString]?.turns.map(\.id), [f.approval.id, restored.id])
    XCTAssertNotNil(archive.localCareModelReviews?[f.approval.id])
    XCTAssertNotNil(archive.localCareModelReviews?[restored.id])
    XCTAssertNil(archive.localCare?.current["glucose"]?.context?.answers?.fastingHours)
    XCTAssertTrue(archive.localCare?.current["glucose"]?.adoptedActions?.isEmpty ?? true)
    XCTAssertTrue(archive.localCareFollowUps?.isEmpty ?? true)
    XCTAssertNil(archive.localCare?.current["glucose"]?.target)
  }

  func testLegacyConsentDoesNotAcquireAutomaticQuestionOrAnswerSharing() throws {
    let f = try HealthModelReviewFixture()
    XCTAssertFalse(f.approval.canProposeAutomaticQuestions)
    XCTAssertThrowsError(try f.records.retainAutomaticCareQuestions(f.approval, arguments: question, now: f.now))
    let authorization = try XCTUnwrap(f.records.load().localCareResearch?.authorizations[f.concern.id.uuidString])
    let decoded = try JSONDecoder().decode(GalaxySSIHealthCareResearch.Authorization.self,
      from: JSONEncoder().encode(authorization))
    XCTAssertNil(decoded.reviewedAnswerFollowUp)
  }

  func testReviewingAnAnswerRejectsTheOlderInFlightReplyBeforeReconciliation() throws {
    let f = try HealthModelReviewFixture(paired: true, questionFollowUp: true)
    let authorization = try XCTUnwrap(f.records.load().localCareResearch?.authorizations[f.concern.id.uuidString])
    let binding = try f.records.bindLocalCareDesktopResearch(authorization, job: f.approval.id, sender: "synthetic-phone",
      reviewedAt: f.now, now: f.now)
    _ = try f.records.retainAutomaticCareQuestions(f.approval, arguments: question, now: f.now)
    let row = try XCTUnwrap(f.records.localCareQuestionPage(id: f.concern.id, metric: .glucose, now: f.now).rows.first)
    try f.records.reviewLocalCareQuestion(id: f.concern.id, metric: .glucose, row: row,
      state: .answered, answer: "Synthetic ten hours", now: f.now)
    XCTAssertNotNil(try f.records.load().localCareResearch?.authorizations[f.concern.id.uuidString])
    XCTAssertNil(f.records.currentLocalCareDesktopResearch(binding.identity,
      contact: binding.route.connector.contactId, source: binding.source, now: f.now))
    XCTAssertThrowsError(try f.records.recordLocalCareModelReview(f.approval, arguments: f.arguments(), now: f.now))
    let next = try XCTUnwrap(f.records.reconcileLocalCareResearch(now: f.now).first?.1)
    XCTAssertNotEqual(next.id, f.approval.id)
    XCTAssertEqual(try f.records.pendingLocalCareDesktopCancellations().first?.binding, binding)
    XCTAssertNil(try f.records.load().localCareModelReviews?[f.approval.id])
  }

  func testDuplicateReviewAtRevisionLimitDoesNotConsumeAnotherRevision() throws {
    var ledger = GalaxySSIHealthCareQuestions.Ledger()
    let now = Date()
    try ledger.propose([.init(key: "context.example", question: "Synthetic missing context?", purpose: "Fixture")],
      scope: "scope", basis: "basis", known: [:], turn: UUID(), now: now)
    let row = try XCTUnwrap(ledger.page(scope: "scope", basis: "basis", known: [:], after: nil).rows.first)
    XCTAssertTrue(try ledger.review(row, scope: "scope", basis: "basis", state: .answered, answer: "Synthetic answer", now: now))
    let answered = try XCTUnwrap(ledger.revisions[row.id.uuidString]?.last)
    ledger.revisions[row.id.uuidString] = Array(repeating: answered, count: GalaxySSIHealthCareQuestions.maximumRevisions)
    XCTAssertFalse(try ledger.review(answered, scope: "scope", basis: "basis", state: .answered, answer: "Synthetic answer", now: now))
    XCTAssertEqual(ledger.revisions[row.id.uuidString]?.count, GalaxySSIHealthCareQuestions.maximumRevisions)
    XCTAssertThrowsError(try ledger.review(answered, scope: "scope", basis: "basis", state: .answered, answer: "Different answer", now: now))
  }

  func testLegacyQuestionAnswerStillRequiresRenewedConsent() throws {
    let f = try HealthModelReviewFixture(questionFollowUp: true)
    _ = try f.records.retainAutomaticCareQuestions(f.approval, arguments: question, now: f.now)
    _ = try f.records.recordLocalCareModelReview(f.approval, arguments: f.arguments(), now: f.now)
    try f.records.finishLocalCareDiscussionTurn(f.approval, answer: "Synthetic initial question", now: f.now)
    var archive = try f.records.load()
    archive.localCareResearch?.authorizations[f.concern.id.uuidString]?.reviewedAnswerFollowUp = nil
    try f.records.persistCareClarification(archive)
    let row = try XCTUnwrap(f.records.localCareQuestionPage(id: f.concern.id, metric: .glucose, now: f.now).rows.first)
    try f.records.reviewLocalCareQuestion(id: f.concern.id, metric: .glucose, row: row,
      state: .answered, answer: "Synthetic ten hours", now: f.now)
    XCTAssertNil(try f.records.load().localCareResearch?.authorizations[f.concern.id.uuidString])
    XCTAssertTrue(try f.records.reconcileLocalCareResearch(now: f.now).isEmpty)
  }

  func testActualCloudLoopRetainsQuestionsThenRecordsAssessmentAndFinalReply() async throws {
    let f = try HealthModelReviewFixture(questionFollowUp: true)
    let model = try XCTUnwrap(f.approval.model)
    let contact = GalaxySSIContact(id: "provider", galaxySSIId: "provider", name: "Fixture", displayName: "Fixture",
      type: "agent", agentKind: "cloud-api", deliveryMode: .cloudAPI, trustState: .verified, desktopId: "", desktopName: "",
      identityFingerprint: "", setupStatus: "ready", setupDetail: "", cloudProvider: "Custom", cloudModels: [model],
      selectedCloudModelId: model.id, deleted: false, createdAt: f.now, updatedAt: f.now)
    let request = try GalaxySSIHealthCareDiscussion.request(f.approval, key: "fixture-api-key")
    XCTAssertTrue(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self).contains(GalaxySSIHealthCareQuestions.tool))
    var sends = 0
    let final = try await GalaxySSIHealthScopedReadTransport.finish(f.approval, records: f.records,
      initial: call(GalaxySSIHealthCareQuestions.tool, question), request: request, style: .openAICompatible,
      ledger: InMemoryAgentDataDisclosureStore(), currentDestination: { contact }, send: { request in
        sends += 1
        if sends == 1 {
          let text = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
          XCTAssertTrue(text.contains("question_id"))
          let row = try XCTUnwrap(f.records.localCareQuestionPage(id: f.concern.id, metric: .glucose).rows.first)
          XCTAssertNil(row.answer)
          return self.call(GalaxySSIHealthCareModelReview.function, try f.arguments())
        }
        return Data(#"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Synthetic unresolved-context question"}}]}"#.utf8)
      })
    XCTAssertEqual(sends, 2)
    try f.records.finishLocalCareDiscussionTurn(f.approval,
      answer: GalaxySSIHealthFollowUpTransport.output(final, style: .openAICompatible), now: f.now)
    XCTAssertEqual(try f.records.load().localCareResearch?.jobs[f.concern.id.uuidString]?.state, .completed)
  }

  func testQuestionToolDoesNotForceAnUnnecessaryQuestionAcrossCloudStyles() throws {
    for style in [GalaxySSICloudAPIStyle.openAICompatible, .anthropic, .gemini] {
      var body: [String: Any] = [:]
      GalaxySSIHealthCareHistoryTool.configure(&body, style: style, proposesPlan: false, historyAvailable: false,
        reviewAvailable: true, automaticQuestionsAvailable: true)
      let text = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
      XCTAssertTrue(text.contains(GalaxySSIHealthCareQuestions.tool))
      if style == .openAICompatible { XCTAssertNil(body["tool_choice"]) }
      if style == .anthropic { XCTAssertEqual((body["tool_choice"] as? [String: Any])?["type"] as? String, "auto") }
      if style == .gemini { XCTAssertNil(body["toolConfig"]) }
    }
  }

  private func envelope(_ f: HealthModelReviewFixture, questions: AgentMcpJSONValue) throws -> String {
    AgentMcpJSONCodec.stringify(["assessment": .object(try f.arguments()), "plan": .null,
      "questions": questions, "answer": .string("Synthetic initial clarification")])
  }

  private func call(_ name: String, _ input: AgentMcpJSONObject) -> Data {
    Data(AgentMcpJSONCodec.stringify(["choices": .array([.object(["finish_reason": .string("tool_calls"),
      "message": .object(["role": .string("assistant"), "tool_calls": .array([.object([
        "id": .string(UUID().uuidString), "type": .string("function"), "function": .object([
          "name": .string(name), "arguments": .string(AgentMcpJSONCodec.stringify(input))])])])])])])]).utf8)
  }
}
