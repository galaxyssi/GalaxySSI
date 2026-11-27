import XCTest
@testable import GalaxySSI

@MainActor
final class AgentBrowserViewLeaseTests: XCTestCase {
  private let scope = String(repeating: "a", count: 64)
  private enum SyntheticFailure: Error { case storage }
  private struct Fixture {
    let defaults: UserDefaults
    let secrets: InMemorySecretStore
    let namespace: String
    let store: AgentManagedBrowserContinuationStore
    let binding: AgentManagedBrowserDispatchBinding
    let ticket: AgentManagedBrowserHandoff.Ticket
    func reopen() -> AgentManagedBrowserContinuationStore {
      AgentManagedBrowserContinuationStore(defaults: defaults, secrets: secrets, namespace: namespace, hostProcessID: "fixture-process")
    }
  }
  private func withFixture(_ body: (Fixture) async throws -> Void) async throws {
    let domain = "BrowserView.\(UUID())", secrets = InMemorySecretStore()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let owner = AgentCollaborationToolEvidenceScope(runId: "run", conversationId: "conversation", turnId: "turn",
      memberId: "member", sourceId: "source")
    let member = AgentTeamMemberSnapshot(agentId: "local-model", status: .running, instanceId: owner.memberId,
      sourceMessageId: owner.sourceId, dispatchCheckpoint: .accepted)
    let team = AgentTeamExecutionSnapshot(supervisorRunId: owner.runId, teamId: "team", conversationId: owner.conversationId,
      taskId: owner.turnId, primaryAgentId: "other", state: .running, members: [member])
    let binding = try XCTUnwrap(AgentManagedBrowserDispatchBinding(owner: owner, team: team, profileID: "profile",
      modelID: "model", hostContextDigest: "context"))
    let store = AgentManagedBrowserContinuationStore(defaults: defaults, secrets: secrets, namespace: domain, hostProcessID: "fixture-process")
    try store.enroll(binding, input: .init(loopID: "loop", inputIdentity: "immutable", toolManifestHash: "pinned",
      systemPrompt: "", prompt: "Synthetic browser task", hasAttachments: false), legacyLoopExists: false)
    let ticket = try await store.withLease(binding: binding, mode: .initial, control: .run) { lease, _ in
      try store.requestControl(lease: lease, binding: binding, callID: "call", invocationID: "invocation", address: "https://example.test/").ticket
    }
    try await body(Fixture(defaults: defaults, secrets: secrets, namespace: domain, store: store, binding: binding, ticket: ticket))
  }
  func testOnlyDurablySavedViewOwnershipBecomesLiveAndCannotBeShared() throws {
    let id = UUID()
    var saved: AgentBrowserViewLease?, writes = 0
    let lease = try AgentBrowserViewLease.claim(scope: scope, id: id, existing: nil, processID: "process") { saved = $0; writes += 1 }
    defer { AgentBrowserViewLease.release(lease) }
    XCTAssertEqual(saved, lease)
    XCTAssertTrue(AgentBrowserViewLease.isLive(lease, scope: scope, processID: "process"))
    XCTAssertEqual(try AgentBrowserViewLease.claim(scope: scope, id: id, existing: lease, processID: "process") { _ in writes += 1 }, lease)
    XCTAssertEqual(writes, 1)
    XCTAssertThrowsError(try AgentBrowserViewLease.claim(scope: scope, id: UUID(), existing: lease, processID: "process") { _ in XCTFail("No second view") })
    XCTAssertFalse(AgentBrowserViewLease.isLive(lease, scope: String(repeating: "b", count: 64), processID: "process"))
    XCTAssertFalse(AgentBrowserViewLease.isLive(lease, scope: scope, processID: "replacement-process"))
  }
  func testFailedPersistenceLeavesNoActiveAuthorityForTheCandidate() throws {
    let id = UUID()
    XCTAssertThrowsError(try AgentBrowserViewLease.claim(scope: scope, id: id, existing: nil, processID: "process") { _ in throw SyntheticFailure.storage })
    let lease = try AgentBrowserViewLease.claim(scope: scope, id: id, existing: nil, processID: "process") { _ in }
    defer { AgentBrowserViewLease.release(lease) }
    XCTAssertTrue(AgentBrowserViewLease.isLive(lease, scope: scope, processID: "process"))
  }
  func testReleasedOrForeignLeaseCannotBeResurrected() throws {
    let lease = try AgentBrowserViewLease.claim(scope: scope, id: UUID(), existing: nil, processID: "process") { _ in }
    AgentBrowserViewLease.release(lease)
    for id in [lease.id, UUID()] {
      XCTAssertThrowsError(try AgentBrowserViewLease.claim(scope: scope, id: id, existing: lease, processID: "process") { _ in XCTFail("Lost view must not reload") }) {
        XCTAssertEqual($0 as? AgentBrowserViewLease.Failure, .viewLost)
      }
    }
    XCTAssertThrowsError(try AgentBrowserViewLease.claim(scope: String(repeating: "b", count: 64), id: UUID(), existing: lease, processID: "process") { _ in })
    XCTAssertThrowsError(try AgentBrowserViewLease.claim(scope: "invalid", id: UUID(), existing: nil, processID: "process") { _ in })
  }
  func testManagedStoreReopensOnlyTheSameLiveViewThenRecordsDurableLoss() async throws {
    try await withFixture { fixture in
      let id = UUID(), lease = try fixture.store.claimView(fixture.ticket, binding: fixture.binding, id: id)
      defer { AgentBrowserViewLease.release(lease) }
      let reopened = fixture.reopen()
      XCTAssertEqual(try reopened.claimView(fixture.ticket, binding: fixture.binding, id: id), lease)
      XCTAssertThrowsError(try reopened.claimView(fixture.ticket, binding: fixture.binding, id: UUID()))
      try reopened.reconcileHostProcess(fixture.binding)
      XCTAssertEqual(try reopened.awaitingHandoff(binding: fixture.binding)?.ticket, fixture.ticket)
      AgentBrowserViewLease.release(lease)
      XCTAssertThrowsError(try reopened.claimView(fixture.ticket, binding: fixture.binding, id: UUID()))
      try reopened.reconcileHostProcess(fixture.binding)
      let interrupted = try fixture.reopen().handoff(fixture.ticket, binding: fixture.binding)
      XCTAssertEqual(interrupted.interruption, .browserViewClosed)
      XCTAssertEqual(interrupted.state, .interrupted)
      XCTAssertNil(interrupted.observation)
      XCTAssertEqual(interrupted.interruption?.output["business_success_verified"], .bool(false))
      XCTAssertThrowsError(try reopened.returnControl(fixture.ticket, binding: fixture.binding,
        observation: .init(address: "https://example.test/", title: "", text: "Stale")))
    }
  }
  func testPausedLostViewRemainsUnverifiedAndCannotRunUntilExplicitResume() async throws {
    try await withFixture { fixture in
      let lease = try fixture.store.claimView(fixture.ticket, binding: fixture.binding, id: UUID())
      let run = AgentManagedBrowserContinuationStore.RunScope(fixture.binding)
      XCTAssertTrue(try fixture.store.writeControl(.pause, scope: run))
      AgentBrowserViewLease.release(lease)
      try fixture.store.reconcileHostProcess(fixture.binding)
      do {
        try await fixture.store.withLease(binding: fixture.binding, mode: .recovery, control: .run) { _, _ in XCTFail("Pause must not run inference") }
        XCTFail("Pause must retain the wake")
      } catch let error as AgentManagedBrowserContinuationStore.Failure { XCTAssertEqual(error, .notReady) }
      XCTAssertTrue(try fixture.store.writeControl(.run, scope: run))
      try await fixture.store.withLease(binding: fixture.binding, mode: .recovery, control: .run) { _, work in
        guard case .continueLoop = work else { return XCTFail("Resume must retain the original loop") }
        XCTAssertEqual(try fixture.store.handoff(fixture.ticket, binding: fixture.binding).interruption, .browserViewClosed)
      }
    }
  }
  func testStoppedOrStaleGenerationCannotClaimOrReturnAView() async throws {
    try await withFixture { fixture in
      let stale = AgentManagedBrowserHandoff.Ticket(dispatchKey: fixture.ticket.dispatchKey, callID: fixture.ticket.callID, generation: UUID())
      XCTAssertThrowsError(try fixture.store.claimView(stale, binding: fixture.binding, id: UUID()))
      let replacementProcess = AgentManagedBrowserContinuationStore(defaults: fixture.defaults, secrets: fixture.secrets,
        namespace: fixture.namespace, hostProcessID: "replacement-process")
      XCTAssertThrowsError(try replacementProcess.claimView(fixture.ticket, binding: fixture.binding, id: UUID()))
      let lease = try fixture.store.claimView(fixture.ticket, binding: fixture.binding, id: UUID())
      defer { AgentBrowserViewLease.release(lease) }
      XCTAssertTrue(try fixture.store.writeControl(.stop, scope: .init(fixture.binding)))
      try fixture.store.retireStoppedBinding(fixture.binding)
      XCTAssertThrowsError(try fixture.store.claimView(fixture.ticket, binding: fixture.binding, id: UUID()))
      try fixture.store.reconcileHostProcess(fixture.binding)
      XCTAssertEqual(try fixture.store.handoff(fixture.ticket, binding: fixture.binding).state, .stopped)
    }
  }
  func testSupervisedTaskLeaseIsOptionalForLegacyDataAndDoesNotRewriteItsPlan() throws {
    var task = AgentTaskRecord(taskId: "turn", sessionId: "conversation", goal: "Synthetic task", phase: .waitingResponse,
      routeKind: .localSystem, targetTitle: "Browser", risk: .low, blocked: false)
    let original = task
    let lease = try AgentBrowserViewLease.claim(scope: scope, id: UUID(), existing: nil, processID: "process") { task.browserViewLease = $0 }
    defer { AgentBrowserViewLease.release(lease) }
    let restored = try JSONDecoder().decode(AgentTaskRecord.self, from: JSONEncoder().encode(task))
    XCTAssertEqual(restored.browserViewLease, lease); XCTAssertNil(restored.activePlan)
    var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any])
    fields.removeValue(forKey: "browser_view_lease")
    let legacy = try JSONDecoder().decode(AgentTaskRecord.self, from: JSONSerialization.data(withJSONObject: fields))
    XCTAssertEqual(legacy, original)
  }
  func testUnopenedRequestIsNotInventedAsViewLossAndCloseNeverMeansSuccess() async throws {
    try await withFixture { fixture in
      try fixture.store.reconcileHostProcess(fixture.binding)
      XCTAssertEqual(try fixture.store.awaitingHandoff(binding: fixture.binding)?.ticket, fixture.ticket)
      XCTAssertTrue(try fixture.store.recordWebContentExit(fixture.ticket, binding: fixture.binding, cause: .browserViewClosed))
      let event = try fixture.reopen().handoff(fixture.ticket, binding: fixture.binding)
      XCTAssertTrue(event.isResolved)
      let output = try XCTUnwrap(event.interruption?.output)
      for key in ["business_success_verified", "authentication_verified", "browser_state_verified", "user_returned_control"] {
        XCTAssertEqual(output[key], .bool(false))
      }
      XCTAssertEqual(output["requires_external_observation"], .bool(true))
      XCTAssertFalse(try fixture.store.recordWebContentExit(fixture.ticket, binding: fixture.binding, cause: .browserViewClosed))
    }
  }
}
