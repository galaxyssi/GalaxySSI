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
    guard let kind = triggerKind(for: parsed.eventClause) else {
      return Result(
        text: "iOS workflow triggers currently support power connected and low battery events.",
        actionId: "workflow_trigger_create"
      )
    }
    do {
      let trigger = try AgentWorkflowTrigger(
        workflowId: workflow.id,
        workflowName: workflow.name,
        kind: kind
      )
      _ = try triggerStore.upsert(trigger)
      return Result(
        text: "Workflow trigger created for \(workflow.name): \(trigger.id) (\(eventName(kind))).",
        actionId: "workflow_trigger_create"
      )
    } catch {
      return Result(
        text: "Unable to create workflow trigger: \(error.localizedDescription)",
        actionId: "workflow_trigger_create"
      )
    }
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

  private static func triggerKind(for clause: String) -> AgentWorkflowTriggerKind? {
    let normalized = clause.lowercased()
    if normalized.range(of: #"\b(charg|charging|charger|plugged|power|connected)\b"#, options: .regularExpression) != nil {
      return .powerConnected
    }
    if normalized.range(of: #"\b(low battery|battery low|battery below|battery under|battery at)\b"#, options: .regularExpression) != nil {
      return .batteryLow
    }
    return nil
  }

  private static func listTriggers(triggerStore: UserDefaultsAgentWorkflowTriggerStore) -> Result {
    let triggers = triggerStore.list()
    guard !triggers.isEmpty else {
      return Result(text: "No workflow triggers configured.", actionId: "workflow_trigger_list")
    }
    let lines = triggers.map { trigger in
      "- \(trigger.id) | \(trigger.workflowName) | \(eventName(trigger.kind)) | \(trigger.enabled ? "enabled" : "disabled")"
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
      text: "Workflow trigger commands: create workflow trigger <workflow> when charging; list workflow triggers; delete workflow trigger <id>.",
      actionId: "workflow_trigger_syntax"
    )
  }

  private static func eventName(_ kind: AgentWorkflowTriggerKind) -> String {
    switch kind {
    case .powerConnected: return "power connected"
    case .batteryLow: return "low battery"
    case .notificationPackage: return "notification package"
    case .notificationText: return "notification text"
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
