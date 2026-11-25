import Foundation
import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthCareModelReviewTests: XCTestCase {
  func testUnexecutedHealthControlRepliesAreRetainedEncryptedWithoutCompletionOrReplay() throws {
    let f = try HealthModelReviewFixture()
    let control = #"{"actions":[{"kind":"native_tool","target":"private-fixture-tool"}]}"#
    let before = try f.records.load().current
    try f.records.finishLocalCareDiscussionTurn(f.approval, answer: control, now: f.now)
    let reopened = GalaxySSIHealthRecords(owner: f.records.owner, secrets: f.secrets, isolatedFile: f.file)
    let archive = try reopened.load()
    let thread = try XCTUnwrap(archive.localCareDiscussions?[f.concern.id.uuidString])
    let turn = try XCTUnwrap(thread.turns.last)
    XCTAssertEqual(turn.id, f.approval.id)
    XCTAssertEqual(thread.id, f.approval.threadID)
    XCTAssertEqual(turn.question, f.approval.question)
    XCTAssertEqual(turn.destination, f.approval.destinationDigest)
    XCTAssertEqual(turn.interruptedReply, control)
    XCTAssertTrue(turn.hasInterruptedReply)
    XCTAssertNil(turn.answer)
    XCTAssertNil(turn.retainedAnswer)
    XCTAssertNil(turn.automaticResearchCompleted)
    XCTAssertEqual(archive.localCareResearch?.jobs[f.concern.id.uuidString]?.state, .interrupted)
    XCTAssertEqual(archive.current, before)
    XCTAssertTrue(archive.localCarePlans?.isEmpty ?? true)
    XCTAssertNil(archive.localCareModelReviews)
    XCTAssertNil(try Data(contentsOf: f.file).range(of: Data(control.utf8)))
    try reopened.finishLocalCareDiscussionTurn(f.approval, answer: control, now: f.now)
    XCTAssertEqual(try reopened.load().localCareDiscussions, archive.localCareDiscussions)
    XCTAssertEqual(try reopened.load().localCareResearch, archive.localCareResearch)
    XCTAssertThrowsError(try reopened.finishLocalCareDiscussionTurn(f.approval, answer: "A replacement answer", now: f.now))
    XCTAssertThrowsError(try reopened.validateLocalCareDiscussionTurn(f.approval, now: f.now))
    XCTAssertThrowsError(try reopened.recordLocalCareModelReview(f.approval, arguments: f.arguments(), now: f.now))
    XCTAssertTrue(try reopened.reconcileLocalCareResearch(now: f.now).isEmpty)
    let next = try GalaxySSIHealthCareDiscussion.payload(concern: f.concern, question: "A new reviewed question",
      thread: thread, destination: f.approval.destinationDigest)
    XCTAssertFalse(next.contains("private-fixture-tool"))
  }

  func testHealthControlClassificationUsesStructuredEnvelopesAndReservedRecoveryMarker() throws {
    for control in [#"{"actions":[]}"#, "```json\n{\"actions\": [{\"kind\": \"native_tool\"}]}\n```",
                    "GALAXYSSI_RECOVERY_ACTION_V1 synthetic pending action"] {
      XCTAssertTrue(AgentModelPlanParser.containsUnexecutedControlReply(control))
    }
    for prose in ["Discuss daily actions with your clinician.", #"{"summary":"Review with a clinician","plan":null}"#,
                  #"{"actions":"Discuss options"}"#] {
      XCTAssertFalse(AgentModelPlanParser.containsUnexecutedControlReply(prose))
    }
    let legacy = GalaxySSIHealthCareDiscussion.Turn(id: UUID(), question: "Synthetic question", destination: "fixture",
      answer: #"{"actions":[]}"#)
    let restored = try JSONDecoder().decode(GalaxySSIHealthCareDiscussion.Turn.self, from: JSONEncoder().encode(legacy))
    XCTAssertNil(restored.interruptedReply)
    XCTAssertTrue(restored.hasInterruptedReply)
    XCTAssertNil(restored.retainedAnswer)
    XCTAssertEqual(restored.answer, legacy.answer)
  }

  func testInterruptedHealthReplyCannotBypassRevocationExpiryOrSizeLimit() throws {
    let f = try HealthModelReviewFixture()
    let control = #"{"actions":[]}"#
    XCTAssertThrowsError(try f.records.finishLocalCareDiscussionTurn(f.approval, answer: control,
      now: f.now.addingTimeInterval(GalaxySSIHealthCareDiscussion.approvalLifetime + 1)))
    XCTAssertThrowsError(try f.records.finishLocalCareDiscussionTurn(f.approval,
      answer: control + String(repeating: "x", count: 6_145), now: f.now))
    XCTAssertNil(try f.records.load().localCareDiscussions?[f.concern.id.uuidString]?.turns.last?.interruptedReply)
    try f.records.setHealthOnlinePermission(false)
    XCTAssertThrowsError(try f.records.finishLocalCareDiscussionTurn(f.approval, answer: control, now: f.now))
  }

  func testStrictInputRejectsApprovalFlagsCoercionDuplicatesAndMissingPlanReceipt() throws {
    let f = try HealthModelReviewFixture()
    let valid = try f.arguments()
    XCTAssertEqual(try GalaxySSIHealthCareModelReview.Input(valid).decision, .observe)
    var changed = valid
    changed["approved"] = .bool(true)
    XCTAssertThrowsError(try GalaxySSIHealthCareModelReview.Input(changed))
    changed = valid; changed["attention_requested"] = .string("true")
    XCTAssertThrowsError(try GalaxySSIHealthCareModelReview.Input(changed))
    changed = valid; changed["review_events"] = .array([.string("SOURCE_CHANGE"), .string("SOURCE_CHANGE")])
    XCTAssertThrowsError(try GalaxySSIHealthCareModelReview.Input(changed))
    changed = valid; changed["decision"] = .string("PROPOSE_PLAN")
    XCTAssertThrowsError(try GalaxySSIHealthCareModelReview.Input(changed))
    changed = valid
    changed["records"] = .array([.object(["id": .string(f.concern.assessment.record!.id.uuidString), "revision": .double(1.5)])])
    XCTAssertThrowsError(try GalaxySSIHealthCareModelReview.Input(changed))
  }

  func testRetainedAssessmentIsEncryptedIdempotentAndDoesNotExecuteActions() throws {
    let f = try HealthModelReviewFixture()
    let before = try f.records.load().localCare
    let arguments = try f.arguments()
    let first = try f.records.recordLocalCareModelReview(f.approval, arguments: arguments, now: f.now)
    let retried = try f.records.recordLocalCareModelReview(f.approval, arguments: arguments, now: f.now.addingTimeInterval(1))
    XCTAssertEqual(first, retried)
    XCTAssertEqual(first.receipt["notification_sent"], .bool(false))
    XCTAssertEqual(first.receipt["scheduled"], .bool(false))
    XCTAssertEqual(try f.records.load().localCare?.current, before?.current)
    let reopened = GalaxySSIHealthRecords(owner: f.records.owner, secrets: f.secrets, isolatedFile: f.file)
    XCTAssertEqual(try reopened.load().localCareModelReviews?[first.id], first)
    XCTAssertNil(try Data(contentsOf: f.file).range(of: Data(first.input.summary.utf8)))
    var conflicting = arguments; conflicting["summary"] = .string("A conflicting final opinion")
    XCTAssertThrowsError(try reopened.recordLocalCareModelReview(f.approval, arguments: conflicting, now: f.now))
    try reopened.finishLocalCareDiscussionTurn(f.approval, answer: "Synthetic retained response", now: f.now)
    let archive = try reopened.load()
    XCTAssertEqual(archive.localCareResearch?.jobs[f.concern.id.uuidString]?.state, .completed)
    XCTAssertEqual(archive.localCareDiscussions?[f.concern.id.uuidString]?.turns.last?.automaticResearchCompleted, true)
    XCTAssertTrue(archive.localCarePlans?.isEmpty ?? true)
    XCTAssertTrue(archive.localCareFollowUps?.isEmpty ?? true)
  }

  func testMissingAssessmentPreservesReplyWithoutClaimingCompletion() throws {
    let f = try HealthModelReviewFixture()
    let job = try XCTUnwrap(f.records.load().localCareResearch?.jobs[f.concern.id.uuidString])
    XCTAssertThrowsError(try f.records.transitionLocalCareResearch(job, concern: f.concern.id, to: .completed))
    try f.records.finishLocalCareDiscussionTurn(f.approval, answer: "Reply without a retained assessment", now: f.now)
    let archive = try f.records.load()
    XCTAssertEqual(archive.localCareDiscussions?[f.concern.id.uuidString]?.turns.last?.answer, "Reply without a retained assessment")
    XCTAssertEqual(archive.localCareResearch?.jobs[f.concern.id.uuidString]?.state, .failed)
    XCTAssertEqual(archive.localCareResearch?.jobs[f.concern.id.uuidString]?.assessmentMissing, true)
    XCTAssertNil(archive.localCareResearch?.checkpoints?[f.concern.id.uuidString])
  }

  func testForeignReferencesAndEvidenceOrPlanFromAnotherTurnAreRejected() throws {
    let f = try HealthModelReviewFixture()
    var arguments = try f.arguments()
    arguments["records"] = .array([.object(["id": .string(UUID().uuidString), "revision": .int(1)])])
    XCTAssertThrowsError(try f.records.recordLocalCareModelReview(f.approval, arguments: arguments, now: f.now))
    arguments = try f.arguments(); arguments["evidence_ids"] = .array([.string(UUID().uuidString)])
    XCTAssertThrowsError(try f.records.recordLocalCareModelReview(f.approval, arguments: arguments, now: f.now))
    arguments = try f.arguments(); arguments["plan_id"] = .string(UUID().uuidString)
    XCTAssertThrowsError(try f.records.recordLocalCareModelReview(f.approval, arguments: arguments, now: f.now))
    XCTAssertNil(try f.records.load().localCareModelReviews)
  }

  func testRevocationAndChangedRecordsFenceAnAlreadyRecordedAssessment() throws {
    let f = try HealthModelReviewFixture()
    let review = try f.records.recordLocalCareModelReview(f.approval, arguments: f.arguments(), now: f.now)
    try f.records.revokeLocalCareResearch(f.concern.id)
    XCTAssertFalse(f.records.localCareModelReviewIsCurrent(review, now: f.now))
    XCTAssertThrowsError(try f.records.recordLocalCareModelReview(f.approval, arguments: f.arguments(), now: f.now))
    XCTAssertThrowsError(try f.records.finishLocalCareDiscussionTurn(f.approval, answer: "Revoked result", now: f.now))
    let changed = try HealthModelReviewFixture()
    _ = try changed.records.recordLocalCareModelReview(changed.approval, arguments: changed.arguments(), now: changed.now)
    try changed.records.write(.init(metric: .glucose, measuredAt: changed.now, value: 115, unitOverride: "mg/dL"))
    try changed.records.reconcileLocalCare(now: changed.now)
    XCTAssertThrowsError(try changed.records.finishLocalCareDiscussionTurn(changed.approval, answer: "Stale result", now: changed.now))
    _ = try changed.records.reconcileLocalCareResearch(now: changed.now)
    XCTAssertNotEqual(try changed.records.load().localCareResearch?.jobs[changed.concern.id.uuidString]?.id, changed.approval.id)
  }

  func testPlanReceiptMustBeRetainedBeforeAssessmentAndRemainsUnadopted() throws {
    let f = try HealthModelReviewFixture(plan: true)
    var input = try f.arguments()
    input["decision"] = .string("PROPOSE_PLAN"); input["plan_id"] = .string(f.approval.id.uuidString)
    XCTAssertThrowsError(try f.records.recordLocalCareModelReview(f.approval, arguments: input, now: f.now))
    try f.records.saveLocalCarePlan(f.approval, arguments: f.planArguments(), now: f.now)
    XCTAssertEqual(try f.records.load().localCareResearch?.jobs[f.concern.id.uuidString]?.state, .dispatched)
    _ = try f.records.recordLocalCareModelReview(f.approval, arguments: input, now: f.now)
    try f.records.finishLocalCareDiscussionTurn(f.approval, answer: "Draft ready for user review", now: f.now)
    XCTAssertEqual(try f.records.load().localCarePlans?[f.approval.id.uuidString]?.state, .pending)
    XCTAssertTrue(try f.records.load().localCare?.current["glucose"]?.adoptedActions?.isEmpty ?? true)
    XCTAssertTrue(try f.records.load().localCareFollowUps?.isEmpty ?? true)
  }

  func testPairedDesktopRetainsTheSameAssessmentWithoutExecutingTools() throws {
    let f = try HealthModelReviewFixture(paired: true)
    let prompt = try GalaxySSIHealthDesktopResearch.prompt(f.approval)
    XCTAssertTrue(prompt.contains("attention_requested"))
    XCTAssertTrue(prompt.contains("record_references"))
    let value: AgentMcpJSONObject = ["assessment": .object(try f.arguments()), "plan": .null, "answer": .string("Paired scoped response")]
    try GalaxySSIHealthDesktopResearch.retainStructuredReview(AgentMcpJSONCodec.stringify(value), approval: f.approval,
      records: f.records, now: f.now)
    XCTAssertNotNil(try f.records.load().localCareModelReviews?[f.approval.id])
    XCTAssertEqual(try f.records.load().localCareResearch?.jobs[f.concern.id.uuidString]?.state, .completed)
  }

  func testLegacyJobDecodingDoesNotRequireAReviewRetroactively() throws {
    let job = GalaxySSIHealthCareResearch.Job(authorization: UUID(), trigger: "legacy", revision: 1, createdAt: Date())
    let reopened = try JSONDecoder().decode(GalaxySSIHealthCareResearch.Job.self, from: JSONEncoder().encode(job))
    XCTAssertNil(reopened.reviewRequired)
  }

  func testAssessmentToolIsAvailableAndParsedForAllCloudStyles() throws {
    let f = try HealthModelReviewFixture()
    let input = try f.arguments()
    for style in [GalaxySSICloudAPIStyle.openAICompatible, .anthropic, .gemini] {
      var body: [String: Any] = [:]
      GalaxySSIHealthCareHistoryTool.configure(&body, style: style, proposesPlan: false, historyAvailable: false,
        reviewAvailable: true)
      let encoded = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
      let text = String(decoding: encoded, as: UTF8.self)
      XCTAssertTrue(text.contains(GalaxySSIHealthCareModelReview.function))
      XCTAssertTrue(text.contains("attention_requested"))
      XCTAssertTrue(text.contains("additionalProperties"))
      let response = try modelCall(style: style, input: input)
      let call = try XCTUnwrap(GalaxySSIHealthCareHistoryTool.call(response, style: style, proposesPlan: false,
        allowsReview: true))
      XCTAssertEqual(call.name, GalaxySSIHealthCareModelReview.function)
      XCTAssertEqual(call.arguments, input)
      XCTAssertThrowsError(try GalaxySSIHealthCareHistoryTool.call(response, style: style, proposesPlan: false))
    }
  }

  func testActualScopedLoopRetainsTheToolAssessmentBeforeFinalReply() async throws {
    let f = try HealthModelReviewFixture()
    let model = try XCTUnwrap(f.approval.model)
    let contact = GalaxySSIContact(id: "provider", galaxySSIId: "provider", name: "Fixture", displayName: "Fixture",
      type: "agent", agentKind: "cloud-api", deliveryMode: .cloudAPI, trustState: .verified, desktopId: "", desktopName: "",
      identityFingerprint: "", setupStatus: "ready", setupDetail: "", cloudProvider: "Custom", cloudModels: [model],
      selectedCloudModelId: model.id, deleted: false, createdAt: f.now, updatedAt: f.now)
    let first = try modelCall(style: .openAICompatible, input: f.arguments())
    let request = try GalaxySSIHealthCareDiscussion.request(f.approval, key: "fixture-api-key")
    var continuations = 0
    let final = try await GalaxySSIHealthScopedReadTransport.finish(f.approval, records: f.records,
      initial: first, request: request, style: .openAICompatible, ledger: InMemoryAgentDataDisclosureStore(),
      currentDestination: { contact }, send: { continued in
        continuations += 1
        XCTAssertNotNil(try f.records.load().localCareModelReviews?[f.approval.id])
        let text = String(decoding: try XCTUnwrap(continued.httpBody), as: UTF8.self)
        XCTAssertTrue(text.contains("notification_sent"))
        return Data(#"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Fixture final response"}}]}"#.utf8)
      })
    XCTAssertEqual(continuations, 1)
    let answer = try GalaxySSIHealthFollowUpTransport.output(final, style: .openAICompatible)
    try f.records.finishLocalCareDiscussionTurn(f.approval, answer: answer, now: f.now)
    XCTAssertEqual(try f.records.load().localCareResearch?.jobs[f.concern.id.uuidString]?.state, .completed)
  }

  func testPriorAssessmentIsAHistoricalOpinionOnlyForMatchingAuthorizationScope() throws {
    let f = try HealthModelReviewFixture()
    _ = try f.records.recordLocalCareModelReview(f.approval, arguments: f.arguments(), now: f.now)
    try f.records.finishLocalCareDiscussionTurn(f.approval, answer: "Earlier model opinion", now: f.now)
    let nextAt = f.now.addingTimeInterval(1)
    try f.records.setLocalCareContext(f.concern, applicability: .applicable, now: nextAt)
    let queued = try XCTUnwrap(f.records.reconcileLocalCareResearch(now: nextAt).first?.1)
    let job = try f.records.transitionLocalCareResearch(queued, concern: f.concern.id, to: .preparing)
    let next = try f.records.prepareLocalCareDiscussion(id: f.concern.id, metric: .glucose, question: "Review changes",
      destinationID: "provider", model: XCTUnwrap(f.approval.model), credential: "fixture-api-key", proposesPlan: true,
      research: job, now: nextAt)
    let prior = try XCTUnwrap(next.researchHandoff?.payload["prior_model_assessment"]?.objectValue)
    XCTAssertEqual(prior["clinical_verification"], .bool(false))
    XCTAssertEqual(prior["actions_executed"], .bool(false))
    let first = try XCTUnwrap(f.records.load().localCareModelReviews?[f.approval.id])
    var different = first.authorization
    different = .init(concern: different.concern, metric: different.metric, thread: different.thread,
      localPermission: different.localPermission, onlinePermission: UUID(), profileScopeEpoch: different.profileScopeEpoch,
      contact: different.contact, model: different.model, endpoint: different.endpoint, destination: different.destination,
      sources: different.sources, authorizedAt: nextAt)
    XCTAssertFalse(first.reusable(for: different, job: job))
  }

  func testInvalidAssessmentReturnsBoundedToolFeedbackAndCanBeCorrected() async throws {
    let f = try HealthModelReviewFixture()
    let model = try XCTUnwrap(f.approval.model)
    let contact = GalaxySSIContact(id: "provider", galaxySSIId: "provider", name: "Fixture", displayName: "Fixture",
      type: "agent", agentKind: "cloud-api", deliveryMode: .cloudAPI, trustState: .verified, desktopId: "", desktopName: "",
      identityFingerprint: "", setupStatus: "ready", setupDetail: "", cloudProvider: "Custom", cloudModels: [model],
      selectedCloudModelId: model.id, deleted: false, createdAt: f.now, updatedAt: f.now)
    var malformed = try f.arguments()
    malformed["approved"] = .bool(true)
    let initial = try modelCall(style: .openAICompatible, input: malformed)
    let corrected = try modelCall(style: .openAICompatible, input: f.arguments())
    let request = try GalaxySSIHealthCareDiscussion.request(f.approval, key: "fixture-api-key")
    var calls = 0
    _ = try await GalaxySSIHealthScopedReadTransport.finish(f.approval, records: f.records, initial: initial,
      request: request, style: .openAICompatible, ledger: InMemoryAgentDataDisclosureStore(), currentDestination: { contact },
      send: { next in
        calls += 1
        if calls == 1 {
          XCTAssertNil(try f.records.load().localCareModelReviews?[f.approval.id])
          XCTAssertTrue(String(decoding: try XCTUnwrap(next.httpBody), as: UTF8.self).contains("invalid_health_review"))
          return corrected
        }
        return Data(#"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Corrected response"}}]}"#.utf8)
      })
    XCTAssertEqual(calls, 2)
    XCTAssertNotNil(try f.records.load().localCareModelReviews?[f.approval.id])
  }

  private func modelCall(style: GalaxySSICloudAPIStyle, input: AgentMcpJSONObject) throws -> Data {
    let name = GalaxySSIHealthCareModelReview.function
    let value: AgentMcpJSONObject
    switch style {
    case .openAICompatible:
      value = ["choices": .array([.object(["finish_reason": .string("tool_calls"), "message": .object([
        "role": .string("assistant"), "tool_calls": .array([.object(["id": .string("review-call"), "type": .string("function"),
          "function": .object(["name": .string(name), "arguments": .string(AgentMcpJSONCodec.stringify(input))])])])])])])]
    case .anthropic:
      value = ["stop_reason": .string("tool_use"), "content": .array([.object(["type": .string("tool_use"),
        "id": .string("review-call"), "name": .string(name), "input": .object(input)])])]
    case .gemini:
      value = ["candidates": .array([.object(["finishReason": .string("STOP"), "content": .object([
        "role": .string("model"), "parts": .array([.object(["functionCall": .object(["name": .string(name), "args": .object(input)])])])])])])]
    }
    return Data(AgentMcpJSONCodec.stringify(value).utf8)
  }
}

@MainActor
final class HealthModelReviewFixture {
  let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let secrets = InMemorySecretStore()
  let records: GalaxySSIHealthRecords
  let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
  let concern: GalaxySSIHealthCare.Concern
  let approval: GalaxySSIHealthCareDiscussion.Approval
  let quote = "This fictional laboratory paragraph is a fixture for testing extraction and exact passage matching only."

  init(plan: Bool = false, paired: Bool = false, selected: Set<GalaxySSIHealthMetric> = [], questionFollowUp: Bool = false) throws {
    let records = GalaxySSIHealthRecords(owner: "review-fixture", secrets: secrets, isolatedFile: file)
    self.records = records
    try records.write(.init(metric: .glucose, measuredAt: now.addingTimeInterval(-120), value: 110, unitOverride: "mg/dL"))
    if !selected.isEmpty {
      for index in 0..<35 {
        try records.write(.init(metric: .weight, measuredAt: now.addingTimeInterval(Double(-300 - index * 3600)), value: 70))
      }
      try records.write(.init(metric: .bloodPressure, measuredAt: now.addingTimeInterval(-200), value: 121, diastolic: 79))
      try records.write(.init(metric: .heartRate, measuredAt: now.addingTimeInterval(-200), value: 72))
    }
    try records.setPrivacy(.localCare, enabled: true)
    try records.setHealthOnlinePermission(true)
    try records.reconcileLocalCare(now: now)
    let original = try XCTUnwrap(records.load().localCare?.current["glucose"])
    if plan { try records.setLocalCareContext(original, applicability: .applicable, now: now) }
    concern = try XCTUnwrap(records.load().localCare?.current["glucose"])
    _ = try records.openLocalCareDiscussion(id: concern.id, metric: .glucose)
    let model = CloudModelConfig(id: "fixture", displayName: "Fixture", provider: "Custom", modelId: "model",
      endpoint: "https://example.test/v1/chat/completions", apiStyle: .openAICompatible, keychainAccount: "", updatedAt: now)
    let route = GalaxySSIHealthDesktopResearch.Route(connector: .init(contactId: "desktop:codex", desktopId: "desktop",
      clientRouteId: "client", modelId: "fixture", reasoningEffort: .automatic), desktopFingerprint: "pinned")
    var preview = try paired ? records.prepareLocalCareDesktopDiscussion(id: concern.id, metric: .glucose,
      question: "Review exact scope", route: route, includesQuestions: questionFollowUp, now: now) : records.prepareLocalCareDiscussion(id: concern.id, metric: .glucose,
      question: "Review exact scope", destinationID: "provider", model: model, credential: "fixture-api-key", includesQuestions: questionFollowUp, now: now)
    preview.allowsStandingQuestionFollowUp = questionFollowUp
    preview = try records.approveRelatedLocalCareMeasurements(preview, selected: selected, now: now)
    try records.authorizeLocalCareResearch(preview, sources: [.labResults], now: now)
    let queued = try XCTUnwrap(records.reconcileLocalCareResearch(now: now).first?.1)
    let job = try records.transitionLocalCareResearch(queued, concern: concern.id, to: .preparing)
    var review = try paired ? records.prepareLocalCareDesktopDiscussion(id: concern.id, metric: .glucose,
      question: "Review exact scope", route: route, research: job, now: now) : records.prepareLocalCareDiscussion(id: concern.id,
      metric: .glucose, question: "Review exact scope", destinationID: "provider", model: model, credential: "fixture-api-key",
      proposesPlan: true, research: job, now: now)
    if review.proposesPlan {
      review.evidence = [try GalaxySSIHealthCareEvidence.fromNativeBody(
        Data("<html><body><article><h1>Fixture</h1><p>\(quote)</p></article></body></html>".utf8),
        source: .labResults, binding: .init(review), retrievedAt: now, observedAt: now)]
    }
    approval = review
    try records.beginLocalCareDiscussionTurn(review, now: now)
  }
  deinit { try? FileManager.default.removeItem(at: file) }

  func arguments() throws -> AgentMcpJSONObject {
    ["summary": .string("Synthetic scoped model assessment"), "rationale": .string("Only supplied data were considered"),
      "uncertainty": .string("Current symptoms are unknown; applicability is not clinically verified"),
      "next_step": .string("Review the missing context"), "decision": .string("OBSERVE"), "questions": .array([]),
      "review_events": .array([.string("USER_FEEDBACK")]),
      "records": .array(records.localCareReviewReferences(concern, related: approval.relatedMeasurements,
        archive: try records.load(), now: now).map(\.payload)),
      "evidence_ids": .array(approval.evidence.map { .string($0.id.uuidString) }), "plan_id": .string(""),
      "attention_requested": .bool(false), "attention_reason": .string("No notification was requested")]
  }

  func planArguments() throws -> AgentMcpJSONObject {
    let evidence = try XCTUnwrap(approval.evidence.first)
    let text = """
      {"uncertainty":"Synthetic scope","sources":[{"title":"Fixture","url":"\(evidence.url.absoluteString)",
      "version":"1","applicability":"Review exact context","evidence_id":"\(evidence.id.uuidString)","quote":"\(quote)"}],
      "actions":[{"kind":"CONTEXT","description":"Review the missing context","rationale":"Fixture","source_index":0,
      "due_from":"","due_until":"","applicability":{"mode":"DISCUSSION_ONLY","checks":[],"missing_information":[],"conflicts":[]}}]}
      """
    return try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(text.utf8))
  }
}
