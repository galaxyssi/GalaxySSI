import XCTest
@testable import GalaxySSI

final class PublicNewsHighlightsTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  func testBalancesPublishersAndInterestsWithoutDroppingSparseSources() throws {
    let tech = (0..<50).map { item("tech\($0)", domain: "busy.example", interest: .technology) }
    let finance = (0..<12).map { item("finance\($0)", domain: "finance.example", interest: .finance, age: 60) }
    let science = (0..<12).map { item("science\($0)", domain: "science.example", interest: .research, age: 90) }
    let result = try PublicNewsHighlights.select(
      tech + finance + science, enabled: Set(PublicNewsInterest.allCases), now: now
    )
    XCTAssertEqual(result.count, 30)
    XCTAssertEqual(result.filter { $0.hasPrefix("tech") }.count, 10)
    XCTAssertEqual(Set(result.prefix(3).map { $0.prefix(4) }), ["tech", "fina", "scie"])
    let sparse = try PublicNewsHighlights.select(tech, enabled: [.technology], now: now)
    XCTAssertEqual(sparse.count, 30)
  }

  func testDeduplicatesOnlyLongSameDayHeadlinesAndKeepsMeaningfulDifferences() throws {
    let headline = "Agent runtime 2.7 is ready"
    let input = [
      item("a", title: headline, domain: "a.example"),
      item("b", title: "  AGENT runtime 2.7 is ready ", domain: "b.example", age: 1),
      item("version", title: "Agent runtime 2.8 is ready", domain: "c.example"),
      item("negation", title: "Agent runtime 2.7 is not ready", domain: "d.example"),
      item("question", title: "Agent runtime 2.7 is ready?", domain: "e.example"),
      item("next-day", title: headline, domain: "f.example", age: 86_400),
      item("brief-1", title: "Market", domain: "g.example"),
      item("brief-2", title: "Market", domain: "h.example")
    ]
    let result = try PublicNewsHighlights.select(input, enabled: [.technology], now: now)
    XCTAssertEqual(Set(result), Set(input.map(\.id)).subtracting(["b"]))
    XCTAssertEqual(input.count, 8)
  }

  func testExcludesDisabledStaleAndFutureItemsAndNormalizesPublisherHost() throws {
    let input = [
      item("tech", domain: "a.example"),
      item("finance", domain: "b.example", interest: .finance),
      item("old", domain: "c.example", age: 8 * 86_400),
      item("future", domain: "d.example", age: -301)
    ]
    XCTAssertEqual(try PublicNewsHighlights.select(input, enabled: [.technology], now: now), ["tech"])
    let existing = PublicNewsArticle(url: URL(string: "https://www.github.blog/article")!,
      title: "Old article", summary: "", publisher: "GitHub", discoveredAt: now)
    let metadata = PublicNewsHighlights.metadata(existing)
    XCTAssertEqual(metadata.domain, "github.blog")
    XCTAssertEqual(metadata.interests, [.technology])
  }

  func testSameArticleRetainsInterestsAcrossSourcesAndRefresh() throws {
    let url = URL(string: "https://example.com/record")!
    let older = PublicNewsArticle(url: url, title: "Older", summary: "", publisher: "Fixture",
      discoveredAt: now, saved: true, interests: [.finance])
    let incoming = PublicNewsArticle(url: url, title: "Current", summary: "", publisher: "Fixture",
      discoveredAt: now, interests: [.technology])
    let duplicate = PublicNewsArticle(url: url, title: "Other feed", summary: "", publisher: "Other",
      discoveredAt: now, interests: [.research])
    let article = try XCTUnwrap(PublicNewsArchive.merge(existing: [older], incoming: [incoming, duplicate]).first)
    XCTAssertEqual(article.title, "Current")
    XCTAssertTrue(article.saved)
    XCTAssertEqual(article.interests, Set(PublicNewsInterest.allCases))
  }

  private func item(_ id: String, title: String? = nil, domain: String,
    interest: PublicNewsInterest = .technology, age: TimeInterval = 0) -> PublicNewsHighlights.Candidate {
    .init(id: id, title: title ?? "Distinct article \(id)", domain: domain,
      interests: [interest], date: now.addingTimeInterval(-age))
  }
}
