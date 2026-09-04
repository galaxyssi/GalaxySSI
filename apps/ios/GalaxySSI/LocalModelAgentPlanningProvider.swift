import Foundation

struct LocalModelAgentPlanningProvider: AgentModelPlanningProviding {
  var runtime: LocalModelInferenceRuntime
  var profile: LocalModelRuntimeProfile

  init(
    runtime: LocalModelInferenceRuntime = .shared,
    profile: LocalModelRuntimeProfile = LocalModelRuntimeSettings.selectedProfile()
  ) {
    self.runtime = runtime
    self.profile = profile
  }

  func rawPlan(invocation: AgentModelPlanningInvocation) async throws -> String {
    let requirements = AgentTaskRequirementAnalyzer.analyze(invocation.prompt)
    let workClass: LocalModelWorkClass = requirements.executionHorizon == .interactive
      ? .interactive
      : .background
    let ready = workClass == .background
      ? runtime.readyForBackground(profile: profile)
      : runtime.ready(profile: profile)
    guard ready else {
      throw AgentModelPlanningProviderError.unavailable(
        "The selected local model is not installed or failed verification"
      )
    }

    do {
      let result = try await runtime.generateAsync(
        profile: profile,
        systemPrompt: invocation.systemPrompt,
        userPrompt: invocation.prompt,
        maximumTokens: 4_096,
        temperature: 0.2,
        workClass: workClass
      )
      return result.text
    } catch {
      throw AgentModelPlanningProviderError.unavailable(error.localizedDescription)
    }
  }
}
