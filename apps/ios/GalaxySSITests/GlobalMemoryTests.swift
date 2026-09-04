import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testGlobalMemoryTemporalSnapshotClassifiesWorldAndInbox() {
    let current = globalMemoryItem("current", kind: .state, lastSeenAtMillis: 6_000)
    let planned = globalMemoryItem("planned", kind: .goal, temporalState: .planned, lastSeenAtMillis: 5_000)
    let historical = globalMemoryItem("historical", kind: .fact, temporalState: .historical, lastSeenAtMillis: 4_000)
    let completed = globalMemoryItem("completed", kind: .task, status: .completed, lastSeenAtMillis: 3_000)
    let deprecated = globalMemoryItem("deprecated", kind: .decision, status: .superseded, lastSeenAtMillis: 2_000)
    let conflict = globalMemoryItem("conflict", kind: .state, status: .conflicted, lastSeenAtMillis: 1_000)
    let pendingCandidate = globalMemoryCandidate("pending-candidate", status: .pendingReview, item: current, createdAtMillis: 10_000)
    let conflictCandidate = globalMemoryCandidate("conflict-candidate", status: .conflicted, item: conflict, createdAtMillis: 11_000)

    let snapshot = GlobalMemoryTemporalPolicy.snapshot(
      world: PersonalWorldModel(items: [current, planned, historical, completed, deprecated, conflict]),
      inbox: GlobalMemoryInbox(candidates: [pendingCandidate, conflictCandidate])
    )

    XCTAssertEqual(snapshot.current.map(\.id), ["current"])
    XCTAssertEqual(snapshot.planned.map(\.id), ["planned"])
    XCTAssertEqual(Set(snapshot.historical.map(\.id)), ["historical", "completed"])
    XCTAssertEqual(snapshot.deprecated.map(\.id), ["deprecated"])
    XCTAssertEqual(snapshot.conflicted.map(\.id), ["conflict"])
    XCTAssertEqual(snapshot.count(.pending), 1)
    XCTAssertEqual(snapshot.count(.conflicted), 2)
    XCTAssertEqual(snapshot.conflictedCandidates.map(\.id), ["conflict-candidate"])
  }

  func testGlobalMemoryNamespacePolicyMatchesAndroidClassification() {
    let explicit = GlobalMemoryNamespacePolicy.resolve(
      event: globalMemoryEvent(
        "explicit",
        type: .memoryCreated,
        content: "Project memory",
        metadata: ["memory_namespace": "PROJECT:GalaxySSI", "memory_namespace_id": "Workspace 1"]
      ),
      understanding: GlobalUnderstanding(topic: "Build", project: ""),
      kind: .fact,
      layer: .topic
    )
    let preference = GlobalMemoryNamespacePolicy.resolve(
      event: globalMemoryEvent("preference", type: .memoryCreated, metadata: ["memory_kind": "PREFERENCE"]),
      understanding: GlobalUnderstanding(),
      kind: .preference,
      layer: .user
    )
    let device = GlobalMemoryNamespacePolicy.resolve(
      event: globalMemoryEvent("device", type: .toolCompleted, metadata: ["tool_key": "wifi.status"]),
      understanding: GlobalUnderstanding(),
      kind: .state,
      layer: .realtime
    )
    let security = GlobalMemoryNamespacePolicy.resolve(
      event: globalMemoryEvent("security", type: .authorizationGranted, metadata: ["policy_id": "Full Access"]),
      understanding: GlobalUnderstanding(),
      kind: .risk,
      layer: .user
    )
    let project = GlobalMemoryNamespacePolicy.resolve(
      event: globalMemoryEvent("project", type: .taskUpdated, content: "Continue iOS work"),
      understanding: GlobalUnderstanding(topic: "iOS parity", project: "GalaxySSI iOS"),
      kind: .task,
      layer: .topic
    )

    XCTAssertEqual(explicit.namespace, .project)
    XCTAssertEqual(explicit.scopeId, "workspace-1")
    XCTAssertEqual(preference.key, "user:self")
    XCTAssertEqual(device.key, "device:local")
    XCTAssertEqual(security.key, "security:full-access")
    XCTAssertEqual(project.key, "project:galaxyssi-ios")
    XCTAssertEqual(GlobalMemoryNamespacePolicy.itemKey(globalMemoryItem("stable", namespace: .project, namespaceId: "ios")), "project:ios\u{0000}stable-key")
  }

  func testGlobalMemoryQueryPlannerMatchesAndroidTermsAndScopes() {
    let toolBuild = GlobalMemoryQueryPlanner.plan("What output did the build command produce?")
    let device = GlobalMemoryQueryPlanner.plan("What battery chip model does this phone have?")
    let preference = GlobalMemoryQueryPlanner.plan("What response style do I prefer?")
    let historical = GlobalMemoryQueryPlanner.plan("What did we decide previously and what changed now?")
    let relationship = GlobalMemoryQueryPlanner.plan("How is the gateway connected to the phone?")

    XCTAssertEqual(toolBuild.type, .toolEvidence)
    XCTAssertTrue(toolBuild.types.contains(.toolEvidence))
    XCTAssertTrue(toolBuild.types.contains(.projectState))
    XCTAssertTrue(toolBuild.preferredNamespaces.isSuperset(of: [.project, .device, .general]))
    XCTAssertEqual(device.type, .deviceCapability)
    XCTAssertEqual(device.preferredNamespaces, [.device])
    XCTAssertEqual(preference.type, .personalPreference)
    XCTAssertEqual(preference.preferredNamespaces, [.user])
    XCTAssertTrue(preference.preferredKinds.contains(.preference))
    XCTAssertEqual(historical.type, .historicalDecision)
    XCTAssertEqual(historical.temporalScope, .currentAndHistory)
    XCTAssertTrue(historical.includeHistorical)
    XCTAssertTrue(relationship.types.contains(.relationship))
    XCTAssertTrue(relationship.types.contains(.deviceCapability))
    XCTAssertTrue(relationship.preferredRelationKinds.contains(.connectedTo))
  }

  func testPersonalWorldRelevantUsesNamespacesVisibilityAndOverlap() {
    let currentConversation = globalMemoryItem(
      "conversation",
      kind: .task,
      layer: .conversation,
      topic: "Draft",
      value: "Draft the active note",
      conversationIds: ["chat-a"],
      lastSeenAtMillis: 1_000
    )
    let userPreference = globalMemoryItem(
      "preference",
      kind: .preference,
      layer: .user,
      namespace: .user,
      namespaceId: "self",
      topic: "Response style",
      value: "Use concise answers",
      confidence: 0.9,
      conversationIds: ["chat-b"],
      lastSeenAtMillis: 2_000
    )
    let otherConversation = globalMemoryItem(
      "other-conversation",
      kind: .task,
      layer: .conversation,
      topic: "Private note",
      value: "Private task in another conversation",
      conversationIds: ["chat-b"],
      lastSeenAtMillis: 3_000
    )
    let expired = globalMemoryItem(
      "expired",
      kind: .preference,
      layer: .user,
      namespace: .user,
      namespaceId: "self",
      topic: "Old style",
      value: "Use verbose answers",
      expiresAtMillis: 5_000
    )
    let world = PersonalWorldModel(items: [currentConversation, userPreference, otherConversation, expired])

    let preferenceResults = world.relevant(
      query: "What response style do I prefer?",
      currentConversationId: "chat-a",
      nowMillis: 6_000
    )
    let conversationResults = world.relevant(
      query: "Draft the active note",
      currentConversationId: "chat-a",
      nowMillis: 6_000
    )

    XCTAssertEqual(preferenceResults.map(\.id), ["preference"])
    XCTAssertEqual(conversationResults.first?.id, "conversation")
    XCTAssertFalse(conversationResults.map(\.id).contains("other-conversation"))
  }

  func testGlobalMemoryModelsUseAndroidWireNames() throws {
    let item = globalMemoryItem(
      "wire",
      kind: .goal,
      namespace: .project,
      namespaceId: "ios",
      temporalState: .planned,
      evidenceProvenance: [globalMemoryEvent("event-a", type: .taskUpdated).evidenceRef],
      supersedesItemIds: ["old"],
      supersededByItemId: "new"
    )
    let candidate = globalMemoryCandidate(
      "candidate",
      status: .pendingReview,
      item: item,
      action: .reviewConflict,
      targetItemIds: ["wire"]
    )
    let snapshot = GlobalMemoryTemporalSnapshot(
      planned: [item],
      pendingCandidates: [candidate]
    )
    let encodedItem = String(decoding: try JSONEncoder().encode(item), as: UTF8.self)
    let encodedSnapshot = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
    let restored = try JSONDecoder().decode(GlobalMemoryTemporalSnapshot.self, from: Data(encodedSnapshot.utf8))

    XCTAssertTrue(encodedItem.contains(#""stable_key":"stable-key""#))
    XCTAssertTrue(encodedItem.contains(#""namespace_id":"ios""#))
    XCTAssertTrue(encodedItem.contains(#""temporal_state":"PLANNED""#))
    XCTAssertTrue(encodedItem.contains(#""evidence_provenance""#))
    XCTAssertTrue(encodedItem.contains(#""superseded_by_item_id":"new""#))
    XCTAssertTrue(encodedSnapshot.contains(#""pending_candidates""#))
    XCTAssertTrue(encodedSnapshot.contains(#""target_item_ids":["wire"]"#))
    XCTAssertEqual(restored.planned.first?.memoryNamespaceKey, "project:ios")
    XCTAssertEqual(restored.pendingCandidates.first?.action, .reviewConflict)
  }

  private func globalMemoryItem(
    _ id: String,
    kind: GlobalWorldItemKind = .fact,
    layer: GlobalWorldLayer = .topic,
    namespace: GlobalMemoryNamespace = .general,
    namespaceId: String = "",
    topic: String = "Topic",
    value: String = "Value",
    confidence: Double = 0.7,
    contextVisibility: GlobalWorldContextVisibility = .shareable,
    evidenceCount: Int = 1,
    conversationIds: Set<String> = [],
    evidenceProvenance: [GlobalEvidenceRef] = [],
    status: GlobalWorldItemStatus = .active,
    temporalState: GlobalMemoryTemporalState = .current,
    conflictGroupId: String = "",
    supersedesItemIds: [String] = [],
    supersededByItemId: String = "",
    firstSeenAtMillis: Int64 = 1_000,
    lastSeenAtMillis: Int64 = 1_000,
    expiresAtMillis: Int64 = 0
  ) -> GlobalWorldItem {
    GlobalWorldItem(
      id: id,
      stableKey: "stable-key",
      kind: kind,
      layer: layer,
      namespace: namespace,
      namespaceId: namespaceId,
      topic: topic,
      value: value,
      confidence: confidence,
      contextVisibility: contextVisibility,
      evidenceCount: evidenceCount,
      conversationIds: conversationIds,
      evidenceEventIds: evidenceProvenance.map(\.eventId),
      evidenceProvenance: evidenceProvenance,
      status: status,
      temporalState: temporalState,
      conflictGroupId: conflictGroupId,
      supersedesItemIds: supersedesItemIds,
      supersededByItemId: supersededByItemId,
      firstSeenAtMillis: firstSeenAtMillis,
      lastSeenAtMillis: lastSeenAtMillis,
      expiresAtMillis: expiresAtMillis
    )
  }

  private func globalMemoryCandidate(
    _ id: String,
    status: GlobalMemoryCandidateStatus,
    item: GlobalWorldItem,
    action: GlobalMemoryEvolutionAction = .create,
    targetItemIds: [String] = [],
    createdAtMillis: Int64 = 1_000
  ) -> GlobalMemoryCandidate {
    GlobalMemoryCandidate(
      id: id,
      sourceEventId: "event-\(id)",
      conversationId: "chat-a",
      kind: .fact,
      temporalState: item.temporalState,
      risk: .reviewRequired,
      status: status,
      action: action,
      targetItemIds: targetItemIds,
      item: item,
      reason: "test",
      createdAtMillis: createdAtMillis
    )
  }

  private func globalMemoryEvent(
    _ id: String,
    type: GlobalConversationEventType,
    content: String = "",
    metadata: [String: String] = [:]
  ) -> GlobalConversationEvent {
    GlobalConversationEvent(
      id: id,
      type: type,
      conversationId: "chat-a",
      actor: .globalAgent,
      timestampMillis: 1_000,
      content: content,
      conversationTitle: "Project GalaxySSI",
      metadata: metadata
    )
  }
}
