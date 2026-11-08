import CryptoKit
import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
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

  func testDesktopMilestonePhaseCannotSwitchReadIntoPublication() {
    let wire = AgentDesktopCollaborationPublicationWire.self
    XCTAssertTrue(wire.accepts(phase: "publish", input: ["mode": .string("publish")]))
    XCTAssertTrue(wire.accepts(phase: "receipt", input: ["mode": .string("receipt")]))
    XCTAssertFalse(wire.accepts(phase: "receipt", input: ["mode": .string("publish")]))
    XCTAssertFalse(wire.accepts(phase: "read", input: ["mode": .string("read")]))
    XCTAssertTrue(wire.accepts(phase: "validate_assessment", input: ["mode": .string("validate_assessment")]))
    for phase in ["publish", "status", "receipt", "list"] {
      XCTAssertTrue(wire.permits(phase: phase, observer: true))
      XCTAssertFalse(wire.permits(phase: phase, observer: false))
    }
    XCTAssertTrue(wire.permits(phase: "validate_assessment", observer: false))
  }

  func testAssessmentPreflightIdentifiesFieldAndDoesNotClaimAcceptance() {
    let raw = """
    {"format":"galaxyssi.goal-assessment.v1","summary":"Draft","decision":"continue","work":[],"blockers":[],
      "criteria":[{"id":"one","requirement":"Check source","verification":"documentary","status":"open","evidence":[],
      "required_observations":[{"origin":"invented","tool":"search"}]}]}
    """
    let invalid = AgentCollaborationGoalAssessmentPolicy.preflight(raw, establishedContract: false)
    XCTAssertEqual(invalid["field_path"], .string("$.criteria[0].required_observations[0].origin"))
    XCTAssertEqual(invalid["json_valid"], .bool(true))
    XCTAssertEqual(invalid["acceptance_contract_state"], .string("not_established"))
    let valid = AgentCollaborationGoalAssessmentPolicy.preflight(
      raw.replacingOccurrences(of: "invented", with: "ios_cloud_tool"), establishedContract: true)
    XCTAssertEqual(valid["status"], .string("valid_structure"))
    XCTAssertEqual(valid["validation_scope"], .string("structure_only_not_admission_or_acceptance"))
    XCTAssertEqual(valid["acceptance_contract_state"], .string("established"))
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
    changed["artifact"] = .string(artifact + " ")
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
    let team = durableTeamSnapshot("audit")
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
      provider: .openAICompatible, requestedModel: nil, startedAtMillis: 3, route: .compatibility)
    try reopened.admitCollaborationModelCall(interrupted)
    let firstPage = try history.collaborationModelAuditPage(conversationId: scope.conversationId, limit: 1)
    let cursor = try XCTUnwrap(firstPage.next)
    let secondPage = try history.collaborationModelAuditPage(conversationId: scope.conversationId, after: cursor, limit: 1)
    let entries = firstPage.entries + secondPage.entries
    XCTAssertEqual(Set(entries.map { $0.admission.id }), [admission.id, interrupted.id])
    XCTAssertEqual(entries.first(where: { $0.admission.id == admission.id })?.settlement, completed)
    XCTAssertNil(entries.first(where: { $0.admission.id == interrupted.id })?.settlement)
    XCTAssertEqual(entries.first(where: { $0.admission.id == interrupted.id })?.admission.route, .compatibility)
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
    XCTAssertFalse(referenced.text.contains(String(repeating: "G", count: 64)))
    XCTAssertThrowsError(try dispatch(recall: false)) { error in
      XCTAssertTrue(error.localizedDescription.contains("model_dispatched=false"))
    }
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
    computation["model"] = .object(["op": .string("shell"), "args": .array([])])
    trial["computation"] = .object(computation)
    XCTAssertNil(AgentCollaborationNumericTrial.evaluate(trial))
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
