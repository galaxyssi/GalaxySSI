import Foundation

enum GalaxySSIGlobalAutonomousBudgetRuntime {
  @MainActor
  static func acquire(
    store: GalaxySSIStore,
    runId: String,
    actionId: String,
    kind: GlobalModelCallKind,
    resourceId: String,
    systemPrompt: String,
    prompt: String,
    nowMillis: Int64
  ) -> GlobalModelCallBudgetDecision {
    let settings = store.globalAgentSettings
    let ownerKey = ownerKey(runId: runId, actionId: actionId, kind: kind)
    let leaseId = GlobalModelCallBudgetPolicy.leaseId(kind: kind, ownerKey: ownerKey)
    let estimatedInputTokens = GlobalModelUsageEstimator.estimateTokens(systemPrompt, prompt)
    let budgetStore = GalaxySSIGlobalResearchRuntimeStore()
    var state = budgetStore.state()
    let decision = GlobalModelCallBudgetPolicy.acquire(
      state: state.modelBudget,
      leaseId: leaseId,
      kind: kind,
      ownerKey: ownerKey,
      leaseMillis: GlobalAutonomousRunPolicy.leaseMillis,
      dailyLimit: settings.dailyBackgroundModelCallBudget,
      concurrencyLimit: settings.maxConcurrentBackgroundModelCalls,
      nowMillis: nowMillis,
      resourceId: resourceId,
      estimatedInputTokens: estimatedInputTokens,
      dailyTokenLimit: settings.dailyBackgroundTokenBudget,
      dailyReportedCostLimitMicros: settings.dailyBackgroundReportedCostBudgetMicros
    )
    state.modelBudget = decision.state
    budgetStore.save(state)
    return decision
  }

  static func complete(
    runId: String,
    actionId: String,
    kind: GlobalModelCallKind,
    inputTokens: Int64,
    outputTokens: Int64,
    reportedCostMicros: Int64,
    responseText: String,
    nowMillis: Int64
  ) {
    let budgetStore = GalaxySSIGlobalResearchRuntimeStore()
    var state = budgetStore.state()
    state.modelBudget = GlobalModelCallBudgetPolicy.complete(
      state: state.modelBudget,
      leaseId: leaseId(runId: runId, actionId: actionId, kind: kind),
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      reportedCostMicros: reportedCostMicros,
      responseText: responseText,
      nowMillis: nowMillis
    )
    budgetStore.save(state)
  }

  static func leaseId(runId: String, actionId: String, kind: GlobalModelCallKind) -> String {
    GlobalModelCallBudgetPolicy.leaseId(
      kind: kind,
      ownerKey: ownerKey(runId: runId, actionId: actionId, kind: kind)
    )
  }

  private static func ownerKey(runId: String, actionId: String, kind: GlobalModelCallKind) -> String {
    "ios-autonomous:\(kind.rawValue.lowercased()):\(runId):\(actionId)"
  }
}
