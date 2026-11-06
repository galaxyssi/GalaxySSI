import Foundation

enum AgentLocalCommandText {
  static func withoutPoliteness(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "^(?:please[ \\t]+|[\u{8bf7}\u{8acb}](?!\u{6c42})(?:[\u{5e2e}\u{5e6b}]\u{6211})?[ \\t]*)",
                            with: "", options: [.regularExpression, .caseInsensitive])
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func sentence(_ value: String) -> String {
    var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    while let last = result.last, ".!?\u{3002}\u{ff01}\u{ff1f}".contains(last) { result.removeLast() }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func matches(_ value: String, _ commands: [String]) -> Bool {
    commands.contains(sentence(value))
  }

  static func startsCommand(_ value: String, _ commands: [String]) -> Bool {
    commands.contains { command in
      guard value.hasPrefix(command) else { return false }
      guard let next = value.dropFirst(command.count).first else { return true }
      return next.isWhitespace || next.isPunctuation || next.asciiValue == nil
    }
  }

  static func captures(_ value: String, _ pattern: String) -> [String]? {
    guard value.utf8.count <= 16_384,
          let regex = try? NSRegularExpression(pattern: "\\A(?:\(pattern))\\z", options: .caseInsensitive) else {
      return nil
    }
    let text = value as NSString
    guard let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: text.length)) else { return nil }
    return (1..<match.numberOfRanges).map {
      let range = match.range(at: $0)
      return range.location == NSNotFound ? "" : text.substring(with: range)
    }
  }

  static func read(_ value: String, _ subjects: [String]) -> Bool {
    let aliases = subjects.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
    let english = #"(?:(?:read|check|show|get)\s+)?(?:(?:the|my)\s+)?(?:(?:current|available|remaining|free)\s+)?(?:\#(aliases))(?:\s+on\s+(?:this|my|the)\s+(?:phone|device))?"#
    let chinese = "(?:\u{8bfb}\u{53d6}|\u{67e5}\u{770b}|\u{67e5}\u{8be2}|\u{83b7}\u{53d6})?" +
      "(?:\u{5f53}\u{524d}|\u{624b}\u{673a}|\u{8bbe}\u{5907})?(?:\(aliases))"
    let brief = "(?:[,;\u{ff0c}][ \\t]*(?:(?:please )?(?:reply|answer) briefly|\u{8bf7}?\u{7b80}\u{77ed}\u{56de}\u{7b54}))?"
    return captures(sentence(value), "(?:\(english)|\(chinese))\(brief)") != nil
  }

  static func plainArgument(_ value: String, limit: Int) -> Bool {
    guard !value.isEmpty, value.count <= limit else { return false }
    let separators = CharacterSet(charactersIn: ";,.!?\u{ff1b}\u{ff0c}\u{3002}\u{ff01}\u{ff1f}")
      .union(.newlines).union(.controlCharacters)
    guard value.rangeOfCharacter(from: separators) == nil else { return false }
    let continuation = "\\b(?:and|or|then|also|if|unless|before|after|except|without|but|not|when|while|instead)\\b|" +
      "\u{7136}\u{540e}|\u{5e76}\u{4e14}|\u{5982}\u{679c}|\u{5426}\u{5219}|\u{4e0d}\u{8981}|\u{4e4b}\u{540e}"
    return value.range(of: continuation, options: [.regularExpression, .caseInsensitive]) == nil
  }

  static let phonePattern = #"\+?[0-9][0-9 ()-]{1,30}[0-9]"#

  static func phone(_ value: String) -> String? {
    let digits = value.filter { "0123456789".contains($0) }
    guard (3...18).contains(digits.count), captures(value, phonePattern) != nil else { return nil }
    return value.hasPrefix("+") ? "+" + digits : digits
  }
}

enum AgentDeterministicLocalShortcutPolicy {
  static func isEligible(
    request: AgentPlanRequest,
    hasAttachments: Bool = false
  ) -> Bool {
    let goal = request.goal.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !goal.isEmpty, !hasAttachments else { return false }
    let requirements = AgentTaskRequirementAnalyzer.analyze(goal)
    let intent = AgentTaskIntentClassifier.classify(
      goal: goal,
      hasAttachments: hasAttachments
    ).intent
    return !requirements.complexReasoning &&
      requirements.executionHorizon == .interactive &&
      !requirements.capabilities.contains(.taskExecution) &&
      intent != .desktopControl &&
      !AgentExplicitMultiAgentIntentPolicy.matches(goal) &&
      !AgentPhoneRuntimePolicy.shouldUsePhoneRuntime(goal: goal) &&
      AgentGoalSegmentationPolicy.split(goal).count == 1
  }
}
