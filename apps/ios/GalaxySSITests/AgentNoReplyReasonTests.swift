import XCTest
@testable import GalaxySSI

final class AgentNoReplyReasonTests: XCTestCase {
  func testPermissionWaitingHasHighestPriority() {
    XCTAssertEqual(
      AgentNoReplyReasonPolicy.classify(
        AgentNoReplySignal(
          taskStatus: "waiting_approval",
          routeKind: .desktopAgent,
          routeStatus: .disconnected,
          networkAvailable: false
        )
      ),
      .permissionWaiting
    )
  }

  func testMissingPhoneNetworkIsExplainedBeforeRemoteAvailability() {
    XCTAssertEqual(
      AgentNoReplyReasonPolicy.classify(
        AgentNoReplySignal(
          taskStatus: "timed_out",
          routeKind: .desktopAgent,
          endpointStatus: .offline,
          networkAvailable: false
        )
      ),
      .networkUnavailable
    )
  }

  func testDisconnectedDesktopIsNotReportedAsGenericTimeout() {
    XCTAssertEqual(
      AgentNoReplyReasonPolicy.classify(
        AgentNoReplySignal(
          taskStatus: "timed_out",
          routeKind: .desktopAgent,
          endpointStatus: .unreachable
        )
      ),
      .desktopOffline
    )
  }

  func testBusyAgentIsDistinctFromUnavailableAgent() {
    XCTAssertEqual(
      AgentNoReplyReasonPolicy.classify(
        AgentNoReplySignal(taskStatus: "queued", endpointStatus: .busy)
      ),
      .agentBusy
    )
  }

  func testSetupAndStartFailuresAreActionable() {
    XCTAssertEqual(
      AgentNoReplyReasonPolicy.classify(
        AgentNoReplySignal(
          taskStatus: "failed",
          error: "Codex could not start",
          routeKind: .desktopAgent,
          routeStatus: .available
        )
      ),
      .desktopAgentStartFailed
    )
    XCTAssertEqual(
      AgentNoReplyReasonPolicy.classify(
        AgentNoReplySignal(routeStatus: .needsSetup)
      ),
      .configurationRequired
    )
  }

  func testAuthenticationConfigurationToolsAndInvalidInputHaveDistinctReasons() {
    XCTAssertEqual(
      AgentNoReplyReasonPolicy.classify(AgentNoReplySignal(error: "HTTP 401: invalid API key")),
      .authenticationRequired
    )
    XCTAssertEqual(
      AgentNoReplyReasonPolicy.classify(AgentNoReplySignal(error: "Cloud provider is not configured")),
      .configurationRequired
    )
    XCTAssertEqual(
      AgentNoReplyReasonPolicy.classify(AgentNoReplySignal(error: "python: command not found")),
      .toolUnavailable
    )
    XCTAssertEqual(
      AgentNoReplyReasonPolicy.classify(AgentNoReplySignal(error: "Unsupported file format")),
      .invalidRequest
    )
  }

  func testDesktopStartFailureRequiresAnOnlineDesktopRoute() {
    XCTAssertEqual(
      AgentNoReplyReasonPolicy.classify(
        AgentNoReplySignal(
          error: "Codex could not start",
          routeKind: .desktopAgent,
          routeStatus: .disconnected
        )
      ),
      .desktopOffline
    )
    XCTAssertEqual(
      AgentNoReplyReasonPolicy.classify(
        AgentNoReplySignal(
          error: "Codex could not start",
          routeKind: .unknown,
          routeStatus: .available
        )
      ),
      .agentUnavailable
    )
  }

  func testGenericTimeoutAndUnknownRemainSeparate() {
    XCTAssertEqual(
      AgentNoReplyReasonPolicy.classify(AgentNoReplySignal(taskStatus: "timed_out")),
      .timedOut
    )
    XCTAssertEqual(
      AgentNoReplyReasonPolicy.classify(
        AgentNoReplySignal(taskStatus: "failed", error: "Unexpected terminal state")
      ),
      .unknown
    )
    XCTAssertEqual(
      AgentNoReplyReasonPolicy.classify(
        AgentNoReplySignal(
          taskStatus: "timed_out",
          networkRequired: false,
          networkAvailable: false
        )
      ),
      .timedOut
    )
  }

  func testWireNamesAndDisplayTextRemainAndroidCompatible() throws {
    let signal = AgentNoReplySignal(
      taskStatus: "failed",
      error: "Credentials expired",
      currentStep: "open provider",
      routeKind: .cloudModel,
      routeStatus: .available,
      endpointStatus: .permissionRequired,
      networkRequired: true,
      networkAvailable: true
    )
    let encoded = try JSONEncoder().encode(signal)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let display = AgentNoReplyReasonPolicy.display(for: .authenticationRequired)

    XCTAssertEqual(object["task_status"] as? String, "failed")
    XCTAssertEqual(object["current_step"] as? String, "open provider")
    XCTAssertEqual(object["route_kind"] as? String, AgentRouteKind.cloudModel.rawValue)
    XCTAssertEqual(object["route_status"] as? String, AgentConnectorStatus.available.rawValue)
    XCTAssertEqual(object["endpoint_status"] as? String, AgentEndpointStatus.permissionRequired.rawValue)
    XCTAssertEqual(object["network_required"] as? Bool, true)
    XCTAssertEqual(object["network_available"] as? Bool, true)
    XCTAssertEqual(AgentNoReplyReason.authenticationRequired.rawValue, "AUTHENTICATION_REQUIRED")
    XCTAssertEqual(display.reason, .authenticationRequired)
    XCTAssertFalse(display.title.isEmpty)
    XCTAssertFalse(display.message.isEmpty)
  }

  func testRecoveryCardShowsBoundedExactFailureInsteadOfGenericFallback() throws {
    let block = try XCTUnwrap(AgentFailureRecoveryRichContent.recoveryBlock(
      taskId: "task-1",
      conversationId: "conversation-1",
      turnId: "turn-1",
      agentId: "cloud-model",
      originalGoal: "Inspect the runtime",
      failure: "Runtime broker rejected the package\n\n\n\nLinux package index is missing",
      status: "failed",
      title: "Agent task needs recovery",
      message: "The Agent did not complete the task."
    ))

    XCTAssertEqual(
      block.text,
      "Runtime broker rejected the package\n\nLinux package index is missing"
    )
    XCTAssertEqual(block.fallbackText, block.text)
  }
}
