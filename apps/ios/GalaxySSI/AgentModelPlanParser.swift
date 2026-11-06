import Foundation

struct AgentModelPlanRejection: Error, Encodable, Equatable {
  let field: String
  let code: String
  let correction: String

  init(_ field: String, _ code: String, _ correction: String) {
    self.field = field
    self.code = code
    self.correction = String(correction.prefix(1_024))
  }

  var repairInstruction: String {
    let data = (try? JSONEncoder().encode(self)) ?? Data()
    return """
    Local ActionPlan rejection:
    \(String(decoding: data, as: UTF8.self))
    Return one corrected JSON ActionPlan. Keep the original goal, execution route and permissions.
    Use only advertised tools and earlier dependencies in this batch. Never combine completion with executable actions.
    """
  }
}

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
    try? parseWithDiagnostics(request: request, raw: raw, settings: settings, context: context).get()
  }

  static func parseWithDiagnostics(
    request: AgentPlanRequest,
    raw: String,
    settings: AgentModelPlannerSettings,
    context: AgentModelPlanParsingContext = .empty,
    allowsNativeDependencies: Bool = false
  ) -> Result<AgentPlan, AgentModelPlanRejection> {
    do {
      return .success(try parseChecked(request: request, raw: raw, settings: settings, context: context,
        allowsNativeDependencies: allowsNativeDependencies))
    }
    catch let rejection as AgentModelPlanRejection { return .failure(rejection) }
    catch { return .failure(.init("$", "validation_failed", "Return an ActionPlan using the advertised schema.")) }
  }

  private static func parseChecked(
    request: AgentPlanRequest,
    raw: String,
    settings: AgentModelPlannerSettings,
    context: AgentModelPlanParsingContext,
    allowsNativeDependencies: Bool
  ) throws -> AgentPlan {
    guard var json = extractJson(raw) else {
      throw AgentModelPlanRejection("$", "invalid_json", "Return one JSON object containing an actions array.")
    }
    if json["actions"] == nil, AgentRollingPlanPolicy.isBatchBoundaryReason(context.replanReason),
       let response = AgentModelDirectResponseCodec.parse(raw, envelopeOnly: true) {
      json["actions"] = .array([.object(["kind": .string(AgentActionKind.draftPlan.rawValue),
                                        "target": .string(taskCompleteTarget), "description": .string(response)])])
    }
    guard let actionValues = json["actions"]?.arrayValue else {
      throw AgentModelPlanRejection("actions", "array_required", "Provide a non-empty actions array.")
    }
    let observed = observedCompletion(json["completion_requirements"]?.objectValue?["outcomes"])
    if let diagnostic = observed.error {
      throw AgentModelPlanRejection("completion_requirements.outcomes", "invalid_completion_shape", diagnostic)
    }
    var completionRequirements = parseCompletionRequirements(json["completion_requirements"])
    completionRequirements?.outcomes = observed.outcomes
    if json["completion_requirements"] != nil && completionRequirements == nil {
      throw AgentModelPlanRejection("completion_requirements", "invalid_requirements",
        "Use the advertised publication and phone_linux fields. Results require a unique id, description, string-list outcome_ids and artifact_paths, and a string answer.")
    }
    if completionRequirements?.canReplace(request.completionRequirements) == false {
      throw AgentModelPlanRejection("completion_requirements.reason", "unexplained_requirement_change",
        "Preserve all previous outcome and requested result IDs. Explain corrections in reason; do not drop unfinished deliverables.")
    }
    let normalizedSettings = settings.normalized
    let maximumActions = context.maximumActionsOverride ?? normalizedSettings.maxActions
    guard !actionValues.isEmpty, actionValues.count <= maximumActions else {
      throw AgentModelPlanRejection("actions", "batch_size",
        "Provide between 1 and \(maximumActions) actions. Leave remaining work for the next batch.")
    }
    if actionValues.count > 1 && actionValues.contains(where: { value in
      let kind = value.objectValue?.string("kind").trimmedForModelPlan.uppercased() ?? ""
      return kind == AgentActionKind.draftPlan.rawValue || kind.replacingOccurrences(of: "-", with: "_") == "TASK_COMPLETE"
    }) {
      throw AgentModelPlanRejection("actions", "completion_mixed_with_execution",
        "Return only the executable actions first. After reviewing verified receipts, return a separate completion-only ActionPlan. A dependency cannot make a future completion valid in this batch.")
    }

    var refs: [String: AgentModelPlanRef] = [:]
    for (index, value) in actionValues.enumerated() {
      guard let item = value.objectValue else {
        throw AgentModelPlanRejection("actions[\(index)]", "object_required", "Each action must be a JSON object.")
      }
      let fallback = "step-\(index + 1)"
      guard let ref = normalizedRef(item.string("ref").trimmedForModelPlan.ifBlank(fallback)) else {
        throw AgentModelPlanRejection("actions[\(index)].ref", "invalid_ref",
          "Use a 1 to 48 character reference containing letters, digits, hyphens or underscores.")
      }
      guard refs[ref] == nil else {
        throw AgentModelPlanRejection("actions[\(index)].ref", "duplicate_ref", "Use a distinct reference for each action.")
      }
      refs[ref] = AgentModelPlanRef(index: index, actionId: "model-\(index + 1)-\(ref)")
    }

    var actions: [AgentAction] = []
    for (index, value) in actionValues.enumerated() {
      guard let item = value.objectValue else {
        throw AgentModelPlanRejection("actions[\(index)]", "object_required", "Each action must be a JSON object.")
      }
      let fallback = "step-\(index + 1)"
      guard let ref = normalizedRef(item.string("ref").trimmedForModelPlan.ifBlank(fallback)),
            let actionId = refs[ref]?.actionId else {
        throw AgentModelPlanRejection("actions[\(index)].ref", "invalid_ref", "Use a valid reference within this batch.")
      }
      actions.append(try parseAction(request: request, context: context, json: item, index: index,
        actionId: actionId, refs: refs, allowCoordination: normalizedSettings.multiAgentCoordination,
        allowsNativeDependencies: allowsNativeDependencies))
    }

    guard hasValidDraftPlanSemantics(context: context, actions: actions) else {
      throw AgentModelPlanRejection("actions", "completion_mixed_with_execution",
        "Return executable actions first. After reviewing receipts, use a single completion action in an eligible continuation.")
    }
    if actions.contains(where: { $0.kind == .draftPlan }), extractJson(raw, exact: true) == nil {
      throw AgentModelPlanRejection("$", "completion_envelope", "Return the completion object alone, with no surrounding prose.")
    }

    var plan = AgentPlanningTiming.measure("plan") {
      AgentPlanFactory.actions(request: request, actions)
    }
    plan.completionRequirements = completionRequirements ?? request.completionRequirements
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
    let maximumGraphDepth = context.maximumActionsOverride ?? normalizedSettings.maxAgentHops
    guard plan.validation.valid else {
      if plan.validation.issues.contains("route_unknown") {
        throw AgentModelPlanRejection("actions", "execution_tool_policy",
          "The ActionPlan parses, but this route does not support the proposed connector or device. Use an advertised target for this route.")
      }
      throw AgentModelPlanRejection("actions", "plan_validation",
        "Use non-empty action descriptions and retain the required confirmation for high-risk actions.")
    }
    guard toolGraphDepth(actions: plan.actions) <= maximumGraphDepth else {
      throw AgentModelPlanRejection("actions.depends_on", "graph_depth",
        "Keep dependency depth within \(maximumGraphDepth). Continue remaining work in a later batch.")
    }
    return plan
  }

  private static func parseCompletionRequirements(
    _ value: AgentMcpJSONValue?
  ) -> AgentCompletionRequirements? {
    guard let object = value?.objectValue,
          case .string(let publicationValue) = object["publication"],
          let publication = AgentPublicationRequirement(rawValue: publicationValue),
          case .bool(let phoneLinux) = object["phone_linux"] else {
      return nil
    }
    let reason: String
    if let value = object["reason"] {
      guard case .string(let rawReason) = value, rawReason.count <= 1_000 else {
        return nil
      }
      reason = rawReason
    } else {
      reason = ""
    }
    var artifacts: [AgentVideoArtifactRequirement]?
    if let declared = object["artifacts"] {
      guard let items = declared.arrayValue, items.count <= 4 else { return nil }
      let parsed = items.compactMap { item -> AgentVideoArtifactRequirement? in
        guard let artifact = item.objectValue, let workspace = artifact["workspace_id"]?.stringValue,
              let path = artifact["path"]?.stringValue else { return nil }
        return AgentVideoArtifactRequirement(workspaceId: workspace, path: path)
      }
      guard parsed.count == items.count, Set(parsed).count == parsed.count else { return nil }
      artifacts = parsed.isEmpty ? nil : parsed
    }
    var fileArtifacts: [AgentArtifactRequirement] = []
    if let value = object["file_artifacts"] {
      guard let items = value.arrayValue, items.count <= 16 else { return nil }
      for item in items {
        guard let fields = item.objectValue, let path = fields["path"]?.stringValue,
              fields["source_sha256"] == nil || fields["source_sha256"]?.stringValue != nil,
              fields["workspace_id"] == nil || fields["workspace_id"]?.stringValue != nil,
              let artifact = AgentArtifactRequirement(path: path, sourceSha256: fields.string("source_sha256"),
                workspaceId: fields.string("workspace_id")), !fileArtifacts.contains(artifact) else { return nil }
        fileArtifacts.append(artifact)
      }
    }
    var requirements = AgentCompletionRequirements(
      publication: publication,
      phoneLinux: phoneLinux,
      reason: reason,
      artifacts: artifacts,
      fileArtifacts: fileArtifacts.isEmpty ? nil : fileArtifacts
    )
    if let value = object["results"] {
      guard let items = value.arrayValue, items.count <= 32 else { return nil }
      let results = items.compactMap { item in item.objectValue.flatMap(AgentGoalResultRequirement.init(json:)) }
      guard results.count == items.count, Set(results.map(\.id)).count == results.count else { return nil }
      requirements.results = results
    }
    return requirements
  }

  static func permitsPhoneExecutionSite(_ raw: String) -> Bool {
    guard let json = extractJson(raw, exact: true) else { return false }
    guard let site = json["execution_location"] else { return true }
    if case let .string(value) = site {
      return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "phone"
    }
    return false
  }

  static func completionShapeRepair(_ raw: String) -> (diagnostic: String, original: AgentMcpJSONObject)? {
    guard raw.utf8.count <= 32_768, let json = extractJson(raw, exact: true),
          let requirements = json["completion_requirements"]?.objectValue,
          let actions = json["actions"]?.arrayValue, !actions.isEmpty,
          let error = observedCompletion(requirements["outcomes"]).error else { return nil }
    return (error, json)
  }

  static func repairedOnlyCompletionShape(_ raw: String, original: AgentMcpJSONObject) -> Bool {
    guard raw.utf8.count <= 32_768, var corrected = extractJson(raw, exact: true),
          var requirements = corrected["completion_requirements"]?.objectValue,
          var prior = original["completion_requirements"]?.objectValue,
          let outcomes = observedCompletion(requirements.removeValue(forKey: "outcomes")).outcomes,
          !outcomes.isEmpty else { return false }
    var expected = original
    if let rows = prior.removeValue(forKey: "outcomes")?.arrayValue {
      guard outcomes.count == rows.count else { return false }
      for (row, outcome) in zip(rows, outcomes) {
        guard let item = row.objectValue else { continue }
        for (key, value) in [("id", outcome.id), ("tool_id", outcome.toolId), ("after_tool_id", outcome.afterToolId)] {
          if case let .string(previous) = item[key], previous != value { return false }
        }
      }
    }
    corrected.removeValue(forKey: "completion_requirements")
    expected.removeValue(forKey: "completion_requirements")
    return corrected == expected && requirements == prior
  }

  private static func observedCompletion(
    _ value: AgentMcpJSONValue?
  ) -> (outcomes: [AgentObservedCompletion]?, error: String?) {
    guard let value else { return (nil, nil) }
    guard let rows = value.arrayValue, rows.count <= 32 else {
      return (nil, "completion_requirements.outcomes must be an array of at most 32 receipt checks.")
    }
    var result: [AgentObservedCompletion] = []
    var ids = Set<String>()
    for (index, row) in rows.enumerated() {
      let field = "completion_requirements.outcomes[\(index)]"
      guard let object = row.objectValue, case let .string(id) = object["id"],
            id.range(of: #"^[A-Za-z0-9_.-]{1,128}$"#, options: .regularExpression) != nil,
            ids.insert(id).inserted,
            case let .string(toolId) = object["tool_id"], validObservedToolID(toolId) else {
        return (nil, "\(field) requires a unique id and a galaxyssi tool_id.")
      }
      let after = object["after_tool_id"] ?? .string("")
      guard case let .string(afterToolId) = after, afterToolId.isEmpty || validObservedToolID(afterToolId) else {
        return (nil, "\(field).after_tool_id must be a tool id or an empty string for read-only goals.")
      }
      guard let identity = object["subject"]?.objectValue, (1...16).contains(identity.count) else {
        return (nil, "\(field).subject must be a JSON object mapping receipt JSON pointers to observed string identities, not an array or string.")
      }
      var subject: [String: String] = [:]
      for (path, value) in identity.sorted(by: { $0.key < $1.key }) {
        guard validObservedPointer(path), case let .string(observed) = value,
              !observed.trimmedForModelPlan.isEmpty, observed.utf8.count <= 4_096 else {
          return (nil, "\(field).subject[\(path)] requires a nonempty string identity. Keep numeric and boolean receipt values typed in checks; JSON syntax is valid.")
        }
        subject[path] = observed
      }
      guard let checks = object["checks"]?.objectValue, (1...16).contains(checks.count) else {
        return (nil, "\(field).checks must be a JSON object mapping receipt JSON pointers to expected scalar values, not an array or string.")
      }
      guard checks.allSatisfy({ path, value in
        guard validObservedPointer(path), !dispatchOnlyFields.contains(path.split(separator: "/").last?.lowercased() ?? "") else { return false }
        switch value {
        case .string(let text): return text.utf8.count <= 1_024
        case .int, .double, .bool: return true
        default: return false
        }
      }) else {
        return (nil, "\(field).checks must use real receipt pointers and typed scalar values; dispatch acceptance or prose is not proof.")
      }
      result.append(AgentObservedCompletion(id: id, toolId: toolId, subject: subject, checks: checks, afterToolId: afterToolId))
    }
    return (result, nil)
  }

  private static func validObservedToolID(_ value: String) -> Bool {
    value.hasPrefix("galaxyssi.") && value.utf8.count <= 256 &&
      value.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
  }

  private static func validObservedPointer(_ path: String) -> Bool {
    AgentObservedOutputFields.isValidPointer(path)
  }

  private static let dispatchOnlyFields: Set<String> = [
    "accepted", "success", "message", "summary", "text", "exit_code", "queued", "dispatched",
    "ui_changed", "request_accepted", "dispatch_attempted", "dispatch_accepted", "target_volume",
    "requested_enabled", "requested_percent", "requested_muted"
  ]

  private static func parseAction(
    request: AgentPlanRequest,
    context: AgentModelPlanParsingContext,
    json: AgentMcpJSONObject,
    index: Int,
    actionId: String,
    refs: [String: AgentModelPlanRef],
    allowCoordination: Bool,
    allowsNativeDependencies: Bool
  ) throws -> AgentAction {
    let field = "actions[\(index)]"
    let rawKind = json.string("kind").trimmedForModelPlan.uppercased()
    let isAlias = rawKind.replacingOccurrences(of: "-", with: "_") == "TASK_COMPLETE"
    let kindName = isAlias ? AgentActionKind.draftPlan.rawValue : rawKind
    guard let kind = AgentActionKind.allCases.first(where: { $0.rawValue == kindName }),
          allowedKinds.contains(kind) else {
      throw AgentModelPlanRejection(field + ".kind", "unsupported_kind", "Use an action kind advertised for this request.")
    }
    let completion = kind == .draftPlan ? completionAnswer(json) : nil
    if kind == .draftPlan && completion == nil {
      throw AgentModelPlanRejection(field, "invalid_completion", "Use the advertised completion envelope and a non-empty answer.")
    }
    guard let dependencyRefs = stringArray(json["depends_on"]) else {
      throw AgentModelPlanRejection(field + ".depends_on", "invalid_dependency",
        "Use a JSON array of earlier ref strings, or leave depends_on empty.")
    }
    guard let outputRefs = stringArray(json["use_outputs_from"]) else {
      throw AgentModelPlanRejection(field + ".use_outputs_from", "invalid_output_reference",
        "Use a JSON array of earlier ref strings. Leave use_outputs_from empty for native actions.")
    }
    if !allowCoordination && !(allowsNativeDependencies && kind == .callNativeTool) &&
        (!dependencyRefs.isEmpty || !outputRefs.isEmpty) {
      throw AgentModelPlanRejection(field + ".depends_on", "coordination_unavailable",
        "This planner does not allow dependency graphs. Remove dependency and output references.")
    }
    if !outputRefs.isEmpty && kind != .callConnector {
      throw AgentModelPlanRejection(field + ".use_outputs_from", "native_output_substitution",
        "Leave use_outputs_from empty for native actions. Order actions with depends_on and inspect actual receipts.")
    }
    if outputRefs.contains(where: { !dependencyRefs.contains($0) }) {
      throw AgentModelPlanRejection(field + ".use_outputs_from", "missing_dependency",
        "Each output reference must also appear in depends_on.")
    }
    guard let dependencyIds = resolvePriorRefs(dependencyRefs, refs: refs, currentIndex: index) else {
      let available = refs.filter { $0.value.index < index }
        .sorted { $0.value.index < $1.value.index }.map(\.key)
      let earlier = available.isEmpty ? "(none)" : available.prefix(12).joined(separator: ", ")
      let suffix = available.count > 12 ? ", ..." : ""
      throw AgentModelPlanRejection(field + ".depends_on", "invalid_dependency",
        "Use earlier ref values from this response, not action IDs, targets, tool IDs or prior batches. Available earlier refs: \(earlier)\(suffix).")
    }
    guard let outputSourceIds = resolvePriorRefs(outputRefs, refs: refs, currentIndex: index),
          let nodeRef = refs.first(where: { $0.value.actionId == actionId })?.key else {
      throw AgentModelPlanRejection(field + ".use_outputs_from", "invalid_output_reference",
        "Reference only distinct earlier actions in this response.")
    }
    guard let parameters = try resolveParameters(kind: kind, input: json.object("parameters") ?? [:],
      request: request, context: context, field: field + ".parameters") else {
      let targetField = (kind == .callConnector || kind == .controlDevice) ? ".connector_id" : ""
      throw AgentModelPlanRejection(field + ".parameters" + targetField, "unresolved_action",
        "Select an available target and use the advertised parameters for this action.")
    }

    var resolvedParameters = parameters
    resolvedParameters["node_ref"] = nodeRef
    resolvedParameters["depends_on"] = dependencyIds.joined(separator: ",")
    resolvedParameters["use_outputs_from"] = outputSourceIds.joined(separator: ",")
    let target = completion != nil ? taskCompleteTarget : resolveTarget(
      kind: kind,
      proposed: json.string("target"),
      parameters: resolvedParameters,
      request: request,
      context: context
    )
    let description = completion ?? json.string("description")
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
    context: AgentModelPlanParsingContext,
    field: String
  ) throws -> [String: String]? {
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
      if AgentInstalledAppLaunchPolicy.target(request.goal)?.explicitlyLocal == true,
         !AgentDirectNativeToolPlanner.appHandoffMatches(request.goal, package: packageName) {
        throw AgentModelPlanRejection(field + ".package", "unavailable_app_handoff",
          "Use the supported iOS bundle identifier for the exact requested app, or report that the app cannot be opened.")
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
      return try resolveNativeTool(input: input, request: request, field: field)

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
    request: AgentPlanRequest,
    field: String
  ) throws -> [String: String] {
    let toolId = input.string("tool_id").trimmedForModelPlan
    guard let descriptor = request.nativeTools.first(where: {
      $0.id == toolId && $0.availability.status == .available
    }) else {
      throw AgentModelPlanRejection(field + ".tool_id", "native_tool_unavailable",
        "Use an exact available tool ID from this request's inventory. Do not invent a replacement or change JSON syntax.")
    }
    let arguments = input.object("arguments") ?? [:]
    if toolId == AgentNativeToolAgentActionAdapter.defaultToolId(.openApp) {
      let package = (arguments["parameters"]?.objectValue ?? arguments).string("package")
      guard AgentDirectNativeToolPlanner.appHandoffMatches(request.goal, package: package) else {
        throw AgentModelPlanRejection(field + ".arguments", "unavailable_app_handoff",
          "Use a supported, exact iOS bundle identifier for the requested app. Do not guess a package or open a different app.")
      }
    }
    if toolId == AgentIOSVisibleCaptureNativeToolCatalog.microphoneRecord {
      guard case .int(let seconds) = arguments["max_duration_seconds"],
            (1...Int64(AgentIOSVisibleCaptureNativeToolCatalog.maxAudioDurationSeconds)).contains(seconds) else {
        throw AgentModelPlanRejection(field + ".arguments.max_duration_seconds", "invalid_audio_duration",
          "Use an explicit whole duration from 1 to 30 seconds. Do not invent or shorten a duration.")
      }
    }
    if toolId == AgentIOSVisibleCaptureNativeToolCatalog.cameraCapture,
       AgentDeviceMutationShortcutCoverage.prohibitsCameraCapture(request.goal) {
      throw AgentModelPlanRejection(field + ".tool_id", "photo_not_requested",
        "Opening the Camera app does not authorize taking a photo. Do not substitute capture for an app launch.")
    }
    let inputJson = AgentMcpJSONCodec.stringify(arguments)
    guard inputJson.count <= maximumNativeToolArgumentCharacters else {
      throw AgentModelPlanRejection(field + ".arguments", "arguments_too_large",
        "Keep arguments within \(maximumNativeToolArgumentCharacters) characters, splitting work if needed.")
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

  static func answerOnlyAction(_ raw: String) -> String? {
    guard let json = extractJson(raw, exact: true),
          Set(json.keys).isSubset(of: ["actions", "expected_result", "rollback_strategy"]),
          let actions = json["actions"]?.arrayValue, actions.count == 1,
          let action = actions[0].objectValue else { return nil }
    return completionAnswer(action)
  }

  private static func completionAnswer(_ action: AgentMcpJSONObject) -> String? {
    let rawKind = action.string("kind").trimmedForModelPlan.uppercased().replacingOccurrences(of: "-", with: "_")
    let alias = rawKind == "TASK_COMPLETE"
    let target = action.string("target").trimmedForModelPlan.lowercased()
    guard alias || rawKind == AgentActionKind.draftPlan.rawValue,
          target == taskCompleteTarget || (alias && target.isEmpty && action["target"]?.stringValue != nil) ||
            (alias && action["target"] == nil),
          Set(action.keys).isSubset(of: ["ref", "kind", "target", "description", "parameters", "depends_on",
                                       "use_outputs_from", "completes_goal"]),
          action["parameters"] == nil || action["parameters"]?.objectValue?.isEmpty == true,
          action["depends_on"] == nil || action["depends_on"]?.arrayValue?.isEmpty == true,
          action["use_outputs_from"] == nil || action["use_outputs_from"]?.arrayValue?.isEmpty == true
    else { return nil }
    return AgentModelDirectResponseCodec.answer(action.string("description"))
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

  private static func extractJson(_ raw: String, exact: Bool = false) -> AgentMcpJSONObject? {
    let trimmed = raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .removingPrefix("```json")
      .removingPrefix("```JSON")
      .removingPrefix("```")
      .removingSuffix("```")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if exact {
      guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return nil }
      return try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(trimmed.utf8))
    }
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

  private static func stringArray(_ value: AgentMcpJSONValue?) -> [String]? {
    guard let value else { return [] }
    guard let array = value.arrayValue, array.count <= AgentPlanExecutionBatchPolicy.maximumModelBatchActions else { return nil }
    let values = array.compactMap { $0.strictStringValue?.trimmedForModelPlan.nonEmpty }
    return values.count == array.count ? values : nil
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
