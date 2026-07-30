import Foundation

struct GuardedModelAgentPlanner {
  var provider: AgentModelPlanningProviding
  var modelProfile: String

  init(
    provider: AgentModelPlanningProviding,
    modelProfile: String = "model"
  ) {
    self.provider = provider
    self.modelProfile = modelProfile.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func plan(
    request: AgentModelPlanningPromptRequest,
    settings: AgentModelPlannerSettings,
    safetySettings: AgentSafetySettings = .default,
    fallbackPlan: AgentPlan
  ) async -> AgentPlan {
    let normalizedSettings = settings.normalized
    let fallback = fallbackPlan

    if fallback.plannerProfile.hasPrefix("specialized-adapter:") {
      return fallback
    }
    if !normalizedSettings.enabled || !safetySettings.connectorCallsAllowed {
      return fallback.copyForGuardedPlanner(profile: "rule-based-local")
    }
    if request.requirements.localOnly {
      return fallback.copyForGuardedPlanner(
        profile: "rule-based-private",
        rationale: "Cloud planning was skipped because the task requires a private route."
      )
    }
    if (request.requirements.mode == .fast || request.requirements.mode == .economy) &&
      !fallback.actions.contains(where: { $0.kind == .draftPlan }) {
      return fallback.copyForGuardedPlanner(
        profile: "rule-based-\(request.requirements.mode.rawValue.lowercased())",
        rationale: "A deterministic route avoided an unnecessary planning-model call."
      )
    }
    if hasSensitivePlannerContext(request.planRequest.screen) ||
      hasSensitivePlannerGoal(request.planRequest.goal) {
      return fallback.copyForGuardedPlanner(
        profile: "rule-based-sensitive-fallback",
        rationale: "Model planning skipped because the current iOS context is sensitive."
      )
    }

    let safeRequest = request.withNativeTools(safeNativeTools(for: request))
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
      return fallback.copyForGuardedPlanner(
        profile: "rule-based-model-error",
        rationale: "Model planning failed; the deterministic local planner was used."
      )
    }

    guard var parsed = AgentModelPlanParser.parse(
      request: safeRequest.planRequest,
      raw: raw,
      settings: normalizedSettings,
      context: safeRequest.parsingContext
    ) else {
      return fallback.copyForGuardedPlanner(
        profile: "rule-based-invalid-model-plan",
        rationale: "Model output failed local ActionPlan validation; deterministic fallback used."
      )
    }

    parsed = AgentActionRiskHardener.enforce(plan: parsed)
    parsed.plannerProfile = "guarded-model:\(modelProfile.prefixStringForGuardedPlanner(80).ifBlankForGuardedPlanner("model"))"
    parsed.routeRationale = "A configured model proposed this plan; all actions were resolved and validated locally."
    parsed.validation = AgentPlanValidator.validate(parsed)
    return parsed.validation.valid ? parsed : fallback.copyForGuardedPlanner(
      profile: "rule-based-invalid-model-plan",
      rationale: "Model output failed local ActionPlan validation after hardening; deterministic fallback used."
    )
  }

  private func safeNativeTools(
    for request: AgentModelPlanningPromptRequest
  ) -> [AgentNativeToolDescriptor] {
    request.planRequest.nativeTools
      .filter { descriptor in
        descriptor.availability.status == .available &&
          descriptor.risk == .low &&
          descriptor.requiredConsents.allSatisfy { !$0.required } &&
          (request.allowsPhoneRuntimeTools || !Self.isPhoneRuntimeTool(descriptor.id))
      }
      .sorted { $0.id < $1.id }
  }

  private static func isPhoneRuntimeTool(_ id: String) -> Bool {
    id.hasPrefix("signalasi.runtime.") || id.hasPrefix("signalasi.workspace.")
  }

  private func hasSensitivePlannerContext(_ screen: AgentScreenContext) -> Bool {
    screen.sensitiveFlagCount > 0
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
      requirements: requirements,
      hasAttachments: hasAttachments,
      allowsPhoneRuntimeTools: allowsPhoneRuntimeTools
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
