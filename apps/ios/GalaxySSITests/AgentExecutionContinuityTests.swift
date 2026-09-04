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

  func testAgentLongTaskHistoryUsesEncryptedBoundedPagesAndRestoresAfterRestart() throws {
    let suiteName = "AgentLongTaskHistoryTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let secrets = InMemorySecretStore()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let actions = (0..<1_100).map { index in
      AgentAction(
        id: "action-\(index)",
        kind: .callNativeTool,
        target: "workspace.read",
        risk: .low,
        status: .completed,
        description: "Read workspace item \(index)",
        requiresConfirmation: false,
        result: "done-\(index)",
        evidence: "evidence-\(index)"
      )
    }
    let checkpoints = (0..<140).map { index in
      AgentExecutionCheckpoint(
        id: "checkpoint-\(index)",
        actionId: "action-\(index)",
        planRevision: 1,
        createdAtMillis: Int64(index)
      )
    }
    var plan = lifecyclePlan()
    plan.actionHistory = actions
    plan.checkpoints = checkpoints
    let record = AgentTaskRecord(
      taskId: "long-task",
      sessionId: "session",
      goal: "Complete a long project",
      phase: .executing,
      routeKind: .unknown,
      targetTitle: "Phone",
      risk: .low,
      blocked: false,
      activePlan: plan
    )
    let persistence = AgentTaskHistoryPersistence(defaults: defaults, secrets: secrets)

    let transaction = try persistence.prepare(records: [record])
    persistence.commit(transaction)

    let manifest = try XCTUnwrap(persistence.manifest(taskId: record.taskId))
    XCTAssertEqual(manifest.actionCount, AgentLongTaskPersistenceLimits.maximumActions)
    XCTAssertEqual(manifest.checkpointCount, AgentLongTaskPersistenceLimits.maximumCheckpoints)
    XCTAssertTrue(manifest.actionPageItemCounts.allSatisfy { $0 <= 32 })
    XCTAssertTrue(manifest.checkpointPageItemCounts.allSatisfy { $0 <= 32 })
    XCTAssertEqual(transaction.rootRecords.first?.activePlan?.actionHistory.count, 40)
    XCTAssertEqual(transaction.rootRecords.first?.activePlan?.checkpoints.count, 16)

    let pagedActions = manifest.actionPageIds.indices.flatMap { pageIndex in
      persistence.actionPage(taskId: record.taskId, pageIndex: pageIndex).items
    }
    let pagedCheckpoints = manifest.checkpointPageIds.indices.flatMap { pageIndex in
      persistence.checkpointPage(taskId: record.taskId, pageIndex: pageIndex).items
    }
    XCTAssertEqual(pagedActions.first?.id, "action-76")
    XCTAssertEqual(pagedActions.last?.id, "action-1099")
    XCTAssertEqual(pagedCheckpoints.first?.id, "checkpoint-12")
    XCTAssertEqual(pagedCheckpoints.last?.id, "checkpoint-139")

    let restarted = AgentTaskHistoryPersistence(defaults: defaults, secrets: secrets)
    let restored = try XCTUnwrap(restarted.restore(transaction.rootRecords).first)
    XCTAssertEqual(restored.activePlan?.actionHistory.count, 1_024)
    XCTAssertEqual(restored.activePlan?.checkpoints.count, 128)
  }

  func testAgentLongTaskHistoryCompactsOversizedTextAndRejectsMissingPages() throws {
    let suiteName = "AgentLongTaskHistoryCompactionTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let secrets = InMemorySecretStore()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let oversized = String(repeating: "escaped-\\\"", count: 12_000)
    var plan = lifecyclePlan()
    plan.actionHistory = [
      AgentAction(
        id: "oversized",
        kind: .callNativeTool,
        target: "workspace.read",
        risk: .low,
        status: .completed,
        description: oversized,
        result: oversized,
        evidence: oversized
      )
    ]
    let record = AgentTaskRecord(
      taskId: "oversized-task",
      sessionId: "session",
      goal: "Persist safely",
      phase: .executing,
      routeKind: .unknown,
      targetTitle: "Phone",
      risk: .low,
      blocked: false,
      activePlan: plan
    )
    let persistence = AgentTaskHistoryPersistence(defaults: defaults, secrets: secrets)
    let transaction = try persistence.prepare(records: [record])
    persistence.commit(transaction)

    let page = persistence.actionPage(taskId: record.taskId, pageIndex: 0)
    XCTAssertTrue(page.available)
    XCTAssertEqual(page.items.count, 1)
    XCTAssertFalse(page.items[0].result.isEmpty)
    XCTAssertLessThanOrEqual(page.items[0].result.count, 1_024)

    let missingManifest = AgentSessionHistoryManifest(
      sessionId: "session",
      actionPageIds: [String(repeating: "0", count: 64)],
      actionPageItemCounts: [1],
      checkpointPageIds: [],
      checkpointPageItemCounts: []
    )
    var missingRecord = record
    missingRecord.historyManifest = missingManifest
    let missingStore = AgentTaskHistoryPersistence(defaults: defaults, secrets: secrets)
    _ = missingStore.restore([missingRecord])
    let missingPage = missingStore.actionPage(taskId: record.taskId, pageIndex: 0)
    XCTAssertFalse(missingPage.available)
    XCTAssertTrue(missingPage.items.isEmpty)
  }

  func testAgentExecutionContinuityRetainsLatest128Checkpoints() {
    var plan = lifecyclePlan()
    for index in 0..<140 {
      plan = plan.addCheckpoint(
        AgentExecutionCheckpoint(
          id: "checkpoint-\(index)",
          actionId: "action-\(index)",
          createdAtMillis: Int64(index)
        )
      )
    }

    XCTAssertEqual(plan.checkpoints.count, AgentLongTaskPersistenceLimits.maximumCheckpoints)
    XCTAssertEqual(plan.checkpoints.first?.id, "checkpoint-12")
    XCTAssertEqual(plan.checkpoints.last?.id, "checkpoint-139")
  }
}
