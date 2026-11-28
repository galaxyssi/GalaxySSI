import XCTest
@testable import GalaxySSI

@MainActor
final class AgentApprovedCaptureDispatchTests: XCTestCase {
  private struct Fixture {
    let task: AgentTaskRecord
    let outgoing: ChatMessage
    let wait: AgentCapturePermissionContinuation
    let execution: AgentAction
    let screen = AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")
    func prepared() throws -> AgentApprovedCaptureDispatch.Prepared {
      try XCTUnwrap(AgentApprovedCaptureDispatch.prepare(wait: wait, task: task, outgoing: outgoing,
        executionAction: execution, screen: screen, nowMillis: 100))
    }
  }
  private func fixture(_ kind: AgentIOSVisibleCaptureKind = .photo) -> Fixture {
    let outgoing = ChatMessage(contactId: "hermes", content: "Synthetic visible capture", isMine: true,
      conversationId: "conversation", turnId: "capture-turn")
    let action = AgentAction(id: "capture-action", kind: .callNativeTool, target: "Visible capture", risk: .medium,
      status: .pendingConfirmation, description: "Capture", parameters: [
        "tool_id": kind == .photo ? AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture : AgentIOSVisibleCaptureNativeToolCatalog.microphoneRecord,
        "input_json": kind == .photo ? #"{"facing":"back"}"# : #"{"max_duration_seconds":5}"#])
    var task = AgentTaskRecord(taskId: "capture-turn", sessionId: "conversation", goal: outgoing.content,
      phase: .waitingResponse, routeKind: .localSystem, targetTitle: "Visible capture", risk: .medium, blocked: false)
    task.activePlan = AgentPlan(goal: task.goal, screen: .init(foregroundApp: "GalaxySSI"), steps: [], actions: [action], route: AgentRoute())
    task.pendingAction = action; task.pendingActions = [action]
    let wait = AgentCapturePermissionContinuation(task: task, outgoing: outgoing, action: action,
      kind: kind, permissionMode: .askBeforeAction)
    task.capturePermission = wait
    var execution = action
    execution.parameters.merge(["_galaxyssi_capture_permission_preflight": "true", "_galaxyssi_task_id": task.taskId,
      "_galaxyssi_session_id": task.sessionId, "_galaxyssi_conversation_id": outgoing.conversationId,
      "_galaxyssi_turn_id": outgoing.turnId, "_galaxyssi_contact_id": outgoing.contactId]) { _, value in value }
    return Fixture(task: task, outgoing: outgoing, wait: wait, execution: execution)
  }
  private func withStorage(_ body: (GalaxySSIStore, EncryptedAgentPlanNodeJournal, UserDefaults, InMemorySecretStore) throws -> Void) throws {
    let suite = "ApprovedCapture.\(UUID())", secrets = InMemorySecretStore()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(GalaxySSIStore(defaults: defaults, secrets: secrets),
      EncryptedAgentPlanNodeJournal(defaults: defaults, secrets: secrets, storageKey: "capture-fixture"), defaults, secrets)
  }
  private func legacySequence(_ kind: AgentIOSVisibleCaptureKind, remaining: [AgentAction]) throws -> Fixture {
    let original = fixture(kind)
    var task = original.task; task.activePlan = nil
    let action = try XCTUnwrap(task.pendingAction)
    task.pendingActions = [action] + remaining
    let wait = AgentCapturePermissionContinuation(task: task, outgoing: original.outgoing, action: action,
      kind: kind, permissionMode: original.wait.permissionMode)
    task.capturePermission = wait
    return Fixture(task: task, outgoing: original.outgoing, wait: wait, execution: original.execution)
  }
  func testLegacyCapturePreservesTheWholeQueueWithoutApprovingLaterActions() throws {
    for kind in AgentIOSVisibleCaptureKind.allCases {
      var next = try XCTUnwrap(fixture(.audio).task.pendingAction)
      next.id = "second-capture"; next.requiresConfirmation = true
      var connector = next; connector.id = "later-connector"; connector.kind = .callConnector
      connector.parameters = ["connector_id": "synthetic", "prompt": "Synthetic follow-up"]
      let fixture = try legacySequence(kind, remaining: [next, connector]), prepared = try fixture.prepared()
      XCTAssertEqual(prepared.task.pendingActions, fixture.task.pendingActions)
      XCTAssertEqual(prepared.task.activePlan?.actions.dropFirst().map { $0 }, [next, connector])
      XCTAssertEqual(prepared.task.activePlan?.actions.first?.id, fixture.wait.actionId)
      XCTAssertEqual(prepared.task.activePlan?.actions.first?.status, .running)
      XCTAssertTrue(prepared.task.activePlan?.confirmationRequired == true)
      XCTAssertEqual(prepared.task.activePlan?.plannerProfile, "legacy-capture-dispatch")
      XCTAssertEqual(prepared.task.capturePermission?.token, fixture.wait.token)
      XCTAssertTrue(prepared.task.capturePermission?.dispatched == true)
      XCTAssertFalse(AgentRollingPlanPolicy.shouldRequestNextBatch(plan: prepared.task.activePlan,
        result: AgentActionResult(actionId: fixture.wait.actionId, success: true, message: "Synthetic")))
    }
  }
  func testLegacyCaptureQueueIsDurableBeforeTheFirstSyntheticCapture() throws {
    try withStorage { store, journal, defaults, secrets in
      var next = try XCTUnwrap(fixture(.audio).task.pendingAction); next.id = "second-capture"
      let fixture = try legacySequence(.photo, remaining: [next]), prepared = try fixture.prepared()
      _ = store.upsertAgentTask(fixture.task)
      XCTAssertTrue(store.commitOwnedAgentTaskState(expected: fixture.task, updated: prepared.task))
      let result = AgentSequentialPlanNodeDispatch.execute(prepared.node, journal: journal) {
        let restored = GalaxySSIStore(defaults: defaults, secrets: secrets).agentTask(id: fixture.task.taskId)
        XCTAssertEqual(restored?.pendingActions, fixture.task.pendingActions)
        XCTAssertEqual(restored?.activePlan, prepared.task.activePlan)
        XCTAssertEqual(restored?.activePlan?.actions.last, next)
        return AgentActionResult(actionId: fixture.wait.actionId, success: true, message: "Synthetic first capture")
      }
      XCTAssertTrue(result.success)
      XCTAssertEqual(try journal.read(prepared.node.key)?.result, result)
    }
  }
  func testSecondCaptureUsesTheSamePlanButANewPermissionAndNode() throws {
    var next = try XCTUnwrap(fixture(.audio).task.pendingAction); next.id = "second-capture"
    let fixture = try legacySequence(.photo, remaining: [next]), first = try fixture.prepared()
    var task = first.task
    task.activePlan?.actions[0].status = .completed
    task.pendingActions.removeFirst(); task.pendingAction = next
    task.phase = .waitingResponse
    let wait = AgentCapturePermissionContinuation(task: task, outgoing: fixture.outgoing, action: next,
      kind: .audio, permissionMode: fixture.wait.permissionMode)
    task.capturePermission = wait
    var execution = fixture.execution
    execution.id = next.id; execution.parameters["tool_id"] = next.parameters["tool_id"]
    execution.parameters["input_json"] = next.parameters["input_json"]
    let second = try XCTUnwrap(AgentApprovedCaptureDispatch.prepare(wait: wait, task: task, outgoing: fixture.outgoing,
      executionAction: execution, screen: fixture.screen, nowMillis: 200))
    XCTAssertEqual(second.node.plan.planId, first.node.plan.planId)
    XCTAssertEqual(second.node.plan.revision, first.node.plan.revision)
    XCTAssertEqual(second.node.plan.actions[0].status, .completed)
    XCTAssertNotEqual(second.node.key, first.node.key)
    XCTAssertNotEqual(wait.token, fixture.wait.token)
    XCTAssertEqual(second.task.capturePermission?.token, wait.token)
    XCTAssertNil(first.task.capturePermission?.action(in: task, outgoing: fixture.outgoing))
  }
  func testLegacyQueueCannotInventProofForMissingPlansOrForeignActions() throws {
    var next = try XCTUnwrap(fixture(.audio).task.pendingAction); next.id = "second-capture"
    let fixture = try legacySequence(.photo, remaining: [next])
    for variation in 0..<8 {
      var task = fixture.task
      if variation == 0 { task.pendingActions.append(next) }
      if variation == 1 { task.pendingActions[1].id = fixture.wait.actionId }
      if variation == 2 { task.pendingActions[1].parameters[AgentPlanContinuationScope.turnIdKey] = "foreign" }
      if variation == 3 { task.pendingActions[1].parameters[AgentPlanContinuationScope.conversationIdKey] = "foreign" }
      if variation == 4 { task.pendingActions[1].status = .running }
      if variation == 5 { task.pendingActions[1].status = .completed }
      if variation == 6 { task.blocked = true }
      if variation == 7 {
        task.planContext = AgentTaskPlanContext(plan: AgentPlan(goal: task.goal, screen: fixture.screen, steps: [], actions: task.pendingActions))
      }
      XCTAssertNil(AgentApprovedCaptureDispatch.prepare(wait: fixture.wait, task: task, outgoing: fixture.outgoing,
        executionAction: fixture.execution, screen: fixture.screen, nowMillis: 100), "variation \(variation)")
    }
  }
  func testBothCaptureKindsStageFinalInputAndRetainTheOriginalPermissionIdentity() throws {
    for kind in AgentIOSVisibleCaptureKind.allCases {
      let fixture = fixture(kind), prepared = try fixture.prepared()
      XCTAssertEqual(prepared.task.phase, .executing)
      let dispatched = try XCTUnwrap(prepared.task.capturePermission)
      XCTAssertTrue(dispatched.dispatched); XCTAssertEqual(dispatched.token, fixture.wait.token)
      XCTAssertEqual(dispatched.action(in: prepared.task, outgoing: fixture.outgoing), fixture.task.pendingAction)
      XCTAssertFalse(dispatched.acceptsCallback(in: prepared.task, outgoing: fixture.outgoing))
      XCTAssertEqual(prepared.node.action.parameters, fixture.execution.parameters)
      XCTAssertEqual(prepared.node.plan.actions.first?.status, .running)
      XCTAssertEqual(prepared.task.activePlan, prepared.node.plan)
      XCTAssertEqual(prepared.node.checkpoint.planRevision, fixture.task.activePlan?.revision)
      XCTAssertFalse(fixture.task.capturePermission?.dispatched == true)
    }
    let original = fixture()
    var legacy = original.task; legacy.activePlan = nil
    let approved = try XCTUnwrap(legacy.pendingAction)
    let legacyWait = AgentCapturePermissionContinuation(task: legacy, outgoing: original.outgoing,
      action: approved, kind: .photo, permissionMode: .askBeforeAction)
    legacy.capturePermission = legacyWait
    let prepared = try XCTUnwrap(AgentApprovedCaptureDispatch.prepare(wait: legacyWait, task: legacy,
      outgoing: original.outgoing, executionAction: original.execution, screen: original.screen, nowMillis: 100))
    XCTAssertEqual(prepared.task.activePlan?.actions.count, 1)
    XCTAssertEqual(prepared.task.capturePermission?.token, legacyWait.token)
    XCTAssertEqual(prepared.task.capturePermission?.action(in: prepared.task, outgoing: original.outgoing), approved)
  }
  func testOwnedTaskAndDispatchIntentAreDurableBeforeSyntheticCaptureStarts() throws {
    try withStorage { store, journal, defaults, secrets in
      let fixture = fixture(), prepared = try fixture.prepared()
      _ = store.upsertAgentTask(fixture.task)
      XCTAssertNil(try journal.observe(prepared.node.key))
      XCTAssertTrue(store.commitOwnedAgentTaskState(expected: fixture.task, updated: prepared.task))
      let result = AgentSequentialPlanNodeDispatch.execute(prepared.node, journal: journal) {
        let reloaded = GalaxySSIStore(defaults: defaults, secrets: secrets)
        XCTAssertEqual(reloaded.agentTask(id: fixture.task.taskId)?.capturePermission, prepared.task.capturePermission)
        XCTAssertEqual(reloaded.agentTask(id: fixture.task.taskId)?.activePlan, prepared.node.plan)
        let saved = try? journal.readDispatch(prepared.node.key)
        XCTAssertEqual(saved?.action.parameters, fixture.execution.parameters)
        XCTAssertEqual(saved?.audits.map(\.event), [.checkpointSaved, .toolStarted])
        return AgentActionResult(actionId: fixture.execution.id, success: true, message: "Synthetic receipt")
      }
      XCTAssertTrue(result.success)
      XCTAssertEqual(try journal.read(prepared.node.key)?.result, result)
    }
  }
  func testCancelledOrStaleTaskCannotCommitThePreparedCaptureIntent() throws {
    try withStorage { store, journal, _, _ in
      let fixture = fixture(), prepared = try fixture.prepared()
      _ = store.upsertAgentTask(fixture.task)
      var cancelled = fixture.task; cancelled.phase = .cancelled
      _ = store.upsertAgentTask(cancelled)
      XCTAssertFalse(store.commitOwnedAgentTaskState(expected: fixture.task, updated: prepared.task))
      XCTAssertEqual(store.agentTask(id: fixture.task.taskId)?.phase, .cancelled)
      XCTAssertNil(try journal.observe(prepared.node.key))
    }
  }
  func testChangedInputOrScopeCannotUseTheOriginalPermission() {
    let fixture = fixture()
    for key in ["input_json", "tool_id", "_galaxyssi_task_id", "_galaxyssi_session_id", "_galaxyssi_conversation_id",
      "_galaxyssi_turn_id", "_galaxyssi_contact_id", "_galaxyssi_capture_permission_preflight"] {
      var action = fixture.execution; action.parameters[key] = "changed"
      XCTAssertNil(AgentApprovedCaptureDispatch.prepare(wait: fixture.wait, task: fixture.task, outgoing: fixture.outgoing,
        executionAction: action, screen: fixture.screen, nowMillis: 100), key)
    }
    var foreign = fixture.outgoing; foreign.id = UUID()
    XCTAssertNil(AgentApprovedCaptureDispatch.prepare(wait: fixture.wait, task: fixture.task, outgoing: foreign,
      executionAction: fixture.execution, screen: fixture.screen, nowMillis: 100))
  }
  func testPausedPlanOnlyDuplicateAndRevisedPlansCannotStartACapture() {
    let fixture = fixture()
    for variation in 0..<5 {
      var task = fixture.task
      if variation == 0 { task.phase = .paused }
      if variation == 1 { task.activePlan?.executionMode = .planOnly }
      if variation == 2 { task.activePlan?.revision += 1 }
      if variation == 3, let action = task.activePlan?.actions.first { task.activePlan?.actions.append(action) }
      if variation == 4 { task.capturePermission?.dispatched = true }
      XCTAssertNil(AgentApprovedCaptureDispatch.prepare(wait: fixture.wait, task: task, outgoing: fixture.outgoing,
        executionAction: fixture.execution, screen: fixture.screen, nowMillis: 100))
    }
  }
  func testInterruptedClaimSurvivesReloadWithoutRepeatingTheCameraOrMicrophone() throws {
    try withStorage { store, journal, defaults, secrets in
      let fixture = fixture(.audio), prepared = try fixture.prepared()
      _ = store.upsertAgentTask(fixture.task)
      XCTAssertTrue(store.commitOwnedAgentTaskState(expected: fixture.task, updated: prepared.task))
      XCTAssertEqual(try journal.claim(prepared.node.key, action: prepared.node.action, checkpoint: prepared.node.checkpoint), .acquired)
      let restored = try XCTUnwrap(GalaxySSIStore(defaults: defaults, secrets: secrets).agentTask(id: fixture.task.taskId))
      XCTAssertFalse(restored.capturePermission?.acceptsCallback(in: restored, outgoing: fixture.outgoing) == true)
      let reopened = EncryptedAgentPlanNodeJournal(defaults: defaults, secrets: secrets, storageKey: "capture-fixture")
      let result = AgentSequentialPlanNodeDispatch.execute(prepared.node, journal: reopened) {
        XCTFail("Unknown capture must not repeat")
        return AgentActionResult(actionId: fixture.execution.id, success: true, message: "Invalid repeat")
      }
      XCTAssertFalse(result.success); XCTAssertEqual(result.metadata["plan_node_outcome_unknown"], "true")
      XCTAssertEqual(result.metadata["non_retriable"], "true")
    }
  }
  func testSavedObservationReplaysWithoutStartingAnotherCapture() throws {
    try withStorage { _, journal, defaults, secrets in
      let fixture = fixture(), prepared = try fixture.prepared()
      var calls = 0
      let first = AgentSequentialPlanNodeDispatch.execute(prepared.node, journal: journal) {
        calls += 1
        return AgentActionResult(actionId: fixture.execution.id, success: true, message: "Synthetic saved capture")
      }
      let reopened = EncryptedAgentPlanNodeJournal(defaults: defaults, secrets: secrets, storageKey: "capture-fixture")
      XCTAssertEqual(AgentSequentialPlanNodeDispatch.execute(prepared.node, journal: reopened) {
        calls += 1; return first
      }, first)
      XCTAssertEqual(calls, 1)
    }
  }
  func testJournalFailureNeverProducesVerifiedCaptureSuccess() throws {
    try withStorage { _, journal, defaults, _ in
      let fixture = fixture(), prepared = try fixture.prepared()
      let result = AgentSequentialPlanNodeDispatch.execute(prepared.node, journal: journal) {
        defaults.set(Data("corrupted after synthetic capture".utf8), forKey: "capture-fixture.encrypted.v1")
        return AgentActionResult(actionId: fixture.execution.id, success: true, message: "Returned before storage failure")
      }
      XCTAssertFalse(result.success); XCTAssertEqual(result.metadata["plan_node_journal_error"], "observation_commit_failed")
      XCTAssertTrue(prepared.task.capturePermission?.dispatched == true)
      let failed = AgentSequentialPlanNodeDispatch.execute(prepared.node, journal: journal) {
        XCTFail("Unreadable journal cannot start a capture")
        return result
      }
      XCTAssertEqual(failed.metadata["execution_started"], "false")
    }
  }
}
