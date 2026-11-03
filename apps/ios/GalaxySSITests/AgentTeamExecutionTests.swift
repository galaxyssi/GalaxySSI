import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testOriginalTeamParentSettlementRejectsUserPauseMismatchAndReplacement() throws {
    let members = [
      AgentTeamMember(agentId: "lead", deliveryMode: .respond, requiredCapabilities: [], role: "lead",
        objective: "", dependsOnAgentIds: [], context: [:]),
      AgentTeamMember(agentId: "reviewer", deliveryMode: .observe, requiredCapabilities: [], role: "reviewer",
        objective: "", dependsOnAgentIds: [], context: [:])
    ]
    let definition = AgentTeamDefinition(teamId: "team", primaryAgentId: "lead", members: members,
      visibilityMode: .background, collectiveCapabilities: [])
    let spec = AgentTeamDispatchSpec(definition: definition, supervisorRunId: "original")
    var action = teamAgentAction("team-action", "lead")
    action.parameters[agentTeamSpecParameter] = AgentTeamDispatchSpecCodec.encode(spec)
    var parent = AgentTaskRecord(taskId: "turn", sessionId: "conversation", goal: "Goal",
      phase: .paused, routeKind: .desktopAgent, targetTitle: "Team", risk: .low, blocked: true,
      activePlan: teamBridgePlan(action), createdAtMillis: 1, updatedAtMillis: 2)
    let saved = AgentTeamExecutionSnapshot(supervisorRunId: "original", teamId: "team",
      conversationId: "conversation", taskId: "turn", primaryAgentId: "lead", state: .succeeded,
      members: members.map { AgentTeamMemberSnapshot(agentId: $0.agentId, deliveryMode: $0.deliveryMode,
        status: .succeeded, instanceId: $0.memberId) }, finalOutput: "Original answer", createdAtMillis: 3)
    XCTAssertNil(AgentSavedTeamReplyPolicy.settleParent(parent, saved: saved, failureText: "Failed", now: 10))
    parent.teamRecoveryRunId = "original"
    let accepted = try XCTUnwrap(AgentSavedTeamReplyPolicy.settleParent(parent, saved: saved, failureText: "Failed", now: 10))
    XCTAssertEqual(accepted.phase, .completed)
    XCTAssertEqual(accepted.result, "Original answer")
    XCTAssertNil(accepted.teamRecoveryRunId)
    XCTAssertNil(AgentSavedTeamReplyPolicy.settleParent(accepted, saved: saved, failureText: "Failed", now: 20))
    var foreign = saved
    foreign.conversationId = "other"
    XCTAssertNil(AgentSavedTeamReplyPolicy.settleParent(parent, saved: foreign, failureText: "Failed", now: 10))
    foreign = saved
    foreign.supervisorRunId = "replacement"
    XCTAssertNil(AgentSavedTeamReplyPolicy.settleParent(parent, saved: foreign, failureText: "Failed", now: 10))
    var multi = parent
    let followup = teamAgentAction("followup", "writer", dependsOn: ["team-action"])
    multi.activePlan = teamBridgePlan(action, followup)
    let continued = try XCTUnwrap(AgentSavedTeamReplyPolicy.settleParent(multi, saved: saved, failureText: "Failed", now: 10))
    XCTAssertEqual(continued.phase, .paused)
    XCTAssertEqual(continued.activePlan?.actions.first?.status, .completed)
    XCTAssertEqual(continued.activePlan?.actions.last, followup)
    XCTAssertEqual(continued.pendingActions.map(\.id), ["followup"])
    XCTAssertNil(continued.teamRecoveryRunId)
    XCTAssertFalse(AgentSavedTeamReplyPolicy.canContinueAutomatically(continued))
    var automatic = continued
    automatic.activePlan?.confirmationRequired = false
    automatic.pendingActions[0].status = .proposed
    XCTAssertTrue(AgentSavedTeamReplyPolicy.canContinueAutomatically(automatic))
    automatic.activePlan?.executionMode = .planOnly
    XCTAssertFalse(AgentSavedTeamReplyPolicy.canContinueAutomatically(automatic))
    automatic.activePlan?.executionMode = .autoComplete
    automatic.pendingActions[0].status = .pendingConfirmation
    XCTAssertFalse(AgentSavedTeamReplyPolicy.canContinueAutomatically(automatic))
    multi.activePlan = teamBridgePlan(action, action)
    XCTAssertNil(AgentSavedTeamReplyPolicy.settleParent(multi, saved: saved, failureText: "Failed", now: 10))
    parent.result = "Existing answer"
    XCTAssertNil(AgentSavedTeamReplyPolicy.settleParent(parent, saved: saved, failureText: "Failed", now: 10))
    parent.result = ""
    parent.phase = .cancelled
    XCTAssertNil(AgentSavedTeamReplyPolicy.settleParent(parent, saved: saved, failureText: "Failed", now: 10))
  }

  func testSavedTeamFailureDistinguishesObserverFromPrimary() throws {
    let saved = AgentTeamExecutionSnapshot(supervisorRunId: "run", teamId: "team",
      conversationId: "conversation", taskId: "turn", primaryAgentId: "lead", state: .running,
      members: [
        AgentTeamMemberSnapshot(agentId: "lead", deliveryMode: .respond, sourceMessageId: "primary"),
        AgentTeamMemberSnapshot(agentId: "reviewer", sourceMessageId: "observer")
      ])
    let observerFailed = try XCTUnwrap(AgentSavedTeamReplyPolicy.apply(to: saved, source: "observer",
      conversation: "conversation", turn: "turn", task: "observer", contact: "reviewer",
      content: "Unavailable", success: false, now: 10))
    XCTAssertEqual(observerFailed.state, .running)
    let primarySucceeded = try XCTUnwrap(AgentSavedTeamReplyPolicy.apply(to: observerFailed, source: "primary",
      conversation: "conversation", turn: "turn", task: "primary", contact: "lead",
      content: "Answer", success: true, now: 20))
    XCTAssertEqual(primarySucceeded.state, .completedWithFailures)
    XCTAssertEqual(primarySucceeded.finalOutput, "Answer")
    let primaryFailed = try XCTUnwrap(AgentSavedTeamReplyPolicy.apply(to: saved, source: "primary",
      conversation: "conversation", turn: "turn", task: "primary", contact: "lead",
      content: "Dispatch failed", success: false, now: 10))
    XCTAssertEqual(primaryFailed.state, .failed)
    XCTAssertEqual(primaryFailed.members[1].status, .pending)
  }

  func testSavedTeamReplyRequiresOriginalIdentityAndPreservesTerminalOutcome() throws {
    let saved = AgentTeamExecutionSnapshot(supervisorRunId: "team-run", teamId: "team",
      conversationId: "conversation", taskId: "turn", primaryAgentId: "agent", state: .running,
      members: [AgentTeamMemberSnapshot(agentId: "agent", deliveryMode: .respond,
        instanceId: "lead", sourceMessageId: "request")], primaryInstanceId: "lead")
    let completed = try XCTUnwrap(AgentSavedTeamReplyPolicy.apply(to: saved, source: "request",
      conversation: "conversation", turn: "turn", task: "request", contact: "agent",
      content: "Final answer", success: true, now: 100))
    XCTAssertEqual(completed.state, .succeeded)
    XCTAssertEqual(completed.finalOutput, "Final answer")
    XCTAssertNil(AgentSavedTeamReplyPolicy.apply(to: completed, source: "request",
      conversation: "conversation", turn: "turn", task: "request", contact: "agent",
      content: "Replacement", success: true, now: 200))
    for identity in [("wrong", "conversation", "turn", "request", "agent"),
                     ("request", "wrong", "turn", "request", "agent"),
                     ("request", "conversation", "wrong", "request", "agent"),
                     ("request", "conversation", "turn", "wrong", "agent"),
                     ("request", "conversation", "turn", "request", "wrong")] {
      XCTAssertNil(AgentSavedTeamReplyPolicy.apply(to: saved, source: identity.0,
        conversation: identity.1, turn: identity.2, task: identity.3, contact: identity.4,
        content: "Foreign answer", success: true, now: 100))
    }
  }

  func testTeamMemberRequestIdentityRoundTripAndLegacyDefault() throws {
    let member = AgentTeamMemberSnapshot(agentId: "agent", instanceId: "reviewer",
      sourceMessageId: "original-request")
    let encoded = try JSONEncoder().encode(member)
    XCTAssertEqual(try JSONDecoder().decode(AgentTeamMemberSnapshot.self, from: encoded), member)
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    legacy.removeValue(forKey: "source_message_id")
    let restored = try JSONDecoder().decode(AgentTeamMemberSnapshot.self,
      from: JSONSerialization.data(withJSONObject: legacy))
    XCTAssertEqual(restored.sourceMessageId, "")
    XCTAssertEqual(restored.memberId, "reviewer")
  }

  func testRecoveryRepublishesSavedTerminalTeamWithoutStartingAnotherRun() {
    let snapshot = AgentTeamExecutionSnapshot(supervisorRunId: "saved-team", teamId: "team",
      conversationId: "conversation", taskId: "turn", primaryAgentId: "lead",
      state: .succeeded, finalOutput: "Saved answer")
    var unbound = snapshot
    unbound.supervisorRunId = "unbound"
    unbound.conversationId = ""
    let store = SavedTeamRecoveryFixture([snapshot, unbound])
    let responses = InMemoryAgentConnectorResponseStore()
    let suite = "team-recovery-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let sink = AgentConnectorTeamCompletionSink(responseStore: responses,
      historyStore: AgentTeamExecutionHistoryStore(defaults: defaults, secrets: InMemorySecretStore(), executionStore: store))
    let runtime = AgentTeamExecutionRuntime(store: store, mailbox: InMemoryAgentTeamMailbox(), completionSink: sink)
    XCTAssertTrue(runtime.recoverInterrupted().isEmpty)
    XCTAssertTrue(runtime.recoverInterrupted().isEmpty)
    XCTAssertEqual(responses.pending().count, 1)
    XCTAssertEqual(responses.pending().first?.content, "Saved answer")
    XCTAssertEqual(responses.pending().first?.conversationId, "conversation")
    XCTAssertEqual(responses.pending().first?.taskId, "turn")
    XCTAssertEqual(store.creates, 0)
    runtime.close()
  }

  func testAgentTeamProgressPolicyHidesBackgroundMembersUntilExpanded() {
    let snapshot = AgentTeamExecutionSnapshot(
      supervisorRunId: "progress-supervisor",
      teamId: "progress-team",
      primaryAgentId: "primary",
      visibilityMode: .background,
      state: .running,
      members: [
        AgentTeamMemberSnapshot(agentId: "primary", deliveryMode: .respond, status: .running),
        AgentTeamMemberSnapshot(agentId: "observer", deliveryMode: .observe, status: .succeeded, output: "evidence")
      ],
      finalOutput: "draft"
    )

    let collapsed = AgentTeamProgressPolicy.project(snapshot, expanded: false)
    let expanded = AgentTeamProgressPolicy.project(snapshot, expanded: true)

    XCTAssertFalse(collapsed.memberDetailsVisible)
    XCTAssertEqual(collapsed.members, [])
    XCTAssertTrue(expanded.memberDetailsVisible)
    XCTAssertEqual(expanded.members.count, 2)
    XCTAssertEqual(expanded.primaryAgentId, "primary")
    XCTAssertEqual(expanded.finalOutput, "draft")
  }

  func testAgentTeamProgressPolicyAlwaysShowsVisibleTeamMembersAndTerminalStates() {
    let snapshot = AgentTeamExecutionSnapshot(
      supervisorRunId: "visible-supervisor",
      teamId: "visible-team",
      primaryAgentId: "lead",
      visibilityMode: .visible,
      state: .completedWithFailures,
      members: [
        AgentTeamMemberSnapshot(agentId: "lead", deliveryMode: .respond, status: .succeeded),
        AgentTeamMemberSnapshot(agentId: "reviewer", deliveryMode: .observe, status: .failed, errorMessage: "timeout")
      ],
      finalOutput: "final"
    )

    let projection = AgentTeamProgressPolicy.project(snapshot, expanded: false)

    XCTAssertTrue(projection.memberDetailsVisible)
    XCTAssertEqual(projection.members.map(\.agentId), ["lead", "reviewer"])
    XCTAssertTrue(AgentTeamExecutionState.succeeded.isTerminal)
    XCTAssertTrue(AgentTeamExecutionState.completedWithFailures.isTerminal)
    XCTAssertTrue(AgentTeamExecutionState.failed.isTerminal)
    XCTAssertTrue(AgentTeamExecutionState.cancelled.isTerminal)
    XCTAssertTrue(AgentTeamExecutionState.interrupted.isTerminal)
    XCTAssertFalse(AgentTeamExecutionState.queued.isTerminal)
    XCTAssertFalse(AgentTeamExecutionState.running.isTerminal)
  }

  func testAgentTeamCompletionSinkPublishesOneDurableConnectorResponse() {
    let responseStore = InMemoryAgentConnectorResponseStore()
    let deliveryLedger = AgentTeamCompletionDeliveryLedger()
    let sink = AgentConnectorTeamCompletionSink(
      responseStore: responseStore,
      ledger: deliveryLedger,
      nowMillis: { 20_000 }
    )
    let snapshot = AgentTeamExecutionSnapshot(
      supervisorRunId: "completion-supervisor",
      teamId: "completion-team",
      conversationId: "completion-conversation",
      taskId: "completion-turn",
      primaryAgentId: "lead",
      goal: "Produce one answer",
      state: .succeeded,
      members: [
        AgentTeamMemberSnapshot(
          agentId: "lead",
          role: "lead synthesizer",
          deliveryMode: .respond,
          status: .succeeded,
          output: "single final answer"
        )
      ],
      finalOutput: "single final answer",
      updatedAtMillis: 10_000
    )

    XCTAssertTrue(sink.publish(snapshot))
    XCTAssertFalse(sink.publish(snapshot))
    let pending = responseStore.pending()

    XCTAssertEqual(pending.count, 1)
    XCTAssertEqual(pending[0].content, "single final answer")
    XCTAssertEqual(pending[0].turnId, "completion-turn")
    XCTAssertEqual(pending[0].taskId, "completion-turn")
    XCTAssertEqual(pending[0].conversationId, "completion-conversation")
    XCTAssertEqual(pending[0].contactId, AgentTeamDispatchIds.responseContactId(teamId: snapshot.teamId))
    XCTAssertEqual(pending[0].sourceMessageId, AgentTeamDispatchIds.sourceMessageId(supervisorRunId: snapshot.supervisorRunId))
    XCTAssertTrue(pending[0].success)
    XCTAssertEqual(pending[0].receivedAtMillis, 20_000)
    XCTAssertEqual(deliveryLedger.snapshot(), ["completion-supervisor"])

    sink.remove(supervisorRunId: "completion-supervisor")
    XCTAssertTrue(sink.publish(snapshot))
    XCTAssertEqual(responseStore.pending().count, 2)
  }

  func testAgentTeamCompletionSinkPublishesFailureResponseWithReason() {
    let responseStore = InMemoryAgentConnectorResponseStore()
    let sink = AgentConnectorTeamCompletionSink(
      responseStore: responseStore,
      ledger: AgentTeamCompletionDeliveryLedger(),
      nowMillis: { 3_000 }
    )
    let snapshot = AgentTeamExecutionSnapshot(
      supervisorRunId: "failed-supervisor",
      teamId: "failed-team",
      taskId: "failed-turn",
      primaryAgentId: "lead",
      state: .failed,
      members: [
        AgentTeamMemberSnapshot(
          agentId: "lead",
          deliveryMode: .respond,
          status: .failed,
          errorMessage: "primary Agent timed out"
        )
      ],
      updatedAtMillis: 2_000
    )

    XCTAssertTrue(sink.publish(snapshot))
    let response = responseStore.pending().first

    XCTAssertEqual(response?.success, false)
    XCTAssertEqual(response?.content, "Agent team failed: primary Agent timed out")
    XCTAssertEqual(response?.contactId, "agent-team:failed-team")
    XCTAssertEqual(response?.receivedAtMillis, 3_000)
  }
}

private final class SavedTeamRecoveryFixture: AgentTeamExecutionStore {
  let saved: [AgentTeamExecutionSnapshot]
  private(set) var creates = 0
  init(_ saved: [AgentTeamExecutionSnapshot]) { self.saved = saved }
  func create(definition: AgentTeamDefinition, request: AgentRunRequest) throws { creates += 1 }
  func append(_ event: AgentSubagentEvent) async throws {}
  func snapshot(supervisorRunId: String) -> AgentTeamExecutionSnapshot? {
    saved.first { $0.supervisorRunId == supervisorRunId }
  }
  func snapshots() -> [AgentTeamExecutionSnapshot] { saved }
  func markInterrupted(supervisorRunId: String, nowMillis: Int64) -> AgentTeamExecutionSnapshot? {
    XCTFail("Terminal teams must not be interrupted")
    return nil
  }
  func markNonTerminalInterrupted(nowMillis: Int64) -> [AgentTeamExecutionSnapshot] {
    XCTFail("Recovery must inspect individual original teams")
    return []
  }
  func remove(supervisorRunId: String) {}
  func clear() {}
}
