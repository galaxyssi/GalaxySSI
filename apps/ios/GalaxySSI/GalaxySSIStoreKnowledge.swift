import Foundation

extension GalaxySSIStore {
  var agentKnowledgeStats: AgentKnowledgeStats {
    let sources = Set(agentKnowledgeItems.map(agentKnowledgeSourceKey))
    return AgentKnowledgeStats(
      itemCount: agentKnowledgeItems.count,
      sourceCount: sources.count,
      lastUpdatedAtMillis: agentKnowledgeItems.map(\.updatedAtMillis).max() ?? 0
    )
  }

  func agentKnowledgeSourceGroups() -> [AgentKnowledgeSourceGroup] {
    Dictionary(grouping: agentKnowledgeItems, by: agentKnowledgeSourceKey)
      .values
      .map { items in
        let sorted = items.sorted { $0.updatedAtMillis > $1.updatedAtMillis }
        let latest = sorted.first ?? items[0]
        return AgentKnowledgeSourceGroup(
          source: agentKnowledgeSourceKey(latest),
          title: latest.title.replacingOccurrences(of: "\\s+\\[[0-9]+/[0-9]+\\]$", with: "", options: .regularExpression),
          itemIds: sorted.map(\.id),
          chunkCount: sorted.count,
          cloudAccess: latest.cloudAccess,
          agentAccess: latest.agentAccess,
          allowedAgentIds: latest.allowedAgentIds,
          updatedAtMillis: sorted.map(\.updatedAtMillis).max() ?? latest.updatedAtMillis
        )
      }
      .sorted { $0.updatedAtMillis > $1.updatedAtMillis }
  }

  @discardableResult
  func importAgentKnowledge(
    title: String,
    content: String,
    source: String = "",
    kind: AgentKnowledgeKind = .document,
    tags: [String] = []
  ) -> [AgentKnowledgeItem] {
    let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanContent.isEmpty else { return [] }
    let assessment = AgentKnowledgeImportPolicy.assess(cleanContent)
    guard assessment.isAllowed, !assessment.indexedContent.isEmpty else { return [] }
    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("Private knowledge")
    let sourceKey = source.trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank("local:\(UUID().uuidString)")
    let chunks = chunkKnowledgeContent(assessment.indexedContent)
    let now = Int64(Date().timeIntervalSince1970 * 1_000)
    let items = chunks.enumerated().map { index, chunk in
      AgentKnowledgeItem(
        kind: kind,
        title: chunks.count > 1 ? "\(cleanTitle) [\(index + 1)/\(chunks.count)]" : cleanTitle,
        content: chunk,
        source: sourceKey,
        tags: tags,
        summary: String(chunk.prefix(700)),
        cloudAccess: .summaryOnly,
        agentAccess: .localOnly,
        chunkIndex: index,
        chunkCount: chunks.count,
        updatedAtMillis: now
      )
    }
    agentKnowledgeItems = Array((agentKnowledgeItems + items).suffix(500))
    return items
  }

  @discardableResult
  func replaceAgentKnowledgeSource(
    title: String,
    content: String,
    source: String,
    kind: AgentKnowledgeKind = .document,
    tags: [String] = []
  ) -> [AgentKnowledgeItem] {
    let sourceKey = source.trimmingCharacters(in: .whitespacesAndNewlines)
    let existingItems = sourceKey.isEmpty
      ? []
      : agentKnowledgeItems.filter { $0.source == sourceKey }
    let previousPolicy = existingItems.first.map {
      (cloudAccess: $0.cloudAccess, agentAccess: $0.agentAccess, allowedAgentIds: $0.allowedAgentIds)
    }
    let imported = importAgentKnowledge(title: title, content: content, source: sourceKey, kind: kind, tags: tags)
    guard !imported.isEmpty else {
      return []
    }
    let existingIds = existingItems.map(\.id)
    if !existingIds.isEmpty {
      _ = deleteAgentKnowledgeSource(itemIds: existingIds)
    }
    if let previousPolicy {
      _ = updateAgentKnowledgeSourceAccess(
        itemIds: imported.map(\.id),
        cloudAccess: previousPolicy.cloudAccess,
        agentAccess: previousPolicy.agentAccess,
        allowedAgentIds: previousPolicy.allowedAgentIds
      )
    }
    return imported
  }

  @discardableResult
  func upsertAgentKnowledge(_ item: AgentKnowledgeItem) -> AgentKnowledgeItem {
    agentKnowledgeItems.removeAll { $0.id == item.id }
    agentKnowledgeItems = Array((agentKnowledgeItems + [item]).suffix(500))
    return item
  }

  @discardableResult
  func updateAgentKnowledgeSourceAccess(
    itemIds: [String],
    cloudAccess: AgentKnowledgeCloudAccess,
    agentAccess: AgentKnowledgeAgentAccess,
    allowedAgentIds: [String] = []
  ) -> Int {
    let ids = Set(itemIds)
    var changed = 0
    agentKnowledgeItems = agentKnowledgeItems.map { item in
      guard ids.contains(item.id) else { return item }
      changed += 1
      return AgentKnowledgeItem(
        id: item.id,
        kind: item.kind,
        title: item.title,
        content: item.content,
        source: item.source,
        tags: item.tags,
        summary: item.summary,
        cloudAccess: cloudAccess,
        agentAccess: agentAccess,
        allowedAgentIds: allowedAgentIds,
        chunkIndex: item.chunkIndex,
        chunkCount: item.chunkCount,
        updatedAtMillis: Int64(Date().timeIntervalSince1970 * 1_000)
      )
    }
    return changed
  }

  @discardableResult
  func deleteAgentKnowledgeSource(itemIds: [String]) -> Int {
    let ids = Set(itemIds)
    let before = agentKnowledgeItems.count
    agentKnowledgeItems.removeAll { ids.contains($0.id) }
    return before - agentKnowledgeItems.count
  }

  func searchAgentKnowledge(_ query: String, limit: Int = 24) -> [AgentKnowledgeHit] {
    let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanQuery.isEmpty else { return [] }
    let tokens = knowledgeTokens(cleanQuery)
    let queryTrigrams = knowledgeTrigrams(cleanQuery)
    return agentKnowledgeItems
      .compactMap { item -> AgentKnowledgeHit? in
        let score = knowledgeScore(
          item,
          query: cleanQuery,
          tokens: tokens,
          queryTrigrams: queryTrigrams
        )
        guard score >= 1.2 else { return nil }
        let matchedTerms = knowledgeMatchedTerms(item, query: cleanQuery, tokens: tokens)
        return AgentKnowledgeHit(
          item: item,
          score: min(score / 24.0, 1.0),
          excerpt: knowledgeExcerpt(item.content, query: cleanQuery, tokens: tokens),
          matchedTerms: matchedTerms
        )
      }
      .sorted {
        if $0.score != $1.score { return $0.score > $1.score }
        return $0.item.updatedAtMillis > $1.item.updatedAtMillis
      }
      .prefix(max(limit, 0))
      .map { $0 }
  }

  func recordAgentKnowledgeSearch(
    query: String,
    hits: [AgentKnowledgeHit],
    targetId: String = "agent-knowledge-local",
    evidenceModes: [AgentKnowledgeEvidenceMode]? = nil,
    blockedMatchCount: Int = 0
  ) {
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let sourceCount = Set(hits.map { agentKnowledgeSourceKey($0.item) }).count
    let entry = AgentKnowledgeAccessAuditEntry(
      queryHash: deterministicHash(query),
      targetId: targetId,
      itemIdHashes: hits.map { deterministicHash($0.item.id) },
      sourceCount: sourceCount,
      evidenceModes: evidenceModes ?? (hits.isEmpty ? [] : [.full]),
      blockedMatchCount: max(blockedMatchCount, 0)
    )
    agentKnowledgeAccessAudit = Array((agentKnowledgeAccessAudit + [entry]).suffix(100))
  }

  private func agentKnowledgeSourceKey(_ item: AgentKnowledgeItem) -> String {
    item.source.trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank("local:\(item.kind.rawValue.lowercased()):\(item.title)")
  }

  private func chunkKnowledgeContent(_ content: String) -> [String] {
    let clean = content
      .replacingOccurrences(of: "\r\n", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return [] }
    let limit = 12_000
    guard clean.count > limit else { return [clean] }

    var chunks: [String] = []
    var current = ""
    for paragraph in clean.components(separatedBy: "\n\n") {
      let part = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !part.isEmpty else { continue }
      if part.count > limit {
        if !current.isEmpty {
          chunks.append(current)
          current = ""
        }
        var start = part.startIndex
        while start < part.endIndex {
          let end = part.index(start, offsetBy: limit, limitedBy: part.endIndex) ?? part.endIndex
          chunks.append(String(part[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines))
          start = end
        }
      } else if current.count + part.count + 2 > limit {
        chunks.append(current)
        current = part
      } else {
        current = current.isEmpty ? part : "\(current)\n\n\(part)"
      }
    }
    if !current.isEmpty {
      chunks.append(current)
    }
    return chunks.isEmpty ? [clean] : chunks
  }

  private func knowledgeTokens(_ query: String) -> [String] {
    let scalars = query.lowercased().unicodeScalars
    let normalized = scalars.map { scalar -> String in
      isKnowledgeCJK(scalar) ? " " : (CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : " ")
    }.joined()
    var seen = Set<String>()
    var values: [String] = []
    for token in normalized.split(whereSeparator: \.isWhitespace).map(String.init) {
      let clean = String(token.prefix(64))
      guard clean.count >= 2, seen.insert(clean).inserted else { continue }
      values.append(clean)
      if values.count >= 64 { return values }
    }
    var cjkRun = ""
    func appendCJKRun(_ run: String) {
      let characters = Array(run)
      guard characters.count >= 2 else { return }
      for index in 0..<(characters.count - 1) {
        let token = String(characters[index...(index + 1)])
        if seen.insert(token).inserted {
          values.append(token)
          if values.count >= 64 { return }
        }
      }
    }
    for scalar in scalars {
      if isKnowledgeCJK(scalar) {
        cjkRun.unicodeScalars.append(scalar)
      } else if !cjkRun.isEmpty {
        appendCJKRun(cjkRun)
        cjkRun = ""
        if values.count >= 64 { break }
      }
    }
    if values.count < 64, !cjkRun.isEmpty {
      appendCJKRun(cjkRun)
    }
    return values
  }

  private func isKnowledgeCJK(_ scalar: Unicode.Scalar) -> Bool {
    (0x3400...0x4DBF).contains(scalar.value) ||
      (0x4E00...0x9FFF).contains(scalar.value) ||
      (0xF900...0xFAFF).contains(scalar.value)
  }

  private func knowledgeTrigrams(_ value: String) -> Set<String> {
    let characters = value.lowercased().unicodeScalars
      .filter { CharacterSet.alphanumerics.contains($0) }
      .map { Character(String($0)) }
    guard characters.count >= 3 else { return [] }
    var trigrams = Set<String>()
    for index in 0...(characters.count - 3) {
      trigrams.insert(String(characters[index...(index + 2)]))
      if trigrams.count >= 512 { break }
    }
    return trigrams
  }

  private func knowledgeMatchedTerms(_ item: AgentKnowledgeItem, query: String, tokens: [String]) -> [String] {
    let haystack = [
      item.title,
      item.summary,
      item.content,
      item.source,
      item.tags.joined(separator: " ")
    ].joined(separator: " ").lowercased()
    var values: [String] = []
    let cleanQuery = query.lowercased()
    if !cleanQuery.isEmpty && haystack.localizedCaseInsensitiveContains(cleanQuery) {
      values.append(String(cleanQuery.prefix(64)))
    }
    for token in tokens where haystack.localizedCaseInsensitiveContains(token) && !values.contains(token) {
      values.append(token)
    }
    return values
  }

  private func knowledgeScore(
    _ item: AgentKnowledgeItem,
    query: String,
    tokens: [String],
    queryTrigrams: Set<String>
  ) -> Double {
    let cleanQuery = query
      .lowercased()
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let title = item.title.lowercased()
    let summary = item.summary.lowercased()
    let content = item.content.lowercased()
    let tags = item.tags.joined(separator: " ").lowercased()
    var score = 0.0

    if title.localizedCaseInsensitiveContains(cleanQuery) { score += 14 }
    if summary.localizedCaseInsensitiveContains(cleanQuery) { score += 10 }
    if content.localizedCaseInsensitiveContains(cleanQuery) { score += 7 }

    for token in tokens {
      if title.localizedCaseInsensitiveContains(token) { score += 4.5 }
      if tags.localizedCaseInsensitiveContains(token) { score += 3.5 }
      if summary.localizedCaseInsensitiveContains(token) { score += 2.5 }
      if content.localizedCaseInsensitiveContains(token) { score += 1.2 }
    }
    if !tokens.isEmpty {
      let searchable = "\(title) \(summary) \(tags) \(content)"
      let matched = tokens.filter { searchable.localizedCaseInsensitiveContains($0) }.count
      score += Double(matched) / Double(tokens.count) * 6
    }
    let itemTrigrams = knowledgeTrigrams("\(title) \(summary) \(content.prefix(1_200))")
    if !queryTrigrams.isEmpty, !itemTrigrams.isEmpty {
      let intersection = queryTrigrams.intersection(itemTrigrams).count
      let union = queryTrigrams.union(itemTrigrams).count
      if union > 0 {
        score += Double(intersection) / Double(union) * 9
      }
    }
    return score
  }

  private func knowledgeExcerpt(_ content: String, query: String, tokens: [String]) -> String {
    let normalized = content
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return "" }
    let needles = ([query] + tokens)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let firstRange = needles.compactMap {
      normalized.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive])
    }.first
    guard let range = firstRange else {
      return String(normalized.prefix(260))
    }
    let start = normalized.index(range.lowerBound, offsetBy: -120, limitedBy: normalized.startIndex) ?? normalized.startIndex
    let end = normalized.index(range.upperBound, offsetBy: 220, limitedBy: normalized.endIndex) ?? normalized.endIndex
    let prefix = start == normalized.startIndex ? "" : "..."
    let suffix = end == normalized.endIndex ? "" : "..."
    return prefix + String(normalized[start..<end]) + suffix
  }

  private func deterministicHash(_ value: String) -> Int {
    var hash: UInt64 = 1_469_598_103_934_665_603
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return Int(hash & 0x7fff_ffff)
  }
}
