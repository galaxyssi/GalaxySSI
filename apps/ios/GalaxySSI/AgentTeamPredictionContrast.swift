import Foundation

enum AgentTeamPredictionContrast {
  struct Text {
    var format = "Purpose: %1$@\nPrediction: If %2$@ is %3$@, a valid reading of %4$@ should be %5$@.\nContrary observation: Under the same assumptions, if %2$@ is %3$@, a valid reading of %4$@ that is %6$@ would contradict the prediction; a missing, invalid or uninterpretable measurement would not.\nAlternative explanation: %7$@; missing evidence: %8$@. This is a hypothesis, not an experimental or clinical conclusion."
    var higher = "higher"
    var lower = "lower"
    static let english = Text()
  }
  struct Draft { let answer: String; let claim: AgentMcpJSONObject? }
  static let writer = """
    Answer the original objective using the brief and public reports. For a directional hypothesis,
    choose the independent quantity and a different observable quantity. Propose the function yourself.
    Return one flat JSON object with these seven string fields and no other keys:
    purpose: one concise sentence explaining the hypothetical function and intended mechanism.
    input: the name of the independent quantity, without a direction or assumption about the readout.
    input_direction: higher or lower. readout: the name of the observable quantity, without a direction.
    expected_direction: higher or lower. These two directions are English enum values.
    alternative: a competing cause of the same readout; explain why the signal alone is not specific.
    gap: the missing evidence, not a claim that the proposed function exists or works.
    Write the text fields in the objective's language. The host will compare two valid observations
    under the identical input change. It supplies no variable, sign, mechanism or scientific conclusion.
    At synthesis only, if a single directional comparison cannot answer the task, use the ordinary
    single-field answer object instead. At rewrite, correct the fields in response to the actual objection.
    """ + "\n" + AgentConversationalTeamProtocol.boundary
  static let auditor = """
    Independently review the complete rendered draft against the objective, assignment, and public objections.
    The paired statements use the same input change by construction; that alone does not validate the hypothesis.
    Check that the proposed input, readout, direction and alternative make sense, respond to the objective,
    and distinguish a prediction from measured evidence. Do not demand proof for an explicitly hypothetical idea.
    If the whole answer is sound, return only {"verdict":"accept"}. Otherwise use verdict "request_changes"
    with a specific objection for the writer, or "withhold" with the reason in objection. No other keys.
    """ + "\n" + AgentConversationalTeamProtocol.boundary
  private static let fields: Set<String> = ["purpose", "input", "input_direction", "readout", "expected_direction", "alternative", "gap"]
  private static let quotes = ##"```[\s\S]*?(?:```|$)|`[^`]*(?:`|$)|"[^"]*"|\u201c[^\u201d]*\u201d|\u300c[^\u300d]*\u300d|\u2018[^\u2019]*\u2019|(?<!\w)'[^'\n]+'(?!\w)"##
  private static let excluded = #"\b(?:translate|define|do not|don't|don\u2019t|no need to|without asking)\b"#
  private static let claim = #"(?:(?:this|that|the|your|our|my|a|an) )?(?:prediction|explanation|hypothesis|claim|model)\b|it\b"#
  private static let against = #"falsify|refute|contradict|disprove|rule out|count (?:as evidence )?against|(?:be )?(?:incompatible|inconsistent) with|conflict with|(?:cannot|could not|can't) coexist with|make (?:you|us|me) (?:abandon|drop|reject|give up)"#
  private static let english = #"\b(?:what|which|name|give|identify|describe|specify)\s+(?:(?:a|an|one|the) )?(?:(?:valid |contrary |possible )?(?:observation|result|outcome|finding|evidence|measurement)s? )?(?:that )?(?:(?:would|could|can|might) )?(?:(?:\#(against)) (?:\#(claim))|prove (?:\#(claim)) wrong\b)|\bhow (?:can|could|would) (?:(?:\#(claim)) be (?:falsified|disproved|refuted)\b|(?:I|you|we) (?:falsify|disprove|refute) (?:\#(claim)))|\b(?:is|was) (?:\#(claim)) falsifiable\b"#
  private static func resource(_ key: String) -> String {
    AgentConversationalTeamCommand.text("contrast_" + key, "(?!)", language: LanguagePolicySettings.zhCN)
  }
  private static func matches(_ text: String, _ pattern: String) -> Bool {
    text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
  }
  static func requested(_ objective: String) -> Bool {
    guard (1...8_000).contains(objective.utf16.count), let regex = try? NSRegularExpression(pattern: quotes) else { return false }
    let visible = regex.stringByReplacingMatches(in: objective, range: NSRange(objective.startIndex..., in: objective), withTemplate: " ")
    return visible.components(separatedBy: CharacterSet(charactersIn: ".!?;\n\u{3002}\u{ff01}\u{ff1f}\u{ff1b}")).contains { clause in
      !matches(clause, excluded) && !matches(clause, resource("excluded")) &&
        (matches(clause, english) || matches(clause, resource("request")))
    }
  }
  private static func normalized(_ text: String) -> String {
    text.precomposedStringWithCompatibilityMapping.lowercased()
      .replacingOccurrences(of: #"[\s\p{Z}]+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
  static func render(_ object: AgentMcpJSONObject, text: Text) throws -> String {
    guard Set(object.keys) == fields else { throw AgentTeamDraftAudit.Failure.invalid }
    let placeholders = fields.union(["string", "text", "placeholder", "placeholder text", "todo", "tbd", "n/a", "na", "none",
      "null", "unknown", "unspecified", "not applicable", "not provided", "input variable", "readout variable", "input name",
      "readout name", "alternative explanation", "missing evidence", "x", "y", "foo", "bar"])
      .union(resource("placeholders").components(separatedBy: "|"))
    let unsafe = #"[\p{Cc}\p{Cf}\p{Cs}\p{Zl}\p{Zp}<>{}|`]|://|\]\(|%\d*\x24?[s@]"#
    func field(_ key: String, limit: Int) throws -> String {
      guard let raw = object[key]?.strictStringValue, (1...limit).contains(raw.utf16.count) else { throw AgentTeamDraftAudit.Failure.invalid }
      let clean = normalized(raw)
      guard clean.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }), !placeholders.contains(clean),
        !matches(raw, unsafe), !matches(clean, unsafe), !(clean.hasPrefix("[") && clean.hasSuffix("]")) else { throw AgentTeamDraftAudit.Failure.invalid }
      return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func direction(_ key: String) throws -> Bool {
      switch object[key] {
      case .string("higher"): return true
      case .string("lower"): return false
      default: throw AgentTeamDraftAudit.Failure.invalid
      }
    }
    let input = try field("input", limit: 120), readout = try field("readout", limit: 120)
    guard normalized(input) != normalized(readout) else { throw AgentTeamDraftAudit.Failure.invalid }
    let expected = try direction("expected_direction"), inputUp = try direction("input_direction")
    return String(format: text.format, locale: Locale(identifier: "en_US_POSIX"), arguments: [
      try field("purpose", limit: 400), input, inputUp ? text.higher : text.lower, readout,
      expected ? text.higher : text.lower, expected ? text.lower : text.higher,
      try field("alternative", limit: 400), try field("gap", limit: 400)])
  }
  static func synthesis(_ raw: String, offered: Bool, text: Text) throws -> Draft {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\r\n", with: "\n")
    if offered && (trimmed.hasPrefix("{") || trimmed.hasPrefix("```json\n")) {
      let object = try AgentTeamDraftAudit.object(raw)
      if object["answer"] == nil {
        let answer = try render(object, text: text)
        guard !answer.isBlank, answer.utf16.count <= 8_000 else { throw AgentTeamDraftAudit.Failure.invalid }
        return Draft(answer: answer, claim: object)
      }
      guard Set(object.keys) == ["answer"] else { throw AgentTeamDraftAudit.Failure.invalid }
    }
    return Draft(answer: try AgentConversationalTeamProtocol.synthesis(raw), claim: nil)
  }
}
