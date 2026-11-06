import Foundation

enum GuardedModelAgentPlanningResult: Equatable {
  case plan(AgentPlan)
  case directResponse(String)

  var actionPlan: AgentPlan? {
    guard case let .plan(plan) = self else { return nil }
    return plan
  }
}

enum AgentModelDirectResponseCodec {
  static func parse(_ rawResponse: String, envelopeOnly: Bool = false) -> String? {
    let normalized = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return nil }

    var unwrapped = normalized
    for prefix in ["```json", "```JSON", "```"] where unwrapped.hasPrefix(prefix) {
      unwrapped.removeFirst(prefix.count)
      break
    }
    if unwrapped.hasSuffix("```") {
      unwrapped.removeLast(3)
    }
    unwrapped = unwrapped.trimmingCharacters(in: .whitespacesAndNewlines)
    guard unwrapped.hasPrefix("{") else {
      return !envelopeOnly && answer(unwrapped) != nil ? answer(normalized) : nil
    }
    guard let data = unwrapped.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let json = object as? [String: Any],
          Set(json.keys).isSubset(of: ["disposition", "final_response", "presentation", "rich_output", "completion_requirements"]),
          let disposition = json["disposition"] as? String,
          disposition.caseInsensitiveCompare("respond") == .orderedSame,
          let response = json["final_response"] as? String else {
      return nil
    }
    if let requirements = json["completion_requirements"] {
      guard let scope = requirements as? [String: Any],
            scope["publication"] == nil || (scope["publication"] as? String) == "none",
            scope["phone_linux"] == nil || (scope["phone_linux"] as? Bool) == false else { return nil }
    }
    if json["presentation"] != nil || json["rich_output"] != nil || json["completion_requirements"] != nil {
      guard unwrapped.utf8.count <= AgentRichContentCodec.maximumSerializedSize,
            response.isEmpty || answer(response) != nil else { return nil }
      return unwrapped
    }
    return answer(response)
  }

  static func answer(_ value: String) -> String? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.utf8.count <= 32_768 else { return nil }
    let lower = text.lowercased()
    let arrayObject = lower.hasPrefix("[") && lower.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
    guard !lower.hasPrefix("{"), !arrayObject, !CloudSupervisedResearch.isControlPayload(text),
          !["<tool_call", "<tool_use", "<function_call", "<invoke", "recipient=functions.",
            "[tool_call", "\"tool_calls\"", "\"actions\":"].contains(where: lower.contains) else { return nil }
    return text
  }
}

struct GuardedModelAgentPlanner {
  var provider: AgentModelPlanningProviding
  var modelProfile: String
  var voiceCorrectionJournal: VoiceCorrectionJournal?

  init(
    provider: AgentModelPlanningProviding,
    modelProfile: String = "model",
    voiceCorrectionJournal: VoiceCorrectionJournal? = nil
  ) {
    self.provider = provider
    self.modelProfile = modelProfile.trimmingCharacters(in: .whitespacesAndNewlines)
    self.voiceCorrectionJournal = voiceCorrectionJournal
  }

  func plan(
    request: AgentModelPlanningPromptRequest,
    settings: AgentModelPlannerSettings,
    safetySettings: AgentSafetySettings = .default,
    fallbackPlan: AgentPlan
  ) async -> AgentPlan {
    let result = await planOrRespond(
      request: request,
      settings: settings,
      safetySettings: safetySettings,
      fallbackPlan: fallbackPlan
    )
    switch result {
    case let .plan(plan):
      return plan
    case .directResponse:
      return fallbackPlan.copyForGuardedPlanner(
        profile: "rule-based-direct-response-unsupported",
        rationale: "The caller did not accept a direct model response; deterministic fallback used."
      )
    }
  }

  func planOrRespond(
    request: AgentModelPlanningPromptRequest,
    settings: AgentModelPlannerSettings,
    safetySettings: AgentSafetySettings = .default,
    fallbackPlan: AgentPlan,
    admit: ((AgentPlan) -> AgentModelPlanRejection?)? = nil
  ) async -> GuardedModelAgentPlanningResult {
    let normalizedSettings = settings.normalized
    var fallback = fallbackPlan
    if request.phoneOwnsExecution {
      fallback = AgentPlanFactory.actions(request: request.planRequest, [])
      fallback.actions = []
      fallback.validation = AgentPlanValidator.validate(fallback)
    }
    let replanning = !request.parsingContext.replanReason
      .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

    if fallback.plannerProfile.hasPrefix("specialized-adapter:") {
      return .plan(fallback)
    }
    if !request.phoneOwnsExecution, !replanning,
       safetySettings.localActionsAllowed,
       safetySettings.deviceControlAllowed,
       let directNativeToolPlan = AgentDirectNativeToolPlanner.shortcutPlan(
         request: request.planRequest,
         hasAttachments: request.hasAttachments || request.conversationContext.hasAttachments
       ), admit?(directNativeToolPlan) == nil {
      return .plan(directNativeToolPlan.withDirectConversationContext(
        request: request,
        executionMode: fallback.executionMode
      ))
    }
    let onDeviceProvider = provider is LocalModelAgentPlanningProvider
    if !normalizedSettings.enabled || (!onDeviceProvider && !safetySettings.connectorCallsAllowed) {
      return .plan(fallback.copyForGuardedPlanner(profile: "rule-based-local"))
    }
    if request.requirements.localOnly && !onDeviceProvider {
      return .plan(fallback.copyForGuardedPlanner(
        profile: "rule-based-private",
        rationale: "Cloud planning was skipped because the task requires a private route."
      ))
    }
    if !request.phoneOwnsExecution, !replanning,
      (request.requirements.mode == .fast || request.requirements.mode == .economy) &&
      !fallback.actions.contains(where: { $0.kind == .draftPlan }) {
      return .plan(fallback.copyForGuardedPlanner(
        profile: "rule-based-\(request.requirements.mode.rawValue.lowercased())",
        rationale: "A deterministic route avoided an unnecessary planning-model call."
      ))
    }
    if !onDeviceProvider && (hasSensitivePlannerContext(request.planRequest.screen) ||
      hasSensitivePlannerGoal(request.planRequest.goal)) {
      return .plan(fallback.copyForGuardedPlanner(
        profile: "rule-based-sensitive-fallback",
        rationale: "Model planning skipped because the current iOS context is sensitive."
      ))
    }

    let nativeSafeRequest = request.withNativeTools(safeNativeTools(for: request))
    let screenEnrichedRequest = nativeSafeRequest.withScreenElements()
    let safeRequest = voiceCorrectionJournal.map {
      VoiceCorrectionContextProvider.merge(
        request: screenEnrichedRequest,
        correctionJournal: $0
      ).request
    } ?? screenEnrichedRequest
    let prompt = AgentModelPlanningPrompt.build(request: safeRequest, settings: normalizedSettings)
    var rejection: AgentModelPlanRejection?
    var shapeRepair: (diagnostic: String, original: AgentMcpJSONObject)?
    for _ in 0...1 {
      guard !Task.isCancelled else { break }
      let repair = rejection
      var invocation = AgentModelPlanningInvocation(
        systemPrompt: AgentModelPlanningPrompt.systemPrompt,
        prompt: repair.map { prompt + "\n\n" + $0.repairInstruction } ?? prompt,
        nativeTools: safeRequest.planRequest.nativeTools,
        request: safeRequest
      )
      if let shapeRepair {
        invocation = AgentModelPlanningInvocation(
          systemPrompt: "Repair JSON structure only. Do not use tools, take actions, or invent observations. Return one JSON object.",
          prompt: prompt + "\nRepair only completion_requirements.outcomes in the following invalid plan. Preserve all actions and other fields verbatim. \(shapeRepair.diagnostic)\nInvalid plan data:\n\(AgentMcpJSONCodec.stringify(shapeRepair.original))",
          nativeTools: [], request: safeRequest.withNativeTools([])
        )
        invocation.completionShapeRepairOnly = true
      }
      let raw: String
      do {
        if repair == nil || shapeRepair != nil { raw = try await provider.rawPlan(invocation: invocation) }
        else { raw = try await provider.repairPlan(invocation: invocation) }
      } catch {
        if repair != nil { break }
        return .plan(fallback.copyForGuardedPlanner(
          profile: "rule-based-model-error",
          rationale: "Model planning failed; the deterministic local planner was used."
        ))
      }
      guard !Task.isCancelled else { break }
      if safeRequest.phoneOwnsExecution && !AgentModelPlanParser.permitsPhoneExecutionSite(raw) {
        return .plan(fallback.copyForGuardedPlanner(profile: "rule-based-phone-execution-rejected"))
      }
      if let shapeRepair {
        guard AgentModelPlanParser.repairedOnlyCompletionShape(raw, original: shapeRepair.original) else {
          return .plan(fallback.copyForGuardedPlanner(profile: "rule-based-invalid-completion-shape"))
        }
      } else if repair == nil, safeRequest.phoneOwnsExecution,
                let invalidShape = AgentModelPlanParser.completionShapeRepair(raw) {
        shapeRepair = invalidShape
        rejection = .init("completion_requirements.outcomes", "invalid_completion_shape", invalidShape.diagnostic)
        continue
      }
      if repair == nil, safeRequest.allowsDirectResponse,
         let response = AgentModelDirectResponseCodec.parse(raw, envelopeOnly: safeRequest.phoneOwnsExecution)
           ?? AgentModelPlanParser.answerOnlyAction(raw) {
        return .directResponse(response)
      }
      switch AgentModelPlanParser.parseWithDiagnostics(
        request: safeRequest.planRequest, raw: raw, settings: normalizedSettings, context: safeRequest.parsingContext
      ) {
      case .failure(let invalid):
        rejection = invalid
      case .success(var parsed):
        guard !request.phoneOwnsExecution || parsed.actions.allSatisfy({
          $0.kind == .callNativeTool || AgentRollingPlanPolicy.closesFromVerifiedEvidence($0)
        }) else {
          return .plan(fallback.copyForGuardedPlanner(profile: "rule-based-phone-execution-rejected"))
        }
        guard AgentPhoneRuntimePolicy.acceptsModelPlan(goal: request.planRequest.goal, actions: parsed.actions) else {
          rejection = .init("actions", "phone_runtime_route",
            "This route cannot execute the proposed phone-runtime actions. Use the tools advertised for the selected route.")
          continue
        }
        parsed = AgentActionRiskHardener.enforce(plan: parsed)
        parsed.validation = AgentPlanValidator.validate(parsed)
        guard parsed.validation.valid else {
          rejection = .init("actions", "hardened_plan_validation", "Keep all required confirmations and use valid actions for this route.")
          continue
        }
        if let invalid = admit?(parsed) {
          rejection = invalid
          continue
        }
        parsed.plannerProfile = "guarded-model:\(modelProfile.prefixStringForGuardedPlanner(80).ifBlankForGuardedPlanner("model"))"
        parsed.routeRationale = "A configured model proposed this plan; all actions were resolved and validated locally."
        return .plan(parsed)
      }
    }
    if rejection?.code == "phone_runtime_route" {
      return .plan(fallback.copyForGuardedPlanner(
        profile: "rule-based-phone-runtime-rejected",
        rationale: "The model proposed phone runtime tools outside an eligible on-device task; the deterministic connector route was kept."
      ))
    }
    return .plan(fallback.copyForGuardedPlanner(
      profile: "rule-based-invalid-model-plan",
      rationale: "Model output failed local ActionPlan validation; deterministic fallback used."
    ))
  }

  private func safeNativeTools(
    for request: AgentModelPlanningPromptRequest
  ) -> [AgentNativeToolDescriptor] {
    let ordinary = standardNativeTools(for: request)
    guard request.phoneOwnsExecution else { return ordinary }
    let ordinaryIDs = Set(ordinary.map(\.id))
    let additional = request.planRequest.nativeTools.filter {
      !ordinaryIDs.contains($0.id) && $0.availability.status == .available &&
        $0.risk != .high && $0.risk != .blocked &&
        AgentPhoneRuntimePolicy.directPhoneActionTools.contains($0.id)
    }
    return (ordinary + additional).sorted { $0.id < $1.id }
  }

  private func standardNativeTools(
    for request: AgentModelPlanningPromptRequest
  ) -> [AgentNativeToolDescriptor] {
    let allowsPhoneRuntimeTools = request.allowsPhoneRuntimeTools &&
      AgentPhoneRuntimePolicy.shouldUsePhoneRuntime(goal: request.planRequest.goal)
    let isResearch = AgentResearchCapabilityDiscovery.isResearchRequest(request)
    return request.planRequest.nativeTools
      .filter { descriptor in
        descriptor.availability.status == .available &&
        descriptor.risk == .low &&
        (descriptor.requiredConsents.allSatisfy { !$0.required } ||
          (isResearch && AgentResearchCapabilityDiscovery.hasOnlyResearchConsent(descriptor))) &&
          (allowsPhoneRuntimeTools || !AgentPhoneRuntimePolicy.isPhoneRuntimeTool(descriptor.id))
      }
      .sorted { $0.id < $1.id }
  }

  private func hasSensitivePlannerContext(_ screen: AgentScreenContext) -> Bool {
    screen.sensitiveFlagCount > 0 ||
      !screen.sensitiveFlags.isEmpty ||
      !screen.clipboard.sensitiveFlags.isEmpty ||
      !screen.notifications.sensitiveFlags.isEmpty ||
      screen.notifications.items.contains { !$0.sensitiveFlags.isEmpty }
  }

  private func hasSensitivePlannerGoal(_ goal: String) -> Bool {
    let normalized = goal.lowercased()
    return sensitivePlannerTerms.contains { normalized.contains($0) }
  }

  private let sensitivePlannerTerms = [
    "password", "passcode", "verification code", "otp", "2fa", "api key", "secret key",
    "private key", "seed phrase", "bank card", "credit card", "cvv",
    "\u{5bc6}\u{7801}", "\u{9a8c}\u{8bc1}\u{7801}", "\u{79c1}\u{94a5}",
    "\u{94f6}\u{884c}\u{5361}", "\u{652f}\u{4ed8}"
  ]
}

private extension AgentModelPlanningPromptRequest {
  func withNativeTools(_ nativeTools: [AgentNativeToolDescriptor]) -> AgentModelPlanningPromptRequest {
    var copy = self
    copy.planRequest.nativeTools = nativeTools
    return copy
  }

  func withScreenElements() -> AgentModelPlanningPromptRequest {
    var nextContext = parsingContext
    if nextContext.clickableElements.isEmpty {
      nextContext.clickableElements = planRequest.screen.clickableElements
    }
    if nextContext.inputFields.isEmpty {
      nextContext.inputFields = planRequest.screen.inputFields
    }
    if nextContext.focusedInputField == nil {
      nextContext.focusedInputField = planRequest.screen.focusedInputField
    }
    var copy = self
    copy.parsingContext = nextContext
    return copy
  }
}

private extension AgentPlan {
  func copyForGuardedPlanner(profile: String, rationale: String = "") -> AgentPlan {
    var copy = self
    copy.plannerProfile = profile
    if !rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      copy.routeRationale = rationale
    }
    copy.validation = AgentPlanValidator.validate(copy)
    return copy
  }
}

private extension String {
  func prefixStringForGuardedPlanner(_ count: Int) -> String {
    String(prefix(max(count, 0)))
  }

  func ifBlankForGuardedPlanner(_ fallback: String) -> String {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
  }
}
