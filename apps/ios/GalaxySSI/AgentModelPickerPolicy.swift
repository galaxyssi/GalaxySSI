import Foundation

enum AgentModelPickerSource: String, CaseIterable, Identifiable {
  case desktop, cloud, local
  var id: String { rawValue }
}

struct AgentModelPickerCloudChoice: Identifiable {
  var contact: GalaxySSIContact
  var model: CloudModelConfig
  var id: String { "\(contact.id):\(model.modelId)" }
}

enum AgentModelPickerPolicy {
  private static let olderCodexIds: Set<String> = [
    "gpt-6-astra", "gpt-6-sol", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"
  ]
  private static let olderClaudeIds: Set<String> = [
    "claude-fable-5", "claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5-20251001"
  ]

  static func desktopTargets(_ targets: [AgentCallableTarget], selectedId: String) -> [AgentCallableTarget] {
    func priority(_ target: AgentCallableTarget) -> Int {
      if target.id == selectedId { return 0 }
      return target.id.split(separator: ":").last == "codex" ? 1 : 2
    }
    return AgentCallableTargetCatalog.selectableAgentTargets(targets).enumerated().sorted {
      let lhs = priority($0.element), rhs = priority($1.element)
      return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
    }.map(\.element)
  }

  static func modelGroups(_ target: AgentCallableTarget, selectedModelId: String) -> (visible: [AgentModelOption], folded: [AgentModelOption]) {
    let models = target.invocationProfile.models.filter { !RetiredAgentModelPolicy.isRetired($0.id) }
    let selected = selectedModelId.isEmpty ? "" : target.invocationProfile.normalizedModelId(selectedModelId)
    let older: Set<String>
    switch target.kind == .agent ? target.id.split(separator: ":").last.map(String.init) : nil {
    case "codex": older = olderCodexIds
    case "claude": older = olderClaudeIds
    default: older = []
    }
    let visible = models.filter { $0.id == selected || !older.contains($0.id) }
    if visible.isEmpty { return (models, []) }
    return (visible, models.filter { $0.id != selected && older.contains($0.id) })
  }

  static func initialSource(selection: AgentModelSelection, agents: [AgentCallableTarget], hasCloud: Bool, hasLocal: Bool) -> AgentModelPickerSource {
    if selection.targetId == "local-llm" { return .local }
    if selection.targetId.hasPrefix("cloud:") { return .cloud }
    if !selection.targetId.isEmpty || !agents.isEmpty { return .desktop }
    if hasCloud { return .cloud }
    return hasLocal ? .local : .desktop
  }

  static func desktopLabel(_ title: String) -> (name: String, device: String) {
    guard let separator = title.range(of: " \u{00B7} ") else { return (title, "") }
    return (String(title[..<separator.lowerBound]), String(title[separator.upperBound...]))
  }

  static func modelLabel(_ id: String) -> String {
    guard id.hasPrefix("gpt-") else { return id }
    return "GPT-" + id.dropFirst(4).split(separator: "-").map {
      $0.prefix(1).uppercased() + String($0.dropFirst())
    }.joined(separator: " ")
  }
}
