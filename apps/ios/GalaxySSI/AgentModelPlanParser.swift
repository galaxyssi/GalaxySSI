import Foundation

enum AgentModelPlanParser {
  static let allowedKinds: Set<AgentActionKind> = [
    .readScreen,
    .saveScreenKnowledge,
    .draftPlan,
    .tap,
    .typeText,
    .swipe,
    .longPress,
    .back,
    .home,
    .recents,
    .lockScreen,
    .openApp,
    .openURL,
    .setAlarm,
    .createNotification,
    .copyScreenText,
    .deleteText,
    .pasteText,
    .importWebKnowledge,
    .callNativeTool,
    .callConnector,
    .controlDevice
  ]

  static func parse(
    request: AgentPlanRequest,
    raw: String,
    settings: AgentModelPlannerSettings,
    context: AgentModelPlanParsingContext = .empty
  ) -> AgentPlan? {
    guard let json = extractJson(raw),
          let actionValues = json["actions"]?.arrayValue,
          !actionValues.isEmpty else {
      return nil
    }
    let normalizedSettings = settings.normalized
    guard actionValues.count <= normalizedSettings.maxActions else {
      return nil
    }

    var refs: [String: AgentModelPlanRef] = [:]
    for (index, value) in actionValues.enumerated() {
      guard let item = value.objectValue else {
        return nil
      }
      let fallback = "step-\(index + 1)"
      guard let ref = normalizedRef(item.string("ref").trimmedForModelPlan.ifBlank(fallback)) else {
        return nil
      }
      guard refs[ref] == nil else {
        return nil
      }
      refs[ref] = AgentModelPlanRef(index: index, actionId: "model-\(index + 1)-\(ref)")
    }

    var actions: [AgentAction] = []
    for (index, value) in actionValues.enumerated() {
      guard let item = value.objectValue else {
        return nil
      }
      let fallback = "step-\(index + 1)"
      guard let ref = normalizedRef(item.string("ref").trimmedForModelPlan.ifBlank(fallback)),
            let actionId = refs[ref]?.actionId,
            let action = parseAction(
              request: request,
              context: context,
              json: item,
              index: index,
              actionId: actionId,
              refs: refs,
              allowCoordination: normalizedSettings.multiAgentCoordination
            ) else {
        return nil
      }
      actions.append(action)
    }

    guard hasValidDraftPlanSemantics(context: context, actions: actions) else {
      return nil
    }

    var plan = AgentPlanFactory.actions(request: request, actions)
    let expectedResult = json.string("expected_result").trimmedForModelPlan.prefixString(500)
    let rollbackStrategy = json.string("rollback_strategy").trimmedForModelPlan.prefixString(500)
    if !expectedResult.isEmpty {
      plan.expectedResult = expectedResult
    }
    if !rollbackStrategy.isEmpty {
      plan.rollbackStrategy = rollbackStrategy
    } else {
      plan.rollbackStrategy = "Stop execution and restore the last safe checkpoint."
    }
    plan.validation = AgentPlanValidator.validate(plan)
    return plan.validation.valid && toolGraphDepth(actions: plan.actions) <= normalizedSettings.maxAgentHops ? plan : nil
  }

  private static func parseAction(
    request: AgentPlanRequest,
    context: AgentModelPlanParsingContext,
    json: AgentMcpJSONObject,
    index: Int,
    actionId: String,
    refs: [String: AgentModelPlanRef],
    allowCoordination: Bool
  ) -> AgentAction? {
    let kindName = json.string("kind").trimmedForModelPlan.uppercased()
    guard let kind = AgentActionKind.allCases.first(where: { $0.rawValue == kindName }),
          allowedKinds.contains(kind) else {
      return nil
    }
    let dependencyRefs = stringArray(json["depends_on"])
    let outputRefs = stringArray(json["use_outputs_from"])
    if !allowCoordination && (!dependencyRefs.isEmpty || !outputRefs.isEmpty) {
      return nil
    }
    if !outputRefs.isEmpty && kind != .callConnector {
      return nil
    }
    if outputRefs.contains(where: { !dependencyRefs.contains($0) }) {
      return nil
    }
    guard let dependencyIds = resolvePriorRefs(dependencyRefs, refs: refs, currentIndex: index),
          let outputSourceIds = resolvePriorRefs(outputRefs, refs: refs, currentIndex: index),
          let nodeRef = refs.first(where: { $0.value.actionId == actionId })?.key,
          let parameters = resolveParameters(
            kind: kind,
            input: json.object("parameters") ?? [:],
            request: request,
            context: context
          ) else {
      return nil
    }

    var resolvedParameters = parameters
    resolvedParameters["node_ref"] = nodeRef
    resolvedParameters["depends_on"] = dependencyIds.joined(separator: ",")
    resolvedParameters["use_outputs_from"] = outputSourceIds.joined(separator: ",")
    let target = resolveTarget(
      kind: kind,
      proposed: json.string("target"),
      parameters: resolvedParameters,
      request: request,
      context: context
    )
    let description = json.string("description")
      .trimmedForModelPlan
      .prefixString(300)
      .ifBlank(defaultDescription(kind: kind, target: target))
    return AgentAction(
      id: actionId,
      kind: kind,
      target: target,
      risk: localRisk(kind: kind, parameters: resolvedParameters, target: target),
      status: .pendingConfirmation,
      description: description,
      parameters: resolvedParameters,
      requiresConfirmation: true
    )
  }

  private static func resolveParameters(
    kind: AgentActionKind,
    input: AgentMcpJSONObject,
    request: AgentPlanRequest,
    context: AgentModelPlanParsingContext
  ) -> [String: String]? {
    switch kind {
    case .tap, .longPress:
      guard let element = AgentScreenElementMatcher.resolve(
        query: input.string("element_query"),
        elements: context.clickableElements
      ) else {
        return nil
      }
      return [
        "bounds": element.bounds,
        "matched_label": safeLabel(element),
        "element_origin": element.origin.rawValue,
        "element_role": element.visualRole.rawValue,
        "element_confidence": String(element.confidence)
      ]

    case .typeText:
      let text = input.string("text").prefixString(maximumTextInputCharacters)
      guard !text.trimmedForModelPlan.isEmpty,
            let field = resolveInputField(query: input.string("field_query"), context: context),
            !isSensitiveInput(field) else {
        return nil
      }
      return [
        "text": text,
        "field_bounds": field.bounds,
        "matched_label": safeLabel(field),
        "field_origin": field.origin.rawValue,
        "field_confidence": String(field.confidence)
      ]

    case .deleteText, .pasteText:
      guard let field = resolveInputField(query: input.string("field_query"), context: context),
            !isSensitiveInput(field) else {
        return nil
      }
      return [
        "field_bounds": field.bounds,
        "matched_label": safeLabel(field),
        "field_origin": field.origin.rawValue,
        "field_confidence": String(field.confidence)
      ]

    case .swipe:
      return swipeParameters(direction: input.string("direction"))

    case .openApp:
      let packageName = input.string("package").trimmedForModelPlan
      guard context.installedApps.contains(where: { $0.packageName == packageName }) else {
        return nil
      }
      return ["package": packageName]

    case .openURL, .importWebKnowledge:
      guard let url = safeHttpUrl(input.string("url")) else {
        return nil
      }
      return ["url": url]

    case .setAlarm:
      let hour = Int(input.int64("hour"))
      let minute = Int(input.int64("minute"))
      guard (0...23).contains(hour), (0...59).contains(minute) else {
        return nil
      }
      return [
        "hour": String(hour),
        "minute": String(minute),
        "message": input.string("message").prefixString(200)
      ]

    case .createNotification:
      let text = input.string("text").prefixString(1_000)
      guard !text.trimmedForModelPlan.isEmpty else {
        return nil
      }
      return [
        "title": input.string("title").prefixString(160).trimmedForModelPlan.ifBlank("GalaxySSI Agent"),
        "text": text
      ]

    case .callConnector, .controlDevice:
      return resolveConnector(kind: kind, input: input, request: request)

    case .callNativeTool:
      return resolveNativeTool(input: input, request: request)

    case .readScreen,
         .saveScreenKnowledge,
         .draftPlan,
         .back,
         .home,
         .recents,
         .lockScreen,
         .copyScreenText:
      return [:]

    case .replyNotification:
      return nil
    }
  }

  private static func resolveConnector(
    kind: AgentActionKind,
    input: AgentMcpJSONObject,
    request: AgentPlanRequest
  ) -> [String: String]? {
    let connectorId = input.string("connector_id").trimmedForModelPlan
    guard let target = request.targets.first(where: {
      $0.id == connectorId &&
        AgentConnectorRouteSelector.isDeliverable($0) &&
        (kind != .controlDevice || $0.kind == .device)
    }) else {
      return nil
    }
    let prompt = input.string("prompt")
      .prefixString(maximumConnectorPromptCharacters)
      .trimmedForModelPlan
      .ifBlank(request.goal.prefixString(maximumConnectorPromptCharacters))
    return [
      "connector_id": target.id,
      "prompt": prompt,
      "custom_device_id": target.id.hasPrefix("custom-device:") ? String(target.id.dropFirst("custom-device:".count)) : ""
    ]
  }

  private static func resolveNativeTool(
    input: AgentMcpJSONObject,
    request: AgentPlanRequest
  ) -> [String: String]? {
    let toolId = input.string("tool_id").trimmedForModelPlan
    guard let descriptor = request.nativeTools.first(where: {
      $0.id == toolId && $0.availability.status == .available
    }) else {
      return nil
    }
    let arguments = input.object("arguments") ?? [:]
    let inputJson = AgentMcpJSONCodec.stringify(arguments)
    guard inputJson.count <= maximumNativeToolArgumentCharacters else {
      return nil
    }
    let effectiveRisk: String
    if descriptor.id == AgentMcpNativeTools.callTool {
      effectiveRisk = AgentMcpToolSecurityPolicy.provisionalRisk(toolName: arguments.string("tool_name")).rawValue
    } else {
      effectiveRisk = descriptor.risk.rawValue
    }
    return [
      "tool_id": descriptor.id,
      "tool_version": descriptor.version,
      "native_tool_risk": effectiveRisk,
      "input_json": inputJson
    ]
  }

  private static func resolveInputField(
    query: String,
    context: AgentModelPlanParsingContext
  ) -> AgentScreenElement? {
    if query.trimmedForModelPlan.isEmpty {
      return context.focusedInputField
    }
    return AgentScreenElementMatcher.resolve(query: query, elements: context.inputFields)
  }

  private static func resolveTarget(
    kind: AgentActionKind,
    proposed: String,
    parameters: [String: String],
    request: AgentPlanRequest,
    context: AgentModelPlanParsingContext
  ) -> String {
    switch kind {
    case .openApp:
      return context.installedApps.first { $0.packageName == parameters["package"] }?.label ?? ""
    case .callConnector, .controlDevice:
      return request.targets.first { $0.id == parameters["connector_id"] }?.title ?? ""
    case .callNativeTool:
      return request.nativeTools.first { $0.id == parameters["tool_id"] }?.title ?? ""
    default:
      return proposed.trimmedForModelPlan.prefixString(200).ifBlank(request.screen.foregroundApp)
    }
  }

  private static func resolvePriorRefs(
    _ values: [String],
    refs: [String: AgentModelPlanRef],
    currentIndex: Int
  ) -> [String]? {
    var resolved: [String] = []
    for value in values {
      guard let ref = normalizedRef(value),
            let match = refs[ref],
            match.index < currentIndex else {
        return nil
      }
      if !resolved.contains(match.actionId) {
        resolved.append(match.actionId)
      }
    }
    return resolved
  }

  private static func hasValidDraftPlanSemantics(
    context: AgentModelPlanParsingContext,
    actions: [AgentAction]
  ) -> Bool {
    let drafts = actions.filter { $0.kind == .draftPlan }
    guard !drafts.isEmpty else {
      return true
    }
    return !context.replanReason.trimmedForModelPlan.isEmpty &&
      actions.count == 1 &&
      drafts[0].target.caseInsensitiveCompare(taskCompleteTarget) == .orderedSame
  }

  private static func swipeParameters(direction: String) -> [String: String]? {
    switch direction.trimmedForModelPlan.lowercased() {
    case "up":
      return coordinates(fromX: 540, fromY: 1_700, toX: 540, toY: 700)
    case "down":
      return coordinates(fromX: 540, fromY: 700, toX: 540, toY: 1_700)
    case "left":
      return coordinates(fromX: 900, fromY: 1_100, toX: 180, toY: 1_100)
    case "right":
      return coordinates(fromX: 180, fromY: 1_100, toX: 900, toY: 1_100)
    default:
      return nil
    }
  }

  private static func coordinates(fromX: Int, fromY: Int, toX: Int, toY: Int) -> [String: String] {
    [
      "from_x": String(fromX),
      "from_y": String(fromY),
      "to_x": String(toX),
      "to_y": String(toY)
    ]
  }

  private static func safeHttpUrl(_ value: String) -> String? {
    let clean = value.trimmedForModelPlan
    guard let components = URLComponents(string: clean),
          let scheme = components.scheme?.lowercased(),
          ["http", "https"].contains(scheme),
          !(components.host ?? "").isEmpty else {
      return nil
    }
    return clean
  }

  private static func localRisk(
    kind: AgentActionKind,
    parameters: [String: String],
    target: String
  ) -> AgentRisk {
    switch kind {
    case .readScreen,
         .draftPlan,
         .swipe,
         .back,
         .home,
         .recents,
         .openApp,
         .copyScreenText:
      return .low

    case .saveScreenKnowledge,
         .tap,
         .typeText,
         .longPress,
         .openURL,
         .setAlarm,
         .createNotification,
         .deleteText,
         .pasteText,
         .importWebKnowledge,
         .callConnector:
      return .medium

    case .callNativeTool:
      switch parameters["native_tool_risk"] {
      case AgentNativeToolRisk.high.rawValue:
        return .high
      case AgentNativeToolRisk.medium.rawValue:
        return .medium
      case AgentNativeToolRisk.blocked.rawValue:
        return .blocked
      default:
        return .low
      }

    case .lockScreen, .controlDevice:
      return isHighRiskTarget(target: target, parameters: parameters) ? .high : .medium
    case .replyNotification:
      return .high
    }
  }

  private static func toolGraphDepth(actions: [AgentAction]) -> Int {
    var depthById: [String: Int] = [:]
    var maximumDepth = actions.isEmpty ? 0 : 1
    for action in actions {
      let dependencies = csvValues(action.parameters["depends_on"] ?? "")
      let depth = (dependencies.compactMap { depthById[$0] }.max() ?? 0) + 1
      depthById[action.id] = depth
      maximumDepth = max(maximumDepth, depth)
    }
    return maximumDepth
  }

  private static func extractJson(_ raw: String) -> AgentMcpJSONObject? {
    let trimmed = raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .removingPrefix("```json")
      .removingPrefix("```")
      .removingSuffix("```")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let start = trimmed.firstIndex(of: "{"),
          let end = trimmed.lastIndex(of: "}"),
          start < end else {
      return nil
    }
    let text = String(trimmed[start...end])
    guard let data = text.data(using: .utf8) else {
      return nil
    }
    return try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data)
  }

  private static func stringArray(_ value: AgentMcpJSONValue?) -> [String] {
    guard let array = value?.arrayValue else {
      return []
    }
    return array.compactMap {
      $0.stringValue?.trimmedForModelPlan.nonEmpty
    }
  }

  private static func csvValues(_ value: String) -> [String] {
    value
      .split(separator: ",")
      .map { String($0).trimmedForModelPlan }
      .filter { !$0.isEmpty }
  }

  private static func normalizedRef(_ value: String) -> String? {
    let clean = value.trimmedForModelPlan.lowercased()
    return clean.range(of: #"^[a-z0-9][a-z0-9_-]{0,47}$"#, options: .regularExpression) == nil ? nil : clean
  }

  private static func safeLabel(_ element: AgentScreenElement) -> String {
    element.label
      .trimmedForModelPlan
      .ifBlank(element.viewId.trimmedForModelPlan.ifBlank(element.className.trimmedForModelPlan))
      .prefixString(160)
  }

  private static func isSensitiveInput(_ element: AgentScreenElement) -> Bool {
    let value = "\(element.label) \(element.viewId) \(element.className)"
    return sensitiveFieldTerms.contains { value.range(of: $0, options: .caseInsensitive) != nil }
  }

  private static func isHighRiskTarget(target: String, parameters: [String: String]) -> Bool {
    highRiskTerms.contains { term in
      target.range(of: term, options: .caseInsensitive) != nil ||
        parameters.values.contains { $0.range(of: term, options: .caseInsensitive) != nil }
    }
  }

  private static func defaultDescription(kind: AgentActionKind, target: String) -> String {
    kind.rawValue.lowercased().replacingOccurrences(of: "_", with: " ") +
      (target.isBlank ? "" : " on \(target)")
  }

  private static let sensitiveFieldTerms = ["password", "passcode", "pin", "otp", "verification", "cvv"]
  private static let highRiskTerms = ["lock", "door", "garage", "alarm", "camera", "security", "siren", "valve"]
  private static let maximumTextInputCharacters = 2_000
  private static let maximumConnectorPromptCharacters = 4_000
  private static let maximumNativeToolArgumentCharacters = 64 * 1_024
  private static let taskCompleteTarget = "task-complete"
}

private struct AgentModelPlanRef: Equatable {
  var index: Int
  var actionId: String
}

private extension String {
  var trimmedForModelPlan: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func prefixString(_ count: Int) -> String {
    String(prefix(max(count, 0)))
  }

  func removingPrefix(_ prefix: String) -> String {
    hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
  }

  func removingSuffix(_ suffix: String) -> String {
    hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
  }
}
