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
    conversation.collaborationRoster?.members[1].resourceId = "cloud"
    XCTAssertTrue(database.upsert(conversation))
    XCTAssertFalse(AgentIOSLocalModelWebToolRunner.collaborationRecallIsAuthorized(scope, database: database))
    conversation.collaborationRoster = .init(members: [leader], coordinatorId: leader.id)
    XCTAssertTrue(database.upsert(conversation))
    XCTAssertFalse(AgentIOSLocalModelWebToolRunner.collaborationRecallIsAuthorized(scope, database: database))
  }
}
