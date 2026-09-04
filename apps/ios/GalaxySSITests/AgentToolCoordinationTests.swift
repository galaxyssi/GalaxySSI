import XCTest
@testable import GalaxySSI

final class AgentToolCoordinationTests: XCTestCase {
  func testDependencyParsingAndRemapMatchAndroidDistinctMappedOnlySemantics() {
    let original = action(
      "old",
      parameters: [
        "depends_on": " a, b, a, , c ",
        "use_outputs_from": "a, d, d"
      ]
    )
    let remapped = AgentToolCoordination.remapToolGraphIds(
      action: original,
      newId: "new",
      idMap: ["a": "A", "c": "C"]
    )

    XCTAssertEqual(AgentToolCoordination.dependencyIds(original), ["a", "b", "c"])
    XCTAssertEqual(AgentToolCoordination.outputSourceIds(original), ["a", "d"])
    XCTAssertEqual(remapped.id, "new")
    XCTAssertEqual(remapped.parameters["depends_on"], "A,C")
    XCTAssertEqual(remapped.parameters["use_outputs_from"], "A")
  }

  func testNextRunnableActionAndFailedDependencyBlocking() throws {
    let completedHistory = action("prepare", status: .completed, result: "done")
    let failedHistory = action("fetch", status: .failed, result: "network failed")
    let ready = action("ready", parameters: ["depends_on": "prepare"])
    let blocked = action("blocked", parameters: ["depends_on": "fetch"])
    let waiting = action("waiting", parameters: ["depends_on": "missing"])
    let plan = self.plan(
      actions: [ready, blocked, waiting],
      actionHistory: [completedHistory, failedHistory]
    )

    let next = try XCTUnwrap(AgentToolCoordination.nextRunnableAction(plan))
    let blockedPlan = AgentToolCoordination.blockActionsWithFailedDependencies(plan)

    XCTAssertEqual(next.id, "ready")
    XCTAssertEqual(blockedPlan.actions.map(\.status), [.proposed, .blocked, .proposed])
    XCTAssertEqual(blockedPlan.actions[1].result, "Dependency fetch did not complete")
  }

  func testMaterializeToolInputInjectsCompletedOutputsOnlyWhenAllowed() {
    let source = action(
      "source",
      target: "Research Agent",
      status: .completed,
      result: "Primary result",
      parameters: ["node_ref": "research"]
    )
    let failed = action("failed", target: "Verifier", status: .failed, result: "Should not appear")
    let target = action(
      "target",
      kind: .callConnector,
      description: "Synthesize",
      parameters: [
        "prompt": "Review",
        "use_outputs_from": "source,failed,missing"
      ]
    )
    let plan = self.plan(actions: [source, failed, target])

    let materialized = AgentToolCoordination.materializeToolInput(
      plan: plan,
      action: target,
      allowOutputHandoff: true
    )
    let unchanged = AgentToolCoordination.materializeToolInput(
      plan: plan,
      action: target,
      allowOutputHandoff: false
    )
    let prompt = materialized.parameters["prompt"] ?? ""

    XCTAssertTrue(prompt.hasPrefix("Review\n\nDependency outputs follow."))
    XCTAssertTrue(prompt.contains("[research] Research Agent:\nPrimary result"))
    XCTAssertFalse(prompt.contains("Should not appear"))
    XCTAssertEqual(unchanged.parameters["prompt"], "Review")
    XCTAssertTrue(AgentToolCoordination.hasOutputHandoff(from: "source", in: plan))
    XCTAssertFalse(AgentToolCoordination.hasOutputHandoff(from: "missing", in: plan))
  }

  func testToolGraphDepthHandlesChainsAndCycles() {
    let chain = plan(actions: [
      action("prepare"),
      action("analyze", parameters: ["depends_on": "prepare"]),
      action("write", parameters: ["depends_on": "analyze"])
    ])
    let cycle = plan(actions: [
      action("a", parameters: ["depends_on": "b"]),
      action("b", parameters: ["depends_on": "a"])
    ])

    XCTAssertEqual(AgentToolCoordination.toolGraphDepth(chain), 3)
    XCTAssertEqual(AgentToolCoordination.toolGraphDepth(cycle), Int.max)
  }

  func testExecutionBatchUsesAdaptiveParallelReadLimit() throws {
    let descriptors = try Dictionary(uniqueKeysWithValues: (0..<6).map { index in
      let id = "galaxyssi.test.read.\(index)"
      return (id, try descriptor(id: id, concurrency: .parallelReadOnly))
    })
    let actions = (0..<6).map { index in
      action(
        "read-\(index)",
        kind: .callNativeTool,
        target: "galaxyssi.test.read.\(index)",
        parameters: [
          "tool_id": "galaxyssi.test.read.\(index)",
          "input_json": "{\"path\":\"file-\(index)\"}"
        ]
      )
    }

    let batch = AgentPlanExecutionBatchPolicy.select(
      plan: plan(actions: actions),
      maximumParallelReads: 5,
      descriptorFor: { descriptors[$0] }
    )

    XCTAssertTrue(batch.parallelReadOnly)
    XCTAssertEqual(batch.actions.map(\.id), ["read-0", "read-1", "read-2", "read-3", "read-4"])
  }

  func testAdaptiveConcurrencyPolicyRespondsToDevicePressure() {
    let healthy = AgentAdaptiveConcurrencySignals(
      logicalProcessorCount: 8,
      totalMemoryBytes: 24 * 1_024 * 1_024 * 1_024,
      availableMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
      lowMemory: false,
      thermalStatus: 0,
      cpuLoadPercent: 10
    )

    XCTAssertEqual(AgentAdaptiveConcurrencyPolicy.limit(signals: healthy, workload: .nativeReadIO), 64)
    XCTAssertEqual(AgentAdaptiveConcurrencyPolicy.limit(signals: healthy, workload: .readReasoning), 16)
    var constrained = healthy
    constrained.availableMemoryBytes = 128 * 1_024 * 1_024
    XCTAssertEqual(AgentAdaptiveConcurrencyPolicy.limit(signals: constrained, workload: .nativeReadIO), 2)
    constrained = healthy
    constrained.thermalStatus = 2
    XCTAssertEqual(AgentAdaptiveConcurrencyPolicy.limit(signals: constrained, workload: .nativeReadIO), 32)
    constrained = healthy
    constrained.cpuLoadPercent = 94
    XCTAssertEqual(AgentAdaptiveConcurrencyPolicy.limit(signals: constrained, workload: .nativeReadIO), 16)
    constrained.lowMemory = true
    XCTAssertEqual(AgentAdaptiveConcurrencyPolicy.limit(signals: constrained, workload: .nativeReadIO), 1)
  }

  func testExecutionBatchStopsBeforeDuplicateOrSerializedObservation() throws {
    let read = try descriptor(id: "galaxyssi.test.read", concurrency: .parallelReadOnly)
    let write = try descriptor(
      id: "galaxyssi.test.write",
      idempotency: .idempotencyKeyRequired,
      concurrency: .serial
    )
    let first = action(
      "first",
      kind: .callNativeTool,
      target: read.id,
      parameters: ["tool_id": read.id, "input_json": "{\"path\":\"a\"}"]
    )
    let duplicate = action(
      "duplicate",
      kind: .callNativeTool,
      target: read.id,
      parameters: ["tool_id": read.id, "input_json": "{\"path\":\"a\"}"]
    )
    let mutation = action(
      "write",
      kind: .callNativeTool,
      target: write.id,
      parameters: ["tool_id": write.id]
    )
    let descriptors = [read.id: read, write.id: write]

    let duplicateBatch = AgentPlanExecutionBatchPolicy.select(
      plan: plan(actions: [first, duplicate]),
      descriptorFor: { descriptors[$0] }
    )
    let mutationBatch = AgentPlanExecutionBatchPolicy.select(
      plan: plan(actions: [mutation, first]),
      descriptorFor: { descriptors[$0] }
    )

    XCTAssertFalse(duplicateBatch.parallelReadOnly)
    XCTAssertEqual(duplicateBatch.actions.map(\.id), ["first"])
    XCTAssertFalse(mutationBatch.parallelReadOnly)
    XCTAssertEqual(mutationBatch.actions.map(\.id), ["write"])
  }

  func testNativeToolBatchExecutorPreservesPlanOrder() {
    let actions = (0..<4).map { index in
      action("action-\(index)", kind: .callNativeTool)
    }

    let results = AgentNativeToolBatchExecutor.executeOrdered(actions: actions) { action in
      let index = Int(action.id.split(separator: "-").last ?? "0") ?? 0
      Thread.sleep(forTimeInterval: Double(4 - index) * 0.005)
      return AgentActionResult(actionId: action.id, success: true, message: "done")
    }

    XCTAssertEqual(results.map(\.actionId), actions.map(\.id))
  }

  private func plan(
    actions: [AgentAction],
    actionHistory: [AgentAction] = []
  ) -> AgentPlan {
    AgentPlan(
      goal: "Coordinate tools",
      screen: AgentScreenContext(foregroundApp: "GalaxySSI"),
      steps: [],
      actions: actions,
      confirmationRequired: true,
      actionHistory: actionHistory
    )
  }

  private func action(
    _ id: String,
    kind: AgentActionKind = .draftPlan,
    target: String = "GalaxySSI",
    status: AgentActionStatus = .proposed,
    result: String = "",
    parameters: [String: String] = [:]
  ) -> AgentAction {
    AgentAction(
      id: id,
      kind: kind,
      target: target,
      risk: .low,
      status: status,
      description: "Action \(id)",
      parameters: parameters,
      requiresConfirmation: false,
      result: result
    )
  }

  private func descriptor(
    id: String,
    idempotency: AgentNativeToolIdempotency = .idempotent,
    concurrency: AgentNativeToolConcurrency
  ) throws -> AgentNativeToolDescriptor {
    try AgentNativeToolDescriptor(
      id: id,
      version: "1.0.0",
      title: id,
      description: "Test tool",
      location: .application,
      risk: .low,
      idempotency: idempotency,
      concurrency: concurrency
    )
  }
}
