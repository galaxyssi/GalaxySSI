import Foundation

enum AgentIOSImageSearchFusion {
  typealias Hit = AgentIOSPublicSearchParser.Hit
  static let modelID = "galaxyssi-web-ranker-v1"
  static let weights = [-1.15, 2.35, 1.8, 1.25, 0.9, 0.55, 0.75, 1.1, 0.45, -1.4]
  struct Group {
    var sourceID: String
    var results: [Hit]
    var weight: Double = 1
    var authority: Double = 0.5
  }
  private struct Candidate {
    var hit: Hit
    var authority: Double
    var ranks: [String: Int]
    var weights: [String: Double]
    var ordinal: Int
    var score = 0.0
  }

  static func rankerScore(_ features: [Double]) -> Double {
    precondition(features.count == weights.count - 1 && features.allSatisfy(\.isFinite))
    let value = zip(weights.dropFirst(), features).reduce(weights[0]) { $0 + $1.0 * $1.1 }
    return 1 / (1 + exp(-min(30, max(-30, value))))
  }

  static func fuse(query: String, groups: [Group], limit: Int) -> [Hit] {
    guard limit > 0 else { return [] }
    var candidates: [Candidate] = []
    var byImage: [String: Int] = [:]
    for group in groups {
      guard !group.sourceID.isEmpty, group.weight.isFinite, group.weight >= 0,
            group.authority.isFinite, (0...1).contains(group.authority) else { continue }
      for (index, hit) in group.results.enumerated() {
        guard let image = hit.image?["url"]?.stringValue, !image.isBlank, !hit.url.isBlank else { continue }
        let key = AgentIOSWebEvidencePack.canonicalURL(image)
        guard !key.isEmpty else { continue }
        let position: Int
        if let existing = byImage[key] { position = existing }
        else {
          position = candidates.count
          byImage[key] = position
          candidates.append(Candidate(hit: hit, authority: group.authority, ranks: [:], weights: [:], ordinal: position))
        }
        var item = candidates[position]
        if hit.title.utf16.count > item.hit.title.utf16.count { item.hit.title = hit.title }
        if hit.excerpt.utf16.count > item.hit.excerpt.utf16.count { item.hit.excerpt = hit.excerpt }
        var media = item.hit.image ?? [:]
        if media["thumbnail_url"]?.stringValue?.isEmpty ?? true, let thumbnail = hit.image?["thumbnail_url"] {
          media["thumbnail_url"] = thumbnail
        }
        for dimension in ["width", "height"] where (media[dimension]?.intValue ?? 0) <= 0 {
          if let value = hit.image?[dimension] { media[dimension] = value }
        }
        item.hit.image = media
        item.authority = max(item.authority, group.authority)
        item.ranks[group.sourceID] = min(item.ranks[group.sourceID] ?? Int.max, index + 1)
        item.weights[group.sourceID] = group.weight
        candidates[position] = item
      }
    }
    let engineCount = max(1, Set(candidates.flatMap { $0.ranks.keys }).count)
    let queryTokens = AgentIOSWebSearchCompletionPolicy.tokens(query)
    let normalizedQuery = query.precomposedStringWithCompatibilityMapping.lowercased()
    for index in candidates.indices {
      let item = candidates[index]
      let titleTokens = AgentIOSWebSearchCompletionPolicy.tokens(item.hit.title)
      let bodyTokens = AgentIOSWebSearchCompletionPolicy.tokens(item.hit.excerpt)
      let titleMatches = Double(queryTokens.intersection(titleTokens).count)
      let titleOverlap = queryTokens.isEmpty ? 0 : titleMatches / Double(queryTokens.count)
      let bodyOverlap = queryTokens.isEmpty ? 0 : Double(queryTokens.intersection(bodyTokens).count) / Double(queryTokens.count)
      let lexical = min(1, max(0, 0.7 * titleOverlap + 0.3 * bodyOverlap))
      let exactness = item.hit.title.precomposedStringWithCompatibilityMapping.lowercased().contains(normalizedQuery) ? 1 : titleOverlap
      let reciprocalRank = min(1, max(0, item.ranks.reduce(0.0) {
        $0 + (item.weights[$1.key] ?? 1) / (60 + Double($1.value))
      } / (1.0 / 61)))
      let consensus = min(1, Double(item.ranks.count) / Double(min(5, engineCount)))
      // Native image hits currently have no publication date; retain Android's unknown-date prior.
      let freshness = 0.35
      let duplicatePenalty = max(0, Double(item.ranks.count - 8) / 16)
      let localModel = rankerScore([reciprocalRank, lexical, consensus, item.authority, freshness,
        exactness, max(titleOverlap, bodyOverlap), urlQuality(item.hit.url), duplicatePenalty])
      let webScore = min(1, max(0, 0.28 * reciprocalRank + 0.21 * lexical + 0.14 * consensus +
        0.10 * item.authority + 0.07 * freshness + 0.20 * localModel))
      let titleSpecificity = titleTokens.isEmpty ? 0 : titleMatches / Double(titleTokens.count)
      candidates[index].score = 0.45 * webScore + 0.35 * titleOverlap + 0.20 * titleSpecificity
    }
    let ranked = candidates.sorted {
      if $0.score != $1.score { return $0.score > $1.score }
      if $0.ranks.count != $1.ranks.count { return $0.ranks.count > $1.ranks.count }
      if $0.authority != $1.authority { return $0.authority > $1.authority }
      return $0.ordinal < $1.ordinal
    }
    var pages = Set<String>()
    var first: [Candidate] = [], remaining: [Candidate] = []
    for item in ranked {
      if pages.insert(AgentIOSWebEvidencePack.canonicalURL(item.hit.url)).inserted { first.append(item) }
      else { remaining.append(item) }
    }
    return (first + remaining).prefix(limit).map(\.hit)
  }

  private static func urlQuality(_ value: String) -> Double {
    guard let components = URLComponents(string: value) else { return 0 }
    let canonical = AgentIOSWebEvidencePack.canonicalURL(value)
    let url = URLComponents(string: canonical) ?? components
    var score = 0.5
    if url.scheme == "https" { score += 0.15 }
    if url.percentEncodedQuery?.isEmpty ?? true { score += 0.1 }
    score += max(0, 0.2 - Double(url.path.split(separator: "/").count) * 0.025)
    if canonical.utf16.count > 250 { score -= 0.2 }
    return min(1, max(0, score))
  }
}
