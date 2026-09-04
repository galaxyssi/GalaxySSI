import Foundation

enum AgentHomeAssistantNativeToolPlanBridge {
  static func rewrite(actions: [AgentAction], request: AgentPlanRequest) -> [AgentAction] {
    actions.map { action in
      rewrite(action: action, request: request) ?? action
    }
  }

  private static func rewrite(action: AgentAction, request: AgentPlanRequest) -> AgentAction? {
    guard action.kind == .controlDevice,
          connectorId(action) == homeAssistantConnectorId,
          let descriptor = request.nativeTools.first(where: {
            $0.id == AgentIOSHomeAssistantNativeToolCatalog.serviceCall &&
              $0.availability.status == .available
          }) else {
      return nil
    }
    let prompt = firstNonBlank(
      action.parameters["prompt"] ?? "",
      action.parameters["original_goal"] ?? "",
      action.description,
      request.goal
    )
    let defaultEntityId = firstNonBlank(
      action.parameters["entity_id"] ?? "",
      looksLikeEntityId(action.target) ? action.target : ""
    )
    guard let serviceCall = AgentHomeAssistantPromptRouter.serviceCall(
      for: prompt,
      defaultEntityId: defaultEntityId
    ) else {
      return nil
    }
    let input = serviceCall.nativeToolInput
    let inputJson = AgentMcpJSONCodec.stringify(input)
    var parameters = action.parameters
    parameters["tool_id"] = descriptor.id
    parameters["tool_version"] = descriptor.version
    parameters["native_tool_risk"] = descriptor.risk.rawValue
    parameters["input_json"] = inputJson
    parameters["connector_id"] = homeAssistantConnectorId
    parameters["home_assistant_entity_id"] = serviceCall.entityId
    parameters["home_assistant_service"] = "\(serviceCall.serviceDomain).\(serviceCall.service)"
    parameters["source_action_kind"] = action.kind.rawValue
    return AgentAction(
      id: "home-assistant-service-\(AgentMcpJSONCodec.sha256(input).prefix(16))",
      kind: .callNativeTool,
      target: serviceCall.entityId,
      risk: higherRisk(action.risk, nativeRisk(descriptor.risk)),
      status: action.status,
      description: action.description,
      parameters: parameters,
      requiresConfirmation: true,
      result: action.result,
      evidence: action.evidence
    )
  }

  private static func connectorId(_ action: AgentAction) -> String {
    firstNonBlank(action.parameters["connector_id"] ?? "", action.target)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  private static func looksLikeEntityId(_ value: String) -> Bool {
    value.range(of: entityIdPattern, options: .regularExpression) != nil
  }

  private static func nativeRisk(_ risk: AgentNativeToolRisk) -> AgentRisk {
    switch risk {
    case .low:
      return .low
    case .medium:
      return .medium
    case .high:
      return .high
    case .blocked:
      return .blocked
    }
  }

  private static func higherRisk(_ first: AgentRisk, _ second: AgentRisk) -> AgentRisk {
    first.weight >= second.weight ? first : second
  }

  private static func firstNonBlank(_ values: String...) -> String {
    values
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? ""
  }

  private static let homeAssistantConnectorId = "home-assistant"
  private static let entityIdPattern = #"\b[a-z_]+\.[A-Za-z0-9_]+\b"#
}
