import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthCyclingSessionTests: XCTestCase {
  typealias Cycling = GalaxySSIHealthMotion.Cycling
  private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
  private var origin: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)).addingTimeInterval(3_600) }
  private func date(_ second: Double) -> Date { origin.addingTimeInterval(second) }
  private func send(_ ledger: inout Cycling, _ kind: Cycling.Kind, _ second: Double) {
    ledger.observe(.init(at: date(second), kind: kind), now: date(second), calendar: calendar)
  }
  func testMissingEnterNeedsRepeatedPedallingAndFootDepartureFinishesOnlyOnce() throws {
    var ledger = Cycling()
    send(&ledger, .pedalling, 60); XCTAssertNil(ledger.started)
    send(&ledger, .pedalling, 80); send(&ledger, .enter, 85); send(&ledger, .pedalling, 120)
    XCTAssertEqual(ledger.today(date(120), calendar: calendar), 60)
    send(&ledger, .foot, 121); send(&ledger, .foot, 145); send(&ledger, .foot, 171)
    XCTAssertNil(ledger.started); XCTAssertEqual(ledger.today(date(171), calendar: calendar), 61)
    let saved = ledger
    send(&ledger, .foot, 171); send(&ledger, .pedalling, 120)
    XCTAssertEqual(ledger, saved); XCTAssertNoThrow(try ledger.validate())
  }
  func testNinetyMinuteRideSurvivesTrafficLightsAndBriefFootEvidence() throws {
    var ledger = Cycling(); send(&ledger, .enter, 0)
    for time in stride(from: 20, through: 5_400, by: 20) {
      let phase = time % 600
      let kind: Cycling.Kind = phase == 200 ? .exit :
        ([220, 240, 260, 280].contains(phase) ? .still : (phase == 400 ? .foot : .pedalling))
      send(&ledger, kind, Double(time))
    }
    XCTAssertTrue(ledger.days.isEmpty); XCTAssertTrue(ledger.riding(date(5_400)))
    XCTAssertEqual(ledger.today(date(5_400), calendar: calendar), 5_400)
    send(&ledger, .foot, 5_401); send(&ledger, .foot, 5_426); send(&ledger, .foot, 5_451)
    XCTAssertNil(ledger.started); XCTAssertEqual(ledger.today(date(5_451), calendar: calendar), 5_401)
    XCTAssertNoThrow(try ledger.validate())
  }
  func testMidnightRideSplitsConfirmedMotorDeparture() {
    let midnight = calendar.startOfDay(for: origin)
    var ledger = Cycling()
    for (offset, kind) in [(-40.0, Cycling.Kind.enter), (60, .motor), (90, .motor)] {
      let at = midnight.addingTimeInterval(offset)
      ledger.observe(.init(at: at, kind: kind), now: at, calendar: calendar)
    }
    XCTAssertNil(ledger.started)
    XCTAssertEqual(ledger.today(midnight.addingTimeInterval(90), calendar: calendar), 60)
    XCTAssertEqual(ledger.days.map(\.seconds).reduce(0, +), 100)
  }
  func testTransientMotorAndFootSignalsDoNotSplitRide() {
    var ledger = Cycling()
    send(&ledger, .enter, 1); send(&ledger, .pedalling, 30); send(&ledger, .motor, 35)
    send(&ledger, .pedalling, 59); send(&ledger, .foot, 79); send(&ledger, .pedalling, 130)
    XCTAssertTrue(ledger.days.isEmpty); XCTAssertEqual(ledger.today(date(130), calendar: calendar), 129)
  }
  func testStillTimeoutAndSilencePreserveOnlyObservedPortion() {
    var ledger = Cycling(); send(&ledger, .enter, 0); send(&ledger, .pedalling, 100)
    send(&ledger, .exit, 120); send(&ledger, .still, 125)
    XCTAssertTrue(ledger.riding(date(290))); XCTAssertFalse(ledger.riding(date(305)))
    send(&ledger, .still, 365)
    XCTAssertNil(ledger.started); XCTAssertEqual(ledger.today(date(365), calendar: calendar), 120)
    var silent = Cycling(); send(&silent, .enter, 0); send(&silent, .pedalling, 60)
    send(&silent, .exit, 1_000)
    XCTAssertNil(silent.started); XCTAssertEqual(silent.today(date(1_000), calendar: calendar), 60)
  }
  func testIsolatedSamplesAndUncertainSignalsDoNotCreateRide() {
    var ledger = Cycling(); send(&ledger, .pedalling, 2); send(&ledger, .pedalling, 100)
    XCTAssertNil(ledger.started); send(&ledger, .still, 101); XCTAssertNil(ledger.candidate)
    let saved = ledger; send(&ledger, .uncertain, 200); XCTAssertEqual(saved, ledger)
    send(&ledger, .pedalling, 201); ledger.expire(now: date(292), calendar: calendar)
    XCTAssertNil(ledger.candidate); XCTAssertEqual(ledger.today(date(292), calendar: calendar), 0)
  }
  func testOptOutAndRebootSettleObservedTimeWithoutCountingGap() throws {
    for reboot in [false, true] {
      var state = GalaxySSIHealthMotion.State()
      state.prepare(now: date(0), uptime: 1_000, calendar: calendar)
      state.enableCycling(true, now: date(0), calendar: calendar)
      state.cycling.days = [.init(start: calendar.startOfDay(for: origin), zone: calendar.timeZone.identifier, seconds: 26 * 60)]
      send(&state.cycling, .enter, 1); send(&state.cycling, .pedalling, 61)
      if reboot { state.prepare(now: date(600), uptime: 1, calendar: calendar) }
      else { state.enableCycling(false, now: date(600), calendar: calendar) }
      XCTAssertNil(state.cycling.started); XCTAssertEqual(state.cycling.today(date(600), calendar: calendar), 27 * 60)
      XCTAssertNoThrow(try state.validate())
    }
  }
  func testShortRideIsRetainedAndTimerAloneCannotExtendIt() {
    var ledger = Cycling(); send(&ledger, .enter, 0); send(&ledger, .pedalling, 29)
    XCTAssertEqual(ledger.today(date(300), calendar: calendar), 29)
    ledger.expire(now: date(600), calendar: calendar)
    XCTAssertNil(ledger.started); XCTAssertEqual(ledger.today(date(600), calendar: calendar), 29)
  }
  func testNativeIntervalReplayIsBoundedIdempotentAndDoesNotFillUnknownTail() throws {
    var ledger = Cycling()
    ledger.replay(.enter, from: date(0), through: date(600), now: date(1_000), calendar: calendar, includeEnd: false)
    XCTAssertEqual(ledger.today(date(1_000), calendar: calendar), 580)
    ledger.replay(.enter, from: date(0), through: date(600), now: date(1_000), calendar: calendar, includeEnd: true)
    XCTAssertEqual(ledger.today(date(1_000), calendar: calendar), 600)
    let saved = ledger
    ledger.replay(.enter, from: date(0), through: date(600), now: date(1_000), calendar: calendar, includeEnd: true)
    XCTAssertEqual(saved, ledger)
    ledger.replay(.uncertain, from: date(600), through: date(1_000), now: date(1_000), calendar: calendar, includeEnd: true)
    XCTAssertEqual(saved, ledger); XCTAssertNoThrow(try ledger.validate())
  }
  func testOptionalFieldsDecodeOldEncryptedLedgerWithoutInventedEvidence() throws {
    var ledger = Cycling(); send(&ledger, .enter, 0)
    let data = try JSONEncoder().encode(ledger)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for key in ["evidence", "gap", "stillSince", "departure", "candidate"] { object.removeValue(forKey: key) }
    let old = try JSONDecoder().decode(Cycling.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertEqual(old.today(date(100), calendar: calendar), 0); XCTAssertNoThrow(try old.validate())
    send(&ledger, .motor, 10)
    XCTAssertEqual(try JSONDecoder().decode(Cycling.self, from: JSONEncoder().encode(ledger)), ledger)
    ledger.departure = .init(kind: .enter, from: date(10), last: date(10))
    XCTAssertThrowsError(try ledger.validate())
  }
}
