import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthCareReviewQuestionsTests: XCTestCase {
  typealias Questions = GalaxySSIHealthCareQuestions
  typealias Review = GalaxySSIHealthCareModelReview

  private var proposal: AgentMcpJSONObject {
    ["questions": .array([.object(["key": .string("context.fasting_hours"),
      "question": .string("Synthetic fasting duration?"), "purpose": .string("Missing sample context")])])]
  }

  private func retained(_ f: HealthModelReviewFixture) throws -> Questions.Row {
    _ = try f.records.retainAutomaticCareQuestions(f.approval, arguments: proposal, now: f.now)
    return try XCTUnwrap(f.records.localCareQuestionPage(id: f.concern.id, metric: .glucose, now: f.now).rows.first)
  }

  private func input(_ f: HealthModelReviewFixture, _ row: Questions.Row) throws -> AgentMcpJSONObject {
    var input = try f.arguments()
    input["decision"] = .string("CLARIFY")
    input["questions"] = .array([.object(["id": .string(row.id.uuidString), "revision": .int(Int64(row.revision))])])
    return input
  }

  private func save(_ row: Questions.Row, fixture f: HealthModelReviewFixture) throws {
    var archive = try f.records.load()
    archive.localCareQuestions?[f.concern.id.uuidString]?.revisions[row.id.uuidString] = [row]
    try f.records.persistCareClarification(archive)
  }

  func testClarificationRequiresExactUniquePositiveQuestionReferences() throws {
    let f = try HealthModelReviewFixture(questionFollowUp: true)
    let row = try retained(f)
    let valid = try input(f, row)
    XCTAssertEqual(try Review.Input(valid).questions?.first?.id, row.id)
    var invalid = valid; invalid.removeValue(forKey: "questions")
    XCTAssertThrowsError(try Review.Input(invalid))
    invalid = valid; invalid["questions"] = .array([])
    XCTAssertThrowsError(try Review.Input(invalid))
    for revision in [AgentMcpJSONValue.int(0), .double(1.5), .string("1"), .bool(true)] {
      invalid = valid
      invalid["questions"] = .array([.object(["id": .string(row.id.uuidString), "revision": revision])])
      XCTAssertThrowsError(try Review.Input(invalid))
    }
    invalid = valid
    invalid["questions"] = .array(Array(repeating: valid["questions"]!.arrayValue!.first!, count: 2))
    XCTAssertThrowsError(try Review.Input(invalid))
    invalid["questions"] = .array(Array(repeating: valid["questions"]!.arrayValue!.first!, count: 31))
    XCTAssertThrowsError(try Review.Input(invalid))
  }

  func testRetainedOpenQuestionIsReferencedWithoutCreatingOrAnsweringQuestions() throws {
    let f = try HealthModelReviewFixture(questionFollowUp: true)
    let row = try retained(f)
    let before = try f.records.load().localCareQuestions?[f.concern.id.uuidString]?.revisions
    let saved = try f.records.recordLocalCareModelReview(f.approval, arguments: input(f, row), now: f.now)
    XCTAssertEqual(saved.input.questions, [Review.Reference(id: row.id, revision: row.revision)])
    XCTAssertEqual(saved.receipt["questions_created"], .bool(false))
    XCTAssertEqual(saved.receipt["question_references"], saved.input.payload["questions"])
    XCTAssertEqual(try f.records.load().localCareQuestions?[f.concern.id.uuidString]?.revisions, before)
    XCTAssertEqual(try f.records.recordLocalCareModelReview(f.approval, arguments: input(f, row), now: f.now), saved)
  }

  func testInventedQuestionAndStaleRevisionAreCorrectableErrors() throws {
    let f = try HealthModelReviewFixture(questionFollowUp: true)
    let row = try retained(f)
    var changed = row; changed.id = UUID()
    XCTAssertThrowsError(try f.records.recordLocalCareModelReview(f.approval, arguments: input(f, changed), now: f.now)) { error in
      guard let failure = error as? GalaxySSIHealthRecords.Failure else { return XCTFail("Wrong failure type") }
      XCTAssertEqual(Review.failure(failure)?["error"], .string("invalid_health_review"))
    }
    changed = row; changed.revision += 1
    try save(changed, fixture: f)
    XCTAssertThrowsError(try f.records.recordLocalCareModelReview(f.approval, arguments: input(f, row), now: f.now))
    XCTAssertNil(try f.records.load().localCareModelReviews?[f.approval.id])
  }

  func testResolvedDeferredDeclinedAndStaleQuestionsAreNotAwaitingClarification() throws {
    for state in [Questions.State.answered, .deferred, .declined, .stale] {
      let f = try HealthModelReviewFixture(questionFollowUp: true)
      var row = try retained(f); row.state = state
      if state == .answered { row.answer = "Synthetic reviewed answer" }
      try save(row, fixture: f)
      XCTAssertThrowsError(try f.records.recordLocalCareModelReview(f.approval, arguments: input(f, row), now: f.now))
      XCTAssertNil(try f.records.load().localCareModelReviews?[f.approval.id])
    }
  }

  func testExplicitConflictRemainsReviewableWithoutRewritingItsAnswer() throws {
    let f = try HealthModelReviewFixture(questionFollowUp: true)
    var row = try retained(f); row.state = .conflict; row.answer = "Synthetic conflicting self-report"
    try save(row, fixture: f)
    let saved = try f.records.recordLocalCareModelReview(f.approval, arguments: input(f, row), now: f.now)
    XCTAssertEqual(saved.input.decision, .clarify)
    XCTAssertEqual(try f.records.load().localCareQuestions?[f.concern.id.uuidString]?.revisions[row.id.uuidString]?.last, row)
  }

  func testWithheldMeasurementScopeAndChangedQuestionBasisAreRejected() throws {
    for alteredScope in [false, true] {
      let f = try HealthModelReviewFixture(questionFollowUp: true)
      var row = try retained(f)
      if alteredScope { row.relatedMeasurements = ["weight"] } else { row.basis = "obsolete-basis" }
      try save(row, fixture: f)
      XCTAssertThrowsError(try f.records.recordLocalCareModelReview(f.approval, arguments: input(f, row), now: f.now))
    }
    let f = try HealthModelReviewFixture()
    var supplied = try f.arguments(); supplied["decision"] = .string("CLARIFY")
    supplied["questions"] = .array([Review.Reference(id: UUID(), revision: 1).payload])
    XCTAssertThrowsError(try f.records.recordLocalCareModelReview(f.approval, arguments: supplied, now: f.now))
  }

  func testSavedFactCannotBeReaskedByAnOtherwiseOpenRow() throws {
    let f = try HealthModelReviewFixture(questionFollowUp: true)
    var row = try retained(f)
    var concern = f.concern
    concern.context = .init(record: try XCTUnwrap(concern.assessment.record), applicability: .unknown,
      answers: .init(fastingHours: 10))
    row.basis = try Questions.basis(concern)
    var archive = try f.records.load()
    archive.localCareQuestions?[concern.id.uuidString]?.revisions[row.id.uuidString] = [row]
    XCTAssertThrowsError(try f.records.validateCareReviewQuestions(Review.Input(input(f, row)),
      approval: f.approval, concern: concern, archive: archive))
  }

  func testSelectedQuestionPageReadsCurrentAnswerStateNotArchivedRevision() throws {
    let f = try HealthModelReviewFixture(questionFollowUp: true)
    let row = try retained(f)
    let review = try f.records.recordLocalCareModelReview(f.approval, arguments: input(f, row), now: f.now)
    try f.records.finishLocalCareDiscussionTurn(f.approval, answer: "Synthetic clarification", now: f.now)
    try f.records.reviewLocalCareQuestion(id: f.concern.id, metric: .glucose, row: row,
      state: .answered, answer: "Synthetic ten hours", now: f.now)
    let current = try f.records.localCareModelReviewQuestions(review, now: f.now)
    XCTAssertEqual(current.rows.map(\.id), [row.id])
    XCTAssertGreaterThan(try XCTUnwrap(current.rows.first?.revision), row.revision)
    XCTAssertEqual(current.state(current.rows[0]), .answered)
    XCTAssertEqual(current.rows[0].answer, "Synthetic ten hours")
    XCTAssertNil(current.next)
  }

  func testPairedDeclaredQuestionIsStoredBeforeItsAssessmentReferenceIsValidated() throws {
    let f = try HealthModelReviewFixture(paired: true, questionFollowUp: true)
    let id = UUID()
    var supplied = try f.arguments(); supplied["decision"] = .string("CLARIFY")
    supplied["questions"] = .array([Review.Reference(id: id, revision: 1).payload])
    var proposed = try XCTUnwrap(proposal["questions"]?.arrayValue?.first?.objectValue)
    proposed["id"] = .string(id.uuidString)
    let envelope = AgentMcpJSONCodec.stringify(["assessment": .object(supplied), "plan": .null,
      "questions": .array([.object(proposed)]), "answer": .string("Synthetic paired clarification")])
    try GalaxySSIHealthDesktopResearch.retainStructuredReview(envelope, approval: f.approval, records: f.records, now: f.now)
    let archive = try f.records.load()
    XCTAssertEqual(archive.localCareQuestions?[f.concern.id.uuidString]?.revisions[id.uuidString]?.last?.id, id)
    XCTAssertEqual(archive.localCareModelReviews?[f.approval.id]?.input.questions, [Review.Reference(id: id, revision: 1)])
    XCTAssertEqual(archive.localCareResearch?.jobs[f.concern.id.uuidString]?.state, .completed)
  }

  func testPairedUnknownReferenceIsNeverInsertedIntoTheAssessmentByTheHost() throws {
    let f = try HealthModelReviewFixture(paired: true, questionFollowUp: true)
    let proposedID = UUID(), invented = UUID()
    var supplied = try f.arguments(); supplied["decision"] = .string("CLARIFY")
    supplied["questions"] = .array([Review.Reference(id: invented, revision: 1).payload])
    var proposed = try XCTUnwrap(proposal["questions"]?.arrayValue?.first?.objectValue)
    proposed["id"] = .string(proposedID.uuidString)
    let envelope = AgentMcpJSONCodec.stringify(["assessment": .object(supplied), "plan": .null,
      "questions": .array([.object(proposed)]), "answer": .string("Must not be retained")])
    XCTAssertThrowsError(try GalaxySSIHealthDesktopResearch.retainStructuredReview(envelope,
      approval: f.approval, records: f.records, now: f.now))
    let archive = try f.records.load()
    XCTAssertNil(archive.localCareModelReviews?[f.approval.id])
    XCTAssertNil(archive.localCareDiscussions?[f.concern.id.uuidString]?.turns.last?.answer)
    XCTAssertNil(archive.localCareQuestions?[f.concern.id.uuidString]?.revisions[invented.uuidString])
    XCTAssertNotNil(archive.localCareQuestions?[f.concern.id.uuidString]?.revisions[proposedID.uuidString])
  }

  func testDeclaredIDsCannotHijackAnotherQuestionOrBeUsedByCloudProposals() throws {
    let f = try HealthModelReviewFixture(questionFollowUp: true)
    XCTAssertThrowsError(try f.records.retainAutomaticCareQuestions(f.approval, arguments: proposal,
      declaredIDs: ["context.fasting_hours": UUID()], now: f.now))
    var ledger = Questions.Ledger()
    let id = UUID(), turn = UUID(), now = Date()
    let first = Questions.Proposal(key: "context.first", question: "Synthetic first?", purpose: "Fixture")
    try ledger.propose([first], scope: "scope", basis: "basis", known: [:], turn: turn, now: now,
      declaredIDs: [first.key: id])
    XCTAssertThrowsError(try ledger.propose([.init(key: "context.second", question: "Hijack?", purpose: "Fixture")],
      scope: "scope", basis: "basis", known: [:], turn: turn, now: now, declaredIDs: ["context.second": id]))
    XCTAssertThrowsError(try ledger.propose([first], scope: "scope", basis: "basis", known: [:], turn: UUID(), now: now,
      declaredIDs: [first.key: id]))
    XCTAssertEqual(ledger.revisions.count, 1)
    XCTAssertEqual(ledger.revisions[id.uuidString]?.last?.proposal, first)
  }

  func testLegacyEncryptedClarificationInputStillDecodesWithoutQuestionReferences() throws {
    let f = try HealthModelReviewFixture()
    var stored = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(Review.Input(f.arguments()))) as? [String: Any])
    stored.removeValue(forKey: "questions")
    stored["decision"] = "CLARIFY"
    let legacy = try JSONDecoder().decode(Review.Input.self, from: JSONSerialization.data(withJSONObject: stored))
    XCTAssertEqual(legacy.decision, .clarify)
    XCTAssertNil(legacy.questions)
    XCTAssertEqual(legacy.payload["questions"], .array([]))
  }

  func testPairedDeclaredIDCannotReplaceAQuestionInAnotherConcernNamespace() throws {
    let f = try HealthModelReviewFixture(paired: true, questionFollowUp: true)
    let id = UUID()
    var foreign = Questions.Ledger()
    let value = Questions.Proposal(key: "context.foreign", question: "Synthetic foreign question?", purpose: "Fixture")
    try foreign.propose([value], scope: "foreign", basis: "foreign", known: [:], turn: UUID(), now: f.now,
      declaredIDs: [value.key: id])
    var archive = try f.records.load()
    archive.localCareQuestions = [UUID().uuidString: foreign]
    try f.records.persistCareClarification(archive)
    let before = try Data(contentsOf: f.file)
    XCTAssertThrowsError(try f.records.retainAutomaticCareQuestions(f.approval, arguments: proposal,
      declaredIDs: ["context.fasting_hours": id], now: f.now))
    XCTAssertEqual(try Data(contentsOf: f.file), before)
  }

  func testReferenceLookupAndScopedPageAreNotLimitedToTheFirstQuestionPage() throws {
    let f = try HealthModelReviewFixture(questionFollowUp: true)
    var archive = try f.records.load()
    let basis = try Questions.basis(f.concern), scope = Questions.scope(f.concern)
    var ledger = Questions.Ledger()
    for offset in [0, 8] {
      let values = (offset..<min(offset + 8, 9)).map {
        Questions.Proposal(key: "context.item_\($0)", question: "Synthetic item \($0)?", purpose: "Fixture")
      }
      try ledger.propose(values, scope: scope, basis: basis, known: [:], turn: f.approval.id, now: f.now)
    }
    archive.localCareQuestions = [f.concern.id.uuidString: ledger]
    try f.records.persistCareClarification(archive)
    let first = try f.records.localCareQuestionPage(id: f.concern.id, metric: .glucose, now: f.now)
    XCTAssertEqual(first.rows.count, 8)
    let selected = try XCTUnwrap(ledger.revisions.values.compactMap(\.last).first { row in
      !first.rows.contains(where: { $0.id == row.id })
    })
    let review = try f.records.recordLocalCareModelReview(f.approval, arguments: input(f, selected), now: f.now)
    let page = try f.records.localCareModelReviewQuestions(review, now: f.now)
    XCTAssertEqual(page.rows.map(\.id), [selected.id])
    XCTAssertNil(page.next)
    var changed = try f.records.load()
    changed.localCareQuestions?[f.concern.id.uuidString]?.revisions.removeValue(forKey: selected.id.uuidString)
    try f.records.persistCareClarification(changed)
    XCTAssertThrowsError(try f.records.localCareModelReviewQuestions(review, now: f.now))
  }

  func testDifferentQuestionSharingScopeIsRejectedEvenWithAMatchingID() throws {
    let f = try HealthModelReviewFixture(questionFollowUp: true)
    let original = try retained(f)
    let outside = Questions.Row(id: original.id, proposal: original.proposal, scope: "outside-scope", basis: original.basis,
      turn: original.turn, createdAt: original.createdAt, updatedAt: original.updatedAt)
    try save(outside, fixture: f)
    XCTAssertThrowsError(try f.records.recordLocalCareModelReview(f.approval, arguments: input(f, original), now: f.now))
  }

  func testActualCloudLoopCorrectsUnknownReferenceUsingTheSavedQuestionReceipt() async throws {
    let f = try HealthModelReviewFixture(questionFollowUp: true)
    let model = try XCTUnwrap(f.approval.model)
    let contact = GalaxySSIContact(id: "provider", galaxySSIId: "provider", name: "Fixture", displayName: "Fixture",
      type: "agent", agentKind: "cloud-api", deliveryMode: .cloudAPI, trustState: .verified, desktopId: "", desktopName: "",
      identityFingerprint: "", setupStatus: "ready", setupDetail: "", cloudProvider: "Custom", cloudModels: [model],
      selectedCloudModelId: model.id, deleted: false, createdAt: f.now, updatedAt: f.now)
    func call(_ name: String, _ args: AgentMcpJSONObject) -> Data {
      Data(AgentMcpJSONCodec.stringify(["choices": .array([.object(["finish_reason": .string("tool_calls"),
        "message": .object(["role": .string("assistant"), "tool_calls": .array([.object([
          "id": .string(UUID().uuidString), "type": .string("function"), "function": .object([
            "name": .string(name), "arguments": .string(AgentMcpJSONCodec.stringify(args))])])])])])])]).utf8)
    }
    var unknown = try f.arguments(); unknown["decision"] = .string("CLARIFY")
    unknown["questions"] = .array([Review.Reference(id: UUID(), revision: 1).payload])
    var count = 0
    let final = try await GalaxySSIHealthScopedReadTransport.finish(f.approval, records: f.records,
      initial: call(Review.function, unknown), request: GalaxySSIHealthCareDiscussion.request(f.approval, key: "fixture-api-key"),
      style: .openAICompatible, ledger: InMemoryAgentDataDisclosureStore(), currentDestination: { contact }, send: { request in
        count += 1
        let body = try JSONDecoder().decode(AgentMcpJSONObject.self, from: XCTUnwrap(request.httpBody))
        let text = try XCTUnwrap(body["messages"]?.arrayValue?.last?.objectValue?["content"]?.strictStringValue)
        let receipt = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(text.utf8))
        if count == 1 {
          XCTAssertEqual(receipt["error"], .string("invalid_health_review"))
          XCTAssertNil(try f.records.load().localCareModelReviews?[f.approval.id])
          return call(Questions.tool, self.proposal)
        }
        if count == 2 {
          let row = try XCTUnwrap(receipt["questions"]?.arrayValue?.first?.objectValue)
          var corrected = try f.arguments(); corrected["decision"] = .string("CLARIFY")
          corrected["questions"] = .array([.object(["id": try XCTUnwrap(row["id"]), "revision": try XCTUnwrap(row["revision"])])])
          return call(Review.function, corrected)
        }
        XCTAssertEqual(receipt["questions_created"], .bool(false))
        XCTAssertEqual(receipt["question_references"]?.arrayValue?.count, 1)
        return Data(#"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Synthetic referenced clarification"}}]}"#.utf8)
      })
    XCTAssertEqual(count, 3)
    try f.records.finishLocalCareDiscussionTurn(f.approval,
      answer: GalaxySSIHealthFollowUpTransport.output(final, style: .openAICompatible), now: f.now)
    XCTAssertEqual(try f.records.load().localCareResearch?.jobs[f.concern.id.uuidString]?.state, .completed)
    XCTAssertEqual(try f.records.load().localCareModelReviews?[f.approval.id]?.input.questions?.count, 1)
  }
}
