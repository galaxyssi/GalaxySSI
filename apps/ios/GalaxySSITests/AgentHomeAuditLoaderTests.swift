import Foundation
import Combine
import XCTest
@testable import GalaxySSI

@MainActor
final class AgentHomeAuditLoaderTests: XCTestCase {
  func testReadIsLazyAndRunsOffMainThread() async {
    let queue = DispatchQueue(label: "audit-deferred-fixture")
    queue.suspend()
    var reads = 0
    let loaded = expectation(description: "Worker records")
    let loader = AgentHomeAuditLoader(queue: queue) {
      XCTAssertFalse(Thread.isMainThread)
      reads += 1
      return [Self.record("worker")]
    }
    let observation = loader.$records.sink { if $0.first?.id == "worker" { loaded.fulfill() } }
    loader.refresh(identity: "owner")
    XCTAssertEqual(reads, 0)
    XCTAssertTrue(loader.records.isEmpty)
    queue.resume()
    await fulfillment(of: [loaded], timeout: 3)
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(loader.records(for: "owner").first?.id, "worker")
    XCTAssertTrue(loader.records(for: "another").isEmpty)
    XCTAssertTrue(loader.records(for: nil).isEmpty)
    withExtendedLifetime(observation) {}
  }

  func testBurstRequestsUseOneTrailingRead() async {
    let queue = DispatchQueue(label: "audit-coalescing-fixture")
    queue.suspend()
    var reads = 0
    let loaded = expectation(description: "Trailing records")
    let loader = AgentHomeAuditLoader(queue: queue) {
      reads += 1
      return [Self.record(String(reads))]
    }
    let observation = loader.$records.sink { if $0.first?.id == "2" { loaded.fulfill() } }
    for _ in 0..<30 { loader.refresh(identity: "owner") }
    queue.resume()
    await fulfillment(of: [loaded], timeout: 3)
    XCTAssertEqual(reads, 2)
    withExtendedLifetime(observation) {}
  }

  func testOldIdentityCompletionCannotPublish() async {
    let queue = DispatchQueue(label: "audit-owner-fixture")
    queue.suspend()
    var reads = 0
    let loaded = expectation(description: "Current owner")
    let loader = AgentHomeAuditLoader(queue: queue) {
      reads += 1
      return [Self.record(reads == 1 ? "old" : "current")]
    }
    let observation = loader.$records.sink {
      XCTAssertNotEqual($0.first?.id, "old")
      if $0.first?.id == "current" { loaded.fulfill() }
    }
    loader.refresh(identity: "old-owner")
    loader.refresh(identity: "current-owner")
    queue.resume()
    await fulfillment(of: [loaded], timeout: 3)
    XCTAssertTrue(loader.records(for: "old-owner").isEmpty)
    XCTAssertEqual(loader.records(for: "current-owner").first?.id, "current")
    withExtendedLifetime(observation) {}
  }

  func testInvalidationRejectsInFlightPublication() async {
    let queue = DispatchQueue(label: "audit-invalidation-fixture")
    queue.suspend()
    let published = expectation(description: "Old result must not publish")
    published.isInverted = true
    let loader = AgentHomeAuditLoader(queue: queue) { [Self.record("stale")] }
    let observation = loader.$records.sink { if !$0.isEmpty { published.fulfill() } }
    loader.refresh(identity: "owner")
    loader.invalidate()
    queue.resume()
    await fulfillment(of: [published], timeout: 0.2)
    XCTAssertTrue(loader.records(for: "owner").isEmpty)
    withExtendedLifetime(observation) {}
  }

  func testBlankIdentityDoesNotReadAndClearsLoadedRecords() async {
    var reads = 0
    let loaded = expectation(description: "Loaded before locking")
    let loader = AgentHomeAuditLoader {
      reads += 1
      return [Self.record("loaded")]
    }
    let observation = loader.$records.sink { if !$0.isEmpty { loaded.fulfill() } }
    loader.refresh(identity: "owner")
    await fulfillment(of: [loaded], timeout: 3)
    loader.refresh(identity: " \n")
    XCTAssertTrue(loader.records.isEmpty)
    XCTAssertEqual(reads, 1)
    withExtendedLifetime(observation) {}
  }

  private nonisolated static func record(_ id: String) -> AgentNativeToolAuditRecord {
    .init(auditId: id, invocationId: id, toolId: "fixture", toolVersion: "1", location: .phone,
      risk: .low, callerId: "fixture", identityHashes: [:], startedAtEpochMillis: 1,
      finishedAtEpochMillis: 2, durationMillis: 1, status: .succeeded, errorCode: "",
      inputSha256: "", outputSha256: "", replayed: false, originalInvocationId: nil, recordSha256: "")
  }
}
