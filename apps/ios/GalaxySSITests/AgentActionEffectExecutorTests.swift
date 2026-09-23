import XCTest
@testable import GalaxySSI

final class AgentActionEffectExecutorTests: XCTestCase {
  private let screen = AgentScreenContext(foregroundApp: "Test", pageTitle: "Action recovery")

  func testCompletedActionReplaysWithoutDispatchingAgain() {
    let store = InMemoryAgentNativeToolReplayStore()
    let executor = AgentActionEffectExecutor(store: store)
    let delegate = CountingActionExecutor { action, _ in
      AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Accepted",
        metadata: ["awaiting_response": "true", "request_id": "request-1"]
      )
    }

    let first = executor.execute(
      action: action,
      screen: screen,
      context: context(invocationId: "first"),
      delegate: delegate
    )
    let replay = executor.execute(
      action: action,
      screen: AgentScreenContext(foregroundApp: "Other", pageTitle: "Changed"),
      context: context(invocationId: "recovery"),
      delegate: delegate
    )

    XCTAssertEqual(first.message, replay.message)
    XCTAssertEqual(replay.metadata["request_id"], "request-1")
    XCTAssertEqual(replay.metadata["action_effect_replayed"], "true")
    XCTAssertEqual(delegate.callCount, 1)
  }

  func testLostOutcomeIsNotDispatchedAgain() {
    let backing = InMemoryAgentNativeToolReplayStore()
    let faulty = FailingCompletionReplayStore(backing: backing)
    let delegate = CountingActionExecutor { action, _ in
      AgentActionResult(actionId: action.id, success: true, message: "Written")
    }

    let first = AgentActionEffectExecutor(store: faulty).execute(
      action: action,
      screen: screen,
      context: context(invocationId: "first"),
      delegate: delegate
    )
    let recovered = AgentActionEffectExecutor(store: backing).execute(
      action: action,
      screen: screen,
      context: context(invocationId: "recovery"),
      delegate: delegate
    )

    XCTAssertEqual(first.metadata["error_code"], "effect_outcome_unknown")
    XCTAssertEqual(recovered.metadata["error_code"], "effect_outcome_unknown")
    XCTAssertEqual(delegate.callCount, 1)
  }

  func testChangedInputCannotReuseActionIdentity() {
    let executor = AgentActionEffectExecutor(store: InMemoryAgentNativeToolReplayStore())
    let delegate = CountingActionExecutor { action, _ in
      AgentActionResult(actionId: action.id, success: true, message: "Done")
    }
    _ = executor.execute(
      action: action,
      screen: screen,
      context: context(invocationId: "first"),
      delegate: delegate
    )
    var changed = action
    changed.parameters["prompt"] = "different"

    let result = executor.execute(
      action: changed,
      screen: screen,
      context: context(invocationId: "changed"),
      delegate: delegate
    )

    XCTAssertEqual(result.metadata["error_code"], "idempotency_key_conflict")
    XCTAssertEqual(delegate.callCount, 1)
  }

  func testScreenReadsRemainFresh() {
    let executor = AgentActionEffectExecutor(store: InMemoryAgentNativeToolReplayStore())
    let delegate = CountingActionExecutor { action, _ in
      AgentActionResult(actionId: action.id, success: true, message: "fresh")
    }
    var read = action
    read.kind = .readScreen

    _ = executor.execute(action: read, screen: screen, context: context(invocationId: "one"), delegate: delegate)
    _ = executor.execute(action: read, screen: screen, context: context(invocationId: "two"), delegate: delegate)

    XCTAssertEqual(delegate.callCount, 2)
  }

  func testConnectorFallbackAttemptsUseIndependentReceipts() {
    let store = InMemoryAgentNativeToolReplayStore()
    let executor = AgentActionEffectExecutor(store: store)
    var primary = action
    primary.parameters["connector_id"] = "codex"
    let selection = AgentConnectorFallbackSelection(
      resourceId: "cloud",
      remainingResourceIds: [],
      deferredRetryIds: ["codex"],
      retriedResourceIds: [],
      attemptedResourceIds: ["codex"]
    )
    let fallback = AgentConnectorFallbackAction.prepare(action: primary, selection: selection, target: nil)
    let delegate = CountingActionExecutor { action, _ in
      AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Accepted",
        metadata: ["connector_id": action.parameters["connector_id"] ?? ""]
      )
    }

    let primaryResult = executor.execute(
      action: primary,
      screen: screen,
      context: context(invocationId: "primary"),
      delegate: delegate
    )
    let fallbackResult = executor.execute(
      action: fallback,
      screen: screen,
      context: context(invocationId: "fallback"),
      delegate: delegate
    )
    let restored = AgentActionEffectExecutor(store: store).execute(
      action: fallback,
      screen: screen,
      context: context(invocationId: "restored"),
      delegate: delegate
    )

    XCTAssertEqual(primaryResult.metadata["connector_id"], "codex")
    XCTAssertEqual(fallbackResult.metadata["connector_id"], "cloud")
    XCTAssertEqual(restored.metadata["connector_id"], "cloud")
    XCTAssertEqual(restored.metadata["action_effect_replayed"], "true")
    XCTAssertEqual(delegate.callCount, 2)
  }

  func testConnectorHandoffRecoveryUsesIndependentInspectableReceipt() throws {
    let store = InMemoryAgentNativeToolReplayStore()
    let executor = AgentActionEffectExecutor(store: store)
    let recovery = try XCTUnwrap(AgentConnectorHandoffRecovery.prepare(
      action: action,
      sourceMessageId: 123,
      attempt: 1,
      sessionId: "session"
    ))
    let delegate = CountingActionExecutor { action, _ in
      AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Accepted",
        metadata: ["awaiting_response": "true", "source_message_id": "123"]
      )
    }

    _ = executor.execute(action: action, screen: screen, context: context(invocationId: "primary"), delegate: delegate)
    _ = executor.execute(action: recovery, screen: screen, context: context(invocationId: "recovery"), delegate: delegate)
    let observed = executor.dispatchedResult(action: recovery, context: context(invocationId: "inspect"))

    XCTAssertNotEqual(
      AgentConnectorHandoffRecovery.effectAttemptKey(action),
      AgentConnectorHandoffRecovery.effectAttemptKey(recovery)
    )
    XCTAssertEqual(observed?.metadata["source_message_id"], "123")
    XCTAssertEqual(observed?.metadata["action_effect_replayed"], "true")
    XCTAssertNil(executor.dispatchedResult(
      action: recovery,
      context: AgentNativeToolInvocationContext(
        invocationId: "other",
        sessionId: "session",
        conversationId: "other",
        turnId: "turn"
      )
    ))
    XCTAssertEqual(delegate.callCount, 2)
  }

  func testConnectorHandoffRecoveryRecognizesRemoteOwnership() {
    XCTAssertTrue(AgentConnectorHandoffRecovery.requiresRemoteObservation(metadata: [:], hasDesktopBinding: true))
    XCTAssertTrue(AgentConnectorHandoffRecovery.requiresRemoteObservation(
      metadata: ["remote_task_status": "running"],
      hasDesktopBinding: false
    ))
    XCTAssertFalse(AgentConnectorHandoffRecovery.requiresRemoteObservation(metadata: [:], hasDesktopBinding: false))
  }

  private var action: AgentAction {
    AgentAction(
      id: "action-1",
      kind: .callConnector,
      target: "test-connector",
      risk: .low,
      status: .running,
      description: "Test request",
      parameters: ["prompt": "hello"],
      requiresConfirmation: false
    )
  }

  private func context(invocationId: String) -> AgentNativeToolInvocationContext {
    AgentNativeToolInvocationContext(
      invocationId: invocationId,
      sessionId: "session",
      conversationId: "conversation",
      turnId: "turn",
      attributes: [
        "client_route_id": "device",
        "task_id": "task",
        "goal_id": "goal"
      ]
    )
  }
}

private final class CountingActionExecutor: AgentActionExecutor {
  private let operation: (AgentAction, AgentScreenContext) -> AgentActionResult
  private(set) var callCount = 0

  init(operation: @escaping (AgentAction, AgentScreenContext) -> AgentActionResult) {
    self.operation = operation
  }

  func execute(action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
    callCount += 1
    return operation(action, screen)
  }
}

private final class FailingCompletionReplayStore: AgentNativeToolReplayStore {
  private let backing: AgentNativeToolReplayStore

  init(backing: AgentNativeToolReplayStore) {
    self.backing = backing
  }

  func get(_ key: AgentNativeToolReplayKey) -> AgentNativeToolResult? {
    backing.get(key)
  }

  func observe(_ key: AgentNativeToolReplayKey) -> AgentNativeEffectClaim? {
    backing.observe(key)
  }

  func claim(
    _ key: AgentNativeToolReplayKey,
    inputSha256: String,
    invocationId: String
  ) throws -> AgentNativeEffectClaim {
    try backing.claim(key, inputSha256: inputSha256, invocationId: invocationId)
  }

  func complete(
    _ key: AgentNativeToolReplayKey,
    invocationId: String,
    result: AgentNativeToolResult
  ) throws {
    throw TestError.interruptedCommit
  }

  func put(_ key: AgentNativeToolReplayKey, result: AgentNativeToolResult) throws {
    try backing.put(key, result: result)
  }

  func clear() {
    backing.clear()
  }

  private enum TestError: Error {
    case interruptedCommit
  }
}
