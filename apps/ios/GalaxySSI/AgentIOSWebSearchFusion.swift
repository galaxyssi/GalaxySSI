import Foundation

enum AgentIOSWebSearchFusion {
  typealias Hit = AgentIOSPublicSearchParser.Hit
  static let modelID = AgentIOSImageSearchFusion.modelID
  struct Group {
    var sourceID: String
    var results: [Hit]
    var weight: Double = 1
    var authority: Double = 0.5
    var vertical: AgentIOSWebIntelligenceVertical = .general
  }
  struct Score: Equatable {
    var final: Double
    var reciprocalRank: Double
    var lexical: Double
    var consensus: Double
    var authority: Double
    var freshness: Double
    var localModel: Double
    var value: AgentMcpJSONObject {
      func rounded(_ number: Double) -> AgentMcpJSONValue { .double((min(1, max(0, number)) * 1_000_000).rounded(.toNearestOrEven) / 1_000_000) }
      return ["final": rounded(final), "reciprocal_rank": rounded(reciprocalRank), "lexical": rounded(lexical),
        "consensus": rounded(consensus), "authority": rounded(authority), "freshness": rounded(freshness), "local_model": rounded(localModel)]
    }
  }
  private struct Candidate {
    var hit: Hit
    var authority: Double
    var ranks: [String: Int] = [:]
    var weights: [String: Double] = [:]
    var ordinal: Int
  }

  static func group(sourceID: String, results: [Hit], verticalOverride: AgentIOSWebIntelligenceVertical? = nil) -> Group {
    let spec = AgentIOSJSONWebSearchAdapter.entry(sourceID)?.spec ?? AgentIOSHTMLWebSearchAdapter.entry(sourceID)?.spec ??
      AgentIOSWebIntelligenceSourceCatalog.indexedSources.first { $0.id == sourceID } ??
      (sourceID == "arxiv" ? AgentIOSArxivSearchAdapter.entry.spec : nil) ??
      (sourceID == "devdocs" ? AgentIOSDevDocsSearchAdapter.entry.spec : nil)
    let imageSource = AgentIOSImageSearchRequestPolicy.supported.contains(sourceID)
    let weight = imageSource ? AgentIOSImageSearchRequestPolicy.weight(sourceID) :
      (["bing", "baidu", "duckduckgo"].contains(sourceID) ? 1.05 : (sourceID == "bing_news" ? 1.1 : 1))
    // Learned adapters retain the immutable catalog's unknown-source fusion authority prior.
    return Group(sourceID: sourceID, results: results, weight: weight,
      authority: imageSource ? AgentIOSImageSearchRequestPolicy.authority(sourceID) : spec?.authority ?? 0.5,
      vertical: verticalOverride ?? (imageSource ? .image : spec?.vertical ?? .general))
  }

  static func fuse(query: String, groups: [Group], limit: Int, nowMillis: Int64, includeImages: Bool = false) -> [Hit] {
    guard limit > 0 else { return [] }
    var candidates: [Candidate] = [], indices: [String: Int] = [:]
    for group in groups.prefix(32) {
      guard !group.sourceID.isEmpty, group.weight.isFinite, group.weight >= 0,
        group.authority.isFinite, (0.0...1.0).contains(group.authority) else { continue }
      for (offset, hit) in group.results.prefix(100).enumerated() {
        guard (includeImages || hit.image == nil), !hit.title.isBlank, let parts = URLComponents(string: hit.url),
          ["http", "https"].contains(parts.scheme?.lowercased() ?? ""), parts.host != nil,
          parts.user == nil, parts.password == nil else { continue }
        let page = AgentIOSWebEvidencePack.canonicalURL(hit.url)
        let media = (hit.image?["url"]?.stringValue).flatMap(AgentIOSWebEvidencePack.mediaURL)
        if hit.image != nil && media == nil { continue }
        let key = media.map(AgentIOSWebEvidencePack.canonicalURL) ?? page
        let index: Int
        if let existing = indices[key] { index = existing }
        else {
          index = candidates.count; indices[key] = index
          var canonical = hit; canonical.url = page
          canonical.vertical = hit.vertical ?? group.vertical.rawValue
          if canonical.vertical == "image", canonical.image == nil { canonical.retrievalStatus = "image_topic_page_reference" }
          candidates.append(Candidate(hit: canonical, authority: group.authority, ordinal: index))
        }
        var item = candidates[index]
        if hit.title.utf16.count > item.hit.title.utf16.count { item.hit.title = hit.title }
        if hit.excerpt.utf16.count > item.hit.excerpt.utf16.count { item.hit.excerpt = hit.excerpt }
        if item.hit.publishedAt.isBlank { item.hit.publishedAt = hit.publishedAt }
        if item.hit.vertical == "general", group.vertical != .general { item.hit.vertical = group.vertical.rawValue }
        if item.hit.image == nil { item.hit.image = hit.image }
        else if let incoming = hit.image {
          var merged = item.hit.image ?? [:]
          if merged["thumbnail_url"]?.stringValue?.isEmpty ?? true, let thumbnail = incoming["thumbnail_url"] {
            merged["thumbnail_url"] = thumbnail
          }
          for dimension in ["width", "height"] where (merged[dimension]?.intValue ?? 0) <= 0 {
            if let value = incoming[dimension] { merged[dimension] = value }
          }
          item.hit.image = merged
        }
        if item.hit.image != nil, item.hit.retrievalStatus == "image_topic_page_reference" { item.hit.retrievalStatus = nil }
        if item.hit.retrievalStatus == "local_index_reference", hit.retrievalStatus != "local_index_reference" {
          item.hit.retrievalStatus = hit.retrievalStatus
        }
        item.authority = max(item.authority, group.authority)
        item.ranks[group.sourceID] = min(item.ranks[group.sourceID] ?? Int.max, offset + 1)
        item.weights[group.sourceID] = group.weight
        candidates[index] = item
      }
    }
    let engineCount = max(1, Set(candidates.flatMap { $0.ranks.keys }).count)
    let queryTokens = AgentIOSWebSearchCompletionPolicy.tokens(query)
    let normalizedQuery = query.precomposedStringWithCompatibilityMapping.lowercased()
    for index in candidates.indices {
      let item = candidates[index]
      let titles = AgentIOSWebSearchCompletionPolicy.tokens(item.hit.title), bodies = AgentIOSWebSearchCompletionPolicy.tokens(item.hit.excerpt)
      let titleOverlap = queryTokens.isEmpty ? 0 : Double(queryTokens.intersection(titles).count) / Double(queryTokens.count)
      let bodyOverlap = queryTokens.isEmpty ? 0 : Double(queryTokens.intersection(bodies).count) / Double(queryTokens.count)
      let rrf = min(1, max(0, item.ranks.keys.sorted().reduce(0.0) { $0 + (item.weights[$1] ?? 1) / (60 + Double(item.ranks[$1] ?? 1)) } / (1.0 / 61)))
      let lexical = min(1, max(0, 0.7 * titleOverlap + 0.3 * bodyOverlap))
      let consensus = min(1, Double(item.ranks.count) / Double(min(5, engineCount)))
      let recency = freshness(item.hit.publishedAt, nowMillis: nowMillis)
      let exactness = item.hit.title.precomposedStringWithCompatibilityMapping.lowercased().contains(normalizedQuery) ? 1.0 : titleOverlap
      let penalty = max(0, Double(item.ranks.count - 8) / 16)
      let local = AgentIOSImageSearchFusion.rankerScore([rrf, lexical, consensus, item.authority, recency,
        exactness, max(titleOverlap, bodyOverlap), urlQuality(item.hit.url), penalty])
      let webScore = min(1, max(0, 0.28 * rrf + 0.21 * lexical + 0.14 * consensus + 0.10 * item.authority + 0.07 * recency + 0.20 * local))
      let specificity = titles.isEmpty ? 0 : Double(queryTokens.intersection(titles).count) / Double(titles.count)
      let final = item.hit.vertical == "image" ? 0.45 * webScore + 0.35 * titleOverlap + 0.20 * specificity : webScore
      candidates[index].hit.searchScore = Score(final: final, reciprocalRank: rrf, lexical: lexical,
        consensus: consensus, authority: item.authority, freshness: recency, localModel: local)
      candidates[index].hit.searchEngines = item.ranks.keys.sorted()
    }
    let ranked = candidates.sorted {
      let left = $0.hit.searchScore?.final ?? 0, right = $1.hit.searchScore?.final ?? 0
      if left != right { return left > right }
      if $0.ranks.count != $1.ranks.count { return $0.ranks.count > $1.ranks.count }
      if $0.authority != $1.authority { return $0.authority > $1.authority }
      return $0.ordinal < $1.ordinal
    }
    if !ranked.isEmpty && ranked.allSatisfy({ $0.hit.vertical == "image" }) {
      var pages = Set<String>(), first: [Candidate] = [], remaining: [Candidate] = []
      for item in ranked {
        if pages.insert(item.hit.url).inserted { first.append(item) } else { remaining.append(item) }
      }
      return (first + remaining).prefix(min(limit, 100)).map(\.hit)
    }
    return ranked.prefix(min(limit, 100)).map(\.hit)
  }

  static func freshness(_ value: String, nowMillis: Int64) -> Double {
    guard !value.isEmpty, value.utf8.count <= 128 else { return 0.35 }
    var seconds: Double?
    if value.allSatisfy({ "0123456789".contains($0) }), let number = Int64(value) {
      seconds = Double(number > 10_000_000_000 ? number / 1000 : number)
    } else {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: value) { seconds = date.timeIntervalSince1970 }
      else {
        formatter.formatOptions = [.withInternetDateTime]
        seconds = formatter.date(from: value)?.timeIntervalSince1970
      }
    }
    if let seconds {
      return min(1, max(0.05, exp(-max(0, Double(nowMillis) / 1000 - seconds) / 86_400 / 365)))
    }
    if let range = value.range(of: #"\b(19|20)[0-9]{2}\b"#, options: .regularExpression), let year = Int(value[range]) {
      let calendar = Calendar(identifier: .gregorian)
      let current = calendar.component(.year, from: Date(timeIntervalSince1970: Double(nowMillis) / 1000))
      return max(0.1, exp(-Double(max(0, current - year)) / 4))
    }
    return 0.35
  }

  private static func urlQuality(_ value: String) -> Double {
    guard let url = URLComponents(string: value) else { return 0 }
    var quality = 0.5
    if url.scheme == "https" { quality += 0.15 }
    if url.percentEncodedQuery?.isEmpty ?? true { quality += 0.1 }
    quality += max(0, 0.2 - Double(url.path.split(separator: "/").count) * 0.025)
    if value.utf16.count > 250 { quality -= 0.2 }
    return min(1, max(0, quality))
  }
}
