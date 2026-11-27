import UIKit
import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSIHealthAnswerBasisTests: XCTestCase {
  typealias Basis = GalaxySSIHealthAnswerBasis

  func testOnlyBoundApprovedTurnsProjectMetadataNotQuestionOrAnswerCitations() throws {
    let f = try Fixture()
    let grant = try XCTUnwrap(f.turn().answerBasis)
    XCTAssertEqual(grant.binding.turn, f.approval.id)
    XCTAssertEqual(grant.conversation, f.conversation)
    XCTAssertEqual(grant.sources.filter { $0.kind == .measurement }.count, 1)
    XCTAssertFalse(grant.sources.contains { $0.kind == .profile || $0.kind == .retrieved })
    let encoded = String(decoding: try JSONEncoder().encode(grant), as: UTF8.self)
    XCTAssertFalse(encoded.contains(f.approval.question))
    XCTAssertFalse(encoded.contains("fabricated-model-source.example"))
    XCTAssertFalse(encoded.contains("fixture-api-key"))
  }

  func testUnknownLegacyBasisAndUnboundThreadsAreNotReconstructed() throws {
    let f = try Fixture()
    var thread = try XCTUnwrap(f.records.load().localCareDiscussions?[f.concern.id.uuidString])
    thread.agentConversationID = nil
    XCTAssertNil(Basis.capture(f.approval, concern: f.concern, thread: thread, archive: try f.records.load()))
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.turn())) as? [String: Any])
    object.removeValue(forKey: "answerBasis")
    let turn = try JSONDecoder().decode(GalaxySSIHealthCareDiscussion.Turn.self,
      from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNil(turn.answerBasis)
  }

  func testUnansweredAndForeignConversationOrTurnCannotReadBasis() throws {
    let f = try Fixture()
    XCTAssertNil(try f.display())
    try f.finish()
    XCTAssertNotNil(try f.display())
    XCTAssertNil(try f.records.localCareAnswerBasis(conversation: "ordinary", turn: f.approval.id,
      expanded: false, now: f.now))
    XCTAssertNil(try f.records.localCareAnswerBasis(conversation: f.conversation, turn: UUID(),
      expanded: false, now: f.now))
    let other = GalaxySSIHealthRecords(owner: "another-owner", secrets: f.secrets, isolatedFile: f.file)
    XCTAssertThrowsError(try other.localCareAnswerBasis(conversation: f.conversation, turn: f.approval.id,
      expanded: true, now: f.now))
  }

  func testExpiryAndEitherConsentRevocationHideAlreadySavedSources() throws {
    let f = try Fixture()
    try f.finish()
    XCTAssertNil(try f.display(now: f.now.addingTimeInterval(600)))
    XCTAssertNil(try f.display(now: f.now.addingTimeInterval(-1)))
    try f.records.setHealthOnlinePermission(false)
    XCTAssertNil(try f.display())
    let second = try Fixture()
    try second.finish()
    try second.records.setPrivacy(.localCare, enabled: false)
    XCTAssertNil(try second.display())
  }

  func testChangedRecordCannotExposeNamesOrCurrentBasis() throws {
    let f = try Fixture(report: true)
    try f.finish()
    XCTAssertNotNil(try f.display())
    var reading = try XCTUnwrap(f.records.load().current.first)
    reading.value = 117
    try f.records.write(reading)
    XCTAssertThrowsError(try f.display(expanded: true))
  }

  func testHistoryProjectionIsExactlyTheApprovedRecentPageAndKeepsUnitsOutOfMetadata() throws {
    let f = try Fixture(history: true)
    let sources = try XCTUnwrap(f.turn().answerBasis).sources.filter { $0.kind == .measurement }
    XCTAssertEqual(sources.count, 30)
    XCTAssertEqual(Set(sources.compactMap { $0.record?.id }).count, 30)
    XCTAssertFalse(String(decoding: try JSONEncoder().encode(sources), as: UTF8.self).contains("mg/dL"))
  }

  func testExpandedNameRequiresExactApprovedRecordTimestampRevisionAndFileIdentity() throws {
    let f = try Fixture(report: true)
    try f.finish()
    XCTAssertEqual(try f.display()?.sources.first?.title, "")
    XCTAssertEqual(try f.display(expanded: true)?.sources.first?.title, "synthetic-report.png")
    let archive = try f.records.load()
    var source = try XCTUnwrap(f.turn().answerBasis?.sources.first)
    source.at = source.at?.addingTimeInterval(1)
    XCTAssertTrue(try Basis.localNames([source], archive: archive, originals: f.records.visitOriginalStore)[0].title.isEmpty)
    source = try XCTUnwrap(f.turn().answerBasis?.sources.first)
    source.files = [.init(id: try XCTUnwrap(f.original).id, sha256: String(repeating: "0", count: 64))]
    XCTAssertTrue(try Basis.localNames([source], archive: archive, originals: f.records.visitOriginalStore)[0].title.isEmpty)
    source.files = [.init(id: UUID(), sha256: try XCTUnwrap(f.original).sha256)]
    XCTAssertTrue(try Basis.localNames([source], archive: archive, originals: f.records.visitOriginalStore)[0].title.isEmpty)
  }

  func testMissingOrReviewOnlyOriginalDoesNotRevealItsFilename() throws {
    let f = try Fixture(report: true)
    let source = try XCTUnwrap(f.turn().answerBasis?.sources.first)
    var archive = try f.records.load()
    archive.reviewOnlyReportOriginals = [try XCTUnwrap(f.original).id]
    XCTAssertTrue(try Basis.localNames([source], archive: archive, originals: f.records.visitOriginalStore)[0].title.isEmpty)
    let directory = try f.records.visitOriginalStore.dataFilesDirectory()
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    let originalID = try XCTUnwrap(f.original).id.uuidString
    for file in files where file.lastPathComponent == originalID {
      try FileManager.default.removeItem(at: file)
    }
    XCTAssertTrue(try Basis.localNames([source], archive: f.records.load(), originals: f.records.visitOriginalStore)[0].title.isEmpty)
  }

  func testRetrievedMetadataRequiresSameBindingAllowedURLHashAndObservedTimes() throws {
    let f = try Fixture()
    let grant = try XCTUnwrap(f.turn().answerBasis)
    let source = GalaxySSIHealthCareEvidence.PublicSource.labResults
    func receipt(_ binding: GalaxySSIHealthCareEvidence.Binding, url: URL, hash: String,
                 retrieved: Date, observed: Date) -> GalaxySSIHealthCareEvidence.Receipt {
      .init(binding: binding, url: url, title: "Synthetic public-source receipt", contentHash: hash,
        excerpt: String(repeating: "x", count: 100), retrievedAt: retrieved, observedAt: observed)
    }
    let valid = receipt(grant.binding, url: source.url, hash: String(repeating: "a", count: 64), retrieved: f.now, observed: f.now)
    XCTAssertEqual(Basis.retrieved([valid], grant: grant, now: f.now).first?.kind, .retrieved)
    let other = try Fixture()
    let foreign = receipt(.init(other.approval), url: source.url, hash: valid.contentHash, retrieved: f.now, observed: f.now)
    let forged = receipt(grant.binding, url: URL(string: "https://fabricated-model-source.example/")!,
      hash: valid.contentHash, retrieved: f.now, observed: f.now)
    let early = receipt(grant.binding, url: source.url, hash: valid.contentHash,
      retrieved: f.now.addingTimeInterval(-1), observed: f.now)
    let future = receipt(grant.binding, url: source.url, hash: valid.contentHash,
      retrieved: f.now, observed: f.now.addingTimeInterval(1))
    let badHash = receipt(grant.binding, url: source.url, hash: "wrong", retrieved: f.now, observed: f.now)
    for invalid in [foreign, forged, early, future, badHash] {
      XCTAssertTrue(Basis.retrieved([invalid], grant: grant, now: f.now).isEmpty)
    }
  }

  func testStoredBasisIsEncryptedAndContextDoesNotInferFastingDuration() throws {
    let f = try Fixture(context: true)
    let turn = try f.turn()
    XCTAssertTrue(turn.answerBasis?.sources.contains { $0.kind == .context } == true)
    XCTAssertEqual(f.concern.context?.answers?.collection, .fasting)
    XCTAssertNil(f.concern.context?.answers?.fastingHours)
    let request = try GalaxySSIHealthCareDiscussion.request(f.approval, key: "fixture-api-key")
    let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
    XCTAssertTrue(body.contains("only if"))
    let bytes = try Data(contentsOf: f.file)
    XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("answerBasis"))
    let reopened = GalaxySSIHealthRecords(owner: f.records.owner, secrets: f.secrets, isolatedFile: f.file)
    XCTAssertEqual(try reopened.load().localCareDiscussions?[f.concern.id.uuidString]?.turns.last?.answerBasis, turn.answerBasis)
  }

  @MainActor private final class Fixture {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let secrets = InMemorySecretStore()
    let records: GalaxySSIHealthRecords
    let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    let conversation = "health-basis-conversation"
    let concern: GalaxySSIHealthCare.Concern
    let approval: GalaxySSIHealthCareDiscussion.Approval
    let original: GalaxySSIHealthOriginalStore.Original?

    init(report: Bool = false, history: Bool = false, context: Bool = false) throws {
      records = .init(owner: "answer-basis-fixture", secrets: secrets, isolatedFile: file)
      if report {
        let data = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { drawing in
          UIColor.white.setFill(); drawing.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        try records.visitOriginalStore.store(data, name: "synthetic-report.png")
        original = try XCTUnwrap(records.visitOriginalStore.list().originals.first)
      } else { original = nil }
      for index in 0..<(history ? 36 : 1) {
        var reading = GalaxySSIHealthReading(metric: .glucose,
          measuredAt: now.addingTimeInterval(Double(-120 - index * 60)), value: 110, unitOverride: "mg/dL")
        if let original {
          reading.reportSource = .init(original: original.id, sha256: original.sha256, page: 1, region: 0, fromOCR: true)
        }
        try records.write(reading)
      }
      try records.setPrivacy(.localCare, enabled: true)
      try records.setHealthOnlinePermission(true)
      try records.reconcileLocalCare(now: now)
      var issue = try XCTUnwrap(records.load().localCare?.current["glucose"])
      if context {
        try records.setLocalCareContext(issue, applicability: .unknown,
          answers: .init(collection: .fasting), now: now)
        issue = try XCTUnwrap(records.load().localCare?.current["glucose"])
      }
      concern = issue
      let thread = try records.openLocalCareDiscussion(id: issue.id, metric: .glucose)
      try records.bindLocalCareAgentDiscussion(id: issue.id, metric: .glucose, threadID: thread.id,
        expectedConversationID: nil, conversationID: conversation)
      let model = CloudModelConfig(id: "fixture", displayName: "Fixture", provider: "Custom", modelId: "model",
        endpoint: "https://example.test/v1/chat/completions", apiStyle: .openAICompatible, keychainAccount: "", updatedAt: now)
      approval = try records.prepareLocalCareDiscussion(id: issue.id, metric: .glucose,
        question: "Synthetic approved question", destinationID: "provider", model: model,
        credential: "fixture-api-key", allowsHistory: history, now: now)
      try records.beginLocalCareDiscussionTurn(approval, now: now)
    }
    func turn() throws -> GalaxySSIHealthCareDiscussion.Turn {
      try XCTUnwrap(records.load().localCareDiscussions?[concern.id.uuidString]?.turns.last)
    }
    func finish() throws {
      try records.finishLocalCareDiscussionTurn(approval, answer: "Synthetic answer claiming fabricated-model-source.example", now: now)
    }
    func display(expanded: Bool = false, now: Date? = nil) throws -> Basis.Display? {
      try records.localCareAnswerBasis(conversation: conversation, turn: approval.id, expanded: expanded, now: now ?? self.now)
    }
    deinit {
      try? FileManager.default.removeItem(at: file)
      try? FileManager.default.removeItem(at: file.appendingPathExtension("visit-originals"))
    }
  }
}
