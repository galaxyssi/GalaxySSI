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

    let offerReview: Bool
    if invocation.request.permitsAnswerOnlyResponse && !invocation.request.hasAttachments {
      offerReview = await AgentLocalTeamReviewWindow.request(owner: receiptOwner,
        conversation: invocation.request.conversationContext.conversationId, turn: invocation.request.executionTurnId,
        objective: invocation.request.planRequest.goal, profile: profile.id)
    } else { offerReview = false }
    do {
      let result = try await runtime.generateAsync(
        profile: profile,
        systemPrompt: invocation.systemPrompt + (offerReview ? "\n\n" + AgentLocalTeamReviewProposal.plannerInstruction : ""),
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
      if var object = AgentLocalTeamReviewProposal.envelope(result.text), object[AgentLocalTeamReviewProposal.field] != nil {
        guard Set(object.keys).isSubset(of: ["disposition", "final_response", AgentLocalTeamReviewProposal.field]),
          object["disposition"] == .string("respond"), object["final_response"]?.strictStringValue?.isBlank == false else {
          throw AgentModelPlanningProviderError.unavailable("A review proposal cannot contain an action or override its scope")
        }
        if offerReview, result.profileId == profile.id, AgentLocalTeamReviewProposal.proposed(object, planner: true) {
          await AgentLocalTeamReviewWindow.mark(owner: receiptOwner,
            conversation: invocation.request.conversationContext.conversationId, turn: invocation.request.executionTurnId)
        }
        object.removeValue(forKey: AgentLocalTeamReviewProposal.field)
        return AgentMcpJSONCodec.stringify(object)
      }
      return result.text
    } catch {
      throw AgentModelPlanningProviderError.unavailable(error.localizedDescription)
    }
  }
}
