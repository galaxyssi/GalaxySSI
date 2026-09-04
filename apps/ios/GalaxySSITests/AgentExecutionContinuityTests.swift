import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentExecutionContinuityCreatesRollbackCheckpointAndAndroidDigest() throws {
    let screen = AgentScreenContext(
      foregroundApp: "GalaxySSI",
      activityName: "MainActivity",
      pageTitle: "Agent",
      visibleTextCount: 2,
      clickableNodeCount: 4,
      inputFieldCount: 1,
      visibleTexts: ["Inbox", "Compose"]
    )
    let changedScreen = AgentScreenContext(
      foregroundApp: "GalaxySSI",
      activityName: "MainActivity",
      pageTitle: "Agent",
      visibleTextCount: 2,
      clickableNodeCount: 4,
      inputFieldCount: 1,
      visibleTexts: ["Inbox", "Changed"]
    )
    let action = AgentAction(
      id: "open",
      kind: .openURL,
      target: "https://example.com",
      risk: .medium,
      status: .running,
      description: "Open docs"
    )

    let checkpoint = AgentExecutionContinuity.checkpointBefore(
      action: action,
      screen: screen,
      planRevision: 7,
      id: "checkpoint-1",
      nowMillis: 1_234
    )

    XCTAssertEqual(AgentExecutionContinuity.screenDigest(screen), "806208482")
    XCTAssertEqual(AgentExecutionContinuity.screenDigest(changedScreen), "-1027068")
    XCTAssertEqual(checkpoint.id, "checkpoint-1")
    XCTAssertEqual(checkpoint.actionId, "open")
    XCTAssertEqual(checkpoint.planRevision, 7)
    XCTAssertEqual(checkpoint.foregroundApp, "GalaxySSI")
    XCTAssertEqual(checkpoint.activityName, "MainActivity")
    XCTAssertEqual(checkpoint.pageTitle, "Agent")
    XCTAssertEqual(checkpoint.screenDigest, "806208482")
    XCTAssertEqual(checkpoint.status, .active)
    XCTAssertEqual(checkpoint.createdAtMillis, 1_234)
    XCTAssertEqual(checkpoint.rollbackAction?.id, "rollback-open")
    XCTAssertEqual(checkpoint.rollbackAction?.kind, .back)
    XCTAssertEqual(checkpoint.rollbackAction?.status, .pendingConfirmation)
    XCTAssertTrue(checkpoint.rollbackAction?.requiresConfirmation == true)

    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try JSONEncoder().encode(checkpoint)) as? [String: Any]
    )
    XCTAssertEqual(object["plan_revision"] as? Int, 7)
    XCTAssertEqual(object["foreground_app"] as? String, "GalaxySSI")
    XCTAssertEqual(object["screen_digest"] as? String, "806208482")
    XCTAssertEqual((object["created_at_millis"] as? NSNumber)?.int64Value, Int64(1_234))
    XCTAssertNotNil(object["rollback_action"])
  }

  func testAgentExecutionContinuityReversesSwipeAndRestoresInterruptedActions() {
    let running = AgentAction(
      id: "swipe",
      kind: .swipe,
      target: "screen",
      risk: .low,
      status: .running,
      description: "Swipe up",
      parameters: [
        "from_x": "10",
        "from_y": "90",
        "to_x": "10",
        "to_y": "10"
      ]
    )
    let pending = AgentAction(
      id: "pending",
      kind: .tap,
      target: "button",
      risk: .low,
      status: .pendingConfirmation,
      description: "Tap"
    )
    let plan = lifecyclePlan(running, pending)
    let checkpoint = AgentExecutionContinuity.checkpointBefore(
      action: running,
      screen: plan.screen,
      planRevision: plan.revision,
      id: "checkpoint-swipe",
      nowMillis: 2_000
    )
    let rollback = checkpoint.rollbackAction
    let recovered = plan.addCheckpoint(checkpoint).recoverInterruptedExecution()

    XCTAssertEqual(rollback?.kind, .swipe)
    XCTAssertEqual(rollback?.description, "Reverse the previous swipe")
    XCTAssertEqual(rollback?.parameters["from_x"], "10")
    XCTAssertEqual(rollback?.parameters["from_y"], "10")
    XCTAssertEqual(rollback?.parameters["to_x"], "10")
    XCTAssertEqual(rollback?.parameters["to_y"], "90")
    XCTAssertEqual(recovered.checkpoints.count, 1)
    XCTAssertEqual(recovered.checkpoints.first?.id, "checkpoint-swipe")
    XCTAssertEqual(recovered.actions[0].status, .pendingConfirmation)
    XCTAssertEqual(recovered.actions[0].result, "Execution was interrupted before verification")
    XCTAssertEqual(recovered.actions[0].evidence, "interrupted")
    XCTAssertEqual(recovered.actions[1].status, .pendingConfirmation)
    let marked = recovered.markCheckpoint("checkpoint-swipe", status: .restored)
    XCTAssertEqual(marked.checkpoints.first?.status, .restored)
  }

  func testAgentExecutionContinuityHistoryAndCheckpointCodecStayBackwardCompatible() throws {
    let history = (0..<45).map { index in
      AgentAction(
        id: "history-\(index)",
        kind: .callConnector,
        target: "Codex",
        risk: .low,
        status: .completed,
        description: "Historical action"
      )
    }
    let blocked = AgentAction(
      id: "blocked",
      kind: .callNativeTool,
      target: "tool",
      risk: .medium,
      status: .blocked,
      description: "Blocked"
    )
    let running = AgentAction(
      id: "running",
      kind: .callNativeTool,
      target: "tool",
      risk: .medium,
      status: .running,
      description: "Running"
    )
    var plan = lifecyclePlan(blocked, running)
    plan.actionHistory = history

    let retained = plan.historyForReplan()
    let legacy = try JSONDecoder().decode(
      AgentExecutionCheckpoint.self,
      from: Data(#"{"action_id":"connector","summary":"checkpoint","timestamp_millis":13}"#.utf8)
    )
    let fallback = try JSONDecoder().decode(
      AgentCheckpointStatus.self,
      from: Data(#""future""#.utf8)
    )

    XCTAssertEqual(retained.count, 40)
    XCTAssertEqual(retained.first?.id, "history-6")
    XCTAssertEqual(retained.last?.id, "blocked")
    XCTAssertFalse(retained.contains { $0.id == "running" })
    XCTAssertEqual(legacy.id, "checkpoint-connector-13")
    XCTAssertEqual(legacy.actionId, "connector")
    XCTAssertEqual(legacy.summary, "checkpoint")
    XCTAssertEqual(legacy.createdAtMillis, 13)
    XCTAssertEqual(legacy.timestampMillis, 13)
    XCTAssertEqual(legacy.status, .active)
    XCTAssertEqual(fallback, .active)
  }
}
