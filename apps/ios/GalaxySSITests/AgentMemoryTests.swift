import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentMemoryModelsUseAndroidWireNamesAndBounds() throws {
    let decoded = try JSONDecoder().decode(
      AgentMemoryItem.self,
      from: Data(
        #"""
        {
          "id": "memory-1",
          "kind": "preference",
          "value": " Use concise answers ",
          "key": "Response Style!",
          "source": "agent",
          "timestamp_millis": 1000,
          "version": 0,
          "supersedes_id": "old",
          "important": true,
          "status": "active",
          "conflict_group_id": "group",
          "scope": "conversation",
          "scope_id": "chat-1",
          "confidence": 5,
          "evidence_count": 20000,
          "auto_learned": true,
          "last_confirmed_at_millis": -1,
          "last_accessed_at_millis": 2000,
          "expires_at_millis": 3000
        }
        """#.utf8
      )
    )
    let encoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)

    XCTAssertEqual(decoded.kind, .preference)
    XCTAssertEqual(decoded.value, "Use concise answers")
    XCTAssertEqual(decoded.key, "response style")
    XCTAssertEqual(decoded.version, 1)
    XCTAssertEqual(decoded.confidence, 1)
    XCTAssertEqual(decoded.evidenceCount, 10_000)
    XCTAssertEqual(decoded.lastConfirmedAtMillis, 0)
    XCTAssertFalse(decoded.isExpired(nowMillis: 2_999))
    XCTAssertTrue(decoded.isExpired(nowMillis: 3_000))
    XCTAssertTrue(encoded.contains(#""timestamp_millis":1000"#))
    XCTAssertTrue(encoded.contains(#""supersedes_id":"old""#))
    XCTAssertTrue(encoded.contains(#""conflict_group_id":"group""#))
    XCTAssertTrue(encoded.contains(#""last_accessed_at_millis":2000"#))
    XCTAssertEqual(AgentMemoryKind.fromWireValue("SAFETY"), .safety)
    XCTAssertEqual(AgentMemoryScope.fromWireValue("workspace"), .workspace)
    XCTAssertEqual(AgentMemoryStatus.fromWireValue("SUPERSEDED"), .superseded)
  }

  func testAgentMemoryStoreDedupesAndMergesEvidence() {
    var now: Int64 = 5_000
    let store = InMemoryAgentMemoryStore(nowMillis: { now })
    let first = store.remember(AgentMemoryItem(
      kind: .preference,
      value: "Use concise answers",
      timestampMillis: 1_000,
      id: "memory-a",
      key: "Response Style",
      confidence: 0.7,
      evidenceCount: 2,
      expiresAtMillis: 8_000
    ))
    now = 6_000
    let duplicate = store.remember(AgentMemoryItem(
      kind: .preference,
      value: "use concise answers",
      timestampMillis: 2_000,
      id: "memory-b",
      key: "response style",
      confidence: 0.9,
      evidenceCount: 4,
      lastConfirmedAtMillis: 5_500,
      expiresAtMillis: 10_000
    ))

    XCTAssertEqual(first.item?.id, "memory-a")
    XCTAssertTrue(duplicate.duplicate)
    XCTAssertEqual(duplicate.item?.id, "memory-a")
    XCTAssertEqual(duplicate.item?.confidence, 0.9)
    XCTAssertEqual(duplicate.item?.evidenceCount, 6)
    XCTAssertEqual(duplicate.item?.lastConfirmedAtMillis, 6_000)
    XCTAssertEqual(duplicate.item?.expiresAtMillis, 10_000)
    XCTAssertEqual(store.snapshot().activeCount, 1)
    XCTAssertEqual(store.count(), 1)
  }

  func testAgentMemoryStoreCreatesAndResolvesConflicts() {
    var now: Int64 = 1_000
    let store = InMemoryAgentMemoryStore(nowMillis: { now })
    let first = store.remember(AgentMemoryItem(
      kind: .preference,
      value: "tone=concise",
      timestampMillis: 1_000,
      id: "tone-a"
    ))
    now = 2_000
    let second = store.remember(AgentMemoryItem(
      kind: .preference,
      value: "tone=warm",
      timestampMillis: 2_000,
      id: "tone-b"
    ))
    let conflict = try XCTUnwrap(second.conflict)

    XCTAssertNil(first.conflict)
    XCTAssertEqual(second.item?.status, .conflicted)
    XCTAssertEqual(second.item?.version, 2)
    XCTAssertEqual(second.item?.supersedesId, "tone-a")
    XCTAssertEqual(conflict.key, "tone")
    XCTAssertEqual(conflict.candidates.map(\.id), ["tone-a", "tone-b"])
    XCTAssertEqual(store.snapshot().conflicts.count, 1)

    now = 3_000
    let resolved = store.resolveConflict(
      groupId: conflict.groupId,
      selectedItemId: "tone-b",
      mergedValue: "tone=concise but warm"
    )
    let snapshot = store.snapshot()

    XCTAssertEqual(resolved?.status, .active)
    XCTAssertEqual(resolved?.source, "memory_conflict_merge")
    XCTAssertEqual(resolved?.version, 3)
    XCTAssertEqual(resolved?.value, "tone=concise but warm")
    XCTAssertEqual(snapshot.conflicts.count, 0)
    XCTAssertEqual(snapshot.activeItems.map(\.value), ["tone=concise but warm"])
    XCTAssertEqual(snapshot.historyItems.map(\.status), [.superseded, .superseded])
  }

  func testAgentMemoryStoreUpdatesLineageRebindsScopeAndDeletesById() throws {
    var now: Int64 = 10_000
    let store = InMemoryAgentMemoryStore(nowMillis: { now })
    store.remember(AgentMemoryItem(
      kind: .task,
      value: "Draft release notes",
      timestampMillis: 9_000,
      id: "task-a",
      key: "release",
      scope: .conversation,
      scopeId: "child"
    ))
    now = 11_000
    let updated = store.update(itemId: "task-a", value: "Draft iOS release notes", key: "")
    let updatedId = try XCTUnwrap(updated?.item?.id)

    XCTAssertEqual(updated?.item?.source, "memory_edit")
    XCTAssertEqual(updated?.item?.version, 2)
    XCTAssertEqual(updated?.item?.supersedesId, "task-a")
    XCTAssertEqual(store.snapshot().historyCount, 1)
    XCTAssertEqual(store.rebindConversationScope(sourceConversationId: "child", targetConversationId: "parent"), 2)
    XCTAssertEqual(Set(store.snapshot().activeItems.map(\.scopeId)), ["parent"])

    XCTAssertTrue(store.setImportant(itemId: updatedId, important: true))
    XCTAssertTrue(store.snapshot().activeItems[0].important)
    XCTAssertTrue(store.deleteById(updatedId))
    XCTAssertEqual(store.snapshot().activeCount, 0)
    XCTAssertEqual(store.snapshot().historyCount, 0)
  }

  func testAgentMemoryRecallRecentDeleteAndCommandParsingMatchAndroid() {
    var now: Int64 = 86_400_000 * 2
    let store = InMemoryAgentMemoryStore(nowMillis: { now })
    store.remember(AgentMemoryItem(
      kind: .knowledge,
      value: "GalaxySSI stores private memory on device",
      timestampMillis: 1_000,
      id: "knowledge-a",
      confidence: 0.8,
      evidenceCount: 2
    ))
    store.remember(AgentMemoryItem(
      kind: .preference,
      value: "preferred response style is concise",
      timestampMillis: 2_000,
      id: "preference-a",
      important: true
    ))
    store.remember(AgentMemoryItem(
      kind: .knowledge,
      value: "Expired memory",
      timestampMillis: 3_000,
      id: "expired",
      expiresAtMillis: now
    ))

    let recalled = store.recall(query: "private memory")
    XCTAssertEqual(recalled.map(\.id), ["knowledge-a"])
    XCTAssertEqual(store.snapshot().activeItems.first { $0.id == "knowledge-a" }?.lastAccessedAtMillis, now)
    XCTAssertEqual(store.recent(limit: 2).map(\.id), ["preference-a", "knowledge-a"])
    XCTAssertEqual(store.delete(query: "concise"), 1)
    XCTAssertEqual(Set(store.snapshot().activeItems.map(\.id)), ["knowledge-a", "expired"])

    let saved = AgentMemoryCommandParser.memoryValue(fromGoal: "remember preference: response style = concise")
    let item = AgentMemoryCommandParser.item(fromCommand: saved ?? "", nowMillis: 12_000)
    let chinese = AgentMemoryCommandParser.item(
      fromCommand: "\u{504f}\u{597d}: \u{8bed}\u{6c14}: \u{7b80}\u{6d01}",
      nowMillis: 13_000
    )

    XCTAssertEqual(item.kind, .preference)
    XCTAssertEqual(item.key, "response style")
    XCTAssertEqual(item.source, "agent_memory_command")
    XCTAssertEqual(chinese.kind, .preference)
    XCTAssertEqual(chinese.key, "\u{8bed}\u{6c14}")
    XCTAssertEqual(AgentMemoryCommandParser.memoryCaptureValue(fromGoal: "disable memory capture"), false)
    XCTAssertEqual(AgentMemoryCommandParser.memoryCaptureValue(fromGoal: "resume memory"), true)
  }

  func testAgentMemorySnapshotCodecRoundTripsAndroidEnvelope() throws {
    let snapshot = AgentMemorySnapshot(
      activeItems: [
        AgentMemoryItem(
          kind: .safety,
          value: "Do not save banking codes",
          timestampMillis: 1_000,
          id: "safety-a",
          key: "banking",
          important: true,
          scope: .global
        )
      ],
      conflicts: [
        AgentMemoryConflict(
          groupId: "group-a",
          kind: .preference,
          key: "tone",
          candidates: [
            AgentMemoryItem(kind: .preference, value: "tone=brief", id: "tone-a", key: "tone", status: .conflicted, conflictGroupId: "group-a"),
            AgentMemoryItem(kind: .preference, value: "tone=warm", id: "tone-b", key: "tone", version: 2, status: .conflicted, conflictGroupId: "group-a")
          ]
        )
      ],
      historyItems: [
        AgentMemoryItem(kind: .preference, value: "old tone", id: "old", status: .superseded)
      ]
    )
    let encoded = try AgentMemoryJSONCodec.encodeSnapshot(snapshot)
    let encodedString = String(decoding: encoded, as: UTF8.self)
    let restored = try AgentMemoryJSONCodec.decodeSnapshot(encoded)

    XCTAssertTrue(encodedString.contains(#""active_items""#))
    XCTAssertTrue(encodedString.contains(#""history_items""#))
    XCTAssertTrue(encodedString.contains(#""group_id":"group-a""#))
    XCTAssertEqual(restored.activeCount, 1)
    XCTAssertEqual(restored.conflicts.first?.candidates.map(\.id), ["tone-a", "tone-b"])
    XCTAssertEqual(restored.historyCount, 1)
  }
}
