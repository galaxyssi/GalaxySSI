import Foundation

enum AgentCodeDiscussionPolicy {
  static func isInformational(_ goal: String) -> Bool {
    let normalized = AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(goal)
      .lowercased(with: Locale(identifier: "en_US_POSIX"))
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return matches(discussionPattern, in: normalized) &&
      !matches(executionOverridePattern, in: normalized)
  }

  private static func matches(_ pattern: String, in value: String) -> Bool {
    value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
  }

  private static let discussionPattern =
    "(?:\\b(?:list|outline|describe|suggest|propose|explain)\\b.{0,96}" +
    "\\b(?:test cases?|unit tests?|test scenarios?)\\b|" +
    "(?:\u{5217}\u{51fa}|\u{7ed9}\u{51fa}|\u{8bf4}\u{660e}|\u{63cf}\u{8ff0}|\u{5efa}\u{8bae}|" +
    "\u{8bbe}\u{8ba1}).{0,64}(?:\u{5355}\u{5143}\u{6d4b}\u{8bd5}|\u{6d4b}\u{8bd5}\u{573a}\u{666f}|" +
    "\u{6d4b}\u{8bd5}\u{7528}\u{4f8b}))"

  private static let executionOverridePattern =
    "(?:\\b(?:write|create|implement|run|execute|add|modify|edit|fix)\\b.{0,96}" +
    "\\b(?:tests?|unit tests?|test cases?|code|function|program|project|repository|files?)\\b|" +
    "(?:\u{7f16}\u{5199}|\u{521b}\u{5efa}|\u{5b9e}\u{73b0}|\u{8fd0}\u{884c}|\u{6267}\u{884c}|" +
    "\u{6dfb}\u{52a0}|\u{4fee}\u{6539}|\u{7f16}\u{8f91}|\u{4fee}\u{590d}).{0,64}" +
    "(?:\u{6d4b}\u{8bd5}|\u{4ee3}\u{7801}|\u{51fd}\u{6570}|\u{7a0b}\u{5e8f}|\u{9879}\u{76ee}|" +
    "\u{4ed3}\u{5e93}|\u{6587}\u{4ef6}|\u{5b83}\u{4eec}|\u{8fd9}\u{4e9b}))"
}
