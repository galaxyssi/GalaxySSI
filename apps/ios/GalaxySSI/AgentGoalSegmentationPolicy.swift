import Foundation

enum AgentGoalSegmentationPolicy {
  static let maximumSegments = 8

  static func split(_ goal: String) -> [String] {
    let source = goal as NSString
    guard source.length > 0, let expression else { return normalized(goal) }
    var segments: [String] = []
    var start = 0
    for match in expression.matches(
      in: goal,
      range: NSRange(location: 0, length: source.length)
    ) {
      append(source.substring(with: NSRange(location: start, length: match.range.location - start)), to: &segments)
      start = NSMaxRange(match.range)
      if segments.count == maximumSegments { return segments }
    }
    append(source.substring(from: start), to: &segments)
    return Array(segments.prefix(maximumSegments))
  }

  private static func append(_ value: String, to segments: inout [String]) {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if !clean.isEmpty { segments.append(clean) }
  }

  private static func normalized(_ goal: String) -> [String] {
    let clean = goal.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? [] : [clean]
  }

  private static let expression: NSRegularExpression? = {
    let comma = String(UnicodeScalar(0xff0c)!)
    let transitions = [
      [0x7136, 0x540e],
      [0x63a5, 0x7740],
      [0x968f, 0x540e]
    ].map { scalars in
      scalars.compactMap { UnicodeScalar($0) }.map(String.init).joined()
    }
    let localized = transitions
      .map { NSRegularExpression.escapedPattern(for: $0) }
      .joined(separator: "|")
    let pattern = "\\s+\\band\\s+then\\b\\s+|(?:[,\(comma)]\\s*)?(?:\(localized))\\s*"
    return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
  }()
}
