import XCTest
@testable import GalaxySSI

final class GlobalMemoryEvolutionStoreTests: XCTestCase {
  func testGlobalMemoryEvolutionCodecRoundTripsInboxAuditAndRecordsWithAndroidKeys() throws {
    let candidate = GlobalMemoryCandidate(
      id: "candidate",
      sourceEventId: "event-a",
      conversationId: "chat-a",
      kind: .goal,
      temporalState: .pending,
      risk: .reviewRequired,
      status: .pendingReview,
      action: .create,
      targetItemIds: ["target-a"],
      item: storeItem("item-a", kind: .goal, temporalState: .planned),
      reason: "needs_review",
      createdAtMillis: 2_000,
      reviewedAtMillis: 0
    )
    let inbox = GlobalMemoryInbox(
      candidates: [candidate],
      processedEventIds: ["event-a"],
      updatedAtMillis: 3_000
    )
    let audit = GlobalMemoryAuditReport(
      findings: [
        GlobalMemoryAuditFinding(
          kind: .staleCandidate,
          stableKey: "memory-inbox",
          summary: "1 memory candidates are still awaiting review",
          evidenceCount: 1
        )
      ],
      themes: [
        GlobalMemoryTheme(
          id: "theme-a",
          title: "Project GalaxySSI",
          itemStableKeys: ["project:ios\u{0000}item-a"],
          itemCount: 2,
          evidenceCount: 4,
          conversationCount: 2,
          confidence: 0.84,
          lastUpdatedAtMillis: 4_000
        )
      ],
      auditedItemCount: 9,
      createdAtMillis: 5_000
    )
    let record = storeRecord("record-a", createdAtMillis: 6_000)

    let encodedInbox = GlobalMemoryEvolutionCodec.encodeInbox(inbox)
    let encodedAudit = GlobalMemoryEvolutionCodec.encodeAudit(audit)
    let encodedRecords = GlobalMemoryEvolutionCodec.encodeRecords([record])
    let restoredInbox = GlobalMemoryEvolutionCodec.decodeInbox(encodedInbox)
    let restoredAudit = GlobalMemoryEvolutionCodec.decodeAudit(encodedAudit)
    let restoredRecords = GlobalMemoryEvolutionCodec.decodeRecords(encodedRecords)

    XCTAssertTrue(encodedInbox.contains(#""processed_event_ids":["event-a"]"#))
    XCTAssertTrue(encodedInbox.contains(#""target_item_ids":["target-a"]"#))
    XCTAssertTrue(encodedInbox.contains(#""reviewed_at_millis":0"#))
    XCTAssertTrue(encodedAudit.contains(#""audited_item_count":9"#))
    XCTAssertTrue(encodedAudit.contains(#""item_stable_keys":["project:ios\u0000item-a"]"#))
    XCTAssertTrue(encodedRecords.contains(#""resulting_item_id":"item-a""#))
    XCTAssertEqual(restoredInbox.candidates.first?.item.memoryNamespaceKey, "project:ios")
    XCTAssertEqual(restoredAudit.findings.first?.kind, .staleCandidate)
    XCTAssertEqual(restoredRecords.first?.outcome, .applied)
  }

  func testGlobalMemoryEvolutionCodecBoundsAndToleratesInvalidPayloads() {
    let inbox = GlobalMemoryInbox(
      candidates: (0..<1_005).map { index in
        GlobalMemoryCandidate(
          id: "candidate-\(index)",
          sourceEventId: "event-\(index)",
          conversationId: "chat-a",
          kind: .fact,
          temporalState: .pending,
          risk: .reviewRequired,
          status: .pendingReview,
          item: storeItem("item-\(index)"),
          reason: "needs_review",
          createdAtMillis: Int64(index)
        )
      },
      processedEventIds: (0..<4_010).map { "event-\($0)" },
      updatedAtMillis: 9_000
    )
    let records = (0..<2_010).map { storeRecord("record-\($0)", createdAtMillis: Int64($0)) }

    let boundedInbox = GlobalMemoryEvolutionCodec.decodeInbox(GlobalMemoryEvolutionCodec.encodeInbox(inbox))
    let boundedRecords = GlobalMemoryEvolutionCodec.decodeRecords(GlobalMemoryEvolutionCodec.encodeRecords(records))

    XCTAssertEqual(boundedInbox.candidates.count, 1_000)
    XCTAssertEqual(boundedInbox.processedEventIds.count, 4_000)
    XCTAssertEqual(boundedInbox.processedEventIds.first, "event-10")
    XCTAssertEqual(boundedRecords.count, 2_000)
    XCTAssertEqual(boundedRecords.first?.id, "record-10")
    XCTAssertEqual(GlobalMemoryEvolutionCodec.decodeInbox("{broken").candidates.count, 0)
    XCTAssertEqual(GlobalMemoryEvolutionCodec.decodeAudit("").findings.count, 0)
    XCTAssertEqual(GlobalMemoryEvolutionCodec.decodeRecords("not-json").count, 0)
  }

  func testGlobalMemoryEvolutionStoreAppendsDedupesExportsAndRestores() {
    let suiteName = "GlobalMemoryEvolutionStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = GlobalMemoryEvolutionStore(defaults: defaults)
    let inbox = GlobalMemoryInbox(
      candidates: [
        GlobalMemoryCandidate(
          id: "candidate",
          sourceEventId: "event-a",
          conversationId: "chat-a",
          kind: .fact,
          temporalState: .pending,
          risk: .reviewRequired,
          status: .pendingReview,
          item: storeItem("item-a"),
          reason: "needs_review",
          createdAtMillis: 1_000
        )
      ],
      processedEventIds: ["event-a"],
      updatedAtMillis: 2_000
    )
    let audit = GlobalMemoryAuditReport(
      findings: [
        GlobalMemoryAuditFinding(kind: .duplicate, stableKey: "item-a", summary: "Merged", evidenceCount: 2)
      ],
      auditedItemCount: 1,
      createdAtMillis: 3_000
    )
    let old = storeRecord("duplicate-record", createdAtMillis: 1_000, resultingItemId: "old")
    let replacement = storeRecord("duplicate-record", createdAtMillis: 4_000, resultingItemId: "new")
    let later = storeRecord("later-record", createdAtMillis: 5_000, resultingItemId: "later")

    store.saveInbox(inbox)
    store.saveAudit(audit)
    store.appendEvolutionRecords([old])
    store.appendEvolutionRecords([replacement, later])
    let archive = store.exportArchive()

    XCTAssertEqual(store.inbox().processedEventIds, ["event-a"])
    XCTAssertEqual(store.auditReport().findings.first?.kind, .duplicate)
    XCTAssertEqual(store.evolutionRecords().map(\.id), ["duplicate-record", "later-record"])
    XCTAssertEqual(store.evolutionRecords().first?.resultingItemId, "new")
    XCTAssertEqual(archive.records.count, 2)

    store.clear()
    XCTAssertTrue(store.inbox().candidates.isEmpty)
    store.restore(GlobalMemoryEvolutionCodec.encodeArchive(archive))

    XCTAssertEqual(store.inbox().candidates.first?.id, "candidate")
    XCTAssertEqual(store.auditReport().auditedItemCount, 1)
    XCTAssertEqual(store.evolutionRecords().map(\.resultingItemId), ["new", "later"])
  }

  private func storeItem(
    _ id: String,
    kind: GlobalWorldItemKind = .fact,
    temporalState: GlobalMemoryTemporalState = .current
  ) -> GlobalWorldItem {
    GlobalWorldItem(
      id: id,
      stableKey: "\(id)-stable",
      kind: kind,
      layer: .topic,
      namespace: .project,
      namespaceId: "ios",
      topic: "Project GalaxySSI iOS memory",
      value: "GalaxySSI iOS memory value",
      confidence: 0.8,
      evidenceCount: 1,
      conversationIds: ["chat-a"],
      evidenceEventIds: ["event-\(id)"],
      evidenceProvenance: [GlobalEvidenceRef(eventId: "event-\(id)", conversationId: "chat-a", timestampMillis: 1_000)],
      temporalState: temporalState,
      firstSeenAtMillis: 1_000,
      lastSeenAtMillis: 1_000
    )
  }

  private func storeRecord(
    _ id: String,
    createdAtMillis: Int64,
    resultingItemId: String = "item-a"
  ) -> GlobalMemoryEvolutionRecord {
    GlobalMemoryEvolutionRecord(
      id: id,
      sourceEventId: "event-\(id)",
      conversationId: "chat-a",
      candidateId: "candidate-\(id)",
      kind: .fact,
      action: .create,
      outcome: .applied,
      temporalState: .current,
      subject: "Project GalaxySSI iOS memory",
      targetItemIds: ["target-\(id)"],
      resultingItemId: resultingItemId,
      evidenceCount: 1,
      createdAtMillis: createdAtMillis
    )
  }
}
