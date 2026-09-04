import XCTest
@testable import GalaxySSI

final class GlobalMemoryEvolutionTests: XCTestCase {
  func testGlobalMemorySupersessionPolicyInspectsAndTracesSafeChains() throws {
    let old = evolutionItem(
      "old",
      topic: "Project GalaxySSI iOS memory",
      value: "GalaxySSI iOS memory used temporal snapshots",
      status: .superseded,
      temporalState: .deprecated,
      supersededByItemId: "new",
      evidenceEventIds: ["event-old"],
      firstSeenAtMillis: 1_000,
      lastSeenAtMillis: 2_000
    )
    let replacement = evolutionItem(
      "new",
      topic: "Project GalaxySSI iOS memory",
      value: "GalaxySSI iOS memory now uses durable context",
      supersedesItemIds: ["old"],
      evidenceEventIds: ["event-new"],
      firstSeenAtMillis: 2_000,
      lastSeenAtMillis: 3_000
    )
    let world = PersonalWorldModel(items: [replacement, old])

    let report = GlobalMemorySupersessionPolicy.inspect(world: world)
    let trace = GlobalMemorySupersessionPolicy.trace(world: world, itemId: "old")

    XCTAssertTrue(report.isSafe)
    XCTAssertNoThrow(try report.requireSafe())
    XCTAssertEqual(report.edges, [GlobalMemorySupersessionEdge(previousItemId: "old", replacementItemId: "new")])
    XCTAssertEqual(trace.items.map(\.id), ["old", "new"])
    XCTAssertEqual(trace.evidenceEventIds, ["event-old", "event-new"])
    XCTAssertTrue(trace.complete)
  }

  func testGlobalMemorySupersessionPolicyFindsBrokenChainsAndCycles() {
    let missingReverse = evolutionItem(
      "old",
      status: .superseded,
      temporalState: .deprecated,
      evidenceEventIds: ["event-old"]
    )
    let crossNamespace = evolutionItem(
      "new",
      namespaceId: "other",
      supersedesItemIds: ["old"],
      evidenceEventIds: ["event-new"]
    )
    let cycleA = evolutionItem(
      "cycle-a",
      status: .superseded,
      temporalState: .deprecated,
      supersedesItemIds: ["cycle-b"],
      supersededByItemId: "cycle-b"
    )
    let cycleB = evolutionItem(
      "cycle-b",
      status: .superseded,
      temporalState: .deprecated,
      supersedesItemIds: ["cycle-a"],
      supersededByItemId: "cycle-a"
    )

    let report = GlobalMemorySupersessionPolicy.inspect(
      world: PersonalWorldModel(items: [missingReverse, crossNamespace, cycleA, cycleB])
    )
    let trace = GlobalMemorySupersessionPolicy.trace(
      world: PersonalWorldModel(items: [cycleA, cycleB]),
      itemId: "cycle-a"
    )

    XCTAssertTrue(report.violations.contains("missing_reverse:old:new"))
    XCTAssertTrue(report.violations.contains("cross_namespace:old:new"))
    XCTAssertTrue(report.violations.contains("cycle"))
    XCTAssertFalse(report.isSafe)
    XCTAssertThrowsError(try report.requireSafe())
    XCTAssertFalse(trace.complete)
  }

  func testGlobalMemoryInboxIsolationPolicyFindsCandidateLeaks() {
    let source = GlobalEvidenceRef(eventId: "event-leak", causalEventIds: ["root-leak"], conversationId: "chat-a")
    let candidateItem = evolutionItem(
      "candidate-item",
      topic: "Candidate memory",
      value: "Awaiting review",
      evidenceEventIds: ["event-leak"],
      evidenceProvenance: [source]
    )
    let privateCandidate = GlobalMemoryCandidate(
      id: "private",
      sourceEventId: "private-event",
      conversationId: "chat-a",
      kind: .fact,
      temporalState: .pending,
      risk: .privateBlocked,
      status: .rejected,
      item: evolutionItem("private-item", topic: "Leaked private", value: "secret"),
      reason: "private_content_not_persisted"
    )
    let inbox = GlobalMemoryInbox(candidates: [
      GlobalMemoryCandidate(
        id: "candidate",
        sourceEventId: "event-leak",
        conversationId: "chat-a",
        kind: .fact,
        temporalState: .pending,
        risk: .reviewRequired,
        status: .pendingReview,
        item: candidateItem,
        reason: "needs_review"
      ),
      privateCandidate
    ])
    let world = PersonalWorldModel(
      items: [candidateItem],
      links: [
        GlobalConversationLink(
          id: "link",
          leftConversationId: "chat-a",
          rightConversationId: "chat-b",
          topic: "Leaked link",
          strength: 0.8,
          evidenceProvenance: [source]
        )
      ]
    )
    let topicGraph = GlobalTopicProjectGraph(
      nodes: [
        GlobalTopicNode(
          id: "topic",
          stableKey: "topic",
          name: "Candidate topic",
          worldItemIds: ["candidate-item"],
          evidenceEventIds: ["event-leak"],
          evidenceProvenance: [source]
        )
      ],
      relations: [
        GlobalTopicRelation(
          id: "topic-relation",
          fromNodeId: "topic",
          toNodeId: "project",
          kind: .contains,
          strength: 0.7,
          evidenceEventIds: ["event-leak"],
          evidenceProvenance: [source],
          firstSeenAtMillis: 1_000,
          lastSeenAtMillis: 1_000
        )
      ]
    )
    let entityGraph = GlobalEntityMemoryGraph(
      nodes: [
        GlobalEntityNode(
          id: "entity",
          stableKey: "entity",
          label: "Candidate entity",
          kind: .concept,
          evidence: [source]
        )
      ],
      relations: [
        GlobalEntityRelation(
          id: "entity-relation",
          fromNodeId: "entity",
          toNodeId: "device",
          kind: .relatedTo,
          evidence: [source]
        )
      ]
    )

    let report = GlobalMemoryInboxIsolationPolicy.inspect(
      world: world,
      topicGraph: topicGraph,
      entityGraph: entityGraph,
      inbox: inbox
    )

    XCTAssertFalse(report.isSafe)
    XCTAssertTrue(report.violations.contains("private_candidate_not_redacted:private"))
    XCTAssertTrue(report.violations.contains("world_item:candidate-item"))
    XCTAssertTrue(report.violations.contains("world_link:link"))
    XCTAssertTrue(report.violations.contains("topic_node:topic"))
    XCTAssertTrue(report.violations.contains("topic_relation:topic-relation"))
    XCTAssertTrue(report.violations.contains("entity_node:entity"))
    XCTAssertTrue(report.violations.contains("entity_relation:entity-relation"))
  }

  func testGlobalMemoryInboxIsolationPolicyAcceptsRedactedPrivateCandidates() throws {
    let redacted = evolutionItem(
      "redacted-private",
      topic: "Private memory candidate",
      value: "",
      contextVisibility: .localOnly
    )
    let inbox = GlobalMemoryInbox(candidates: [
      GlobalMemoryCandidate(
        id: "private",
        sourceEventId: "private-event",
        conversationId: "chat-a",
        kind: .fact,
        temporalState: .pending,
        risk: .privateBlocked,
        status: .rejected,
        item: redacted,
        reason: "private_content_not_persisted"
      )
    ])

    let report = GlobalMemoryInboxIsolationPolicy.inspect(
      world: PersonalWorldModel(),
      topicGraph: GlobalTopicProjectGraph(),
      entityGraph: GlobalEntityMemoryGraph(),
      inbox: inbox
    )

    XCTAssertTrue(report.isSafe)
    XCTAssertNoThrow(try report.requireSafe())
  }

  func testGlobalMemoryEvolutionPolicyApproveStrengthensTargetAndMarksInbox() {
    let existing = evolutionItem(
      "existing",
      topic: "Project GalaxySSI iOS memory",
      value: "GalaxySSI iOS memory uses durable context",
      confidence: 0.6,
      evidenceProvenance: [GlobalEvidenceRef(eventId: "old-event", conversationId: "chat-a", timestampMillis: 1_000)],
      lastSeenAtMillis: 2_000,
      expiresAtMillis: 9_000
    )
    let incoming = evolutionItem(
      "incoming",
      topic: "Project GalaxySSI iOS memory",
      value: "GalaxySSI iOS memory uses durable context",
      confidence: 0.86,
      evidenceProvenance: [GlobalEvidenceRef(eventId: "new-event", conversationId: "chat-b", timestampMillis: 2_000)],
      lastSeenAtMillis: 3_000,
      expiresAtMillis: 10_000
    )
    let candidate = GlobalMemoryCandidate(
      id: "candidate-strengthen",
      sourceEventId: "new-event",
      conversationId: "chat-b",
      kind: .fact,
      temporalState: .pending,
      risk: .reviewRequired,
      status: .pendingReview,
      action: .strengthen,
      targetItemIds: ["existing"],
      item: incoming,
      reason: "needs_review",
      createdAtMillis: 3_000
    )

    let result = GlobalMemoryEvolutionPolicy.approve(
      world: PersonalWorldModel(items: [existing], updatedAtMillis: 1_000),
      inbox: GlobalMemoryInbox(candidates: [candidate], updatedAtMillis: 1_000),
      candidateId: "candidate-strengthen",
      nowMillis: 5_000
    )

    XCTAssertEqual(result.world.items.map(\.id), ["existing"])
    XCTAssertEqual(result.world.items.first?.evidenceEventIds, ["old-event", "new-event"])
    XCTAssertEqual(result.world.items.first?.confidence ?? 0, 0.895, accuracy: 0.000_001)
    XCTAssertEqual(result.world.items.first?.lastSeenAtMillis, 5_000)
    XCTAssertEqual(result.world.items.first?.expiresAtMillis, 10_000)
    XCTAssertEqual(result.world.updatedAtMillis, 5_000)
    XCTAssertEqual(result.inbox.candidates.first?.status, .approved)
    XCTAssertEqual(result.inbox.candidates.first?.temporalState, .current)
    XCTAssertEqual(result.inbox.candidates.first?.reviewedAtMillis, 5_000)
  }

  func testGlobalMemoryEvolutionPolicyApproveSupersedesMatchingWorldItems() {
    let active = evolutionItem(
      "active",
      kind: .decision,
      topic: "Project GalaxySSI iOS routing",
      value: "Use native routing for iOS tools",
      status: .active,
      temporalState: .current,
      conflictGroupId: "routing-conflict",
      lastSeenAtMillis: 2_000
    )
    let unrelated = evolutionItem(
      "unrelated",
      kind: .decision,
      namespaceId: "other",
      topic: "Project Other routing",
      value: "Use native routing for another project",
      lastSeenAtMillis: 3_000
    )
    let incoming = evolutionItem(
      "replacement",
      kind: .decision,
      topic: "Project GalaxySSI iOS routing",
      value: "Use native routing for iOS tools after review",
      temporalState: .conflicted,
      lastSeenAtMillis: 4_000
    )
    let candidate = GlobalMemoryCandidate(
      id: "candidate-replacement",
      sourceEventId: "replacement-event",
      conversationId: "chat-a",
      kind: .decision,
      temporalState: .conflicted,
      risk: .reviewRequired,
      status: .conflicted,
      action: .create,
      item: incoming,
      reason: "conflicting_evidence_requires_review",
      createdAtMillis: 4_000
    )

    let result = GlobalMemoryEvolutionPolicy.approve(
      world: PersonalWorldModel(items: [active, unrelated], updatedAtMillis: 1_000),
      inbox: GlobalMemoryInbox(candidates: [candidate], updatedAtMillis: 1_000),
      candidateId: "candidate-replacement",
      nowMillis: 6_000
    )
    let byId = Dictionary(uniqueKeysWithValues: result.world.items.map { ($0.id, $0) })

    XCTAssertEqual(byId["active"]?.status, .superseded)
    XCTAssertEqual(byId["active"]?.temporalState, .deprecated)
    XCTAssertEqual(byId["active"]?.conflictGroupId, "")
    XCTAssertEqual(byId["active"]?.supersededByItemId, "replacement")
    XCTAssertEqual(byId["replacement"]?.status, .active)
    XCTAssertEqual(byId["replacement"]?.temporalState, .current)
    XCTAssertEqual(byId["replacement"]?.supersedesItemIds, ["active"])
    XCTAssertEqual(byId["replacement"]?.lastSeenAtMillis, 6_000)
    XCTAssertEqual(byId["unrelated"]?.status, .active)
    XCTAssertEqual(result.inbox.candidates.first?.status, .approved)
    XCTAssertEqual(result.inbox.candidates.first?.temporalState, .current)
  }

  func testGlobalMemoryEvolutionPolicyRejectsOnlyReviewableCandidates() {
    let pending = GlobalMemoryCandidate(
      id: "pending",
      sourceEventId: "pending-event",
      conversationId: "chat-a",
      kind: .fact,
      temporalState: .pending,
      risk: .reviewRequired,
      status: .pendingReview,
      item: evolutionItem("pending-item"),
      reason: "needs_review",
      createdAtMillis: 2_000
    )
    let applied = GlobalMemoryCandidate(
      id: "applied",
      sourceEventId: "applied-event",
      conversationId: "chat-a",
      kind: .fact,
      temporalState: .current,
      risk: .low,
      status: .autoMerged,
      item: evolutionItem("applied-item"),
      reason: "auto_merged",
      createdAtMillis: 1_000
    )
    let inbox = GlobalMemoryInbox(candidates: [pending, applied], updatedAtMillis: 1_000)

    let rejected = GlobalMemoryEvolutionPolicy.reject(
      inbox: inbox,
      candidateId: "pending",
      nowMillis: 7_000
    )
    let unchanged = GlobalMemoryEvolutionPolicy.reject(
      inbox: rejected,
      candidateId: "applied",
      nowMillis: 8_000
    )

    XCTAssertEqual(rejected.candidates.first(where: { $0.id == "pending" })?.status, .rejected)
    XCTAssertEqual(rejected.candidates.first(where: { $0.id == "pending" })?.reviewedAtMillis, 7_000)
    XCTAssertEqual(rejected.updatedAtMillis, 7_000)
    XCTAssertEqual(unchanged.candidates.first(where: { $0.id == "applied" })?.status, .autoMerged)
    XCTAssertEqual(unchanged.updatedAtMillis, 7_000)
  }

  func testGlobalMemoryEvolutionPolicyBuildsReviewStrengthenAndAuditRecords() {
    let pendingGoal = GlobalMemoryCandidate(
      id: "candidate-goal",
      sourceEventId: "event-goal",
      conversationId: "chat-a",
      kind: .goal,
      temporalState: .pending,
      risk: .reviewRequired,
      status: .pendingReview,
      action: .create,
      targetItemIds: ["old-goal"],
      item: evolutionItem("goal", kind: .goal, topic: "Project goal", value: "Ship iOS parity"),
      reason: "needs_review",
      createdAtMillis: 4_000
    )
    let privateBlocked = GlobalMemoryCandidate(
      id: "candidate-private",
      sourceEventId: "event-private",
      conversationId: "chat-a",
      kind: .fact,
      temporalState: .pending,
      risk: .privateBlocked,
      status: .rejected,
      item: evolutionItem("private", topic: "Secret", value: ""),
      reason: "private_content_not_persisted",
      createdAtMillis: 3_000
    )
    let existing = evolutionItem(
      "existing",
      topic: "Project GalaxySSI iOS memory",
      value: "GalaxySSI iOS memory uses context",
      confidence: 0.7,
      evidenceProvenance: [GlobalEvidenceRef(eventId: "old-event", conversationId: "chat-a", timestampMillis: 1_000)],
      lastSeenAtMillis: 2_000,
      expiresAtMillis: 9_000
    )
    let incoming = evolutionItem(
      "incoming",
      topic: "Project GalaxySSI iOS memory",
      value: "GalaxySSI iOS memory uses context",
      confidence: 0.9,
      evidenceProvenance: [GlobalEvidenceRef(eventId: "new-event", conversationId: "chat-b", timestampMillis: 2_000)],
      temporalState: .planned,
      lastSeenAtMillis: 5_000,
      expiresAtMillis: 10_000
    )
    let strengthened = GlobalMemoryEvolutionPolicy.strengthened(existing: existing, incoming: incoming)
    let waiting = GlobalMemoryEvolutionPolicy.record(for: pendingGoal)
    let approved = GlobalMemoryEvolutionPolicy.reviewRecord(candidate: pendingGoal, outcome: .approved, nowMillis: 5_000)
    let privateRecord = GlobalMemoryEvolutionPolicy.record(for: privateBlocked)

    XCTAssertEqual(waiting.outcome, .waitingReview)
    XCTAssertEqual(waiting.resultingItemId, "")
    XCTAssertEqual(approved.outcome, .approved)
    XCTAssertEqual(approved.temporalState, .planned)
    XCTAssertEqual(approved.resultingItemId, "goal")
    XCTAssertEqual(privateRecord.outcome, .privateBlocked)
    XCTAssertEqual(privateRecord.subject, "Private memory candidate")
    XCTAssertEqual(strengthened.confidence, 0.935, accuracy: 0.000_001)
    XCTAssertEqual(strengthened.evidenceEventIds, ["old-event", "new-event"])
    XCTAssertEqual(strengthened.temporalState, .planned)
    XCTAssertEqual(strengthened.expiresAtMillis, 10_000)
  }

  func testGlobalMemoryEvolutionPolicyAuditRecordsAndWireNames() throws {
    let before = evolutionItem(
      "old",
      kind: .decision,
      topic: "Project GalaxySSI iOS decision",
      value: "Use durable context compiler",
      evidenceEventIds: ["event-old"],
      evidenceProvenance: [GlobalEvidenceRef(eventId: "event-old", conversationId: "chat-a", timestampMillis: 1_000)],
      lastSeenAtMillis: 2_000
    )
    let deprecated = evolutionItem(
      "old",
      kind: .decision,
      topic: "Project GalaxySSI iOS decision",
      value: "Use durable context compiler",
      status: .superseded,
      temporalState: .deprecated,
      supersededByItemId: "new",
      evidenceEventIds: ["event-old"],
      evidenceProvenance: [GlobalEvidenceRef(eventId: "event-old", conversationId: "chat-a", timestampMillis: 1_000)],
      lastSeenAtMillis: 3_000
    )
    let consolidated = evolutionItem(
      "new",
      kind: .decision,
      topic: "Project GalaxySSI iOS decision",
      value: "Use durable context compiler",
      supersedesItemIds: ["old"],
      evidenceEventIds: ["event-new"],
      lastSeenAtMillis: 4_000
    )
    let records = GlobalMemoryEvolutionPolicy.auditRecords(
      worldBefore: PersonalWorldModel(items: [before]),
      worldAfter: PersonalWorldModel(items: [deprecated, consolidated]),
      nowMillis: 7_000
    )
    let edge = GlobalMemorySupersessionEdge(previousItemId: "old", replacementItemId: "new")
    let trace = GlobalMemorySupersessionTrace(
      items: [deprecated, consolidated],
      edges: [edge],
      evidenceEventIds: ["event-old", "event-new"]
    )
    let record = try XCTUnwrap(records.first)
    let encodedRecord = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
    let encodedTrace = String(decoding: try JSONEncoder().encode(trace), as: UTF8.self)
    let restored = try JSONDecoder().decode(GlobalMemoryEvolutionRecord.self, from: Data(encodedRecord.utf8))

    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(record.action, .consolidate)
    XCTAssertEqual(record.resultingItemId, "new")
    XCTAssertTrue(encodedRecord.contains(#""source_event_id":"event-old""#))
    XCTAssertTrue(encodedRecord.contains(#""candidate_id":"""#))
    XCTAssertTrue(encodedRecord.contains(#""target_item_ids":["old"]"#))
    XCTAssertTrue(encodedRecord.contains(#""resulting_item_id":"new""#))
    XCTAssertTrue(encodedTrace.contains(#""previous_item_id":"old""#))
    XCTAssertTrue(encodedTrace.contains(#""replacement_item_id":"new""#))
    XCTAssertTrue(encodedTrace.contains(#""evidence_event_ids":["event-old","event-new"]"#))
    XCTAssertEqual(restored.outcome, .applied)
  }

  private func evolutionItem(
    _ id: String,
    kind: GlobalWorldItemKind = .fact,
    layer: GlobalWorldLayer = .topic,
    namespace: GlobalMemoryNamespace = .project,
    namespaceId: String = "galaxyssi-ios",
    topic: String = "Project GalaxySSI iOS memory",
    value: String = "GalaxySSI iOS memory value",
    confidence: Double = 0.82,
    contextVisibility: GlobalWorldContextVisibility = .shareable,
    conversationIds: Set<String> = ["chat-a"],
    evidenceEventIds: [String] = [],
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
      stableKey: "\(id)-stable",
      kind: kind,
      layer: layer,
      namespace: namespace,
      namespaceId: namespaceId,
      topic: topic,
      value: value,
      confidence: confidence,
      contextVisibility: contextVisibility,
      evidenceCount: max(evidenceProvenance.count, 1),
      conversationIds: conversationIds,
      evidenceEventIds: evidenceEventIds.isEmpty ? evidenceProvenance.map(\.eventId) : evidenceEventIds,
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
}
