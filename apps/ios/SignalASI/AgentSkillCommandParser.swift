import Foundation

enum AgentSkillCommandParser {
  static func isSaveCommand(_ value: String) -> Bool {
    let text = normalize(value)
    if text.hasPrefix("\u{4e0d}\u{8981}") || text.hasPrefix("do not ") || text.hasPrefix("don't ") {
      return false
    }
    return savePrefixes.contains(where: text.hasPrefix) ||
      savePhrases.contains(where: text.contains)
  }

  static func isUpgradeCommand(_ value: String) -> Bool {
    let text = normalize(value)
    return upgradePrefixes.contains(where: text.hasPrefix)
  }

  private static func normalize(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  }

  private static let savePrefixes: Set<String> = [
    "save as skill",
    "save this as a skill",
    "save this method",
    "remember this method",
    "\u{4fdd}\u{5b58}\u{6210}skill",
    "\u{4fdd}\u{5b58}\u{6210} skill",
    "\u{4fdd}\u{5b58}\u{4e3a}skill",
    "\u{4fdd}\u{5b58}\u{4e3a} skill",
    "\u{628a}\u{8fd9}\u{4e2a}\u{4fdd}\u{5b58}\u{4e3a}skill",
    "\u{628a}\u{8fd9}\u{4e2a}\u{4fdd}\u{5b58}\u{4e3a} skill",
    "\u{628a}\u{521a}\u{624d}\u{7684}\u{65b9}\u{6cd5}\u{4fdd}\u{5b58}\u{4e0b}\u{6765}",
    "\u{4ee5}\u{540e}\u{6309}\u{8fd9}\u{4e2a}\u{65b9}\u{5f0f}\u{6267}\u{884c}"
  ]

  private static let savePhrases: Set<String> = [
    "\u{628a}\u{8fd9}\u{4e2a}\u{4fdd}\u{5b58}\u{6210}skill",
    "\u{628a}\u{8fd9}\u{4e2a}\u{4fdd}\u{5b58}\u{6210} skill"
  ]

  private static let upgradePrefixes: Set<String> = [
    "upgrade skill",
    "upgrade this skill",
    "improve this skill",
    "\u{5347}\u{7ea7}skill",
    "\u{5347}\u{7ea7} skill",
    "\u{5347}\u{7ea7}\u{8fd9}\u{4e2a}skill",
    "\u{5347}\u{7ea7}\u{8fd9}\u{4e2a} skill",
    "\u{6539}\u{8fdb}\u{8fd9}\u{4e2a}skill",
    "\u{6539}\u{8fdb}\u{8fd9}\u{4e2a} skill"
  ]
}
