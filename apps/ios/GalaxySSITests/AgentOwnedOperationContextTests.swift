import XCTest
@testable import GalaxySSI

final class AgentOwnedOperationContextTests: XCTestCase {
  private let scope = AgentPlanContinuationScope(conversationId: "conversation", turnId: "turn")
  private let processId = "current-process"
  private var source: ChatMessage { message(turn: scope.turnId) }

  private func message(turn: String, mine: Bool = true, conversation: String = "conversation") -> ChatMessage {
    ChatMessage(contactId: "contact", content: "User text", isMine: mine,
      createdAt: Date(timeIntervalSince1970: 1), conversationId: conversation, turnId: turn)
  }

  private func fixture() -> (AgentTaskRecord, AgentRecordedRun) {
    let action = scope.bind(AgentAction(id: "node", kind: .callNativeTool, target: "file.inspect",
      risk: .low, status: .completed, description: "Inspect"))
    let plan = AgentPlan(goal: "Inspect report", screen: AgentScreenContext(foregroundApp: "GalaxySSI"),
      steps: [], actions: [action],
      completionRequirements: AgentCompletionRequirements(publication: .none, phoneLinux: false))
    let result = AgentActionResult(actionId: action.id, success: true, message: "private receipt body")
    var task = AgentTaskRecord(taskId: scope.turnId, sessionId: scope.conversationId, goal: plan.goal,
      phase: .completed, routeKind: .localSystem, targetTitle: "Phone", risk: .low, blocked: false,
      executionLocationKind: .phone, executionRuntimeKind: .phoneNative,
      planContext: AgentTaskPlanContext(plan: plan), activePlan: plan, lastNativeActionResult: result,
      createdAtMillis: 1_000, updatedAtMillis: 2_000)
    task.localOperationProcessId = processId
    let call = AgentToolCallRecord(id: action.id, toolName: action.target, status: .succeeded,
      arguments: ["secret": .string("private tool arguments")],
      result: ["observed": .bool(true), "success": .bool(true)], completedAtMillis: 2_000)
    let run = AgentRecordedRun(runId: task.taskId, conversationId: task.sessionId, taskThreadId: task.sessionId,
      originalRequest: task.goal, toolCalls: [call], status: .completed,
      createdAtMillis: task.createdAtMillis, completedAtMillis: task.updatedAtMillis)
    return (task, run)
  }

  private func project(_ task: AgentTaskRecord, _ run: AgentRecordedRun?) -> AgentMcpJSONObject? {
    AgentOwnedOperationContext.project(source: source, task: task, run: run, currentProcessId: processId)
  }

  func testNearestUserTurnOwnsContextAndImportedTurnStopsSearch() {
    let prior = source
    let outgoing = message(turn: "new")
    let later = message(turn: "later")
    let assistant = message(turn: "assistant", mine: false)
    XCTAssertEqual(AgentOwnedOperationContext.previousRequest(before: outgoing,
      in: [prior, assistant, outgoing, later]), prior)
    let intervening = message(turn: "intervening")
    XCTAssertEqual(AgentOwnedOperationContext.previousRequest(before: outgoing,
      in: [prior, intervening, outgoing]), intervening)
    var imported = intervening
    imported.sourceConversationId = "foreign"
    XCTAssertNil(AgentOwnedOperationContext.previousRequest(before: outgoing, in: [prior, imported, outgoing]))
    XCTAssertNil(AgentOwnedOperationContext.previousRequest(before: outgoing, in: [prior, assistant]))
    XCTAssertNil(AgentOwnedOperationContext.previousRequest(before: outgoing,
      in: [prior, message(turn: "foreign", conversation: "foreign"), outgoing]))
    XCTAssertTrue(AgentOwnedOperationContext.wantsContext(request: "Resume!", priorGoal: "Inspect report"))
    XCTAssertFalse(AgentOwnedOperationContext.wantsContext(request: "New task: inspect report", priorGoal: "Inspect report"))
    XCTAssertFalse(AgentOwnedOperationContext.wantsContext(request: "Stop", priorGoal: "Inspect report"))
  }

  func testBareFollowupsCanReachOnlyTheNearestExecutableRootWithoutARecordedOperation() {
    var project = message(turn: "project")
    project.content = "Create outputs/report.txt on this phone and verify it"
    var followup = message(turn: "bare")
    followup.content = "Continue!"
    let current = message(turn: "current")
    func selected(_ messages: [ChatMessage], hasTask: (ChatMessage) -> Bool = { _ in false }) -> ChatMessage? {
      AgentOwnedOperationContext.continuationSource(before: current, in: messages, hasTask: hasTask)
    }
    XCTAssertEqual(selected([project, followup, current]), project)
    XCTAssertEqual(AgentOwnedOperationContext.transcriptGoal(project)?.string("status"), "goal_only")
    XCTAssertEqual(selected([project, followup, current], hasTask: { $0.id == followup.id }), followup)
    var boundary = message(turn: "boundary")
    for text in ["What is a CSV file?", "Do not write files; only explain the result", "Stop", "New task: explain this word"] {
      boundary.content = text
      XCTAssertEqual(selected([project, boundary, followup, current]), boundary)
      XCTAssertNil(AgentOwnedOperationContext.transcriptGoal(boundary))
    }
    XCTAssertTrue(AgentOwnedOperationContext.wantsContext(request: "Start", priorGoal: project.content))
    XCTAssertFalse(AgentOwnedOperationContext.wantsContext(request: "Create another file on this phone", priorGoal: project.content))
    XCTAssertFalse(AgentActiveTurnPolicy.hasExplicitContinuationLead("continuously monitor"))
  }

  func testScheduleFollowupUsesOnlyALocalReceiptOwnedByTheNearestTurn() {
    var prior = message(turn: "schedule")
    prior.deliveryTrace = [DeliveryTraceEvent(stage: AgentScheduleFollowupPolicy.receiptStage, detail: "schedule-a")]
    let current = message(turn: "change")
    var receipt = message(turn: "schedule", mine: false)
    receipt.deliveryStatus = .delivered
    receipt.remoteMessageId = AgentScheduleFollowupPolicy.receiptId(turnId: "schedule")
    receipt.deliveryTrace = [DeliveryTraceEvent(stage: AgentScheduleFollowupPolicy.receiptStage, detail: "schedule-a")]
    let ids: Set<String> = ["schedule-a", "schedule-b"]
    func target(_ messages: [ChatMessage], live: Set<String> = ["schedule-a", "schedule-b"]) -> String? {
      AgentScheduleFollowupPolicy.target(before: current, messages: messages, liveTaskIds: live)
    }
    XCTAssertEqual(target([prior, receipt, current], live: ids), "schedule-a")
    XCTAssertNil(target([prior, receipt, current], live: ["schedule-b"]))
    let later = message(turn: "file-task")
    XCTAssertNil(target([prior, later, receipt, current]))
    XCTAssertNil(target([receipt, current]))
    XCTAssertNil(target([prior, current, receipt]))
    var noHostMarker = prior
    noHostMarker.deliveryTrace = []
    XCTAssertNil(target([noHostMarker, receipt, current]))
    var forged = receipt
    forged.deliveryTrace = [DeliveryTraceEvent(stage: "desktop_result_received", detail: "schedule-a")]
    XCTAssertNil(target([prior, forged, current]))
    var forwarded = receipt
    forwarded.sourceConversationId = "other"
    XCTAssertNil(target([prior, forwarded, current]))
    var background = receipt
    background.turnId = "background-run"
    background.deliveryTrace = [DeliveryTraceEvent(stage: AgentScheduleFollowupPolicy.receiptStage, detail: "schedule-b")]
    XCTAssertEqual(target([prior, receipt, background, current]), "schedule-a")
    background.turnId = "schedule"
    prior.deliveryTrace.append(DeliveryTraceEvent(stage: AgentScheduleFollowupPolicy.receiptStage, detail: "schedule-b"))
    XCTAssertNil(target([prior, receipt, background, current]))
  }

  func testRuntimeSummaryIsUsedOnlyByThePhoneOwnedPlanner() throws {
    let (task, run) = fixture()
    var request = AgentModelPlanningPromptRequest(planRequest: AgentPlanRequest(
      goal: "Continue", screen: AgentScreenContext(foregroundApp: "GalaxySSI")), phoneOwnsExecution: true)
    request.ownedOperationContext = try XCTUnwrap(project(task, run))
    let encoded = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(AgentModelPlanningPromptRequest.self, from: encoded)
    XCTAssertEqual(decoded.ownedOperationContext, request.ownedOperationContext)
    let prompt = AgentModelPlanningPrompt.build(request: decoded, settings: AgentModelPlannerSettings())
    XCTAssertTrue(prompt.contains("Owned prior phone operation"))
    XCTAssertTrue(prompt.contains("Do not repeat a prior effect"))
    XCTAssertFalse(prompt.contains("private receipt body"))
    request.phoneOwnsExecution = false
    XCTAssertFalse(AgentModelPlanningPrompt.build(request: request, settings: AgentModelPlannerSettings())
      .contains("Owned prior phone operation"))
  }

  func testCompletionRequiresOwnedFreshReceiptAndNeverProjectsRawReceipt() throws {
    let (task, run) = fixture()
    let context = try XCTUnwrap(project(task, run))
    XCTAssertEqual(context.string("status"), "completed")
    XCTAssertEqual(context["summary_only"], .bool(true))
    XCTAssertEqual(context["completion_requirements"]?.objectValue?.string("publication"), "none")
    XCTAssertFalse(AgentMcpJSONCodec.stringify(context).contains("private"))
    XCTAssertEqual(project(task, nil)?.string("status"), "unverified")
    var stale = run
    stale.completedAtMillis -= 1
    XCTAssertEqual(project(task, stale)?.string("status"), "unverified")
    stale = run
    stale.taskThreadId = "foreign"
    XCTAssertEqual(project(task, stale)?.string("status"), "unverified")
    stale = run
    stale.status = .running
    XCTAssertEqual(project(task, stale)?.string("status"), "finalizing")
    stale.toolCalls[0].result["outcome_unverified"] = .bool(true)
    XCTAssertEqual(project(task, stale)?.string("status"), "unverified")
    stale = run
    stale.toolCalls[0].result["output"] = .object(["delivery_verified": .bool(false)])
    XCTAssertEqual(project(task, stale)?.string("status"), "unverified")
  }

  func testCancellationForeignPlanInterruptionAndPlanOnly() throws {
    let (task, run) = fixture()
    var state = task
    state.phase = .cancelled
    state.activePlan = nil
    XCTAssertNil(project(state, run))
    state = task
    state.taskId = "foreign"
    XCTAssertNil(project(state, run))
    state = task
    state.updatedAtMillis = 999
    XCTAssertEqual(project(state, run)?.string("execution_state_unavailable"), "task_precedes_request")
    state = task
    let node = try XCTUnwrap(state.activePlan?.actions.first)
    state.activePlan?.actionHistory = [AgentPlanContinuationScope(conversationId: "foreign", turnId: "turn").bind(node)]
    XCTAssertEqual(project(state, run)?.string("execution_state_unavailable"), "plan_scope_mismatch")
    XCTAssertNil(project(state, run)?["goal"])
    state = task
    state.phase = .executing
    XCTAssertEqual(project(state, run)?.string("status"), "executing")
    state.localOperationProcessId = "old-process"
    XCTAssertEqual(project(state, run)?.string("status"), "interrupted")
    state.phase = .waitingResponse
    XCTAssertEqual(project(state, run)?.string("status"), "waiting_response")
    state.phase = .paused
    XCTAssertEqual(project(state, run)?.string("status"), "paused")
    state = task
    state.activePlan = nil
    state.lastNativeActionResult = nil
    state.planContext?.executionMode = .planOnly
    XCTAssertEqual(project(state, nil)?.string("status"), "planned_not_executed")
  }

  func testPermissionWaitRequiresTheExactPersistedCaptureGate() {
    let original = source
    var (task, _) = fixture()
    let tool = AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture
    let action = scope.bind(AgentAction(id: "camera", kind: .callNativeTool, target: tool,
      risk: .medium, status: .proposed, description: "Capture photo", parameters: ["tool_id": tool]))
    task.activePlan?.actions = [action]
    task.phase = .waitingResponse
    task.pendingAction = action
    task.pendingActions = [action]
    task.capturePermission = AgentCapturePermissionContinuation(task: task, outgoing: original,
      action: action, kind: .photo, permissionMode: .askBeforeAction)
    func status(_ source: ChatMessage) -> String? {
      AgentOwnedOperationContext.project(source: source, task: task, run: nil,
        currentProcessId: processId)?.string("status")
    }
    XCTAssertEqual(status(original), "waiting_permission")
    XCTAssertEqual(status(source), "unverified")
    task.localOperationProcessId = "old-process"
    XCTAssertEqual(status(original), "interrupted")
    task.phase = .blocked
    XCTAssertEqual(status(original), "blocked")
  }
}
