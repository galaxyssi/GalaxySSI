import SQLite3
import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthActivityComparisonTests: XCTestCase {
  func testAlignedPeriodsPreserveUnknownDaysAndUseOnlyPairedTotals() throws {
    let calendar = utcCalendar
    let now = try date("2026-03-15", calendar: calendar)
    let first = try date("2026-03-08", calendar: calendar)
    let last = try date("2026-03-14", calendar: calendar)
    let rows: [GalaxySSIHealthActivityDay] = [
      .init(kind: .steps, day: "2026-03-08", total: 120),
      .init(kind: .steps, day: "2026-03-01", total: 100),
      .init(kind: .steps, day: "2026-03-09", total: 0),
      .init(kind: .steps, day: "2026-03-02", total: 0),
      .init(kind: .steps, day: "2026-03-10", total: 900),
      .init(kind: .cycling, day: "2026-03-08", total: 60_000)
    ]
    let result = try GalaxySSIHealthActivityComparison(first: first, last: last, now: now,
      calendar: calendar, rows: rows, kind: .steps)
    XCTAssertEqual(result.coverage, 3)
    XCTAssertEqual(result.paired.count, 2)
    XCTAssertEqual(result.currentTotal, 1_020)
    XCTAssertEqual(result.currentPaired, 120)
    XCTAssertEqual(result.previousPaired, 100)
    XCTAssertEqual(result.changePercent, 20)
    XCTAssertEqual(result.pairs[1].current, 0)
    XCTAssertNil(result.pairs[2].previous)
    XCTAssertNil(result.pairs[3].current)
    XCTAssertNoThrow(try GalaxySSIHealthActivityComparison(first: first, last: now, now: now,
      calendar: calendar, rows: [], kind: .steps))
    XCTAssertThrowsError(try GalaxySSIHealthActivityComparison(first: first, last: now.addingTimeInterval(86400), now: now,
      calendar: calendar, rows: [], kind: .steps))
  }

  func testDayAlignmentUsesCalendarNotFixed86400SecondWindows() throws {
    var calendar = utcCalendar
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let first = try date("2026-03-07", calendar: calendar)
    let last = try date("2026-03-09", calendar: calendar)
    let result = try GalaxySSIHealthActivityComparison(first: first, last: last,
      now: date("2026-03-10", calendar: calendar), calendar: calendar, rows: [], kind: .steps)
    XCTAssertEqual(result.pairs.count, 3)
    XCTAssertEqual(result.pairs[2].day.timeIntervalSince(result.pairs[1].day), 23 * 3_600)
    XCTAssertEqual(GalaxySSIHealthActivityComparison.dayKey(result.pairs[2].previousDay, zone: calendar.timeZone), "2026-03-06")
    XCTAssertTrue(GalaxySSIHealthActivityComparison.validDay("2024-02-29"))
    XCTAssertFalse(GalaxySSIHealthActivityComparison.validDay("2026-02-29"))
    XCTAssertFalse(GalaxySSIHealthActivityComparison.validDay("2026-13-01"))
  }

  func testPresetsIncludeTodayAcrossYearLeapAndDSTBoundaries() throws {
    for key in ["2026-01-01", "2024-03-01", "2026-03-09"] {
      var calendar = utcCalendar
      calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
      let today = try date(key, calendar: calendar)
      for days in [7, 30, 90] {
        let range = try GalaxySSIHealthActivityComparison.trailing(days: days, now: today, calendar: calendar)
        XCTAssertEqual(range.upperBound, today)
        XCTAssertEqual(calendar.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day, days - 1)
        let result = try GalaxySSIHealthActivityComparison(first: range.lowerBound, last: range.upperBound,
          now: today, calendar: calendar, rows: [], kind: .steps)
        XCTAssertEqual(result.pairs.count, days)
        XCTAssertEqual(result.coverage, 0)
      }
    }
    XCTAssertThrowsError(try GalaxySSIHealthActivityComparison.trailing(days: 367, now: Date(), calendar: utcCalendar))
  }

  func testTodayOverlayPreservesUnknownZeroAndPreviousPeriod() throws {
    let today = try date("2026-11-20", calendar: utcCalendar)
    let base = try GalaxySSIHealthActivityComparison(first: today, last: today, now: today,
      calendar: utcCalendar, rows: [.init(kind: .steps, day: "2026-11-19", total: 80)], kind: .steps)
    XCTAssertEqual(try base.withDay(nil, kind: .steps, zone: utcCalendar.timeZone), base)
    XCTAssertNil(base.pairs.first?.current)
    let zero = try base.withDay(.init(kind: .steps, day: "2026-11-20", total: 0), kind: .steps, zone: utcCalendar.timeZone)
    XCTAssertEqual(zero.coverage, 1)
    XCTAssertEqual(zero.pairs.first?.current, 0)
    XCTAssertEqual(zero.pairs.first?.previous, 80)
    let observed = try base.withDay(.init(kind: .steps, day: "2026-11-20", total: 100), kind: .steps, zone: utcCalendar.timeZone)
    XCTAssertEqual(try observed.withDay(.init(kind: .steps, day: "2026-11-20", total: 20), kind: .steps,
      zone: utcCalendar.timeZone).pairs.first?.current, 100)
    XCTAssertEqual(try base.withDay(.init(kind: .steps, day: "2026-11-21", total: 100), kind: .steps, zone: utcCalendar.timeZone), base)
    XCTAssertThrowsError(try base.withDay(.init(kind: .steps, day: "2026-11-20", total: -1), kind: .steps, zone: utcCalendar.timeZone))
  }

  func testUnobservedStepsStayUnknownButRealZeroAndPausedTotalsRemain() throws {
    let today = try date("2026-11-20", calendar: utcCalendar), now = today.addingTimeInterval(3600)
    var state = GalaxySSIHealthMotion.State(steps: .init(day: today, zone: utcCalendar.timeZone.identifier))
    XCTAssertNil(GalaxySSIHealthActivityComparison.today(nil, kind: .steps, now: now, calendar: utcCalendar))
    XCTAssertNil(GalaxySSIHealthActivityComparison.today(state, kind: .steps, now: now, calendar: utcCalendar))
    state.steps?.sampledThrough = now
    XCTAssertEqual(GalaxySSIHealthActivityComparison.today(state, kind: .steps, now: now, calendar: utcCalendar)?.total, 0)
    state.steps?.total = 250; state.steps?.sampledThrough = nil
    XCTAssertEqual(GalaxySSIHealthActivityComparison.today(state, kind: .steps, now: now, calendar: utcCalendar)?.total, 250)
    XCTAssertNil(GalaxySSIHealthActivityComparison.today(state, kind: .steps, now: now.addingTimeInterval(86400), calendar: utcCalendar))
  }

  func testOngoingCyclingIsDisplayOnlyAndCanBeCorrected() throws {
    let today = try date("2026-11-20", calendar: utcCalendar), now = today.addingTimeInterval(7200)
    var state = GalaxySSIHealthMotion.State()
    XCTAssertNil(GalaxySSIHealthActivityComparison.today(state, kind: .cycling, now: now, calendar: utcCalendar))
    state.enableCycling(true, now: today, calendar: utcCalendar)
    XCTAssertEqual(GalaxySSIHealthActivityComparison.today(state, kind: .cycling, now: now, calendar: utcCalendar)?.total, 0)
    state.cycling.started = now.addingTimeInterval(-1800)
    state.cycling.evidence = now; state.cycling.lastEvent = now
    state.cycling.days = [.init(start: today, zone: utcCalendar.timeZone.identifier, seconds: 600)]
    let before = state
    XCTAssertEqual(GalaxySSIHealthActivityComparison.today(state, kind: .cycling, now: now.addingTimeInterval(300), calendar: utcCalendar)?.total, 2_400_000)
    XCTAssertEqual(state, before)
    XCTAssertEqual(GalaxySSIHealthActivityComparison.checkpoints(state).map(\.total), [600_000])
    let base = try GalaxySSIHealthActivityComparison(first: today, last: today, now: now, calendar: utcCalendar, rows: [], kind: .cycling)
    let first = try base.withDay(GalaxySSIHealthActivityComparison.today(state, kind: .cycling, now: now, calendar: utcCalendar),
      kind: .cycling, zone: utcCalendar.timeZone)
    state.cycling.gap = now.addingTimeInterval(-900)
    state.cycling.evidence = state.cycling.gap
    try state.validate()
    let corrected = try base.withDay(GalaxySSIHealthActivityComparison.today(state, kind: .cycling, now: now, calendar: utcCalendar),
      kind: .cycling, zone: utcCalendar.timeZone)
    XCTAssertEqual(first.currentTotal, 2_400_000)
    XCTAssertEqual(corrected.currentTotal, 1_500_000)
    XCTAssertEqual(state.cycling.days.first?.seconds, 600)
  }

  func testCyclingAcrossMidnightCountsOnlyCurrentLocalDay() throws {
    let today = try date("2026-11-20", calendar: utcCalendar), now = today.addingTimeInterval(3600)
    var state = GalaxySSIHealthMotion.State()
    state.enableCycling(true, now: today.addingTimeInterval(-3600), calendar: utcCalendar)
    state.cycling.started = today.addingTimeInterval(-3600); state.cycling.evidence = now; state.cycling.lastEvent = now
    XCTAssertEqual(GalaxySSIHealthActivityComparison.today(state, kind: .cycling, now: now, calendar: utcCalendar)?.total, 3_600_000)
    XCTAssertTrue(GalaxySSIHealthActivityComparison.checkpoints(state).isEmpty)
  }

  func testEncryptedHistoryIsMonotonicAndRetainedAcrossReopening() throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("history.sqlite")
    let secrets = ActivityHistorySecrets()
    do {
      let store = try GalaxySSIHealthActivityHistoryStore(file: file, owner: "fixture", secrets: secrets)
      try store.save([.init(kind: .steps, day: "2020-01-01", total: 42)])
      try store.save([.init(kind: .steps, day: "2020-01-01", total: 5), .init(kind: .steps, day: "2020-01-01", total: 50)])
      try store.save([.init(kind: .cycling, day: "2020-01-01", total: 120_000)])
    }
    let reopened = try GalaxySSIHealthActivityHistoryStore(file: file, owner: "fixture", secrets: secrets)
    XCTAssertEqual(try reopened.read(kind: .steps, first: "2020-01-01", last: "2020-01-02").map(\.total), [50])
    XCTAssertEqual(try reopened.read(kind: .cycling, first: "2020-01-01", last: "2020-01-01").map(\.total), [120_000])
    XCTAssertThrowsError(try reopened.read(kind: .steps, first: "2020-01-01", last: "2026-01-01"))
    XCTAssertThrowsError(try reopened.save([.init(kind: .steps, day: "2026-02-29", total: 5)]))
    XCTAssertThrowsError(try reopened.save([.init(kind: .cycling, day: "2020-01-02", total: -1)]))
    let otherOwner = try GalaxySSIHealthActivityHistoryStore(file: file, owner: "other", secrets: secrets)
    XCTAssertThrowsError(try otherOwner.read(kind: .steps, first: "2020-01-01", last: "2020-01-01"))
  }

  func testCiphertextCannotBeReassignedToAnotherDate() throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("history.sqlite")
    let store = try GalaxySSIHealthActivityHistoryStore(file: file, owner: "fixture", secrets: ActivityHistorySecrets())
    try store.save([.init(kind: .steps, day: "2026-01-01", total: 10), .init(kind: .steps, day: "2026-01-02", total: 20)])
    var database: OpaquePointer?
    XCTAssertEqual(sqlite3_open(file.path, &database), SQLITE_OK)
    defer { sqlite3_close_v2(database) }
    XCTAssertEqual(sqlite3_exec(database, "UPDATE days SET payload=(SELECT payload FROM days WHERE kind=0 AND day='2026-01-01') WHERE kind=0 AND day='2026-01-02'", nil, nil, nil), SQLITE_OK)
    XCTAssertThrowsError(try store.read(kind: .steps, first: "2026-01-02", last: "2026-01-02"))
  }

  @MainActor
  func testRollingCheckpointMigrationNeverCreatesUnknownZeroDays() throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: ActivityHistorySecrets(), isolatedFile: root.appendingPathComponent("records"))
    let day = try date("2026-01-01", calendar: utcCalendar)
    try records.updateMotion {
      $0.steps = .init(day: day, zone: "GMT", total: 800, base: 800, sampledThrough: day.addingTimeInterval(100))
    }
    try records.updateMotion { $0.steps = nil }
    XCTAssertEqual(try records.activityHistoryStore().read(kind: .steps, first: "2026-01-01", last: "2026-01-02").map(\.total), [800])
    let empty = GalaxySSIHealthMotion.State(steps: .init(day: day, zone: "GMT"))
    XCTAssertTrue(GalaxySSIHealthActivityComparison.checkpoints(empty).isEmpty)
  }

  private var utcCalendar: Calendar {
    var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value
  }
  private func date(_ value: String, calendar: Calendar) throws -> Date {
    let parts = value.split(separator: "-").compactMap { Int($0) }
    return try XCTUnwrap(calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])))
  }
  private func directory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
}

private final class ActivityHistorySecrets: GalaxySSISecretStore {
  private var values: [String: String] = [:]
  func string(account: String) -> String? { values[account] }
  func setString(_ value: String, account: String) throws { values[account] = value }
  func delete(account: String) { values.removeValue(forKey: account) }
}
