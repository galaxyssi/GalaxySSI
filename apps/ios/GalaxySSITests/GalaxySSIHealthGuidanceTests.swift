import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthGuidanceTests: XCTestCase {
  typealias Guidance = GalaxySSIHealthOverviewGuidance
  func testAgeBandsIncludeInfantMonthsAndEveryAdultBoundary() {
    let cases: [(Int, Int, Guidance.SleepBand)] = [(0, 3, .months0_3), (0, 4, .months4_12),
      (1, 0, .years1_2), (2, 11, .years1_2), (3, 0, .years3_5), (6, 0, .years6_12),
      (13, 0, .years13_17), (18, 0, .years18_60), (60, 11, .years18_60), (61, 0, .years61_64), (65, 0, .years65Plus)]
    for (years, months, expected) in cases { XCTAssertEqual(Guidance.sleep(.init(years: years, months: months)), expected) }
    XCTAssertEqual(Guidance.sleep(nil), .adultUnspecified)
    XCTAssertFalse(Guidance.adult(.init(years: 17, months: 11))); XCTAssertTrue(Guidance.adult(nil))
  }
  func testAgeIsAtMeasurementDayNotCurrentAgeAndFutureBirthIsUnavailable() throws {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let birth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2000, month: 5, day: 2)))
    let before = try XCTUnwrap(calendar.date(from: DateComponents(year: 2018, month: 5, day: 1)))
    let birthday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2018, month: 5, day: 2)))
    XCTAssertEqual(Guidance.age(birth: birth, on: before, calendar: calendar)?.years, 17)
    XCTAssertEqual(Guidance.age(birth: birth, on: birthday, calendar: calendar)?.years, 18)
    XCTAssertNil(Guidance.age(birth: birthday, on: birth, calendar: calendar))
    XCTAssertNil(Guidance.age(birth: nil, on: birthday, calendar: calendar))
  }
  func testGeneralSourcesAreNotPersonalTargetsAndAdultReferencesAreHiddenForChildren() throws {
    XCTAssertNil(Guidance.reference(metric: .bloodPressure, age: .init(years: 10, months: 0), language: "en"))
    XCTAssertNil(Guidance.reference(metric: .restingHeartRate, age: .init(years: 10, months: 0), language: "en"))
    XCTAssertNil(Guidance.reference(metric: .steps, age: nil, language: "en"))
    let pressure = try XCTUnwrap(Guidance.reference(metric: .bloodPressure, age: nil, language: "en"))
    XCTAssertTrue(pressure.detail.contains("not personal targets")); XCTAssertEqual(pressure.url.scheme, "https")
    let sleep = try XCTUnwrap(Guidance.reference(metric: .sleepDuration, age: nil, language: "en"))
    XCTAssertTrue(sleep.detail.contains("general reference")); XCTAssertEqual(sleep.url.host, "www.cdc.gov")
  }
  func testUserCalendarDoesNotChangeCivilAgeBands() throws {
    var civil = Calendar(identifier: .gregorian); civil.timeZone = TimeZone(secondsFromGMT: 0)!
    var user = Calendar(identifier: .islamicCivil); user.timeZone = civil.timeZone
    let birth = try XCTUnwrap(civil.date(from: DateComponents(year: 2000, month: 5, day: 2)))
    let day = try XCTUnwrap(civil.date(from: DateComponents(year: 2018, month: 5, day: 1)))
    XCTAssertEqual(Guidance.age(birth: birth, on: day, calendar: civil), Guidance.age(birth: birth, on: day, calendar: user))
  }
}
