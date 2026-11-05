import Foundation

enum PublicNewsInterest: Int, Codable, CaseIterable, Identifiable {
  case technology, finance, research

  var id: Int { rawValue }
  var bit: Int { 1 << rawValue }
  static let allMask = allCases.reduce(0) { $0 | $1.bit }
}

enum PublicNewsHighlights {
  static let maximum = 30
  private static let day: TimeInterval = 86_400

  struct Candidate {
    let id: String
    let title: String
    let domain: String
    let interests: Set<PublicNewsInterest>
    let date: Date
  }

  private enum DuplicateKey: Hashable {
    case article(String)
    case headline(day: Int, title: String)
  }

  static func metadata(_ article: PublicNewsArticle) -> Candidate {
    let host = article.url.host?.lowercased() ?? ""
    let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    let inferred = PublicNewsSource.builtIn.first { $0.publisher == article.publisher }?.interest
    let interests = article.interests ?? inferred.map { Set([$0]) } ?? []
    return Candidate(
      id: article.id, title: article.title, domain: domain, interests: interests, date: article.sortDate
    )
  }

  static func select(
    _ metadata: [Candidate], enabled: Set<PublicNewsInterest>, now: Date, limit: Int = maximum
  ) throws -> [String] {
    let maximum = min(limit, Self.maximum)
    guard maximum > 0, !enabled.isEmpty else { return [] }
    let ordered = metadata.filter {
      !$0.domain.isEmpty && !$0.title.isEmpty && !$0.interests.isDisjoint(with: enabled) &&
        $0.date >= now.addingTimeInterval(-7 * day) && $0.date <= now.addingTimeInterval(300)
    }.sorted {
      $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date
    }
    var headlines = Set<DuplicateKey>()
    var articleIDs = Set<String>()
    let candidates = ordered.filter {
      articleIDs.insert($0.id).inserted && headlines.insert(duplicateKey($0)).inserted
    }.map { ($0, $0.interests.intersection(enabled).sorted { $0.rawValue < $1.rawValue }) }
    guard !candidates.isEmpty else { return [] }

    let domainCount = Set(candidates.map { $0.0.domain }).count
    let interestCount = Set(candidates.flatMap { $0.1 }).count
    let domainCap = max(3, (maximum + domainCount - 1) / domainCount)
    let interestCap = max(3, (maximum + interestCount - 1) / interestCount)
    var selected = Set<String>()
    var output: [String] = []
    var domains: [String: Int] = [:]
    var interests: [PublicNewsInterest: Int] = [:]
    while output.count < maximum {
      try Task.checkCancellation()
      var best: (Candidate, PublicNewsInterest)?
      var least = interestCap
      for (article, eligible) in candidates {
        guard !selected.contains(article.id), domains[article.domain, default: 0] < domainCap else { continue }
        for interest in eligible where interests[interest, default: 0] < least {
          least = interests[interest, default: 0]
          best = (article, interest)
        }
        if least == 0 { break }
      }
      guard let (article, interest) = best else { break }
      selected.insert(article.id)
      output.append(article.id)
      domains[article.domain, default: 0] += 1
      interests[interest, default: 0] += 1
    }
    return output
  }

  private static func duplicateKey(_ item: Candidate) -> DuplicateKey {
    // Keep numbers, negation and punctuation; this is not semantic deduplication.
    let title = item.title.precomposedStringWithCompatibilityMapping.lowercased()
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    let hanCount = title.unicodeScalars.filter { (0x3400...0x9FFF).contains($0.value) }.count
    guard title.count >= 16 || hanCount >= 8 else { return .article(item.id) }
    let dayNumber = Int(floor(item.date.timeIntervalSince1970 / day))
    return .headline(day: dayNumber, title: title)
  }
}
