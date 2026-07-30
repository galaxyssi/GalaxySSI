import XCTest
@testable import SignalASI

final class GlobalMemoryEvolutionTests: XCTestCase {
  func testGlobalMemorySupersessionPolicyInspectsAndTracesSafeChains() throws {
    let old = evolutionItem(
      "old",
      topic: "Project SignalASI iOS memory",
      value: "SignalASI iOS memory used temporal snapshots",
      status: .superseded,
      temporalState: .deprecated,
      supersededByItemId: "new",
      evidenceEventIds: ["event-old"],
      firstSeenAtMillis: 1_000,
      lastSeenAtMillis: 2_000
    )
    let replacement = evolutionItem(
      "new",
      topic: "Project SignalASI iOS memory",
      value: "SignalASI iOS memory now uses durable context",
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
      topic: "Project SignalASI iOS memory",
      value: "SignalASI iOS memory uses context",
      confidence: 0.7,
      evidenceProvenance: [GlobalEvidenceRef(eventId: "old-event", conversationId: "chat-a", timestampMillis: 1_000)],
      lastSeenAtMillis: 2_000,
      expiresAtMillis: 9_000
    )
    let incoming = evolutionItem(
      "incoming",
      topic: "Project SignalASI iOS memory",
      value: "SignalASI iOS memory uses context",
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
      topic: "Project SignalASI iOS decision",
      value: "Use durable context compiler",
      evidenceEventIds: ["event-old"],
      evidenceProvenance: [GlobalEvidenceRef(eventId: "event-old", conversationId: "chat-a", timestampMillis: 1_000)],
      lastSeenAtMillis: 2_000
    )
    let deprecated = evolutionItem(
      "old",
      kind: .decision,
      topic: "Project SignalASI iOS decision",
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
      topic: "Project SignalASI iOS decision",
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
    namespaceId: String = "signalasi-ios",
    topic: String = "Project SignalASI iOS memory",
    value: String = "SignalASI iOS memory value",
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
