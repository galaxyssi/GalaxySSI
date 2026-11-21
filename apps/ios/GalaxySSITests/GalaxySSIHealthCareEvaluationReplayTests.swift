import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthCareEvaluationReplayTests: XCTestCase {
  func testDuplicateFirstEvaluationReturnsCommittedStateWithoutAnotherWrite() throws {
    let f = try EvaluationReplayFixture()
    try f.records.reconcileLocalCare(now: f.now)
    let committed = try f.concern()
    let bytes = try Data(contentsOf: f.file)
    let history = try f.records.localCareHistory(committed.id)
    let other = f.reopen()
    try other.reconcileLocalCare(now: f.now.addingTimeInterval(60))
    XCTAssertEqual(try other.load().localCare?.current["glucose"], committed)
    XCTAssertEqual(try other.localCareHistory(committed.id), history)
    XCTAssertEqual(try Data(contentsOf: f.file), bytes)
  }

  func testDuplicateUpdatedEvaluationDoesNotPublishAnotherRevisionOrComparison() throws {
    let f = try EvaluationReplayFixture()
    try f.records.reconcileLocalCare(now: f.now)
    let original = try f.concern()
    let next = f.now.addingTimeInterval(60)
    try f.records.write(.init(metric: .glucose, measuredAt: next, value: 115, unitOverride: "mg/dL"))
    try f.records.reconcileLocalCare(now: next)
    let updated = try f.concern()
    XCTAssertGreaterThan(updated.revision, original.revision)
    let history = try f.records.localCareHistory(updated.id)
    let bytes = try Data(contentsOf: f.file)
    let other = f.reopen()
    try other.reconcileLocalCare(now: next.addingTimeInterval(60))
    XCTAssertEqual(try other.load().localCare?.current["glucose"], updated)
    XCTAssertEqual(try other.localCareHistory(updated.id), history)
    XCTAssertEqual(try Data(contentsOf: f.file), bytes)
  }

  func testDuplicateEvaluationPreservesLaterUserPause() throws {
    let f = try EvaluationReplayFixture()
    try f.records.reconcileLocalCare(now: f.now)
    let before = try f.concern()
    try f.records.reviewLocalCare(before, stage: .paused, reason: "Synthetic user pause", now: f.now)
    let paused = try f.concern()
    let history = try f.records.localCareHistory(paused.id)
    let bytes = try Data(contentsOf: f.file)
    try f.reopen().reconcileLocalCare(now: f.now.addingTimeInterval(60))
    XCTAssertEqual(try f.concern(), paused)
    XCTAssertEqual(try f.records.localCareHistory(paused.id), history)
    XCTAssertEqual(try Data(contentsOf: f.file), bytes)
    XCTAssertEqual(try f.concern().stage, .paused)
  }

  func testDuplicateEvaluationDoesNotRecreateDeletedConcern() throws {
    let f = try EvaluationReplayFixture()
    try f.records.reconcileLocalCare(now: f.now)
    let concern = try f.concern()
    let source = try f.records.load().current
    try f.records.deleteLocalCare(concern, now: f.now)
    let bytes = try Data(contentsOf: f.file)
    let other = f.reopen()
    try other.reconcileLocalCare(now: f.now.addingTimeInterval(60))
    let archive = try other.load()
    XCTAssertNil(archive.localCare?.current["glucose"])
    XCTAssertNotNil(archive.localCare?.deletedInput["glucose"])
    XCTAssertEqual(archive.current, source)
    XCTAssertEqual(try Data(contentsOf: f.file), bytes)
  }

  func testGenuinelyNewInputCanCreateAConcernAfterUserDeletion() throws {
    let f = try EvaluationReplayFixture()
    try f.records.reconcileLocalCare(now: f.now)
    let old = try f.concern()
    try f.records.deleteLocalCare(old, now: f.now)
    let next = f.now.addingTimeInterval(60)
    try f.records.write(.init(metric: .glucose, measuredAt: next, value: 115, unitOverride: "mg/dL"))
    try f.reopen().reconcileLocalCare(now: next)
    let fresh = try f.concern()
    XCTAssertNotEqual(fresh.id, old.id)
    XCTAssertNotEqual(fresh.assessment.record, old.assessment.record)
    XCTAssertEqual(try f.records.load().current.count, 2)
  }

  func testFreshEvaluationUsesConfirmedContextAndStaleUserEditsStillFail() throws {
    let f = try EvaluationReplayFixture()
    try f.records.reconcileLocalCare(now: f.now)
    let old = try f.concern()
    try f.records.setLocalCareContext(old, applicability: .applicable, now: f.now)
    let confirmed = try f.concern()
    XCTAssertNotNil(confirmed.context)
    XCTAssertNotEqual(old.revision, confirmed.revision)
    let bytes = try Data(contentsOf: f.file)
    let other = f.reopen()
    try other.reconcileLocalCare(now: f.now.addingTimeInterval(60))
    XCTAssertEqual(try f.concern(), confirmed)
    XCTAssertEqual(try Data(contentsOf: f.file), bytes)
    XCTAssertThrowsError(try other.reviewLocalCare(old, stage: .paused, reason: "Obsolete view", now: f.now))
    XCTAssertEqual(try f.concern(), confirmed)
  }

  func testReplayCannotBypassCurrentConsentAndReopenedCallerUsesTheNewEpoch() throws {
    let f = try EvaluationReplayFixture()
    try f.records.reconcileLocalCare(now: f.now)
    let oldEpoch = try XCTUnwrap(f.records.load().localCarePermission)
    let existing = f.reopen()
    try f.records.setPrivacy(.localCare, enabled: false)
    let disabled = try Data(contentsOf: f.file)
    XCTAssertThrowsError(try existing.reconcileLocalCare(now: f.now))
    XCTAssertEqual(try Data(contentsOf: f.file), disabled)
    try f.records.setPrivacy(.localCare, enabled: true)
    let newEpoch = try XCTUnwrap(f.records.load().localCarePermission)
    XCTAssertNotEqual(newEpoch, oldEpoch)
    try existing.reconcileLocalCare(now: f.now)
    XCTAssertEqual(try existing.load().localCarePermission, newEpoch)
    XCTAssertEqual(try existing.load().localCare?.current.count, 1)
  }

  func testTwoTaskCallersWithIndependentStoresPublishOnlyOneInitialConcern() async throws {
    let f = try EvaluationReplayFixture()
    let first = f.records, second = f.reopen(), now = f.now
    // The production API is synchronous and MainActor-isolated, not a cross-process database transaction.
    let left = Task { @MainActor in
      try first.reconcileLocalCare(now: now)
      return try first.load().localCare?.current["glucose"]
    }
    let right = Task { @MainActor in
      try second.reconcileLocalCare(now: now)
      return try second.load().localCare?.current["glucose"]
    }
    let firstValue = try await left.value
    let secondValue = try await right.value
    let a = try XCTUnwrap(firstValue)
    let b = try XCTUnwrap(secondValue)
    XCTAssertEqual(a, b)
    XCTAssertEqual(try f.records.load().localCare?.current.count, 1)
    XCTAssertTrue(try f.records.localCareHistory(a.id).isEmpty)
  }
}

@MainActor
private final class EvaluationReplayFixture {
  let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let secrets = InMemorySecretStore()
  let records: GalaxySSIHealthRecords
  let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))

  init() throws {
    records = GalaxySSIHealthRecords(owner: "evaluation-replay", secrets: secrets, isolatedFile: file)
    try records.write(.init(metric: .glucose, measuredAt: now.addingTimeInterval(-60), value: 110, unitOverride: "mg/dL"))
    try records.setPrivacy(.localCare, enabled: true)
  }

  func reopen() -> GalaxySSIHealthRecords {
    GalaxySSIHealthRecords(owner: records.owner, secrets: secrets, isolatedFile: file)
  }

  func concern() throws -> GalaxySSIHealthCare.Concern {
    try XCTUnwrap(records.load().localCare?.current["glucose"])
  }

  deinit { try? FileManager.default.removeItem(at: file) }
}
