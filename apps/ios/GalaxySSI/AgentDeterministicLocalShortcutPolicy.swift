import Foundation

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
    return !requirements.complexReasoning &&
      requirements.executionHorizon == .interactive &&
      !requirements.capabilities.contains(.taskExecution) &&
      intent != .desktopControl &&
      !AgentExplicitMultiAgentIntentPolicy.matches(goal) &&
      !AgentPhoneRuntimePolicy.shouldUsePhoneRuntime(goal: goal) &&
      AgentGoalSegmentationPolicy.split(goal).count == 1
  }
}
