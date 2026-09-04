import Foundation

struct AgentMentionSelection: Equatable {
  var goal: String
  var requestedMembers: [AgentRequestedMember]
}

enum AgentMentionText {
  static func parse(
    _ text: String,
    targets: [AgentCallableTarget]
  ) -> AgentMentionSelection {
    let source = text as NSString
    let candidates = targets
      .filter { [.agent, .model].contains($0.kind) && $0.status == .available }
      .flatMap { target -> [(label: String, target: AgentCallableTarget)] in
        let labels = [target.title, target.id]
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
        return labels.map { ($0, target) }
      }
      .sorted { lhs, rhs in
        if lhs.label.count != rhs.label.count { return lhs.label.count > rhs.label.count }
        return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
      }
    guard source.length > 1, !candidates.isEmpty else {
      return AgentMentionSelection(
        goal: text.trimmingCharacters(in: .whitespacesAndNewlines),
        requestedMembers: []
      )
    }

    var matches: [Match] = []
    var cursor = 0
    while cursor < source.length {
      let searchRange = NSRange(location: cursor, length: source.length - cursor)
      let at = source.range(of: "@", options: [], range: searchRange)
      guard at.location != NSNotFound else { break }
      let labelStart = at.location + at.length
      let candidate = candidates.first { item in
        let labelLength = (item.label as NSString).length
        guard labelStart + labelLength <= source.length else { return false }
        let range = NSRange(location: labelStart, length: labelLength)
        guard source.compare(item.label, options: [.caseInsensitive], range: range) == .orderedSame else {
          return false
        }
        return isMentionBoundary(source, offset: NSMaxRange(range))
      }
      guard let candidate else {
        cursor = labelStart
        continue
      }
      let labelLength = (candidate.label as NSString).length
      var tokenEnd = labelStart + labelLength
      tokenEnd = consumeOccurrenceSuffix(source, offset: tokenEnd)
      matches.append(Match(
        range: NSRange(location: at.location, length: tokenEnd - at.location),
        target: candidate.target
      ))
      cursor = max(tokenEnd, labelStart)
    }

    var occurrences: [String: Int] = [:]
    let members = matches.enumerated().map { index, match -> AgentRequestedMember in
      let occurrence = occurrences[match.target.id, default: 0] + 1
      occurrences[match.target.id] = occurrence
      let roleStart = NSMaxRange(match.range)
      let roleEnd = matches.indices.contains(index + 1) ? matches[index + 1].range.location : source.length
      let roleHint = roleEnd > roleStart
        ? String(source.substring(with: NSRange(location: roleStart, length: roleEnd - roleStart))
          .trimmingCharacters(in: roleSeparators).prefix(240))
        : ""
      return AgentRequestedMember(
        agentId: match.target.id,
        displayName: match.target.title.ifBlank(match.target.id),
        occurrence: occurrence,
        roleHint: roleHint
      )
    }
    var cleaned = text
    for match in matches.reversed() {
      guard let range = Range(match.range, in: cleaned) else { continue }
      cleaned.removeSubrange(range)
    }
    cleaned = cleaned
      .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
      .replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
      .trimmingCharacters(in: roleSeparators)
    return AgentMentionSelection(goal: cleaned, requestedMembers: members)
  }

  static func suggestions(
    for text: String,
    targets: [AgentCallableTarget],
    limit: Int = 8,
    sortByTitle: Bool = true
  ) -> [AgentCallableTarget] {
    guard let fragment = activeFragment(in: text) else { return [] }
    let query = fragment.query.lowercased()
    var seen = Set<String>()
    let matches = targets
      .filter { [.agent, .model].contains($0.kind) && $0.status == .available }
      .filter { seen.insert($0.id).inserted }
      .filter { target in
        query.isEmpty || target.title.lowercased().contains(query) || target.id.lowercased().contains(query)
      }
    let ordered = sortByTitle
      ? matches.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
      : matches
    return ordered
      .prefix(max(limit, 0))
      .map { $0 }
  }

  static func inserting(_ target: AgentCallableTarget, into text: String) -> String {
    let token = "@\(target.title.ifBlank(target.id)) "
    guard let fragment = activeFragment(in: text),
      let range = Range(fragment.range, in: text) else {
      return text + token
    }
    return text.replacingCharacters(in: range, with: token)
  }

  private static func activeFragment(in text: String) -> (range: NSRange, query: String)? {
    let source = text as NSString
    guard source.length > 0 else { return nil }
    let at = source.range(of: "@", options: .backwards)
    guard at.location != NSNotFound else { return nil }
    let range = NSRange(location: at.location, length: source.length - at.location)
    let raw = source.substring(with: range)
    guard !raw.contains("\n"), !raw.contains("\t"), raw.dropFirst().count <= 80 else { return nil }
    return (range, String(raw.dropFirst()).trimmingCharacters(in: .whitespaces))
  }

  private static func isMentionBoundary(_ source: NSString, offset: Int) -> Bool {
    guard offset < source.length else { return true }
    let scalar = UnicodeScalar(source.character(at: offset))
    guard let scalar else { return true }
    return CharacterSet.whitespacesAndNewlines.contains(scalar) ||
      CharacterSet.punctuationCharacters.contains(scalar)
  }

  private static func consumeOccurrenceSuffix(_ source: NSString, offset: Int) -> Int {
    guard offset < source.length else { return offset }
    let remainder = source.substring(from: offset)
    guard let expression = try? NSRegularExpression(pattern: #"^\s+#\d+"#),
      let match = expression.firstMatch(
        in: remainder,
        range: NSRange(location: 0, length: (remainder as NSString).length)
      ) else {
      return offset
    }
    return offset + match.range.length
  }

  private struct Match {
    var range: NSRange
    var target: AgentCallableTarget
  }

  private static let roleSeparators = CharacterSet(
    charactersIn: " \n\r\t,\u{ff0c}:\u{ff1a};\u{ff1b}"
  )
}

enum AgentExplicitMultiAgentIntentPolicy {
  static func matches(_ request: String) -> Bool {
    let normalized = request
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    guard !normalized.isEmpty else { return false }
    let patterns = [
      #"\b(?:use|ask|have|let|coordinate|assign|run|form)\b.{0,48}\b(?:multiple|several|two|three|\d+|multi[\s-]*)\s*(?:ai\s+)?agents?\b"#,
      #"\b(?:multiple|several|two|three|\d+)\s+(?:independent\s+)?(?:ai\s+)?agents?\s+(?:should|must|to)\b"#,
      "(?:\u{8bf7}|\u{7528}|\u{8ba9}|\u{8c03}\u{7528}|\u{5b89}\u{6392}|\u{534f}\u{8c03}).{0,16}(?:\u{591a}|\u{4e24}|\u{4e8c}|\u{4e09}|\\d+)\\s*(?:\u{4e2a})?\\s*(?:agents?|\u{667a}\u{80fd}\u{4f53})"
    ]
    return patterns.contains { pattern in
      normalized.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
  }
}
