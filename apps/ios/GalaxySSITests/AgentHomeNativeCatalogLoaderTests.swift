import Combine
import Foundation
import XCTest
@testable import GalaxySSI

@MainActor
final class AgentHomeNativeCatalogLoaderTests: XCTestCase {
  func testHomeCatalogReadsOffCallerAndProjectsActualAvailableTools() async throws {
    let tools = try [Self.tool("ready"), Self.tool("blocked", risk: .blocked), Self.tool("setup", status: .requiresSetup)]
    let queue = DispatchQueue(label: "home-catalog-worker-fixture"); queue.suspend()
    var reads = 0
    let loaded = expectation(description: "Worker result delivered")
    let loader = AgentHomeNativeCatalogLoader(queue: queue) {
      XCTAssertFalse(Thread.isMainThread); reads += 1; return tools
    }
    let observation = loader.$hasSnapshot.sink { if $0 { loaded.fulfill() } }
    loader.refresh(identity: "owner")
    XCTAssertEqual(reads, 0); XCTAssertFalse(loader.isCurrent(identity: "owner"))
    queue.resume()
    await fulfillment(of: [loaded], timeout: 3)
    XCTAssertEqual(reads, 1); XCTAssertEqual(loader.tools.count, 3); XCTAssertEqual(loader.availableCount, 1)
    XCTAssertTrue(loader.isCurrent(identity: "owner"))
    withExtendedLifetime(observation) {}
  }

  func testHomeCatalogBurstCoalescesIntoOneTrailingRefresh() async throws {
    let first = try Self.tool("one"), second = try Self.tool("two")
    let queue = DispatchQueue(label: "home-catalog-burst-fixture"); queue.suspend()
    var reads = 0
    let latest = expectation(description: "Coalesced trailing result")
    let loader = AgentHomeNativeCatalogLoader(queue: queue) { reads += 1; return [reads == 1 ? first : second] }
    let observation = loader.$tools.sink { if $0.first?.id == second.id { latest.fulfill() } }
    loader.refresh(identity: "owner")
    for _ in 0..<30 { loader.refreshIfActive(identity: "owner") }
    queue.resume()
    await fulfillment(of: [latest], timeout: 3)
    XCTAssertEqual(reads, 2); XCTAssertEqual(loader.tools, [second])
    withExtendedLifetime(observation) {}
  }

  func testHomeCatalogOldProfileCompletionCannotReplaceCurrentWork() async throws {
    let old = try Self.tool("old"), current = try Self.tool("current")
    let queue = DispatchQueue(label: "home-catalog-profile-fixture"); queue.suspend()
    var reads = 0
    let loaded = expectation(description: "Current owner result")
    let loader = AgentHomeNativeCatalogLoader(queue: queue) { reads += 1; return [reads == 1 ? old : current] }
    let observation = loader.$hasSnapshot.sink { if $0 { loaded.fulfill() } }
    loader.refresh(identity: "old"); loader.refresh(identity: "current")
    XCTAssertFalse(loader.isCurrent(identity: "old")); XCTAssertFalse(loader.isCurrent(identity: "current"))
    queue.resume()
    await fulfillment(of: [loaded], timeout: 3)
    XCTAssertEqual(loader.tools, [current]); XCTAssertTrue(loader.isCurrent(identity: "current"))
    XCTAssertFalse(loader.isCurrent(identity: "old"))
    withExtendedLifetime(observation) {}
  }

  func testHomeCatalogFailedRefreshKeepsLastCompleteSnapshotWithoutInventingSuccess() async throws {
    let tool = try Self.tool("retained")
    var reads = 0
    let loaded = expectation(description: "Complete snapshot"), failed = expectation(description: "Read failure")
    let loader = AgentHomeNativeCatalogLoader { reads += 1; return reads == 1 ? [tool] : nil }
    let success = loader.$hasSnapshot.sink { if $0 { loaded.fulfill() } }
    let failure = loader.$refreshFailed.sink { if $0 { failed.fulfill() } }
    loader.refresh(identity: "owner"); await fulfillment(of: [loaded], timeout: 3)
    loader.refresh(identity: "owner"); await fulfillment(of: [failed], timeout: 3)
    XCTAssertEqual(loader.tools, [tool]); XCTAssertTrue(loader.isCurrent(identity: "owner"))
    XCTAssertTrue(loader.refreshFailed)
    withExtendedLifetime((success, failure)) {}
  }

  func testHomeCatalogInvalidationAndOffscreenWakeDoNotReactivateSources() async throws {
    let tool = try Self.tool("loaded"), loaded = expectation(description: "Loaded before invalidation")
    var reads = 0
    let loader = AgentHomeNativeCatalogLoader { reads += 1; return [tool] }
    let observation = loader.$hasSnapshot.sink { if $0 { loaded.fulfill() } }
    loader.refresh(identity: "owner"); await fulfillment(of: [loaded], timeout: 3)
    loader.invalidate(); loader.refreshIfActive(identity: "another-owner")
    XCTAssertEqual(reads, 1); XCTAssertTrue(loader.tools.isEmpty); XCTAssertFalse(loader.hasSnapshot)
    XCTAssertFalse(loader.isCurrent(identity: "owner")); XCTAssertFalse(loader.isCurrent(identity: "another-owner"))
    loader.refresh(identity: "")
    XCTAssertEqual(reads, 1)
    withExtendedLifetime(observation) {}
  }

  func testHomeCatalogUnknownAndSuccessfullyEmptyAreDifferentStates() async {
    let loaded = expectation(description: "Empty but complete snapshot")
    let loader = AgentHomeNativeCatalogLoader { [] }
    XCTAssertFalse(loader.hasSnapshot); XCTAssertFalse(loader.isCurrent(identity: "owner"))
    let observation = loader.$hasSnapshot.sink { if $0 { loaded.fulfill() } }
    loader.refresh(identity: "owner"); await fulfillment(of: [loaded], timeout: 3)
    XCTAssertTrue(loader.hasSnapshot); XCTAssertTrue(loader.tools.isEmpty); XCTAssertEqual(loader.availableCount, 0)
    XCTAssertTrue(loader.isCurrent(identity: "owner")); XCTAssertFalse(loader.isCurrent(identity: "foreign"))
    withExtendedLifetime(observation) {}
  }

  nonisolated private static func tool(_ suffix: String, risk: AgentNativeToolRisk = .low,
                                      status: AgentNativeToolAvailabilityStatus = .available) throws -> AgentNativeToolDescriptor {
    try .init(id: "synthetic.home.\(suffix)", version: "1.0.0", title: "Synthetic", description: "Synthetic descriptor",
      location: .phone, risk: risk, availability: .init(status: status))
  }
}
