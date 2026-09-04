import Foundation

enum GlobalEvidenceEvaluator {
  static func build(
    plan: GlobalResearchPlan,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> GlobalEvidenceLedger {
    let completed = plan.completedUnits()
    let unitsById = plan.units.reduce(into: [String: GlobalResearchUnit]()) { result, unit in
      result[unit.id] = unit
    }
    let observations = completed.flatMap { unit -> [SourceObservation] in
      uniqueStrings((unit.evidenceUris + extractUrls(unit.result)).compactMap { canonicalUri($0) })
        .prefix(maximumSourcesPerUnit)
        .map { uri in
          SourceObservation(uri: uri, unitId: unit.id, publishedAtMillis: publishedAtMillis(unit.result, uri, nowMillis))
        }
    }
    var observationsByUri: [String: [SourceObservation]] = [:]
    observations.forEach { observationsByUri[$0.uri, default: []].append($0) }
    let sourcesByUri = observationsByUri.reduce(into: [String: GlobalEvidenceSource]()) { result, entry in
      let uri = entry.key
      let values = entry.value
      let kind = sourceKind(uri)
      let unitIds = Set(values.map(\.unitId))
      let windows = unitIds.compactMap { unitsById[$0]?.freshnessWindowMillis }.filter { $0 > 0 }
      let strictestFreshnessWindow = windows.min() ?? 0
      let published = values.map(\.publishedAtMillis).max() ?? 0
      let sourceFreshness = freshness(published, strictestFreshnessWindow, nowMillis)
      result[uri] = GlobalEvidenceSource(
        uri: uri,
        kind: kind,
        qualityScore: quality(kind: kind, uri: uri, freshness: sourceFreshness, freshnessRelevant: strictestFreshnessWindow > 0),
        authority: sourceAuthority(uri),
        contributingUnitIds: unitIds,
        publishedAtMillis: published,
        freshness: sourceFreshness,
        retrievedAtMillis: nowMillis
      )
    }

    var claims: [GlobalEvidenceClaim] = []
    for unit in completed {
      let unitUris = Set(uniqueStrings((unit.evidenceUris + extractUrls(unit.result)).compactMap { canonicalUri($0) })
        .prefix(maximumSourcesPerUnit))
      for parsed in extractClaims(unit.result, fallbackUris: unitUris) {
        if let index = claims.firstIndex(where: { existing in
          polarity(existing.statement) == polarity(parsed.statement) &&
            GlobalAgentText.overlap(
              GlobalAgentText.tokens(existing.statement),
              GlobalAgentText.tokens(parsed.statement)
            ) >= claimMergeOverlap
        }) {
          let existing = claims[index]
          let contributingUnits = existing.contributingUnitIds.union([unit.id])
          claims[index] = GlobalEvidenceClaim(
            id: existing.id,
            statement: existing.statement,
            sourceUris: existing.sourceUris.union(parsed.sourceUris),
            contributingUnitIds: contributingUnits,
            corroborationCount: contributingUnits.count,
            independentSourceCount: existing.independentSourceCount,
            primarySourceCount: existing.primarySourceCount,
            confidence: existing.confidence,
            contested: existing.contested
          )
        } else {
          claims.append(GlobalEvidenceClaim(
            id: "claim-\(GlobalAgentText.stableKey(parsed.statement))",
            statement: parsed.statement,
            sourceUris: parsed.sourceUris,
            contributingUnitIds: [unit.id]
          ))
        }
      }
    }

    var contestedIds = Set<String>()
    for leftIndex in claims.indices {
      for rightIndex in claims.indices where rightIndex > leftIndex {
        let left = claims[leftIndex]
        let right = claims[rightIndex]
        let overlap = GlobalAgentText.overlap(
          GlobalAgentText.tokens(left.statement),
          GlobalAgentText.tokens(right.statement)
        )
        if overlap >= contestOverlap && polarity(left.statement) != polarity(right.statement) {
          contestedIds.insert(left.id)
          contestedIds.insert(right.id)
        }
      }
    }

    let scoredClaims = Array(claims.map { claim -> GlobalEvidenceClaim in
      let claimSources = claim.sourceUris.compactMap { sourcesByUri[$0] }
      let independentSourceCount = Set(claimSources.map(\.authority).filter { !$0.isBlank }).count
      let primarySourceCount = claimSources.filter { primarySourceKinds.contains($0.kind) }.count
      let sourceQuality = averageOrZero(claimSources.map(\.qualityScore))
      let sourceFactor = Double(min(independentSourceCount, 3)) * 0.09
      let corroborationFactor = Double(min(max(claim.contributingUnitIds.count - 1, 0), 3)) * 0.08
      let freshnessBonus = claimSources.contains(where: { $0.freshness == .fresh }) ? 0.04 : 0.0
      let stalePenalty = !claimSources.isEmpty && claimSources.allSatisfy { $0.freshness == .stale } ? 0.12 : 0.0
      let noSourcePenalty = claim.sourceUris.isEmpty ? 0.24 : 0.0
      let contestedPenalty = contestedIds.contains(claim.id) ? 0.22 : 0.0
      return GlobalEvidenceClaim(
        id: claim.id,
        statement: claim.statement,
        sourceUris: claim.sourceUris,
        contributingUnitIds: claim.contributingUnitIds,
        corroborationCount: claim.contributingUnitIds.count,
        independentSourceCount: independentSourceCount,
        primarySourceCount: primarySourceCount,
        confidence: clamp(
          0.24 + sourceQuality * 0.48 + sourceFactor + corroborationFactor -
            noSourcePenalty - contestedPenalty - stalePenalty + freshnessBonus,
          lower: 0.05,
          upper: 0.98
        ),
        contested: contestedIds.contains(claim.id)
      )
    }.sorted { $0.confidence > $1.confidence }.prefix(maximumClaims))

    let sources = Array(sourcesByUri.values.sorted { $0.qualityScore > $1.qualityScore }.prefix(maximumSources))
    let independentSources = Set(sources.map(\.authority).filter { !$0.isBlank }).count
    let primarySources = sources.filter { primarySourceKinds.contains($0.kind) }.count
    let freshSources = sources.filter { $0.freshness == .fresh }.count
    let staleSources = sources.filter { $0.freshness == .stale }.count
    let undatedSources = sources.filter { $0.publishedAtMillis <= 0 }.count
    let corroborated = scoredClaims.filter {
      $0.corroborationCount >= 2 && $0.independentSourceCount >= 2 && !$0.contested
    }.count
    let contested = scoredClaims.filter { $0.contested }.count
    let overall = averageOrZero(scoredClaims.prefix(8).map(\.confidence))
    let issues = qualityIssues(
      plan: plan,
      claims: scoredClaims,
      independentSources: independentSources,
      primarySources: primarySources,
      freshSources: freshSources,
      staleSources: staleSources,
      corroboratedClaims: corroborated,
      contestedClaims: contested,
      overallConfidence: overall
    )
    return GlobalEvidenceLedger(
      sources: sources,
      claims: scoredClaims,
      independentSourceCount: independentSources,
      primarySourceCount: primarySources,
      freshSourceCount: freshSources,
      staleSourceCount: staleSources,
      undatedSourceCount: undatedSources,
      corroboratedClaimCount: corroborated,
      contestedClaimCount: contested,
      qualityIssues: issues,
      overallConfidence: overall,
      verified: issues.isEmpty,
      updatedAtMillis: nowMillis
    )
  }

  static func extractUrls(_ value: String) -> [String] {
    guard let expression = try? NSRegularExpression(pattern: #"https://[^\s<>()]+"#, options: [.caseInsensitive]) else {
      return []
    }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    let matches = expression.matches(in: value, range: range)
    let urls = matches.compactMap { match -> String? in
      guard let matchRange = Range(match.range, in: value) else { return nil }
      return canonicalUri(String(value[matchRange]).trimmingTrailingCharacters(in: CharacterSet(charactersIn: ".,)]}")))
    }
    return Array(uniqueStrings(urls).prefix(maximumSources))
  }

  static func canonicalUri(_ value: String) -> String? {
    var components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
    guard components?.scheme?.lowercased() == "https",
          let host = components?.host?.lowercased(),
          !host.isBlank else {
      return nil
    }
    components?.scheme = "https"
    components?.host = host
    if components?.path.isEmpty == true {
      components?.path = "/"
    }
    if let queryItems = components?.queryItems {
      let filtered = queryItems.filter { item in
        let key = item.name.lowercased()
        return !key.hasPrefix("utm_") && !trackingQueryKeys.contains(key)
      }
      components?.queryItems = filtered.isEmpty ? nil : filtered
    }
    components?.fragment = nil
    guard let absolute = components?.url?.absoluteString else { return nil }
    return absolute.trimmingTrailingCharacters(in: CharacterSet(charactersIn: "/"))
  }

  static func sourceKind(_ uri: String) -> GlobalEvidenceSourceKind {
    let domain = sourceDomain(uri)
    let authority = sourceAuthority(uri)
    if domain.hasSuffix(".gov") || domain.contains(".gov.") { return .government }
    if domain == "github.com" || domain == "gitlab.com" { return .codeRepository }
    if officialAuthorities.contains(authority) { return .official }
    if domain == "doi.org" || domain == "arxiv.org" || domain.hasSuffix(".edu") { return .paper }
    if newsAuthorities.contains(authority) { return .news }
    if communityAuthorities.contains(authority) { return .community }
    return .unknown
  }

  static func sourceAuthority(_ uri: String) -> String {
    let domain = sourceDomain(uri)
    if domain.isBlank || ipv4Pattern(domain) { return domain }
    let labels = domain.split(separator: ".").map(String.init).filter { !$0.isBlank }
    if labels.count <= 2 { return domain }
    let suffix = labels.suffix(2).joined(separator: ".")
    if twoLevelPublicSuffixes.contains(suffix), labels.count >= 3 {
      return labels.suffix(3).joined(separator: ".")
    }
    return suffix
  }

  private static func extractClaims(_ value: String, fallbackUris: Set<String>) -> [ParsedClaim] {
    var claims: [ParsedClaim] = []
    value.components(separatedBy: .newlines).forEach { line in
      let lineUris = Set(extractUrls(line))
      let cleanedLine = cleanClaimText(line)
      let statements = sentenceParts(cleanedLine).map(normalizeClaim).filter(isUsableClaim)
      if statements.isEmpty && !lineUris.isEmpty && !claims.isEmpty {
        let previous = claims.removeLast()
        claims.append(ParsedClaim(statement: previous.statement, sourceUris: previous.sourceUris.union(lineUris)))
      } else {
        statements.forEach { claims.append(ParsedClaim(statement: $0, sourceUris: lineUris)) }
      }
    }
    if claims.isEmpty {
      sentenceParts(removeUrls(value))
        .map(normalizeClaim)
        .filter(isUsableClaim)
        .forEach { claims.append(ParsedClaim(statement: $0, sourceUris: [])) }
    }
    var seen = Set<String>()
    return claims.compactMap { claim in
      let normalized = GlobalAgentText.normalize(claim.statement)
      if !seen.insert(normalized).inserted { return nil }
      if claim.sourceUris.isEmpty && fallbackUris.count == 1 {
        return ParsedClaim(statement: claim.statement, sourceUris: fallbackUris)
      }
      return claim
    }.prefixArray(maximumClaimsPerUnit)
  }

  private static func cleanClaimText(_ value: String) -> String {
    removeUrls(value)
      .replacingOccurrences(
        of: #"(?i)\b(claim|finding|source|url|date|published|updated|confidence)\s*[:=]\s*"#,
        with: " ",
        options: .regularExpression
      )
      .replacingOccurrences(
        of: #"(?<!\d)(20\d{2})[-/.](0?[1-9]|1[0-2])[-/.](0?[1-9]|[12]\d|3[01])(?!\d)"#,
        with: " ",
        options: .regularExpression
      )
      .replacingOccurrences(of: "|", with: " ")
  }

  private static func normalizeClaim(_ value: String) -> String {
    value
      .replacingOccurrences(of: #"^[#>*\-\d. )]+"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isUsableClaim(_ value: String) -> Bool {
    value.count >= minimumClaimCharacters &&
      value.count <= maximumClaimCharacters &&
      !value.hasSuffix(":") &&
      value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count >= minimumClaimContentCharacters
  }

  private static func publishedAtMillis(_ value: String, _ uri: String, _ nowMillis: Int64) -> Int64 {
    let lines = value.components(separatedBy: .newlines)
    let sourcePath = URLComponents(string: uri)?.path ?? ""
    let lineIndex = lines.firstIndex { line in
      line.range(of: uri, options: .caseInsensitive) != nil ||
        (sourcePath.count > 4 && line.range(of: sourcePath, options: .caseInsensitive) != nil)
    }
    let nearby = lineIndex.map { index in
      lines[index..<min(index + 2, lines.count)].joined(separator: " ")
    } ?? ""
    return (dateCandidates(nearby, nowMillis) + dateCandidates(uri, nowMillis)).max() ?? 0
  }

  private static func dateCandidates(_ value: String, _ nowMillis: Int64) -> [Int64] {
    guard let expression = try? NSRegularExpression(
      pattern: #"(?<!\d)(20\d{2})[-/.](0?[1-9]|1[0-2])[-/.](0?[1-9]|[12]\d|3[01])(?!\d)"#
    ) else {
      return []
    }
    let matches = expression.matches(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value))
    return matches.compactMap { match -> Int64? in
      guard match.numberOfRanges >= 4,
            let yearRange = Range(match.range(at: 1), in: value),
            let monthRange = Range(match.range(at: 2), in: value),
            let dayRange = Range(match.range(at: 3), in: value),
            let year = Int(value[yearRange]),
            let month = Int(value[monthRange]),
            let day = Int(value[dayRange]) else {
        return nil
      }
      var calendar = Calendar(identifier: .gregorian)
      if let utc = TimeZone(secondsFromGMT: 0) {
        calendar.timeZone = utc
      }
      let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
      let millis = date.map { Int64($0.timeIntervalSince1970 * 1_000) }
      return millis.flatMap { $0 <= nowMillis + futureDateToleranceMillis ? $0 : nil }
    }
  }

  private static func freshness(
    _ publishedAtMillis: Int64,
    _ windowMillis: Int64,
    _ nowMillis: Int64
  ) -> GlobalEvidenceFreshness {
    if publishedAtMillis <= 0 || windowMillis <= 0 { return .unknown }
    return publishedAtMillis >= nowMillis - windowMillis ? .fresh : .stale
  }

  private static func qualityIssues(
    plan: GlobalResearchPlan,
    claims: [GlobalEvidenceClaim],
    independentSources: Int,
    primarySources: Int,
    freshSources: Int,
    staleSources: Int,
    corroboratedClaims: Int,
    contestedClaims: Int,
    overallConfidence: Double
  ) -> Set<GlobalEvidenceQualityIssue> {
    var issues = Set<GlobalEvidenceQualityIssue>()
    let requiredIndependentSources: Int
    switch plan.depth {
    case .quickFact:
      requiredIndependentSources = 1
    case .deepResearch, .continuousMonitor, .proactiveInference:
      requiredIndependentSources = 2
    }
    if claims.isEmpty { issues.insert(.noUsableClaims) }
    if independentSources < requiredIndependentSources { issues.insert(.insufficientSourceDiversity) }
    let primaryRequired = plan.depth != .proactiveInference ||
      plan.units.contains { !$0.requiredSourceKinds.intersection(primarySourceKinds).isEmpty }
    if primaryRequired && primarySources == 0 { issues.insert(.primarySourceMissing) }
    let freshnessRequired = plan.depth == .continuousMonitor || plan.units.contains { $0.purpose == .changeMonitor }
    if freshnessRequired && freshSources == 0 { issues.insert(.freshEvidenceMissing) }
    if plan.depth == .quickFact && staleSources > 0 && freshSources == 0 { issues.insert(.freshEvidenceMissing) }
    if plan.depth != .quickFact && corroboratedClaims == 0 { issues.insert(.claimsNotCorroborated) }
    if contestedClaims > 0 { issues.insert(.unresolvedContradictions) }
    let confidenceThreshold: Double
    switch plan.depth {
    case .quickFact:
      confidenceThreshold = 0.50
    case .deepResearch:
      confidenceThreshold = 0.58
    case .continuousMonitor:
      confidenceThreshold = 0.60
    case .proactiveInference:
      confidenceThreshold = 0.56
    }
    if overallConfidence < confidenceThreshold { issues.insert(.lowConfidence) }
    return issues
  }

  private static func quality(
    kind: GlobalEvidenceSourceKind,
    uri: String,
    freshness: GlobalEvidenceFreshness,
    freshnessRelevant: Bool
  ) -> Double {
    let base: Double
    switch kind {
    case .government:
      base = 0.96
    case .official:
      base = 0.93
    case .paper:
      base = 0.90
    case .codeRepository:
      base = 0.84
    case .news:
      base = 0.68
    case .community:
      base = 0.48
    case .unknown:
      base = 0.56
    }
    let httpsBonus = uri.lowercased().hasPrefix("https://") ? 0.02 : 0.0
    let freshnessAdjustment: Double
    if !freshnessRelevant {
      freshnessAdjustment = 0
    } else {
      switch freshness {
      case .fresh:
        freshnessAdjustment = 0.02
      case .stale:
        freshnessAdjustment = -0.18
      case .unknown:
        freshnessAdjustment = -0.05
      }
    }
    return clamp(base + httpsBonus + freshnessAdjustment, lower: 0.20, upper: 0.98)
  }

  private static func sourceDomain(_ uri: String) -> String {
    (URLComponents(string: uri)?.host ?? "")
      .lowercased()
      .replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
  }

  private static func polarity(_ value: String) -> Int {
    let lower = value.lowercased()
    if lower.range(of: #"\b(no|not|never|without|cannot|failed|unsupported)\b"#, options: .regularExpression) != nil ||
      negationSignals.contains(where: lower.contains) {
      return -1
    }
    return 1
  }

  private static func sentenceParts(_ value: String) -> [String] {
    value.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
  }

  private static func removeUrls(_ value: String) -> String {
    value.replacingOccurrences(of: #"https://[^\s<>()]+"#, with: " ", options: [.regularExpression, .caseInsensitive])
  }

  private static func averageOrZero(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
  }

  private static func ipv4Pattern(_ value: String) -> Bool {
    value.range(of: #"^(?:\d{1,3}\.){3}\d{1,3}$"#, options: .regularExpression) != nil
  }

  private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(max(value, lower), upper)
  }

  private static let claimMergeOverlap = 0.72
  private static let contestOverlap = 0.34
  private static let minimumClaimCharacters = 28
  private static let maximumClaimCharacters = 700
  private static let minimumClaimContentCharacters = 18
  private static let maximumClaimsPerUnit = 10
  private static let maximumClaims = 32
  private static let maximumSourcesPerUnit = 16
  private static let maximumSources = 40
  private static let futureDateToleranceMillis: Int64 = 2 * 24 * 60 * 60 * 1_000
  private static let primarySourceKinds: Set<GlobalEvidenceSourceKind> = [.government, .official, .paper]
  private static let negationSignals = [
    "\u{4e0d}\u{652f}\u{6301}",
    "\u{4e0d}\u{80fd}",
    "\u{65e0}\u{6cd5}",
    "\u{672a}\u{901a}\u{8fc7}",
    "\u{5931}\u{8d25}"
  ]
  private static let trackingQueryKeys: Set<String> = ["ref", "source", "fbclid", "gclid", "mc_cid", "mc_eid"]
  private static let twoLevelPublicSuffixes: Set<String> = [
    "co.uk", "org.uk", "ac.uk", "com.cn", "net.cn", "org.cn", "com.au", "co.jp", "co.kr", "com.br"
  ]
  private static let officialAuthorities: Set<String> = [
    "openai.com", "android.com", "microsoft.com", "apple.com", "anthropic.com", "google.com",
    "github.com", "kotlinlang.org", "oracle.com", "python.org", "rust-lang.org", "nodejs.org",
    "mozilla.org", "w3.org"
  ]
  private static let newsAuthorities: Set<String> = ["reuters.com", "apnews.com", "bbc.com", "bloomberg.com"]
  private static let communityAuthorities: Set<String> = ["stackoverflow.com", "reddit.com", "medium.com"]

  private struct SourceObservation {
    var uri: String
    var unitId: String
    var publishedAtMillis: Int64
  }

  private struct ParsedClaim {
    var statement: String
    var sourceUris: Set<String>
  }
}

private extension Array {
  func prefixArray(_ maximumCount: Int) -> [Element] {
    Array(prefix(Swift.max(maximumCount, 0)))
  }
}

private func uniqueStrings(_ values: [String]) -> [String] {
  var seen = Set<String>()
  var result: [String] = []
  for value in values where seen.insert(value).inserted {
    result.append(value)
  }
  return result
}

private extension String {
  func trimmingTrailingCharacters(in characters: CharacterSet) -> String {
    var value = self
    while let scalar = value.unicodeScalars.last, characters.contains(scalar) {
      value.removeLast()
    }
    return value
  }
}
