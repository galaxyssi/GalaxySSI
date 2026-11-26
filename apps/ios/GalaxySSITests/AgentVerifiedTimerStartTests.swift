import XCTest
@testable import GalaxySSI

final class AgentVerifiedTimerStartTests: XCTestCase {
  private let screen = AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")
  private let input = #"{"target":"timer","parameters":{"timer_operation":"start","timer_seconds":60}}"#
  private let operation = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!

  func testExactTimerGoalsCloseWithRealDurationButCompoundGoalsDoNot() {
    for goal in ["1 minute", "Set a 1 minute timer", "1\u{5206}\u{949f}", "\u{8bbe}\u{7f6e}1\u{5206}\u{949f}\u{5012}\u{8ba1}\u{65f6}"] {
      XCTAssertTrue(AgentVerifiedTimerStart.permits(plan: plan(goal: goal), action: timer(), result: receipt()), goal)
    }
    XCTAssertFalse(AgentVerifiedTimerStart.permits(plan: plan(goal: "2 minutes"), action: timer(), result: receipt()))
    XCTAssertEqual(AgentDirectNativeToolPlanner.exactTimerStartSeconds("1 minute and 30 seconds"), 90)
    XCTAssertEqual(AgentDirectNativeToolPlanner.exactTimerStartSeconds("1\u{5206}\u{949f}\u{52a0}30\u{79d2}"), 90)
    XCTAssertFalse(AgentVerifiedTimerStart.permits(plan: plan(goal: "1 minute and 30 seconds"), action: timer(), result: receipt()))
    XCTAssertFalse(AgentVerifiedTimerStart.permits(plan: plan(goal: "Start a one-minute timer and tell me when it finishes"),
      action: timer(), result: receipt()))
    var declared = timer()
    declared.parameters[AgentVerifiedTimerStart.terminalParameter] = "true"
    XCTAssertTrue(AgentVerifiedTimerStart.permits(plan: plan(goal: "Do that", actions: [declared]), action: declared, result: receipt()))
  }

  func testUnverifiedForeignOrMismatchedReceiptNeverCompletes() {
    for (key, bad) in [("completion_verified", "false"), ("timer_state", "paused"), ("duration_seconds", "120"),
                       ("operation_id", ""), ("execution_authority", "desktop")] {
      XCTAssertFalse(AgentVerifiedTimerStart.permits(plan: plan(), action: timer(), result: receipt(changes: [key: .string(bad)])), key)
    }
    for key in ["invocation_id", "native_tool_id", "native_tool_status"] {
      var result = receipt()
      result.metadata.removeValue(forKey: key)
      XCTAssertFalse(AgentVerifiedTimerStart.permits(plan: plan(), action: timer(), result: result))
    }
    var result = receipt()
    result.actionId = "foreign"
    XCTAssertFalse(AgentVerifiedTimerStart.permits(plan: plan(), action: timer(), result: result))
    result = receipt()
    result.metadata["effect_outcome_unknown"] = "true"
    XCTAssertFalse(AgentVerifiedTimerStart.permits(plan: plan(), action: timer(), result: result))
  }

  func testPendingWorkFailedReviewerAndExtraResultRequirementsStayOpen() throws {
    var other = timer()
    other.id = "notify"
    other.status = .proposed
    XCTAssertFalse(AgentVerifiedTimerStart.permits(plan: plan(actions: [timer(), other]), action: timer(), result: receipt()))
    var failed = reviewer()
    failed.status = .failed
    XCTAssertFalse(AgentVerifiedTimerStart.permits(plan: plan(actions: [timer(), failed]), action: timer(), result: receipt()))
    var required = plan()
    required.completionRequirements = .init(publication: .none, phoneLinux: false)
    required.completionRequirements?.results = [try XCTUnwrap(AgentGoalResultRequirement(json:
      ["id": .string("answer"), "description": .string("Explain")]))]
    XCTAssertFalse(AgentVerifiedTimerStart.permits(plan: required, action: timer(), result: receipt()))
    var duplicate = plan()
    duplicate.actions.append(timer())
    XCTAssertFalse(AgentVerifiedTimerStart.permits(plan: duplicate, action: timer(), result: receipt()))
  }

  func testInspectPauseResumeCancelReplaceAndWrongIdentityDoNotBecomeStart() {
    for command in ["inspect", "pause", "resume", "cancel", "replace"] {
      var action = timer()
      action.parameters["input_json"] = input.replacingOccurrences(of: "start", with: command)
      XCTAssertFalse(AgentVerifiedTimerStart.permits(plan: plan(actions: [action]), action: action, result: receipt()))
    }
    var action = timer()
    action.parameters["input_json"] = #"{"parameters":{"timer_seconds":60,"operation_id":"foreign"}}"#
    XCTAssertFalse(AgentVerifiedTimerStart.permits(plan: plan(actions: [action]), action: action, result: receipt()))
  }

  func testLegacyReceiptNeedsOriginalLocalProvenanceAndBoundImmutableCheckpoint() {
    let checkpoint = AgentIOSTimerCheckpoint(id: operation, sourceTurnId: "turn", durationSeconds: 60,
      deadlineMillis: 61_000, state: .scheduled)
    var result = receipt(removing: ["execution_authority", "duration_seconds"])
    XCTAssertFalse(AgentVerifiedTimerStart.permits(plan: plan(), action: timer(), result: result))
    XCTAssertTrue(AgentVerifiedTimerStart.permits(plan: plan(), action: timer(), result: result, legacyCheckpoint: checkpoint))
    result.metadata["provenance"] = "remote"
    XCTAssertFalse(AgentVerifiedTimerStart.permits(plan: plan(), action: timer(), result: result, legacyCheckpoint: checkpoint))
    result = receipt(changes: ["completion_verified": .string("false")], removing: ["execution_authority", "duration_seconds"])
    XCTAssertFalse(AgentVerifiedTimerStart.permits(plan: plan(), action: timer(), result: result, legacyCheckpoint: checkpoint))
  }

  func testWaitingReviewMustDependOnlyOnTheSingleCompletedTimer() {
    XCTAssertEqual(AgentVerifiedTimerStart.waitingStart([timer(), reviewer()], waitingId: "review")?.id, "timer")
    XCTAssertNil(AgentVerifiedTimerStart.waitingStart([timer(), reviewer()], waitingId: "foreign"))
    var foreign = reviewer()
    foreign.parameters["use_outputs_from"] = "other"
    XCTAssertNil(AgentVerifiedTimerStart.waitingStart([timer(), foreign], waitingId: "review"))
    var failed = timer()
    failed.status = .failed
    XCTAssertNil(AgentVerifiedTimerStart.waitingStart([failed, reviewer()], waitingId: "review"))
  }

  func testJournalReopenUsesTheOriginalReceiptWithoutASecondTimerDispatch() throws {
    let suite = "VerifiedTimerJournal-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let secrets = InMemorySecretStore()
    let journal = EncryptedAgentPlanNodeJournal(defaults: defaults, secrets: secrets)
    let prepared = try XCTUnwrap(AgentSequentialPlanNodeDispatch.prepare(plan: plan(actions: [timer()]), action: timer(),
      screen: screen, sessionId: "session", conversationId: "session", turnId: "turn"))
    let result = AgentSequentialPlanNodeDispatch.execute(prepared, journal: journal) { self.receipt() }
    let reopened = EncryptedAgentPlanNodeJournal(defaults: defaults, secrets: secrets)
    let saved = try XCTUnwrap(AgentSequentialPlanNodeDispatch.replay(plan: prepared.plan, actionId: "timer",
      sessionId: "session", conversationId: "session", turnId: "turn", journal: reopened))
    XCTAssertEqual(saved.result, result)
    var observed = prepared.plan
    observed.actions[0].status = .completed
    XCTAssertTrue(AgentVerifiedTimerStart.permits(plan: observed, action: saved.action, result: saved.result))
    XCTAssertEqual(AgentSequentialPlanNodeDispatch.execute(prepared, journal: reopened) {
      XCTFail("No second timer command")
      return self.receipt()
    }, result)
  }

  func testActualTimerProducerReturnsDurationOnlyWithVerifiedSystemState() throws {
    let suite = "VerifiedTimerProducer-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var pending = Set<String>()
    let io = AgentIOSTimerNotificationIO(authorization: { true }, add: { id, _, _ in pending.insert(id); return .accepted },
      pending: { .init(ids: pending, timers: pending) }, delivered: { [] }, remove: { pending.remove($0) })
    let executor = AgentIOSTimerExecutor(store: .init(defaults: defaults, secrets: InMemorySecretStore()), io: io, now: { 1_000 })
    let action = AgentAction(id: "actual", kind: .setAlarm, target: "timer", risk: .medium, status: .proposed,
      description: "Timer", parameters: ["timer_seconds": "60", "_galaxyssi_conversation_id": "session", "_galaxyssi_turn_id": "turn"])
    let result = executor.execute(action)
    XCTAssertTrue(result.success)
    XCTAssertEqual(result.metadata["duration_seconds"], "60")
    XCTAssertEqual(result.metadata["execution_authority"], "galaxyssi-phone")
    XCTAssertEqual(result.metadata["completion_verified"], "true")
    pending.removeAll()
    XCTAssertFalse(executor.execute(action).success)
  }

  private func timer() -> AgentAction {
    AgentAction(id: "timer", kind: .callNativeTool, target: "Phone timer", risk: .medium, status: .completed,
      description: "Start timer", parameters: ["tool_id": AgentVerifiedTimerStart.toolId, "input_json": input])
  }

  private func reviewer() -> AgentAction {
    AgentAction(id: "review", kind: .callConnector, target: "Codex", risk: .low, status: .waitingResponse,
      description: "Review", parameters: ["connector_task_mode": "phone_supervised_project_plan_v1",
        "depends_on": "timer", "use_outputs_from": "timer"])
  }

  private func plan(goal: String = "1 minute", actions: [AgentAction]? = nil) -> AgentPlan {
    AgentPlan(goal: goal, screen: screen, steps: [], actions: actions ?? [timer(), reviewer()], route: AgentRoute())
  }

  private func receipt(changes: AgentMcpJSONObject = [:], removing: Set<String> = []) -> AgentActionResult {
    var meta: AgentMcpJSONObject = ["execution_authority": .string("galaxyssi-phone"), "completion_verified": .string("true"),
      "timer_state": .string("running"), "duration_seconds": .string("60"), "operation_id": .string(operation.uuidString),
      "source_turn_id": .string("turn")]
    meta.merge(changes) { _, new in new }
    for key in removing { meta.removeValue(forKey: key) }
    return AgentActionResult(actionId: "timer", success: true, message: "Timer started", metadata: [
      "native_tool_id": AgentVerifiedTimerStart.toolId, "native_tool_status": "succeeded", "invocation_id": "timer",
      "provenance": AgentPhoneNativeToolCatalog.actionExecutorId,
      "native_tool_output": AgentMcpJSONCodec.stringify(["success": .bool(true), "message": .string("Timer started"), "metadata": .object(meta)])])
  }
}
