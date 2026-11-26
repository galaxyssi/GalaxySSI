import Foundation
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeReadConnectionPoolTests: XCTestCase {
  private enum Fault: Error { case injected }
  private final class Resource { let id: Int; init(_ id: Int) { self.id = id } }
  private typealias Pool = AgentKnowledgeReadConnectionPool<String, Resource>
  private final class PoolBox { weak var value: Pool? }
  private func boundedBorrow(_ pool: Pool, _ key: String) throws -> Pool.Lease {
    var checks = 0
    return try pool.borrow(key, checkActive: {
      checks += 1
      if checks > 2 { throw CancellationError() }
    }, create: { Resource(0) })
  }

  func testActivePlusIdleBoundAndSingleSlotEviction() throws {
    var disposed: [Int] = []
    let pool = Pool(capacity: 1) { disposed.append($0.id) }
    defer { pool.close() }
    let first = try pool.borrow("a", create: { Resource(1) })
    XCTAssertThrowsError(try boundedBorrow(pool, "b"))
    first.end()
    let next = try pool.borrow("b", create: { Resource(2) })
    XCTAssertEqual(disposed, [1])
    XCTAssertEqual(pool.stats.peak, 1)
    XCTAssertEqual(pool.stats.active + pool.stats.idle, 1)
    next.end()
  }

  func testSameKeyActiveLeasesHaveIndependentResources() throws {
    let pool = Pool(capacity: 2) { _ in }
    defer { pool.close() }
    let first = try pool.borrow("a", create: { Resource(1) }), second = try pool.borrow("a", create: { Resource(2) })
    XCTAssertNotEqual(try first.access { ObjectIdentifier($0) }, try second.access { ObjectIdentifier($0) })
    first.end(); second.end()
    XCTAssertEqual(pool.stats.idle, 2)
    let next = try pool.borrow("a", create: { XCTFail("Must reuse"); return Resource(3) })
    next.end()
    XCTAssertEqual(pool.stats.opened, 2)
    XCTAssertEqual(pool.stats.reused, 1)
  }

  func testReturnOrderLRUEvictsOldestIdleKey() throws {
    var disposed: [Int] = []
    let pool = Pool(capacity: 2) { disposed.append($0.id) }
    defer { pool.close() }
    try pool.borrow("a", create: { Resource(1) }).end()
    try pool.borrow("b", create: { Resource(2) }).end()
    try pool.borrow("a", create: { XCTFail("Must reuse"); return Resource(3) }).end()
    try pool.borrow("c", create: { Resource(4) }).end()
    XCTAssertEqual(disposed, [2])
    XCTAssertEqual(pool.stats.evicted, 1)
  }

  func testFailedActionAndValidationDiscardResources() throws {
    var disposed: [Int] = []
    let pool = Pool(capacity: 1) { disposed.append($0.id) }
    defer { pool.close() }
    let failed = try pool.borrow("a", create: { Resource(1) })
    XCTAssertThrowsError(try failed.access { _ in throw Fault.injected })
    failed.end()
    try pool.borrow("a", create: { Resource(2) }).end()
    XCTAssertThrowsError(try pool.borrow("a", valid: { _ in throw Fault.injected }, create: { Resource(3) }))
    XCTAssertEqual(disposed, [1, 2])
    XCTAssertEqual(pool.stats.active + pool.stats.idle, 0)
  }

  func testInvalidStampReopensAndFactoryFailureReleasesReservation() throws {
    var disposed: [Int] = []
    let pool = Pool(capacity: 1) { disposed.append($0.id) }
    defer { pool.close() }
    try pool.borrow("a", create: { Resource(1) }).end()
    XCTAssertThrowsError(try pool.borrow("a", valid: { _ in false }, create: { throw Fault.injected }))
    XCTAssertEqual(disposed, [1])
    XCTAssertEqual(pool.stats.active, 0)
    let next = try boundedBorrow(pool, "b"); next.end()
  }

  func testIdleRequiredRetirementRefusesActiveLeaseWithoutInvalidatingIt() throws {
    var disposed: [Int] = []
    let pool = Pool(capacity: 1) { disposed.append($0.id) }
    defer { pool.close() }
    let lease = try pool.borrow("a", create: { Resource(1) })
    XCTAssertThrowsError(try pool.invalidate(where: { $0 == "a" }, requireIdle: true))
    XCTAssertEqual(try lease.access { $0.id }, 1)
    lease.end()
    XCTAssertEqual(pool.stats.idle, 1)
    try pool.invalidate(where: { $0 == "a" }, requireIdle: true)
    XCTAssertEqual(disposed, [1])
  }

  func testTrimDefersActiveDisposalUntilLeaseReturn() throws {
    var disposed: [Int] = []
    let pool = Pool(capacity: 2) { disposed.append($0.id) }
    defer { pool.close() }
    let active = try pool.borrow("a", create: { Resource(1) })
    try pool.borrow("b", create: { Resource(2) }).end()
    try pool.invalidate(where: { _ in true })
    XCTAssertEqual(disposed, [2])
    XCTAssertEqual(try active.access { $0.id }, 1)
    active.end()
    XCTAssertEqual(disposed, [2, 1])
    XCTAssertEqual(pool.stats.active + pool.stats.idle, 0)
  }

  func testFactoriesValidationAndDisposalCanInspectPoolWithoutDeadlock() throws {
    let box = PoolBox()
    let pool = Pool(capacity: 1) { _ in XCTAssertEqual(box.value?.stats.active, 1) }
    box.value = pool
    defer { pool.close() }
    try pool.borrow("a", create: { XCTAssertEqual(pool.stats.active, 1); return Resource(1) }).end()
    try pool.borrow("a", valid: { _ in XCTAssertEqual(pool.stats.active, 1); return true }, create: { Resource(2) }).end()
    try pool.invalidate(where: { _ in true })
  }

  func testInvalidationDuringFactoryPreventsPublicationAndKeepsBound() throws {
    var disposed: [Int] = []
    let pool = Pool(capacity: 1) { disposed.append($0.id) }
    defer { pool.close() }
    XCTAssertThrowsError(try pool.borrow("a", create: {
      XCTAssertThrowsError(try boundedBorrow(pool, "b"))
      try pool.invalidate(where: { _ in true })
      return Resource(1)
    }))
    XCTAssertEqual(disposed, [1])
    XCTAssertEqual(pool.stats.active, 0)
    XCTAssertEqual(pool.stats.peak, 1)
  }

  func testCancellationAfterFactoryDisposesAndReleasesCapacity() throws {
    var checks = 0, disposed: [Int] = []
    let pool = Pool(capacity: 1) { disposed.append($0.id) }
    defer { pool.close() }
    XCTAssertThrowsError(try pool.borrow("a", checkActive: {
      checks += 1; if checks == 2 { throw CancellationError() }
    }, create: { Resource(1) }))
    XCTAssertEqual(disposed, [1])
    try boundedBorrow(pool, "b").end()
  }

  func testDoubleReturnCannotReleaseAReborrowedResource() throws {
    let pool = Pool(capacity: 1) { _ in }
    defer { pool.close() }
    let old = try boundedBorrow(pool, "a"); old.end()
    let next = try boundedBorrow(pool, "a"); old.end()
    XCTAssertEqual(pool.stats.active, 1)
    XCTAssertThrowsError(try old.access { $0.id })
    XCTAssertThrowsError(try boundedBorrow(pool, "b"))
    next.end()
  }

  func testCloseWakesBlockedBorrowerAndDefersActiveDisposal() throws {
    let pool = Pool(capacity: 1) { _ in }
    let active = try boundedBorrow(pool, "a")
    let entered = DispatchSemaphore(value: 0), finished = expectation(description: "Closed waiter")
    DispatchQueue.global().async {
      XCTAssertThrowsError(try pool.borrow("b", checkActive: { entered.signal() }, create: { Resource(2) }))
      finished.fulfill()
    }
    XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
    pool.close()
    wait(for: [finished], timeout: 2)
    XCTAssertEqual(pool.stats.active, 1)
    active.end()
    XCTAssertEqual(pool.stats.active, 0)
    XCTAssertThrowsError(try boundedBorrow(pool, "c"))
  }
}
