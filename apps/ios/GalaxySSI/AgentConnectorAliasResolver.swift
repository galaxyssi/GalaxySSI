import Foundation

enum AgentConnectorAliasResolver {
  static func resolve(
    actions: [AgentAction],
    targets: [AgentCallableTarget]
  ) -> [AgentAction] {
    actions.map { action in
      guard action.kind == .callConnector else { return action }
      let requested = firstNonBlank(
        action.parameters["connector_id"] ?? "",
        action.target
      )
      guard let target = target(for: requested, in: targets) else {
        return action
      }

      var resolved = action
      resolved.target = target.title
      resolved.parameters["connector_id"] = target.id
      if normalized(requested) != normalized(target.id) {
        resolved.parameters["connector_alias"] = requested
      }
      return resolved
    }
  }

  private static func target(
    for requested: String,
    in targets: [AgentCallableTarget]
  ) -> AgentCallableTarget? {
    let requestedKey = normalized(requested)
    guard !requestedKey.isEmpty else { return nil }
    return targets
      .filter { target in
        target.kind != .device && AgentConnectorRouteSelector.isDeliverable(target)
      }
      .sorted { left, right in
        let leftExact = normalized(left.id) == requestedKey || normalized(left.title) == requestedKey
        let rightExact = normalized(right.id) == requestedKey || normalized(right.title) == requestedKey
        if leftExact != rightExact { return leftExact }
        return left.id < right.id
      }
      .first { target in
        let aliases = [
          target.id,
          target.id.split(separator: ":").last.map(String.init) ?? target.id,
          target.title
        ].map(normalized).filter { $0.count >= 3 }
        return aliases.contains { alias in
          alias == requestedKey || alias.contains(requestedKey) || requestedKey.contains(alias)
        }
      }
  }

  private static func normalized(_ value: String) -> String {
    value
      .lowercased()
      .unicodeScalars
      .filter { CharacterSet.alphanumerics.contains($0) }
      .map(String.init)
      .joined()
  }

  private static func firstNonBlank(_ values: String...) -> String {
    values
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? ""
  }
}
