import Foundation
import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthOCRSourceContextTests: XCTestCase {
  func testOnlyExplicitNamesAndCollectionTimesAreUsed() throws {
    let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let result = GalaxySSIHealthOCRSourceContext.inspect([
      "Physician name: Not the patient",
      "Report date: 2026-08-02 09:10",
      "Patient's name: Casey\nSample collection date/time: 2026-08-01 09:15:03+05:30",
      "Patient's name: Casey"
    ], timeZone: zone)
    XCTAssertEqual(result.names, ["Casey"])
    XCTAssertEqual(result.times, ["2026-08-01 09:15:03+05:30"])
    XCTAssertEqual(result.sample?.zone, "UTC+05:30")
    XCTAssertEqual(result.sample?.date, ISO8601DateFormatter().date(from: "2026-08-01T03:45:03Z"))
  }

  func testChineseLabelsAndDuplicateLinesUseLocalZone() throws {
    let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
    let name = "\u{53D7}\u{68C0}\u{8005}\u{59D3}\u{540D}\u{FF1A} Casey"
    let time = "\u{91C7}\u{6837}\u{65F6}\u{95F4}\u{FF1A} 2026\u{5E74}8\u{6708}1\u{65E5} 9:15"
    let result = GalaxySSIHealthOCRSourceContext.inspect([name, time, name, time], timeZone: zone)
    XCTAssertEqual(result.names, ["Casey"])
    XCTAssertEqual(result.times.count, 1)
    XCTAssertEqual(result.sample?.zone, zone.identifier)
    XCTAssertEqual(result.sample?.date, ISO8601DateFormatter().date(from: "2026-08-01T01:15:00Z"))
  }

  func testAmbiguousOrInvalidTimesRemainVisibleButCannotBeApplied() throws {
    let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    for time in ["2026-08-01", "2026-02-30 09:15", "2026-08-01 09:15 EST",
                 "2026-08-01 09:15+18:01", "2026-03-08 02:30", "2026-11-01 01:30"] {
      let result = GalaxySSIHealthOCRSourceContext.inspect(["Collected at: " + time], timeZone: zone)
      XCTAssertEqual(result.times, [time])
      XCTAssertNil(result.sample, time)
    }
    let explicit = GalaxySSIHealthOCRSourceContext.inspect(["Collected at: 2026-11-01 01:30-05:00"], timeZone: zone)
    XCTAssertEqual(explicit.sample?.date, ISO8601DateFormatter().date(from: "2026-11-01T06:30:00Z"))
  }

  func testConflictingNamesOrTimesPreventPrefill() throws {
    let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let time = "Measured at: 2026-08-01T09:15Z"
    let names = GalaxySSIHealthOCRSourceContext.inspect(["Patient name: Casey", "Patient name: Morgan", time],
                                                       timeZone: zone)
    XCTAssertEqual(names.names, ["Casey", "Morgan"])
    XCTAssertNil(names.sample)
    let times = GalaxySSIHealthOCRSourceContext.inspect([time, "Collected: 2026-08-01T09:16Z"], timeZone: zone)
    XCTAssertEqual(times.times.count, 2)
    XCTAssertNil(times.sample)
  }
}
