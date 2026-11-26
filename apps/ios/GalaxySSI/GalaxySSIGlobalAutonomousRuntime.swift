import Foundation

struct GalaxySSIGlobalAutonomousExecutionResult: Equatable {
  var runId: String
  var actionId: String
  var status: GlobalAutonomousRunStatus
  var detail: String
  var dispatchRequest: GalaxySSIGlobalAutonomousDispatchRequest?

  init(
    runId: String,
    actionId: String = "",
    status: GlobalAutonomousRunStatus,
    detail: String = "",
    dispatchRequest: GalaxySSIGlobalAutonomousDispatchRequest? = nil
  ) {
    self.runId = runId
    self.actionId = actionId
    self.status = status
    self.detail = detail
    self.dispatchRequest = dispatchRequest
  }
}

enum GlobalAutonomousSourceScope {
  static func inheritedSources(_ task: GlobalCognitionTask) -> Set<String>? {
    guard task.status == .completed, let contextIds = task.contextConversationIds,
          let sources = GlobalBackgroundCognitionScope.sourceConversationIds(task) else { return nil }
    return sources.union(contextIds)
  }

  static func allows(_ run: GlobalAutonomousRun, scope: GlobalRealtimePlanningScope) -> Bool {
    guard scope.canRead, let sources = run.sourceConversationIds,
          !GlobalAgentEvidenceLifecyclePolicy.isInvalidatedState(run.lastError),
          run.sourceConversationId.isEmpty || sources.contains(run.sourceConversationId) else { return false }
    return sources.isSubset(of: scope.allowedConversationIds)
  }

  static func matches(_ response: AgentConnectorResponse, run: GlobalAutonomousRun) -> Bool {
    guard response.sourceMessageId > 0, response.taskId.isEmpty || response.taskId == run.id else { return false }
    if run.status == .replanning, run.review.status == .running,
       run.review.sourceMessageId == response.sourceMessageId {
      return !run.review.resourceId.isEmpty && response.contactId == run.review.resourceId &&
        (response.conversationId.isEmpty || response.conversationId == "global-autonomous-review:\(run.id)") &&
        (response.turnId.isEmpty || response.turnId == "revision:\(run.revision + 1)")
    }
    let actions = run.actions.filter { $0.status == .running && $0.sourceMessageId == response.sourceMessageId }
    guard run.status == .running, actions.count == 1, let action = actions.first else { return false }
    return !action.resourceId.isEmpty && response.contactId == action.resourceId &&
      (response.conversationId.isEmpty || response.conversationId == "global-autonomous:\(run.id)") &&
      (response.turnId.isEmpty || response.turnId == action.id)
  }

  @MainActor
  static func liveScope(_ store: GalaxySSIStore) -> GlobalRealtimePlanningScope {
    GlobalRealtimePlanningScope(enabled: store.globalAgentSettings.enabled && store.globalAgentSettings.autonomousPreparationEnabled,
      conversations: store.agentSessions(includeArchived: true))
  }

  @MainActor
  static func resourceAuthorized(_ id: String, store: GalaxySSIStore) -> Bool {
    if id == "phone-local-model" { return true }
    guard let contact = store.contact(id: id), !contact.deleted else { return false }
    if contact.deliveryMode == .cloudAPI { return store.globalAgentSettings.allowCloudCognition }
    return store.globalAgentSettings.allowPairedAgentCognition && contact.trustState == .verified &&
      contact.deliveryMode.isGalaxySSILinkFamily
  }
}

enum GalaxySSIGlobalAutonomousRunPlanner {
  @discardableResult
  static func upsertRun(
    store: GlobalAgentDeliberationStore,
    task: GlobalCognitionTask,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> GlobalAutonomousRun? {
    guard !task.result.actions.isEmpty, let sources = GlobalAutonomousSourceScope.inheritedSources(task) else { return nil }
    let existingRuns = store.autonomousRuns()
    guard store.lastErrorDescription.isEmpty else { return nil }
    if let existing = existingRuns.first(where: {
      $0.sourceCognitionTaskId == task.id && $0.status != .failed
    }) {
      return existing.sourceEventId == task.sourceEvent.id && existing.sourceConversationIds == sources ? existing : nil
    }

    let proposed = Array(task.result.actions.prefix(12)).map {
      GlobalAutonomousActionAuthorityPolicy.prepareProposal($0)
    }
    let actions = GlobalAutonomousActionGraphPolicy.prepare(proposed)
    guard !actions.isEmpty else { return nil }
    let goal = (task.result.goals.first ?? "")
      .ifBlank(task.result.progressSummary)
      .ifBlank(task.sourceEvent.content)
    let run = GlobalAutonomousRun(
      sourceCognitionTaskId: task.id,
      sourceEventId: task.sourceEvent.id,
      sourceConversationId: sources.contains(task.sourceEvent.conversationId) ? task.sourceEvent.conversationId : "",
      topic: task.result.topic.ifBlank(task.baselineUnderstanding.topic),
      goal: String(goal.prefix(2_000)),
      actions: actions,
      causalEventIds: task.sourceEvent.causalEventIds.union([task.sourceEvent.id]),
      createdAtMillis: nowMillis,
      updatedAtMillis: nowMillis,
      sourceConversationIds: sources
    )
    store.upsertAutonomousRun(run)
    return store.lastErrorDescription.isEmpty ? run : nil
  }
}

extension GalaxySSIGlobalAgentRuntimeBridge {
  static func permitsAutonomousRequest(store: GalaxySSIStore, request: GalaxySSIGlobalAutonomousDispatchRequest) -> Bool {
    let deliberation = GlobalAgentDeliberationStore()
    let runs = deliberation.autonomousRuns().filter { $0.id == request.runId }
    guard deliberation.lastErrorDescription.isEmpty, runs.count == 1, let run = runs.first,
          GlobalAutonomousSourceScope.allows(run, scope: GlobalAutonomousSourceScope.liveScope(store)) else { return false }
    let response = AgentConnectorResponse(sourceMessageId: request.sourceMessageId, contactId: request.resourceId,
      content: "", conversationId: request.conversationId, turnId: request.turnId, taskId: request.runId,
      receivedAtMillis: 0)
    guard GlobalAutonomousSourceScope.matches(response, run: run),
          (request.actionId.isEmpty ? run.status == .replanning : request.actionId == request.turnId) else { return false }
    if request.transport == .onDeviceModel {
      return request.resourceId == "phone-local-model" && request.contactId.isEmpty
    }
    guard request.contactId == request.resourceId, let contact = store.contact(id: request.contactId), !contact.deleted else { return false }
    switch request.transport {
    case .pairedAgent:
      return store.globalAgentSettings.allowPairedAgentCognition && contact.trustState == .verified && contact.deliveryMode.isGalaxySSILinkFamily
    case .cloudModel:
      return store.globalAgentSettings.allowCloudCognition && contact.deliveryMode == .cloudAPI
    case .onDeviceModel: return false
    }
  }

  @discardableResult
  static func processAutonomousCycle(
    store: GalaxySSIStore,
    toolRegistry: AgentNativeToolRegistry? = nil,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> GalaxySSIGlobalAutonomousExecutionResult? {
    let settings = store.globalAgentSettings
    guard settings.enabled, settings.autonomousPreparationEnabled else { return nil }

    let deliberationStore = GlobalAgentDeliberationStore()
    let scope = GlobalAutonomousSourceScope.liveScope(store)
    guard let claim = deliberationStore.claimAutonomousWork(nowMillis: nowMillis,
      eligible: { GlobalAutonomousSourceScope.allows($0, scope: scope) }) else {
      return nil
    }
    var run = claim.run
    let reconciled = GlobalAutonomousActionGraphPolicy.reconcile(
      run.actions,
      nowMillis: nowMillis
    )
    if reconciled != run.actions {
      run.actions = reconciled
      run.updatedAtMillis = nowMillis
      deliberationStore.upsertAutonomousRun(run)
    }

    if claim.planReview {
      return GalaxySSIGlobalAutonomousModelRuntime.dispatchPlanReview(
        run: run,
        appStore: store,
        deliberationStore: deliberationStore,
        nowMillis: nowMillis
      )
    }
    guard let action = run.actions.first(where: {
      $0.id == claim.actionId && $0.status == .running
    }) else {
      return settle(run: run, store: deliberationStore, nowMillis: nowMillis)
    }

    switch action.kind {
    case .invokeTool:
      return executeTool(
        run: run,
        action: action,
        store: deliberationStore,
        registry: toolRegistry,
        enabled: settings.autonomousToolExecutionEnabled,
        nowMillis: nowMillis
      )
    case .createTopic:
      appendProactiveTopicMessage(
        to: store,
        run: run,
        action: action,
        nowMillis: nowMillis
      )
      let updated = complete(
        run: run,
        action: action,
        result: "A focused topic workspace was prepared",
        evidence: localEvidence(
          summary: "A focused topic workspace was prepared",
          sourceRef: "topic:\(run.id):\(action.id)",
          nowMillis: nowMillis
        ),
        nowMillis: nowMillis
      )
      return settle(run: updated, store: deliberationStore, nowMillis: nowMillis)
    case .startResearch:
      guard let task = queueResearch(run: run, action: action, nowMillis: nowMillis) else {
        var failed = run
        failed.actions = failed.actions.map { candidate in
          guard candidate.id == action.id else { return candidate }
          var copy = candidate
          copy.status = .failed
          copy.result = "The research task could not be queued"
          copy.verificationStatus = .insufficient
          copy.lastError = "The research task could not be queued"
          copy.completedAtMillis = nowMillis
          return copy
        }
        return settle(run: failed, store: deliberationStore, nowMillis: nowMillis)
      }
      return waitForResearchEvidence(
        run: run,
        action: action,
        task: task,
        store: deliberationStore,
        nowMillis: nowMillis
      )
    case .startMonitor:
      let task = queueResearch(run: run, action: action, nowMillis: nowMillis)
      let updated = complete(
        run: run,
        action: action,
        result: task == nil ? "The monitoring task could not be queued" : "Monitoring was scheduled",
        evidence: localEvidence(
          summary: task == nil ? "The monitoring task could not be queued" : "Monitoring was scheduled",
          sourceRef: task.map { "research:\($0.id)" } ?? "research:unavailable",
          nowMillis: nowMillis
        ),
        nowMillis: nowMillis
      )
      if task == nil {
        var failed = updated
        failed.actions = failed.actions.map { candidate in
          guard candidate.id == action.id else { return candidate }
          var copy = candidate
          copy.status = .failed
          copy.result = "The monitoring task could not be queued"
          copy.verificationStatus = .insufficient
          copy.lastError = "The monitoring task could not be queued"
          return copy
        }
        return settle(run: failed, store: deliberationStore, nowMillis: nowMillis)
      }
      return settle(run: updated, store: deliberationStore, nowMillis: nowMillis)
    case .analyze, .draft, .readOnlyCheck:
      return GalaxySSIGlobalAutonomousModelRuntime.dispatchAction(
        run: run,
        action: action,
        appStore: store,
        deliberationStore: deliberationStore,
        nowMillis: nowMillis
      )
    }
  }

  private static func executeTool(
    run: GlobalAutonomousRun,
    action: GlobalAutonomousAction,
    store: GlobalAgentDeliberationStore,
    registry: AgentNativeToolRegistry?,
    enabled: Bool,
    nowMillis: Int64
  ) -> GalaxySSIGlobalAutonomousExecutionResult {
    guard enabled else {
      return settle(
        run: fail(run: run, action: action, reason: "Autonomous tool execution is disabled", nowMillis: nowMillis),
        store: store,
        nowMillis: nowMillis
      )
    }
    guard let registry else {
      return settle(
        run: fail(run: run, action: action, reason: "The iOS native tool runtime is unavailable", nowMillis: nowMillis),
        store: store,
        nowMillis: nowMillis
      )
    }

    let host = GlobalAutonomousToolHost(registry: registry)
    let decision = host.inspect(action: action, sessionId: run.id)
    switch decision.status {
    case .waitingConfirmation:
      var waiting = run
      waiting.actions = waiting.actions.map { candidate in
        guard candidate.id == action.id else { return candidate }
        var copy = candidate
        copy.status = .waitingConfirmation
        copy.leaseExpiresAtMillis = 0
        copy.resourceId = action.toolId
        copy.lastError = decision.reason
        return copy
      }
      waiting.status = .waitingConfirmation
      waiting.leaseExpiresAtMillis = 0
      waiting.updatedAtMillis = nowMillis
      store.upsertAutonomousRun(waiting)
      return GalaxySSIGlobalAutonomousExecutionResult(
        runId: waiting.id,
        actionId: action.id,
        status: waiting.status,
        detail: decision.reason
      )
    case .rejected:
      return settle(
        run: fail(run: run, action: action, reason: decision.reason, nowMillis: nowMillis),
        store: store,
        nowMillis: nowMillis
      )
    case .ready:
      break
    }

    let selected = run
    let execution = host.execute(run: selected, action: action, decision: decision)
    let nativeResult = execution.result
    if nativeResult.isSuccess {
      let updated = complete(
        run: selected,
        action: action,
        result: execution.summary,
        evidence: execution.evidence,
        nowMillis: nowMillis
      )
      return settle(run: updated, store: store, nowMillis: nowMillis)
    }
    let reason = (nativeResult.error?.message ?? "")
      .ifBlank(execution.summary)
      .ifBlank("The iOS native tool failed")
    return settle(
      run: fail(run: selected, action: action, reason: reason, nowMillis: nowMillis),
      store: store,
      nowMillis: nowMillis
    )
  }

  private static func finishPlanReview(
    run: GlobalAutonomousRun,
    store: GlobalAgentDeliberationStore,
    nowMillis: Int64
  ) -> GalaxySSIGlobalAutonomousExecutionResult {
    var waiting = run
    waiting.status = .waitingForResource
    waiting.review.status = .waitingForResource
    waiting.review.sourceMessageId = 0
    waiting.review.leaseExpiresAtMillis = 0
    waiting.review.nextAttemptAtMillis = nowMillis + 15 * 60 * 1_000
    waiting.review.lastError = "iOS autonomous plan review is waiting for a model resource"
    waiting.nextAttemptAtMillis = waiting.review.nextAttemptAtMillis
    waiting.leaseExpiresAtMillis = 0
    waiting.updatedAtMillis = nowMillis
    store.upsertAutonomousRun(waiting)
    return GalaxySSIGlobalAutonomousExecutionResult(
      runId: waiting.id,
      actionId: "",
      status: waiting.status,
      detail: waiting.review.lastError
    )
  }

  private static func settle(
    run: GlobalAutonomousRun,
    store: GlobalAgentDeliberationStore,
    nowMillis: Int64
  ) -> GalaxySSIGlobalAutonomousExecutionResult {
    var settled = run
    settled.status = GlobalAutonomousRunPolicy.terminalStatus(settled.actions) ?? .queued
    settled.nextAttemptAtMillis = settled.status == .queued ? nowMillis : 0
    settled.leaseExpiresAtMillis = 0
    settled.updatedAtMillis = nowMillis
    let latestOutcome = settled.actions
      .filter { !$0.result.isBlank }
      .map(\.result)
      .last
      ?? ""
    settled.outcomeSummary = latestOutcome.ifBlank(settled.outcomeSummary)
    store.upsertAutonomousRun(settled)
    return GalaxySSIGlobalAutonomousExecutionResult(
      runId: settled.id,
      actionId: settled.activeAction()?.id ?? "",
      status: settled.status,
      detail: settled.outcomeSummary
    )
  }

  private static func complete(
    run: GlobalAutonomousRun,
    action: GlobalAutonomousAction,
    result: String,
    evidence: GlobalActionEvidence,
    nowMillis: Int64
  ) -> GlobalAutonomousRun {
    var updated = run
    updated.actions = updated.actions.map { candidate in
      guard candidate.id == action.id else { return candidate }
      var copy = candidate
      copy.status = .completed
      copy.leaseExpiresAtMillis = 0
      copy.result = String(result.prefix(12_000))
      copy.evidence.append(evidence)
      copy.verificationStatus = GlobalActionVerificationPolicy.evaluate(
        contract: copy.verificationContract,
        evidence: copy.evidence
      )
      copy.lastError = ""
      copy.completedAtMillis = nowMillis
      return copy
    }
    updated.lastError = ""
    updated.updatedAtMillis = nowMillis
    return updated
  }

  private static func fail(
    run: GlobalAutonomousRun,
    action: GlobalAutonomousAction,
    reason: String,
    nowMillis: Int64
  ) -> GlobalAutonomousRun {
    var updated = run
    updated.actions = updated.actions.map { candidate in
      guard candidate.id == action.id else { return candidate }
      var copy = candidate
      copy.status = .failed
      copy.leaseExpiresAtMillis = 0
      copy.result = String(reason.prefix(12_000))
      copy.lastError = String(reason.prefix(2_000))
      copy.verificationStatus = .insufficient
      copy.completedAtMillis = nowMillis
      return copy
    }
    updated.lastError = String(reason.prefix(2_000))
    updated.updatedAtMillis = nowMillis
    return updated
  }

  private static func queueResearch(
    run: GlobalAutonomousRun,
    action: GlobalAutonomousAction,
    nowMillis: Int64
  ) -> GlobalResearchTask? {
    guard let sources = run.sourceConversationIds else { return nil }
    let researchStore = GalaxySSIGlobalResearchRuntimeStore()
    var state = researchStore.state()
    guard researchStore.lastErrorDescription.isEmpty else { return nil }
    let id = "autonomous-research:\(run.id):\(action.id)"
    if let existing = state.task(id: id) {
      return existing.sourceConversationIds == sources && existing.sourceEventId == run.sourceEventId &&
        existing.sourceConversationId == run.sourceConversationId ? existing : nil
    }
    let question = action.goal.ifBlank(run.goal)
    guard !question.isBlank else { return nil }
    let task = GlobalResearchTask(
      id: id,
      sourceEventId: run.sourceEventId,
      sourceConversationId: run.sourceConversationId,
      topic: action.targetTopic.ifBlank(run.topic),
      question: question,
      depth: action.kind == .startMonitor ? .continuousMonitor : .deepResearch,
      preferredSources: ["official", "primary", "repository", "paper"],
      causalEventIds: run.causalEventIds,
      status: .queued,
      monitorIntervalMillis: action.kind == .startMonitor ? 24 * 60 * 60 * 1_000 : 0,
      createdAtMillis: nowMillis,
      updatedAtMillis: nowMillis,
      sourceConversationIds: sources
    )
    state.upsert(task)
    researchStore.save(state)
    return researchStore.lastErrorDescription.isEmpty ? task : nil
  }

  private static func waitForResearchEvidence(
    run: GlobalAutonomousRun,
    action: GlobalAutonomousAction,
    task: GlobalResearchTask,
    store: GlobalAgentDeliberationStore,
    nowMillis: Int64
  ) -> GalaxySSIGlobalAutonomousExecutionResult {
    var waiting = run
    waiting.actions = run.actions.map { candidate in
      guard candidate.id == action.id else { return candidate }
      var copy = candidate
      copy.status = .running
      copy.resourceId = task.id
      copy.sourceMessageId = 0
      copy.leaseExpiresAtMillis = 0
      copy.result = "Research was queued"
      copy.lastError = ""
      return copy
    }
    waiting.status = .waitingForResource
    waiting.nextAttemptAtMillis = 0
    waiting.leaseExpiresAtMillis = 0
    waiting.updatedAtMillis = nowMillis
    store.upsertAutonomousRun(waiting)
    return GalaxySSIGlobalAutonomousExecutionResult(
      runId: run.id,
      actionId: action.id,
      status: .waitingForResource,
      detail: "Research was queued"
    )
  }

  private static func localEvidence(
    summary: String,
    sourceRef: String,
    nowMillis: Int64,
    kind: GlobalActionEvidenceKind = .localReceipt
  ) -> GlobalActionEvidence {
    GlobalActionEvidence(
      kind: kind,
      summary: summary,
      sourceRef: sourceRef,
      confidence: kind == .researchLedger ? 0.82 : 0.96,
      verified: true,
      createdAtMillis: nowMillis
    )
  }

  private static func appendProactiveTopicMessage(
    to store: GalaxySSIStore,
    run: GlobalAutonomousRun,
    action: GlobalAutonomousAction,
    nowMillis: Int64
  ) {
    store.appendGlobalProactiveMessage(GlobalProactiveMessage(
      sourceEventId: "autonomous-topic:\(run.id):\(action.id)",
      sourceConversationId: run.sourceConversationId,
      target: .newConversation,
      title: action.targetTopic.ifBlank(run.topic).ifBlank("New topic"),
      content: action.goal,
      topic: action.targetTopic.ifBlank(run.topic),
      urgent: false,
      causalEventIds: run.causalEventIds,
      createdAtMillis: nowMillis
    ))
  }
}
