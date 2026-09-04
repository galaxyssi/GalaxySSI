import XCTest
@testable import GalaxySSI

final class GlobalCapabilityObservationsTests: XCTestCase {
  func testMcpTimestampOnlyUpdatesAreSuppressedAndSecretsRedacted() throws {
    let connection = try mcpConnection()
    let installed = try XCTUnwrap(
      GlobalCapabilityObservationExtractor.mcpMutations(
        before: [],
        after: [connection],
        timestampMillis: 1_000
      ).single
    )

    XCTAssertEqual(installed.type, .resourceRegistered)
    XCTAssertEqual(installed.metadata["resource_kind"], "mcp")
    XCTAssertEqual(installed.metadata["resource_state"], "available")
    XCTAssertEqual(installed.metadata["callable"], "true")
    XCTAssertEqual(installed.metadata["tool_count"], "1")
    assertEvent(installed, doesNotExpose: [
      "mcp-private-id",
      "private.example.internal",
      "access-token",
      "secret backend error"
    ])

    var timestampOnly = connection
    timestampOnly.updatedAtMillis = 2_000
    timestampOnly.lastValidatedAtMillis = 2_000

    XCTAssertTrue(
      GlobalCapabilityObservationExtractor.mcpMutations(
        before: [connection],
        after: [timestampOnly],
        timestampMillis: 2_000
      ).isEmpty
    )
  }

  func testAgentHeartbeatsPublishOnlyAvailabilityOrCapacityChanges() {
    let online = agentRegistration(status: .online, activeRuns: 0)
    var sameAvailability = online
    sameAvailability.activeRuns = 1
    sameAvailability.lastHeartbeatMillis = 2_000
    sameAvailability.updatedAtMillis = 2_000
    var atCapacity = sameAvailability
    atCapacity.activeRuns = 2
    atCapacity.lastHeartbeatMillis = 3_000
    atCapacity.updatedAtMillis = 3_000

    XCTAssertTrue(
      GlobalCapabilityObservationExtractor.agentMutations(
        before: [online],
        after: [sameAvailability],
        timestampMillis: 2_000
      ).isEmpty
    )

    let event = GlobalCapabilityObservationExtractor.agentMutations(
      before: [sameAvailability],
      after: [atCapacity],
      timestampMillis: 3_000
    ).single

    XCTAssertEqual(event?.type, .resourceUpdated)
    XCTAssertEqual(event?.metadata["resource_kind"], "agent")
    XCTAssertEqual(event?.metadata["resource_state"], "busy")
    XCTAssertEqual(event?.metadata["at_capacity"], "true")
    if let event {
      assertEvent(event, doesNotExpose: [
        "agent-private-id",
        "installation-secret",
        "device-secret",
        "provider-secret"
      ])
    }
  }

  func testDeviceResourceEventsNeverExposeConnectionMaterial() {
    let home = GlobalCapabilityObservationExtractor.homeAssistantMutations(
      before: .default,
      after: HomeAssistantSettings(
        enabled: true,
        baseUrl: "https://home.private.example/api",
        accessToken: "long-lived-access-token",
        defaultEntityId: "lock.private_front_door"
      ),
      timestampMillis: 1_000
    ).single
    let connector = CustomDeviceConnector(
      id: "device-private-id",
      name: "Workshop relay",
      transport: .httpRest,
      endpoint: "https://192.0.2.10/private-control",
      commandTarget: "relay/private-channel",
      username: "private-user",
      authToken: "private-token",
      risk: .high
    )
    let registered = GlobalCapabilityObservationExtractor.customDeviceMutations(
      before: [],
      after: [connector],
      timestampMillis: 1_100
    ).single
    let removed = GlobalCapabilityObservationExtractor.customDeviceMutations(
      before: [connector],
      after: [],
      timestampMillis: 1_200
    ).single

    XCTAssertEqual(home?.metadata["resource_kind"], "home_assistant")
    XCTAssertEqual(home?.metadata["resource_state"], "ready")
    XCTAssertEqual(home?.metadata["credentials_configured"], "true")
    XCTAssertEqual(registered?.metadata["resource_kind"], "custom_device")
    XCTAssertEqual(registered?.metadata["resource_state"], "ready")
    XCTAssertEqual(registered?.metadata["risk"], "high")
    XCTAssertEqual(removed?.type, .resourceRemoved)
    XCTAssertEqual(removed?.metadata["projection"], "retract_stable_keys")

    [home, registered, removed].compactMap { $0 }.forEach {
      assertEvent($0, doesNotExpose: [
        "home.private.example",
        "long-lived-access-token",
        "lock.private_front_door",
        "device-private-id",
        "192.0.2.10",
        "private-channel",
        "private-user",
        "private-token"
      ])
    }
  }

  func testHealthTransitionsPublishOnlyStateChanges() {
    let healthy = AgentResourceHealth(successes: 1, lastUpdatedAt: 1_000)
    let degraded = AgentResourceHealth(
      successes: 1,
      failures: 1,
      consecutiveFailures: 1,
      lastUpdatedAt: 2_000
    )
    let repeatedDegraded = AgentResourceHealth(
      successes: 1,
      failures: 2,
      consecutiveFailures: 2,
      lastUpdatedAt: 3_000
    )
    let unavailable = AgentResourceHealth(
      successes: 1,
      failures: 3,
      consecutiveFailures: 3,
      circuitOpenUntil: 100_000,
      lastUpdatedAt: 4_000
    )
    let recovered = AgentResourceHealth(
      successes: 2,
      failures: 3,
      consecutiveFailures: 0,
      lastUpdatedAt: 5_000
    )

    let healthyEvent = GlobalCapabilityObservationExtractor.resourceHealthTransition(
      resourceId: "target:private-agent-id",
      before: AgentResourceHealth(),
      after: healthy,
      timestampMillis: 1_000
    )
    let degradedEvent = GlobalCapabilityObservationExtractor.resourceHealthTransition(
      resourceId: "target:private-agent-id",
      before: healthy,
      after: degraded,
      timestampMillis: 2_000
    )
    let repeatedEvent = GlobalCapabilityObservationExtractor.resourceHealthTransition(
      resourceId: "target:private-agent-id",
      before: degraded,
      after: repeatedDegraded,
      timestampMillis: 3_000
    )
    let unavailableEvent = GlobalCapabilityObservationExtractor.resourceHealthTransition(
      resourceId: "target:private-agent-id",
      before: repeatedDegraded,
      after: unavailable,
      timestampMillis: 4_000
    )
    let recoveredEvent = GlobalCapabilityObservationExtractor.resourceHealthTransition(
      resourceId: "target:private-agent-id",
      before: unavailable,
      after: recovered,
      timestampMillis: 5_000
    )

    XCTAssertEqual(healthyEvent?.metadata["resource_state"], "healthy")
    XCTAssertEqual(degradedEvent?.metadata["resource_state"], "degraded")
    XCTAssertNil(repeatedEvent)
    XCTAssertEqual(unavailableEvent?.metadata["resource_state"], "unavailable")
    XCTAssertEqual(recoveredEvent?.metadata["resource_state"], "healthy")
    if let unavailableEvent {
      assertEvent(unavailableEvent, doesNotExpose: ["private-agent-id"])
    }
  }

  func testSnapshotResetUsesLocalOnlyCapabilityProjection() {
    let reset = GlobalCapabilityObservationExtractor.snapshotReset(timestampMillis: 2_000)

    XCTAssertEqual(reset.type, .capabilitySnapshotReset)
    XCTAssertEqual(reset.conversationId, "global-capabilities")
    XCTAssertEqual(reset.conversationTitle, "Available capabilities")
    XCTAssertEqual(reset.metadata["projection"], "reset_capabilities")
    XCTAssertEqual(reset.metadata["context_visibility"], "LOCAL_ONLY")
    XCTAssertTrue(reset.type.isCapabilityLifecycleEvent)
  }

  private func mcpConnection() throws -> AgentMcpConnection {
    AgentMcpConnection(
      id: "mcp-private-id",
      catalogId: "example.private",
      displayName: "Private research MCP",
      endpoint: "https://private.example.internal/mcp?access-token=secret",
      distribution: .remote,
      transport: .streamableHTTP,
      authProfile: try AgentMcpAuthProfile(.bearerToken),
      authState: .authenticated,
      state: .connected,
      enabled: true,
      installedAtMillis: 1_000,
      updatedAtMillis: 1_000,
      lastValidatedAtMillis: 1_000,
      lastError: "secret backend error",
      toolIds: ["research.search"]
    )
  }

  private func agentRegistration(
    status: AgentEndpointStatus,
    activeRuns: Int
  ) -> AgentRegistration {
    AgentRegistration(
      agentId: "agent-private-id",
      installationId: "installation-secret",
      deviceId: "device-secret",
      providerId: "provider-secret",
      displayName: "Codex workstation",
      kind: .agent,
      location: .trustedDesktop,
      status: status,
      capabilities: [.chat, .code, .taskExecution],
      toolIds: ["workspace.read"],
      activeRuns: activeRuns,
      maxParallelRuns: 2
    )
  }

  private func assertEvent(
    _ event: GlobalConversationEvent,
    doesNotExpose secrets: [String],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let text = eventText(event)
    for secret in secrets {
      XCTAssertFalse(
        text.contains(secret.lowercased()),
        "Event leaked \(secret)",
        file: file,
        line: line
      )
    }
  }

  private func eventText(_ event: GlobalConversationEvent) -> String {
    (
      event.content + " " +
        event.contentRef + " " +
        event.metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    ).lowercased()
  }
}

private extension Array {
  var single: Element? {
    count == 1 ? self[0] : nil
  }
}
