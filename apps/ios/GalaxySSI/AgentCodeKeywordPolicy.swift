import Foundation

// Routing hints only: a business field or a delivery constraint is not an execution request.
enum AgentCodeKeywordPolicy {
  static func contains(_ text: String, term: String) -> Bool {
    guard !term.isEmpty else { return false }
    var start = text.startIndex
    while start < text.endIndex,
          let match = text.range(of: term, range: start..<text.endIndex) {
      let before = text[..<match.lowerBound].last
      let after = text[match.upperBound...].first
      let embedded = (isASCIIWord(term.first) && isASCIIWord(before)) ||
        (isASCIIWord(term.last) && isASCIIWord(after))
      let quotedField = (before == "\"" || before == "'") && after == before &&
        text[match.upperBound...].dropFirst().drop(while: { $0.isWhitespace }).first == ":"
      let prefix = String(text[..<match.lowerBound].suffix(80))
      let negated = prefix.range(of: negativeMention, options: [.regularExpression, .caseInsensitive]) != nil
      if !embedded && !quotedField && !negated { return true }
      start = match.upperBound
    }
    return false
  }

  private static func isASCIIWord(_ character: Character?) -> Bool {
    guard let character, character.unicodeScalars.count == 1,
          let scalar = character.unicodeScalars.first else { return false }
    return (97...122).contains(scalar.value) || (48...57).contains(scalar.value) || scalar.value == 95
  }

  // Clause boundaries prevent a negative constraint from swallowing a later positive command.
  private static let negativeMention =
    "(?:(?:\u{4e0d}\u{8981}|\u{4e0d}\u{80fd}|\u{4e0d}\u{5fc5}|\u{65e0}\u{9700}|\u{4e0d}\u{7528}|\u{52ff})(?:\u{53ea})?" +
    "(?:\u{7ed9}\u{51fa}|\u{63d0}\u{4f9b}|\u{8fd4}\u{56de}|\u{8f93}\u{51fa}|\u{5c55}\u{793a}|\u{663e}\u{793a}|" +
    "\u{9644}\u{4e0a}|\u{5305}\u{542b}|\u{7ed9}|\u{5199}|\u{7f16}\u{5199}|\u{751f}\u{6210}|\u{6267}\u{884c}|\u{8fd0}\u{884c})" +
    "[^\u{3002}\u{ff01}\u{ff1f};\u{ff1b},\u{ff0c}\\n]{0,40}|" +
    "(?:\u{4e0d}\u{8981}|\u{65e0}\u{9700}|\u{4e0d}\u{7528}|\u{4e0d}\u{9700}\u{8981})\\s*|" +
    "\\b(?:do not|don't|never|no need to)\\s+(?:only\\s+|just\\s+)?" +
    "(?:give|return|provide|show|output|include|write|generate|run|execute)[^.!?;,\\n]{0,40})$"
}
