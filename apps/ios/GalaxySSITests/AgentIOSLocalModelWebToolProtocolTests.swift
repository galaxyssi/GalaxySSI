import XCTest
@testable import GalaxySSI

final class AgentIOSLocalModelWebToolProtocolTests: XCTestCase {
  func testDecodeAcceptsAnswerOrReadOnlyWebCalls() throws {
    let inference = LocalModelInferenceResult(
      text: "",
      profileId: "fixture",
      backend: "test",
      smeAvailable: false,
      elapsedMillis: 10
    )
    let answer = try AgentIOSLocalModelWebToolProtocol.decode(
      #"{"answer":"Stable answer","tool_calls":[]}"#,
      inference: inference
    )
    let call = try AgentIOSLocalModelWebToolProtocol.decode(
      #"{"answer":"","tool_calls":[{"name":"galaxyssi.web.intelligence.search","arguments":{"query":"current release"}}]}"#,
      inference: inference
    )

    XCTAssertEqual(answer.assistantText, "Stable answer")
    XCTAssertEqual(call.toolCalls.first?.toolId, AgentIOSWebIntelligenceNativeToolCatalog.search)
    XCTAssertEqual(call.toolCalls.first?.arguments["query"], .string("current release"))
  }

  func testToolAllowlistExcludesMutatingDownloads() {
    XCTAssertTrue(AgentIOSLocalModelWebToolProtocol.toolIDs.contains(AgentIOSWebMediaNativeToolCatalog.webFetch))
    XCTAssertFalse(AgentIOSLocalModelWebToolProtocol.toolIDs.contains(AgentIOSWebMediaNativeToolCatalog.webDownload))
    XCTAssertFalse(AgentIOSLocalModelWebToolProtocol.toolIDs.contains(AgentIOSWebMediaNativeToolCatalog.fileDownload))
    XCTAssertFalse(AgentIOSLocalModelWebToolProtocol.toolIDs.contains(AgentIOSLocalModelWebToolRunner.collaborationRecallId))
  }

  func testScopedRecallUsesCurrentRosterAndPrivacyState() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let database = AgentConversationDatabase(fileURL: root.appendingPathComponent("conversations.sqlite"),
      secrets: InMemorySecretStore())
    let leader = AgentCollaborationRoster.Member(name: "Lead", resourceId: "codex")
    let reviewer = AgentCollaborationRoster.Member(name: "Reviewer", resourceId: "local-llm")
    var conversation = AgentConversation(id: "group", title: "Group", createdAt: 1, updatedAt: 1,
      collaborationRoster: .init(members: [leader, reviewer], coordinatorId: leader.id))
    XCTAssertTrue(database.upsert(conversation))
    let scope = AgentCollaborationToolEvidenceScope(runId: "run", conversationId: "group", turnId: "turn",
      memberId: reviewer.id.uuidString.lowercased() + ":recheck", sourceId: "source")
    XCTAssertTrue(AgentIOSLocalModelWebToolRunner.collaborationRecallIsAuthorized(scope, database: database))
    conversation.trackingPaused = true
    XCTAssertTrue(database.upsert(conversation))
    XCTAssertFalse(AgentIOSLocalModelWebToolRunner.collaborationRecallIsAuthorized(scope, database: database))
    conversation.trackingPaused = false
    conversation.collaborationRoster = .init(members: [leader], coordinatorId: leader.id)
    XCTAssertTrue(database.upsert(conversation))
    XCTAssertFalse(AgentIOSLocalModelWebToolRunner.collaborationRecallIsAuthorized(scope, database: database))
  }

  func testLocalGoalToolRequiresOriginalCoordinatorAndUnchangedRoster() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "local-coordinator-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let database = AgentConversationDatabase(fileURL: root.appendingPathComponent("conversations.sqlite"), secrets: secrets)
    let history = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets, fileURL: root.appendingPathComponent("team.sqlite"))
    let leader = AgentCollaborationRoster.Member(name: "Lead", resourceId: "local-llm")
    let reviewer = AgentCollaborationRoster.Member(name: "Review", resourceId: "review")
    let roster = AgentCollaborationRoster(members: [leader, reviewer], coordinatorId: leader.id)
    var conversation = AgentConversation(id: "group", title: "Group", createdAt: 1, updatedAt: 1, collaborationRoster: roster)
    XCTAssertTrue(database.upsert(conversation))
    let turn = UUID().uuidString
    let scope = AgentCollaborationToolEvidenceScope(runId: "run", conversationId: "group", turnId: turn,
      memberId: leader.id.uuidString.lowercased(), sourceId: "source")
    let snapshot = AgentTeamExecutionSnapshot(supervisorRunId: scope.runId, teamId: "team",
      conversationId: scope.conversationId, taskId: scope.turnId, primaryAgentId: leader.resourceId,
      goal: "Preserve the original goal", state: .running, members: [
        .init(agentId: leader.resourceId, deliveryMode: .respond, instanceId: scope.memberId,
          sourceMessageId: scope.sourceId, dispatchCheckpoint: .accepted),
        .init(agentId: reviewer.resourceId, deliveryMode: .observe, instanceId: reviewer.id.uuidString.lowercased(),
          sourceMessageId: "review-source", dispatchCheckpoint: .accepted)
      ], createdAtMillis: 1, updatedAtMillis: 1, primaryInstanceId: scope.memberId)
    XCTAssertTrue(history.upsert(snapshot))
    let authority = AgentIOSLocalModelWebToolRunner.GoalCoordinator(scope: scope, roster: roster,
      database: database, recruitmentTemplates: [:], history: history)
    XCTAssertNoThrow(try authority.validate())
    XCTAssertEqual(try authority.executable().descriptor.effect, .mutation)
    XCTAssertFalse(AgentIOSLocalModelWebToolProtocol.toolIDs.contains(AgentIOSLocalModelWebToolRunner.goalCoordinatorToolID))
    let original = ChatMessage(contactId: "owner", content: "Original request", isMine: true,
      conversationId: scope.conversationId, turnId: scope.turnId)
    let source = AgentCollaborationAcceptedDelivery.Source(profileID: "owner", messageID: original.id,
      contactID: original.contactId, rosterDigest: try XCTUnwrap(AgentCollaborationAcceptedDelivery.Source.rosterDigest(roster)))
    let profile = try XCTUnwrap(LocalModelRuntimeCatalog.profiles(defaults: defaults).first(where: \.supportsIOSRuntime))
    let binding = AgentCollaborationCoordinatorRecovery(owner: scope, source: source,
      originalPrompt: "Original request", process: "previous-process", local: profile,
      localSourceDigest: AgentCollaborationCoordinatorRecovery.messageDigest(original))
    var edited = original
    edited.content = "Edited request"
    XCTAssertTrue(binding.matchesOriginal(original))
    XCTAssertFalse(binding.matchesOriginal(edited))
    try history.saveGoalCoordinatorRecovery(binding)
    let reopened = AgentTeamExecutionHistoryStore(defaults: defaults, secrets: secrets, fileURL: root.appendingPathComponent("team.sqlite"))
    XCTAssertEqual(try reopened.acceptedGoalDeliveryRecoveryPage(after: "").coordinators, [binding])
    var changed = binding
    changed.local?.fileName = "replacement.gguf"
    XCTAssertThrowsError(try reopened.saveGoalCoordinatorRecovery(changed))
    XCTAssertNil(try reopened.claimGoalCoordinatorRecovery(changed))
    XCTAssertEqual(try reopened.claimGoalCoordinatorRecovery(binding)?["revision"], .int(0))
    XCTAssertNil(try reopened.claimGoalCoordinatorRecovery(binding))
    XCTAssertNotNil(try history.reserveGoalContinuation(after: "", scope: scope, scheduleRetry: true, now: 10))
    XCTAssertNil(try history.reserveGoalContinuation(after: "", scope: scope, scheduleRetry: true, now: 11))
    XCTAssertEqual(try reopened.goalCoordinatorRetryAt(scope), 30_011)
    XCTAssertNil(try reopened.claimGoalCoordinatorRecovery(binding, now: 30_010))
    XCTAssertEqual(try reopened.claimGoalCoordinatorRecovery(binding, now: 30_011)?["revision"], .int(0))
    XCTAssertEqual(try history.goalCoordinatorRetryAt(scope), 90_011)
    XCTAssertNil(try history.claimGoalCoordinatorRecovery(binding, now: 30_011))
    XCTAssertEqual(AgentCollaborationCoordinatorRetry.schedule(after: 100, now: 11).retryAt, 900_011)
    var foreign = scope
    foreign.sourceId = "foreign"
    XCTAssertThrowsError(try AgentIOSLocalModelWebToolRunner.GoalCoordinator(scope: foreign, roster: roster,
      database: database, recruitmentTemplates: [:], history: history).validate())
    conversation.trackingPaused = true
    XCTAssertTrue(database.upsert(conversation))
    XCTAssertThrowsError(try authority.validate())
  }
}
