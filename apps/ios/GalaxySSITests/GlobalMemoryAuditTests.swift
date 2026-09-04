import XCTest
@testable import GalaxySSI

final class GlobalMemoryAuditTests: XCTestCase {
  func testGlobalMemoryCriticRetiresExpiredAndReportsOperationalFindings() {
    let day: Int64 = 24 * 60 * 60 * 1_000
    let expired = auditItem(
      "expired",
      topic: "Temporary device state",
      value: "Battery state was charging",
      expiresAtMillis: day,
      lastSeenAtMillis: day
    )
    let lowConfidence = auditItem(
      "low-confidence",
      topic: "Repeated uncertain capability",
      value: "Model support might be available",
      confidence: 0.42,
      evidenceCount: 3
    )
    let conflictA = auditItem(
      "conflict-a",
      topic: "Project GalaxySSI route",
      value: "Route A is active",
      evidenceCount: 2,
      status: .conflicted,
      temporalState: .conflicted,
      conflictGroupId: "route-conflict"
    )
    let conflictB = auditItem(
      "conflict-b",
      topic: "Project GalaxySSI route",
      value: "Route B is active",
      evidenceCount: 4,
      status: .conflicted,
      temporalState: .conflicted,
      conflictGroupId: "route-conflict"
    )
    let decision = auditItem(
      "skill",
      kind: .decision,
      topic: "Repeated workflow",
      value: "Use the same workflow repeatedly",
      evidenceCount: 3
    )
    let completedGoal = auditItem(
      "goal",
      kind: .goal,
      topic: "Finished milestone",
      value: "The milestone is complete",
      evidenceCount: 2,
      status: .completed,
      temporalState: .historical
    )
    let stale = GlobalMemoryCandidate(
      id: "stale",
      sourceEventId: "stale-event",
      conversationId: "chat-a",
      kind: .fact,
      temporalState: .pending,
      risk: .reviewRequired,
      status: .pendingReview,
      item: auditItem("candidate"),
      reason: "needs_review",
      createdAtMillis: 1_000
    )

    let result = GlobalMemoryCritic.audit(
      world: PersonalWorldModel(items: [expired, lowConfidence, conflictA, conflictB, decision, completedGoal]),
      inbox: GlobalMemoryInbox(candidates: [stale]),
      nowMillis: day * 40
    )
    let findings = Set(result.report.findings.map(\.kind))
    let byId = Dictionary(uniqueKeysWithValues: result.world.items.map { ($0.id, $0) })

    XCTAssertEqual(byId["expired"]?.status, .superseded)
    XCTAssertEqual(byId["expired"]?.temporalState, .deprecated)
    XCTAssertTrue(findings.isSuperset(of: [
      .expired,
      .lowConfidenceReused,
      .unresolvedConflict,
      .skillCandidate,
      .completedGoal,
      .staleCandidate
    ]))
    XCTAssertEqual(result.report.findings.first { $0.kind == .unresolvedConflict }?.evidenceCount, 6)
    XCTAssertEqual(result.report.findings.first { $0.kind == .staleCandidate }?.stableKey, "memory-inbox")
    XCTAssertEqual(result.report.auditedItemCount, 6)
    XCTAssertEqual(result.report.createdAtMillis, day * 40)
  }

  func testGlobalMemoryCriticConsolidatesDuplicatesAndBuildsThemes() {
    let newer = auditItem(
      "newer",
      namespaceId: "memory-dedupe",
      topic: "Project GalaxySSI iOS memory",
      value: "Durable context compiler is active",
      evidenceProvenance: [GlobalEvidenceRef(eventId: "newer-event", conversationId: "chat-a")],
      lastSeenAtMillis: 6_000
    )
    let duplicate = auditItem(
      "duplicate",
      namespaceId: "memory-dedupe",
      topic: "Project GalaxySSI iOS memory",
      value: "Durable context compiler is active",
      evidenceProvenance: [GlobalEvidenceRef(eventId: "duplicate-event", conversationId: "chat-b")],
      lastSeenAtMillis: 5_000
    )
    let themeA = auditItem(
      "theme-a",
      kind: .task,
      namespaceId: "audit-theme",
      topic: "Project GalaxySSI iOS audit",
      value: "Audit task uses finding models",
      conversationIds: ["chat-a"],
      lastSeenAtMillis: 4_000
    )
    let themeB = auditItem(
      "theme-b",
      kind: .goal,
      namespaceId: "audit-theme",
      topic: "Project GalaxySSI iOS audit",
      value: "Audit goal keeps durable memory healthy",
      conversationIds: ["chat-b"],
      temporalState: .planned,
      lastSeenAtMillis: 3_000
    )
    let themeC = auditItem(
      "theme-c",
      kind: .preference,
      namespaceId: "audit-theme",
      topic: "Project GalaxySSI iOS audit",
      value: "Audit preference favors reviewed records",
      conversationIds: ["chat-c"],
      lastSeenAtMillis: 2_000
    )

    let result = GlobalMemoryCritic.audit(
      world: PersonalWorldModel(items: [duplicate, themeA, newer, themeB, themeC]),
      inbox: GlobalMemoryInbox(),
      nowMillis: 8_000
    )
    let byId = Dictionary(uniqueKeysWithValues: result.world.items.map { ($0.id, $0) })
    let duplicateFinding = result.report.findings.first { $0.kind == .duplicate }
    let theme = result.report.themes.first

    XCTAssertEqual(byId["newer"]?.status, .active)
    XCTAssertEqual(byId["newer"]?.supersedesItemIds, ["duplicate"])
    XCTAssertEqual(byId["newer"]?.evidenceEventIds, ["newer-event", "duplicate-event"])
    XCTAssertEqual(byId["duplicate"]?.status, .superseded)
    XCTAssertEqual(byId["duplicate"]?.supersededByItemId, "newer")
    XCTAssertEqual(duplicateFinding?.stableKey, "newer-stable")
    XCTAssertEqual(theme?.title, "Project GalaxySSI iOS audit")
    XCTAssertEqual(theme?.itemCount, 3)
    XCTAssertEqual(theme?.conversationCount, 3)
    XCTAssertEqual(theme?.itemStableKeys.count, 3)
  }

  func testGlobalMemoryCriticDueAndNextAuditAtMatchAndroidPolicy() {
    let day: Int64 = 24 * 60 * 60 * 1_000

    XCTAssertTrue(GlobalMemoryCritic.due(lastAuditMillis: 0, processedEvents: 0, nowMillis: day))
    XCTAssertTrue(GlobalMemoryCritic.due(lastAuditMillis: day, processedEvents: 20, nowMillis: day + 1))
    XCTAssertTrue(GlobalMemoryCritic.due(lastAuditMillis: day, processedEvents: 1, nowMillis: day * 3))
    XCTAssertFalse(GlobalMemoryCritic.due(lastAuditMillis: day, processedEvents: 1, nowMillis: day + 1_000))
    XCTAssertEqual(GlobalMemoryCritic.nextAuditAt(lastAuditMillis: 0, nowMillis: day), day)
    XCTAssertEqual(GlobalMemoryCritic.nextAuditAt(lastAuditMillis: day, nowMillis: day + 1_000), day * 2)
    XCTAssertEqual(GlobalMemoryCritic.nextAuditAt(lastAuditMillis: day, nowMillis: day * 3), day * 3)
  }

  func testGlobalMemoryAuditModelsUseAndroidWireNames() throws {
    let finding = GlobalMemoryAuditFinding(
      kind: .duplicate,
      stableKey: "memory-key",
      summary: "Equivalent evidence was consolidated",
      evidenceCount: 4
    )
    let theme = GlobalMemoryTheme(
      id: "theme",
      title: "Project GalaxySSI",
      itemStableKeys: ["project:ios\u{0000}memory"],
      itemCount: 3,
      evidenceCount: 8,
      conversationCount: 2,
      confidence: 0.88,
      lastUpdatedAtMillis: 7_000
    )
    let report = GlobalMemoryAuditReport(
      findings: [finding],
      themes: [theme],
      auditedItemCount: 9,
      createdAtMillis: 10_000
    )
    let encoded = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
    let restored = try JSONDecoder().decode(GlobalMemoryAuditReport.self, from: Data(encoded.utf8))

    XCTAssertTrue(encoded.contains(#""stable_key":"memory-key""#))
    XCTAssertTrue(encoded.contains(#""evidence_count":4"#))
    XCTAssertTrue(encoded.contains(#""item_stable_keys":["project:ios\u0000memory"]"#))
    XCTAssertTrue(encoded.contains(#""conversation_count":2"#))
    XCTAssertTrue(encoded.contains(#""last_updated_at_millis":7000"#))
    XCTAssertTrue(encoded.contains(#""audited_item_count":9"#))
    XCTAssertTrue(encoded.contains(#""created_at_millis":10000"#))
    XCTAssertEqual(restored.findings.first?.kind, .duplicate)
    XCTAssertEqual(restored.themes.first?.confidence, 0.88)
  }

  private func auditItem(
    _ id: String,
    kind: GlobalWorldItemKind = .fact,
    layer: GlobalWorldLayer = .topic,
    namespace: GlobalMemoryNamespace = .project,
    namespaceId: String = "galaxyssi-ios",
    topic: String = "Project GalaxySSI iOS memory",
    value: String = "GalaxySSI iOS memory value",
    confidence: Double = 0.82,
    contextVisibility: GlobalWorldContextVisibility = .shareable,
    evidenceCount: Int = 1,
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
      evidenceCount: evidenceCount,
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
