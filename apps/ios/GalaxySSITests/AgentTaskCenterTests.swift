import XCTest
@testable import GalaxySSI

final class AgentTaskCenterTests: XCTestCase {
  func testTerminalTaskOffersCompleteTaskCenterActions() {
    XCTAssertEqual(
      AgentTaskCenterPolicy.actions(task(phase: .completed)),
      [.retry, .copy, .viewLog, .delete]
    )
  }

  func testActiveTaskCannotBeDuplicatedOrDeletedFromHistory() {
    XCTAssertEqual(
      AgentTaskCenterPolicy.actions(task(phase: .executing)),
      [.copy, .viewLog]
    )
  }

  func testRedactedGoalCannotBeRetried() {
    let actions = AgentTaskCenterPolicy.actions(
      task(goal: "Sensitive goal withheld", phase: .failed)
    )

    XCTAssertFalse(actions.contains(.retry))
    XCTAssertTrue(actions.contains(.delete))
  }

  func testDeleteRemovesOnlySelectedTask() {
    let first = task(taskId: "task-1", sessionId: "shared-session")
    let second = task(taskId: "task-2", sessionId: "shared-session")
    let store = InMemoryTaskStore([first, second])
    let center = AgentTaskCenter(store: store)

    XCTAssertTrue(center.deleteTask(first.taskId))
    XCTAssertNil(store.find(first.taskId))
    XCTAssertEqual(store.find(second.taskId), second)
    XCTAssertFalse(center.deleteTask(first.taskId))
  }

  func testCapturePermissionContinuationPreservesOriginalScopeAcrossPauseAndReload() throws {
    let (original, outgoing, wait) = captureWait()
    XCTAssertTrue(wait.acceptsCallback(in: original, outgoing: outgoing))
    XCTAssertTrue(AgentTaskCenterPolicy.actions(original).contains(.pause))
    XCTAssertTrue(AgentTaskCenterPolicy.actions(original).contains(.cancel))
    var paused = original
    paused.phase = .paused
    let restored = try JSONDecoder().decode(AgentTaskRecord.self, from: JSONEncoder().encode(paused))
    XCTAssertEqual(restored.activePlan, original.activePlan)
    XCTAssertEqual(restored.pendingActions, original.pendingActions)
    XCTAssertEqual(wait.action(in: restored, outgoing: outgoing), original.pendingAction)
    XCTAssertFalse(wait.acceptsCallback(in: restored, outgoing: outgoing))
    XCTAssertTrue(AgentTaskCenterPolicy.resumable(restored))
    var changed = original
    changed.activePlan?.revision += 1
    XCTAssertFalse(wait.acceptsCallback(in: changed, outgoing: outgoing))
    changed = original
    changed.pendingAction?.parameters["input_json"] = #"{"facing":"front"}"#
    changed.pendingActions = try [XCTUnwrap(changed.pendingAction)]
    XCTAssertFalse(wait.acceptsCallback(in: changed, outgoing: outgoing))
    var foreign = outgoing
    foreign.turnId = "different-turn"
    XCTAssertFalse(wait.acceptsCallback(in: original, outgoing: foreign))
    foreign = outgoing
    foreign.conversationId = "different-conversation"
    XCTAssertFalse(wait.acceptsCallback(in: original, outgoing: foreign))
    var dispatched = wait
    dispatched.dispatched = true
    paused.capturePermission = dispatched
    XCTAssertFalse(AgentTaskCenterPolicy.resumable(paused))
    XCTAssertFalse(AgentTaskCenterPolicy.pauseable(paused))
    XCTAssertFalse(AgentTaskCenterPolicy.pauseable(task(phase: .blocked)))
    XCTAssertFalse(AgentTaskCenterPolicy.cancellable(task(phase: .blocked)))
  }

  func testCapturePermissionRejectsDuplicateAndLateCallbacksWithoutAffectingAnotherTask() {
    let (_, _, first) = captureWait()
    let (_, _, other) = captureWait(taskId: "other")
    var requests = AgentCapturePermissionRequests()
    requests.register(first)
    requests.register(other)
    requests.invalidate(taskId: first.taskId)
    XCTAssertFalse(requests.consume(first))
    var resumed = first
    resumed.token = UUID()
    requests.register(resumed)
    XCTAssertFalse(requests.consume(first))
    XCTAssertTrue(requests.consume(resumed))
    XCTAssertFalse(requests.consume(resumed))
    XCTAssertTrue(requests.consume(other))
    requests.register(first)
    requests.invalidate(taskId: first.taskId)
    XCTAssertFalse(requests.consume(first))
  }

  func testPermissionRequiredIsNonterminalAndCancellationSurvivesLedgerReload() throws {
    let (_, _, wait) = captureWait()
    let suite = "capture-permission-tests-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let ledger = UserDefaultsAgentRunEventStore(defaults: defaults)
    let required = wait.event(.toolPermissionRequired, stage: "permission_required", now: 1)
    _ = ledger.appendNext(required)
    _ = ledger.appendNext(required)
    XCTAssertEqual(ledger.snapshot(runId: wait.taskId)?.state, .waitingForUser)
    _ = ledger.appendNext(wait.event(.paused, stage: "paused", now: 2))
    _ = ledger.appendNext(wait.event(.runRecovered, stage: "resumed", now: 3))
    _ = ledger.appendNext(wait.event(.runCancelled, stage: "cancelled", now: 4))
    let restored = UserDefaultsAgentRunEventStore(defaults: defaults)
    XCTAssertEqual(restored.snapshot(runId: wait.taskId)?.state, .cancelled)
    XCTAssertEqual(restored.events(runId: wait.taskId).map(\.type),
      [.toolPermissionRequired, .paused, .runRecovered, .runCancelled])
  }

  private func captureWait(taskId: String = "capture") -> (
    AgentTaskRecord, ChatMessage, AgentCapturePermissionContinuation
  ) {
    let outgoing = ChatMessage(contactId: "hermes", content: "Take a photo", isMine: true,
      conversationId: "conversation", turnId: taskId)
    let action = AgentAction(id: "camera", kind: .callNativeTool, target: "Camera", risk: .medium,
      status: .pendingConfirmation, description: "Capture", parameters: [
        "tool_id": AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture,
        "input_json": #"{"facing":"back"}"#
      ])
    var record = task(taskId: taskId, phase: .waitingResponse)
    record.pendingAction = action
    record.pendingActions = [action]
    record.activePlan = AgentPlan(goal: record.goal, screen: AgentScreenContext(foregroundApp: "GalaxySSI"),
      steps: [], actions: [action], route: AgentRoute())
    let wait = AgentCapturePermissionContinuation(task: record, outgoing: outgoing, action: action,
      kind: .photo, permissionMode: .askBeforeAction)
    record.capturePermission = wait
    return (record, outgoing, wait)
  }

  private func task(
    taskId: String = "task",
    sessionId: String = "conversation",
    goal: String = "Summarize the file",
    phase: AgentPhase = .completed
  ) -> AgentTaskRecord {
    AgentTaskRecord(
      taskId: taskId,
      sessionId: sessionId,
      goal: goal,
      phase: phase,
      routeKind: .desktopAgent,
      targetTitle: "Codex",
      risk: .low,
      blocked: false
    )
  }

  private final class InMemoryTaskStore: AgentTaskStore {
    private var records: [String: AgentTaskRecord]

    init(_ initial: [AgentTaskRecord]) {
      records = Dictionary(uniqueKeysWithValues: initial.map { ($0.taskId, $0) })
    }

    func upsert(_ record: AgentTaskRecord) {
      records[record.taskId] = record
    }

    func recent(limit: Int) -> [AgentTaskRecord] {
      Array(records.values.prefix(limit))
    }

    func forSession(_ sessionId: String, limit: Int) -> [AgentTaskRecord] {
      Array(records.values.filter { $0.sessionId == sessionId }.prefix(limit))
    }

    func find(_ taskId: String) -> AgentTaskRecord? {
      records[taskId]
    }

    func search(query: String, limit: Int) -> [AgentTaskRecord] {
      Array(records.values.filter { $0.goal.contains(query) }.prefix(limit))
    }

    func rebindSession(sourceSessionId: String, targetSessionId: String) -> Int {
      0
    }

    func delete(_ taskIds: Set<String>) {
      records = records.filter { entry in
        !taskIds.contains(entry.key) && !taskIds.contains(entry.value.sessionId)
      }
    }

    func deleteTask(_ taskId: String) {
      records.removeValue(forKey: taskId)
    }

    func clear() {
      records.removeAll()
    }
  }
}
