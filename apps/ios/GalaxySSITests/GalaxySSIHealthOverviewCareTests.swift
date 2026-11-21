import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthOverviewCareTests: XCTestCase {
  typealias Care = GalaxySSIHealthOverviewCare

  func testOverviewIsReadOnlyAndDoesNotReconcileMissingConcerns() throws {
    let f = try Fixture(reconcile: false)
    let before = try Data(contentsOf: f.file)
    let overview = try f.records.localCareOverview(now: f.now)
    XCTAssertTrue(overview.enabled)
    XCTAssertTrue(overview.concerns.isEmpty)
    XCTAssertTrue(overview.actions.isEmpty)
    XCTAssertNil(try f.records.load().localCare)
    XCTAssertEqual(try Data(contentsOf: f.file), before)
  }

  func testConcernAndNoActionsDoNotRequireOnlineProfileAnalysisPermission() throws {
    let f = try Fixture()
    let before = try Data(contentsOf: f.file)
    let overview = try f.records.localCareOverview(now: f.now)
    XCTAssertNil(try f.records.load().profileAnalysisPermission)
    XCTAssertEqual(overview.concerns.count, 1)
    XCTAssertFalse(try XCTUnwrap(overview.concerns.first).sourceChanged)
    XCTAssertTrue(overview.actionsReady)
    XCTAssertTrue(overview.actions.isEmpty)
    XCTAssertNil(overview.upcoming)
    XCTAssertEqual(try Data(contentsOf: f.file), before)
  }

  func testSummaryRevocationHidesRetainedCareData() throws {
    let f = try Fixture()
    try f.records.setPrivacy(.overview, enabled: false)
    let overview = try f.records.localCareOverview(now: f.now)
    XCTAssertFalse(overview.permitted)
    XCTAssertTrue(overview.concerns.isEmpty)
    XCTAssertTrue(overview.visits.isEmpty)
    XCTAssertTrue(overview.actions.isEmpty)
  }

  func testCareRevocationHidesRetainedDataAndRenewalRotatesEpoch() throws {
    let f = try Fixture()
    let previous = try f.records.localCareOverview(now: f.now).permission
    try f.records.setPrivacy(.localCare, enabled: false)
    let disabled = try f.records.localCareOverview(now: f.now)
    XCTAssertFalse(disabled.enabled)
    XCTAssertTrue(disabled.concerns.isEmpty)
    XCTAssertNil(disabled.permission)
    try f.records.setPrivacy(.localCare, enabled: true)
    XCTAssertNotEqual(try f.records.localCareOverview(now: f.now).permission, previous)
  }

  func testSourceChangesAreMarkedWithoutRewritingConcern() throws {
    let f = try Fixture()
    let concern = try f.concern()
    try f.records.write(.init(metric: .glucose, measuredAt: f.now, value: 135, unitOverride: "mg/dL"))
    let before = try Data(contentsOf: f.file)
    let item = try XCTUnwrap(f.records.localCareOverview(now: f.now).concerns.first)
    XCTAssertTrue(item.sourceChanged)
    XCTAssertEqual(item.revision, concern.revision)
    XCTAssertEqual(try Data(contentsOf: f.file), before)
  }

  func testVisitPreviewKeepsExactIDAndRecordedTimeZone() throws {
    let f = try Fixture()
    let concern = try f.concern()
    let stamp = try f.records.localCareEncounterPage(id: concern.id, metric: .glucose, now: f.now).stamp
    var draft = GalaxySSIHealthEncounter.Draft()
    draft.purpose = "Synthetic visit"; draft.state = .booked; draft.zone = "Asia/Tokyo"
    draft.plannedAt = f.now.addingTimeInterval(86_400)
    let saved = try f.records.saveLocalCareEncounter(draft, id: UUID(), operation: UUID(), expected: stamp,
      expectedEntry: nil, now: f.now).entry
    let preview = try XCTUnwrap(f.records.localCareOverview(now: f.now).visits.first)
    XCTAssertEqual(preview.id, saved.id)
    XCTAssertEqual(preview.concern, concern.id)
    XCTAssertEqual(preview.entry.details.zone, "Asia/Tokyo")
    XCTAssertEqual(preview.at, draft.plannedAt)
    XCTAssertNil(preview.journal)
  }

  func testLatestVisitUsesRevisionBeforeClockAndCancellationDoesNotResurrectOldVisit() {
    let concern = UUID()
    let old = visit(concern: concern, revision: 3, updated: 900, state: .booked)
    let cancelled = visit(concern: concern, revision: 4, updated: 800, state: .cancelled)
    XCTAssertNil(Care.latestVisit([old, cancelled], concern: concern))
    let latest = visit(concern: concern, revision: 5, updated: 700, state: .attended)
    XCTAssertEqual(Care.latestVisit([old, cancelled, latest], concern: concern)?.id, latest.id)
    XCTAssertNil(Care.latestVisit([latest], concern: UUID()))
  }

  func testActionWithoutPlannedDateAndReviewOrRecordedRowsAreNotCurrentActions() {
    let now = Date(timeIntervalSince1970: 1_000)
    XCTAssertNil(Care.Action(item(planned: nil), now: now))
    XCTAssertNil(Care.Action(item(planned: now, bucket: .review), now: now))
    XCTAssertNil(Care.Action(item(planned: now, bucket: .recorded), now: now))
  }

  func testActionDeadlineControlsOverdueButNotNormalPlannedTime() throws {
    let planned = Date(timeIntervalSince1970: 1_000), deadline = planned.addingTimeInterval(600)
    let input = item(planned: planned, deadline: deadline)
    let before = try XCTUnwrap(Care.Action(input, now: planned.addingTimeInterval(100)))
    XCTAssertFalse(before.overdue)
    XCTAssertEqual(before.due, planned)
    let exact = try XCTUnwrap(Care.Action(input, now: deadline))
    XCTAssertFalse(exact.overdue)
    let after = try XCTUnwrap(Care.Action(input, now: deadline.addingTimeInterval(1)))
    XCTAssertTrue(after.overdue)
    XCTAssertEqual(after.due, deadline)
    XCTAssertEqual(after.actionID, input.action?.id)
    XCTAssertEqual(after.concern, input.scope.concern)
  }

  func testExactActionLookupRejectsUnknownScopeInsteadOfOpeningFirstAction() throws {
    let f = try Fixture()
    let concern = try f.concern()
    XCTAssertThrowsError(try f.records.localCareAgendaAction(scope: .init(concern: concern.id, metric: .glucose),
      actionID: "missing", now: f.now))
    XCTAssertThrowsError(try f.records.localCareAgendaAction(scope: .init(concern: UUID(), metric: .glucose),
      actionID: "missing", now: f.now))
  }

  func testConfirmedActionsAreBoundedAndExactLookupDoesNotReturnFirstAction() throws {
    let f = try Fixture()
    try f.adopt(count: 5, due: f.now.addingTimeInterval(120))
    let overview = try f.records.localCareOverview(now: f.now)
    XCTAssertEqual(overview.actions.count, Care.previewLimit)
    XCTAssertTrue(overview.actionsReady)
    XCTAssertNil(overview.upcoming)
    let action = try XCTUnwrap(overview.actions.last)
    let page = try f.records.localCareAgendaAction(scope: .init(concern: action.concern, metric: action.metric),
      actionID: action.actionID, now: f.now)
    XCTAssertEqual(page.items.count, 1)
    XCTAssertEqual(page.items.first?.action?.id, action.actionID)
    XCTAssertNil(page.next)
    let concern = try f.concern()
    try f.records.reviewLocalCare(concern, stage: .paused, reason: "Synthetic pause", now: f.now)
    XCTAssertTrue(try f.records.localCareOverview(now: f.now).actions.isEmpty)
    XCTAssertThrowsError(try f.records.localCareAgendaAction(scope: .init(concern: action.concern, metric: action.metric),
      actionID: action.actionID, now: f.now))
  }

  func testFutureActionBecomesTodayAcrossLocalDayBoundaryAndSourceChangeRemovesIt() throws {
    let f = try Fixture()
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    let boundary = try XCTUnwrap(calendar.dateInterval(of: .day, for: f.now)?.end)
    let due = boundary.addingTimeInterval(3600)
    try f.adopt(count: 1, due: due)
    let first = try f.records.localCareOverview(calendar: calendar, now: f.now)
    XCTAssertTrue(first.actions.isEmpty)
    XCTAssertNotNil(first.upcoming)
    let next = try f.records.localCareOverview(calendar: calendar, now: boundary)
    XCTAssertEqual(next.actions.count, 1)
    XCTAssertNil(next.upcoming)
    try f.records.write(.init(metric: .glucose, measuredAt: f.now, value: 135, unitOverride: "mg/dL"))
    let changed = try f.records.localCareOverview(calendar: calendar, now: boundary)
    XCTAssertTrue(changed.actions.isEmpty)
    XCTAssertNil(changed.upcoming)
    XCTAssertTrue(try XCTUnwrap(changed.concerns.first).sourceChanged)
  }

  private func item(planned: Date?, deadline: Date? = nil, bucket: GalaxySSIHealthCareAgenda.Bucket = .planned)
      -> GalaxySSIHealthCareAgenda.Item {
    let action = GalaxySSIHealthCarePlan.AdoptedAction(proposalID: UUID(),
      action: .init(id: 1, kind: .recheck, description: "Synthetic action", rationale: "Review", sourceIndex: 0,
        dueFrom: planned, dueUntil: deadline),
      source: .init(title: "Synthetic source", url: URL(string: "https://example.invalid/source")!, version: "1", applicability: "Review"),
      confirmedAt: Date(timeIntervalSince1970: 500))
    return .init(scope: .init(concern: UUID(), metric: .glucose), revision: 4, action: action,
      reminder: nil, plannedAt: planned, bucket: bucket, canRecord: true)
  }

  private func visit(concern: UUID, revision: Int, updated: TimeInterval, state: GalaxySSIHealthEncounter.State)
      -> GalaxySSIHealthEncounter.Entry {
    var draft = GalaxySSIHealthEncounter.Draft(); draft.state = state; draft.purpose = "Synthetic visit"
    return .init(id: UUID(), concern: concern, revision: revision, source: nil,
      created: Date(timeIntervalSince1970: 100), updated: Date(timeIntervalSince1970: updated), details: draft)
  }

  @MainActor
  private final class Fixture {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let records: GalaxySSIHealthRecords
    let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    init(reconcile: Bool = true) throws {
      records = GalaxySSIHealthRecords(owner: "overview-care", secrets: InMemorySecretStore(), isolatedFile: file)
      try records.write(.init(metric: .glucose, measuredAt: now.addingTimeInterval(-120), value: 110, unitOverride: "mg/dL"))
      try records.setPrivacy(.overview, enabled: true)
      try records.setPrivacy(.localCare, enabled: true)
      if reconcile { try records.reconcileLocalCare(now: now) }
    }
    func concern() throws -> GalaxySSIHealthCare.Concern { try XCTUnwrap(records.load().localCare?.current["glucose"]) }
    func adopt(count: Int, due: Date) throws {
      let concern = try concern()
      try records.setHealthOnlinePermission(true)
      _ = try records.openLocalCareDiscussion(id: concern.id, metric: .glucose)
      let model = CloudModelConfig(id: "fixture", displayName: "Fixture", provider: "Custom", modelId: "model",
        endpoint: "https://example.test/v1/chat/completions", apiStyle: .openAICompatible, keychainAccount: "", updatedAt: now)
      var approval = try records.prepareLocalCareDiscussion(id: concern.id, metric: .glucose, question: "Review follow-up",
        destinationID: "provider", model: model, credential: "fixture-api-key", proposesPlan: true, now: now)
      let source = GalaxySSIHealthCareEvidence.PublicSource.labResults
      let quote = "This synthetic laboratory paragraph is a fixture for exact evidence matching and source review."
      approval.evidence = [try GalaxySSIHealthCareEvidence.fromNativeBody(
        Data("<html><body><article><h1>Fixture</h1><p>\(quote)</p></article></body></html>".utf8),
        source: source, binding: .init(approval), retrievedAt: now, observedAt: now)]
      let date = ISO8601DateFormatter().string(from: due)
      let actions: [AgentMcpJSONValue] = (0..<count).map { index in .object([
        "kind": .string("RECHECK"), "description": .string("Synthetic action \(index)"), "rationale": .string("Review"),
        "source_index": .int(0), "due_from": .string(date), "due_until": .string(date),
        "applicability": .object(["mode": .string("INDIVIDUALIZED"), "checks": .array([.object([
          "field": .string("unit"), "operator": .string("EQUALS"), "expected": .string("mg/dL"), "source_index": .int(0)
        ])]), "missing_information": .array([]), "conflicts": .array([])])
      ]) }
      let arguments: AgentMcpJSONObject = ["uncertainty": .string("Timing requires review"), "actions": .array(actions),
        "sources": .array([.object(["title": .string("Fixture"), "url": .string(source.url.absoluteString),
          "version": .string("2026"), "applicability": .string("Confirm recorded unit"),
          "evidence_id": .string(approval.evidence[0].id.uuidString), "quote": .string(quote)])])]
      try records.beginLocalCareDiscussionTurn(approval, now: now)
      try records.saveLocalCarePlan(approval, arguments: arguments, now: now)
      let proposal = try XCTUnwrap(records.load().localCarePlans?[approval.id.uuidString])
      try records.resolveLocalCarePlan(proposal, selected: Set(0..<count), currentDestination: approval.destinationDigest, now: now)
    }
    deinit { try? FileManager.default.removeItem(at: file) }
  }
}
