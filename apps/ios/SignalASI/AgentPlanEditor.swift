import Foundation

struct AgentPlanEditResult: Equatable {
  var plan: AgentPlan?
  var error: String

  var success: Bool {
    plan != nil && error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  init(plan: AgentPlan? = nil, error: String = "") {
    self.plan = plan
    self.error = error
  }
}

enum AgentPlanEditor {
  static func inputKey(action: AgentAction) -> String? {
    switch action.kind {
    case .callConnector, .controlDevice:
      return "prompt"
    case .typeText, .createNotification:
      return "text"
    case .setAlarm:
      return "message"
    default:
      return nil
    }
  }

  static func inputValue(action: AgentAction) -> String {
    guard let key = inputKey(action: action) else {
      return ""
    }
    return action.parameters[key] ?? ""
  }

  static func updatePendingAction(
    plan: AgentPlan,
    actionId: String,
    description: String,
    input: String
  ) -> AgentPlanEditResult {
    guard let action = plan.actions.first(where: { $0.id == actionId }) else {
      return failure("Action is no longer in the active plan")
    }
    guard isEditablePending(action) else {
      return failure("Only pending actions can be edited")
    }
    let cleanDescription = description.trimmed().clamped(to: maxDescriptionCharacters)
    guard !cleanDescription.isEmpty else {
      return failure("Action description cannot be empty")
    }
    let key = inputKey(action: action)
    let cleanInput = input.trimmed().clamped(to: maxInputCharacters(action.kind))
    if key != nil && cleanInput.isEmpty {
      return failure("Action input cannot be empty")
    }
    var updatedAction = action
    updatedAction.description = cleanDescription
    if let key {
      updatedAction.parameters[key] = cleanInput
    }
    return validateEditedPlan(
      original: plan,
      actions: plan.actions.map { $0.id == actionId ? updatedAction : $0 },
      editSummary: "updated:\(actionId)"
    )
  }

  static func removePendingAction(plan: AgentPlan, actionId: String) -> AgentPlanEditResult {
    guard let action = plan.actions.first(where: { $0.id == actionId }) else {
      return failure("Action is no longer in the active plan")
    }
    guard isEditablePending(action) else {
      return failure("Only pending actions can be removed")
    }
    guard plan.actions.count > 1 else {
      return failure("A plan must contain at least one action")
    }
    if let dependent = plan.actions.first(where: { dependencyIds($0).contains(actionId) }) {
      return failure("Remove dependent action \(dependent.description) first")
    }
    return validateEditedPlan(
      original: plan,
      actions: plan.actions.filter { $0.id != actionId },
      editSummary: "removed:\(actionId)"
    )
  }

  static func movePendingAction(plan: AgentPlan, actionId: String, offset: Int) -> AgentPlanEditResult {
    guard [-1, 1].contains(offset) else {
      return failure("Unsupported move")
    }
    guard let currentIndex = plan.actions.firstIndex(where: { $0.id == actionId }) else {
      return failure("Action is no longer in the active plan")
    }
    let action = plan.actions[currentIndex]
    guard isEditablePending(action) else {
      return failure("Only pending actions can be moved")
    }
    let targetIndex = currentIndex + offset
    guard plan.actions.indices.contains(targetIndex) else {
      return failure("Action is already at the plan boundary")
    }
    guard isEditablePending(plan.actions[targetIndex]) else {
      return failure("Completed or running actions cannot be reordered")
    }
    var reordered = plan.actions
    let moved = reordered.remove(at: currentIndex)
    reordered.insert(moved, at: targetIndex)
    return validateEditedPlan(
      original: plan,
      actions: reordered,
      editSummary: "moved:\(actionId):\(offset)"
    )
  }

  private static func validateEditedPlan(
    original: AgentPlan,
    actions: [AgentAction],
    editSummary: String
  ) -> AgentPlanEditResult {
    var candidate = original
    candidate.actions = actions
    candidate.revision = original.revision + 1
    candidate.routeRationale = original.routeRationale.components(separatedBy: " User edit:").first.orEmpty +
      " User edit: \(editSummary)."
    candidate.validation = AgentPlanValidator.validate(candidate)
    if candidate.validation.valid {
      return AgentPlanEditResult(plan: candidate)
    }
    return failure(candidate.validation.issues.joined(separator: ", ").clamped(to: 300))
  }

  private static func isEditablePending(_ action: AgentAction) -> Bool {
    [.proposed, .pendingConfirmation].contains(action.status)
  }

  private static func dependencyIds(_ action: AgentAction) -> Set<String> {
    Set(listParameter("depends_on", action: action))
  }

  private static func listParameter(_ key: String, action: AgentAction) -> [String] {
    (action.parameters[key] ?? "")
      .split(separator: ",")
      .map { String($0).trimmed() }
      .filter { !$0.isEmpty }
  }

  private static func maxInputCharacters(_ kind: AgentActionKind) -> Int {
    switch kind {
    case .typeText:
      return 2_000
    case .createNotification:
      return 1_000
    case .setAlarm:
      return 200
    default:
      return 4_000
    }
  }

  private static func failure(_ message: String) -> AgentPlanEditResult {
    AgentPlanEditResult(error: message)
  }

  private static let maxDescriptionCharacters = 300
}

private extension Optional where Wrapped == String {
  var orEmpty: String {
    self ?? ""
  }
}

private extension String {
  func trimmed() -> String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func clamped(to limit: Int) -> String {
    String(prefix(max(limit, 0)))
  }
}
