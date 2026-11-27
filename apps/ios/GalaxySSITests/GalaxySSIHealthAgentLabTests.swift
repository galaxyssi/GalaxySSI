import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthAgentLabTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private var calendar: Calendar {
    var result = Calendar(identifier: .gregorian)
    result.timeZone = TimeZone(secondsFromGMT: 0)!
    return result
  }
  private func reading(_ offset: TimeInterval, imported: Bool = false) -> GalaxySSIHealthReading {
    var row = GalaxySSIHealthReading(metric: .glucose, measuredAt: now.addingTimeInterval(offset), value: 8)
    row.referenceInterval = "3-6"
    if imported { row.reportSource = .init(original: UUID(), sha256: String(repeating: "a", count: 64), page: 1, region: 1, fromOCR: true) }
    return row
  }
  func testLatestImportedReportDayPrecedesMoreRecentManualRows() throws {
    let imported = reading(-172_800, imported: true)
    let old = reading(-345_600, imported: true)
    let result = try GalaxySSIHealthAgentLab.snapshot([reading(-60), imported, old], policy: .init(.init()),
      through: now, now: now, calendar: calendar)
    XCTAssertTrue(result.imported)
    XCTAssertEqual(result.rows, [imported])
    XCTAssertEqual(result.olderUntil, calendar.startOfDay(for: imported.measuredAt).addingTimeInterval(-0.001))
  }
  func testManualFallbackExcludesDailyDeletedFutureAndInvalidMeasurements() throws {
    let valid = reading(-60)
    var deleted = reading(-30); deleted.deleted = true
    var invalid = reading(-20); invalid.value = -1
    let daily = GalaxySSIHealthReading(metric: .steps, measuredAt: now, value: 500)
    let result = try GalaxySSIHealthAgentLab.snapshot([valid, deleted, invalid, reading(60), daily],
      policy: .init(.init()), through: now, now: now, calendar: calendar)
    XCTAssertFalse(result.imported)
    XCTAssertEqual(result.rows, [valid])
  }
  func testUnknownReferenceIsNotAWithinRangeOrAbnormalResult() throws {
    var unknown = reading(-60); unknown.referenceInterval = nil
    let high = reading(-30)
    let result = try GalaxySSIHealthAgentLab.snapshot([unknown, high], policy: .init(.init()),
      through: now, now: now, calendar: calendar)
    XCTAssertEqual(result.unknown, 1)
    XCTAssertEqual(result.abnormal, [high])
  }
  func testHistoricalCutoffDoesNotIncludeLaterReportOrLaterSameDayRow() throws {
    let prior = reading(-172_800, imported: true)
    let result = try GalaxySSIHealthAgentLab.snapshot([prior, reading(-60, imported: true)],
      policy: .init(.init()), through: prior.measuredAt, now: now, calendar: calendar)
    XCTAssertEqual(result.rows, [prior])
  }
  func testInvalidOrFutureCutoffFailsClosed() {
    for cutoff in [Date(timeIntervalSince1970: 0), now.addingTimeInterval(1)] {
      XCTAssertThrowsError(try GalaxySSIHealthAgentLab.snapshot([], policy: .init(.init()), through: cutoff, now: now, calendar: calendar))
    }
  }
  @MainActor func testOneTimeReadIsBoundToOwnerPolicyCutoffAndMonotonicExpiry() {
    let policy = GalaxySSIHealthAgentLab.Policy(.init())
    let once = GalaxySSIHealthAgentLab.Once(owner: "synthetic-owner", policy: policy, through: now, uptime: 100)
    XCTAssertFalse(once.claim(owner: "other", policy: policy, through: now, uptime: 100))
    XCTAssertFalse(once.claim(owner: "synthetic-owner", policy: policy, through: now.addingTimeInterval(-1), uptime: 100))
    XCTAssertFalse(once.claim(owner: "synthetic-owner", policy: policy, through: now, uptime: 99))
    XCTAssertFalse(once.claim(owner: "synthetic-owner", policy: policy, through: now, uptime: 161))
    XCTAssertTrue(once.claim(owner: "synthetic-owner", policy: policy, through: now, uptime: 101))
    XCTAssertFalse(once.claim(owner: "synthetic-owner", policy: policy, through: now, uptime: 102))
  }
  @MainActor func testConsentRevocationCannotReuseAOneTimeRead() {
    var archive = GalaxySSIHealthRecords.Archive()
    archive.derivesOverview = false
    let policy = GalaxySSIHealthAgentLab.Policy(archive)
    let once = GalaxySSIHealthAgentLab.Once(owner: "synthetic-owner", policy: policy, through: now, uptime: 100)
    archive.privacyEvents = [.init(at: now, scope: .overview, enabled: false)]
    XCTAssertFalse(once.claim(owner: "synthetic-owner", policy: .init(archive), through: now, uptime: 101))
  }
  func testOldArchiveDoesNotInventAuditOrGrant() throws {
    let archive = try JSONDecoder().decode(GalaxySSIHealthRecords.Archive.self,
      from: JSONEncoder().encode(GalaxySSIHealthRecords.Archive()))
    XCTAssertNil(archive.localLabReadAudit)
    XCTAssertFalse(GalaxySSIHealthAgentLab.Policy(archive).allowed)
  }
}
