import XCTest
@testable import GalaxySSI

final class AgentTurnReceiptTests: XCTestCase {
  typealias Store = AgentTurnReceiptStore
  private let key = Store.Key(owner: "owner", conversation: "chat", turn: "turn")

  func testFirstVisibleUsesOnlySameProcessMonotonicTimeAndIsOneShot() throws {
    let store = try fixture()
    store.begin(key, choice: .init(), wall: 10_000, uptime: 1_000_000)
    store.visible(key, wall: 2_000, uptime: 6_000_000)
    store.visible(key, wall: 90_000, uptime: 99_000_000)
    XCTAssertEqual(store.read(key)?.sent, 10_000)
    XCTAssertEqual(store.read(key)?.body, 2_000)
    XCTAssertEqual(store.read(key)?.bodyMillis, 5)
    XCTAssertFalse(store.shouldObserve(key))
  }

  func testReopenedOrInvalidatedLiveClockCannotFabricateElapsedTime() throws {
    let store = try fixture()
    store.begin(key, choice: .init(), wall: 1, uptime: 10_000)
    store.visible(key, wall: 2, uptime: 9_000)
    XCTAssertNil(store.read(key)?.body)
    store.invalidateLive()
    store.begin(key, choice: .init(), wall: 3, uptime: 1)
    store.visible(key, wall: 4, uptime: 100_000)
    XCTAssertNil(store.read(key)?.bodyMillis)
  }

  func testRowsAndKeysAreOwnerConversationAndTurnScopedAndEncrypted() throws {
    let suite = "turn-receipt-fixture-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)), secrets = InMemorySecretStore()
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = Store(defaults: defaults, secrets: secrets)
    store.begin(key, choice: .init(mode: .manual, modelId: "fixture-model"), wall: 1, uptime: 1)
    XCTAssertNil(defaults.object(forKey: key.row))
    let bytes = try XCTUnwrap(defaults.data(forKey: key.row + ".encrypted.v1"))
    XCTAssertNil(bytes.range(of: Data("fixture-model".utf8)))
    let reopened = Store(defaults: defaults, secrets: secrets)
    XCTAssertEqual(reopened.read(key)?.requested, "fixture-model")
    XCTAssertNil(reopened.read(.init(owner: "other", conversation: "chat", turn: "turn")))
    XCTAssertNil(reopened.read(.init(owner: "owner", conversation: "other", turn: "turn")))
    XCTAssertNil(reopened.read(.init(owner: "owner", conversation: "chat", turn: "other")))
    reopened.visible(key, wall: 2, uptime: 1_000_000)
    XCTAssertNil(reopened.read(key)?.body)
  }

  func testIdentifierFilterRejectsProseSecretsAndTrailingNewlines() {
    for value in ["", "private words", "model\n", "model\r\n", String(repeating: "x", count: 121)] {
      XCTAssertEqual(AgentTurnReceiptEvidence.identifier(value), "")
    }
    XCTAssertEqual(AgentTurnReceiptEvidence.identifier("provider/model-v2:latest"), "provider/model-v2:latest")
    XCTAssertEqual(AgentTurnReceiptEvidence.identifier(123), "")
  }

  func testDesktopSubmissionNeedsExactEventTaskGenerationAndBoundedFields() throws {
    var p = payload(generation: 2, attempt: 3)
    var evidence = try XCTUnwrap(AgentTurnReceiptEvidence.desktop(p))
    XCTAssertEqual(evidence.attempt, 3)
    XCTAssertEqual(evidence.provider, "codex")
    XCTAssertEqual(evidence.model, "submitted-model")
    p["execution_generation"] = true
    XCTAssertNil(AgentTurnReceiptEvidence.desktop(p))
    p = payload(generation: 2, attempt: 3)
    p["events"] = [["kind": "model", "event_id": "provider:other:2", "metadata": [
      "attempt": 3, "execution_generation": 2, "provider": "codex", "model": "wrong"]]]
    evidence = try XCTUnwrap(AgentTurnReceiptEvidence.desktop(p))
    XCTAssertEqual(evidence.attempt, 0)
    XCTAssertEqual(evidence.model, "")
  }

  func testTerminalReplayUsesCurrentGenerationSubmissionAndKeepsActualUnknown() throws {
    var p = payload(generation: 2, attempt: 1)
    p["type"] = "text"
    p["turn_receipt"] = ["generation": 2, "desktop_received_at": 22, "submission": [
      "attempt": 3, "provider": "codex", "model": "replayed-model", "effort": "high"]]
    let evidence = try XCTUnwrap(AgentTurnReceiptEvidence.desktop(p))
    XCTAssertEqual(evidence.attempt, 3)
    XCTAssertEqual(evidence.model, "replayed-model")
    XCTAssertTrue(evidence.terminal)
    let store = try fixture(); store.begin(key, choice: .init(), wall: 1, uptime: 1)
    store.outbound(key, task: "task", model: "requested-model", effort: "low")
    store.authenticated(key, payload: p, wall: 50)
    XCTAssertEqual(store.read(key)?.wire, "requested-model")
    XCTAssertEqual(store.read(key)?.submitted, "replayed-model")
    XCTAssertNil(store.read(key)?.cloudActual)
    XCTAssertEqual(store.read(key)?.resultAt, 50)
  }

  func testStaleDesktopAttemptsGenerationsAndForeignTasksCannotOverwriteCurrent() throws {
    let store = try fixture(); store.begin(key, choice: .init(), wall: 1, uptime: 1)
    store.outbound(key, task: "task", model: "requested", effort: "auto")
    store.authenticated(key, payload: payload(generation: 3, attempt: 4))
    store.authenticated(key, payload: payload(generation: 2, attempt: 9))
    store.authenticated(key, payload: payload(generation: 3, attempt: 1))
    XCTAssertEqual(store.read(key)?.generation, 3)
    XCTAssertEqual(store.read(key)?.attempt, 4)
    var foreign = payload(generation: 9, attempt: 9); foreign["task_id"] = "other"
    store.authenticated(key, payload: foreign)
    XCTAssertEqual(store.read(key)?.generation, 3)
    store.outbound(key, task: "new-task", model: "new-request", effort: "auto")
    XCTAssertNil(store.read(key)?.submitted)
    XCTAssertNil(store.read(key)?.resultAt)
  }

  func testCloudResponseIsAttemptScopedAndDoesNotInferModelOrEffort() throws {
    let store = try fixture(); store.begin(key, choice: .init(), wall: 1, uptime: 1)
    let old = store.cloudStarted(key, model: "requested-A")
    let current = store.cloudStarted(key, model: "requested-B")
    store.cloudResponse(key, attempt: old, actual: "stale")
    XCTAssertNil(store.read(key)?.cloudActual)
    store.cloudResponse(key, attempt: current, actual: "reported-B")
    XCTAssertEqual(store.read(key)?.cloudActual, "reported-B")
    XCTAssertEqual(store.read(key)?.cloudEffort, "")
    store.cloudResponse(key, attempt: current, actual: nil)
    XCTAssertEqual(store.read(key)?.cloudActual, "")
  }

  func testDeleteAndClearRejectLateCallbacksAndDoNotRecreateOldRows() throws {
    let store = try fixture(); store.begin(key, choice: .init(), wall: 1, uptime: 1)
    let attempt = store.cloudStarted(key, model: "model")
    store.delete(owner: key.owner, conversation: key.conversation)
    store.cloudResponse(key, attempt: attempt, actual: "late")
    store.begin(key, choice: .init(), wall: 2, uptime: 2)
    XCTAssertNil(store.read(key))
    store.clear()
    store.cloudResponse(key, attempt: attempt, actual: "late-after-clear")
    XCTAssertNil(store.read(key))
  }

  func testToolDeviceNeedsSuccessfulNonReplayedExactInvocationAndProvenance() throws {
    let store = try fixture(); store.begin(key, choice: .init(), wall: 1, uptime: 1)
    let context = AgentNativeToolInvocationContext(invocationId: "invocation", conversationId: key.conversation, turnId: key.turn)
    var result = nativeResult()
    result.receipt.replayed = true
    store.toolFinished(key, context: context, tool: "fixture.tool", result: result)
    XCTAssertNil(store.read(key)?.phoneExecuted)
    result.receipt.replayed = false; result.receipt.invocationId = "other"
    store.toolFinished(key, context: context, tool: "fixture.tool", result: result)
    XCTAssertNil(store.read(key)?.phoneExecuted)
    result.receipt.invocationId = "invocation"
    result.status = .failed
    store.toolFinished(key, context: context, tool: "fixture.tool", result: result)
    XCTAssertNil(store.read(key)?.phoneExecuted)
    result.status = .succeeded
    store.toolFinished(key, context: context, tool: "different.tool", result: result)
    XCTAssertNil(store.read(key)?.phoneExecuted)
    store.toolFinished(key, context: context, tool: "fixture.tool", result: result)
    XCTAssertEqual(store.read(key)?.phoneExecuted, true)
    result.provenance.location = .desktop
    store.toolFinished(key, context: context, tool: "fixture.tool", result: result)
    XCTAssertEqual(store.read(key)?.desktopExecuted, true)
  }

  func testBodyPolicyExcludesUsersFailuresControlPayloadsAndCitationPreviews() {
    let body = ChatMessage(contactId: "hermes", content: "Actual reply", isMine: false, conversationId: "chat", turnId: "turn")
    XCTAssertTrue(AgentTurnReceiptBodyPolicy.eligible(body))
    var candidate = body; candidate.isMine = true
    XCTAssertFalse(AgentTurnReceiptBodyPolicy.eligible(candidate))
    candidate = body; candidate.isSystem = true
    XCTAssertFalse(AgentTurnReceiptBodyPolicy.eligible(candidate))
    candidate = body; candidate.remoteMessageId = "agent-stream-preview-fixture"
    XCTAssertFalse(AgentTurnReceiptBodyPolicy.eligible(candidate))
    candidate = body; candidate.deliveryStatus = .failed
    XCTAssertFalse(AgentTurnReceiptBodyPolicy.eligible(candidate))
    candidate = body; candidate.content = #"{"execution_location":"phone","actions":[]}"#
    XCTAssertFalse(AgentTurnReceiptBodyPolicy.eligible(candidate))
  }

  private func payload(generation: Int, attempt: Int) -> [String: Any] {
    ["type": "agent_task_event", "task_id": "task", "conversation_id": "chat", "turn_id": "turn", "execution_generation": generation,
     "events": [["kind": "model", "event_id": "provider:task:\(attempt - 1)", "metadata": [
      "attempt": attempt, "execution_generation": generation, "provider": "codex", "model": "submitted-model", "reasoning_effort": "high"]]]]
  }
  private func nativeResult() -> AgentNativeToolResult {
    .init(status: .succeeded, output: [:], message: "Fixture", receipt: .init(invocationId: "invocation",
      startedAtEpochMillis: 1, finishedAtEpochMillis: 2, durationMillis: 1, status: .succeeded, inputSha256: "", outputSha256: ""),
      provenance: .init(toolId: "fixture.tool", toolVersion: "1", location: .phone, executorId: "fixture", contractVersion: "1"))
  }
  private func fixture() throws -> Store {
    let suite = "turn-receipt-fixture-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
    return Store(defaults: defaults, secrets: InMemorySecretStore())
  }
}
