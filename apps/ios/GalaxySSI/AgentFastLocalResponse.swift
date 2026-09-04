import Foundation

enum AgentFastLocalResponse {
  static func reply(goal: String, context: AgentConversationContext) -> String? {
    let clean = goal.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.isEmpty {
      return nil
    }
    if let sharedStorageReply = sharedStorageAccessReply(goal: clean) {
      return sharedStorageReply
    }
    if let arithmeticReply = arithmetic(goal: clean) {
      return arithmeticReply
    }
    let priorTurns: [AgentTranscriptEntry]
    if let last = context.turns.last,
      last.role == .user,
      last.text.trimmingCharacters(in: .whitespacesAndNewlines) == clean {
      priorTurns = Array(context.turns.dropLast())
    } else {
      priorTurns = context.turns
    }
    if !priorTurns.isEmpty || !context.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return nil
    }
    let normalized = trimTrailingPromptPunctuation(clean)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if vagueChinese.contains(normalized) {
      return chineseVagueReply
    }
    if vagueEnglish.contains(normalized) {
      return englishVagueReply
    }
    return nil
  }

  private static func sharedStorageAccessReply(goal: String) -> String? {
    guard firstMatch(pattern: rawSharedStoragePathPattern, in: goal, options: .caseInsensitive) != nil else {
      return nil
    }
    let lower = goal.lowercased()
    let requestsFileAccess = fileAccessTerms.contains { lower.contains($0) }
    guard requestsFileAccess else {
      return nil
    }
    return containsCJK(goal) ? chineseSharedStorageReply : englishSharedStorageReply
  }

  private static func arithmetic(goal: String) -> String? {
    if goal.count > 100 {
      return nil
    }
    let matches = allMatches(pattern: binaryExpressionPattern, in: goal)
    guard matches.count == 1 else {
      return nil
    }
    let lower = goal.lowercased()
    let explicit = firstMatch(pattern: bareExpressionPattern, in: goal) != nil ||
      arithmeticIntentTerms.contains { lower.contains($0) }
    guard explicit else {
      return nil
    }
    let match = matches[0]
    guard match.count >= 4,
      let left = Decimal(string: match[1]),
      let right = Decimal(string: match[3]) else {
      return nil
    }
    let result: Decimal
    switch match[2] {
    case "+":
      result = left + right
    case "-":
      result = left - right
    case "x", "X", "*", "\u{00d7}":
      result = left * right
    case "/", "\u{00f7}":
      guard right != 0 else {
        return nil
      }
      result = NSDecimalNumber(decimal: left)
        .dividing(by: NSDecimalNumber(decimal: right), withBehavior: decimalBehavior)
        .decimalValue
    default:
      return nil
    }
    return plainDecimalString(result)
  }

  private static func trimTrailingPromptPunctuation(_ value: String) -> String {
    var result = value
    while let last = result.last, trailingPromptPunctuation.contains(last) {
      result.removeLast()
    }
    return result
  }

  private static func containsCJK(_ value: String) -> Bool {
    value.unicodeScalars.contains { scalar in
      scalar.value >= 0x3400 && scalar.value <= 0x9fff
    }
  }

  private static func firstMatch(
    pattern: String,
    in value: String,
    options: NSRegularExpression.Options = []
  ) -> [String]? {
    allMatches(pattern: pattern, in: value, options: options).first
  }

  private static func allMatches(
    pattern: String,
    in value: String,
    options: NSRegularExpression.Options = []
  ) -> [[String]] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
      return []
    }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return regex.matches(in: value, options: [], range: range).map { match in
      (0..<match.numberOfRanges).map { index in
        guard let range = Range(match.range(at: index), in: value) else {
          return ""
        }
        return String(value[range])
      }
    }
  }

  private static func plainDecimalString(_ value: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 16
    return formatter.string(from: NSDecimalNumber(decimal: value)) ?? NSDecimalNumber(decimal: value).stringValue
  }

  private static let binaryExpressionPattern =
    "(-?\\d+(?:\\.\\d+)?)\\s*([+\\-xX*\u{00d7}/\u{00f7}])\\s*(-?\\d+(?:\\.\\d+)?)"
  private static let bareExpressionPattern =
    "^\\s*-?\\d+(?:\\.\\d+)?\\s*[+\\-xX*\u{00d7}/\u{00f7}]\\s*-?\\d+(?:\\.\\d+)?" +
    "\\s*(?:[=\u{ff1d}]\\s*)?[?\u{3002}\u{ff1f}!\u{ff01}]?\\s*$"
  private static let rawSharedStoragePathPattern =
    #"(?:^|\s)(/(?:storage/emulated/\d+|storage/self/primary|sdcard|mnt/sdcard)/[^\s]+)"#
  private static let vagueChinese: Set<String> = [
    "\u{5e2e}\u{6211}\u{5904}\u{7406}\u{4e00}\u{4e0b}",
    "\u{5e2e}\u{6211}\u{5f04}\u{4e00}\u{4e0b}",
    "\u{5904}\u{7406}\u{4e00}\u{4e0b}",
    "\u{4f60}\u{770b}\u{7740}\u{529e}"
  ]
  private static let vagueEnglish: Set<String> = [
    "help me with this",
    "handle this",
    "deal with this",
    "do something with this"
  ]
  private static let fileAccessTerms = [
    "read", "open", "inspect", "view", "summarize", "analyze",
    "\u{8bfb}\u{53d6}", "\u{6253}\u{5f00}", "\u{67e5}\u{770b}", "\u{68c0}\u{67e5}",
    "\u{603b}\u{7ed3}", "\u{5206}\u{6790}"
  ]
  private static let arithmeticIntentTerms = [
    "calculate", "what is", "result", "answer",
    "\u{8ba1}\u{7b97}", "\u{7b97}\u{4e00}\u{4e0b}", "\u{7ed3}\u{679c}", "\u{53ea}\u{7ed9}\u{51fa}"
  ]
  private static let trailingPromptPunctuation: Set<Character> = [
    ".", "!", "?", "\u{3002}", "\u{ff01}", "\u{ff1f}"
  ]
  private static let decimalBehavior = NSDecimalNumberHandler(
    roundingMode: .plain,
    scale: 16,
    raiseOnExactness: false,
    raiseOnOverflow: false,
    raiseOnUnderflow: false,
    raiseOnDivideByZero: false
  )
  private static let englishVagueReply =
    "What should I work on? Send text, a file, or an image, or tell me whether to inspect, edit, summarize, or execute it."
  private static let englishSharedStorageReply =
    "iOS does not let apps read this raw shared-storage path directly. Select the file again with the input bar's file button; after you grant access, I will process it directly."
  private static let chineseVagueReply =
    "\u{4f60}\u{60f3}\u{8ba9}\u{6211}\u{5904}\u{7406}\u{4ec0}\u{4e48}\u{ff1f}\u{53ef}\u{4ee5}\u{53d1}\u{6587}\u{5b57}\u{3001}\u{6587}\u{4ef6}\u{6216}\u{56fe}\u{7247}\u{ff0c}\u{6216}\u{76f4}\u{63a5}\u{8bf4}\u{8981}\u{6211}\u{67e5}\u{770b}\u{3001}\u{4fee}\u{6539}\u{3001}\u{603b}\u{7ed3}\u{8fd8}\u{662f}\u{6267}\u{884c}\u{3002}"
  private static let chineseSharedStorageReply =
    "iOS \u{4e0d}\u{5141}\u{8bb8} App \u{76f4}\u{63a5}\u{8bfb}\u{53d6}\u{8fd9}\u{4e2a}\u{5171}\u{4eab}\u{5b58}\u{50a8}\u{8def}\u{5f84}\u{3002}\u{8bf7}\u{70b9}\u{8f93}\u{5165}\u{680f}\u{7684}\u{6587}\u{4ef6}\u{6309}\u{94ae}\u{91cd}\u{65b0}\u{9009}\u{62e9}\u{8be5}\u{6587}\u{4ef6}\u{ff0c}\u{6388}\u{6743}\u{540e}\u{6211}\u{4f1a}\u{76f4}\u{63a5}\u{5904}\u{7406}\u{3002}"
}
