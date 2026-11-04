import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
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
    var restored = try XCTUnwrap(history.snapshot(supervisorRunId: "run"))
    XCTAssertEqual(restored.members[index].researchStage, "EXPLORE")
    XCTAssertEqual(restored.members[index].executionStartedAtMillis, 20)
    XCTAssertEqual(restored.members[index].elapsedExecutionMillis(now: 40, team: restored), 20)
    restored.members[index].status = .succeeded
    restored.members[index].updatedAtMillis = 50
    XCTAssertEqual(restored.members[index].elapsedExecutionMillis(now: 100, team: restored), 30)
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
