import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgePrimaryReaderSlotsTests: XCTestCase {
  private typealias Fixture = AgentKnowledgePrimaryPartitionsTests.Fixture

  private func boundedAcquire(_ slots: AgentKnowledgePrimaryReaderSlots) throws -> AgentKnowledgePrimaryReaderSlots.Lease {
    var checks = 0
    return try slots.acquire {
      checks += 1
      if checks > 2 { throw CancellationError() }
    }
  }

  private func boundedRead(_ fixture: Fixture) throws -> Data? {
    var checks = 0
    return try fixture.store.read(itemHash: fixture.key, catalog: fixture.catalog) {
      checks += 1
      if checks > 12 { throw CancellationError() }
    }
  }

  func testCapacityAndDoubleEndCannotCreateAdditionalSlots() throws {
    let slots = AgentKnowledgePrimaryReaderSlots(capacity: 2)
    let first = try boundedAcquire(slots), second = try boundedAcquire(slots)
    defer { first.end(); second.end() }
    XCTAssertThrowsError(try boundedAcquire(slots))
    first.end()
    first.end()
    let third = try boundedAcquire(slots)
    defer { third.end() }
    XCTAssertThrowsError(try boundedAcquire(slots))
    second.end()
    third.end()
    let fourth = try boundedAcquire(slots), fifth = try boundedAcquire(slots)
    defer { fourth.end(); fifth.end() }
    XCTAssertThrowsError(try boundedAcquire(slots))
  }

  func testLeaseDeinitializationReleasesTheSlot() throws {
    let slots = AgentKnowledgePrimaryReaderSlots(capacity: 1)
    var lease: AgentKnowledgePrimaryReaderSlots.Lease? = try boundedAcquire(slots)
    XCTAssertThrowsError(try boundedAcquire(slots))
    withExtendedLifetime(lease) {}
    lease = nil
    let next = try boundedAcquire(slots)
    next.end()
  }

  func testCancellationAfterAcquisitionReturnsTheSlot() throws {
    let slots = AgentKnowledgePrimaryReaderSlots(capacity: 1)
    var checks = 0
    XCTAssertThrowsError(try slots.acquire {
      checks += 1
      if checks == 2 { throw CancellationError() }
    })
    XCTAssertEqual(checks, 2)
    let next = try boundedAcquire(slots)
    next.end()
  }

  func testTwoStoresShareTheSameReaderCapacity() throws {
    let slots = AgentKnowledgePrimaryReaderSlots(capacity: 1)
    let first = try Fixture(readerSlots: slots), second = try Fixture(readerSlots: slots)
    let body = Data("shared capacity".utf8)
    try first.write(body)
    try second.write(body)
    let occupied = try boundedAcquire(slots)
    defer { occupied.end() }
    XCTAssertThrowsError(try boundedRead(first))
    XCTAssertThrowsError(try boundedRead(second))
    occupied.end()
    XCTAssertEqual(try boundedRead(first), body)
    XCTAssertEqual(try boundedRead(second), body)
  }

  func testOwnedPendingReadbackDoesNotConsumeAnIndependentReaderSlot() throws {
    let slots = AgentKnowledgePrimaryReaderSlots(capacity: 1)
    let fixture = try Fixture(readerSlots: slots), body = Data("pending owner".utf8)
    let occupied = try boundedAcquire(slots)
    defer { occupied.end() }
    try fixture.batch {
      try fixture.stage(body)
      XCTAssertEqual(try boundedRead(fixture), body)
    }
    XCTAssertThrowsError(try boundedRead(fixture))
    occupied.end()
    XCTAssertEqual(try boundedRead(fixture), body)
  }

  func testOpenAndFrameFailuresReleaseTheIndependentReaderSlot() throws {
    for missingFile in [false, true] {
      let slots = AgentKnowledgePrimaryReaderSlots(capacity: 1)
      let fixture = try Fixture(readerSlots: slots)
      try fixture.write(Data("body".utf8))
      let url = fixture.partitionURL(try fixture.partitionID())
      if missingFile {
        try FileManager.default.removeItem(at: url)
      } else {
        var raw: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
        let database = try XCTUnwrap(raw)
        defer { sqlite3_close_v2(database) }
        XCTAssertEqual(sqlite3_exec(database, "UPDATE frames SET sealed=x'00'", nil, nil, nil), SQLITE_OK)
      }
      XCTAssertThrowsError(try boundedRead(fixture))
      let next = try boundedAcquire(slots)
      next.end()
    }
  }
}
