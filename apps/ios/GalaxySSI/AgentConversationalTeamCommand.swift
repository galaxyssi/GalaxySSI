import Foundation

enum AgentConversationalTeamCommand: Equatable {
  case start(String), stop, help, tooLong, privateObjective
  private static let team = #"(?:a |an |the )?(?:(?:temporary|agent|small|multi-agent) )?team\b"#
  private static let agents = #"(?:multiple|several|different|independent|two or more) agents\b"#
  private static let review = #"(?:an? |some )?independent (?:review|assessment|critique|check)\b"#
  private static let invite = #"(?:have|ask|let|use|get|assemble|form|create|organize|bring together)"#
  private static let work = #"(?:work|help|review|check|assess|analy[sz]e|compare|evaluate|draft|plan|research|solve|use|challenge|collaborate|investigate|design|write|tackle|brainstorm)"#
  private static let want = #"\b(?:i|we)(?: need| want| would like|['\u2019]d like) "#
  private static let request = #"(?:^|\bplease\s+|\b(?:can|could|would|will) you\s+|\#(want)you to |\b(?:and|then)\s+)(?:please\s+)?(?:\#(invite) (?:\#(team)|\#(agents))(?: (?:of agents )?(?:to )?(?:(?:independently|jointly) )?\#(work)\b| (?:for|on) (?:this|the following)\b|\s*$)|(?:work|collaborate) (?:together )?as \#(team)|team up\b|(?:give me |provide |do |run |conduct |arrange |request |seek |get (?:me )?)\#(review)|independently (?:review|assess|check|critique|verify)\b)|\#(want)(?:\#(review)|(?:\#(team)|\#(agents)) to \#(work)\b)"#
  private static let withTeam = #"^(?:(?:can|could|would) you )?(?:please )?(?:review|compare|assess|evaluate|draft|analy[sz]e|solve|research|design)\b.+?\s(?:as (?:a |an )?(?:agent )?team|with (?:a team of agents|\#(agents)))\b"#
  private static let quotes = ##"```[\s\S]*?(?:```|$)|`[^`]*(?:`|$)|"[^"]*(?:"|$)|\u201c[^\u201d]*(?:\u201d|$)|\u300c[^\u300d]*(?:\u300d|$)|\u2018[^\u2019]*(?:\u2019|$)|(?<!\w)'[^'\n]+'(?!\w)"##
  private static let separators = CharacterSet(charactersIn: ",.!?;\n\u{ff0c}\u{3002}\u{ff01}\u{ff1f}\u{ff1b}")

  static func text(_ key: String, _ fallback: String, language: String = LanguagePolicySettings.auto) -> String {
    GalaxySSILocalization.string("galaxyssi.conversation_team." + key, fallback: fallback, language: language)
  }
  private static func matches(_ value: String, key: String, english: String, entire: Bool = false) -> Bool {
    let translated = text("pattern_" + key, english, language: LanguagePolicySettings.zhCN)
    return Set([english, translated]).contains { pattern in
      value.range(of: entire ? "^(?:" + pattern + ")$" : pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
  }
  private static let negative = #"\b(?:do not|don't|don\u2019t|not to|never|without|no need to|no)\s+(?:(?:do|use|using|form|forming|ask|asking|have|having|need|want|get|an?|the|any|to)\s+){0,4}(?:team|agents?|multiple agents|multi-agent|delegat\w*|independent(?:ly)?)\b"#
  private static let meta = #"^(?:(?:please |can you |could you )?(?:explain|translate|define|describe|tell me (?:about|how|what|why))\b|(?:what|why|how|when|where|should|does|is it|do (?:i|we))\b)"#
  static func requestsFinalAudit(_ text: String) -> Bool {
    guard text.utf16.count <= 8_000, let regex = try? NSRegularExpression(pattern: quotes) else { return false }
    let visible = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
    let audit = #"(?:^|\bplease\s+|\bthen\s+|\band\s+)(?:provide\s+|perform\s+|arrange\s+|request\s+|get\s+)?(?:independently (?:review|audit|check)|(?:an? )?independent (?:final )?(?:review|audit|check)(?: of)?) (?:the |my |our )?(?:final (?:answer|draft|response|report)|conclusion)\b"#
    return visible.components(separatedBy: separators).contains { clause in
      let value = clause.trimmingCharacters(in: .whitespacesAndNewlines)
      return !matches(value, key: "negative", english: negative) && !matches(value, key: "meta", english: meta) &&
        matches(value, key: "final_audit", english: audit)
    }
  }
  static func allowsModelReview(_ text: String, language: String) -> Bool {
    !text.isBlank && !text.hasPrefix("/") && makeStart(text) == .start(text) &&
      !matches(text, key: "negative", english: negative) &&
      GalaxySSIHealthAgentLab.intent(text, following: true, language: language) == nil
  }
  private static func makeStart(_ objective: String) -> Self {
    guard objective.utf16.count <= 4_000 else { return .tooLong }
    let health = #"\b(?:my|our|patient['\u2019]s)\s+(?:(?:latest|last|recent|personal)\s+){0,2}(?:health records?|medical records?|lab results?|blood (?:pressure|sugar|tests?)|diagnosis|prescriptions?|symptoms?)\b|\bblood pressure\b\s*[:=]?\s*\d{2,3}\s*/\s*\d{2,3}"#
    return matches(objective, key: "health", english: health) ? .privateObjective : .start(objective)
  }
  static func parse(_ input: String) -> Self? {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("/") {
      guard text.prefix(5).lowercased() == "/team" else { return nil }
      let suffix = text.dropFirst(5)
      guard suffix.isEmpty || suffix.first?.isWhitespace == true else { return nil }
      let objective = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
      if objective.isEmpty || ["help", Self.text("help_alias", "help", language: LanguagePolicySettings.zhCN)].contains(objective.lowercased()) { return .help }
      if ["stop", Self.text("stop_alias", "stop", language: LanguagePolicySettings.zhCN)].contains(objective.lowercased()) { return .stop }
      return makeStart(objective)
    }
    let stop = #"(?:(?:could|can|would|will) you )?(?:please )?(?:stop|cancel|end) (?:the |this |my |our |current )*(?:(?:temporary |agent |auto )?team(?: run| task| collaboration)?|multi-agent run)(?: please)?[.!?]*"#
    if text.utf16.count <= 100 && matches(text, key: "stop", english: stop, entire: true) { return .stop }
    guard let quoted = try? NSRegularExpression(pattern: quotes) else { return nil }
    let prefix = String(text.prefix(4_000))
    let visible = quoted.stringByReplacingMatches(in: prefix, range: NSRange(prefix.startIndex..., in: prefix), withTemplate: " ")
    if matches(visible, key: "negative", english: negative) { return nil }
    let requested = visible.components(separatedBy: separators).contains { clause in
      let value = clause.trimmingCharacters(in: .whitespacesAndNewlines)
      return !value.isEmpty && !matches(value, key: "meta", english: meta) &&
        (matches(value, key: "request", english: request) || matches(value, key: "with_team", english: withTeam))
    }
    return requested ? makeStart(text) : nil
  }
}
