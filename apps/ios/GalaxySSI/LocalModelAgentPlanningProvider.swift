import Foundation

struct LocalModelAgentPlanningProvider: AgentModelPlanningProviding {
  var runtime: LocalModelInferenceRuntime
  var profile: LocalModelRuntimeProfile
  var receiptStore: AgentTurnReceiptStore?
  var receiptOwner: String

  init(
    runtime: LocalModelInferenceRuntime = .shared,
    profile: LocalModelRuntimeProfile = LocalModelRuntimeSettings.selectedProfile(),
    receiptStore: AgentTurnReceiptStore? = nil,
    receiptOwner: String = ""
  ) {
    self.runtime = runtime
    self.profile = profile
    self.receiptStore = receiptStore
    self.receiptOwner = receiptOwner
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
        workClass: workClass,
        taskId: invocation.request.executionTurnId.ifBlank(
          invocation.request.conversationContext.conversationId
        )
      )
      receiptStore?.localModel(.init(owner: receiptOwner, conversation: invocation.request.conversationContext.conversationId,
        turn: invocation.request.executionTurnId), profile: result.profileId)
      return result.text
    } catch {
      throw AgentModelPlanningProviderError.unavailable(error.localizedDescription)
    }
  }
}
