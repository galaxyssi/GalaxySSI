import XCTest
@testable import GalaxySSI

final class GlobalAutonomousActionGraphTests: XCTestCase {
  func testAuthorityStripsModelAuthoredEffectsFromHostLocalActions() {
    let proposed = action(
      "draft",
      kind: .draft,
      goal: "Prepare a reply",
      externalEffect: true,
      reversible: false,
      confirmationGranted: true,
      status: .waitingConfirmation
    )

    let prepared = GlobalAutonomousActionAuthorityPolicy.prepareProposal(proposed)

    XCTAssertEqual(prepared.status, .pending)
    XCTAssertFalse(prepared.externalEffect)
    XCTAssertTrue(prepared.reversible)
    XCTAssertFalse(prepared.confirmationGranted)
  }

  func testAuthorityLeavesToolRiskForRegisteredToolContract() {
    let proposed = action(
      "tool",
      kind: .invokeTool,
      goal: "Run native tool",
      toolId: "galaxyssi.test.echo",
      toolInputJson: #"{"query":"hello"}"#,
      externalEffect: true,
      reversible: false,
      confirmationGranted: true,
      status: .waitingConfirmation
    )

    let prepared = GlobalAutonomousActionAuthorityPolicy.prepareProposal(proposed)

    XCTAssertEqual(prepared.status, .pending)
    XCTAssertTrue(prepared.externalEffect)
    XCTAssertFalse(prepared.reversible)
    XCTAssertFalse(prepared.confirmationGranted)
  }

  func testRecoverPersistedOnlyNormalizesPendingNonToolActions() {
    let nonTool = action(
      "non-tool",
      kind: .draft,
      goal: "Draft",
      externalEffect: true,
      status: .waitingConfirmation
    )
    let tool = action(
      "tool",
      kind: .invokeTool,
      goal: "Run",
      confirmationGranted: true,
      status: .waitingConfirmation
    )

    XCTAssertFalse(GlobalAutonomousActionAuthorityPolicy.recoverPersisted(nonTool).externalEffect)
    XCTAssertTrue(GlobalAutonomousActionAuthorityPolicy.recoverPersisted(tool).confirmationGranted)
  }

  func testPrepareAssignsPlanKeysDedupesAndResolvesDependencies() {
    let collect = action("collect", kind: .readOnlyCheck, goal: "Collect facts", planKey: "collect")
    let duplicate = action("duplicate", kind: .draft, goal: "Duplicate key", planKey: "collect")
    let draft = action(
      "draft",
      kind: .draft,
      goal: "Draft answer",
      dependencyKeys: ["collect"]
    )

    let prepared = GlobalAutonomousActionGraphPolicy.prepare([collect, duplicate, draft])

    XCTAssertEqual(prepared.map(\.id), ["collect", "draft"])
    XCTAssertEqual(prepared.first { $0.id == "draft" }?.dependsOnActionIds, ["collect"])
    XCTAssertTrue(prepared.allSatisfy { !$0.planKey.isBlank })
  }

  func testPrepareSkipsUnknownDependencyAndCycles() {
    let unknown = GlobalAutonomousActionGraphPolicy.prepare([
      action("blocked", kind: .draft, goal: "Draft", dependencyKeys: ["missing"])
    ])

    XCTAssertEqual(unknown.singleValue().status, .skipped)
    XCTAssertTrue(unknown.singleValue().lastError.contains("Unknown prerequisite step"))

    let cycle = GlobalAutonomousActionGraphPolicy.prepare([
      action("a", kind: .draft, goal: "A", planKey: "a", dependencyKeys: ["b"]),
      action("b", kind: .draft, goal: "B", planKey: "b", dependencyKeys: ["a"])
    ])

    XCTAssertEqual(Set(cycle.map(\.status)), [.skipped])
    XCTAssertTrue(cycle.allSatisfy { $0.lastError.contains("cycle") })
  }

  func testResolveAgainstExistingActionsUsesExistingPlanKeys() {
    let existing = action("collect", kind: .readOnlyCheck, goal: "Collect", planKey: "collect", status: .completed)
    let proposed = action("draft", kind: .draft, goal: "Draft", dependencyKeys: ["collect"])

    let resolved = GlobalAutonomousActionGraphPolicy.resolveAgainst(
      existing: [existing],
      proposed: [proposed]
    )

    XCTAssertEqual(resolved.singleValue().dependsOnActionIds, ["collect"])
    XCTAssertNotEqual(resolved.singleValue().planKey, "")
  }

  func testReconcileSkipsActionsAfterFailedOrMissingPrerequisites() throws {
    let failed = action("failed", kind: .readOnlyCheck, goal: "Collect", status: .failed)
    let blocked = action(
      "blocked",
      kind: .draft,
      goal: "Draft",
      dependsOnActionIds: ["failed", "missing"],
      status: .pending
    )

    let reconciled = GlobalAutonomousActionGraphPolicy.reconcile([failed, blocked], nowMillis: 42)

    let result = try XCTUnwrap(reconciled.first { $0.id == "blocked" })
    XCTAssertEqual(result.status, .skipped)
    XCTAssertEqual(result.lastError, "A prerequisite step did not complete")
    XCTAssertEqual(result.completedAtMillis, 42)
  }

  func testReadyActionsAndReserveNextUseDependencyCompletionAndPriority() throws {
    let completed = action("collect", kind: .readOnlyCheck, goal: "Collect", status: .completed)
    let low = action(
      "low",
      kind: .draft,
      goal: "Low priority",
      dependsOnActionIds: ["collect"],
      priority: 0.2
    )
    let high = action(
      "high",
      kind: .draft,
      goal: "High priority",
      dependsOnActionIds: ["collect"],
      priority: 0.9
    )
    let blocked = action(
      "blocked",
      kind: .draft,
      goal: "Blocked",
      dependsOnActionIds: ["missing"],
      priority: 1
    )

    let ready = GlobalAutonomousActionGraphPolicy.readyActions([completed, low, high, blocked])
    let reservation = try XCTUnwrap(GlobalAutonomousActionGraphPolicy.reserveNext(
      actions: [completed, low, high, blocked],
      nowMillis: 100,
      leaseExpiresAtMillis: 500
    ))
    let reserved = try XCTUnwrap(reservation.actions.first { $0.id == "high" })

    XCTAssertEqual(ready.map(\.id), ["high", "low"])
    XCTAssertEqual(reservation.actionId, "high")
    XCTAssertEqual(reserved.status, .running)
    XCTAssertEqual(reserved.attemptCount, 1)
    XCTAssertEqual(reserved.leaseExpiresAtMillis, 500)
    XCTAssertEqual(reserved.startedAtMillis, 100)
  }

  private func action(
    _ id: String,
    kind: GlobalAutonomousActionKind,
    goal: String,
    planKey: String = "",
    dependencyKeys: Set<String> = [],
    dependsOnActionIds: Set<String> = [],
    toolId: String = "",
    toolInputJson: String = "",
    priority: Double = 0.5,
    externalEffect: Bool = false,
    reversible: Bool = true,
    confirmationGranted: Bool = false,
    status: GlobalAutonomousActionStatus = .pending
  ) -> GlobalAutonomousAction {
    GlobalAutonomousAction(
      id: id,
      planKey: planKey,
      dependencyKeys: dependencyKeys,
      dependsOnActionIds: dependsOnActionIds,
      kind: kind,
      goal: goal,
      toolId: toolId,
      toolInputJson: toolInputJson,
      priority: priority,
      externalEffect: externalEffect,
      reversible: reversible,
      confirmationGranted: confirmationGranted,
      status: status
    )
  }
}

private extension Array {
  func singleValue(file: StaticString = #filePath, line: UInt = #line) -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    return self[0]
  }
}
