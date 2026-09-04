import Foundation

@MainActor
enum AgentWorkflowTemplateCommandRouter {
  struct Result {
    let text: String
    let actionId: String
    let templateToRun: AgentWorkflowTemplate?
  }

  static func handle(_ input: String) -> Result? {
    let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = command.lowercased()
    guard !command.isEmpty else { return nil }

    if ["workflow templates", "list templates", "show templates"].contains(normalized) {
      let templates = AgentWorkflowTemplates.all
      let lines = templates.map { "\($0.name) | \($0.goal)" }
      return Result(
        text: "Workflow templates: \(templates.count)\n\(lines.joined(separator: "\n"))",
        actionId: "workflow_template_list",
        templateToRun: nil
      )
    }
    if let name = prefixedValue(command, prefixes: ["run template ", "start template "]) {
      guard let template = AgentWorkflowTemplates.find(name) else {
        return Result(
          text: "Template '\(name)' was not found",
          actionId: "workflow_template_run",
          templateToRun: nil
        )
      }
      return Result(
        text: "Starting template \(template.name)",
        actionId: "workflow_template_run",
        templateToRun: template
      )
    }
    if ["run template", "start template", "workflow template", "workflow templates"].contains(where: {
      normalized == $0 || normalized.hasPrefix($0 + " ")
    }) {
      return Result(
        text: "Template commands: workflow templates; run template Name.",
        actionId: "workflow_template_syntax",
        templateToRun: nil
      )
    }
    return nil
  }

  private static func prefixedValue(_ value: String, prefixes: [String]) -> String? {
    let lower = value.lowercased()
    guard let prefix = prefixes.first(where: { lower.hasPrefix($0) }) else { return nil }
    let clean = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? nil : clean
  }
}
