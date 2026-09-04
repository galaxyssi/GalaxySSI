import Foundation

@MainActor
enum AgentWorkflowTriggerCommandRouter {
  struct Result {
    let text: String
    let actionId: String
  }

  private static let listCommands: Set<String> = [
    "triggers",
    "list triggers",
    "show triggers",
    "workflow triggers",
    "list workflow triggers",
    "show workflow triggers"
  ]

  static func handle(
    _ input: String,
    triggerStore: UserDefaultsAgentWorkflowTriggerStore = .shared,
    workflowStore: AgentWorkflowStore = UserDefaultsAgentWorkflowStore.shared
  ) -> Result? {
    let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = command.lowercased()
    guard !command.isEmpty else { return nil }

    if listCommands.contains(normalized) {
      return listTriggers(triggerStore: triggerStore)
    }
    if let request = parseCondition(command) {
      return addCondition(
        request.condition,
        triggerID: request.triggerID,
        triggerStore: triggerStore
      )
    }
    if let triggerID = parseClearConditions(command) {
      return clearConditions(triggerID, triggerStore: triggerStore)
    }
    if let triggerId = capture(
      #"^(?:delete|remove)\s+(?:workflow\s+)?trigger\s+(\S+)$"#,
      in: command
    ) {
      return deleteTrigger(triggerId, triggerStore: triggerStore)
    }
    if isManagementCommand(normalized) {
      return syntax()
    }
    guard let parsed = parseCreate(command) else { return nil }
    guard let workflow = workflowStore.find(parsed.workflowReference) else {
      return Result(
        text: "Workflow not found: \(parsed.workflowReference). Create the workflow first.",
        actionId: "workflow_trigger_create"
      )
    }
    guard let spec = triggerSpec(for: parsed.eventClause) else {
      return Result(
        text: "iOS workflow triggers support charging, low battery, notification package, and notification text events.",
        actionId: "workflow_trigger_create"
      )
    }
    do {
      let trigger = try AgentWorkflowTrigger(
        workflowId: workflow.id,
        workflowName: workflow.name,
        kind: spec.kind,
        condition: spec.condition
      )
      _ = try triggerStore.upsert(trigger)
      return Result(
        text: "Workflow trigger created for \(workflow.name): \(trigger.id) (\(eventName(spec.kind, condition: spec.condition))).",
        actionId: "workflow_trigger_create"
      )
    } catch {
      return Result(
        text: "Unable to create workflow trigger: \(error.localizedDescription)",
        actionId: "workflow_trigger_create"
      )
    }
  }

  private struct ConditionRequest {
    let triggerID: String
    let condition: AgentWorkflowCondition
  }

  private static func parseCondition(_ command: String) -> ConditionRequest? {
    let patterns = [
      #"^(?:add|attach)\s+(?:workflow\s+)?trigger\s+condition\s+(\S+)\s*(?:::|when|if)\s*(.+)$"#,
      #"^(?:add|attach)\s+condition\s+to\s+(?:workflow\s+)?trigger\s+(\S+)\s*(?:::|when|if)\s*(.+)$"#
    ]
    for pattern in patterns {
      guard let values = captures(pattern, in: command), values.count == 2 else { continue }
      let triggerID = values[0].trimmingCharacters(in: .whitespacesAndNewlines)
      guard !triggerID.isEmpty, let condition = parseConditionValue(values[1]) else { continue }
      return ConditionRequest(triggerID: triggerID, condition: condition)
    }
    return nil
  }

  private static func parseConditionValue(_ value: String) -> AgentWorkflowCondition? {
    let normalized = value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    switch normalized {
    case "charging", "device charging", "is charging", "charging required":
      return .deviceCharging(required: true)
    case "not charging", "device not charging", "is not charging":
      return .deviceCharging(required: false)
    case "network available", "network availability", "online", "connected":
      return .networkAvailable(required: true)
    case "network unavailable", "offline", "no network", "disconnected":
      return .networkAvailable(required: false)
    default:
      break
    }

    let batteryPattern = #"^battery(?:\s+threshold)?\s+(below|under|at most|at least|above|over|<=|>=|<|>)\s*(\d{1,3})%?$"#
    if let values = captures(batteryPattern, in: normalized),
       values.count == 2,
       let percent = Int(values[1]),
       (0...100).contains(percent) {
      let comparison: AgentWorkflowBatteryComparison
      switch values[0] {
      case "below", "under", "<":
        comparison = .below
      case "at most", "<=":
        comparison = .atMost
      case "at least", ">=":
        comparison = .atLeast
      case "above", "over", ">":
        comparison = .above
      default:
        return nil
      }
      return .batteryThreshold(percent: percent, comparison: comparison)
    }

    let timePattern = #"^(?:time(?:\s+window)?|between)\s+(\d{1,2}):(\d{2})\s*(?:-|to|and)\s*(\d{1,2}):(\d{2})$"#
    if let values = captures(timePattern, in: normalized),
       values.count == 4,
       let start = minuteOfDay(hour: values[0], minute: values[1]),
       let end = minuteOfDay(hour: values[2], minute: values[3]) {
      return .timeWindow(startMinuteOfDay: start, endMinuteOfDay: end)
    }
    return nil
  }

  private static func minuteOfDay(hour: String, minute: String) -> Int? {
    guard let hour = Int(hour), (0...23).contains(hour),
          let minute = Int(minute), (0...59).contains(minute) else {
      return nil
    }
    return hour * 60 + minute
  }

  private static func parseClearConditions(_ command: String) -> String? {
    let patterns = [
      #"^(?:clear|remove)\s+(?:workflow\s+)?trigger\s+conditions\s+(\S+)$"#,
      #"^(?:clear|remove)\s+(?:all\s+)?conditions\s+from\s+(?:workflow\s+)?trigger\s+(\S+)$"#
    ]
    for pattern in patterns {
      if let triggerID = capture(pattern, in: command)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
         !triggerID.isEmpty {
        return triggerID
      }
    }
    return nil
  }

  private static func addCondition(
    _ condition: AgentWorkflowCondition,
    triggerID: String,
    triggerStore: UserDefaultsAgentWorkflowTriggerStore
  ) -> Result {
    guard let trigger = triggerStore.findById(triggerID) else {
      return Result(
        text: "Workflow trigger not found: \(triggerID)",
        actionId: "workflow_trigger_condition_add"
      )
    }
    guard !trigger.conditions.contains(condition) else {
      return Result(
        text: "Workflow trigger condition already exists: \(conditionLabel(condition))",
        actionId: "workflow_trigger_condition_add"
      )
    }
    do {
      let updated = try AgentWorkflowTrigger(
        id: trigger.id,
        workflowId: trigger.workflowId,
        workflowName: trigger.workflowName,
        kind: trigger.kind,
        condition: trigger.condition,
        enabled: trigger.enabled,
        cooldownMinutes: trigger.cooldownMinutes,
        lastTriggeredAtMillis: trigger.lastTriggeredAtMillis,
        createdAtMillis: trigger.createdAtMillis,
        conditions: trigger.conditions + [condition]
      )
      _ = try triggerStore.upsert(updated)
      return Result(
        text: "Workflow trigger condition added: \(conditionLabel(condition))",
        actionId: "workflow_trigger_condition_add"
      )
    } catch {
      return Result(
        text: "Unable to add workflow trigger condition: \(error.localizedDescription)",
        actionId: "workflow_trigger_condition_add"
      )
    }
  }

  private static func clearConditions(
    _ triggerID: String,
    triggerStore: UserDefaultsAgentWorkflowTriggerStore
  ) -> Result {
    guard let trigger = triggerStore.findById(triggerID) else {
      return Result(
        text: "Workflow trigger not found: \(triggerID)",
        actionId: "workflow_trigger_condition_clear"
      )
    }
    guard !trigger.conditions.isEmpty else {
      return Result(
        text: "Workflow trigger has no additional conditions: \(triggerID)",
        actionId: "workflow_trigger_condition_clear"
      )
    }
    do {
      let updated = try AgentWorkflowTrigger(
        id: trigger.id,
        workflowId: trigger.workflowId,
        workflowName: trigger.workflowName,
        kind: trigger.kind,
        condition: trigger.condition,
        enabled: trigger.enabled,
        cooldownMinutes: trigger.cooldownMinutes,
        lastTriggeredAtMillis: trigger.lastTriggeredAtMillis,
        createdAtMillis: trigger.createdAtMillis,
        conditions: []
      )
      _ = try triggerStore.upsert(updated)
      return Result(
        text: "Workflow trigger conditions cleared: \(triggerID)",
        actionId: "workflow_trigger_condition_clear"
      )
    } catch {
      return Result(
        text: "Unable to clear workflow trigger conditions: \(error.localizedDescription)",
        actionId: "workflow_trigger_condition_clear"
      )
    }
  }

  private static func conditionLabel(_ condition: AgentWorkflowCondition) -> String {
    switch condition {
    case .deviceCharging(let required):
      return required ? "charging" : "not charging"
    case .networkAvailable(let required):
      return required ? "network available" : "network unavailable"
    case .batteryThreshold(let percent, let comparison):
      let operatorLabel: String
      switch comparison {
      case .below: operatorLabel = "<"
      case .atMost: operatorLabel = "<="
      case .atLeast: operatorLabel = ">="
      case .above: operatorLabel = ">"
      }
      return "battery \(operatorLabel) \(percent)%"
    case .timeWindow(let start, let end):
      return "time \(clockLabel(start))-\(clockLabel(end))"
    case .text(let expected, _, _):
      return "text contains \(expected)"
    case .packageName(let expected, _, _):
      return "package \(expected)"
    }
  }

  private static func clockLabel(_ minute: Int) -> String {
    String(format: "%02d:%02d", minute / 60, minute % 60)
  }

  private struct CreateCommand {
    let workflowReference: String
    let eventClause: String
  }

  private static func parseCreate(_ command: String) -> CreateCommand? {
    let patterns = [
      #"^(?:create|add)\s+(?:workflow\s+)?trigger\s+(?:for\s+)?(.+?)\s+(?:when|on)\s+(.+)$"#,
      #"^trigger\s+workflow\s+(.+?)\s+(?:when|on)\s+(.+)$"#,
      #"^(?:create|add)\s+(?:workflow\s+)?trigger\s*::\s*(.+?)\s*::\s*(.+)$"#
    ]
    for pattern in patterns {
      if let captures = captures(pattern, in: command), captures.count == 2 {
        let workflowReference = captures[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let eventClause = captures[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workflowReference.isEmpty, !eventClause.isEmpty else { continue }
        return CreateCommand(workflowReference: workflowReference, eventClause: eventClause)
      }
    }
    return nil
  }

  private static func triggerSpec(for clause: String) -> (kind: AgentWorkflowTriggerKind, condition: String)? {
    let packagePattern = #"^notification\s+(?:from\s+)?package(?:\s+(?:contains|matches))?(?:\s*::\s*|\s+)(.+)$"#
    if let condition = capture(packagePattern, in: clause)?.trimmingCharacters(in: .whitespacesAndNewlines),
       !condition.isEmpty {
      return (.notificationPackage, condition)
    }
    let textPattern = #"^notification\s+text(?:\s+(?:contains|matches))?(?:\s*::\s*|\s+)(.+)$"#
    if let condition = capture(textPattern, in: clause)?.trimmingCharacters(in: .whitespacesAndNewlines),
       !condition.isEmpty {
      return (.notificationText, condition)
    }
    let normalized = clause.lowercased()
    if normalized.range(of: #"\b(charg|charging|charger|plugged|power|connected)\b"#, options: .regularExpression) != nil {
      return (.powerConnected, "")
    }
    if normalized.range(of: #"\b(low battery|battery low|battery below|battery under|battery at)\b"#, options: .regularExpression) != nil {
      return (.batteryLow, "")
    }
    return nil
  }

  private static func listTriggers(triggerStore: UserDefaultsAgentWorkflowTriggerStore) -> Result {
    let triggers = triggerStore.list()
    guard !triggers.isEmpty else {
      return Result(text: "No workflow triggers configured.", actionId: "workflow_trigger_list")
    }
    let lines = triggers.map { trigger in
      "- \(trigger.id) | \(trigger.workflowName) | \(eventName(trigger.kind, condition: trigger.condition)) | \(trigger.enabled ? "enabled" : "disabled")"
    }
    return Result(
      text: "Workflow triggers:\n\(lines.joined(separator: "\n"))",
      actionId: "workflow_trigger_list"
    )
  }

  private static func deleteTrigger(
    _ triggerId: String,
    triggerStore: UserDefaultsAgentWorkflowTriggerStore
  ) -> Result {
    guard triggerStore.delete(id: triggerId) else {
      return Result(text: "Workflow trigger not found: \(triggerId)", actionId: "workflow_trigger_delete")
    }
    return Result(text: "Workflow trigger deleted: \(triggerId)", actionId: "workflow_trigger_delete")
  }

  private static func isManagementCommand(_ normalized: String) -> Bool {
    [
      "create workflow trigger",
      "add workflow trigger",
      "create trigger",
      "add trigger",
      "delete workflow trigger",
      "remove workflow trigger",
      "delete trigger",
      "remove trigger",
      "list workflow trigger",
      "show workflow trigger"
    ].contains { normalized == $0 || normalized.hasPrefix($0 + " ") }
  }

  private static func syntax() -> Result {
    Result(
      text: "Workflow trigger commands: create workflow trigger <workflow> when charging; create workflow trigger <workflow> when notification text contains <text>; list workflow triggers; delete workflow trigger <id>.",
      actionId: "workflow_trigger_syntax"
    )
  }

  private static func eventName(_ kind: AgentWorkflowTriggerKind, condition: String = "") -> String {
    switch kind {
    case .powerConnected: return "power connected"
    case .batteryLow: return "low battery"
    case .notificationPackage: return "notification package contains '\(condition)'"
    case .notificationText: return "notification text contains '\(condition)'"
    }
  }

  private static func captures(_ pattern: String, in value: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    guard let match = regex.firstMatch(in: value, options: [], range: range) else { return nil }
    return (1..<match.numberOfRanges).compactMap { index in
      let captureRange = match.range(at: index)
      guard captureRange.location != NSNotFound, let swiftRange = Range(captureRange, in: value) else { return nil }
      return String(value[swiftRange])
    }
  }

  private static func capture(_ pattern: String, in value: String) -> String? {
    captures(pattern, in: value)?.first
  }
}
