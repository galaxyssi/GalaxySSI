import XCTest
@testable import GalaxySSI

final class CloudToolInvocationJournalTests: XCTestCase {
  private func binding() -> CloudToolInvocationJournal.Binding {
    .init(owner: "synthetic-owner", contactID: "synthetic-model", conversationID: "conversation",
      turnID: "turn", requestID: "request", round: 0, slot: 0,
      requestSHA256: String(repeating: "a", count: 64), collaborationOwner: nil)
  }
  private func call() -> AssembledToolCall {
    .init(callId: "call", index: 0, name: "synthetic_tool", argumentsJson: "{\"value\":1}")
  }

  func testCompletedResultReplaysWithoutExecutingAgain() async throws {
    let runtime = CloudToolInvocationJournal(journal: InMemoryAgentModelLoopJournal())
    var executions = 0, replays = 0
    for index in 0..<2 {
      let result = try await runtime.execute(binding: binding(), call: call(), validateOwner: {},
        restoreResult: { _ in replays += 1 }) { executions += 1; return "saved result" }
      XCTAssertEqual(result.output, "saved result")
      XCTAssertEqual(result.replayed, index == 1)
    }
    XCTAssertEqual(executions, 1)
    XCTAssertEqual(replays, 1)
  }

  func testChangedArgumentsDoNotCreateANewClaimForTheSameSlot() async throws {
    let runtime = CloudToolInvocationJournal(journal: InMemoryAgentModelLoopJournal())
    _ = try await runtime.execute(binding: binding(), call: call(), validateOwner: {}) { "saved" }
    var changed = call()
    changed.argumentsJson = "{\"value\":2}"
    var executions = 0
    do {
      _ = try await runtime.execute(binding: binding(), call: changed, validateOwner: {}) { executions += 1; return "new" }
      XCTFail("Changed input was accepted")
    } catch { XCTAssertEqual((error as? AgentModelLoopRecoveryError)?.code, "cloud_tool_input_changed") }
    XCTAssertEqual(executions, 0)
  }

  func testChangedProviderRequestCannotReuseTheSameSlot() async throws {
    let runtime = CloudToolInvocationJournal(journal: InMemoryAgentModelLoopJournal())
    _ = try await runtime.execute(binding: binding(), call: call(), validateOwner: {}) { "saved" }
    var changed = binding()
    changed.requestSHA256 = String(repeating: "b", count: 64)
    XCTAssertEqual(changed.scope, binding().scope)
    do {
      _ = try await runtime.execute(binding: changed, call: call(), validateOwner: {}) { XCTFail("Unexpected execution"); return "new" }
      XCTFail("Changed provider request was accepted")
    } catch { XCTAssertEqual((error as? AgentModelLoopRecoveryError)?.code, "cloud_tool_input_changed") }
  }

  func testThrownOperationLeavesAnUncertainClaim() async throws {
    let runtime = CloudToolInvocationJournal(journal: InMemoryAgentModelLoopJournal())
    var executions = 0
    for _ in 0..<2 {
      do {
        _ = try await runtime.execute(binding: binding(), call: call(), validateOwner: {}) {
          executions += 1
          throw SyntheticFailure.injected
        }
        XCTFail("Uncertain operation completed")
      } catch { XCTAssertEqual((error as? AgentModelLoopRecoveryError)?.code, "cloud_tool_outcome_unknown") }
    }
    XCTAssertEqual(executions, 1)
  }

  func testFailedClaimWritePreventsExecutionAndCanRetryOnlyWhenNoClaimWasSaved() async throws {
    let journal = FaultJournal(operation: "cloud-tool-input")
    let runtime = CloudToolInvocationJournal(journal: journal)
    var executions = 0
    do {
      _ = try await runtime.execute(binding: binding(), call: call(), validateOwner: {}) { executions += 1; return "saved" }
      XCTFail("Claim write failure was ignored")
    } catch {}
    XCTAssertEqual(executions, 0)
    journal.failedOperation = nil
    _ = try await runtime.execute(binding: binding(), call: call(), validateOwner: {}) { executions += 1; return "saved" }
    XCTAssertEqual(executions, 1)
  }

  func testAmbiguousClaimWriteDoesNotAuthorizeExecutionOrReplay() async throws {
    let journal = FaultJournal(operation: "cloud-tool-input", afterWrite: true)
    let runtime = CloudToolInvocationJournal(journal: journal)
    var executions = 0
    do {
      _ = try await runtime.execute(binding: binding(), call: call(), validateOwner: {}) { executions += 1; return "saved" }
      XCTFail("Ambiguous write was ignored")
    } catch {}
    journal.failedOperation = nil
    do {
      _ = try await runtime.execute(binding: binding(), call: call(), validateOwner: {}) { executions += 1; return "saved" }
      XCTFail("Ambiguous claim replayed")
    } catch { XCTAssertEqual((error as? AgentModelLoopRecoveryError)?.code, "cloud_tool_outcome_unknown") }
    XCTAssertEqual(executions, 0)
  }

  func testFailedResultWriteRetainsTheOriginalClaim() async throws {
    let journal = FaultJournal(operation: "cloud-tool-result")
    let runtime = CloudToolInvocationJournal(journal: journal)
    var executions = 0
    do {
      _ = try await runtime.execute(binding: binding(), call: call(), validateOwner: {}) { executions += 1; return "saved" }
      XCTFail("Result write failure was ignored")
    } catch {}
    journal.failedOperation = nil
    do {
      _ = try await runtime.execute(binding: binding(), call: call(), validateOwner: {}) { executions += 1; return "new" }
      XCTFail("Missing result replayed")
    } catch { XCTAssertEqual((error as? AgentModelLoopRecoveryError)?.code, "cloud_tool_outcome_unknown") }
    XCTAssertEqual(executions, 1)
  }

  func testLeaseRejectsAConcurrentDuplicateWithoutRunningIt() async throws {
    let runtime = CloudToolInvocationJournal(journal: InMemoryAgentModelLoopJournal())
    var duplicateExecutions = 0
    _ = try await runtime.execute(binding: binding(), call: call(), validateOwner: {}) {
      do {
        _ = try await runtime.execute(binding: self.binding(), call: self.call(), validateOwner: {}) {
          duplicateExecutions += 1; return "duplicate"
        }
        XCTFail("Duplicate lease was admitted")
      } catch { XCTAssertEqual((error as? AgentModelLoopRecoveryError)?.code, "model_loop_busy") }
      return "saved"
    }
    XCTAssertEqual(duplicateExecutions, 0)
  }

  func testDistinctOwnersRequestsRoundsAndSlotsHaveDistinctScopes() {
    let original = binding()
    for variation in 0..<7 {
      var changed = original
      if variation == 0 { changed.owner = "other-owner" }
      if variation == 1 { changed.requestID = "other-request" }
      if variation == 2 { changed.turnID = "other-turn" }
      if variation == 3 { changed.conversationID = "other-conversation" }
      if variation == 4 { changed.contactID = "other-contact" }
      if variation == 5 { changed.round += 1 }
      if variation == 6 { changed.slot += 1 }
      XCTAssertNotEqual(changed.scope, original.scope)
    }
  }

  func testRejectedOwnerCannotClaimOrExecute() async throws {
    let journal = FaultJournal(operation: nil)
    let runtime = CloudToolInvocationJournal(journal: journal)
    do {
      _ = try await runtime.execute(binding: binding(), call: call(), validateOwner: { throw SyntheticFailure.injected }) {
        XCTFail("Rejected owner executed"); return "new"
      }
      XCTFail("Rejected owner was admitted")
    } catch {}
    XCTAssertEqual(journal.writes, 0)
  }

  func testResultIsSavedBeforeRejectingALateOwnerChange() async throws {
    let runtime = CloudToolInvocationJournal(journal: InMemoryAgentModelLoopJournal())
    var current = true, executions = 0
    do {
      _ = try await runtime.execute(binding: binding(), call: call(), validateOwner: {
        if !current { throw SyntheticFailure.injected }
      }) { current = false; executions += 1; return "saved" }
      XCTFail("Stale result was delivered")
    } catch {}
    current = true
    let result = try await runtime.execute(binding: binding(), call: call(), validateOwner: {}) {
      executions += 1; return "new"
    }
    XCTAssertEqual(result.output, "saved")
    XCTAssertEqual(executions, 1)
  }

  func testFailedArtifactRestorationDoesNotRerunTheTool() async throws {
    let runtime = CloudToolInvocationJournal(journal: InMemoryAgentModelLoopJournal())
    var executions = 0
    _ = try await runtime.execute(binding: binding(), call: call(), validateOwner: {}) { executions += 1; return "saved" }
    do {
      _ = try await runtime.execute(binding: binding(), call: call(), validateOwner: {},
        restoreResult: { _ in throw SyntheticFailure.injected }) { executions += 1; return "new" }
      XCTFail("Missing artifact was ignored")
    } catch {}
    XCTAssertEqual(executions, 1)
  }

  func testEncryptedReopenRetainsTheCompletedResult() async throws {
    let domain = "cloud-tool-fixture-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let secrets = InMemorySecretStore()
    let first = CloudToolInvocationJournal(journal: EncryptedAgentModelLoopJournal(defaults: defaults, secrets: secrets))
    _ = try await first.execute(binding: binding(), call: call(), validateOwner: {}) { "saved" }
    let reopened = CloudToolInvocationJournal(journal: EncryptedAgentModelLoopJournal(defaults: defaults, secrets: secrets))
    let result = try await reopened.execute(binding: binding(), call: call(), validateOwner: {}) {
      XCTFail("Completed tool replayed after reopen"); return "new"
    }
    XCTAssertEqual(result.output, "saved")
  }

  func testReplayedPublicationCannotClaimANewExecution() throws {
    let output = CloudConversationStreamEngine.replayedToolOutput(
      "{\"status\":\"recorded\",\"replayed\":false,\"new_execution\":true}",
      toolName: CloudModelStreamMutableConversation.collaborationPublishName)
    let receipt = try CloudModelStreamJSON.mcpObject(from: output)
    XCTAssertEqual(receipt["status"], .string("recorded"))
    XCTAssertEqual(receipt["replayed"], .bool(true))
    XCTAssertEqual(receipt["new_execution"], .bool(false))
    XCTAssertEqual(receipt["galaxyssi_cloud_invocation"]?.objectValue?["fresh_observation"], .bool(false))
  }

  func testInvalidAnnotationReplayCannotCreateAnArtifact() {
    let context = CloudConversationToolExecutionContext(requestId: "fixture", conversationId: "conversation", turnId: "turn")
    XCTAssertThrowsError(try CloudImageAnnotationSession.restoreResult(
      "{\"tool\":\"untrusted\",\"image_saved\":true,\"image_index\":0,\"image_sha256\":\"../invalid\"}", context: context))
  }

  private enum SyntheticFailure: Error { case injected }
  private final class FaultJournal: AgentModelLoopJournal {
    let base = InMemoryAgentModelLoopJournal()
    var failedOperation: String?
    var afterWrite: Bool
    var writes = 0
    init(operation: String?, afterWrite: Bool = false) {
      failedOperation = operation; self.afterWrite = afterWrite
    }
    func hasRecords(scope: AgentModelLoopScope) throws -> Bool { try base.hasRecords(scope: scope) }
    func withLease<T>(scope: AgentModelLoopScope, _ operation: (AgentModelLoopRecords) async throws -> T) async throws -> T {
      try await base.withLease(scope: scope) { try await operation(Records(base: $0, owner: self)) }
    }
    private final class Records: AgentModelLoopRecords {
      let base: AgentModelLoopRecords
      let owner: FaultJournal
      init(base: AgentModelLoopRecords, owner: FaultJournal) { self.base = base; self.owner = owner }
      func read(_ operation: String) throws -> Data? { try base.read(operation) }
      func write(_ operation: String, data: Data) throws {
        owner.writes += 1
        if owner.failedOperation == operation, !owner.afterWrite { throw SyntheticFailure.injected }
        try base.write(operation, data: data)
        if owner.failedOperation == operation, owner.afterWrite { throw SyntheticFailure.injected }
      }
    }
  }
}
