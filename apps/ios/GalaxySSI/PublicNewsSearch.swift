import Foundation

struct PublicNewsSearchRequest: Equatable {
  enum Scope: String, CaseIterable { case all, unread, saved }
  enum Order: String, CaseIterable { case relevance, newest }
  enum Period: Int, CaseIterable { case anytime = 0, week = 7, month = 30, quarter = 90 }

  var text: String
  var scope: Scope = .all
  var order: Order = .relevance
  var period: Period = .anytime
  var publisher = ""
}

struct PublicNewsSearchResult {
  static let pageSize = 30
  let articles: [PublicNewsArticle]
  let terms: [String]

  func page(start: Int) -> [PublicNewsSearchHit] {
    guard start >= 0, start < articles.count else { return [] }
    return articles[start..<min(articles.count, start + Self.pageSize)].map { article in
      PublicNewsSearchHit(article: article, snippet: PublicNewsSearch.snippet(article.summary, terms: terms))
    }
  }
}

struct PublicNewsSearchHit: Identifiable {
  let article: PublicNewsArticle
  let snippet: String
  var id: String { article.id }
}

enum PublicNewsSearch {
  static let maximumQueryLength = 256
  private static let matchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

  static func terms(_ input: String) -> [String] {
    var seen = Set<String>()
    return input.prefix(maximumQueryLength).split(whereSeparator: \.isWhitespace)
      .map(String.init).filter { seen.insert($0.folding(options: matchOptions, locale: nil)).inserted }
  }

  static func index(
    _ query: PublicNewsSearchRequest, articles: [PublicNewsArticle], now: Date
  ) throws -> PublicNewsSearchResult {
    let terms = terms(query.text)
    guard !terms.isEmpty else { return PublicNewsSearchResult(articles: [], terms: []) }
    let lowerBound = query.period == .anytime
      ? Date.distantPast : now.addingTimeInterval(-Double(query.period.rawValue) * 86_400)
    var ranked: [(article: PublicNewsArticle, rank: Int)] = []
    for article in articles {
      try Task.checkCancellation()
      guard article.sortDate >= lowerBound, query.publisher.isEmpty || article.publisher == query.publisher,
            query.scope != .unread || !article.read, query.scope != .saved || article.saved else { continue }
      var rank = 0
      var matched = 0
      for term in terms {
        let inTitle = first(term, in: article.title) != nil ||
          (article.displayTitle != article.title && first(term, in: article.displayTitle) != nil)
        let inPublisher = first(term, in: article.publisher) != nil
        if inTitle || inPublisher || first(term, in: article.summary) != nil {
          matched += 1
          rank += (inTitle ? 10 : 0) + (inPublisher ? 3 : 0)
        } else {
          break
        }
      }
      if matched == terms.count { ranked.append((article, rank)) }
    }
    ranked.sort {
      if query.order == .relevance, $0.rank != $1.rank { return $0.rank > $1.rank }
      if $0.article.sortDate != $1.article.sortDate { return $0.article.sortDate > $1.article.sortDate }
      return $0.article.id < $1.article.id
    }
    try Task.checkCancellation()
    return PublicNewsSearchResult(articles: ranked.map(\.article), terms: terms)
  }

  static func ranges(in text: String, terms: [String]) -> [Range<String.Index>] {
    var hits: [Range<String.Index>] = []
    for term in terms where !term.isEmpty {
      var start = text.startIndex
      while start < text.endIndex,
            let match = text.range(of: term, options: matchOptions, range: start..<text.endIndex) {
        guard !match.isEmpty else { break }
        hits.append(match)
        start = match.upperBound
      }
    }
    var merged: [Range<String.Index>] = []
    for hit in hits.sorted(by: { $0.lowerBound < $1.lowerBound }) {
      if let previous = merged.last, hit.lowerBound <= previous.upperBound {
        merged[merged.count - 1] = previous.lowerBound..<max(previous.upperBound, hit.upperBound)
      } else {
        merged.append(hit)
      }
    }
    return merged
  }

  static func snippet(_ summary: String, terms: [String]) -> String {
    let firstHit = terms.compactMap { first($0, in: summary)?.lowerBound }.min() ?? summary.startIndex
    let start = summary.index(firstHit, offsetBy: -48, limitedBy: summary.startIndex) ?? summary.startIndex
    let end = summary.index(start, offsetBy: 220, limitedBy: summary.endIndex) ?? summary.endIndex
    return (start == summary.startIndex ? "" : "...") + String(summary[start..<end])
      + (end == summary.endIndex ? "" : "...")
  }

  private static func first(_ term: String, in text: String) -> Range<String.Index>? {
    text.range(of: term, options: matchOptions)
  }
}
