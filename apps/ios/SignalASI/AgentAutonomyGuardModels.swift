import Foundation

struct AgentAutonomyDecision: Codable, Equatable {
  var allowed: Bool
  var reason: String
  var completedToolCalls: Int
  var repeatedCalls: Int

  init(
    allowed: Bool,
    reason: String = "",
    completedToolCalls: Int = 0,
    repeatedCalls: Int = 0
  ) {
    self.allowed = allowed
    self.reason = reason
    self.completedToolCalls = max(completedToolCalls, 0)
    self.repeatedCalls = max(repeatedCalls, 0)
  }

  enum CodingKeys: String, CodingKey {
    case allowed
    case reason
    case completedToolCalls = "completed_tool_calls"
    case repeatedCalls = "repeated_calls"
  }
}

enum AgentAutonomyGuard {
  static let maxRepeatedToolCalls = 2

  static func completedToolCalls(plan: AgentPlan) -> Int {
    (plan.actionHistory + plan.actions).filter {
      $0.kind.isBudgetedAutonomyToolCall && terminalToolStatuses.contains($0.status)
    }.count
  }

  static func review(
    plan: AgentPlan,
    action: AgentAction,
    settings: AgentModelPlannerSettings
  ) -> AgentAutonomyDecision {
    let history = plan.actionHistory + plan.actions
    let completedCalls = completedToolCalls(plan: plan)
    if completedCalls >= settings.normalized.maxToolCalls {
      return AgentAutonomyDecision(
        allowed: false,
        reason: "Autonomous tool-call budget reached",
        completedToolCalls: completedCalls
      )
    }

    let signature = autonomySignature(for: action)
    let repeatedCalls = history.filter {
      $0.kind.isLoopSensitiveAutonomyToolCall &&
        terminalToolStatuses.contains($0.status) &&
        autonomySignature(for: $0) == signature
    }.count
    if action.kind.isLoopSensitiveAutonomyToolCall && repeatedCalls >= maxRepeatedToolCalls {
      return AgentAutonomyDecision(
        allowed: false,
        reason: "Repeated autonomous tool-call loop blocked",
        completedToolCalls: completedCalls,
        repeatedCalls: repeatedCalls
      )
    }

    return AgentAutonomyDecision(
      allowed: true,
      completedToolCalls: completedCalls,
      repeatedCalls: repeatedCalls
    )
  }

  private static func autonomySignature(for action: AgentAction) -> String {
    [
      action.kind.rawValue,
      action.parameters["connector_id"] ?? "",
      action.parameters["package"] ?? "",
      action.parameters["url"] ?? "",
      androidStringHash(action.parameters["prompt"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
      action.target
    ].joined(separator: "|")
  }

  private static func androidStringHash(_ value: String) -> String {
    var hash = Int32(0)
    for unit in value.utf16 {
      hash = hash &* 31 &+ Int32(unit)
    }
    return String(hash)
  }

  private static let terminalToolStatuses: Set<AgentActionStatus> = [
    .completed,
    .failed,
    .blocked,
    .rolledBack
  ]
}

private extension AgentActionKind {
  var isBudgetedAutonomyToolCall: Bool {
    ![.readScreen, .draftPlan].contains(self)
  }

  var isLoopSensitiveAutonomyToolCall: Bool {
    [.callConnector, .controlDevice, .openURL, .openApp].contains(self)
  }
}
