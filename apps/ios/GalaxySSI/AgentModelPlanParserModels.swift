import Foundation

struct AgentModelPlanInstalledApp: Codable, Equatable, Identifiable {
  var packageName: String
  var label: String

  var id: String { packageName }

  init(packageName: String, label: String) {
    self.packageName = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
    self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  enum CodingKeys: String, CodingKey {
    case packageName = "package_name"
    case label
  }
}

struct AgentModelPlanParsingContext: Codable, Equatable {
  var replanReason: String
  var clickableElements: [AgentScreenElement]
  var inputFields: [AgentScreenElement]
  var focusedInputField: AgentScreenElement?
  var installedApps: [AgentModelPlanInstalledApp]

  init(
    replanReason: String = "",
    clickableElements: [AgentScreenElement] = [],
    inputFields: [AgentScreenElement] = [],
    focusedInputField: AgentScreenElement? = nil,
    installedApps: [AgentModelPlanInstalledApp] = []
  ) {
    self.replanReason = String(replanReason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
    self.clickableElements = clickableElements
    self.inputFields = inputFields
    self.focusedInputField = focusedInputField
    self.installedApps = installedApps
  }

  static let empty = AgentModelPlanParsingContext()

  enum CodingKeys: String, CodingKey {
    case replanReason = "replan_reason"
    case clickableElements = "clickable_elements"
    case inputFields = "input_fields"
    case focusedInputField = "focused_input_field"
    case installedApps = "installed_apps"
  }
}
