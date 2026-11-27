import Foundation

struct PublicNewsEvent: Equatable, Identifiable {
  struct Report: Equatable, Identifiable {
    let article: PublicNewsArticle
    let source: String
    let excerpts: [String]
    var id: String { article.id }
  }

  let reports: [Report]
  var id: String { reports.first?.id ?? "" }
  var sources: Int { Set(reports.map(\.source)).count }
  private var readReports: [Report] {
    reports.filter { $0.article.read && ($0.article.readAt?.timeIntervalSince1970 ?? 0) > 0 }
  }
  private var lastRead: Date? { readReports.compactMap { $0.article.readAt }.max() }
  func arrivedSinceRead(_ report: Report) -> Bool {
    guard let lastRead else { return false }
    return !report.article.read && report.article.discoveredAt > lastRead
  }
  var newCount: Int { reports.filter(arrivedSinceRead).count }
  var newExcerpt: (source: String, text: String)? {
    let previous = Set(readReports.flatMap(\.excerpts).map(Self.comparable))
    guard !previous.isEmpty else { return nil }
    for report in reports where arrivedSinceRead(report) {
      if let text = report.excerpts.first(where: { !previous.contains(Self.comparable($0)) }) {
        return (report.source, text)
      }
    }
    return nil
  }

  private static func comparable(_ value: String) -> String {
    value.precomposedStringWithCompatibilityMapping.lowercased()
      .filter { !$0.isWhitespace }.trimmingCharacters(in: PublicNewsEvents.trailingPunctuation)
  }
}

enum PublicNewsEvents {
  static let window: TimeInterval = 36 * 3_600
  static let trailingPunctuation = CharacterSet(charactersIn: ".!")
    .union(CharacterSet(charactersIn: String(UnicodeScalar(0x3002)!)))
    .union(CharacterSet(charactersIn: String(UnicodeScalar(0xFF01)!)))
  private static let sentenceEnd = trailingPunctuation.union(CharacterSet(charactersIn: "?"))
    .union(CharacterSet(charactersIn: String(UnicodeScalar(0xFF1F)!)))

  struct Request: Equatable {
    let articles: [PublicNewsArticle]
    let mask: Int
    var enabled: Set<PublicNewsInterest> {
      Set(PublicNewsInterest.allCases.filter { mask & $0.bit != 0 })
    }
  }

  static func group(_ articles: [PublicNewsArticle], enabled: Set<PublicNewsInterest>) throws -> [String: PublicNewsEvent] {
    var buckets: [String: [PublicNewsArticle]] = [:]
    for article in articles {
      try Task.checkCancellation()
      let metadata = PublicNewsHighlights.metadata(article)
      guard let date = article.publishedAt, date.timeIntervalSince1970 > 0,
            !metadata.domain.isEmpty, !metadata.interests.isDisjoint(with: enabled),
            let title = headline(article.title) else { continue }
      buckets[title, default: []].append(article)
    }
    var result: [String: PublicNewsEvent] = [:]
    for bucket in buckets.values where bucket.count > 1 {
      try Task.checkCancellation()
      var period: [PublicNewsArticle] = []
      var shared: Set<PublicNewsInterest> = []
      func flush() {
        var seen: Set<String> = []
        let reports = period.reversed().filter { seen.insert($0.id).inserted }.map {
          PublicNewsEvent.Report(article: $0, source: PublicNewsHighlights.metadata($0).domain, excerpts: excerpts($0))
        }
        guard reports.count > 1, Set(reports.map(\.source)).count > 1 else { return }
        let event = PublicNewsEvent(reports: reports)
        for report in reports { result[report.id] = event }
      }
      let ordered = bucket.sorted {
        $0.sortDate == $1.sortDate ? $0.id < $1.id : $0.sortDate < $1.sortDate
      }
      for article in ordered {
        let topics = PublicNewsHighlights.metadata(article).interests.intersection(enabled)
        if let first = period.first, article.sortDate.timeIntervalSince(first.sortDate) > window || shared.isDisjoint(with: topics) {
          flush()
          period = []
        }
        shared = period.isEmpty ? topics : shared.intersection(topics)
        period.append(article)
      }
      flush()
    }
    return result
  }

  static func representatives(_ articles: [PublicNewsArticle], events: [String: PublicNewsEvent]) -> [PublicNewsArticle] {
    articles.filter { article in events[article.id].map { $0.id == article.id } ?? true }
  }

  private static func headline(_ original: String) -> String? {
    guard (12...512).contains(original.utf16.count) else { return nil }
    let title = original.precomposedStringWithCompatibilityMapping.lowercased()
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
      .trimmingCharacters(in: CharacterSet(charactersIn: ".").union(CharacterSet(charactersIn: String(UnicodeScalar(0x3002)!))))
    let han = title.unicodeScalars.filter { (0x3400...0x9FFF).contains($0.value) }.count
    guard !title.unicodeScalars.contains(where: { $0.value == 0x3F || $0.value == 0xFF1F }),
          han >= 12 || title.split(separator: " ").filter({ $0.count > 1 }).count >= 5 else { return nil }
    return title
  }

  private static func excerpts(_ article: PublicNewsArticle) -> [String] {
    let preview = String(article.summary.prefix(900))
    var result: [String] = []
    preview.enumerateSubstrings(in: preview.startIndex..<preview.endIndex, options: .bySentences) { text, _, _, stop in
      guard let text else { return }
      let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard (12...220).contains(line.utf16.count), let last = line.unicodeScalars.last,
            sentenceEnd.contains(last), !line.contains("\n"), !line.contains("<"), !line.contains("://"),
            line.caseInsensitiveCompare(article.title) != .orderedSame else { return }
      result.append(line)
      if result.count == 4 { stop = true }
    }
    return result
  }
}
