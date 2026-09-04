import XCTest
@testable import GalaxySSI

final class AgentExplicitToolHandlesTests: XCTestCase {
  func testHandleIsOpaqueScopedAndDoesNotExposeItsResource() throws {
    let clock = MutableClock(now: 1_000)
    let registry = AgentExplicitToolHandleRegistry(clock: { clock.now })
    let resource = ["url": ""]
    let opened = try registry.create(
      kind: "browser_session",
      resourceId: "internal-browser-resource",
      scope: AgentExplicitToolHandleScope(ownerId: "owner-1", contextId: "conversation-1"),
      capabilities: ["browser.navigate"],
      resource: resource
    )

    let handleId = try XCTUnwrap(opened["handle_id"]?.stringValue)
    XCTAssertTrue(handleId.hasPrefix("sth_browsers_"))
    XCTAssertNil(opened["resource_id"])
    XCTAssertFalse(AgentMcpJSONCodec.stringify(opened).contains("internal-browser-resource"))

    let resolved = try registry.resolve(
      handleId: handleId,
      kind: "browser_session",
      scope: AgentExplicitToolHandleScope(ownerId: "owner-1", contextId: "conversation-1"),
      requiredCapability: "browser.navigate"
    )
    XCTAssertEqual(resolved.resourceId, "internal-browser-resource")
    XCTAssertEqual((resolved.resource.rawValue as? [String: String])?["url"], "")

    XCTAssertThrowsError(
      try registry.resolve(
        handleId: handleId,
        kind: "browser_session",
        scope: AgentExplicitToolHandleScope(ownerId: "owner-1", contextId: "conversation-2"),
        requiredCapability: "browser.navigate"
      )
    ) { error in
      XCTAssertEqual((error as? AgentExplicitToolHandleException)?.code, "tool_handle_context_mismatch")
    }
  }

  func testExpiredAndReleasedHandlesFailExplicitly() throws {
    let clock = MutableClock(now: 2_000)
    let registry = AgentExplicitToolHandleRegistry(clock: { clock.now })
    let opened = try registry.create(
      kind: "browser_session",
      resourceId: "browser-1",
      scope: AgentExplicitToolHandleScope(ownerId: "owner"),
      capabilities: ["browser.close"],
      resource: "browser-resource",
      ttlMillis: 100,
      idleTimeoutMillis: 0
    )
    clock.now = 2_100

    XCTAssertThrowsError(
      try registry.resolve(
        handleId: opened["handle_id"]?.stringValue ?? "",
        kind: "browser_session",
        scope: AgentExplicitToolHandleScope(ownerId: "owner"),
        requiredCapability: "browser.close"
      )
    ) { error in
      let handleError = error as? AgentExplicitToolHandleException
      XCTAssertEqual(handleError?.code, "tool_handle_expired")
      XCTAssertEqual(handleError?.retryable, true)
    }

    let replacement = try registry.create(
      kind: "browser_session",
      resourceId: "browser-2",
      scope: AgentExplicitToolHandleScope(ownerId: "owner"),
      capabilities: ["browser.close"],
      resource: "browser-resource"
    )
    XCTAssertTrue(try registry.release(
      handleId: replacement["handle_id"]?.stringValue ?? "",
      scope: AgentExplicitToolHandleScope(ownerId: "owner")
    ))
    XCTAssertEqual(registry.status().activeCount, 0)
  }

  private final class MutableClock {
    var now: Int64

    init(now: Int64) {
      self.now = now
    }
  }
}
