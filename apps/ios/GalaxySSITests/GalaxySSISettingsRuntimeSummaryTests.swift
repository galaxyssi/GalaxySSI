import XCTest
@testable import GalaxySSI

final class GalaxySSISettingsRuntimeSummaryTests: XCTestCase {
  func testNativeTotalsDoNotAdvertiseBlockedOrUnavailableToolsAsReady() throws {
    let tools = try [tool("ready"), tool("blocked", risk: .blocked), tool("setup", status: .requiresSetup),
      tool("unavailable", status: .unavailable)]
    let snapshot = GalaxySSISettingsRuntimeSummary.project(tools: tools, connections: [], localKey: "local", nowMillis: 1)
    XCTAssertEqual(snapshot.nativeToolTotal, 4); XCTAssertEqual(snapshot.nativeToolAvailable, 1)
    XCTAssertEqual(snapshot.mcpInstalled, 0); XCTAssertEqual(snapshot.mcpReady, 0)
  }

  func testRuntimeKeyChangesWithActualAvailabilityRiskAndLocalConfiguration() throws {
    var descriptor = try tool("one")
    func project(_ local: String = "local") -> GalaxySSISettingsRuntimeSummary {
      .project(tools: [descriptor], connections: [], localKey: local, nowMillis: 1)
    }
    let original = project()
    descriptor.availability = .init(status: .requiresSetup)
    XCTAssertNotEqual(project().key, original.key)
    descriptor.availability = .available; descriptor.risk = .blocked
    XCTAssertNotEqual(project().key, original.key)
    descriptor.risk = .low
    XCTAssertEqual(project(), original); XCTAssertNotEqual(project("another-local").key, original.key)
  }

  func testMcpReadinessUsesExistingAuthExpiryAndEnabledRulesAtOneSnapshotClock() throws {
    var connection = try mcp("one")
    connection.authProfile = try AgentMcpAuthProfile(.bearerToken)
    connection.authState = .authenticated; connection.expiresAtMillis = 100; connection.refreshAtMillis = 0
    func snapshot(_ now: Int64) -> GalaxySSISettingsRuntimeSummary {
      .project(tools: [], connections: [connection], localKey: "", nowMillis: now)
    }
    let before = snapshot(99), expired = snapshot(100)
    XCTAssertEqual(before.mcpInstalled, 1); XCTAssertEqual(before.mcpReady, 1)
    XCTAssertEqual(expired.mcpInstalled, 1); XCTAssertEqual(expired.mcpReady, 0)
    XCTAssertNotEqual(before.key, expired.key)
    connection.expiresAtMillis = 0; connection.enabled = false
    XCTAssertEqual(snapshot(1).mcpReady, 0)
    connection.enabled = true; connection.state = .error
    XCTAssertEqual(snapshot(1).mcpReady, 0)
    connection.state = .connected; connection.endpoint = ""
    XCTAssertEqual(snapshot(1).mcpReady, 0)
  }

  func testSnapshotRetainsValueIsolationAndOnlyAggregateCounts() throws {
    var tools = try [tool("one")], connections = try [mcp("one")]
    let original = GalaxySSISettingsRuntimeSummary.project(tools: tools, connections: connections, localKey: "", nowMillis: 1)
    tools[0].availability = .init(status: .unavailable); connections[0].enabled = false
    let changed = GalaxySSISettingsRuntimeSummary.project(tools: tools, connections: connections, localKey: "", nowMillis: 1)
    XCTAssertEqual(original.nativeToolAvailable, 1); XCTAssertEqual(original.mcpReady, 1)
    XCTAssertEqual(changed.nativeToolAvailable, 0); XCTAssertEqual(changed.mcpReady, 0)
    XCTAssertFalse(original.key.contains("https://example.invalid"))
    XCTAssertFalse(original.key.contains("Synthetic private title"))
  }

  func testSummaryCacheUsesThirtyMonotonicSecondsWithoutWallClockExtension() {
    XCTAssertTrue(GalaxySSISettingsRuntimeSummary.isFresh(storedAt: 100, now: 100))
    XCTAssertTrue(GalaxySSISettingsRuntimeSummary.isFresh(storedAt: 100, now: 129.999))
    XCTAssertFalse(GalaxySSISettingsRuntimeSummary.isFresh(storedAt: 100, now: 130))
    XCTAssertFalse(GalaxySSISettingsRuntimeSummary.isFresh(storedAt: 100, now: 99))
    XCTAssertFalse(GalaxySSISettingsRuntimeSummary.isFresh(storedAt: -1, now: 1))
    XCTAssertFalse(GalaxySSISettingsRuntimeSummary.isFresh(storedAt: .infinity, now: .infinity))
    XCTAssertFalse(GalaxySSISettingsRuntimeSummary.isFresh(storedAt: .nan, now: 1))
  }

  func testEmptyProjectionRemainsEmptyWithoutInventingToolOrMcpAvailability() {
    let empty = GalaxySSISettingsRuntimeSummary.project(tools: [], connections: [], localKey: "", nowMillis: 1)
    XCTAssertEqual(empty.nativeToolTotal, 0); XCTAssertEqual(empty.nativeToolAvailable, 0)
    XCTAssertEqual(empty.mcpInstalled, 0); XCTAssertEqual(empty.mcpReady, 0)
    XCTAssertEqual(empty.mcpRecommended, AgentDefaultCapabilityCatalog.mcpEntries.count)
  }

  private func tool(_ suffix: String, risk: AgentNativeToolRisk = .low,
                    status: AgentNativeToolAvailabilityStatus = .available) throws -> AgentNativeToolDescriptor {
    try .init(id: "synthetic.summary.\(suffix)", version: "1.0.0", title: "Synthetic private title",
      description: "Synthetic descriptor", location: .phone, risk: risk, availability: .init(status: status))
  }
  private func mcp(_ id: String) throws -> AgentMcpConnection {
    .init(id: id, displayName: "Synthetic private title", endpoint: "https://example.invalid/mcp",
      distribution: .remote, transport: .streamableHTTP, authProfile: try AgentMcpAuthProfile(.none),
      authState: .notRequired, state: .connected)
  }
}
