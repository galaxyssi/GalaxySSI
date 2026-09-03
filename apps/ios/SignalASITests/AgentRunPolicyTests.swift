import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
  func testAgentExecutionPresentationPolicyMatchesAndroidLocalAndRemoteLocations() {
    let desktop = AgentExecutionPresentationPolicy.local(
      routeKind: .desktopAgent,
      targetTitle: "Codex \u{00b7} WORKSTATION",
      selectedAgentOrModel: "",
      phase: .executing,
      currentStep: "Reading files",
      startedAtMillis: 1_000
    )

    XCTAssertEqual(desktop.executorLabel, "Codex")
    XCTAssertEqual(desktop.locationLabelHint, "WORKSTATION")
    XCTAssertEqual(desktop.locationKind, .desktop)
    XCTAssertEqual(desktop.runtimeKind, .desktopAgent)
    XCTAssertTrue(desktop.cancellable)

    let phone = AgentExecutionPresentationPolicy.local(
      routeKind: .localSystem,
      targetTitle: "",
      selectedAgentOrModel: "",
      phase: .executing,
      currentStep: "Reading battery",
      startedAtMillis: 1_000
    )
    let cloud = AgentExecutionPresentationPolicy.local(
      routeKind: .cloudModel,
      targetTitle: "DeepSeek",
      selectedAgentOrModel: "",
      phase: .waitingResponse,
      currentStep: "Waiting for model",
      startedAtMillis: 1_000
    )

    XCTAssertEqual(phone.locationKind, .phone)
    XCTAssertEqual(phone.executorLabel, "SignalASI")
    XCTAssertEqual(phone.runtimeKind, .phoneNative)
    XCTAssertEqual(cloud.locationKind, .phone)
    XCTAssertEqual(cloud.runtimeKind, .phoneCloudAPI)
    XCTAssertEqual(cloud.executorLabel, "DeepSeek")

    let completed = AgentExecutionPresentationPolicy.remote(
      executorId: "codex",
      executorLabel: "Codex",
      locationKind: "desktop",
      locationId: "desktop-1",
      locationName: "WORKSTATION",
      runtimeKind: "desktop_tool",
      runtimeId: "terminal",
      runtimeName: "Terminal",
      contract: AgentExecutionLocationContract.version,
      status: "completed",
      currentStep: "",
      startedAtMillis: 1_000,
      completedAtMillis: 2_000,
      advertisedCancellable: true
    )

    XCTAssertFalse(completed.cancellable)
    XCTAssertEqual(completed.phase, .completed)
    XCTAssertEqual(completed.locationKind, .desktop)
    XCTAssertEqual(completed.runtimeKind, .desktopTool)
    XCTAssertEqual(completed.runtimeId, "terminal")
    XCTAssertEqual(completed.runtimeLabelHint, "Terminal")
    XCTAssertEqual(completed.locationId, "desktop-1")
    XCTAssertTrue(completed.locationTrusted)
  }

  func testAgentExecutionPresentationPolicyResolvesRouteActionAndTaskRecordLocations() {
    let desktopRoute = AgentRoute(
      kind: .localModel,
      targetId: "ollama",
      targetTitle: "Ollama \u{00b7} MINI",
      executionDeviceId: "desktop-1",
      executionDeviceName: "Mac Mini"
    )
    let desktop = AgentExecutionPresentationPolicy.location(route: desktopRoute)

    XCTAssertEqual(desktop.locationKind, .desktop)
    XCTAssertEqual(desktop.runtimeKind, .desktopAgent)
    XCTAssertEqual(desktop.locationId, "desktop-1")
    XCTAssertEqual(desktop.locationName, "Mac Mini")
    XCTAssertEqual(desktop.runtimeId, "ollama")

    let runtimeAction = AgentAction(
      id: "runtime",
      kind: .callConnector,
      target: "runtime",
      risk: .medium,
      status: .proposed,
      description: "Run in local runtime",
      parameters: ["tool_id": AgentIOSOnDeviceRuntimeNativeToolCatalog.execute]
    )
    let linux = AgentExecutionPresentationPolicy.location(
      route: AgentRoute(kind: .localSystem, targetTitle: "SignalASI"),
      action: runtimeAction
    )

    XCTAssertEqual(linux.locationKind, .phone)
    XCTAssertEqual(linux.runtimeKind, .phoneLinux)
    XCTAssertEqual(linux.runtimeId, AgentIOSOnDeviceRuntimeNativeToolCatalog.execute)

    let record = AgentTaskRecord(
      taskId: "task",
      sessionId: "conversation",
      goal: "Inspect desktop",
      phase: .executing,
      routeKind: .localSystem,
      targetTitle: "SignalASI",
      risk: .low,
      blocked: false,
      executionLocationKind: .desktop,
      executionRuntimeKind: .desktopTool,
      executionLocationId: "desktop-2",
      executionLocationName: "Studio PC",
      executionRuntimeId: "shell",
      executionLocationTrusted: false
    )
    let restored = AgentExecutionPresentationPolicy.location(record: record)

    XCTAssertEqual(restored.locationKind, .desktop)
    XCTAssertEqual(restored.runtimeKind, .desktopTool)
    XCTAssertEqual(restored.locationId, "desktop-2")
    XCTAssertEqual(restored.locationName, "Studio PC")
    XCTAssertEqual(restored.runtimeId, "shell")
    XCTAssertFalse(restored.trusted)
  }

  func testAgentExecutionPresentationPolicyDecodesAndroidWireNames() throws {
    let phase = try JSONDecoder.signalASI.decode(AgentPhase.self, from: Data(#""WAITING_RESPONSE""#.utf8))
    let route = try JSONDecoder.signalASI.decode(AgentRouteKind.self, from: Data(#""DESKTOP_AGENT""#.utf8))
    let location = try JSONDecoder.signalASI.decode(AgentExecutionLocationKind.self, from: Data(#""connected_device""#.utf8))
    let runtime = try JSONDecoder.signalASI.decode(AgentExecutionRuntimeKind.self, from: Data(#""PHONE_LINUX""#.utf8))
    let fallbackPhase = try JSONDecoder.signalASI.decode(AgentPhase.self, from: Data(#""not-supported""#.utf8))
    let fallbackRoute = try JSONDecoder.signalASI.decode(AgentRouteKind.self, from: Data(#""not-supported""#.utf8))
    let fallbackLocation = try JSONDecoder.signalASI.decode(AgentExecutionLocationKind.self, from: Data(#""not-supported""#.utf8))
    let fallbackRuntime = try JSONDecoder.signalASI.decode(AgentExecutionRuntimeKind.self, from: Data(#""not-supported""#.utf8))

    XCTAssertEqual(phase, .waitingResponse)
    XCTAssertEqual(route, .desktopAgent)
    XCTAssertEqual(location, .connectedDevice)
    XCTAssertEqual(runtime, .phoneLinux)
    XCTAssertEqual(fallbackPhase, .executing)
    XCTAssertEqual(fallbackRoute, .unknown)
    XCTAssertEqual(fallbackLocation, .unknown)
    XCTAssertEqual(fallbackRuntime, .unknown)
    XCTAssertFalse(AgentExecutionPresentationPolicy.isCancellable(.blocked))
    XCTAssertEqual(AgentExecutionPresentationPolicy.phaseForRemoteStatus("timed_out"), .failed)
    XCTAssertEqual(AgentExecutionPresentationPolicy.phaseForRemoteStatus("waiting_approval"), .paused)
  }

  func testAgentRemoteTaskStatusPolicyMatchesAndroidTerminalSemantics() {
    for status in ["failed", "cancelled", "timed_out", "not_found"] {
      XCTAssertTrue(AgentRemoteTaskStatusPolicy.isTerminal(status))
      XCTAssertTrue(AgentRemoteTaskStatusPolicy.settlesWithoutResponse(status))
    }

    XCTAssertTrue(AgentRemoteTaskStatusPolicy.isTerminal("completed"))
    XCTAssertFalse(AgentRemoteTaskStatusPolicy.settlesWithoutResponse("completed"))
    XCTAssertFalse(AgentRemoteTaskStatusPolicy.isTerminal("running"))
    XCTAssertEqual(AgentRemoteTaskStatusPolicy.normalize(" TIMED_OUT "), "timed_out")
  }

  func testAgentRemoteTaskStatusPolicyAssignsTerminalCompletionTimestamp() {
    XCTAssertEqual(
      AgentRemoteTaskStatusPolicy.completionTimestamp(
        status: "timed_out",
        declaredCompletedAtMillis: 0,
        updatedAtMillis: 120,
        observedAtMillis: 130
      ),
      120
    )
    XCTAssertEqual(
      AgentRemoteTaskStatusPolicy.completionTimestamp(
        status: "failed",
        declaredCompletedAtMillis: 0,
        updatedAtMillis: 0,
        observedAtMillis: 130
      ),
      130
    )
    XCTAssertEqual(
      AgentRemoteTaskStatusPolicy.completionTimestamp(
        status: "running",
        declaredCompletedAtMillis: 100,
        updatedAtMillis: 120,
        observedAtMillis: 130
      ),
      0
    )
  }

  func testAgentRemoteTaskStatusPolicyMapsVisibleTerminalPhase() {
    XCTAssertEqual(AgentRemoteTaskStatusPolicy.phase("COMPLETED"), .completed)
    XCTAssertEqual(AgentRemoteTaskStatusPolicy.phase(" cancelled "), .cancelled)
    XCTAssertEqual(AgentRemoteTaskStatusPolicy.phase("timed_out"), .failed)
    XCTAssertEqual(AgentRemoteTaskStatusPolicy.workspaceStatus("not_found"), .failed)
    XCTAssertNil(AgentRemoteTaskStatusPolicy.workspaceStatus("running"))
    XCTAssertEqual(AgentRemoteTaskStatusPolicy.timeoutStage("timed_out"), "REMOTE_TASK")
    XCTAssertEqual(AgentRemoteTaskStatusPolicy.timeoutStage("failed"), "")
  }

  func testAgentRemoteTaskStatusPolicyFailedStatusDoesNotResetResourceHealth() {
    for status in ["failed", "cancelled", "timed_out", "not_found"] {
      XCTAssertFalse(AgentRemoteTaskStatusPolicy.keepsResourceHealthy(status))
    }
    for status in ["accepted", "running", "completed"] {
      XCTAssertTrue(AgentRemoteTaskStatusPolicy.keepsResourceHealthy(status))
    }
  }

  func testAgentRemoteTaskStatusPolicyRestoredTaskUsesOnlyRemainingDeadline() {
    XCTAssertEqual(
      AgentRemoteTaskStatusPolicy.remainingDeadlineMillis(
        deadlineMillis: 10_000,
        startedAtMillis: 2_000,
        nowMillis: 10_000
      ),
      2_000
    )
    XCTAssertEqual(
      AgentRemoteTaskStatusPolicy.remainingDeadlineMillis(
        deadlineMillis: 10_000,
        startedAtMillis: 2_000,
        nowMillis: 20_000
      ),
      0
    )
    XCTAssertEqual(
      AgentRemoteTaskStatusPolicy.remainingDeadlineMillis(
        deadlineMillis: 10_000,
        startedAtMillis: 0,
        nowMillis: 20_000
      ),
      10_000
    )
  }

  func testAgentPlanLifecyclePolicyRestoresConnectorResultAndCompletesSession() {
    let connector = lifecycleAction(
      id: "connector-codex",
      kind: .callConnector,
      target: "Codex",
      status: .completed,
      result: "The worksheet has been corrected."
    )
    let draft = lifecycleAction(
      id: "draft-plan",
      kind: .draftPlan,
      target: "local-agent-runtime",
      status: .completed
    )
    let session = lifecycleSession(
      phase: .planning,
      plan: lifecyclePlan(connector, draft),
      result: AgentActionResult(actionId: draft.id, success: true, message: "")
    )

    let normalized = AgentPlanLifecyclePolicy.normalize(session)

    XCTAssertTrue(normalized.changed)
    XCTAssertEqual(normalized.session.currentPlan?.actions, [connector])
    XCTAssertEqual(normalized.session.phase, .completed)
    XCTAssertEqual(normalized.session.lastActionResult?.actionId, connector.id)
    XCTAssertEqual(normalized.session.lastActionResult?.message, connector.result)
  }

  func testAgentPlanLifecyclePolicyRemovesPendingTrailingDraftBeforeItRuns() {
    let connector = lifecycleAction(
      id: "connector-codex",
      kind: .callConnector,
      target: "Codex",
      status: .completed,
      result: "Done"
    )
    let draft = lifecycleAction(
      id: "draft-plan",
      kind: .draftPlan,
      target: "local-agent-runtime",
      status: .pendingConfirmation
    )
    let plan = lifecyclePlan(connector, draft)

    let normalized = AgentPlanLifecyclePolicy.normalize(plan)

    XCTAssertTrue(normalized.changed)
    XCTAssertEqual(normalized.plan.actions, [connector])
  }

  func testAgentPlanLifecyclePolicyRetiresStandaloneLegacyRuntimeDraft() {
    let standalone = lifecyclePlan(
      lifecycleAction(
        id: "draft-plan",
        kind: .draftPlan,
        target: "local-agent-runtime",
        status: .completed
      )
    )
    let taskComplete = lifecyclePlan(
      lifecycleAction(id: "connector", kind: .callConnector, target: "Codex", status: .completed),
      lifecycleAction(id: "done", kind: .draftPlan, target: "task-complete", status: .completed)
    )

    let normalized = AgentPlanLifecyclePolicy.normalize(standalone)

    XCTAssertTrue(normalized.changed)
    XCTAssertEqual(normalized.plan.actions.first?.target, "task-complete")
    XCTAssertEqual(normalized.plan.actions.first?.status, .failed)
    XCTAssertTrue(normalized.plan.actions.first?.result.contains("Send it again") == true)
    XCTAssertTrue(normalized.plan.validation.valid)
    XCTAssertFalse(AgentPlanLifecyclePolicy.normalize(taskComplete).changed)
  }

  func testAgentPlanLifecyclePolicyRecoversCompletedConnectorFromHistory() {
    let connector = lifecycleAction(
      id: "connector-codex",
      kind: .callConnector,
      target: "Codex",
      status: .completed,
      result: "Recovered Codex reply"
    )
    let draft = lifecycleAction(
      id: "replanned-draft",
      kind: .draftPlan,
      target: "local-agent-runtime",
      status: .completed
    )
    var sourcePlan = lifecyclePlan(draft)
    sourcePlan.actionHistory = [connector]
    let sourceSession = lifecycleSession(
      phase: .planning,
      plan: sourcePlan,
      result: AgentActionResult(actionId: draft.id, success: true, message: "")
    )

    let normalized = AgentPlanLifecyclePolicy.normalize(sourceSession)

    XCTAssertTrue(normalized.changed)
    XCTAssertEqual(normalized.session.currentPlan?.actions, [connector])
    XCTAssertTrue(normalized.session.currentPlan?.actionHistory.isEmpty == true)
    XCTAssertEqual(normalized.session.phase, .completed)
    XCTAssertEqual(normalized.session.lastActionResult?.message, "Recovered Codex reply")
  }

  func testAgentPlanLifecyclePolicyRecoversReceivedConnectorWithoutLocalRuntimeDraft() {
    let draft = lifecycleAction(
      id: "replanned-draft",
      kind: .draftPlan,
      target: "local-agent-runtime",
      status: .completed
    )
    var sourcePlan = lifecyclePlan(draft)
    sourcePlan.route = AgentRoute(kind: .desktopAgent, targetTitle: "Codex")
    let sourceSession = lifecycleSession(
      phase: .planning,
      plan: sourcePlan,
      result: AgentActionResult(actionId: draft.id, success: true, message: "Created a local task plan"),
      auditTrail: [
        AgentAuditEntry(
          event: .connectorResponseReceived,
          detail: "source_message_id=1",
          timestampMillis: 2
        )
      ]
    )
    let durableTask = agentTaskRecord(
      taskId: sourcePlan.planId,
      sessionId: "session",
      goal: sourcePlan.goal,
      phase: .completed,
      routeKind: .desktopAgent,
      targetTitle: "Codex",
      risk: .low,
      result: "Durable Codex result"
    )

    let recovered = AgentPlanLifecyclePolicy.recoverCompletedConnector(
      session: sourceSession,
      persistedTask: durableTask,
      missingResult: "No final result"
    )

    XCTAssertEqual(recovered.phase, .completed)
    XCTAssertEqual(recovered.currentPlan?.actions.first?.kind, .callConnector)
    XCTAssertEqual(recovered.currentPlan?.actions.first?.target, "Codex")
    XCTAssertEqual(recovered.lastActionResult?.message, "Durable Codex result")
    XCTAssertFalse(recovered.currentPlan?.actions.contains { $0.target == "local-agent-runtime" } == true)
  }

  func testAgentPlanLifecyclePolicyDoesNotRewriteWithoutConnectorReceipt() {
    let draft = lifecycleAction(
      id: "draft",
      kind: .draftPlan,
      target: "local-agent-runtime",
      status: .pendingConfirmation
    )
    let source = lifecycleSession(phase: .planning, plan: lifecyclePlan(draft), result: nil)

    let recovered = AgentPlanLifecyclePolicy.recoverCompletedConnector(
      session: source,
      persistedTask: nil,
      missingResult: "No final result"
    )

    XCTAssertEqual(source, recovered)
  }

  func testAgentPlanLifecycleModelsUseAndroidWireNames() throws {
    let decoded = try JSONDecoder().decode(
      AgentSessionSnapshot.self,
      from: Data(
        #"""
        {
          "session_id": "session",
          "phase": "PLANNING",
          "current_goal": "Correct the worksheet",
          "current_screen": {
            "foreground_app": "SignalASI",
            "page_title": "Agent"
          },
          "current_plan": {
            "goal": "Correct the worksheet",
            "screen": {
              "foreground_app": "SignalASI",
              "page_title": "Agent"
            },
            "steps": [
              {"order": 1, "kind": "BUILD_PLAN", "status": "CURRENT"}
            ],
            "actions": [
              {
                "id": "connector",
                "kind": "CALL_CONNECTOR",
                "target": "Codex",
                "risk": "LOW",
                "status": "COMPLETED",
                "description": "Run Codex",
                "result": "Done"
              }
            ],
            "execution_mode": "AUTO_COMPLETE",
            "plan_id": "plan",
            "route": {
              "kind": "DESKTOP_AGENT",
              "target_title": "Codex"
            },
            "verification_results": [
              {"action_id": "connector", "success": true, "evidence": "ok", "timestamp_millis": 12}
            ],
            "checkpoints": [
              {"action_id": "connector", "summary": "checkpoint", "timestamp_millis": 13}
            ]
          },
          "audit_trail": [
            {"event": "CONNECTOR_RESPONSE_RECEIVED", "detail": "ok", "timestamp_millis": 14}
          ],
          "last_action_result": {
            "action_id": "connector",
            "success": true,
            "message": "Done"
          },
          "task_execution_mode": "AUTO_COMPLETE",
          "updated_at_millis": 15
        }
        """#.utf8
      )
    )
    let fallbackAudit = try JSONDecoder().decode(
      AgentAuditEvent.self,
      from: Data(#""FUTURE""#.utf8)
    )
    let encoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)

    XCTAssertEqual(decoded.phase, .planning)
    XCTAssertEqual(decoded.currentPlan?.route.kind, .desktopAgent)
    XCTAssertEqual(decoded.currentPlan?.steps.first?.kind, .buildPlan)
    XCTAssertEqual(decoded.auditTrail.first?.event, .connectorResponseReceived)
    XCTAssertEqual(fallbackAudit, .invocationAudit)
    XCTAssertTrue(encoded.contains(#""current_plan":"#) || encoded.contains(#""current_plan":{"#))
    XCTAssertTrue(encoded.contains(#""task_execution_mode":"AUTO_COMPLETE""#))
    XCTAssertTrue(encoded.contains(#""timestamp_millis":14"#))
  }

  func testAgentNativeToolLifecycleRunControlAdapterMatchesAndroidTimelinePayload() {
    let progress = AgentNativeToolLifecycleEvent(
      stage: .progress,
      toolId: "signalasi.workspace.file.read.text",
      invocationId: "invoke-1",
      stepId: "step-1",
      conversationId: "conversation-1",
      turnId: "turn-1",
      progressStage: "reading",
      message: "Reading file",
      percent: 42,
      sequence: 7,
      timestampMillis: 12_345
    )
    let event = AgentNativeToolRunControlAdapter.controlEvent(
      from: progress,
      runId: "run-1",
      agentId: "signalasi-mobile",
      deviceId: "phone-1",
      sequence: 99
    )

    XCTAssertEqual(event.type, .toolProgress)
    XCTAssertEqual(event.conversationId, "conversation-1")
    XCTAssertEqual(event.messageId, "turn-1")
    XCTAssertEqual(event.taskId, "turn-1")
    XCTAssertEqual(event.runId, "run-1")
    XCTAssertEqual(event.stepId, "step-1")
    XCTAssertEqual(event.toolCallId, "invoke-1")
    XCTAssertEqual(event.sequence, 99)
    XCTAssertEqual(event.timestampMillis, 12_345)
    XCTAssertEqual(event.payload["timeline_contract"]?.stringValue, AgentRunTimelineContract.version)
    XCTAssertEqual(event.payload["timeline_kind"]?.stringValue, "tool")
    XCTAssertEqual(event.payload["tool_id"]?.stringValue, "signalasi.workspace.file.read.text")
    XCTAssertEqual(event.payload["progress_stage"]?.stringValue, "reading")
    XCTAssertEqual(event.payload["message"]?.stringValue, "Reading file")
    XCTAssertEqual(event.payload["percent"]?.intValue, 42)
    XCTAssertEqual(event.payload["progress_sequence"]?.intValue, 7)
    XCTAssertEqual(event.payload["timestamp_millis"]?.intValue, 12_345)
    XCTAssertEqual(AgentRunTimelineContract.kind(event), .tool)

    let started = AgentNativeToolRunControlAdapter.controlEvent(
      from: AgentNativeToolLifecycleEvent(
        stage: .started,
        toolId: "tool",
        invocationId: "invoke-start",
        stepId: "",
        conversationId: "",
        turnId: "",
        timestampMillis: 1
      ),
      runId: "run"
    )
    let finished = AgentNativeToolRunControlAdapter.controlEvent(
      from: AgentNativeToolLifecycleEvent(
        stage: .finished,
        toolId: "tool",
        invocationId: "invoke-finish",
        stepId: "step-finish",
        conversationId: "conversation",
        turnId: "turn",
        status: .succeeded,
        message: "done",
        timestampMillis: 2
      ),
      runId: "run",
      taskId: "task"
    )

    XCTAssertEqual(started.type, .toolStarted)
    XCTAssertEqual(started.messageId, "invoke-start")
    XCTAssertEqual(started.taskId, "run")
    XCTAssertEqual(started.stepId, "invoke-start")
    XCTAssertEqual(finished.type, .toolCompleted)
    XCTAssertEqual(finished.payload["status"]?.stringValue, "succeeded")
    XCTAssertEqual(finished.payload["message"]?.stringValue, "done")
    XCTAssertEqual(finished.taskId, "task")
  }

  func testAgentRunEventStoreReducerPreservesTerminalStateUntilExplicitRecovery() {
    let completed = AgentRunEventStore.reduce(current: .running, event: .runCompleted)
    let ignoredLateProgress = AgentRunEventStore.reduce(current: completed, event: .toolProgress)
    let recovered = AgentRunEventStore.reduce(current: completed, event: .runRecovered)
    let waiting = AgentRunEventStore.reduce(current: .running, event: .toolPermissionRequired)
    let paused = AgentRunEventStore.reduce(current: .running, event: .permissionRevoked)

    XCTAssertEqual(completed, .completed)
    XCTAssertEqual(ignoredLateProgress, .completed)
    XCTAssertEqual(recovered, .running)
    XCTAssertEqual(waiting, .waitingForUser)
    XCTAssertEqual(paused, .paused)
  }

  func testAgentRunRecoveryPolicyMatchesAndroidDurableDesktopRules() {
    let snapshot = runControlSnapshot(state: .waitingForDevice)
    let recorded = AgentRecordedRun(
      runId: "run",
      conversationId: "conversation",
      taskThreadId: "task",
      originalRequest: "Continue the task"
    )
    let paused = runControlSnapshot(state: .paused)
    let completed = runControlSnapshot(state: .completed)

    let durable = AgentRunRecoveryPolicy.decide(
      snapshot: snapshot,
      recordedRun: recorded,
      registration: runRecoveryRegistration()
    )
    let cloud = AgentRunRecoveryPolicy.decide(
      snapshot: snapshot,
      recordedRun: recorded,
      registration: runRecoveryRegistration(location: .cloud, connectionKind: .http)
    )
    let localWait = AgentRunRecoveryPolicy.decide(
      snapshot: paused,
      recordedRun: recorded,
      registration: nil
    )
    let terminal = AgentRunRecoveryPolicy.decide(
      snapshot: snapshot,
      recordedRun: AgentRecordedRun(
        runId: "run",
        conversationId: "conversation",
        taskThreadId: "task",
        originalRequest: "Done",
        status: .completed
      ),
      registration: runRecoveryRegistration()
    )
    let recoverable = AgentRunEventStore.recoverableRuns([snapshot, paused, completed])

    XCTAssertEqual(durable.disposition, .reconnectDurableRemote)
    XCTAssertEqual(durable.reason, "durable_remote_run_can_reconnect")
    XCTAssertEqual(cloud.disposition, .failNonReplayable)
    XCTAssertEqual(cloud.reason, "interrupted_run_cannot_be_replayed_safely")
    XCTAssertEqual(localWait.disposition, .restoreLocalWait)
    XCTAssertEqual(localWait.reason, "user_resumable_checkpoint")
    XCTAssertEqual(terminal.disposition, .ignoreTerminal)
    XCTAssertEqual(recoverable.map(\.state), [.waitingForDevice, .paused])
  }

  func testAgentRunRecoveryModelsUseAndroidWireNames() throws {
    let decodedSnapshot = try JSONDecoder().decode(
      AgentRunControlSnapshot.self,
      from: Data(
        #"""
        {
          "run_id": "run",
          "task_id": "task",
          "state": "WAITING_FOR_DEVICE",
          "agent_id": "codex",
          "device_id": "desktop",
          "last_sequence": 4,
          "last_event": {
            "event_id": "event",
            "conversation_id": "conversation",
            "message_id": "message",
            "task_id": "task",
            "run_id": "run",
            "agent_id": "codex",
            "device_id": "desktop",
            "type": "WAITING_FOR_DEVICE",
            "sequence": 4,
            "timestamp_millis": 1000
          }
        }
        """#.utf8
      )
    )
    let decodedRegistration = try JSONDecoder().decode(
      AgentRunRecoveryRegistration.self,
      from: Data(#"{"agent_id":"codex","location":"TRUSTED_DESKTOP","connection_kind":"SIGNALASI_LINK"}"#.utf8)
    )
    let fallbackRegistration = try JSONDecoder().decode(
      AgentRunRecoveryRegistration.self,
      from: Data(#"{"agent_id":"future","location":"FUTURE","connection_kind":"FUTURE"}"#.utf8)
    )
    let missingStatus = try JSONDecoder().decode(
      AgentRecordedRun.self,
      from: Data(#"{"run_id":"run","conversation_id":"conversation","task_thread_id":"task","original_request":"Continue"}"#.utf8)
    )
    let futureStatus = try JSONDecoder().decode(
      AgentRecordedRunStatus.self,
      from: Data(#""FUTURE""#.utf8)
    )
    let encodedSnapshot = String(decoding: try JSONEncoder().encode(decodedSnapshot), as: UTF8.self)
    let encodedRegistration = String(decoding: try JSONEncoder().encode(decodedRegistration), as: UTF8.self)
    let encodedRun = String(decoding: try JSONEncoder().encode(missingStatus), as: UTF8.self)

    XCTAssertEqual(decodedSnapshot.state, .waitingForDevice)
    XCTAssertEqual(decodedSnapshot.lastEvent.type, .waitingForDevice)
    XCTAssertEqual(decodedRegistration.location, .trustedDesktop)
    XCTAssertEqual(decodedRegistration.connectionKind, .signalasiLink)
    XCTAssertEqual(fallbackRegistration.location, .cloud)
    XCTAssertEqual(fallbackRegistration.connectionKind, .http)
    XCTAssertEqual(missingStatus.status, .running)
    XCTAssertEqual(futureStatus, .failed)
    XCTAssertTrue(encodedSnapshot.contains(#""last_sequence":4"#))
    XCTAssertTrue(encodedRegistration.contains(#""connection_kind":"SIGNALASI_LINK""#))
    XCTAssertTrue(encodedRun.contains(#""task_thread_id":"task""#))
  }

  func testAgentRunStartReceiptStoreReservesAndReplaysIdempotentRequests() throws {
    var now: Int64 = 1_000
    let registration = networkRegistration(agentId: "codex", displayName: "Codex")
    let store = InMemoryAgentRunStartReceiptStore(clock: { now })
    let request = runStartRequest(requiredCapabilities: [.code, .chat])

    let reserved = try store.reserve(registration: registration, request: request)
    now = 2_000
    let replay = try store.reserve(
      registration: registration,
      request: runStartRequest(runId: "run-replayed", requiredCapabilities: [.chat, .code])
    )

    XCTAssertEqual(reserved, replay)
    XCTAssertEqual(reserved.status, .reserved)
    XCTAssertEqual(reserved.createdAtMillis, 1_000)
    XCTAssertEqual(reserved.updatedAtMillis, 1_000)
    XCTAssertEqual(reserved.runId, "run")
    XCTAssertEqual(reserved.taskId, "task")
    XCTAssertEqual(
      reserved.requestDigest,
      "2c83a56ff6e923a40ce01a63d26f37f6bc2e7b78ff367da21217b92ef586b719"
    )
    XCTAssertEqual(store.find(agentId: " codex ", idempotencyKey: " key ")?.idempotencyKey, "key")

    XCTAssertThrowsError(
      try store.reserve(
        registration: registration,
        request: runStartRequest(goal: "different request content", requiredCapabilities: [.chat, .code])
      )
    ) { error in
      XCTAssertTrue((error as? AgentRunStartReceiptError)?.message.contains("different request content") == true)
    }
  }

  func testAgentRunStartReceiptStoreAcceptsPersistsAndRejectsMismatchedHandles() throws {
    var now: Int64 = 1_000
    let registration = networkRegistration(agentId: "codex", displayName: "Codex")
    let store = InMemoryAgentRunStartReceiptStore(clock: { now })
    let request = runStartRequest()
    _ = try store.reserve(registration: registration, request: request)
    now = 2_000

    XCTAssertThrowsError(
      try store.accept(
        agentId: "codex",
        idempotencyKey: "key",
        handle: AgentRunHandle(runId: "wrong", taskId: "task", agentId: "codex", remoteRunId: "remote")
      )
    ) { error in
      XCTAssertTrue((error as? AgentRunStartReceiptError)?.message.contains("different Run") == true)
    }

    let handle = AgentRunHandle(
      runId: "run",
      taskId: "task",
      agentId: "codex",
      remoteRunId: "remote-1",
      acceptedAtMillis: 1_950
    )
    let accepted = try store.accept(agentId: "codex", idempotencyKey: "key", handle: handle)
    let recreated = InMemoryAgentRunStartReceiptStore(serialized: store.serializedSnapshot(), clock: { 3_000 })

    XCTAssertEqual(accepted.status, .accepted)
    XCTAssertEqual(accepted.handle, handle)
    XCTAssertEqual(accepted.error, "")
    XCTAssertEqual(accepted.updatedAtMillis, 2_000)
    XCTAssertEqual(recreated.list().count, 1)
    XCTAssertEqual(recreated.list().first?.handle?.remoteRunId, "remote-1")
    XCTAssertEqual(recreated.list().first?.status, .accepted)

    let ignored = recreated.markOutcomeUnknown(agentId: "codex", idempotencyKey: "key", error: "connection_lost")
    XCTAssertEqual(ignored?.status, .accepted)
    XCTAssertEqual(recreated.markCancelledByRun(agentId: "codex", runId: "run"), 1)
    XCTAssertEqual(recreated.list().first?.status, .cancelled)
  }

  func testAgentRunStartReceiptStoreTracksUnknownOutcomeAndBoundsSerializedReceipts() throws {
    var now: Int64 = 1_000
    let registration = networkRegistration(agentId: "codex", displayName: "Codex")
    let store = InMemoryAgentRunStartReceiptStore(clock: { now })
    _ = try store.reserve(registration: registration, request: runStartRequest(runId: "run-a", idempotencyKey: "key-a"))
    now = 2_000
    let unknown = store.markOutcomeUnknown(
      agentId: "codex",
      idempotencyKey: "key-a",
      error: " connection_lost "
    )
    now = 3_000
    let accepted = try store.accept(
      agentId: "codex",
      idempotencyKey: "key-a",
      handle: AgentRunHandle(runId: "run-a", taskId: "task", agentId: "codex", remoteRunId: "remote-a")
    )

    XCTAssertEqual(unknown?.status, .outcomeUnknown)
    XCTAssertEqual(unknown?.error, "connection_lost")
    XCTAssertEqual(unknown?.updatedAtMillis, 2_000)
    XCTAssertEqual(accepted.status, .accepted)
    XCTAssertEqual(accepted.updatedAtMillis, 3_000)

    let bulk = (0..<4_005).map { index in
      AgentRunStartReceipt(
        agentId: "codex",
        installationId: "installation-codex",
        idempotencyKey: "bulk-key-\(index)",
        requestDigest: String(repeating: "b", count: 64),
        runId: "bulk-\(index)",
        taskId: "task-\(index)",
        status: .reserved,
        createdAtMillis: Int64(index),
        updatedAtMillis: Int64(index)
      )
    }
    let bulkStore = InMemoryAgentRunStartReceiptStore(
      serialized: AgentRunStartReceiptJsonCodec.encode(bulk),
      clock: { 9_000 }
    )
    XCTAssertEqual(bulkStore.markCancelledByRun(agentId: "codex", runId: "bulk-4004"), 1)
    let receipts = bulkStore.list()
    XCTAssertEqual(receipts.count, 4_000)
    XCTAssertFalse(receipts.contains { $0.idempotencyKey == "bulk-key-0" })
    XCTAssertEqual(receipts.first?.idempotencyKey, "bulk-key-4004")
    XCTAssertEqual(receipts.last?.idempotencyKey, "bulk-key-5")
  }

  func testAgentRunStartReceiptCodecUsesAndroidWireNamesAndSkipsInvalidRecords() throws {
    let valid = AgentRunStartReceipt(
      agentId: "codex",
      installationId: "installation-codex",
      idempotencyKey: "key",
      requestDigest: String(repeating: "a", count: 64),
      runId: "run",
      taskId: "task",
      status: .accepted,
      handle: AgentRunHandle(runId: "run", taskId: "task", agentId: "codex", remoteRunId: "remote", acceptedAtMillis: 123),
      createdAtMillis: 1,
      updatedAtMillis: 2
    )
    let encoded = AgentRunStartReceiptJsonCodec.encode([valid])
    let object = try XCTUnwrap(
      (JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [[String: Any]])?.first
    )
    let decoded = AgentRunStartReceiptJsonCodec.decode(
      """
      [
        {"agent_id":"bad","idempotency_key":"bad","status":"FUTURE"},
        \(encoded.dropFirst().dropLast())
      ]
      """
    )

    XCTAssertEqual(object["agent_id"] as? String, "codex")
    XCTAssertEqual(object["installation_id"] as? String, "installation-codex")
    XCTAssertEqual(object["idempotency_key"] as? String, "key")
    XCTAssertEqual(object["request_digest"] as? String, String(repeating: "a", count: 64))
    XCTAssertEqual(object["run_id"] as? String, "run")
    XCTAssertEqual(object["task_id"] as? String, "task")
    XCTAssertEqual(object["status"] as? String, "ACCEPTED")
    XCTAssertEqual((object["handle"] as? [String: Any])?["remote_run_id"] as? String, "remote")
    XCTAssertEqual(decoded, [valid])
    XCTAssertEqual(AgentRunStartReceiptJsonCodec.decode("not-json"), [])
  }

  func testAgentExplicitToolHandleIsOpaqueScopedAndDoesNotExposeResource() throws {
    var now: Int64 = 1_000
    let registry = AgentExplicitToolHandleRegistry(nowMillis: { now })
    let opened = try registry.create(
      kind: "browser_session",
      resourceId: "internal-browser-resource",
      scope: AgentExplicitToolHandleScope(ownerId: "owner-1", contextId: "conversation-1"),
      capabilities: ["browser.navigate"],
      resource: AgentExplicitToolHandleResource(
        resourceId: "internal-browser-resource",
        payload: ["url": .string("")]
      ),
      metadata: ["mode": .string(" isolated ")]
    )

    let handleId = opened.handleId
    let publicJSON = String(decoding: try JSONEncoder.signalASI.encode(opened), as: UTF8.self)
    now = 1_250
    let resolved = try registry.resolve(
      handleId: handleId,
      kind: "browser_session",
      scope: AgentExplicitToolHandleScope(ownerId: "owner-1", contextId: "conversation-1"),
      requiredCapability: "browser.navigate"
    )

    XCTAssertTrue(handleId.hasPrefix("sth_browsers_"))
    XCTAssertFalse(publicJSON.contains("resource_id"))
    XCTAssertFalse(publicJSON.contains("internal-browser-resource"))
    XCTAssertEqual(opened.contract, AgentExplicitToolHandleContract.version)
    XCTAssertEqual(opened.metadata["mode"]?.stringValue, "isolated")
    XCTAssertEqual(resolved.resourceId, "internal-browser-resource")
    XCTAssertEqual(resolved.resource.payload["url"]?.stringValue, "")
    XCTAssertEqual(resolved.useCount, 1)
    XCTAssertEqual(registry.status().activeCount, 1)

    assertToolHandleError("tool_handle_context_mismatch") {
      _ = try registry.resolve(
        handleId: handleId,
        kind: "browser_session",
        scope: AgentExplicitToolHandleScope(ownerId: "owner-1", contextId: "conversation-2"),
        requiredCapability: "browser.navigate"
      )
    }
  }

  func testAgentExplicitToolHandleEnforcesOwnerKindAndCapabilities() throws {
    let registry = AgentExplicitToolHandleRegistry(nowMillis: { 2_000 })
    let opened = try registry.create(
      kind: "browser",
      resourceId: "browser-resource",
      scope: AgentExplicitToolHandleScope(ownerId: "phone-a", contextId: "conversation-a"),
      capabilities: ["browser.navigate"]
    )

    assertToolHandleError("tool_handle_owner_mismatch") {
      _ = try registry.resolve(
        handleId: opened.handleId,
        kind: "browser",
        scope: AgentExplicitToolHandleScope(ownerId: "phone-b", contextId: "conversation-a"),
        requiredCapability: "browser.navigate"
      )
    }
    assertToolHandleError("tool_handle_kind_mismatch") {
      _ = try registry.resolve(
        handleId: opened.handleId,
        kind: "desktop_session",
        scope: AgentExplicitToolHandleScope(ownerId: "phone-a", contextId: "conversation-a"),
        requiredCapability: "browser.navigate"
      )
    }
    assertToolHandleError("tool_handle_capability_denied") {
      _ = try registry.resolve(
        handleId: opened.handleId,
        kind: "browser",
        scope: AgentExplicitToolHandleScope(ownerId: "phone-a", contextId: "conversation-a"),
        requiredCapability: "browser.download"
      )
    }
  }

  func testAgentExplicitToolHandleExpiresReleasesAndRevokesResources() throws {
    var now: Int64 = 2_000
    let registry = AgentExplicitToolHandleRegistry(nowMillis: { now })
    let opened = try registry.create(
      kind: "browser_session",
      resourceId: "browser-1",
      scope: AgentExplicitToolHandleScope(ownerId: "owner"),
      capabilities: ["browser.close"],
      ttlMillis: 100,
      idleTimeoutMillis: 0
    )
    now = 2_100

    assertToolHandleError("tool_handle_expired", retryable: true) {
      _ = try registry.resolve(
        handleId: opened.handleId,
        kind: "browser_session",
        scope: AgentExplicitToolHandleScope(ownerId: "owner"),
        requiredCapability: "browser.close"
      )
    }

    let first = try registry.create(
      kind: "browser_session",
      resourceId: "browser-2",
      scope: AgentExplicitToolHandleScope(ownerId: "owner"),
      capabilities: ["browser.close"]
    )
    let second = try registry.create(
      kind: "browser_session",
      resourceId: "browser-3",
      scope: AgentExplicitToolHandleScope(ownerId: "owner"),
      capabilities: ["browser.close"]
    )

    XCTAssertTrue(try registry.release(handleId: first.handleId, scope: AgentExplicitToolHandleScope(ownerId: "owner")))
    XCTAssertFalse(try registry.release(handleId: first.handleId, scope: AgentExplicitToolHandleScope(ownerId: "owner")))
    XCTAssertEqual(try registry.revokeResource(kind: "browser_session", resourceId: "browser-3"), 1)
    XCTAssertEqual(second.kind, "browser_session")
    XCTAssertEqual(registry.status().activeCount, 0)
  }

  func testAgentExplicitToolHandleCapacityEvictsLeastRecentlyUsed() throws {
    var now: Int64 = 3_000
    let registry = AgentExplicitToolHandleRegistry(nowMillis: { now }, maxHandles: 2)
    let first = try registry.create(
      kind: "browser",
      resourceId: "resource-1",
      scope: AgentExplicitToolHandleScope(ownerId: "phone-a", contextId: "conversation-a"),
      capabilities: ["browser.navigate"]
    )
    now += 1
    let second = try registry.create(
      kind: "browser",
      resourceId: "resource-2",
      scope: AgentExplicitToolHandleScope(ownerId: "phone-a", contextId: "conversation-a"),
      capabilities: ["browser.navigate"]
    )
    now += 1
    _ = try registry.resolve(
      handleId: first.handleId,
      kind: "browser",
      scope: AgentExplicitToolHandleScope(ownerId: "phone-a", contextId: "conversation-a"),
      requiredCapability: "browser.navigate"
    )
    now += 1
    let third = try registry.create(
      kind: "browser",
      resourceId: "resource-3",
      scope: AgentExplicitToolHandleScope(ownerId: "phone-a", contextId: "conversation-a"),
      capabilities: ["browser.navigate"]
    )

    XCTAssertEqual(registry.status().activeCount, 2)
    XCTAssertEqual(registry.status().byKind["browser"], 2)
    XCTAssertEqual(third.kind, "browser")
    XCTAssertEqual(
      try registry.resolve(
        handleId: first.handleId,
        kind: "browser",
        scope: AgentExplicitToolHandleScope(ownerId: "phone-a", contextId: "conversation-a"),
        requiredCapability: "browser.navigate"
      ).resourceId,
      "resource-1"
    )
    assertToolHandleError("tool_handle_not_found", retryable: true) {
      _ = try registry.resolve(
        handleId: second.handleId,
        kind: "browser",
        scope: AgentExplicitToolHandleScope(ownerId: "phone-a", contextId: "conversation-a"),
        requiredCapability: "browser.navigate"
      )
    }
  }

  func testAgentExplicitToolHandleModelsUseAndroidWireNames() throws {
    let scope = try JSONDecoder.signalASI.decode(
      AgentExplicitToolHandleScope.self,
      from: Data(#"{"owner_id":"owner","context_id":"conversation"}"#.utf8)
    )
    let record = AgentExplicitToolHandlePublicRecord(
      contract: AgentExplicitToolHandleContract.version,
      handleId: "sth_browser_abc",
      kind: "browser",
      capabilities: ["browser.navigate"],
      ownerId: "owner",
      contextId: "conversation",
      metadata: ["reuse": .bool(false), "ttl": .int(60)],
      createdAtEpochMillis: 1,
      lastUsedAtEpochMillis: 2,
      expiresAtEpochMillis: 3,
      useCount: 4
    )
    let status = AgentExplicitToolHandleStatus(
      contract: AgentExplicitToolHandleContract.version,
      activeCount: 1,
      byKind: ["browser": 1]
    )
    let recordJSON = String(decoding: try JSONEncoder.signalASI.encode(record), as: UTF8.self)
    let statusJSON = String(decoding: try JSONEncoder.signalASI.encode(status), as: UTF8.self)

    XCTAssertEqual(scope.ownerId, "owner")
    XCTAssertEqual(scope.contextId, "conversation")
    XCTAssertTrue(recordJSON.contains(#""handle_id":"sth_browser_abc""#))
    XCTAssertTrue(recordJSON.contains(#""created_at_epoch_ms":1"#))
    XCTAssertTrue(recordJSON.contains(#""expires_at_epoch_ms":3"#))
    XCTAssertTrue(recordJSON.contains(#""use_count":4"#))
    XCTAssertFalse(recordJSON.contains("resource_id"))
    XCTAssertTrue(statusJSON.contains(#""active_count":1"#))
    XCTAssertTrue(statusJSON.contains(#""by_kind":{"browser":1}"#))
  }

  func testAgentPrivateDataInventoryAuditCoversExportAndEraseDecisions() {
    let audit = AgentPrivateDataInventory.audit()
    let ids = AgentPrivateDataInventory.descriptors.map(\.id)

    XCTAssertTrue(audit.complete)
    XCTAssertTrue(audit.duplicateIds.isEmpty)
    XCTAssertTrue(audit.descriptorsWithoutStorage.isEmpty)
    XCTAssertTrue(audit.exportedDescriptorsWithoutPath.isEmpty)
    XCTAssertTrue(audit.nonExportedDescriptorsWithPath.isEmpty)
    XCTAssertEqual(audit.identityRotationCount, 1)
    XCTAssertEqual(ids.count, Set(ids).count)
  }

  func testAgentPrivateDataInventoryMinimalManifestExcludesOptionalAndLocalOnlyStores() {
    let manifest = AgentPrivateDataInventory.backupManifest(
      includeContacts: false,
      includeSessionHistory: false
    )
    let included = Set(manifest.includedStoreIds)
    let excluded = Set(manifest.excludedStoreIds)

    XCTAssertEqual(manifest.policyVersion, AgentPrivateDataInventory.policyVersion)
    XCTAssertTrue(manifest.encryptedContainerRequired)
    XCTAssertFalse(manifest.privateModeExported)
    XCTAssertFalse(manifest.pausedTrackingExported)
    XCTAssertTrue(manifest.identityRotatedOnReset)
    XCTAssertTrue(included.contains("identity"))
    XCTAssertTrue(included.contains("memory"))
    XCTAssertTrue(included.contains("memory_deletion_index"))
    XCTAssertTrue(included.contains("personal_asi"))
    XCTAssertTrue(excluded.contains("contacts"))
    XCTAssertTrue(excluded.contains("chat_history"))
    XCTAssertTrue(excluded.contains("transcript"))
    XCTAssertTrue(excluded.contains("permission_grants"))
    XCTAssertTrue(excluded.contains("run_start_receipts"))
    XCTAssertTrue(excluded.contains("data_disclosure_ledger"))
    XCTAssertTrue(excluded.contains("runtime_files"))
    XCTAssertEqual(Set(manifest.eraseStoreIds), Set(AgentPrivateDataInventory.descriptors.map(\.id)))
  }

  func testAgentPrivateDataInventoryFullManifestIncludesChosenDataButNeverLiveAuthority() {
    let manifest = AgentPrivateDataInventory.backupManifest(
      includeContacts: true,
      includeSessionHistory: true
    )
    let included = Set(manifest.includedStoreIds)
    let excluded = Set(manifest.excludedStoreIds)
    let all = Set(AgentPrivateDataInventory.descriptors.map(\.id))

    XCTAssertTrue(included.contains("contacts"))
    XCTAssertTrue(included.contains("chat_history"))
    XCTAssertTrue(included.contains("transcript"))
    XCTAssertTrue(included.contains("home_assistant"))
    XCTAssertTrue(Set(manifest.secretStoreIds).contains("identity"))
    XCTAssertTrue(Set(manifest.secretStoreIds).contains("memory_deletion_index"))
    XCTAssertTrue(Set(manifest.secretStoreIds).contains("home_assistant"))
    XCTAssertTrue(excluded.contains("permission_grants"))
    XCTAssertTrue(excluded.contains("run_start_receipts"))
    XCTAssertTrue(excluded.contains("data_disclosure_ledger"))
    XCTAssertTrue(excluded.contains("mcp_credentials"))
    XCTAssertEqual(included.union(excluded), all)
    XCTAssertTrue(included.intersection(excluded).isEmpty)
  }

  func testAgentPrivateDataInventoryExportedBackupPathsMatchAndroidSchema() {
    let paths = Set(
      AgentPrivateDataInventory.descriptors
        .filter { $0.exportPolicy != .neverExport }
        .map(\.backupPath)
    )

    XCTAssertEqual(
      paths,
      Set([
        "root.identity",
        "root.profile",
        "root.contacts",
        "root.friend_requests",
        "root.messages",
        "agent.memory",
        "agent.memory_deletion_index",
        "agent.knowledge",
        "agent.tasks",
        "agent.transcript",
        "agent.agent_conversations",
        "agent.active_agent_conversation",
        "agent.workflows",
        "agent.workflow_schedules",
        "agent.workflow_triggers",
        "agent.workflow_execution_history",
        "agent.safety",
        "agent.custom_device_connectors",
        "agent.global_super_agent",
        "agent.agent_self_model",
        "agent.model_planner",
        "agent.voice_assistant",
        "agent.home_assistant"
      ])
    )
  }

  func testAgentPrivateDataInventoryModelsUseAndroidWireNames() throws {
    let descriptor = try JSONDecoder.signalASI.decode(
      AgentPrivateDataDescriptor.self,
      from: Data(
        """
        {
          "id": "identity",
          "category": "Identity",
          "storage_ids": ["keychain:identity"],
          "backup_path": "root.identity",
          "export_policy": "ALWAYS_ENCRYPTED",
          "sensitivity": "SECRET",
          "erase_policy": "DELETE_AND_ROTATE_IDENTITY"
        }
        """.utf8
      )
    )
    let fallbackPolicy = try JSONDecoder.signalASI.decode(
      AgentPrivateDataExportPolicy.self,
      from: Data(#""future""#.utf8)
    )
    let encoded = String(
      decoding: try JSONEncoder.signalASI.encode(
        AgentPrivateDataInventory.backupManifest(includeContacts: true, includeSessionHistory: false)
      ),
      as: UTF8.self
    )

    XCTAssertEqual(descriptor.exportPolicy, .alwaysEncrypted)
    XCTAssertEqual(descriptor.sensitivity, .secret)
    XCTAssertEqual(descriptor.erasePolicy, .deleteAndRotateIdentity)
    XCTAssertEqual(fallbackPolicy, .neverExport)
    XCTAssertTrue(encoded.contains(#""policy_version":1"#))
    XCTAssertTrue(encoded.contains(#""encrypted_container_required":true"#))
    XCTAssertTrue(encoded.contains(#""identity_rotated_on_reset":true"#))
    XCTAssertTrue(encoded.contains(#""erase_store_ids""#))
  }

  func testAgentFailoverPolicyMatchesAndroidDesktopFallbackAndTimeoutStages() {
    let primary = AgentFailoverResource(location: .trustedDesktop, failureDomain: "desktop-a")
    let cloud = AgentFailoverResource(location: .cloud, failureDomain: "cloud-openai")
    let phone = AgentFailoverResource(location: .phone, failureDomain: "phone")
    let otherDesktop = AgentFailoverResource(location: .trustedDesktop, failureDomain: "desktop-b")
    let sameDesktop = AgentFailoverResource(location: .trustedDesktop, failureDomain: "desktop-a")

    XCTAssertEqual(AgentFailoverPolicy.fallbackTier(primary: primary, candidate: cloud), 0)
    XCTAssertEqual(AgentFailoverPolicy.fallbackTier(primary: primary, candidate: phone), 0)
    XCTAssertEqual(AgentFailoverPolicy.fallbackTier(primary: primary, candidate: otherDesktop), 1)
    XCTAssertEqual(AgentFailoverPolicy.fallbackTier(primary: primary, candidate: sameDesktop), 2)
    XCTAssertEqual(AgentFailoverPolicy.fallbackTier(primary: phone, candidate: sameDesktop), 0)

    XCTAssertTrue(
      AgentFailoverPolicy.shouldFailOver(stage: .notAccepted, status: "", liveReadOnly: false)
    )
    XCTAssertFalse(
      AgentFailoverPolicy.shouldFailOver(stage: .notAccepted, status: "accepted", liveReadOnly: false)
    )
    XCTAssertTrue(
      AgentFailoverPolicy.shouldFailOver(stage: .notRunning, status: "queued", liveReadOnly: false)
    )
    XCTAssertFalse(
      AgentFailoverPolicy.shouldFailOver(stage: .notRunning, status: "running", liveReadOnly: false)
    )
    XCTAssertTrue(
      AgentFailoverPolicy.shouldFailOver(stage: .readOnlyStale, status: "running", liveReadOnly: true)
    )
    XCTAssertFalse(
      AgentFailoverPolicy.shouldFailOver(stage: .readOnlyStale, status: "running", liveReadOnly: false)
    )
  }

  func testAgentFailoverPolicyMatchesAndroidOnlyResourceAndCooldownBehavior() {
    XCTAssertTrue(
      AgentFailoverPolicy.shouldKeepOnlyResourceAlive(stage: .notRunning, status: "accepted", hasFallback: false)
    )
    XCTAssertTrue(
      AgentFailoverPolicy.shouldKeepOnlyResourceAlive(stage: .notRunning, status: "queued", hasFallback: false)
    )
    XCTAssertFalse(
      AgentFailoverPolicy.shouldKeepOnlyResourceAlive(stage: .notRunning, status: "accepted", hasFallback: true)
    )
    XCTAssertTrue(
      AgentFailoverPolicy.shouldKeepOnlyResourceAlive(stage: .notAccepted, status: "", hasFallback: false)
    )
    XCTAssertFalse(
      AgentFailoverPolicy.shouldKeepOnlyResourceAlive(stage: .readOnlyStale, status: "running", hasFallback: false)
    )

    XCTAssertEqual(AgentFailoverPolicy.domainCooldownMs(consecutiveFailures: 0), 60_000)
    XCTAssertEqual(AgentFailoverPolicy.domainCooldownMs(consecutiveFailures: 1), 60_000)
    XCTAssertEqual(AgentFailoverPolicy.domainCooldownMs(consecutiveFailures: 2), 5 * 60_000)
    XCTAssertEqual(AgentFailoverPolicy.domainCooldownMs(consecutiveFailures: 3), 15 * 60_000)
    XCTAssertEqual(AgentFailoverPolicy.domainCooldownMs(consecutiveFailures: 8), 60 * 60_000)
  }

  func testAgentConnectorTimingPolicyMatchesAndroidAttachmentDeadlinesAndWireNames() throws {
    let regular = AgentConnectorTimingPolicy.deadlines(hasAttachments: false)
    let attachment = AgentConnectorTimingPolicy.deadlines(hasAttachments: true)

    XCTAssertEqual(regular.acceptedMs, 5_000)
    XCTAssertEqual(regular.runningMs, 8_000)
    XCTAssertEqual(regular.liveStaleMs, 15_000)
    XCTAssertEqual(attachment.acceptedMs, 60_000)
    XCTAssertEqual(attachment.runningMs, 90_000)
    XCTAssertGreaterThan(attachment.liveStaleMs, regular.liveStaleMs)

    let encoded = try JSONEncoder.signalASI.encode(attachment)
    let encodedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    XCTAssertEqual(encodedObject["accepted_ms"] as? Int, 60_000)
    XCTAssertEqual(encodedObject["running_ms"] as? Int, 90_000)
    XCTAssertEqual(encodedObject["live_stale_ms"] as? Int, 180_000)

    let stage = try JSONDecoder.signalASI.decode(
      AgentConnectorTimeoutStage.self,
      from: Data(#""READ_ONLY_STALE""#.utf8)
    )
    let resource = try JSONDecoder.signalASI.decode(
      AgentFailoverResource.self,
      from: Data(#"{"location":"TRUSTED_DESKTOP","failure_domain":"desktop-a"}"#.utf8)
    )

    XCTAssertEqual(stage, .readOnlyStale)
    XCTAssertEqual(resource.location, .trustedDesktop)
    XCTAssertEqual(resource.failureDomain, "desktop-a")
  }

  func testAgentProactiveTaskSchedulerIntervalCatchUpIsBounded() throws {
    let now: Int64 = 1_800_000_000_000
    let task = try proactiveIntervalTask(
      policy: try AgentProactivePolicy(
        misfire: .catchUp,
        catchUpLimit: 3
      ),
      nextRunAtMillis: now - 20 * 60 * 1_000
    )

    let result = try AgentProactiveTaskScheduler.dueOccurrences(task: task, nowMillis: now)

    XCTAssertEqual(result.occurrences.count, 3)
    XCTAssertTrue(result.occurrences.allSatisfy { $0.status == .queued })
    XCTAssertTrue(result.nextRunAtMillis > now)
  }

  func testAgentProactiveTaskSchedulerFireOnceAndSkipCollapseMissedIntervals() throws {
    let now: Int64 = 1_800_000_000_000
    let fireOnceTask = try proactiveIntervalTask(
      policy: try AgentProactivePolicy(misfire: .fireOnce),
      nextRunAtMillis: now - 10 * 60 * 1_000
    )
    let skipTask = try proactiveIntervalTask(
      policy: try AgentProactivePolicy(
        misfire: .skip,
        catchUpLimit: 2
      ),
      nextRunAtMillis: now - 10 * 60 * 1_000
    )

    let fireOnce = try AgentProactiveTaskScheduler.dueOccurrences(task: fireOnceTask, nowMillis: now)
    let skipped = try AgentProactiveTaskScheduler.dueOccurrences(task: skipTask, nowMillis: now)

    XCTAssertEqual(fireOnce.occurrences.map(\.status), [.queued])
    XCTAssertTrue(fireOnce.nextRunAtMillis > now)
    XCTAssertEqual(skipped.occurrences.count, 2)
    XCTAssertTrue(skipped.occurrences.allSatisfy { $0.status == .skipped })
    XCTAssertTrue(skipped.nextRunAtMillis > now)
  }

  func testAgentProactiveTaskPolicyValidatesTeamLeadAndGoalCheckpoint() throws {
    XCTAssertThrowsError(
      try AgentProactiveAction(
        kind: .subagentTeam,
        team: [
          try AgentProactiveTeamMember(agentId: "codex", role: .observer),
          try AgentProactiveTeamMember(agentId: "hermes", role: .verifier)
        ]
      )
    )
    XCTAssertThrowsError(
      try AgentProactiveTrigger(
        kind: .goalCheckpoint,
        intervalSeconds: 300,
        goalId: ""
      )
    )
  }

  func testAgentProactiveTaskSchedulerInitialRunJitterAndOutcomeDisableRules() throws {
    let now: Int64 = 1_800_000_000_000
    let jitterTask = try proactiveIntervalTask(
      taskId: "jitter-task",
      policy: try AgentProactivePolicy(jitterSeconds: 30),
      nextRunAtMillis: 0
    )

    let next = try AgentProactiveTaskScheduler.initialNextRun(task: jitterTask, nowMillis: now)

    XCTAssertGreaterThanOrEqual(next, now + 60_000)
    XCTAssertLessThanOrEqual(next, now + 90_000)
    XCTAssertEqual(next, try AgentProactiveTaskScheduler.initialNextRun(task: jitterTask, nowMillis: now))

    let limited = try proactiveIntervalTask(
      policy: try AgentProactivePolicy(maxRuns: 1),
      nextRunAtMillis: now + 60_000
    )
    let completed = try AgentProactiveTaskScheduler.recordOutcome(
      task: limited,
      status: .completed,
      completedAtMillis: now
    )

    XCTAssertFalse(completed.enabled)
    XCTAssertEqual(completed.nextRunAtMillis, 0)
    XCTAssertEqual(completed.lastStatus, .completed)
    XCTAssertEqual(completed.runCount, 1)
    XCTAssertEqual(completed.consecutiveFailures, 0)

    let failing = try proactiveIntervalTask(
      policy: try AgentProactivePolicy(maxConsecutiveFailures: 2),
      nextRunAtMillis: now + 60_000,
      consecutiveFailures: 1
    )
    let failed = try AgentProactiveTaskScheduler.recordOutcome(
      task: failing,
      status: .failed,
      completedAtMillis: now
    )

    XCTAssertFalse(failed.enabled)
    XCTAssertEqual(failed.consecutiveFailures, 2)
    XCTAssertTrue(
      AgentProactiveTaskScheduler.shouldDisable(
        task: try proactiveIntervalTask(
          policy: try AgentProactivePolicy(deadlineAtMillis: now - 1),
          nextRunAtMillis: now + 60_000
        ),
        nowMillis: now
      )
    )
  }

  func testAgentProactiveTaskModelsUseAndroidWireNames() throws {
    let task = try AgentProactiveTask(
      taskId: "wire-task",
      name: "Wire task",
      trigger: try AgentProactiveTrigger(
        kind: .interval,
        intervalSeconds: 300,
        eventFilter: ["source.type": "desktop"]
      ),
      action: try AgentProactiveAction(
        kind: .nativeTool,
        targetId: "open_url",
        prompt: "Open the latest report",
        argumentsJson: #"{"path":"/tmp/report.txt","limit":2}"#,
        deliveryMode: "mobile",
        clientRouteId: "route-1",
        grantedPermissions: ["native.open_url"],
        grantedConsents: ["user-approved"]
      ),
      policy: try AgentProactivePolicy(
        misfire: .catchUp,
        catchUpLimit: 4,
        maxConcurrency: 2,
        network: "unmetered",
        requiresCharging: true
      ),
      nextRunAtMillis: 1_800_000_060_000
    )
    let run = try AgentProactiveRun(
      runId: "run-1",
      taskId: task.taskId,
      scheduledForMillis: 1_800_000_060_000,
      status: .waiting,
      attempt: 2,
      causeJson: #"{"type":"manual"}"#,
      linkedExecutionId: "execution-1",
      teamRunId: "team-1"
    )

    let taskObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any])
    let triggerObject = try XCTUnwrap(taskObject["trigger"] as? [String: Any])
    let actionObject = try XCTUnwrap(taskObject["action"] as? [String: Any])
    let policyObject = try XCTUnwrap(taskObject["policy"] as? [String: Any])
    let runObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(run)) as? [String: Any])

    XCTAssertEqual(taskObject["protocol"] as? String, AgentProactiveTaskScheduler.protocolVersion)
    XCTAssertEqual(taskObject["task_id"] as? String, "wire-task")
    XCTAssertNotNil(taskObject["next_run_at_millis"])
    XCTAssertEqual(triggerObject["interval_seconds"] as? Int, 300)
    XCTAssertEqual(triggerObject["event_filter"] as? [String: String], ["source.type": "desktop"])
    XCTAssertEqual(actionObject["target_id"] as? String, "open_url")
    XCTAssertNotNil(actionObject["arguments"] as? [String: Any])
    XCTAssertNil(actionObject["arguments_json"])
    XCTAssertEqual(actionObject["delivery_mode"] as? String, "mobile")
    XCTAssertEqual(actionObject["client_route_id"] as? String, "route-1")
    XCTAssertEqual(policyObject["catch_up_limit"] as? Int, 4)
    XCTAssertEqual(policyObject["max_concurrency"] as? Int, 2)
    XCTAssertEqual(policyObject["requires_charging"] as? Bool, true)
    XCTAssertNotNil(runObject["cause"] as? [String: Any])
    XCTAssertNil(runObject["cause_json"])
    XCTAssertEqual(runObject["linked_execution_id"] as? String, "execution-1")

    let decoded = try JSONDecoder().decode(AgentProactiveTask.self, from: JSONEncoder().encode(task))
    let fallback = try JSONDecoder().decode(
      AgentProactiveMisfirePolicy.self,
      from: Data(#""future""#.utf8)
    )

    XCTAssertEqual(decoded.action.argumentsJson, #"{"limit":2,"path":"/tmp/report.txt"}"#)
    XCTAssertEqual(decoded.policy.misfire, .catchUp)
    XCTAssertEqual(fallback, .fireOnce)
  }

  func testGlobalProactiveInboxProjectsDeliveredFindingsAndDigests() {
    let items = GlobalProactiveInboxPolicy.project(
      messages: [
        globalProactiveMessage("current"),
        globalProactiveMessage("topic", target: .newConversation)
      ],
      feedback: []
    )
    let digest = GlobalProactiveInboxPolicy.project(
      messages: [
        globalProactiveMessage("digest-a", target: .globalDigest, deliveryGroupId: "daily"),
        globalProactiveMessage(
          "digest-b",
          target: .globalDigest,
          content: "A second material change is ready.",
          topic: "Release risk",
          deliveryGroupId: "daily"
        )
      ],
      feedback: []
    )

    XCTAssertEqual(items.count, 2)
    XCTAssertEqual(GlobalProactiveInboxPolicy.newCount(items), 2)
    XCTAssertTrue(items.allSatisfy(\.isNew))
    XCTAssertEqual(Set(items.map(\.destinationConversationId)), Set(["destination"]))
    XCTAssertEqual(digest.count, 1)
    XCTAssertEqual(digest.first?.key, "global-agent-digest:daily")
    XCTAssertEqual(digest.first?.messageIds, Set(["digest-a", "digest-b"]))
    XCTAssertTrue(digest.first?.content.contains("Release risk") == true)
  }

  func testGlobalProactiveInboxFiltersStatusesAndFeedback() {
    let pending = globalProactiveMessage("pending", status: .pending)
    let dismissed = globalProactiveMessage("dismissed", status: .dismissed)
    let helpful = globalProactiveMessage("helpful")
    let irrelevant = globalProactiveMessage("irrelevant")
    let frequent = globalProactiveMessage("frequent")

    let statusItems = GlobalProactiveInboxPolicy.project(messages: [pending, dismissed], feedback: [])
    let helpfulItem = GlobalProactiveInboxPolicy.project(
      messages: [helpful],
      feedback: [globalAgentFeedback(messageId: helpful.id, kind: .helpful)]
    ).first
    let negativeItems = GlobalProactiveInboxPolicy.project(
      messages: [irrelevant, frequent],
      feedback: [
        globalAgentFeedback(messageId: irrelevant.id, kind: .notRelevant),
        globalAgentFeedback(messageId: frequent.id, kind: .tooFrequent)
      ]
    )

    XCTAssertTrue(statusItems.isEmpty)
    XCTAssertFalse(helpfulItem?.isNew ?? true)
    XCTAssertEqual(helpfulItem?.feedbackKind, .helpful)
    XCTAssertTrue(negativeItems.isEmpty)
  }

  func testGlobalProactiveInboxMarksOnlySelectedDeliveredMessagesViewed() {
    let delivered = globalProactiveMessage("delivered")
    let untouched = globalProactiveMessage("untouched")
    let pending = globalProactiveMessage("pending", status: .pending)

    let updated = Dictionary(
      uniqueKeysWithValues: GlobalProactiveInboxPolicy.markViewed(
        messages: [delivered, untouched, pending],
        messageIds: Set(["delivered", "pending"]),
        nowMillis: 9_000
      ).map { ($0.id, $0) }
    )

    XCTAssertEqual(updated["delivered"]?.viewedAtMillis, 9_000)
    XCTAssertEqual(updated["untouched"]?.viewedAtMillis, 0)
    XCTAssertEqual(updated["pending"]?.viewedAtMillis, 0)
  }

  func testGlobalProactiveInboxModelsUseAndroidWireNames() throws {
    let decoded = try JSONDecoder().decode(
      GlobalProactiveMessage.self,
      from: Data(
        #"""
        {
          "id": "wire",
          "source_event_id": "event-wire",
          "source_conversation_id": "source",
          "target": "global-digest",
          "title": "Signal digest",
          "content": "Digest ready",
          "topic": "Release risk",
          "urgent": true,
          "causal_event_ids": ["event-a", "event-b"],
          "status": "delivered",
          "delivered_at_millis": 5,
          "delivered_conversation_id": "destination",
          "delivery_group_id": "daily"
        }
        """#.utf8
      )
    )
    let feedback = try JSONDecoder().decode(
      GlobalAgentFeedback.self,
      from: Data(
        #"""
        {
          "proactive_message_id": "wire",
          "delivery_group_id": "daily",
          "conversation_id": "destination",
          "topic": "Release risk",
          "target": "CURRENT_CONVERSATION",
          "kind": "too-frequent",
          "created_at_millis": 6
        }
        """#.utf8
      )
    )
    let fallbackTarget = try JSONDecoder().decode(
      GlobalProactiveTarget.self,
      from: Data(#""future""#.utf8)
    )
    let fallbackStatus = try JSONDecoder().decode(
      GlobalProactiveMessageStatus.self,
      from: Data(#""future""#.utf8)
    )
    let legacy = GlobalProactiveInboxPolicy.project(
      messages: [globalProactiveMessage("legacy", title: "Signal \u{5efa}\u{8bae}")],
      feedback: []
    ).first
    let projected = try XCTUnwrap(GlobalProactiveInboxPolicy.project(messages: [decoded], feedback: []).first)
    let encoded = String(decoding: try JSONEncoder().encode(projected), as: UTF8.self)

    XCTAssertEqual(decoded.target, .globalDigest)
    XCTAssertEqual(decoded.status, .delivered)
    XCTAssertEqual(decoded.causalEventIds, Set(["event-a", "event-b"]))
    XCTAssertEqual(feedback.kind, .tooFrequent)
    XCTAssertEqual(fallbackTarget, .currentConversation)
    XCTAssertEqual(fallbackStatus, .pending)
    XCTAssertEqual(legacy?.title, "SignalASI \u{5efa}\u{8bae}")
    XCTAssertEqual(GlobalAgentText.productTitle("Signal Protocol"), "Signal Protocol")
    XCTAssertTrue(encoded.contains(#""message_ids""#))
    XCTAssertTrue(encoded.contains(#""destination_conversation_id":"destination""#))
  }

  func testAgentTranscriptScrollPolicyMatchesAndroidAutoFollowAndPagination() {
    XCTAssertTrue(
      AgentTranscriptScrollPolicy.nextAutoFollow(
        current: true,
        userScrollActive: false,
        itemCount: 3,
        lastVisiblePosition: 2,
        remainingPx: 600,
        thresholdPx: 56
      )
    )
    XCTAssertFalse(
      AgentTranscriptScrollPolicy.nextAutoFollow(
        current: true,
        userScrollActive: true,
        itemCount: 3,
        lastVisiblePosition: 1,
        remainingPx: Int.max,
        thresholdPx: 56
      )
    )
    XCTAssertTrue(
      AgentTranscriptScrollPolicy.nextAutoFollow(
        current: false,
        userScrollActive: true,
        itemCount: 3,
        lastVisiblePosition: 2,
        remainingPx: 20,
        thresholdPx: 56
      )
    )
    XCTAssertTrue(
      AgentTranscriptScrollPolicy.shouldLoadOlderFromScroll(
        dy: -8,
        firstVisiblePosition: 1,
        hydrationPending: false
      )
    )
    XCTAssertTrue(
      AgentTranscriptScrollPolicy.shouldLoadOlderFromPull(
        downY: 200,
        currentY: 240,
        canScrollUp: false,
        hydrationPending: false,
        thresholdPx: 24
      )
    )
  }

  func testAgentTranscriptScrollPolicyBlocksOrdinaryScrollAndHydration() {
    XCTAssertFalse(
      AgentTranscriptScrollPolicy.shouldLoadOlderFromScroll(
        dy: 12,
        firstVisiblePosition: 0,
        hydrationPending: false
      )
    )
    XCTAssertFalse(
      AgentTranscriptScrollPolicy.shouldLoadOlderFromPull(
        downY: 200,
        currentY: 240,
        canScrollUp: true,
        hydrationPending: false,
        thresholdPx: 24
      )
    )
    XCTAssertFalse(
      AgentTranscriptScrollPolicy.shouldLoadOlderFromScroll(
        dy: -8,
        firstVisiblePosition: 0,
        hydrationPending: true
      )
    )
    XCTAssertFalse(
      AgentTranscriptScrollPolicy.shouldLoadOlderFromPull(
        downY: 200,
        currentY: 240,
        canScrollUp: false,
        hydrationPending: true,
        thresholdPx: 24
      )
    )
  }

  func testAgentFinalResponseIdentityMatchesAndroidPriorityAndResolution() {
    let local = AgentFinalResponseIdentity.dedupeKey(
      turnId: "turn-1",
      sourceMessageId: 101,
      taskId: "mobile-session"
    )
    let remote = AgentFinalResponseIdentity.dedupeKey(
      turnId: "turn-1",
      sourceMessageId: 101,
      taskId: "desktop-task"
    )

    XCTAssertEqual(local, remote)
    XCTAssertEqual(
      AgentFinalResponseIdentity.dedupeKey(turnId: "", sourceMessageId: 202, taskId: "mobile-session"),
      AgentFinalResponseIdentity.dedupeKey(turnId: "", sourceMessageId: 202, taskId: "desktop-task")
    )
    XCTAssertNotEqual(
      AgentFinalResponseIdentity.dedupeKey(turnId: "turn-1", sourceMessageId: 101, taskId: "task"),
      AgentFinalResponseIdentity.dedupeKey(turnId: "turn-2", sourceMessageId: 101, taskId: "task")
    )
    XCTAssertEqual(
      AgentFinalResponseIdentity.dedupeKey(turnId: "", taskId: " task-1 "),
      "assistant-final:task:task-1"
    )
    XCTAssertEqual(
      AgentFinalResponseIdentity.resolveTurnId(
        explicitTurnId: "",
        taskId: "task-1"
      ) { taskId in
        taskId == "task-1" ? "turn-1" : nil
      },
      "turn-1"
    )
    XCTAssertEqual(
      AgentFinalResponseIdentity.resolveTurnId(
        explicitTurnId: " turn-2 ",
        taskId: "task-1"
      ) { _ in "turn-1" },
      "turn-2"
    )
  }

  func testAgentTranscriptEntryDecodesAndroidWireNames() throws {
    let decoded = try JSONDecoder().decode(
      AgentTranscriptEntry.self,
      from: Data(
        #"""
        {
          "id": "entry-1",
          "role": "ASSISTANT",
          "text": "CODEX_OK",
          "timestamp_millis": 42,
          "dedupe_key": "assistant-final:turn:turn-1",
          "conversation_id": "conversation",
          "turn_id": "turn-1",
          "task_id": "task-1",
          "rich_output_json": "{\"type\":\"markdown\"}",
          "source_conversation_id": "source-conversation",
          "source_conversation_title": "Source",
          "source_entry_id": "source-entry"
        }
        """#.utf8
      )
    )

    XCTAssertEqual(decoded.role, .assistant)
    XCTAssertEqual(decoded.timestampMillis, 42)
    XCTAssertEqual(decoded.dedupeKey, "assistant-final:turn:turn-1")
    XCTAssertEqual(decoded.richOutputJson, #"{"type":"markdown"}"#)
    XCTAssertEqual(decoded.sourceConversationTitle, "Source")

    let fallback = try JSONDecoder().decode(
      AgentTranscriptEntry.self,
      from: Data(#"{"id":"entry-2","role":"FUTURE","text":"Running"}"#.utf8)
    )
    XCTAssertEqual(fallback.role, .process)

    let encoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
    XCTAssertTrue(encoded.contains(#""timestamp_millis":42"#))
    XCTAssertTrue(encoded.contains(#""dedupe_key":"assistant-final:turn:turn-1""#))
    XCTAssertTrue(encoded.contains(#""rich_output_json":"#))
  }

  func testAgentTranscriptLifecyclePolicyRemovesOnlyLegacyPlannerProcessRows() {
    XCTAssertTrue(
      AgentTranscriptLifecyclePolicy.isObsoletePlannerProcessEntry(
        role: .process,
        dedupeKey: "pending:plan:ask-codex:1"
      )
    )
    XCTAssertFalse(
      AgentTranscriptLifecyclePolicy.isObsoletePlannerProcessEntry(
        role: .user,
        dedupeKey: "pending:plan:user-text:1"
      )
    )
    XCTAssertFalse(
      AgentTranscriptLifecyclePolicy.isObsoletePlannerProcessEntry(
        role: .process,
        dedupeKey: "connector-task:task-id"
      )
    )
  }

  func testAgentTranscriptLifecyclePolicyRecoversStaleConnectorTurnWithoutAssistantReply() {
    let entries = [
      transcriptEntry("user", role: .user, timestampMillis: 1),
      transcriptEntry("remote", timestampMillis: 2, dedupeKey: "connector-task:task")
    ]
    let task = agentTaskRecord(
      phase: .completed,
      result: " Recovered result\n",
      updatedAtMillis: 2
    )

    let recovered = AgentTranscriptLifecyclePolicy.staleConnectorRecoveries(
      entries: entries,
      tasks: [task],
      activeTaskIds: [],
      nowMillis: AgentTranscriptLifecyclePolicy.staleConnectorMillis + 3
    )

    XCTAssertEqual(recovered.count, 1)
    XCTAssertEqual(recovered.first?.conversationId, "conversation")
    XCTAssertEqual(recovered.first?.turnId, "turn")
    XCTAssertEqual(recovered.first?.taskId, "task")
    XCTAssertEqual(recovered.first?.result, "Recovered result")
  }

  func testAgentTranscriptLifecyclePolicySkipsActiveAnsweredFreshAndInternalPlannerResults() {
    let user = transcriptEntry("user", role: .user, timestampMillis: 1)
    let process = transcriptEntry("remote", timestampMillis: 2, dedupeKey: "connector-task:task")
    let approval = transcriptEntry(
      "approval",
      role: .assistant,
      timestampMillis: 3,
      dedupeKey: "remote-approval:task"
    )
    let assistant = transcriptEntry(
      "assistant",
      role: .assistant,
      timestampMillis: 4,
      dedupeKey: "assistant-final:turn:turn"
    )
    let task = agentTaskRecord(result: "Recovered result", updatedAtMillis: 2)

    let answered = AgentTranscriptLifecyclePolicy.staleConnectorRecoveries(
      entries: [user, process, assistant],
      tasks: [task],
      activeTaskIds: [],
      nowMillis: 10 * 60 * 1_000
    )
    let active = AgentTranscriptLifecyclePolicy.staleConnectorRecoveries(
      entries: [user, process],
      tasks: [task],
      activeTaskIds: ["task"],
      nowMillis: 10 * 60 * 1_000
    )
    let fresh = AgentTranscriptLifecyclePolicy.staleConnectorRecoveries(
      entries: [user, process],
      tasks: [agentTaskRecord(result: "Recovered result", updatedAtMillis: 9 * 60 * 1_000)],
      activeTaskIds: [],
      nowMillis: 10 * 60 * 1_000
    )
    let approvalOnly = AgentTranscriptLifecyclePolicy.staleConnectorRecoveries(
      entries: [user, process, approval],
      tasks: [task],
      activeTaskIds: [],
      nowMillis: 10 * 60 * 1_000
    )
    let internalPlanner = AgentTranscriptLifecyclePolicy.staleConnectorRecoveries(
      entries: [
        transcriptEntry("user-2", role: .user, turnId: "turn-2", timestampMillis: 1, taskId: "internal-task"),
        transcriptEntry(
          "remote-2",
          turnId: "turn-2",
          timestampMillis: 2,
          dedupeKey: "connector-task:internal-task",
          taskId: "internal-task"
        )
      ],
      tasks: [
        agentTaskRecord(
          taskId: "internal-task",
          result: "Create a safe local task plan for local-agent-runtime",
          updatedAtMillis: 2
        )
      ],
      activeTaskIds: [],
      nowMillis: 10 * 60 * 1_000
    )

    XCTAssertTrue(answered.isEmpty)
    XCTAssertTrue(active.isEmpty)
    XCTAssertTrue(fresh.isEmpty)
    XCTAssertEqual(approvalOnly.count, 1)
    XCTAssertEqual(internalPlanner.count, 1)
    XCTAssertEqual(internalPlanner.first?.result, "")
  }

  func testAgentTranscriptLifecycleModelsUseAndroidWireNames() throws {
    let decodedTask = try JSONDecoder().decode(
      AgentTaskRecord.self,
      from: Data(
        #"""
        {
          "task_id": "task",
          "session_id": "conversation",
          "goal": "goal",
          "phase": "COMPLETED",
          "route_kind": "DESKTOP_AGENT",
          "target_title": "Codex",
          "risk": "LOW",
          "blocked": false,
          "result": "Recovered",
          "verification": "Verified",
          "output_files": ["report.md"],
          "execution_log": ["step"],
          "created_at_millis": 1,
          "updated_at_millis": 2
        }
        """#.utf8
      )
    )
    let fallbackTask = try JSONDecoder().decode(
      AgentTaskRecord.self,
      from: Data(#"{"task_id":"future","session_id":"conversation","goal":"goal","phase":"FUTURE","route_kind":"FUTURE","risk":"FUTURE"}"#.utf8)
    )
    let recovery = AgentStaleConnectorRecovery(
      conversationId: "conversation",
      turnId: "turn",
      taskId: "task",
      result: "Recovered"
    )
    let encodedTask = String(decoding: try JSONEncoder().encode(decodedTask), as: UTF8.self)
    let encodedRecovery = String(decoding: try JSONEncoder().encode(recovery), as: UTF8.self)

    XCTAssertEqual(decodedTask.phase, .completed)
    XCTAssertEqual(decodedTask.routeKind, .desktopAgent)
    XCTAssertEqual(decodedTask.risk, .low)
    XCTAssertEqual(decodedTask.executionLocationKind, .unknown)
    XCTAssertEqual(decodedTask.executionRuntimeKind, .unknown)
    XCTAssertTrue(decodedTask.executionLocationTrusted)
    XCTAssertEqual(decodedTask.outputFiles, ["report.md"])
    XCTAssertEqual(decodedTask.executionLog, ["step"])
    XCTAssertEqual(fallbackTask.phase, .executing)
    XCTAssertEqual(fallbackTask.routeKind, .unknown)
    XCTAssertEqual(fallbackTask.risk, .medium)
    XCTAssertTrue(encodedTask.contains(#""updated_at_millis":2"#))
    XCTAssertTrue(encodedTask.contains(#""route_kind":"DESKTOP_AGENT""#))
    XCTAssertTrue(encodedTask.contains(#""execution_location_kind":"UNKNOWN""#))
    XCTAssertTrue(encodedTask.contains(#""execution_runtime_kind":"UNKNOWN""#))
    XCTAssertTrue(encodedRecovery.contains(#""conversation_id":"conversation""#))
    XCTAssertTrue(encodedRecovery.contains(#""turn_id":"turn""#))
  }

  func testAgentTranscriptPresentationPolicyCollapsesProcessGroupsBetweenUserAndAssistant() {
    let entries = [
      transcriptEntry("process-before-user", timestampMillis: 1),
      transcriptEntry("user", role: .user, timestampMillis: 2),
      transcriptEntry("process-running", timestampMillis: 3),
      transcriptEntry("process-linux", timestampMillis: 4),
      transcriptEntry("assistant", role: .assistant, timestampMillis: 5)
    ]

    let visible = AgentTranscriptPresentationPolicy.collapseProcessGroups(entries)

    XCTAssertEqual(visible.map(\.role), [.user, .process, .assistant])
    XCTAssertEqual(visible[1].text, "process-linux")
    XCTAssertTrue(visible[1].id.hasPrefix("process-group:"))
  }

  func testAgentTranscriptPresentationPolicyFoldsRemoteCompletionAndKeepsStableRenderId() {
    let user = transcriptEntry("user", role: .user, timestampMillis: 10)
    let accepted = transcriptEntry("accepted", timestampMillis: 20)
    let running = transcriptEntry("running", timestampMillis: 30)
    let assistant = transcriptEntry("assistant", role: .assistant, timestampMillis: 40)
    let completed = transcriptEntry(
      "completed",
      turnId: "remote-codex-turn",
      timestampMillis: 50
    )

    let completedVisible = AgentTranscriptPresentationPolicy.collapseProcessGroups([
      user,
      running,
      assistant,
      completed
    ])
    let initial = AgentTranscriptPresentationPolicy.collapseProcessGroups([user, accepted])
    let updated = AgentTranscriptPresentationPolicy.collapseProcessGroups([user, running])
    let diff = AgentTranscriptRenderPolicy.diff(
      renderedIds: initial.map(AgentTranscriptRenderPolicy.identity),
      renderedSignatures: Dictionary(uniqueKeysWithValues: initial.map {
        (AgentTranscriptRenderPolicy.identity($0), AgentTranscriptRenderPolicy.signature($0))
      }),
      incoming: updated
    )

    XCTAssertEqual(completedVisible.map(\.role), [.user, .process, .assistant])
    XCTAssertEqual(completedVisible[1].text, "completed")
    XCTAssertEqual(completedVisible[1].turnId, "turn")
    XCTAssertEqual(initial[1].id, updated[1].id)
    XCTAssertFalse(diff.reset)
    XCTAssertEqual(diff.replacementIndices, [1])
  }

  func testAgentTranscriptPresentationPolicyClassifiesExpansionCompletionAndDurations() {
    XCTAssertEqual(
      AgentTranscriptPresentationPolicy.processVisualKind("\u{5df2}\u{5206}\u{6790}\u{8bf7}\u{6c42}"),
      .analysis
    )
    XCTAssertEqual(
      AgentTranscriptPresentationPolicy.processVisualKind("\u{6b63}\u{5728}\u{8fd0}\u{884c}\u{624b}\u{673a}\u{672c}\u{5730} Linux"),
      .command
    )
    XCTAssertEqual(AgentTranscriptPresentationPolicy.processVisualKind("Edited 2 files"), .file)
    XCTAssertEqual(
      AgentTranscriptPresentationPolicy.processVisualKind("\u{5df2}\u{67e5}\u{770b} 1 \u{5f20}\u{56fe}\u{7247}"),
      .image
    )
    XCTAssertEqual(AgentTranscriptPresentationPolicy.processVisualKind("Web search complete"), .network)

    XCTAssertTrue(AgentTranscriptPresentationPolicy.processExpanded(
      completed: false,
      manuallyExpanded: false,
      manuallyCollapsedWhileActive: false
    ))
    XCTAssertFalse(AgentTranscriptPresentationPolicy.processExpanded(
      completed: false,
      manuallyExpanded: false,
      manuallyCollapsedWhileActive: true
    ))
    XCTAssertFalse(AgentTranscriptPresentationPolicy.processExpanded(
      completed: true,
      manuallyExpanded: false,
      manuallyCollapsedWhileActive: false
    ))
    XCTAssertTrue(AgentTranscriptPresentationPolicy.processExpanded(
      completed: true,
      manuallyExpanded: true,
      manuallyCollapsedWhileActive: false
    ))

    XCTAssertTrue(AgentTranscriptPresentationPolicy.processClockStopsFor(.waitingConfirmation))
    XCTAssertTrue(AgentTranscriptPresentationPolicy.processClockStopsFor(.completed))
    XCTAssertFalse(AgentTranscriptPresentationPolicy.processClockStopsFor(.executing))
    XCTAssertFalse(AgentTranscriptPresentationPolicy.processClockStopsFor(.waitingResponse))

    XCTAssertFalse(AgentTranscriptPresentationPolicy.shouldRenderToolCompletion(
      actionKind: .callConnector,
      succeeded: true,
      awaitingResponse: true
    ))
    XCTAssertFalse(AgentTranscriptPresentationPolicy.shouldRenderToolCompletion(
      actionKind: .callConnector,
      succeeded: true,
      awaitingResponse: nil
    ))
    XCTAssertTrue(AgentTranscriptPresentationPolicy.shouldRenderToolCompletion(
      actionKind: .callConnector,
      succeeded: true,
      awaitingResponse: false
    ))
    XCTAssertTrue(AgentTranscriptPresentationPolicy.shouldRenderToolCompletion(
      actionKind: .callConnector,
      succeeded: false,
      awaitingResponse: true
    ))
    XCTAssertTrue(AgentTranscriptPresentationPolicy.shouldRenderToolCompletion(
      actionKind: .callNativeTool,
      succeeded: true,
      awaitingResponse: false
    ))

    XCTAssertEqual(AgentTranscriptPresentationPolicy.formatElapsedSeconds(0), "1s")
    XCTAssertEqual(AgentTranscriptPresentationPolicy.formatElapsedSeconds(999), "1s")
    XCTAssertEqual(AgentTranscriptPresentationPolicy.formatElapsedSeconds(1_999), "1s")
    XCTAssertEqual(AgentTranscriptPresentationPolicy.formatElapsedSeconds(2_000), "2s")
    XCTAssertEqual(AgentTranscriptPresentationPolicy.formatElapsedSeconds(59_999), "59s")
    XCTAssertEqual(AgentTranscriptPresentationPolicy.formatElapsedSeconds(60_000), "1m")
    XCTAssertEqual(AgentTranscriptPresentationPolicy.formatElapsedSeconds(77_000), "1m 17s")
    XCTAssertEqual(AgentTranscriptPresentationPolicy.formatElapsedSeconds(3_600_000), "1h")
    XCTAssertEqual(AgentTranscriptPresentationPolicy.formatElapsedSeconds(4_646_000), "1h 17m 26s")
    XCTAssertEqual(
      AgentTranscriptPresentationPolicy.formatProcessedDuration(
        4_646_000,
        hoursUnit: "\u{5c0f}\u{65f6}",
        minutesUnit: "\u{5206}\u{949f}",
        secondsUnit: "\u{79d2}"
      ),
      "1\u{5c0f}\u{65f6} 17\u{5206}\u{949f} 26\u{79d2}"
    )
    XCTAssertEqual(
      AgentTranscriptPresentationPolicy.processedSummary(
        completed: false,
        duration: "17s"
      ),
      "Working for 17s"
    )
    XCTAssertEqual(
      AgentTranscriptPresentationPolicy.processedSummary(
        completed: true,
        duration: "17\u{79d2}",
        processingFormat: "\u{5904}\u{7406}\u{4e2d} %@",
        processedFormat: "\u{5df2}\u{5904}\u{7406} %@"
      ),
      "\u{5df2}\u{5904}\u{7406} 17\u{79d2}"
    )
  }

  func testAgentTranscriptPresentationPolicySegmentsVisibleProcessRows() {
    let entries = [
      transcriptEntry(
        "generic-analysis",
        text: "Analyzed the request - Codex",
        dedupeKey: "audit:1:REASONING_SUMMARY:fallback"
      ),
      transcriptEntry("tool-start", timestampMillis: 2, dedupeKey: "audit:2:TOOL_STARTED:x"),
      transcriptEntry("tool-complete", timestampMillis: 3, dedupeKey: "audit:3:TOOL_COMPLETED:x"),
      transcriptEntry(
        "plan",
        timestampMillis: 4,
        text: "Implement a small Python program",
        dedupeKey: "pending:plan:action"
      ),
      transcriptEntry("phone-linux", timestampMillis: 5, dedupeKey: "audit:5:TOOL_STARTED:y"),
      transcriptEntry("phone-linux-complete", timestampMillis: 6, dedupeKey: "audit:6:TOOL_COMPLETED:y")
    ]
    let connectorEntries = [
      transcriptEntry(
        "fallback-analysis",
        text: "Analyzed the request",
        dedupeKey: "audit:1:REASONING_SUMMARY:fallback"
      ),
      transcriptEntry("running-codex", text: "Running Codex", dedupeKey: "audit:2:TOOL_STARTED:codex"),
      transcriptEntry(
        "commentary",
        timestampMillis: 3,
        text: "I will inspect the provided input before acting.",
        dedupeKey: "connector-event:task:REASONING_SUMMARY:codex:commentary:1"
      ),
      transcriptEntry(
        "image-view",
        timestampMillis: 4,
        text: "Viewed 1 image",
        dedupeKey: "connector-event:task:TOOL_EVENT:codex:image_view:1"
      )
    ]

    let segments = AgentTranscriptPresentationPolicy.processSegments(entries)
    let connectorSegments = AgentTranscriptPresentationPolicy.processSegments(connectorEntries)

    XCTAssertEqual(segments.map(\.kind), [.toolActivity, .narration, .toolActivity])
    XCTAssertEqual(segments.map { $0.entries.count }, [3, 1, 2])
    XCTAssertEqual(
      connectorSegments.flatMap { $0.entries }.map(\.text),
      ["I will inspect the provided input before acting.", "Viewed 1 image"]
    )
    XCTAssertEqual(connectorSegments.map(\.kind), [.narration, .toolActivity])
    XCTAssertEqual(
      AgentTranscriptPresentationPolicy.narrationSegments(connectorEntries).flatMap { $0.entries }.map(\.text),
      ["I will inspect the provided input before acting."]
    )
  }

  func testAgentTranscriptPresentationPolicyFiltersInternalProcessNoise() {
    let loopEntries = [
      transcriptEntry("planning", text: "Planning", dedupeKey: "agent-loop:turn:PLAN:1"),
      transcriptEntry("observe", timestampMillis: 2, text: "Checking the result", dedupeKey: "agent-loop:turn:OBSERVE:2"),
      transcriptEntry(
        "waiting",
        timestampMillis: 3,
        text: "Waiting for a resource",
        dedupeKey: "agent-loop:turn:WAITING_RESPONSE:3"
      ),
      transcriptEntry(
        "heartbeat",
        timestampMillis: 4,
        text: "Working",
        dedupeKey: "connector-event:task:TOOL_EVENT:codex:heartbeat:1"
      ),
      transcriptEntry("watchdog", timestampMillis: 5, text: "No progress reported", dedupeKey: "task-watchdog:turn"),
      transcriptEntry("finalize", timestampMillis: 6, text: "Finalizing", dedupeKey: "agent-loop:turn:FINALIZE:4")
    ]
    let legacyEntries = [
      transcriptEntry("user", role: .user, timestampMillis: 1),
      transcriptEntry(
        "legacy-zh",
        timestampMillis: 2,
        text: "\u{8fd0}\u{884c}\u{4e86} 3 \u{4e2a}\u{5de5}\u{5177}\u{6b65}\u{9aa4}",
        dedupeKey: "pending:legacy:tool-summary"
      ),
      transcriptEntry("legacy-en", timestampMillis: 3, text: "Ran 2 tool steps.", dedupeKey: "pending:legacy:tool-summary-en"),
      transcriptEntry("assistant", role: .assistant, timestampMillis: 4)
    ]
    let runtimeEntries = [
      transcriptEntry("user", role: .user, timestampMillis: 1),
      transcriptEntry(
        "runtime",
        timestampMillis: 2,
        text: "Execute in the on-device Linux sandbox",
        dedupeKey: "pending:plan:runtime"
      ),
      transcriptEntry(
        "implementation",
        timestampMillis: 3,
        text: "Implement a small Python program",
        dedupeKey: "pending:plan:summary"
      ),
      transcriptEntry("assistant", role: .assistant, timestampMillis: 4)
    ]

    XCTAssertTrue(AgentTranscriptPresentationPolicy.processSegments(loopEntries).isEmpty())
    XCTAssertEqual(
      AgentTranscriptPresentationPolicy.collapseProcessGroups(legacyEntries).map(\.text),
      ["user", "assistant"]
    )
    XCTAssertTrue(AgentTranscriptPresentationPolicy.processSegments(legacyEntries).isEmpty())
    XCTAssertEqual(
      AgentTranscriptPresentationPolicy.collapseProcessGroups(runtimeEntries).map(\.text),
      ["user", "Implement a small Python program", "assistant"]
    )
    XCTAssertEqual(AgentTranscriptPresentationPolicy.controlMessageKind("Task cancelled"), .cancelled)
    XCTAssertEqual(AgentTranscriptPresentationPolicy.controlMessageKind(" task CANCELED "), .cancelled)
    XCTAssertNil(AgentTranscriptPresentationPolicy.controlMessageKind("The user discussed a cancelled task"))
  }

  func testAgentTranscriptRenderPolicyMatchesAndroidDiffRules() {
    let previous = transcriptEntry("process-1", text: "Accepted")
    let current = transcriptEntry("process-1", text: "Running")
    let first = transcriptEntry("user-1", role: .user, text: "Run this")
    let second = transcriptEntry("process-2", text: "Processing")
    let assistantPrevious = transcriptEntry("assistant-1", role: .assistant, text: "Done", richOutputJson: #"{"type":"text"}"#)
    let assistantCurrent = transcriptEntry("assistant-1", role: .assistant, text: "Done", richOutputJson: #"{"type":"table"}"#)

    let changed = AgentTranscriptRenderPolicy.diff(
      renderedIds: [previous.id],
      renderedSignatures: [previous.id: AgentTranscriptRenderPolicy.signature(previous)],
      incoming: [current]
    )
    let appended = AgentTranscriptRenderPolicy.diff(
      renderedIds: [first.id],
      renderedSignatures: [first.id: AgentTranscriptRenderPolicy.signature(first)],
      incoming: [first, second]
    )
    let reset = AgentTranscriptRenderPolicy.diff(
      renderedIds: [first.id, second.id],
      renderedSignatures: [
        first.id: AgentTranscriptRenderPolicy.signature(first),
        second.id: AgentTranscriptRenderPolicy.signature(second)
      ],
      incoming: [second]
    )
    let richChanged = AgentTranscriptRenderPolicy.diff(
      renderedIds: [assistantPrevious.id],
      renderedSignatures: [assistantPrevious.id: AgentTranscriptRenderPolicy.signature(assistantPrevious)],
      incoming: [assistantCurrent]
    )
    let assistantAppended = AgentTranscriptRenderPolicy.diff(
      renderedIds: [first.id, second.id],
      renderedSignatures: [
        first.id: AgentTranscriptRenderPolicy.signature(first),
        second.id: AgentTranscriptRenderPolicy.signature(second)
      ],
      incoming: [first, second, transcriptEntry("assistant-2", role: .assistant, text: "Done")]
    )

    XCTAssertFalse(changed.reset)
    XCTAssertEqual(changed.replacementIndices, [0])
    XCTAssertEqual(changed.appendFromIndex, 1)
    XCTAssertFalse(appended.reset)
    XCTAssertTrue(appended.replacementIndices.isEmpty)
    XCTAssertEqual(appended.appendFromIndex, 1)
    XCTAssertTrue(reset.reset)
    XCTAssertTrue(reset.replacementIndices.isEmpty)
    XCTAssertEqual(reset.appendFromIndex, 0)
    XCTAssertEqual(richChanged.replacementIndices, [0])
    XCTAssertFalse(assistantAppended.reset)
    XCTAssertEqual(assistantAppended.replacementIndices, [1])
    XCTAssertEqual(assistantAppended.appendFromIndex, 2)
  }

  func testCompletedAgentStreamWithIdenticalVisibleContentDoesNotRebind() {
    let stream = transcriptEntry(
      "stream-1",
      role: .assistant,
      timestampMillis: 10,
      text: "Complete",
      dedupeKey: "assistant-final:turn:turn-1"
    )
    let final = transcriptEntry(
      "persisted-1",
      role: .assistant,
      timestampMillis: 20,
      text: "Complete",
      dedupeKey: "assistant-final:turn:turn-1"
    )
    let identity = AgentTranscriptRenderPolicy.identity(stream)
    let diff = AgentTranscriptRenderPolicy.diff(
      renderedIds: [identity],
      renderedSignatures: [identity: AgentTranscriptRenderPolicy.signature(stream)],
      incoming: [final]
    )

    XCTAssertFalse(diff.reset)
    XCTAssertTrue(diff.replacementIndices.isEmpty)
    XCTAssertEqual(diff.appendFromIndex, 1)
  }

  func testAgentTaskLivenessPolicyWarnsBeforeHardTimeout() {
    let policy = agentLivenessPolicy()
    let workspace = agentWorkspace(
      status: .running,
      events: [agentWorkspaceEvent(1, AgentTaskEventKinds.running, 1_000)]
    )

    XCTAssertEqual(policy.evaluate(workspace: workspace, nowMillis: 1_099).state, .healthy)

    let stalled = policy.evaluate(workspace: workspace, nowMillis: 1_100)
    XCTAssertEqual(stalled.state, .stalled)
    XCTAssertEqual(stalled.reason, "running_progress_stalled")
    XCTAssertEqual(stalled.idleMillis, 100)

    let timedOut = policy.evaluate(workspace: workspace, nowMillis: 1_200)
    XCTAssertEqual(timedOut.state, .timedOut)
    XCTAssertEqual(timedOut.reason, "running_progress_timeout")
    XCTAssertEqual(timedOut.lifetimeMillis, 200)
  }

  func testAgentTaskLivenessPolicyClearsUnresolvedWarningAfterProgress() {
    let policy = agentLivenessPolicy()
    let stalled = agentWorkspace(
      status: .running,
      events: [
        agentWorkspaceEvent(1, AgentTaskEventKinds.running, 1_000),
        agentWorkspaceEvent(2, AgentTaskEventKinds.stalled, 1_100)
      ]
    )
    let recovered = agentWorkspace(
      status: .running,
      events: stalled.eventJournal + [agentWorkspaceEvent(3, AgentTaskEventKinds.progress, 1_110)]
    )

    XCTAssertTrue(policy.hasUnresolvedStall(workspace: stalled))
    XCTAssertFalse(policy.hasUnresolvedStall(workspace: recovered))
    XCTAssertEqual(policy.evaluate(workspace: recovered, nowMillis: 1_150).state, .healthy)
    XCTAssertEqual(policy.meaningfulActivityAt(recovered), 1_110)
  }

  func testAgentTaskLivenessPolicyIgnoresUserControlledAndCancelledTasks() {
    let policy = agentLivenessPolicy()

    for status in [AgentWorkspaceStatus.waitingConfirmation, .paused, .blocked] {
      XCTAssertEqual(
        policy.evaluate(workspace: agentWorkspace(status: status), nowMillis: 10_000).state,
        .healthy,
        status.rawValue
      )
    }
    XCTAssertEqual(
      policy.evaluate(workspace: agentWorkspace(status: .running, cancellationRequested: true), nowMillis: 10_000).state,
      .healthy
    )
    XCTAssertEqual(
      policy.evaluate(workspace: agentWorkspace(status: .completed), nowMillis: 10_000).state,
      .healthy
    )
  }

  func testAgentTaskLivenessPolicyAppliesAbsoluteDeadlineAndVolatileActivity() {
    let policy = agentLivenessPolicy()
    let workspace = agentWorkspace(
      status: .running,
      events: [agentWorkspaceEvent(1, AgentTaskEventKinds.progress, 1_950)]
    )
    let active = agentWorkspace(
      status: .running,
      events: [agentWorkspaceEvent(1, AgentTaskEventKinds.running, 1_000)]
    )
    let longRunning = agentWorkspace(
      status: .running,
      events: [agentWorkspaceEvent(1, AgentTaskEventKinds.progress, 12 * 60 * 60_000 - 1_000)]
    )

    let decision = policy.evaluate(workspace: workspace, nowMillis: 2_000)
    let volatile = policy.evaluate(
      workspace: active,
      nowMillis: 1_150,
      volatileActivityAtMillis: 1_090
    )
    let defaultDecision = AgentTaskLivenessPolicy().evaluate(
      workspace: longRunning,
      nowMillis: 12 * 60 * 60_000
    )

    XCTAssertEqual(decision.state, .timedOut)
    XCTAssertEqual(decision.reason, "absolute_deadline_exceeded")
    XCTAssertEqual(volatile.state, .healthy)
    XCTAssertEqual(volatile.idleMillis, 60)
    XCTAssertEqual(defaultDecision.state, .healthy)
    XCTAssertGreaterThan(defaultDecision.lifetimeMillis, 2 * 60 * 60_000)
  }

  func testAgentTaskTerminalReplyPolicyMatchesAndroidDedupePrefixes() {
    let entries = [
      terminalReplyTranscript(role: .user, dedupeKey: "", turnId: "turn"),
      terminalReplyTranscript(role: .process, dedupeKey: "task-watchdog:turn", turnId: "turn"),
      terminalReplyTranscript(role: .assistant, dedupeKey: "result:plan:action:hash", turnId: "turn"),
      terminalReplyTranscript(
        role: .assistant,
        dedupeKey: "assistant-final:turn:other-turn",
        turnId: "other-turn",
        taskId: "turn"
      )
    ]
    let nonTerminal = [
      terminalReplyTranscript(role: .assistant, dedupeKey: "approval:plan:action", turnId: "turn"),
      terminalReplyTranscript(role: .assistant, dedupeKey: "task-watchdog-timeout:turn", turnId: "turn")
    ]

    XCTAssertTrue(AgentTaskTerminalReplyPolicy.hasTerminalReply(entries: entries, turnId: "turn"))
    XCTAssertTrue(AgentTaskTerminalReplyPolicy.hasTerminalReply(entries: entries, turnId: "other-turn"))
    XCTAssertFalse(AgentTaskTerminalReplyPolicy.hasTerminalReply(entries: entries, turnId: "unrelated-turn"))
    XCTAssertFalse(AgentTaskTerminalReplyPolicy.hasTerminalReply(entries: nonTerminal, turnId: "turn"))
    XCTAssertFalse(AgentTaskTerminalReplyPolicy.hasTerminalReply(entries: entries, turnId: " "))
  }

  func testAgentWorkspaceLivenessModelsUseAndroidWireNames() throws {
    let decoded = try JSONDecoder().decode(
      AgentWorkspace.self,
      from: Data(
        #"""
        {
          "workspace_id": "workspace",
          "session_id": "session",
          "conversation_id": "conversation",
          "task_id": "task",
          "goal": "Run task",
          "status": "WAITING_RESPONSE",
          "event_sequence": 2,
          "event_journal": [
            {
              "sequence": 2,
              "kind": "task.progress",
              "message": "still running",
              "payload_json": "{\"step\":1}",
              "timestamp_millis": 1234
            }
          ],
          "cancellation_requested": true,
          "created_at_millis": 1000,
          "updated_at_millis": 1234,
          "revision": 5
        }
        """#.utf8
      )
    )
    let fallback = try JSONDecoder().decode(
      AgentWorkspace.self,
      from: Data(#"{"workspace_id":"w","session_id":"s","conversation_id":"c","task_id":"t","status":"FUTURE"}"#.utf8)
    )
    let encodedSignal = String(
      decoding: try JSONEncoder().encode(
        AgentTaskLivenessSignal(
          kind: .timedOut,
          workspace: decoded,
          reason: "running_progress_timeout",
          observedAtMillis: 2_000
        )
      ),
      as: UTF8.self
    )
    let encodedPolicy = String(decoding: try JSONEncoder().encode(AgentTaskLivenessPolicy()), as: UTF8.self)

    XCTAssertEqual(decoded.status, .waitingResponse)
    XCTAssertEqual(decoded.key, AgentWorkspaceKey(workspaceId: "workspace", sessionId: "session", conversationId: "conversation", taskId: "task"))
    XCTAssertEqual(decoded.eventJournal.first?.payloadJson, #"{"step":1}"#)
    XCTAssertTrue(decoded.cancellationRequested)
    XCTAssertEqual(fallback.status, .created)
    XCTAssertTrue(AgentWorkspaceStatus.completed.isTerminal)
    XCTAssertFalse(AgentWorkspaceStatus.running.isTerminal)
    XCTAssertTrue(encodedSignal.contains(#""observed_at_millis":2000"#))
    XCTAssertTrue(encodedSignal.contains(#""event_journal":["#))
    XCTAssertTrue(encodedPolicy.contains(#""queued_warning_millis":15000"#))
    XCTAssertTrue(encodedPolicy.contains(#""heartbeat_write_throttle_millis":2000"#))
  }

}
