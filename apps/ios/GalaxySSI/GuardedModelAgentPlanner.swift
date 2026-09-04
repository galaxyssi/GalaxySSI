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
  static func parse(_ rawResponse: String) -> String? {
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
    guard unwrapped.hasPrefix("{") else { return normalized }
    guard let data = unwrapped.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let json = object as? [String: Any],
          let disposition = json["disposition"] as? String,
          disposition.caseInsensitiveCompare("respond") == .orderedSame,
          let response = json["final_response"] as? String else {
      return nil
    }
    let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
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
    fallbackPlan: AgentPlan
  ) async -> GuardedModelAgentPlanningResult {
    let normalizedSettings = settings.normalized
    let fallback = fallbackPlan
    let replanning = !request.parsingContext.replanReason
      .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

    if fallback.plannerProfile.hasPrefix("specialized-adapter:") {
      return .plan(fallback)
    }
    if !replanning,
       safetySettings.localActionsAllowed,
       safetySettings.deviceControlAllowed,
       let directNativeToolPlan = AgentDirectNativeToolPlanner.plan(request: request.planRequest) {
      return .plan(directNativeToolPlan.withDirectConversationContext(
        request: request,
        executionMode: fallback.executionMode
      ))
    }
    if !normalizedSettings.enabled || !safetySettings.connectorCallsAllowed {
      return .plan(fallback.copyForGuardedPlanner(profile: "rule-based-local"))
    }
    if request.requirements.localOnly {
      return .plan(fallback.copyForGuardedPlanner(
        profile: "rule-based-private",
        rationale: "Cloud planning was skipped because the task requires a private route."
      ))
    }
    if !replanning,
      (request.requirements.mode == .fast || request.requirements.mode == .economy) &&
      !fallback.actions.contains(where: { $0.kind == .draftPlan }) {
      return .plan(fallback.copyForGuardedPlanner(
        profile: "rule-based-\(request.requirements.mode.rawValue.lowercased())",
        rationale: "A deterministic route avoided an unnecessary planning-model call."
      ))
    }
    if hasSensitivePlannerContext(request.planRequest.screen) ||
      hasSensitivePlannerGoal(request.planRequest.goal) {
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
    let raw: String
    do {
      raw = try await provider.rawPlan(invocation: AgentModelPlanningInvocation(
        systemPrompt: AgentModelPlanningPrompt.systemPrompt,
        prompt: prompt,
        nativeTools: safeRequest.planRequest.nativeTools,
        request: safeRequest
      ))
    } catch {
      return .plan(fallback.copyForGuardedPlanner(
        profile: "rule-based-model-error",
        rationale: "Model planning failed; the deterministic local planner was used."
      ))
    }

    if safeRequest.allowsDirectResponse,
       let response = AgentModelDirectResponseCodec.parse(raw) {
      return .directResponse(response)
    }

    guard var parsed = AgentModelPlanParser.parse(
      request: safeRequest.planRequest,
      raw: raw,
      settings: normalizedSettings,
      context: safeRequest.parsingContext
    ) else {
      return .plan(fallback.copyForGuardedPlanner(
        profile: "rule-based-invalid-model-plan",
        rationale: "Model output failed local ActionPlan validation; deterministic fallback used."
      ))
    }

    guard AgentPhoneRuntimePolicy.acceptsModelPlan(
      goal: request.planRequest.goal,
      actions: parsed.actions
    ) else {
      return .plan(fallback.copyForGuardedPlanner(
        profile: "rule-based-phone-runtime-rejected",
        rationale: "The model proposed phone runtime tools outside an eligible on-device task; the deterministic connector route was kept."
      ))
    }

    parsed = AgentActionRiskHardener.enforce(plan: parsed)
    parsed.plannerProfile = "guarded-model:\(modelProfile.prefixStringForGuardedPlanner(80).ifBlankForGuardedPlanner("model"))"
    parsed.routeRationale = "A configured model proposed this plan; all actions were resolved and validated locally."
    parsed.validation = AgentPlanValidator.validate(parsed)
    return parsed.validation.valid
      ? .plan(parsed)
      : .plan(fallback.copyForGuardedPlanner(
        profile: "rule-based-invalid-model-plan",
        rationale: "Model output failed local ActionPlan validation after hardening; deterministic fallback used."
      ))
  }

  private func safeNativeTools(
    for request: AgentModelPlanningPromptRequest
  ) -> [AgentNativeToolDescriptor] {
    let allowsPhoneRuntimeTools = request.allowsPhoneRuntimeTools &&
      AgentPhoneRuntimePolicy.shouldUsePhoneRuntime(goal: request.planRequest.goal)
    return request.planRequest.nativeTools
      .filter { descriptor in
        descriptor.availability.status == .available &&
        descriptor.risk == .low &&
        descriptor.requiredConsents.allSatisfy { !$0.required } &&
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
    var nextPlanRequest = planRequest
    nextPlanRequest.nativeTools = nativeTools
    return AgentModelPlanningPromptRequest(
      planRequest: nextPlanRequest,
      parsingContext: parsingContext,
      conversationContext: conversationContext,
      executionHistory: executionHistory,
      globalRealtimeContext: globalRealtimeContext,
      requirements: requirements,
      hasAttachments: hasAttachments,
      allowsPhoneRuntimeTools: allowsPhoneRuntimeTools,
      allowsDirectResponse: allowsDirectResponse
    )
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
    return AgentModelPlanningPromptRequest(
      planRequest: planRequest,
      parsingContext: nextContext,
      conversationContext: conversationContext,
      executionHistory: executionHistory,
      globalRealtimeContext: globalRealtimeContext,
      requirements: requirements,
      hasAttachments: hasAttachments,
      allowsPhoneRuntimeTools: allowsPhoneRuntimeTools,
      allowsDirectResponse: allowsDirectResponse
    )
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
