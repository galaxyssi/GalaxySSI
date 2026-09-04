import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentControlPlaneActionExecutorRoutesConnectorOnlyOnceAndAnnotatesMetadata() {
    var executions = 0
    let delegate = TestAgentActionExecutor { action, _ in
      executions += 1
      return AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Waiting",
        metadata: [
          "awaiting_response": "true",
          "source_message_id": "42",
          "contact_id": "codex"
        ]
      )
    }
    let executor = AgentControlPlaneActionExecutor(
      registrationSource: { [actionExecutorRegistration()] },
      delegate: delegate
    )
    let action = actionExecutorConnectorAction()

    let first = executor.execute(action: action, screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent"))
    let replay = executor.execute(action: action, screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent"))

    XCTAssertTrue(first.success)
    XCTAssertTrue(replay.success)
    XCTAssertEqual(executions, 1)
    XCTAssertEqual(first.metadata["control_plane_run_id"], replay.metadata["control_plane_run_id"])
    XCTAssertEqual(first.metadata["control_plane_agent_id"], "codex")
    XCTAssertEqual(first.metadata["control_plane_remote_run_id"], "42")
    XCTAssertEqual(first.metadata["control_plane_adapter_family"], "codex")
    XCTAssertEqual(first.metadata["control_plane_health_scope"], "desktop-installation:codex")
  }

  func testAgentControlPlaneActionExecutorFallsBackForNonConnectorAndTeamSpec() {
    var delegatedIds: [String] = []
    let delegate = TestAgentActionExecutor { action, _ in
      delegatedIds.append(action.id)
      return AgentActionResult(actionId: action.id, success: true, message: "delegated")
    }
    let executor = AgentControlPlaneActionExecutor(
      registrationSource: { [actionExecutorRegistration()] },
      delegate: delegate
    )
    let draft = AgentAction(
      id: "draft",
      kind: .draftPlan,
      target: "Codex",
      risk: .low,
      status: .proposed,
      description: "Plan"
    )
    let team = actionExecutorConnectorAction(
      id: "team",
      parameters: ["_galaxyssi_agent_team_spec": "{}"]
    )

    XCTAssertTrue(executor.execute(action: draft, screen: AgentScreenContext(foregroundApp: "GalaxySSI")).success)
    XCTAssertTrue(executor.execute(action: team, screen: AgentScreenContext(foregroundApp: "GalaxySSI")).success)
    XCTAssertEqual(delegatedIds, ["draft", "team"])
  }

  func testAgentControlPlaneActionExecutorIgnoreDeliveryNeverTouchesDelegate() {
    var executions = 0
    let delegate = TestAgentActionExecutor { action, _ in
      executions += 1
      return AgentActionResult(actionId: action.id, success: false, message: "unexpected")
    }
    let executor = AgentControlPlaneActionExecutor(
      registrationSource: { [actionExecutorRegistration()] },
      delegate: delegate
    )
    let result = executor.execute(
      action: actionExecutorConnectorAction(parameters: ["delivery_mode": "ignore"]),
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")
    )

    XCTAssertTrue(result.success)
    XCTAssertEqual(result.metadata["delivery_mode"], "ignore")
    XCTAssertEqual(result.metadata["control_plane_agent_id"], "codex")
    XCTAssertEqual(executions, 0)
  }

  func testAgentControlPlaneActionExecutorRejectsIncompatibleProtocolBeforeDelegate() {
    var executions = 0
    let delegate = TestAgentActionExecutor { action, _ in
      executions += 1
      return AgentActionResult(actionId: action.id, success: true, message: "unexpected")
    }
    let executor = AgentControlPlaneActionExecutor(
      registrationSource: {
        [actionExecutorRegistration(
          protocolRange: AgentProtocolRange(preferred: "2.0", minimum: "2.0", maximum: "2.1")
        )]
      },
      delegate: delegate
    )

    let result = executor.execute(
      action: actionExecutorConnectorAction(),
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")
    )

    XCTAssertFalse(result.success)
    XCTAssertTrue(result.message.contains("compatible"))
    XCTAssertEqual(result.metadata["control_plane_agent_id"], "codex")
    XCTAssertEqual(executions, 0)
  }

  func testActionExecutorAgentTransportBuffersRunEventsAndResults() async throws {
    let registration = actionExecutorRegistration()
    let delegate = TestAgentActionExecutor { action, _ in
      AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Ready for user response",
        metadata: [
          "awaiting_response": "true",
          "source_message_id": "73"
        ]
      )
    }
    let provider = ActionExecutorAgentProvider(
      registrationSource: { [registration] },
      delegate: delegate
    )
    let adapter = try XCTUnwrap(try await provider.adapter(agentId: "codex"))
    let request = AgentRunRequest(
      conversationId: "conversation",
      messageId: "message",
      taskId: "turn",
      runId: "run-buffered",
      goal: "Inspect project",
      context: ["managed_team": .bool(true)],
      idempotencyKey: "run-buffered"
    )
    provider.prepare(
      agentId: "codex",
      request: request,
      action: actionExecutorConnectorAction(),
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")
    )

    let handle = try await adapter.startRun(request)
    var iterator = adapter.observeEvents(runId: request.runId).makeAsyncIterator()
    let created = await iterator.next()
    let started = await iterator.next()
    let connected = await iterator.next()
    let waiting = await iterator.next()

    XCTAssertEqual(handle.remoteRunId, "73")
    XCTAssertEqual(provider.result(agentId: "codex", runId: request.runId)?.message, "Ready for user response")
    XCTAssertEqual(created?.type, .runCreated)
    XCTAssertEqual(started?.type, .runStarted)
    XCTAssertEqual(connected?.type, .agentConnected)
    XCTAssertEqual(waiting?.type, .waitingForDevice)
    XCTAssertEqual(waiting?.sequence, 4)
    XCTAssertEqual(waiting?.payload["source_message_id"]?.stringValue, "73")
  }

  func testActionExecutorKeepsExecutionPolicySeparateFromToolEvidence() async throws {
    let registration = actionExecutorRegistration()
    var receivedPolicyPrompt = ""
    let delegate = TestAgentActionExecutor { action, _ in
      receivedPolicyPrompt = action.parameters[AgentExecutionPolicyPrompt.contextKey] ?? ""
      return AgentActionResult(actionId: action.id, success: true, message: "Done")
    }
    let provider = ActionExecutorAgentProvider(
      registrationSource: { [registration] },
      delegate: delegate
    )
    let adapter = try XCTUnwrap(try await provider.adapter(agentId: "codex"))
    let policyPrompt = "Research and compare two primary sources"
    let request = AgentRunRequest(
      conversationId: "conversation",
      messageId: "message",
      taskId: "turn",
      runId: "run-policy",
      goal: "Immutable tool receipt: the workflow was installed successfully",
      context: [AgentExecutionPolicyPrompt.contextKey: .string(policyPrompt)],
      idempotencyKey: "run-policy"
    )
    provider.prepare(
      agentId: "codex",
      request: request,
      action: actionExecutorConnectorAction(),
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")
    )

    _ = try await adapter.startRun(request)

    XCTAssertEqual(receivedPolicyPrompt, policyPrompt)
    XCTAssertEqual(request.executionPolicyPrompt, policyPrompt)
  }

  func testActionExecutorAgentProviderRecordsNativeToolLifecycleEventsIntoRunStream() async throws {
    let registration = actionExecutorRegistration()
    var eventSink = AgentNativeToolLifecycleEventSink.none
    let delegate = TestAgentActionExecutor { _, _ in
      eventSink.emit(
        AgentNativeToolLifecycleEvent(
          stage: .progress,
          toolId: "galaxyssi.workspace.file.read.text",
          invocationId: "native-invoke",
          stepId: "native-step",
          conversationId: "conversation",
          turnId: "message",
          progressStage: "reading",
          message: "Reading file",
          percent: 64,
          sequence: 5,
          timestampMillis: 12_000
        )
      )
      return AgentActionResult(actionId: "route-codex", success: true, message: "Done")
    }
    let provider = ActionExecutorAgentProvider(
      registrationSource: { [registration] },
      delegate: delegate
    )
    eventSink = provider.nativeToolLifecycleEventSink()
    let adapter = try XCTUnwrap(try await provider.adapter(agentId: "codex"))
    let request = AgentRunRequest(
      conversationId: "conversation",
      messageId: "message",
      taskId: "turn",
      runId: "run-native-tool",
      goal: "Read a workspace file",
      context: ["managed_team": .bool(true)],
      idempotencyKey: "run-native-tool"
    )
    provider.prepare(
      agentId: "codex",
      request: request,
      action: actionExecutorConnectorAction(id: "native-step"),
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")
    )

    _ = try await adapter.startRun(request)
    var iterator = adapter.observeEvents(runId: request.runId).makeAsyncIterator()
    let created = await iterator.next()
    let started = await iterator.next()
    let connected = await iterator.next()
    let native = try XCTUnwrap(await iterator.next())
    let completed = await iterator.next()

    XCTAssertEqual(created?.type, .runCreated)
    XCTAssertEqual(started?.type, .runStarted)
    XCTAssertEqual(connected?.type, .agentConnected)
    XCTAssertEqual(native.type, .toolProgress)
    XCTAssertEqual(native.runId, "run-native-tool")
    XCTAssertEqual(native.messageId, "message")
    XCTAssertEqual(native.taskId, "message")
    XCTAssertEqual(native.stepId, "native-step")
    XCTAssertEqual(native.toolCallId, "native-invoke")
    XCTAssertEqual(native.agentId, "galaxyssi-mobile")
    XCTAssertEqual(native.deviceId, "desktop-device")
    XCTAssertEqual(native.sequence, 5)
    XCTAssertEqual(native.payload["timeline_kind"]?.stringValue, "tool")
    XCTAssertEqual(native.payload["tool_id"]?.stringValue, "galaxyssi.workspace.file.read.text")
    XCTAssertEqual(native.payload["progress_stage"]?.stringValue, "reading")
    XCTAssertEqual(native.payload["percent"]?.intValue, 64)
    XCTAssertEqual(completed?.type, .runCompleted)
  }

  func actionExecutorConnectorAction(
    id: String = "route-codex",
    parameters: [String: String] = [:]
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: .callConnector,
      target: "Codex",
      risk: .low,
      status: .proposed,
      description: "Ask Codex",
      parameters: [
        "connector_id": "codex",
        "prompt": "Inspect the project",
        "_galaxyssi_conversation_id": "conversation",
        "_galaxyssi_turn_id": "turn"
      ].merging(parameters) { _, new in new },
      requiresConfirmation: false
    )
  }

  func actionExecutorRegistration(
    protocolRange: AgentProtocolRange = AgentProtocolRange(
      preferred: "1.0",
      minimum: "1.0",
      maximum: "1.0",
      features: ["run.cancel", "run.recover", "run.events", "message.respond", "message.observe"]
    )
  ) -> AgentRegistration {
    AgentRegistration(
      agentId: "codex",
      installationId: "desktop-installation",
      deviceId: "desktop-device",
      providerId: "desktop-provider",
      displayName: "Codex",
      kind: .agent,
      location: .trustedDesktop,
      status: .online,
      capabilities: [.code, .taskExecution],
      protocol: protocolRange,
      connectionKind: .galaxyssiLink,
      trust: .verifiedPaired,
      adapterType: "codex-app-server-or-cli",
      runtimeFailureDomain: "desktop-installation:codex"
    )
  }
}
