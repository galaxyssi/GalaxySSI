import Foundation

enum AgentBenchmarkTrialClassification: String, Codable, CaseIterable {
  case passed
  case capabilityFailure = "capability_failure"
  case infrastructureFailure = "infrastructure_failure"
  case waitingForRealCondition = "waiting_for_real_condition"
}

enum AgentBenchmarkTrialClassificationPolicy {
  static func classify(_ result: AgentBenchmarkTrialResult) -> AgentBenchmarkTrialClassification {
    classify(passed: result.passed, failureReasons: result.failureReasons)
  }

  static func classify(
    passed: Bool,
    failureReasons: [String]
  ) -> AgentBenchmarkTrialClassification {
    if passed { return .passed }
    let reasons = failureReasons.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    if reasons.contains(where: waitingReasons.contains) { return .waitingForRealCondition }
    if reasons.contains(where: { reason in infrastructurePrefixes.contains(where: reason.hasPrefix) }) {
      return .infrastructureFailure
    }
    return .capabilityFailure
  }

  private static let waitingReasons: Set<String> = [
    "condition_not_observed",
    "memory_horizon_not_verified",
    "recovery_not_verified"
  ]

  private static let infrastructurePrefixes: Set<String> = [
    "run_status:",
    "run_failure:",
    "tool_infrastructure:",
    "duration_budget_exceeded",
    "cost_budget_exceeded"
  ]
}
