import Foundation

enum GlobalResearchExecutorPolicy {
  static func executeNext(
    state: GlobalResearchExecutorState,
    resources: [GlobalResearchExecutorResource],
    context: GlobalResearchExecutionContext = GlobalResearchExecutionContext(),
    budgetLimits: GlobalResearchExecutorBudgetLimits = GlobalResearchExecutorBudgetLimits(),
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> GlobalResearchExecutorStep? {
    guard let claimed = claimTask(from: state.tasks, nowMillis: nowMillis) else { return nil }
    var next = state
    var task = prepareClaimedTask(claimed, nowMillis: nowMillis)
    let initialPlan = task.researchPlan.id.isBlank
      ? GlobalResearchPlanBuilder.create(task: task, nowMillis: nowMillis)
      : task.researchPlan
    let recoveredPlan = GlobalResearchPlanBuilder.recoverStale(plan: initialPlan, nowMillis: nowMillis)
    let recoveredLedger = recoveredPlan.completedUnits().isEmpty
      ? task.evidenceLedger
      : GlobalEvidenceEvaluator.build(plan: recoveredPlan, nowMillis: nowMillis)
    let plan = GlobalResearchPlanBuilder.closeCollection(
      task: task,
      plan: recoveredPlan,
      ledger: recoveredLedger,
      nowMillis: nowMillis
    )
    task.researchPlan = plan
    task.evidenceLedger = recoveredLedger
    task.updatedAtMillis = nowMillis
    next.upsert(task)

    if plan.phase == .synthesisPending || plan.phase == .synthesizing {
      return synthesize(
        task: task,
        state: next,
        resources: resources,
        context: context,
        budgetLimits: budgetLimits,
        nowMillis: nowMillis
      )
    }

    let routedResources = GlobalResearchPromptBuilder.routeResources(task: task, resources: resources)
    if routedResources.isEmpty {
      return waitForResource(
        task: task,
        state: next,
        reason: "No research-capable model or Agent is available",
        nowMillis: nowMillis
      )
    }
    let parallelism = GlobalResearchPlanBuilder.parallelism(depth: task.depth, resourceCount: routedResources.count)
    let running = task.researchPlan.runningUnits().count
    let capacity = max(parallelism - running, 0)
    if capacity <= 0 {
      return GlobalResearchExecutorStep(
        state: next,
        result: GlobalResearchExecutionResult(
          taskId: task.id,
          status: .running,
          detail: "Evidence workers are running"
        )
      )
    }
    let pending = Array(task.researchPlan.pendingUnits().prefix(capacity))
    if pending.isEmpty {
      return advanceAfterCollection(
        task: task,
        state: next,
        resources: resources,
        context: context,
        budgetLimits: budgetLimits,
        nowMillis: nowMillis
      )
    }

    var budgetDecision: GlobalModelCallBudgetDecision?
    for unit in pending {
      let selected = GlobalResearchPromptBuilder.selectResource(
        task: task,
        unit: unit,
        resources: routedResources
      )
      let dispatch = dispatchUnit(
        task: task,
        unit: unit,
        resource: selected,
        state: next,
        context: context,
        budgetLimits: budgetLimits,
        nowMillis: nowMillis
      )
      next = dispatch.state
      task = dispatch.task
      if let decision = dispatch.budgetDecision {
        budgetDecision = decision
        break
      }
    }
    if let decision = budgetDecision {
      return waitForModelBudget(
        task: task,
        state: next,
        decision: decision,
        releaseClaimAttempt: task.researchPlan.runningUnits().isEmpty,
        nowMillis: nowMillis
      )
    }
    return advanceAfterCollection(
      task: task,
      state: next,
      resources: resources,
      context: context,
      budgetLimits: budgetLimits,
      nowMillis: nowMillis
    )
  }

  static func consumeConnectorResponse(
    _ response: AgentConnectorResponse,
    state: GlobalResearchExecutorState,
    context: GlobalResearchExecutionContext = GlobalResearchExecutionContext(),
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> GlobalResearchExecutorStep? {
    if response.sourceMessageId <= 0 { return nil }
    var next = state
    let dispatch = next.dispatchRequests.first { $0.sourceMessageId == response.sourceMessageId }
    next.dispatchRequests.removeAll { $0.sourceMessageId == response.sourceMessageId }

    if let task = next.tasks.first(where: {
      $0.researchPlan.synthesisSourceMessageId == response.sourceMessageId &&
        [.running, .waitingForResource].contains($0.status)
    }) {
      let leaseId = dispatch?.leaseId ?? GlobalModelCallBudgetPolicy.leaseId(
        kind: .researchSynthesis,
        ownerKey: GlobalResearchPromptBuilder.synthesisBudgetOwner(task: task)
      )
      next.modelBudget = GlobalModelCallBudgetPolicy.complete(
        state: next.modelBudget,
        leaseId: leaseId,
        inputTokens: response.inputTokens,
        outputTokens: response.outputTokens,
        reportedCostMicros: response.costMicros,
        responseText: response.content,
        nowMillis: nowMillis
      )
      if response.success && !response.content.isBlank {
        return complete(
          task: task,
          rawResult: response.content,
          resourceId: task.researchPlan.synthesisResourceId.ifBlank(response.contactId),
          evidenceLedger: task.evidenceLedger,
          state: next,
          context: context,
          nowMillis: nowMillis
        )
      }
      return handleSynthesisFailure(
        task: task,
        state: next,
        reason: response.content.isBlank ? "The synthesis Agent did not return a result" : response.content,
        context: context,
        nowMillis: nowMillis
      )
    }

    if let task = next.tasks.first(where: {
      $0.researchPlan.units.contains(where: { $0.sourceMessageId == response.sourceMessageId }) &&
        [.running, .waitingForResource].contains($0.status)
    }), let unit = task.researchPlan.units.first(where: { $0.sourceMessageId == response.sourceMessageId }) {
      let leaseId = dispatch?.leaseId ?? GlobalModelCallBudgetPolicy.leaseId(
        kind: .researchEvidence,
        ownerKey: GlobalResearchPromptBuilder.evidenceBudgetOwner(task: task, unit: unit)
      )
      next.modelBudget = GlobalModelCallBudgetPolicy.complete(
        state: next.modelBudget,
        leaseId: leaseId,
        inputTokens: response.inputTokens,
        outputTokens: response.outputTokens,
        reportedCostMicros: response.costMicros,
        responseText: response.content,
        nowMillis: nowMillis
      )
      if response.success && !response.content.isBlank {
        let updated = completeUnit(
          task: task,
          unit: unit,
          rawResult: response.content,
          resourceId: unit.resourceId.ifBlank(response.contactId),
          state: &next,
          nowMillis: nowMillis
        )
        return GlobalResearchExecutorStep(
          state: next,
          result: GlobalResearchExecutionResult(
            taskId: updated.id,
            status: updated.status,
            resourceId: updated.resourceId,
            detail: "Evidence worker completed"
          )
        )
      }
      let updated = failUnit(
        task: task,
        unit: unit,
        reason: response.content.isBlank ? "The evidence worker did not return a result" : response.content,
        state: &next,
        nowMillis: nowMillis
      )
      return GlobalResearchExecutorStep(
        state: next,
        result: GlobalResearchExecutionResult(
          taskId: updated.id,
          status: updated.status,
          resourceId: updated.resourceId,
          detail: updated.lastError
        )
      )
    }

    guard let legacy = next.tasks.first(where: {
      $0.sourceMessageId == response.sourceMessageId &&
        [.running, .waitingForResource].contains($0.status)
    }) else {
      return nil
    }
    if !response.success {
      var retryTask = legacy
      retryTask.attemptedResourceIds = executorUniqueStrings(
        (retryTask.attemptedResourceIds + [retryTask.resourceId]).filter { !$0.isBlank }
      )
      retryTask.sourceMessageId = 0
      retryTask.leaseExpiresAtMillis = 0
      return retryOrFail(
        task: retryTask,
        state: next,
        reason: response.content.isBlank ? "The paired Agent could not complete the research task" : response.content,
        context: context,
        nowMillis: nowMillis
      )
    }
    return complete(
      task: legacy,
      rawResult: response.content,
      resourceId: legacy.resourceId.ifBlank(response.contactId),
      evidenceLedger: legacy.evidenceLedger,
      state: next,
      context: context,
      nowMillis: nowMillis
    )
  }

  private static func dispatchUnit(
    task: GlobalResearchTask,
    unit: GlobalResearchUnit,
    resource: GlobalResearchExecutorResource?,
    state: GlobalResearchExecutorState,
    context: GlobalResearchExecutionContext,
    budgetLimits: GlobalResearchExecutorBudgetLimits,
    nowMillis: Int64
  ) -> UnitDispatchOutcome {
    var next = state
    guard let resource else {
      let failed = failUnit(
        task: task,
        unit: unit,
        reason: "No untried research resource is available",
        state: &next,
        nowMillis: nowMillis
      )
      return UnitDispatchOutcome(state: next, task: failed)
    }
    let prompt = GlobalResearchPromptBuilder.buildUnitPrompt(task: task, unit: unit, context: context)
    let ownerKey = GlobalResearchPromptBuilder.evidenceBudgetOwner(
      task: task,
      unit: unit,
      attemptCount: unit.attemptCount + 1
    )
    let leaseId = GlobalModelCallBudgetPolicy.leaseId(kind: .researchEvidence, ownerKey: ownerKey)
    let estimatedTokens = GlobalModelUsageEstimator.estimateTokens(
      GlobalResearchPromptBuilder.researchSystemPrompt,
      prompt
    )
    let permit = GlobalModelCallBudgetPolicy.acquire(
      state: next.modelBudget,
      leaseId: leaseId,
      kind: .researchEvidence,
      ownerKey: ownerKey,
      leaseMillis: GlobalResearchTaskPolicy.leaseMillis(task.depth),
      dailyLimit: budgetLimits.dailyLimit,
      concurrencyLimit: budgetLimits.concurrencyLimit,
      nowMillis: nowMillis,
      resourceId: resource.id,
      estimatedInputTokens: estimatedTokens,
      dailyTokenLimit: budgetLimits.dailyTokenLimit,
      dailyReportedCostLimitMicros: budgetLimits.dailyReportedCostLimitMicros
    )
    next.modelBudget = permit.state
    if !permit.granted {
      return UnitDispatchOutcome(state: next, task: task, budgetDecision: permit)
    }
    let sourceMessageId = GlobalResearchPromptBuilder.correlationId(
      taskId: task.id,
      unitId: unit.id,
      nowMillis: nowMillis
    )
    let running = markUnitRunning(
      task: task,
      unit: unit,
      resourceId: resource.id,
      sourceMessageId: sourceMessageId,
      nowMillis: nowMillis
    )
    next.upsert(running)
    let request = GlobalResearchDispatchRequest(
      id: "research-dispatch:\(sourceMessageId)",
      taskId: running.id,
      unitId: unit.id,
      stage: .evidence,
      transport: resource.transport,
      resourceId: resource.id,
      contactId: resource.targetContactId,
      sourceMessageId: sourceMessageId,
      conversationId: "global-research:\(running.id)",
      turnId: unit.id,
      ownerKey: ownerKey,
      leaseId: leaseId,
      systemPrompt: GlobalResearchPromptBuilder.researchSystemPrompt,
      prompt: prompt,
      estimatedInputTokens: estimatedTokens,
      createdAtMillis: nowMillis
    )
    next.dispatchRequests.append(request)
    return UnitDispatchOutcome(state: next, task: running)
  }

  private static func markUnitRunning(
    task: GlobalResearchTask,
    unit: GlobalResearchUnit,
    resourceId: String,
    sourceMessageId: Int64,
    nowMillis: Int64
  ) -> GlobalResearchTask {
    var updated = task
    let lease = nowMillis + GlobalResearchTaskPolicy.leaseMillis(task.depth)
    var plan = task.researchPlan
    plan.phase = .collecting
    plan.units = plan.units.map { current in
      var copy = current
      if current.id == unit.id && current.status == .pending {
        copy.status = .running
        copy.resourceId = resourceId
        copy.sourceMessageId = sourceMessageId
        copy.attemptCount = current.attemptCount + 1
        copy.leaseExpiresAtMillis = lease
        copy.lastError = ""
        copy.startedAtMillis = nowMillis
      }
      return copy
    }
    plan.updatedAtMillis = nowMillis
    updated.status = .running
    updated.resourceId = resourceId
    updated.leaseExpiresAtMillis = max(updated.leaseExpiresAtMillis, lease)
    updated.researchPlan = plan
    updated.updatedAtMillis = nowMillis
    return updated
  }

  private static func completeUnit(
    task: GlobalResearchTask,
    unit: GlobalResearchUnit,
    rawResult: String,
    resourceId: String,
    state: inout GlobalResearchExecutorState,
    nowMillis: Int64
  ) -> GlobalResearchTask {
    let result = String(CodexStyleResponsePolicy.sanitizeAssistantText(rawResult)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(GlobalResearchExecutorLimits.maxUnitResultCharacters))
    if result.isBlank {
      return failUnit(
        task: task,
        unit: unit,
        reason: "The evidence result was empty",
        state: &state,
        nowMillis: nowMillis
      )
    }
    let evidenceUris = GlobalEvidenceEvaluator.extractUrls(result)
    var currentTask = state.task(id: task.id) ?? task
    var plan = currentTask.researchPlan
    plan.units = plan.units.map { current in
      var copy = current
      if current.id == unit.id {
        copy.status = .completed
        copy.resourceId = resourceId
        copy.sourceMessageId = 0
        copy.leaseExpiresAtMillis = 0
        copy.result = result
        copy.evidenceUris = evidenceUris
        copy.lastError = ""
        copy.completedAtMillis = nowMillis
      }
      return copy
    }
    plan.updatedAtMillis = nowMillis
    let collectedLedger = GlobalEvidenceEvaluator.build(plan: plan, nowMillis: nowMillis)
    let nextPlan = GlobalResearchPlanBuilder.closeCollection(
      task: currentTask,
      plan: plan,
      ledger: collectedLedger,
      nowMillis: nowMillis
    )
    let ledger = GlobalEvidenceEvaluator.build(plan: nextPlan, nowMillis: nowMillis)
    let nextStatus: GlobalResearchTaskStatus
    if nextPlan.phase == .synthesisPending || !nextPlan.pendingUnits().isEmpty {
      nextStatus = .waitingForResource
    } else {
      nextStatus = .running
    }
    currentTask.status = nextStatus
    currentTask.nextAttemptAtMillis = nextStatus == .waitingForResource ? nowMillis : 0
    currentTask.leaseExpiresAtMillis = nextPlan.runningUnits().map(\.leaseExpiresAtMillis).max() ?? 0
    currentTask.researchPlan = nextPlan
    currentTask.evidenceLedger = ledger
    currentTask.updatedAtMillis = nowMillis
    state.upsert(currentTask)
    state.healthUpdates.append(GlobalResearchResourceHealthUpdate(
      resourceId: "target:\(resourceId)",
      success: true,
      latencyMillis: max(nowMillis - unit.startedAtMillis, 0),
      createdAtMillis: nowMillis
    ))
    return currentTask
  }

  private static func failUnit(
    task: GlobalResearchTask,
    unit: GlobalResearchUnit,
    reason: String,
    state: inout GlobalResearchExecutorState,
    nowMillis: Int64
  ) -> GlobalResearchTask {
    var currentTask = state.task(id: task.id) ?? task
    var plan = currentTask.researchPlan
    plan.units = plan.units.map { current in
      var copy = current
      if current.id == unit.id {
        copy.status = current.attemptCount >= GlobalResearchExecutorLimits.maximumUnitAttempts ? .failed : .pending
        copy.attemptedResourceIds = executorUniqueStrings(
          (current.attemptedResourceIds + [current.resourceId]).filter { !$0.isBlank }
        )
        copy.sourceMessageId = 0
        copy.leaseExpiresAtMillis = 0
        copy.lastError = String(reason.prefix(600))
      }
      return copy
    }
    plan.updatedAtMillis = nowMillis
    let collectedLedger = GlobalEvidenceEvaluator.build(plan: plan, nowMillis: nowMillis)
    let nextPlan = GlobalResearchPlanBuilder.closeCollection(
      task: currentTask,
      plan: plan,
      ledger: collectedLedger,
      nowMillis: nowMillis
    )
    let noUsefulEvidence = nextPlan.units.allSatisfy { $0.status == .failed }
    if noUsefulEvidence ||
      !nextPlan.pendingUnits().isEmpty ||
      nextPlan.phase == .synthesisPending {
      currentTask.status = .waitingForResource
    } else {
      currentTask.status = .running
    }
    let failedAttempt = max(nextPlan.units.first(where: { $0.id == unit.id })?.attemptCount ?? 1, 1)
    currentTask.nextAttemptAtMillis = nowMillis + GlobalResearchTaskPolicy.retryDelayMillis(failedAttempt)
    currentTask.leaseExpiresAtMillis = nextPlan.runningUnits().map(\.leaseExpiresAtMillis).max() ?? 0
    currentTask.lastError = String(reason.prefix(600))
    currentTask.researchPlan = nextPlan
    currentTask.evidenceLedger = GlobalEvidenceEvaluator.build(plan: nextPlan, nowMillis: nowMillis)
    currentTask.updatedAtMillis = nowMillis
    state.upsert(currentTask)
    if !unit.resourceId.isBlank {
      state.healthUpdates.append(GlobalResearchResourceHealthUpdate(
        resourceId: "target:\(unit.resourceId)",
        success: false,
        latencyMillis: max(nowMillis - unit.startedAtMillis, 0),
        createdAtMillis: nowMillis
      ))
    }
    return currentTask
  }

  private static func advanceAfterCollection(
    task: GlobalResearchTask,
    state: GlobalResearchExecutorState,
    resources: [GlobalResearchExecutorResource],
    context: GlobalResearchExecutionContext,
    budgetLimits: GlobalResearchExecutorBudgetLimits,
    nowMillis: Int64
  ) -> GlobalResearchExecutorStep {
    var next = state
    var latest = next.task(id: task.id) ?? task
    let initialPlan = latest.researchPlan
    let ledger = GlobalEvidenceEvaluator.build(plan: initialPlan, nowMillis: nowMillis)
    let plan = GlobalResearchPlanBuilder.closeCollection(
      task: latest,
      plan: initialPlan,
      ledger: ledger,
      nowMillis: nowMillis
    )
    if plan.phase == .synthesisPending {
      latest.status = .waitingForResource
      latest.nextAttemptAtMillis = nowMillis
      latest.researchPlan = plan
      latest.evidenceLedger = ledger
      latest.leaseExpiresAtMillis = 0
      latest.updatedAtMillis = nowMillis
      next.upsert(latest)
      return synthesize(
        task: latest,
        state: next,
        resources: resources,
        context: context,
        budgetLimits: budgetLimits,
        nowMillis: nowMillis
      )
    }
    if plan.completedUnits().isEmpty && !plan.units.isEmpty && plan.units.allSatisfy({ $0.status == .failed }) {
      return retryOrFail(
        task: latest,
        state: next,
        reason: latest.lastError.isBlank ? "Every evidence worker failed" : latest.lastError,
        context: context,
        nowMillis: nowMillis
      )
    }
    let status: GlobalResearchTaskStatus = plan.runningUnits().isEmpty ? .waitingForResource : .running
    latest.status = status
    latest.nextAttemptAtMillis = status == .waitingForResource
      ? nowMillis + GlobalResearchExecutorLimits.collectionContinueDelayMillis
      : 0
    latest.leaseExpiresAtMillis = plan.runningUnits().map(\.leaseExpiresAtMillis).max() ?? 0
    latest.researchPlan = plan
    latest.evidenceLedger = ledger
    latest.updatedAtMillis = nowMillis
    next.upsert(latest)
    return GlobalResearchExecutorStep(
      state: next,
      result: GlobalResearchExecutionResult(
        taskId: latest.id,
        status: latest.status,
        detail: "\(plan.completedUnits().count)/\(plan.units.count) evidence tasks completed"
      )
    )
  }

  private static func synthesize(
    task: GlobalResearchTask,
    state: GlobalResearchExecutorState,
    resources: [GlobalResearchExecutorResource],
    context: GlobalResearchExecutionContext,
    budgetLimits: GlobalResearchExecutorBudgetLimits,
    nowMillis: Int64
  ) -> GlobalResearchExecutorStep {
    var next = state
    var currentTask = next.task(id: task.id) ?? task
    let ledger = currentTask.evidenceLedger.claims.isEmpty
      ? GlobalEvidenceEvaluator.build(plan: currentTask.researchPlan, nowMillis: nowMillis)
      : currentTask.evidenceLedger
    if currentTask.researchPlan.completedUnits().isEmpty {
      return retryOrFail(
        task: currentTask,
        state: next,
        reason: "No evidence was available for synthesis",
        context: context,
        nowMillis: nowMillis
      )
    }
    let qualityPlan = GlobalResearchPlanBuilder.closeCollection(
      task: currentTask,
      plan: currentTask.researchPlan,
      ledger: ledger,
      nowMillis: nowMillis
    )
    if qualityPlan.phase != .synthesisPending && qualityPlan.phase != .synthesizing {
      currentTask.status = .waitingForResource
      currentTask.nextAttemptAtMillis = nowMillis
      currentTask.leaseExpiresAtMillis = 0
      currentTask.researchPlan = qualityPlan
      currentTask.evidenceLedger = ledger
      currentTask.updatedAtMillis = nowMillis
      next.upsert(currentTask)
      return GlobalResearchExecutorStep(
        state: next,
        result: GlobalResearchExecutionResult(
          taskId: currentTask.id,
          status: currentTask.status,
          detail: "Additional evidence verification is required"
        )
      )
    }
    currentTask.researchPlan = qualityPlan
    currentTask.evidenceLedger = ledger
    let routedResources = GlobalResearchPromptBuilder.routeResources(task: currentTask, resources: resources)
    guard !routedResources.isEmpty else {
      return complete(
        task: currentTask,
        rawResult: GlobalResearchPromptBuilder.buildLocalSynthesis(task: currentTask, ledger: ledger),
        resourceId: "local-evidence-synthesis",
        evidenceLedger: ledger,
        state: next,
        context: context,
        nowMillis: nowMillis
      )
    }
    let index = qualityPlan.synthesisAttemptCount % routedResources.count
    let resource = routedResources[index]
    let prompt = GlobalResearchPromptBuilder.buildSynthesisPrompt(
      task: currentTask,
      ledger: ledger,
      context: context
    )
    let ownerKey = GlobalResearchPromptBuilder.synthesisBudgetOwner(
      task: currentTask,
      attemptCount: qualityPlan.synthesisAttemptCount + 1
    )
    let leaseId = GlobalModelCallBudgetPolicy.leaseId(kind: .researchSynthesis, ownerKey: ownerKey)
    let estimatedTokens = GlobalModelUsageEstimator.estimateTokens(
      GlobalResearchPromptBuilder.synthesisSystemPrompt,
      prompt
    )
    let permit = GlobalModelCallBudgetPolicy.acquire(
      state: next.modelBudget,
      leaseId: leaseId,
      kind: .researchSynthesis,
      ownerKey: ownerKey,
      leaseMillis: GlobalResearchTaskPolicy.leaseMillis(currentTask.depth),
      dailyLimit: budgetLimits.dailyLimit,
      concurrencyLimit: budgetLimits.concurrencyLimit,
      nowMillis: nowMillis,
      resourceId: resource.id,
      estimatedInputTokens: estimatedTokens,
      dailyTokenLimit: budgetLimits.dailyTokenLimit,
      dailyReportedCostLimitMicros: budgetLimits.dailyReportedCostLimitMicros
    )
    next.modelBudget = permit.state
    if !permit.granted {
      return waitForModelBudget(
        task: currentTask,
        state: next,
        decision: permit,
        releaseClaimAttempt: true,
        nowMillis: nowMillis
      )
    }
    let sourceMessageId = GlobalResearchPromptBuilder.correlationId(
      taskId: currentTask.id,
      unitId: "synthesis-\(qualityPlan.synthesisAttemptCount)",
      nowMillis: nowMillis
    )
    let synthesizing = markSynthesisRunning(
      task: currentTask,
      resourceId: resource.id,
      sourceMessageId: sourceMessageId,
      ledger: ledger,
      nowMillis: nowMillis
    )
    next.upsert(synthesizing)
    next.dispatchRequests.append(GlobalResearchDispatchRequest(
      id: "research-dispatch:\(sourceMessageId)",
      taskId: synthesizing.id,
      stage: .synthesis,
      transport: resource.transport,
      resourceId: resource.id,
      contactId: resource.targetContactId,
      sourceMessageId: sourceMessageId,
      conversationId: "global-research:\(synthesizing.id)",
      turnId: "\(synthesizing.id):synthesis",
      ownerKey: ownerKey,
      leaseId: leaseId,
      systemPrompt: GlobalResearchPromptBuilder.synthesisSystemPrompt,
      prompt: prompt,
      estimatedInputTokens: estimatedTokens,
      createdAtMillis: nowMillis
    ))
    return GlobalResearchExecutorStep(
      state: next,
      result: GlobalResearchExecutionResult(
        taskId: synthesizing.id,
        status: .running,
        resourceId: resource.id,
        detail: "Evidence synthesis accepted"
      )
    )
  }

  private static func markSynthesisRunning(
    task: GlobalResearchTask,
    resourceId: String,
    sourceMessageId: Int64,
    ledger: GlobalEvidenceLedger,
    nowMillis: Int64
  ) -> GlobalResearchTask {
    var updated = task
    let lease = nowMillis + GlobalResearchTaskPolicy.leaseMillis(task.depth)
    var plan = task.researchPlan
    plan.phase = .synthesizing
    plan.synthesisResourceId = resourceId
    plan.synthesisSourceMessageId = sourceMessageId
    plan.synthesisLeaseExpiresAtMillis = lease
    plan.synthesisAttemptCount += 1
    plan.updatedAtMillis = nowMillis
    updated.status = .running
    updated.resourceId = resourceId
    updated.sourceMessageId = 0
    updated.leaseExpiresAtMillis = lease
    updated.researchPlan = plan
    updated.evidenceLedger = ledger
    updated.updatedAtMillis = nowMillis
    return updated
  }

  private static func handleSynthesisFailure(
    task: GlobalResearchTask,
    state: GlobalResearchExecutorState,
    reason: String,
    context: GlobalResearchExecutionContext,
    nowMillis: Int64
  ) -> GlobalResearchExecutorStep {
    var next = state
    if task.researchPlan.synthesisAttemptCount >= GlobalResearchExecutorLimits.maximumSynthesisAttempts {
      return complete(
        task: task,
        rawResult: GlobalResearchPromptBuilder.buildLocalSynthesis(task: task, ledger: task.evidenceLedger),
        resourceId: "local-evidence-synthesis",
        evidenceLedger: task.evidenceLedger,
        state: next,
        context: context,
        nowMillis: nowMillis
      )
    }
    var updated = task
    updated.status = .waitingForResource
    updated.nextAttemptAtMillis = nowMillis + GlobalResearchTaskPolicy.retryDelayMillis(task.researchPlan.synthesisAttemptCount)
    updated.leaseExpiresAtMillis = 0
    updated.lastError = String(reason.prefix(600))
    updated.researchPlan.phase = .synthesisPending
    updated.researchPlan.synthesisSourceMessageId = 0
    updated.researchPlan.synthesisLeaseExpiresAtMillis = 0
    updated.researchPlan.updatedAtMillis = nowMillis
    updated.updatedAtMillis = nowMillis
    next.upsert(updated)
    if !task.researchPlan.synthesisResourceId.isBlank {
      next.healthUpdates.append(GlobalResearchResourceHealthUpdate(
        resourceId: "target:\(task.researchPlan.synthesisResourceId)",
        success: false,
        latencyMillis: max(nowMillis - task.updatedAtMillis, 0),
        createdAtMillis: nowMillis
      ))
    }
    return GlobalResearchExecutorStep(
      state: next,
      result: GlobalResearchExecutionResult(
        taskId: task.id,
        status: updated.status,
        resourceId: task.resourceId,
        detail: reason
      )
    )
  }

  private static func complete(
    task: GlobalResearchTask,
    rawResult: String,
    resourceId: String,
    evidenceLedger: GlobalEvidenceLedger,
    state: GlobalResearchExecutorState,
    context: GlobalResearchExecutionContext,
    nowMillis: Int64
  ) -> GlobalResearchExecutorStep {
    var next = state
    let causalEventIds = task.causalEventIds.isEmpty ? Set([task.sourceEventId].filter { !$0.isBlank }) : task.causalEventIds
    if context.hasRetractedEvidence(causalEventIds) {
      var invalidated = task
      invalidated.status = .failed
      invalidated.sourceMessageId = 0
      invalidated.leaseExpiresAtMillis = 0
      invalidated.lastError = GlobalAgentEvidenceLifecyclePolicy.invalidatedReason
      invalidated.updatedAtMillis = nowMillis
      next.upsert(invalidated)
      return GlobalResearchExecutorStep(
        state: next,
        result: GlobalResearchExecutionResult(
          taskId: task.id,
          status: invalidated.status,
          resourceId: resourceId,
          detail: invalidated.lastError
        )
      )
    }
    let result = String(CodexStyleResponsePolicy.sanitizeAssistantText(rawResult)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(GlobalResearchExecutorLimits.maxResultCharacters))
    if result.isBlank {
      return retryOrFail(
        task: task,
        state: next,
        reason: "The research result was empty",
        context: context,
        nowMillis: nowMillis
      )
    }
    let evidenceUris = Array(executorUniqueStrings(
      evidenceLedger.sources.map(\.uri) + GlobalEvidenceEvaluator.extractUrls(result)
    ).prefix(GlobalResearchExecutorLimits.maxEvidenceUris))
    let materialChange = GlobalResearchTaskPolicy.isMaterialChange(
      previousResult: task.result,
      previousEvidenceUris: task.evidenceUris,
      nextResult: result,
      nextEvidenceUris: evidenceUris
    )
    let continuous = task.depth == .continuousMonitor
    var completedPlan = task.researchPlan
    completedPlan.phase = .completed
    completedPlan.units = completedPlan.units.map { unit in
      var copy = unit
      copy.sourceMessageId = 0
      copy.leaseExpiresAtMillis = 0
      copy.result = String(unit.result.prefix(GlobalResearchExecutorLimits.maxArchivedUnitResultCharacters))
      return copy
    }
    completedPlan.synthesisSourceMessageId = 0
    completedPlan.synthesisLeaseExpiresAtMillis = 0
    completedPlan.updatedAtMillis = nowMillis

    var completed = task
    completed.status = continuous ? .scheduled : .completed
    completed.resourceId = resourceId
    completed.fallbackResourceIds = []
    completed.attemptedResourceIds = []
    completed.sourceMessageId = 0
    completed.attemptCount = continuous ? 0 : task.attemptCount
    completed.nextAttemptAtMillis = continuous
      ? nowMillis + GlobalResearchTaskPolicy.monitorIntervalMillis(task.monitorIntervalMillis)
      : 0
    completed.leaseExpiresAtMillis = 0
    completed.lastCompletedAtMillis = nowMillis
    completed.lastResultFingerprint = GlobalResearchTaskPolicy.fingerprint(result, evidenceUris: evidenceUris)
    completed.result = result
    completed.evidenceUris = evidenceUris
    completed.researchPlan = continuous ? GlobalResearchPlan() : completedPlan
    completed.evidenceLedger = evidenceLedger
    completed.lastError = ""
    completed.updatedAtMillis = nowMillis
    next.upsert(completed)
    publishCompletedResearch(
      task: completed,
      materialChange: materialChange,
      resourceId: resourceId,
      state: &next
    )
    if resourceId != "local-evidence-synthesis" {
      next.healthUpdates.append(GlobalResearchResourceHealthUpdate(
        resourceId: "target:\(resourceId)",
        success: true,
        latencyMillis: max(nowMillis - task.updatedAtMillis, 0),
        createdAtMillis: nowMillis
      ))
    }
    return GlobalResearchExecutorStep(
      state: next,
      result: GlobalResearchExecutionResult(
        taskId: completed.id,
        status: completed.status,
        resourceId: resourceId,
        detail: result
      )
    )
  }

  private static func publishCompletedResearch(
    task: GlobalResearchTask,
    materialChange: Bool,
    resourceId: String,
    state: inout GlobalResearchExecutorState
  ) {
    let continuous = task.depth == .continuousMonitor
    if continuous && (!materialChange || !task.evidenceLedger.verified) { return }
    let nowMillis = task.updatedAtMillis
    let chinese = GlobalAgentText.containsCjk(task.question)
    let causalEventIds = task.causalEventIds.isEmpty ? Set([task.sourceEventId].filter { !$0.isBlank }) : task.causalEventIds
    let target: GlobalProactiveTarget
    if !task.evidenceLedger.verified {
      target = .currentConversation
    } else if task.depth == .deepResearch || task.depth == .continuousMonitor {
      target = .newConversation
    } else {
      target = .currentConversation
    }
    state.proactiveMessages.append(GlobalProactiveMessage(
      sourceEventId: "research:\(task.id):\(task.lastResultFingerprint)",
      sourceConversationId: task.sourceConversationId,
      target: target,
      title: researchTitle(verified: task.evidenceLedger.verified, chinese: chinese),
      content: task.result,
      topic: task.topic,
      urgent: false,
      causalEventIds: causalEventIds,
      createdAtMillis: nowMillis
    ))
    state.events.append(GlobalConversationEvent(
      id: "research-result:\(task.id):\(task.lastResultFingerprint)",
      type: .toolResult,
      conversationId: task.sourceConversationId,
      messageId: task.id,
      actor: .tool,
      timestampMillis: nowMillis,
      content: task.result,
      contentRef: "encrypted://global-agent/research/\(task.id)",
      conversationTitle: task.topic,
      topicHints: Set([task.topic].filter { !$0.isBlank }),
      metadata: [
        "research_task_id": task.id,
        "resource_id": resourceId,
        "evidence_count": String(task.evidenceLedger.sources.count),
        "independent_source_count": String(task.evidenceLedger.independentSourceCount),
        "primary_source_count": String(task.evidenceLedger.primarySourceCount),
        "fresh_source_count": String(task.evidenceLedger.freshSourceCount),
        "stale_source_count": String(task.evidenceLedger.staleSourceCount),
        "corroborated_claim_count": String(task.evidenceLedger.corroboratedClaimCount),
        "contested_claim_count": String(task.evidenceLedger.contestedClaimCount),
        "quality_issues": task.evidenceLedger.qualityIssues.map(\.rawValue).sorted().joined(separator: ","),
        "evidence_confidence": String(task.evidenceLedger.overallConfidence),
        "material_change": String(materialChange),
        "monitoring": String(continuous),
        "verified": String(task.evidenceLedger.verified)
      ],
      causalEventIds: causalEventIds
    ))
  }

  private static func waitForResource(
    task: GlobalResearchTask,
    state: GlobalResearchExecutorState,
    reason: String,
    nowMillis: Int64
  ) -> GlobalResearchExecutorStep {
    var next = state
    var waiting = task
    waiting.status = .waitingForResource
    waiting.nextAttemptAtMillis = nowMillis + GlobalResearchExecutorLimits.resourceRetryMillis
    waiting.sourceMessageId = 0
    waiting.leaseExpiresAtMillis = 0
    waiting.lastError = reason
    waiting.updatedAtMillis = nowMillis
    next.upsert(waiting)
    return GlobalResearchExecutorStep(
      state: next,
      result: GlobalResearchExecutionResult(taskId: task.id, status: waiting.status, detail: reason)
    )
  }

  private static func waitForModelBudget(
    task: GlobalResearchTask,
    state: GlobalResearchExecutorState,
    decision: GlobalModelCallBudgetDecision,
    releaseClaimAttempt: Bool,
    nowMillis: Int64
  ) -> GlobalResearchExecutorStep {
    var next = state
    var current = next.task(id: task.id) ?? task
    let runningLease = current.researchPlan.runningUnits().map(\.leaseExpiresAtMillis).max() ?? 0
    current.status = runningLease > 0 ? .running : .waitingForResource
    if releaseClaimAttempt {
      current.attemptCount = max(current.attemptCount - 1, 0)
    }
    current.nextAttemptAtMillis = max(decision.nextEligibleAtMillis, nowMillis + 1_000)
    current.leaseExpiresAtMillis = runningLease
    current.lastError = "The background model-call budget is temporarily unavailable"
    current.updatedAtMillis = nowMillis
    next.upsert(current)
    return GlobalResearchExecutorStep(
      state: next,
      result: GlobalResearchExecutionResult(
        taskId: task.id,
        status: current.status,
        detail: current.lastError
      )
    )
  }

  private static func retryOrFail(
    task: GlobalResearchTask,
    state: GlobalResearchExecutorState,
    reason: String,
    context: GlobalResearchExecutionContext,
    nowMillis: Int64
  ) -> GlobalResearchExecutorStep {
    var next = state
    if task.depth == .continuousMonitor && task.attemptCount >= GlobalResearchExecutorLimits.maximumAttempts {
      var scheduled = task
      scheduled.status = .scheduled
      scheduled.sourceMessageId = 0
      scheduled.attemptCount = 0
      scheduled.nextAttemptAtMillis = nowMillis + GlobalResearchExecutorLimits.monitorFailureRetryMillis
      scheduled.leaseExpiresAtMillis = 0
      scheduled.lastError = String(reason.prefix(600))
      scheduled.researchPlan = GlobalResearchPlan()
      scheduled.updatedAtMillis = nowMillis
      next.upsert(scheduled)
      return GlobalResearchExecutorStep(
        state: next,
        result: GlobalResearchExecutionResult(
          taskId: task.id,
          status: scheduled.status,
          resourceId: task.resourceId,
          detail: reason
        )
      )
    }
    if task.attemptCount < GlobalResearchExecutorLimits.maximumAttempts {
      var waiting = task
      waiting.status = .waitingForResource
      waiting.sourceMessageId = 0
      waiting.nextAttemptAtMillis = nowMillis + GlobalResearchTaskPolicy.retryDelayMillis(task.attemptCount)
      waiting.leaseExpiresAtMillis = 0
      waiting.lastError = String(reason.prefix(600))
      waiting.updatedAtMillis = nowMillis
      next.upsert(waiting)
      return GlobalResearchExecutorStep(
        state: next,
        result: GlobalResearchExecutionResult(
          taskId: task.id,
          status: waiting.status,
          resourceId: task.resourceId,
          detail: reason
        )
      )
    }
    var failed = task
    failed.status = .failed
    failed.sourceMessageId = 0
    failed.leaseExpiresAtMillis = 0
    failed.lastError = String(reason.prefix(600))
    failed.updatedAtMillis = nowMillis
    next.upsert(failed)
    publishResearchFailure(task: failed, reason: reason, context: context, state: &next)
    return GlobalResearchExecutorStep(
      state: next,
      result: GlobalResearchExecutionResult(
        taskId: task.id,
        status: failed.status,
        resourceId: task.resourceId,
        detail: reason
      )
    )
  }

  private static func publishResearchFailure(
    task: GlobalResearchTask,
    reason: String,
    context: GlobalResearchExecutionContext,
    state: inout GlobalResearchExecutorState
  ) {
    let causalEventIds = task.causalEventIds.isEmpty ? Set([task.sourceEventId].filter { !$0.isBlank }) : task.causalEventIds
    if context.hasRetractedEvidence(causalEventIds) { return }
    let chinese = GlobalAgentText.containsCjk(task.question)
    let title = chinese ? "\u{7814}\u{7a76}\u{6682}\u{672a}\u{5b8c}\u{6210}" : "Research paused"
    let content: String
    if chinese {
      content = "\u{201c}\(task.topic)\u{201d}\u{6682}\u{65f6}\u{65e0}\u{6cd5}\u{7ee7}\u{7eed}\u{ff1a}\(String(reason.prefix(240)))\u{3002}\u{8d44}\u{6e90}\u{6062}\u{590d}\u{540e}\u{53ef}\u{4ee5}\u{91cd}\u{65b0}\u{5c1d}\u{8bd5}\u{3002}"
    } else {
      content = "Research for \(task.topic) could not continue: \(String(reason.prefix(240))). It can be retried when a resource becomes available."
    }
    state.proactiveMessages.append(GlobalProactiveMessage(
      sourceEventId: "research-failed:\(task.id)",
      sourceConversationId: task.sourceConversationId,
      target: .currentConversation,
      title: title,
      content: content,
      topic: task.topic,
      urgent: false,
      causalEventIds: causalEventIds,
      createdAtMillis: task.updatedAtMillis
    ))
  }

  private static func claimTask(from tasks: [GlobalResearchTask], nowMillis: Int64) -> GlobalResearchTask? {
    tasks
      .map { GlobalResearchTaskPolicy.recoverIfStale($0, nowMillis: nowMillis) }
      .filter { isClaimable($0, nowMillis: nowMillis) }
      .sorted { left, right in
        let leftScore = GlobalResearchTaskPolicy.selectionScore(left, nowMillis: nowMillis)
        let rightScore = GlobalResearchTaskPolicy.selectionScore(right, nowMillis: nowMillis)
        if leftScore == rightScore { return left.createdAtMillis < right.createdAtMillis }
        return leftScore > rightScore
      }
      .first
  }

  private static func isClaimable(_ task: GlobalResearchTask, nowMillis: Int64) -> Bool {
    switch task.status {
    case .queued:
      return true
    case .scheduled, .waitingForResource:
      return task.nextAttemptAtMillis <= 0 || task.nextAttemptAtMillis <= nowMillis
    case .running:
      return task.leaseExpiresAtMillis > 0 && task.leaseExpiresAtMillis <= nowMillis
    case .completed, .failed, .paused:
      return false
    }
  }

  private static func prepareClaimedTask(_ task: GlobalResearchTask, nowMillis: Int64) -> GlobalResearchTask {
    var claimed = GlobalResearchTaskPolicy.recoverIfStale(task, nowMillis: nowMillis)
    claimed.status = .running
    claimed.attemptCount += 1
    claimed.nextAttemptAtMillis = 0
    claimed.leaseExpiresAtMillis = nowMillis + GlobalResearchTaskPolicy.leaseMillis(claimed.depth)
    claimed.updatedAtMillis = nowMillis
    return claimed
  }

  private static func researchTitle(verified: Bool, chinese: Bool) -> String {
    if verified && chinese { return "\u{7814}\u{7a76}\u{7ed3}\u{679c}" }
    if verified { return "Research result" }
    if chinese { return "\u{8bc1}\u{636e}\u{5f85}\u{9a8c}\u{8bc1}" }
    return "Evidence needs verification"
  }
}

private struct UnitDispatchOutcome {
  var state: GlobalResearchExecutorState
  var task: GlobalResearchTask
  var budgetDecision: GlobalModelCallBudgetDecision?

  init(
    state: GlobalResearchExecutorState,
    task: GlobalResearchTask,
    budgetDecision: GlobalModelCallBudgetDecision? = nil
  ) {
    self.state = state
    self.task = task
    self.budgetDecision = budgetDecision
  }
}

private func executorUniqueStrings(_ values: [String]) -> [String] {
  var seen = Set<String>()
  var result: [String] = []
  for value in values where seen.insert(value).inserted {
    result.append(value)
  }
  return result
}
