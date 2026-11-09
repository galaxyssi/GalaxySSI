import CryptoKit
import SQLite3
import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testTypedGoalWorkBindsExactMilestoneWithoutReleasingCompletionEdges() throws {
    let suite = "typed-input-\(UUID())", root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore(), file = root.appendingPathComponent("team.sqlite")
    func open() -> AgentTeamExecutionHistoryStore {
      .init(defaults: defaults, secrets: secrets, executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    }
    let history = open()
    var team = durableTeamSnapshot("typed-input")
    team.goal = "Check the fixture"
    team.members[0].dispatchCheckpoint = .accepted
    XCTAssertTrue(history.upsert(team))
    let coordinator = team.members[0], worker = team.members[1]
    let scope = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId, memberId: coordinator.memberId, sourceId: coordinator.sourceMessageId)
    XCTAssertTrue(history.advanceGoalCheckpoint(.init(runId: scope.runId, conversationId: scope.conversationId,
      turnId: scope.turnId, revision: 1, phase: .working,
      contract: [.init(id: "check", requirement: "Check the fixture", verification: .documentary, status: .open,
        evidence_kind: nil, evidence: [])], completedWorkIds: []), expectedRevision: 0))
    func work(_ id: String, dependencies: [String] = [], typed: Bool = false) -> AgentMcpJSONValue {
      var value: AgentMcpJSONObject = ["id": .string(id), "member": .string(worker.memberId), "assignment": .string(id),
        "stage": .string("CHALLENGE"), "depends_on": .array(dependencies.map(AgentMcpJSONValue.string))]
      if typed {
        value["data_dependencies"] = .array([.object([
          "work_id": .string("measure"), "requirement": .string("Frozen reading")
        ])])
      }
      return .object(value)
    }
    func expansion(_ id: String, _ revision: Int64, work: [AgentMcpJSONValue],
                   bindings: [AgentMcpJSONValue] = []) -> AgentMcpJSONObject {
      ["mode": .string("append_work"), "milestone_id": .string(id), "expected_revision": .int(revision),
       "artifact": .string(AgentMcpJSONCodec.stringify(["format": .string("galaxyssi.work-expansion.v1"),
         "work": .array(work), "rebind_inputs": .array(bindings)]))]
    }
    let seeded = expansion("seed", 1, work: [work("measure"), work("release"),
      work("challenge", dependencies: ["measure", "release"], typed: true)])
    XCTAssertEqual(try history.publishCollaborationMilestone(seeded, scope: scope)["admitted_work_count"], .int(3))
    let (measurement, _) = try history.goalWork("measure", scope: scope)
    let (release, _) = try history.goalWork("release", scope: scope)
    let producer = try history.claimGoalWork(measurement, scope: scope, now: 2).run
    let completing = try history.claimGoalWork(release, scope: scope, now: 2).run
    let version = try history.publishGoalWorkInput(producer, id: "first", payload: ["reading": .int(42)], now: 3)
    let token = try XCTUnwrap(version["token"]?.strictStringValue)
    XCTAssertEqual(try history.publishGoalWorkInput(producer, id: "first", payload: ["reading": .int(42)], now: 3)["replayed"],
      .bool(true))
    XCTAssertThrowsError(try history.publishGoalWorkInput(producer, id: "first", payload: ["reading": .int(43)], now: 3))
    func binding(_ dependency: String = "measure", revision: Int64 = 0) -> AgentMcpJSONValue {
      .object(["work_id": .string("challenge"), "expected_revision": .int(revision), "reason": .string("Exact input"),
        "inputs": .array([.object(["dependency": .string(dependency), "uses_milestones": .array([.string(token)])])])])
    }
    XCTAssertThrowsError(try history.publishCollaborationMilestone(expansion("bad", 2, work: [work("not-added")],
      bindings: [binding("release")]), scope: scope))
    XCTAssertThrowsError(try history.goalWork("not-added", scope: scope))
    let bound = expansion("bind", 2, work: [], bindings: [binding()])
    XCTAssertEqual(try history.publishCollaborationMilestone(bound, scope: scope)["input_revisions"]?.objectValue?["challenge"], .int(1))
    XCTAssertFalse(try history.readyGoalWork(scope: scope, excluding: [], limit: 3, now: 4).contains("challenge"))
    _ = try history.finishGoalWork(completing, output: "Released", interrupted: false, now: 4)
    let reopened = open()
    XCTAssertEqual(try reopened.publishCollaborationMilestone(bound, scope: scope)["replayed"], .bool(true))
    XCTAssertTrue(try reopened.readyGoalWork(scope: scope, excluding: [], limit: 3, now: 5).contains("challenge"))
    let (target, _) = try reopened.goalWork("challenge", scope: scope)
    let claim = try reopened.claimGoalWork(target, scope: scope, now: 5)
    XCTAssertTrue(claim.claimed)
    XCTAssertEqual(claim.run.inputRevision, 1)
    XCTAssertEqual(claim.dependencies.first?["versions"]?.arrayValue?.first?.objectValue?["data"]?.objectValue?["reading"], .int(42))
    XCTAssertEqual(claim.dependencies.last?["output"], .string("Released"))
    XCTAssertFalse(try open().claimGoalWork(target, scope: scope, now: 5).claimed)
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(expansion("late", 3, work: [],
      bindings: [binding(revision: 1)]), scope: scope))
  }

  func testScopedTeamHistoryRoutesExactReadsWithoutJoiningDefaultRecovery() throws {
    let suite = "scoped-team-history-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore(), file = root.appendingPathComponent("history.sqlite3")
    func history(_ key: String = AgentTeamExecutionHistoryStore.defaultStorageKey) -> AgentTeamExecutionHistoryStore {
      .init(defaults: defaults, storageKey: key, secrets: secrets, executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    }
    let standard = history(), isolated = history("fixture-scoped-pilot"), other = history("fixture-other-pilot")
    let legacy = durableTeamSnapshot("existing-default")
    XCTAssertTrue(standard.upsert(legacy))
    XCTAssertFalse(isolated.upsert(legacy))
    var run = durableTeamSnapshot("isolated-live")
    run.goal = "Read exact fixture"
    run.members[0].dispatchCheckpoint = .accepted
    run.members[1].dispatchCheckpoint = .dispatching
    XCTAssertTrue(isolated.upsert(run))
    XCTAssertTrue(history("fixture-scoped-pilot").upsert(run))
    XCTAssertFalse(standard.upsert(run))
    XCTAssertFalse(other.upsert(run))
    var replacement = run
    replacement.teamId = "different-team"
    XCTAssertFalse(isolated.upsert(replacement))
    XCTAssertFalse(standard.recoverable(conversationId: run.conversationId).contains { $0.supervisorRunId == run.supervisorRunId })
    XCTAssertNil(standard.snapshot(supervisorRunId: run.supervisorRunId))

    let member = run.members[0]
    let scope = AgentCollaborationToolEvidenceScope(runId: run.supervisorRunId, conversationId: run.conversationId,
      turnId: run.taskId, memberId: member.memberId, sourceId: member.sourceMessageId)
    XCTAssertTrue(isolated.advanceGoalCheckpoint(.init(runId: scope.runId, conversationId: scope.conversationId,
      turnId: scope.turnId, revision: 1, phase: .working,
      contract: [.init(id: "check", requirement: "Check the fixture", verification: .documentary, status: .open,
        evidence_kind: nil, evidence: [])], completedWorkIds: []), expectedRevision: 0))
    let evidence = try isolated.recordCloudEvidence(.init(scope: scope, round: 1,
      call: .init(callId: "probe", name: "fixture_probe", argumentsJson: "{}"),
      output: "{\"fixture\":true}", succeeded: true, startedAtMillis: 2, finishedAtMillis: 3))
    var selector = evidence.filter { ["evidence_id", "sha256"].contains($0.key) }
    selector["mode"] = .string("evidence")
    let reopened = history()
    XCTAssertEqual(try reopened.goalWorkInventory(scope: scope)["revision"], .int(1))
    let page = try reopened.recallCollaborationOriginal(selector, scope: scope, evidenceRead: .desktopPreview)
    XCTAssertNil(page["host_read_coverage"])
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(selector, scope: scope,
      evidenceRead: .desktopConfirm(contentHash: "wrong")))
    let confirmation = try reopened.recallCollaborationOriginal(selector, scope: scope,
      evidenceRead: .desktopConfirm(contentHash: AgentDesktopNativeEvidenceDelivery.digest(page.string("content"))))
    XCTAssertNotNil(confirmation["host_read_coverage"])
    var foreign = scope
    foreign.sourceId = "wrong-source"
    XCTAssertThrowsError(try reopened.goalWorkInventory(scope: foreign))
    XCTAssertThrowsError(try other.recallCollaborationOriginal(selector, scope: scope))
    XCTAssertNil(try reopened.recoveryContext(source: scope.sourceId, conversation: scope.conversationId,
      turn: scope.turnId, contact: member.agentId))
    XCTAssertEqual(try reopened.recoveryContext(source: scope.sourceId, conversation: scope.conversationId,
      turn: scope.turnId, contact: member.agentId, requireResearchAccess: true)?.team.supervisorRunId, scope.runId)

    var paused = run
    paused.state = .waitingResponse
    paused.updatedAtMillis += 1
    XCTAssertTrue(isolated.upsert(paused))
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(selector, scope: scope))
    run.updatedAtMillis = paused.updatedAtMillis + 1
    XCTAssertTrue(isolated.upsert(run))
    let defaultDatabase = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    try defaultDatabase.transaction {
      try defaultDatabase.insertResearchRecord(true, conversationId: scope.conversationId,
        key: "native-evidence-revoked", revision: 0)
    }
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(selector, scope: scope))
    XCTAssertThrowsError(try isolated.recallCollaborationOriginal(selector, scope: scope))
    try defaultDatabase.transaction {
      try defaultDatabase.removeResearchRecord(conversationId: scope.conversationId, key: "native-evidence-revoked")
    }
    let disposable = durableTeamSnapshot("other-isolated")
    XCTAssertTrue(other.upsert(disposable))
    other.remove(supervisorRunId: scope.runId)
    other.clear()
    XCTAssertTrue(standard.upsert(disposable))
    XCTAssertEqual(try reopened.goalWorkInventory(scope: scope)["revision"], .int(1))
    let runKey = SHA256.hash(data: Data(scope.runId.utf8)).map { String(format: "%02x", $0) }.joined()
    var connection: OpaquePointer?
    XCTAssertEqual(sqlite3_open(file.path, &connection), SQLITE_OK)
    defer { sqlite3_close(connection) }
    XCTAssertEqual(sqlite3_exec(connection, "DELETE FROM team_history WHERE run_key='\(runKey)'", nil, nil, nil), SQLITE_OK)
    XCTAssertThrowsError(try reopened.goalWorkInventory(scope: scope))
    XCTAssertFalse(standard.upsert(run))
    XCTAssertTrue(isolated.upsert(run))
    XCTAssertEqual(sqlite3_exec(connection,
      "UPDATE team_execution_locations SET encrypted_payload=x'00' WHERE run_key='\(runKey)'", nil, nil, nil), SQLITE_OK)
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(selector, scope: scope))
    XCTAssertFalse(standard.upsert(run))
  }

  func testTeamSnapshotCacheRechecksCiphertextFromAnExternalWriterAndDoesNotReviveDeletedRows() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("team.sqlite3")
    let secrets = InMemorySecretStore()
    let reader = try AgentTeamHistoryDatabase(fileURL: file, storageKey: "team-cache", secrets: secrets)
    let writer = try AgentTeamHistoryDatabase(fileURL: file, storageKey: "team-cache", secrets: secrets)
    let original = durableTeamSnapshot("external-update")
    try writer.transaction { try writer.put(original) }
    XCTAssertEqual(try reader.snapshots(runId: original.supervisorRunId), [original])
    XCTAssertEqual(try reader.snapshots(runId: original.supervisorRunId), [original])
    var updated = original
    updated.members[0].output = "Changed without a timestamp update"
    try writer.transaction { try writer.put(updated) }
    XCTAssertEqual(try reader.snapshots(runId: original.supervisorRunId), [updated])
    try writer.transaction { try writer.remove(runId: original.supervisorRunId) }
    XCTAssertTrue(try reader.snapshots(runId: original.supervisorRunId).isEmpty)
  }

  @MainActor
  func testTeamRecoveryFailureBudgetSurvivesReloadAndOnlyResumesValidScope() throws {
    let suite = "team-recovery-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let secrets = InMemorySecretStore()
    let ledger = AgentTeamRecoveryRetryLedger(defaults: defaults, secrets: secrets)
    let profile = "owner"
    var now: Int64 = 100_000
    for attempt in 1...10 {
      ledger.failure(run: "retry", profile: profile, progress: "no-progress", now: now)
      let state = ledger.state(run: "retry", profile: profile)
      XCTAssertEqual(state.failures, attempt)
      ledger.failure(run: "retry", profile: profile, progress: "no-progress", now: now)
      XCTAssertEqual(ledger.state(run: "retry", profile: profile).failures, attempt)
      now = state.retryAtMillis
    }
    XCTAssertTrue(ledger.stopMissingScope(run: "deleted", profile: profile, now: now))
    let reopened = AgentTeamRecoveryRetryLedger(defaults: defaults, secrets: secrets)
    XCTAssertTrue(reopened.state(run: "retry", profile: profile).stalled)
    XCTAssertTrue(reopened.resume(run: "retry", profile: profile))
    XCTAssertEqual(reopened.state(run: "retry", profile: profile).failures, 0)
    XCTAssertFalse(reopened.resume(run: "deleted", profile: profile))
    XCTAssertFalse(reopened.state(run: "deleted", profile: "other-profile").stalled)
  }

  func testTeamRecoveryProgressDoesNotCountStartupOrIgnoredMembers() {
    var team = durableTeamSnapshot("recovery-progress")
    let original = AgentTeamRecoveryRetryState.progress(team)
    team.updatedAtMillis += 1
    team.state = .running
    team.members.append(.init(agentId: "ignored", deliveryMode: .ignore, status: .succeeded))
    XCTAssertEqual(AgentTeamRecoveryRetryState.progress(team), original)
    team.members[0].status = .succeeded
    XCTAssertNotEqual(AgentTeamRecoveryRetryState.progress(team), original)
  }

  func testStoppingMissingTeamPreservesCompletedChildrenAndRejectsStaleSnapshot() throws {
    let suite = "team-missing-scope-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let store = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: InMemorySecretStore(),
      executionStore: SavedTeamRecoveryFixture([]), fileURL: root.appendingPathComponent("team.sqlite3"))
    let original = durableTeamSnapshot("deleted-group")
    XCTAssertTrue(store.upsert(original))
    var progressed = original
    progressed.members[0].status = .succeeded
    progressed.members[0].output = "Saved child result"
    progressed.updatedAtMillis += 1
    XCTAssertTrue(store.upsert(progressed))
    XCTAssertNil(try store.cancelRecoveryForMissingScope(expected: original, now: progressed.updatedAtMillis + 1))
    let stopped = try XCTUnwrap(store.cancelRecoveryForMissingScope(expected: progressed, now: progressed.updatedAtMillis + 1))
    XCTAssertEqual(stopped.state, .cancelled)
    XCTAssertEqual(stopped.members, progressed.members)
    XCTAssertEqual(store.snapshot(supervisorRunId: progressed.supervisorRunId), stopped)
    XCTAssertTrue(AgentTeamRecoveryRetryState.missingScope(conversation: "ios-agent-deleted",
      session: nil, requiresRoster: true))
    XCTAssertFalse(AgentTeamRecoveryRetryState.missingScope(conversation: "direct-contact",
      session: nil, requiresRoster: false))
  }

  func testCollaborationEvolutionRejectsUnboundOptionsAndUnsupportedNovelty() throws {
    let raw = """
    {"format":"galaxyssi.research-artifact.v1","workspace":[
      {"id":"gap","base_revision":0,"kind":"capability_gap","title":"Gap","parents":[],"body":{
        "capability_gap":{"category":"verification","symptom":"Unstable output","needed_capability":"Repeat checks",
          "learning_options":[{"id":"repeat","action":"Repeat","expected_gain":"Confidence","cost":"One trial",
            "goal_relevance":"Check stability","verification":"Compare outputs"}],"chosen_option":"repeat","rationale":"Isolate noise"}}},
      {"id":"idea","base_revision":0,"kind":"innovation","title":"Idea","parents":[],"body":{
        "innovation":{"origin":"gap","novelty_scope":"not_checked","hypothesis":"Check twice","mechanism":"Pair trials",
          "difference":"Same input","prior_art":"Not reviewed","falsifier":"No improvement","domain":"Testing",
          "applies_when":"Repeatable","risks":"Correlated errors","alternatives":["Independent test"],
          "predictions":[{"id":"p1","statement":"Detect instability","test":"Repeat on baseline"}]}}}
    ]}
    """
    var drafts = try XCTUnwrap(AgentCollaborationResearchEnvelope.publication(in: raw))
    XCTAssertTrue(drafts.allSatisfy(AgentCollaborationEvolutionIntake.validates))
    var gap = try XCTUnwrap(drafts[0].body["capability_gap"]?.objectValue)
    gap["chosen_option"] = .string("missing")
    drafts[0].body["capability_gap"] = .object(gap)
    XCTAssertFalse(AgentCollaborationEvolutionIntake.validates(drafts[0]))
    var idea = try XCTUnwrap(drafts[1].body["innovation"]?.objectValue)
    idea["origin"] = .string("combination")
    drafts[1].body["innovation"] = .object(idea)
    XCTAssertFalse(AgentCollaborationEvolutionIntake.validates(drafts[1]))
    idea["origin"] = .string("gap")
    idea["novelty_scope"] = .string("searched_scope_only")
    drafts[1].body["innovation"] = .object(idea)
    XCTAssertFalse(AgentCollaborationEvolutionIntake.validates(drafts[1]))
  }

  func testRejectedResearchReplyReopensWithExactScopeAndOriginalBytes() throws {
    let suite = "research-rejection-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    var team = durableTeamSnapshot("rejected-run")
    let malformed = "{\"format\":\"galaxyssi.research-artifact.v1\",\"workspace\":{}}"
    team.members[0].status = .succeeded
    team.members[0].replyContent = malformed
    let member = team.members[0]
    let scope = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId,
      conversationId: team.conversationId, turnId: team.taskId, memberId: member.memberId,
      sourceId: member.sourceMessageId)
    XCTAssertTrue(history.upsert(team))
    XCTAssertThrowsError(try history.publishSavedResearchReply(malformed + " ", scope: scope))
    XCTAssertNil(try history.rejectedResearchReply(scope: scope))
    XCTAssertThrowsError(try history.publishSavedResearchReply(malformed, scope: scope))
    XCTAssertThrowsError(try history.publishSavedResearchReply(malformed, scope: scope))
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    let rejected = try XCTUnwrap(reopened.rejectedResearchReply(scope: scope))
    XCTAssertEqual(rejected.raw, malformed)
    XCTAssertEqual(rejected.rejection.reason, .malformedEnvelope)
    XCTAssertNil(try reopened.committedResearchRevisions(scope: scope))
    var foreign = scope
    foreign.turnId = "other-turn"
    XCTAssertNil(try reopened.rejectedResearchReply(scope: foreign))
    reopened.removeResearchObjects(conversationId: scope.conversationId)
    XCTAssertNil(try reopened.rejectedResearchReply(scope: scope))
  }

  func testCollaborationMemberProjectionKeepsCurrentWorkAndOriginalAttempts() {
    var snapshot = durableTeamSnapshot("current-projection")
    let rosterId = UUID().uuidString.lowercased()
    let otherId = UUID().uuidString.lowercased()
    snapshot.members = [
      .init(agentId: "shared-model", status: .succeeded, output: "original", updatedAtMillis: 100, instanceId: rosterId),
      .init(agentId: "shared-model", status: .running, updatedAtMillis: 50, instanceId: rosterId + ":revise"),
      .init(agentId: "shared-model", status: .queued, updatedAtMillis: 60, instanceId: rosterId + ":recheck"),
      .init(agentId: "shared-model", status: .succeeded, updatedAtMillis: 40, instanceId: otherId)
    ]
    XCTAssertEqual(AgentTeamProgressPolicy.currentCollaborationMembers(snapshot).map(\.memberId),
      [rosterId + ":revise", otherId])
    snapshot.members[1].status = .succeeded
    XCTAssertEqual(AgentTeamProgressPolicy.currentCollaborationMembers(snapshot).first?.memberId, rosterId + ":recheck")
    XCTAssertEqual(snapshot.members.count, 4)
    XCTAssertEqual(snapshot.members.first?.output, "original")
  }

  func testCollaborationPanelKeepsRecoverySeparateFromThePublishedTranscript() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "team-panel-recovery-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    func openHistory() -> AgentTeamExecutionHistoryStore {
      AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
        executionStore: SavedTeamRecoveryFixture([]), fileURL: root.appendingPathComponent("team.sqlite3"))
    }

    let store = makeStore()
    let person = UUID().uuidString.lowercased()
    var current = durableTeamSnapshot("panel-recovery")
    let outgoing = store.appendOutgoing("Current assignment", to: "hermes",
      turnId: current.taskId, conversationOverride: current.conversationId)
    let source = UUID().uuidString
    current.primaryInstanceId = person
    current.createdAtMillis = 100
    current.updatedAtMillis = 100
    current.state = .waitingResponse
    current.members = [
      .init(agentId: current.primaryAgentId, deliveryMode: .respond, status: .queued, updatedAtMillis: 100,
        instanceId: person, sourceMessageId: source, dispatchCheckpoint: .accepted, executionStartedAtMillis: 99),
      .init(agentId: current.primaryAgentId, status: .failed, errorMessage: "Older failed attempt",
        updatedAtMillis: 90, instanceId: person + ":revise")
    ]

    let history = openHistory()
    for attempt in 1...22 {
      var failed = durableTeamSnapshot("panel-failed-\(attempt)")
      failed.taskId = "older-turn-\(attempt)"
      failed.state = .failed
      failed.createdAtMillis = Int64(attempt)
      failed.updatedAtMillis = Int64(attempt)
      failed.primaryInstanceId = person
      failed.members[0].instanceId = person
      failed.members[0].status = .failed
      XCTAssertTrue(history.upsert(failed))
    }
    XCTAssertTrue(history.upsert(current))

    func panel(_ history: AgentTeamExecutionHistoryStore) throws -> [AgentTeamMemberSnapshot] {
      let snapshot = try XCTUnwrap(history.latestCollaborationRun(conversationId: current.conversationId))
      XCTAssertEqual(snapshot.supervisorRunId, current.supervisorRunId)
      return AgentTeamProgressPolicy.currentCollaborationMembers(snapshot)
    }
    func transcript() async throws -> [ChatMessage] {
      let page = await store.chatHistoryDatabase.agentTranscriptWindow(conversationId: current.conversationId, limit: 30)
      return try XCTUnwrap(page).messages
    }

    XCTAssertEqual(try panel(history).map(\.memberId), [person])
    XCTAssertEqual(try panel(history).map(\.dispatchCheckpoint), [.accepted])
    let waitingTranscript = try await transcript()
    XCTAssertEqual(waitingTranscript.map(\.id), [outgoing.id])
    current.state = .running
    current.updatedAtMillis = 101
    current.members[0].status = .running
    current.members[0].updatedAtMillis = 101
    XCTAssertTrue(history.upsert(current))
    XCTAssertEqual(try panel(history).map(\.status), [.running])
    let reconcilingTranscript = try await transcript()
    XCTAssertEqual(reconcilingTranscript.map(\.id), [outgoing.id])

    let owner = try XCTUnwrap(history.recoveryContext(source: source, conversation: current.conversationId,
      turn: current.taskId, contact: current.primaryAgentId)?.owner)
    let identity = AgentTaskIdentity(clientRouteId: "route", conversationId: current.conversationId,
      taskId: source, turnId: current.taskId)
    let binding = try XCTUnwrap(AgentDesktopReplyBinding.teamPrimary(owner: owner,
      desktopId: "desktop", agentId: "codex", identity: identity, outgoing: outgoing))
    let observation = AgentTeamReplyObservation(generation: 2, sequence: 10)
    let answer = "Recovered original result"
    func recover(_ history: AgentTeamExecutionHistoryStore) throws -> ChatMessage {
      let message = try store.persistTransportIncoming(answer, from: binding.displayContactId,
        remoteMessageId: "recovered-result", conversationId: identity.conversationId, turnId: identity.turnId,
        richOutputJson: "", tracePrefix: "desktop_team_result")
      XCTAssertTrue(try history.commitRecoveredPrimary(binding: binding, content: answer, rich: "",
        success: true, observation: observation, now: 102))
      return message
    }

    let reply = try recover(history)
    let reopened = openHistory()
    XCTAssertEqual(try recover(reopened).id, reply.id)
    XCTAssertEqual(try panel(reopened).map(\.status), [.succeeded])
    let replies = try await transcript().filter { !$0.isMine }
    XCTAssertEqual(replies.map(\.id), [reply.id])
    XCTAssertEqual(replies.map(\.content), [answer])
    let completed = try XCTUnwrap(replies.first)
    let start = Int64(outgoing.createdAt.timeIntervalSince1970 * 1_000)
    XCTAssertEqual(AgentTranscriptExecutionProgress.resolve(owned: nil, cached: nil,
      deliveredAt: AgentTranscriptExecutionProgress.finalDeliveryTime(completed), requestStartedAt: start)?.status, .completed)
    let records = try reopened.readCollaborationResults(conversationId: current.conversationId, limit: 30)
    XCTAssertEqual(records.filter { $0.state == .failed }.count, 22)
    XCTAssertEqual(records.first { $0.supervisorRunId == current.supervisorRunId }?.members.last?.status, .failed)
  }

  func testCollaborationReviewerIdentityCannotChangeWithResearchStage() {
    let rosterId = UUID().uuidString
    XCTAssertEqual(AgentTeamProgressPolicy.stableCollaborationMemberId(rosterId + ":revise"), rosterId.lowercased())
    XCTAssertEqual(AgentTeamProgressPolicy.stableCollaborationMemberId(rosterId + ":recheck"), rosterId.lowercased())
    XCTAssertEqual(AgentTeamProgressPolicy.stableCollaborationMemberId(rosterId + ":unknown"), rosterId + ":unknown")
    XCTAssertNotEqual(AgentTeamProgressPolicy.stableCollaborationMemberId(UUID().uuidString + ":revise"), rosterId.lowercased())
  }

  func testCollaborationTimingUsesRecordedExecutionBounds() throws {
    var snapshot = durableTeamSnapshot("timed-run")
    snapshot.state = .running
    XCTAssertNil(snapshot.elapsedExecutionMillis(now: 5_000))
    snapshot.executionStartedAtMillis = 1_000
    XCTAssertEqual(snapshot.elapsedExecutionMillis(now: 5_000), 4_000)
    snapshot.state = .succeeded
    XCTAssertNil(snapshot.elapsedExecutionMillis(now: 5_000))
    snapshot.executionEndedAtMillis = 6_000
    let restored = try JSONDecoder().decode(AgentTeamExecutionSnapshot.self, from: JSONEncoder().encode(snapshot))
    XCTAssertEqual(restored.elapsedExecutionMillis(now: 20_000), 5_000)
    snapshot.state = .interrupted
    snapshot.executionEndedAtMillis = nil
    snapshot.interruptedAtMillis = 4_000
    XCTAssertEqual(snapshot.elapsedExecutionMillis(now: 20_000), 3_000)
  }

  func testCollaborationRecallExcludesCurrentTurnPendingRunsAndOtherGroups() {
    let suite = "collaboration-recall-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    var prior = durableTeamSnapshot("prior")
    prior.taskId = "past"
    prior.createdAtMillis = 10
    prior.updatedAtMillis = 50
    prior.state = .succeeded
    prior.finalOutput = "Verified battery comparison"
    var current = prior
    current.supervisorRunId = "current"
    current.taskId = "turn"
    current.createdAtMillis = 20
    current.updatedAtMillis = 30
    var foreign = prior
    foreign.supervisorRunId = "foreign"
    foreign.conversationId = "another-group"
    var pending = prior
    pending.supervisorRunId = "pending"
    pending.state = .running
    for record in [prior, current, foreign, pending] { XCTAssertTrue(history.upsert(record)) }
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    XCTAssertEqual(reopened.recallCollaborationResults(conversationId: prior.conversationId,
      excludingTurnId: "turn", query: "BATTERY comparison").map(\.supervisorRunId), ["prior"])
    XCTAssertTrue(reopened.recallCollaborationResults(conversationId: prior.conversationId,
      excludingTurnId: "turn", query: "unmatched").isEmpty)
    XCTAssertEqual(reopened.latestCollaborationRun(conversationId: prior.conversationId)?.supervisorRunId, "current")
  }

  func testCandidateDirectoryRecallsExactFailedNativeTestsWithoutExecutionAuthority() throws {
    let suite = "candidate-recall-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
    let secrets = InMemorySecretStore()
    let file = folder.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    let database = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    let producer = durableTeamSnapshot("candidate-tests")
    let author = try XCTUnwrap(producer.members.first { !$0.status.isTerminal })
    XCTAssertTrue(history.upsert(producer))
    func object(_ number: Int64, kind: AgentCollaborationResearchDraft.Kind, body: AgentMcpJSONObject,
                parents: [AgentCollaborationResearchReference] = []) -> AgentCollaborationResearchRevision {
      let ref = AgentCollaborationResearchReference(objectId: String(format: "%064llx", number),
        revision: 1, sha256: String(format: "%064llx", number + 100))
      return .init(reference: ref, previousHash: nil, runId: producer.supervisorRunId, turnId: producer.taskId,
        authorId: author.memberId, sourceId: author.sourceMessageId,
        draft: .init(id: "item", objectId: nil, baseRevision: 0, kind: kind, title: "Unfinished work",
          body: [kind.rawValue: .object(body)], parents: parents))
    }
    let source = object(1, kind: .executableTool, body: [
      "name": .string("WeatherNormalizer"), "source": .string("only_in_source_code")
    ])
    let sourceReference = AgentCollaborationCandidateRecall.reference(source.reference)
    let plan = object(2, kind: .toolTestPlan, body: [
      "executable_tool": .object(sourceReference), "cases": .array([.object(["expected": .string("only_in_expected")])])
    ], parents: [source.reference])
    try database.transaction {
      for row in [source, plan] {
        try database.insertResearchRecord(row, conversationId: producer.conversationId,
          key: "object:" + row.reference.objectId, revision: row.reference.revision)
      }
    }
    let planReference = AgentCollaborationCandidateRecall.reference(plan.reference)
    for index in 0...13 {
      let runtime: AgentMcpJSONObject = [
        "mode": .string("test"), "tool_test_plan": .object(planReference), "executable_tool": .object(sourceReference),
        "passed": .bool(false), "diagnostic": .string("expected 4; got 3")
      ]
      let result = AgentNativeToolResult(status: .failed,
        output: index == 13 ? [:] : ["collaboration_tool_receipt": .object(runtime)], message: "",
        receipt: .init(invocationId: "test-\(index)", startedAtEpochMillis: 1, finishedAtEpochMillis: 2,
          durationMillis: 1, status: .failed, inputSha256: "input", outputSha256: "output", replayed: index == 1),
        provenance: .init(toolId: AgentIOSOnDeviceRuntimeNativeToolCatalog.execute, toolVersion: "1", location: .application,
          executorId: AgentIOSOnDeviceRuntimeNativeToolCatalog.brokerExecutorId, contractVersion: "1"))
      _ = try history.recordNativeObservation(.init(runId: producer.supervisorRunId, conversationId: producer.conversationId,
        turnId: producer.taskId, memberId: author.memberId, sourceId: author.sourceMessageId,
        input: ["collaboration_tool": .object(["mode": .string("test"), "tool_test_plan": .object(planReference)])],
        result: result))
    }
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    var reader = durableTeamSnapshot("candidate-review")
    reader.taskId = "candidate-review-turn"
    XCTAssertTrue(reopened.upsert(reader))
    let member = try XCTUnwrap(reader.members.first { !$0.status.isTerminal })
    let scope = AgentCollaborationToolEvidenceScope(runId: reader.supervisorRunId, conversationId: reader.conversationId,
      turnId: reader.taskId, memberId: member.memberId, sourceId: member.sourceMessageId)
    func search(_ term: String) throws -> [AgentMcpJSONObject] {
      let found = try reopened.recallCollaborationOriginal(["mode": .string("capabilities"), "query": .string(term)], scope: scope)
      return found["capabilities"]?.arrayValue?.compactMap(\.objectValue) ?? []
    }
    let matches = try search("weathernormalizer")
    XCTAssertEqual(Set(matches.map { $0.string("kind") }), ["executable_tool", "tool_test_plan"])
    XCTAssertTrue(try search("only_in_source_code").isEmpty)
    XCTAssertTrue(try search("only_in_expected").isEmpty)
    let hit = try XCTUnwrap(matches.first { $0.string("kind") == "executable_tool" })
    XCTAssertEqual(hit["grants_permissions"], .bool(false))
    var selector = try XCTUnwrap(hit["usage_recall"]?.objectValue)
    let first = try reopened.recallCollaborationOriginal(selector, scope: scope)
    let firstRows = try XCTUnwrap(first["records"]?.arrayValue?.compactMap(\.objectValue))
    XCTAssertEqual(firstRows.count, 12)
    XCTAssertTrue(firstRows.allSatisfy { $0["subject_binding"] == .string("runtime_resolved_candidate") })
    selector["cursor"] = try XCTUnwrap(first["next_cursor"])
    let last = try reopened.recallCollaborationOriginal(selector, scope: scope)
    XCTAssertEqual(last["records"]?.arrayValue?.count, 1)
    var wrongSelector = AgentCollaborationCandidateRecall.selector(plan.reference)
    wrongSelector["cursor"] = selector["cursor"]
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(wrongSelector, scope: scope))
    var planSelector = AgentCollaborationCandidateRecall.selector(plan.reference)
    let planPage = try reopened.recallCollaborationOriginal(planSelector, scope: scope)
    planSelector["cursor"] = planPage["next_cursor"]
    let tail = try reopened.recallCollaborationOriginal(planSelector, scope: scope)
    let rows = (planPage["records"]?.arrayValue ?? []) + (tail["records"]?.arrayValue ?? [])
    XCTAssertEqual(rows.count, 14)
    XCTAssertTrue(rows.contains { $0.objectValue?["runtime_report_available"] == .bool(false) })
    XCTAssertTrue(rows.contains { $0.objectValue?["replayed"] == .bool(true) })
    let original = try XCTUnwrap(firstRows.first?["read_original"]?.objectValue)
    let recalled = try reopened.recallCollaborationOriginal(original, scope: scope)
    XCTAssertTrue(recalled.string("content").contains("expected 4; got 3"))
    XCTAssertEqual(recalled["source_reference"]?.objectValue?["sha256"], original["sha256"])
    reopened.removeResearchObjects(conversationId: scope.conversationId)
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(original, scope: scope))
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(selector, scope: scope))
  }

  func testNativeObservationRequiresExactActiveMemberAndRejectsDeletedGroup() throws {
    let suite = "native-evidence-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: InMemorySecretStore(),
      executionStore: SavedTeamRecoveryFixture([]), fileURL: root.appendingPathComponent("team.sqlite"))
    let team = durableTeamSnapshot("native-run")
    let member = try XCTUnwrap(team.members.first { !$0.status.isTerminal })
    XCTAssertTrue(history.upsert(team))
    let result = AgentNativeToolResult(status: .succeeded, output: ["value": .int(1)], message: "",
      receipt: AgentNativeToolReceipt(invocationId: "invocation", startedAtEpochMillis: 1,
        finishedAtEpochMillis: 2, durationMillis: 1, status: .succeeded, inputSha256: "input", outputSha256: "output"),
      provenance: AgentNativeToolProvenance(toolId: "test.tool", toolVersion: "1", location: .phone,
        executorId: "test", contractVersion: "1"))
    var observation = AgentCollaborationNativeToolObservation(runId: team.supervisorRunId,
      conversationId: team.conversationId, turnId: team.taskId, memberId: member.memberId,
      sourceId: member.sourceMessageId, input: [:], result: result)
    let receipt = try history.recordNativeObservation(observation)
    XCTAssertEqual(receipt["origin"], .string("ios_native_tool"))
    XCTAssertEqual(try history.recordNativeObservation(observation), receipt)
    observation.sourceId = "foreign"
    XCTAssertThrowsError(try history.recordNativeObservation(observation))
    observation.sourceId = member.sourceMessageId
    history.removeResearchObjects(conversationId: team.conversationId)
    XCTAssertThrowsError(try history.recordNativeObservation(observation))
  }

  func testNativeOriginalRecallReopensAndRequiresAnExactVisibleSource() throws {
    let suite = "native-original-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite")
    func open() -> AgentTeamExecutionHistoryStore {
      AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
        executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    }
    let history = open()
    var team = durableTeamSnapshot("native-original")
    let author = team.members[0]
    team.members[1].dispatchDependencyMemberIds = [author.memberId]
    XCTAssertTrue(history.upsert(team))
    func scope(_ snapshot: AgentTeamExecutionSnapshot, index: Int) -> AgentCollaborationToolEvidenceScope {
      .init(runId: snapshot.supervisorRunId, conversationId: snapshot.conversationId, turnId: snapshot.taskId,
        memberId: snapshot.members[index].memberId, sourceId: snapshot.members[index].sourceMessageId)
    }
    let longInput = String(repeating: "original parameters ", count: 240)
    let result = AgentNativeToolResult(status: .rejected, output: [:], message: "Rejected before execution",
      receipt: AgentNativeToolReceipt(invocationId: "replay", startedAtEpochMillis: 1,
        finishedAtEpochMillis: 2, durationMillis: 1, status: .rejected, inputSha256: "input",
        outputSha256: "output", replayed: true, originalInvocationId: "original"),
      provenance: AgentNativeToolProvenance(toolId: "test.tool", toolVersion: "2", location: .phone,
        executorId: "test", contractVersion: "1"))
    let observation = AgentCollaborationNativeToolObservation(runId: team.supervisorRunId,
      conversationId: team.conversationId, turnId: team.taskId, memberId: author.memberId,
      sourceId: author.sourceMessageId, input: ["parameters": .string(longInput)], result: result)
    let receipt = try history.recordNativeObservation(observation)
    let selector: AgentMcpJSONObject = ["mode": .string("evidence"),
      "evidence_id": .string(receipt.string("evidence_id")), "sha256": .string(receipt.string("sha256"))]
    let reader = scope(team, index: 1)
    XCTAssertThrowsError(try history.recallCollaborationOriginal(selector, scope: reader))
    let own = try history.recallCollaborationOriginal(selector, scope: scope(team, index: 0))
    XCTAssertEqual(own["host_read_coverage"]?.objectValue?["complete"], .bool(false))

    team.members[0].status = .failed
    XCTAssertTrue(history.upsert(team))
    let reopened = open()
    var wrongHash = selector
    wrongHash["sha256"] = .string(String(repeating: "0", count: 64))
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(wrongHash, scope: reader))
    var anotherRun = durableTeamSnapshot("another-native-run")
    XCTAssertTrue(reopened.upsert(anotherRun))
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(selector, scope: scope(anotherRun, index: 0)))
    anotherRun = durableTeamSnapshot("another-native-group")
    anotherRun.conversationId = "foreign-group"
    XCTAssertTrue(reopened.upsert(anotherRun))
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(selector, scope: scope(anotherRun, index: 0)))

    let first = try reopened.recallCollaborationOriginal(selector, scope: reader, evidenceRead: .desktopPreview)
    XCTAssertEqual(first["source_reference"]?.objectValue?["origin"], .string("ios_native_tool"))
    XCTAssertEqual(first["source_reference"]?.objectValue?["status"], .string("rejected"))
    XCTAssertEqual(first["source_reference"]?.objectValue?["replayed"], .bool(true))
    XCTAssertNil(first["host_read_coverage"])
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(selector, scope: reader,
      evidenceRead: .desktopConfirm(contentHash: String(repeating: "0", count: 64))))
    var lastSelector = selector
    lastSelector["offset"] = .int(4_000)
    let last = try reopened.recallCollaborationOriginal(lastSelector, scope: reader)
    XCTAssertEqual(last["next_offset"], .null)
    XCTAssertEqual(last["host_read_coverage"]?.objectValue?["first_missing_offset"], .int(0))
    let deliveredHash = AgentDesktopNativeEvidenceDelivery.digest(first.string("content"))
    let confirmed = try reopened.recallCollaborationOriginal(selector, scope: reader,
      evidenceRead: .desktopConfirm(contentHash: deliveredHash))
    XCTAssertEqual(confirmed["host_read_coverage"]?.objectValue?["first_missing_offset"], .int(2_000))
    XCTAssertEqual(try open().recallCollaborationOriginal(selector, scope: reader,
      evidenceRead: .desktopConfirm(contentHash: deliveredHash))["host_read_coverage"], confirmed["host_read_coverage"])
    var middleSelector = selector
    middleSelector["offset"] = .int(2_000)
    let middle = try open().recallCollaborationOriginal(middleSelector, scope: reader)
    XCTAssertEqual(middle["host_read_coverage"]?.objectValue?["complete"], .bool(true))
    let joined = Data((first.string("content") + middle.string("content") + last.string("content")).utf8)
    let original = try JSONDecoder().decode(AgentCollaborationNativeToolObservation.self, from: joined)
    XCTAssertEqual(original.input, observation.input)
    XCTAssertEqual(original.result, observation.result)
    var later = durableTeamSnapshot("native-later-turn")
    later.taskId = "later-turn"
    XCTAssertTrue(reopened.upsert(later))
    let laterPage = try reopened.recallCollaborationOriginal(selector, scope: scope(later, index: 0))
    XCTAssertEqual(laterPage["source_reference"], first["source_reference"])
    XCTAssertEqual(laterPage["host_read_coverage"]?.objectValue?["complete"], .bool(false))
    reopened.removeResearchObjects(conversationId: team.conversationId)
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(selector, scope: reader))
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(selector, scope: scope(later, index: 0)))
  }

  func testDesktopNativeEvidenceReceiptBindsPageRouteAndProcess() throws {
    let delivery = AgentDesktopNativeEvidenceDelivery()
    let input: AgentMcpJSONObject = ["mode": .string("evidence"), "offset": .int(0),
      "evidence_id": .string(String(repeating: "a", count: 64)), "sha256": .string(String(repeating: "b", count: 64))]
    XCTAssertTrue(AgentDesktopNativeEvidenceDelivery.accepts(input))
    let receipt = try XCTUnwrap(delivery.issue(content: "original page", binding: "route-a", input: input, now: 1_000))
    let digest = AgentDesktopNativeEvidenceDelivery.digest("original page")
    XCTAssertEqual(delivery.confirm(receipt, binding: "route-a", input: input, now: 2_000), digest)
    XCTAssertEqual(delivery.confirm(receipt, binding: "route-a", input: input, now: 2_001), digest)
    XCTAssertNil(delivery.confirm(receipt, binding: "route-b", input: input, now: 2_000))
    XCTAssertNil(delivery.confirm(receipt, binding: "route-a", input: input, now: 61_000))
    XCTAssertNil(AgentDesktopNativeEvidenceDelivery().confirm(receipt, binding: "route-a", input: input, now: 2_000))
    var next = input
    next["offset"] = .int(2_000)
    XCTAssertNil(delivery.confirm(receipt, binding: "route-a", input: next, now: 2_000))
    next["offset"] = .string("2000")
    XCTAssertFalse(AgentDesktopNativeEvidenceDelivery.accepts(next))
    var tampered = receipt
    tampered["content_sha256"] = .string(String(repeating: "c", count: 64))
    XCTAssertNil(delivery.confirm(tampered, binding: "route-a", input: input, now: 2_000))
  }

  func testCloudEvidenceReceiptIsScopedAndRejectsChangedReplay() throws {
    let suite = "team-cloud-evidence-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    let team = durableTeamSnapshot("cloud-team")
    XCTAssertTrue(history.upsert(team))
    let member = try XCTUnwrap(team.members.first { !$0.status.isTerminal })
    let scope = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId,
      conversationId: team.conversationId, turnId: team.taskId, memberId: member.memberId,
      sourceId: member.sourceMessageId)
    var observation = AgentCollaborationCloudToolEvidence(scope: scope, round: 1,
      call: AssembledToolCall(callId: "tool-call", index: 0, name: "web_search", argumentsJson: "{}"),
      output: String(repeating: "search result ", count: 320), succeeded: true, startedAtMillis: 10, finishedAtMillis: 12)
    let receipt = try history.recordCloudEvidence(observation)
    var failed = observation
    failed.succeeded = false
    failed.output = "sensitive failure detail"
    var failedIds = Set<String>()
    for round in 20...28 {
      failed.round = round
      if round == 28 {
        failed.succeeded = true
        failed.output = "{\"success\":false}"
      }
      failedIds.insert(try history.recordCloudEvidence(failed).string("evidence_id"))
    }
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    let directory: AgentMcpJSONObject = ["mode": .string("problems")]
    let rules: AgentMcpJSONObject = ["mode": .string("evolution_rules"), "topic": .string("catalog")]
    let catalog = try reopened.recallCollaborationOriginal(rules, scope: scope)
    XCTAssertEqual(catalog["trust"], .string("host_schema_not_execution_authority"))
    XCTAssertTrue(catalog.string("content").contains("workflows"))
    XCTAssertFalse(catalog.string("content").contains("self_research"))
    let suffix = try reopened.recallCollaborationOriginal(
      ["mode": .string("evolution_rules"), "topic": .string("catalog"), "offset": .int(10)], scope: scope)
    XCTAssertEqual(suffix.string("content"), String(catalog.string("content").dropFirst(10)))
    var foreignRulesScope = scope
    foreignRulesScope.sourceId = "foreign-source"
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(rules, scope: foreignRulesScope))
    let unknown = try reopened.recallCollaborationOriginal(
      ["mode": .string("evolution_rules"), "topic": .string("unknown")], scope: scope)
    XCTAssertEqual(unknown["error"], .string("unknown_evolution_topic"))
    let firstProblems = try reopened.recallCollaborationOriginal(directory, scope: scope)
    let entries = try XCTUnwrap(firstProblems["problems"]?.arrayValue)
    XCTAssertEqual(entries.count, 8)
    XCTAssertFalse(AgentMcpJSONCodec.stringify(firstProblems).contains("sensitive failure detail"))
    let lastProblems = try reopened.recallCollaborationOriginal(
      ["mode": .string("problems"), "cursor": .string(firstProblems.string("next_cursor"))], scope: scope)
    let tail = try XCTUnwrap(lastProblems["problems"]?.arrayValue)
    XCTAssertEqual(tail.count, 1)
    XCTAssertEqual(lastProblems["next_cursor"], .null)
    XCTAssertEqual(Set((entries + tail).compactMap { $0.objectValue?.string("evidence_id") }), failedIds)
    let other = try XCTUnwrap(team.members.first { $0.memberId != scope.memberId })
    var otherScope = scope
    otherScope.memberId = other.memberId
    otherScope.sourceId = other.sourceMessageId
    let isolated = try reopened.recallCollaborationOriginal(directory, scope: otherScope)
    XCTAssertEqual(isolated["problems"], .array([]))
    XCTAssertEqual(try reopened.recordCloudEvidence(observation), receipt)
    let input: AgentMcpJSONObject = [
      "mode": .string("evidence"), "evidence_id": receipt["evidence_id"] ?? .null,
      "sha256": receipt["sha256"] ?? .null
    ]
    let firstPage = try reopened.recallCollaborationOriginal(input, scope: scope)
    guard case .object(let source)? = firstPage["source_reference"],
          case .int(let next)? = firstPage["next_offset"] else {
      return XCTFail("Expected an original source citation and a second page")
    }
    XCTAssertEqual(source["evidence_id"], receipt["evidence_id"])
    XCTAssertEqual(source["sha256"], receipt["sha256"])
    XCTAssertEqual(source["tool"], .string("web_search"))
    var lastInput = input
    lastInput["offset"] = .int(4_000)
    let lastPage = try reopened.recallCollaborationOriginal(lastInput, scope: scope)
    XCTAssertEqual(lastPage["next_offset"], .null)
    guard case .object(let partial)? = lastPage["host_read_coverage"] else {
      return XCTFail("Expected persisted partial coverage")
    }
    XCTAssertEqual(partial["complete"], .bool(false))
    XCTAssertEqual(partial["mode"], .string("scoped_pages"))
    XCTAssertEqual(partial["reader"]?.objectValue?["source_id"], .string(scope.sourceId))
    XCTAssertEqual(partial["first_missing_offset"], .int(next))
    var secondInput = input
    secondInput["offset"] = .int(next)
    let recovered = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    let secondPage = try recovered.recallCollaborationOriginal(secondInput, scope: scope)
    XCTAssertEqual(secondPage["source_reference"], firstPage["source_reference"])
    guard case .object(let full)? = secondPage["host_read_coverage"] else {
      return XCTFail("Expected complete coverage after filling the gap")
    }
    XCTAssertEqual(full["complete"], .bool(true))
    XCTAssertEqual(full["mode"], .string("scoped_pages"))
    XCTAssertEqual(full["reader"]?.objectValue?["member_id"], .string(scope.memberId))
    XCTAssertEqual(full["first_missing_offset"], .null)
    let content = firstPage.string("content") + secondPage.string("content") + lastPage.string("content")
    XCTAssertTrue(content.contains("web_search"))
    let fileDigest = SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    XCTAssertEqual(full["content_utf8_sha256"], .string(fileDigest))
    XCTAssertEqual(partial["content_utf8_sha256"], full["content_utf8_sha256"])
    XCTAssertNotEqual(full["content_sha256"], full["content_utf8_sha256"])
    XCTAssertEqual(full["content_sha256_encoding"], .string("galaxyssi_json_string_utf8_v1"))
    XCTAssertEqual(full["content_digest_scope"], .string("complete_evidence_content"))
    XCTAssertEqual(firstPage["offset_unit"], .string("utf16_code_units"))
    var invalidScope = scope
    invalidScope.memberId = "foreign-member"
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(input, scope: invalidScope))
    var invalidInput = input
    invalidInput["sha256"] = .string(String(repeating: "f", count: 64))
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(invalidInput, scope: scope))
    observation.output = "different"
    XCTAssertThrowsError(try reopened.recordCloudEvidence(observation))
    observation.scope.conversationId = "other-group"
    XCTAssertThrowsError(try reopened.recordCloudEvidence(observation))
    let fallback = CloudConversationStreamEngine.cloudEvidenceOutput("{}", receipt: nil)
    XCTAssertTrue(fallback.contains("not_durable"))
    XCTAssertFalse(fallback.contains("galaxyssi_evidence_receipt"))
    var unread = observation
    unread.scope = scope
    unread.round = 2
    let unreadReceipt = try reopened.recordCloudEvidence(unread)
    var finished = team
    let index = try XCTUnwrap(finished.members.firstIndex { $0.memberId == member.memberId })
    finished.members[index].status = .succeeded
    finished.updatedAtMillis += 1
    XCTAssertTrue(reopened.upsert(finished))
    func publish(_ draft: AgentCollaborationResearchDraft) throws -> AgentCollaborationResearchPublication {
      try reopened.publishResearchObjects([draft], runId: scope.runId, conversationId: scope.conversationId,
        turnId: scope.turnId, memberId: scope.memberId, sourceId: scope.sourceId)
    }
    var earlier = durableTeamSnapshot("target-run")
    earlier.taskId = "previous-turn"
    earlier.members[0].status = .succeeded
    XCTAssertTrue(reopened.upsert(earlier))
    let targetPublication = try reopened.publishResearchObjects([
      .init(id: "target", objectId: nil, baseRevision: 0, kind: .artifact, title: "Target",
        body: ["content": .string("Original result")], parents: [])
    ], runId: earlier.supervisorRunId, conversationId: scope.conversationId, turnId: earlier.taskId,
      memberId: earlier.members[0].memberId, sourceId: earlier.members[0].sourceMessageId)
    let target = try XCTUnwrap(targetPublication.references.first)
    var review = AgentCollaborationResearchDraft(id: "review", objectId: nil, baseRevision: 0,
      kind: .acceptanceReview, title: "Review", body: ["acceptance_review": .object([
        "criterion_id": .string("accuracy"), "requirement": .string("Cite the original"),
        "target": .object(["object_id": .string(target.objectId), "revision": .int(target.revision), "sha256": .string(target.sha256)]),
        "verdict": .string("supported"), "rationale": .string("Observed the original"), "unresolved": .array([])
      ])], parents: [target], observations: [
        ["evidence_id": unreadReceipt["evidence_id"] ?? .null, "sha256": unreadReceipt["sha256"] ?? .null]
      ])
    XCTAssertThrowsError(try publish(review))
    review.observations = [["evidence_id": receipt["evidence_id"] ?? .null, "sha256": receipt["sha256"] ?? .null]]
    let reviewPublication = try publish(review)
    XCTAssertEqual(try publish(review).references, reviewPublication.references)
    let savedReview = try XCTUnwrap(reopened.committedResearchRevisions(scope: scope)?.first)
    XCTAssertEqual(savedReview.frozenCloudReads?.first?.evidenceId, source["evidence_id"]?.stringValue)
    XCTAssertEqual(savedReview.frozenCloudReads?.first?.hostReadCoverage, full)
    var later = durableTeamSnapshot("later-review")
    later.taskId = "later-turn"
    XCTAssertTrue(reopened.upsert(later))
    let peer = AgentCollaborationToolEvidenceScope(runId: later.supervisorRunId, conversationId: later.conversationId,
      turnId: later.taskId, memberId: later.members[0].memberId, sourceId: later.members[0].sourceMessageId)
    var sourceAccess = AgentCollaborationSourceAccess.workspaceReference(savedReview.reference)
    sourceAccess["mode"] = .string(AgentCollaborationSourceAccess.mode)
    let peerDirectory = try reopened.recallCollaborationOriginal(sourceAccess, scope: peer)
    let peerReceipt = try XCTUnwrap(peerDirectory["references"]?.arrayValue?.last?.objectValue?["author_read_coverage"]?.objectValue)
    XCTAssertEqual(peerReceipt, full)
    XCTAssertEqual(peerReceipt["transfers_coverage"], .bool(false))
    let peerFirst = try reopened.recallCollaborationOriginal(input, scope: peer)
    XCTAssertEqual(peerFirst["host_read_coverage"]?.objectValue?["complete"], .bool(false))
    XCTAssertEqual(peerFirst["host_read_coverage"]?.objectValue?["reader"]?.objectValue?["member_id"], .string(peer.memberId))
  }

  func testEvidenceUTF16PagesPreserveExistingCoverageAndExactBytes() throws {
    let fragment = "\u{8BC1}\n\"quoted\"\\path\t\u{1F600}e\u{0301}"
    let content = String(repeating: fragment, count: 340)
    let bytes = Data(content.utf8)
    func digest(_ value: String) -> AgentMcpJSONValue {
      .string(SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined())
    }
    let first = try AgentCollaborationEvidenceContent.page(bytes, offset: 0, evidence: true)
    XCTAssertEqual(first.ledgerEnd, 2_000)
    XCTAssertEqual(first.end, Int64(first.content.utf16.count))
    XCTAssertGreaterThan(first.end, first.ledgerEnd)
    let legacy = Data(#"{"spans":[{"start":0,"end":2000}]}"#.utf8)
    var coverage = try JSONDecoder().decode(AgentCollaborationReadCoverage.self, from: legacy)
    let second = try AgentCollaborationEvidenceContent.page(bytes, offset: first.end, evidence: true)
    XCTAssertEqual(try second.firstMissingOffset(coverage.contiguousEnd), .int(first.end))
    XCTAssertEqual(second.wireTotal, Int64(content.utf16.count))
    XCTAssertLessThan(coverage.contiguousEnd, second.total)
    XCTAssertEqual(.string(second.rawDigest), digest(content))
    XCTAssertEqual(.string(second.jsonStringDigest), digest(AgentMcpJSONCodec.stringify(.string(content))))
    XCTAssertNotEqual(.string(second.rawDigest), digest(second.content))
    XCTAssertEqual(coverage.spans, [.init(start: 0, end: 2_000)])
    let emoji = try XCTUnwrap(content.firstIndex(of: "\u{1F600}"))
    XCTAssertThrowsError(try AgentCollaborationEvidenceContent.page(bytes,
      offset: Int64(emoji.utf16Offset(in: content) + 1), evidence: true))
    var cursor = first.end
    var joined = Data(first.content.utf8)
    while cursor < first.wireTotal {
      let page = try AgentCollaborationEvidenceContent.page(bytes, offset: cursor, evidence: true)
      XCTAssertGreaterThan(page.end, cursor)
      guard page.end > cursor else { return }
      joined.append(contentsOf: page.content.utf8)
      coverage.include(start: page.ledgerStart, end: page.ledgerEnd)
      cursor = page.end
    }
    XCTAssertEqual(joined, bytes)
    XCTAssertEqual(try first.firstMissingOffset(coverage.contiguousEnd), .null)
    XCTAssertEqual(first.rawDigest, second.rawDigest)
    XCTAssertEqual(coverage.contiguousEnd, Int64(content.count))
    let workspace = try AgentCollaborationEvidenceContent.page(bytes, offset: 0, evidence: false)
    XCTAssertEqual(workspace.end, workspace.ledgerEnd)
  }

  func testCommittedPredictionOutcomeRecoveryRequiresMatchingFrozenObservation() throws {
    let suite = "prediction-recovery-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    let database = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    for matches in [true, false] {
      var team = durableTeamSnapshot("prediction-\(matches)")
      team.members[1].status = .succeeded
      XCTAssertTrue(history.upsert(team))
      let member = team.members[1]
      let scope = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId, conversationId: team.conversationId,
        turnId: team.taskId, memberId: member.memberId, sourceId: member.sourceMessageId)
      let reference = AgentCollaborationResearchReference(objectId: "outcome-\(matches)", revision: 1, sha256: "revision")
      let draft = AgentCollaborationResearchDraft(id: "outcome", objectId: nil, baseRevision: 0, kind: .predictionOutcome,
        title: "Outcome", body: [:], parents: [],
        observations: [["evidence_id": .string("original"), "sha256": .string("expected")]])
      let revision = AgentCollaborationResearchRevision(reference: reference, previousHash: nil, runId: scope.runId,
        turnId: scope.turnId, authorId: scope.memberId, sourceId: scope.sourceId, draft: draft,
        frozenCloudReads: [.init(evidenceId: "original", sha256: matches ? "expected" : "changed", totalCharacters: 10)])
      let key = "publication:" + AgentMcpJSONCodec.sha256([
        "run": .string(scope.runId), "member": .string(scope.memberId), "source": .string(scope.sourceId)
      ])
      try database.transaction {
        try database.insertResearchRecord(revision, conversationId: scope.conversationId,
          key: "object:" + reference.objectId, revision: reference.revision)
        try database.insertResearchRecord(AgentCollaborationResearchPublication(requestHash: "request", references: [reference]),
          conversationId: scope.conversationId, key: key, revision: 0)
      }
      let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
        executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
      if matches {
        XCTAssertEqual(try reopened.committedResearchRevisions(scope: scope)?.first?.reference, reference)
      } else {
        XCTAssertThrowsError(try reopened.committedResearchRevisions(scope: scope))
      }
    }
  }

  func testDesktopCollaborationCiphertextReplayIsExactScopedAndExpiring() {
    typealias Replay = AgentDesktopCollaborationCiphertextReplay
    func key(_ wire: String = "sealed", profile: String = "phone", pair: String = "desktop",
             route: String = "route", secret: String = "secret") -> String {
      Replay.key(wire: Data(wire.utf8), profile: profile, pair: pair, route: route, secretFingerprint: secret)
    }
    var replay = Replay()
    let exact = key()
    replay.remember(exact, now: 1_000, expiresAt: 61_001)
    XCTAssertFalse(replay.contains(exact, now: 1_000))
    replay.remember(exact, now: 1_000, expiresAt: 2_000)
    replay.remember(exact, now: 1_500, expiresAt: 3_000)
    XCTAssertTrue(replay.contains(exact, now: 1_999))
    for other in [key("fresh encryption"), key(profile: "other"), key(pair: "other"),
                  key(route: "other"), key(secret: "rotated")] {
      XCTAssertFalse(replay.contains(other, now: 1_999))
    }
    XCTAssertFalse(replay.contains(exact, now: 2_000))
  }

  func testDesktopMilestonePhaseCannotSwitchReadIntoPublication() {
    let wire = AgentDesktopCollaborationPublicationWire.self
    XCTAssertTrue(wire.accepts(phase: "publish", input: ["mode": .string("publish")]))
    XCTAssertTrue(wire.accepts(phase: "receipt", input: ["mode": .string("receipt")]))
    XCTAssertFalse(wire.accepts(phase: "receipt", input: ["mode": .string("publish")]))
    XCTAssertFalse(wire.accepts(phase: "read", input: ["mode": .string("read")]))
    XCTAssertTrue(wire.accepts(phase: "validate_assessment", input: ["mode": .string("validate_assessment")]))
    for phase in ["publish", "status", "receipt", "list"] {
      XCTAssertTrue(wire.permits(phase: phase, observer: true))
    }
    XCTAssertTrue(wire.permits(phase: "status", observer: false))
    XCTAssertTrue(wire.permits(phase: "publish", observer: false))
    XCTAssertFalse(wire.permits(phase: "receipt", observer: false))
    XCTAssertFalse(wire.permits(phase: "list", observer: false))
    XCTAssertTrue(wire.permits(phase: "validate_assessment", observer: false))
  }

  func testAssessmentPreflightIdentifiesFieldAndDoesNotClaimAcceptance() {
    let raw = """
    {"format":"galaxyssi.goal-assessment.v1","summary":"Draft","decision":"continue","work":[],"blockers":[],
      "criteria":[{"id":"one","requirement":"Check source","verification":"documentary","status":"open","evidence":[],
      "required_observations":[{"origin":"invented","tool":"search"}]}]}
    """
    let invalid = AgentCollaborationGoalAssessmentPolicy.preflight(raw, establishedContract: false)
    XCTAssertEqual(invalid["success"], .bool(true))
    XCTAssertEqual(invalid["schema_valid"], .bool(false))
    XCTAssertEqual(invalid["field_path"], .string("$.criteria[0].required_observations[0].origin"))
    XCTAssertEqual(invalid["json_valid"], .bool(true))
    XCTAssertEqual(invalid["failure"]?.objectValue?["actual"], .string("invented"))
    XCTAssertTrue(invalid["allowed_values"]?.arrayValue?.contains(.string("ios_cloud_tool")) == true)
    let decision = AgentCollaborationGoalAssessmentPolicy.preflight(
      raw.replacingOccurrences(of: "\"continue\"", with: "\"proceed\""), establishedContract: false)
    XCTAssertEqual(decision["field_path"], .string("$.decision"))
    XCTAssertEqual(decision["failure"]?.objectValue?["actual"], .string("proceed"))
    XCTAssertTrue(decision["allowed_values"]?.arrayValue?.contains(.string("continue")) == true)
    XCTAssertEqual(invalid["acceptance_contract_state"], .string("not_established"))
    let valid = AgentCollaborationGoalAssessmentPolicy.preflight(
      raw.replacingOccurrences(of: "invented", with: "ios_cloud_tool"), establishedContract: true)
    XCTAssertEqual(valid["status"], .string("returned"))
    XCTAssertEqual(valid["schema_valid"], .bool(true))
    XCTAssertEqual(valid["validation_scope"], .string("structure_only_not_admission_or_acceptance"))
    XCTAssertEqual(valid["acceptance_contract_state"], .string("established"))
  }

  func testAssessmentPreflightSharesValidatorSchemaWithAdmissionWithoutEndorsingWork() throws {
    typealias Policy = AgentCollaborationGoalAssessmentPolicy
    let spec: AgentMcpJSONObject = ["id": .string(AgentCollaborationNumericTrial.validatorId),
      "variables": .array([.string("x")]), "cases": .array([.object([
        "id": .string("original"), "input": .object(["x": .int(3)]), "expected": .int(3), "absolute_tolerance": .int(0)
      ])])]
    func draft(_ validator: AgentMcpJSONObject) -> String {
      AgentMcpJSONCodec.stringify(["format": .string("galaxyssi.goal-assessment.v1"), "summary": .string("Draft"),
        "decision": .string("continue"), "criteria": .array([.object([
          "id": .string("one"), "requirement": .string(AgentCollaborationNumericTrial.requirement),
          "verification": .string("computational"), "status": .string("open"), "evidence": .array([]),
          "validator": .object(validator)
        ])]), "work": .array([.object(["id": .string("verify"), "member": .string("owner"),
          "assignment": .string("Review originals")])]), "blockers": .array([])])
    }
    let good = draft(spec)
    var broken = spec
    var row = try XCTUnwrap(spec["cases"]?.arrayValue?.first?.objectValue)
    row["absolute_tolerance"] = .int(-1)
    broken["cases"] = .array([.object(row)])
    let bad = draft(broken)
    let invalid = Policy.preflight(bad, establishedContract: false)
    XCTAssertEqual(invalid["schema_valid"], .bool(false))
    XCTAssertEqual(invalid["failure"]?.objectValue?["path"], .string("$.criteria[0].validator.cases[0].absolute_tolerance"))
    XCTAssertEqual(invalid["failure"]?.objectValue?["code"], .string("invalid_validator"))
    XCTAssertEqual(Policy.evaluate(bad, preserving: [], authorizedMembers: ["owner"], completedWork: []), .needsAssessment)
    let valid = Policy.preflight(good, establishedContract: false)
    XCTAssertEqual(valid["schema_valid"], .bool(true))
    XCTAssertEqual(valid["committed"], .bool(false))
    XCTAssertEqual(valid["goal_accepted"], .bool(false))
    XCTAssertEqual(valid["assignment_completed"], .bool(false))
    XCTAssertTrue(valid["not_checked"]?.arrayValue?.contains(.string("permissions")) == true)
    XCTAssertEqual(Policy.evaluate(good, preserving: [], authorizedMembers: [], completedWork: []), .needsAssessment)
    XCTAssertEqual(Policy.evaluate(good, preserving: [], authorizedMembers: ["owner"], completedWork: []), .schedule(["verify"]))
    XCTAssertNotEqual(valid["draft_sha256"], Policy.preflight(good + "\n", establishedContract: false)["draft_sha256"])
    XCTAssertEqual(Policy.preflight("{", establishedContract: false)["json_syntax"], .string("invalid"))
    let array = Policy.preflight("[]", establishedContract: false)
    XCTAssertEqual(array["json_syntax"], .string("valid"))
    XCTAssertEqual(array["schema_valid"], .bool(false))
  }

  func testCoordinatorAssessmentPreflightDoesNotPublishAndRejectsRetiredAssignments() throws {
    let suite = "preflight-scope-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
    let secrets = InMemorySecretStore()
    let file = folder.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    var team = durableTeamSnapshot("assessment-scope")
    team.members[0].dispatchCheckpoint = .accepted
    XCTAssertTrue(history.upsert(team))
    let owner = team.members[0]
    let scope = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId, memberId: owner.memberId, sourceId: owner.sourceMessageId)
    let draft = #"{"format":"galaxyssi.goal-assessment.v1","summary":"Review","decision":"continue","work":[],"blockers":[],"criteria":[{"id":"one","requirement":"Check","verification":"documentary","status":"open","evidence":[]}]}"#
    let input: AgentMcpJSONObject = ["mode": .string("validate_assessment"), "artifact": .string(draft)]
    let result = try history.publishCollaborationMilestone(input, scope: scope)
    XCTAssertEqual(result["schema_valid"], .bool(true))
    XCTAssertEqual(result["acceptance_contract_state"], .string("not_established"))
    let database = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    XCTAssertTrue(try database.researchObjectHeads(conversationId: scope.conversationId, after: "", limit: 1).isEmpty)
    let query: AgentMcpJSONObject = ["mode": .string("status")]
    let capability = try history.publishCollaborationMilestone(query, scope: scope)
    XCTAssertEqual(capability["status"], .string("returned"))
    XCTAssertEqual(capability["capability"]?.objectValue?["publish_allowed"], .bool(false))
    XCTAssertEqual(capability["capability"]?.objectValue?["grants_authority"], .bool(false))
    let unavailable = try history.publishCollaborationMilestone(["mode": .string("publish"),
      "milestone_id": .string("forbidden"), "artifact": .string("{")], scope: scope)
    XCTAssertEqual(unavailable["error_code"], .string("assignment_not_enrolled"))
    XCTAssertEqual(unavailable["artifact_validated"], .bool(false))
    XCTAssertEqual(unavailable["retryable"], .bool(false))
    XCTAssertNil(unavailable["rejected_draft_preserved"])
    XCTAssertThrowsError(try history.publishCollaborationMilestone(query.merging(["member_id": .string("other")]) { a, _ in a },
      scope: scope))
    var forged = input
    forged["member_id"] = .string("other")
    XCTAssertThrowsError(try history.publishCollaborationMilestone(forged, scope: scope))
    var oversized = input
    oversized["artifact"] = .string(String(repeating: "\" ", count: 50_000))
    XCTAssertThrowsError(try history.publishCollaborationMilestone(oversized, scope: scope))
    var foreign = scope
    foreign.sourceId = "other-source"
    XCTAssertThrowsError(try history.publishCollaborationMilestone(input, scope: foreign))
    team.state = .interrupted
    team.updatedAtMillis += 1
    XCTAssertTrue(history.upsert(team))
    XCTAssertThrowsError(try history.publishCollaborationMilestone(input, scope: scope))
    XCTAssertTrue(try database.researchObjectHeads(conversationId: scope.conversationId, after: "", limit: 1).isEmpty)
  }

  func testDesktopEvidenceAdmissionRejectsCallableAliasesWithoutChangingLegacyBindings() throws {
    typealias Policy = AgentCollaborationGoalAssessmentPolicy
    let suite = "desktop-evidence-admission-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore(), file = root.appendingPathComponent("history.sqlite3")
    func open() -> AgentTeamExecutionHistoryStore {
      .init(defaults: defaults, secrets: secrets, executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    }
    func setup(_ run: String) -> AgentCollaborationToolEvidenceScope {
      var team = durableTeamSnapshot(run)
      team.goal = "Document the Desktop result"
      team.members[0].dispatchCheckpoint = .accepted
      XCTAssertTrue(open().upsert(team))
      return .init(runId: team.supervisorRunId, conversationId: team.conversationId, turnId: team.taskId,
        memberId: team.members[0].memberId, sourceId: team.members[0].sourceMessageId)
    }
    func draft(_ tool: String) -> String {
      let criterion: AgentMcpJSONObject = ["id": .string("result"), "requirement": .string("Document the return value"),
        "verification": .string("documentary"), "status": .string("open"), "evidence": .array([]),
        "required_observations": .array([.object(["origin": .string("desktop_codex_tool"), "tool": .string(tool)])])]
      return AgentMcpJSONCodec.stringify(["format": .string("galaxyssi.goal-assessment.v1"), "summary": .string("Bind"),
        "decision": .string("continue"), "criteria": .array([.object(criterion)]), "work": .array([]), "blockers": .array([])])
    }
    func submit(_ mode: String, tool: String, scope: AgentCollaborationToolEvidenceScope) throws -> AgentMcpJSONObject {
      try open().publishCollaborationMilestone(["mode": .string(mode), "artifact": .string(draft(tool))], scope: scope)
    }
    let scope = setup("recorded-families")
    let rejected = try submit(Policy.establishContractMode, tool: "exec_command", scope: scope)
    XCTAssertEqual(rejected["status"], .string("assessment_rejected"))
    XCTAssertEqual(rejected["work_dispatched"], .bool(false))
    let repair = try XCTUnwrap(rejected["assessment_repair"]?.objectValue)
    XCTAssertEqual(repair["reason"], .string("unknown_recorded_tool"))
    XCTAssertEqual(repair["field_path"], .string("$.criteria[0].required_observations[0].tool"))
    XCTAssertEqual(repair["draft_retained"], .bool(true))
    XCTAssertNil(open().goalCheckpoint(runId: scope.runId, conversationId: scope.conversationId, turnId: scope.turnId))
    for supported in ["codex.commandExecution", "codex.mcpToolCall", "codex.dynamicToolCall", "codex.webSearch"] {
      XCTAssertEqual(try submit("validate_assessment", tool: supported, scope: scope)["schema_valid"], .bool(true))
    }
    for unsupported in ["commandExecution", "codex.commandexecution", "codex.fileChange", "exec_command"] {
      XCTAssertEqual(try submit("validate_assessment", tool: unsupported, scope: scope)["reason"], .string("unknown_recorded_tool"))
    }
    XCTAssertEqual(try submit(Policy.establishContractMode, tool: "codex.commandExecution", scope: scope)["revision"], .int(1))
    XCTAssertEqual(open().goalCheckpoint(runId: scope.runId, conversationId: scope.conversationId, turnId: scope.turnId)?
      .bindsRecordedDesktopTools, true)
    let contaminated = AgentMcpJSONCodec.stringify(["format": .string("galaxyssi.work-expansion.v1"), "criteria": .array([]),
      "work": .array([.object(["id": .string("not-admitted"), "member": .string("review"),
        "assignment": .string("Do work"), "depends_on": .array([])])])])
    let denied = try open().publishCollaborationMilestone(["mode": .string(Policy.appendWorkMode), "expected_revision": .int(1),
      "milestone_id": .string("criteria-smuggling"), "artifact": .string(contaminated)], scope: scope)
    XCTAssertEqual(denied["reason"], .string("criteria_not_allowed_in_work_expansion"))
    XCTAssertThrowsError(try open().goalWork("not-admitted", scope: scope))

    let legacy = setup("legacy-families")
    let original = try XCTUnwrap(Policy.initialContract(draft("commandExecution")))
    XCTAssertTrue(open().advanceGoalCheckpoint(.init(runId: legacy.runId, conversationId: legacy.conversationId,
      turnId: legacy.turnId, revision: 1, phase: .working, contract: original, completedWorkIds: []), expectedRevision: 0))
    XCTAssertEqual(try submit("validate_assessment", tool: "commandExecution", scope: legacy)["schema_valid"], .bool(true))
    XCTAssertEqual(try submit(Policy.establishContractMode, tool: "commandExecution", scope: legacy)["replayed"], .bool(true))
    XCTAssertEqual(try submit(Policy.establishContractMode, tool: "codex.commandExecution", scope: legacy)["status"],
      .string("assessment_rejected"))
    let unchanged = try XCTUnwrap(open().goalCheckpoint(runId: legacy.runId,
      conversationId: legacy.conversationId, turnId: legacy.turnId))
    XCTAssertEqual(unchanged.contract, original)
    XCTAssertNil(unchanged.bindsRecordedDesktopTools)
  }

  func testInterimPublicationReopensWithSameReceiptWithoutCompletingAssignment() throws {
    let suite = "milestone-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    var team = durableTeamSnapshot("run")
    team.members[1].dispatchCheckpoint = .dispatching
    XCTAssertTrue(history.upsert(team))
    let scope = AgentCollaborationToolEvidenceScope(runId: "run", conversationId: team.conversationId,
      turnId: team.taskId, memberId: "review", sourceId: "source-review")
    let artifact = """
    {"format":"galaxyssi.research-artifact.v1","summary":"Interim",
     "workspace":[{"id":"note","base_revision":0,"kind":"artifact","title":"Note","body":{"content":"Original"},"parents":[]}]}
    """
    let input: AgentMcpJSONObject = ["mode": .string("publish"), "milestone_id": .string("first"),
      "artifact": .string(artifact)]
    let status = try history.publishCollaborationMilestone(["mode": .string("status")], scope: scope)
    XCTAssertEqual(status["capability"]?.objectValue?["publish_allowed"], .bool(true))
    XCTAssertEqual(status["assignment_completed"], .bool(false))
    let denied = try history.publishCollaborationMilestone(input, scope: scope, desktopWire: true,
      transportAllowsInterim: false)
    XCTAssertEqual(denied["status"], .string("unavailable"))
    XCTAssertEqual(try history.publishCollaborationMilestone(["mode": .string("list")], scope: scope)["milestones"], .array([]))
    let receipt = try history.publishCollaborationMilestone(input, scope: scope)
    XCTAssertEqual(receipt["success"], .bool(true))
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    XCTAssertEqual(try reopened.publishCollaborationMilestone(input, scope: scope), receipt)
    let lookup: AgentMcpJSONObject = ["mode": .string("receipt"), "milestone_id": .string("first"),
      "artifact_sha256": try XCTUnwrap(receipt["artifact_sha256"])]
    XCTAssertEqual(try reopened.publishCollaborationMilestone(lookup, scope: scope)["references"], receipt["references"])
    for index in 2...33 {
      let id = "milestone-\(index)"
      _ = try reopened.publishCollaborationMilestone(["mode": .string("publish"), "milestone_id": .string(id),
        "artifact": .string(artifact.replacingOccurrences(of: #""id":"note""#, with: "\"id\":\"\(id)\""))], scope: scope)
    }
    let directory = try reopened.publishCollaborationMilestone(["mode": .string("list")], scope: scope)
    XCTAssertEqual(directory["milestones"]?.arrayValue?.count, 32)
    let cursor = try XCTUnwrap(directory["next_cursor"]?.strictStringValue)
    let tail = try reopened.publishCollaborationMilestone(["mode": .string("list"), "cursor": .string(cursor)], scope: scope)
    XCTAssertEqual(tail["milestones"]?.arrayValue?.count, 1)
    XCTAssertEqual(tail["next_cursor"], .null)
    let entries = (directory["milestones"]?.arrayValue ?? []) + (tail["milestones"]?.arrayValue ?? [])
    XCTAssertEqual(entries.compactMap { $0.objectValue }.first { $0.string("milestone_id") == "first" }?["raw_sha256"],
      receipt["artifact_sha256"])
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(["mode": .string("list"),
      "cursor": .string("foreign:" + cursor)], scope: scope))
    XCTAssertEqual(reopened.snapshot(supervisorRunId: "run")?.members[1].status, team.members[1].status)
    var changed = input
    changed["artifact"] = .string(artifact.replacingOccurrences(of: #""summary":"Interim","#,
      with: #""summary":"Interim","candidates":[],"findings":[],"#))
    let stale = try reopened.publishCollaborationMilestone(changed, scope: scope)
    XCTAssertEqual(stale["status"], .string("stale_binding_or_revision"))
    var malformed = input
    malformed["milestone_id"] = .string("invalid")
    malformed["artifact"] = .string("not JSON")
    let rejected = try reopened.publishCollaborationMilestone(malformed, scope: scope)
    XCTAssertEqual(rejected["status"], .string("invalid_artifact"))
    let rejectionLookup: AgentMcpJSONObject = ["mode": .string("receipt"), "milestone_id": .string("invalid"),
      "artifact_sha256": try XCTUnwrap(rejected["artifact_sha256"])]
    XCTAssertEqual(try history.publishCollaborationMilestone(rejectionLookup, scope: scope), rejected)
    malformed["milestone_id"] = .string("invalid-notes")
    malformed["artifact"] = .string(artifact.replacingOccurrences(of: #""summary":"Interim","#,
      with: #""summary":"Interim","findings":null,"#))
    let invalidNotes = try reopened.publishCollaborationMilestone(malformed, scope: scope)
    XCTAssertEqual(invalidNotes["status"], .string("invalid_artifact"))
    XCTAssertEqual(invalidNotes["record_validation"]?.objectValue?["field"], .string("findings"))
    XCTAssertEqual(try history.publishCollaborationMilestone(["mode": .string("receipt"),
      "milestone_id": .string("invalid-notes"), "artifact_sha256": try XCTUnwrap(invalidNotes["artifact_sha256"])],
      scope: scope), invalidNotes)
    let database = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    let base = "publication:" + AgentMcpJSONCodec.sha256([
      "run": .string(scope.runId), "member": .string(scope.memberId), "source": .string(scope.sourceId)
    ]) + ":milestone:"
    func key(_ id: String) -> String { base + AgentMcpJSONCodec.sha256(["id": .string(id)]) }
    var legacy = try XCTUnwrap(database.researchRecord(AgentCollaborationResearchPublication.self,
      conversationId: scope.conversationId, key: key("first"), revision: 0))
    legacy.milestoneId = "legacy"
    legacy.requestHash = try XCTUnwrap(invalidNotes["artifact_sha256"]?.strictStringValue)
    try database.insertResearchRecord(legacy, conversationId: scope.conversationId, key: key("legacy"), revision: 0)
    malformed["milestone_id"] = .string("legacy")
    let legacyRetry = try reopened.publishCollaborationMilestone(malformed, scope: scope)
    XCTAssertEqual(legacyRetry["status"], .string("published"))
    XCTAssertEqual(legacyRetry["references"], receipt["references"])
    XCTAssertEqual(try history.publishCollaborationMilestone(lookup, scope: scope)["references"], receipt["references"])
    var foreign = scope
    foreign.sourceId = "foreign"
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(input, scope: foreign))
    team.members[1].status = .succeeded
    let final = #"{"format":"galaxyssi.research-artifact.v1","summary":"Final","milestones":["first"]}"#
    team.members[1].replyContent = final
    team.updatedAtMillis += 1
    XCTAssertTrue(reopened.upsert(team))
    XCTAssertNil(try reopened.committedResearchRevisions(scope: scope))
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(input, scope: scope))
    try reopened.publishSavedResearchReply(final, scope: scope)
    let linked = try XCTUnwrap(reopened.committedResearchRevisions(scope: scope))
    XCTAssertEqual(linked.map { $0.draft.id }, ["note"])
  }

  func testDecisionMilestonesFilterPrivateRecordsAndLinkExactOriginalsAfterReopen() throws {
    let suite = "decision-milestone-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore(), file = root.appendingPathComponent("history.sqlite3")
    func open() -> AgentTeamExecutionHistoryStore {
      .init(defaults: defaults, secrets: secrets, executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    }
    var team = durableTeamSnapshot("decision")
    team.goal = "Compare two hypotheses"
    team.members[0].dispatchCheckpoint = .accepted
    team.members[1].dispatchCheckpoint = .accepted
    XCTAssertTrue(open().upsert(team))
    func scope(_ index: Int) -> AgentCollaborationToolEvidenceScope {
      .init(runId: team.supervisorRunId, conversationId: team.conversationId, turnId: team.taskId,
        memberId: team.members[index].memberId, sourceId: team.members[index].sourceMessageId)
    }
    func publish(_ id: String, _ artifact: AgentMcpJSONObject) throws -> AgentMcpJSONObject {
      try open().publishCollaborationMilestone(["mode": .string("publish"), "milestone_id": .string(id),
        "artifact": .string(AgentMcpJSONCodec.stringify(artifact))], scope: scope(1))
    }
    let base: AgentMcpJSONObject = ["format": .string("galaxyssi.research-artifact.v1"), "summary": .string("Measurements")]
    let privateMode: AgentMcpJSONValue = .object(["mode": .string("record_only")])
    var original: AgentMcpJSONObject?
    for index in 0..<35 {
      var evidence = base
      evidence["workspace"] = .array([.object(["id": .string("sample-\(index)"), "base_revision": .int(0),
        "kind": .string("artifact"), "title": .string("Original"), "parents": .array([]),
        "body": .object(["content": .string("Private original measurements")])])])
      evidence["coordination"] = privateMode
      let receipt = try publish("record-\(index)", evidence)
      XCTAssertEqual(receipt["status"], .string("published"))
      if index == 0 { original = receipt }
    }
    let history = open()
    func inventory() throws -> [AgentMcpJSONValue] {
      let snapshot = try open().goalWorkInventory(scope: scope(0))
      return snapshot["members"]?.arrayValue?.first?.objectValue?["published_milestones"]?.arrayValue ?? []
    }
    XCTAssertTrue(try inventory().isEmpty)
    let audit = try history.publishCollaborationMilestone(["mode": .string("list")], scope: scope(1))
    XCTAssertEqual(audit["milestones"]?.arrayValue?.count, 32)
    let cursor = try XCTUnwrap(audit["next_cursor"]?.strictStringValue)
    let tail = try history.publishCollaborationMilestone(["mode": .string("list"), "cursor": .string(cursor)], scope: scope(1))
    XCTAssertEqual(tail["milestones"]?.arrayValue?.count, 3)
    let originalReceipt = try XCTUnwrap(original)
    let recovered = try history.publishCollaborationMilestone(["mode": .string("receipt"), "milestone_id": .string("record-0"),
      "artifact_sha256": try XCTUnwrap(originalReceipt["artifact_sha256"])], scope: scope(1))
    XCTAssertEqual(recovered["coordination"], privateMode)
    var request = base
    request["workspace"] = .array([])
    request["milestones"] = .array([.string("record-0")])
    request["coordination"] = privateMode
    XCTAssertEqual(try publish("not-an-offer", request)["status"], .string("invalid_artifact"))
    let decision: AgentMcpJSONValue = .object(["mode": .string("request"), "decision": .string("Choose the next sample"),
      "why_now": .string("The next measurement can distinguish the alternatives")])
    request["coordination"] = decision
    let offer = try publish("decision", request)
    XCTAssertEqual(offer["references"], originalReceipt["references"])
    XCTAssertEqual(try publish("decision", request), offer)
    let rows = try inventory()
    XCTAssertEqual(rows.count, 1)
    let row = try XCTUnwrap(rows.first?.objectValue)
    XCTAssertEqual(row["coordination"], decision)
    let query: AgentMcpJSONObject = ["mode": .string(AgentCollaborationMilestoneCoordination.readMode),
      "token": try XCTUnwrap(row["token"])]
    XCTAssertThrowsError(try open().publishCollaborationMilestone(query, scope: scope(1)))
    let available = try open().publishCollaborationMilestone(query, scope: scope(0))
    XCTAssertEqual(available["references"], originalReceipt["references"])
    let ref = try XCTUnwrap(available["references"]?.arrayValue?.first?.objectValue)
    var exact = query
    exact["object_id"] = ref["object_id"]
    exact["revision"] = ref["revision"]
    exact["artifact_sha256"] = ref["sha256"]
    exact["offset"] = .int(0)
    let page = try open().publishCollaborationMilestone(exact, scope: scope(0))
    let bytes = try XCTUnwrap(Data(base64Encoded: page.string("data_b64")))
    XCTAssertEqual(page["next_offset"], .null)
    let record = try JSONDecoder().decode(AgentCollaborationResearchRevision.self, from: bytes)
    XCTAssertEqual(record.draft.body["content"], .string("Private original measurements"))
    exact["revision"] = .int(2)
    XCTAssertThrowsError(try open().publishCollaborationMilestone(exact, scope: scope(0)))
    var foreign = scope(0)
    foreign.sourceId = "other-source"
    XCTAssertThrowsError(try open().publishCollaborationMilestone(query, scope: foreign))
    let author = scope(1)
    team.members[1].status = .succeeded
    team.updatedAtMillis += 1
    XCTAssertTrue(history.upsert(team))
    let final = try open().publishResearchObjects([], runId: author.runId, conversationId: author.conversationId,
      turnId: author.turnId, memberId: author.memberId, sourceId: author.sourceId, finalMilestones: ["record-0"])
    XCTAssertEqual(final.references.first, record.reference)
    history.removeResearchObjects(conversationId: team.conversationId)
    XCTAssertThrowsError(try open().publishCollaborationMilestone(query, scope: scope(0)))
    let database = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    let key = AgentCollaborationMilestoneCoordination.requestPrefix + query.string("token")
    XCTAssertNil(try database.researchRecord(AgentCollaborationMilestoneCoordination.RequestIndex.self,
      conversationId: team.conversationId, key: key, revision: 0))
  }

  func testDesktopFileHandoffRecallsOnlyExactFrozenVersionForPairedDependency() throws {
    typealias Handoff = AgentDesktopCollaborationFileHandoff
    let suite = "file-handoff-\(UUID())", root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore(), file = root.appendingPathComponent("history.sqlite3")
    func open() -> AgentTeamExecutionHistoryStore {
      .init(defaults: defaults, secrets: secrets, executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    }
    let history = open()
    let pair = Handoff.Pair(desktopID: "desktop", clientRouteID: "route", contactID: "contact",
      phoneFingerprint: "phone-key", desktopFingerprint: "desktop-key")
    XCTAssertEqual(pair.storeID, "08d406beec042f5f4bafcdbf2b26f5911e4737ed89f9a358f3f1d7f9b22ca296")
    let binding = Handoff.Binding(pair: pair, generation: 1)
    var team = durableTeamSnapshot("file-handoff")
    let producer = AgentTeamMemberSnapshot(agentId: pair.contactID, instanceId: "producer", sourceMessageId: "produce",
      dispatchCheckpoint: .dispatching)
    var peer = AgentTeamMemberSnapshot(agentId: pair.contactID, instanceId: "peer", sourceMessageId: "receive",
      dispatchCheckpoint: .notStarted)
    peer.dispatchDependencyMemberIds = [producer.memberId]
    let other = AgentTeamMemberSnapshot(agentId: pair.contactID, instanceId: "other", sourceMessageId: "unrelated",
      dispatchCheckpoint: .dispatching)
    team.members = [team.members[0], producer, peer, other]
    XCTAssertTrue(history.upsert(team))
    func scope(_ member: AgentTeamMemberSnapshot) -> AgentCollaborationToolEvidenceScope {
      .init(runId: team.supervisorRunId, conversationId: team.conversationId, turnId: team.taskId,
        memberId: member.memberId, sourceId: member.sourceMessageId)
    }
    let author = scope(producer), recipient = scope(peer)
    let storeID = try XCTUnwrap(pair.storeID)
    func publish(_ id: String, filename: String = "snapshot-\u{1F642}.bin", objectID: String? = nil) -> AgentMcpJSONObject {
      let fileID = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
      let body: AgentMcpJSONObject = ["format": .string(Handoff.format), "store_id": .string(storeID),
        "file_id": .string(fileID), "name": .string(filename), "size_bytes": .int(2 * 1_024 * 1_024),
        "sha256": .string(String(repeating: "b", count: 64)), "availability": .string("originating_desktop")]
      var item: AgentMcpJSONObject = ["id": .string(fileID), "kind": .string("artifact"), "title": .string("Snapshot"),
        "body": .object(body), "parents": .array([]), "resolves": .array([]), "observations": .array([])]
      if let objectID { item["object_id"] = .string(objectID); item["base_revision"] = .int(1) }
      let raw = AgentMcpJSONCodec.stringify(["format": .string("galaxyssi.research-artifact.v1"), "summary": .string("Snapshot"),
        "workspace": .array([.object(item)])])
      return ["mode": .string("publish"), "milestone_id": .string(id), "artifact": .string(raw)]
    }
    let first = publish("v1")
    let wire = AgentDesktopCollaborationPublicationWire.self
    let result = wire.result(try history.publishCollaborationMilestone(first, scope: author,
      desktopWire: true, desktopFile: binding), phase: "publish")
    let ref = try XCTUnwrap(result["revisions"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(result["status"], .string("recorded"))
    XCTAssertEqual(result["assignment_completed"], .bool(false))
    let request: AgentMcpJSONObject = ["mode": .string("workspace"), "object_id": .string(ref.string("object_id")),
      "revision": .int(1), "offset": .int(0)]
    XCTAssertThrowsError(try history.recallDesktopFileHandoff(request, scope: recipient, reader: binding))
    XCTAssertThrowsError(try history.recallDesktopFileHandoff(request, scope: scope(other), reader: binding))
    XCTAssertTrue(history.advanceDispatchCheckpoint(runId: recipient.runId, conversationId: recipient.conversationId,
      turnId: recipient.turnId, memberId: recipient.memberId, sourceMessageId: recipient.sourceId, to: .dispatching, now: 2))
    let reopened = open()
    let recalled = try reopened.recallDesktopFileHandoff(request, scope: recipient, reader: binding)
    XCTAssertEqual(recalled["total_characters"], .int(Int64(recalled.string("content").utf16.count)))
    XCTAssertEqual(recalled["next_offset"], .null)
    let decoded = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(recalled.string("content").utf8))
    XCTAssertEqual(decoded["object_id"], ref["object_id"])
    XCTAssertEqual(decoded["sha256"], ref["sha256"])
    XCTAssertEqual(decoded["body"]?.objectValue?["name"], .string("snapshot-\u{1F642}.bin"))
    XCTAssertEqual(decoded["body"]?.objectValue?["size_bytes"], .int(2 * 1_024 * 1_024))
    let second = publish("v2", objectID: ref.string("object_id"))
    XCTAssertEqual(try reopened.publishCollaborationMilestone(second, scope: author, desktopWire: true,
      desktopFile: binding)["status"], .string("published"))
    var newer = request
    newer["revision"] = .int(2)
    XCTAssertThrowsError(try reopened.recallDesktopFileHandoff(newer, scope: recipient, reader: binding))
    XCTAssertEqual(try reopened.recallDesktopFileHandoff(request, scope: recipient, reader: binding), recalled)
    XCTAssertEqual(try reopened.publishCollaborationMilestone(first, scope: scope(other), desktopWire: true,
      desktopFile: binding)["success"], .bool(false))
    let receipt: AgentMcpJSONObject = ["mode": .string("receipt"), "milestone_id": .string("v1"),
      "artifact_sha256": result["artifact_sha256"] ?? .null]
    XCTAssertEqual(try reopened.publishCollaborationMilestone(receipt, scope: author, desktopWire: true,
      desktopFile: binding)["status"], .string("recorded"))
    let foreign = Handoff.Binding(pair: .init(desktopID: pair.desktopID, clientRouteID: pair.clientRouteID,
      contactID: pair.contactID, phoneFingerprint: pair.phoneFingerprint, desktopFingerprint: "new-key"), generation: 1)
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(receipt, scope: author, desktopWire: true, desktopFile: foreign))
    XCTAssertThrowsError(try reopened.recallDesktopFileHandoff(request, scope: recipient, reader: foreign))
    var generic = request
    generic["sha256"] = ref["sha256"]
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(generic, scope: author))
    let database = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    try database.transaction {
      try database.insertResearchRecord(true, conversationId: recipient.conversationId, key: "native-evidence-revoked", revision: 0)
    }
    XCTAssertThrowsError(try reopened.recallDesktopFileHandoff(request, scope: recipient, reader: binding))
  }

  func testDesktopPublicationRecoversExactFrozenArtifactsAndDistinguishesAbsence() throws {
    let suite = "desktop-publication-receipt-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    func open() -> AgentTeamExecutionHistoryStore {
      .init(defaults: defaults, secrets: secrets, executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    }
    let history = open()
    var team = durableTeamSnapshot("desktop-publication")
    team.members[0].dispatchCheckpoint = .accepted
    team.members[1].dispatchCheckpoint = .dispatching
    XCTAssertTrue(history.upsert(team))
    let member = team.members[1]
    let scope = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId, memberId: member.memberId, sourceId: member.sourceMessageId)
    let wire = AgentDesktopCollaborationPublicationWire.self
    func sha(_ raw: String) -> String {
      SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func lookup(_ id: String, _ digest: String) -> AgentMcpJSONObject {
      ["mode": .string("receipt"), "milestone_id": .string(id), "artifact_sha256": .string(digest)]
    }
    let text = "\u{FEFF}def predict(x):\r\n    return x * 2\r\n" +
      String(repeating: "# \u{4E2D}\u{6587} \u{1F52C} e\u{301}\r\n", count: 700)
    for kind in ["text", "other"] {
      let body: AgentMcpJSONObject = ["format": .string("galaxyssi.\(kind)-artifact/1"),
        "name": .string("snapshot.py"), "content": .string(text), "encoding": .string("utf-8"),
        "size_bytes": .int(Int64(text.utf8.count)), "sha256": .string(sha(text))]
      let item: AgentMcpJSONObject = ["id": .string(kind), "kind": .string("artifact"), "title": .string("Snapshot"),
        "body": .object(body), "parents": .array([])]
      let raw = AgentMcpJSONCodec.stringify(["format": .string("galaxyssi.research-artifact.v1"),
        "summary": .string("Snapshot"), "workspace": .array([.object(item)])])
      let request = lookup(kind, sha(raw))
      let absent = try history.publishCollaborationMilestone(request, scope: scope)
      XCTAssertEqual(absent["success"], .bool(true))
      XCTAssertEqual(absent["status"], .string("not_recorded"))
      XCTAssertEqual(absent["milestone_id"], .string(kind))
      XCTAssertEqual(absent["artifact_sha256"], .string(sha(raw)))
      let original: AgentMcpJSONObject = ["mode": .string("publish"), "milestone_id": .string(kind), "artifact": .string(raw)]
      let submitted = wire.result(try history.publishCollaborationMilestone(original, scope: scope, desktopWire: true),
        phase: "publish")
      XCTAssertEqual(submitted["status"], .string("recorded"))
      XCTAssertEqual(submitted["artifact_sha256"], .string(sha(raw)))
      XCTAssertEqual(submitted["revisions"]?.arrayValue?.count, 1)
      let reopened = open()
      let recovered = wire.result(try reopened.publishCollaborationMilestone(request, scope: scope), phase: "receipt")
      XCTAssertEqual(recovered["status"], .string("recorded"))
      XCTAssertEqual(recovered["receipt_recovered"], .bool(true))
      XCTAssertEqual(recovered["assignment_completed"], .bool(false))
      XCTAssertEqual(recovered["revisions"], submitted["revisions"])
      XCTAssertThrowsError(try reopened.publishCollaborationMilestone(lookup(kind, sha(raw + " ")), scope: scope))
      var foreign = scope
      foreign.sourceId = "other-source"
      XCTAssertThrowsError(try reopened.publishCollaborationMilestone(request, scope: foreign))
      typealias Read = AgentDesktopCollaborationTextArtifact.Read
      let ref = try XCTUnwrap(submitted["revisions"]?.arrayValue?.first?.objectValue)
      let query: AgentMcpJSONObject = ["mode": .string("workspace"), "object_id": ref["object_id"] ?? .null,
        "revision": ref["revision"] ?? .null, "offset": .int(0)]
      let firstRead = try XCTUnwrap(Read(query))
      XCTAssertThrowsError(try reopened.readDesktopTextArtifact(firstRead, scope: foreign))
      if kind != "text" {
        XCTAssertThrowsError(try reopened.readDesktopTextArtifact(firstRead, scope: scope))
        continue
      }
      var nextTeam = durableTeamSnapshot("text-reader")
      nextTeam.taskId = "next-turn"
      nextTeam.members[1].dispatchCheckpoint = .accepted
      XCTAssertTrue(reopened.upsert(nextTeam))
      let reader = AgentCollaborationToolEvidenceScope(runId: nextTeam.supervisorRunId,
        conversationId: nextTeam.conversationId, turnId: nextTeam.taskId,
        memberId: nextTeam.members[1].memberId, sourceId: nextTeam.members[1].sourceMessageId)
      var sameTurnPeer = scope
      sameTurnPeer.memberId = team.members[0].memberId
      sameTurnPeer.sourceId = team.members[0].sourceMessageId
      XCTAssertThrowsError(try reopened.readDesktopTextArtifact(firstRead, scope: sameTurnPeer))
      var document = ""
      var offset: Int64 = 0
      var total: Int64?
      var pages = 0
      while pages < 64 {
        var args = query
        args["offset"] = .int(offset)
        let page = try reopened.readDesktopTextArtifact(XCTUnwrap(Read(args)), scope: reader)
        let part = try XCTUnwrap(page["content"]?.strictStringValue)
        XCTAssertFalse(part.isEmpty)
        XCTAssertLessThanOrEqual(part.utf16.count, 2_000)
        document += part
        offset += Int64(part.utf16.count)
        pages += 1
        let size = try XCTUnwrap(page["total_characters"]?.intValue)
        XCTAssertEqual(size, total ?? size)
        total = size
        guard page["next_offset"] != .null else { break }
        XCTAssertEqual(page["next_offset"], .int(offset))
      }
      XCTAssertGreaterThan(pages, 1)
      XCTAssertEqual(Int64(document.utf16.count), total)
      let decoded = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(document.utf8))
      XCTAssertEqual(decoded["sha256"], ref["sha256"])
      XCTAssertEqual(decoded["object_id"], ref["object_id"])
      XCTAssertEqual(decoded["revision"], ref["revision"])
      let materialized = try XCTUnwrap(decoded["body"]?.objectValue?["content"]?.strictStringValue)
      XCTAssertEqual(Data(materialized.utf8), Data(text.utf8))
      XCTAssertEqual(decoded["evidence_state"], .string("member_reported_not_verified"))
      var outOfRange = query
      outOfRange["offset"] = .int(try XCTUnwrap(total))
      XCTAssertThrowsError(try reopened.readDesktopTextArtifact(XCTUnwrap(Read(outOfRange)), scope: reader))
      var badBody = body
      badBody["sha256"] = .string(String(repeating: "0", count: 64))
      var badItem = item
      badItem["body"] = .object(badBody)
      let tampered = AgentMcpJSONCodec.stringify(["format": .string("galaxyssi.research-artifact.v1"),
        "summary": .string("Snapshot"), "workspace": .array([.object(badItem)])])
      let rejected = try reopened.publishCollaborationMilestone(["mode": .string("publish"),
        "milestone_id": .string("tampered-text"), "artifact": .string(tampered)], scope: scope, desktopWire: true)
      XCTAssertEqual(rejected["status"], .string("rejected"))
      XCTAssertEqual(rejected["record_validation"]?.objectValue?["code"], .string("invalid_text_artifact"))
    }
    let database = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    let base = "publication:" + AgentMcpJSONCodec.sha256([
      "run": .string(scope.runId), "member": .string(scope.memberId), "source": .string(scope.sourceId)
    ]) + ":milestone:"
    let invalidDigest = sha("invalid reference fixture")
    let invalid = AgentCollaborationResearchPublication(requestHash: invalidDigest,
      references: [.init(objectId: String(repeating: "a", count: 64), revision: 1, sha256: invalidDigest)],
      milestoneId: "broken", recordedAtMillis: 1)
    try database.insertResearchRecord(invalid, conversationId: scope.conversationId,
      key: base + AgentMcpJSONCodec.sha256(["id": .string("broken")]), revision: 0)
    XCTAssertThrowsError(try history.publishCollaborationMilestone(lookup("broken", invalidDigest), scope: scope))
    team.state = .cancelled
    team.updatedAtMillis += 1
    XCTAssertTrue(history.upsert(team))
    XCTAssertThrowsError(try history.publishCollaborationMilestone(lookup("missing", invalidDigest), scope: scope))
  }

  func testResearchPublicationNotesDefaultOnlyWhenAbsentAndPreserveExplicitValues() throws {
    typealias Envelope = AgentCollaborationResearchEnvelope
    let base: AgentMcpJSONObject = ["format": .string(Envelope.wireFormat), "summary": .string("Research")]
    func decode(_ extra: AgentMcpJSONObject = [:]) throws -> Envelope {
      let raw = AgentMcpJSONCodec.stringify(base.merging(extra) { _, supplied in supplied })
      return try JSONDecoder().decode(Envelope.self, from: Data(raw.utf8))
    }
    let omitted = try decode()
    XCTAssertEqual(omitted.candidates, [])
    XCTAssertEqual(omitted.findings, [])
    let candidate: AgentMcpJSONValue = .object(["id": .string("C1"), "proposal": .string("Compare methods"),
      "criteria": .array([.string("Compare on held-out inputs")])])
    let finding: AgentMcpJSONValue = .object(["outcome": .string("not_tested"), "note": .string("No results yet")])
    let explicit = try decode(["candidates": .array([candidate]), "findings": .array([finding])])
    XCTAssertEqual(explicit.candidates, [candidate])
    XCTAssertEqual(explicit.findings, [finding])
    let malformed: [(AgentMcpJSONObject, String)] = [
      (["candidates": .object([:])], "candidates"),
      (["findings": .null], "findings"),
      (["candidates": .array([candidate, candidate])], "candidates[1].id"),
      (["findings": .array([.object(["outcome": .string("unknown")])])], "findings[0].outcome")
    ]
    for (extra, field) in malformed {
      XCTAssertThrowsError(try decode(extra)) { error in
        XCTAssertEqual((error as? Envelope.InvalidNotes)?.field, field)
      }
    }
  }

  func testDirectedRequestsKeepLongQuestionsAndSeparateCandidateIdentities() throws {
    var team = durableTeamSnapshot("run")
    team.members[1].researchStage = "EXPLORE"
    let sender = team.members[1]
    let question = String(repeating: "q", count: 1_300)
    func request(_ candidate: String, recipient: String = "primary") -> AgentMcpJSONValue {
      .object(["to": .array([.string(recipient)]), "question": .string(question), "candidate_id": .string(candidate)])
    }
    var envelope: AgentMcpJSONObject = ["format": .string(AgentCollaborationResearchEnvelope.wireFormat),
      "requests": .array([request("a"), request("b"), request("a"), request("c")])]
    let roster: Set<String> = ["primary", "review"]
    let rows = try AgentCollaborationDirectedRequests.messages(in: AgentMcpJSONCodec.stringify(envelope),
      team: team, sender: sender, rosterMemberIds: roster)
    XCTAssertEqual(rows.count, 3)
    XCTAssertEqual(Set(rows.map(\.messageId)).count, 3)
    XCTAssertTrue(rows.allSatisfy { $0.text == question && $0.toInstanceId == "primary" })
    XCTAssertTrue(AgentCollaborationDirectedRequests.prompt(rows).contains(#""candidate_id":"b""#))
    envelope["requests"] = .array([request("a", recipient: "foreign")])
    XCTAssertThrowsError(try AgentCollaborationDirectedRequests.messages(in: AgentMcpJSONCodec.stringify(envelope),
      team: team, sender: sender, rosterMemberIds: roster))
  }

  func testResearchPublicationRequiresExplicitStructuredArtifact() throws {
    XCTAssertNil(try AgentCollaborationResearchEnvelope.publication(in: "A normal reply"))
    let raw = """
    {"format":"galaxyssi.research-artifact.v1","summary":"Notes","workspace":[
      {"id":"note","object_id":"","base_revision":0,"kind":"evidence","title":"Notes","body":{"text":"Source"},"parents":[]}
    ]}
    """
    let drafts = try XCTUnwrap(AgentCollaborationResearchEnvelope.publication(in: raw))
    XCTAssertEqual(drafts.map(\.id), ["note"])
    let fenced = " \r\n```json\r\n" + raw + "\r\n```\r\n "
    let fencedDrafts = try XCTUnwrap(AgentCollaborationResearchEnvelope.publication(in: fenced))
    XCTAssertEqual(fencedDrafts.map(\.id), ["note"])
    XCTAssertThrowsError(try AgentCollaborationResearchEnvelope.publication(
      in: "{\"format\":\"galaxyssi.research-artifact.v1\",\"workspace\":{}}"))
  }

  func testCapabilityDirectoryReturnsExactCandidateWithoutExposingSameTurnPeer() throws {
    let suite = "capability-directory-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: InMemorySecretStore(),
      executionStore: SavedTeamRecoveryFixture([]), fileURL: root.appendingPathComponent("history.sqlite3"))
    var team = durableTeamSnapshot("capability-author")
    team.members[0].status = .succeeded
    XCTAssertTrue(history.upsert(team))
    var early = durableTeamSnapshot("capability-early-reader")
    early.taskId = "early"
    early.goal = "Verify evidence"
    XCTAssertTrue(history.upsert(early))
    func scope(_ team: AgentTeamExecutionSnapshot) -> AgentCollaborationToolEvidenceScope {
      let peer = team.members[1]
      return .init(runId: team.supervisorRunId, conversationId: team.conversationId, turnId: team.taskId,
        memberId: peer.memberId, sourceId: peer.sourceMessageId)
    }
    XCTAssertTrue(try history.initialCollaborationCapabilities(scope: scope(early)).isEmpty)
    let raw = """
    {"purpose":"Verify evidence","domain":"Research","bottleneck":"Errors","change_rationale":"Check",
     "applies_when":"Comparable","avoid_when":"Unsafe","risks":"Delay","expected_gain":"Accuracy","falsifier":"No gain",
     "dimensions":["verification"],"roles":["worker"],"inputs":[],
     "steps":[{"id":"check","role":"worker","stage":"VERIFY","assignment":"Check input"}]}
    """
    let method = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8))
    let author = team.members[0]
    let publication = try history.publishResearchObjects([
      .init(id: "method", objectId: nil, baseRevision: 0, kind: .workflowMethod,
        title: "Evidence method", body: ["workflow_method": .object(method)], parents: [])
    ], runId: team.supervisorRunId, conversationId: team.conversationId, turnId: team.taskId,
      memberId: author.memberId, sourceId: author.sourceMessageId)
    var later = durableTeamSnapshot("capability-reader")
    later.taskId = "later"
    later.goal = "Verify evidence"
    XCTAssertTrue(history.upsert(later))
    func read(_ team: AgentTeamExecutionSnapshot) throws -> AgentMcpJSONObject {
      let peer = team.members[1]
      return try history.recallCollaborationOriginal(["mode": .string("capabilities"), "query": .string("EVIDENCE research")],
        scope: .init(runId: team.supervisorRunId, conversationId: team.conversationId, turnId: team.taskId,
          memberId: peer.memberId, sourceId: peer.sourceMessageId))
    }
    XCTAssertEqual(try read(team)["capabilities"], .array([]))
    let result = try read(later)
    let entry = try XCTUnwrap(result["capabilities"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(entry.string("sha256"), publication.references.first?.sha256)
    XCTAssertEqual(entry.string("state"), "unverified_candidate")
    XCTAssertEqual(result["grants_permissions"], .bool(false))
    XCTAssertTrue(try history.initialCollaborationCapabilities(scope: scope(early)).isEmpty)
    let pinned = try history.initialCollaborationCapabilities(scope: scope(later))
    XCTAssertEqual(pinned.first?.objectValue?.string("sha256"), publication.references.first?.sha256)
    XCTAssertNil(pinned.first?.objectValue?["title"])

    let toolSpec = """
    {"language":"python","name":"Optical calibration","purpose":"Check sensors","applies_when":"Fixture","avoid_when":"Unsafe",
     "environment":"python","dependencies":"None","side_effects":"None","source":"def run(parameters): return parameters # hidden_source",
     "input_schema":{"type":"object","required":["value"],"properties":{"value":{"type":"integer"}}}}
    """
    let candidate = try history.publishResearchObjects([
      .init(id: "optical-candidate", objectId: nil, baseRevision: 0, kind: .executableTool,
        title: "Device candidate", body: ["executable_tool": .object(
          try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(toolSpec.utf8)))], parents: [])
    ], runId: team.supervisorRunId, conversationId: team.conversationId, turnId: team.taskId,
      memberId: author.memberId, sourceId: author.sourceMessageId)
    let toolRef = try XCTUnwrap(candidate.references.first)
    let testSpec = """
    {"environment":"python","purpose":"Validate","coverage_gaps":"None known","oracle_basis":"Identity",
     "cases":[{"id":"target","purpose":"target","reason":"Typical","input":{"value":1},"expected":"hidden_answer"},
       {"id":"regression","purpose":"regression","reason":"Zero","input":{"value":0},"expected":null}]}
    """
    var tests = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(testSpec.utf8))
    tests["executable_tool"] = .object(["object_id": .string(toolRef.objectId), "revision": .int(toolRef.revision),
      "sha256": .string(toolRef.sha256)])
    _ = try history.publishResearchObjects([
      .init(id: "optical-tests", objectId: nil, baseRevision: 0, kind: .toolTestPlan,
        title: "Candidate tests", body: ["tool_test_plan": .object(tests)], parents: [toolRef])
    ], runId: team.supervisorRunId, conversationId: team.conversationId, turnId: team.taskId,
      memberId: author.memberId, sourceId: author.sourceMessageId)
    func search(_ query: String) throws -> [AgentMcpJSONValue] {
      try history.recallCollaborationOriginal(["mode": .string("capabilities"), "query": .string(query)],
        scope: scope(later))["capabilities"]?.arrayValue ?? []
    }
    let linked = try XCTUnwrap(search("optical calibration").compactMap(\.objectValue).first {
      $0.string("kind") == "tool_test_plan"
    })
    XCTAssertEqual(linked.string("state"), "unverified_candidate")
    XCTAssertEqual(linked["linked_sources"]?.arrayValue?.first?.objectValue?.string("sha256"), toolRef.sha256)
    XCTAssertEqual(linked["linked_sources"]?.arrayValue?.first?.objectValue?["complete_read"], .bool(false))
    XCTAssertTrue(try search("hidden_source").isEmpty)
    XCTAssertTrue(try search("hidden_answer").isEmpty)
  }

  func testModelCallAuditPreservesUnsettledAdmissionAndImmutableTerminalReceipt() throws {
    let suite = "model-call-audit-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    var team = durableTeamSnapshot("audit")
    team.goal = "Verify the synthetic model admission"
    team.members[0].dispatchCheckpoint = .accepted
    XCTAssertTrue(history.upsert(team))
    let member = try XCTUnwrap(team.members.first)
    let scope = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId, memberId: member.memberId, sourceId: member.sourceMessageId)
    let admission = AgentCollaborationModelAdmission(id: UUID(), scope: scope, round: 0,
      provider: .openAICompatible, requestedModel: "fixture", startedAtMillis: 1)
    try history.admitCollaborationModelCall(admission)
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    XCTAssertTrue(try reopened.collaborationModelCall(admission).admitted)
    XCTAssertNil(try reopened.collaborationModelCall(admission).settlement)
    let completed = AgentCollaborationModelSettlement(state: .completed, finishedAtMillis: 2,
      reportedUsage: .init(inputTokens: 10, outputTokens: 3, cachedInputTokens: 2), usageComplete: false, costMicros: nil)
    try reopened.settleCollaborationModelCall(admission, settlement: completed)
    try reopened.settleCollaborationModelCall(admission, settlement: completed)
    XCTAssertEqual(try history.collaborationModelCall(admission).settlement, completed)
    let interrupted = AgentCollaborationModelAdmission(id: UUID(), scope: scope, round: 0,
      provider: .openAICompatible, requestedModel: nil, startedAtMillis: 3, route: .compatibility, lane: .hostLivePlanning)
    try reopened.requireGoalCoordinationAuthority(scope, resourceID: member.agentId)
    XCTAssertThrowsError(try reopened.requireGoalCoordinationAuthority(scope, resourceID: "wrong-resource"))
    let observer = team.members[1]
    let observerScope = AgentCollaborationToolEvidenceScope(runId: scope.runId, conversationId: scope.conversationId,
      turnId: scope.turnId, memberId: observer.memberId, sourceId: observer.sourceMessageId)
    XCTAssertThrowsError(try reopened.admitCollaborationModelCall(.init(id: UUID(), scope: observerScope,
      round: 0, provider: .openAICompatible, requestedModel: nil, startedAtMillis: 3, lane: .hostLivePlanning)))
    try reopened.admitCollaborationModelCall(interrupted)
    let firstPage = try history.collaborationModelAuditPage(conversationId: scope.conversationId, limit: 1)
    let cursor = try XCTUnwrap(firstPage.next)
    let secondPage = try history.collaborationModelAuditPage(conversationId: scope.conversationId, after: cursor, limit: 1)
    let entries = firstPage.entries + secondPage.entries
    XCTAssertEqual(Set(entries.map { $0.admission.id }), [admission.id, interrupted.id])
    XCTAssertEqual(entries.first(where: { $0.admission.id == admission.id })?.settlement, completed)
    XCTAssertNil(entries.first(where: { $0.admission.id == interrupted.id })?.settlement)
    XCTAssertEqual(entries.first(where: { $0.admission.id == interrupted.id })?.admission.route, .compatibility)
    XCTAssertEqual(entries.first(where: { $0.admission.id == interrupted.id })?.admission.lane, .hostLivePlanning)
    XCTAssertNil(secondPage.next)
    XCTAssertTrue(try history.collaborationModelAuditPage(conversationId: "foreign").entries.isEmpty)
    XCTAssertThrowsError(try reopened.settleCollaborationModelCall(admission, settlement: .init(
      state: .failed, finishedAtMillis: 3, reportedUsage: nil, usageComplete: false, costMicros: nil)))
    reopened.removeResearchObjects(conversationId: scope.conversationId)
    XCTAssertFalse(try history.collaborationModelCall(admission).admitted)
    XCTAssertTrue(try history.collaborationModelAuditPage(conversationId: scope.conversationId).entries.isEmpty)
    XCTAssertThrowsError(try reopened.settleCollaborationModelCall(admission, settlement: completed))
  }

  func testPublicationRecoveryFindsSavedReplyAndSkipsCommittedReplay() throws {
    let suite = "publication-recovery-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    XCTAssertTrue(history.upsert(durableTeamSnapshot("run")))
    let body = """
    {"format":"galaxyssi.research-artifact.v1","workspace":[
      {"id":"note","base_revision":0,"kind":"evidence","title":"Note","body":{"text":"Saved"},"parents":[]}
    ]}
    """
    XCTAssertEqual(try history.consumeOwnedReply(source: "source-review", conversation: "conversation", turn: "turn",
      task: "source-review", contact: "review", content: body, richOutputJson: "", terminal: true,
      success: true, now: 20, observation: AgentTeamReplyObservation(generation: 2, sequence: 1)), .observerCommitted)
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    let pending = try reopened.pendingPublicationRecoveryPage(after: "")
    let owner = try XCTUnwrap(pending.owners.first)
    XCTAssertEqual(pending.owners.count, 1)
    XCTAssertEqual(owner.sourceMessageId, "source-review")
    let scope = AgentCollaborationToolEvidenceScope(runId: owner.supervisorRunId, conversationId: owner.conversationId,
      turnId: owner.turnId, memberId: owner.memberId, sourceId: owner.sourceMessageId)
    try reopened.publishSavedResearchReply(body, scope: scope)
    XCTAssertTrue(try reopened.pendingPublicationRecoveryPage(after: "").owners.isEmpty)
    XCTAssertEqual(try reopened.committedResearchRevisions(scope: scope)?.count, 1)
  }

  func testControlledWorkflowComparisonRejectsMismatchedVersionsAndPreservesQualityFailures() throws {
    typealias Intake = AgentCollaborationExperimentPlanIntake
    func ref(_ id: String) -> AgentCollaborationResearchReference { .init(objectId: id, revision: 1, sha256: id) }
    func wire(_ id: String) -> AgentMcpJSONValue {
      .object(["object_id": .string(id), "revision": .int(1), "sha256": .string(id)])
    }
    func record(_ id: String, _ kind: AgentCollaborationResearchDraft.Kind, _ body: AgentMcpJSONObject,
                parents: [AgentCollaborationResearchReference] = []) -> AgentCollaborationResearchRevision {
      .init(reference: ref(id), previousHash: nil, runId: "run", turnId: "turn", authorId: "author", sourceId: "source",
        draft: .init(id: id, objectId: nil, baseRevision: 0, kind: kind, title: id, body: body, parents: parents))
    }
    let records = [
      "dataset": record("dataset", .artifact, [:]),
      "before": record("before", .workflowMethod, ["workflow_method": .object(["domain": .string("fixture")])]),
      "after": record("after", .workflowMethod, ["workflow_method": .object(["domain": .string("fixture")])]),
      "baseline": record("baseline", .innovation,
        ["innovation": .object(["workflow_method": wire("before")])], parents: [ref("before")]),
      "candidate": record("candidate", .innovation, ["innovation": .object([
        "workflow_method": wire("after"), "predictions": .array([.object(["id": .string("prediction")])])
      ])], parents: [ref("after")])
    ]
    func exact(_ reference: AgentCollaborationResearchReference) -> AgentCollaborationResearchRevision? {
      records[reference.objectId].flatMap { $0.reference == reference ? $0 : nil }
    }
    func planCase(_ id: String, purpose: String, direction: String) -> AgentMcpJSONValue {
      .object(["id": .string(id), "purpose": .string(purpose), "metric": .string(id),
        "direction": .string(direction), "prediction": .string("Check"),
        "repetitions": .int(1), "minimum_gain": .int(0), "tolerance": .int(0), "dataset": wire("dataset")])
    }
    var spec: AgentMcpJSONObject = [
      "innovation": wire("candidate"), "baseline": wire("baseline"), "method": .string("A/B"),
      "environment": .string("fixture"), "budget_unit": .string("calls"), "budget_limit": .int(1),
      "prediction_id": .string("prediction"), "report_pointer": .string(""),
      "source": .object(["origin": .string("ios_cloud_tool"), "tool": .string("fixture_measure")]),
      "cases": .array([planCase("time", purpose: "target", direction: "minimize"),
                       planCase("quality", purpose: "regression", direction: "maximize")])
    ]
    func plan(_ spec: AgentMcpJSONObject) -> AgentCollaborationResearchRevision {
      record("plan", .experimentPlan, ["experiment_plan": .object(spec)],
        parents: [ref("baseline"), ref("candidate"), ref("dataset")])
    }
    XCTAssertFalse(Intake.validates(plan(spec).draft, current: exact))
    spec["workflow_comparison"] = .object(["dataset": wire("dataset"), "controlled_conditions": .string("Same inputs"),
      "quality_oracle": .string("Exact expected results"), "cost_accounting": .string("Calls"), "selection_bias": .string("Fixed cases")])
    var registered = plan(spec)
    var comparison: Intake.WorkflowComparison?
    XCTAssertTrue(Intake.validates(registered.draft, freezeComparison: { comparison = $0 }, current: exact))
    registered.workflowComparison = try XCTUnwrap(comparison)
    func sample(_ id: String, variant: String, score: Int64, wrong: Bool = false) -> AgentMcpJSONValue {
      let baseline = variant == "baseline"
      return .object(["case_id": .string(id), "metric": .string(id), "variant": .string(variant),
        "variant_sha256": .string(variant), "workflow_sha256": .string(wrong || baseline ? "before" : "after"),
        "dataset_sha256": .string("dataset"), "value": .int(score), "repetition": .int(1), "budget_used": .int(1)])
    }
    var report: AgentMcpJSONObject = ["format": .string("galaxyssi.experiment-measurements.v1"),
      "plan_sha256": .string("plan"), "environment": .string("fixture"), "budget_unit": .string("calls"),
      "measurements": .array([sample("time", variant: "baseline", score: 4), sample("time", variant: "candidate", score: 2),
        sample("quality", variant: "baseline", score: 5), sample("quality", variant: "candidate", score: 4)])]
    let measured = try XCTUnwrap(Intake.measure([report], plan: registered))
    XCTAssertEqual(measured.first { $0.id == "time" }?.state, "passed")
    XCTAssertEqual(measured.first { $0.id == "quality" }?.state, "not_met")
    XCTAssertFalse(AgentCollaborationMeasuredCase.supportsRetention(measured))
    var samples = try XCTUnwrap(report["measurements"]?.arrayValue)
    samples[1] = sample("time", variant: "candidate", score: 2, wrong: true)
    report["measurements"] = .array(samples)
    XCTAssertNil(Intake.measure([report], plan: registered))
    let revision: AgentMcpJSONObject = ["domain": .string("fixture"), "previous_method": wire("before"),
      "feedback": .array([wire("dataset")])]
    XCTAssertTrue(AgentCollaborationWorkflowIntake.validatesLineage(revision, parents: [ref("before"), ref("dataset")], current: exact))
    XCTAssertFalse(AgentCollaborationWorkflowIntake.validatesLineage(revision, parents: [ref("before")], current: exact))
  }

  func testExperimentResultPlanFeedbackKeepsFieldFactsAndDoesNotDiscloseIsolatedRecords() throws {
    typealias Feedback = AgentCollaborationExperimentResultFeedback
    let scope = AgentCollaborationToolEvidenceScope(runId: "run", conversationId: "group", turnId: "turn",
      memberId: "reporter", sourceId: "source")
    let id = String(repeating: "a", count: 64)
    let hash = String(repeating: "b", count: 64)
    let ref = AgentCollaborationResearchReference(objectId: id, revision: 1, sha256: hash)
    let reference: AgentMcpJSONObject = ["object_id": .string(id), "revision": .int(1), "sha256": .string(hash)]
    var saved = AgentCollaborationResearchRevision(reference: ref, previousHash: nil, runId: "previous",
      turnId: "previous-turn", authorId: "other", sourceId: "other-source",
      draft: .init(id: "plan", objectId: nil, baseRevision: 0, kind: .artifact, title: "Plan",
        body: ["content": .string("Saved")], parents: []))
    func draft(_ raw: AgentMcpJSONValue?) -> AgentCollaborationResearchDraft {
      var body: AgentMcpJSONObject = ["interpretation": .string("Report"), "limitations": .string("Observational")]
      body["plan"] = raw
      return .init(id: "result", objectId: nil, baseRevision: 0, kind: .experimentResult, title: "Result",
        body: ["experiment_result": .object(body)], parents: [ref])
    }
    func problem(_ raw: AgentMcpJSONValue?) throws -> AgentMcpJSONObject {
      do { _ = try Feedback.registeredPlan(in: draft(raw), scope: scope) { _ in saved } }
      catch let feedback as Feedback { return feedback.problem }
      XCTFail("Expected typed result feedback")
      return [:]
    }
    let absent = try problem(nil)
    XCTAssertEqual(absent["code"], .string("experiment_plan_reference_required"))
    XCTAssertEqual(absent["path"], .string("/body/experiment_result/plan"))
    XCTAssertEqual(absent["actual"], .string("absent"))
    XCTAssertEqual(try problem(.null)["actual"], .string("null"))
    XCTAssertEqual(try problem(.array([]))["actual"], .string("not an object"))
    var fractional = reference
    fractional["revision"] = .double(1.5)
    let revision = try problem(.object(fractional))
    XCTAssertEqual(revision["code"], .string("record_revision_invalid"))
    XCTAssertEqual(revision["path"], .string("/body/experiment_result/plan/revision"))
    XCTAssertEqual(revision["actual"], .double(1.5))
    let wrongKind = try problem(.object(reference))
    XCTAssertEqual(wrongKind["component"], .string("WorkspaceRecordValidator"))
    XCTAssertEqual(wrongKind["path"], .string("/body/experiment_result/plan/kind"))
    XCTAssertEqual(wrongKind["actual"], .string("artifact"))
    XCTAssertEqual(wrongKind["reference"], .object(reference))
    var wrongHash = reference
    wrongHash["sha256"] = .string(String(repeating: "c", count: 64))
    let wrong = try problem(.object(wrongHash))
    XCTAssertEqual(wrong["code"], .string("record_digest_mismatch"))
    XCTAssertEqual(wrong["expected"], .string(hash))
    XCTAssertEqual(wrong["actual"], wrongHash["sha256"])
    saved.turnId = scope.turnId
    let hidden = try problem(.object(wrongHash))
    XCTAssertEqual(hidden["code"], .string("record_unavailable"))
    XCTAssertEqual(hidden["actual"], .string("missing or isolated"))
    XCTAssertFalse(AgentMcpJSONCodec.stringify(hidden).contains(hash))
    XCTAssertThrowsError(try Feedback.registeredPlan(in: draft(.object(reference)), scope: scope) { _ in
      throw AgentTeamHistoryDatabase.Failure.unavailable
    }) { XCTAssertTrue($0 is AgentTeamHistoryDatabase.Failure) }
    let contract = try XCTUnwrap(absent["record_contract"]?.objectValue)
    XCTAssertEqual(contract["automatic_conversion"], .bool(false))
    XCTAssertEqual(contract["registration_before_measurements_required"], .bool(true))
    XCTAssertTrue(contract.string("guidance").contains("coordinator assistance"))
  }

  func testExperimentResultRejectionRetainsDraftAndReceiptAcrossReopenWithoutRelabeling() throws {
    let suite = "experiment-result-feedback-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
    let secrets = InMemorySecretStore()
    let file = folder.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    var team = durableTeamSnapshot("experiment-feedback")
    team.members[1].dispatchCheckpoint = .dispatching
    XCTAssertTrue(history.upsert(team))
    let member = team.members[1]
    let scope = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId, memberId: member.memberId, sourceId: member.sourceMessageId)
    func artifact(kind: String, plan: AgentMcpJSONValue? = nil) -> String {
      var result: AgentMcpJSONObject = ["interpretation": .string("Observed"), "limitations": .string("Not measured")]
      result["plan"] = plan
      return AgentMcpJSONCodec.stringify(["format": .string(AgentCollaborationResearchEnvelope.wireFormat),
        "summary": .string("Report"), "workspace": .array([.object([
          "id": .string("report"), "title": .string("Report"), "kind": .string(kind), "base_revision": .int(0),
          "body": .object(["experiment_result": .object(result), "content": .string("Complete original report")]),
          "parents": .array([])
        ])])])
    }
    let raw = artifact(kind: "experiment_result") + "\n"
    let rejected = try history.publishCollaborationMilestone([
      "mode": .string("publish"), "milestone_id": .string("comparison"), "artifact": .string(raw)
    ], scope: scope)
    XCTAssertEqual(rejected["status"], .string("rejected"))
    XCTAssertEqual(rejected["rejected_draft_preserved"], .bool(true))
    let detail = try XCTUnwrap(rejected["record_validation"]?.objectValue)
    XCTAssertEqual(detail["code"], .string("experiment_plan_reference_required"))
    XCTAssertNil(rejected["references"])
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    let lookup: AgentMcpJSONObject = ["mode": .string("receipt"), "milestone_id": .string("comparison"),
      "artifact_sha256": try XCTUnwrap(rejected["artifact_sha256"])]
    XCTAssertEqual(try reopened.publishCollaborationMilestone(lookup, scope: scope), rejected)
    let records = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    let base = "publication:" + AgentMcpJSONCodec.sha256(["run": .string(scope.runId),
      "member": .string(scope.memberId), "source": .string(scope.sourceId)])
    let rejectionKey = base + ":rejected-milestone:" + AgentMcpJSONCodec.sha256([
      "id": .string("comparison"), "hash": try XCTUnwrap(rejected["artifact_sha256"])
    ])
    let preserved = try XCTUnwrap(records.researchRecord(AgentCollaborationMilestoneRejection.self,
      conversationId: scope.conversationId, key: rejectionKey, revision: 0))
    XCTAssertEqual(preserved.artifact, Data(raw.utf8))
    let corruptID = String(repeating: "d", count: 64)
    try records.transaction {
      try records.insertResearchRecord("not a workspace revision", conversationId: scope.conversationId,
        key: "object:" + corruptID, revision: 1)
    }
    let corruptPlan = AgentMcpJSONValue.object(["object_id": .string(corruptID), "revision": .int(1),
      "sha256": .string(String(repeating: "e", count: 64))])
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone([
      "mode": .string("publish"), "milestone_id": .string("broken-store"),
      "artifact": .string(artifact(kind: "experiment_result", plan: corruptPlan))
    ], scope: scope)) { XCTAssertTrue($0 is DecodingError) }
    XCTAssertEqual(try reopened.publishCollaborationMilestone(["mode": .string("list")], scope: scope)["milestones"], .array([]))
    let stored = try reopened.publishCollaborationMilestone([
      "mode": .string("publish"), "milestone_id": .string("report"), "artifact": .string(artifact(kind: "artifact"))
    ], scope: scope)
    let ref = try XCTUnwrap(stored["references"]?.arrayValue?.first?.objectValue)
    var selector = ref
    selector["mode"] = .string("workspace")
    let document = try reopened.recallCollaborationOriginal(selector, scope: scope)
    XCTAssertTrue(document.string("content").contains("Complete original report"))
    let saved = try JSONDecoder().decode(AgentCollaborationResearchRevision.self, from: Data(document.string("content").utf8))
    XCTAssertEqual(saved.draft.kind, .artifact)
    XCTAssertNil(saved.measuredCases)
    team.members[1].status = .succeeded
    team.members[1].replyContent = raw
    team.updatedAtMillis += 1
    XCTAssertTrue(reopened.upsert(team))
    XCTAssertThrowsError(try reopened.publishSavedResearchReply(raw, scope: scope)) {
      XCTAssertEqual(($0 as? AgentCollaborationExperimentResultFeedback)?.problem, detail)
    }
    let final = try XCTUnwrap(history.rejectedResearchReply(scope: scope))
    XCTAssertEqual(Data(final.raw.utf8), Data(raw.utf8))
    XCTAssertEqual(final.rejection.reason, .invalidDraft)
    XCTAssertEqual(final.rejection.problem, detail)
    XCTAssertNil(try history.committedResearchRevisions(scope: scope))
  }

  func testExperimentRegistrationRequiresMeasurableTargetAndUniqueCases() {
    var item: AgentMcpJSONObject = ["id": .string("target"), "metric": .string("accuracy"),
      "prediction": .string("Improves"), "purpose": .string("target"), "direction": .string("maximize"),
      "minimum_gain": .int(1), "tolerance": .int(0), "repetitions": .int(2)]
    XCTAssertTrue(AgentCollaborationExperimentPlanIntake.validatesCases([.object(item)]))
    XCTAssertFalse(AgentCollaborationExperimentPlanIntake.validatesCases([.object(item), .object(item)]))
    item["purpose"] = .string("regression")
    XCTAssertFalse(AgentCollaborationExperimentPlanIntake.validatesCases([.object(item)]))
    item["purpose"] = .string("feasibility")
    XCTAssertFalse(AgentCollaborationExperimentPlanIntake.validatesCases([.object(item)]))
    item["threshold"] = .int(3)
    XCTAssertTrue(AgentCollaborationExperimentPlanIntake.validatesCases([.object(item)]))
  }

  func testExperimentMeasurementKeepsPartialAndRejectsDuplicateOrOverBudgetTrials() throws {
    func decode(_ raw: String) throws -> AgentMcpJSONObject {
      try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8))
    }
    let spec = try decode("""
      {"innovation":{"object_id":"idea","revision":1,"sha256":"new"},
       "baseline":{"object_id":"baseline","revision":1,"sha256":"old"},
       "environment":"fixture","budget_unit":"calls","budget_limit":1,
       "cases":[{"id":"target","purpose":"target","direction":"maximize","metric":"score",
        "prediction":"Gain","minimum_gain":1,"tolerance":0,"repetitions":1}]}
      """)
    let plan = AgentCollaborationResearchRevision(reference: .init(objectId: "plan", revision: 1, sha256: "hash"),
      previousHash: nil, runId: "run", turnId: "turn", authorId: "author", sourceId: "source",
      draft: .init(id: "plan", objectId: nil, baseRevision: 0, kind: .experimentPlan,
        title: "Plan", body: ["experiment_plan": .object(spec)], parents: []))
    let raw = """
      {"format":"galaxyssi.experiment-measurements.v1","plan_sha256":"hash","environment":"fixture","budget_unit":"calls",
       "measurements":[
        {"case_id":"target","variant":"baseline","variant_sha256":"old","metric":"score","repetition":1,"value":2,"budget_used":1},
        {"case_id":"target","variant":"candidate","variant_sha256":"new","metric":"score","repetition":1,"value":4,"budget_used":1}]}
      """
    let report = try decode(raw)
    let complete = AgentCollaborationExperimentPlanIntake.measure([report], plan: plan)
    XCTAssertEqual(complete?.first?.state, "passed")
    XCTAssertEqual(complete?.first?.gain, 2)
    var partial = report
    partial["measurements"] = .array(Array(try XCTUnwrap(report["measurements"]?.arrayValue).prefix(1)))
    XCTAssertEqual(AgentCollaborationExperimentPlanIntake.measure([partial], plan: plan)?.first?.state, "incomplete")
    XCTAssertNil(AgentCollaborationExperimentPlanIntake.measure([report, report], plan: plan))
    let costly = try decode(raw.replacingOccurrences(of: "\"budget_used\":1", with: "\"budget_used\":2"))
    XCTAssertNil(AgentCollaborationExperimentPlanIntake.measure([costly], plan: plan))
  }

  func testCapabilityBankRejectsDroppedCasesWeakerTestsAndCumulativeDrift() throws {
    typealias Intake = AgentCollaborationExperimentPlanIntake
    func ref(_ id: String) -> AgentCollaborationResearchReference { .init(objectId: id, revision: 1, sha256: id) }
    func wire(_ value: AgentCollaborationResearchReference) -> AgentMcpJSONValue {
      .object(["object_id": .string(value.objectId), "revision": .int(value.revision), "sha256": .string(value.sha256)])
    }
    let dataset = ref("dataset")
    let anchor = AgentCollaborationCapabilityBank.Anchor(id: "protected", metric: "score", direction: "maximize",
      dataset: dataset, repetitions: 1, tolerance: 2, value: 100, threshold: 99, result: ref("original"))
    let bank = AgentCollaborationCapabilityBank(lesson: ref("lesson"), previous: nil, domain: "fixture",
      environment: "offline", budgetUnit: "calls", anchors: [anchor])
    let protected: AgentMcpJSONObject = ["id": .string("protected"), "metric": .string("score"),
      "prediction": .string("Retain"), "purpose": .string("regression"), "direction": .string("maximize"),
      "dataset": wire(dataset), "repetitions": .int(1), "minimum_gain": .int(0), "tolerance": .int(2)]
    var target = protected
    target["id"] = .string("target")
    target["purpose"] = .string("target")
    let spec: AgentMcpJSONObject = ["innovation": wire(ref("idea")), "baseline": wire(ref("old")),
      "environment": .string("offline"), "budget_unit": .string("calls"), "budget_limit": .int(1),
      "retention_suite": wire(ref("suite")), "cases": .array([.object(protected), .object(target)])]
    XCTAssertTrue(bank.admits(spec, domain: "fixture"))
    XCTAssertFalse(bank.admits(spec, domain: "other"))
    for (field, value) in [("dataset", wire(ref("different"))), ("tolerance", .int(3)),
                           ("repetitions", .int(0)), ("direction", .string("minimize"))] {
      var changed = protected
      changed[field] = value
      var weakened = spec
      weakened["cases"] = .array([.object(changed), .object(target)])
      XCTAssertFalse(bank.admits(weakened, domain: "fixture"), field)
    }
    var omitted = spec
    omitted["cases"] = .array([.object(target)])
    XCTAssertFalse(bank.admits(omitted, domain: "fixture"))

    let plan = AgentCollaborationResearchRevision(reference: ref("plan"), previousHash: nil,
      runId: "run", turnId: "turn", authorId: "author", sourceId: "source",
      draft: .init(id: "plan", objectId: nil, baseRevision: 0, kind: .experimentPlan,
        title: "Plan", body: ["experiment_plan": .object(spec)], parents: []), retentionBank: bank)
    func report(candidate: Int64) -> AgentMcpJSONObject {
      let rows: [AgentMcpJSONValue] = ["protected", "target"].flatMap { id in
        ["baseline", "candidate"].map { variant in
          .object(["case_id": .string(id), "variant": .string(variant),
            "variant_sha256": .string(variant == "baseline" ? "old" : "idea"),
            "metric": .string("score"), "dataset_sha256": .string("dataset"), "repetition": .int(1),
            "value": .int(id == "protected" ? (variant == "baseline" ? 99 : candidate) :
              (variant == "baseline" ? 1 : 2)), "budget_used": .int(1)])
        }
      }
      return ["format": .string("galaxyssi.experiment-measurements.v1"), "plan_sha256": .string("plan"),
        "environment": .string("offline"), "budget_unit": .string("calls"), "measurements": .array(rows)]
    }
    for candidate in [97, 98, 99] as [Int64] {
      let measured = try XCTUnwrap(Intake.measure([report(candidate: candidate)], plan: plan))
      let row = try XCTUnwrap(measured.first { $0.id == "protected" })
      XCTAssertEqual(row.originalAnchorMet, candidate == 99)
      XCTAssertEqual(row.state, candidate == 99 ? "passed" : "not_met")
    }
    var unpinned = plan
    unpinned.retentionBank = nil
    XCTAssertNil(Intake.measure([report(candidate: 99)], plan: unpinned))
  }

  func testCapabilityChannelRollbackKeepsLatestBankAndRejectsOtherChannels() throws {
    typealias Selection = AgentCollaborationCapabilitySelection
    func ref(_ id: String, _ revision: Int64 = 1) -> AgentCollaborationResearchReference {
      .init(objectId: id, revision: revision, sha256: id + "-\(revision)")
    }
    func record(_ identity: AgentCollaborationResearchReference, kind: AgentCollaborationResearchDraft.Kind)
      -> AgentCollaborationResearchRevision {
      .init(reference: identity, previousHash: nil, runId: "run", turnId: "turn", authorId: "author", sourceId: "source",
        draft: .init(id: identity.objectId, objectId: nil, baseRevision: 0, kind: kind, title: "Fixture", body: [:], parents: []))
    }
    let implementation = ref("implementation"), lesson = ref("lesson"), innovation = ref("innovation")
    let oldSuite = ref("old-bank"), newSuite = ref("new-bank")
    let oldChannel = ref("channel"), currentChannel = ref("channel", 2)
    func selection(_ bank: AgentCollaborationResearchReference) -> Selection {
      .init(implementation: implementation, implementationKind: "tool_release", lesson: lesson, innovation: innovation,
        suite: bank, testedSuite: bank, domain: "fixture", restoredFrom: nil)
    }
    var old = record(oldChannel, kind: .capabilityChannel)
    old.capabilitySelection = selection(oldSuite)
    var current = record(currentChannel, kind: .capabilityChannel)
    current.capabilitySelection = selection(newSuite)
    var retained = record(lesson, kind: .capabilityLesson)
    retained.frozenCloudReads = [.init(evidenceId: "source", sha256: "hash", totalCharacters: 10)]
    var firstBank = record(oldSuite, kind: .capabilitySuite)
    firstBank.retentionBank = .init(lesson: lesson, previous: nil, domain: "fixture",
      environment: "offline", budgetUnit: "calls", anchors: [])
    var latestBank = record(newSuite, kind: .capabilitySuite)
    latestBank.retentionBank = firstBank.retentionBank
    let exact = [lesson.objectId: retained, oldSuite.objectId: firstBank, newSuite.objectId: latestBank,
                 innovation.objectId: record(innovation, kind: .innovation)]
    func rollback(_ target: AgentCollaborationResearchReference) -> Selection? {
      let draft = AgentCollaborationResearchDraft(id: "rollback", objectId: currentChannel.objectId, baseRevision: 2,
        kind: .capabilityChannel, title: "Rollback", body: ["capability_channel": .object([
          "operation": .string("rollback"), "reason": .string("Restore known implementation"),
          "target_revision": .object(["object_id": .string(target.objectId), "revision": .int(target.revision),
            "sha256": .string(target.sha256)])
        ])], parents: [target])
      return Selection.validate(draft: draft, objectID: currentChannel.objectId, head: current,
        exact: { exact[$0.objectId] }, historical: { $0 == old.reference ? old : nil },
        implementationKind: { $0 == implementation ? "tool_release" : nil })
    }
    let restored = try XCTUnwrap(rollback(oldChannel))
    XCTAssertEqual(restored.testedSuite, oldSuite)
    XCTAssertEqual(restored.suite, newSuite)
    XCTAssertTrue(restored.requiresRevalidation)
    XCTAssertNil(rollback(ref("other-channel")))
    XCTAssertNil(rollback(currentChannel))
  }

  func testMethodEvaluationRecallPagesNegativeHistoryAndRequiresVisibleExactCounterparts() throws {
    typealias Recall = AgentCollaborationMethodEvaluations
    let suite = "method-evaluations-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("history.sqlite3")
    let secrets = InMemorySecretStore()
    let group = "comparison-group"
    var team = durableTeamSnapshot("recall-evaluations")
    team.conversationId = group
    let member = try XCTUnwrap(team.members.first)
    let scope = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId, conversationId: group,
      turnId: team.taskId, memberId: member.memberId, sourceId: member.sourceMessageId)
    func makeHistory() -> AgentTeamExecutionHistoryStore {
      AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
        executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    }
    XCTAssertTrue(makeHistory().upsert(team))
    func record(_ number: Int, _ kind: AgentCollaborationResearchDraft.Kind, _ body: AgentMcpJSONObject = [:],
                parents: [AgentCollaborationResearchReference] = [], turn: String = "historical")
      -> AgentCollaborationResearchRevision {
      let digest = String(format: "%064llx", Int64(number))
      return .init(reference: .init(objectId: digest, revision: 1, sha256: digest), previousHash: nil,
        runId: "historical-run", turnId: turn, authorId: "historical-member", sourceId: "historical-source",
        draft: .init(id: "fixture-\(number)", objectId: nil, baseRevision: 0, kind: kind,
          title: "Fixture", body: body, parents: parents))
    }
    let old = record(40, .workflowMethod, ["workflow_method": .object(["domain": .string("research")])])
    let new = record(41, .workflowMethod, old.draft.body)
    let dataset = record(42, .artifact)
    func idea(_ number: Int, _ method: AgentCollaborationResearchRevision) -> AgentCollaborationResearchRevision {
      record(number, .innovation, ["innovation": .object(["domain": .string("research"),
        "workflow_method": .object(Recall.reference(method.reference))])], parents: [method.reference])
    }
    let before = idea(43, old), after = idea(44, new)
    let conditions: AgentMcpJSONObject = ["dataset": .object(Recall.reference(dataset.reference)),
      "controlled_conditions": .string("same data"), "quality_oracle": .string("measured score"),
      "cost_accounting": .string("same limit"), "selection_bias": .string("held out")]
    func comparisonCase(_ purpose: String) -> AgentMcpJSONValue {
      .object(["id": .string(purpose), "purpose": .string(purpose), "metric": .string("score"),
        "prediction": .string("Stable"), "direction": .string("maximize"), "minimum_gain": .int(1),
        "tolerance": .int(0), "repetitions": .int(1)])
    }
    var plan = record(45, .experimentPlan, ["experiment_plan": .object([
      "baseline": .object(Recall.reference(before.reference)), "innovation": .object(Recall.reference(after.reference)),
      "workflow_comparison": .object(conditions), "environment": .string("fixture"), "budget_unit": .string("calls"),
      "budget_limit": .int(1), "cases": .array([comparisonCase("target"), comparisonCase("regression")])
    ])], parents: [before.reference, after.reference, dataset.reference])
    let inputs = [old, new, before, after, dataset]
    plan.workflowComparison = try XCTUnwrap(AgentCollaborationWorkflowComparison.resolve(plan.draft) { reference in
      inputs.first { $0.reference == reference }
    })
    XCTAssertEqual(plan.workflowComparison?.candidate, new.reference)
    var result = record(46, .experimentResult, ["experiment_result": .object([
      "plan": .object(Recall.reference(plan.reference))])], parents: [plan.reference])
    result.measuredCases = [.init(id: "regression", purpose: "regression", state: "not_met")]
    let review = record(47, .capabilityLesson, ["capability_lesson": .object([
      "decision": .string("reject"), "result": .object(Recall.reference(result.reference))])], parents: [result.reference])
    let hidden = record(48, .workflowMethod, old.draft.body, turn: scope.turnId)
    var inaccessible = record(49, .experimentPlan, plan.draft.body, parents: plan.draft.parents)
    inaccessible.workflowComparison = .init(baseline: hidden.reference, candidate: new.reference, dataset: dataset.reference)
    let db = try AgentTeamHistoryDatabase(fileURL: file, storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    let filler = (1...33).map { record($0, .artifact) }
    try db.transaction {
      for row in filler + inputs + [plan, result, review, hidden, inaccessible] {
        try db.insertResearchRecord(row, conversationId: group,
          key: "object:" + row.reference.objectId, revision: row.reference.revision)
      }
    }
    let history = makeHistory()
    var query = Recall.selector(new.reference)
    let page = try history.recallCollaborationOriginal(query, scope: scope)
    XCTAssertEqual(page["records"]?.arrayValue, [])
    let cursor = try XCTUnwrap(page["next_cursor"]?.stringValue)
    query["cursor"] = .string(cursor)
    let rows = try XCTUnwrap(history.recallCollaborationOriginal(query, scope: scope)["records"]?.arrayValue)
    XCTAssertEqual(rows.compactMap { $0.objectValue?.string("kind") }, ["experiment_plan", "experiment_result", "capability_lesson"])
    XCTAssertEqual(rows.dropFirst().first?.objectValue?.string("measured_state"), "regressed")
    XCTAssertEqual(rows.last?.objectValue?.string("review_decision"), "reject")
    XCTAssertEqual(rows.last?.objectValue?["complete_read"], .bool(false))
    XCTAssertEqual(rows.last?.objectValue?["read_original"]?.objectValue?.string("mode"), "workspace")
    var wrong = Recall.selector(old.reference)
    wrong["cursor"] = .string(cursor)
    XCTAssertThrowsError(try history.recallCollaborationOriginal(wrong, scope: scope))
    var otherScope = scope
    otherScope.sourceId = "foreign"
    XCTAssertThrowsError(try history.recallCollaborationOriginal(query, scope: otherScope))
    history.removeResearchObjects(conversationId: group)
    XCTAssertThrowsError(try history.recallCollaborationOriginal(query, scope: scope))
  }

  func testCapabilityRetentionRequiresPassingTargetAndRegression() {
    let target = AgentCollaborationMeasuredCase(id: "target", purpose: "target", state: "passed")
    var regression = AgentCollaborationMeasuredCase(id: "regression", purpose: "regression", state: "passed")
    XCTAssertFalse(AgentCollaborationMeasuredCase.supportsRetention([target]))
    XCTAssertTrue(AgentCollaborationMeasuredCase.supportsRetention([target, regression]))
    regression.state = "not_met"
    XCTAssertFalse(AgentCollaborationMeasuredCase.supportsRetention([target, regression]))
    regression.state = "incomplete"
    XCTAssertFalse(AgentCollaborationMeasuredCase.supportsRetention([target, regression]))
  }

  func testInlineCollaborationOriginalsReportOnlyCompleteSections() {
    func page(_ section: String, _ text: String, next: AgentMcpJSONValue = .null) -> AgentMcpJSONObject {
      let bytes = Data(text.utf8)
      return ["section": .string(section), "offset": .int(0), "next_offset": next,
        "total_bytes": .int(Int64(bytes.count)), "data_b64": .string(bytes.base64EncodedString())]
    }
    let complete = AgentCollaborationInlineOriginals.prompt(originalGoalPrefix: "Exact goal") { section in
      ["goal": "Exact goal", "criteria": "Exact criteria", "source": "Exact source"][section].map {
        page(section, $0)
      }
    }
    XCTAssertTrue(complete.contains("complete_in_prompt_prefix"))
    XCTAssertTrue(complete.contains("complete_in_originals"))
    XCTAssertTrue(complete.contains("Exact criteria"))
    XCTAssertTrue(complete.contains("Exact source"))
    XCTAssertFalse(complete.contains("Exact goal"))
    let limited = AgentCollaborationInlineOriginals.prompt(originalGoalPrefix: "Different", maximumBytes: 10) { section in
      section == "goal" ? page(section, "Partial original", next: .int(16)) : page(section, "Oversized criteria")
    }
    XCTAssertTrue(limited.contains("not_included"))
    XCTAssertFalse(limited.contains("complete_in"))
    XCTAssertFalse(limited.contains("Partial original"))
    XCTAssertFalse(limited.contains("Oversized criteria"))
  }

  func testCollaborationPromptReconsidersFullUnicodeGoalAfterReferenceSpaceIsFreed() throws {
    typealias Budget = AgentCollaborationPromptBudget
    let goal = String(repeating: "\u{1F642}", count: 2_805)
    let required: [Budget.Section] = [.init(name: "Assignment", body: "Keep all instructions")]
    let optional: [Budget.Section] = [
      .init(name: Budget.goal, body: goal, reference: ["section": .string("goal")]),
      .init(name: "Small section", body: "Keep", reference: ["reference": .string(String(repeating: "r", count: 2_600))]),
      .init(name: "Oversized", body: String(repeating: "x", count: 40_000), reference: ["section": .string("source")])
    ]
    let result = try Budget.assemble(required: required, optional: optional, maximum: 7_000)
    XCTAssertEqual(result.included, ["Assignment", Budget.goal, "Small section"])
    XCTAssertEqual(result.omitted, ["Oversized"])
    XCTAssertTrue(result.text.contains(goal))
    XCTAssertTrue(result.text.contains("\"original_goal\":\"complete_inline\""))
    XCTAssertFalse(result.text.contains(String(repeating: "r", count: 128)))
    XCTAssertLessThanOrEqual(result.text.utf16.count, 7_000)
  }

  func testCollaborationPromptUsesExactFooterAndNeverClipsRequiredContext() throws {
    typealias Budget = AgentCollaborationPromptBudget
    let originals = [Budget.goal, Budget.criteria, Budget.source].map {
      Budget.Section(name: $0, body: "complete \($0)", reference: ["section": .string($0)])
    }
    let required: [Budget.Section] = [.init(name: "Assignment", body: "Required instructions")]
    let full = try Budget.assemble(required: required, optional: originals)
    let exact = try Budget.assemble(required: required, optional: originals, maximum: full.text.utf16.count)
    XCTAssertEqual(exact.text, full.text)
    XCTAssertTrue(exact.omitted.isEmpty)
    let largeGoal = Budget.Section(name: Budget.goal, body: String(repeating: "G", count: 40_000),
      reference: ["mode": .string("goal"), "section": .string("goal"), "sha256": .string("exact-goal")])
    func dispatch(recall: Bool) throws -> Budget.Result {
      try Budget.dispatch(assignment: "Complete assignment", resources: "Complete resources",
        responseProtocol: "Complete response protocol", originals: [largeGoal],
        observations: [], canRecall: recall, desktop: false, peerRecipients: "",
        peerRequests: "", peerRequestsPinned: false)
    }
    let referenced = try dispatch(recall: true)
    XCTAssertTrue(referenced.omitted.contains(Budget.goal))
    XCTAssertTrue(referenced.text.contains("exact-goal"))
    XCTAssertTrue(referenced.text.contains("Complete response protocol"))
    XCTAssertTrue(referenced.text.contains(Budget.deliveryReviewGuidance))
    XCTAssertLessThanOrEqual(referenced.text.utf16.count, Budget.maximumCharacters)
    XCTAssertFalse(referenced.text.contains(String(repeating: "G", count: 64)))
    XCTAssertThrowsError(try dispatch(recall: false)) { error in
      XCTAssertTrue(error.localizedDescription.contains("model_dispatched=false"))
    }
  }

  func testCollaborationDeliveryReadinessGuidanceSurvivesAllMemberRoutesAndFinalAssessment() throws {
    typealias Budget = AgentCollaborationPromptBudget
    let guidance = Budget.deliveryReviewGuidance
    XCTAssertTrue(guidance.contains("not future receipt"))
    XCTAssertTrue(guidance.contains("recipient acknowledgement"))
    XCTAssertTrue(guidance.contains("preserve that blocker"))
    for (recall, desktop) in [(false, false), (true, false), (true, true)] {
      let prompt = try Budget.dispatch(assignment: "Review the saved work", resources: "Current resources",
        responseProtocol: nil, originals: [], observations: [], canRecall: recall, desktop: desktop,
        peerRecipients: "", peerRequests: "", peerRequestsPinned: false)
      XCTAssertTrue(prompt.text.contains(guidance))
    }
    let final = CloudModelStreamMutableConversation.goalAssessmentFinalInstruction
    XCTAssertTrue(final.contains(guidance))
    XCTAssertTrue(final.contains("Do not preclaim or await review of this assessment"))
  }

  func testCapabilityPageReusesExactReadsOnlyWithinOneAuthorizedPage() throws {
    let objectID = String(repeating: "a", count: 64)
    let digest = String(repeating: "b", count: 64)
    let ref = AgentCollaborationResearchReference(objectId: objectID, revision: 1, sha256: digest)
    let row = AgentCollaborationCapabilityPage.Row(objectID: objectID, revision: 1)
    let original = AgentCollaborationResearchRevision(reference: ref, previousHash: nil, runId: "run",
      turnId: "turn", authorId: "author", sourceId: "source", draft: .init(id: "tool",
        objectId: nil, baseRevision: 0, kind: .executableTool, title: "Candidate", body: [:], parents: []))
    let author = AgentCollaborationToolEvidenceScope(runId: "run", conversationId: "group",
      turnId: "turn", memberId: "author", sourceId: "source")
    var reads = 0
    func load(_ requested: AgentCollaborationCapabilityPage.Row) -> AgentCollaborationResearchRevision? {
      XCTAssertEqual(requested, row)
      reads += 1
      return original
    }
    var page = AgentCollaborationCapabilityPage(scope: author, load: load)
    XCTAssertEqual(try page.read(row, matching: ref)?.reference, ref)
    XCTAssertEqual(try page.read(row)?.reference, ref)
    XCTAssertNil(try page.read(row, matching: .init(objectId: objectID, revision: 1, sha256: String(repeating: "c", count: 64))))
    XCTAssertEqual(reads, 1)
    var next = AgentCollaborationCapabilityPage(scope: author, load: load)
    XCTAssertEqual(try next.read(row)?.reference, ref)
    XCTAssertEqual(reads, 2)
    let peer = AgentCollaborationToolEvidenceScope(runId: "run", conversationId: "group",
      turnId: "turn", memberId: "peer", sourceId: "peer-source")
    var foreign = AgentCollaborationCapabilityPage(scope: peer, load: load)
    XCTAssertNil(try foreign.read(row, matching: ref))
    XCTAssertNil(try foreign.read(row))
    XCTAssertEqual(reads, 3)
  }

  func testProcedureRecallFindsExactRetainedLessonWithoutExposingPrivateOrMismatchedSources() throws {
    let suite = "procedure-recall-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    var team = durableTeamSnapshot("procedure-discovery")
    team.goal = "Find the frozenmethodneedle"
    team.members[0].dispatchCheckpoint = .accepted
    let reader = team.members[0]
    let other = team.members[1]
    let scope = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId, memberId: reader.memberId, sourceId: reader.sourceMessageId)
    XCTAssertTrue(history.upsert(team))
    let database = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    func ref(_ id: String, digest: String = "f") -> AgentCollaborationResearchReference {
      .init(objectId: String(repeating: id, count: 64), revision: 1, sha256: String(repeating: digest, count: 64))
    }
    func row(_ id: String, _ kind: AgentCollaborationResearchDraft.Kind, _ body: AgentMcpJSONObject)
      -> AgentCollaborationResearchRevision {
      .init(reference: ref(id), previousHash: nil, runId: "previous", turnId: "previous-turn", authorId: "previous-author",
        sourceId: "previous-source", draft: .init(id: id, objectId: nil, baseRevision: 0, kind: kind,
          title: "Directory fixture", body: [kind.rawValue: .object(body)], parents: []))
    }
    let method = String(repeating: "a", count: 220) + " frozenmethodneedle end"
    var visible = row("a", .capabilityLesson, ["decision": .string("retain"), "procedure": .string(method),
      "applies_when": .string("comparisonwindow"), "avoid_when": .string("contraindicationneedle"),
      "transfer_test": .string("transfertestneedle")])
    visible.frozenCloudReads = [.init(evidenceId: "evidence", sha256: "digest", totalCharacters: 10)]
    var hidden = visible
    hidden.reference = ref("b")
    hidden.runId = scope.runId
    hidden.turnId = scope.turnId
    hidden.authorId = other.memberId
    hidden.sourceId = other.sourceMessageId
    func skill(_ id: String, _ lesson: AgentCollaborationResearchReference) -> AgentCollaborationResearchRevision {
      var record = row(id, .procedureSkill, ["name": .string("Review"), "lesson": .object(AgentCollaborationProcedure.fields(lesson)),
        "inputs": .array([.object(["name": .string("dataset"), "description": .string("inputdescriptionneedle")])])])
      record.draft.parents = [lesson]
      record.retainedProcedure = .init(lesson: lesson, innovation: ref("1"), plan: ref("2"), result: ref("3"),
        rollback: ref("4"), domain: "domainneedle", inputs: [.init(name: "dataset", required: true)], method: method,
        appliesWhen: "comparisonwindow", avoidWhen: "contraindicationneedle", transferTest: "transfertestneedle",
        limitations: "Fixture only")
      return record
    }
    let first = skill("c", visible.reference)
    let second = skill("d", visible.reference)
    let isolated = skill("e", hidden.reference)
    let mismatched = skill("f", ref("a", digest: "0"))
    for original in [visible, hidden, first, second, isolated, mismatched] {
      try database.insertResearchRecord(original, conversationId: scope.conversationId,
        key: "object:" + original.reference.objectId, revision: original.reference.revision)
    }
    func skills(_ query: String) throws -> [AgentMcpJSONObject] {
      let output = try history.recallCollaborationOriginal(["mode": .string("capabilities"), "query": .string(query)], scope: scope)
      return (output["capabilities"]?.arrayValue ?? []).compactMap(\.objectValue).filter { $0.string("kind") == "procedure_skill" }
    }
    for query in ["frozenmethodneedle", "comparisonwindow", "contraindicationneedle", "transfertestneedle"] {
      XCTAssertEqual(try skills(query).map { $0.string("object_id") }, [first.reference.objectId, second.reference.objectId])
    }
    let found = try XCTUnwrap(skills("frozenmethodneedle").first)
    XCTAssertTrue(found["excerpts"]?.objectValue?["procedure"]?.strictStringValue?.contains("frozenmethodneedle") == true)
    let linked = try XCTUnwrap(found["linked_sources"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(linked["source"], .object(AgentCollaborationProcedure.fields(visible.reference)))
    XCTAssertEqual(linked["complete_read"], .bool(false))
    XCTAssertEqual(found["grants_permissions"], .bool(false))
    let byInput = try skills("inputdescriptionneedle domainneedle")
    XCTAssertEqual(byInput.count, 4)
    for entry in byInput.suffix(2) { XCTAssertEqual(entry["linked_sources"], .array([])) }
    let pinned = try history.initialCollaborationCapabilities(scope: scope).compactMap(\.objectValue)
    XCTAssertEqual(pinned.map { $0.string("object_id") }, [first.reference.objectId, second.reference.objectId])
    XCTAssertTrue(pinned.allSatisfy { $0["excerpts"] == nil })
    var reads = 0
    var page = AgentCollaborationCapabilityPage(scope: scope) { _ in reads += 1; return visible }
    _ = try page.procedureMetadata(first)
    _ = try page.procedureMetadata(second)
    XCTAssertEqual(reads, 1)
  }

  func testCapabilityRecallFindsHostValidatedReleasesByExactSourceMetadata() throws {
    let suite = "capability-release-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    let team = durableTeamSnapshot("release-recall-reader")
    XCTAssertTrue(history.upsert(team))
    let reader = team.members[0]
    let other = team.members[1]
    let scope = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId, memberId: reader.memberId, sourceId: reader.sourceMessageId)
    let database = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    func record(_ id: String, kind: AgentCollaborationResearchDraft.Kind, title: String, value: AgentMcpJSONObject,
                privateCurrent: Bool = false) -> AgentCollaborationResearchRevision {
      .init(reference: .init(objectId: String(repeating: id, count: 64), revision: 1, sha256: String(repeating: "f", count: 64)),
        previousHash: nil,
        runId: privateCurrent ? scope.runId : "previous", turnId: privateCurrent ? scope.turnId : "previous-turn",
        authorId: privateCurrent ? other.memberId : "previous-author", sourceId: privateCurrent ? other.sourceMessageId : "previous-source",
        draft: .init(id: id, objectId: nil, baseRevision: 0, kind: kind, title: title,
          body: [kind.rawValue: .object(value)], parents: []))
    }
    func save(_ record: AgentCollaborationResearchRevision, group: String? = nil) throws {
      try database.insertResearchRecord(record, conversationId: group ?? scope.conversationId,
        key: "object:" + record.reference.objectId, revision: record.reference.revision)
    }
    let source = "def run(input): return 'internal-code-needle'"
    let digest = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    let spec: AgentMcpJSONObject = [
      "name": .string("Stable integer sort"), "purpose": .string("Order arrays"), "environment": .string("standard-library"),
      "dependencies": .array([.string("Python")]), "applies_when": .string("Comparable values"),
      "source": .string(source), "cases": .array([.string("private-test-needle")])
    ]
    let tool = record("a", kind: .executableTool, title: "Candidate", value: spec)
    let hidden = record("b", kind: .executableTool, title: "Private", value: spec, privateCurrent: true)
    try save(tool)
    try save(hidden)
    func release(_ id: String, title: String, tool: AgentCollaborationResearchReference, hash: String,
                 state: String = AgentCollaborationCapabilityPage.releaseState) -> AgentCollaborationResearchRevision {
      var value = record(id, kind: .toolRelease, title: title, value: ["review": .string("Checked"),
        "applies_when": .string("Integer lists"), "avoid_when": .string("Unknown element types")])
      value.testedToolRelease = ["state": .string(state), "executable_tool": .object(AgentCollaborationCandidateRecall.reference(tool)),
        "source_sha256": .string(hash), "grants_permissions": .bool(false)]
      return value
    }
    let reviewed = release("c", title: "Verified fixture", tool: tool.reference, hash: digest)
    let stale = release("d", title: "Stale digest fixture", tool: tool.reference, hash: String(repeating: "0", count: 64))
    let isolated = release("e", title: "Isolated fixture", tool: hidden.reference, hash: digest)
    let rejected = release("f", title: "Rejected fixture", tool: tool.reference, hash: digest, state: "rejected")
    let mismatched = release("1", title: "Wrong revision digest fixture",
      tool: .init(objectId: tool.reference.objectId, revision: tool.reference.revision, sha256: String(repeating: "2", count: 64)),
      hash: digest)
    for item in [reviewed, stale, isolated, rejected, mismatched] { try save(item) }
    let legacy: AgentMcpJSONObject = ["draft": .object(["kind": .string("tool_release")])]
    try database.insertResearchRecord(legacy, conversationId: scope.conversationId,
      key: "object:" + String(repeating: "0", count: 64), revision: 1)
    XCTAssertNil(AgentCollaborationSavedToolRelease.Review(reviewed.draft))

    func matches(_ query: String) throws -> [AgentMcpJSONObject] {
      let page = try history.recallCollaborationOriginal(["mode": .string("capabilities"), "query": .string(query)], scope: scope)
      return (page["capabilities"]?.arrayValue ?? []).compactMap(\.objectValue)
    }
    for query in ["stable", "arrays", "standard-library"] {
      let released = try matches(query).filter { $0.string("kind") == "tool_release" }
      XCTAssertEqual(released.map { $0.string("object_id") }, [reviewed.reference.objectId])
    }
    let found = try XCTUnwrap(matches("stable").first { $0.string("kind") == "tool_release" })
    XCTAssertEqual(found["state"], .string(AgentCollaborationCapabilityPage.releaseState))
    XCTAssertEqual(found["grants_permissions"], .bool(false))
    XCTAssertEqual(found["requires_scope_and_lineage_check"], .bool(true))
    XCTAssertEqual(found["excerpts"]?.objectValue?["tool_applies_when"], .string("Comparable values"))
    XCTAssertEqual(found["excerpts"]?.objectValue?["applies_when"], .string("Integer lists"))
    let provenance = try XCTUnwrap(found["linked_sources"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(provenance["source"], .object(AgentCollaborationCandidateRecall.reference(tool.reference)))
    XCTAssertEqual(provenance["complete_read"], .bool(false))
    XCTAssertEqual(found["usage_recall"]?.objectValue?["mode"], .string("method_history"))
    for query in ["stale", "isolated", "wrong"] {
      let entry = try XCTUnwrap(matches(query).first)
      XCTAssertEqual(entry["linked_sources"], .array([]))
      XCTAssertNil(entry["excerpts"]?.objectValue?["tool_name"])
    }
    XCTAssertTrue(try matches("rejected").isEmpty)
    XCTAssertTrue(try matches("internal-code-needle").isEmpty)
    XCTAssertTrue(try matches("private-test-needle").isEmpty)
  }

  func testCollaborationSourceMappingPreservesExactUTF16Boundaries() throws {
    let goal = String(repeating: "a", count: 1_023) + "\u{1F642} Next.  "
    let bytes = AgentCollaborationInlineOriginals.source(goal: goal, criteria: Data("[]".utf8))
    let source = try JSONDecoder().decode(AgentMcpJSONObject.self, from: bytes)
    let segments = try XCTUnwrap(source["segments"]?.arrayValue).compactMap(\.objectValue)
    XCTAssertEqual(segments.map { $0.string("id") }, ["source-1", "source-2"])
    XCTAssertEqual(segments.first?.string("text").utf16.count, 1_025)
    XCTAssertEqual(Data(segments.map { $0.string("text") }.joined().utf8), Data(goal.utf8))
    XCTAssertNotEqual(bytes, AgentCollaborationInlineOriginals.source(goal: goal, criteria: Data("[1]".utf8)))
  }

  func testLiveGraphSeparatesReviewTargetsFromEvidenceDependencies() throws {
    func graph(_ targets: String, independent: Bool = true) -> AgentCollaborationLiveGraph? {
      let input = """
      {"format":"galaxyssi.work-expansion.v1","work":[
        {"id":"artifact","member":"author","assignment":"Write","depends_on":[]},
        {"id":"checks","member":"reviewer","assignment":"Collect checks","depends_on":[]},
        {"id":"review","member":"reviewer","assignment":"Review","depends_on":["artifact","checks"],
         "independent_review":\(independent)\(targets)}
      ]}
      """
      return AgentCollaborationLiveGraph().appending(input, authorizedMembers: ["author", "reviewer"],
        historicalAuthors: [:], settled: [:])
    }
    let saved = try XCTUnwrap(graph(#","review_targets":["artifact"]"#))
    let reopened = try JSONDecoder().decode(AgentCollaborationLiveGraph.self, from: JSONEncoder().encode(saved))
    XCTAssertEqual(reopened.work.last?.review_targets, ["artifact"])
    XCTAssertFalse(reopened.ready(settled: ["artifact": .succeeded], active: []).contains { $0.id == "review" })
    XCTAssertTrue(reopened.ready(settled: ["artifact": .succeeded, "checks": .succeeded],
      active: []).contains { $0.id == "review" })
    XCTAssertNil(graph(""))
    XCTAssertNil(graph(#","review_targets":["checks"]"#))
    XCTAssertNil(graph(#","review_targets":["missing"]"#))
    XCTAssertNil(graph(#","review_targets":["artifact","artifact"]"#))
    XCTAssertNil(graph(#","review_targets":[]"#))
    XCTAssertNil(graph(#","review_targets":["artifact"]"#, independent: false))
  }

  func testHypothesisForecastScoresInformationAndRejectsInconsistentMarginals() throws {
    let input = """
    {
      "selected_action":"probe",
      "events":[{"id":"yes","pointer":"/result","expected":true},{"id":"no","pointer":"/result","expected":false}],
      "choices":[{"action_id":"probe","probabilities":{"yes":0.5,"no":0.5}},
        {"action_id":"defer","probabilities":{"yes":0.5,"no":0.5}}],
      "hypothesis_test":{"question":"Which case?","assumptions":"Two cases","likelihood_basis":"Declared",
        "misspecification_check":"Unexpected output",
        "hypotheses":[{"id":"a","claim":"A","prior":0.5},{"id":"b","claim":"B","prior":0.5}],
        "event_ids":["yes","no"],"likelihoods":{
          "probe":{"a":{"yes":1,"no":0},"b":{"yes":0,"no":1}},
          "defer":{"a":{"yes":0.5,"no":0.5},"b":{"yes":0.5,"no":0.5}}}}
    }
    """
    let decode = { (raw: String) in try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8)) }
    let scores = try XCTUnwrap(AgentCollaborationForecastIntake.hypothesisInformation(decode(input)))
    XCTAssertEqual(scores, ["probe": 1, "defer": 0])
    let forecast = try decode(input)
    let observed = try XCTUnwrap(AgentCollaborationForecastIntake.hypothesisFeedback(forecast,
      observed: .bool(true), withinValidity: true))
    XCTAssertEqual(observed.string("state"), "updated_from_observation")
    XCTAssertEqual(observed["posterior"], .object(["a": .double(1), "b": .double(0)]))
    XCTAssertEqual(observed["information_gain_bits"], .double(1))
    XCTAssertEqual(observed["brier_scores"], .object(["yes": .string("0.25"), "no": .string("0.25")]))
    var chained = forecast
    var next = try XCTUnwrap(chained["hypothesis_test"]?.objectValue)
    let previous = next
    next["conditional_history"] = .string("Condition on the first measurement.")
    next["prior_outcome"] = .object(["object_id": .string("old")])
    next["hypotheses"] = .array([
      .object(["id": .string("a"), "claim": .string("A")]),
      .object(["id": .string("b"), "claim": .string("B")])
    ])
    XCTAssertTrue(AgentCollaborationForecastIntake.sameHypothesisQuestion(previous, next))
    chained["hypothesis_test"] = .object(next)
    let carried: AgentMcpJSONObject = ["a": .double(0.5), "b": .double(0.5)]
    XCTAssertNil(AgentCollaborationForecastIntake.hypothesisInformation(chained))
    XCTAssertEqual(AgentCollaborationForecastIntake.hypothesisInformation(chained, carriedPosterior: carried), scores)
    next["question"] = .string("A different question")
    XCTAssertFalse(AgentCollaborationForecastIntake.sameHypothesisQuestion(previous, next))
    XCTAssertEqual(AgentCollaborationForecastIntake.hypothesisFeedback(forecast,
      observed: .bool(true), withinValidity: false)?.string("state"), "stale_observation")
    XCTAssertEqual(AgentCollaborationForecastIntake.hypothesisFeedback(forecast,
      observed: nil, withinValidity: true)?.string("state"), "incomplete_observation")
    XCTAssertEqual(AgentCollaborationForecastIntake.hypothesisFeedback(forecast,
      observed: .string("unknown"), withinValidity: true)?.string("state"), "unmodeled_outcome")
    let invalid = input.replacingOccurrences(of: #""probabilities":{"yes":0.5,"no":0.5}"#,
      with: #""probabilities":{"yes":0.75,"no":0.25}"#)
    XCTAssertNil(AgentCollaborationForecastIntake.hypothesisInformation(try decode(invalid)))
  }

  func testBrierScoreRetainsTinyNonzeroDerivedValues() {
    XCTAssertEqual(AgentCollaborationForecastIntake.brierScore(probability: 1e-200, occurred: false),
      "0." + String(repeating: "0", count: 399) + "1")
    XCTAssertEqual(AgentCollaborationForecastIntake.brierScore(probability: 0.01, occurred: true), "0.9801")
    XCTAssertEqual(AgentCollaborationForecastIntake.brierScore(probability: 0.99, occurred: true), "0.0001")
    XCTAssertEqual(AgentCollaborationForecastIntake.brierScore(probability: 1, occurred: false), "1")
    XCTAssertNil(AgentCollaborationForecastIntake.brierScore(probability: .infinity, occurred: true))
  }

  func testLargeNumericReplayPersistsAllComputedCases() throws {
    let suite = "numeric-replay-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    var team = durableTeamSnapshot("run")
    team.members[1].status = .succeeded
    XCTAssertTrue(history.upsert(team))
    let count = 1_000
    let cases: [AgentMcpJSONValue] = (1...count).map { index in
      .object(["id": .string("case-\(index)"), "input": .object(["x": .int(1)]),
        "expected": .int(1), "absolute_tolerance": .int(0)])
    }
    let validator = AgentCollaborationNumericTrial.validatorId
    let trial: AgentMcpJSONObject = ["purpose": .string("Replay"), "reference_basis": .string("Supplied"),
      "limitations": .string("Finite cases"),
      "validator": .object(["id": .string(validator), "variables": .array([.string("x")]), "cases": .array(cases)]),
      "computation": .object(["validator_id": .string(validator), "model": .object(["constant": .double(1e300)])])]
    let draft = AgentCollaborationResearchDraft(id: "numeric", objectId: nil, baseRevision: 0,
      kind: .numericModelTrial, title: "Trial", body: ["numeric_model_trial": .object(trial)], parents: [])
    let scope = AgentCollaborationToolEvidenceScope(runId: "run", conversationId: team.conversationId,
      turnId: team.taskId, memberId: "review", sourceId: "source-review")
    _ = try history.publishResearchObjects([draft], runId: scope.runId, conversationId: scope.conversationId,
      turnId: scope.turnId, memberId: scope.memberId, sourceId: scope.sourceId)
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    let saved = try XCTUnwrap(reopened.committedResearchRevisions(scope: scope)?.first)
    XCTAssertGreaterThan(try JSONEncoder().encode(saved).count, AgentCollaborationResearchRevision.standardStorageBytes)
    XCTAssertEqual(saved.numericReplay?["checks"]?.arrayValue?.count, count)
    XCTAssertEqual(saved.numericReplay?["failed_cases"], .int(Int64(count)))
  }

  func testNumericTrialUsesExactDecimalToleranceAtFloatBoundary() throws {
    let raw = """
    {"purpose":"Replay","reference_basis":"Supplied","limitations":"Finite cases",
     "validator":{"id":"numeric_model_cases.v1","variables":["x"],"cases":[
       {"id":"boundary","input":{"x":0.4},"expected":0.1,"absolute_tolerance":0.3},
       {"id":"strict","input":{"x":0.4},"expected":0.1,"absolute_tolerance":"0.2999999999999999999"},
       {"id":"opposite","input":{"x":-0.4},"expected":0.1,"absolute_tolerance":"0.5"}]},
     "computation":{"validator_id":"numeric_model_cases.v1","model":{"variable":"x"}}}
    """
    let trial = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8))
    let report = try XCTUnwrap(AgentCollaborationNumericTrial.evaluate(trial))
    let checks = try XCTUnwrap(report["checks"]?.arrayValue).compactMap(\.objectValue)
    XCTAssertEqual(checks.map { $0["passed"] }, [.bool(true), .bool(false), .bool(true)])
    XCTAssertEqual(checks.map { $0["absolute_error"] }, [.string("3e-1"), .string("3e-1"), .string("5e-1")])
  }

  func testNumericTrialPersistsCounterexamplesAndComparesIdenticalCases() throws {
    let raw = """
    {"purpose":"Replay","reference_basis":"Supplied","limitations":"Finite cases",
     "validator":{"id":"numeric_model_cases.v1","variables":["x"],"cases":[
       {"id":"tiny","input":{"x":0.000000000001},"expected":0.000000000001,"absolute_tolerance":0.000000000000000001},
       {"id":"domain","input":{"x":-2},"expected":0,"absolute_tolerance":0}]},
     "computation":{"validator_id":"numeric_model_cases.v1","model":{"op":"log1p","args":[{"variable":"x"}]}}}
    """
    var trial = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8))
    let first = try XCTUnwrap(AgentCollaborationNumericTrial.evaluate(trial))
    XCTAssertEqual(first["failed_cases"], .int(1))
    XCTAssertEqual(first["domain_error_cases"], .int(1))
    var computation = try XCTUnwrap(trial["computation"]?.objectValue)
    computation["model"] = .object(["constant": .double(0)])
    trial["computation"] = .object(computation)
    let second = try XCTUnwrap(AgentCollaborationNumericTrial.evaluate(trial))
    let changes = try XCTUnwrap(AgentCollaborationNumericTrial.comparison(previous: first, current: second))
    XCTAssertEqual(changes["domain_recovered_case_ids"], .array([.string("domain")]))
    XCTAssertEqual(changes["regressed_case_ids"], .array([.string("tiny")]))
    XCTAssertEqual(changes["error_increased_case_ids"], .array([.string("tiny")]))
    computation["model"] = .object(["op": .string("shell"), "args": .array([])])
    trial["computation"] = .object(computation)
    XCTAssertNil(AgentCollaborationNumericTrial.evaluate(trial))
  }

  func testNumericFeedbackPagesRetainAllScopedCasesAndCompactMilestoneReceipts() throws {
    typealias Feedback = AgentCollaborationNumericFeedback
    let suite = "numeric-feedback-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    var team = durableTeamSnapshot("run")
    team.members[1].dispatchCheckpoint = .dispatching
    XCTAssertTrue(history.upsert(team))
    let scope = AgentCollaborationToolEvidenceScope(runId: "run", conversationId: team.conversationId,
      turnId: team.taskId, memberId: team.members[1].memberId, sourceId: team.members[1].sourceMessageId)
    let caseCount = 140
    let ids = (0..<caseCount).map { "case-\u{1F9EA}-\($0)" }
    let cases: [AgentMcpJSONValue] = ids.enumerated().map { index, id in
      .object(["id": .string(id), "input": .object(["x": .int(index.isMultiple(of: 2) ? 4 : -4)]),
        "expected": .int(2), "absolute_tolerance": .int(0)])
    }
    let x: AgentMcpJSONValue = .object(["variable": .string("x")])
    func publish(_ id: String, input: AgentMcpJSONValue, previous: AgentMcpJSONObject? = nil) throws -> AgentMcpJSONObject {
      let validator = AgentCollaborationNumericTrial.validatorId
      var trial: AgentMcpJSONObject = ["purpose": .string("Replay"), "reference_basis": .string("Supplied"),
        "limitations": .string("Finite cases"),
        "validator": .object(["id": .string(validator), "variables": .array([.string("x")]), "cases": .array(cases)]),
        "computation": .object(["validator_id": .string(validator),
          "model": .object(["op": .string("sqrt"), "args": .array([input])])])]
      if let previous { trial["previous_trial"] = .object(previous) }
      let draft: AgentMcpJSONObject = ["id": .string(id), "base_revision": .int(0), "kind": .string("numeric_model_trial"),
        "title": .string("Numeric trial"), "body": .object(["numeric_model_trial": .object(trial)]),
        "parents": .array(previous.map { [.object($0)] } ?? [])]
      let artifact = AgentMcpJSONCodec.stringify(["format": .string("galaxyssi.research-artifact.v1"),
        "summary": .string("Registered trial"), "workspace": .array([.object(draft)])])
      return try history.publishCollaborationMilestone(["mode": .string("publish"), "milestone_id": .string(id),
        "artifact": .string(artifact)], scope: scope)
    }
    let baseline = try publish("before", input: x)
    let oldRef = try XCTUnwrap(baseline["references"]?.arrayValue?.first?.objectValue)
    let candidate = try publish("after", input: .object(["op": .string("neg"), "args": .array([x])]), previous: oldRef)
    let summary = try XCTUnwrap(candidate["numeric_trials"]?.arrayValue?.first?.objectValue)
    let ref = try XCTUnwrap(summary["source_reference"]?.objectValue)
    let selector = try XCTUnwrap(summary["case_feedback"]?.objectValue)
    XCTAssertEqual(summary["case_count"], .int(Int64(caseCount)))
    XCTAssertEqual(summary["failed_cases"], .int(Int64(caseCount / 2)))
    XCTAssertEqual(summary["worst_case"]?.objectValue?["id"], .string(ids[0]))
    XCTAssertNil(summary["checks"])
    XCTAssertEqual(summary["comparison"]?.objectValue?["domain_failed_case_count"], .int(Int64(caseCount / 2)))
    XCTAssertNil(summary["comparison"]?.objectValue?["domain_failed_case_ids"])
    XCTAssertLessThan(AgentMcpJSONCodec.stringify(summary).utf8.count, 2_000)
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    let receipt = try reopened.publishCollaborationMilestone(["mode": .string("receipt"), "milestone_id": .string("after"),
      "artifact_sha256": try XCTUnwrap(candidate["artifact_sha256"])], scope: scope)
    XCTAssertEqual(receipt["numeric_trials"], candidate["numeric_trials"])

    let firstPage = try reopened.recallCollaborationOriginal(selector, scope: scope)
    XCTAssertEqual(firstPage["source_reference"], .object(ref))
    XCTAssertEqual(firstPage["matched_case_count"], .int(Int64(caseCount / 2)))
    let cursor = try XCTUnwrap(firstPage["next_cursor"]?.strictStringValue)
    var wrongFilter = selector
    wrongFilter["cursor"] = .string(cursor)
    wrongFilter["case_filter"] = .string("all")
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(wrongFilter, scope: scope))
    var wrongRevision = oldRef
    wrongRevision["mode"] = .string(Feedback.mode)
    wrongRevision["cursor"] = .string(cursor)
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(wrongRevision, scope: scope))
    var otherReader = scope
    otherReader.memberId = team.members[0].memberId
    otherReader.sourceId = team.members[0].sourceMessageId
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(selector, scope: otherReader))
    var foreignGroup = scope
    foreignGroup.conversationId = "other"
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(selector, scope: foreignGroup))

    let progress = CloudWebToolLoopProgress()
    let tool = CloudModelStreamMutableConversation.collaborationRecallName
    XCTAssertTrue(progress.record(toolName: tool, arguments: selector, output: AgentMcpJSONCodec.stringify(firstPage)))
    var defaultsOnly = selector
    defaultsOnly["case_filter"] = nil
    defaultsOnly["cursor"] = .string("")
    XCTAssertFalse(progress.record(toolName: tool, arguments: defaultsOnly, output: AgentMcpJSONCodec.stringify(firstPage)))
    func read(_ filter: String) throws -> [AgentMcpJSONObject] {
      var input = selector
      input["case_filter"] = .string(filter)
      var content = ""
      for _ in 0..<100 {
        let output = try reopened.recallCollaborationOriginal(input, scope: scope)
        XCTAssertTrue(Feedback.advances(try XCTUnwrap(Feedback.Request(input)), output: output))
        content += try XCTUnwrap(output["content"]?.strictStringValue)
        guard let next = output["next_cursor"]?.strictStringValue else {
          let result = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(content.utf8))
          return try XCTUnwrap(result["cases"]?.arrayValue).compactMap(\.objectValue)
        }
        input["cursor"] = .string(next)
      }
      XCTFail("Numeric case pagination did not terminate")
      return []
    }
    XCTAssertEqual(try read("all").map { $0.string("id") }, ids)
    let failures = try read("failed")
    XCTAssertEqual(failures.map { $0.string("id") }, ids.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element))
    XCTAssertEqual(failures.first?["expected"], .int(2))
    XCTAssertEqual(failures.first?["absolute_tolerance"], .int(0))
    XCTAssertEqual(failures.first?["input"]?.objectValue?["x"], .int(4))
    XCTAssertEqual(failures.first?["observed"]?.objectValue?["error"], .string("nonfinite_expression_result"))
    XCTAssertEqual(failures.first?["changes"], .array([.string("regressed"), .string("domain_failed")]))
    XCTAssertEqual(try read("domain_error").count, caseCount / 2)
    XCTAssertEqual(try read("regressed").count, caseCount / 2)
    XCTAssertEqual(try read("improved").count, caseCount / 2)
    XCTAssertEqual(try read("domain_recovered").count, caseCount / 2)
    XCTAssertTrue(try read("error_reduced").isEmpty)
  }

  func testWorkflowConditionDiagnosticsKeepMissingNullAndExactNumbersDistinct() throws {
    func inspect(_ expected: AgentMcpJSONValue, _ supplied: AgentMcpJSONValue?, pointer: String = "",
                 op: String = "eq") throws -> AgentCollaborationWorkflowConditions.Observation {
      let condition = try XCTUnwrap(AgentCollaborationWorkflowConditions.Condition(.object([
        "id": .string("c"), "input": .string("data"), "pointer": .string(pointer),
        "operator": .string(op), "value": expected, "rationale": .string("Test")
      ]), inputNames: ["data"]))
      var inputs: AgentMcpJSONObject = [:]
      inputs["data"] = supplied
      return condition.evaluate(inputs)
    }
    XCTAssertEqual(try inspect(.null, nil).unknown, "input_missing")
    XCTAssertEqual(try inspect(.null, .null).state, "matched")
    XCTAssertEqual(try inspect(.bool(false), .object([:]), pointer: "/missing").unknown, "pointer_unavailable")
    XCTAssertEqual(try inspect(.int(3), .array([])).unknown, "non_scalar_value")
    XCTAssertEqual(try inspect(.int(3), .string("3")).unknown, "type_mismatch")
    XCTAssertEqual(try inspect(.int(3), .double(1e200)).unknown, "unsupported_numeric_value")
    XCTAssertEqual(try inspect(.int(9_007_199_254_740_993), .double(9_007_199_254_740_992), op: "lt").state, "matched")
    XCTAssertEqual(try inspect(.int(3), .object(["a/b": .array([.double(3.0)])]), pointer: "/a~1b/0").state, "matched")
  }

  func testWorkflowCheckReadsCurrentRetainedLineageWithoutExecutionOrCoverage() throws {
    typealias Check = AgentCollaborationWorkflowCheck
    let suite = "workflow-check-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
    let secrets = InMemorySecretStore()
    let file = folder.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    let database = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    var team = durableTeamSnapshot("check")
    team.members[1].dispatchCheckpoint = .dispatching
    XCTAssertTrue(history.upsert(team))
    let member = team.members[1]
    let scope = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId, memberId: member.memberId, sourceId: member.sourceMessageId)
    func saved(_ number: Int64, _ kind: AgentCollaborationResearchDraft.Kind, _ body: AgentMcpJSONObject,
               parents: [AgentCollaborationResearchReference] = [], author: String = "author") -> AgentCollaborationResearchRevision {
      .init(reference: .init(objectId: String(format: "%064llx", number), revision: 1,
        sha256: String(format: "%064llx", number + 100)), previousHash: nil, runId: "past", turnId: "past-turn",
        authorId: author, sourceId: "original-source", draft: .init(id: "row", objectId: nil, baseRevision: 0,
          kind: kind, title: "Synthetic row", body: [kind.rawValue: .object(body)], parents: parents))
    }
    func method(_ assignment: String) -> AgentMcpJSONObject {
      var body = Dictionary(uniqueKeysWithValues: ["purpose", "bottleneck", "change_rationale", "applies_when",
        "avoid_when", "risks", "expected_gain", "falsifier"].map { ($0, AgentMcpJSONValue.string("Fixture")) })
      body["domain"] = .string("fixture")
      body["inputs"] = .array([.string("data")])
      body["roles"] = .array([.string("worker")])
      body["dimensions"] = .array([.string("verification")])
      body["steps"] = .array([.object(["id": .string("work"), "role": .string("worker"),
        "stage": .string("EXECUTE"), "assignment": .string(assignment)])])
      return body
    }
    let baseline = saved(1, .workflowMethod, method("Baseline work"))
    let candidate = saved(2, .workflowMethod, method("Candidate work"))
    let dataset = saved(3, .artifact, ["content": .string("Dataset")])
    let earlier = saved(4, .innovation, [:], parents: [baseline.reference])
    let later = saved(5, .innovation, [:], parents: [candidate.reference])
    var plan = saved(6, .experimentPlan, [:], parents: [earlier.reference, later.reference, dataset.reference])
    plan.registeredAtMillis = 1
    var result = saved(7, .experimentResult, ["plan": .object(Check.reference(plan.reference))], parents: [plan.reference])
    result.measuredCases = [.init(id: "target", purpose: "target", state: "passed"),
      .init(id: "regression", purpose: "regression", state: "passed")]
    result.trialAuthors = ["author"]
    result.frozenCloudReads = [.init(evidenceId: "original", sha256: "digest", totalCharacters: 1)]
    var lesson = saved(8, .capabilityLesson, ["decision": .string("retain"), "result": .object(Check.reference(result.reference))],
      parents: [result.reference], author: "independent-reviewer")
    lesson.frozenCloudReads = result.frozenCloudReads
    var persistedPlan = try JSONDecoder().decode(AgentMcpJSONObject.self, from: JSONEncoder().encode(plan))
    persistedPlan["workflowComparison"] = .object(["baseline": .object(Check.reference(baseline.reference)),
      "candidate": .object(Check.reference(candidate.reference)), "dataset": .object(Check.reference(dataset.reference))])
    try database.transaction {
      for row in [baseline, candidate, dataset, earlier, later, result, lesson] {
        try database.insertResearchRecord(row, conversationId: scope.conversationId,
          key: "object:" + row.reference.objectId, revision: row.reference.revision)
      }
      try database.insertResearchRecord(persistedPlan, conversationId: scope.conversationId,
        key: "object:" + plan.reference.objectId, revision: plan.reference.revision)
    }
    func condition(_ id: String, _ pointer: String, _ value: AgentMcpJSONValue, rationale: String = "Test") -> AgentMcpJSONValue {
      .object(["id": .string(id), "input": .string("data"), "pointer": .string(pointer), "operator": .string("eq"),
        "value": value, "rationale": .string(rationale)])
    }
    let raw = AgentMcpJSONCodec.stringify(["format": .string(AgentCollaborationResearchEnvelope.wireFormat),
      "summary": .string("Rule"), "workspace": .array([.object([
        "id": .string("conditional"), "title": .string("Conditional workflow"), "kind": .string(Check.kind), "base_revision": .int(0),
        "parents": .array([.object(Check.reference(lesson.reference))]), "body": .object([Check.kind: .object([
          "domain": .string("fixture"), "purpose": .string("Check"), "condition_basis": .string("Original observations"),
          "limitations": .string("Synthetic"), "prospective_test": .string("Future comparison"),
          "lesson": .object(Check.reference(lesson.reference)),
          "when_all": .array((0..<9).map { condition("repeat-\($0)", "/count", .int(3),
            rationale: String(repeating: "x", count: 880)) }),
          "unless_any": .array([condition("mutable", "/mutable", .bool(true))])
        ])])
      ])])])
    let receipt = try history.publishCollaborationMilestone([
      "mode": .string("publish"), "milestone_id": .string("rule"), "artifact": .string(raw)
    ], scope: scope)
    var selector = try XCTUnwrap(receipt["references"]?.arrayValue?.first?.objectValue)
    selector["mode"] = .string(Check.mode)
    selector["inputs"] = .object(["data": .object(["count": .int(3)])])
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    func contents(_ input: AgentMcpJSONObject) throws -> AgentMcpJSONObject {
      var input = input
      var output = ""
      for _ in 0..<32 {
        let page = try reopened.recallCollaborationOriginal(input, scope: scope)
        XCTAssertNil(page["host_read_coverage"])
        XCTAssertEqual(page["trust"], .string(Check.trust))
        output += page.string("content")
        guard let offset = page["next_offset"]?.intValue else {
          return try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(output.utf8))
        }
        input["offset"] = .int(offset)
      }
      throw AgentTeamHistoryDatabase.Failure.corrupt
    }
    let first = try reopened.recallCollaborationOriginal(selector, scope: scope)
    XCTAssertNotNil(first["next_offset"]?.intValue)
    let partial = try contents(selector)
    XCTAssertEqual(partial["unknowns_may_change_selection"], .bool(true))
    XCTAssertEqual(partial["unless_any"]?.arrayValue?.first?.objectValue?["unknown_reason"], .string("pointer_unavailable"))
    XCTAssertEqual(partial["executes_work"], .bool(false))
    XCTAssertEqual(partial["baseline_applicability_verified"], .bool(false))
    selector["inputs"] = .object(["data": .object(["count": .int(2)])])
    let blocked = try contents(selector)
    XCTAssertEqual(blocked["known_blockers"]?.arrayValue?.count, 9)
    XCTAssertEqual(blocked["unknowns_may_change_selection"], .bool(false))
    selector["inputs"] = .object(["data": .object(["count": .int(3), "mutable": .bool(false)])])
    let selected = try contents(selector)
    XCTAssertEqual(selected["selection"]?.objectValue?["variant"], .string("candidate"))
    XCTAssertEqual(selected["grants_permissions"], .bool(false))
    let callback: (AgentMcpJSONObject) -> AgentMcpJSONObject? = {
      try? reopened.recallCollaborationOriginal($0, scope: scope)
    }
    let original = try AgentIOSLocalModelWebToolRunner.collaborationRecallTool(read: callback)
    let registry = try AgentNativeToolRegistry().registerExecutable(Check.nativeTool(original, read: callback))
    XCTAssertTrue(registry.invoke(original.id, input: selector).isSuccess)
    var foreign = scope
    foreign.sourceId = "wrong-source"
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(selector, scope: foreign))
    XCTAssertEqual(reopened.snapshot(supervisorRunId: scope.runId)?.members[1].status, member.status)
    var consumer = durableTeamSnapshot("observed-route")
    consumer.taskId = "observed-route"
    consumer.members[0].dispatchCheckpoint = .accepted
    consumer.members[1].dispatchCheckpoint = .dispatching
    XCTAssertTrue(reopened.upsert(consumer))
    func consumerScope(_ index: Int) -> AgentCollaborationToolEvidenceScope {
      let member = consumer.members[index]
      return .init(runId: consumer.supervisorRunId, conversationId: consumer.conversationId,
        turnId: consumer.taskId, memberId: member.memberId, sourceId: member.sourceMessageId)
    }
    let coordinator = consumerScope(0), producer = consumerScope(1)
    XCTAssertTrue(reopened.advanceGoalCheckpoint(.init(runId: coordinator.runId, conversationId: coordinator.conversationId,
      turnId: coordinator.turnId, revision: 1, phase: .working,
      contract: [.init(id: "result", requirement: "Review output", verification: .documentary, status: .open,
        evidence_kind: nil, evidence: [])], completedWorkIds: []), expectedRevision: 0))
    let now = AgentControlPlaneClock.nowMillis()
    let observation = AgentCollaborationCloudToolEvidence(scope: producer, round: 1,
      call: .init(callId: "observation", name: "probe", argumentsJson: "{}"),
      output: #"{"success":false,"report":"{\"a/b\":[{\"count\":3,\"mutable\":false}]}"}"#,
      succeeded: false, startedAtMillis: now, finishedAtMillis: now)
    let observed = try reopened.recordCloudEvidence(observation).filter { ["evidence_id", "sha256"].contains($0.key) }
    var read = observed
    read["mode"] = .string("evidence")
    _ = try reopened.recallCollaborationOriginal(read, scope: producer)
    let failure: AgentMcpJSONObject = ["observed_issue": .string("Synthetic failure"),
      "interpretation": .string("Report still available"), "uncertainty": .string("Fixture"),
      "applies_when": .string("This fixture"), "avoid_repetition": .string("Keep original"),
      "reconsider_when": .string("New observation"), "recovery_options": .array([.string("Read original fields")])]
    let publication = AgentCollaborationResearchDraft(id: "observation", objectId: nil, baseRevision: 0,
      kind: .failureExperience, title: "Observed failure", body: ["failure_experience": .object(failure)],
      parents: [], observations: [observed])
    _ = try reopened.publishResearchObjects([publication], runId: producer.runId, conversationId: producer.conversationId,
      turnId: producer.turnId, memberId: producer.memberId, sourceId: producer.sourceId,
      milestone: ("observation", String(repeating: "a", count: 64)))
    let inventory = try reopened.goalWorkInventory(scope: coordinator)
    let token = try XCTUnwrap(inventory["members"]?.arrayValue?.first?.objectValue?["published_milestones"]?.arrayValue?
      .first?.objectValue?["token"])
    let ruleRef = try XCTUnwrap(receipt["references"]?.arrayValue?.first)
    func admission(token: AgentMcpJSONValue?, pointer: String = "/a~1b/0", override: Bool = false) -> AgentMcpJSONObject {
      var source: AgentMcpJSONObject = ["observation": .object(observed), "report_pointer": .string("/report"), "pointer": .string(pointer)]
      source["milestone"] = token
      let item: AgentMcpJSONObject = ["execution_id": .string("observed-workflow"), "selection_rule": ruleRef,
        "inputs": .object(override ? ["data": .object(["count": .int(2)])] : [:]),
        "roles": .object(["worker": .string(producer.memberId)]), "observed_inputs": .object(["data": .object(source)])]
      return ["mode": .string("append_work"), "expected_revision": .int(1), "milestone_id": .string("admission"),
        "artifact": .string(AgentMcpJSONCodec.stringify(["format": .string("galaxyssi.work-expansion.v1"),
          "work": .array([.object(["workflow_instance": .object(item)])])]))]
    }
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(admission(token: nil), scope: coordinator))
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(admission(token: token, pointer: "/a~1b/01"), scope: coordinator))
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(admission(token: token, override: true), scope: coordinator))
    let input = admission(token: token)
    let admitted = try reopened.publishCollaborationMilestone(input, scope: coordinator)
    XCTAssertEqual(admitted["status"], .string("work_admitted"))
    let ready = try reopened.readyGoalWork(scope: coordinator, excluding: [], limit: 1)
    let workID = try XCTUnwrap(ready.first)
    let work = try XCTUnwrap(reopened.goalWork(workID, scope: coordinator)?.0)
    XCTAssertEqual(work.assignment, "Candidate work")
    XCTAssertEqual(work.workflowObservedBinding?["method_selection"]?.objectValue?["variant"], .string("candidate"))
    XCTAssertEqual(work.workflowObservedBinding?["input_observations"]?.objectValue?["data"]?.objectValue?["status"], .string("failed"))
    var changed = baseline
    changed.reference.revision = 2
    try database.transaction {
      try database.insertResearchRecord(changed, conversationId: scope.conversationId,
        key: "object:" + changed.reference.objectId, revision: 2)
    }
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(selector, scope: scope))
    XCTAssertFalse(registry.invoke(original.id, input: selector).isSuccess)
    let afterReopen = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    XCTAssertEqual(try afterReopen.publishCollaborationMilestone(input, scope: coordinator)["replayed"], .bool(true))
    let claim = try afterReopen.claimGoalWork(work, scope: coordinator)
    XCTAssertTrue(claim.claimed)
    XCTAssertEqual(claim.dependencies.first?["binding"]?.objectValue, work.workflowObservedBinding)
    reopened.removeResearchObjects(conversationId: scope.conversationId)
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(selector, scope: scope))
  }

  func testWorkflowMethodRejectsCyclesAndExecutionOverrides() throws {
    let raw = """
    {"purpose":"Verify","domain":"Research","bottleneck":"Errors","change_rationale":"Independent review",
     "applies_when":"Comparable","avoid_when":"Unsafe","risks":"Delay","expected_gain":"Accuracy","falsifier":"No gain",
     "dimensions":["verification"],"roles":["author","reviewer"],"inputs":[],
     "steps":[{"id":"draft","role":"author","stage":"EXPLORE","assignment":"Draft"},
       {"id":"review","role":"reviewer","stage":"VERIFY","assignment":"Review",
        "depends_on":["draft"],"independent_review":true}]}
    """
    func validates(_ input: String) throws -> Bool {
      AgentCollaborationWorkflowIntake.validates(try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(input.utf8)))
    }
    XCTAssertTrue(try validates(raw))
    let body = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8))
    let method = AgentCollaborationResearchReference(objectId: "method", revision: 1, sha256: "exact")
    let instance = AgentCollaborationWorkflowInstance(execution_id: "run", method: method,
      inputs: [:], roles: ["author": "writer", "reviewer": "reviewer"])
    let steps = try XCTUnwrap(instance.compile(body))
    XCTAssertEqual(steps.map(\.stage), ["EXPLORE", "VERIFY"])
    XCTAssertEqual(steps.last?.depends_on, [try XCTUnwrap(steps.first?.id)])
    XCTAssertEqual(instance.compile(body), steps)
    let sameMember = AgentCollaborationWorkflowInstance(execution_id: "run", method: method,
      inputs: [:], roles: ["author": "writer", "reviewer": "writer"])
    XCTAssertNil(sameMember.compile(body))
    let mixed = """
    {"format":"galaxyssi.work-expansion.v1","work":[
      {"id":"ordinary","member":"writer","assignment":"Other work","depends_on":[]},
      {"workflow_instance":{"execution_id":"run","method":{"object_id":"method","revision":1,"sha256":"exact"},
        "inputs":{},"roles":{"author":"writer","reviewer":"reviewer"}}}
    ]}
    """
    let expansion = try JSONDecoder().decode(AgentCollaborationLiveGraph.WorkflowExpansion.self, from: Data(mixed.utf8))
    let empty = AgentCollaborationLiveGraph()
    XCTAssertNil(empty.appending(expansion, authorizedMembers: ["writer", "reviewer"],
      historicalAuthors: [:], settled: [:]) { _ in nil })
    let graph = try XCTUnwrap(empty.appending(expansion, authorizedMembers: ["writer", "reviewer"],
      historicalAuthors: [:], settled: [:]) { $0.compile(body) })
    XCTAssertEqual(graph.work.map(\.id), ["ordinary"] + steps.map(\.id))
    XCTAssertEqual(graph.workflowInstances?["run"], instance)
    let replay = try JSONDecoder().decode(AgentCollaborationLiveGraph.WorkflowExpansion.self,
      from: Data(mixed.replacingOccurrences(of: "{\"id\":\"ordinary\",\"member\":\"writer\",\"assignment\":\"Other work\",\"depends_on\":[]},", with: "").utf8))
    XCTAssertEqual(graph.appending(replay, authorizedMembers: ["writer", "reviewer"],
      historicalAuthors: [:], settled: [:]) { _ in nil }, graph)
    let overridden = mixed.replacingOccurrences(of: "{\"workflow_instance\":", with: "{\"assignment\":\"Override\",\"workflow_instance\":")
    XCTAssertThrowsError(try JSONDecoder().decode(AgentCollaborationLiveGraph.WorkflowExpansion.self, from: Data(overridden.utf8)))
    XCTAssertFalse(try validates(raw.replacingOccurrences(of: "\"assignment\":\"Draft\"",
      with: "\"assignment\":\"Draft\",\"depends_on\":[\"review\"]")))
    XCTAssertFalse(try validates(raw.replacingOccurrences(of: "\"assignment\":\"Draft\"",
      with: "\"assignment\":\"Draft\",\"tool_id\":\"override\"")))
    XCTAssertFalse(try validates(raw.replacingOccurrences(of: "\"role\":\"reviewer\"", with: "\"role\":\"author\"")))
  }

  func testSavedToolValidationPreflightCannotLookLikeRuntimeExecution() throws {
    typealias Validation = AgentCollaborationTypedRecordValidation
    typealias Execution = AgentCollaborationSavedToolExecution
    let ref = AgentCollaborationResearchReference(objectId: String(repeating: "a", count: 64), revision: 1,
      sha256: String(repeating: "b", count: 64))
    let assignment = AgentCollaborationToolEvidenceScope(runId: "run", conversationId: "group", turnId: "turn",
      memberId: "member", sourceId: "source")
    let draft = AgentCollaborationResearchDraft(id: "tool", objectId: nil, baseRevision: 0, kind: .executableTool,
      title: "Tool", body: ["executable_tool": .object([:])], parents: [])
    let revision = AgentCollaborationResearchRevision(reference: ref, previousHash: nil, runId: assignment.runId,
      turnId: assignment.turnId, authorId: assignment.memberId, sourceId: assignment.sourceId, draft: draft)
    XCTAssertThrowsError(try Validation.requireToolRecord(ref, kind: .toolTestPlan, path: "/reference", read: { _ in nil })) {
      let problem = ($0 as? Validation)?.problem
      XCTAssertEqual(problem?["code"], .string("record_unavailable"))
      XCTAssertEqual(problem?["actual"], .string("missing or isolated"))
    }
    var problem: AgentMcpJSONObject = [:]
    XCTAssertThrowsError(try Validation.requireToolRecord(ref, kind: .executableTool, path: "/reference",
      read: { _ in revision }, isCurrent: { _ in false })) {
      problem = ($0 as? Validation)?.problem ?? [:]
      XCTAssertEqual(problem["code"], .string("record_not_current"))
    }
    let scope = Execution.Scope(assignment: assignment, profileFingerprint: "phone", desktopID: "desktop",
      desktopFingerprint: "pair", routeID: "route", generation: 1)
    var record = Execution.Record(scope: scope, executionID: "request", inputHash: "input", plan: ref,
      timeoutMillis: 1_000, ownerProcess: Execution.processID, state: .running, updatedAt: 1)
    let observation = Execution.validationObservation(problem, record: record, now: 2)
    XCTAssertEqual(observation.result.status, .rejected)
    XCTAssertFalse(observation.result.isSuccess)
    XCTAssertEqual(observation.result.output["runtime_invoked"], .bool(false))
    XCTAssertNotEqual(observation.result.provenance.executorId, AgentIOSOnDeviceRuntimeNativeToolCatalog.brokerExecutorId)
    record.result = observation.result.output
    XCTAssertEqual(record.response["record_validation"], .object(problem))
  }

  func testTypedRecordContentIsOptionalButNeverCoercedOrSynthesized() throws {
    for kind in [AgentCollaborationResearchDraft.Kind.executableTool, .toolTestPlan, .workflowMethod, .experimentPlan,
                 .experimentResult, .capabilityGap, .innovation, .learningAgenda, .failureExperience] {
      var draft = AgentCollaborationResearchDraft(id: "typed", objectId: nil, baseRevision: 0, kind: kind, title: "Typed",
        body: [kind.rawValue: .object(["original": .string("Exact payload")])], parents: [])
      let before = try JSONEncoder().encode(draft)
      XCTAssertNoThrow(try AgentCollaborationTypedRecordValidation.validate(draft))
      XCTAssertEqual(try JSONEncoder().encode(draft).count, before.count)
      XCTAssertNil(draft.body["content"])
      for invalid in [AgentMcpJSONValue.null, .int(1), .bool(true), .array([]), .object([:]), .string(" \n\t")] {
        draft.body["content"] = invalid
        XCTAssertThrowsError(try AgentCollaborationTypedRecordValidation.validate(draft)) {
          let problem = ($0 as? AgentCollaborationTypedRecordValidation)?.problem
          XCTAssertEqual(problem?["code"], .string("record_content_invalid"))
          XCTAssertEqual(problem?["path"], .string("/body/content"))
        }
        XCTAssertEqual(draft.body["content"], invalid)
      }
      draft.body["content"] = .string("Supplied original prose")
      XCTAssertNoThrow(try AgentCollaborationTypedRecordValidation.validate(draft))
      draft.body[kind.rawValue] = .string("not structured")
      XCTAssertThrowsError(try AgentCollaborationTypedRecordValidation.validate(draft)) {
        XCTAssertEqual(($0 as? AgentCollaborationTypedRecordValidation)?.problem["code"], .string("typed_body_required"))
      }
    }
    let documentary = AgentCollaborationResearchDraft(id: "document", objectId: nil, baseRevision: 0,
      kind: .artifact, title: "Document", body: ["content": .string("Documentary original")], parents: [])
    XCTAssertFalse(AgentCollaborationTypedRecordValidation.kinds.contains(documentary.kind.rawValue))
  }

  func testTypedToolPublicationPreservesSourceAndPersistsInvalidOptionalContentFeedback() throws {
    let suite = "typed-content-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
    let secrets = InMemorySecretStore()
    let file = folder.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    var team = durableTeamSnapshot("typed-records")
    team.members[1].dispatchCheckpoint = .dispatching
    XCTAssertTrue(history.upsert(team))
    let member = team.members[1]
    let scope = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId, memberId: member.memberId, sourceId: member.sourceMessageId)
    let source = "def run(parameters):\n    return parameters\n"
    let spec: AgentMcpJSONObject = ["language": .string("python"), "name": .string("Identity"),
      "purpose": .string("Preserve data"), "applies_when": .string("Tests"), "avoid_when": .string("Unverified use"),
      "environment": .string("python"), "dependencies": .string("None"), "side_effects": .string("None"),
      "source": .string(source), "input_schema": .object(["type": .string("object"), "properties": .object([:])])]
    func artifact(_ content: AgentMcpJSONValue?, id: String = "source", kind: String = "executable_tool") -> String {
      var body: AgentMcpJSONObject = ["executable_tool": .object(spec)]
      body["content"] = content
      return AgentMcpJSONCodec.stringify(["format": .string(AgentCollaborationResearchEnvelope.wireFormat),
        "summary": .string("Tool candidate"), "workspace": .array([.object([
          "id": .string(id), "base_revision": .int(0), "kind": .string(kind), "title": .string("Identity"),
          "body": .object(body), "parents": .array([])
        ])])])
    }
    let raw = artifact(nil)
    let input: AgentMcpJSONObject = ["mode": .string("publish"), "milestone_id": .string("typed"), "artifact": .string(raw)]
    let receipt = try history.publishCollaborationMilestone(input, scope: scope)
    XCTAssertEqual(receipt["success"], .bool(true))
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    XCTAssertEqual(try reopened.publishCollaborationMilestone(input, scope: scope), receipt)
    var selector = try XCTUnwrap(receipt["references"]?.arrayValue?.first?.objectValue)
    selector["mode"] = .string("workspace")
    let original = try reopened.recallCollaborationOriginal(selector, scope: scope)
    let saved = try JSONDecoder().decode(AgentCollaborationResearchRevision.self, from: Data(original.string("content").utf8))
    XCTAssertNil(saved.draft.body["content"])
    XCTAssertEqual(saved.draft.body["executable_tool"]?.objectValue, spec)
    XCTAssertNil(saved.measuredCases)
    let generic: AgentMcpJSONObject = ["mode": .string("publish"), "milestone_id": .string("document"),
      "artifact": .string(artifact(.string("Just a document"), id: "generic", kind: "artifact"))]
    let genericReceipt = try reopened.publishCollaborationMilestone(generic, scope: scope)
    let notice = try XCTUnwrap(genericReceipt["record_notices"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(notice["code"], .string("typed_payload_not_registered"))
    XCTAssertEqual(notice["executable_registration"], .bool(false))
    var genericSelector = try XCTUnwrap(notice["reference"]?.objectValue)
    genericSelector["mode"] = .string("workspace")
    let genericPage = try reopened.recallCollaborationOriginal(genericSelector, scope: scope)
    XCTAssertEqual(genericPage["record_notice"]?.objectValue?["actual_kind"], .string("artifact"))
    let wrongDigest = String(repeating: "0", count: 64)
    let wrongReference: AgentMcpJSONObject = ["object_id": .string(saved.reference.objectId),
      "revision": .int(saved.reference.revision), "sha256": .string(wrongDigest)]
    let badLink = AgentMcpJSONCodec.stringify(["format": .string(AgentCollaborationResearchEnvelope.wireFormat),
      "summary": .string("Test"), "workspace": .array([.object([
        "id": .string("wrong-digest"), "base_revision": .int(0), "kind": .string("tool_test_plan"), "title": .string("Test"),
        "body": .object(["tool_test_plan": .object(["executable_tool": .object(wrongReference)])]),
        "parents": .array([.object(wrongReference)])
      ])])])
    let linkFailure = try reopened.publishCollaborationMilestone(["mode": .string("publish"),
      "milestone_id": .string("wrong-digest"), "artifact": .string(badLink)], scope: scope)
    XCTAssertEqual(linkFailure["record_validation"]?.objectValue?["code"], .string("record_digest_mismatch"))
    XCTAssertEqual(linkFailure["record_validation"]?.objectValue?["expected"], .string(saved.reference.sha256))
    XCTAssertEqual(try history.publishCollaborationMilestone(["mode": .string("receipt"), "milestone_id": .string("wrong-digest"),
      "artifact_sha256": try XCTUnwrap(linkFailure["artifact_sha256"])], scope: scope), linkFailure)
    let invalid = artifact(.int(7), id: "invalid")
    let rejected = try reopened.publishCollaborationMilestone([
      "mode": .string("publish"), "milestone_id": .string("invalid"), "artifact": .string(invalid)
    ], scope: scope)
    XCTAssertEqual(rejected["status"], .string("rejected"))
    let detail = try XCTUnwrap(rejected["record_validation"]?.objectValue)
    XCTAssertEqual(detail["code"], .string("record_content_invalid"))
    XCTAssertEqual(detail["actual"], .string("not a string"))
    XCTAssertEqual(try history.publishCollaborationMilestone(["mode": .string("receipt"), "milestone_id": .string("invalid"),
      "artifact_sha256": try XCTUnwrap(rejected["artifact_sha256"])], scope: scope), rejected)
    team.members[1].status = .succeeded
    team.members[1].replyContent = invalid
    team.updatedAtMillis += 1
    XCTAssertTrue(reopened.upsert(team))
    XCTAssertThrowsError(try reopened.publishSavedResearchReply(invalid, scope: scope)) {
      XCTAssertTrue($0 is AgentCollaborationTypedRecordValidation)
    }
    let retained = try XCTUnwrap(history.rejectedResearchReply(scope: scope))
    XCTAssertEqual(retained.raw, invalid)
    XCTAssertEqual(retained.rejection.problem, detail)
    XCTAssertNil(try history.committedResearchRevisions(scope: scope))
  }

  func testToolTestRegistrationUsesSkillParameterContract() throws {
    let tool = """
    {"language":"python","name":"Check","purpose":"Validate","applies_when":"Input","avoid_when":"None",
     "environment":"python","dependencies":"None","side_effects":"None","source":"def run(parameters): return parameters",
     "input_schema":{"type":"object","required":["value"],"properties":{"value":{"type":"integer"}}}}
    """
    let plan = """
    {"environment":"python","purpose":"Validate","coverage_gaps":"None known","oracle_basis":"Identity",
     "cases":[{"id":"target","purpose":"target","reason":"Typical","input":{"value":1},"expected":1},
       {"id":"regression","purpose":"regression","reason":"Zero","input":{"value":0},"expected":null}]}
    """
    func decode(_ raw: String) throws -> AgentMcpJSONObject {
      try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8))
    }
    let spec = try decode(tool)
    XCTAssertTrue(AgentCollaborationToolRegistration.validatesTestPlan(try decode(plan), tool: spec))
    XCTAssertFalse(AgentCollaborationToolRegistration.validatesTestPlan(
      try decode(plan.replacingOccurrences(of: "\"value\":0", with: "\"value\":\"0\"")), tool: spec))
    XCTAssertFalse(AgentCollaborationToolRegistration.validatesTestPlan(
      try decode(plan.replacingOccurrences(of: ",\"expected\":null", with: "")), tool: spec))
  }

  func testSavedToolExecutionJournalRecoversWithoutRerunningAndFencesScope() throws {
    typealias Execution = AgentCollaborationSavedToolExecution
    let suite = "saved-tool-execution-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    func open() -> AgentTeamExecutionHistoryStore {
      AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets, executionStore: SavedTeamRecoveryFixture([]),
        fileURL: root.appendingPathComponent("history.sqlite"))
    }
    let history = open()
    var team = durableTeamSnapshot("journal-run")
    team.members[0].dispatchCheckpoint = .accepted
    team.members[0].dispatchAllowsSavedToolTest = true
    XCTAssertTrue(history.upsert(team))
    let assignment = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId, memberId: team.members[0].memberId, sourceId: team.members[0].sourceMessageId)
    func scope(generation: Int64 = 1) -> Execution.Scope {
      .init(assignment: assignment, profileFingerprint: "profile", desktopID: "desktop",
        desktopFingerprint: "pair", routeID: "route", generation: generation)
    }
    func start(_ id: String, timeout: AgentMcpJSONValue = .int(2_000), extra: Bool = false) -> Execution.Request? {
      var input: AgentMcpJSONObject = ["mode": .string("start"), "execution_id": .string(id), "timeout_ms": timeout,
        "tool_test_plan": .object(["object_id": .string(String(repeating: "a", count: 64)),
          "sha256": .string(String(repeating: "b", count: 64)), "revision": .int(1)])]
      if extra { input["source"] = .string("not permitted") }
      return Execution.Request(phase: "start", input: input)
    }
    func query(_ id: String, _ mode: String) throws -> Execution.Request {
      try XCTUnwrap(Execution.Request(phase: mode, input: ["mode": .string(mode), "execution_id": .string(id)]))
    }
    XCTAssertNil(start("tool\n"))
    XCTAssertNil(start("tool", timeout: .string("2000")))
    XCTAssertNil(start("tool", extra: true))
    var runInput: AgentMcpJSONObject = ["mode": .string("start"), "execution_id": .string("run-tool"),
      "tool_release": .object(["object_id": .string(String(repeating: "c", count: 64)),
        "sha256": .string(String(repeating: "d", count: 64)), "revision": .int(1)]),
      "parameters": .object(["value": .int(21)]), "timeout_ms": .int(2_000)]
    let requestedRun = try XCTUnwrap(Execution.Request(phase: "start", input: runInput))
    let runAdmission = try history.updateSavedToolExecution(.request(requestedRun), scope: scope(), process: "a", now: 1)
    XCTAssertTrue(runAdmission.shouldLaunch)
    XCTAssertEqual(runAdmission.record?.releaseTarget, .release)
    XCTAssertEqual(runAdmission.record?.parameters?["value"], .int(21))
    XCTAssertFalse(try history.updateSavedToolExecution(.request(requestedRun), scope: scope(), process: "a", now: 2).shouldLaunch)
    runInput["parameters"] = .object(["value": .int(22)])
    XCTAssertThrowsError(try history.updateSavedToolExecution(.request(try XCTUnwrap(
      Execution.Request(phase: "start", input: runInput))), scope: scope(), process: "a", now: 2))
    runInput["source"] = .string("override")
    XCTAssertNil(Execution.Request(phase: "start", input: runInput))
    XCTAssertNil(Execution.Request(phase: "cancel", input: ["mode": .string("status"), "execution_id": .string("tool")]))
    let original = try XCTUnwrap(start("tool"))
    XCTAssertTrue(Execution.permitsDirectRuntime(source: "def run(parameters): return parameters", key: "saved-test"))
    XCTAssertFalse(Execution.permitsDirectRuntime(source: "def run(parameters): return 'delete'", key: "saved-test"))
    let busy = try history.updateSavedToolExecution(.request(original), scope: scope(), allowAdmission: false, process: "a", now: 1)
    XCTAssertEqual(busy.response["status"], .string("busy"))
    XCTAssertFalse(busy.shouldLaunch)
    let admitted = try history.updateSavedToolExecution(.request(original), scope: scope(), process: "a", now: 1)
    XCTAssertTrue(admitted.shouldLaunch)
    XCTAssertEqual(admitted.response["status"], .string("queued"))
    XCTAssertFalse(try history.updateSavedToolExecution(.request(original), scope: scope(), process: "a", now: 2).shouldLaunch)
    let different = try XCTUnwrap(start("tool", timeout: .int(3_000)))
    XCTAssertThrowsError(try history.updateSavedToolExecution(.request(different), scope: scope(), process: "a", now: 2))
    XCTAssertThrowsError(try history.updateSavedToolExecution(.request(original), scope: scope(generation: 2), process: "a", now: 2))
    XCTAssertTrue(try history.updateSavedToolExecution(.running(executionID: "tool"), scope: scope(), process: "a", now: 3).didStart)
    let reopened = open()
    let recovered = try reopened.updateSavedToolExecution(.request(original), scope: scope(), process: "b", now: 4)
    XCTAssertFalse(recovered.shouldLaunch)
    XCTAssertEqual(recovered.response["status"], .string("interrupted"))
    XCTAssertFalse(try reopened.updateSavedToolExecution(.running(executionID: "tool"), scope: scope(), process: "b", now: 5).didStart)

    let queued = try XCTUnwrap(start("queued"))
    _ = try reopened.updateSavedToolExecution(.request(queued), scope: scope(), process: "b", now: 6)
    let cancelled = try reopened.updateSavedToolExecution(.request(query("queued", "cancel")), scope: scope(), process: "b", now: 7)
    XCTAssertEqual(cancelled.response["status"], .string("cancelled"))
    XCTAssertFalse(cancelled.shouldCancel)
    XCTAssertFalse(try reopened.updateSavedToolExecution(.running(executionID: "queued"), scope: scope(), process: "b", now: 8).didStart)
    let revoked = try XCTUnwrap(start("revoked"))
    _ = try reopened.updateSavedToolExecution(.request(revoked), scope: scope(), process: "b", now: 8)
    let interrupted = try reopened.updateSavedToolExecution(.interrupt(executionID: "revoked"),
      scope: scope(), process: "b", now: 8)
    XCTAssertEqual(interrupted.response["status"], .string("interrupted"))
    XCTAssertFalse(try reopened.updateSavedToolExecution(.request(revoked), scope: scope(), process: "b", now: 8).shouldLaunch)

    let running = try XCTUnwrap(start("running"))
    _ = try reopened.updateSavedToolExecution(.request(running), scope: scope(), process: "b", now: 9)
    _ = try reopened.updateSavedToolExecution(.running(executionID: "running"), scope: scope(), process: "b", now: 10)
    let cancelling = try reopened.updateSavedToolExecution(.request(query("running", "cancel")),
      scope: scope(), process: "b", now: 11)
    XCTAssertTrue(cancelling.shouldCancel)
    XCTAssertEqual(cancelling.response["status"], .string("cancelling"))
    let pending = try XCTUnwrap(cancelling.record)
    let outcomes: [(String, Execution.Record.State)] = [
      ("runtime_execution_cancelled", .cancelled), ("runtime_cancellation_unconfirmed", .interrupted),
      ("runtime_execution_outcome_unknown", .interrupted)
    ]
    for (code, state) in outcomes {
      let output: AgentMcpJSONObject = ["error": .object(["code": .string(code)])]
      let terminal = try Execution.apply(.finish(executionID: "running", result: output),
        scope: scope(), existing: pending, process: "b", now: 12)
      XCTAssertEqual(terminal.record?.state, state)
      XCTAssertEqual(terminal.record?.result, output)
    }
    let result: AgentMcpJSONObject = ["native_status": .string("cancelled"), "passed": .null]
    _ = try reopened.updateSavedToolExecution(.finish(executionID: "running", result: result), scope: scope(), process: "b", now: 12)
    let restored = try open().updateSavedToolExecution(.request(query("running", "status")), scope: scope(), process: "c", now: 13)
    XCTAssertEqual(restored.response["status"], .string("finished"))
    XCTAssertEqual(restored.response["result"], .object(result))
    reopened.removeResearchObjects(conversationId: assignment.conversationId)
    XCTAssertThrowsError(try reopened.updateSavedToolExecution(.request(original), scope: scope(), process: "b", now: 14))
  }

  func testSavedToolTestResolvesExactRecordsAndKeepsTheOracleOutsidePython() throws {
    let suite = "saved-tool-test-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: InMemorySecretStore(),
      executionStore: SavedTeamRecoveryFixture([]), fileURL: root.appendingPathComponent("history.sqlite"))
    func scope(_ team: AgentTeamExecutionSnapshot) -> AgentCollaborationToolEvidenceScope {
      .init(runId: team.supervisorRunId, conversationId: team.conversationId, turnId: team.taskId,
        memberId: team.members[0].memberId, sourceId: team.members[0].sourceMessageId)
    }
    func publish(_ draft: AgentCollaborationResearchDraft, run: String) throws -> AgentCollaborationResearchReference {
      var author = durableTeamSnapshot(run)
      author.taskId = run
      author.members[0].status = .succeeded
      XCTAssertTrue(history.upsert(author))
      let owner = scope(author)
      return try XCTUnwrap(history.publishResearchObjects([draft], runId: owner.runId,
        conversationId: owner.conversationId, turnId: owner.turnId,
        memberId: owner.memberId, sourceId: owner.sourceId).references.first)
    }
    let spec: AgentMcpJSONObject = [
      "language": .string("python"), "name": .string("Check"), "purpose": .string("Validate"),
      "applies_when": .string("Input"), "avoid_when": .string("None"), "environment": .string("python"),
      "dependencies": .string("None"), "side_effects": .string("None"),
      "source": .string("def run(parameters): return parameters['value']"),
      "input_schema": .object(["type": .string("object"), "required": .array([.string("value")]),
        "properties": .object(["value": .object(["type": .string("integer")])])])
    ]
    let tool = try publish(.init(id: "tool", objectId: nil, baseRevision: 0, kind: .executableTool,
      title: "Saved source", body: ["executable_tool": .object(spec)], parents: []), run: "author-tool")
    let oracle = AgentMcpJSONValue.object(["a/b": .array([.string("held-back"), .int(1)])])
    let plan: AgentMcpJSONObject = [
      "environment": .string("python"), "purpose": .string("Validate"), "coverage_gaps": .string("Limited"),
      "oracle_basis": .string("External"), "executable_tool": .object(["object_id": .string(tool.objectId),
        "revision": .int(tool.revision), "sha256": .string(tool.sha256)]),
      "cases": .array([
        .object(["id": .string("target"), "purpose": .string("target"), "reason": .string("Typical"),
          "input": .object(["value": .int(1)]), "expected": oracle]),
        .object(["id": .string("regression"), "purpose": .string("regression"), "reason": .string("Zero"),
          "input": .object(["value": .int(0)]), "expected": .null])
      ])
    ]
    let reference = try publish(.init(id: "plan", objectId: nil, baseRevision: 0, kind: .toolTestPlan,
      title: "Saved plan", body: ["tool_test_plan": .object(plan)], parents: [tool]), run: "author-plan")
    var running = durableTeamSnapshot("execute-plan")
    running.members[0].dispatchCheckpoint = .dispatching
    running.members[0].dispatchAllowsSavedToolTest = true
    running.members[1].dispatchCheckpoint = .dispatching
    running.members[1].dispatchDependencyMemberIds = [running.members[0].memberId]
    running.members.append(AgentTeamMemberSnapshot(agentId: "unread-review", deliveryMode: .observe,
      sourceMessageId: "unread-review-source"))
    XCTAssertTrue(history.upsert(running))
    let reader = scope(running)
    let prepared = try history.prepareSavedToolTest(reference, timeoutMillis: 1_000, scope: reader)
    XCTAssertEqual(prepared.runtimeInput["network_enabled"], .bool(false))
    XCTAssertEqual(prepared.runtimeInput["language"], .string("python"))
    let source = prepared.runtimeInput.string("source")
    let encoded = try XCTUnwrap(source.components(separatedBy: "base64.b64decode('").last?.split(separator: "'").first)
    let supplied = try XCTUnwrap(Data(base64Encoded: String(encoded)))
    let passedToPython = try JSONDecoder().decode(AgentMcpJSONObject.self, from: supplied)
    XCTAssertEqual(Set(passedToPython.keys), ["cases", "source"])
    XCTAssertEqual(passedToPython["cases"]?.arrayValue?.first?.objectValue?["input"], .object(["value": .int(1)]))
    XCTAssertFalse(String(decoding: supplied, as: UTF8.self).contains("held-back"))

    func report(_ rows: [AgentMcpJSONValue], truncated: Bool = false) -> AgentNativeToolResult {
      let runtime: AgentMcpJSONObject = ["python": .array([.int(3), .int(11), .int(0)]),
        "implementation": .string("cpython"), "machine": .string("aarch64")]
      let stdout = AgentMcpJSONCodec.stringify(["format": .string(AgentCollaborationSavedToolTest.reportFormat),
        "runtime": .object(runtime), "environment_matches": .bool(true), "results": .array(rows)])
      let output: AgentMcpJSONObject = ["exit_code": .int(0), "stdout": .string(stdout), "output_truncated": .bool(truncated)]
      let now = AgentControlPlaneClock.nowMillis()
      return .init(status: .succeeded, output: output, message: "", receipt: .init(invocationId: "fixture",
        startedAtEpochMillis: now, finishedAtEpochMillis: now + 1, durationMillis: 1, status: .succeeded,
        inputSha256: AgentMcpJSONCodec.sha256(prepared.runtimeInput), outputSha256: AgentMcpJSONCodec.sha256(output)),
        provenance: .init(toolId: AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
          toolVersion: "1", location: .application, executorId: AgentIOSOnDeviceRuntimeNativeToolCatalog.brokerExecutorId,
          contractVersion: "1"))
    }
    let rows: [AgentMcpJSONValue] = [
      .object(["id": .string("target"), "output": oracle]),
      .object(["id": .string("regression"), "output": .null])
    ]
    XCTAssertEqual(prepared.evaluate(report(rows))["passed"], .bool(true))
    XCTAssertEqual(prepared.evaluate(report(rows, truncated: true))["passed"], .bool(false))
    XCTAssertEqual(prepared.evaluate(report([rows[0], rows[0]]))["passed"], .bool(false))
    var wrong = rows
    wrong[0] = .object(["id": .string("target"), "output": .object(["a/b": .array([.string("held-back"), .bool(true)])])])
    let mismatch = prepared.evaluate(report(wrong))
    XCTAssertEqual(mismatch["passed"], .bool(false))
    XCTAssertEqual(mismatch["problems"]?.arrayValue?.first?.objectValue?["path"], .string("/results/0/output/a~1b/1"))
    var tampered = report(rows)
    tampered.receipt.inputSha256 = "changed"
    XCTAssertEqual(prepared.evaluate(tampered)["passed"], .bool(false))
    var stale = reference
    stale.sha256 = String(repeating: "0", count: 64)
    XCTAssertThrowsError(try history.prepareSavedToolTest(stale, timeoutMillis: 1_000, scope: reader)) {
      let detail = ($0 as? AgentCollaborationTypedRecordValidation)?.problem
      XCTAssertEqual(detail?["code"], .string("record_digest_mismatch"))
      XCTAssertEqual(detail?["path"], .string("/tool_test_plan/sha256"))
    }
    XCTAssertThrowsError(try history.prepareSavedToolTest(tool, timeoutMillis: 1_000, scope: reader)) {
      XCTAssertEqual(($0 as? AgentCollaborationTypedRecordValidation)?.problem["code"], .string("record_kind_mismatch"))
    }

    let result = report(rows)
    let proof = try history.recordNativeObservation(.init(runId: reader.runId, conversationId: reader.conversationId,
      turnId: reader.turnId, memberId: reader.memberId, sourceId: reader.sourceId, input: prepared.evidenceInput,
      result: result, evaluation: prepared.evaluate(result)))
    let citation = proof.filter { ["evidence_id", "sha256", "origin"].contains($0.key) }
    let reviewer = running.members[1]
    let reviewScope = AgentCollaborationToolEvidenceScope(runId: reader.runId, conversationId: reader.conversationId,
      turnId: reader.turnId, memberId: reviewer.memberId, sourceId: reviewer.sourceMessageId)
    func readOriginal(_ owner: AgentCollaborationToolEvidenceScope, evidence: AgentMcpJSONObject, mode: String) throws {
      var offset: Int64? = 0
      while let position = offset {
        let page = try history.recallCollaborationOriginal(["mode": .string(mode),
          "evidence_id": .string(evidence.string("evidence_id")), "sha256": .string(evidence.string("sha256")),
          "offset": .int(position)], scope: owner)
        offset = page["next_offset"]?.intValue
      }
    }
    var replay = result
    replay.receipt.replayed = true
    let replayProof = try history.recordNativeObservation(.init(runId: reader.runId, conversationId: reader.conversationId,
      turnId: reader.turnId, memberId: reader.memberId, sourceId: reader.sourceId, input: prepared.evidenceInput,
      result: replay, evaluation: prepared.evaluate(replay)))
    let replayCitation = replayProof.filter { ["evidence_id", "sha256", "origin"].contains($0.key) }
    try readOriginal(reader, evidence: citation, mode: "native_evidence")
    running.members[0].status = .succeeded
    XCTAssertTrue(history.upsert(running))
    try readOriginal(reviewScope, evidence: citation, mode: "evidence")
    try readOriginal(reviewScope, evidence: replayCitation, mode: "evidence")
    running.members[1].status = .succeeded
    running.members[2].status = .succeeded
    XCTAssertTrue(history.upsert(running))
    func release(_ evidence: AgentMcpJSONObject, as owner: AgentCollaborationToolEvidenceScope)
        throws -> AgentCollaborationResearchPublication {
      let spec: AgentMcpJSONObject = ["tool_test_plan": .object(AgentCollaborationCandidateRecall.reference(reference)),
        "observation": .object(evidence), "review": .string("Reviewed the original test outputs"),
        "applies_when": .string("Integer inputs"), "avoid_when": .string("Untrusted input"),
        "limitations": .string("Only registered cases were checked"),
        "authorization_boundary": .string("Existing runtime permissions"), "unresolved": .array([])]
      let draft = AgentCollaborationResearchDraft(id: "release", objectId: nil, baseRevision: 0, kind: .toolRelease,
        title: "Reviewed saved tool", body: ["tool_release": .object(spec)], parents: [reference], observations: [evidence])
      return try history.publishResearchObjects([draft], runId: owner.runId, conversationId: owner.conversationId,
        turnId: owner.turnId, memberId: owner.memberId, sourceId: owner.sourceId)
    }
    XCTAssertThrowsError(try release(citation, as: reader), "The source author cannot independently release it")
    let unread = running.members[2]
    let unreadScope = AgentCollaborationToolEvidenceScope(runId: reader.runId, conversationId: reader.conversationId,
      turnId: reader.turnId, memberId: unread.memberId, sourceId: unread.sourceMessageId)
    XCTAssertThrowsError(try release(citation, as: unreadScope), "Coverage belongs to the exact reviewer")
    XCTAssertThrowsError(try release(replayCitation, as: reviewScope), "A replay cannot validate a release")
    var forged = citation
    forged["sha256"] = .string(String(repeating: "a", count: 64))
    XCTAssertThrowsError(try release(forged, as: reviewScope))
    let released = try XCTUnwrap(release(citation, as: reviewScope).references.first)
    var future = durableTeamSnapshot("use-reviewed-tool")
    future.taskId = "future-turn"
    future.members[0].dispatchCheckpoint = .accepted
    future.members[0].dispatchAllowsSavedToolTest = true
    XCTAssertTrue(history.upsert(future))
    let capabilities = try history.recallCollaborationOriginal(["mode": .string("capabilities"), "query": .string("check")],
      scope: scope(future))
    let entry = try XCTUnwrap(capabilities["capabilities"]?.arrayValue?.compactMap(\.objectValue)
      .first { $0.string("object_id") == released.objectId })
    XCTAssertEqual(entry["state"], .string(AgentCollaborationCapabilityPage.releaseState))
    XCTAssertEqual(entry["grants_permissions"], .bool(false))
    XCTAssertEqual(entry["excerpts"]?.objectValue?["tool_name"], .string("Check"))
    let run = try history.prepareSavedToolRun(.release, reference: released, parameters: ["value": .int(21)],
      timeoutMillis: 1_000, scope: scope(future))
    XCTAssertEqual(run.runtimeInput["network_enabled"], .bool(false))
    XCTAssertEqual(run.evidenceInput["tool_release"], .object(AgentCollaborationCandidateRecall.reference(released)))
    XCTAssertEqual(run.evidenceInput["parameters"], .object(["value": .int(21)]))
    XCTAssertThrowsError(try history.prepareSavedToolRun(.release, reference: released, parameters: ["value": .string("21")],
      timeoutMillis: 1_000, scope: scope(future)))
    XCTAssertThrowsError(try history.prepareSavedToolRun(.channel, reference: released, parameters: ["value": .int(21)],
      timeoutMillis: 1_000, scope: scope(future)))
    var noGrant = scope(future)
    noGrant.sourceId = "different-source"
    XCTAssertThrowsError(try history.prepareSavedToolRun(.release, reference: released, parameters: ["value": .int(21)],
      timeoutMillis: 1_000, scope: noGrant))
    func runReport(runtime: AgentMcpJSONObject) -> AgentNativeToolResult {
      var native = result
      native.output = ["exit_code": .int(0), "stdout": .string(AgentMcpJSONCodec.stringify([
        "format": .string(AgentCollaborationReleasedToolRun.format), "environment_matches": .bool(true),
        "runtime": .object(runtime), "output": .int(21)
      ]))]
      native.receipt.inputSha256 = AgentMcpJSONCodec.sha256(run.runtimeInput)
      native.receipt.outputSha256 = AgentMcpJSONCodec.sha256(native.output)
      return native
    }
    XCTAssertEqual(run.evaluate(runReport(runtime: run.runtime))["passed"], .bool(true))
    var changedRuntime = run.runtime
    changedRuntime["machine"] = .string("different")
    XCTAssertEqual(run.evaluate(runReport(runtime: changedRuntime))["reason"], .string("runtime_identity_changed"))
    history.removeResearchObjects(conversationId: reader.conversationId)
    XCTAssertThrowsError(try history.prepareSavedToolTest(reference, timeoutMillis: 1_000, scope: reader))
  }

  func testToolComparisonRequiresBothOriginalsAndPreservesPairedFailures() throws {
    let suite = "tool-comparison-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite")
    func open() -> AgentTeamExecutionHistoryStore {
      .init(defaults: defaults, secrets: secrets, executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    }
    let history = open()
    func scope(_ team: AgentTeamExecutionSnapshot) -> AgentCollaborationToolEvidenceScope {
      .init(runId: team.supervisorRunId, conversationId: team.conversationId, turnId: team.taskId,
        memberId: team.members[0].memberId, sourceId: team.members[0].sourceMessageId)
    }
    func publish(_ draft: AgentCollaborationResearchDraft, as owner: AgentCollaborationToolEvidenceScope)
      throws -> AgentCollaborationResearchReference {
      try XCTUnwrap(history.publishResearchObjects([draft], runId: owner.runId, conversationId: owner.conversationId,
        turnId: owner.turnId, memberId: owner.memberId, sourceId: owner.sourceId).references.first)
    }
    func register(_ draft: AgentCollaborationResearchDraft) throws -> AgentCollaborationResearchReference {
      var team = durableTeamSnapshot(draft.id)
      team.taskId = draft.id
      team.members[0].status = .succeeded
      XCTAssertTrue(history.upsert(team))
      return try publish(draft, as: scope(team))
    }
    func registerPair(_ name: String, source: String, oracle: String = "Known values") throws -> AgentCollaborationResearchReference {
      let tool: AgentMcpJSONObject = ["language": .string("python"), "name": .string(name), "purpose": .string("Check"),
        "applies_when": .string("Inputs"), "avoid_when": .string("None"), "environment": .string("python"),
        "dependencies": .string("None"), "side_effects": .string("None"), "source": .string(source),
        "input_schema": .object(["type": .string("object"), "required": .array([.string("n")]),
          "properties": .object(["n": .object(["type": .string("integer")])])])]
      let ref = try register(.init(id: name + "-tool", objectId: nil, baseRevision: 0, kind: .executableTool,
        title: name, body: ["executable_tool": .object(tool)], parents: []))
      let cases: [AgentMcpJSONValue] = ["target", "regression", "stable", "known_failure"].enumerated().map { index, id in
        .object(["id": .string(id), "purpose": .string(index == 0 ? "target" : "regression"),
          "reason": .string("Preserved check"), "input": .object(["n": .int(Int64(index))]), "expected": .int(1)])
      }
      let plan: AgentMcpJSONObject = ["environment": .string("python"), "purpose": .string("Check"),
        "coverage_gaps": .string("Finite cases"), "oracle_basis": .string(oracle), "cases": .array(cases),
        "executable_tool": .object(AgentCollaborationCandidateRecall.reference(ref))]
      return try register(.init(id: name + "-plan", objectId: nil, baseRevision: 0, kind: .toolTestPlan,
        title: name, body: ["tool_test_plan": .object(plan)], parents: [ref]))
    }
    let baseline = try registerPair("baseline", source: "def run(p): return [0, 1, 1, 0][p['n']]")
    let candidate = try registerPair("candidate", source: "def run(p): return [1, 0, 1, 0][p['n']]")
    let changed = try registerPair("changed-contract", source: "def run(p): return [1, 0, 1, 0][p['n']]",
      oracle: "A different oracle")
    var team = durableTeamSnapshot("comparison-run")
    team.members[0].dispatchCheckpoint = .dispatching
    team.members[0].dispatchAllowsSavedToolTest = true
    team.members[1].dispatchCheckpoint = .dispatching
    XCTAssertTrue(history.upsert(team))
    let owner = scope(team)
    func observe(_ ref: AgentCollaborationResearchReference, id: String, values: [Int64],
                 patch: Int64 = 0) throws -> AgentMcpJSONObject {
      let prepared = try history.prepareSavedToolTest(ref, timeoutMillis: 1_000, scope: owner)
      let rows: [AgentMcpJSONValue] = zip(["target", "regression", "stable", "known_failure"], values).map {
        .object(["id": .string($0.0), "output": .int($0.1)])
      }
      let runtime: AgentMcpJSONObject = ["python": .array([.int(3), .int(11), .int(patch)]),
        "implementation": .string("cpython"), "machine": .string("aarch64")]
      let stdout = AgentMcpJSONCodec.stringify(["format": .string(AgentCollaborationSavedToolTest.reportFormat),
        "runtime": .object(runtime), "environment_matches": .bool(true), "results": .array(rows)])
      let output: AgentMcpJSONObject = ["exit_code": .int(0), "stdout": .string(stdout)]
      let now = AgentControlPlaneClock.nowMillis()
      let result = AgentNativeToolResult(status: .succeeded, output: output, message: "", receipt: .init(invocationId: id,
        startedAtEpochMillis: now, finishedAtEpochMillis: now, durationMillis: 0, status: .succeeded,
        inputSha256: AgentMcpJSONCodec.sha256(prepared.runtimeInput), outputSha256: AgentMcpJSONCodec.sha256(output)),
        provenance: .init(toolId: AgentIOSOnDeviceRuntimeNativeToolCatalog.execute, toolVersion: "1", location: .application,
          executorId: AgentIOSOnDeviceRuntimeNativeToolCatalog.brokerExecutorId, contractVersion: "1"))
      let evidence = try history.recordNativeObservation(.init(runId: owner.runId, conversationId: owner.conversationId,
        turnId: owner.turnId, memberId: owner.memberId, sourceId: owner.sourceId, input: prepared.evidenceInput,
        result: result, evaluation: prepared.evaluate(result)))
      return evidence.filter { ["evidence_id", "sha256", "origin"].contains($0.key) }
    }
    let before = try observe(baseline, id: "before", values: [0, 1, 1, 0])
    let after = try observe(candidate, id: "after", values: [1, 0, 1, 0])
    let differentRuntime = try observe(candidate, id: "different-runtime", values: [1, 0, 1, 0], patch: 1)
    let differentContract = try observe(changed, id: "different-contract", values: [1, 0, 1, 0])
    func read(_ evidence: AgentMcpJSONObject, as reader: AgentCollaborationToolEvidenceScope) throws {
      var offset: Int64? = 0
      while let position = offset {
        let page = try history.recallCollaborationOriginal(["mode": .string("native_evidence"),
          "evidence_id": evidence["evidence_id"] ?? .null, "sha256": evidence["sha256"] ?? .null,
          "offset": .int(position)], scope: reader)
        offset = page["next_offset"]?.intValue
      }
    }
    func comparison(_ after: AgentMcpJSONObject, candidate alternate: AgentCollaborationResearchReference? = nil)
      -> AgentCollaborationResearchDraft {
      func side(_ ref: AgentCollaborationResearchReference, _ proof: AgentMcpJSONObject) -> AgentMcpJSONValue {
        .object(["tool_test_plan": .object(AgentCollaborationCandidateRecall.reference(ref)),
          "observation": .object(proof.filter { $0.key != "origin" })])
      }
      let selected = alternate ?? candidate
      return .init(id: "comparison", objectId: nil, baseRevision: 0, kind: .toolTestComparison, title: "Paired result",
        body: ["tool_test_comparison": .object(["purpose": .string("Compare methods"),
          "interpretation": .string("Tradeoff"), "limitations": .string("Four disclosed cases"),
          "baseline": side(baseline, before), "candidate": side(selected, after)])],
        parents: [baseline, selected], observations: [before, after])
    }
    var incompleteReader = owner
    incompleteReader.memberId = team.members[1].memberId
    incompleteReader.sourceId = team.members[1].sourceMessageId
    try read(before, as: incompleteReader)
    try read(before, as: owner)
    try read(after, as: owner)
    try read(differentRuntime, as: owner)
    try read(differentContract, as: owner)
    team.members[0].status = .succeeded
    team.members[1].status = .succeeded
    XCTAssertTrue(history.upsert(team))
    XCTAssertThrowsError(try publish(comparison(after), as: incompleteReader))
    XCTAssertThrowsError(try publish(comparison(differentRuntime), as: owner))
    XCTAssertThrowsError(try publish(comparison(differentContract, candidate: changed), as: owner))
    let ref = try publish(comparison(after), as: owner)
    var reader = durableTeamSnapshot("recall-comparison")
    reader.taskId = "recall-comparison"
    XCTAssertTrue(history.upsert(reader))
    var request = AgentCollaborationCandidateRecall.reference(ref)
    request["mode"] = .string("workspace")
    var offset: Int64? = 0
    var content = ""
    var lineage: AgentMcpJSONObject?
    while let position = offset {
      request["offset"] = .int(position)
      let page = try history.recallCollaborationOriginal(request, scope: scope(reader))
      content += try XCTUnwrap(page["content"]?.strictStringValue)
      lineage = page["comparison_lineage"]?.objectValue
      offset = page["next_offset"]?.intValue
    }
    let revision = try JSONDecoder().decode(AgentCollaborationResearchRevision.self, from: Data(content.utf8))
    let result = try XCTUnwrap(revision.toolTestComparison)
    XCTAssertEqual(result["counts"], .object(["improved": .int(1), "regressed": .int(1),
      "both_passed": .int(1), "both_failed": .int(1)]))
    let regression = result["cases"]?.arrayValue?[1].objectValue?["candidate"]?.objectValue
    XCTAssertEqual(regression?["expected"], .int(1))
    XCTAssertEqual(regression?["actual"], .int(0))
    XCTAssertEqual(result["source_changed"], .bool(true))
    XCTAssertEqual(result["grants_permissions"], .bool(false))
    XCTAssertEqual(lineage?["status"], .string("current_at_read"))
    let sides = try XCTUnwrap(lineage?["sides"]?.arrayValue)
    XCTAssertEqual(sides.count, 2)
    for (entry, plan) in zip(sides, [baseline, candidate]) {
      XCTAssertEqual(entry.objectValue?["tool_test_plan"], .object(AgentCollaborationCandidateRecall.reference(plan)))
      XCTAssertNotNil(entry.objectValue?["executable_tool"])
    }
    func directory(_ store: AgentTeamExecutionHistoryStore) throws -> AgentMcpJSONObject? {
      let page = try store.recallCollaborationOriginal(["mode": .string("capabilities"), "query": .string("Paired")],
        scope: scope(reader))
      return page["capabilities"]?.arrayValue?.compactMap(\.objectValue).first {
        $0.string("object_id") == ref.objectId
      }?["comparison_lineage"]?.objectValue
    }
    XCTAssertEqual(try directory(history), lineage)
    XCTAssertEqual(try open().committedResearchRevisions(scope: owner)?.first?.toolTestComparison, result)

    let database = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    let key = "object:" + baseline.objectId
    var newer = try XCTUnwrap(database.researchRecord(AgentCollaborationResearchRevision.self,
      conversationId: owner.conversationId, key: key, revision: baseline.revision))
    newer.previousHash = baseline.sha256
    newer.reference.revision += 1
    newer.reference.sha256 = String(repeating: "1", count: 64)
    try database.insertResearchRecord(newer, conversationId: owner.conversationId, key: key, revision: newer.reference.revision)
    let stale = try XCTUnwrap(directory(open()))
    XCTAssertEqual(stale["status"], .string("requires_revalidation"))
    XCTAssertEqual(stale["sides"]?.arrayValue?.first?.objectValue?["status"], .string("requires_revalidation"))
    XCTAssertEqual(stale["sides"]?.arrayValue?.last?.objectValue?["status"], .string("current_at_read"))
    XCTAssertEqual(try open().committedResearchRevisions(scope: owner)?.first?.toolTestComparison, result)
  }

  func testProbeContinuationsOnlyMatchMeasuredConditionsForSelectedAction() throws {
    typealias Probe = AgentCollaborationProbeContinuation
    let ref = AgentCollaborationResearchReference(objectId: "saved-method", revision: 1, sha256: String(repeating: "a", count: 64))
    func branch(_ id: String, _ flag: AgentMcpJSONValue) -> AgentMcpJSONObject {
      ["id": .string(id), "rationale": .string("Registered branch"), "when_events": .object(["measured": flag]),
       "method": .object(["object_id": .string(ref.objectId), "revision": .int(ref.revision), "sha256": .string(ref.sha256)]),
       "roles": .object(["worker": .string("worker-id")]), "inputs": .object(["scope": .string("fixture")]),
       "observed_inputs": .object(["value": .string("/escaped~1name")])]
    }
    func forecast(_ branches: [AgentMcpJSONObject]) -> AgentMcpJSONObject {
      ["selected_action": .string("probe"), "events": .array([.object(["id": .string("measured")])]),
       "choices": .array([
         .object(["action_id": .string("probe"), "continuations": .array(branches.map(AgentMcpJSONValue.object))]),
         .object(["action_id": .string("not-selected"), "continuations": .array([.object(branch("foreign", .bool(true)))])])
       ])]
    }
    let parsed = try XCTUnwrap(Probe(forecast([branch("first", .bool(true)), branch("parallel", .bool(true)),
      branch("fallback", .bool(false))])))
    XCTAssertEqual(parsed.decisions(occurrence: [:]).map(\.state), [.unknown, .unknown, .unknown])
    let matched = parsed.decisions(occurrence: ["measured": true]).filter { $0.state == .matched }
    XCTAssertEqual(matched.map(\.branch.id), ["first", "parallel"])
    XCTAssertEqual(parsed.decisions(occurrence: ["measured": false]).filter { $0.state == .matched }.map(\.branch.id),
      ["fallback"])
    XCTAssertNotEqual(matched[0].branch.executionID(forecast: ref), matched[1].branch.executionID(forecast: ref))
    XCTAssertNil(Probe(forecast([branch("duplicate", .bool(true)), branch("duplicate", .bool(false))])))
    XCTAssertNil(Probe(forecast([branch("probability", .int(1))])))
    var override = branch("override", .bool(true))
    override["observed_inputs"] = .object(["scope": .string("/scope")])
    XCTAssertNil(Probe(forecast([override])))
    override["observed_inputs"] = .object(["value": .string("/invalid~2escape")])
    XCTAssertNil(Probe(forecast([override])))
  }

  func testProbeOccurrenceDoesNotTreatFailedOrMissingMeasurementsAsFalse() {
    let forecast: AgentMcpJSONObject = ["events": .array([
      .object(["id": .string("same"), "pointer": .string("/same"), "expected": .int(5)]),
      .object(["id": .string("different"), "pointer": .string("/different"), "expected": .bool(true)]),
      .object(["id": .string("missing"), "pointer": .string("/missing"), "expected": .bool(true)]),
      .object(["id": .string("structured"), "pointer": .string("/structured"), "expected": .string("value")])
    ])]
    let values: AgentMcpJSONObject = ["/same": .double(5), "/different": .bool(false), "/structured": .object([:])]
    XCTAssertEqual(AgentCollaborationProbeContinuation.measuredEvents(forecast, valid: true) { values[$0] },
      ["same": true, "different": false])
    XCTAssertTrue(AgentCollaborationProbeContinuation.measuredEvents(forecast, valid: false) { values[$0] }.isEmpty)
  }

  func testProbeContinuationAdmissionPinsOriginalInputsAndReplaysWithoutNewWork() throws {
    let suite = "probe-continuation-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore(), file = root.appendingPathComponent("history.sqlite3")
    func open() -> AgentTeamExecutionHistoryStore {
      .init(defaults: defaults, secrets: secrets, executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    }
    let history = open()
    var team = durableTeamSnapshot("prospective-probe")
    team.goal = "Verify the fixture"
    team.members[0].dispatchCheckpoint = .accepted
    team.members[1].dispatchCheckpoint = .dispatching
    XCTAssertTrue(history.upsert(team))
    func scope(_ index: Int) -> AgentCollaborationToolEvidenceScope {
      let member = team.members[index]
      return .init(runId: team.supervisorRunId, conversationId: team.conversationId, turnId: team.taskId,
        memberId: member.memberId, sourceId: member.sourceMessageId)
    }
    let coordinator = scope(0), producer = scope(1)
    XCTAssertTrue(history.advanceGoalCheckpoint(.init(runId: coordinator.runId, conversationId: coordinator.conversationId,
      turnId: coordinator.turnId, revision: 1, phase: .working,
      contract: [.init(id: "check", requirement: "Check result", verification: .documentary, status: .open,
        evidence_kind: nil, evidence: [])], completedWorkIds: []), expectedRevision: 0))
    let evidence = try history.recordCloudEvidence(.init(scope: producer, round: 1,
      call: .init(callId: "measurement", name: "probe", argumentsJson: "{}"),
      output: #"{"passed":true,"report":{"values":[42]}}"#, succeeded: true, startedAtMillis: 2, finishedAtMillis: 3))
    func ref(_ n: Int) -> AgentCollaborationResearchReference {
      .init(objectId: String(format: "%064x", n), revision: 1, sha256: String(format: "%064x", n + 10))
    }
    func wire(_ ref: AgentCollaborationResearchReference) -> AgentMcpJSONValue {
      .object(["object_id": .string(ref.objectId), "revision": .int(ref.revision), "sha256": .string(ref.sha256)])
    }
    func row(_ n: Int, _ kind: AgentCollaborationResearchDraft.Kind, _ body: AgentMcpJSONObject,
             parents: [AgentCollaborationResearchReference] = [], owner: AgentCollaborationToolEvidenceScope)
      -> AgentCollaborationResearchRevision {
      .init(reference: ref(n), previousHash: nil, runId: owner.runId, turnId: owner.turnId,
        authorId: owner.memberId, sourceId: owner.sourceId, draft: .init(id: "fixture", objectId: nil,
          baseRevision: 0, kind: kind, title: "Fixture", body: [kind.rawValue: .object(body)], parents: parents))
    }
    let model = row(1, .environmentModel, [
      "goal_sha256": .string(SHA256.hash(data: Data(team.goal.utf8)).map { String(format: "%02x", $0) }.joined()),
      "criterion_id": .string("check"), "requirement": .string("Check result")], owner: coordinator)
    var methodFields = Dictionary(uniqueKeysWithValues: ["purpose", "domain", "bottleneck", "change_rationale",
      "applies_when", "avoid_when", "risks", "expected_gain", "falsifier"].map { ($0, AgentMcpJSONValue.string("Fixture")) })
    methodFields["roles"] = .array([.string("worker")])
    methodFields["inputs"] = .array([.string("data")])
    methodFields["dimensions"] = .array([.string("verification")])
    methodFields["steps"] = .array([.object(["id": .string("verify"), "role": .string("worker"),
      "stage": .string("VERIFY"), "assignment": .string("Check the supplied value")])])
    var earlier = coordinator
    earlier.turnId = "earlier-turn"
    let method = row(2, .workflowMethod, methodFields, owner: earlier)
    func branch(_ id: String, event: String, occurrence: Bool) -> AgentMcpJSONValue {
      .object(["id": .string(id), "rationale": .string("Fixture branch"),
        "when_events": .object([event: .bool(occurrence)]), "method": wire(method.reference),
        "roles": .object(["worker": .string(producer.memberId)]), "inputs": .object([:]),
        "observed_inputs": .object(["data": .string("/values/0")])])
    }
    var forecast = row(3, .actionForecast, ["selected_action": .string("probe"),
      "task_environment_model": wire(model.reference), "executor": .string(producer.memberId),
      "valid_until": .int(4), "source": .object(["tool": .string("probe")]), "report_pointer": .string("/report"),
      "events": .array([.object(["id": .string("pass"), "pointer": .string("/passed"), "expected": .bool(true)]),
        .object(["id": .string("missing"), "pointer": .string("/missing"), "expected": .bool(true)])]),
      "choices": .array([.object(["action_id": .string("probe"), "continuations": .array([
        branch("first", event: "pass", occurrence: true), branch("parallel", event: "pass", occurrence: true),
        branch("unknown", event: "missing", occurrence: false)])])])], parents: [model.reference], owner: producer)
    forecast.registeredAtMillis = 1
    forecast.probeExecutorSourceID = producer.sourceId
    var outcome = row(4, .predictionOutcome, ["forecast": wire(forecast.reference)],
      parents: [forecast.reference], owner: producer)
    outcome.probeMeasuredEvents = ["pass": true]
    outcome.frozenCloudReads = [.init(evidenceId: evidence.string("evidence_id"), sha256: evidence.string("sha256"),
      totalCharacters: 1)]
    let hash = String(repeating: "f", count: 64), milestone = "measured"
    let base = "publication:" + AgentMcpJSONCodec.sha256(["run": .string(producer.runId),
      "member": .string(producer.memberId), "source": .string(producer.sourceId)])
    let key = base + ":milestone:" + AgentMcpJSONCodec.sha256(["id": .string(milestone)])
    let token = AgentMcpJSONCodec.sha256(["publication": .string(key), "artifact_sha256": .string(hash)])
    let database = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    try database.transaction {
      for saved in [model, method, forecast, outcome] {
        try database.insertResearchRecord(saved, conversationId: coordinator.conversationId,
          key: "object:" + saved.reference.objectId, revision: saved.reference.revision)
      }
      try database.insertResearchRecord(AgentCollaborationResearchPublication(requestHash: hash,
        references: [outcome.reference], milestoneId: milestone, recordedAtMillis: 3),
        conversationId: coordinator.conversationId, key: key, revision: 0)
    }
    func admission(_ id: String, revision: Int64, token: String) -> AgentMcpJSONObject {
      ["mode": .string("append_work"), "milestone_id": .string(id), "expected_revision": .int(revision),
       "artifact": .string(AgentMcpJSONCodec.stringify(["format": .string("galaxyssi.work-expansion.v1"),
         "work": .array([.object(["probe_continuation": .object([
           "outcome": wire(outcome.reference), "milestone": .string(token)])])])]))]
    }
    XCTAssertThrowsError(try history.publishCollaborationMilestone(admission("wrong", revision: 1, token: hash), scope: coordinator))
    let input = admission("admit", revision: 1, token: token)
    let accepted = try history.publishCollaborationMilestone(input, scope: coordinator)
    XCTAssertEqual(accepted["admitted_work_count"], .int(2))
    let reopened = open()
    XCTAssertEqual(try reopened.publishCollaborationMilestone(input, scope: coordinator)["replayed"], .bool(true))
    XCTAssertEqual(try reopened.publishCollaborationMilestone(admission("again", revision: 2, token: token),
      scope: coordinator)["admitted_work_count"], .int(0))
    let graph = try XCTUnwrap(reopened.goalCheckpoint(runId: coordinator.runId,
      conversationId: coordinator.conversationId, turnId: coordinator.turnId)?.liveGraph)
    XCTAssertEqual(graph.work.count, 2)
    XCTAssertEqual(Set(graph.work.compactMap { $0.probeBinding?.string("branch_id") }), Set(["first", "parallel"]))
    let work = try XCTUnwrap(graph.work.first)
    let claim = try reopened.claimGoalWork(work, scope: coordinator)
    XCTAssertEqual(claim.dependencies.first?["inputs"]?.objectValue?["data"], .int(42))
    XCTAssertEqual(claim.run.receipt(now: claim.run.startedAt)["probe_origin"]?.objectValue?["observation"]?.objectValue?["sha256"],
      evidence["sha256"])
    XCTAssertFalse(try open().claimGoalWork(work, scope: coordinator).claimed)
  }

  func testQualitativeForecastPreservesContradictionsAndFrozenObservationOnReopen() throws {
    typealias Prediction = AgentCollaborationQualitativePrediction
    let raw = """
    {"prediction_mode":"qualitative","work_id":"trial","executor":"review","horizon":"One run",
     "decision_rationale":"Compare","risk_tradeoff":"Low","information_value":"Distinguish",
     "revalidate_before_action":"Check inputs","selected_action":"probe","report_pointer":"",
     "events":[{"id":"ordered","meaning":"Output ordered","unit":"boolean","pointer":"/ordered","expected":true},
               {"id":"complete","meaning":"Output complete","unit":"boolean","pointer":"/complete","expected":true}],
     "choices":[
       {"action_id":"probe","reasoning":"Observe","uncertainty":"Unknown","resources":"One","risk":"Low",
        "expectations":{"ordered":"expected","complete":"expected"}},
       {"action_id":"defer","reasoning":"Wait","uncertainty":"Unknown","resources":"None","risk":"Low",
        "expectations":{"ordered":"unknown","complete":"unknown"}}],
     "hypothesis_test":{"question":"Why does it fail?","assumptions":"Same input","prediction_basis":"Fixture",
       "misspecification_check":"Both may fail","event_ids":["ordered","complete"],
       "hypotheses":[{"id":"a","claim":"A"},{"id":"b","claim":"B"}],
       "predictions":{"probe":{"a":{"ordered":"expected","complete":"expected"},
                               "b":{"ordered":"not_expected","complete":"expected"}},
                      "defer":{"a":{"ordered":"unknown","complete":"unknown"},
                               "b":{"ordered":"unknown","complete":"unknown"}}}}}
    """
    var spec = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8))
    let actions: Set<String> = ["probe", "defer"]
    let prediction = try XCTUnwrap(Prediction(spec, actions: actions))
    XCTAssertNil(AgentCollaborationForecastIntake.utilities(spec, actions: actions))
    XCTAssertNil(AgentCollaborationForecastIntake.hypothesisInformation(spec))
    let partial = prediction.feedback(withinValidity: true) { $0 == "/ordered" ? .bool(false) : nil }
    XCTAssertEqual(partial["state"], .string("incomplete_observation"))
    XCTAssertEqual(partial["hypotheses"]?.arrayValue?.first?.objectValue?["state"], .string("contradicted"))
    XCTAssertEqual(partial["hypotheses"]?.arrayValue?.last?.objectValue?["state"], .string("unresolved"))
    let contradicted = prediction.feedback(withinValidity: true) { _ in .bool(false) }
    XCTAssertEqual(contradicted["state"], .string("contradicted_hypothesis_space"))
    XCTAssertEqual(contradicted["scored_events"], .int(0))
    XCTAssertEqual(contradicted["posterior"], .null)
    XCTAssertEqual(prediction.feedback(withinValidity: false) { _ in .bool(false) }["observed_events"], .int(0))
    var mixed = spec
    mixed["utility_unit"] = .string("points")
    XCTAssertNil(Prediction(mixed, actions: actions))
    mixed = spec
    mixed["prediction_mode"] = .null
    XCTAssertNil(Prediction(mixed, actions: actions))

    let suite = "qualitative-prediction-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore(), file = root.appendingPathComponent("history.sqlite3")
    func open() -> AgentTeamExecutionHistoryStore {
      .init(defaults: defaults, secrets: secrets, executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    }
    let history = open()
    var team = durableTeamSnapshot("qualitative")
    team.members[1].dispatchCheckpoint = .dispatching
    XCTAssertTrue(history.upsert(team))
    let reader = team.members[1]
    let scope = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId, memberId: reader.memberId, sourceId: reader.sourceMessageId)
    XCTAssertTrue(history.advanceGoalCheckpoint(.init(runId: scope.runId, conversationId: scope.conversationId,
      turnId: scope.turnId, revision: 1, phase: .working,
      contract: [.init(id: "check", requirement: "Check result", verification: .documentary,
        status: .open, evidence_kind: nil, evidence: [])], completedWorkIds: []), expectedRevision: 0))
    let database = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    let goalHash = SHA256.hash(data: Data(team.goal.utf8)).map { String(format: "%02x", $0) }.joined()
    let model = AgentCollaborationResearchReference(objectId: String(repeating: "a", count: 64), revision: 1,
      sha256: String(repeating: "b", count: 64))
    let modelActions: [AgentMcpJSONValue] = ["probe", "defer"].map { id in
      .object(["id": .string(id), "mode": .string(id), "description": .string("Observe"),
        "preconditions": .string("Fixture"), "expected_transition": .string("Unknown"),
        "side_effects": .string("None"), "reversibility": .string("Read only"), "authorization": .string("Scoped")])
    }
    let environment = AgentCollaborationResearchDraft(id: "environment", objectId: nil, baseRevision: 0,
      kind: .environmentModel, title: "Fixture", body: ["task_environment_model": .object([
        "goal_sha256": .string(goalHash), "criterion_id": .string("check"), "requirement": .string("Check result"),
        "actions": .array(modelActions)])], parents: [])
    try database.insertResearchRecord(AgentCollaborationResearchRevision(reference: model, previousHash: nil,
      runId: scope.runId, turnId: scope.turnId, authorId: scope.memberId, sourceId: scope.sourceId, draft: environment),
      conversationId: scope.conversationId, key: "object:" + model.objectId, revision: model.revision)
    let now = AgentControlPlaneClock.nowMillis()
    spec["executor"] = .string(scope.memberId)
    spec["task_environment_model"] = .object(AgentCollaborationCandidateRecall.reference(model))
    spec["source"] = .object(["origin": .string("ios_cloud_tool"), "tool": .string("measure")])
    spec["valid_until"] = .int(now + 60_000)
    let forecast = AgentCollaborationResearchDraft(id: "forecast", objectId: nil, baseRevision: 0,
      kind: .actionForecast, title: "Qualitative forecast", body: ["action_forecast": .object(spec)], parents: [model])
    let ref = try XCTUnwrap(history.publishResearchObjects([forecast], runId: scope.runId,
      conversationId: scope.conversationId, turnId: scope.turnId, memberId: scope.memberId, sourceId: scope.sourceId,
      milestone: ("forecast", String(repeating: "c", count: 64))).references.first)
    let observed = AgentCollaborationCloudToolEvidence(scope: scope, round: 1,
      call: .init(callId: "observation", name: "measure", argumentsJson: "{}"), output: #"{"ordered":false}"#,
      succeeded: true, startedAtMillis: now + 10_000, finishedAtMillis: now + 10_001)
    let evidence = try history.recordCloudEvidence(observed)
    let citation = evidence.filter { ["evidence_id", "sha256"].contains($0.key) }
    var lookup = citation
    lookup["mode"] = .string("evidence")
    _ = try history.recallCollaborationOriginal(lookup, scope: scope)
    team.members[1].status = .succeeded
    team.updatedAtMillis += 1
    XCTAssertTrue(history.upsert(team))
    let outcome = AgentCollaborationResearchDraft(id: "outcome", objectId: nil, baseRevision: 0,
      kind: .predictionOutcome, title: "Partial measurement",
      body: ["prediction_outcome": .object(["forecast": .object(AgentCollaborationCandidateRecall.reference(ref))])],
      parents: [ref], observations: [citation])
    _ = try history.publishResearchObjects([outcome], runId: scope.runId, conversationId: scope.conversationId,
      turnId: scope.turnId, memberId: scope.memberId, sourceId: scope.sourceId)
    let saved = try XCTUnwrap(open().committedResearchRevisions(scope: scope)?.first)
    XCTAssertEqual(saved.hypothesisFeedback, partial)
    XCTAssertEqual(saved.frozenCloudReads?.first?.evidenceId, citation.string("evidence_id"))
  }

  func testForecastRecomputesUtilityWithoutChoosingAnAction() throws {
    let raw = """
    {"work_id":"test","executor":"member","horizon":"One test","decision_rationale":"Avoid side effects",
     "risk_tradeoff":"Delay","information_value":"Compare","revalidate_before_action":"Check input","utility_unit":"points",
     "selected_action":"defer","events":[{"id":"pass","meaning":"Test passes","unit":"boolean","pointer":"/pass",
       "expected":true,"utility_if_true":10,"utility_if_false":-2}],
     "choices":[{"action_id":"probe","reasoning":"Measure","uncertainty":"Known input","resources":"One trial","risk":"Low",
       "probabilities":{"pass":0.75}},{"action_id":"defer","reasoning":"Wait","uncertainty":"No measure",
       "resources":"None","risk":"Delay","probabilities":{"pass":0}}]}
    """
    let forecast = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8))
    XCTAssertEqual(AgentCollaborationForecastIntake.utilities(forecast, actions: ["probe", "defer"]),
      ["probe": 7, "defer": -2])
    XCTAssertNil(AgentCollaborationForecastIntake.utilities(forecast, actions: ["probe", "defer", "act"]))
    let invalid = raw.replacingOccurrences(of: "0.75", with: "1.25")
    XCTAssertNil(AgentCollaborationForecastIntake.utilities(
      try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(invalid.utf8)), actions: ["probe", "defer"]))
  }

  func testCloudObservationDistinguishesExplicitFailureFromEmptyErrors() {
    for output in ["{}", "{\"error\":false}", "{\"error\":null}", "{\"error\":{}}",
                   "{\"error\":[]}", "{\"error\":0}", "{\"error\":\"  \"}",
                   "{\"success\":\"false\"}", "unstructured error text"] {
      XCTAssertFalse(AgentCollaborationCloudToolEvidence.reportsFailure(output), output)
    }
    for output in ["{\"success\":false}", "{\"ok\":false}", "{\"isError\":true}",
                   "{\"error\":{\"code\":\"offline\"}}", "{\"status\":\"timed_out\"}"] {
      XCTAssertTrue(AgentCollaborationCloudToolEvidence.reportsFailure(output), output)
    }
  }

  func testInnovationOpportunityCannotReplaceGoalCriterionOrDriverEvidence() throws {
    let raw = """
    {"format":"galaxyssi.research-artifact.v1","workspace":[
      {"id":"opportunity","kind":"innovation_opportunity","title":"Opportunity","base_revision":0,
       "parents":[{"object_id":"gap","revision":1,"sha256":"exact"}],
       "body":{"innovation_opportunity":{"goal_sha256":"pinned","criterion_id":"accuracy","requirement":"Preserve accuracy",
        "question":"Reduce noise?","unmet_need":"Unstable responses","expected_benefit":"Repeatability","constraints":"Same budget",
        "null_hypothesis":"No change","discriminating_test":"Compare trials","uncertainty":"Sample size",
        "alternative_routes":["Keep baseline"],"drivers":[{"id":"one","kind":"knowledge_gap","why":"Observed gap",
          "what_would_change":"Better checks","sources":[{"object_id":"gap","revision":1,"sha256":"exact"}]}]}}}
    ]}
    """
    let draft = try XCTUnwrap(AgentCollaborationResearchEnvelope.publication(in: raw)?.first)
    let criterion = AgentCollaborationGoalAssessmentPolicy.Criterion(id: "accuracy", requirement: "Preserve accuracy",
      verification: .documentary, status: .open, evidence_kind: nil, evidence: [])
    XCTAssertTrue(AgentCollaborationOpportunityIntake.validates(draft, goalHash: "pinned", contract: [criterion]) { _ in "capability_gap" })
    XCTAssertFalse(AgentCollaborationOpportunityIntake.validates(draft, goalHash: "changed", contract: [criterion]) { _ in "capability_gap" })
    XCTAssertFalse(AgentCollaborationOpportunityIntake.validates(draft, goalHash: "pinned", contract: []) { _ in "capability_gap" })
    XCTAssertFalse(AgentCollaborationOpportunityIntake.validates(draft, goalHash: "pinned", contract: [criterion]) { _ in "proposal" })
  }

  func testTransferStudyRequiresCurrentFailureAndDistinctTargetDomain() throws {
    let raw = """
    {"format":"galaxyssi.research-artifact.v1","workspace":[
      {"id":"study","kind":"transfer_study","title":"Study","base_revision":0,
       "parents":[{"object_id":"failure","revision":1,"sha256":"exact"}],
       "body":{"transfer_study":{
         "source":{"object_id":"failure","revision":1,"sha256":"exact"},
         "source_domain":"Parsing","target_domain":"Extraction","mode":"cross_domain","target_task":"Extract fields",
         "abstract_strategy":"Validate input","proposed_method":"Check schema","rationale":"Avoid ambiguity",
         "risks":"Reject valid input","falsifier":"No gain","limitations":"Structured only",
         "alternatives":["Manual review"],"calibration_data":[],
         "mappings":[{"source_element":"Parser","target_element":"Extractor","invariant":"Structure",
           "adaptation":"New schema","breaks_when":"Free text"}]
       }}}
    ]}
    """
    let draft = try XCTUnwrap(AgentCollaborationResearchEnvelope.publication(in: raw)?.first)
    XCTAssertTrue(AgentCollaborationTransferIntake.validates(draft) { _ in "failure_experience" })
    XCTAssertFalse(AgentCollaborationTransferIntake.validates(draft) { _ in nil })
    XCTAssertFalse(AgentCollaborationTransferIntake.validates(draft) { _ in "proposal" })
    let sameDomain = raw.replacingOccurrences(of: "\"Extraction\"", with: "\"Parsing\"")
    let invalid = try XCTUnwrap(AgentCollaborationResearchEnvelope.publication(in: sameDomain)?.first)
    XCTAssertFalse(AgentCollaborationTransferIntake.validates(invalid) { _ in "failure_experience" })
  }

  func testLearningAgendaRetainsDeferredOptionAndRejectsInventedCost() throws {
    let raw = """
    {"format":"galaxyssi.research-artifact.v1","workspace":[
      {"id":"agenda","base_revision":0,"kind":"learning_agenda","title":"Compare","parents":[
        {"object_id":"gap","revision":1,"sha256":"original"}
      ],"body":{"learning_agenda":{"goal_alignment":"Goal","resource_reasoning":"Bounded",
        "selection_reason":"Defer until data arrives","reconsider_when":"Data available","options":[
          {"id":"option","gap":{"object_id":"gap","revision":1,"sha256":"original"},"gap_option":"repeat",
           "priority":1,"decision":"defer","member":"member","stage":"VERIFY","assignment":"Repeat",
           "current_goal_value":"Direct","future_transfer_value":"Unknown","information_gain":"Measure variance",
           "uncertainty":"Sample size","tradeoff":"Time","verification":"Compare","reconsider_when":"Data available",
           "resource_estimates":[{"unit":"cost_micros","status":"unknown","basis":"Not measured"}]}
        ]}}}
    ]}
    """
    var draft = try XCTUnwrap(AgentCollaborationResearchEnvelope.publication(in: raw)?.first)
    func valid(_ draft: AgentCollaborationResearchDraft) -> Bool {
      AgentCollaborationLearningAgendaIntake.validates(draft, members: ["member"]) { reference in
        reference.objectId == "gap" && reference.revision == 1 && reference.sha256 == "original" ? ["repeat"] : nil
      }
    }
    XCTAssertTrue(valid(draft))
    var revision = draft
    revision.baseRevision = 1
    XCTAssertFalse(valid(revision))
    revision = draft
    revision.parents = []
    XCTAssertFalse(valid(revision))
    let priced = raw.replacingOccurrences(of: "\"status\":\"unknown\"", with: "\"status\":\"unknown\",\"value\":0")
    draft = try XCTUnwrap(AgentCollaborationResearchEnvelope.publication(in: priced)?.first)
    XCTAssertFalse(valid(draft))
  }

  func testLearningAdmissionRequiresExactSelectedAssignment() throws {
    let raw = """
    {"format":"galaxyssi.work-expansion.v1","work":[
      {"id":"learn","member":"member","stage":"VERIFY","assignment":"Repeat the check","depends_on":[],
       "learning":{"agenda":{"object_id":"agenda","revision":1,"sha256":"exact"},"option_id":"repeat"}}
    ]}
    """
    let graph = try XCTUnwrap(AgentCollaborationLiveGraph().appending(raw, authorizedMembers: ["member"],
      historicalAuthors: [:], settled: [:]))
    let item = try XCTUnwrap(graph.work.first)
    var option: AgentMcpJSONObject = ["decision": .string("select"), "member": .string("member"),
      "stage": .string("VERIFY"), "assignment": .string("Repeat the check")]
    XCTAssertTrue(AgentCollaborationLearningAgendaIntake.matchesSelection(option, work: item))
    option["decision"] = .string("defer")
    XCTAssertFalse(AgentCollaborationLearningAgendaIntake.matchesSelection(option, work: item))
    option["decision"] = .string("select")
    option["assignment"] = .string("Repeat a different check")
    XCTAssertFalse(AgentCollaborationLearningAgendaIntake.matchesSelection(option, work: item))
  }

  @MainActor
  func testGoalWorkAdmissionKeepsPlannerOrderWithReversedTasksAndCancelledCandidate() async {
    let gate = AgentGoalWorkAdmissionOrder()
    let laterTasksArrived = expectation(description: "Later candidates ask for admission first")
    laterTasksArrived.expectedFulfillmentCount = 2
    let last = Task { @MainActor in
      laterTasksArrived.fulfill()
      guard await gate.wait(for: 2) else { XCTFail("Final reservation was unexpectedly cancelled"); return }
      gate.finish(2, claimedID: "a-last")
    }
    let middle = Task { @MainActor in
      laterTasksArrived.fulfill()
      if await gate.wait(for: 1) { gate.finish(1, claimedID: Task.isCancelled ? nil : "m-cancelled") }
    }
    middle.cancel()
    await fulfillment(of: [laterTasksArrived], timeout: 3)
    XCTAssertTrue(gate.claimedIDs.isEmpty)
    let first = await gate.wait(for: 0)
    XCTAssertTrue(first)
    gate.finish(0, claimedID: "z-first")
    await last.value
    await middle.value
    XCTAssertEqual(gate.claimedIDs, ["z-first", "a-last"])
  }

  @MainActor
  func testSharedPlanningLaneRemainsIndependentOfWorkersAndRevalidatesQueuedGoals() async throws {
    let workers = AgentGlobalRunSlotLedger()
    XCTAssertTrue(workers.acquire(ownerId: "worker", runtimeKey: "same-provider", maxParallelRuns: 1, nowMillis: 1))
    XCTAssertFalse(workers.acquire(ownerId: "queued-worker", runtimeKey: "same-provider", maxParallelRuns: 1, nowMillis: 1))
    let lane = AgentCollaborationCoordinationLane()
    func scope(_ run: String) -> AgentCollaborationToolEvidenceScope {
      .init(runId: run, conversationId: "conversation", turnId: run, memberId: "planner", sourceId: "source")
    }
    let first = try XCTUnwrap(lane.acquireIfAvailable(owner: scope("first"), resourceID: "same-provider"))
    XCTAssertNil(lane.acquireIfAvailable(owner: scope("different-provider"), resourceID: "other"))
    let queued = expectation(description: "Coordinator queued")
    var valid = true
    let stale = Task { @MainActor in
      do {
        try await lane.withLease(owner: scope("stale"), resourceID: "same-provider", validate: {
          if !valid { throw CancellationError() }
          queued.fulfill()
        }, operation: { XCTFail("A stale coordinator must not start") })
      } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
    await fulfillment(of: [queued], timeout: 3)
    valid = false
    lane.release(first)
    await stale.value
    XCTAssertTrue(lane.available)
    XCTAssertEqual(workers.activeCount(runtimeKey: "same-provider"), 1)
    XCTAssertEqual(AgentCollaborationAdmissionCapacity.wire["maximum_single_run"], .int(4))
  }

  @MainActor
  func testCancellingQueuedCoordinatorDoesNotConsumeOrReleaseAnotherLease() async throws {
    let lane = AgentCollaborationCoordinationLane()
    func scope(_ id: String) -> AgentCollaborationToolEvidenceScope {
      .init(runId: id, conversationId: id, turnId: id, memberId: "planner", sourceId: id)
    }
    let first = try XCTUnwrap(lane.acquireIfAvailable(owner: scope("first"), resourceID: "one"))
    let queued = expectation(description: "Coordinator waiting")
    let cancelled = Task { @MainActor in
      do {
        try await lane.withLease(owner: scope("cancelled"), resourceID: "two", validate: {
          queued.fulfill()
        }, operation: { XCTFail("Cancelled coordinator must not start") })
      } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
    await fulfillment(of: [queued], timeout: 3)
    cancelled.cancel()
    await cancelled.value
    XCTAssertEqual(lane.queuedCount, 0)
    XCTAssertFalse(lane.available)
    lane.release(first)
    let next = try XCTUnwrap(lane.acquireIfAvailable(owner: scope("next"), resourceID: "two"))
    lane.release(first)
    XCTAssertFalse(lane.available)
    lane.release(next)
    XCTAssertTrue(lane.available)
  }

  func testResearchSubagentsAdmitReadyWorkInOrderWithoutWaitingForUnrelatedWorker() async throws {
    let fixture = OrderedSubagentAdmissionFixture()
    let runtime = AgentSubagentRuntime(limits: .init(maxConcurrency: 2), eventHook: fixture)
    defer { runtime.close() }
    let reviewStarted = expectation(description: "Dependent review does not wait for unrelated work")
    let plan = AgentSubagentPlan(supervisorId: "research", children: [
      .init(childId: "z-review", dependencies: ["m-producer"]),
      .init(childId: "m-producer"),
      .init(childId: "y-unrelated"),
      .init(childId: "a-last")
    ], preserveAdmissionOrder: true)
    let run = try runtime.start(plan: plan, worker: ClosureAgentSubagentWorker { context in
      if context.childId == "y-unrelated" { await fixture.waitForRelease() }
      if context.childId == "z-review" { reviewStarted.fulfill() }
      return .init(content: context.childId)
    })
    await fulfillment(of: [reviewStarted], timeout: 3)
    await fixture.release()
    let result = try await run.wait()
    let admitted = await fixture.admitted
    XCTAssertEqual(admitted, ["m-producer", "y-unrelated", "z-review", "a-last"])
    XCTAssertEqual(result.status, .succeeded)
  }

  func testResearchSubagentsSkipFailedPrerequisiteAndAdmitIndependentWork() async throws {
    let fixture = OrderedSubagentAdmissionFixture()
    let runtime = AgentSubagentRuntime(limits: .init(maxConcurrency: 1), eventHook: fixture)
    defer { runtime.close() }
    let plan = AgentSubagentPlan(supervisorId: "research", children: [
      .init(childId: "z-review", dependencies: ["m-producer"]),
      .init(childId: "m-producer"),
      .init(childId: "a-independent")
    ], preserveAdmissionOrder: true)
    let result = try await runtime.execute(plan: plan, worker: ClosureAgentSubagentWorker { context in
      if context.childId == "m-producer" { throw AgentSubagentRuntimeError.invalid("Synthetic failure") }
      return .init(content: context.childId)
    })
    let admitted = await fixture.admitted
    XCTAssertEqual(admitted, ["m-producer", "a-independent"])
    XCTAssertEqual(result["z-review"]?.status, .skipped)
  }

  func testLearningPrioritiesOnlyReorderReadySlotsInSameAgendaAfterReopen() throws {
    let raw = """
    {"format":"galaxyssi.work-expansion.v1","work":[
      {"id":"later","member":"member","assignment":"Later","depends_on":[],
       "learning":{"agenda":{"object_id":"agenda","revision":1,"sha256":"exact"},"option_id":"later"}},
      {"id":"ordinary","member":"member","assignment":"Ordinary","depends_on":[]},
      {"id":"first","member":"member","assignment":"First","depends_on":[],
       "learning":{"agenda":{"object_id":"agenda","revision":1,"sha256":"exact"},"option_id":"first"}},
      {"id":"blocked","member":"member","assignment":"Blocked","depends_on":["ordinary"],
       "learning":{"agenda":{"object_id":"agenda","revision":1,"sha256":"exact"},"option_id":"blocked"}}
    ]}
    """
    let graph = try XCTUnwrap(AgentCollaborationLiveGraph().appending(raw, authorizedMembers: ["member"],
      historicalAuthors: [:], settled: [:])).pinningLearningPriorities(["later": 3, "first": 2, "blocked": 1])
    let reopened = try JSONDecoder().decode(AgentCollaborationLiveGraph.self, from: JSONEncoder().encode(graph))
    XCTAssertEqual(reopened.ready(settled: [:], active: []).map(\.id), ["first", "ordinary", "later"])
    XCTAssertEqual(reopened.ready(settled: [:], active: ["first"]).map(\.id), ["later", "ordinary"])
    XCTAssertEqual(reopened.ready(settled: ["ordinary": .succeeded], active: []).map(\.id), ["blocked", "first", "later"])
  }

  func testResearchObjectPublicationRejectsStaleBatchAndReplaysExactReceipt() throws {
    let suite = "research-publication-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    var first = durableTeamSnapshot("run-1")
    first.members[0].status = .succeeded
    let member = first.members[0]
    XCTAssertTrue(history.upsert(first))
    let draft = AgentCollaborationResearchDraft(id: "notes", objectId: nil, baseRevision: 0,
      kind: .evidence, title: "Notes", body: ["text": .string("Initial evidence")], parents: [])
    func publish(_ drafts: [AgentCollaborationResearchDraft], team: AgentTeamExecutionSnapshot,
                 store: AgentTeamExecutionHistoryStore) throws -> AgentCollaborationResearchPublication {
      try store.publishResearchObjects(drafts, runId: team.supervisorRunId,
        conversationId: team.conversationId, turnId: team.taskId, memberId: team.members[0].memberId,
        sourceId: team.members[0].sourceMessageId)
    }
    let original = try publish([draft], team: first, store: history)
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    XCTAssertEqual(try publish([draft], team: first, store: reopened).references, original.references)
    var changed = draft
    changed.title = "Changed replay"
    XCTAssertThrowsError(try publish([changed], team: first, store: reopened))
    var second = first
    second.supervisorRunId = "run-2"
    second.taskId = "turn-2"
    second.members[0].sourceMessageId = "new-source"
    XCTAssertTrue(reopened.upsert(second))
    changed.objectId = original.references[0].objectId
    changed.parents = original.references
    var new = draft
    new.id = "other"
    XCTAssertThrowsError(try publish([new, changed], team: second, store: reopened))
    changed.baseRevision = 1
    let updated = try publish([new, changed], team: second, store: reopened)
    XCTAssertEqual(updated.references.map(\.revision), [1, 2])
    XCTAssertNotEqual(updated.references.last?.sha256, original.references.first?.sha256)
    let scope = AgentCollaborationToolEvidenceScope(runId: first.supervisorRunId,
      conversationId: first.conversationId, turnId: first.taskId, memberId: member.memberId,
      sourceId: member.sourceMessageId)
    let recovered = try XCTUnwrap(reopened.committedResearchRevisions(scope: scope))
    XCTAssertEqual(recovered.map(\.reference), original.references)
    XCTAssertEqual(recovered.first?.draft.title, draft.title)
    var wrongScope = scope
    wrongScope.sourceId = second.members[0].sourceMessageId
    XCTAssertThrowsError(try reopened.committedResearchRevisions(scope: wrongScope))
    reopened.removeResearchObjects(conversationId: first.conversationId)
    XCTAssertNil(try reopened.committedResearchRevisions(scope: scope))
  }

  func testRetainedProcedurePinsOriginalMethodAndRejectsChangedInputsOrLineage() throws {
    let suite = "procedure-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    func open() -> AgentTeamExecutionHistoryStore {
      .init(defaults: defaults, secrets: secrets, executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    }
    let history = open()
    var team = durableTeamSnapshot("procedure-run")
    team.goal = "Review the fixture using retained evidence"
    team.members[0].dispatchCheckpoint = .accepted
    let owner = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId, memberId: team.primaryMemberId, sourceId: team.members[0].sourceMessageId)
    XCTAssertTrue(history.upsert(team))
    let checkpoint = AgentCollaborationGoalCheckpoint(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId, revision: 1, phase: .working,
      contract: [.init(id: "result", requirement: "Observe result", verification: .physical,
        status: .open, evidence_kind: nil, evidence: [])], completedWorkIds: [])
    XCTAssertTrue(history.advanceGoalCheckpoint(checkpoint, expectedRevision: 0))
    let database = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    func ref(_ id: String, _ revision: Int64 = 1) -> AgentCollaborationResearchReference {
      .init(objectId: id, revision: revision, sha256: id + "-\(revision)")
    }
    func wire(_ id: String) -> AgentMcpJSONValue { .object(AgentCollaborationProcedure.fields(ref(id))) }
    func row(_ ref: AgentCollaborationResearchReference, _ kind: AgentCollaborationResearchDraft.Kind,
             _ body: AgentMcpJSONObject = [:]) -> AgentCollaborationResearchRevision {
      .init(reference: ref, previousHash: nil, runId: "older", turnId: "older-turn", authorId: "reviewer", sourceId: "source",
        draft: .init(id: ref.objectId, objectId: nil, baseRevision: 0, kind: kind, title: ref.objectId, body: body, parents: []))
    }
    let read = AgentCollaborationFrozenCloudRead(evidenceId: "evidence", sha256: "hash", totalCharacters: 10)
    var lesson = row(ref("lesson"), .capabilityLesson, ["capability_lesson": .object([
      "decision": .string("retain"), "result": wire("result"), "rollback": wire("baseline"),
      "procedure": .string("Original reviewed procedure"), "applies_when": .string("Same data"),
      "avoid_when": .string("Unknown source"), "transfer_test": .string("Check exact results")
    ])])
    lesson.frozenCloudReads = [read]
    var result = row(ref("result"), .experimentResult, ["experiment_result": .object(["plan": wire("plan")])])
    result.frozenCloudReads = [read]
    result.measuredCases = [.init(id: "target", purpose: "target", state: "passed"),
      .init(id: "regression", purpose: "regression", state: "passed")]
    let plan = row(ref("plan"), .experimentPlan, ["experiment_plan": .object([
      "innovation": wire("idea"), "baseline": wire("baseline")
    ])])
    let idea = row(ref("idea"), .innovation, ["innovation": .object(["domain": .string("Fixtures")])])
    let baseline = row(ref("baseline"), .artifact)
    let lineage = [lesson, result, plan, idea, baseline]
    func exact(_ ref: AgentCollaborationResearchReference) -> AgentCollaborationResearchRevision? {
      lineage.first { $0.reference == ref }
    }
    let spec: AgentMcpJSONObject = ["name": .string("Review"), "keywords": .array([.string("fixture")]),
      "limitations": .string("Fixture only"), "lesson": wire("lesson"),
      "inputs": .array([.object(["name": .string("dataset"), "description": .string("Input"), "required": .bool(true)])])]
    var skill = row(ref("skill"), .procedureSkill, ["procedure_skill": .object(spec)])
    skill.draft.parents = [ref("lesson")]
    skill.retainedProcedure = try XCTUnwrap(AgentCollaborationProcedure.freeze(skill.draft, current: exact))
    XCTAssertEqual(skill.retainedProcedure?.method, "Original reviewed procedure")
    var overridden = skill.draft
    overridden.body["procedure_skill"] = .object(spec.merging(["procedure": .string("Override")]) { _, new in new })
    XCTAssertNil(AgentCollaborationProcedure.freeze(overridden, current: exact))
    func save(_ row: AgentCollaborationResearchRevision) throws {
      try database.insertResearchRecord(row, conversationId: team.conversationId, key: "object:" + row.reference.objectId,
        revision: row.reference.revision)
    }
    for row in lineage + [skill] { try save(row) }
    func expansion(_ id: String, input: String) -> String {
      """
      {"format":"galaxyssi.work-expansion.v1","work":[
       {"id":"\(id)","member":"\(team.primaryMemberId)","assignment":"Review this fixture","depends_on":[],"stage":"VERIFY",
        "procedure_use":{"procedure":{"object_id":"skill","revision":1,"sha256":"skill-1"},
          "inputs":\(input),"applicability":{"why":"Same fixture","conditions_checked":["Input known"],
           "remaining_uncertainty":"Fixture only"},"failures":[]}}]}
      """
    }
    func append(_ id: String, input: String, revision: Int64, store: AgentTeamExecutionHistoryStore) -> Bool {
      store.appendCollaborationGraph(expansion(id, input: input), runId: checkpoint.runId, conversationId: checkpoint.conversationId,
        turnId: checkpoint.turnId, expectedRevision: revision, authorizedMembers: [team.primaryMemberId],
        historicalAuthors: [:], settled: [:])
    }
    XCTAssertFalse(append("invalid", input: #"{"dataset":null}"#, revision: 1, store: history))
    XCTAssertFalse(append("unknown", input: #"{"dataset":1,"other":2}"#, revision: 1, store: history))
    XCTAssertTrue(append("first", input: #"{"dataset":1}"#, revision: 1, store: history))
    func admission(_ input: String) -> AgentMcpJSONObject {
      ["mode": .string(AgentCollaborationGoalAssessmentPolicy.appendWorkMode), "milestone_id": .string("live"),
       "expected_revision": .int(2), "artifact": .string(expansion("live", input: input))]
    }
    XCTAssertThrowsError(try history.publishCollaborationMilestone(admission(#"{"dataset":null}"#), scope: owner))
    let request = admission(#"{"dataset":2}"#)
    XCTAssertEqual(try history.publishCollaborationMilestone(request, scope: owner)["revision"], .int(3))
    try save(row(ref("idea", 2), .innovation))
    let reopened = open()
    XCTAssertFalse(append("first", input: #"{"dataset":2}"#, revision: 3, store: reopened))
    XCTAssertFalse(append("stale", input: #"{"dataset":2}"#, revision: 3, store: reopened))
    XCTAssertEqual(try reopened.publishCollaborationMilestone(request, scope: owner)["replayed"], .bool(true))
    let bindings = try XCTUnwrap(reopened.goalCheckpoint(runId: checkpoint.runId,
      conversationId: checkpoint.conversationId, turnId: checkpoint.turnId)?.liveGraph?.procedureBindings)
    XCTAssertEqual(bindings["live"]?["inputs"], .object(["dataset": .int(2)]))
    let saved = try XCTUnwrap(bindings["first"])
    XCTAssertEqual(saved["method"], .string("Original reviewed procedure"))
    XCTAssertEqual(saved["inputs"], .object(["dataset": .int(1)]))
    XCTAssertEqual(saved["grants_permissions"], .bool(false))
  }

  func testGoalCheckpointCompareAndSetRetainsPriorRevisionAfterReopen() throws {
    let suite = "goal-checkpoint-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    var team = durableTeamSnapshot("goal-run")
    team.goal = String(repeating: "a", count: 8_191) + "\u{7814}\u{7A76}"
    let activeIndex = try XCTUnwrap(team.members.firstIndex { !$0.status.isTerminal })
    team.members[activeIndex].dispatchCheckpoint = .notStarted
    XCTAssertTrue(history.upsert(team))
    let first = AgentCollaborationGoalCheckpoint(runId: team.supervisorRunId,
      conversationId: team.conversationId, turnId: team.taskId, revision: 1, phase: .working,
      contract: [.init(id: "result", requirement: "Observe the result", verification: .physical,
        status: .open, evidence_kind: nil, evidence: [])], completedWorkIds: ["explore"])
    XCTAssertTrue(history.advanceGoalCheckpoint(first, expectedRevision: 0))
    var next = first
    next.revision = 2
    XCTAssertFalse(history.advanceGoalCheckpoint(next, expectedRevision: 1))
    next.completedWorkIds = ["verify"]
    XCTAssertTrue(history.advanceGoalCheckpoint(next, expectedRevision: 1))
    XCTAssertFalse(history.advanceGoalCheckpoint(next, expectedRevision: 1))
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    XCTAssertEqual(reopened.goalCheckpoint(runId: first.runId, conversationId: first.conversationId,
      turnId: first.turnId), next)
    XCTAssertEqual(reopened.goalCheckpoint(runId: first.runId, conversationId: first.conversationId,
      turnId: first.turnId, revision: 1), first)
    let member = try XCTUnwrap(team.members.first { !$0.status.isTerminal })
    var scope = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId,
      conversationId: team.conversationId, turnId: team.taskId, memberId: member.memberId,
      sourceId: member.sourceMessageId)
    let page = try reopened.readPinnedCollaborationGoal(scope: scope, section: "goal")
    let promptOriginals = try reopened.collaborationPromptOriginals(scope: scope)
    XCTAssertEqual(promptOriginals.map(\.name), [AgentCollaborationPromptBudget.goal,
      AgentCollaborationPromptBudget.criteria, AgentCollaborationPromptBudget.source])
    XCTAssertEqual(promptOriginals.first?.body, team.goal)
    XCTAssertEqual(promptOriginals.first?.reference?.string("sha256"), page.string("sha256"))
    let tail = try reopened.readPinnedCollaborationGoal(scope: scope, section: "goal",
      offset: Int(page.int64("next_offset")), expectedHash: page.string("sha256"))
    let headBytes = try XCTUnwrap(Data(base64Encoded: page.string("data_b64")))
    let tailBytes = try XCTUnwrap(Data(base64Encoded: tail.string("data_b64")))
    XCTAssertEqual(headBytes + tailBytes, Data(team.goal.utf8))
    XCTAssertThrowsError(try reopened.readPinnedCollaborationGoal(scope: scope, section: "goal",
      offset: 8_192, expectedHash: "wrong"))
    scope.sourceId = "foreign-source"
    XCTAssertThrowsError(try reopened.readPinnedCollaborationGoal(scope: scope, section: "criteria"))
    XCTAssertThrowsError(try reopened.collaborationPromptOriginals(scope: scope))
    var weakened = team
    weakened.goal = "A different goal"
    weakened.updatedAtMillis += 1
    XCTAssertFalse(reopened.upsert(weakened))
    let expansion = """
    {"format":"galaxyssi.work-expansion.v1","work":[
      {"id":"review","member":"reviewer","assignment":"Review the saved result","depends_on":["verify"],"independent_review":true}
    ]}
    """
    XCTAssertFalse(reopened.appendCollaborationGraph(expansion, runId: first.runId,
      conversationId: first.conversationId, turnId: first.turnId, expectedRevision: 2,
      authorizedMembers: ["reviewer"], historicalAuthors: ["verify": "reviewer"], settled: ["verify": .succeeded]))
    XCTAssertTrue(reopened.appendCollaborationGraph(expansion, runId: first.runId,
      conversationId: first.conversationId, turnId: first.turnId, expectedRevision: 2,
      authorizedMembers: ["reviewer"], historicalAuthors: ["verify": "author"], settled: ["verify": .succeeded]))
    XCTAssertFalse(reopened.appendCollaborationGraph(expansion, runId: first.runId,
      conversationId: first.conversationId, turnId: first.turnId, expectedRevision: 2,
      authorizedMembers: ["reviewer"], historicalAuthors: ["verify": "author"], settled: ["verify": .succeeded]))
    let graph = history.goalCheckpoint(runId: first.runId, conversationId: first.conversationId,
      turnId: first.turnId)?.liveGraph
    XCTAssertEqual(graph?.ready(settled: ["verify": .succeeded], active: ["unrelated"]).map(\.id), ["review"])
    XCTAssertEqual(graph?.ready(settled: ["verify": .failed], active: []).count, 0)
    XCTAssertNil(reopened.goalCheckpoint(runId: first.runId, conversationId: "foreign", turnId: first.turnId))
    reopened.remove(supervisorRunId: first.runId)
    XCTAssertTrue(reopened.upsert(team))
    XCTAssertNil(reopened.goalCheckpoint(runId: first.runId, conversationId: first.conversationId, turnId: first.turnId))
  }

  func testCollaborationDispatchCheckpointSurvivesReopenAndRejectsDuplicateStart() throws {
    let suite = "team-checkpoint-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    var snapshot = durableTeamSnapshot("run")
    let index = try XCTUnwrap(snapshot.members.firstIndex { $0.deliveryMode == .observe })
    snapshot.members[index].dispatchCheckpoint = .notStarted
    snapshot.goal = "Preserve the original task"
    snapshot.members[index].researchStage = "EXPLORE"
    let member = snapshot.members[index]
    XCTAssertTrue(history.upsert(snapshot))
    let scope = AgentCollaborationToolEvidenceScope(runId: "run", conversationId: snapshot.conversationId,
      turnId: snapshot.taskId, memberId: member.memberId, sourceId: member.sourceMessageId)
    let goal = try history.recallCollaborationOriginal(["mode": .string("goal"), "section": .string("goal")], scope: scope)
    XCTAssertEqual(Data(base64Encoded: goal.string("data_b64")), Data(snapshot.goal.utf8))
    XCTAssertThrowsError(try history.recallCollaborationOriginal(
      ["mode": .string("goal"), "section": .string("criteria")], scope: scope))
    var changedGoal = snapshot
    changedGoal.goal = "Do something else"
    changedGoal.updatedAtMillis += 1
    XCTAssertFalse(history.upsert(changedGoal))
    XCTAssertFalse(history.advanceDispatchCheckpoint(runId: "run", conversationId: "foreign",
      turnId: snapshot.taskId, memberId: member.memberId, sourceMessageId: member.sourceMessageId,
      to: .dispatching, now: 20))
    XCTAssertTrue(history.advanceDispatchCheckpoint(runId: "run", conversationId: snapshot.conversationId,
      turnId: snapshot.taskId, memberId: member.memberId, sourceMessageId: member.sourceMessageId,
      to: .dispatching, now: 20))
    let observation: AgentMcpJSONObject = ["observed_at_unix_ms": .int(21), "admissions_reserved": .int(1)]
    var foreign = scope
    foreign.sourceId = "foreign"
    XCTAssertThrowsError(try history.recordDispatchResourceObservation(observation, scope: foreign))
    let originalContext = String(repeating: "x", count: 8_191) + "\u{1F642} end"
    try history.recordDispatchResourceObservation(observation, scope: scope,
      sections: ["context:assignment": originalContext])
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    XCTAssertEqual(reopened.snapshot(supervisorRunId: "run")?.members[index].dispatchCheckpoint, .dispatching)
    XCTAssertEqual(reopened.snapshot(supervisorRunId: "run")?.members[index].dispatchResourceObservation, observation)
    let firstPage = try reopened.readPinnedCollaborationGoal(scope: scope, section: "context:assignment")
    let next = Int(firstPage.int64("next_offset"))
    XCTAssertGreaterThan(next, 0)
    let lastPage = try reopened.readPinnedCollaborationGoal(scope: scope, section: "context:assignment",
      offset: next, expectedHash: firstPage.string("sha256"))
    let bytes = try XCTUnwrap(Data(base64Encoded: firstPage.string("data_b64"))) +
      (try XCTUnwrap(Data(base64Encoded: lastPage.string("data_b64"))))
    XCTAssertEqual(bytes, Data(originalContext.utf8))
    XCTAssertThrowsError(try reopened.readPinnedCollaborationGoal(scope: foreign, section: "context:assignment"))
    XCTAssertThrowsError(try reopened.recordDispatchResourceObservation(observation, scope: scope,
      sections: ["context:assignment": "Replaced"]))
    XCTAssertNoThrow(try reopened.recordDispatchResourceObservation(observation, scope: scope))
    XCTAssertThrowsError(try reopened.recordDispatchResourceObservation(["observed_at_unix_ms": .int(22)], scope: scope))
    XCTAssertFalse(reopened.advanceDispatchCheckpoint(runId: "run", conversationId: snapshot.conversationId,
      turnId: snapshot.taskId, memberId: member.memberId, sourceMessageId: member.sourceMessageId,
      to: .dispatching, now: 30))
    XCTAssertTrue(reopened.advanceDispatchCheckpoint(runId: "run", conversationId: snapshot.conversationId,
      turnId: snapshot.taskId, memberId: member.memberId, sourceMessageId: member.sourceMessageId,
      to: .accepted, now: 30))
    XCTAssertEqual(history.snapshot(supervisorRunId: "run")?.members[index].dispatchCheckpoint, .accepted)
    var restored = try XCTUnwrap(history.snapshot(supervisorRunId: "run"))
    XCTAssertEqual(restored.members[index].researchStage, "EXPLORE")
    XCTAssertEqual(restored.members[index].executionStartedAtMillis, 20)
    XCTAssertEqual(restored.members[index].elapsedExecutionMillis(now: 40, team: restored), 20)
    restored.members[index].status = .succeeded
    restored.members[index].updatedAtMillis = 50
    XCTAssertEqual(restored.members[index].elapsedExecutionMillis(now: 100, team: restored), 30)
  }

  func testCollaborationResultsStayInTheirConversationAfterReopen() throws {
    let suite = "team-results-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    var first = durableTeamSnapshot("first")
    first.members[0].displayName = "Original member name"
    var other = durableTeamSnapshot("other")
    other.conversationId = "other-conversation"
    XCTAssertTrue(history.upsert(first))
    XCTAssertTrue(history.upsert(other))
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    let scoped = try reopened.readCollaborationResults(conversationId: first.conversationId, limit: 20)
    XCTAssertEqual(scoped.map(\.supervisorRunId), ["first"])
    XCTAssertEqual(scoped.first?.members.first?.displayName, "Original member name")
    XCTAssertTrue(reopened.collaborationResults(conversationId: "", limit: 20).isEmpty)
    XCTAssertTrue(try reopened.readCollaborationResults(conversationId: "empty", limit: 20).isEmpty)
    let unavailable = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: root)
    XCTAssertThrowsError(try unavailable.readCollaborationResults(conversationId: first.conversationId, limit: 20))
  }

  func testObserverRecoveryPersistsFullFailureAndRejectsPreviewOnlyDuplicateProof() throws {
    let suite = "team-recovery-body-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    XCTAssertTrue(history.upsert(durableTeamSnapshot("run")))
    let body = String(repeating: "failure-detail-", count: 400)
    let rich = "{\"version\":1,\"blocks\":[]}"
    XCTAssertEqual(try history.consumeOwnedReply(source: "source-review", conversation: "conversation", turn: "turn",
      task: "source-review", contact: "review", content: body, richOutputJson: rich, terminal: true,
      success: false, now: 20, observation: AgentTeamReplyObservation(generation: 2, sequence: 3)), .observerCommitted)
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    let context = try XCTUnwrap(reopened.recoveryContext(source: "source-review", conversation: "conversation",
      turn: "turn", contact: "review"))
    XCTAssertEqual(context.member.replyContent, body)
    XCTAssertEqual(context.member.errorMessage.count, AgentTeamMemberSnapshot.maxErrorCharacters)
    XCTAssertEqual(context.member.richOutputJson, rich)
    XCTAssertEqual(context.owner.observedSequence, 3)
    XCTAssertNil(try reopened.recoveryContext(source: "source-review", conversation: "foreign", turn: "turn", contact: "review"))
    let replacement = String(body.prefix(AgentTeamMemberSnapshot.maxErrorCharacters)) + "different tail"
    XCTAssertEqual(try reopened.consumeOwnedReply(source: "source-review", conversation: "conversation", turn: "turn",
      task: "source-review", contact: "review", content: replacement, richOutputJson: rich, terminal: true,
      success: false, now: 30, observation: AgentTeamReplyObservation(generation: 2, sequence: 4)), .observerDuplicate)
    let unchanged = try XCTUnwrap(reopened.recoveryContext(source: "source-review", conversation: "conversation",
      turn: "turn", contact: "review"))
    XCTAssertEqual(unchanged.member.replyContent, body)
    XCTAssertEqual(unchanged.owner.observedSequence, 3)
  }

  func testManagedBrowserTeamRecoveryClassifiesSavedMembersWithoutRedispatchingAcceptedWork() {
    var member = AgentTeamMemberSnapshot(agentId: "local-llm", status: .pending, instanceId: "member",
      sourceMessageId: "original", dispatchCheckpoint: .notStarted)
    XCTAssertEqual(AgentManagedBrowserTeamDispatch.MemberRecovery(member), .dispatch)
    member.dispatchCheckpoint = .dispatching
    XCTAssertEqual(AgentManagedBrowserTeamDispatch.MemberRecovery(member), .awaitOriginal)
    member.dispatchCheckpoint = .accepted
    member.status = .interrupted
    XCTAssertEqual(AgentManagedBrowserTeamDispatch.MemberRecovery(member), .awaitOriginal)
    member.status = .succeeded
    member.replyContent = "Original output"
    XCTAssertEqual(AgentManagedBrowserTeamDispatch.MemberRecovery(member), .reuse("Original output"))
    member.status = .cancelled
    XCTAssertEqual(AgentManagedBrowserTeamDispatch.MemberRecovery(member), .stop)
  }

  func testManagedBrowserReceiptUpdatesOnlyOriginalSavedMemberAndIsIdempotent() throws {
    let suite = "managed-browser-receipt-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    let owner = AgentCollaborationToolEvidenceScope(runId: "run", conversationId: "conversation",
      turnId: "turn", memberId: "member", sourceId: "member-source")
    let member = AgentTeamMemberSnapshot(agentId: "local-llm", status: .running, instanceId: owner.memberId,
      sourceMessageId: owner.sourceId, dispatchCheckpoint: .accepted)
    let sibling = AgentTeamMemberSnapshot(agentId: "other", deliveryMode: .respond, status: .pending,
      instanceId: "sibling", sourceMessageId: "sibling-source", dispatchCheckpoint: .notStarted)
    let team = AgentTeamExecutionSnapshot(supervisorRunId: owner.runId, teamId: "team", conversationId: owner.conversationId,
      taskId: owner.turnId, primaryAgentId: sibling.agentId, state: .running, members: [member, sibling],
      primaryInstanceId: sibling.memberId)
    XCTAssertTrue(history.upsert(team))
    let binding = try XCTUnwrap(AgentManagedBrowserDispatchBinding(owner: owner, team: team, profileID: "profile",
      modelID: "model", hostContextDigest: "context"))
    let receipt = AgentManagedBrowserMemberReceipt(id: UUID(), state: .completed, text: "Member result")
    XCTAssertTrue(try history.commitManagedBrowserReceipt(receipt, binding: binding, now: 20))
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    XCTAssertTrue(try reopened.commitManagedBrowserReceipt(receipt, binding: binding, now: 21))
    XCTAssertFalse(try reopened.commitManagedBrowserReceipt(.init(id: UUID(), state: .completed, text: "Changed result"),
      binding: binding, now: 22))
    let final = try XCTUnwrap(reopened.snapshot(supervisorRunId: owner.runId))
    XCTAssertEqual(final.members[0].replyContent, receipt.text)
    XCTAssertEqual(final.members[0].status, .succeeded)
    XCTAssertEqual(final.members[0].updatedAtMillis, 20)
    XCTAssertEqual(final.members[1], sibling)
  }

  func testTeamRecoveryCursorCoversPendingTeamsExactlyOnce() throws {
    let suite = "team-recovery-page-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: InMemorySecretStore(),
      executionStore: SavedTeamRecoveryFixture([]), fileURL: root.appendingPathComponent("history.sqlite3"))
    for index in 0..<19 { XCTAssertTrue(history.upsert(durableTeamSnapshot("pending-\(index)"))) }
    var finished = durableTeamSnapshot("finished")
    finished.state = .succeeded
    XCTAssertTrue(history.upsert(finished))
    var cursor = ""
    var seen = Set<String>()
    var pages = 0
    repeat {
      let page = try history.pendingRecoveryPage(after: cursor, limit: 8)
      XCTAssertLessThanOrEqual(page.teams.count, 8)
      for team in page.teams { XCTAssertTrue(seen.insert(team.supervisorRunId).inserted) }
      cursor = page.next ?? ""
      pages += 1
      XCTAssertLessThanOrEqual(pages, 3)
      if pages > 3 { break }
    } while !cursor.isEmpty
    XCTAssertEqual(seen, Set((0..<19).map { "pending-\($0)" }))
    XCTAssertEqual(pages, 3)
  }

  func testObserverGenerationAndSequenceFloorsSurviveReopen() throws {
    let suite = "team-owner-generation-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    var snapshot = durableTeamSnapshot("run")
    let source = UUID().uuidString.lowercased()
    snapshot.members[1].sourceMessageId = source
    XCTAssertTrue(history.upsert(snapshot))
    XCTAssertEqual(try history.consumeOwnedReply(source: source, conversation: "conversation", turn: "turn", task: source,
      contact: "review", content: "partial", richOutputJson: "", terminal: false, success: true, now: 10,
      observation: AgentTeamReplyObservation(generation: 2, sequence: 10)), .observerProgress)
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    for observation in [AgentTeamReplyObservation(generation: 1, sequence: 999),
      AgentTeamReplyObservation(generation: 2, sequence: 9), AgentTeamReplyObservation(generation: 2),
      AgentTeamReplyObservation(), AgentTeamReplyObservation(payload: ["execution_generation": true, "status_sequence": 20])] {
      XCTAssertEqual(try reopened.consumeOwnedReply(source: source, conversation: "conversation", turn: "turn", task: source,
        contact: "review", content: "stale", richOutputJson: "", terminal: true, success: true, now: 20,
        observation: observation), .observerStale)
    }
    XCTAssertEqual(reopened.snapshot(supervisorRunId: "run")?.members[1].status, .pending)
    XCTAssertEqual(try reopened.consumeOwnedReply(source: source, conversation: "conversation", turn: "turn", task: source,
      contact: "review", content: "current", richOutputJson: "", terminal: true, success: true, now: 30,
      observation: AgentTeamReplyObservation(generation: 2, sequence: 11)), .observerCommitted)
    XCTAssertEqual(reopened.snapshot(supervisorRunId: "run")?.members[1].output, "current")
    XCTAssertEqual(reopened.snapshot(supervisorRunId: "run")?.members[0].status, .pending)
  }

  func testObserverNewGenerationResetsSequenceAndRejectedUpdateDoesNotAdvanceFloor() throws {
    let suite = "team-owner-generation-reset-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: InMemorySecretStore(),
      executionStore: SavedTeamRecoveryFixture([]), fileURL: root.appendingPathComponent("history.sqlite3"))
    XCTAssertTrue(history.upsert(durableTeamSnapshot("run")))
    func consume(_ generation: Int64, _ sequence: Int64, terminal: Bool, content: String, success: Bool = true) throws -> AgentTeamReplyDisposition {
      try history.consumeOwnedReply(source: "source-review", conversation: "conversation", turn: "turn", task: "source-review",
        contact: "review", content: content, richOutputJson: "", terminal: terminal, success: success, now: 20,
        observation: AgentTeamReplyObservation(generation: generation, sequence: sequence))
    }
    XCTAssertEqual(try consume(1, 100, terminal: false, content: "partial"), .observerProgress)
    XCTAssertEqual(try consume(2, 1, terminal: false, content: "new attempt"), .observerProgress)
    XCTAssertThrowsError(try consume(3, 100, terminal: true, content: "", success: false))
    XCTAssertEqual(try consume(1, 200, terminal: true, content: "old"), .observerStale)
    XCTAssertEqual(try consume(2, 2, terminal: true, content: "current"), .observerCommitted)
  }

  func testObserverObservationRejectsMalformedAndUnsafeNumbers() {
    let invalidValues: [Any] = [true, -1, 1.5, Double.infinity, "not-an-integer", "9223372036854775808"]
    for value in invalidValues {
      XCTAssertFalse(AgentTeamReplyObservation(payload: ["execution_generation": value]).valid)
    }
    XCTAssertFalse(AgentTeamReplyObservation(payload: ["status_sequence": true]).valid)
    XCTAssertFalse(AgentTeamReplyObservation(payload: ["status_sequence": 9_007_199_254_740_992.0]).valid)
    let observation = AgentTeamReplyObservation(payload: ["execution_generation": "2", "status_seq": "3"])
    XCTAssertTrue(observation.valid)
    XCTAssertEqual(observation.generation, 2)
    XCTAssertEqual(observation.sequence, 3)
    XCTAssertTrue(AgentTeamReplyObservation().valid)
  }

  func testObserverOwnershipHidesProgressAndKeepsFirstCommittedResult() throws {
    let suite = "team-owner-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: root.appendingPathComponent("history.sqlite3"))
    var snapshot = durableTeamSnapshot("run")
    let source = UUID().uuidString.lowercased()
    snapshot.members[1].sourceMessageId = source
    XCTAssertTrue(history.upsert(snapshot))
    func consume(_ content: String, terminal: Bool, task: String? = nil) throws -> AgentTeamReplyDisposition {
      try history.consumeOwnedReply(source: source, conversation: "conversation", turn: "turn", task: task ?? source,
        contact: "review", content: content, richOutputJson: "{\"version\":1,\"blocks\":[]}",
        terminal: terminal, success: true, now: 20)
    }
    XCTAssertEqual(try consume("delta", terminal: false), .observerProgress)
    XCTAssertEqual(history.snapshot(supervisorRunId: "run")?.members[1].status, .pending)
    XCTAssertEqual(try consume("review result", terminal: true), .observerCommitted)
    XCTAssertEqual(history.snapshot(supervisorRunId: "run")?.members[0].status, .pending)
    XCTAssertEqual(history.snapshot(supervisorRunId: "run")?.state, .running)
    XCTAssertEqual(try consume("replacement duplicate", terminal: true), .observerDuplicate)
    XCTAssertEqual(history.snapshot(supervisorRunId: "run")?.members[1].output, "review result")
    XCTAssertEqual(try consume("foreign", terminal: true, task: "other"), .notOwned)
    XCTAssertEqual(try history.consumeOwnedReply(source: "source-primary", conversation: "conversation", turn: "turn",
      task: "source-primary", contact: "primary", content: "answer", richOutputJson: "", terminal: true,
      success: true, now: 30), .primary)
    history.remove(supervisorRunId: "run")
    XCTAssertEqual(try consume("late", terminal: true), .retired)
    history.clear()
    XCTAssertEqual(try consume("late after clear", terminal: true), .retired)
    AgentTeamExecutionHistoryStore.destroyPersistentStore(defaults: defaults, secrets: secrets, fileURL: root.appendingPathComponent("history.sqlite3"))
    XCTAssertEqual(try consume("after full destroy", terminal: true), .notOwned)
  }

  func testObserverOwnershipRejectsAmbiguousAndForeignTaskScope() throws {
    let suite = "team-owner-scope-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: InMemorySecretStore(),
      executionStore: SavedTeamRecoveryFixture([]), fileURL: root.appendingPathComponent("history.sqlite3"))
    let original = durableTeamSnapshot("run")
    XCTAssertTrue(history.upsert(original))
    for (conversation, turn, contact) in [("other", "turn", "review"), ("conversation", "other", "review"), ("conversation", "turn", "other")] {
      XCTAssertEqual(try history.consumeOwnedReply(source: "source-review", conversation: conversation, turn: turn,
        task: "source-review", contact: contact, content: "foreign", richOutputJson: "", terminal: true,
        success: true, now: 20), .notOwned)
    }
    var duplicateOwner = original
    duplicateOwner.supervisorRunId = "another-run"
    XCTAssertTrue(history.upsert(duplicateOwner))
    XCTAssertThrowsError(try history.consumeOwnedReply(source: "source-review", conversation: "conversation", turn: "turn",
      task: "source-review", contact: "review", content: "ambiguous", richOutputJson: "", terminal: true,
      success: true, now: 20))
    XCTAssertEqual(history.snapshot(supervisorRunId: "run")?.members[1].status, .pending)
  }

  func testObserverOwnershipSurvivesFinishedHistoryPruning() throws {
    let suite = "team-owner-prune-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    var old = durableTeamSnapshot("run")
    old.state = .succeeded
    XCTAssertTrue(history.upsert(old))
    for index in 0..<201 {
      var next = durableTeamSnapshot("new-\(index)")
      next.state = .succeeded
      next.updatedAtMillis = Int64(index + 100)
      XCTAssertTrue(history.upsert(next))
    }
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    XCTAssertNil(reopened.snapshot(supervisorRunId: "run"))
    XCTAssertEqual(try reopened.consumeOwnedReply(source: "source-review", conversation: "conversation", turn: "turn",
      task: "source-review", contact: "review", content: "late result", richOutputJson: "", terminal: true,
      success: true, now: 1_000), .retired)
  }

  func testTeamHistoryUpdatesLatestRosterAcrossInstancesAndPreservesRichReplies() throws {
    let suite = "team-history-atomic-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    let first = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    let second = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    let initial = durableTeamSnapshot("run")
    XCTAssertTrue(first.upsert(initial))
    let rich = #"{"version":1,"blocks":[{"id":"review-image","type":"image","uri":"galaxyssi-artifact://task/image.png"}]}"#
    XCTAssertNotNil(second.applyReply(supervisorRunId: "run", source: "source-review", conversation: "conversation",
      turn: "turn", task: "source-review", contact: "review", content: "review", richOutputJson: rich, success: true, now: 20))
    let final = try XCTUnwrap(first.applyReply(supervisorRunId: "run", source: "source-primary", conversation: "conversation",
      turn: "turn", task: "source-primary", contact: "primary", content: "answer", success: true, now: 30))
    XCTAssertEqual(final.state, .succeeded)
    XCTAssertEqual(second.snapshot(supervisorRunId: "run")?.members.last?.richOutputJson, rich)
    var stale = initial
    stale.updatedAtMillis = 99_999
    XCTAssertTrue(first.upsert(stale))
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([stale]), fileURL: file)
    XCTAssertEqual(reopened.snapshot(supervisorRunId: "run")?.state, .succeeded)
    XCTAssertEqual(reopened.snapshot(supervisorRunId: "run")?.finalOutput, "answer")
  }

  func testTeamHistoryRetentionNeverDropsPendingOrInterruptedTeams() {
    let suite = "team-history-retention-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: InMemorySecretStore(),
      executionStore: SavedTeamRecoveryFixture([]), fileURL: root.appendingPathComponent("history.sqlite3"))
    for index in 0..<205 { XCTAssertTrue(history.upsert(durableTeamSnapshot("pending-\(index)"))) }
    var interrupted = durableTeamSnapshot("interrupted")
    interrupted.state = .interrupted
    XCTAssertTrue(history.upsert(interrupted))
    for index in 0..<205 {
      var final = durableTeamSnapshot("final-\(index)")
      final.state = .succeeded
      final.updatedAtMillis = Int64(index + 100)
      XCTAssertTrue(history.upsert(final))
    }
    XCTAssertEqual(history.recoverable(conversationId: "conversation").count, 206)
    XCTAssertEqual(history.recent(1_000).filter { $0.state.deliverable }.count, 200)
    XCTAssertEqual(history.recent(1_000).count, 406)
    XCTAssertTrue(history.recoverable(conversationId: "other").isEmpty)
  }

  func testTeamHistoryMigrationCommitsBeforeRemovingLegacyAndClearCannotResurrect() throws {
    let suite = "team-history-migration-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let key = AgentTeamExecutionHistoryStore.defaultStorageKey
    let legacy = try JSONEncoder().encode([durableTeamSnapshot("legacy")])
    defaults.set(legacy, forKey: key)
    let secrets = TeamCompletionFailingSecrets()
    let file = root.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    XCTAssertFalse(history.upsert(durableTeamSnapshot("new")))
    XCTAssertEqual(defaults.data(forKey: key), legacy)
    secrets.rejectWrites = false
    XCTAssertNotNil(history.snapshot(supervisorRunId: "legacy"))
    XCTAssertNil(defaults.object(forKey: key))
    history.clear()
    defaults.set(legacy, forKey: key)
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    XCTAssertNil(reopened.snapshot(supervisorRunId: "legacy"))
    XCTAssertNil(defaults.object(forKey: key))
    XCTAssertTrue(reopened.upsert(durableTeamSnapshot("new")))
    AgentTeamExecutionHistoryStore.destroyPersistentStore(defaults: defaults, secrets: secrets, fileURL: file)
    XCTAssertNil(reopened.snapshot(supervisorRunId: "new"))
  }

  func testPrimaryRecallRequiresCurrentGenerationAndCannotReopenTerminalGeneration() {
    let owner = AgentTeamReplyOwner(supervisorRunId: "run", memberId: "primary", conversationId: "group",
      turnId: "turn", sourceMessageId: "source", contactId: "codex", deliveryMode: .respond)
    XCTAssertFalse(owner.permitsRecall(generation: 1))
    let first = owner.observingPrimaryRecall(.init(generation: 1, sequence: 10), terminal: false)
    XCTAssertTrue(first.permitsRecall(generation: 1))
    let closed = first.observingPrimaryRecall(.init(generation: 1), terminal: true)
    XCTAssertFalse(closed.permitsRecall(generation: 1))
    XCTAssertFalse(closed.observingPrimaryRecall(.init(generation: 1, sequence: 11), terminal: false)
      .permitsRecall(generation: 1))
    let resumed = closed.observingPrimaryRecall(.init(generation: 2, sequence: 1), terminal: false)
    XCTAssertFalse(resumed.permitsRecall(generation: 1))
    XCTAssertTrue(resumed.permitsRecall(generation: 2))
  }

  func testDesktopRecallReplayPreservesResponseAndRejectsChangedIdentity() {
    var cache = AgentDesktopCollaborationResponseReplay()
    let result: AgentMcpJSONObject = ["success": .bool(true), "data_b64": .string("original")]
    cache.remember(result, key: "nonce", fingerprint: "assignment-1", expiresAt: 20, now: 10)
    XCTAssertEqual(cache.lookup(key: "nonce", fingerprint: "assignment-1", now: 11), .response(result))
    XCTAssertEqual(cache.lookup(key: "nonce", fingerprint: "assignment-2", now: 11), .identityMismatch)
    let absent: AgentMcpJSONObject = ["success": .bool(true), "status": .string("not_recorded")]
    cache.remember(absent, key: "receipt-nonce", fingerprint: "assignment-1", expiresAt: 20, now: 10)
    XCTAssertEqual(cache.lookup(key: "receipt-nonce", fingerprint: "assignment-1", now: 11, revalidate: true), .missing)
    XCTAssertEqual(cache.lookup(key: "receipt-nonce", fingerprint: "assignment-2", now: 11, revalidate: true), .identityMismatch)
    XCTAssertEqual(cache.lookup(key: "nonce", fingerprint: "assignment-1", now: 20), .missing)
    cache.remember(["success": .bool(false)], key: "failed", fingerprint: "assignment-1", expiresAt: 30, now: 20)
    XCTAssertEqual(cache.lookup(key: "failed", fingerprint: "assignment-1", now: 21), .missing)
    for _ in 0..<4 { XCTAssertTrue(cache.begin(desktopId: "desktop")) }
    XCTAssertFalse(cache.begin(desktopId: "desktop"))
    XCTAssertTrue(cache.begin(desktopId: "other"))
    cache.end(desktopId: "desktop")
    XCTAssertTrue(cache.begin(desktopId: "desktop"))
  }

  func testDesktopGoalRecallCursorBindsOriginalSectionAndAssignment() {
    let recall = AgentDesktopCollaborationArchiveRecall.self
    let scope = AgentCollaborationToolEvidenceScope(runId: "run", conversationId: "group",
      turnId: "turn", memberId: "review", sourceId: "source")
    let hash = String(repeating: "a", count: 64)
    let cursor = recall.goalCursor(scope: scope, generation: 1, section: "criteria", hash: hash, offset: 8_192)
    var request: AgentMcpJSONObject = ["mode": .string("goal_contract"), "section": .string("criteria"),
      "cursor": .string(cursor)]
    XCTAssertEqual(recall.goalSelector(request, scope: scope, generation: 1)?["offset"], .int(8_192))
    XCTAssertEqual(recall.goalSelector(request, scope: scope, generation: 1)?["sha256"], .string(hash))
    XCTAssertNil(recall.goalSelector(request, scope: scope, generation: 2))
    var other = scope
    other.sourceId = "other"
    XCTAssertNil(recall.goalSelector(request, scope: other, generation: 1))
    request["section"] = .string("goal")
    XCTAssertNil(recall.goalSelector(request, scope: scope, generation: 1))
  }

  func testDecisionContextPrefersRecentWholeDependencyAndKeepsOriginalSelector() {
    let long = String(repeating: "\u{1F642}", count: 200)
    let recent = String(repeating: "r", count: 200)
    let context = AgentCollaborationDecisionContext.dependencyLines([("old", long), ("recent", recent)], maximumBytes: 400)
    XCTAssertTrue(context.omitted)
    XCTAssertTrue(context.lines[0].contains("archive_record_id="))
    XCTAssertFalse(context.lines[0].contains(long))
    XCTAssertTrue(context.lines[1].hasSuffix(recent))
    XCTAssertLessThanOrEqual(context.lines.joined(separator: "\n").utf8.count, 400)
    let preview = AgentCollaborationDecisionContext.dependencyLines([("old", long)], maximumBytes: 1,
      recallAvailable: false)
    XCTAssertTrue(preview.lines[0].hasSuffix(long))
  }

  func testDesktopObserverRecallCanUseAuthenticatedEventsBeforeText() {
    let owner = AgentTeamReplyOwner(supervisorRunId: "run", memberId: "observer", conversationId: "group",
      turnId: "turn", sourceMessageId: "source", contactId: "codex", deliveryMode: .observe)
    let first = owner.observingRecallEvent(.init(generation: 2, sequence: 4), terminal: false)
    XCTAssertNil(first.observedGeneration)
    XCTAssertTrue(first.permitsRecall(generation: 2))
    XCTAssertFalse(first.observingRecallEvent(.init(generation: 1, sequence: 99), terminal: false)
      .permitsRecall(generation: 1))
    let closed = first.observingRecallEvent(.init(generation: 2, sequence: 5), terminal: true)
    XCTAssertFalse(closed.observingRecallEvent(.init(generation: 2, sequence: 4), terminal: false)
      .permitsRecall(generation: 2))
  }

  func testDesktopArchiveRecallAcceptsOnlyScopedRecordSelectors() {
    let id = AgentDesktopCollaborationArchiveRecall.recordId(memberId: "review")
    let query: AgentMcpJSONObject = ["mode": .string("archive"), "record_id": .string(id), "offset": .int(8_192)]
    XCTAssertEqual(AgentDesktopCollaborationArchiveRecall.selector(query)?.recordId, id)
    XCTAssertEqual(AgentDesktopCollaborationArchiveRecall.selector(query)?.offset, 8_192)
    var invalid = query
    invalid["member_id"] = .string("review")
    XCTAssertNil(AgentDesktopCollaborationArchiveRecall.selector(invalid))
    invalid = query
    invalid["offset"] = .int(-1)
    XCTAssertNil(AgentDesktopCollaborationArchiveRecall.selector(invalid))
  }

  func testDependencyRecallRequiresPinnedDirectDependencyAndExactReply() throws {
    let suite = "team-dependency-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: InMemorySecretStore(),
      executionStore: SavedTeamRecoveryFixture([]), fileURL: root.appendingPathComponent("history.sqlite3"))
    var team = durableTeamSnapshot("run")
    team.members[0].dispatchCheckpoint = .dispatching
    team.members[0].dispatchDependencyMemberIds = ["review"]
    let original = String(repeating: "\u{1F642}", count: 2_050)
    team.members[1].status = .succeeded
    team.members[1].replyContent = original
    XCTAssertTrue(history.upsert(team))
    var input: AgentMcpJSONObject = ["mode": .string("dependency"), "member_id": .string("review")]
    let scope = AgentCollaborationToolEvidenceScope(runId: "run", conversationId: team.conversationId,
      turnId: team.taskId, memberId: "primary", sourceId: "source-primary")
    var foreign = scope
    foreign.sourceId = "other"
    XCTAssertThrowsError(try history.recallCollaborationOriginal(input, scope: foreign))
    let page = try history.recallCollaborationOriginal(input, scope: scope)
    input["offset"] = page["next_offset"]
    XCTAssertThrowsError(try history.recallCollaborationOriginal(input, scope: scope))
    input["sha256"] = page["sha256"]
    let tail = try history.recallCollaborationOriginal(input, scope: scope)
    let prefix = try XCTUnwrap(Data(base64Encoded: page.string("data_b64")))
    let suffix = try XCTUnwrap(Data(base64Encoded: tail.string("data_b64")))
    XCTAssertEqual(prefix + suffix, Data(original.utf8))
    input["member_id"] = .string("primary")
    XCTAssertThrowsError(try history.recallCollaborationOriginal(input, scope: scope))
    input["member_id"] = .string("review")
    history.removeResearchObjects(conversationId: team.conversationId)
    XCTAssertThrowsError(try history.recallCollaborationOriginal(input, scope: scope))
  }

  func testSourceAccessReturnsOnlyDirectReadableSelectorsWithoutCoverage() throws {
    let suite = "team-source-access-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
    let secrets = InMemorySecretStore()
    let file = folder.appendingPathComponent("history.sqlite3")
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    let database = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    let team = durableTeamSnapshot("source-access")
    XCTAssertTrue(history.upsert(team))
    let member = try XCTUnwrap(team.members.first { !$0.status.isTerminal })
    let scope = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId, memberId: member.memberId, sourceId: member.sourceMessageId)
    let observation = AgentCollaborationCloudToolEvidence(scope: scope, round: 1,
      call: AssembledToolCall(callId: "observation", index: 0, name: "web_search", argumentsJson: "{}"),
      output: "private tool result", succeeded: true, startedAtMillis: 10, finishedAtMillis: 12)
    let receipt = try history.recordCloudEvidence(observation)
    let evidenceID = receipt.string("evidence_id")
    let digest = receipt.string("sha256")
    func reference(_ index: Int64) -> AgentCollaborationResearchReference {
      .init(objectId: String(format: "%064llx", index), revision: 1, sha256: String(format: "%064llx", index + 100))
    }
    func revision(_ ref: AgentCollaborationResearchReference, author: String,
                  parents: [AgentCollaborationResearchReference] = []) -> AgentCollaborationResearchRevision {
      .init(reference: ref, previousHash: nil, runId: scope.runId, turnId: scope.turnId, authorId: author,
        sourceId: scope.sourceId, draft: .init(id: "item", objectId: nil, baseRevision: 0, kind: .evidence,
          title: "Private source title", body: ["embedded": .object(AgentCollaborationSourceAccess.workspaceReference(reference(98)))],
          parents: parents))
    }
    let parents = (1...21).map { reference(Int64($0)) }
    var root = revision(reference(99), author: scope.memberId, parents: parents)
    root.frozenCloudReads = [.init(evidenceId: evidenceID, sha256: digest, totalCharacters: 1)]
    try database.transaction {
      for record in [root, revision(parents[0], author: scope.memberId, parents: [reference(98)]),
                     revision(parents[1], author: "other-member")] {
        try database.insertResearchRecord(record, conversationId: scope.conversationId,
          key: "object:" + record.reference.objectId, revision: record.reference.revision)
      }
    }
    var input = AgentCollaborationSourceAccess.workspaceReference(root.reference)
    input["mode"] = .string("source_access")
    let first = try history.recallCollaborationOriginal(input, scope: scope, generation: 1)
    let rows = try XCTUnwrap(first["references"]?.arrayValue)
    XCTAssertEqual(rows.count, 20)
    XCTAssertEqual(first["total_references"], .int(22))
    XCTAssertEqual(first["availability_snapshot"], .bool(false))
    XCTAssertEqual(rows.first?.objectValue?["status"], .string("available"))
    XCTAssertEqual(rows.dropFirst().first?.objectValue?["status"], .string("missing_changed_or_out_of_scope"))
    XCTAssertNil(rows.dropFirst().first?.objectValue?["read_original"])
    XCTAssertFalse(AgentMcpJSONCodec.stringify(first).contains("Private source title"))
    input["cursor"] = try XCTUnwrap(first["next_cursor"])
    XCTAssertThrowsError(try history.recallCollaborationOriginal(input, scope: scope, generation: 2))
    let second = try history.recallCollaborationOriginal(input, scope: scope, generation: 1)
    let evidence = try XCTUnwrap(second["references"]?.arrayValue?.last?.objectValue)
    XCTAssertEqual(second["next_cursor"], .null)
    XCTAssertEqual(evidence["source_field"], .string("host_observations"))
    XCTAssertEqual(evidence["status"], .string("available"))
    XCTAssertFalse(AgentMcpJSONCodec.stringify(second).contains("private tool result"))
    let original = try XCTUnwrap(evidence["read_original"]?.objectValue)
    let coverageKey = "cloud-read-coverage:" + AgentMcpJSONCodec.sha256([
      "run": .string(scope.runId), "group": .string(scope.conversationId), "turn": .string(scope.turnId),
      "member": .string(scope.memberId), "source": .string(scope.sourceId),
      "evidence": .string(evidenceID), "sha256": .string(digest)
    ])
    func coverage() throws -> AgentCollaborationReadCoverage? {
      try database.researchRecord(AgentCollaborationReadCoverage.self, conversationId: scope.conversationId,
        key: coverageKey, revision: 0)
    }
    XCTAssertNil(try coverage())
    var replay = AgentDesktopCollaborationResponseReplay()
    func read(_ record: Bool) throws -> AgentMcpJSONObject {
      try history.recallCollaborationOriginal(original, scope: scope, recordEvidenceCoverage: record)
    }
    let deliveryPage = try XCTUnwrap(AgentDesktopCollaborationEvidenceDelivery.exchange(input: original,
      confirmation: nil, binding: "active", expiresAt: 100, now: 1, replay: &replay, read: read))
    XCTAssertNil(deliveryPage["host_read_coverage"])
    XCTAssertNil(try coverage())
    let delivery = try XCTUnwrap(deliveryPage["delivery"]?.objectValue)
    XCTAssertNil(try AgentDesktopCollaborationEvidenceDelivery.exchange(input: original,
      confirmation: delivery, binding: "wrong", expiresAt: 100, now: 2, replay: &replay, read: read))
    XCTAssertNil(try coverage())
    let confirmed = try AgentDesktopCollaborationEvidenceDelivery.exchange(input: original,
      confirmation: delivery, binding: "active", expiresAt: 100, now: 3, replay: &replay, read: read)
    XCTAssertEqual(confirmed?["status"], .string("confirmed"))
    XCTAssertEqual(confirmed?["host_read_coverage"]?.objectValue?["mode"], .string("scoped_pages"))
    XCTAssertEqual(confirmed?["host_read_coverage"]?.objectValue?["reader"]?.objectValue?["source_id"], .string(scope.sourceId))
    XCTAssertEqual(confirmed?["host_read_coverage"]?.objectValue?["sha256"], .string(digest))
    XCTAssertNotNil(try coverage())
    history.removeResearchObjects(conversationId: scope.conversationId)
    XCTAssertThrowsError(try history.recallCollaborationOriginal(input, scope: scope, generation: 1))
  }

  func testMailboxMigratesWithoutEvictingOldPendingMessages() throws {
    let suite = "team-mailbox-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let key = "mailbox"
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("mailbox.sqlite3")
    let legacy = (1...5_001).map { index in
      AgentTeamMessageEnvelope(messageId: "message-\(index)", teamId: "team", conversationId: "group",
        supervisorRunId: "run", fromInstanceId: "author", toInstanceId: "reviewer",
        kind: .review, text: "Review", sequence: Int64(index), state: index == 1 ? .pending : .acknowledged)
    }
    XCTAssertTrue(GalaxySSIEncryptedUserDefaultsStore.write(try JSONEncoder().encode(legacy),
      defaults: defaults, key: key, secrets: secrets))
    let mailbox = UserDefaultsAgentTeamMailbox(defaults: defaults, key: key, secrets: secrets, fileURL: file)
    XCTAssertEqual(mailbox.pendingMessages(supervisorRunId: "run", instanceId: "reviewer").map(\.sequence), [1])
    XCTAssertNil(defaults.data(forKey: key + ".encrypted.v1"))
    let reopened = UserDefaultsAgentTeamMailbox(defaults: defaults, key: key, secrets: secrets, fileURL: file)
    XCTAssertEqual(try reopened.append(legacy[0]).sequence, 1)
    XCTAssertEqual(reopened.acknowledge(messageId: "message-1", atMillis: 1)?.state, .acknowledged)
    XCTAssertTrue(mailbox.pendingMessages(supervisorRunId: "run", instanceId: "reviewer").isEmpty)
    XCTAssertEqual(mailbox.messages(supervisorRunId: "run", instanceId: "reviewer", afterSequence: 5_000).count, 1)
    XCTAssertEqual(mailbox.messages(supervisorRunId: "run", instanceId: "unrelated", afterSequence: 0).count, 0)
    let recent = try reopened.recentMessages(supervisorRunId: "run", conversationId: "group")
    XCTAssertEqual(recent.map(\.sequence), Array(Int64(4_982)...5_001))
    XCTAssertThrowsError(try reopened.recentMessages(supervisorRunId: "run", conversationId: "other"))
    XCTAssertTrue(try reopened.recentMessages(supervisorRunId: "missing", conversationId: "group").isEmpty)
    var added = legacy[0]
    added.messageId = "new-request"
    var invalid = added
    invalid.messageId = "invalid-request"
    invalid.text = ""
    XCTAssertThrowsError(try reopened.appendAll([added, invalid]))
    XCTAssertTrue(mailbox.pendingMessages(supervisorRunId: "run", instanceId: "reviewer").isEmpty)
    let batch = try reopened.appendAll([legacy[0], added, added])
    XCTAssertEqual(batch.map(\.sequence), [1, 5_002, 5_002])
    XCTAssertEqual(mailbox.pendingMessages(supervisorRunId: "run", instanceId: "reviewer").map(\.messageId), ["new-request"])
  }

  func testOriginalPrimaryRecoveryIsDurableAndRejectsForeignOrConflictingReplies() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let suite = "primary-recovery-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let secrets = InMemorySecretStore()
    func history() -> AgentTeamExecutionHistoryStore {
      AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
        executionStore: SavedTeamRecoveryFixture([]), fileURL: root.appendingPathComponent("team.sqlite3"))
    }
    let sourceID = UUID().uuidString
    var original = durableTeamSnapshot("original-primary")
    original.state = .interrupted
    original.members[0].status = .interrupted
    original.members[0].sourceMessageId = sourceID
    original.members[0].dispatchCheckpoint = .accepted
    XCTAssertTrue(history().upsert(original))
    let store = history()
    let owner = try XCTUnwrap(store.recoveryContext(source: sourceID, conversation: original.conversationId,
      turn: original.taskId, contact: original.primaryAgentId)?.owner)
    let outgoing = ChatMessage(contactId: "hermes", content: "Original request", isMine: true,
      conversationId: original.conversationId, turnId: original.taskId)
    let identity = AgentTaskIdentity(clientRouteId: "route", conversationId: original.conversationId,
      taskId: sourceID, turnId: original.taskId)
    let binding = try XCTUnwrap(AgentDesktopReplyBinding.teamPrimary(owner: owner,
      desktopId: "desktop", agentId: "codex", identity: identity, outgoing: outgoing))
    XCTAssertEqual(binding.sourceIdentity, sourceID)
    XCTAssertEqual(binding.sourceId, outgoing.id)
    XCTAssertNil(AgentDesktopReplyBinding.teamPrimary(owner: owner, desktopId: "desktop", agentId: "codex",
      identity: identity, outgoing: ChatMessage(contactId: "hermes", content: "Wrong turn", isMine: true,
        conversationId: original.conversationId, turnId: "other")))
    var wrong = binding
    wrong.contactId = "foreign"
    let observed = AgentTeamReplyObservation(generation: 2, sequence: 10)
    XCTAssertFalse(try store.commitRecoveredPrimary(binding: wrong, content: "Original answer", rich: "",
      success: true, observation: observed, now: 10))
    XCTAssertTrue(try store.commitRecoveredPrimary(binding: binding, content: "Original answer", rich: "",
      success: true, observation: observed, now: 10))
    let reopened = history()
    XCTAssertTrue(try reopened.commitRecoveredPrimary(binding: binding, content: "Original answer", rich: "",
      success: true, observation: observed, now: 11))
    XCTAssertFalse(try reopened.commitRecoveredPrimary(binding: binding, content: "Conflicting answer", rich: "",
      success: true, observation: observed, now: 11))
    XCTAssertFalse(try reopened.commitRecoveredPrimary(binding: binding, content: "Original answer", rich: "",
      success: true, observation: .init(generation: 1, sequence: 20), now: 11))
    XCTAssertEqual(reopened.snapshot(supervisorRunId: original.supervisorRunId)?.members[0].replyContent, "Original answer")
  }

  func testCurrentCollaborationKeepsUnresolvedResearchAheadOfFollowUps() {
    var research = durableTeamSnapshot("older-research")
    research.state = .interrupted
    research.members[1].researchStage = "investigate"
    var followUp = durableTeamSnapshot("newer-follow-up")
    followUp.createdAtMillis = research.createdAtMillis + 5
    followUp.state = .succeeded
    XCTAssertEqual(AgentTeamExecutionHistoryStore.preferredCollaborationRun([followUp, research]), research)
    research.state = .succeeded
    XCTAssertEqual(AgentTeamExecutionHistoryStore.preferredCollaborationRun([followUp, research]), followUp)
  }

  private func durableTeamSnapshot(_ run: String) -> AgentTeamExecutionSnapshot {
    AgentTeamExecutionSnapshot(supervisorRunId: run, teamId: "team", conversationId: "conversation",
      taskId: "turn", primaryAgentId: "primary", state: .running,
      members: [AgentTeamMemberSnapshot(agentId: "primary", deliveryMode: .respond,
        sourceMessageId: run == "run" ? "source-primary" : "source-primary-\(run)"),
        AgentTeamMemberSnapshot(agentId: "review", deliveryMode: .observe,
          sourceMessageId: run == "run" ? "source-review" : "source-review-\(run)")],
      createdAtMillis: 1, updatedAtMillis: 1)
  }

  func testStartupAndReopenedLiveWorkUseStableDispatchTextWithoutRewritingSources() async throws {
    let role = String(repeating: "r", count: 79)
    let objective = String(repeating: "a", count: 7_999)
    let originalRole = "  " + role + " remainder\n"
    let originalObjective = "  " + objective + " remainder\n"
    let raw = AgentTeamMember(agentId: "provider", deliveryMode: .respond, requiredCapabilities: [],
      role: originalRole, objective: originalObjective, dependsOnAgentIds: [], context: [:], instanceId: "opaque-member")
    let goal = "  Preserve the original goal\n"
    let run = AgentRunRequest(conversationId: "projection", messageId: "turn", taskId: "turn",
      runId: UUID().uuidString, parentRunId: "", goal: goal, deliveryMode: .respond, requiredCapabilities: [],
      context: [:], idempotencyKey: "projection", createdAtMillis: 1)
    let definition = AgentTeamDefinition(teamId: "team", primaryAgentId: "provider", members: [raw],
      visibilityMode: .background, collectiveCapabilities: [], primaryInstanceId: raw.memberId)
    let runtime = AgentTeamExecutionRuntime(store: InMemoryAgentTeamExecutionStore(), mailbox: InMemoryAgentTeamMailbox())
    defer { runtime.close() }
    let handle = try runtime.start(definition: definition, request: run,
      worker: ClosureAgentTeamMemberWorker { context in
        XCTAssertEqual(context.member.role, role)
        XCTAssertEqual(context.member.objective, objective)
        XCTAssertEqual(context.member.memberId, raw.memberId)
        XCTAssertEqual(context.request.context["team_role"], .string(role))
        XCTAssertEqual(Data(context.request.goal.utf8), Data(goal.utf8))
        return AgentSubagentOutput(content: "Completed")
      })
    let result = try await handle.wait()
    XCTAssertEqual(result.finalOutput, "Completed")
    XCTAssertEqual(definition.members.first?.role, originalRole)
    XCTAssertEqual(definition.members.first?.objective, originalObjective)
    XCTAssertEqual(AgentTeamDispatchText.role(role), role)
    XCTAssertEqual(AgentTeamDispatchText.objective(objective), objective)

    let fullAssignment = String(repeating: "s", count: 12_000) + " keep the final requirement"
    let retained = " \n" + fullAssignment + "\n "
    let work = AgentCollaborationLiveGraph.Work(id: "live-review", member: raw.memberId,
      assignment: retained, depends_on: [], dependency_policy: nil, independent_review: nil)
    let bytes = try JSONEncoder().encode(work)
    let reopened = try JSONDecoder().decode(AgentCollaborationLiveGraph.Work.self, from: bytes)
    XCTAssertEqual(Data(reopened.assignment.utf8), Data(retained.utf8))
    XCTAssertEqual(reopened.dispatchAssignment, fullAssignment)
    XCTAssertEqual(reopened.member, raw.memberId)
  }

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
    XCTAssertNil(AgentSavedTeamReplyPolicy.reconcileRecoveryWait(parent, runId: "original",
      cancelled: false, verification: "Waiting", now: 10))
    parent.teamRecoveryRunId = "original"
    var waiting = try XCTUnwrap(AgentSavedTeamReplyPolicy.reconcileRecoveryWait(parent, runId: "original",
      cancelled: false, verification: "Waiting", now: 10))
    XCTAssertEqual(waiting.phase, .waitingResponse)
    XCTAssertEqual(waiting.teamRecoveryRunId, "original")
    XCTAssertFalse(waiting.blocked)
    XCTAssertEqual(waiting.activePlan, parent.activePlan)
    XCTAssertNotNil(AgentSavedTeamReplyPolicy.settleParent(waiting, saved: saved, failureText: "Failed", now: 10))
    waiting.teamRecoveryRunId = "replacement"
    XCTAssertNil(AgentSavedTeamReplyPolicy.settleParent(waiting, saved: saved, failureText: "Failed", now: 10))
    let accepted = try XCTUnwrap(AgentSavedTeamReplyPolicy.settleParent(parent, saved: saved, failureText: "Failed", now: 10))
    XCTAssertEqual(accepted.phase, .completed)
    XCTAssertEqual(accepted.result, "Original answer")
    XCTAssertNil(accepted.teamRecoveryRunId)
    let receiverStore = makeStore()
    receiverStore.upsertAgentTask(parent)
    var cancelledReceiver = parent
    cancelledReceiver.phase = .cancelled
    receiverStore.upsertAgentTask(cancelledReceiver)
    XCTAssertFalse(receiverStore.replaceAgentTaskForRecovery(expected: parent, updated: accepted))
    XCTAssertEqual(receiverStore.agentTask(id: parent.taskId)?.phase, .cancelled)
    receiverStore.upsertAgentTask(parent)
    XCTAssertTrue(receiverStore.replaceAgentTaskForRecovery(expected: parent, updated: accepted))
    XCTAssertFalse(receiverStore.replaceAgentTaskForRecovery(expected: parent, updated: accepted))
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
    automatic.activePlan?.actions[1].status = .proposed
    XCTAssertTrue(AgentSavedTeamReplyPolicy.canContinueAutomatically(automatic))
    automatic.activePlan?.executionMode = .planOnly
    XCTAssertFalse(AgentSavedTeamReplyPolicy.canContinueAutomatically(automatic))
    automatic.activePlan?.executionMode = .autoComplete
    automatic.pendingActions[0].status = .pendingConfirmation
    automatic.activePlan?.actions[1].status = .pendingConfirmation
    XCTAssertFalse(AgentSavedTeamReplyPolicy.canContinueAutomatically(automatic))
    multi.activePlan = teamBridgePlan(action, action)
    XCTAssertNil(AgentSavedTeamReplyPolicy.settleParent(multi, saved: saved, failureText: "Failed", now: 10))
    parent.result = "Existing answer"
    XCTAssertNil(AgentSavedTeamReplyPolicy.settleParent(parent, saved: saved, failureText: "Failed", now: 10))
    parent.result = ""
    parent.phase = .cancelled
    XCTAssertNil(AgentSavedTeamReplyPolicy.settleParent(parent, saved: saved, failureText: "Failed", now: 10))
  }

  func testCoordinatorChecksExactIndependentGoalEvidenceWithoutAcceptingGoal() throws {
    let suite = "goal-evidence-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    func open() -> AgentTeamExecutionHistoryStore {
      .init(defaults: defaults, secrets: secrets, executionStore: SavedTeamRecoveryFixture([]),
        fileURL: root.appendingPathComponent("history.sqlite3"))
    }
    let history = open()
    var team = durableTeamSnapshot("goal-evidence")
    team.goal = "Document the observed value. Preserve its units."
    team.members.append(AgentTeamMemberSnapshot(agentId: "delivery", deliveryMode: .observe, sourceMessageId: "delivery-source"))
    team.members.append(AgentTeamMemberSnapshot(agentId: "dissent", deliveryMode: .observe, sourceMessageId: "dissent-source"))
    for index in team.members.indices { team.members[index].dispatchCheckpoint = .accepted }
    XCTAssertTrue(history.upsert(team))
    func scope(_ index: Int) -> AgentCollaborationToolEvidenceScope {
      .init(runId: team.supervisorRunId, conversationId: team.conversationId, turnId: team.taskId,
        memberId: team.members[index].memberId, sourceId: team.members[index].sourceMessageId)
    }
    func publish(_ draft: AgentCollaborationResearchDraft, author: Int, id: String) throws -> AgentCollaborationResearchReference {
      let owner = scope(author)
      let publication = try history.publishResearchObjects([draft], runId: owner.runId,
        conversationId: owner.conversationId, turnId: owner.turnId, memberId: owner.memberId,
        sourceId: owner.sourceId, milestone: (id, id))
      return try XCTUnwrap(publication.references.first)
    }
    let initial = """
      {"format":"galaxyssi.goal-assessment.v1","summary":"Pinned","decision":"continue","work":[],"blockers":[],
       "criteria":[{"id":"value","requirement":"Document the value","verification":"documentary","status":"open","evidence":[],
         "required_observations":[{"origin":"ios_native_tool","tool":"fixture.sensor"}]}]}
      """
    let pinned = try history.publishCollaborationMilestone(
      ["mode": .string("establish_contract"), "artifact": .string(initial)], scope: scope(0))
    var artifact = AgentCollaborationResearchDraft(id: "delivery", objectId: nil, baseRevision: 0, kind: .artifact,
      title: "Delivery", body: ["content": .string("Observed value 42")], parents: [])
    let delivery = try publish(artifact, author: 2, id: "delivery-v1")
    func ref(_ value: AgentCollaborationResearchReference) -> AgentMcpJSONObject {
      ["object_id": .string(value.objectId), "revision": .int(value.revision), "sha256": .string(value.sha256)]
    }
    var read = ref(delivery)
    read["mode"] = .string("workspace")
    XCTAssertThrowsError(try history.recallCollaborationOriginal(read, scope: scope(1)))
    read["mode"] = .string("acceptance_record")
    XCTAssertTrue(try history.recallCollaborationOriginal(read, scope: scope(1)).string("content").contains("Observed value 42"))
    let nativeAuthor = scope(2)
    let toolResult = AgentNativeToolResult(status: .succeeded, output: ["value": .int(42)], message: "",
      receipt: .init(invocationId: "fixture-invocation", startedAtEpochMillis: 1, finishedAtEpochMillis: 2,
        durationMillis: 1, status: .succeeded, inputSha256: "input", outputSha256: "output"),
      provenance: .init(toolId: "fixture.sensor", toolVersion: "1", location: .phone, executorId: "fixture", contractVersion: "1"))
    let observed = try history.recordNativeObservation(.init(runId: nativeAuthor.runId, conversationId: nativeAuthor.conversationId,
      turnId: nativeAuthor.turnId, memberId: nativeAuthor.memberId, sourceId: nativeAuthor.sourceId, input: [:], result: toolResult))
    let citation: AgentMcpJSONObject = ["origin": .string("ios_native_tool"),
      "evidence_id": observed["evidence_id"] ?? .null, "sha256": observed["sha256"] ?? .null]
    let reviewDraft = AgentCollaborationResearchDraft(id: "review", objectId: nil, baseRevision: 0, kind: .acceptanceReview,
      title: "Independent review", body: ["acceptance_review": .object([
        "criterion_id": .string("value"), "requirement": .string("Document the value"), "target": .object(ref(delivery)),
        "verdict": .string("supported"), "rationale": .string("Reviewed the exact delivery"), "unresolved": .array([])
      ])], parents: [delivery], observations: [citation])
    XCTAssertThrowsError(try publish(reviewDraft, author: 1, id: "review-v1"))
    var observationQuery = citation
    observationQuery.removeValue(forKey: "origin")
    observationQuery["mode"] = .string("native_evidence")
    let observationPage = try open().recallCollaborationOriginal(observationQuery, scope: scope(1))
    XCTAssertEqual(observationPage["host_read_coverage"]?.objectValue?["complete"], .bool(true))
    XCTAssertEqual(observationPage["source_reference"]?.objectValue?["origin"], .string("ios_native_tool"))
    let review = try publish(reviewDraft, author: 1, id: "review-v1")
    var reviewRead = ref(review)
    reviewRead["mode"] = .string("acceptance_record")
    var reviewJSON = ""
    var reviewOffset: Int64? = 0
    while let position = reviewOffset {
      reviewRead["offset"] = .int(position)
      let page = try open().recallCollaborationOriginal(reviewRead, scope: scope(3))
      XCTAssertNil(page["host_read_coverage"])
      reviewJSON += page.string("content")
      reviewOffset = page["next_offset"]?.intValue
    }
    let peerReview = try JSONDecoder().decode(AgentCollaborationResearchRevision.self, from: Data(reviewJSON.utf8))
    XCTAssertEqual(peerReview.frozenNativeReads?.first?.hostReadCoverage, observationPage["host_read_coverage"]?.objectValue)
    XCTAssertThrowsError(try publish(reviewDraft, author: 3, id: "peer-without-own-read"))
    let criterion: AgentMcpJSONObject = ["id": .string("value"), "requirement": .string("Document the value"),
      "verification": .string("documentary"), "status": .string("met"), "evidence_kind": .string("observed"),
      "evidence": .array([.string(delivery.sha256), .string(review.sha256), citation["evidence_id"] ?? .null]),
      "required_observations": .array([.object(["origin": .string("ios_native_tool"), "tool": .string("fixture.sensor")])]),
      "delivery": .object(ref(delivery)), "review": .object(ref(review))]
    let assessment: AgentMcpJSONObject = ["format": .string("galaxyssi.goal-assessment.v1"), "summary": .string("Reviewed"),
      "decision": .string("achieved"), "work": .array([]), "blockers": .array([]), "criteria": .array([.object(criterion)])]
    var request: AgentMcpJSONObject = ["mode": .string("check_goal_evidence"), "expected_revision": .int(1),
      "artifact": .string(AgentMcpJSONCodec.stringify(assessment))]
    XCTAssertThrowsError(try open().publishCollaborationMilestone(request, scope: scope(1)))
    let checked = try open().publishCollaborationMilestone(request, scope: scope(0))
    XCTAssertEqual(checked["status"], .string("criterion_evidence_verified"))
    XCTAssertEqual(checked["goal_accepted"], .bool(false))
    XCTAssertEqual(checked["criteria_sha256"], pinned["criteria_sha256"])
    let header: AgentMcpJSONObject = ["goal_sha256": checked["goal_sha256"] ?? .null,
      "criteria_sha256": checked["criteria_sha256"] ?? .null]
    let mapped: [AgentMcpJSONObject] = [
      ["id": .string("source-1"), "coverage_kind": .string("outcome"), "criterion_ids": .array([.string("value")]),
        "rationale": .string("The criterion covers the requested observation")],
      ["id": .string("source-2"), "coverage_kind": .string("constraint"), "criterion_ids": .array([]),
        "rationale": .string("Preserve the original units in the report")]
    ]
    let mappingBody = header.merging(["format": .string("galaxyssi.semantic-goal-mapping.v1"),
      "segments": .array(mapped.map(AgentMcpJSONValue.object))]) { _, new in new }
    let mapping = try publish(.init(id: "mapping", objectId: nil, baseRevision: 0, kind: .artifact,
      title: "Goal mapping", body: ["semantic_goal_mapping": .object(mappingBody)], parents: []), author: 2, id: "mapping")
    func coverageReview(_ verdict: String, segments: [AgentMcpJSONObject]) -> AgentCollaborationResearchDraft {
      let issues: AgentMcpJSONValue = .array(verdict == "supported" ? [] : [.string("Units not addressed")])
      let fields: AgentMcpJSONObject = ["verdict": .string(verdict), "unresolved": issues]
      let body = fields.merging(["target": .object(ref(mapping)), "rationale": .string("Checked the mapping"),
        "segments": .array(segments.map { .object($0.merging(fields) { _, new in new }) })]) { _, new in new }
      return .init(id: "coverage-review", objectId: nil, baseRevision: 0, kind: .acceptanceReview, title: "Coverage",
        body: ["semantic_coverage_review": .object(body)], parents: [mapping])
    }
    let semanticReview = try publish(coverageReview("supported", segments: mapped), author: 1, id: "coverage-review")
    let part: AgentMcpJSONObject = ["mapping": .object(ref(mapping)), "review": .object(ref(semanticReview))]
    let manifest = try publish(.init(id: "manifest", objectId: nil, baseRevision: 0, kind: .artifact,
      title: "Directory", body: ["semantic_goal_manifest": .object(header.merging([
        "format": .string("galaxyssi.semantic-goal-manifest.v1"), "parts": .array([.object(part)])
      ]) { _, new in new })], parents: [mapping, semanticReview]), author: 2, id: "manifest")
    func coverageStatus(_ coverage: AgentMcpJSONObject) throws -> AgentMcpJSONObject {
      var candidate = assessment
      candidate["goal_coverage"] = .object(coverage)
      var query = request
      query["artifact"] = .string(AgentMcpJSONCodec.stringify(candidate))
      return try open().publishCollaborationMilestone(query, scope: scope(0))
    }
    XCTAssertEqual(try coverageStatus(part)["status"], .string("goal_coverage_verified"))
    let manifestCheck = try coverageStatus(["manifest": .object(ref(manifest))])
    XCTAssertEqual(manifestCheck["status"], .string("goal_coverage_verified"))
    XCTAssertEqual(manifestCheck["goal_accepted"], .bool(false))
    XCTAssertEqual(try coverageStatus(["parts": .array([.object(part), .object(part)])])["status"],
      .string("goal_coverage_unverified"))
    let dissent = try publish(coverageReview("refuted", segments: mapped), author: 3, id: "dissent")
    XCTAssertEqual(try coverageStatus(part)["status"], .string("goal_coverage_unverified"))
    request["expected_revision"] = .int(2)
    XCTAssertThrowsError(try open().publishCollaborationMilestone(request, scope: scope(0)))
    request["expected_revision"] = .int(1)
    var candidate = assessment
    candidate["goal_coverage"] = .object(part)
    candidate["final_delivery"] = .object(ref(delivery))
    candidate["summary"] = .string("Do not substitute this model summary")
    let proposed = AgentMcpJSONCodec.stringify(candidate)
    XCTAssertThrowsError(try open().prepareFinalGoalDelivery(proposed, scope: scope(0)))
    var resolved = coverageReview("supported", segments: mapped)
    resolved.objectId = dissent.objectId
    resolved.baseRevision = dissent.revision
    _ = try publish(resolved, author: 3, id: "resolved-dissent")
    var wrongDelivery = candidate
    wrongDelivery["final_delivery"] = .object(ref(mapping))
    XCTAssertThrowsError(try open().prepareFinalGoalDelivery(AgentMcpJSONCodec.stringify(wrongDelivery), scope: scope(0)))
    XCTAssertThrowsError(try open().prepareFinalGoalDelivery(proposed, scope: scope(1)))
    let source = AgentCollaborationAcceptedDelivery.Source(profileID: "original-profile", messageID: UUID(),
      contactID: "original-contact", rosterDigest: "original-roster")
    let accepted = try open().prepareFinalGoalDelivery(proposed, scope: scope(0), source: source)
    XCTAssertEqual(accepted.reference, delivery)
    XCTAssertEqual(accepted.content, "Observed value 42")
    XCTAssertEqual(try open().acceptedGoalDelivery(scope: scope(0)), accepted)
    XCTAssertEqual(try open().prepareFinalGoalDelivery(proposed, scope: scope(0), source: source), accepted)
    XCTAssertThrowsError(try open().prepareFinalGoalDelivery(proposed, scope: scope(0)))
    XCTAssertThrowsError(try open().prepareFinalGoalDelivery(proposed + "\n", scope: scope(0), source: source))
    XCTAssertEqual(try open().acceptedGoalDeliveryRecoveryPage(after: "").deliveries, [accepted])
    XCTAssertEqual(open().goalCheckpoint(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId)?.phase, .accepted)
    artifact.objectId = delivery.objectId
    artifact.baseRevision = delivery.revision
    artifact.body["content"] = .string("Revised value")
    _ = try publish(artifact, author: 2, id: "delivery-v2")
    XCTAssertThrowsError(try history.recallCollaborationOriginal(read, scope: scope(1)))
    XCTAssertThrowsError(try open().publishCollaborationMilestone(request, scope: scope(0)))
    XCTAssertEqual(try open().acceptedGoalDelivery(scope: scope(0))?.content, "Observed value 42")
    let coordinator = scope(0)
    XCTAssertNotNil(open().applyReply(supervisorRunId: coordinator.runId, source: coordinator.sourceId,
      conversation: coordinator.conversationId, turn: coordinator.turnId, task: coordinator.sourceId,
      contact: team.members[0].agentId, content: accepted.content, success: true, now: 10))
    XCTAssertTrue(try open().acceptedGoalDeliveryRecoveryPage(after: "").deliveries.isEmpty)
  }

  func testSavedMemberDecodingPreservesRecruitmentProvenance() throws {
    var team = durableTeamSnapshot("provenance")
    team.members[1].recruitmentTemplateID = UUID()
    let restored = try JSONDecoder().decode(AgentTeamExecutionSnapshot.self, from: JSONEncoder().encode(team))
    XCTAssertEqual(restored.members[1].recruitmentTemplateID, team.members[1].recruitmentTemplateID)
    XCTAssertEqual(restored.reviewIdentity(restored.members[1].memberId),
      team.members[1].recruitmentTemplateID?.uuidString.lowercased())
    XCTAssertNil(restored.members[0].recruitmentTemplateID)
  }

  func testRecruitDirectoryProjectionUsesStableIdentityAndDoesNotRestoreDeletedMembers() throws {
    typealias Graph = AgentCollaborationLiveGraph
    let lead = AgentCollaborationRoster.Member(name: "Lead", resourceId: "lead")
    let template = AgentCollaborationRoster.Member(name: "Evidence", resourceId: "original-resource", modelId: "model")
    let roster = AgentCollaborationRoster(members: [lead, template], coordinatorId: lead.id)
    let request = Graph.RecruitmentRequest(id: "first", template_member: template.id.uuidString, role: "Evidence",
      scope: "Check the sample", reason: "Current task")
    let digest = Graph.Recruitment.templateDigest(template)
    let first = try XCTUnwrap(Graph.Recruitment(request, owner: "run-one", templateDigest: digest, directoryOwner: "group"))
    let second = try XCTUnwrap(Graph.Recruitment(request, owner: "run-two", templateDigest: digest, directoryOwner: "group"))
    XCTAssertNotEqual(first.identity, second.identity)
    XCTAssertEqual(first.directoryID, second.directoryID)
    let source = AgentCollaborationAcceptedDelivery.Source(profileID: "profile", messageID: UUID(),
      contactID: "hermes", rosterDigest: "roster")
    let projection = Graph.DirectoryProjection(source: source, recruits: [first, second])
    let updated = projection.applying(to: roster)
    let added = try XCTUnwrap(updated.members.last)
    XCTAssertEqual(updated.members.count, 3)
    XCTAssertEqual(added.id, first.directoryID)
    XCTAssertEqual(added.name, "Evidence 2")
    XCTAssertEqual(added.resourceId, template.resourceId)
    XCTAssertEqual(added.modelId, template.modelId)
    XCTAssertEqual(added.recruitmentTemplateID, template.id)
    XCTAssertTrue(added.mentionOnly)
    XCTAssertEqual(projection.applying(to: updated), updated)
    XCTAssertFalse(first.isReusable(added, originalTemplateID: template.id))
    var optedIn = updated
    optedIn.members[2].mentionOnly = false
    let reusable = optedIn.members[2]
    XCTAssertTrue(first.isReusable(reusable, originalTemplateID: template.id))
    let templateKey = template.id.uuidString
    let workerKey = reusable.id.uuidString
    let work = Graph.Work(id: "sample", member: "recruit:first", assignment: "Check the sample",
      depends_on: [], dependency_policy: nil, independent_review: nil)
    let expansion = Graph.WorkflowExpansion(format: "galaxyssi.work-expansion.v1", work: [.work(work)], recruit: [request])
    let graph = try XCTUnwrap(Graph().appending(expansion, authorizedMembers: [templateKey, workerKey],
      historicalAuthors: [:], settled: [:], recruitmentTemplates: [templateKey: digest], recruitmentOwner: "run-two",
      recruitmentDirectory: "group", resolveHistorical: { recruit, _ in
        recruit.isReusable(reusable, originalTemplateID: template.id) ? workerKey : nil
      }, resolve: { _ in nil }))
    let reused = try XCTUnwrap(graph.work.first?.recruitment)
    XCTAssertEqual(graph.work.first?.member, workerKey)
    XCTAssertEqual(reused.executionIdentity, workerKey.lowercased())
    XCTAssertTrue(reused.accepts(reusable, roster: optedIn))
    XCTAssertFalse(reused.accepts(added, roster: updated))
    var changedRole = reusable
    changedRole.role = "Different responsibility"
    XCTAssertFalse(reused.accepts(changedRole, roster: optedIn))
    var edited = updated
    edited.members[2].name = "Edited by the user"
    XCTAssertEqual(projection.applying(to: edited), edited)
    edited.members.removeLast()
    XCTAssertEqual(projection.applying(to: edited), edited)
    var changedTemplate = roster
    changedTemplate.members[1].modelId = "replacement"
    XCTAssertEqual(projection.applying(to: changedTemplate).members, changedTemplate.members)
    var team = durableTeamSnapshot("review-identity")
    team.members[1].instanceId = added.id.uuidString
    team.members[1].recruitmentTemplateID = template.id
    XCTAssertEqual(team.reviewIdentity(added.id.uuidString), team.reviewIdentity(template.id.uuidString))
  }

  func testScopedCoordinatorCanEstablishOnlyAnOpenImmutableGoalContract() throws {
    let suite = "established-contract-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    func open() -> AgentTeamExecutionHistoryStore {
      .init(defaults: defaults, secrets: secrets, executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    }
    let history = open()
    var team = durableTeamSnapshot("active-goal")
    team.goal = "Original user goal"
    team.members[0].dispatchCheckpoint = .dispatching
    team.members[1].dispatchCheckpoint = .accepted
    XCTAssertTrue(history.upsert(team))
    func scope(_ index: Int) -> AgentCollaborationToolEvidenceScope {
      let member = team.members[index]
      return .init(runId: team.supervisorRunId, conversationId: team.conversationId, turnId: team.taskId,
        memberId: member.memberId, sourceId: member.sourceMessageId)
    }
    let raw = """
    {"format":"galaxyssi.goal-assessment.v1","summary":"Retain original acceptance","decision":"continue",
     "criteria":[{"id":"sample","requirement":"Measure the sample","verification":"physical","status":"open","evidence":[]}],
     "work":[],"blockers":[]}
    """
    let mode = AgentCollaborationGoalAssessmentPolicy.establishContractMode
    let request: AgentMcpJSONObject = ["mode": .string(mode), "artifact": .string(raw)]
    XCTAssertThrowsError(try history.reserveGoalContinuation(after: raw, scope: scope(1)))
    XCTAssertEqual(try history.reserveGoalContinuation(after: raw, scope: scope(0))?["status"], .string("contract_missing"))
    XCTAssertNil(try open().reserveGoalContinuation(after: "The same goal, different model prose.", scope: scope(0)))
    var cloud = GalaxySSIContact.hermes()
    cloud.id = team.members[0].agentId
    cloud.deliveryMode = .cloudAPI
    cloud.cloudProvider = "Custom"
    cloud.selectedCloudModelId = "fixture-model"
    cloud.cloudModels = [.init(id: "fixture", displayName: "Fixture", provider: "Custom", modelId: "fixture-model",
      endpoint: "https://example.invalid/v1/chat/completions", apiStyle: .openAICompatible,
      keychainAccount: "fixture-key", updatedAt: Date(timeIntervalSince1970: 1))]
    let original = ChatMessage(contactId: "hermes", content: "Original request", isMine: true,
      conversationId: scope(0).conversationId, turnId: scope(0).turnId)
    let source = AgentCollaborationAcceptedDelivery.Source(profileID: "profile", messageID: original.id,
      contactID: original.contactId, rosterDigest: "roster")
    let route = try XCTUnwrap(AgentManualCloudBinding(contact: cloud, hadAttachments: false))
    let digest = AgentCollaborationCoordinatorRecovery.messageDigest(original)
    let coordinatorRecovery = AgentCollaborationCoordinatorRecovery(owner: scope(0), source: source, route: route,
      originalPrompt: "Original scoped coordinator prompt", process: "previous-process", cloudSourceDigest: digest)
    let rewritten = AgentCollaborationCoordinatorRecovery(owner: scope(0), source: source, route: route,
      originalPrompt: "Changed prompt", process: "previous-process", cloudSourceDigest: digest)
    var edited = original
    edited.content = "Edited request with the same message ID"
    var unpinned = coordinatorRecovery
    unpinned.cloudSourceDigest = nil
    XCTAssertTrue(coordinatorRecovery.matchesOriginal(original))
    XCTAssertFalse(coordinatorRecovery.matchesOriginal(edited))
    XCTAssertFalse(unpinned.matchesOriginal(original))
    XCTAssertThrowsError(try history.saveGoalCoordinatorRecovery(unpinned))
    try history.saveGoalCoordinatorRecovery(coordinatorRecovery)
    XCTAssertThrowsError(try open().saveGoalCoordinatorRecovery(rewritten))
    XCTAssertEqual(try open().acceptedGoalDeliveryRecoveryPage(after: "").coordinators, [coordinatorRecovery])
    XCTAssertNil(try open().claimGoalCoordinatorRecovery(rewritten))
    XCTAssertEqual(try open().claimGoalCoordinatorRecovery(coordinatorRecovery)?["revision"], .int(0))
    XCTAssertNil(try open().claimGoalCoordinatorRecovery(coordinatorRecovery))
    let check: AgentMcpJSONObject = ["mode": .string("validate_assessment"), "artifact": .string(raw)]
    XCTAssertTrue(AgentDesktopCollaborationPublicationWire.accepts(phase: mode, input: request))
    XCTAssertFalse(AgentDesktopCollaborationPublicationWire.permits(phase: mode, observer: true))
    XCTAssertTrue(AgentDesktopCollaborationPublicationWire.permits(phase: mode, observer: false))
    XCTAssertEqual(try history.publishCollaborationMilestone(check, scope: scope(0))["acceptance_contract_state"],
      .string("not_established"))
    XCTAssertThrowsError(try history.publishCollaborationMilestone(request, scope: scope(1)))
    var differentSource = scope(0)
    differentSource.sourceId = "stale-dispatch"
    XCTAssertThrowsError(try history.publishCollaborationMilestone(request, scope: differentSource))
    var closed = request
    closed["artifact"] = .string(raw.replacingOccurrences(of: "\"open\"", with: "\"met\""))
    let rejected = try history.publishCollaborationMilestone(closed, scope: scope(0))
    XCTAssertEqual(rejected["status"], .string("assessment_rejected"))
    XCTAssertEqual(rejected["assessment_repair"]?.objectValue?["contract_state"], .string("initial_criteria_pending"))
    XCTAssertEqual(rejected["assessment_repair"]?.objectValue?["field_path"], .string("$.criteria[0].status"))
    XCTAssertEqual(rejected["work_dispatched"], .bool(false))
    let oldRead = try XCTUnwrap(rejected["assessment_repair"]?.objectValue?["draft_read"]?.objectValue)
    var work = request
    let invalidWork = raw.replacingOccurrences(of: "\"work\":[]",
      with: "\"work\":[{\"id\":\"new\",\"member\":\"primary\",\"assignment\":\"" +
        String(repeating: "work-\u{1F9EA}", count: 800) + "\"}]")
    work["artifact"] = .string(invalidWork)
    let rejectedWork = try history.publishCollaborationMilestone(work, scope: scope(0))
    let repair = try XCTUnwrap(rejectedWork["assessment_repair"]?.objectValue)
    XCTAssertEqual(repair["field_path"], .string("$.work"))
    XCTAssertNil(repair["draft"])
    XCTAssertNil(open().goalCheckpoint(runId: team.supervisorRunId, conversationId: team.conversationId, turnId: team.taskId))
    var read = try XCTUnwrap(repair["draft_read"]?.objectValue)
    XCTAssertThrowsError(try open().publishCollaborationMilestone(read, scope: scope(1)))
    XCTAssertThrowsError(try open().publishCollaborationMilestone(oldRead, scope: scope(0)))
    let repairStore = open()
    var rebuilt = ""
    var offset: Int64? = 0
    var pages = 0
    while let position = offset, pages < 10 {
      read["offset"] = .int(position)
      let page = try repairStore.publishCollaborationMilestone(read, scope: scope(0))
      rebuilt += try XCTUnwrap(page["content"]?.strictStringValue)
      offset = page["next_offset"]?.intValue
      pages += 1
    }
    XCTAssertNil(offset)
    XCTAssertGreaterThan(pages, 1)
    XCTAssertEqual(rebuilt, invalidWork)
    let saved = try history.publishCollaborationMilestone(request, scope: scope(0))
    XCTAssertEqual(saved["replayed"], .bool(false))
    XCTAssertEqual(saved["goal_accepted"], .bool(false))
    XCTAssertEqual(saved["work_dispatched"], .bool(false))
    var replacement = team
    replacement.goal = "A different goal"
    replacement.updatedAtMillis += 1
    XCTAssertFalse(history.upsert(replacement))
    let reopened = open()
    XCTAssertEqual(try reopened.publishCollaborationMilestone(request, scope: scope(0))["replayed"], .bool(true))
    var changed = request
    changed["artifact"] = .string(raw.replacingOccurrences(of: "Measure the sample", with: "Replace the criterion"))
    let rejectedChange = try reopened.publishCollaborationMilestone(changed, scope: scope(0))
    XCTAssertEqual(rejectedChange["assessment_repair"]?.objectValue?["contract_state"], .string("established"))
    XCTAssertEqual(rejectedChange["assessment_repair"]?.objectValue?["field_path"], .string("$.criteria[0].requirement"))
    let criteria = try reopened.readPinnedCollaborationGoal(scope: scope(0), section: "criteria")
    XCTAssertEqual(criteria["sha256"], saved["criteria_sha256"])
    XCTAssertEqual(reopened.goalCheckpoint(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId)?.contract.first?.requirement, "Measure the sample")
    let originalAssignment = "  Measure the fixture\n"
    func work(_ requestID: String, id: String, member: String, expected: Int64,
              dependencies: [String] = [], terminal: Bool = false) -> AgentMcpJSONObject {
      let graph: AgentMcpJSONObject = ["format": .string("galaxyssi.work-expansion.v1"), "work": .array([.object([
        "id": .string(id), "member": .string(member), "assignment": .string(originalAssignment),
        "depends_on": .array(dependencies.map(AgentMcpJSONValue.string)),
        "dependency_policy": .string(terminal ? "terminal" : "success")
      ])])]
      return ["mode": .string(AgentCollaborationGoalAssessmentPolicy.appendWorkMode),
        "artifact": .string(AgentMcpJSONCodec.stringify(graph)), "milestone_id": .string(requestID),
        "expected_revision": .int(expected)]
    }
    let first = work("batch-1", id: "measure", member: scope(1).memberId, expected: 1)
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(first, scope: scope(1)))
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(
      work("unknown", id: "forbidden", member: "not-in-team", expected: 1), scope: scope(0)))
    let admitted = try reopened.publishCollaborationMilestone(first, scope: scope(0))
    XCTAssertEqual(admitted["revision"], .int(2))
    XCTAssertEqual(admitted["work_dispatched"], .bool(false))
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(
      work("batch-1", id: "changed", member: scope(1).memberId, expected: 1), scope: scope(0)))
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(
      work("stale", id: "stale-work", member: scope(1).memberId, expected: 1), scope: scope(0)))
    let followup = work("batch-2", id: "verify", member: scope(1).memberId, expected: 2, dependencies: ["measure"])
    XCTAssertEqual(try reopened.publishCollaborationMilestone(followup, scope: scope(0))["revision"], .int(3))
    XCTAssertEqual(try open().publishCollaborationMilestone(first, scope: scope(0))["replayed"], .bool(true))
    let latest = try XCTUnwrap(open().goalCheckpoint(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId))
    XCTAssertEqual(latest.liveGraph?.work.map(\.id), ["measure", "verify"])
    XCTAssertEqual(latest.liveGraph?.ready(settled: [:], active: []).map(\.id), ["measure"])
    let inventoryRequest: AgentMcpJSONObject = ["mode": .string(AgentCollaborationGoalAssessmentPolicy.workInventoryMode)]
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(inventoryRequest, scope: scope(1)))
    var foreign = scope(0)
    foreign.sourceId = "other-source"
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(inventoryRequest, scope: foreign))
    let interim = """
    {"format":"galaxyssi.research-artifact.v1","summary":"Private interim summary",
      "workspace":[{"id":"note","base_revision":0,"kind":"artifact","title":"Note",
      "body":{"content":"Private interim body"},"parents":[]}]}
    """
    let published = try reopened.publishCollaborationMilestone(["mode": .string("publish"),
      "milestone_id": .string("private-interim-id"), "artifact": .string(interim)], scope: scope(1))
    XCTAssertEqual(published["success"], .bool(true))
    let inventory = try open().publishCollaborationMilestone(inventoryRequest, scope: scope(0))
    XCTAssertEqual(inventory["revision"], .int(3))
    XCTAssertEqual(inventory["grants_access"], .bool(false))
    let milestone = try XCTUnwrap(inventory["members"]?.arrayValue?.first?.objectValue?["published_milestones"]?
      .arrayValue?.first?.objectValue)
    XCTAssertEqual(milestone["artifact_sha256"], published["artifact_sha256"])
    XCTAssertEqual(milestone["token"]?.strictStringValue?.count, 64)
    XCTAssertFalse(AgentMcpJSONCodec.stringify(inventory).contains("Private interim"))
    XCTAssertFalse(AgentMcpJSONCodec.stringify(inventory).contains("private-interim-id"))
    func item(_ id: String, _ snapshot: AgentMcpJSONObject) throws -> AgentMcpJSONObject {
      try XCTUnwrap(snapshot["items"]?.arrayValue?.compactMap(\.objectValue).first { $0["work_id"] == .string(id) })
    }
    XCTAssertEqual(try item("measure", inventory)["dependency_state"], .string("satisfied"))
    XCTAssertEqual(try item("verify", inventory)["status"], .string("unclaimed"))
    XCTAssertEqual(try item("verify", inventory)["dependency_state"], .string("waiting"))
    XCTAssertEqual(try item("verify", inventory)["waiting_for"]?.arrayValue?.first?.objectValue?["status"], .string("unclaimed"))
    let unfinished = try open().reserveGoalContinuation(after: raw, scope: scope(0))
    XCTAssertEqual(unfinished?["revision"], .int(3))
    XCTAssertEqual(unfinished?["work_counts"]?.objectValue?["unclaimed"], .int(2))
    XCTAssertEqual(unfinished?["work_inventory"]?.objectValue, inventory)
    XCTAssertNil(try open().reserveGoalContinuation(after: raw + "\n", scope: scope(0)))
    XCTAssertEqual(try open().readyGoalWork(scope: scope(0), excluding: [], limit: 3, now: 10), ["measure"])
    XCTAssertEqual(try open().readyGoalWork(scope: scope(0), excluding: ["measure"], limit: 3, now: 10), [])
    XCTAssertThrowsError(try open().readyGoalWork(scope: scope(1), excluding: [], limit: 3, now: 10))
    let measure = try XCTUnwrap(latest.liveGraph?.work.first)
    let verify = try XCTUnwrap(latest.liveGraph?.work.last)
    XCTAssertEqual(Data(measure.assignment.utf8), Data(originalAssignment.utf8))
    XCTAssertEqual(measure.dispatchAssignment, "Measure the fixture")
    XCTAssertThrowsError(try reopened.claimGoalWork(verify, scope: scope(0), now: 10))
    XCTAssertThrowsError(try reopened.claimGoalWork(measure, scope: scope(1), now: 10))
    let worker = AgentCollaborationGoalWorkRun.Target(kind: .cloud, resourceID: team.members[1].agentId, modelID: "selected-model")
    let wrongWorker = AgentCollaborationGoalWorkRun.Target(kind: .local, resourceID: "local-llm", modelID: "installed")
    XCTAssertThrowsError(try reopened.claimGoalWork(measure, scope: scope(0), target: wrongWorker, now: 10))
    let started = try reopened.claimGoalWork(measure, scope: scope(0), target: worker, now: 10)
    XCTAssertTrue(started.claimed)
    let runningInventory = try open().goalWorkInventory(scope: scope(0), now: 11)
    XCTAssertEqual(try item("measure", runningInventory)["status"], .string("running"))
    XCTAssertEqual(try item("measure", runningInventory)["result_settled"], .bool(false))
    XCTAssertEqual(try item("verify", runningInventory)["waiting_for"]?.arrayValue?.first?.objectValue?["status"], .string("running"))
    XCTAssertEqual(try open().readyGoalWork(scope: scope(0), excluding: [], limit: 3, now: 11), [])
    let duplicate = try open().claimGoalWork(measure, scope: scope(0), target: wrongWorker, now: 11)
    XCTAssertFalse(duplicate.claimed)
    XCTAssertEqual(duplicate.run.dispatchID, started.run.dispatchID)
    XCTAssertEqual(duplicate.run.target, worker)
    XCTAssertThrowsError(try reopened.claimGoalWork(verify, scope: scope(0), now: 11))
    let finished = try reopened.finishGoalWork(started.run, output: "Observed value", interrupted: false, now: 12)
    XCTAssertEqual(finished["status"], .string("succeeded"))
    XCTAssertEqual(finished["goal_accepted"], .bool(false))
    XCTAssertEqual(finished["target"], .object(worker.fields))
    let advanced = try open().reserveGoalContinuation(after: raw, scope: scope(0))
    XCTAssertEqual(advanced?["work_counts"]?.objectValue?["succeeded"], .int(1))
    let settledInventory = try open().goalWorkInventory(scope: scope(0), now: 13)
    XCTAssertEqual(try item("verify", settledInventory)["dependency_state"], .string("satisfied"))
    XCTAssertEqual(try item("verify", settledInventory)["status"], .string("unclaimed"))
    XCTAssertFalse(AgentMcpJSONCodec.stringify(settledInventory).contains("Observed value"))
    XCTAssertNil(try open().reserveGoalContinuation(after: raw, scope: scope(0)))
    let resumed = try open().claimGoalCoordinatorRecovery(coordinatorRecovery)
    XCTAssertEqual(resumed?["revision"], .int(3))
    XCTAssertEqual(resumed?["recent_work"]?.arrayValue?.first?.objectValue?["status"], .string("succeeded"))
    XCTAssertEqual(resumed?["work_inventory"]?.objectValue, settledInventory)
    XCTAssertNil(try open().claimGoalCoordinatorRecovery(coordinatorRecovery))
    XCTAssertEqual(try open().readyGoalWork(scope: scope(0), excluding: [], limit: 3, now: 13), ["verify"])
    XCTAssertThrowsError(try reopened.finishGoalWork(started.run, output: "Replace", interrupted: false, now: 13))
    let next = try reopened.claimGoalWork(verify, scope: scope(0), now: 14)
    XCTAssertTrue(next.claimed)
    XCTAssertEqual(next.dependencies.first?["output"], .string("Observed value"))
    let expired = try open().claimGoalWork(verify, scope: scope(0), now: 14 + AgentCollaborationGoalWorkRun.leaseMillis)
    XCTAssertFalse(expired.claimed)
    XCTAssertEqual(expired.run.visibleState(now: 14 + AgentCollaborationGoalWorkRun.leaseMillis), .interrupted)
    XCTAssertEqual(try open().readyGoalWork(scope: scope(0), excluding: [], limit: 3,
      now: 14 + AgentCollaborationGoalWorkRun.leaseMillis), [])
    XCTAssertThrowsError(try reopened.finishGoalWork(next.run, output: "Late", interrupted: false,
      now: 14 + AgentCollaborationGoalWorkRun.leaseMillis))
    let desktopRequest = work("batch-3", id: "desktop", member: scope(1).memberId, expected: 3)
    _ = try reopened.publishCollaborationMilestone(desktopRequest, scope: scope(0))
    let desktopWork = try reopened.goalWork("desktop", scope: scope(0)).0
    let desktopTarget = AgentCollaborationGoalWorkRun.Target(kind: .desktop, resourceID: team.members[1].agentId,
      modelID: "codex-model")
    let dispatch = try reopened.claimGoalWork(desktopWork, scope: scope(0), target: desktopTarget, now: 20).run
    let binding = AgentCollaborationGoalWorkRun.DesktopBinding(owner: scope(0), workID: dispatch.workID,
      dispatchID: dispatch.dispatchID, profileID: "profile", desktopID: "desktop", desktopFingerprint: "fingerprint",
      routeID: "route", contactID: desktopTarget.resourceID, agentID: "codex")
    try reopened.bindDesktopGoalWork(binding, now: 21)
    var packet: [String: Any] = ["client_route_id": "route", "contact_id": desktopTarget.resourceID,
      "source_message_id": dispatch.dispatchID, "task_id": dispatch.dispatchID, "agent_id": "codex",
      "conversation_id": team.conversationId, "turn_id": team.taskId, "execution_generation": 1]
    XCTAssertTrue(binding.matches(packet, desktop: "desktop", fingerprint: "fingerprint", route: "route", profile: "profile"))
    XCTAssertFalse(binding.matches(packet, desktop: "desktop", fingerprint: "changed", route: "route", profile: "profile"))
    packet["execution_generation"] = 2
    XCTAssertFalse(binding.matches(packet, desktop: "desktop", fingerprint: "fingerprint", route: "route", profile: "profile"))
    let secondOpen = open()
    XCTAssertEqual(try secondOpen.desktopGoalWorkBinding(dispatchID: dispatch.dispatchID, conversationID: team.conversationId), binding)
    let recovery = try XCTUnwrap(binding.recoveryBinding)
    XCTAssertTrue(recovery.isValid)
    XCTAssertEqual(recovery.sourceIdentity, dispatch.dispatchID)
    var transcriptBinding = recovery
    transcriptBinding.goalWork = nil
    XCTAssertNotEqual(recovery.key, transcriptBinding.key)
    let digest = String(repeating: "a", count: 64)
    XCTAssertTrue(try secondOpen.finishDesktopGoalWork(binding, output: "Original result",
      archiveDigest: digest, now: 22 + AgentCollaborationGoalWorkRun.leaseMillis))
    XCTAssertTrue(try open().finishDesktopGoalWork(binding, output: "Do not replace", archiveDigest: digest))
    XCTAssertFalse(try secondOpen.finishDesktopGoalWork(binding, output: "Wrong archive",
      archiveDigest: String(repeating: "b", count: 64)))
    XCTAssertFalse(try secondOpen.finishDesktopGoalWork(binding, output: "Late inline result"))
    XCTAssertEqual(try secondOpen.goalWork("desktop", scope: scope(0)).1?.desktopArchiveDigest, digest)
    XCTAssertEqual(try secondOpen.goalWork("desktop", scope: scope(0)).1?.output, "Original result")
    for (index, id) in ["recover-a", "recover-b", "recover-c", "recover-d"].enumerated() {
      _ = try reopened.publishCollaborationMilestone(work("batch-" + id, id: id, member: scope(1).memberId,
        expected: 4 + Int64(index), dependencies: ["verify"], terminal: true), scope: scope(0))
    }
    XCTAssertEqual(try open().readyGoalWork(scope: scope(0), excluding: [], limit: 99, now: 15), [])
    XCTAssertEqual(try open().readyGoalWork(scope: scope(0), excluding: [], limit: 99,
      now: 14 + AgentCollaborationGoalWorkRun.leaseMillis), ["recover-a", "recover-b", "recover-c"])
    let expiredInventory = try open().goalWorkInventory(scope: scope(0), now: 14 + AgentCollaborationGoalWorkRun.leaseMillis)
    XCTAssertEqual(try item("verify", expiredInventory)["status"], .string("interrupted"))
    XCTAssertEqual(try item("verify", expiredInventory)["result_settled"], .bool(false))
    XCTAssertEqual(try item("recover-a", expiredInventory)["dependency_state"], .string("satisfied"))
    XCTAssertEqual(try item("recover-a", expiredInventory)["unsuccessful_dependencies"], .array([.string("verify")]))
    XCTAssertEqual(try open().readyGoalWork(scope: scope(0), excluding: ["recover-a"], limit: 3,
      now: 14 + AgentCollaborationGoalWorkRun.leaseMillis), ["recover-b", "recover-c", "recover-d"])
    let template = scope(1).memberId
    let templates = [template: "authorized-template-digest"]
    func recruit(_ vacancy: String, workID: String, batch: String, revision: Int64, role: String = "Evidence collector",
                 independent: Bool = false) -> AgentMcpJSONObject {
      let request: AgentMcpJSONObject = ["id": .string(vacancy), "template_member": .string(template),
        "role": .string(role), "scope": .string("Collect a bounded observation"), "reason": .string("Existing scope")]
      let item: AgentMcpJSONObject = ["id": .string(workID), "member": .string("recruit:" + vacancy),
        "assignment": .string("Collect the observation"), "independent_review": .bool(independent),
        "depends_on": .array(independent ? [.string("measure")] : [])]
      let graph: AgentMcpJSONObject = ["format": .string("galaxyssi.work-expansion.v1"),
        "recruit": .array([.object(request)]), "work": .array([.object(item)])]
      return ["mode": .string("append_work"), "artifact": .string(AgentMcpJSONCodec.stringify(graph)),
        "milestone_id": .string(batch), "expected_revision": .int(revision)]
    }
    let recruitOne = recruit("vacancy-one", workID: "recruited-one", batch: "recruit-one", revision: 8)
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(recruitOne, scope: scope(0)))
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(
      recruit("independent", workID: "forbidden-review", batch: "forbidden-review", revision: 8, independent: true),
      scope: scope(0), recruitmentTemplates: templates))
    let recruited = try reopened.publishCollaborationMilestone(recruitOne, scope: scope(0), recruitmentTemplates: templates)
    let same = try open().publishCollaborationMilestone(recruitOne, scope: scope(0), recruitmentTemplates: templates)
    XCTAssertEqual(same["replayed"], .bool(true))
    let member = recruited["recruits"]?.objectValue?["recruit:vacancy-one"]?.objectValue
    XCTAssertEqual(member?["template_member_id"], .string(template))
    XCTAssertThrowsError(try open().publishCollaborationMilestone(
      recruit("vacancy-one", workID: "changed-role", batch: "recruit-change", revision: 9, role: "Other role"),
      scope: scope(0), recruitmentTemplates: templates))
    let second = try open().publishCollaborationMilestone(
      recruit("vacancy-two", workID: "recruited-two", batch: "recruit-two", revision: 9),
      scope: scope(0), recruitmentTemplates: templates)
    XCTAssertEqual(second["recruits"]?.objectValue?["recruit:vacancy-two"]?.objectValue, member)
    let firstWork = try open().goalWork("recruited-one", scope: scope(0)).0
    let secondWork = try open().goalWork("recruited-two", scope: scope(0)).0
    let firstRun = try open().claimGoalWork(firstWork, scope: scope(0), target: worker, now: 40).run
    XCTAssertEqual(firstRun.receipt(now: 41)["member_id"], member?["member_id"])
    XCTAssertThrowsError(try open().claimGoalWork(secondWork, scope: scope(0), target: worker, now: 41))
    _ = try open().finishGoalWork(firstRun, output: "First result", interrupted: false, now: 42)
    XCTAssertTrue(try open().claimGoalWork(secondWork, scope: scope(0), target: worker, now: 43).claimed)
    let blocker = AgentCollaborationGoalAssessmentPolicy.Blocker(id: "missing-instrument", kind: .resource,
      reason: "The instrument is unavailable", resume_when: "An authorized instrument is reachable", alternatives: nil)
    let resolutionBinding = try XCTUnwrap(AgentCollaborationGoalAssessmentPolicy.Resolution(blocker))
    var blocked = try JSONDecoder().decode(AgentCollaborationGoalAssessmentPolicy.Assessment.self, from: Data(raw.utf8))
    blocked.decision = .blocked
    blocked.blockers = [blocker]
    func encode(_ value: AgentCollaborationGoalAssessmentPolicy.Assessment) throws -> String {
      String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
    let pending = try encode(blocked)
    XCTAssertFalse(try open().planGoalBlockerResolution(after: pending, scope: scope(0), eligibleMembers: [scope(0).memberId]))
    XCTAssertTrue(try open().planGoalBlockerResolution(after: pending, scope: scope(0), eligibleMembers: [template]))
    XCTAssertFalse(try open().planGoalBlockerResolution(after: pending, scope: scope(0), eligibleMembers: [template]))
    let resolution = try open().goalWork(resolutionBinding.workID, scope: scope(0)).0
    XCTAssertEqual(resolution.blockerResolution, resolutionBinding)
    let job = try open().claimGoalWork(resolution, scope: scope(0), target: worker, now: 44).run
    let report = """
      {"format":"galaxyssi.resource-resolution-result.v1","alternatives":[
        {"option":"Shared instrument","status":"unavailable","result":"The authorized route is offline","evidence":["saved observation"]}]}
      """
    let result = try open().finishGoalWork(job, output: report, interrupted: false, now: 45)
    let reportDigest = try XCTUnwrap(result["output_sha256"]?.strictStringValue)
    let evidence = try XCTUnwrap(AgentCollaborationGoalAssessmentPolicy.ResolutionReport.checked(report))
    var checkedBlocker = blocker
    checkedBlocker.alternatives = [.init(option: "Shared instrument", status: .unavailable,
      result: "The authorized route is offline", evidence: ["saved observation", resolutionBinding.workID, reportDigest])]
    XCTAssertTrue(evidence.supportsWaiting(checkedBlocker, workID: resolutionBinding.workID, digest: reportDigest))
    XCTAssertFalse(evidence.supportsWaiting(checkedBlocker, workID: resolutionBinding.workID, digest: "invented"))
    let available = try XCTUnwrap(AgentCollaborationGoalAssessmentPolicy.ResolutionReport.checked(
      report.replacingOccurrences(of: "\"unavailable\"", with: "\"available\"")))
    XCTAssertFalse(available.supportsWaiting(checkedBlocker, workID: resolutionBinding.workID, digest: reportDigest))
    blocked.blockers = [checkedBlocker]
    let feedback = try open().reserveGoalContinuation(after: encode(blocked), scope: scope(0))
    XCTAssertEqual(feedback?["resource_resolution"]?.arrayValue?.first?.objectValue?["status"],
      .string("waiting_supported_by_saved_report"))
    reopened.removeResearchObjects(conversationId: team.conversationId)
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(first, scope: scope(0)))
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(request, scope: scope(0)))
  }

  func testTargetedWorkRepairRejectsInvalidLineageAndArchivesExactOriginWithoutImplicitReads() throws {
    typealias Policy = AgentCollaborationGoalAssessmentPolicy
    let suite = "work-repair-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore(), file = root.appendingPathComponent("history.sqlite3")
    func open() -> AgentTeamExecutionHistoryStore {
      .init(defaults: defaults, secrets: secrets, executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    }
    var team = durableTeamSnapshot("repair")
    team.goal = "Deliver the original measurement with its limitations"
    team.members[0].dispatchCheckpoint = .accepted
    XCTAssertTrue(open().upsert(team))
    let owner = team.members[0], worker = team.members[1]
    let scope = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId, memberId: owner.memberId, sourceId: owner.sourceMessageId)
    let contract = #"{"format":"galaxyssi.goal-assessment.v1","summary":"Bind","decision":"continue","criteria":[{"id":"measure","requirement":"Report limitations","verification":"documentary","status":"open","evidence":[]}],"work":[],"blockers":[]}"#
    XCTAssertEqual(try open().publishCollaborationMilestone(["mode": .string(Policy.establishContractMode),
      "artifact": .string(contract)], scope: scope)["revision"], .int(1))
    func row(_ id: String) -> AgentMcpJSONObject {
      ["id": .string(id), "member": .string(worker.memberId), "assignment": .string("Report only the omitted limitation"),
       "depends_on": .array([])]
    }
    func admission(_ id: String, revision: Int64, rows: [AgentMcpJSONObject]) -> AgentMcpJSONObject {
      let raw = AgentMcpJSONCodec.stringify(["format": .string("galaxyssi.work-expansion.v1"),
        "work": .array(rows.map(AgentMcpJSONValue.object))])
      return ["mode": .string(Policy.appendWorkMode), "artifact": .string(raw), "milestone_id": .string(id),
        "expected_revision": .int(revision)]
    }
    func submit(_ request: AgentMcpJSONObject) throws -> AgentMcpJSONObject {
      try open().publishCollaborationMilestone(request, scope: scope)
    }
    XCTAssertEqual(try submit(admission("initial", revision: 1, rows: [row("original")]))["revision"], .int(2))
    let original = try open().goalWork("original", scope: scope).0
    let originalRun = try open().claimGoalWork(original, scope: scope, now: 10)
    let reason = "Original delivery omitted the measurement limitation."
    let repair = row("repair").merging(["repair_of": .string("original"), "repair_reason": .string(reason)]) { _, new in new }
    let request = admission("repair-batch", revision: 2, rows: [repair])
    let inFlight = try submit(request)
    XCTAssertEqual(inFlight["failure"]?.objectValue?["field"], .string("repair_of"))
    XCTAssertEqual(inFlight["work_dispatched"], .bool(false))
    _ = try open().finishGoalWork(originalRun.run, output: "Unchanged original result", interrupted: false, now: 11)
    var malformed = repair
    malformed["id"] = .string("invalid")
    malformed["repair_reason"] = .null
    let rejected = try submit(admission("atomic", revision: 2, rows: [repair, malformed]))
    XCTAssertEqual(rejected["failure"]?.objectValue?["work_id"], .string("invalid"))
    XCTAssertEqual(rejected["failure"]?.objectValue?["field"], .string("repair_reason"))
    XCTAssertEqual(rejected["failure"]?.objectValue?["actual"], .string("null"))
    XCTAssertThrowsError(try open().goalWork("repair", scope: scope))
    XCTAssertEqual(try submit(admission("duplicate", revision: 2, rows: [row("original")]))["failure"]?.objectValue?["code"],
      .string("completed_dispatch_reused"))
    XCTAssertEqual(try submit(request)["revision"], .int(3))
    XCTAssertEqual(try submit(request)["replayed"], .bool(true))
    let inventory = try open().goalWorkInventory(scope: scope, now: 12)
    let visible = try XCTUnwrap(inventory["items"]?.arrayValue?.compactMap(\.objectValue)
      .first { $0["work_id"] == .string("repair") })
    XCTAssertEqual(visible["repair_of"], .string("original"))
    XCTAssertEqual(visible["repair_reason"], .string(reason))
    XCTAssertEqual(try open().readyGoalWork(scope: scope, excluding: [], limit: 3, now: 12), ["repair"])
    let saved = try open().goalWork("repair", scope: scope).0
    let claim = try open().claimGoalWork(saved, scope: scope, now: 12)
    XCTAssertTrue(claim.claimed)
    XCTAssertTrue(claim.dependencies.isEmpty, "Repair lineage alone cannot grant access to the original output")
    let result = try open().finishGoalWork(claim.run, output: "Added limitation only", interrupted: false, now: 13)
    XCTAssertEqual(result["repair_reason"], .string(reason))
    var changed = saved
    changed.repair_reason = "Different identity"
    XCTAssertThrowsError(try open().claimGoalWork(changed, scope: scope, now: 14))
    XCTAssertFalse(try open().claimGoalWork(saved, scope: scope, now: 14).claimed)
    let savedOriginal = try XCTUnwrap(open().goalWork("original", scope: scope).1)
    XCTAssertEqual(savedOriginal.output, "Unchanged original result")
    XCTAssertNil(savedOriginal.repair)
    let archive = try XCTUnwrap(open().goalWork("repair", scope: scope).1)
    XCTAssertEqual(archive.repair?.repair_of, "original")
    XCTAssertEqual(archive.output, "Added limitation only")
  }

  func testCancelledLocalGoalWorkDoesNotStartQueuedInference() async {
    let cancellation = AgentModelToolLoopCancellationSource()
    cancellation.cancel()
    do {
      _ = try await LocalModelInferenceRuntime.shared.generateAsync(profile: LocalModelRuntimeSettings.selectedProfile(),
        systemPrompt: "", userPrompt: "Must not execute", cancellation: cancellation.token)
      XCTFail("Cancelled work must not start inference")
    } catch is CancellationError {
      return
    } catch {
      XCTFail("Expected cancellation before model preflight, got \(error)")
    }
  }

  func testQualifiedVerificationRouteRequiresOpenUnclaimedCriteriaAndPersistsExactAmendment() throws {
    typealias Policy = AgentCollaborationGoalAssessmentPolicy
    let suite = "verification-route-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
    let secrets = InMemorySecretStore(), file = folder.appendingPathComponent("history.sqlite3")
    func open() -> AgentTeamExecutionHistoryStore {
      .init(defaults: defaults, secrets: secrets, executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    }
    var team = durableTeamSnapshot("verification")
    team.goal = "Evaluate only the supplied numeric cases"
    team.members[0].dispatchCheckpoint = .accepted
    team.members[1].dispatchCheckpoint = .accepted
    XCTAssertTrue(open().upsert(team))
    func scope(_ index: Int) -> AgentCollaborationToolEvidenceScope {
      .init(runId: team.supervisorRunId, conversationId: team.conversationId, turnId: team.taskId,
        memberId: team.members[index].memberId, sourceId: team.members[index].sourceMessageId)
    }
    func checkpoint(revision: Int64? = nil) throws -> AgentCollaborationGoalCheckpoint {
      try XCTUnwrap(open().goalCheckpoint(runId: team.supervisorRunId, conversationId: team.conversationId,
        turnId: team.taskId, revision: revision))
    }
    let numeric: AgentMcpJSONObject = ["id": .string("cases"),
      "requirement": .string(AgentCollaborationNumericTrial.requirement), "verification": .string("computational"),
      "status": .string("open"), "evidence": .array([]), "required_observations": .array([.object([
        "origin": .string("desktop_codex_tool"), "tool": .string("codex.commandExecution")
      ])])]
    let documentary: AgentMcpJSONObject = ["id": .string("summary"), "requirement": .string("Explain limitations"),
      "verification": .string("documentary"), "status": .string("open"), "evidence": .array([])]
    func artifact(_ first: AgentMcpJSONObject, _ second: AgentMcpJSONObject? = nil, decision: String = "continue") -> AgentMcpJSONValue {
      .string(AgentMcpJSONCodec.stringify(["format": .string("galaxyssi.goal-assessment.v1"), "summary": .string("Bind the cases"),
        "decision": .string(decision), "criteria": .array([.object(first), .object(second ?? documentary)]),
        "work": .array([]), "blockers": .array([])]))
    }
    let registered = try open().publishCollaborationMilestone(["mode": .string(Policy.establishContractMode),
      "artifact": artifact(numeric)], scope: scope(0))
    XCTAssertEqual(registered["revision"], .int(1))
    let oldHash = try XCTUnwrap(registered["criteria_sha256"]?.strictStringValue)
    let before = try checkpoint()
    var ready = numeric
    ready["evidence_kind"] = .string("observed")
    ready["validator"] = .object(["id": .string(AgentCollaborationNumericTrial.validatorId),
      "variables": .array([.string("x")]), "cases": .array([.object([
        "id": .string("case"), "input": .object(["x": .int(3)]), "expected": .int(3), "absolute_tolerance": .int(0)
      ])])])
    func request(_ value: AgentMcpJSONValue, expected: Int64 = 1) -> AgentMcpJSONObject {
      ["mode": .string(Policy.establishVerificationMode), "expected_revision": .int(expected), "artifact": value]
    }
    let valid = request(artifact(ready))
    XCTAssertThrowsError(try open().publishCollaborationMilestone(valid, scope: scope(1)))
    XCTAssertEqual(try open().publishCollaborationMilestone(valid, scope: scope(0))["status"],
      .string("verification_work_in_flight"))
    team.members[1].status = .succeeded
    team.updatedAtMillis += 1
    XCTAssertTrue(open().upsert(team))
    var invalidSecond = documentary
    invalidSecond["requirement"] = .string("Omit limitations")
    let invalid: [AgentMcpJSONValue] = [artifact(ready, invalidSecond), artifact(ready, decision: "achieved"),
      artifact(ready.merging(["required_observations": .array([])]) { _, next in next }),
      artifact(ready.merging(["evidence": .array([.string("claimed")])]) { _, next in next }),
      artifact(ready.merging(["review": .null]) { _, next in next }),
      artifact(ready.merging(["validator": .object(["id": .string("model_claimed_pass")])]) { _, next in next })]
    for draft in invalid {
      XCTAssertEqual(try open().publishCollaborationMilestone(request(draft), scope: scope(0))["status"],
        .string("verification_route_rejected"))
      XCTAssertEqual(try checkpoint(), before)
    }
    let bound = try open().publishCollaborationMilestone(valid, scope: scope(0))
    XCTAssertEqual(bound["revision"], .int(2))
    XCTAssertEqual(bound["status"], .string("verification_route_established"))
    XCTAssertEqual(bound["goal_accepted"], .bool(false))
    XCTAssertEqual(bound["work_dispatched"], .bool(false))
    XCTAssertEqual(try checkpoint(revision: 1), before)
    let current = try checkpoint()
    XCTAssertEqual(current.contract.first?.validator, ready["validator"]?.objectValue)
    XCTAssertEqual(current.contract.first?.required_observations, before.contract.first?.required_observations)
    XCTAssertEqual(current.liveGraph, before.liveGraph)
    XCTAssertThrowsError(try open().readPinnedCollaborationGoal(scope: scope(0), section: "criteria", expectedHash: oldHash))
    XCTAssertEqual(try open().readPinnedCollaborationGoal(scope: scope(0), section: "criteria")["sha256"], bound["criteria_sha256"])
    XCTAssertEqual(try open().publishCollaborationMilestone(valid, scope: scope(0))["replayed"], .bool(true))
    XCTAssertEqual(try open().publishCollaborationMilestone(request(artifact(ready), expected: 2), scope: scope(0))["status"],
      .string("verification_route_rejected"))
    var advanced = current
    advanced.revision = 3
    advanced.completedWorkIds = ["completed-fixture"]
    XCTAssertTrue(open().advanceGoalCheckpoint(advanced, expectedRevision: 2))
    XCTAssertEqual(try checkpoint().contract, current.contract)
  }

  func testNativeReleaseHistoryPagesOnlyVisibleExactVersionAndPreservesOriginalReceipts() throws {
    typealias History = AgentCollaborationNativeReleaseHistory
    let suite = "native-release-history-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite")
    func open() -> AgentTeamExecutionHistoryStore {
      AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
        executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    }
    let history = open()
    let team = durableTeamSnapshot("history-reader")
    XCTAssertTrue(history.upsert(team))
    func scope(member index: Int) -> AgentCollaborationToolEvidenceScope {
      let member = team.members[index]
      return .init(runId: team.supervisorRunId, conversationId: team.conversationId, turnId: team.taskId,
        memberId: member.memberId, sourceId: member.sourceMessageId)
    }
    let reader = scope(member: 0)
    let other = scope(member: 1)
    let release = AgentCollaborationResearchReference(objectId: String(repeating: "a", count: 64),
      revision: 2, sha256: String(repeating: "b", count: 64))
    let earlier = AgentCollaborationResearchReference(objectId: release.objectId,
      revision: 1, sha256: String(repeating: "c", count: 64))
    let database = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    for version in [release, earlier] {
      let saved: AgentMcpJSONObject = ["reference": .object(History.fields(version)), "runId": .string("older"),
        "turnId": .string("older-turn"), "authorId": .string("author"), "sourceId": .string("older-source"),
        "draft": .object(["kind": .string("tool_release")]),
        "testedToolRelease": .object(["state": .string("eligible_for_scoped_tool_execution")])]
      try database.insertResearchRecord(saved, conversationId: reader.conversationId,
        key: "object:" + version.objectId, revision: version.revision)
    }
    func record(_ id: String, ref: AgentCollaborationResearchReference,
                owner: AgentCollaborationToolEvidenceScope, replayed: Bool = false,
                status: AgentNativeToolResultStatus = .succeeded) throws -> AgentMcpJSONObject {
      let result = AgentNativeToolResult(status: status, output: ["stdout": .string("private output")], message: "",
        receipt: .init(invocationId: id, startedAtEpochMillis: 1, finishedAtEpochMillis: 2,
          durationMillis: 1, status: status, inputSha256: "input", outputSha256: "output",
          replayed: replayed, originalInvocationId: replayed ? "initial" : nil),
        provenance: .init(toolId: AgentIOSOnDeviceRuntimeNativeToolCatalog.execute, toolVersion: "1",
          location: .phone, executorId: "test", contractVersion: "1"))
      return try history.recordNativeObservation(.init(runId: owner.runId, conversationId: owner.conversationId,
        turnId: owner.turnId, memberId: owner.memberId, sourceId: owner.sourceId,
        input: ["mode": .string("run"), "tool_release": .object(History.fields(ref)),
          "parameters": .object(["value": .string("private input")])], result: result))
    }
    for i in 0..<21 { _ = try record("unrelated-\(i)", ref: earlier, owner: reader) }
    _ = try record("hidden", ref: release, owner: other)
    let initial = try record("initial", ref: release, owner: reader)
    let replay = try record("replay", ref: release, owner: reader, replayed: true)
    let failed = try record("failed", ref: release, owner: reader, status: .failed)
    var query = History.fields(release)
    query["mode"] = .string(History.mode)
    let reopened = open()
    let first = try reopened.recallCollaborationOriginal(query, scope: reader)
    let cursor = try XCTUnwrap(first["next_cursor"]?.strictStringValue)
    query["cursor"] = .string(cursor)
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(query, scope: other))
    var wrongVersion = query.merging(History.fields(earlier)) { _, new in new }
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(wrongVersion, scope: reader))
    wrongVersion["cursor"] = nil
    wrongVersion["sha256"] = .string(release.sha256)
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(wrongVersion, scope: reader))
    let second = try reopened.recallCollaborationOriginal(query, scope: reader)
    XCTAssertEqual(second["next_cursor"], .null)
    let records = ((first["records"]?.arrayValue ?? []) + (second["records"]?.arrayValue ?? [])).compactMap(\.objectValue)
    XCTAssertEqual(Set(records.map { $0.string("evidence_id") }), Set([initial, replay, failed].map { $0.string("evidence_id") }))
    let replayRow = try XCTUnwrap(records.first(where: { $0["replayed"] == .bool(true) }))
    XCTAssertEqual(replayRow["original_invocation_id"], .string("initial"))
    XCTAssertEqual(replayRow["read_original"]?.objectValue?["sha256"], replay["sha256"])
    XCTAssertEqual(records.first(where: { $0["evidence_id"] == failed["evidence_id"] })?["native_status"], .string("failed"))
    XCTAssertFalse(AgentMcpJSONCodec.stringify(second).contains("private input"))
    XCTAssertFalse(AgentMcpJSONCodec.stringify(first).contains("private output"))
    reopened.removeResearchObjects(conversationId: reader.conversationId)
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(query, scope: reader))
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

  func testSavedTeamCompletesRegardlessOfObserverReplyOrder() throws {
    for order in [["lead", "reviewer"], ["reviewer", "lead"]] {
      var saved = AgentTeamExecutionSnapshot(supervisorRunId: "run", teamId: "team",
        conversationId: "conversation", taskId: "turn", primaryAgentId: "lead", state: .running,
        members: [
          AgentTeamMemberSnapshot(agentId: "lead", deliveryMode: .respond, sourceMessageId: "lead-request"),
          AgentTeamMemberSnapshot(agentId: "reviewer", deliveryMode: .observe, sourceMessageId: "reviewer-request")
        ])
      for (index, agent) in order.enumerated() {
        saved = try XCTUnwrap(AgentSavedTeamReplyPolicy.apply(to: saved,
          source: agent + "-request", conversation: "conversation", turn: "turn",
          task: agent + "-request", contact: agent,
          content: agent == "lead" ? "Primary answer" : "Observation",
          success: true, now: Int64(index + 1)))
        XCTAssertEqual(saved.state, index == 0 ? .running : .succeeded)
      }
      XCTAssertEqual(saved.finalOutput, "Primary answer")
      XCTAssertTrue(saved.members.allSatisfy { $0.status == .succeeded })
      XCTAssertNil(AgentSavedTeamReplyPolicy.apply(to: saved, source: "reviewer-request",
        conversation: "conversation", turn: "turn", task: "reviewer-request", contact: "reviewer",
        content: "Late replacement", success: true, now: 100))
      XCTAssertEqual(saved.finalOutput, "Primary answer")
    }
  }

  func testSavedTeamAllowsEmptyObservationButRequiresPrimaryAnswer() throws {
    let saved = AgentTeamExecutionSnapshot(supervisorRunId: "run", teamId: "team",
      conversationId: "conversation", taskId: "turn", primaryAgentId: "lead", state: .running,
      members: [
        AgentTeamMemberSnapshot(agentId: "lead", deliveryMode: .respond, sourceMessageId: "primary"),
        AgentTeamMemberSnapshot(agentId: "reviewer", deliveryMode: .observe, sourceMessageId: "observer")
      ])
    XCTAssertNil(AgentSavedTeamReplyPolicy.apply(to: saved, source: "primary",
      conversation: "conversation", turn: "turn", task: "primary", contact: "lead",
      content: " \n", success: true, now: 1))
    let observed = try XCTUnwrap(AgentSavedTeamReplyPolicy.apply(to: saved, source: "observer",
      conversation: "conversation", turn: "turn", task: "observer", contact: "reviewer",
      content: "", success: true, now: 1))
    XCTAssertEqual(observed.members[1].status, .succeeded)
    let completed = try XCTUnwrap(AgentSavedTeamReplyPolicy.apply(to: observed, source: "primary",
      conversation: "conversation", turn: "turn", task: "primary", contact: "lead",
      content: "Answer", success: true, now: 2))
    XCTAssertEqual(completed.state, .succeeded)
    XCTAssertEqual(completed.finalOutput, "Answer")
  }

  func testInterruptedTeamAcceptsOnlyOriginalLateResultsWithoutReplacingFinalStates() throws {
    let saved = AgentTeamExecutionSnapshot(supervisorRunId: "original", teamId: "team",
      conversationId: "conversation", taskId: "turn", primaryAgentId: "lead", state: .interrupted,
      members: [
        AgentTeamMemberSnapshot(agentId: "lead", deliveryMode: .respond,
          status: .interrupted, sourceMessageId: "primary"),
        AgentTeamMemberSnapshot(agentId: "reviewer", deliveryMode: .observe,
          status: .interrupted, sourceMessageId: "observer")
      ])
    XCTAssertNil(AgentSavedTeamReplyPolicy.apply(to: saved, source: "replacement",
      conversation: "conversation", turn: "turn", task: "replacement", contact: "lead",
      content: "Foreign", success: true, now: 1))
    let primary = try XCTUnwrap(AgentSavedTeamReplyPolicy.apply(to: saved, source: "primary",
      conversation: "conversation", turn: "turn", task: "primary", contact: "lead",
      content: "Original answer", success: true, now: 2))
    XCTAssertEqual(primary.state, .interrupted)
    let completed = try XCTUnwrap(AgentSavedTeamReplyPolicy.apply(to: primary, source: "observer",
      conversation: "conversation", turn: "turn", task: "observer", contact: "reviewer",
      content: "Observation", success: true, now: 3))
    XCTAssertEqual(completed.state, .succeeded)
    XCTAssertEqual(completed.finalOutput, "Original answer")
    for state in [AgentTeamExecutionState.cancelled, .failed, .succeeded, .completedWithFailures] {
      var terminal = saved
      terminal.state = state
      XCTAssertNil(AgentSavedTeamReplyPolicy.apply(to: terminal, source: "primary",
        conversation: "conversation", turn: "turn", task: "primary", contact: "lead",
        content: "Late overwrite", success: true, now: 4))
    }
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
    let historyRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: historyRoot) }
    let sink = AgentConnectorTeamCompletionSink(responseStore: responses,
      historyStore: AgentTeamExecutionHistoryStore(defaults: defaults, secrets: InMemorySecretStore(), executionStore: store,
        fileURL: historyRoot.appendingPathComponent("teams.sqlite3")))
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

  func testArtifactOnlyPrimaryReplySurvivesTheCheckpointAndFinalDelivery() throws {
    let image = AgentRichBlock(id: "primary-image", type: .image, uri: "https://example.com/result.png")
    let file = AgentRichBlock(id: "primary-file", type: .file, uri: "https://example.com/result.zip")
    let observer = AgentRichBlock(id: "observer-file", type: .file, uri: "https://example.com/observer.zip")
    let snapshot = AgentTeamExecutionSnapshot(supervisorRunId: UUID().uuidString, teamId: "team",
      conversationId: "conversation", taskId: "turn", primaryAgentId: "lead", state: .waitingResponse,
      members: [
        AgentTeamMemberSnapshot(agentId: "lead", deliveryMode: .respond, status: .running, sourceMessageId: "source"),
        AgentTeamMemberSnapshot(agentId: "observer", deliveryMode: .observe, status: .succeeded,
          richOutputJson: AgentRichContentCodec.encode([observer]))
      ])
    let settled = try XCTUnwrap(AgentSavedTeamReplyPolicy.apply(to: snapshot, source: "source",
      conversation: "conversation", turn: "turn", task: "source", contact: "lead", content: "",
      richOutputJson: AgentRichContentCodec.encode([image, file]), success: true, now: 1_000))
    XCTAssertEqual(settled.state, .succeeded)
    let restored = try JSONDecoder().decode(AgentTeamExecutionSnapshot.self, from: JSONEncoder().encode(settled))
    let responses = InMemoryAgentConnectorResponseStore()
    let sink = AgentConnectorTeamCompletionSink(responseStore: responses)
    defer { sink.remove(supervisorRunId: restored.supervisorRunId) }
    XCTAssertTrue(sink.publish(restored))
    XCTAssertFalse(sink.publish(restored))
    let response = try XCTUnwrap(responses.pending().first)
    XCTAssertTrue(response.success)
    XCTAssertEqual(AgentRichContentCodec.decode(response.richOutputJson).map(\.id), ["primary-image", "primary-file"])
    let continued = AgentTeamArtifactOutput.appendingArtifacts(response.richOutputJson,
      to: "Completed.", richOutput: AgentRichContentCodec.encode([image]))
    XCTAssertEqual(AgentRichContentCodec.decode(continued).filter(\.isArtifactBlock).map(\.id),
      ["primary-image", "primary-file"])
  }

  func testAgentTeamCompletionRetriesWhenHistoryEncryptionFails() throws {
    let suite = "team-completion-write-failure-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let historyRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: historyRoot) }
    let secrets = TeamCompletionFailingSecrets()
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: historyRoot.appendingPathComponent("teams.sqlite3"))
    let responses = InMemoryAgentConnectorResponseStore()
    let ledger = AgentTeamCompletionDeliveryLedger()
    let sink = AgentConnectorTeamCompletionSink(responseStore: responses, ledger: ledger,
      historyStore: history)
    let snapshot = AgentTeamExecutionSnapshot(supervisorRunId: "retry-history",
      teamId: "team", conversationId: "conversation", taskId: "turn",
      primaryAgentId: "lead", state: .succeeded, finalOutput: "Answer")

    XCTAssertFalse(sink.publish(snapshot))
    XCTAssertTrue(responses.pending().isEmpty)
    XCTAssertTrue(ledger.snapshot().isEmpty)
    XCTAssertNil(history.snapshot(supervisorRunId: snapshot.supervisorRunId))

    secrets.rejectWrites = false
    XCTAssertTrue(sink.publish(snapshot))
    XCTAssertEqual(responses.pending().count, 1)
    XCTAssertEqual(history.snapshot(supervisorRunId: snapshot.supervisorRunId), snapshot)
    XCTAssertFalse(sink.publish(snapshot))
    XCTAssertEqual(responses.pending().count, 1)
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

private final class TeamCompletionFailingSecrets: GalaxySSISecretStore {
  var rejectWrites = true
  private let backing = InMemorySecretStore()

  func setString(_ value: String, account: String) throws {
    if rejectWrites { throw GalaxySSIError.invalidPayload("Injected history key write failure") }
    try backing.setString(value, account: account)
  }

  func string(account: String) -> String? { backing.string(account: account) }
  func delete(account: String) { backing.delete(account: account) }
}

private actor OrderedSubagentAdmissionFixture: AgentSubagentEventHook {
  private(set) var admitted: [String] = []
  private var released = false
  private var waiting: CheckedContinuation<Void, Never>?

  func append(_ event: AgentSubagentEvent) async throws {
    if event.kind == AgentSubagentEventKinds.childRunning { admitted.append(event.childId) }
  }

  func waitForRelease() async {
    if !released { await withCheckedContinuation { waiting = $0 } }
  }

  func release() {
    released = true
    waiting?.resume()
    waiting = nil
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
