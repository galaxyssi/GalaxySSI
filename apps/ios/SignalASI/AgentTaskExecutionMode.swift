import Foundation

enum AgentTaskExecutionMode: String, CaseIterable, Identifiable, Codable {
  case planOnly = "plan_only"
  case autoComplete = "auto_complete"

  var id: String { rawValue }

  var androidName: String {
    switch self {
    case .planOnly: return "PLAN_ONLY"
    case .autoComplete: return "AUTO_COMPLETE"
    }
  }

  var displayTitle: String {
    switch self {
    case .planOnly: return "Plan only"
    case .autoComplete: return "Auto complete"
    }
  }

  var detail: String {
    switch self {
    case .planOnly:
      return "Inspect context and return an actionable plan without changing anything."
    case .autoComplete:
      return "Continue through execution, recovery, verification, and completion."
    }
  }

  static func fromStoredValue(_ value: String?) -> AgentTaskExecutionMode {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let lowered = trimmed.lowercased()
    let uppercased = trimmed.uppercased()
    return allCases.first { $0.rawValue == lowered || $0.androidName == uppercased } ?? .autoComplete
  }

  static func fromWireValue(_ value: String?) -> AgentTaskExecutionMode {
    fromStoredValue(value)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromStoredValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(androidName)
  }
}

struct AgentTaskExecutionModeResolution: Codable, Equatable {
  var mode: AgentTaskExecutionMode
  var explicitlyRequested: Bool
  var matchedSignal: String

  init(
    mode: AgentTaskExecutionMode,
    explicitlyRequested: Bool = false,
    matchedSignal: String = ""
  ) {
    self.mode = mode
    self.explicitlyRequested = explicitlyRequested
    self.matchedSignal = matchedSignal
  }
}

enum AgentTaskExecutionModePolicy {
  static func resolve(
    request: String,
    configuredMode: AgentTaskExecutionMode = .autoComplete
  ) -> AgentTaskExecutionModeResolution {
    let normalized = request
      .lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if let signal = planOnlySignals.first(where: normalized.contains) {
      return AgentTaskExecutionModeResolution(
        mode: .planOnly,
        explicitlyRequested: true,
        matchedSignal: signal
      )
    }
    if let signal = autoCompleteSignals.first(where: normalized.contains) {
      return AgentTaskExecutionModeResolution(
        mode: .autoComplete,
        explicitlyRequested: true,
        matchedSignal: signal
      )
    }
    return AgentTaskExecutionModeResolution(mode: configuredMode)
  }

  private static let planOnlySignals = [
    "\u{5148}\u{7ed9}\u{65b9}\u{6848}",
    "\u{5148}\u{7ed9}\u{6211}\u{65b9}\u{6848}",
    "\u{53ea}\u{7ed9}\u{65b9}\u{6848}",
    "\u{4ec5}\u{7ed9}\u{65b9}\u{6848}",
    "\u{4ec5}\u{63d0}\u{4f9b}\u{65b9}\u{6848}",
    "\u{53ea}\u{5236}\u{5b9a}\u{8ba1}\u{5212}",
    "\u{5148}\u{5236}\u{5b9a}\u{8ba1}\u{5212}",
    "\u{5148}\u{5217}\u{51fa}\u{8ba1}\u{5212}",
    "\u{6682}\u{4e0d}\u{6267}\u{884c}",
    "\u{5148}\u{4e0d}\u{8981}\u{6267}\u{884c}",
    "\u{4e0d}\u{8981}\u{5b9e}\u{9645}\u{6267}\u{884c}",
    "\u{4e0d}\u{8981}\u{6267}\u{884c}\u{4efb}\u{4f55}\u{64cd}\u{4f5c}",
    "\u{4e0d}\u{8981}\u{6267}\u{884c}\u{4efb}\u{4f55}\u{52a8}\u{4f5c}",
    "plan only",
    "proposal only",
    "show me the plan first",
    "give me a plan first",
    "do not execute",
    "don't execute",
    "without executing",
    "without making changes"
  ]

  private static let autoCompleteSignals = [
    "\u{81ea}\u{52a8}\u{6267}\u{884c}\u{5230}\u{5b8c}\u{6210}",
    "\u{76f4}\u{63a5}\u{6267}\u{884c}\u{5230}\u{5b8c}\u{6210}",
    "\u{4e00}\u{76f4}\u{6267}\u{884c}\u{5230}\u{5b8c}\u{6210}",
    "\u{6267}\u{884c}\u{8fd9}\u{4e2a}\u{65b9}\u{6848}",
    "\u{6309}\u{8fd9}\u{4e2a}\u{65b9}\u{6848}\u{6267}\u{884c}",
    "\u{7ee7}\u{7eed}\u{6267}\u{884c}\u{5230}\u{5b8c}\u{6210}",
    "go ahead and execute",
    "execute until complete",
    "carry this through to completion",
    "implement this plan",
    "proceed with the plan"
  ]
}
