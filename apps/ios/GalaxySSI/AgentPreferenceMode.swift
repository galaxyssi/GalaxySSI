import Foundation

enum AgentPreferenceMode: String, Codable, CaseIterable, Identifiable {
  case fewerQuestions = "fewer_questions"
  case cautious = "cautious"
  case automation = "automation"
  case developer = "developer"

  var id: String { rawValue }
  var wireValue: String { rawValue }

  var androidName: String {
    switch self {
    case .fewerQuestions: return "FEWER_QUESTIONS"
    case .cautious: return "CAUTIOUS"
    case .automation: return "AUTOMATION"
    case .developer: return "DEVELOPER"
    }
  }

  var titleKey: String {
    switch self {
    case .fewerQuestions: return "agent_preference_fewer_questions"
    case .cautious: return "agent_preference_cautious"
    case .automation: return "agent_preference_automation"
    case .developer: return "agent_preference_developer"
    }
  }

  var titleFallback: String {
    switch self {
    case .fewerQuestions: return "Fewer Questions"
    case .cautious: return "Cautious"
    case .automation: return "Automation"
    case .developer: return "Developer"
    }
  }

  var detailKey: String {
    switch self {
    case .fewerQuestions: return "agent_preference_fewer_questions_subtitle"
    case .cautious: return "agent_preference_cautious_subtitle"
    case .automation: return "agent_preference_automation_subtitle"
    case .developer: return "agent_preference_developer_subtitle"
    }
  }

  var detailFallback: String {
    switch self {
    case .fewerQuestions:
      return "Act with fewer clarifying questions while still confirming executable actions."
    case .cautious:
      return "Ask before actions and keep high-risk protection enabled."
    case .automation:
      return "Run low-risk work directly and keep sensitive actions behind confirmation."
    case .developer:
      return "Prefer structured detail and low-risk automation for technical workflows."
    }
  }

  static func fromWireValue(_ value: String?) -> AgentPreferenceMode {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "-", with: "_") ?? ""
    return allCases.first {
      $0.wireValue == normalized || $0.androidName.lowercased() == normalized
    } ?? .cautious
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(wireValue)
  }
}

struct AgentPreferenceProfile: Codable, Equatable {
  var permissionMode: AgentPermissionMode
  var taskExecutionMode: AgentTaskExecutionMode
  var highRiskGuard: Bool
  var minimizeClarifications: Bool
  var expandStructuredDetails: Bool

  init(
    permissionMode: AgentPermissionMode,
    taskExecutionMode: AgentTaskExecutionMode,
    highRiskGuard: Bool = true,
    minimizeClarifications: Bool = false,
    expandStructuredDetails: Bool = false
  ) {
    self.permissionMode = permissionMode
    self.taskExecutionMode = taskExecutionMode
    self.highRiskGuard = highRiskGuard
    self.minimizeClarifications = minimizeClarifications
    self.expandStructuredDetails = expandStructuredDetails
  }
}

enum AgentPreferenceModePolicy {
  static func profile(_ mode: AgentPreferenceMode) -> AgentPreferenceProfile {
    switch mode {
    case .fewerQuestions:
      return AgentPreferenceProfile(
        permissionMode: .askBeforeAction,
        taskExecutionMode: .autoComplete,
        minimizeClarifications: true
      )
    case .cautious:
      return AgentPreferenceProfile(
        permissionMode: .askBeforeAction,
        taskExecutionMode: .autoComplete
      )
    case .automation:
      return AgentPreferenceProfile(
        permissionMode: .autoLowRisk,
        taskExecutionMode: .autoComplete,
        minimizeClarifications: true
      )
    case .developer:
      return AgentPreferenceProfile(
        permissionMode: .autoLowRisk,
        taskExecutionMode: .autoComplete,
        expandStructuredDetails: true
      )
    }
  }

  static func resolveClarification(
    mode: AgentPreferenceMode,
    goal: String,
    baseline: AgentClarificationDecision
  ) -> AgentClarificationDecision {
    let preferenceProfile = profile(mode)
    if preferenceProfile.minimizeClarifications &&
      !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      baseline.mode == .askLocally {
      return AgentClarificationDecision(mode: .execute)
    }
    return baseline
  }
}

final class AgentPreferenceModeStore {
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> AgentPreferenceMode {
    AgentPreferenceMode.fromWireValue(defaults.string(forKey: Self.modeKey))
  }

  func save(_ mode: AgentPreferenceMode) {
    defaults.set(mode.wireValue, forKey: Self.modeKey)
  }

  private let defaults: UserDefaults
  private static let modeKey = "galaxyssi_agent_preference.mode"
}
