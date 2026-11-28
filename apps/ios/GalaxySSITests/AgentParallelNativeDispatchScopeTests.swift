import XCTest
@testable import GalaxySSI

@MainActor
final class AgentParallelNativeDispatchScopeTests: XCTestCase {
  private func fixture() -> (task: AgentTaskRecord, source: ChatMessage, actions: [AgentAction]) {
    let source = ChatMessage(contactId: "hermes", content: "Synthetic parallel tools", isMine: true,
      conversationId: "conversation", turnId: "parallel-turn")
    let owner = AgentPlanContinuationScope(conversationId: source.conversationId, turnId: source.turnId)
    let actions = ["a", "b"].map { id in
      owner.bind(AgentAction(id: id, kind: .callNativeTool, target: "fixture.tool.\(id)", risk: .low,
        status: .proposed, description: "Fixture", parameters: ["tool_id": "fixture.tool.\(id)", "input_json": "{}"],
        requiresConfirmation: false))
    }
    let running = actions.map { original -> AgentAction in var value = original; value.status = .running; return value }
    var task = AgentTaskRecord(taskId: source.turnId, sessionId: source.conversationId, goal: source.content,
      phase: .executing, routeKind: .localSystem, targetTitle: "Fixture", risk: .low, blocked: false)
    task.activePlan = AgentPlan(goal: task.goal, screen: .init(foregroundApp: "GalaxySSI"), steps: [], actions: running, route: AgentRoute())
    task.localOperationProcessId = "fixture-process"
    return (task, source, actions)
  }

  private func scope(_ f: (task: AgentTaskRecord, source: ChatMessage, actions: [AgentAction])) throws -> AgentParallelNativeDispatchScope {
    try XCTUnwrap(AgentParallelNativeDispatchScope(profile: "profile-a", task: f.task, source: f.source,
      actions: f.actions, processId: "fixture-process"))
  }

  func testExactParallelTaskAndSourceKeepTheirOwner() throws {
    let f = fixture(), owned = try scope(f)
    XCTAssertTrue(owned.matches(profile: "profile-a", task: f.task, source: f.source, cancelled: false))
    XCTAssertEqual(owned.task, f.task)
  }

  func testDifferentProfileAndCancellationCannotProjectParallelResults() throws {
    let f = fixture(), owned = try scope(f)
    XCTAssertFalse(owned.matches(profile: "profile-b", task: f.task, source: f.source, cancelled: false))
    XCTAssertFalse(owned.matches(profile: "profile-a", task: f.task, source: f.source, cancelled: true))
    XCTAssertFalse(owned.matches(profile: "profile-a", task: nil, source: f.source, cancelled: false))
  }

  func testConcurrentTaskChangesCannotBeOverwrittenByTheOldBatch() throws {
    let f = fixture(), owned = try scope(f)
    for variation in 0..<5 {
      var task = f.task
      if variation == 0 { task.phase = .paused }
      if variation == 1 { task.activePlan?.revision += 1 }
      if variation == 2 { task.activePlan?.actions[0].parameters["input_json"] = "changed" }
      if variation == 3 { task.executionLog.append("Concurrent task update") }
      if variation == 4 { task.localOperationProcessId = "other-process" }
      XCTAssertFalse(owned.matches(profile: "profile-a", task: task, source: f.source, cancelled: false))
    }
  }

  func testChangedOrMissingOriginalSourceCannotReceiveOldResults() throws {
    let f = fixture(), owned = try scope(f)
    for variation in 0..<5 {
      var source = f.source
      if variation == 0 { source.id = UUID() }
      if variation == 1 { source.conversationId = "other-conversation" }
      if variation == 2 { source.content = "Changed request" }
      if variation == 3 { source.richOutputJson = "changed-attachments" }
      if variation == 4 { source.readOnlyAnalysis = true }
      XCTAssertFalse(owned.matches(profile: "profile-a", task: f.task, source: source, cancelled: false))
    }
    XCTAssertFalse(owned.matches(profile: "profile-a", task: f.task, source: nil, cancelled: false))
  }

  func testDuplicateForeignOrUnplannedActionsCannotOwnAParallelDispatch() {
    let f = fixture()
    for variation in 0..<5 {
      var actions = f.actions, task = f.task
      if variation == 0 { actions = [actions[0], actions[0]] }
      if variation == 1 { actions[0].parameters["input_json"] = "different" }
      if variation == 2 { actions.removeLast() }
      if variation == 3 { task.activePlan?.executionMode = .planOnly }
      if variation == 4 { actions[0].kind = .callConnector }
      XCTAssertNil(AgentParallelNativeDispatchScope(profile: "profile-a", task: task, source: f.source,
        actions: actions, processId: "fixture-process"))
    }
  }

  func testCheckedNativeTaskCommitSurvivesStoreReopen() throws {
    try withStore { store, defaults, secrets in
      let f = fixture()
      _ = store.upsertAgentTask(f.task)
      var updated = f.task
      updated.verification = "Durably recorded fixture state"
      XCTAssertEqual(store.commitNativeAgentTaskState(expected: f.task, updated: updated), updated)
      XCTAssertEqual(GalaxySSIStore(defaults: defaults, secrets: secrets).agentTask(id: updated.taskId), updated)
    }
  }

  func testCheckedNativeCommitRejectsStaleAndCancelledOwners() throws {
    try withStore { store, _, _ in
      let f = fixture()
      _ = store.upsertAgentTask(f.task)
      var current = f.task
      current.verification = "Newer fixture state"
      _ = store.upsertAgentTask(current)
      XCTAssertNil(store.commitNativeAgentTaskState(expected: f.task, updated: f.task))
      current.phase = .cancelled
      _ = store.upsertAgentTask(current)
      XCTAssertNil(store.commitNativeAgentTaskState(expected: current, updated: f.task))
      XCTAssertEqual(store.agentTask(id: current.taskId)?.phase, .cancelled)
    }
  }

  func testFailedStateWriteRollsBackAndDoesNotAdmitSyntheticExecution() throws {
    try withStore { store, defaults, secrets in
      let f = fixture()
      _ = store.upsertAgentTask(f.task)
      var next = f.task
      next.executionLog.append("Uncommitted dispatch intent")
      secrets.rejectStateWrites = true
      var executions = 0
      if store.commitNativeAgentTaskState(expected: f.task, updated: next) != nil { executions += 1 }
      XCTAssertEqual(executions, 0)
      XCTAssertEqual(store.agentTask(id: f.task.taskId), f.task)
      secrets.rejectStateWrites = false
      XCTAssertEqual(GalaxySSIStore(defaults: defaults, secrets: secrets).agentTask(id: f.task.taskId), f.task)
    }
  }

  private func withStore(_ body: (GalaxySSIStore, UserDefaults, FailingSecrets) throws -> Void) throws {
    let suite = "ParallelDispatchOwnership.\(UUID())", secrets = FailingSecrets()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(GalaxySSIStore(defaults: defaults, secrets: secrets), defaults, secrets)
  }

  private final class FailingSecrets: GalaxySSISecretStore {
    var rejectStateWrites = false
    private var values: [String: String] = [:]
    func string(account: String) -> String? {
      if rejectStateWrites && account == "state.encryption.aes256" { return nil }
      return values[account]
    }
    func setString(_ value: String, account: String) throws {
      if rejectStateWrites && account == "state.encryption.aes256" {
        throw GalaxySSIError.invalidPayload("Injected fixture state-write failure")
      }
      values[account] = value
    }
    func delete(account: String) { values.removeValue(forKey: account) }
  }
}
