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

  func testValidationKeepsVersionsAndRejectsUntranslatedOrMultilineOutput() {
    let source = "Publisher releases new version 2.4.1"
    XCTAssertEqual(PublicNewsHeadlineTranslator.validate(translation, source: source), translation)
    XCTAssertNil(PublicNewsHeadlineTranslator.validate(translation.replacingOccurrences(of: "2.4.1", with: "2.4.2"), source: source))
    XCTAssertNil(PublicNewsHeadlineTranslator.validate(translation + "\n" + translation, source: source))
    XCTAssertNil(PublicNewsHeadlineTranslator.validate(source, source: source))
  }

  @MainActor
  func testCacheKeepsProvenanceAndRejectsObsoleteOrDuplicateCallback() throws {
    struct Fixture: Encodable { let articles: [PublicNewsArticle] }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
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
