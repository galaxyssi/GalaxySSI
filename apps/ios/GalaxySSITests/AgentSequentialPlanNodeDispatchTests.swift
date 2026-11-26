import Foundation
import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testSequentialDispatchStagesFinalInputAndCheckpointBeforeOperation() throws {
    try sequentialFixture { journal, _, _ in
      let prepared = try sequentialPrepared()
      var calls = 0
      let result = AgentSequentialPlanNodeDispatch.execute(prepared, journal: journal) {
        calls += 1
        let saved = try? journal.readDispatch(prepared.key)
        XCTAssertEqual(saved?.action, prepared.action)
        XCTAssertEqual(saved?.checkpoint, prepared.checkpoint)
        XCTAssertEqual(saved?.audits.map(\.event), [.checkpointSaved, .toolStarted])
        return AgentActionResult(actionId: prepared.action.id, success: true, message: "Observed")
      }
      XCTAssertTrue(result.success)
      XCTAssertEqual(calls, 1)
      XCTAssertEqual(try journal.read(prepared.key)?.result, result)
      XCTAssertEqual(prepared.plan.actions.first?.target, "final-target")
      XCTAssertEqual(prepared.plan.actions.first?.status, .running)
    }
  }

  func testSequentialDispatchReplaysObservedResultWithoutExecutingAgain() throws {
    try sequentialFixture { journal, defaults, secrets in
      let prepared = try sequentialPrepared()
      let result = AgentSequentialPlanNodeDispatch.execute(prepared, journal: journal) {
        AgentActionResult(actionId: prepared.action.id, success: true, message: "Original receipt")
      }
      let reopened = EncryptedAgentPlanNodeJournal(defaults: defaults, secrets: secrets, storageKey: "sequential-fixture")
      let replay = try XCTUnwrap(AgentSequentialPlanNodeDispatch.replay(plan: prepared.plan, actionId: prepared.action.id,
        sessionId: "session", conversationId: "conversation", turnId: "turn", journal: reopened))
      XCTAssertEqual(replay.action, prepared.action)
      XCTAssertEqual(replay.result, result)
      let again = AgentSequentialPlanNodeDispatch.execute(prepared, journal: reopened) {
        XCTFail("Do not dispatch an observed node again")
        return result
      }
      XCTAssertEqual(again, result)
    }
  }

  func testSequentialPendingAndLegacyClaimsCannotGainNewExecutionAuthority() throws {
    try sequentialFixture { journal, _, _ in
      let prepared = try sequentialPrepared()
      XCTAssertEqual(try journal.claim(prepared.key), .acquired)
      let result = AgentSequentialPlanNodeDispatch.execute(prepared, journal: journal) {
        XCTFail("Unknown prior effect cannot be repeated")
        return AgentActionResult(actionId: prepared.action.id, success: true, message: "Invalid")
      }
      XCTAssertFalse(result.success)
      XCTAssertEqual(result.metadata["plan_node_outcome_unknown"], "true")
      XCTAssertEqual(result.metadata["non_retriable"], "true")
      XCTAssertNil(try journal.readDispatch(prepared.key))
    }
  }

  func testSequentialUnreadableClaimPreventsExternalOperation() throws {
    try sequentialFixture { journal, defaults, _ in
      let prepared = try sequentialPrepared()
      defaults.set(Data("invalid encrypted record".utf8), forKey: "sequential-fixture.encrypted.v1")
      let result = AgentSequentialPlanNodeDispatch.execute(prepared, journal: journal) {
        XCTFail("Claim failure must precede external execution")
        return AgentActionResult(actionId: prepared.action.id, success: true, message: "Invalid")
      }
      XCTAssertEqual(result.metadata["execution_started"], "false")
      XCTAssertEqual(result.metadata["plan_node_journal_error"], "dispatch_claim_failed")
    }
  }

  func testSequentialObservationCommitFailureDoesNotBecomeVerifiedSuccess() throws {
    try sequentialFixture { journal, defaults, _ in
      let prepared = try sequentialPrepared()
      var calls = 0
      let result = AgentSequentialPlanNodeDispatch.execute(prepared, journal: journal) {
        calls += 1
        defaults.set(Data("corrupt after effect".utf8), forKey: "sequential-fixture.encrypted.v1")
        return AgentActionResult(actionId: prepared.action.id, success: true, message: "External effect returned")
      }
      XCTAssertEqual(calls, 1)
      XCTAssertFalse(result.success)
      XCTAssertEqual(result.metadata["plan_node_journal_error"], "observation_commit_failed")
      XCTAssertEqual(result.metadata["plan_node_outcome_unknown"], "true")
      XCTAssertThrowsError(try AgentSequentialPlanNodeDispatch.replay(plan: prepared.plan, actionId: prepared.action.id,
        sessionId: "session", conversationId: "conversation", turnId: "turn", journal: journal))
    }
  }

  func testSequentialFallbackInputHasDistinctDurableSpecificationAndReplaysOnce() throws {
    try sequentialFixture { journal, _, _ in
      let initial = try sequentialPrepared()
      _ = AgentSequentialPlanNodeDispatch.execute(initial, journal: journal) {
        AgentActionResult(actionId: initial.action.id, success: false, message: "Known failure")
      }
      var action = initial.action
      action.target = "reviewed-fallback-target"
      action.parameters["input_json"] = #"{"path":"fallback.txt"}"#
      let fallback = try XCTUnwrap(AgentSequentialPlanNodeDispatch.prepare(plan: initial.plan, action: action,
        screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent"), sessionId: "session",
        conversationId: "conversation", turnId: "turn"))
      XCTAssertEqual(fallback.checkpoint, initial.checkpoint)
      XCTAssertNotEqual(fallback.key, initial.key)
      let result = AgentSequentialPlanNodeDispatch.execute(fallback, journal: journal) {
        AgentActionResult(actionId: action.id, success: true, message: "Fallback receipt")
      }
      XCTAssertEqual(try journal.readDispatch(initial.key)?.action, initial.action)
      XCTAssertEqual(try journal.readDispatch(fallback.key)?.action, fallback.action)
      XCTAssertEqual(AgentSequentialPlanNodeDispatch.execute(fallback, journal: journal) {
        XCTFail("Fallback cannot repeat"); return result
      }, result)
    }
  }

  func testSequentialPreparationRejectsMissingDuplicateAndStaleRevision() throws {
    let initial = try sequentialPrepared()
    let screen = AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")
    for variation in 0..<3 {
      var plan = initial.plan
      if variation == 0 { plan.actions = [] }
      if variation == 1 { plan.actions.append(initial.action) }
      if variation == 2 { plan.revision += 1 }
      XCTAssertNil(AgentSequentialPlanNodeDispatch.prepare(plan: plan, action: initial.action, screen: screen,
        sessionId: "session", conversationId: "conversation", turnId: "turn"))
    }
  }

  func testSequentialPreparedIdentityCannotBeChangedBeforeClaim() throws {
    try sequentialFixture { journal, _, _ in
      var prepared = try sequentialPrepared()
      prepared.action.parameters["input_json"] = "{}"
      let result = AgentSequentialPlanNodeDispatch.execute(prepared, journal: journal) {
        XCTFail("Mismatched specification must not dispatch")
        return AgentActionResult(actionId: prepared.action.id, success: true, message: "Invalid")
      }
      XCTAssertEqual(result.metadata["plan_node_journal_error"], "identity_mismatch")
      XCTAssertNil(try journal.observe(prepared.key))
    }
  }

  func testSequentialReplayRejectsPriorRevisionAndForgedPreparedRevision() throws {
    try sequentialFixture { journal, _, _ in
      var prepared = try sequentialPrepared()
      _ = AgentSequentialPlanNodeDispatch.execute(prepared, journal: journal) {
        AgentActionResult(actionId: prepared.action.id, success: true, message: "Old revision receipt")
      }
      prepared.plan.revision += 1
      XCTAssertThrowsError(try AgentSequentialPlanNodeDispatch.replay(plan: prepared.plan, actionId: prepared.action.id,
        sessionId: "session", conversationId: "conversation", turnId: "turn", journal: journal)) { error in
        XCTAssertEqual(error as? AgentPlanNodeJournalError, .identityMismatch)
      }
      let result = AgentSequentialPlanNodeDispatch.execute(prepared, journal: journal) {
        XCTFail("A stale revision cannot dispatch or reuse its old receipt")
        return AgentActionResult(actionId: prepared.action.id, success: true, message: "Invalid")
      }
      XCTAssertFalse(result.success)
      XCTAssertEqual(result.metadata["plan_node_journal_error"], "identity_mismatch")
      XCTAssertEqual(try journal.read(prepared.key)?.result.message, "Old revision receipt")
    }
  }

  func testSequentialReplayRejectsMismatchedStoredCheckpointBeforeUsingResult() throws {
    try sequentialFixture { journal, _, _ in
      let prepared = try sequentialPrepared()
      var wrong = prepared.checkpoint
      wrong.planRevision += 1
      XCTAssertEqual(try journal.claim(prepared.key, action: prepared.action, checkpoint: wrong), .acquired)
      try journal.record(prepared.key, observation: .init(result: AgentActionResult(actionId: prepared.action.id,
        success: true, message: "Mismatched checkpoint receipt"), verified: true))
      XCTAssertThrowsError(try AgentSequentialPlanNodeDispatch.replay(plan: prepared.plan, actionId: prepared.action.id,
        sessionId: "session", conversationId: "conversation", turnId: "turn", journal: journal)) { error in
        XCTAssertEqual(error as? AgentPlanNodeJournalError, .identityMismatch)
      }
      let result = AgentSequentialPlanNodeDispatch.execute(prepared, journal: journal) {
        XCTFail("A mismatched stored checkpoint cannot authorize execution or result reuse")
        return AgentActionResult(actionId: prepared.action.id, success: true, message: "Invalid")
      }
      XCTAssertFalse(result.success)
      XCTAssertEqual(result.metadata["execution_started"], "false")
    }
  }

  func testSequentialReplayDoesNotLeakReceiptAcrossSessionConversationOrTurn() throws {
    try sequentialFixture { journal, _, _ in
      let prepared = try sequentialPrepared()
      _ = AgentSequentialPlanNodeDispatch.execute(prepared, journal: journal) {
        AgentActionResult(actionId: prepared.action.id, success: true, message: "Scoped receipt")
      }
      for scope in [("other-session", "conversation", "turn"), ("session", "other-conversation", "turn"),
        ("session", "conversation", "other-turn")] {
        XCTAssertNil(try AgentSequentialPlanNodeDispatch.replay(plan: prepared.plan, actionId: prepared.action.id,
          sessionId: scope.0, conversationId: scope.1, turnId: scope.2, journal: journal))
      }
      XCTAssertNotNil(try AgentSequentialPlanNodeDispatch.replay(plan: prepared.plan, actionId: prepared.action.id,
        sessionId: "session", conversationId: "conversation", turnId: "turn", journal: journal))
    }
  }

  func testSequentialPreparationAndReplayRejectAmbiguousActiveCheckpointAndInvalidRevision() throws {
    try sequentialFixture { journal, _, _ in
      let prepared = try sequentialPrepared()
      let screen = AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent")
      for variation in 0..<3 {
        var invalid = prepared
        if variation == 0 { invalid.plan.revision = 0 }
        if variation == 1 { invalid.plan.actions.append(prepared.action) }
        if variation == 2 {
          var duplicate = prepared.checkpoint
          duplicate.id = "another-active-checkpoint"
          invalid.plan.checkpoints.append(duplicate)
        }
        XCTAssertNil(AgentSequentialPlanNodeDispatch.prepare(plan: invalid.plan, action: prepared.action, screen: screen,
          sessionId: "session", conversationId: "conversation", turnId: "turn"))
        XCTAssertThrowsError(try AgentSequentialPlanNodeDispatch.replay(plan: invalid.plan, actionId: prepared.action.id,
          sessionId: "session", conversationId: "conversation", turnId: "turn", journal: journal))
        let result = AgentSequentialPlanNodeDispatch.execute(invalid, journal: journal) {
          XCTFail("An ambiguous identity cannot execute")
          return AgentActionResult(actionId: prepared.action.id, success: true, message: "Invalid")
        }
        XCTAssertEqual(result.metadata["execution_started"], "false")
        XCTAssertNil(try journal.observe(prepared.key))
      }
    }
  }

  private func sequentialPrepared() throws -> AgentSequentialPlanNodeDispatch.Prepared {
    let proposed = AgentAction(id: "sequential-node", kind: .callNativeTool, target: "proposed-target", risk: .low,
      status: .proposed, description: "Read", parameters: ["input_json": #"{"path":"proposed.txt"}"#])
    var resolved = proposed
    resolved.target = "final-target"
    resolved.parameters["input_json"] = #"{"path":"private-final-input.txt"}"#
    return try XCTUnwrap(AgentSequentialPlanNodeDispatch.prepare(plan: lifecyclePlan(proposed), action: resolved,
      screen: AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent"), sessionId: "session",
      conversationId: "conversation", turnId: "turn"))
  }

  private func sequentialFixture(_ body: (EncryptedAgentPlanNodeJournal, UserDefaults, InMemorySecretStore) throws -> Void) throws {
    let suite = "SequentialDispatch.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let secrets = InMemorySecretStore()
    try body(EncryptedAgentPlanNodeJournal(defaults: defaults, secrets: secrets, storageKey: "sequential-fixture"), defaults, secrets)
  }
}
