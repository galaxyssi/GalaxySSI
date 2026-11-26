import XCTest
@testable import GalaxySSI

final class GlobalResearchExecutorPolicyTests: XCTestCase {
  func testResearchScopeRequiresCompleteKnownEligibleSources() {
    var candidate = task(.quickFact)
    let scope = researchScope()
    XCTAssertFalse(GlobalResearchSourceScope.allows(candidate, scope: scope))
    candidate.sourceConversationIds = ["conversation-main"]
    XCTAssertTrue(GlobalResearchSourceScope.allows(candidate, scope: scope))
    for excluded in ["private", "paused", "removed"] {
      candidate.sourceConversationIds = ["conversation-main", excluded]
      XCTAssertFalse(GlobalResearchSourceScope.allows(candidate, scope: scope))
    }
    candidate.sourceConversationIds = []
    XCTAssertFalse(GlobalResearchSourceScope.allows(candidate, scope: scope))
    candidate.sourceConversationId = ""
    XCTAssertTrue(GlobalResearchSourceScope.allows(candidate, scope: scope))
    XCTAssertFalse(GlobalResearchSourceScope.allows(candidate,
      scope: GlobalRealtimePlanningScope(enabled: false, conversations: [])))
  }

  func testResearchSelectionAndExecutorUseTheSameEligibilityPredicate() throws {
    var denied = task(.quickFact)
    denied.id = "denied"
    var allowed = denied
    allowed.id = "allowed"
    let state = GlobalResearchExecutorState(tasks: [denied, allowed])
    let eligible: (GlobalResearchTask) -> Bool = { $0.id == "allowed" }
    XCTAssertEqual(GlobalResearchExecutorPolicy.claimTask(from: state.tasks, nowMillis: now, eligible: eligible)?.id, "allowed")
    let step = try XCTUnwrap(GlobalResearchExecutorPolicy.executeNext(state: state,
      resources: [resource("cloud-models", .cloudModel)], nowMillis: now, eligible: eligible))
    XCTAssertEqual(step.result.taskId, "allowed")
    XCTAssertEqual(step.state.task(id: "denied"), denied)
    XCTAssertTrue(step.state.dispatchRequests.allSatisfy { $0.taskId == "allowed" })
    XCTAssertNil(GlobalResearchExecutorPolicy.executeNext(state: state,
      resources: [resource("cloud-models", .cloudModel)], nowMillis: now, eligible: { _ in false }))
    XCTAssertNotNil(GlobalResearchExecutorPolicy.claimTask(from: state.tasks, nowMillis: now))
  }

  func testResearchSeedSourcesKeepMetadataAndRejectPrivateSensitivity() {
    var cognition = researchCognition()
    cognition.sourceEvent.metadata["source_conversation_ids"] = " secondary, conversation-main, ,secondary "
    XCTAssertEqual(GlobalResearchSourceScope.sourceIds(from: cognition), ["conversation-main", "secondary"])
    cognition.status = .completed
    XCTAssertNil(GlobalResearchSourceScope.sourceIds(from: cognition))
    cognition.contextConversationIds = ["context-source"]
    XCTAssertEqual(GlobalResearchSourceScope.sourceIds(from: cognition), ["conversation-main", "secondary", "context-source"])
    cognition.sourceEvent.sensitivity = .sessionPrivate
    XCTAssertNil(GlobalResearchSourceScope.sourceIds(from: cognition))
  }

  func testResearchSyntheticGoalNeedsCompleteHostMetadata() {
    var cognition = researchCognition()
    cognition.longHorizonGoalId = "goal"
    cognition.sourceEvent.conversationId = "global-goal:goal"
    XCTAssertNil(GlobalResearchSourceScope.sourceIds(from: cognition))
    cognition.sourceEvent.metadata = ["long_horizon_goal_id": "goal", "origin": "global_long_horizon_scheduler",
      "source_conversation_ids": "conversation-main,private"]
    XCTAssertEqual(GlobalResearchSourceScope.sourceIds(from: cognition), ["conversation-main", "private"])
    cognition.sourceEvent.metadata["long_horizon_goal_id"] = "other"
    XCTAssertNil(GlobalResearchSourceScope.sourceIds(from: cognition))
  }

  func testResearchSourceProofRoundtripAndLegacyDecodeDoNotInventSources() throws {
    var candidate = task(.quickFact)
    candidate.sourceConversationIds = ["conversation-main", "secondary"]
    let bytes = try JSONEncoder().encode(candidate)
    XCTAssertEqual(try JSONDecoder().decode(GlobalResearchTask.self, from: bytes), candidate)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    object.removeValue(forKey: "sourceConversationIds")
    let legacy = try JSONDecoder().decode(GlobalResearchTask.self,
      from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNil(legacy.sourceConversationIds)
    XCTAssertFalse(GlobalResearchSourceScope.allows(legacy, scope: researchScope()))
  }

  func testResearchResponseBindingRejectsWrongOwnerAndAcceptsBlankLegacyScope() throws {
    let step = try XCTUnwrap(GlobalResearchExecutorPolicy.executeNext(
      state: GlobalResearchExecutorState(tasks: [task(.quickFact)]),
      resources: [resource("cloud-models", .cloudModel)], nowMillis: now))
    let request = try XCTUnwrap(step.state.dispatchRequests.first)
    let response = AgentConnectorResponse(sourceMessageId: request.sourceMessageId,
      contactId: request.resourceId, content: "Evidence", receivedAtMillis: now)
    XCTAssertTrue(GlobalResearchSourceScope.matches(response, request: request))
    var wrong = response; wrong.sourceMessageId = 0
    XCTAssertFalse(GlobalResearchSourceScope.matches(wrong, request: request))
    wrong = response; wrong.contactId = "other"
    XCTAssertFalse(GlobalResearchSourceScope.matches(wrong, request: request))
    wrong = response; wrong.conversationId = "other"
    XCTAssertFalse(GlobalResearchSourceScope.matches(wrong, request: request))
    wrong = response; wrong.turnId = "other"
    XCTAssertFalse(GlobalResearchSourceScope.matches(wrong, request: request))
    wrong = response; wrong.taskId = "other"
    XCTAssertFalse(GlobalResearchSourceScope.matches(wrong, request: request))
  }

  func testPublicResearchKeepsItsDedicatedPolicyWithoutPrivateSourceProof() {
    var candidate = task(.quickFact)
    candidate.id = PublicAttentionResearchPolicy.taskPrefix + "fixture"
    XCTAssertTrue(GlobalResearchSourceScope.allows(candidate, scope: researchScope()))
    XCTAssertFalse(GlobalResearchSourceScope.allows(candidate,
      scope: GlobalRealtimePlanningScope(enabled: false, conversations: [])))
  }

  func testExpiredResearchLeasePreservesTheFullSourceProof() {
    var candidate = task(.quickFact)
    candidate.sourceConversationIds = ["conversation-main", "secondary"]
    candidate.status = .running
    candidate.leaseExpiresAtMillis = now - 1
    let recovered = GlobalResearchTaskPolicy.recoverIfStale(candidate, nowMillis: now)
    XCTAssertEqual(recovered.status, .waitingForResource)
    XCTAssertEqual(recovered.sourceConversationIds, candidate.sourceConversationIds)
    XCTAssertFalse(GlobalResearchSourceScope.allows(recovered, scope: researchScope()))
    candidate.sourceConversationIds = ["conversation-main"]
    candidate.lastError = GlobalAgentEvidenceLifecyclePolicy.invalidatedReason
    XCTAssertNil(GlobalResearchExecutorPolicy.claimTask(from: [candidate], nowMillis: now,
      eligible: { GlobalResearchSourceScope.allows($0, scope: self.researchScope()) }))
  }

  private func researchScope() -> GlobalRealtimePlanningScope {
    GlobalRealtimePlanningScope(enabled: true, conversations: [
      AgentConversation(id: "conversation-main", title: "Main", createdAt: 1, updatedAt: 1),
      AgentConversation(id: "private", title: "Private", createdAt: 1, updatedAt: 1, privateMode: true),
      AgentConversation(id: "paused", title: "Paused", createdAt: 1, updatedAt: 1, trackingPaused: true)
    ])
  }

  private func researchCognition() -> GlobalCognitionTask {
    GlobalCognitionTask(id: "cognition", sourceEvent: GlobalConversationEvent(id: "event",
      type: .messageCreated, conversationId: "conversation-main", actor: .user,
      timestampMillis: now, content: "Research", conversationTitle: "Research"),
      baselineUnderstanding: GlobalUnderstanding(topic: "Research", project: ""), baselineIntent: "research")
  }

  func testExecuteNextDispatchesEvidenceUnitsWithinParallelismAndBudget() throws {
    let researchTask = task(.deepResearch)
    let step = try XCTUnwrap(GlobalResearchExecutorPolicy.executeNext(
      state: GlobalResearchExecutorState(tasks: [researchTask]),
      resources: [
        resource("cloud-models", .cloudModel),
        resource("codex", .pairedAgent),
        resource("hermes", .pairedAgent)
      ],
      context: context,
      nowMillis: now
    ))

    XCTAssertEqual(step.result.status, .running)
    XCTAssertEqual(step.state.dispatchRequests.count, 3)
    XCTAssertTrue(step.state.dispatchRequests.allSatisfy { $0.stage == .evidence })
    XCTAssertEqual(step.state.modelBudget.activeLeases.count, 3)
    let updated = try XCTUnwrap(step.state.task(id: researchTask.id))
    XCTAssertEqual(updated.researchPlan.runningUnits().count, 3)
    XCTAssertEqual(updated.researchPlan.pendingUnits().count, 1)
    XCTAssertTrue(step.state.dispatchRequests.allSatisfy { $0.prompt.contains("Independent evidence assignment") })
  }

  func testBudgetDenialWaitsWithoutDispatchAndReleasesClaimAttempt() throws {
    let lease = GlobalModelCallLease(
      id: "busy",
      kind: .researchEvidence,
      ownerKey: "other",
      startedAtMillis: now,
      expiresAtMillis: now + 60_000
    )
    let budget = GlobalModelCallBudgetState(activeLeases: [lease])
    let researchTask = task(.quickFact)

    let step = try XCTUnwrap(GlobalResearchExecutorPolicy.executeNext(
      state: GlobalResearchExecutorState(tasks: [researchTask], modelBudget: budget),
      resources: [resource("cloud-models", .cloudModel)],
      budgetLimits: GlobalResearchExecutorBudgetLimits(dailyLimit: 10, concurrencyLimit: 1),
      nowMillis: now
    ))

    XCTAssertEqual(step.result.status, .waitingForResource)
    XCTAssertTrue(step.state.dispatchRequests.isEmpty)
    let updated = try XCTUnwrap(step.state.task(id: researchTask.id))
    XCTAssertEqual(updated.attemptCount, 0)
    XCTAssertEqual(updated.nextAttemptAtMillis, now + 60_000)
    XCTAssertEqual(updated.lastError, "The background model-call budget is temporarily unavailable")
  }

  func testConsumesEvidenceResponseThenDispatchesAndCompletesSynthesis() throws {
    let researchTask = task(.quickFact)
    let first = try XCTUnwrap(GlobalResearchExecutorPolicy.executeNext(
      state: GlobalResearchExecutorState(tasks: [researchTask]),
      resources: [resource("cloud-models", .cloudModel)],
      context: context,
      nowMillis: now
    ))
    let evidenceDispatch = try XCTUnwrap(first.state.dispatchRequests.first)

    let evidence = AgentConnectorResponse(
      sourceMessageId: evidenceDispatch.sourceMessageId,
      contactId: "cloud-models",
      content: evidenceResult("GalaxySSI supports iOS 15 and later."),
      inputTokens: 120,
      outputTokens: 80,
      costMicros: 25,
      receivedAtMillis: now + 1_000
    )
    let evidenceStep = try XCTUnwrap(GlobalResearchExecutorPolicy.consumeConnectorResponse(
      evidence,
      state: first.state,
      context: context,
      nowMillis: now + 1_000
    ))
    XCTAssertEqual(evidenceStep.result.status, .waitingForResource)
    XCTAssertTrue(evidenceStep.state.dispatchRequests.isEmpty)
    let collected = try XCTUnwrap(evidenceStep.state.task(id: researchTask.id))
    XCTAssertEqual(collected.researchPlan.phase, .synthesisPending)
    XCTAssertGreaterThan(collected.evidenceLedger.sources.count, 0)

    let synthesisStart = try XCTUnwrap(GlobalResearchExecutorPolicy.executeNext(
      state: evidenceStep.state,
      resources: [resource("cloud-models", .cloudModel)],
      context: context,
      nowMillis: now + 2_000
    ))
    let synthesisDispatch = try XCTUnwrap(synthesisStart.state.dispatchRequests.first)
    XCTAssertEqual(synthesisDispatch.stage, .synthesis)
    XCTAssertTrue(synthesisDispatch.prompt.contains("Evidence ledger"))

    let synthesis = AgentConnectorResponse(
      sourceMessageId: synthesisDispatch.sourceMessageId,
      contactId: "cloud-models",
      content: "Verified: GalaxySSI supports iOS 15 and later. https://developer.apple.com/documentation/swiftui",
      inputTokens: 160,
      outputTokens: 70,
      costMicros: 30,
      receivedAtMillis: now + 3_000
    )
    let completedStep = try XCTUnwrap(GlobalResearchExecutorPolicy.consumeConnectorResponse(
      synthesis,
      state: synthesisStart.state,
      context: context,
      nowMillis: now + 3_000
    ))
    let completed = try XCTUnwrap(completedStep.state.task(id: researchTask.id))
    XCTAssertEqual(completed.status, .completed)
    XCTAssertEqual(completed.resourceId, "cloud-models")
    XCTAssertFalse(completed.result.isBlank)
    XCTAssertEqual(completedStep.state.proactiveMessages.count, 1)
    XCTAssertEqual(completedStep.state.events.first?.metadata["research_task_id"], researchTask.id)
    XCTAssertTrue(completedStep.state.modelBudget.activeLeases.isEmpty)
  }

  func testNoResourceSynthesizesLocallyFromCompletedEvidence() throws {
    var researchTask = task(.quickFact)
    researchTask.researchPlan = completedPlan(for: researchTask, result: evidenceResult("The release is available."))
    researchTask.evidenceLedger = GlobalEvidenceEvaluator.build(plan: researchTask.researchPlan, nowMillis: now)
    researchTask.status = .waitingForResource
    researchTask.nextAttemptAtMillis = now

    let step = try XCTUnwrap(GlobalResearchExecutorPolicy.executeNext(
      state: GlobalResearchExecutorState(tasks: [researchTask]),
      resources: [],
      context: context,
      nowMillis: now + 1_000
    ))

    let completed = try XCTUnwrap(step.state.task(id: researchTask.id))
    XCTAssertEqual(completed.status, .completed)
    XCTAssertEqual(completed.resourceId, "local-evidence-synthesis")
    XCTAssertTrue(completed.result.contains("Research findings"))
    XCTAssertTrue(step.state.dispatchRequests.isEmpty)
  }

  func testContinuousMonitorSchedulesWithoutNotificationWhenFactsDoNotChange() throws {
    var monitor = task(.continuousMonitor)
    monitor.result = "MATERIAL_CHANGE: no\nSupported version is 1.2.3."
    monitor.evidenceUris = ["https://developer.apple.com/documentation/swiftui"]
    monitor.lastCompletedAtMillis = now - 86_400_000
    monitor.monitorIntervalMillis = 60 * 60 * 1_000
    monitor.researchPlan = completedPlan(
      for: monitor,
      result: "CLAIM: Supported version is 1.2.3. | SOURCE: https://developer.apple.com/documentation/swiftui | DATE: 2026-07-30"
    )
    monitor.researchPlan.qualityExpansionCount = 2
    monitor.evidenceLedger = GlobalEvidenceEvaluator.build(plan: monitor.researchPlan, nowMillis: now)
    monitor.status = .waitingForResource
    monitor.nextAttemptAtMillis = now

    let start = try XCTUnwrap(GlobalResearchExecutorPolicy.executeNext(
      state: GlobalResearchExecutorState(tasks: [monitor]),
      resources: [resource("cloud-models", .cloudModel)],
      nowMillis: now + 1_000
    ))
    let dispatch = try XCTUnwrap(start.state.dispatchRequests.first)
    XCTAssertEqual(dispatch.stage, .synthesis)

    let response = AgentConnectorResponse(
      sourceMessageId: dispatch.sourceMessageId,
      contactId: "cloud-models",
      content: monitor.result,
      receivedAtMillis: now + 2_000
    )
    let step = try XCTUnwrap(GlobalResearchExecutorPolicy.consumeConnectorResponse(
      response,
      state: start.state,
      nowMillis: now + 2_000
    ))

    let scheduled = try XCTUnwrap(step.state.task(id: monitor.id))
    XCTAssertEqual(scheduled.status, .scheduled)
    XCTAssertEqual(scheduled.nextAttemptAtMillis, now + 2_000 + 60 * 60 * 1_000)
    XCTAssertTrue(step.state.proactiveMessages.isEmpty)
  }

  private var context: GlobalResearchExecutionContext {
    GlobalResearchExecutionContext(
      conversationContext: "Conversation context: the user is building the iOS client.",
      realtimeContext: "Realtime context: active research task is isolated.",
      worldContext: "World context: GalaxySSI mobile parity work."
    )
  }

  private func task(_ depth: GlobalResearchDepth) -> GlobalResearchTask {
    GlobalResearchTask(
      id: "research-\(depth.rawValue.lowercased())",
      sourceEventId: "event-\(depth.rawValue.lowercased())",
      sourceConversationId: "conversation-main",
      topic: "GalaxySSI iOS",
      question: "Verify whether GalaxySSI iOS supports iOS 15 and later.",
      depth: depth,
      preferredSources: ["official", "primary"],
      createdAtMillis: now - 10_000,
      updatedAtMillis: now - 10_000
    )
  }

  private func resource(
    _ id: String,
    _ transport: GlobalResearchResourceTransport
  ) -> GlobalResearchExecutorResource {
    GlobalResearchExecutorResource(id: id, transport: transport, contactId: id)
  }

  private func completedPlan(for task: GlobalResearchTask, result: String) -> GlobalResearchPlan {
    let initial = GlobalResearchPlanBuilder.create(task: task, nowMillis: now)
    let units = initial.units.map { unit -> GlobalResearchUnit in
      var completed = unit
      completed.status = .completed
      completed.resourceId = "cloud-models"
      completed.attemptCount = 1
      completed.result = result
      completed.evidenceUris = GlobalEvidenceEvaluator.extractUrls(result)
      completed.completedAtMillis = now
      return completed
    }
    return GlobalResearchPlan(
      id: initial.id,
      depth: initial.depth,
      phase: .synthesisPending,
      units: units,
      qualityExpansionCount: initial.qualityExpansionCount,
      createdAtMillis: initial.createdAtMillis,
      updatedAtMillis: now
    )
  }

  private func evidenceResult(_ claim: String) -> String {
    "CLAIM: \(claim) | SOURCE: https://developer.apple.com/documentation/swiftui | DATE: 2026-07-30"
  }

  private let now: Int64 = 1_786_000_000_000
}
