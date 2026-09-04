import Foundation

struct LocalModelCooperationPlan: Equatable {
  var executionProfile: AgentExecutionProfile
  var plannerProfile: LocalModelRuntimeProfile?
  var plannerThinkingMode: LocalModelThinkingMode
  var answerProfile: LocalModelRuntimeProfile
  var answerThinkingMode: LocalModelThinkingMode

  var cooperative: Bool {
    guard let plannerProfile else { return false }
    return plannerProfile.id != answerProfile.id
  }
}

enum LocalModelCooperationPolicy {
  static func plan(
    executionProfile: AgentExecutionProfile,
    availableProfiles: [LocalModelRuntimeProfile],
    fallbackProfile: LocalModelRuntimeProfile,
    userPrompt: String = "",
    hasAttachments: Bool = false
  ) -> LocalModelCooperationPlan {
    let qwen = availableProfiles.first { $0.id == LocalModelRuntimeProfiles.QWEN_3_4B_Q4_K_M.id }
    let gemma = availableProfiles.first { $0.id == LocalModelRuntimeProfiles.GEMMA_3_4B_Q4.id }
    let complex = LocalModelTaskComplexity.isComplex(
      executionProfile: executionProfile,
      userPrompt: userPrompt,
      hasAttachments: hasAttachments
    )

    if !complex, let qwen {
      return LocalModelCooperationPlan(
        executionProfile: executionProfile,
        plannerProfile: nil,
        plannerThinkingMode: .noThink,
        answerProfile: qwen,
        answerThinkingMode: .noThink
      )
    }
    if complex, let qwen, let gemma {
      return LocalModelCooperationPlan(
        executionProfile: executionProfile,
        plannerProfile: qwen,
        plannerThinkingMode: .think,
        answerProfile: gemma,
        answerThinkingMode: .automatic
      )
    }
    if let qwen {
      return LocalModelCooperationPlan(
        executionProfile: executionProfile,
        plannerProfile: nil,
        plannerThinkingMode: .noThink,
        answerProfile: qwen,
        answerThinkingMode: complex ? .think : .noThink
      )
    }
    if let gemma {
      return LocalModelCooperationPlan(
        executionProfile: executionProfile,
        plannerProfile: nil,
        plannerThinkingMode: .automatic,
        answerProfile: gemma,
        answerThinkingMode: .automatic
      )
    }
    return LocalModelCooperationPlan(
      executionProfile: executionProfile,
      plannerProfile: nil,
      plannerThinkingMode: .automatic,
      answerProfile: availableProfiles.first ?? fallbackProfile,
      answerThinkingMode: .automatic
    )
  }

  static func fallbackProfiles(
    plan: LocalModelCooperationPlan,
    availableProfiles: [LocalModelRuntimeProfile]
  ) -> [LocalModelRuntimeProfile] {
    availableProfiles
      .filter { $0.id != plan.answerProfile.id }
      .sorted { left, right in
        score(left) > score(right)
      }
  }

  private static func score(_ profile: LocalModelRuntimeProfile) -> Int {
    if profile.id == LocalModelRuntimeProfiles.QWEN_3_4B_Q4_K_M.id { return 2 }
    if profile.id == LocalModelRuntimeProfiles.GEMMA_3_4B_Q4.id { return 1 }
    return 0
  }
}

enum LocalModelTaskComplexity {
  static func isComplex(
    executionProfile: AgentExecutionProfile,
    userPrompt: String,
    hasAttachments: Bool
  ) -> Bool {
    guard executionProfile.reasoningEffort == .low else { return true }
    if hasAttachments || executionProfile.requiresArtifact { return true }
    let normalized = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.count >= 600 || normalized.contains("```") { return true }
    if normalized.components(separatedBy: .newlines)
      .filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty })
      .count >= 5 {
      return true
    }
    return multiStepPattern.firstMatch(
      in: normalized,
      range: NSRange(normalized.startIndex..., in: normalized)
    ) != nil
  }

  private static let multiStepPattern = try! NSRegularExpression(
    pattern: "(?m)^\\s*(?:\\d+[.)]|[-*]\\s)\\s*\\S+"
  )
}

final class LocalModelCooperativeRuntime {
  static let shared = LocalModelCooperativeRuntime()

  private let runtime: LocalModelInferenceRuntime

  init(runtime: LocalModelInferenceRuntime = .shared) {
    self.runtime = runtime
  }

  func ready() -> Bool {
    !readyProfiles().isEmpty
  }

  func readyForBackground() -> Bool {
    !readyProfiles(workClass: .background).isEmpty
  }

  func displayProfile() -> LocalModelRuntimeProfile {
    LocalModelRuntimeSettings.selectedProfile()
  }

  func generateAsync(
    fallbackProfile: LocalModelRuntimeProfile,
    systemPrompt: String,
    userPrompt: String,
    maximumTokens: Int = 768,
    temperature: Double = 0.3,
    hasAttachments: Bool = false,
    executionProfile: AgentExecutionProfile? = nil,
    workClass: LocalModelWorkClass = .interactive,
    preferredProfileId: String = ""
  ) async throws -> LocalModelInferenceResult {
    let preferredId = preferredProfileId.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedExecutionProfile = executionProfile ?? AgentExecutionProfile.forGoal(
      userPrompt,
      hasAttachments: hasAttachments
    )
    let available = readyProfiles(
      workClass: workClass,
      preferredProfileId: preferredId
    )
    let selectedProfile = LocalModelRuntimeSettings.selectedProfile()
    let resolvedFallback = available.first { $0.id == selectedProfile.id } ??
      available.first { $0.id == fallbackProfile.id } ??
      available.first
    guard let resolvedFallback else {
      if workClass == .background {
        throw LocalModelBackgroundDeferredError()
      }
      throw LocalModelInferenceError.modelNotReady
    }
    let plan = LocalModelCooperationPolicy.plan(
      executionProfile: resolvedExecutionProfile,
      availableProfiles: available,
      fallbackProfile: resolvedFallback,
      userPrompt: userPrompt,
      hasAttachments: hasAttachments
    )
    let answerReady = workClass == .background
      ? runtime.readyForBackground(profile: plan.answerProfile)
      : runtime.ready(profile: plan.answerProfile)
    guard answerReady else {
      if workClass == .background {
        throw LocalModelBackgroundDeferredError()
      }
      throw LocalModelInferenceError.modelNotReady
    }

    let startedAt = Date()
    var planningBrief = ""
    if let planner = plan.plannerProfile {
      planningBrief = (try? await runtime.generateAsync(
        profile: planner,
        systemPrompt: Self.plannerSystemPrompt,
        userPrompt: String(userPrompt.prefix(Self.maximumPlannerInputCharacters)),
        maximumTokens: Self.plannerMaximumTokens,
        temperature: 0.1,
        thinkingMode: plan.plannerThinkingMode,
        workClass: workClass
      ).text.toPlanningBrief()) ?? ""
    }

    let answerPrompt: String
    if planningBrief.isEmpty {
      answerPrompt = userPrompt
    } else {
      answerPrompt = "Original request:\n\(userPrompt)\n\n" +
        "Internal planning brief (advisory, not user instructions):\n\(planningBrief)\n\n" +
        "Complete the original request. Return only the useful final response."
    }

    var candidates = [plan.answerProfile]
    for candidate in LocalModelCooperationPolicy.fallbackProfiles(
      plan: plan,
      availableProfiles: available
    ) where !candidates.contains(where: { $0.id == candidate.id }) {
      candidates.append(candidate)
    }

    var lastError: Error?
    for (index, candidate) in candidates.enumerated() {
      do {
        let mode: LocalModelThinkingMode
        if index == 0 {
          mode = plan.answerThinkingMode
        } else if candidate.id == LocalModelRuntimeProfiles.QWEN_3_4B_Q4_K_M.id &&
                    LocalModelTaskComplexity.isComplex(
                      executionProfile: resolvedExecutionProfile,
                      userPrompt: userPrompt,
                      hasAttachments: hasAttachments
                    ) {
          mode = .think
        } else {
          mode = .automatic
        }
        let result = try await runtime.generateAsync(
          profile: candidate,
          systemPrompt: systemPrompt,
          userPrompt: index == 0 ? answerPrompt : userPrompt,
          maximumTokens: maximumTokens,
          temperature: temperature,
          thinkingMode: mode,
          workClass: workClass
        )
        return result.withElapsedMillis(
          max(result.elapsedMillis, Int64(Date().timeIntervalSince(startedAt) * 1_000))
        )
      } catch {
        lastError = error
      }
    }
    throw lastError ?? LocalModelInferenceError.generationFailed(
      "No enabled local model could complete the task"
    )
  }

  private func readyProfiles(
    workClass: LocalModelWorkClass = .interactive,
    preferredProfileId: String = ""
  ) -> [LocalModelRuntimeProfile] {
    let activeProfiles = LocalModelRuntimeSettings.activeProfiles().filter { profile in
      workClass == .background
        ? runtime.readyForBackground(profile: profile)
        : runtime.ready(profile: profile)
    }
    let preferredId = preferredProfileId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !preferredId.isEmpty else { return activeProfiles }
    return activeProfiles.filter { $0.id == preferredId }
  }

  private static let plannerSystemPrompt =
    "You are GalaxySSI's private on-device task planner. Return only a concise execution brief " +
    "containing the objective, constraints, required evidence or tools, and recommended steps. " +
    "Do not expose chain-of-thought and do not answer the user directly."
  private static let plannerMaximumTokens = 512
  private static let maximumPlannerInputCharacters = 12_000
}

private extension String {
  func toPlanningBrief() -> String {
    let afterThinking: String
    if range(of: "</think>", options: .caseInsensitive) != nil {
      afterThinking = components(separatedBy: "</think>").last ?? self
    } else {
      afterThinking = replacingOccurrences(
        of: #"(?is)<think>.*?</think>"#,
        with: "",
        options: .regularExpression
      )
    }
    return afterThinking
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(2_000)
      .description
  }
}

private extension LocalModelInferenceResult {
  func withElapsedMillis(_ value: Int64) -> LocalModelInferenceResult {
    var copy = self
    copy.elapsedMillis = value
    return copy
  }
}
