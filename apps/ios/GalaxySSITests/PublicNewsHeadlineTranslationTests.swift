import XCTest
@testable import GalaxySSI

final class PublicNewsHeadlineTranslationTests: XCTestCase {
  private let translation = "\u{53D1}\u{5E03}\u{65B0}\u{7248}\u{672C} 2.4.1"

  func testAutomaticPreferenceIsIndependentAndVisibleTitlesTakePriority() {
    XCTAssertFalse(PublicNewsAutomaticHeadlinePolicy.enabled(false, language: LanguagePolicySettings.zhCN))
    XCTAssertFalse(PublicNewsAutomaticHeadlinePolicy.enabled(true, language: LanguagePolicySettings.enUS))
    XCTAssertTrue(PublicNewsAutomaticHeadlinePolicy.enabled(true, language: LanguagePolicySettings.zhCN))
    let first = fixture()
    let second = PublicNewsArticle(url: URL(string: "https://example.com/b")!,
      title: "Research team announces a new release", summary: "", publisher: "", discoveredAt: Date())
    XCTAssertEqual(PublicNewsAutomaticHeadlinePolicy.candidates([first, second], visible: [second.id]).map(\.id),
      [second.id, first.id])
  }

  func testDurableRetryLeaseRejectsStaleCompletionAndOnlyDelaysTheFailedTitle() throws {
    let article = fixture()
    var changed = article
    changed.title += " today"
    let key = PublicNewsHeadlineRetryLedger.key(article)
    let other = PublicNewsHeadlineRetryLedger.key(changed)
    XCTAssertNotEqual(key, other)
    let now = Date(timeIntervalSince1970: 100)
    var ledger = PublicNewsHeadlineRetryLedger()
    let lease = ledger.claim([key, other], at: now, retaining: [key, other])
    ledger = try JSONDecoder().decode(PublicNewsHeadlineRetryLedger.self, from: JSONEncoder().encode(ledger))
    XCTAssertFalse(ledger.ready(key, at: now))
    ledger.finish(key, lease: UUID(), at: now, reason: nil)
    XCTAssertEqual(ledger.entries[key]?.lease, lease)
    ledger.finish(key, lease: lease, at: now, reason: "preserve_exact_numbers_and_versions")
    ledger.finish(other, lease: lease, at: now, reason: nil)
    XCTAssertTrue(ledger.ready(other, at: now))
    XCTAssertFalse(ledger.ready(key, at: now))
    XCTAssertTrue(ledger.ready(key, at: now.addingTimeInterval(30)))
    XCTAssertEqual(ledger.entries[key]?.reason, "preserve_exact_numbers_and_versions")
  }

  func testStructuredCloudResultsValidateEachItemAndProduceTargetedFeedback() {
    let article = fixture()
    let valid = #"{"items":[{"id":0,"translation":"\#(translation)"}]}"#
    XCTAssertEqual(PublicNewsAutomaticHeadlinePolicy.read(valid, articles: [article]).translations[0], translation)
    let invalid = valid.replacingOccurrences(of: "2.4.1", with: "2.4.2")
    XCTAssertEqual(PublicNewsAutomaticHeadlinePolicy.read(invalid, articles: [article]).feedback[0],
      "preserve_exact_numbers_and_versions")
    let duplicated = #"{"items":[{"id":0,"translation":"\#(translation)"},{"id":0,"translation":"\#(translation)"}]}"#
    let result = PublicNewsAutomaticHeadlinePolicy.read(duplicated, articles: [article])
    XCTAssertTrue(result.translations.isEmpty)
    XCTAssertEqual(result.feedback[0], "include_each_id_once")
  }

  func testHeadlineNumbersAllowEquivalentCountsAndMonthsWithoutRelaxingLiterals() {
    let source = "Twenty-one teams launch version 2.4.1 on Sept. 15"
    XCTAssertTrue(PublicNewsHeadlineNumbers.preserved(original: source, translated: "21 2.4.1 9 15"))
    XCTAssertTrue(PublicNewsHeadlineNumbers.preserved(original: source, translated: "2.4.1 15"))
    for invalid in ["20 2.4.1 9 15", "21 2.4.2 9 15", "21 2.4.1 9", "21 21 2.4.1 9 15"] {
      XCTAssertFalse(PublicNewsHeadlineNumbers.preserved(original: source, translated: invalid), invalid)
    }
    XCTAssertFalse(PublicNewsHeadlineNumbers.preserved(original: "One hundred teams", translated: "1"))
    XCTAssertFalse(PublicNewsHeadlineNumbers.preserved(original: "Two devices use 2 and 2.0", translated: "2 2"))
    let shortTitle = "iPhone 17 Pro review"
    XCTAssertEqual(PublicNewsHeadlineTranslator.validate("iPhone 17 Pro \u{8BC4}\u{6D4B}", source: shortTitle),
      "iPhone 17 Pro \u{8BC4}\u{6D4B}")
    XCTAssertEqual(PublicNewsHeadlineTranslator.rejection(
      "\u{8BC4}\u{6D4B} 17 https://example.com", source: shortTitle), "remove_unexpected_markup")
  }

  func testPreviousValidatorBackoffRecoversWithoutBypassingAnActiveLeaseOrPermissionBackoff() throws {
    let now = Date(timeIntervalSince1970: 100)
    var current = PublicNewsHeadlineRetryLedger()
    let lease = current.claim(["validation", "permission", "active"], at: now, retaining: ["validation", "permission", "active"])
    current.finish("validation", lease: lease, at: now, reason: "preserve_exact_numbers_and_versions")
    current.finish("permission", lease: lease, at: now, reason: "disclosure_blocked")

    let data = try JSONEncoder().encode(current)
    let dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var entries = try XCTUnwrap(dictionary["entries"] as? [String: [String: Any]])
    for key in Array(entries.keys) { entries[key]?.removeValue(forKey: "validatorRevision") }
    let legacy = try JSONSerialization.data(withJSONObject: ["entries": entries])
    var reopened = try JSONDecoder().decode(PublicNewsHeadlineRetryLedger.self, from: legacy)
    XCTAssertTrue(reopened.ready("validation", at: now))
    XCTAssertFalse(reopened.ready("permission", at: now))
    XCTAssertFalse(reopened.ready("active", at: now))
    let renewed = reopened.claim(["validation"], at: now, retaining: ["validation", "permission", "active"])
    XCTAssertEqual(reopened.entries["validation"]?.attempts, 1)
    reopened.finish("validation", lease: renewed, at: now, reason: "preserve_exact_numbers_and_versions")
    XCTAssertFalse(reopened.ready("validation", at: now))
  }

  func testValidationKeepsVersionsAndRejectsUntranslatedOrMultilineOutput() {
    let source = "Publisher releases new version 2.4.1"
    XCTAssertEqual(PublicNewsHeadlineTranslator.validate(translation, source: source), translation)
    XCTAssertNil(PublicNewsHeadlineTranslator.validate(translation.replacingOccurrences(of: "2.4.1", with: "2.4.2"), source: source))
    XCTAssertNil(PublicNewsHeadlineTranslator.validate(translation + "\n" + translation, source: source))
    XCTAssertNil(PublicNewsHeadlineTranslator.validate(source, source: source))
  }

  func testPairedHeadlineBatchSurvivesReopenAndRejectsForeignOrExpiredReplies() throws {
    let article = fixture()
    let now = Date(timeIntervalSince1970: 100)
    let key = PublicNewsHeadlineRetryLedger.key(article)
    var ledger = PublicNewsHeadlineRetryLedger()
    let lease = ledger.claim([key], at: now, retaining: [key])
    ledger.paired = .init(id: "batch", source: 42, profile: "owner", desktop: "desktop", contact: "contact",
      route: "route", agent: "codex", expiresAt: now.addingTimeInterval(900), lease: lease,
      items: [.init(articleID: article.id, original: article.title, key: key)])
    let reopened = try JSONDecoder().decode(PublicNewsHeadlineRetryLedger.self, from: JSONEncoder().encode(ledger))
    var batch = try XCTUnwrap(reopened.paired)
    let reply = AgentConnectorResponse(sourceMessageId: 42, contactId: "contact",
      content: #"{"items":[{"id":0,"translation":"\#(translation)"}]}"#,
      conversationId: batch.conversation, turnId: batch.id, taskId: batch.id, outputTokens: 12, taskStatus: "completed")
    XCTAssertTrue(batch.matches(reply, desktop: "desktop", route: "route", agent: "codex", profile: "owner", now: now))
    XCTAssertFalse(batch.matches(reply, desktop: "other", route: "route", agent: "codex", profile: "owner", now: now))
    XCTAssertFalse(batch.matches(reply, desktop: "desktop", route: "other", agent: "codex", profile: "owner", now: now))
    XCTAssertFalse(batch.matches(reply, desktop: "desktop", route: "route", agent: "codex", profile: "other", now: now))
    XCTAssertFalse(batch.matches(reply, desktop: "desktop", route: "route", agent: "codex", profile: "owner",
      now: batch.expiresAt))
    var wrongTurn = reply
    wrongTurn.turnId = "other"
    XCTAssertFalse(batch.matches(wrongTurn, desktop: "desktop", route: "route", agent: "codex", profile: "owner", now: now))

    var unknownID = reply
    unknownID.content = #"{"items":[{"id":9,"translation":"\#(translation)"}]}"#
    var rejected = batch
    rejected.recordReply(unknownID)
    XCTAssertEqual(rejected.reply?.feedback[0], "copy_only_requested_ids")
    var fenced = reply
    let fence = String(repeating: "\u{60}", count: 3)
    fenced.content = fence + "json\n" + reply.content + "\n" + fence
    batch.recordReply(fenced)
    batch.recordReply(unknownID)
    XCTAssertEqual(batch.reply?.translations[0], translation)
    XCTAssertEqual(batch.usage?.output, 12)
    let payload: [String: Any] = ["type": "text", "conversation_id": batch.conversation]
    XCTAssertTrue(GalaxySSITransportPrivacyPolicy.isLocalOnly(payload))
    XCTAssertFalse(GalaxySSITransportPrivacyPolicy.isLocalOnly(payload, trustedBackgroundCognitionAuthorized: true))
  }

  func testPairedHeadlineProvenanceKeepsTheLegacyArchiveReadable() throws {
    struct Legacy: Decodable { let provider: String }
    let title = PublicNewsHeadlineTranslation(source: fixture().title, chinese: translation, provider: .pairedDesktop)
    let data = try JSONEncoder().encode(title)
    XCTAssertEqual(try JSONDecoder().decode(Legacy.self, from: data).provider, "cloud")
    XCTAssertEqual(try JSONDecoder().decode(PublicNewsHeadlineTranslation.self, from: data), title)
  }

  @MainActor
  func testCacheKeepsProvenanceAndRejectsObsoleteOrDuplicateCallback() throws {
    struct Fixture: Encodable { let articles: [PublicNewsArticle] }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: PublicNewsRowArchive.directory(for: file))
      try? FileManager.default.removeItem(at: file)
    }
    var article = fixture()
    try JSONEncoder().encode(Fixture(articles: [article])).write(to: file)
    let archive = PublicNewsArchive(fileURL: file)
    archive.load()
    XCTAssertFalse(archive.storeHeadline(translation, for: article.id, source: "Stale version 2.4.1", provider: .apple))
    XCTAssertTrue(archive.storeHeadline(translation, for: article.id, source: article.title, provider: .apple))
    XCTAssertFalse(archive.storeHeadline(translation, for: article.id, source: article.title, provider: .localModel))
    let reopened = PublicNewsArchive(fileURL: file)
    reopened.load()
    let stored = try XCTUnwrap(reopened.articles.first)
    XCTAssertEqual(stored.displayTitle, translation)
    XCTAssertEqual(stored.headlineTranslation?.provider, .apple)
    XCTAssertEqual(PublicNewsArchive.merge(existing: [stored], incoming: [article]).first?.displayTitle, translation)
    article.title = "Publisher releases new version 2.4.2"
    XCTAssertEqual(PublicNewsArchive.merge(existing: [stored], incoming: [article]).first?.displayTitle, article.title)
  }

  func testSearchMatchesBothTitleVersions() throws {
    var article = fixture()
    article.headlineTranslation = .init(source: article.title, chinese: translation, provider: .localModel)
    let translated = try PublicNewsSearch.index(.init(text: "\u{7248}\u{672C}"), articles: [article], now: Date())
    let original = try PublicNewsSearch.index(.init(text: "releases"), articles: [article], now: Date())
    XCTAssertEqual(translated.articles.map(\.id), [article.id])
    XCTAssertEqual(original.articles.map(\.id), [article.id])
  }

  private func fixture() -> PublicNewsArticle {
    .init(url: URL(string: "https://example.com/a")!, title: "Publisher releases new version 2.4.1",
      summary: "Summary", publisher: "Fixture", discoveredAt: Date())
  }
}
