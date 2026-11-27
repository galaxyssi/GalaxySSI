import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testQueuedConnectorPreparationDoesNotFabricateRemoteAcceptance() throws {
    var action = nativeConnectorWaitFixture().action
    action.parameters[AgentIOSConnectorDispatch.sourceKey] = UUID().uuidString
    action.parameters[AgentIOSConnectorDispatch.profileKey] = "profile"
    action.parameters[AgentIOSConnectorDispatch.permissionKey] = "approved-mode"
    let pending = AgentIOSConnectorDispatch.prepare(action)
    XCTAssertTrue(pending.success)
    XCTAssertEqual(pending.message, "Queued")
    XCTAssertEqual(pending.metadata["awaiting_response"], "true")
    XCTAssertEqual(pending.metadata["completion_verified"], "false")
    for key in ["remote_task_status", "remote_task_status_seq", "remote_task_status_updated_at", "transport_accepted_at"] {
      XCTAssertNil(pending.metadata[key], key)
    }
    let start = try XCTUnwrap(pending.metadata["resource_started_at"].flatMap(Int64.init))
    XCTAssertTrue(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: pending.metadata,
      nowMillis: start + 14_999).isEmpty)
    let overdue = AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: pending.metadata,
      nowMillis: start + 15_000)
    XCTAssertEqual(overdue["native_connector_observation_timeout_stage"], AgentConnectorTimeoutStage.notAccepted.rawValue)
    XCTAssertNil(overdue["awaiting_response"])
    XCTAssertNil(overdue["non_retriable"])
  }

  func testPreparedConnectorAcceptanceRequiresTheOriginalSourceAndContact() throws {
    var action = nativeConnectorWaitFixture().action
    action.parameters[AgentIOSConnectorDispatch.sourceKey] = UUID().uuidString
    action.parameters[AgentIOSConnectorDispatch.profileKey] = "profile"
    action.parameters[AgentIOSConnectorDispatch.permissionKey] = "approved-mode"
    let pending = AgentIOSConnectorDispatch.prepare(action)
    let source = try XCTUnwrap(pending.metadata["source_message_id"].flatMap(Int64.init))
    let contact = try XCTUnwrap(pending.metadata["contact_id"])
    XCTAssertNil(AgentConnectorTransportReceiptRecorder.recordAccepted(pending: pending,
      sourceMessageId: source + 1, contactId: contact, nowMillis: 50_000))
    XCTAssertNil(AgentConnectorTransportReceiptRecorder.recordAccepted(pending: pending,
      sourceMessageId: source, contactId: "foreign", nowMillis: 50_000))
    let accepted = try XCTUnwrap(AgentConnectorTransportReceiptRecorder.recordAccepted(pending: pending,
      sourceMessageId: source, contactId: contact, nowMillis: 50_000))
    XCTAssertEqual(accepted.metadata["remote_task_status"], "accepted")
    XCTAssertEqual(accepted.metadata["transport_accepted_at"], "50000")
    XCTAssertEqual(accepted.metadata["awaiting_response"], "true")
    XCTAssertEqual(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: accepted.metadata,
      nowMillis: 95_000)["native_connector_observation_timeout_stage"], AgentConnectorTimeoutStage.notRunning.rawValue)
    XCTAssertEqual(try JSONDecoder().decode(AgentActionResult.self, from: JSONEncoder().encode(accepted)), accepted)
  }

  func testOwnedConnectorRunIdentitySeparatesRetriesAndPreservesFirstManualIdentity() throws {
    let original = nativeConnectorWaitFixture().action
    let first = AgentControlPlaneActionExecutor.connectorRunId(action: original, agentId: "codex")
    XCTAssertEqual(first, AgentControlPlaneActionExecutor.stableRunId(conversationId: "conversation",
      turnId: "turn", actionId: original.id, agentId: "codex"))
    var retry = original
    retry.parameters["routing_fallback_action_id"] = retry.id
    retry.parameters[AgentConnectorFallbackAction.attemptedParameter] = "codex,cloud-model:deepseek"
    retry.parameters["routing_retried_resource_ids"] = "codex"
    let attempt = AgentControlPlaneActionExecutor.connectorRunId(action: retry, agentId: "codex")
    XCTAssertNotEqual(first, attempt)
    let reopened = try JSONDecoder().decode(AgentAction.self, from: JSONEncoder().encode(retry))
    XCTAssertEqual(attempt, AgentControlPlaneActionExecutor.connectorRunId(action: reopened, agentId: "codex"))
    retry.parameters["manual_target_locked"] = "true"
    XCTAssertEqual(first, AgentControlPlaneActionExecutor.connectorRunId(action: retry, agentId: "codex"))
    var unrelated = original
    unrelated.parameters["routing_fallback_action_id"] = "another-action"
    unrelated.parameters[AgentConnectorFallbackAction.attemptedParameter] = "codex"
    XCTAssertEqual(first, AgentControlPlaneActionExecutor.connectorRunId(action: unrelated, agentId: "codex"))
  }

  func testQueuedConnectorKickoffRunsOnlyAfterDurableOwnershipAndDoesNotReplay() {
    for reject in [false, true] {
      let ledger: AgentManagedResponseLedger = reject
        ? RejectingConnectorResponseLedger() : InMemoryAgentManagedResponseLedger()
      var starts = 0
      var ownedAtStart = false
      let queued = AgentIOSQueuedConnectorExecutor(delegate: TestAgentActionExecutor { action, _ in
        AgentActionResult(actionId: action.id, success: false, message: "Unexpected native delegation")
      }) { action, receipt in
        starts += 1
        if let request = AgentIOSConnectorDispatch(action: action, receipt: receipt) {
          ownedAtStart = (try? ledger.ownsResponse(request.response("probe", success: true))) == true
        }
      }
      let executor = AgentControlPlaneActionExecutor(registrationSource: { [actionExecutorRegistration()] },
        delegate: queued, managedResponseLedger: ledger)
      var action = nativeConnectorWaitFixture().action
      action.parameters[AgentIOSConnectorDispatch.sourceKey] = UUID().uuidString
      action.parameters[AgentIOSConnectorDispatch.profileKey] = "profile"
      action.parameters[AgentIOSConnectorDispatch.permissionKey] = "approved-mode"
      let screen = AgentScreenContext(foregroundApp: "GalaxySSI")
      let first = executor.execute(action: action, screen: screen)
      let replay = executor.execute(action: action, screen: screen)
      XCTAssertEqual(starts, reject ? 0 : 1)
      XCTAssertEqual(ownedAtStart, !reject)
      XCTAssertEqual(first.success, !reject)
      XCTAssertEqual(replay.success, !reject)
      if reject { XCTAssertEqual(first.metadata["effect_outcome_unknown"], "true") }
      else { XCTAssertEqual(first.metadata["awaiting_response"], "true") }
    }
  }

  func testQueuedConnectorIdentityAndHostPolicyMatchKeepExactSourceAndPrompt() throws {
    let fixture = nativeConnectorWaitFixture()
    var action = fixture.action
    action.parameters[AgentIOSConnectorDispatch.sourceKey] = fixture.outgoing.id.uuidString
    action.parameters[AgentIOSConnectorDispatch.profileKey] = "profile"
    action.parameters[AgentIOSConnectorDispatch.permissionKey] = "approved-mode"
    var pending = AgentIOSConnectorDispatch.prepare(action)
    XCTAssertTrue(pending.success)
    XCTAssertEqual(pending.metadata["source_message_id"], AgentIOSConnectorDispatch.prepare(action).metadata["source_message_id"])
    var other = action
    other.parameters[AgentIOSConnectorDispatch.profileKey] = "another-profile"
    XCTAssertNotEqual(pending.metadata["source_message_id"], AgentIOSConnectorDispatch.prepare(other).metadata["source_message_id"])
    pending.metadata["control_plane_agent_id"] = "codex"
    pending.metadata["control_plane_run_id"] = fixture.result.metadata["control_plane_run_id"]
    let waiting = try XCTUnwrap(AgentNativeConnectorContinuation.waitingAction(action,
      result: pending, task: fixture.task, outgoing: fixture.outgoing))
    var prepared = action
    prepared.parameters[AgentExecutionPolicyPrompt.contextKey] = "Host execution policy"
    let request = try XCTUnwrap(AgentIOSConnectorDispatch(action: prepared, receipt: pending))
    XCTAssertTrue(request.matchesWaitingAction(waiting))
    XCTAssertTrue(request.executionPrompt.hasPrefix("Host execution policy"))
    var changed = waiting
    changed.parameters["prompt"] = "Another request"
    XCTAssertFalse(request.matchesWaitingAction(changed))
    changed = action
    changed.parameters.removeValue(forKey: AgentIOSConnectorDispatch.sourceKey)
    XCTAssertFalse(AgentIOSConnectorDispatch.prepare(changed).success)
  }

  func testNativeConnectorWaitRoundTripsAndOnlySettlesExactCommittedOwner() throws {
    let fixture = nativeConnectorWaitFixture()
    let waiting = try XCTUnwrap(AgentNativeConnectorContinuation.waitingAction(fixture.action,
      result: fixture.result, task: fixture.task, outgoing: fixture.outgoing))
    XCTAssertEqual(waiting.status, .waitingResponse)
    let restored = try JSONDecoder().decode(AgentAction.self, from: JSONEncoder().encode(waiting))
    XCTAssertEqual(AgentNativeConnectorContinuation.pendingResult(restored), fixture.result)
    let response = AgentConnectorResponse(sourceMessageId: 9920, contactId: "codex", content: "Done",
      conversationId: "conversation", turnId: "turn", taskId: "remote-task", taskStatus: "completed")
    let record = AgentManagedResponseRecord(ownerRunId: fixture.result.metadata["control_plane_run_id"]!,
      supervisorRunId: "parent", agentId: "codex", deliveryMode: .respond, sourceMessageId: 9920,
      contactId: "codex", conversationId: "conversation", turnId: "turn", taskId: "remote-task",
      state: .completed, response: response)
    let settled = try XCTUnwrap(AgentNativeConnectorContinuation.settle(fixture.result, record: record))
    XCTAssertTrue(settled.success)
    XCTAssertEqual(settled.metadata["awaiting_response"], "false")
    var uncertain = fixture.result
    uncertain.metadata["native_connector_dispatch_uncertain"] = "true"
    uncertain.metadata["effect_outcome_unknown"] = "true"
    uncertain.metadata["non_retriable"] = "true"
    XCTAssertNil(AgentNativeConnectorContinuation.settle(uncertain, record: record)?.metadata["effect_outcome_unknown"])
    var failed = record
    failed.response?.taskStatus = "failed"
    failed.response?.success = false
    XCTAssertEqual(AgentNativeConnectorContinuation.settle(uncertain, record: failed)?.metadata["effect_outcome_unknown"], "true")
    var overdue = fixture.result
    overdue.metadata["native_connector_observation_overdue"] = "true"
    XCTAssertNil(AgentNativeConnectorContinuation.settle(overdue, record: failed)?.metadata["effect_outcome_unknown"])
    XCTAssertEqual(AgentNativeConnectorContinuation.settle(overdue, record: failed)?.metadata["remote_task_status"], "failed")
    XCTAssertNil(AgentNativeConnectorContinuation.settle(overdue, record: failed)?.metadata["non_retriable"])
    for field in ["owner", "agent", "source", "contact", "conversation", "turn", "task", "generation", "pending"] {
      var foreign = record
      switch field {
      case "owner": foreign.ownerRunId = "other"
      case "agent": foreign.agentId = "other"
      case "source": foreign.sourceMessageId += 1
      case "contact": foreign.contactId = "other"
      case "conversation": foreign.conversationId = "other"
      case "turn": foreign.turnId = "other"
      case "task": foreign.taskId = "other"
      case "generation": foreign.executionGeneration += 1
      default: foreign.state = .pending
      }
      XCTAssertNil(AgentNativeConnectorContinuation.settle(fixture.result, record: foreign), field)
    }
  }

  func testNativeConnectorQueueCannotProjectSuccessfulToolCompletion() throws {
    let fixture = nativeConnectorWaitFixture()
    let waiting = try XCTUnwrap(AgentNativeConnectorContinuation.waitingAction(fixture.action,
      result: fixture.result, task: fixture.task, outgoing: fixture.outgoing))
    var task = fixture.task
    task.activePlan = AgentPlanFactory.singleAction(request: AgentPlanRequest(goal: task.goal,
      screen: AgentScreenContext(foregroundApp: "GalaxySSI")), action: waiting)
    XCTAssertTrue(AgentNativeConnectorContinuation.hasWaitingAction(task))
    let projection = AgentRecordedExecutionEvidence.project(task: task,
      scope: AgentPlanContinuationScope(conversationId: "conversation", turnId: "turn"), previous: [],
      observations: [.init(action: waiting, result: fixture.result)], now: 1234)
    let call = try XCTUnwrap(projection.calls.first)
    XCTAssertEqual(call.status, .running)
    XCTAssertEqual(call.completedAtMillis, 0)
    XCTAssertEqual(call.result["success"], .bool(false))
    XCTAssertEqual(call.result["awaiting_response"], .bool(true))
    XCTAssertFalse(AgentRollingPlanPolicy.shouldRequestNextBatch(plan: task.activePlan, result: fixture.result))
  }

  func testNativeConnectorWaitRejectsMissingScopeAndUntrackedFailureCannotReroute() throws {
    let fixture = nativeConnectorWaitFixture()
    for key in ["conversation_id", "turn_id", "task_id", "contact_id", "control_plane_run_id", "source_message_id"] {
      var invalid = fixture.result
      invalid.metadata[key] = ""
      XCTAssertNil(AgentNativeConnectorContinuation.waitingAction(fixture.action,
        result: invalid, task: fixture.task, outgoing: fixture.outgoing), key)
    }
    var action = fixture.action
    action.parameters["auto_reroute_on_failure"] = "true"
    let cloud = AgentCallableTarget(id: "cloud-model:deepseek", title: "Cloud", kind: .model,
      status: .available, capabilities: [.chat, .reasoning])
    var failure = AgentActionResult(actionId: action.id, success: false, message: "Failed",
      metadata: ["resource_id": "codex"])
    XCTAssertNotNil(AgentConnectorFallbackAction.freshFallback(action: action, failure: failure,
      currentResourceIds: [cloud.id], targets: [cloud]))
    for flag in ["effect_outcome_unknown", "non_retriable"] {
      failure.metadata[flag] = "true"
      XCTAssertNil(AgentConnectorFallbackAction.freshFallback(action: action, failure: failure,
        currentResourceIds: [cloud.id], targets: [cloud]))
      failure.metadata.removeValue(forKey: flag)
    }
  }

  private func nativeConnectorWaitFixture() -> (action: AgentAction, result: AgentActionResult,
    task: AgentTaskRecord, outgoing: ChatMessage) {
    let action = actionExecutorConnectorAction(parameters: ["_galaxyssi_task_id": "turn",
      "_galaxyssi_session_id": "conversation"])
    let result = AgentActionResult(actionId: action.id, success: true, message: "Queued",
      metadata: ["awaiting_response": "true", "source_message_id": "9920", "contact_id": "codex",
        "conversation_id": "conversation", "turn_id": "turn", "task_id": "remote-task",
        "control_plane_agent_id": "codex",
        "control_plane_run_id": AgentControlPlaneActionExecutor.stableRunId(conversationId: "conversation",
          turnId: "turn", actionId: action.id, agentId: "codex")])
    let task = AgentTaskRecord(taskId: "turn", sessionId: "conversation", goal: "Inspect project",
      phase: .executing, routeKind: .localSystem, targetTitle: "Codex", risk: .low, blocked: false)
    let outgoing = ChatMessage(contactId: "hermes", content: task.goal, isMine: true,
      conversationId: "conversation", turnId: "turn")
    return (action, result, task, outgoing)
  }

  func testConnectorTrackingFailureIsUnknownNonRetriableAndNotRedispatched() {
    var executions = 0
    let delegate = TestAgentActionExecutor { action, _ in
      executions += 1
      return AgentActionResult(actionId: action.id, success: true, message: "Queued",
        metadata: ["awaiting_response": "true", "source_message_id": "9142",
          "contact_id": "codex", "remote_task_status": "accepted",
          "auto_reroute_on_failure": "true", "manual_target_locked": "true"])
    }
    let executor = AgentControlPlaneActionExecutor(
      registrationSource: { [actionExecutorRegistration()] }, delegate: delegate,
      managedResponseLedger: RejectingConnectorResponseLedger())
    let action = actionExecutorConnectorAction()
    let screen = AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")
    let failed = executor.execute(action: action, screen: screen)
    let replay = executor.execute(action: action, screen: screen)
    XCTAssertFalse(failed.success)
    XCTAssertEqual(failed.metadata["error_code"], "connector_response_tracking_unavailable")
    XCTAssertEqual(failed.metadata["awaiting_response"], "false")
    XCTAssertEqual(failed.metadata["completion_verified"], "false")
    XCTAssertEqual(failed.metadata["effect_outcome_unknown"], "true")
    XCTAssertEqual(failed.metadata["non_retriable"], "true")
    XCTAssertEqual(failed.metadata["manual_target_locked"], "true")
    XCTAssertEqual(failed.metadata["conversation_id"], "conversation")
    XCTAssertEqual(failed.metadata["turn_id"], "turn")
    XCTAssertEqual(failed.metadata["source_message_id"], "9142")
    XCTAssertEqual(failed.metadata["provider_failure_attribution"], "local_transport")
    XCTAssertFalse(replay.success)
    XCTAssertEqual(replay.metadata["effect_outcome_unknown"], "true")
    XCTAssertEqual(executions, 1)
  }

  func testMalformedQueuedConnectorReceiptCannotBecomeCompletedOrWaiting() {
    for invalid in ["missing-source", "invalid-generation", "foreign-action"] {
      let executor = AgentControlPlaneActionExecutor(
        registrationSource: { [actionExecutorRegistration()] },
        delegate: TestAgentActionExecutor { action, _ in
          AgentActionResult(actionId: invalid == "foreign-action" ? "foreign" : action.id,
            success: true, message: "Queued", metadata: ["awaiting_response": "true",
              "source_message_id": invalid == "missing-source" ? "0" : "9143",
              "execution_generation": invalid == "invalid-generation" ? "0" : "1"])
        }, managedResponseLedger: InMemoryAgentManagedResponseLedger())
      let action = actionExecutorConnectorAction()
      let result = executor.execute(action: action, screen: AgentScreenContext(foregroundApp: "GalaxySSI"))
      XCTAssertFalse(result.success, invalid)
      XCTAssertEqual(result.actionId, action.id, invalid)
      XCTAssertEqual(result.metadata["error_code"], "invalid_connector_wait_receipt", invalid)
      XCTAssertEqual(result.metadata["awaiting_response"], "false", invalid)
      XCTAssertEqual(result.metadata["effect_outcome_unknown"], "true", invalid)
      XCTAssertEqual(result.metadata["non_retriable"], "true", invalid)
    }
  }

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

private final class RejectingConnectorResponseLedger: AgentManagedResponseLedger {
  private enum Failure: Error { case unavailable }
  func register(_ record: AgentManagedResponseRecord) throws { throw Failure.unavailable }
  func ownsResponse(_ response: AgentConnectorResponse) throws -> Bool { false }
  func complete(_ response: AgentConnectorResponse) -> AgentManagedResponseRecord? { nil }
  func acknowledge(_ response: AgentConnectorResponse) -> AgentManagedResponseRecord? { nil }
  func pendingForSupervisor(_ supervisorRunId: String) -> [AgentManagedResponseRecord] { [] }
  func completedUnapplied() -> [AgentManagedResponseRecord] { [] }
  func markApplied(ownerRunId: String) {}
  func removeOwner(_ ownerRunId: String) {}
  func clear() {}
}
