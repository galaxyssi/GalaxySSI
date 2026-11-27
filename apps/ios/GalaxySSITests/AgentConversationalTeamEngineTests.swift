import XCTest
@testable import GalaxySSI

private actor SyntheticTeamWire {
  enum Fault: Error { case transport, badInput }
  struct Snapshot: Sendable {
    let calls: [String]
    let peak: Int
    let parents: [String: [String]]
    let synthesisOrder: [String]
    let cancelled: Set<String>
  }
  let plan: String
  let minimumParallel: Int
  let fail: String?
  let wait: String?
  let releaseOn: String?
  let synthesis: String
  let dissent: [String: String]
  private var calls: [String] = []
  private var active = 0
  private var peak = 0
  private var released = false
  private var parents: [String: [String]] = [:]
  private var synthesisOrder: [String] = []
  private var cancelled = Set<String>()
  init(plan: String, minimumParallel: Int = 0, fail: String? = nil, wait: String? = nil, releaseOn: String? = nil,
    synthesis: String = "Combined.\nEND", dissent: [String: String] = [:]) {
    self.plan = plan; self.minimumParallel = minimumParallel; self.fail = fail; self.wait = wait; self.releaseOn = releaseOn
    self.synthesis = synthesis; self.dissent = dissent
  }
  func snapshot() -> Snapshot { .init(calls: calls, peak: peak, parents: parents, synthesisOrder: synthesisOrder, cancelled: cancelled) }
  func ask(_ system: String, _ raw: String) async throws -> String {
    guard !system.contains("synthetic-objective"),
      let input = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
      input["objective"] as? String == "synthetic-objective", let stage = input["stage"] as? String else { throw Fault.badInput }
    let id = input["id"] as? String ?? stage
    calls.append(id)
    if id == fail {
      let deadline = ProcessInfo.processInfo.systemUptime + 3
      while let wait, parents[wait] == nil {
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw Fault.transport }
        try await Task.sleep(nanoseconds: 1_000_000)
      }
      throw Fault.transport
    }
    if stage == "plan" { return plan }
    guard let reports = input["reports"] as? [[String: Any]] else { throw Fault.badInput }
    let ids = reports.compactMap { $0["id"] as? String }
    guard ids.count == reports.count else { throw Fault.badInput }
    if stage == "synthesis" { synthesisOrder = ids; return synthesis }
    guard stage == "role" else { throw Fault.badInput }
    parents[id] = ids
    active += 1; peak = max(peak, active)
    defer { active -= 1 }
    if active >= minimumParallel { released = true }
    do {
      let deadline = ProcessInfo.processInfo.systemUptime + 3
      while !released {
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw Fault.transport }
        try await Task.sleep(nanoseconds: 1_000_000)
      }
      while id == wait {
        if let releaseOn, parents[releaseOn] != nil { break }
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw Fault.transport }
        try await Task.sleep(nanoseconds: 1_000_000)
      }
      try Task.checkCancellation()
      return "FINDING|public-\(id)\nDISSENT|\(dissent[id] ?? "-")\nEND"
    } catch is CancellationError { cancelled.insert(id); throw CancellationError() }
  }
}

final class AgentConversationalTeamEngineTests: XCTestCase {
  private func role(_ id: String, _ parents: String = "-", _ kind: String = "worker") -> String { "ROLE|\(id)|\(kind)|\(parents)|assignment-\(id)" }
  private func plan(_ roles: [String]) -> String { (roles + ["SYNTHESIS|Combine public findings."]).joined(separator: "\n") }

  @MainActor func testZeroRolesStillUsesSeparatePlanningAndAnswerCalls() async throws {
    let wire = SyntheticTeamWire(plan: plan([]))
    var events: [AgentConversationalTeamEngine.Event] = []
    let result = try await AgentConversationalTeamEngine.run(objective: "synthetic-objective", ask: { try await wire.ask($0, $1) }, onEvent: { events.append($0) })
    let snapshot = await wire.snapshot()
    XCTAssertEqual(snapshot.calls, ["plan", "synthesis"])
    XCTAssertEqual(result.calls, 2); XCTAssertEqual(result.answer, "Combined.")
    XCTAssertEqual(events, [.planning, .planAccepted(0), .synthesizing, .completed])
  }
  @MainActor func testTenRolesOverlapAtMostThreeAndConsumeTwelveLogicalCalls() async throws {
    let ids = (1...10).map { "job\($0)" }
    let wire = SyntheticTeamWire(plan: plan(ids.map { role($0) }), minimumParallel: 3)
    let result = try await AgentConversationalTeamEngine.run(objective: "synthetic-objective", ask: { try await wire.ask($0, $1) })
    let snapshot = await wire.snapshot()
    XCTAssertEqual(snapshot.peak, 3); XCTAssertEqual(snapshot.calls.count, 12); XCTAssertEqual(result.calls, 12)
    XCTAssertEqual(snapshot.synthesisOrder, ids)
    XCTAssertTrue(snapshot.parents.values.allSatisfy(\.isEmpty))
  }
  @MainActor func testOnlyDirectPredecessorsAreSharedAndDisagreementSurvivesSynthesis() async throws {
    let roles = [role("review", "draft,critic", "reviewer"), role("critic", "source", "dissent"), role("draft"), role("source"), role("slow")]
    let wire = SyntheticTeamWire(plan: plan(roles), wait: "slow", releaseOn: "review",
      dissent: ["critic": "The sample omits weekends.", "review": "The dates are unconfirmed."])
    let result = try await AgentConversationalTeamEngine.run(objective: "synthetic-objective", ask: { try await wire.ask($0, $1) })
    let snapshot = await wire.snapshot()
    XCTAssertEqual(snapshot.parents["critic"], ["source"])
    XCTAssertEqual(snapshot.parents["review"], ["draft", "critic"])
    XCTAssertEqual(snapshot.synthesisOrder, ["review", "critic", "draft", "source", "slow"])
    let output = result.publicText(disagreementsTitle: "Reported disagreements:")
    XCTAssertTrue(output.hasSuffix("Reported disagreements:\n- [review] The dates are unconfirmed.\n- [critic] The sample omits weekends."))
  }
  @MainActor func testInvalidPlanCannotDispatchAnOtherwiseReadyRoot() async {
    let wire = SyntheticTeamWire(plan: plan([role("ok"), role("broken", "missing")]))
    var events: [AgentConversationalTeamEngine.Event] = []
    do {
      _ = try await AgentConversationalTeamEngine.run(objective: "synthetic-objective", ask: { try await wire.ask($0, $1) }, onEvent: { events.append($0) })
      XCTFail("Invalid graph must fail before dispatch")
    } catch { }
    let snapshot = await wire.snapshot()
    XCTAssertEqual(snapshot.calls, ["plan"]); XCTAssertEqual(events.last, .stopped)
  }
  @MainActor func testFailedBranchCancelsSiblingAndDoesNotSynthesize() async {
    let wire = SyntheticTeamWire(plan: plan([role("waiter"), role("broken"), role("later", "broken")]), fail: "broken", wait: "waiter")
    do {
      _ = try await AgentConversationalTeamEngine.run(objective: "synthetic-objective", ask: { try await wire.ask($0, $1) })
      XCTFail("A failed branch must not produce an answer")
    } catch { }
    let snapshot = await wire.snapshot()
    XCTAssertFalse(snapshot.calls.contains("synthesis")); XCTAssertFalse(snapshot.calls.contains("later"))
    XCTAssertTrue(snapshot.cancelled.contains("waiter"))
  }
  @MainActor func testCallerCancellationDoesNotDispatchDependents() async throws {
    let wire = SyntheticTeamWire(plan: plan([role("first"), role("later", "first")]), wait: "first")
    let task = Task { try await AgentConversationalTeamEngine.run(objective: "synthetic-objective", ask: { try await wire.ask($0, $1) }) }
    let deadline = ProcessInfo.processInfo.systemUptime + 3
    while !(await wire.snapshot()).calls.contains("first"), ProcessInfo.processInfo.systemUptime < deadline {
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancellation must propagate") } catch { XCTAssertTrue(error is CancellationError) }
    let snapshot = await wire.snapshot()
    XCTAssertFalse(snapshot.calls.contains("later")); XCTAssertFalse(snapshot.calls.contains("synthesis"))
  }
  @MainActor func testInvalidObjectivesAndIncompleteFinalAnswerCannotComplete() async {
    for objective in [" ", String(repeating: "x", count: 8_001)] {
      let wire = SyntheticTeamWire(plan: plan([]))
      do { _ = try await AgentConversationalTeamEngine.run(objective: objective, ask: { try await wire.ask($0, $1) }); XCTFail("Invalid objective") } catch { }
      let snapshot = await wire.snapshot(); XCTAssertTrue(snapshot.calls.isEmpty)
    }
    let wire = SyntheticTeamWire(plan: plan([]), synthesis: "Partial answer without an end marker")
    var events: [AgentConversationalTeamEngine.Event] = []
    do { _ = try await AgentConversationalTeamEngine.run(objective: "synthetic-objective", ask: { try await wire.ask($0, $1) }, onEvent: { events.append($0) }); XCTFail("Incomplete answer") } catch { }
    XCTAssertFalse(events.contains(.completed)); XCTAssertEqual(events.last, .stopped)
  }
}
