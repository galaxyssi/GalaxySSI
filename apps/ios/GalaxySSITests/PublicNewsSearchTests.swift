import XCTest
@testable import GalaxySSI

final class PublicNewsSearchTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  func testLiteralTermsMatchAcrossFieldsWithCombinedFilters() throws {
    let word = "\u{6A21}\u{578B}"
    let articles = [
      article(1, title: "\(word) 100%_ok", summary: "New evaluation", saved: true),
      article(2, title: "\(word) 100%Xok", summary: "New evaluation", saved: true),
      article(3, title: "\(word) 100%_ok", summary: "New evaluation", publisher: "Other", saved: true),
      article(4, title: "\(word) 100%_ok", summary: "New evaluation", age: 8, saved: true),
      article(5, title: "\(word) 100%_ok", summary: "New evaluation")
    ]
    let query = PublicNewsSearchRequest(text: "\(word) 100%_ok PUBLISHER", scope: .saved,
      period: .week, publisher: "Publisher")
    let result = try PublicNewsSearch.index(query, articles: articles, now: now)
    XCTAssertEqual(result.articles.map(\.id), [articles[0].id])
  }

  func testStablePagesAndRelevanceVersusNewest() throws {
    var articles = (0..<75).map { article($0, title: "Update", summary: "Climate evidence") }
    articles.append(article(100, title: "Climate update", summary: "", age: 1))
    let ranked = try PublicNewsSearch.index(.init(text: "climate"), articles: Array(articles.reversed()), now: now)
    XCTAssertEqual(ranked.articles.first?.id, articles.last?.id)
    let newest = try PublicNewsSearch.index(.init(text: "climate", order: .newest), articles: articles, now: now)
    XCTAssertEqual(newest.articles.last?.id, articles.last?.id)
    let pages = [0, 30, 60].map { ranked.page(start: $0) }
    XCTAssertEqual(pages.map(\.count), [30, 30, 16])
    XCTAssertEqual(pages.flatMap { $0 }.map(\.id), ranked.articles.map(\.id))
    XCTAssertTrue(ranked.page(start: 76).isEmpty)
  }

  func testSnippetRetainsLiteralKeywordAndMergesOverlappingHighlights() {
    let summary = String(repeating: "Long opening. ", count: 30) + "Alpha Beta" + String(repeating: " more", count: 80)
    let snippet = PublicNewsSearch.snippet(summary, terms: ["alpha", "pha"])
    XCTAssertTrue(snippet.hasPrefix("..."))
    XCTAssertTrue(snippet.hasSuffix("..."))
    XCTAssertEqual(PublicNewsSearch.ranges(in: snippet, terms: ["alpha", "pha"]).map { String(snippet[$0]) }, ["Alpha"])
  }

  private func article(_ id: Int, title: String, summary: String, publisher: String = "Publisher",
    age: Int = 0, saved: Bool = false) -> PublicNewsArticle {
    PublicNewsArticle(url: URL(string: "https://example.com/\(id)")!, title: title, summary: summary,
      publisher: publisher, discoveredAt: now.addingTimeInterval(-Double(age) * 86_400), saved: saved)
  }
}
