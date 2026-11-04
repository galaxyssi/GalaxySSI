import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
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
    prior.state = .succeeded
    prior.finalOutput = "Verified battery comparison"
    var current = prior
    current.supervisorRunId = "current"
    current.taskId = "turn"
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
      output: "{\"hits\":[]}", succeeded: true, startedAtMillis: 10, finishedAtMillis: 12)
    let receipt = try history.recordCloudEvidence(observation)
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    XCTAssertEqual(try reopened.recordCloudEvidence(observation), receipt)
    let input: AgentMcpJSONObject = [
      "mode": .string("evidence"), "evidence_id": receipt["evidence_id"] ?? .null,
      "sha256": receipt["sha256"] ?? .null
    ]
    XCTAssertTrue(try reopened.recallCollaborationOriginal(input, scope: scope).string("content").contains("web_search"))
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
    let member = snapshot.members[index]
    XCTAssertTrue(history.upsert(snapshot))
    XCTAssertFalse(history.advanceDispatchCheckpoint(runId: "run", conversationId: "foreign",
      turnId: snapshot.taskId, memberId: member.memberId, sourceMessageId: member.sourceMessageId,
      to: .dispatching, now: 20))
    XCTAssertTrue(history.advanceDispatchCheckpoint(runId: "run", conversationId: snapshot.conversationId,
      turnId: snapshot.taskId, memberId: member.memberId, sourceMessageId: member.sourceMessageId,
      to: .dispatching, now: 20))
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets,
      executionStore: SavedTeamRecoveryFixture([]), fileURL: file)
    XCTAssertEqual(reopened.snapshot(supervisorRunId: "run")?.members[index].dispatchCheckpoint, .dispatching)
    XCTAssertFalse(reopened.advanceDispatchCheckpoint(runId: "run", conversationId: snapshot.conversationId,
      turnId: snapshot.taskId, memberId: member.memberId, sourceMessageId: member.sourceMessageId,
      to: .dispatching, now: 30))
    XCTAssertTrue(reopened.advanceDispatchCheckpoint(runId: "run", conversationId: snapshot.conversationId,
      turnId: snapshot.taskId, memberId: member.memberId, sourceMessageId: member.sourceMessageId,
      to: .accepted, now: 30))
    XCTAssertEqual(history.snapshot(supervisorRunId: "run")?.members[index].dispatchCheckpoint, .accepted)
  }

  func testCollaborationResultsStayInTheirConversationAfterReopen() {
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
    let scoped = reopened.collaborationResults(conversationId: first.conversationId, limit: 20)
    XCTAssertEqual(scoped.map(\.supervisorRunId), ["first"])
    XCTAssertEqual(scoped.first?.members.first?.displayName, "Original member name")
    XCTAssertTrue(reopened.collaborationResults(conversationId: "", limit: 20).isEmpty)
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
