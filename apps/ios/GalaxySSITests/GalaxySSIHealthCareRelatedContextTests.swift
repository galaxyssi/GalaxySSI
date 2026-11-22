import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthCareRelatedContextTests: XCTestCase {
  typealias Related = GalaxySSIHealthCareRelatedContext

  func testNormalMeasurementsAreSelectableWithoutCreatingConcerns() throws {
    let f = try HealthModelReviewFixture(selected: [.weight, .bloodPressure])
    let archive = try f.records.load()
    XCTAssertNil(archive.localCare?.current["weight"])
    XCTAssertEqual(Set(try f.records.relatedLocalCareOptions(primary: .glucose).map(\.metric)),
      [.weight, .bloodPressure, .heartRate])
    let payload = try f.approval.providerPayload(now: f.now)
    XCTAssertTrue(payload.contains("kg")); XCTAssertTrue(payload.contains("mmHg"))
    XCTAssertFalse(payload.contains("heartRate"))
    XCTAssertFalse(payload.contains("bluetoothReceipt")); XCTAssertFalse(payload.contains("tableSource"))
    XCTAssertEqual(Set(f.approval.relatedMeasurements.keys), ["weight", "bloodPressure"])
  }

  func testSelectedSourceChangeRejectsReadsBeforeReconciliationAndCreatesOneJob() throws {
    let f = try HealthModelReviewFixture(selected: [.weight])
    let old = try XCTUnwrap(f.approval.research)
    let cursor = try XCTUnwrap(f.approval.relatedHistory["weight"]?.recent.cursor)
    try f.records.write(.init(metric: .weight, measuredAt: f.now.addingTimeInterval(-1), value: 71))
    XCTAssertThrowsError(try f.records.readRelatedLocalCareHistory(f.approval, metric: .weight, after: cursor, now: f.now))
    XCTAssertThrowsError(try f.records.recordLocalCareModelReview(f.approval, arguments: f.arguments(), now: f.now))
    let next = try XCTUnwrap(f.records.reconcileLocalCareResearch(now: f.now).first?.1)
    XCTAssertNotEqual(next.id, old.id); XCTAssertNotEqual(next.trigger, old.trigger)
    for _ in 0..<3 {
      XCTAssertEqual(try f.records.reconcileLocalCareResearch(now: f.now).first?.1, next)
    }
  }

  func testUnselectedSourceChangeDoesNotInvalidateOrRestart() throws {
    let f = try HealthModelReviewFixture(selected: [.weight])
    try f.records.write(.init(metric: .heartRate, measuredAt: f.now.addingTimeInterval(-1), value: 73))
    try f.records.validateLocalCareDiscussionTurn(f.approval, now: f.now)
    XCTAssertTrue(try f.records.reconcileLocalCareResearch(now: f.now).isEmpty)
    XCTAssertEqual(try f.records.load().localCareResearch?.jobs[f.concern.id.uuidString]?.id, f.approval.id)
  }

  func testCombinedAssessmentRequiresPrimaryAndOnlySelectedReferences() throws {
    let f = try HealthModelReviewFixture(selected: [.weight, .bloodPressure])
    let archive = try f.records.load()
    let weight = try XCTUnwrap(Related.measurement(.weight, archive: archive, now: f.now).record)
    let foreign = try XCTUnwrap(Related.measurement(.heartRate, archive: archive, now: f.now).record)
    var input = try f.arguments()
    input["records"] = .array([GalaxySSIHealthCareModelReview.Reference(weight).payload])
    XCTAssertThrowsError(try f.records.recordLocalCareModelReview(f.approval, arguments: input, now: f.now))
    input = try f.arguments()
    input["records"] = .array((try f.arguments()["records"]?.arrayValue ?? []) +
      [GalaxySSIHealthCareModelReview.Reference(foreign).payload])
    XCTAssertThrowsError(try f.records.recordLocalCareModelReview(f.approval, arguments: input, now: f.now))
    input["records"] = .array(f.records.localCareReviewReferences(f.concern,
      related: f.approval.relatedMeasurements, archive: archive, now: f.now).map(\.payload))
    let saved = try f.records.recordLocalCareModelReview(f.approval, arguments: input, now: f.now)
    XCTAssertEqual(saved.relatedMeasurements, f.approval.relatedMeasurements)
    XCTAssertEqual(try f.records.recordLocalCareModelReview(f.approval, arguments: input, now: f.now), saved)
    let reopened = GalaxySSIHealthRecords(owner: f.records.owner, secrets: f.secrets, isolatedFile: f.file)
    XCTAssertEqual(try reopened.load().localCareModelReviews?[saved.id], saved)
  }

  func testSelectedChangesInvalidateCompletedAssessmentAndAttentionReceipt() throws {
    let f = try HealthModelReviewFixture(selected: [.weight])
    var input = try f.arguments(); input["attention_requested"] = .bool(true)
    let review = try f.records.recordLocalCareModelReview(f.approval, arguments: input, now: f.now)
    try f.records.finishLocalCareDiscussionTurn(f.approval, answer: "Synthetic completed review", now: f.now)
    let notice = try XCTUnwrap(f.records.load().localCareModelAttention?[f.concern.id])
    XCTAssertTrue(f.records.modelAttentionCurrent(notice, now: f.now))
    try f.records.write(.init(metric: .weight, measuredAt: f.now.addingTimeInterval(-1), value: 71))
    XCTAssertFalse(f.records.localCareModelReviewIsCurrent(review, now: f.now))
    XCTAssertFalse(f.records.modelAttentionCurrent(notice, now: f.now))
  }

  func testPendingPlanCannotBeAdoptedAfterSelectedRecordChanges() throws {
    let f = try HealthModelReviewFixture(plan: true, selected: [.weight])
    try f.records.saveLocalCarePlan(f.approval, arguments: f.planArguments(), now: f.now)
    let plan = try XCTUnwrap(f.records.load().localCarePlans?[f.approval.id.uuidString])
    XCTAssertEqual(plan.relatedMeasurements, f.approval.relatedMeasurements)
    try f.records.write(.init(metric: .weight, measuredAt: f.now.addingTimeInterval(-1), value: 71))
    XCTAssertThrowsError(try f.records.validateLocalCarePlanReview(plan, now: f.now))
    XCTAssertThrowsError(try f.records.resolveLocalCarePlan(plan, selected: [0],
      currentDestination: f.approval.destinationDigest, now: f.now))
    XCTAssertEqual(try f.records.load().localCarePlans?[plan.id.uuidString]?.state, .pending)
  }

  func testRelatedHistoryHasIndependentCursorsAndPreservesUnitsAndReferences() throws {
    let f = try HealthModelReviewFixture(selected: [.weight, .bloodPressure])
    let page = try XCTUnwrap(f.approval.relatedHistory["weight"]?.recent)
    XCTAssertEqual(page.payload["samples"]?.arrayValue?.count, 30)
    let token = try XCTUnwrap(page.token)
    XCTAssertTrue(page.authorizes(["input_version": .string(f.approval.id.uuidString), "cursor": .string(token)], turn: f.approval.id))
    XCTAssertFalse(page.authorizes(["input_version": .string(UUID().uuidString), "cursor": .string(token)], turn: f.approval.id))
    let older = try f.records.readRelatedLocalCareHistory(f.approval, metric: .weight,
      after: XCTUnwrap(page.cursor), now: f.now)
    XCTAssertEqual(older.rows.count, 5)
    XCTAssertTrue(older.rows.allSatisfy { $0.unit == "kg" && $0.record.revision > 0 })
    XCTAssertThrowsError(try f.records.readRelatedLocalCareHistory(f.approval, metric: .bloodPressure,
      after: XCTUnwrap(page.cursor), now: f.now))
    XCTAssertThrowsError(try f.records.readRelatedLocalCareHistory(f.approval, metric: .heartRate,
      after: XCTUnwrap(page.cursor), now: f.now))
  }

  func testRevokingStandingConsentInvalidatesRelatedPendingPlansWithoutDeletingThem() throws {
    let f = try HealthModelReviewFixture(plan: true, selected: [.weight])
    try f.records.saveLocalCarePlan(f.approval, arguments: f.planArguments(), now: f.now)
    let plan = try XCTUnwrap(f.records.load().localCarePlans?[f.approval.id.uuidString])
    try f.records.revokeLocalCareResearch(f.concern.id)
    XCTAssertThrowsError(try f.records.validateLocalCarePlanReview(plan, now: f.now))
    XCTAssertEqual(try f.records.load().localCarePlans?[plan.id.uuidString], plan)
  }

  func testActualCloudLoopReadsSelectedHistoryOnlyOnItsOpaqueEntryRequest() async throws {
    let f = try HealthModelReviewFixture(selected: [.weight])
    let model = try XCTUnwrap(f.approval.model)
    let contact = GalaxySSIContact(id: "provider", galaxySSIId: "provider", name: "Fixture", displayName: "Fixture",
      type: "agent", agentKind: "cloud-api", deliveryMode: .cloudAPI, trustState: .verified, desktopId: "", desktopName: "",
      identityFingerprint: "", setupStatus: "ready", setupDetail: "", cloudProvider: "Custom", cloudModels: [model],
      selectedCloudModelId: model.id, deleted: false, createdAt: f.now, updatedAt: f.now)
    let history = try XCTUnwrap(f.approval.relatedHistory["weight"])
    let entry = try XCTUnwrap(history.entryArguments(turn: f.approval.id))
    let payload = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(f.approval.providerPayload(now: f.now).utf8))
    let initial = try XCTUnwrap(payload["selected_measurement_history"]?.arrayValue?.first?.objectValue)
    XCTAssertNil(initial["samples"])
    XCTAssertEqual(initial["next"], .object(entry))
    func call(_ args: AgentMcpJSONObject) -> Data {
      Data(AgentMcpJSONCodec.stringify(["choices": .array([.object(["finish_reason": .string("tool_calls"),
        "message": .object(["role": .string("assistant"), "tool_calls": .array([.object([
          "id": .string(UUID().uuidString), "type": .string("function"), "function": .object([
            "name": .string(GalaxySSIHealthCareHistoryTool.function), "arguments": .string(AgentMcpJSONCodec.stringify(args))])])])])])])]).utf8)
    }
    var received = 0
    _ = try await GalaxySSIHealthScopedReadTransport.finish(f.approval, records: f.records,
      initial: call(entry), request: GalaxySSIHealthCareDiscussion.request(f.approval, key: "fixture-api-key"),
      style: .openAICompatible, ledger: InMemoryAgentDataDisclosureStore(), currentDestination: { contact }, send: { request in
        received += 1
        let body = try JSONDecoder().decode(AgentMcpJSONObject.self, from: XCTUnwrap(request.httpBody))
        let outputText = try XCTUnwrap(body["messages"]?.arrayValue?.last?.objectValue?["content"]?.strictStringValue)
        let page = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(outputText.utf8))
        XCTAssertEqual(page["metric"], .string("weight"))
        XCTAssertEqual(page["samples"]?.arrayValue?.count, received == 1 ? 30 : 5)
        if received == 1 { return call(try XCTUnwrap(page["next"]?.objectValue)) }
        return Data(#"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Synthetic scoped history read"}}]}"#.utf8)
      })
    XCTAssertEqual(received, 2)
  }

  func testForgedPayloadCannotBroadenReviewedConsent() throws {
    let f = try HealthModelReviewFixture(selected: [.weight])
    var forged = f.approval
    forged.relatedPayload["other_conversations_included"] = .bool(true)
    XCTAssertThrowsError(try f.records.validateLocalCareDiscussionTurn(forged, now: f.now))
    forged = f.approval
    forged.relatedMeasurements["heartRate"] = String(repeating: "a", count: 64)
    XCTAssertThrowsError(try f.records.validateLocalCareDiscussionTurn(forged, now: f.now))
    XCTAssertThrowsError(try Related.metrics(["unknown": String(repeating: "a", count: 64)]))
    XCTAssertThrowsError(try Related.metrics(["weight": "bad-hash"]))
  }

  func testWithdrawnMeasurementsDoNotReturnThroughPrivateReplies() throws {
    let f = try HealthModelReviewFixture(selected: [.weight])
    var thread = try XCTUnwrap(f.records.load().localCareDiscussions?[f.concern.id.uuidString])
    thread.turns = [.init(id: UUID(), question: "Synthetic weight question", destination: f.approval.destinationDigest,
      answer: "Synthetic weight answer", relatedMeasurements: f.approval.relatedMeasurements)]
    let redacted = try GalaxySSIHealthCareDiscussion.payload(concern: f.concern, question: "Review glucose only",
      thread: thread, destination: f.approval.destinationDigest)
    XCTAssertFalse(redacted.contains("Synthetic weight answer"))
    let retained = try GalaxySSIHealthCareDiscussion.payload(concern: f.concern, question: "Review selected metrics",
      thread: thread, destination: f.approval.destinationDigest, relatedMeasurements: f.approval.relatedMeasurements)
    XCTAssertTrue(retained.contains("Synthetic weight answer"))
    XCTAssertEqual(thread.turns.count, 1)
  }

  func testWithdrawnMeasurementQuestionsStayVisibleLocallyButCannotReachTheModel() throws {
    var ledger = GalaxySSIHealthCareQuestions.Ledger()
    let now = Date()
    try ledger.propose([.init(key: "context.weight", question: "Synthetic weight context?", purpose: "Fixture")],
      scope: "scope", basis: "basis", known: [:], turn: UUID(), now: now, relatedMeasurements: ["weight"])
    XCTAssertEqual(try ledger.page(scope: "scope", basis: "basis", known: [:], after: nil).rows.count, 1)
    XCTAssertTrue(try ledger.page(scope: "scope", basis: "basis", known: [:], after: nil,
      allowedRelatedMeasurements: []).rows.isEmpty)
    XCTAssertEqual(try ledger.page(scope: "scope", basis: "basis", known: [:], after: nil,
      allowedRelatedMeasurements: ["weight"]).rows.count, 1)
  }

  func testPriorAssessmentCannotReintroduceWithdrawnMeasurements() throws {
    let f = try HealthModelReviewFixture(selected: [.weight])
    let saved = try f.records.recordLocalCareModelReview(f.approval, arguments: f.arguments(), now: f.now)
    var next = saved.authorization
    var job = try XCTUnwrap(f.approval.research); job.id = UUID()
    XCTAssertTrue(saved.reusable(for: next, job: job))
    next.relatedMeasurements = nil
    XCTAssertFalse(saved.reusable(for: next, job: job))
  }

  func testPairedDesktopReceivesOnlySelectedReadOnlyMeasurementContext() throws {
    let f = try HealthModelReviewFixture(paired: true, selected: [.weight])
    let prompt = try GalaxySSIHealthDesktopResearch.prompt(f.approval)
    XCTAssertTrue(prompt.contains("weight")); XCTAssertTrue(prompt.contains("kg"))
    XCTAssertFalse(prompt.contains("heartRate"))
    XCTAssertTrue(prompt.contains("Do not use tools"))
    let review = try f.records.recordLocalCareModelReview(f.approval, arguments: f.arguments(), now: f.now)
    XCTAssertEqual(review.relatedMeasurements, f.approval.relatedMeasurements)
  }

  func testLegacyAuthorizationHasNoImplicitAdditionalMeasurementConsent() throws {
    let f = try HealthModelReviewFixture()
    let saved = try XCTUnwrap(f.records.load().localCareResearch?.authorizations[f.concern.id.uuidString])
    let bytes = try JSONEncoder().encode(saved)
    XCTAssertEqual(try JSONDecoder().decode(GalaxySSIHealthCareResearch.Authorization.self, from: bytes), saved)
    XCTAssertNil(saved.relatedMeasurements)
    XCTAssertTrue(f.approval.relatedHistory.isEmpty)
    XCTAssertFalse(try f.approval.providerPayload(now: f.now).contains("related_measurements"))
  }

  func testMissingSelectedInputIsCorrectableWithoutInsertingReferences() throws {
    let f = try HealthModelReviewFixture(selected: [.weight, .bloodPressure])
    var missing = try f.arguments()
    missing["records"] = .array(GalaxySSIHealthCareModelReview.references(f.concern).map(\.payload))
    let original = missing
    XCTAssertThrowsError(try f.records.recordLocalCareModelReview(f.approval, arguments: missing, now: f.now)) { error in
      guard let failure = error as? GalaxySSIHealthRecords.Failure else { return XCTFail("Wrong failure type") }
      XCTAssertEqual(GalaxySSIHealthCareModelReview.failure(failure)?["error"], .string("invalid_health_review"))
    }
    XCTAssertEqual(missing, original)
    XCTAssertNil(try f.records.load().localCareModelReviews?[f.approval.id])
    let repaired = try f.records.recordLocalCareModelReview(f.approval, arguments: f.arguments(), now: f.now)
    XCTAssertEqual(repaired.input.records.count, 3)
    XCTAssertEqual(repaired.input.payload["records"], try f.arguments()["records"])
  }

  func testOmittingOneOfSeveralSelectedInputsIsAlsoRejected() throws {
    let f = try HealthModelReviewFixture(selected: [.weight, .bloodPressure])
    let pressure = try XCTUnwrap(GalaxySSIHealthCareRelatedContext.measurement(.bloodPressure,
      archive: f.records.load(), now: f.now).record)
    var input = try f.arguments()
    input["records"] = .array((input["records"]?.arrayValue ?? []).filter {
      $0 != GalaxySSIHealthCareModelReview.Reference(pressure).payload
    })
    XCTAssertThrowsError(try f.records.recordLocalCareModelReview(f.approval, arguments: input, now: f.now)) { error in
      guard let failure = error as? GalaxySSIHealthRecords.Failure else { return XCTFail("Wrong failure type") }
      XCTAssertEqual(GalaxySSIHealthCareModelReview.failure(failure)?["error"], .string("invalid_health_review"))
    }
    XCTAssertNil(try f.records.load().localCareModelReviews?[f.approval.id])
  }

  func testUnavailableSelectedMetricDoesNotRequireInventedReference() throws {
    let f = try HealthModelReviewFixture(selected: [.weight, .height])
    let archive = try f.records.load()
    XCTAssertNil(GalaxySSIHealthCareRelatedContext.measurement(.height, archive: archive, now: f.now).record)
    XCTAssertEqual(f.records.requiredLocalCareReviewReferences(f.concern, related: f.approval.relatedMeasurements,
      archive: archive, now: f.now).count, 2)
    let review = try f.records.recordLocalCareModelReview(f.approval, arguments: f.arguments(), now: f.now)
    XCTAssertEqual(review.input.records.count, 2)
  }

  func testRequiredSelectedReferencesCannotBeTruncatedByLongPrimaryBaseline() throws {
    let f = try HealthModelReviewFixture(selected: [.weight, .bloodPressure])
    var concern = f.concern
    let source = concern.assessment
    let baseline = (0..<30).map { _ in
      GalaxySSIHealthCare.Record(GalaxySSIHealthReading(revision: 1, metric: .glucose, value: 100))
    }
    concern.assessment = .init(record: source.record, measuredAt: source.measuredAt, result: source.result,
      unit: source.unit, reference: source.reference, signals: source.signals, guidelineVersion: source.guidelineVersion,
      baseline: .init(records: baseline, low: 90, high: 110))
    let archive = try f.records.load()
    let required = f.records.requiredLocalCareReviewReferences(concern, related: f.approval.relatedMeasurements,
      archive: archive, now: f.now)
    let allowed = f.records.localCareReviewReferences(concern, related: f.approval.relatedMeasurements,
      archive: archive, now: f.now)
    XCTAssertEqual(required.count, 3); XCTAssertEqual(allowed.count, 30)
    XCTAssertTrue(Set(required).isSubset(of: Set(allowed)))
  }

  func testActualCloudLoopCanRepairMissingSelectedReferencesWithinSameTurn() async throws {
    let f = try HealthModelReviewFixture(selected: [.weight, .bloodPressure])
    let model = try XCTUnwrap(f.approval.model)
    let contact = GalaxySSIContact(id: "provider", galaxySSIId: "provider", name: "Fixture", displayName: "Fixture",
      type: "agent", agentKind: "cloud-api", deliveryMode: .cloudAPI, trustState: .verified, desktopId: "", desktopName: "",
      identityFingerprint: "", setupStatus: "ready", setupDetail: "", cloudProvider: "Custom", cloudModels: [model],
      selectedCloudModelId: model.id, deleted: false, createdAt: f.now, updatedAt: f.now)
    func call(_ input: AgentMcpJSONObject) -> Data {
      Data(AgentMcpJSONCodec.stringify(["choices": .array([.object(["finish_reason": .string("tool_calls"),
        "message": .object(["role": .string("assistant"), "tool_calls": .array([.object([
          "id": .string(UUID().uuidString), "type": .string("function"), "function": .object([
            "name": .string(GalaxySSIHealthCareModelReview.function), "arguments": .string(AgentMcpJSONCodec.stringify(input))])])])])])])]).utf8)
    }
    var missing = try f.arguments()
    missing["records"] = .array(GalaxySSIHealthCareModelReview.references(f.concern).map(\.payload))
    let corrected = call(try f.arguments())
    var steps = 0
    let final = try await GalaxySSIHealthScopedReadTransport.finish(f.approval, records: f.records,
      initial: call(missing), request: GalaxySSIHealthCareDiscussion.request(f.approval, key: "fixture-api-key"),
      style: .openAICompatible, ledger: InMemoryAgentDataDisclosureStore(), currentDestination: { contact }, send: { request in
        steps += 1
        let text = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        if steps == 1 {
          XCTAssertNil(try f.records.load().localCareModelReviews?[f.approval.id])
          XCTAssertTrue(text.contains("invalid_health_review"))
          XCTAssertTrue(text.contains("EVERY available selected"))
          XCTAssertFalse(text.contains("health_review_scope_changed"))
          return corrected
        }
        XCTAssertEqual(try f.records.load().localCareModelReviews?[f.approval.id]?.input.records.count, 3)
        return Data(#"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Corrected input provenance"}}]}"#.utf8)
      })
    XCTAssertEqual(steps, 2)
    try f.records.finishLocalCareDiscussionTurn(f.approval,
      answer: GalaxySSIHealthFollowUpTransport.output(final, style: .openAICompatible), now: f.now)
    XCTAssertEqual(try f.records.load().localCareResearch?.jobs[f.concern.id.uuidString]?.state, .completed)
    XCTAssertTrue(try f.records.load().localCareFollowUps?.isEmpty ?? true)
    XCTAssertTrue(try f.records.load().localCare?.current["glucose"]?.adoptedActions?.isEmpty ?? true)
  }
}
