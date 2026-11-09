import Foundation
import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthVisitJournalDiscussionTests: XCTestCase {
  @MainActor func testScopedJournalToolRequiresApprovalAndRecoversLongFieldsExactly() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let records = GalaxySSIHealthRecords(owner: "journal-discussion-fixture", secrets: InMemorySecretStore(),
      isolatedFile: root.appendingPathComponent("health"))
    let now = Date(), visit = UUID()
    try records.write(.init(metric: .glucose, measuredAt: now.addingTimeInterval(-600), value: 110,
      unitOverride: "mg/dL", referenceInterval: "70 - 99"))
    try records.setPrivacy(.localCare, enabled: true)
    try records.reconcileLocalCare(now: now)
    let concern = try XCTUnwrap(records.load().localCare?.current["glucose"])
    let encounter = try records.localCareEncounterPage(id: concern.id, metric: .glucose, now: now)
    _ = try records.saveLocalCareEncounter(.init(purpose: "Synthetic visit", facility: "Not shared",
      state: .attended, attendedAt: now), id: visit, operation: UUID(), expected: encounter.stamp, expectedEntry: nil, now: now)
    func page() throws -> GalaxySSIHealthVisitJournal.Page {
      try records.visitJournal(concern: concern.id, metric: .glucose, visit: visit, now: now)
    }
    _ = try records.saveVisitJournal(.init(kind: .start, goal: "Synthetic goal"), operation: UUID(), expected: page(), now: now)
    let long = String(repeating: "\u{6F22}", count: 1_900)
    let latest = try records.saveVisitJournal(.init(kind: .checkIn, note: long), operation: UUID(), expected: page(), now: now)
    let model = CloudModelConfig(id: "fixture", displayName: "Fixture", provider: "Custom", modelId: "model",
      endpoint: "https://example.test/v1/chat/completions", apiStyle: .openAICompatible, keychainAccount: "", updatedAt: now)
    let contact = GalaxySSIContact(id: "cloud-fixture", galaxySSIId: "cloud-fixture", name: "Fixture", displayName: "Fixture",
      type: "agent", agentKind: "cloud-api", deliveryMode: .cloudAPI, trustState: .verified, desktopId: "", desktopName: "",
      identityFingerprint: "", setupStatus: "ready", setupDetail: "", cloudProvider: "Custom", cloudModels: [model],
      selectedCloudModelId: model.id, deleted: false, createdAt: now, updatedAt: now)
    func approve(_ destination: GalaxySSIContact = contact) throws -> GalaxySSIHealthVisitJournalRead.Approval {
      try records.prepareVisitJournalDiscussion(page(), question: "What did I report?", contact: destination,
        key: "fixture-api-key", now: now)
    }
    XCTAssertThrowsError(try approve())
    try records.setHealthOnlinePermission(true)
    let review = try approve()
    let request = try GalaxySSIHealthCareDiscussion.request(review.transport, key: "fixture-api-key", journalRead: true)
    let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
    XCTAssertTrue(body.contains(GalaxySSIHealthVisitJournalRead.providerName))
    XCTAssertFalse(body.contains("Not shared"))
    XCTAssertFalse(body.contains(long))
    XCTAssertFalse(body.contains(GalaxySSIHealthCareFeedbackTool.function))
    var cursor = GalaxySSIHealthVisitJournalRead.Cursor()
    let revision: AgentMcpJSONValue = .int(Int64(review.binding.revision))
    let entry: AgentMcpJSONValue = .int(Int64(latest.entry.revision))
    var field: AgentMcpJSONObject = ["revision": revision, "entry_revision": entry, "field": .string("note")]
    func read(_ args: AgentMcpJSONObject) throws -> AgentMcpJSONObject {
      try records.visitJournalDiscussionRead(review, cursor: &cursor, arguments: args, now: now)
    }
    XCTAssertThrowsError(try read(["revision": revision]))
    try records.beginVisitJournalDiscussion(review, now: now)
    XCTAssertThrowsError(try records.beginVisitJournalDiscussion(review, now: now))
    XCTAssertThrowsError(try read(field))
    XCTAssertThrowsError(try read(["revision": revision, "journal": .string(UUID().uuidString)]))
    let first = try read(["revision": revision])
    XCTAssertEqual(first["clinical_improvement_verified"], .bool(false))
    XCTAssertEqual(first["items"]?.arrayValue?.first?.objectValue?["omitted_fields"], .array([.string("note")]))
    var restored = ""
    for _ in 0..<4 {
      let chunk = try read(field)
      restored += chunk.string("value")
      guard let next = chunk["next_offset"]?.intValue else { break }
      field["offset"] = .int(next)
    }
    XCTAssertEqual(restored, long)
    XCTAssertThrowsError(try read(field))
    try records.finishVisitJournalDiscussion(review, answer: "Saved synthetic reply", now: now)
    XCTAssertEqual(try approve().previous.first?.answer, "Saved synthetic reply")
    var other = contact
    other.id = "other-cloud-fixture"
    XCTAssertTrue(try approve(other).previous.isEmpty)
    let next = try approve()
    try records.beginVisitJournalDiscussion(next, now: now)
    try records.setHealthOnlinePermission(false)
    XCTAssertThrowsError(try records.validateActiveVisitJournalDiscussion(next, now: now))
    try records.setHealthOnlinePermission(true)
    XCTAssertTrue(try approve().previous.isEmpty)
    let providerReview = try approve()
    let disclosure = InMemoryAgentDataDisclosureStore()
    var sent = 0
    let output = try await GalaxySSIHealthVisitJournalDiscussionTransport.run(providerReview, records: records,
      ledger: disclosure, currentRoute: { (contact, "fixture-api-key") }, send: { request in
        sent += 1
        let json = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        if sent == 1 {
          XCTAssertFalse(json.contains("omitted_fields"))
          let args = AgentMcpJSONCodec.stringify(["revision": .int(Int64(providerReview.binding.revision))])
          return try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "tool_calls", "message": [
            "tool_calls": [["type": "function", "id": "read-one", "function": [
              "name": GalaxySSIHealthVisitJournalRead.providerName, "arguments": args]]]]]]])
        }
        XCTAssertTrue(json.contains("omitted_fields"))
        return Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"Scoped fixture reply"}}]}"#.utf8)
      })
    XCTAssertEqual(output, "Scoped fixture reply")
    XCTAssertEqual(sent, 2)
    XCTAssertEqual(try approve().previous.last?.answer, "Scoped fixture reply")
    try records.deleteVisitJournal(page(), now: now)
    XCTAssertNil(try records.load().localVisitJournalDiscussions?[visit])
  }
}
