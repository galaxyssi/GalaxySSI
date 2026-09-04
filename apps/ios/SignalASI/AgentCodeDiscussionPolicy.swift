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
    "(?:\\b(?:explain|describe|compare|summarize|discuss)\\b|" +
    "(?:\u{8bf4}\u{660e}|\u{89e3}\u{91ca}|\u{63cf}\u{8ff0}|\u{6bd4}\u{8f83}|\u{603b}\u{7ed3}|\u{8ba8}\u{8bba})|" +
    "\\b(?:list|outline|describe|suggest|propose|explain)\\b.{0,96}" +
    "\\b(?:test cases?|unit tests?|test scenarios?)\\b|" +
    "\\b(?:what happens|what occurs|why|how|explain|describe)\\b.{0,128}" +
    "\\b(?:code|function|async|await|promise|error|exception|bug|algorithm)\\b|" +
    "\\b(?:give|provide|show)\\b.{0,64}" +
    "\\b(?:example|sample|snippet|pseudocode|fix|approach)\\b|" +
    "(?:\u{5217}\u{51fa}|\u{7ed9}\u{51fa}|\u{8bf4}\u{660e}|\u{63cf}\u{8ff0}|\u{5efa}\u{8bae}|" +
    "\u{8bbe}\u{8ba1}).{0,64}(?:\u{5355}\u{5143}\u{6d4b}\u{8bd5}|\u{6d4b}\u{8bd5}\u{573a}\u{666f}|" +
    "\u{6d4b}\u{8bd5}\u{7528}\u{4f8b})|" +
    "(?:\u{4f1a}\u{9020}\u{6210}\u{4ec0}\u{4e48}|\u{4f1a}\u{53d1}\u{751f}\u{4ec0}\u{4e48}|" +
    "\u{4e3a}\u{4ec0}\u{4e48}|\u{4e3a}\u{4f55}|\u{5982}\u{4f55}|\u{89e3}\u{91ca}|\u{8bf4}\u{660e}).{0,96}" +
    "(?:\u{4ee3}\u{7801}|\u{51fd}\u{6570}|\u{5f02}\u{6b65}|\u{9519}\u{8bef}|\u{5f02}\u{5e38}|" +
    "\u{7b97}\u{6cd5}|bug|await|promise)|" +
    "(?:\u{7ed9}\u{51fa}|\u{63d0}\u{4f9b}|\u{5c55}\u{793a}).{0,64}" +
    "(?:\u{793a}\u{4f8b}|\u{4f8b}\u{5b50}|\u{6837}\u{4f8b}|\u{4ee3}\u{7801}\u{7247}\u{6bb5}|" +
    "\u{4f2a}\u{4ee3}\u{7801}|\u{4fee}\u{590d}\u{601d}\u{8def}|\u{4fee}\u{590d}\u{65b9}\u{6848}))"

  private static let executionOverridePattern =
    "(?:\\b(?:analyze|inspect|review|audit)\\b.{0,64}" +
    "\\b(?:project|repository|repo|codebase|files?)\\b|" +
    "(?:\u{5206}\u{6790}|\u{68c0}\u{67e5}|\u{5ba1}\u{67e5}|\u{5ba1}\u{8ba1}).{0,64}" +
    "(?:\u{9879}\u{76ee}|\u{4ed3}\u{5e93}|\u{4ee3}\u{7801}\u{5e93}|\u{6587}\u{4ef6})|" +
    "\\b(?:write|create|implement|run|execute|add|modify|edit|fix)\\b.{0,96}" +
    "\\b(?:tests?|unit tests?|test cases?|code|function|program|project|repository|files?|" +
    "bugs?|errors?|exceptions?)\\b|" +
    "\\b(?:write|create|run|execute)\\b.{0,64}\\b(?:examples?|samples?)\\b|" +
    "(?:\u{7f16}\u{5199}|\u{521b}\u{5efa}|\u{5b9e}\u{73b0}|\u{8fd0}\u{884c}|\u{6267}\u{884c}|" +
    "\u{6dfb}\u{52a0}|\u{4fee}\u{6539}|\u{7f16}\u{8f91}|\u{4fee}\u{590d}).{0,64}" +
    "(?:\u{6d4b}\u{8bd5}|\u{4ee3}\u{7801}|\u{51fd}\u{6570}|\u{7a0b}\u{5e8f}|\u{9879}\u{76ee}|" +
    "\u{4ed3}\u{5e93}|\u{6587}\u{4ef6}|\u{9519}\u{8bef}|\u{5f02}\u{5e38}|\u{95ee}\u{9898}|" +
    "\u{5b83}\u{4eec}|\u{8fd9}\u{4e9b})|" +
    "(?:\u{7f16}\u{5199}|\u{521b}\u{5efa}|\u{8fd0}\u{884c}|\u{6267}\u{884c}).{0,64}" +
    "(?:\u{793a}\u{4f8b}|\u{4f8b}\u{5b50}))"
}
