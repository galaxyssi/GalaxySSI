import Foundation

@MainActor
enum AgentWorkflowCommandRouter {
  struct Result {
    let text: String
    let actionId: String
  }

  private static let listCommands: Set<String> = [
    "workflows",
    "list workflows",
    "show workflows"
  ]

  private static let historyCommands: Set<String> = [
    "workflow history",
    "workflow execution history",
    "workflow run history",
    "workflow runs",
    "list workflow history",
    "list workflow runs",
    "show workflow history",
    "show workflow runs"
  ]

  static func handle(
    _ input: String,
    workflowStore: AgentWorkflowStore = UserDefaultsAgentWorkflowStore.shared,
    triggerStore: UserDefaultsAgentWorkflowTriggerStore = .shared,
    historyStore: AgentWorkflowExecutionHistoryStore = AgentWorkflowExecutionHistoryStore()
  ) -> Result? {
    let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = command.lowercased()
    guard !command.isEmpty else { return nil }

    if listCommands.contains(normalized) {
      return listWorkflows(workflowStore: workflowStore)
    }
    if historyCommands.contains(normalized) {
      return listHistory(historyStore: historyStore)
    }
    if let request = parseSave(command) {
      return saveWorkflow(request, workflowStore: workflowStore)
    }
    if let name = capture(
      #"^(?:delete|remove)\s+workflow\s+(.+)$"#,
      in: command
    ) {
      return deleteWorkflow(
        name.trimmingCharacters(in: .whitespacesAndNewlines),
        workflowStore: workflowStore,
        triggerStore: triggerStore,
        historyStore: historyStore
      )
    }
    if isManagementCommand(normalized) {
      return syntax()
    }
    return nil
  }

  private struct SaveRequest {
    let name: String
    let goal: String
  }

  private static func parseSave(_ command: String) -> SaveRequest? {
    let pattern = #"^(?:save|create)\s+workflow\s+(.+?)\s*(?:::|=>)\s*(.+)$"#
    guard let values = captures(pattern, in: command), values.count == 2 else { return nil }
    let name = values[0].trimmingCharacters(in: .whitespacesAndNewlines)
    let goal = values[1].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !goal.isEmpty else { return nil }
    return SaveRequest(name: name, goal: goal)
  }

  private static func saveWorkflow(
    _ request: SaveRequest,
    workflowStore: AgentWorkflowStore
  ) -> Result {
    do {
      let workflow = try workflowStore.save(name: request.name, goal: request.goal)
      return Result(
        text: "Saved workflow \(workflow.name)",
        actionId: "workflow_save"
      )
    } catch {
      return Result(
        text: error.localizedDescription,
        actionId: "workflow_save"
      )
    }
  }

  private static func listWorkflows(workflowStore: AgentWorkflowStore) -> Result {
    let workflows = workflowStore.list()
    guard !workflows.isEmpty else {
      return Result(
        text: "No saved workflows. Use: save workflow Name :: goal",
        actionId: "workflow_list"
      )
    }
    let lines = workflows.prefix(20).map { workflow in
      let goal = workflow.goal
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
        .prefix(120)
      return "- \(workflow.name) | runs=\(workflow.runCount) | \(goal)"
    }
    return Result(
      text: "Saved workflows: \(workflows.count)\n\(lines.joined(separator: "\n"))",
      actionId: "workflow_list"
    )
  }

  private static func listHistory(historyStore: AgentWorkflowExecutionHistoryStore) -> Result {
    let records = historyStore.recent(20)
    guard !records.isEmpty else {
      return Result(text: "No workflow execution history", actionId: "workflow_history")
    }
    let lines = records.map { record in
      var line = "- \(record.id) | \(record.workflowName) | \(record.source.rawValue.lowercased()) | \(record.status.rawValue.lowercased()) | started=\(timestamp(record.startedAtMillis))"
      if record.completedAtMillis > 0 {
        line += " | completed=\(timestamp(record.completedAtMillis))"
      }
      if !record.resultSummary.isEmpty {
        line += " | \(compact(record.resultSummary, limit: 160))"
      }
      return line
    }
    return Result(
      text: "Workflow execution history: \(records.count)\n\(lines.joined(separator: "\n"))",
      actionId: "workflow_history"
    )
  }

  private static func deleteWorkflow(
    _ name: String,
    workflowStore: AgentWorkflowStore,
    triggerStore: UserDefaultsAgentWorkflowTriggerStore,
    historyStore: AgentWorkflowExecutionHistoryStore
  ) -> Result {
    guard let workflow = workflowStore.find(name) else {
      return Result(text: "Workflow '\(name)' was not found", actionId: "workflow_delete")
    }
    let deleted = workflowStore.delete(name: name)
    guard deleted > 0 else {
      return Result(text: "Workflow '\(name)' was not found", actionId: "workflow_delete")
    }
    let deletedTriggers = triggerStore.deleteForWorkflow(workflow.id)
    let deletedHistory = historyStore.deleteForWorkflow(workflow.id)
    return Result(
      text: "Deleted workflow \(workflow.name); removed triggers=\(deletedTriggers); removed history=\(deletedHistory)",
      actionId: "workflow_delete"
    )
  }

  private static func isManagementCommand(_ normalized: String) -> Bool {
    [
      "save workflow",
      "create workflow",
      "delete workflow",
      "remove workflow"
    ].contains { normalized == $0 || normalized.hasPrefix($0 + " ") }
  }

  private static func syntax() -> Result {
    Result(
      text: "Workflow commands: save workflow Name :: goal; list workflows; delete workflow Name; workflow history.",
      actionId: "workflow_syntax"
    )
  }

  private static func compact(_ value: String, limit: Int) -> String {
    String(value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(limit))
  }

  private static func timestamp(_ millis: Int64) -> String {
    ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(millis) / 1_000))
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
