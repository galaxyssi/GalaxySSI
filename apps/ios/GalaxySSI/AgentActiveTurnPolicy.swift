import Foundation

enum AgentActiveTurnDisposition: String, Codable, CaseIterable, Identifiable {
  case independent = "INDEPENDENT"
  case steer = "STEER"
  case interrupt = "INTERRUPT"

  var id: String { rawValue }
}

enum AgentActiveTurnInterventionKind: String, Codable, CaseIterable, Identifiable {
  case none = "NONE"
  case constraint = "CONSTRAINT"
  case goalChange = "GOAL_CHANGE"
  case interrupt = "INTERRUPT"

  var id: String { rawValue }
}

struct AgentActiveTurnDecision: Codable, Equatable {
  var disposition: AgentActiveTurnDisposition
  var interventionKind: AgentActiveTurnInterventionKind

  init(
    disposition: AgentActiveTurnDisposition,
    interventionKind: AgentActiveTurnInterventionKind = .none
  ) {
    self.disposition = disposition
    self.interventionKind = interventionKind
  }

  var intervenes: Bool {
    disposition != .independent
  }
}

enum AgentActiveTurnPolicy {
  static func decide(
    request: String,
    activeGoal: String,
    hasNewAttachments: Bool = false
  ) -> AgentActiveTurnDecision {
    let clean = normalize(request)
    guard !clean.isEmpty, !activeGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return independent
    }
    if interruptCommands.contains(clean) {
      return AgentActiveTurnDecision(disposition: .interrupt, interventionKind: .interrupt)
    }
    if independentPrefixes.contains(where: clean.hasPrefix) {
      return independent
    }
    if standaloneRequests.contains(where: { regexMatches(pattern: $0, in: clean).first != nil }) {
      return independent
    }
    if continuationPrefixes.contains(where: clean.hasPrefix) {
      return steerDecision(clean)
    }
    if !hasNewAttachments && continuationReferences.contains(where: clean.contains) {
      return steerDecision(clean)
    }
    if !hasNewAttachments &&
      looksLikeFragment(clean) &&
      !distinctiveTokens(clean).intersection(distinctiveTokens(normalize(activeGoal))).isEmpty {
      return steerDecision(clean)
    }
    return independent
  }

  static func supersedingGoal(
    activeGoal: String,
    intervention: String,
    kind: AgentActiveTurnInterventionKind
  ) -> String {
    let original = String(activeGoal.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16_000))
    let latest = String(intervention.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8_000))
    let label = kind == .goalChange
      ? "The user changed the goal of an in-progress task."
      : "The user added a constraint to an in-progress task."
    return """
    \(label)
    Continue as one task. The latest instruction has priority wherever it conflicts with the original request.

    Original request:
    \(original)

    Latest instruction:
    \(latest)
    """
  }

  private static func steerDecision(_ clean: String) -> AgentActiveTurnDecision {
    AgentActiveTurnDecision(
      disposition: .steer,
      interventionKind: goalChangePrefixes.contains(where: clean.hasPrefix) ? .goalChange : .constraint
    )
  }

  private static func normalize(_ value: String) -> String {
    let punctuationScalars: Set<UnicodeScalar> = [
      "\u{3002}", "\u{ff0c}", "\u{ff01}", "\u{ff1f}", "\u{ff1a}",
      "\u{ff1b}", "\u{201c}", "\u{201d}", "\u{2018}", "\u{2019}"
    ]
    let mapped = value.lowercased().unicodeScalars.map { scalar -> String in
      if CharacterSet.punctuationCharacters.contains(scalar) || punctuationScalars.contains(scalar) {
        return " "
      }
      return String(scalar)
    }.joined()
    return mapped
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func looksLikeFragment(_ value: String) -> Bool {
    if value.count > 100 { return false }
    if regexMatches(pattern: #"[a-z0-9_+-]+"#, in: value).count > 12 { return false }
    return !standaloneLeads.contains(where: value.hasPrefix)
  }

  private static func distinctiveTokens(_ value: String) -> Set<String> {
    var result = Set(
      regexMatches(pattern: #"[a-z0-9][a-z0-9_+.-]{2,}"#, in: value)
        .filter { !commonWords.contains($0) }
    )
    for sequence in cjkSequences(in: value) {
      guard sequence.count >= 2 else { continue }
      let characters = Array(sequence)
      for index in 0..<(characters.count - 1) {
        result.insert(String(characters[index...index + 1]))
      }
    }
    return result
  }

  private static func regexMatches(pattern: String, in value: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return regex.matches(in: value, range: range).compactMap { match in
      Range(match.range, in: value).map { String(value[$0]) }
    }
  }

  private static func cjkSequences(in value: String) -> [String] {
    var sequences: [String] = []
    var current = ""
    for scalar in value.unicodeScalars {
      if scalar.value >= 0x4e00 && scalar.value <= 0x9fff {
        current.append(Character(scalar))
      } else if !current.isEmpty {
        sequences.append(current)
        current = ""
      }
    }
    if !current.isEmpty {
      sequences.append(current)
    }
    return sequences
  }

  private static let independent = AgentActiveTurnDecision(disposition: .independent)
  private static let commonWords: Set<String> = ["the", "and", "for", "with", "this", "that", "please"]
  private static let interruptCommands: Set<String> = [
    "stop", "stop task", "stop this task", "stop the task", "stop current task",
    "stop the current task", "cancel", "cancel task", "cancel this task",
    "cancel the task", "cancel current task", "cancel the current task",
    "abort", "abort task", "interrupt", "interrupt task", "stop working", "stop running",
    "\u{505c}\u{6b62}", "\u{53d6}\u{6d88}", "\u{4e2d}\u{65ad}",
    "\u{505c}\u{6b62}\u{4efb}\u{52a1}", "\u{53d6}\u{6d88}\u{4efb}\u{52a1}",
    "\u{4e2d}\u{65ad}\u{4efb}\u{52a1}", "\u{505c}\u{6b62}\u{5f53}\u{524d}\u{4efb}\u{52a1}",
    "\u{53d6}\u{6d88}\u{5f53}\u{524d}\u{4efb}\u{52a1}", "\u{4e2d}\u{65ad}\u{5f53}\u{524d}\u{4efb}\u{52a1}",
    "\u{5148}\u{505c}\u{4e0b}", "\u{505c}\u{4e0b}\u{6765}",
    "\u{522b}\u{505a}\u{4e86}", "\u{4e0d}\u{7528}\u{7ee7}\u{7eed}\u{4e86}",
    "\u{4e0d}\u{8981}\u{7ee7}\u{7eed}\u{4e86}"
  ]
  private static let independentPrefixes = [
    "new task", "start a new task", "separate task", "another task", "independent task",
    "\u{65b0}\u{4efb}\u{52a1}", "\u{65b0}\u{7684}\u{4efb}\u{52a1}",
    "\u{53e6}\u{4e00}\u{4e2a}\u{4efb}\u{52a1}", "\u{53e6}\u{5916}\u{4e00}\u{4e2a}\u{4efb}\u{52a1}",
    "\u{5355}\u{72ec}\u{4efb}\u{52a1}", "\u{72ec}\u{7acb}\u{4efb}\u{52a1}"
  ]
  private static let standaloneRequests = [
    #"^(reply|respond) exactly\b.*"#,
    #"^(hello|hi|hey)$"#
  ]
  private static let goalChangePrefixes = [
    "change the goal", "change goal", "switch the goal", "replace the task",
    "do this instead", "instead ", "not that", "\u{6539}\u{76ee}\u{6807}",
    "\u{66f4}\u{6362}\u{76ee}\u{6807}", "\u{6362}\u{4e2a}\u{76ee}\u{6807}",
    "\u{6539}\u{6210}", "\u{6539}\u{4e3a}", "\u{6539}\u{505a}",
    "\u{522b}\u{505a}", "\u{4e0d}\u{662f}"
  ]
  private static let continuationPrefixes = [
    "continue", "keep going", "go on", "also", "add ", "additionally",
    "change ", "correct ", "correction", "make sure", "ensure ", "use the previous",
    "use this", "use that", "with that", "based on that", "instead", "remove ",
    "keep ", "retry", "redo", "not that", "do not ", "no ", "wait",
    "\u{7ee7}\u{7eed}", "\u{63a5}\u{7740}", "\u{518d}", "\u{91cd}\u{65b0}",
    "\u{91cd}\u{8bd5}", "\u{66f4}\u{6b63}", "\u{7ea0}\u{6b63}",
    "\u{4fee}\u{6539}", "\u{6539}\u{6210}", "\u{6539}\u{4e3a}",
    "\u{6539}\u{4e00}\u{4e0b}", "\u{8865}\u{5145}", "\u{8ffd}\u{52a0}",
    "\u{53e6}\u{5916}", "\u{8fd8}\u{6709}", "\u{786e}\u{4fdd}",
    "\u{4fdd}\u{8bc1}", "\u{8981}\u{786e}\u{4fdd}", "\u{8981}\u{4fdd}\u{8bc1}",
    "\u{8bf7}\u{786e}\u{4fdd}", "\u{4e0d}\u{8981}", "\u{53bb}\u{6389}",
    "\u{5220}\u{6389}", "\u{4fdd}\u{7559}", "\u{6062}\u{590d}",
    "\u{7528}\u{521a}\u{624d}", "\u{6309}\u{521a}\u{624d}", "\u{6839}\u{636e}\u{521a}\u{624d}",
    "\u{4e0a}\u{9762}", "\u{524d}\u{9762}", "\u{8fd9}\u{4e2a}",
    "\u{8fd9}\u{5f20}", "\u{90a3}\u{4e2a}", "\u{628a}\u{5b83}",
    "\u{4e0d}\u{5bf9}", "\u{4e0d}\u{662f}"
  ]
  private static let continuationReferences = [
    "previous", "above", "earlier", "that", "this", "same", "again",
    "\u{521a}\u{624d}", "\u{4e0a}\u{4e00}\u{4e2a}", "\u{4e0a}\u{4e00}\u{6761}",
    "\u{4e0a}\u{9762}", "\u{524d}\u{9762}", "\u{539f}\u{6765}",
    "\u{8fd9}\u{4e2a}", "\u{8fd9}\u{5f20}", "\u{90a3}\u{4e2a}",
    "\u{5b83}", "\u{540c}\u{4e00}\u{4e2a}", "\u{4e00}\u{6837}"
  ]
  private static let standaloneLeads = [
    "write", "create", "build", "generate", "search", "find", "check", "tell",
    "explain", "summarize", "translate", "open", "run", "set",
    "\u{5199}", "\u{521b}\u{5efa}", "\u{751f}\u{6210}", "\u{67e5}",
    "\u{641c}\u{7d22}", "\u{6253}\u{5f00}", "\u{8fd0}\u{884c}",
    "\u{8bbe}\u{7f6e}", "\u{89e3}\u{91ca}", "\u{603b}\u{7ed3}",
    "\u{7ffb}\u{8bd1}"
  ]
}
