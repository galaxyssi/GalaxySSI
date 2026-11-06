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

  static func statusRead(_ value: String, _ subjects: [String]) -> Bool {
    if read(value, subjects) { return true }
    let aliases = subjects.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
    let prefix = "(?:[\u{8bfb}\u{8b80}]\u{53d6}|\u{67e5}(?:\u{770b}|[\u{8be2}\u{8a62}]|\u{4e00}?\u{4e0b})?|[\u{83b7}\u{7372}]\u{53d6})?" +
      "(?:[\u{8fd9}\u{9019}][\u{53f0}\u{90e8}]|\u{6211}\u{7684})?(?:\u{624b}[\u{673a}\u{6a5f}]|[\u{8bbe}\u{8a2d}][\u{5907}\u{5099}])?\u{7684}?" +
      "(?:[\u{5f53}\u{7576}]\u{524d}|[\u{73b0}\u{73fe}]\u{5728}|[\u{8fd8}\u{9084}]\u{6709}\u{591a}\u{5c11}|\u{5269}[\u{4f59}\u{9918}]|\u{53ef}\u{7528})?"
    let suffix = "(?:\u{591a}\u{5c11}|\u{72b6}\u{6001}|\u{72c0}\u{614b})?" +
      "(?:[,\u{ff0c}]\\s*[\u{8bf7}\u{8acb}]?[\u{7b80}\u{7c21}]\u{77ed}\u{56de}[\u{7b54}\u{590d}\u{8986}])?"
    let text = sentence(value)
    guard text.range(of: #"\p{Han}"#, options: .regularExpression) != nil else { return false }
    return captures(text, "\(prefix)(?:\(aliases))\(suffix)") != nil
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
    return !AgentDeviceStatusShortcutCoverage.requiresReasoning(goal) &&
      !requirements.complexReasoning &&
      requirements.executionHorizon == .interactive &&
      !requirements.capabilities.contains(.taskExecution) &&
      intent != .desktopControl &&
      !AgentExplicitMultiAgentIntentPolicy.matches(goal) &&
      !AgentPhoneRuntimePolicy.shouldUsePhoneRuntime(goal: goal) &&
      AgentGoalSegmentationPolicy.split(goal).count == 1
  }
}

enum AgentDeviceStatusShortcutCoverage {
  private static let subjects = #"(?<![a-z0-9])(?:battery|power status|power saving|low power|memory|ram|storage|network|bluetooth status|nfc|wi-?fi|audio status|sound status|volume status|vpn|(?:phone|device) (?:status|health))(?![a-z0-9])"# +
    "|\u{7535}\u{91cf}|\u{96fb}\u{91cf}|\u{7535}\u{6c60}|\u{96fb}\u{6c60}|\u{5185}\u{5b58}|\u{5167}\u{5b58}|\u{5b58}\u{50a8}|\u{5132}\u{5b58}|\u{7f51}\u{7edc}|\u{7db2}[\u{7d61}\u{8def}]|\u{84dd}\u{7259}|\u{85cd}\u{7259}|\u{97f3}\u{91cf}|\u{7701}[\u{7535}\u{96fb}]|[\u{7535}\u{96fb}]\u{6e90}|\u{7a7a}[\u{95f4}\u{9593}]"
  private static let readSignal = #"\b(?:read|check|show|get|current|available|remaining|free|status|how much|if|when|unless)\b"# +
    "|[\u{8bfb}\u{8b80}\u{67e5}]|\u{5f53}\u{524d}|\u{7576}\u{524d}|\u{5269}\u{4f59}|\u{5269}\u{9918}|\u{53ef}\u{7528}|\u{591a}\u{5c11}|\u{72b6}\u{6001}|\u{72c0}\u{614b}|\u{5982}\u{679c}"
  private static let listSeparator = #"\s+and\s+|[,;]"# + "|[\u{ff0c}\u{ff1b}\u{3001}\u{548c}\u{8207}\u{4e0e}]|\u{4ee5}\u{53ca}"
  private static let desktop = #"\b(?:computer|desktop|windows|macos)\b"# + "|\u{7535}\u{8111}|\u{96fb}\u{8166}"
  private static let discussion = #"^(?:explain|describe|define|compare|what (?:is|are)|how (?:does|do))\b"# +
    "|^(?:\u{89e3}\u{91ca}|\u{89e3}\u{91cb}|\u{4ec0}\u{4e48}\u{662f}|\u{4ec0}\u{9ebc}\u{662f})"
  private static let action = #"\b(?:read|check|show|get|save|export|set|turn)\b"# + "|[\u{8bfb}\u{8b80}\u{67e5}]"

  static func requiresReasoning(_ goal: String) -> Bool {
    let text = AgentLocalCommandText.sentence(
      AgentLocalCommandText.withoutPoliteness(AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(goal))
    ).lowercased()
    guard matches(subjects, in: text), !AgentDirectNativeToolPlanner.isCompleteDeviceStatusRead(text) else { return false }
    if matches(discussion, in: text), !matches(action, in: text) { return false }
    if matches(readSignal, in: text) { return true }
    let parts = text.replacingOccurrences(of: listSeparator, with: "\n", options: .regularExpression)
      .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    return parts.count > 1 && parts.allSatisfy(AgentDirectNativeToolPlanner.isCompleteDeviceStatusRead)
  }

  static func requiresPhoneReasoning(_ goal: String) -> Bool {
    let text = AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(goal)
    guard requiresReasoning(text), !hasExplicitDesktopTarget(text) else { return false }
    let intent = AgentTaskIntentClassifier.classify(goal: text).intent
    return intent != .desktopControl && intent != .code && !AgentPhoneRuntimePolicy.shouldUsePhoneRuntime(goal: text)
  }

  static func hasExplicitDesktopTarget(_ goal: String) -> Bool {
    matches(desktop, in: AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(goal).lowercased())
  }

  private static func matches(_ pattern: String, in text: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
  }
}
