import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
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
    team.members[1].dispatchCheckpoint = .accepted
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
    var acceptanceSelector = selector
    acceptanceSelector["mode"] = .string("native_evidence")
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(acceptanceSelector, scope: reader,
      evidenceRead: .desktopConfirm(contentHash: deliveredHash)))
    let acceptancePage = try reopened.recallCollaborationOriginal(acceptanceSelector, scope: reader)
    XCTAssertEqual(acceptancePage.string("content"), first.string("content"))
    XCTAssertEqual(acceptancePage["host_read_coverage"]?.objectValue?["first_missing_offset"], .int(2_000))
    XCTAssertEqual(acceptancePage["source_reference"]?.objectValue?["status"], .string("failed"))
    let joined = Data((first.string("content") + middle.string("content") + last.string("content")).utf8)
    let original = try JSONDecoder().decode(AgentCollaborationNativeToolObservation.self, from: joined)
    XCTAssertEqual(original.input, observation.input)
    XCTAssertEqual(original.result, observation.result)
    var later = durableTeamSnapshot("native-later-turn")
    later.taskId = "later-turn"
    later.members[0].dispatchCheckpoint = .accepted
    XCTAssertTrue(reopened.upsert(later))
    let laterPage = try reopened.recallCollaborationOriginal(selector, scope: scope(later, index: 0))
    XCTAssertEqual(laterPage["source_reference"], first["source_reference"])
    XCTAssertEqual(laterPage["host_read_coverage"]?.objectValue?["complete"], .bool(false))
    XCTAssertThrowsError(try reopened.recallCollaborationOriginal(acceptanceSelector, scope: scope(later, index: 0)))
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
    let withChannel = mixed.replacingOccurrences(of: "\"inputs\":{},\"roles\":",
      with: "\"capability_channel\":{\"object_id\":\"channel\",\"revision\":1,\"sha256\":\"exact\"},\"inputs\":{},\"roles\":")
    let selected = try JSONDecoder().decode(AgentCollaborationLiveGraph.WorkflowExpansion.self, from: Data(withChannel.utf8))
    guard case .workflow(let pinned)? = selected.work.last else { return XCTFail("Missing workflow selection") }
    XCTAssertEqual(pinned.capability_channel?.objectId, "channel")
    XCTAssertEqual(pinned.compile(body), steps)
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
    let selection: AgentMcpJSONValue = .object(["object_id": .string(String(repeating: "c", count: 64)),
      "sha256": .string(String(repeating: "d", count: 64)), "revision": .int(1)])
    var runInput: AgentMcpJSONObject = ["mode": .string("start"), "execution_id": .string("release-run"),
      "timeout_ms": .int(1_000), "tool_release": selection, "parameters": .object(["value": .int(1)])]
    let run = try XCTUnwrap(Execution.Request(phase: "start", input: runInput))
    let runAdmitted = try reopened.updateSavedToolExecution(.request(run), scope: scope(), process: "b", now: 14)
    XCTAssertTrue(runAdmitted.shouldLaunch)
    XCTAssertNil(runAdmitted.record?.plan)
    XCTAssertEqual(runAdmitted.record?.parameters, ["value": .int(1)])
    runInput["parameters"] = .object(["value": .int(2)])
    let changedRun = try XCTUnwrap(Execution.Request(phase: "start", input: runInput))
    XCTAssertThrowsError(try reopened.updateSavedToolExecution(.request(changedRun), scope: scope(), process: "b", now: 15))
    runInput["source"] = .string("untrusted override")
    XCTAssertNil(Execution.Request(phase: "start", input: runInput))
    runInput["source"] = nil
    runInput["execution_id"] = .string("channel-run")
    runInput["capability_channel"] = selection
    XCTAssertNil(Execution.Request(phase: "start", input: runInput))
    runInput["tool_release"] = nil
    let channel = try XCTUnwrap(Execution.Request(phase: "start", input: runInput))
    let channelAdmission = try reopened.updateSavedToolExecution(.request(channel), scope: scope(), process: "b", now: 16)
    XCTAssertNotNil(channelAdmission.record?.channel)
    XCTAssertNil(channelAdmission.record?.release)
    XCTAssertFalse(try reopened.updateSavedToolExecution(.request(channel), scope: scope(), process: "b", now: 17).shouldLaunch)
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
      return .init(status: .succeeded, output: output, message: "", receipt: .init(invocationId: "fixture",
        startedAtEpochMillis: AgentControlPlaneClock.nowMillis(),
        finishedAtEpochMillis: AgentControlPlaneClock.nowMillis(), durationMillis: 1, status: .succeeded,
        inputSha256: AgentMcpJSONCodec.sha256(prepared.runtimeInput), outputSha256: AgentMcpJSONCodec.sha256(output)),
        provenance: .init(toolId: AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
          toolVersion: "1", location: .application, executorId: "fixture", contractVersion: "1"))
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
    XCTAssertThrowsError(try history.prepareSavedToolTest(stale, timeoutMillis: 1_000, scope: reader))

    let original = AgentCollaborationNativeToolObservation(runId: reader.runId, conversationId: reader.conversationId,
      turnId: reader.turnId, memberId: reader.memberId, sourceId: reader.sourceId,
      input: prepared.evidenceInput, result: report(rows))
    let evidence = try history.recordNativeObservation(original)
    let citation = ["evidence_id": try XCTUnwrap(evidence["evidence_id"]),
                    "sha256": try XCTUnwrap(evidence["sha256"])]
    var review = durableTeamSnapshot("release-review")
    review.taskId = "review-turn"
    let reviewer = AgentCollaborationToolEvidenceScope(runId: review.supervisorRunId, conversationId: review.conversationId,
      turnId: review.taskId, memberId: review.members[1].memberId, sourceId: review.members[1].sourceMessageId)
    let release = AgentCollaborationResearchDraft(id: "release", objectId: nil, baseRevision: 0, kind: .toolRelease,
      title: "Reviewed tool", body: ["tool_release": .object([
        "tool_test_plan": .object(["object_id": .string(reference.objectId), "revision": .int(reference.revision),
          "sha256": .string(reference.sha256)]), "observation": .object(citation),
        "review": .string("Reviewed source and oracle"), "applies_when": .string("Known input"),
        "avoid_when": .string("Other domains"), "limitations": .string("Two checked cases"),
        "authorization_boundary": .string("No new permissions"), "unresolved": .array([])
      ])], parents: [reference], observations: [citation])
    func publishRelease() throws -> AgentCollaborationResearchPublication {
      try history.publishResearchObjects([release], runId: reviewer.runId, conversationId: reviewer.conversationId,
        turnId: reviewer.turnId, memberId: reviewer.memberId, sourceId: reviewer.sourceId)
    }
    review.members[1].status = .succeeded
    XCTAssertTrue(history.upsert(review))
    XCTAssertThrowsError(try publishRelease())
    review.members[1].status = .running
    review.updatedAtMillis += 1
    XCTAssertTrue(history.upsert(review))
    var offset: Int64 = 0
    for _ in 0..<16 {
      let page = try history.recallCollaborationOriginal(citation.merging([
        "mode": .string("evidence"), "offset": .int(offset)
      ]) { _, new in new }, scope: reviewer)
      guard let next = page["next_offset"]?.intValue else { break }
      XCTAssertGreaterThan(next, offset)
      offset = next
    }
    review.members[1].status = .succeeded
    review.updatedAtMillis += 1
    XCTAssertTrue(history.upsert(review))
    let releaseRef = try XCTUnwrap(publishRelease().references.first)
    let runnable = try history.prepareSavedToolExecution(test: nil, release: releaseRef, parameters: ["value": .int(42)],
      timeoutMillis: 1_000, scope: reader)
    XCTAssertEqual(runnable.evidenceInput["mode"], .string("run"))
    XCTAssertEqual(runnable.evidenceInput["parameters"], .object(["value": .int(42)]))
    XCTAssertEqual(runnable.runtimeInput["network_enabled"], .bool(false))
    XCTAssertTrue(runnable.runtimeInput.string("source").contains("runtime != payload['expected_runtime']"))
    var rejectionEvidence: AgentMcpJSONObject?
    do {
      _ = try history.prepareSavedToolExecution(test: nil, release: releaseRef,
        parameters: ["value": .string("42")], timeoutMillis: 1_000, scope: reader)
      XCTFail("A rejected schema must not produce a runtime invocation")
    } catch let rejection as AgentCollaborationSavedToolExecution.PreflightRejected {
      XCTAssertEqual(rejection.code, "saved_tool_run_preflight_rejected")
      rejectionEvidence = try history.recordSavedToolRejection(.init(scope: reader, invocationId: "preflight",
        input: rejection.input, code: rejection.code, rejectedAt: 42))
    }
    let savedRejection = try XCTUnwrap(rejectionEvidence)
    let rejectionSelector: AgentMcpJSONObject = ["mode": .string("evidence"),
      "evidence_id": savedRejection["evidence_id"] ?? .null, "sha256": savedRejection["sha256"] ?? .null]
    let preview = try history.recallCollaborationOriginal(rejectionSelector, scope: reader, evidenceRead: .desktopPreview)
    XCTAssertEqual(preview["source_reference"]?.objectValue?["runtime_invoked"], .bool(false))
    var acceptanceSelector = rejectionSelector
    acceptanceSelector["mode"] = .string("native_evidence")
    XCTAssertThrowsError(try history.recallCollaborationOriginal(acceptanceSelector, scope: reader))
    let originalRejection = try JSONDecoder().decode(AgentCollaborationSavedToolRejection.self,
      from: Data(preview.string("content").utf8))
    XCTAssertEqual(originalRejection.input["parameters"], .object(["value": .string("42")]))
    var historyInput = AgentCollaborationNativeReleaseHistory.fields(releaseRef)
    historyInput["mode"] = .string("method_history")
    let page = try history.recallCollaborationOriginal(historyInput, scope: reader)
    let rejected = try XCTUnwrap(page["records"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(rejected["evidence_id"], savedRejection["evidence_id"])
    XCTAssertEqual(rejected["native_invocation_id"], .null)
    XCTAssertEqual(rejected["runtime_report_available"], .bool(false))
    history.removeResearchObjects(conversationId: reader.conversationId)
    XCTAssertThrowsError(try history.prepareSavedToolTest(reference, timeoutMillis: 1_000, scope: reader))
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

  func testWorkflowChannelPinsOldInstancesAndRejectsStaleNewAdmissions() throws {
    let suite = "workflow-channel-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let file = root.appendingPathComponent("history.sqlite3")
    func open() -> AgentTeamExecutionHistoryStore {
      .init(defaults: defaults, secrets: secrets, executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    }
    let history = open()
    let team = durableTeamSnapshot("workflow-channel")
    XCTAssertTrue(history.upsert(team))
    let checkpoint = AgentCollaborationGoalCheckpoint(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId, revision: 1, phase: .working,
      contract: [.init(id: "result", requirement: "Observe the result", verification: .physical,
        status: .open, evidence_kind: nil, evidence: [])], completedWorkIds: [])
    XCTAssertTrue(history.advanceGoalCheckpoint(checkpoint, expectedRevision: 0))
    let database = try AgentTeamHistoryDatabase(fileURL: file,
      storageKey: AgentTeamExecutionHistoryStore.defaultStorageKey, secrets: secrets)
    func ref(_ id: String, _ revision: Int64 = 1) -> AgentCollaborationResearchReference {
      .init(objectId: id, revision: revision, sha256: id + "-\(revision)")
    }
    func row(_ ref: AgentCollaborationResearchReference, _ kind: AgentCollaborationResearchDraft.Kind,
             body: AgentMcpJSONObject = [:]) -> AgentCollaborationResearchRevision {
      .init(reference: ref, previousHash: nil, runId: "earlier-run", turnId: "earlier-turn",
        authorId: "author", sourceId: "source", draft: .init(id: ref.objectId, objectId: nil, baseRevision: 0,
          kind: kind, title: "Fixture", body: body, parents: []))
    }
    func save(_ row: AgentCollaborationResearchRevision) throws {
      try database.insertResearchRecord(row, conversationId: team.conversationId,
        key: "object:" + row.reference.objectId, revision: row.reference.revision)
    }
    let body = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data("""
      {"purpose":"Verify","domain":"Fixture","bottleneck":"Errors","change_rationale":"Review",
       "applies_when":"Comparable","avoid_when":"Unsafe","risks":"Delay","expected_gain":"Accuracy","falsifier":"No gain",
       "dimensions":["verification"],"roles":["author"],"inputs":[],
       "steps":[{"id":"draft","role":"author","stage":"EXPLORE","assignment":"Draft"}]}
      """.utf8))
    let previousMethod = ref("method-1"), nextMethod = ref("method-2")
    for method in [previousMethod, nextMethod] {
      try save(row(method, .workflowMethod, body: ["workflow_method": .object(body)]))
    }
    let lesson = ref("lesson"), innovation = ref("innovation"), bankRef = ref("suite")
    try save(row(lesson, .capabilityLesson))
    try save(row(innovation, .innovation))
    var bank = row(bankRef, .capabilitySuite)
    bank.retentionBank = .init(lesson: lesson, previous: nil, domain: "Fixture",
      environment: "fixture", budgetUnit: "calls", anchors: [])
    try save(bank)
    func channel(_ identity: AgentCollaborationResearchReference, method: AgentCollaborationResearchReference)
      -> AgentCollaborationResearchRevision {
      var selected = row(identity, .capabilityChannel)
      selected.capabilitySelection = .init(implementation: method, implementationKind: "workflow_method",
        lesson: lesson, innovation: innovation, suite: bankRef, testedSuite: bankRef, domain: "Fixture", restoredFrom: nil)
      return selected
    }
    let first = ref("channel"), promoted = ref("channel", 2)
    try save(channel(first, method: previousMethod))
    func instance(_ id: String, method: AgentCollaborationResearchReference, channel: AgentCollaborationResearchReference)
      -> AgentCollaborationWorkflowInstance {
      .init(execution_id: id, method: method, inputs: [:], roles: ["author": team.primaryMemberId], capability_channel: channel)
    }
    func append(_ instance: AgentCollaborationWorkflowInstance, revision: Int64, in store: AgentTeamExecutionHistoryStore) -> Bool {
      store.appendSavedCollaborationWorkflow(instance, runId: team.supervisorRunId, conversationId: team.conversationId,
        turnId: team.taskId, expectedRevision: revision, historicalAuthors: [:], settled: [:])
    }
    let existing = instance("first", method: previousMethod, channel: first)
    XCTAssertFalse(append(instance("wrong", method: nextMethod, channel: first), revision: 1, in: history))
    XCTAssertTrue(append(existing, revision: 1, in: history))
    try save(channel(promoted, method: nextMethod))
    let reopened = open()
    XCTAssertTrue(append(existing, revision: 2, in: reopened))
    XCTAssertFalse(append(instance("first", method: nextMethod, channel: promoted), revision: 2, in: reopened))
    XCTAssertFalse(append(instance("stale", method: previousMethod, channel: first), revision: 2, in: reopened))
    let new = instance("second", method: nextMethod, channel: promoted)
    XCTAssertTrue(append(new, revision: 2, in: reopened))
    let saved = try XCTUnwrap(reopened.goalCheckpoint(runId: checkpoint.runId,
      conversationId: checkpoint.conversationId, turnId: checkpoint.turnId)?.liveGraph)
    XCTAssertEqual(saved.workflowInstances?["first"], existing)
    XCTAssertEqual(saved.workflowInstances?["second"], new)
    XCTAssertEqual(saved.work.count, 2)
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
    let tail = try reopened.readPinnedCollaborationGoal(scope: scope, section: "goal",
      offset: Int(page.int64("next_offset")), expectedHash: page.string("sha256"))
    let headBytes = try XCTUnwrap(Data(base64Encoded: page.string("data_b64")))
    let tailBytes = try XCTUnwrap(Data(base64Encoded: tail.string("data_b64")))
    XCTAssertEqual(headBytes + tailBytes, Data(team.goal.utf8))
    XCTAssertThrowsError(try reopened.readPinnedCollaborationGoal(scope: scope, section: "goal",
      offset: 8_192, expectedHash: "wrong"))
    scope.sourceId = "foreign-source"
    XCTAssertThrowsError(try reopened.readPinnedCollaborationGoal(scope: scope, section: "criteria"))
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
    XCTAssertThrowsError(try history.publishCollaborationMilestone(closed, scope: scope(0)))
    var work = request
    work["artifact"] = .string(raw.replacingOccurrences(of: "\"work\":[]",
      with: "\"work\":[{\"id\":\"new\",\"member\":\"primary\",\"assignment\":\"Run now\"}]"))
    XCTAssertThrowsError(try history.publishCollaborationMilestone(work, scope: scope(0)))
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
    XCTAssertThrowsError(try reopened.publishCollaborationMilestone(changed, scope: scope(0)))
    let criteria = try reopened.readPinnedCollaborationGoal(scope: scope(0), section: "criteria")
    XCTAssertEqual(criteria["sha256"], saved["criteria_sha256"])
    XCTAssertEqual(reopened.goalCheckpoint(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId)?.contract.first?.requirement, "Measure the sample")
    func work(_ requestID: String, id: String, member: String, expected: Int64,
              dependencies: [String] = [], terminal: Bool = false) -> AgentMcpJSONObject {
      let graph: AgentMcpJSONObject = ["format": .string("galaxyssi.work-expansion.v1"), "work": .array([.object([
        "id": .string(id), "member": .string(member), "assignment": .string("Measure the fixture"),
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
    let unfinished = try open().reserveGoalContinuation(after: raw, scope: scope(0))
    XCTAssertEqual(unfinished?["revision"], .int(3))
    XCTAssertEqual(unfinished?["work_counts"]?.objectValue?["unclaimed"], .int(2))
    XCTAssertNil(try open().reserveGoalContinuation(after: raw + "\n", scope: scope(0)))
    XCTAssertEqual(try open().readyGoalWork(scope: scope(0), excluding: [], limit: 3, now: 10), ["measure"])
    XCTAssertEqual(try open().readyGoalWork(scope: scope(0), excluding: ["measure"], limit: 3, now: 10), [])
    XCTAssertThrowsError(try open().readyGoalWork(scope: scope(1), excluding: [], limit: 3, now: 10))
    let measure = try XCTUnwrap(latest.liveGraph?.work.first)
    let verify = try XCTUnwrap(latest.liveGraph?.work.last)
    XCTAssertThrowsError(try reopened.claimGoalWork(verify, scope: scope(0), now: 10))
    XCTAssertThrowsError(try reopened.claimGoalWork(measure, scope: scope(1), now: 10))
    let worker = AgentCollaborationGoalWorkRun.Target(kind: .cloud, resourceID: team.members[1].agentId, modelID: "selected-model")
    let wrongWorker = AgentCollaborationGoalWorkRun.Target(kind: .local, resourceID: "local-llm", modelID: "installed")
    XCTAssertThrowsError(try reopened.claimGoalWork(measure, scope: scope(0), target: wrongWorker, now: 10))
    let started = try reopened.claimGoalWork(measure, scope: scope(0), target: worker, now: 10)
    XCTAssertTrue(started.claimed)
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
    XCTAssertNil(try open().reserveGoalContinuation(after: raw, scope: scope(0)))
    let resumed = try open().claimGoalCoordinatorRecovery(coordinatorRecovery)
    XCTAssertEqual(resumed?["revision"], .int(3))
    XCTAssertEqual(resumed?["recent_work"]?.arrayValue?.first?.objectValue?["status"], .string("succeeded"))
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
