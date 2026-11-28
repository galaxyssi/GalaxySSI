import XCTest
@testable import GalaxySSI

@MainActor
final class AgentUnplannedNativeDispatchTests: XCTestCase {
  private let screen = AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Synthetic")
  private func fixture() -> (AgentTaskRecord, AgentAction, ChatMessage) {
    let outgoing = ChatMessage(contactId: "hermes", content: "Synthetic native request", isMine: true,
      conversationId: "native-conversation", turnId: "native-turn")
    let action = AgentAction(id: "native-first", kind: .callNativeTool, target: "Synthetic tool", risk: .low,
      status: .pendingConfirmation, description: "Synthetic action", parameters: ["tool_id": "fixture.read", "input_json": "{}",
        "_galaxyssi_task_id": "native-turn", "_galaxyssi_session_id": "native-conversation",
        "_galaxyssi_conversation_id": "native-conversation", "_galaxyssi_turn_id": "native-turn", "_galaxyssi_contact_id": "hermes"])
    let task = AgentTaskRecord(taskId: "native-turn", sessionId: "native-conversation", goal: outgoing.content,
      phase: .executing, routeKind: .localSystem, targetTitle: "Synthetic tool", risk: .low, blocked: false)
    return (task, action, outgoing)
  }
  private func prepare(_ task: AgentTaskRecord, _ action: AgentAction, _ outgoing: ChatMessage) throws -> AgentSequentialPlanNodeDispatch.Prepared {
    let plan = try XCTUnwrap(AgentUnplannedNativeDispatch.plan(task: task, action: action, outgoing: outgoing, screen: screen))
    return try XCTUnwrap(AgentSequentialPlanNodeDispatch.prepare(plan: plan, action: action, screen: screen,
      sessionId: task.sessionId, conversationId: outgoing.conversationId, turnId: outgoing.turnId))
  }
  private func withStorage(_ body: (GalaxySSIStore, EncryptedAgentPlanNodeJournal, UserDefaults, InMemorySecretStore) throws -> Void) throws {
    let suite = "UnplannedNative.\(UUID())", secrets = InMemorySecretStore()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(GalaxySSIStore(defaults: defaults, secrets: secrets),
      EncryptedAgentPlanNodeJournal(defaults: defaults, secrets: secrets, storageKey: "unplanned-fixture"), defaults, secrets)
  }
  func testEnvelopeRetainsExactChosenAndRemainingActionsWithoutReplanning() throws {
    var (task, action, outgoing) = fixture()
    var next = action; next.id = "native-second"; next.parameters["input_json"] = #"{"synthetic":2}"#
    task.pendingActions = [next]; task.pendingAction = next
    let plan = try XCTUnwrap(AgentUnplannedNativeDispatch.plan(task: task, action: action, outgoing: outgoing, screen: screen))
    XCTAssertEqual(plan.actions, [action, next]); XCTAssertTrue(plan.confirmationRequired)
    XCTAssertEqual(plan.revision, 1); XCTAssertTrue(plan.checkpoints.isEmpty)
    XCTAssertEqual(plan.executionMode, .autoComplete)
    XCTAssertEqual(plan.plannerProfile, "legacy-native-dispatch")
    XCTAssertFalse(AgentRollingPlanPolicy.shouldRequestNextBatch(plan: plan,
      result: AgentActionResult(actionId: action.id, success: true, message: "Synthetic result")))
    XCTAssertNil(task.activePlan)
    let prepared = try prepare(task, action, outgoing)
    XCTAssertEqual(prepared.action.parameters, action.parameters)
    XCTAssertEqual(prepared.plan.actions[1], next)
    XCTAssertEqual(prepared.plan.actions.first?.status, .running)
  }
  func testExistingPlanIdentityAndModeAreNeverReplaced() throws {
    var (task, action, outgoing) = fixture()
    task.activePlan = AgentPlan(goal: task.goal, screen: screen, steps: [], actions: [action], executionMode: .autoComplete,
      planId: "existing-plan", revision: 4)
    XCTAssertEqual(AgentUnplannedNativeDispatch.plan(task: task, action: action, outgoing: outgoing, screen: screen), task.activePlan)
    task.activePlan?.executionMode = .planOnly
    XCTAssertNil(AgentUnplannedNativeDispatch.plan(task: task, action: action, outgoing: outgoing, screen: screen))
    task.planContext = task.activePlan.map(AgentTaskPlanContext.init)
    task.activePlan = nil
    XCTAssertNil(AgentUnplannedNativeDispatch.plan(task: task, action: action, outgoing: outgoing, screen: screen))
  }
  func testMalformedOwnershipAndInactiveTasksCannotAcquireAnEnvelope() {
    let (original, action, outgoing) = fixture()
    for key in ["_galaxyssi_task_id", "_galaxyssi_session_id", "_galaxyssi_conversation_id", "_galaxyssi_turn_id", "_galaxyssi_contact_id"] {
      var foreign = action; foreign.parameters[key] = "other"
      XCTAssertNil(AgentUnplannedNativeDispatch.plan(task: original, action: foreign, outgoing: outgoing, screen: screen), key)
    }
    for phase in [AgentPhase.cancelled, .paused, .failed, .blocked, .waitingResponse, .completed] {
      var task = original; task.phase = phase
      XCTAssertNil(AgentUnplannedNativeDispatch.plan(task: task, action: action, outgoing: outgoing, screen: screen))
    }
    var task = original; task.blocked = true
    XCTAssertNil(AgentUnplannedNativeDispatch.plan(task: task, action: action, outgoing: outgoing, screen: screen))
    task = original; task.taskId = "other"
    XCTAssertNil(AgentUnplannedNativeDispatch.plan(task: task, action: action, outgoing: outgoing, screen: screen))
    task = original; task.sessionId = "other"
    XCTAssertNil(AgentUnplannedNativeDispatch.plan(task: task, action: action, outgoing: outgoing, screen: screen))
  }
  func testDuplicateForeignOrPreviouslyDispatchedActionsAreNotReauthorized() {
    let (original, action, outgoing) = fixture()
    var task = original; task.pendingActions = [action]
    XCTAssertNil(AgentUnplannedNativeDispatch.plan(task: task, action: action, outgoing: outgoing, screen: screen))
    var next = action; next.id = "next"
    task.pendingActions = [next, next]
    XCTAssertNil(AgentUnplannedNativeDispatch.plan(task: task, action: action, outgoing: outgoing, screen: screen))
    next.parameters[AgentPlanContinuationScope.turnIdKey] = "other"
    task.pendingActions = [next]
    XCTAssertNil(AgentUnplannedNativeDispatch.plan(task: task, action: action, outgoing: outgoing, screen: screen))
    for status in [AgentActionStatus.running, .waitingResponse, .completed, .failed, .blocked, .rolledBack] {
      var previouslyDispatched = action; previouslyDispatched.status = status
      XCTAssertNil(AgentUnplannedNativeDispatch.plan(task: original, action: previouslyDispatched, outgoing: outgoing, screen: screen))
    }
  }
  func testTaskAndDispatchAreSavedBeforeTheSyntheticOperationAndReplayOnce() throws {
    try withStorage { store, journal, defaults, secrets in
      let (task, action, outgoing) = fixture(), prepared = try prepare(task, action, outgoing)
      _ = store.upsertAgentTask(task)
      var updated = task; updated.activePlan = prepared.plan; updated.planContext = AgentTaskPlanContext(plan: prepared.plan)
      XCTAssertTrue(store.commitOwnedAgentTaskState(expected: task, updated: updated))
      var calls = 0
      let result = AgentSequentialPlanNodeDispatch.execute(prepared, journal: journal) {
        calls += 1
        XCTAssertEqual(GalaxySSIStore(defaults: defaults, secrets: secrets).agentTask(id: task.taskId)?.activePlan, prepared.plan)
        let dispatch = try? journal.readDispatch(prepared.key)
        XCTAssertEqual(dispatch?.action.parameters, action.parameters)
        XCTAssertEqual(dispatch?.audits.map(\.event), [.checkpointSaved, .toolStarted])
        return AgentActionResult(actionId: action.id, success: true, message: "Synthetic observation")
      }
      let reopened = EncryptedAgentPlanNodeJournal(defaults: defaults, secrets: secrets, storageKey: "unplanned-fixture")
      XCTAssertEqual(AgentSequentialPlanNodeDispatch.execute(prepared, journal: reopened) {
        calls += 1; return AgentActionResult(actionId: action.id, success: false, message: "Unexpected replay")
      }, result)
      XCTAssertEqual(calls, 1)
    }
  }
  func testPendingOriginalClaimCannotBeRedispatchedAfterRestore() throws {
    try withStorage { _, journal, defaults, secrets in
      let (task, action, outgoing) = fixture(), prepared = try prepare(task, action, outgoing)
      XCTAssertEqual(try journal.claim(prepared.key, action: prepared.action, checkpoint: prepared.checkpoint), .acquired)
      let restored = EncryptedAgentPlanNodeJournal(defaults: defaults, secrets: secrets, storageKey: "unplanned-fixture")
      var calls = 0
      let result = AgentSequentialPlanNodeDispatch.execute(prepared, journal: restored) {
        calls += 1; return AgentActionResult(actionId: action.id, success: true, message: "Unexpected repeat")
      }
      XCTAssertEqual(calls, 0); XCTAssertFalse(result.success)
      XCTAssertEqual(result.metadata["plan_node_outcome_unknown"], "true")
    }
  }
  func testCancelledStoreStateRejectsThePreparedEnvelopeBeforeDispatch() throws {
    try withStorage { store, journal, _, _ in
      let (task, action, outgoing) = fixture(), prepared = try prepare(task, action, outgoing)
      _ = store.upsertAgentTask(task)
      var cancelled = task; cancelled.phase = .cancelled
      _ = store.upsertAgentTask(cancelled)
      var updated = task; updated.activePlan = prepared.plan
      XCTAssertFalse(store.commitOwnedAgentTaskState(expected: task, updated: updated))
      XCTAssertNil(try journal.observe(prepared.key))
    }
  }
  func testNextActionRetainsTheOriginalEnvelopeAndIndependentNodeIdentity() throws {
    var (task, action, outgoing) = fixture()
    var next = action; next.id = "native-second"
    task.pendingActions = [next]
    let first = try prepare(task, action, outgoing)
    task.activePlan = first.plan; task.activePlan?.actions[0].status = .completed
    task.planContext = task.activePlan.map(AgentTaskPlanContext.init)
    task.pendingActions = []
    let second = try prepare(task, next, outgoing)
    XCTAssertEqual(first.plan.planId, second.plan.planId)
    XCTAssertEqual(first.key.turnId, second.key.turnId)
    XCTAssertNotEqual(first.key, second.key)
    XCTAssertEqual(second.plan.actions[0].status, .completed)
  }
}
