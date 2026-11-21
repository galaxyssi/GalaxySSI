import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthMotionLedgerTests: XCTestCase {
  typealias Motion = GalaxySSIHealthMotion
  private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  func testStepProgressRequiresPermissionFreshIntegerGoalAndDoesNotClampAchievement() {
    XCTAssertNil(Motion.progress(goal: nil, steps: 100, fresh: true, permitted: true))
    XCTAssertNil(Motion.progress(goal: 0, steps: 100, fresh: true, permitted: true))
    XCTAssertNil(Motion.progress(goal: 1_000_001, steps: 100, fresh: true, permitted: true))
    XCTAssertNil(Motion.progress(goal: 100, steps: -1, fresh: true, permitted: true))
    XCTAssertNil(Motion.progress(goal: 100, steps: 100, fresh: false, permitted: true))
    XCTAssertNil(Motion.progress(goal: 100, steps: 100, fresh: true, permitted: false))
    XCTAssertEqual(Motion.progress(goal: 100, steps: 150, fresh: true, permitted: true), 1.5)
  }
  func testCumulativeStepsAreNotAddedTwiceAndResumeDoesNotCountPausedGap() throws {
    var state = Motion.State(); state.enableSteps(true, now: now, calendar: calendar)
    let first = try XCTUnwrap(state.steps?.segment)
    state.steps?.observe(10, from: now, through: now.addingTimeInterval(10), now: now.addingTimeInterval(10), calendar: calendar)
    state.steps?.observe(10, from: now, through: now.addingTimeInterval(10), now: now.addingTimeInterval(10), calendar: calendar)
    XCTAssertEqual(state.steps?.total, 10)
    state.enableSteps(false, now: now.addingTimeInterval(20), calendar: calendar)
    XCTAssertNotEqual(state.steps?.segment, first); XCTAssertNil(state.steps?.start)
    let resumed = now.addingTimeInterval(100)
    state.enableSteps(true, now: resumed, calendar: calendar)
    state.steps?.observe(500, from: now, through: resumed.addingTimeInterval(1), now: resumed.addingTimeInterval(1), calendar: calendar)
    XCTAssertEqual(state.steps?.total, 10)
    state.steps?.observe(3, from: resumed, through: resumed.addingTimeInterval(2), now: resumed.addingTimeInterval(2), calendar: calendar)
    XCTAssertEqual(state.steps?.total, 13); XCTAssertNoThrow(try state.validate())
  }
  func testStepOutOfOrderWrongWindowAndFutureSamplesDoNotChangeTotals() throws {
    var state = Motion.State(); state.enableSteps(true, now: now, calendar: calendar)
    let end = now.addingTimeInterval(10)
    state.steps?.observe(10, from: now, through: end, now: end, calendar: calendar)
    for (from, through) in [(now.addingTimeInterval(-1), end), (now, now.addingTimeInterval(9)), (now, end.addingTimeInterval(1))] {
      state.steps?.observe(999, from: from, through: through, now: end, calendar: calendar)
      XCTAssertEqual(state.steps?.total, 10)
    }
    state.steps?.observe(Int.max, from: now, through: end, now: end, calendar: calendar)
    XCTAssertEqual(state.steps?.total, Motion.maximumSteps)
    XCTAssertNoThrow(try state.validate())
  }
  func testLocalMidnightResetsStepWindowRatherThanAddingYesterday() throws {
    var state = Motion.State()
    state.prepare(now: now, uptime: 100, calendar: calendar); state.enableSteps(true, now: now, calendar: calendar)
    state.steps?.observe(10, from: now, through: now, now: now, calendar: calendar)
    let next = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
    state.prepare(now: next, uptime: 100 + next.timeIntervalSince(now), calendar: calendar)
    XCTAssertEqual(state.steps?.total, 0); XCTAssertEqual(state.steps?.base, 0)
    XCTAssertEqual(state.steps?.start, calendar.startOfDay(for: next))
    XCTAssertNil(state.steps?.today(now, calendar: calendar)); XCTAssertNoThrow(try state.validate())
  }
  func testClockJumpDoesNotRecountTheExistingStepWindowOrKeepPendingRide() {
    var state = Motion.State(); state.prepare(now: now, uptime: 100, calendar: calendar)
    state.enableSteps(true, now: now, calendar: calendar); state.enableCycling(true, now: now, calendar: calendar)
    state.steps?.observe(10, from: now, through: now, now: now, calendar: calendar)
    state.cycling.observe(.init(at: now, kind: .cycling), now: now, calendar: calendar)
    let jumped = now.addingTimeInterval(600)
    state.prepare(now: jumped, uptime: 101, calendar: calendar)
    XCTAssertEqual(state.steps?.start, jumped); XCTAssertNil(state.cycling.started)
    state.steps?.observe(3, from: jumped, through: jumped, now: jumped, calendar: calendar)
    XCTAssertEqual(state.steps?.total, 13)
  }
  func testCyclingFinishesOnlyOnceAndRejectsOutOfOrderEvents() {
    var ledger = Motion.Cycling()
    ledger.observe(.init(at: now, kind: .cycling), now: now, calendar: calendar)
    ledger.observe(.init(at: now.addingTimeInterval(10), kind: .cycling), now: now.addingTimeInterval(10), calendar: calendar)
    let end = now.addingTimeInterval(60)
    ledger.observe(.init(at: end, kind: .inactive), now: end, calendar: calendar)
    XCTAssertEqual(ledger.today(end, calendar: calendar), 60)
    let previous = ledger
    ledger.observe(.init(at: end, kind: .inactive), now: end, calendar: calendar)
    ledger.observe(.init(at: now, kind: .cycling), now: end, calendar: calendar)
    XCTAssertEqual(ledger, previous)
  }
  func testCyclingRejectsTooShortOverlongFutureAndUncertainSessions() {
    for duration in [29.0, 43_201.0] {
      var ledger = Motion.Cycling()
      ledger.observe(.init(at: now, kind: .cycling), now: now, calendar: calendar)
      let end = now.addingTimeInterval(duration)
      ledger.observe(.init(at: end, kind: .inactive), now: end, calendar: calendar)
      XCTAssertTrue(ledger.days.isEmpty); XCTAssertNil(ledger.started)
    }
    var ledger = Motion.Cycling()
    ledger.observe(.init(at: now.addingTimeInterval(1), kind: .cycling), now: now, calendar: calendar)
    XCTAssertNil(ledger.started)
    ledger.observe(.init(at: now, kind: .cycling), now: now, calendar: calendar)
    ledger.observe(.init(at: now.addingTimeInterval(30), kind: .uncertain), now: now.addingTimeInterval(30), calendar: calendar)
    ledger.observe(.init(at: now.addingTimeInterval(60), kind: .inactive), now: now.addingTimeInterval(60), calendar: calendar)
    XCTAssertTrue(ledger.days.isEmpty)
  }
  func testRideCrossingMidnightSplitsOnlyCompletedDuration() {
    let midnight = calendar.startOfDay(for: now)
    var ledger = Motion.Cycling()
    ledger.observe(.init(at: midnight.addingTimeInterval(-30), kind: .cycling), now: midnight.addingTimeInterval(-30), calendar: calendar)
    XCTAssertEqual(ledger.today(midnight, calendar: calendar), 0)
    ledger.observe(.init(at: midnight.addingTimeInterval(30), kind: .inactive), now: midnight.addingTimeInterval(30), calendar: calendar)
    XCTAssertEqual(ledger.today(midnight, calendar: calendar), 30)
    XCTAssertEqual(ledger.today(midnight.addingTimeInterval(-1), calendar: calendar), 30)
  }
  func testCyclingUsesActualDSTDurationAndKeepsAtMostEightDays() throws {
    var local = calendar; local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let begin = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 30)))
    let end = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 30)))
    var ledger = Motion.Cycling()
    ledger.observe(.init(at: begin, kind: .cycling), now: begin, calendar: local)
    ledger.observe(.init(at: end, kind: .inactive), now: end, calendar: local)
    XCTAssertEqual(ledger.today(end, calendar: local), 3_600)
    for day in 1...10 {
      let start = try XCTUnwrap(local.date(byAdding: .day, value: day, to: end))
      ledger.observe(.init(at: start, kind: .cycling), now: start, calendar: local)
      ledger.observe(.init(at: start.addingTimeInterval(60), kind: .inactive), now: start.addingTimeInterval(60), calendar: local)
    }
    XCTAssertLessThanOrEqual(ledger.days.count, 8)
  }
  func testOptOutAndTimezoneOrRebootDropPendingSegmentsWithoutAddingDuration() throws {
    var state = Motion.State(); state.prepare(now: now, uptime: 100, calendar: calendar)
    state.enableCycling(true, now: now, calendar: calendar)
    state.cycling.observe(.init(at: now, kind: .cycling), now: now, calendar: calendar)
    state.prepare(now: now.addingTimeInterval(60), uptime: 1, calendar: calendar)
    XCTAssertNil(state.cycling.started); XCTAssertTrue(state.cycling.days.isEmpty)
    let epoch = state.cycling.epoch
    state.enableCycling(false, now: now.addingTimeInterval(60), calendar: calendar)
    XCTAssertNotEqual(state.cycling.epoch, epoch); XCTAssertNil(state.cyclingEnabled)
    var other = calendar; other.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
    state.prepare(now: now.addingTimeInterval(61), uptime: 2, calendar: other)
    XCTAssertEqual(state.cycling.zone, other.timeZone.identifier); XCTAssertNoThrow(try state.validate())
  }
  func testStateRoundTripAndValidationRejectCorruptCountsDurationsAndGoals() throws {
    var state = Motion.State(); state.enableSteps(true, now: now, calendar: calendar)
    state.goal = 10_000
    XCTAssertEqual(try JSONDecoder().decode(Motion.State.self, from: JSONEncoder().encode(state)), state)
    state.goal = -1; XCTAssertThrowsError(try state.validate()); state.goal = 1
    state.steps?.total = -1; XCTAssertThrowsError(try state.validate()); state.steps?.total = 0
    state.steps?.base = 1; XCTAssertThrowsError(try state.validate()); state.steps?.base = 0
    state.cycling.days = [.init(start: calendar.startOfDay(for: now), zone: calendar.timeZone.identifier, seconds: 90_000)]
    XCTAssertThrowsError(try state.validate())
  }
  func testRebootRecoveryStartsAfterBootRatherThanDroppingAvailableHistoryOrSpanningBoot() throws {
    var state = Motion.State(); state.prepare(now: now, uptime: 1_000, calendar: calendar)
    state.enableSteps(true, now: now, calendar: calendar); state.enableCycling(true, now: now, calendar: calendar)
    state.steps?.observe(10, from: now, through: now, now: now, calendar: calendar)
    state.cycling.observe(.init(at: now, kind: .cycling), now: now, calendar: calendar)
    let resumed = now.addingTimeInterval(3_600), boot = resumed.addingTimeInterval(-120)
    state.prepare(now: resumed, uptime: 120, calendar: calendar)
    XCTAssertEqual(state.steps?.start, boot); XCTAssertEqual(state.cycling.cursor, boot); XCTAssertNil(state.cycling.started)
    state.steps?.observe(5, from: boot, through: resumed, now: resumed, calendar: calendar)
    XCTAssertEqual(state.steps?.total, 15); XCTAssertNoThrow(try state.validate())
  }
}
