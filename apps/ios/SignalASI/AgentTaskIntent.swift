import Foundation

enum AgentTaskIntent: String, Codable, CaseIterable, Identifiable {
  case chat = "CHAT"
  case code = "CODE"
  case phoneControl = "PHONE_CONTROL"
  case desktopControl = "DESKTOP_CONTROL"
  case research = "RESEARCH"
  case file = "FILE"
  case memory = "MEMORY"
  case automation = "AUTOMATION"

  var id: String { rawValue }
}

struct AgentTaskIntentClassification: Codable, Equatable {
  var intent: AgentTaskIntent
  var confidence: Int
  var matchedSignals: [String]
}

enum AgentTaskIntentClassifier {
  static func classify(
    goal: String,
    hasAttachments: Bool = false
  ) -> AgentTaskIntentClassification {
    let normalized = goal
      .lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    var scores: [AgentTaskIntent: Int] = [:]
    var signals: [AgentTaskIntent: [String]] = [:]

    for rule in rules {
      for term in rule.terms where normalized.contains(term) {
        scores[rule.intent, default: 0] += rule.weight
        signals[rule.intent, default: []].append(term)
      }
    }
    let automationDiscussion = matches(automationDiscussionPattern, in: normalized)
    let scheduledAction = matches(automationFrequencyPattern, in: normalized) &&
      matches(automationActionPattern, in: normalized)
    if !automationDiscussion &&
       (scheduledAction || matches(automationCommandPattern, in: normalized)) {
      scores[.automation, default: 0] += 7
      signals[.automation, default: []].append(
        scheduledAction ? "scheduled-action" : "automation-command"
      )
    }
    if hasAttachments {
      scores[.file, default: 0] += 3
      signals[.file, default: []].append("attachment")
    }
    guard !scores.isEmpty else {
      return AgentTaskIntentClassification(
        intent: .chat,
        confidence: 100,
        matchedSignals: []
      )
    }

    let ranked = scores.sorted { lhs, rhs in
      if lhs.value != rhs.value {
        return lhs.value > rhs.value
      }
      return priorityIndex(lhs.key) < priorityIndex(rhs.key)
    }
    let winner = ranked[0]
    let runnerUpScore = ranked.dropFirst().first?.value ?? 0
    let margin = winner.value - runnerUpScore
    let rawConfidence = 55 + winner.value * 4 + margin * 5
    let confidence = min(max(rawConfidence, 55), 98)
    return AgentTaskIntentClassification(
      intent: winner.key,
      confidence: confidence,
      matchedSignals: uniquePrefix(signals[winner.key] ?? [], limit: 6)
    )
  }

  private struct Rule {
    var intent: AgentTaskIntent
    var weight: Int
    var terms: [String]
  }

  private static func priorityIndex(_ intent: AgentTaskIntent) -> Int {
    intentPriority.firstIndex(of: intent) ?? intentPriority.count
  }

  private static func uniquePrefix(_ values: [String], limit: Int) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values where !seen.contains(value) {
      seen.insert(value)
      result.append(value)
      if result.count == limit {
        break
      }
    }
    return result
  }

  private static func matches(_ pattern: String, in value: String) -> Bool {
    value.range(
      of: pattern,
      options: [.regularExpression, .caseInsensitive]
    ) != nil
  }

  private static let intentPriority: [AgentTaskIntent] = [
    .automation,
    .memory,
    .desktopControl,
    .phoneControl,
    .code,
    .file,
    .research,
    .chat
  ]

  private static let rules = [
    Rule(
      intent: .code,
      weight: 3,
      terms: [
        "build", "compile", "implement", "develop", "code", "program",
        "fix bug", "repository", "pull request", "unit test", "apk",
        "\u{7f16}\u{8bd1}", "\u{6784}\u{5efa}", "\u{5f00}\u{53d1}", "\u{5b9e}\u{73b0}",
        "\u{4ee3}\u{7801}", "\u{7a0b}\u{5e8f}", "\u{4fee}\u{590d} bug", "\u{9879}\u{76ee}",
        "\u{4ed3}\u{5e93}", "\u{5355}\u{5143}\u{6d4b}\u{8bd5}"
      ]
    ),
    Rule(
      intent: .phoneControl,
      weight: 3,
      terms: [
        "phone setting", "open phone app",
        "launch the app on my phone",
        "battery", "flashlight", "camera", "take a photo", "sms",
        "text message", "make a call", "timer", "alarm", "volume",
        "\u{64cd}\u{4f5c}\u{624b}\u{673a}", "\u{63a7}\u{5236}\u{624b}\u{673a}",
        "\u{624b}\u{673a}\u{8bbe}\u{7f6e}", "\u{5728}\u{8fd9}\u{90e8}\u{624b}\u{673a}\u{4e0a}\u{6253}\u{5f00}",
        "\u{5728}\u{624b}\u{673a}\u{4e0a}\u{6253}\u{5f00}",
        "\u{6253}\u{5f00}\u{624b}\u{673a} app",
        "\u{7535}\u{91cf}", "\u{624b}\u{7535}\u{7b52}", "\u{6444}\u{50cf}\u{5934}",
        "\u{62cd}\u{7167}", "\u{77ed}\u{4fe1}", "\u{6253}\u{7535}\u{8bdd}",
        "\u{8ba1}\u{65f6}\u{5668}", "\u{95f9}\u{949f}", "\u{97f3}\u{91cf}"
      ]
    ),
    Rule(
      intent: .desktopControl,
      weight: 3,
      terms: [
        "on my computer", "on the computer", "desktop control",
        "remote desktop", "windows desktop", "open on desktop", "on desktop", "on my desktop",
        "computer screen", "mouse click", "keyboard shortcut",
        "\u{7535}\u{8111}", "\u{8fdc}\u{7a0b}\u{684c}\u{9762}", "\u{63a7}\u{5236}\u{7535}\u{8111}",
        "\u{7535}\u{8111}\u{5c4f}\u{5e55}", "\u{9f20}\u{6807}", "\u{952e}\u{76d8}\u{5feb}\u{6377}\u{952e}"
      ]
    ),
    Rule(
      intent: .research,
      weight: 2,
      terms: [
        "research", "search the web", "look up", "latest", "today's news",
        "current news", "weather", "find sources", "compare sources",
        "\u{8c03}\u{67e5}", "\u{641c}\u{7d22}", "\u{67e5}\u{8d44}\u{6599}", "\u{6700}\u{65b0}",
        "\u{4eca}\u{5929}\u{7684}\u{65b0}\u{95fb}", "\u{65b0}\u{95fb}", "\u{5929}\u{6c14}",
        "\u{67e5}\u{627e}\u{6765}\u{6e90}"
      ]
    ),
    Rule(
      intent: .file,
      weight: 2,
      terms: [
        "file", "pdf", "spreadsheet", "xlsx", "csv", "docx", "image",
        "screenshot", "audio", "video", "archive", "zip", "extract text",
        "convert this", "summarize this document",
        "\u{6587}\u{4ef6}", "\u{8868}\u{683c}", "\u{56fe}\u{7247}", "\u{622a}\u{56fe}",
        "\u{97f3}\u{9891}", "\u{89c6}\u{9891}", "\u{538b}\u{7f29}\u{5305}",
        "\u{63d0}\u{53d6}\u{6587}\u{5b57}", "\u{8f6c}\u{6362}\u{8fd9}\u{4e2a}",
        "\u{603b}\u{7ed3}\u{8fd9}\u{4efd}\u{6587}\u{6863}"
      ]
    ),
    Rule(
      intent: .memory,
      weight: 4,
      terms: [
        "remember that", "remember my", "forget that", "my preference",
        "memory", "knowledge base", "what did i say", "what do you know about me",
        "\u{8bb0}\u{4f4f}", "\u{5fd8}\u{8bb0}", "\u{6211}\u{7684}\u{504f}\u{597d}",
        "\u{8bb0}\u{5fc6}", "\u{77e5}\u{8bc6}\u{5e93}", "\u{6211}\u{4e4b}\u{524d}\u{8bf4}",
        "\u{4f60}\u{8bb0}\u{5f97}"
      ]
    )
  ]

  private static let automationCommandPattern =
    "(?:\\b(?:automate|remind me|monitor continuously)\\b|" +
    "\\b(?:create|set up|configure|add|enable)\\b.{0,48}" +
    "\\b(?:automation|workflow|trigger|reminder|cron|recurring|scheduled (?:job|task))\\b|" +
    "\\bwhen this happens\\b.{0,80}" +
    "\\b(?:run|execute|send|open|start|stop|backup|sync|notify)\\b|" +
    "(?:\u{6301}\u{7eed}\u{76d1}\u{63a7}|\u{63d0}\u{9192}\u{6211})|" +
    "(?:\u{521b}\u{5efa}|\u{8bbe}\u{7f6e}|\u{914d}\u{7f6e}|\u{6dfb}\u{52a0}|\u{5f00}\u{542f}|" +
    "\u{5b89}\u{6392}).{0,24}(?:\u{5de5}\u{4f5c}\u{6d41}|\u{89e6}\u{53d1}\u{5668}|" +
    "\u{63d0}\u{9192}|\u{5b9a}\u{65f6}\u{4efb}\u{52a1}|\u{81ea}\u{52a8}\u{5316})|" +
    "\u{5b9a}\u{65f6}.{0,24}(?:\u{8fd0}\u{884c}|\u{6267}\u{884c}|\u{68c0}\u{67e5}|" +
    "\u{76d1}\u{63a7}|\u{53d1}\u{9001}|\u{5907}\u{4efd}|\u{540c}\u{6b65}|\u{63d0}\u{9192}))"

  private static let automationFrequencyPattern =
    "(?:\\bevery\\s+(?:minute|hour|day|week|month|morning|evening)s?\\b|" +
    "\\b(?:hourly|daily|weekly|monthly)\\b|" +
    "(?:\u{6bcf}\u{5206}\u{949f}|\u{6bcf}\u{5c0f}\u{65f6}|\u{6bcf}\u{5929}|" +
    "\u{6bcf}\u{65e5}|\u{6bcf}\u{5468}|\u{6bcf}\u{6708}|\u{6bcf}\u{665a}|\u{6bcf}\u{65e9}))"
  private static let automationActionPattern =
    "(?:\\b(?:run|execute|check|monitor|send|open|start|stop|backup|sync|fetch|publish)\\b|" +
    "\\bturn\\s+(?:on|off)\\b|" +
    "(?:\u{8fd0}\u{884c}|(?<!\u{53ef})\u{6267}\u{884c}|\u{68c0}\u{67e5}|\u{76d1}\u{63a7}|" +
    "\u{53d1}\u{9001}|\u{6253}\u{5f00}|\u{5f00}\u{542f}|\u{5173}\u{95ed}|\u{5907}\u{4efd}|" +
    "\u{540c}\u{6b65}|\u{542f}\u{52a8}|\u{505c}\u{6b62}|\u{63d0}\u{9192}|\u{63a8}\u{9001}|" +
    "\u{62c9}\u{53d6}|\u{53d1}\u{5e03}))"
  private static let automationDiscussionPattern =
    "(?:[?\u{ff1f}]|\\b(?:why|how|whether|compare|difference|does|do|is|are|explain|describe)\\b|" +
    "(?:\u{662f}\u{5426}|\u{4e3a}\u{4ec0}\u{4e48}|\u{4e3a}\u{4f55}|\u{600e}\u{4e48}|" +
    "\u{5982}\u{4f55}|\u{6bd4}\u{8f83}|\u{533a}\u{522b}|\u{89e3}\u{91ca}|\u{8bf4}\u{660e}))"
}
