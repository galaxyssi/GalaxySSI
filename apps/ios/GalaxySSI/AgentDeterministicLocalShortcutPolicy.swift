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
      !AgentDeviceMutationShortcutCoverage.requiresReasoning(goal) &&
      !requirements.complexReasoning &&
      requirements.executionHorizon == .interactive &&
      !requirements.capabilities.contains(.taskExecution) &&
      intent != .desktopControl &&
      !AgentExplicitMultiAgentIntentPolicy.matches(goal) &&
      !AgentPhoneRuntimePolicy.shouldUsePhoneRuntime(goal: goal) &&
      AgentGoalSegmentationPolicy.split(goal).count == 1
  }
}

enum AgentInstalledAppLaunchPolicy {
  struct Target: Equatable {
    let name: String
    let explicitlyLocal: Bool
    let appMarker: Bool
  }

  private static let phone = "(?:\\u624b[\\u673a\\u6a5f]|\\u672c[\\u673a\\u6a5f]|iPhone)"
  private static let englishPhone = #"(?:(?:my|this|the)\s+)?(?:phone|device|iphone)"#
  private static let verb = "(?:(?:open|launch|start|run)\\s+|\\u6253[\\u5f00\\u958b]|[\\u5f00\\u958b][\\u542f\\u555f]|[\\u542f\\u555f][\\u52a8\\u52d5]|[\\u8fd0\\u904b]\\u884c)"
  private static let desktopLocation = #"\b(?:on|from)\s+(?:(?:my|this|the)\s+)?(?:computer|desktop|pc|mac|windows|macos)\b"# +
    "|(?:\\u5728)?(?:\\u6211\\u7684)?(?:\\u7535\\u8111|\\u96fb\\u8166)(?:\\u4e0a(?:\\u7684)?|\\u7684)"

  static func target(_ goal: String) -> Target? {
    let trusted = AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(goal)
    var command = AgentLocalCommandText.withoutPoliteness(trusted)
    guard !command.hasSuffix("?"), !command.hasSuffix("\u{ff1f}"),
          command.range(of: desktopLocation, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
    command = AgentLocalCommandText.sentence(command)
    var explicitlyLocal = false
    func strip(_ value: inout String, _ pattern: String) -> Bool {
      guard let range = value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return false }
      value.removeSubrange(range)
      value = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return true
    }
    if strip(&command, "^(?:on\\s+\(englishPhone)(?:\\s*,\\s*|\\s+)|\\u5728(?:\\u6211\\u7684)?\(phone)\\u4e0a[ \\t]*[,\\uff0c]?[ \\t]*)") {
      explicitlyLocal = true
      command = AgentLocalCommandText.withoutPoliteness(command)
    }
    guard strip(&command, "^\(verb)[ \\t]*") else { return nil }
    if strip(&command, "^\\s*(?:\\u6211\\u7684)?\(phone)(?:\\u4e0a(?:\\u7684)?|\\u7684)[ \\t]*") { explicitlyLocal = true }
    if strip(&command, "(?:^|\\s+)on\\s+\(englishPhone)\\s*$") { explicitlyLocal = true }
    let leadingApp = strip(&command, #"^app\s+"#)
    let trailingApp = strip(&command, "(?:\\s+app|\\u5e94\\u7528|\\u61c9\\u7528)$")
    guard AgentLocalCommandText.plainArgument(command, limit: 128),
          command.range(of: "[\\u7136\\u968f\\u96a8][\\u540e\\u5f8c]|\\u63a5[\\u7740\\u8457]|[\\u5e76\\u4e26]\\u4e14",
                        options: .regularExpression) == nil,
          command.range(of: #"^(?:the\s+)?(?:app|device|iphone|website|url|link|wifi|wi-fi|bluetooth|vpn|settings|file(?!\s+manager$)|folder|report|document|timer|countdown|recording|flashlight|torch)(?:\s|$)"#,
                        options: [.regularExpression, .caseInsensitive]) == nil,
          !["\u{624b}\u{673a}", "\u{624b}\u{6a5f}", "\u{672c}\u{673a}", "\u{672c}\u{6a5f}", "\u{5e94}\u{7528}", "\u{61c9}\u{7528}",
            "\u{624b}\u{7535}\u{7b52}", "\u{624b}\u{96fb}\u{7b52}"].contains(command) else { return nil }
    return Target(name: command, explicitlyLocal: explicitlyLocal, appMarker: leadingApp || trailingApp)
  }
}

enum AgentDeviceMutationShortcutCoverage {
  private static let flashlight = #"\b(?:flashlight|torch)\b"# + "|\u{624b}[\u{7535}\u{96fb}]\u{7b52}|[\u{95ea}\u{9583}]\u{5149}[\u{706f}\u{71c8}]"
  private static let switchAction = #"\b(?:on|off|open|close|enable|disable)\b"# +
    "|\u{6253}[\u{5f00}\u{958b}]|[\u{5f00}\u{958b}][\u{542f}\u{555f}]|[\u{5173}\u{95dc}][\u{95ed}\u{9589}\u{6389}]"
  private static let volume = #"\bvolume\b"# + "|\u{97f3}\u{91cf}"
  private static let volumeAction = #"\b(?:set|change|adjust|increase|decrease|raise|lower|turn|mute|unmute)\b|[0-9]"# +
    "|[\u{8bbe}\u{8a2d}\u{8c03}\u{8abf}\u{6539}\u{964d}\u{63d0}]"
  private static let mute = #"\b(?:mute|unmute|turn sound on)\b"# + "|\u{9759}\u{97f3}"
  private static let camera = #"\b(?:open|launch|use) (?:the )?(?:phone )?camera\b|\b(?:take|capture|snap) (?:[a-z0-9]+ )?photos?\b"# +
    "|\u{62cd}(?:\u{7167}|[^\n]{0,48}\u{7167}\u{7247})|\u{6253}[\u{5f00}\u{958b}][^\n]{0,24}(?:\u{76f8}[\u{673a}\u{6a5f}]|[\u{6444}\u{651d}]\u{50cf}[\u{5934}\u{982d}])"
  private static let microphone = #"\b(?:record (?:audio|voice|sound|with microphone)|use microphone to record|start recording)\b"# +
    "|[\u{5f55}\u{9304}]\u{97f3}|\u{5f55}\u{5236}\u{97f3}\u{9891}"
  private static let advice = #"^(?:why|how|explain|describe|what happens)\b"# +
    "|^(?:\u{4e3a}\u{4ec0}\u{4e48}|\u{5982}\u{4f55}|\u{89e3}\u{91ca})"

  static func requiresReasoning(_ goal: String) -> Bool {
    let text = commandText(goal)
    let candidate = (matches(flashlight, text) && matches(switchAction, text)) ||
      (matches(volume, text) && matches(volumeAction, text)) ||
      matches(mute, text) || matches(camera, text) || matches(microphone, text) || isAppLaunch(text)
    return candidate && !AgentDirectNativeToolPlanner.isCompleteDeviceMutationCommand(text)
  }

  static func requiresPhoneReasoning(_ goal: String) -> Bool {
    let text = AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(goal)
    guard requiresReasoning(text), !matches(advice, commandText(text)),
          !AgentDeviceStatusShortcutCoverage.hasExplicitDesktopTarget(text) else { return false }
    let intent = AgentTaskIntentClassifier.classify(goal: text).intent
    return intent != .desktopControl && intent != .code && !AgentPhoneRuntimePolicy.shouldUsePhoneRuntime(goal: text)
  }

  static func prohibitsMutation(_ goal: String) -> Bool {
    let text = commandText(goal)
    guard requiresReasoning(goal) else { return false }
    if matches(advice, text) || text.hasSuffix("?") || text.hasSuffix("\u{ff1f}") { return true }
    return matches(#"^(?:don't|do not|never)\b"# + "|^(?:\u{4e0d}\u{8981}|[\u{522b}\u{5225}])", text) &&
      !matches(#"\b(?:instead|but|then)\b"# + "|\u{800c}\u{662f}|\u{7136}\u{540e}", text)
  }

  static func prohibitsCameraCapture(_ goal: String) -> Bool {
    let text = commandText(goal)
    let app = AgentInstalledAppLaunchPolicy.target(goal)?.name.lowercased()
    return ["camera", "the camera", "phone camera", "\u{76f8}\u{673a}", "\u{76f8}\u{6a5f}",
      "\u{6444}\u{50cf}\u{5934}", "\u{651d}\u{50cf}\u{982d}"].contains(app ?? "") ||
      matches(#"^(?:open|launch) (?:the )?(?:phone )?camera(?: app)?(?: on (?:this|my|the) (?:phone|device|iphone))?$"#, text) ||
      matches("^(?:\u{6253}[\u{5f00}\u{958b}]|\u{542f}\u{52a8}|\u{555f}\u{52d5})(?:\u{624b}[\u{673a}\u{6a5f}])?\u{76f8}[\u{673a}\u{6a5f}]$", text)
  }

  private static func isAppLaunch(_ text: String) -> Bool {
    if AgentDirectNativeToolPlanner.isNamedSystemAppCommand(text) { return true }
    if let target = AgentInstalledAppLaunchPolicy.target(text), target.explicitlyLocal || target.appMarker { return true }
    let nonApp = #"^(?:open|launch)\s+(?:https?://|url\b|website\b|link\b|wifi\b|wi-fi\b|bluetooth\b|vpn\b|settings\b|file\b|folder\b|report\b|document\b)"#
    guard !matches(nonApp, text) else { return false }
    if matches(#"^(?:open|launch)\s+.+\b(?:app|on (?:my|this|the) (?:phone|device|iphone))\b"#, text) { return true }
    if matches(#"\b(?:open|launch)\s+(?:photos|gallery|safari|browser|contacts|calendar|files|messages|dialer|calculator|maps|mail)\b"#, text) { return true }
    if matches(#"^(?:open|launch)\s+[a-z][a-z0-9_-]*$"#, text) { return true }
    return matches("^(?:\u{6253}[\u{5f00}\u{958b}]|\u{542f}\u{52a8}|\u{555f}\u{52d5}).*(?:app|\u{5e94}\u{7528}|\u{61c9}\u{7528}|\u{8ba1}\u{7b97}\u{5668}|\u{8a08}\u{7b97}\u{6a5f})$", text)
  }

  static func unresolvedStandaloneAppLaunch(_ goal: String) -> Bool {
    let text = commandText(goal)
    return isAppLaunch(text) && requiresReasoning(text) &&
      !matches(#"\b(?:and|then|if|after|before|unless|but)\b|[;,]"# + "|[\u{ff0c}\u{ff1b}]|\u{7136}\u{540e}|\u{5982}\u{679c}", text)
  }

  private static func commandText(_ goal: String) -> String {
    let text = AgentLocalCommandText.withoutPoliteness(AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(goal))
      .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    return text.hasSuffix("?") || text.hasSuffix("\u{ff1f}") ? text : AgentLocalCommandText.sentence(text)
  }

  private static func matches(_ pattern: String, _ text: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
  }
}

enum AgentPhoneShortcutRouting {
  static func requiresPhoneReasoning(_ goal: String) -> Bool {
    AgentDeviceStatusShortcutCoverage.requiresPhoneReasoning(goal) ||
      AgentDeviceMutationShortcutCoverage.requiresPhoneReasoning(goal)
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
