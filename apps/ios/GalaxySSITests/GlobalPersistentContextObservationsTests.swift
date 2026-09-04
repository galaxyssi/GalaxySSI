import XCTest
@testable import GalaxySSI

final class GlobalPersistentContextObservationsTests: XCTestCase {
  func testMemoryCreateUpdateSupersedeAndDeleteUseRetractableEvents() throws {
    let original = memoryItem(
      id: "memory-a",
      kind: .preference,
      value: "Use dark mode",
      key: "theme",
      timestampMillis: 1_000
    )
    var updated = original
    updated.value = "Use light mode"
    updated.version = 2
    var superseded = updated
    superseded.status = .superseded

    let created = try GlobalPersistentContextObservationExtractor.memoryMutations(
      before: [],
      after: [original],
      timestampMillis: 1_000
    ).singleValue()
    let changed = try GlobalPersistentContextObservationExtractor.memoryMutations(
      before: [original],
      after: [updated],
      timestampMillis: 2_000
    ).singleValue()
    let retracted = try GlobalPersistentContextObservationExtractor.memoryMutations(
      before: [updated],
      after: [superseded],
      timestampMillis: 3_000
    ).singleValue()
    let deleted = try GlobalPersistentContextObservationExtractor.memoryMutations(
      before: [updated],
      after: [],
      timestampMillis: 4_000
    ).singleValue()

    XCTAssertEqual(created.type, .memoryCreated)
    XCTAssertEqual(created.conversationId, "global-memory")
    XCTAssertEqual(created.content, "Use dark mode")
    XCTAssertEqual(created.metadata["projection"], "upsert")
    XCTAssertEqual(created.causalEventIds, Set(["memory-root:memory-a"]))
    XCTAssertEqual(changed.type, .memoryUpdated)
    XCTAssertTrue(changed.retractedEventIds.contains(created.id))
    XCTAssertEqual(retracted.type, .memoryUpdated)
    XCTAssertEqual(retracted.metadata["projection"], "retract_only")
    XCTAssertEqual(retracted.content, "")
    XCTAssertEqual(deleted.type, .memoryDeleted)
    XCTAssertEqual(deleted.metadata["projection"], "retract_only")
    XCTAssertTrue(deleted.retractedEventIds.contains("memory-root:memory-a"))
  }

  func testConversationScopedMemoryUsesOwningConversation() throws {
    let memory = memoryItem(
      id: "conversation-memory",
      kind: .task,
      value: "Remember this thread's plan",
      key: "thread plan",
      scope: .conversation,
      scopeId: "conversation-a"
    )

    let event = try GlobalPersistentContextObservationExtractor.memoryMutations(
      before: [],
      after: [memory],
      timestampMillis: 1_000
    ).singleValue()

    XCTAssertEqual(event.conversationId, "conversation-a")
    XCTAssertEqual(event.metadata["memory_scope"], "CONVERSATION")
    XCTAssertEqual(event.metadata["memory_scope_id"], "conversation-a")
  }

  func testLocalOnlyKnowledgeImportIsRedactedAndLocalOnly() throws {
    let item = knowledgeItem(
      cloudAccess: .deny,
      agentAccess: .localOnly
    )

    let imported = try GlobalPersistentContextObservationExtractor.knowledgeMutations(
      before: [],
      after: [item],
      timestampMillis: 1_000
    ).singleValue()

    XCTAssertEqual(imported.type, .knowledgeImported)
    XCTAssertEqual(imported.conversationId, "knowledge-library")
    XCTAssertEqual(imported.metadata["context_visibility"], "LOCAL_ONLY")
    XCTAssertEqual(imported.metadata["cloud_access"], "DENY")
    XCTAssertEqual(imported.metadata["agent_access"], "LOCAL_ONLY")
    XCTAssertEqual(imported.metadata["source_kind"], "content")
    XCTAssertTrue(imported.content.contains("Runtime architecture notes"))
    XCTAssertTrue(imported.content.contains("Verified runtime design summary"))
    assertEvent(imported, doesNotExpose: [
      "content://private.provider",
      "FULL_PRIVATE_DOCUMENT_BODY"
    ])
  }

  func testKnowledgeAccessChangeRetractsPriorEventAndSharesOnlySummary() throws {
    let local = knowledgeItem(
      cloudAccess: .deny,
      agentAccess: .localOnly
    )
    var shared = local
    shared.cloudAccess = .summaryOnly
    shared.agentAccess = .anyPairedAgent
    shared.updatedAtMillis = 2_000

    let imported = try GlobalPersistentContextObservationExtractor.knowledgeMutations(
      before: [],
      after: [local],
      timestampMillis: 1_000
    ).singleValue()
    let accessChanged = try GlobalPersistentContextObservationExtractor.knowledgeMutations(
      before: [local],
      after: [shared],
      timestampMillis: 2_000
    ).singleValue()

    XCTAssertEqual(accessChanged.type, .knowledgeAccessChanged)
    XCTAssertTrue(accessChanged.retractedEventIds.contains(imported.id))
    XCTAssertEqual(accessChanged.metadata["context_visibility"], "SHAREABLE")
    XCTAssertEqual(accessChanged.metadata["cloud_access"], "SUMMARY_ONLY")
    XCTAssertEqual(accessChanged.metadata["agent_access"], "ANY_PAIRED_AGENT")
    XCTAssertTrue(accessChanged.content.contains("Verified runtime design summary"))
    assertEvent(accessChanged, doesNotExpose: ["FULL_PRIVATE_DOCUMENT_BODY"])
  }

  func testChunkedKnowledgeSourceProducesOneLifecycleEventAndDeletionRetractsIt() throws {
    var first = knowledgeItem()
    first.id = "chunk-1"
    first.title = "Runtime guide [1/2]"
    first.chunkIndex = 0
    first.chunkCount = 2
    var second = knowledgeItem()
    second.id = "chunk-2"
    second.title = "Runtime guide [2/2]"
    second.chunkIndex = 1
    second.chunkCount = 2

    let imported = GlobalPersistentContextObservationExtractor.knowledgeMutations(
      before: [],
      after: [first, second],
      timestampMillis: 1_000
    )
    let deleted = try GlobalPersistentContextObservationExtractor.knowledgeMutations(
      before: [first, second],
      after: [],
      timestampMillis: 2_000
    ).singleValue()

    XCTAssertEqual(imported.count, 1)
    XCTAssertEqual(imported[0].metadata["item_count"], "2")
    XCTAssertEqual(imported[0].metadata["knowledge_title"], "Runtime guide")
    XCTAssertEqual(deleted.type, .knowledgeDeleted)
    XCTAssertTrue(deleted.retractedEventIds.contains(imported[0].id))
    XCTAssertTrue(deleted.retractedEventIds.contains("knowledge-root:\(imported[0].messageId)"))
  }

  func testKnowledgeBodyChangeProducesUpdateEvenWhenSummaryAndAccessStaySame() throws {
    let original = knowledgeItem()
    var changed = original
    changed.content = "A completely different document body beyond the retained summary"
    changed.updatedAtMillis = 2_000

    let event = try GlobalPersistentContextObservationExtractor.knowledgeMutations(
      before: [original],
      after: [changed],
      timestampMillis: 2_000
    ).singleValue()

    XCTAssertEqual(event.type, .knowledgeUpdated)
    XCTAssertEqual(event.metadata["projection"], "upsert")
    XCTAssertTrue(event.content.contains("Verified runtime design summary"))
    assertEvent(event, doesNotExpose: ["A completely different document body"])
  }

  func testKnowledgeModelsUseAndroidWireNames() throws {
    let item = AgentKnowledgeItem(
      kind: .document,
      title: "Reference",
      content: "Body",
      cloudAccess: .summaryOnly,
      agentAccess: .selectedAgents,
      allowedAgentIds: ["agent-a"]
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any]
    )

    XCTAssertEqual(object["kind"] as? String, "DOCUMENT")
    XCTAssertEqual(object["cloud_access"] as? String, "SUMMARY_ONLY")
    XCTAssertEqual(object["agent_access"] as? String, "SELECTED_AGENTS")
    XCTAssertEqual(object["allowed_agent_ids"] as? [String], ["agent-a"])
  }

  private func memoryItem(
    id: String,
    kind: AgentMemoryKind,
    value: String,
    key: String,
    timestampMillis: Int64 = 1_000,
    scope: AgentMemoryScope = .global,
    scopeId: String = ""
  ) -> AgentMemoryItem {
    AgentMemoryItem(
      kind: kind,
      value: value,
      timestampMillis: timestampMillis,
      id: id,
      source: "agent",
      key: key,
      scope: scope,
      scopeId: scopeId,
      confidence: 0.75,
      evidenceCount: 2
    )
  }

  private func knowledgeItem(
    cloudAccess: AgentKnowledgeCloudAccess = .deny,
    agentAccess: AgentKnowledgeAgentAccess = .localOnly
  ) -> AgentKnowledgeItem {
    AgentKnowledgeItem(
      id: "knowledge-1",
      kind: .document,
      title: "Runtime architecture notes",
      content: "FULL_PRIVATE_DOCUMENT_BODY",
      source: "content://private.provider/documents/runtime-notes",
      tags: ["runtime", "architecture"],
      summary: "Verified runtime design summary",
      cloudAccess: cloudAccess,
      agentAccess: agentAccess,
      updatedAtMillis: 1_000
    )
  }

  private func assertEvent(
    _ event: GlobalConversationEvent,
    doesNotExpose secrets: [String],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let text = (
      event.content + " " +
        event.contentRef + " " +
        event.metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    ).lowercased()
    for secret in secrets {
      XCTAssertFalse(
        text.contains(secret.lowercased()),
        "Event leaked \(secret)",
        file: file,
        line: line
      )
    }
  }
}

private extension Array {
  func singleValue(file: StaticString = #filePath, line: UInt = #line) throws -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    return try XCTUnwrap(first, file: file, line: line)
  }
}
