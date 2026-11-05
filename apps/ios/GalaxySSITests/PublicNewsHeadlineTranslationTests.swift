import XCTest
@testable import GalaxySSI

final class PublicNewsHeadlineTranslationTests: XCTestCase {
  private let translation = "\u{53D1}\u{5E03}\u{65B0}\u{7248}\u{672C} 2.4.1"

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
