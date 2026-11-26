import Foundation
import XCTest
@testable import GalaxySSI

@MainActor
final class AgentEvalOpsTests: XCTestCase {
  func testKnowledgeGapSourceProofRoundtripAndLegacyDecode() throws {
    var gap = knowledgeGap()
    gap.sourceConversationIds = ["a", "b"]
    let bytes = try JSONEncoder().encode(gap)
    XCTAssertEqual(try JSONDecoder().decode(AgentKnowledgeGap.self, from: bytes), gap)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    object.removeValue(forKey: "sourceConversationIds")
    let legacy = try JSONDecoder().decode(AgentKnowledgeGap.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNil(legacy.sourceConversationIds)
  }

  func testKnowledgeGapDetectorUnionsAllObservedConversationSources() throws {
    try withKnowledgeGapStores { governance, _, _ in
      var first = recordedRun(runId: "first", request: "Verify app compatibility", status: .failed)
      first.conversationId = "a"
      let gap = try XCTUnwrap(AgentKnowledgeGapDetector.observe(store: governance, run: first, sample: gapSample("first")))
      XCTAssertEqual(gap.sourceConversationIds, ["a"])
      var second = first; second.runId = "second"; second.conversationId = "b"
      let merged = try XCTUnwrap(AgentKnowledgeGapDetector.observe(store: governance, run: second, sample: gapSample("second")))
      XCTAssertEqual(merged.id, gap.id)
      XCTAssertEqual(merged.sourceConversationIds, ["a", "b"])
      XCTAssertEqual(governance.gaps().first?.sourceConversationIds, ["a", "b"])
    }
  }

  func testKnowledgeGapLegacyProseDoesNotAcquireInferredSourceProof() throws {
    try withKnowledgeGapStores { governance, _, _ in
      let run = recordedRun(runId: "first", request: "Verify app compatibility", status: .failed)
      var gap = try XCTUnwrap(AgentKnowledgeGapDetector.observe(store: governance, run: run, sample: gapSample("first")))
      gap.sourceConversationIds = nil
      _ = governance.upsertGap(gap)
      var next = run; next.runId = "next"; next.conversationId = "new-source"
      let merged = try XCTUnwrap(AgentKnowledgeGapDetector.observe(store: governance, run: next, sample: gapSample("next")))
      XCTAssertNil(merged.sourceConversationIds)
    }
  }

  func testKnowledgeGapBlankAndLabOriginsRemainUnproven() throws {
    try withKnowledgeGapStores { governance, _, _ in
      for origin in ["", "lab:fixture"] {
        var run = recordedRun(runId: "run-\(origin)", request: "Verify app compatibility", status: .failed)
        run.conversationId = origin
        let gap = try XCTUnwrap(AgentKnowledgeGapDetector.observe(store: governance, run: run, sample: gapSample(run.runId)))
        XCTAssertNil(gap.sourceConversationIds)
      }
    }
  }

  func testKnowledgeGapRejectsMismatchedRunAndEvaluation() throws {
    try withKnowledgeGapStores { governance, _, _ in
      let run = recordedRun(runId: "owner", request: "Verify app compatibility", status: .failed)
      XCTAssertNil(AgentKnowledgeGapDetector.observe(store: governance, run: run, sample: gapSample("other")))
      XCTAssertTrue(governance.gaps().isEmpty)
    }
  }

  func testKnowledgeGapResearchCarriesAllSourcesAndUsesCurrentScope() async throws {
    try await withKnowledgeGapStoresAsync { governance, research, _ in
      var gap = knowledgeGap(); gap.sourceConversationIds = ["a", "b"]
      _ = governance.upsertGap(gap)
      let bridge = AgentKnowledgeGapResearchBridge(researchStore: research, governance: governance)
      bridge.install { false }; await bridge.observe(gap).value
      XCTAssertTrue(research.state().tasks.isEmpty)
      bridge.install { true }; await bridge.observe(gap).value; await bridge.observe(gap).value
      let state = research.state()
      XCTAssertEqual(state.tasks.count, 1)
      let task = try XCTUnwrap(state.tasks.first)
      XCTAssertEqual(task.sourceConversationId, "a")
      XCTAssertEqual(task.sourceConversationIds, ["a", "b"])
      XCTAssertEqual(governance.gaps().first?.status, .researching)
      let allowed = GlobalRealtimePlanningScope(enabled: true, conversations: [
        AgentConversation(id: "a", title: "A", createdAt: 1, updatedAt: 1),
        AgentConversation(id: "b", title: "B", createdAt: 1, updatedAt: 1)
      ])
      XCTAssertTrue(GlobalResearchSourceScope.allows(task, scope: allowed))
      let revoked = GlobalRealtimePlanningScope(enabled: true, conversations: [
        AgentConversation(id: "a", title: "A", createdAt: 1, updatedAt: 1),
        AgentConversation(id: "b", title: "B", createdAt: 1, updatedAt: 1, privateMode: true)
      ])
      XCTAssertFalse(GlobalResearchSourceScope.allows(task, scope: revoked))
    }
  }

  func testKnowledgeGapResearchDoesNotAuthorizeMissingEmptyOrMalformedSources() async throws {
    try await withKnowledgeGapStoresAsync { governance, research, _ in
      let bridge = AgentKnowledgeGapResearchBridge(researchStore: research, governance: governance)
      bridge.install { true }
      let cases: [Set<String>?] = [nil, [], [""], [" a "]]
      for sources in cases {
        var gap = knowledgeGap(); gap.sourceConversationIds = sources
        _ = governance.upsertGap(gap); await bridge.observe(gap).value
      }
      XCTAssertTrue(research.state().tasks.isEmpty)
      XCTAssertTrue(governance.decisions().isEmpty)
      XCTAssertEqual(governance.gaps().first?.status, .open)
    }
  }

  func testKnowledgeGapFailedResearchSaveDoesNotAdvanceGovernance() async throws {
    try await withKnowledgeGapStoresAsync { governance, _, file in
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      let blocker = file.deletingLastPathComponent().appendingPathComponent("blocker")
      try Data("file instead of directory".utf8).write(to: blocker)
      let research = GalaxySSIGlobalResearchRuntimeStore(fileURL: blocker.appendingPathComponent("state.json"))
      let bridge = AgentKnowledgeGapResearchBridge(researchStore: research, governance: governance)
      bridge.install { true }
      var gap = knowledgeGap(); gap.sourceConversationIds = ["a"]
      _ = governance.upsertGap(gap); await bridge.observe(gap).value
      XCTAssertFalse(research.lastErrorDescription.isEmpty)
      XCTAssertEqual(governance.gaps().first?.status, .open)
      XCTAssertTrue(governance.decisions().isEmpty)
    }
  }

  func testKnowledgeGapUnreadableResearchStateIsNotOverwritten() async throws {
    try await withKnowledgeGapStoresAsync { governance, research, file in
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      let bytes = Data("unreadable state".utf8); try bytes.write(to: file)
      let bridge = AgentKnowledgeGapResearchBridge(researchStore: research, governance: governance)
      bridge.install { true }
      var gap = knowledgeGap(); gap.sourceConversationIds = ["a"]
      _ = governance.upsertGap(gap); await bridge.observe(gap).value
      XCTAssertEqual(try Data(contentsOf: file), bytes)
      XCTAssertEqual(governance.gaps().first?.status, .open)
      XCTAssertTrue(governance.decisions().isEmpty)
    }
  }

  func testKnowledgeGapSourceSetIsNotTruncatedWithRunReferenceHistory() throws {
    try withKnowledgeGapStores { governance, _, _ in
      for index in 0..<45 {
        var run = recordedRun(runId: "run-\(index)", request: "Verify app compatibility", status: .failed)
        run.conversationId = "conversation-\(index)"
        _ = AgentKnowledgeGapDetector.observe(store: governance, run: run, sample: gapSample(run.runId))
      }
      let gap = try XCTUnwrap(governance.gaps().first)
      XCTAssertEqual(gap.sourceRunIds.count, 40)
      XCTAssertEqual(gap.sourceConversationIds?.count, 45)
    }
  }

  func testKnowledgeGapPolicyRunsOnMainActorAfterPreviousObservationCompletes() async throws {
    try await withKnowledgeGapStoresAsync { governance, research, _ in
      let bridge = AgentKnowledgeGapResearchBridge(researchStore: research, governance: governance)
      let probe = KnowledgeGapPolicyProbe()
      probe.research = research
      bridge.install {
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertEqual(probe.research?.state().tasks.count ?? -1, probe.reads)
        probe.reads += 1
        return true
      }
      var first = knowledgeGap(); first.id = "first"; first.sourceConversationIds = ["a"]
      var second = first; second.id = "second"
      _ = governance.upsertGap(first); _ = governance.upsertGap(second)
      let firstTask = bridge.observe(first)
      let secondTask = bridge.observe(second)
      await secondTask.value; await firstTask.value
      XCTAssertEqual(probe.reads, 2)
      XCTAssertEqual(research.state().tasks.count, 2)
    }
  }

  func testKnowledgeGapPolicyIsReadWhenQueuedWorkExecutesNotWhenEnqueued() async throws {
    try await withKnowledgeGapStoresAsync { governance, research, _ in
      let bridge = AgentKnowledgeGapResearchBridge(researchStore: research, governance: governance)
      let probe = KnowledgeGapPolicyProbe()
      bridge.install { probe.reads += 1; return probe.enabled }
      var gap = knowledgeGap(); gap.sourceConversationIds = ["a"]
      _ = governance.upsertGap(gap)
      let work = bridge.observe(gap)
      probe.enabled = false
      await work.value
      XCTAssertEqual(probe.reads, 1)
      XCTAssertTrue(research.state().tasks.isEmpty)
      XCTAssertEqual(governance.gaps().first?.status, .open)
    }
  }

  private func withKnowledgeGapStores(_ body: (AgentCognitiveGovernanceStore, GalaxySSIGlobalResearchRuntimeStore, URL) throws -> Void) throws {
    let suite = "gap-sources-\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
    let governance = AgentCognitiveGovernanceStore(defaults: defaults, secrets: InMemorySecretStore())
    let file = directory.appendingPathComponent("state.json")
    try body(governance, GalaxySSIGlobalResearchRuntimeStore(fileURL: file), file)
  }

  private func withKnowledgeGapStoresAsync(_ body: @MainActor (AgentCognitiveGovernanceStore, GalaxySSIGlobalResearchRuntimeStore, URL) async throws -> Void) async throws {
    let suite = "gap-sources-\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
    let governance = AgentCognitiveGovernanceStore(defaults: defaults, secrets: InMemorySecretStore())
    let file = directory.appendingPathComponent("state.json")
    try await body(governance, GalaxySSIGlobalResearchRuntimeStore(fileURL: file), file)
  }

  private func knowledgeGap() -> AgentKnowledgeGap {
    AgentKnowledgeGap(id: "gap", topic: "Compatibility", knownSummary: "Missing evidence",
      unknownQuestions: ["Which official evidence is available?"], missingEvidence: ["final_response"], priority: 0.8)
  }

  private func gapSample(_ runId: String) -> AgentEvalSample {
    var value = sample(runId: runId, passed: false, completedAtMillis: 200)
    value.failureReasons = ["missing_evidence:final_response"]
    return value
  }

  func testCompletionWorkerDoesNotBlockMainActorAndDeduplicatesPendingRuns() async {
    let queue = AgentCompletionWorkQueue()
    let release = DispatchSemaphore(value: 0)
    let started = expectation(description: "background learning started")
    let finished = expectation(description: "later work runs after failure")
    enum ExpectedFailure: Error { case observation }
    XCTAssertTrue(queue.enqueue(runID: "first") {
      XCTAssertFalse(Thread.isMainThread)
      started.fulfill()
      XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
      throw ExpectedFailure.observation
    })
    defer { release.signal() }
    XCTAssertFalse(queue.enqueue(runID: "first") { XCTFail("duplicate observation") })
    XCTAssertTrue(queue.enqueue(runID: "second") {
      // A worker may recheck UI-owned policy without a synchronous wait on the main thread.
      await MainActor.run { finished.fulfill() }
    })
    await fulfillment(of: [started], timeout: 3)
    release.signal()
    await fulfillment(of: [finished], timeout: 3)
    XCTAssertFalse(queue.enqueue(runID: " ") { XCTFail("blank run") })
  }

  func testOutcomeContractClassifiesCodeAndRecoveryEvidence() {
    let code = AgentOutcomeContractCompiler.compile(runId: "code-1", goal: "Write and test Swift code")
    XCTAssertEqual(code.taskClass, .code)
    XCTAssertTrue(code.requiredEvidence.contains(.finalResponse))
    XCTAssertTrue(code.requiredEvidence.contains(.toolReceipt))
    XCTAssertTrue(code.requiredEvidence.contains(.artifactDigest))

    let recovery = AgentOutcomeContractCompiler.compile(
      runId: "recovery-1",
      goal: "Recover this task after network loss"
    )
    XCTAssertEqual(recovery.taskClass, .reliability)
    XCTAssertEqual(recovery.condition, .networkLoss)
    XCTAssertTrue(recovery.requiredEvidence.contains(.recoveryEvent))
  }

  func testEvalStatisticsMeasureVerifiedPassRatesAndRepeatedTrials() {
    let samples = [
      sample(runId: "1", passed: true, completedAtMillis: 1),
      sample(runId: "2", passed: true, completedAtMillis: 2),
      sample(runId: "3", passed: true, completedAtMillis: 3),
      sample(runId: "4", passed: false, completedAtMillis: 4)
    ]

    let dashboard = AgentEvalStatistics.dashboard(samples: samples, k: 2, nowMillis: 10)

    XCTAssertEqual(dashboard.totalRuns, 4)
    XCTAssertEqual(dashboard.verifiedRuns, 4)
    XCTAssertEqual(dashboard.passAt1, 0.75, accuracy: 0.0001)
    XCTAssertEqual(dashboard.passPowerK, 0.5, accuracy: 0.0001)
    XCTAssertEqual(AgentEvalStatistics.theoreticalPassPowerK(passAt1: 0.5, k: 2), 0.25, accuracy: 0.0001)
  }

  func testAgentLabKeepsOnePhysicalRuntimeAndPrefersConcreteAlias() {
    let generic = registration(id: "codex", name: "Codex")
    let concrete = registration(id: "desktop-1:codex", name: "Codex Agent \u{00b7} DESKTOP-T14")

    let selected = AgentLabAgentSelectionPolicy.independentAgents([generic, concrete])

    XCTAssertEqual(selected.map(\.agentId), ["desktop-1:codex"])
  }

  func testCurrentDashboardUsesNewestCompleteCampaignWithoutDeletingHistory() throws {
    let oldTrial = AgentLabTrial(
      agentId: "agent-a", blindAlias: "Agent A", repetition: 1,
      runId: "old-run", status: .failed
    )
    let currentTrials = (1...10).map { index in
      AgentLabTrial(
        agentId: "agent-a", blindAlias: "Agent A", repetition: index,
        runId: "current-\(index)", status: .completed
      )
    }
    let old = AgentLabCampaign(
      task: "old", outcomeContract: AgentOutcomeContractCompiler.compile(runId: "old", goal: "old"),
      trials: [oldTrial], status: .readyForReview, createdAtMillis: 1, updatedAtMillis: 1_000
    )
    let current = AgentLabCampaign(
      task: "current", outcomeContract: AgentOutcomeContractCompiler.compile(runId: "current", goal: "current"),
      trials: currentTrials, blindReview: false, status: .readyForReview,
      createdAtMillis: 2, updatedAtMillis: 2_000
    )
    let history = [sample(runId: "old-run", passed: false, completedAtMillis: 1_000)] +
      currentTrials.enumerated().map { offset, trial in
        sample(runId: trial.runId, passed: true, completedAtMillis: Int64(2_000 + offset))
      }

    let selected = try XCTUnwrap(AgentLabDashboardPolicy.currentCompletedSamples(
      campaigns: [old, current],
      samples: history
    ))
    let dashboard = AgentEvalStatistics.dashboard(samples: selected, k: 10)

    XCTAssertEqual(history.count, 11)
    XCTAssertEqual(dashboard.totalRuns, 10)
    XCTAssertEqual(dashboard.passAt1, 1, accuracy: 0.0001)
  }

  func testLabFailureCodeSeparatesTimeoutDispatchAndEmptyResponse() {
    let timeout = AgentEvolutionLabRuntimeError(message: "response timed out")
    XCTAssertEqual(
      AgentLabRunFailurePolicy.code(error: timeout, terminalType: nil, output: ""),
      "response_timeout"
    )
    XCTAssertEqual(
      AgentLabRunFailurePolicy.code(error: nil, terminalType: .runFailed, output: "", detail: "failed"),
      "dispatch_failed"
    )
    XCTAssertEqual(
      AgentLabRunFailurePolicy.code(error: nil, terminalType: .runCompleted, output: ""),
      "empty_response"
    )
  }

  func testLabRecoveryUsesFreshIdentityAndWatchdogPolicy() {
    let trial = AgentLabTrial(
      id: "trial",
      agentId: "agent-a",
      blindAlias: "Agent A",
      repetition: 1,
      runId: "old-run",
      status: .running
    )
    let campaign = AgentLabCampaign(
      id: "campaign",
      task: "evaluate",
      outcomeContract: AgentOutcomeContractCompiler.compile(runId: "campaign", goal: "evaluate"),
      trials: [trial],
      status: .running,
      createdAtMillis: 1,
      updatedAtMillis: 1_000
    )

    let recovered = AgentLabRecoveryPolicy.resetIncomplete(
      campaign,
      condition: .processDeath,
      nowMillis: 2_000
    )
    let recoveredTrial = recovered.trials[0]

    XCTAssertEqual(recovered.status, .draft)
    XCTAssertEqual(recoveredTrial.status, .pending)
    XCTAssertEqual(recoveredTrial.previousRunId, "old-run")
    XCTAssertEqual(recoveredTrial.recoveryAttempt, 1)
    XCTAssertEqual(
      AgentLabRunIdentity.idempotencyKey(campaignId: campaign.id, trial: recoveredTrial),
      "agent-lab:campaign:trial:recovery:1"
    )
    XCTAssertTrue(AgentLabStallRecoveryPolicy.shouldRecover(
      campaign: campaign,
      hasActiveTask: false,
      nowMillis: 1_001,
      staleAfterMillis: 10_000
    ))
    XCTAssertTrue(AgentLabStallRecoveryPolicy.shouldRecover(
      campaign: campaign,
      hasActiveTask: true,
      nowMillis: 20_000,
      staleAfterMillis: 10_000
    ))
  }

  func testLabStoreIndexesRunsAndResetsAllIncompleteTrials() throws {
    let suite = "AgentLabRecoveryTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    let secrets = InMemorySecretStore()
    let store = AgentLabStore(defaults: defaults, secrets: secrets, nowMillis: { 2_000 })
    let campaign = try XCTUnwrap(store.create(task: "evaluate", agentIds: ["agent-a"], repetitions: 2))
    let firstTrial = campaign.trials[0]
    _ = store.bindRun(campaignId: campaign.id, trialId: firstTrial.id, runId: "run-one")

    let reopened = AgentLabStore(defaults: defaults, secrets: secrets, nowMillis: { 3_000 })
    XCTAssertEqual(reopened.campaignForRun("run-one")?.id, campaign.id)
    let recovered = try XCTUnwrap(reopened.resetIncompleteTrials(
      campaignId: campaign.id,
      condition: .processDeath
    ))

    XCTAssertTrue(recovered.trials.allSatisfy { $0.status == .pending })
    XCTAssertEqual(recovered.trials.first?.previousRunId, "run-one")
    XCTAssertTrue(recovered.trials.allSatisfy { $0.recoveryAttempt == 1 })
    XCTAssertNil(reopened.campaignForRun("run-one"))
  }

  func testSyntheticLabRunsDoNotFeedPersonalLearning() {
    XCTAssertFalse(AgentEvalSideEffectPolicy.allowsPersonalLearning(conversationId: "lab:campaign"))
    XCTAssertTrue(AgentEvalSideEffectPolicy.allowsPersonalLearning(conversationId: "conversation"))
  }

  func testEvalStoreEncryptsSamplesAndPersistsNormalizedSettings() {
    let suite = "AgentEvalOpsTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = AgentEvalOpsStore(defaults: defaults, secrets: InMemorySecretStore())

    let settings = store.updateSettings { value in
      var updated = value
      updated.repeatedTrials = 99
      updated.minimumAutomaticRoutingSamples = 1
      return updated
    }
    store.saveSample(sample(runId: "encrypted-run", passed: true, completedAtMillis: 5))

    XCTAssertEqual(settings.repeatedTrials, 10)
    XCTAssertEqual(settings.minimumAutomaticRoutingSamples, 6)
    XCTAssertEqual(store.sample(runId: "encrypted-run")?.verdict, .passed)
    let encrypted = defaults.data(forKey: "\(AgentEvalOpsStore.defaultKey).encrypted.v1")
    XCTAssertNotNil(encrypted)
    XCTAssertFalse(encrypted.map { String(decoding: $0, as: UTF8.self).contains("encrypted-run") } ?? true)
    XCTAssertNil(defaults.object(forKey: AgentEvalOpsStore.defaultKey))
  }

  func testSensitiveRunIsNotCaptured() {
    let suite = "AgentEvalOpsPrivacyTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = AgentEvalOpsStore(defaults: defaults, secrets: InMemorySecretStore())
    let run = recordedRun(
      runId: "sensitive",
      request: "Use password=do-not-store to continue",
      status: .running
    )

    AgentEvalOpsService.observeRunStarted(run, store: store, device: deviceSnapshot(at: 1))

    XCTAssertNil(store.start(runId: run.runId))
  }

  func testAssessmentRequiresContractEvidence() {
    let start = AgentEvalRunStart(
      runId: "assessment",
      contract: AgentOutcomeContract(
        runId: "assessment",
        goal: "Research current release details",
        taskClass: .research,
        successCriteria: ["Return evidence"],
        requiredEvidence: [.finalResponse, .verifiedSource],
        maxDurationMillis: 10_000,
        createdAtMillis: 1
      ),
      device: deviceSnapshot(at: 1)
    )
    let run = recordedRun(
      runId: "assessment",
      request: start.contract.goal,
      status: .completed,
      finalOutput: ["text": .string("Completed")],
      completedAtMillis: 2_000
    )

    let result = AgentEvalOpsService.assess(
      start: start,
      completedDevice: deviceSnapshot(at: 2_000),
      run: run,
      events: []
    )

    XCTAssertEqual(result.verdict, .partial)
    XCTAssertFalse(result.verified)
    XCTAssertTrue(result.failureReasons.contains("missing_evidence:verified_source"))
  }

  func testQualityRoutingOnlySwitchesAfterVerifiedEvidenceThreshold() {
    let local = candidate(id: "local", targetId: "local-llm", trust: .phoneSystem, score: 500)
    let cloud = candidate(id: "cloud", targetId: "cloud-model:slow", trust: .cloudConfigured, score: 500)
    var settings = AgentEvalOpsSettings()
    settings.automaticQualityRoutingEnabled = true
    settings.minimumAutomaticRoutingSamples = 6
    let evidence = (0..<6).map {
      sample(runId: "local-\($0)", passed: true, resourceId: "local-llm", completedAtMillis: Int64($0))
    } + (0..<6).map {
      sample(runId: "cloud-\($0)", passed: false, resourceId: "cloud-model:slow", completedAtMillis: Int64($0 + 10))
    }

    let recommendation = AgentQualityAwareRoutingPolicy.recommend(
      goal: "Answer this request",
      requirements: AgentTaskRequirements(),
      candidates: [cloud, local],
      samples: evidence,
      actualResourceId: "cloud-model:slow",
      settings: settings
    )

    XCTAssertEqual(recommendation?.recommendedResourceId, "local-llm")
    XCTAssertEqual(recommendation?.shouldAutoSwitch, true)
    let decision = AgentRoutingDecision(requirements: AgentTaskRequirements(), primary: cloud, fallbacks: [local])
    XCTAssertEqual(
      AgentQualityAwareRoutingPolicy.apply(recommendation: recommendation, to: decision).primary?.resource.targetId,
      "local-llm"
    )
  }

  func testShadowRoutingStoreKeepsIndexedNewestRecordsAcrossInstances() {
    let suite = "AgentShadowRoutingIndexTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    let secrets = InMemorySecretStore()
    let key = "shadow-routing-test"

    for index in 0..<12 {
      AgentShadowRoutingStore(defaults: defaults, secrets: secrets, key: key).save(
        AgentShadowRoutingRecommendation(
          id: "recommendation-\(index)",
          scenarioId: "scenario-\(index)",
          taskClass: .general,
          actualResourceId: "actual",
          recommendedResourceId: "recommended",
          scores: [],
          shouldAutoSwitch: false,
          confidence: 0.5,
          createdAtMillis: Int64(index)
        )
      )
    }

    let reopened = AgentShadowRoutingStore(defaults: defaults, secrets: secrets, key: key)
    XCTAssertEqual(reopened.recent(limit: 3).map(\.id), [
      "recommendation-11", "recommendation-10", "recommendation-9"
    ])
    XCTAssertFalse(defaults.dictionaryRepresentation().keys.contains(key))
  }

  func testAttentionBudgetSuppressesLowValueInterruptions() {
    let high = AgentAttentionBudgetPolicy.evaluate(
      candidate: AgentAttentionCandidate(
        relevance: 1,
        novelty: 1,
        credibility: 1,
        actionability: 1,
        interruptionCost: 0.1,
        tokenCost: 0.1,
        batteryCost: 0.1
      ),
      threshold: 0.58
    )
    let low = AgentAttentionBudgetPolicy.evaluate(
      candidate: AgentAttentionCandidate(
        relevance: 0.1,
        novelty: 0.1,
        credibility: 0.1,
        actionability: 0.1,
        interruptionCost: 1,
        tokenCost: 1,
        batteryCost: 1
      ),
      threshold: 0.58
    )

    XCTAssertEqual(high.disposition, .notifyNow)
    XCTAssertEqual(low.disposition, .discard)
  }

  func testA2AAndACPAdaptersRoundTripRunRequests() {
    let request = AgentRunRequest(
      conversationId: "conversation",
      messageId: "message",
      taskId: "task",
      runId: "run",
      parentRunId: "",
      goal: "Inspect this result",
      deliveryMode: .respond,
      requiredCapabilities: [],
      context: [:],
      idempotencyKey: "run",
      createdAtMillis: 1
    )

    XCTAssertEqual(AgentA2ABoundaryAdapter().decodeRequest(
      AgentA2ABoundaryAdapter().encodeRequest(request)
    )?.goal, request.goal)
    XCTAssertEqual(AgentACPBoundaryAdapter().decodeRequest(
      AgentACPBoundaryAdapter().encodeRequest(request)
    )?.conversationId, request.conversationId)
  }

  func testSignedSkillMarkdownCanBeVerified() throws {
    let manifest = AgentSkillManifest(
      id: "eval-skill",
      name: "Eval Skill",
      version: "1.0.0",
      summary: "Evaluate an Agent run",
      instructions: "Evaluate the supplied run and return evidence."
    )
    let secrets = InMemorySecretStore()

    let signed = try AgentSkillMarkdownSigner.sign(AgentSkillMarkdownCodec.encode(manifest), secrets: secrets)
    let inspection = try XCTUnwrap(AgentSkillMarkdownSigner.inspect(signed))

    XCTAssertTrue(inspection.signed)
    XCTAssertTrue(inspection.signatureValid)
    XCTAssertEqual(inspection.manifest.id, manifest.id)
    XCTAssertFalse(inspection.manifest.autoInvoke)
  }

  func testShadowReleaseRollsBackCrashRegression() {
    let baseline = releaseMetrics(passAt1: 0.9, crashes: 0)
    let candidate = releaseMetrics(passAt1: 0.9, crashes: 1)

    let decision = AgentShadowReleasePolicy.compare(baseline: baseline, candidate: candidate)

    XCTAssertFalse(decision.promote)
    XCTAssertTrue(decision.rollback)
    XCTAssertTrue(decision.reasons.contains("crash_regression"))
  }

  func testProactiveFeedbackCompletesUnverifiedDeliverySample() {
    let suite = "AgentProactiveEvalTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = AgentEvalOpsStore(defaults: defaults, secrets: InMemorySecretStore())
    let message = GlobalProactiveMessage(
      id: "insight-1",
      sourceEventId: "event-1",
      sourceConversationId: "conversation-1",
      target: .currentConversation,
      title: "Risk",
      content: "Review this risk now",
      topic: "release",
      urgent: true,
      createdAtMillis: 1
    )
    let attention = AgentAttentionDecisionRecord(
      messageId: message.id,
      decision: AgentAttentionDecision(value: 0.9, threshold: 0.5, disposition: .notifyNow, reasons: []),
      relatedGoal: message.topic,
      whyNow: "New evidence",
      impactIfIgnored: "Delayed decision",
      createdAtMillis: 2
    )

    let pending = store.recordProactiveDelivery(message, attention: attention)
    let completed = store.recordProactiveFeedback(runId: pending.runId, relevant: true, accepted: true)

    XCTAssertEqual(pending.verdict, .unverified)
    XCTAssertEqual(completed?.verdict, .passed)
    XCTAssertEqual(completed?.verified, true)
  }

  func testIOSWorldCodecAcceptsAndroidWorldAliases() throws {
    let data = Data(#"{"tasks":[{"task_id":"settings","goal":"Open settings","success_criteria":[{"type":"foreground_package","operator":"contains","expected":"GalaxySSI"}]}]}"#.utf8)

    let tasks = try AgentIOSWorldCodec.decodeTasks(data, source: "fixture")

    XCTAssertEqual(tasks.first?.id, "settings")
    XCTAssertEqual(tasks.first?.verifiers.first?.kind, .foregroundScreen)
  }

  func testProtocolBoundaryRequiresEnabledFingerprintGrant() {
    let suite = "AgentProtocolBoundaryTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    let grants = AgentProtocolEndpointGrantStore(defaults: defaults, secrets: InMemorySecretStore())
    let gateway = AgentProtocolBoundaryGateway(grants: grants, settings: {
      var settings = AgentEvalOpsSettings()
      settings.protocolAdaptersEnabled = true
      return settings
    })
    let request = AgentRunRequest(
      conversationId: "conversation", messageId: "message", taskId: "task", runId: "run",
      parentRunId: "", goal: "Inspect this result", deliveryMode: .respond,
      requiredCapabilities: [.chat], context: [:], idempotencyKey: "run", createdAtMillis: 1
    )
    let payload = AgentA2ABoundaryAdapter().encodeRequest(request)

    XCTAssertEqual(gateway.decodeInbound(
      protocolKind: .a2a,
      endpointId: "peer",
      identityFingerprint: "sha256:trusted",
      payload: payload
    ).reason, "endpoint_not_authorized")
    XCTAssertTrue(grants.save(AgentProtocolEndpointGrant(
      endpointId: "peer", protocolKind: .a2a, displayName: "Peer",
      identityFingerprint: "sha256:trusted", allowedCapabilities: [.chat], enabled: true,
      createdAtMillis: 1, updatedAtMillis: 1
    )))
    XCTAssertEqual(gateway.decodeInbound(
      protocolKind: .a2a,
      endpointId: "peer",
      identityFingerprint: "sha256:impostor",
      payload: payload
    ).reason, "endpoint_identity_mismatch")
    XCTAssertTrue(gateway.decodeInbound(
      protocolKind: .a2a,
      endpointId: "peer",
      identityFingerprint: "sha256:trusted",
      payload: payload
    ).allowed)
  }

  func testMemoryHorizonUsesActualOldestMemoryTimestamp() {
    let day: Int64 = 86_400_000
    XCTAssertTrue(AgentMemoryHorizonPolicy.qualifies(
      oldestMemoryTimestampMillis: day,
      answeredAtMillis: 31 * day,
      requiredHorizonDays: 30
    ))
    XCTAssertFalse(AgentMemoryHorizonPolicy.qualifies(
      oldestMemoryTimestampMillis: 10 * day,
      answeredAtMillis: 31 * day,
      requiredHorizonDays: 30
    ))
  }

  func testContinuousEvalRejectsLabRunsAndHonorsCooldown() {
    var settings = AgentEvalOpsSettings()
    settings.continuousEvaluationEnabled = true
    var run = recordedRun(runId: "continuous", request: "Compare this answer", status: .completed)
    let value = sample(runId: run.runId, passed: true, completedAtMillis: 100)

    XCTAssertTrue(AgentContinuousEvalPolicy.decide(
      settings: settings, run: run, sample: value, availableAgentCount: 2,
      lastScheduledAtMillis: 0, nowMillis: 100
    ).schedule)
    XCTAssertEqual(AgentContinuousEvalPolicy.decide(
      settings: settings, run: run, sample: value, availableAgentCount: 2,
      lastScheduledAtMillis: 50, nowMillis: 100
    ).reason, "scenario_cooldown")
    run.conversationId = "lab:campaign"
    XCTAssertEqual(AgentContinuousEvalPolicy.decide(
      settings: settings, run: run, sample: value, availableAgentCount: 2,
      lastScheduledAtMillis: 0, nowMillis: 100
    ).reason, "agent_lab_run")
  }

  func testBlindReviewRedactsProviderIdentities() {
    let output = "Codex used deepseek-cloud and Claude to answer."
    let redacted = AgentBlindReviewSanitizer.redact(output, agentIds: ["deepseek-cloud"])

    XCTAssertFalse(redacted.localizedCaseInsensitiveContains("Codex"))
    XCTAssertFalse(redacted.localizedCaseInsensitiveContains("DeepSeek"))
    XCTAssertFalse(redacted.localizedCaseInsensitiveContains("Claude"))
  }

  func testShadowReleaseRequiresCanaryBeforeApproval() {
    let passing = AgentShadowReleaseDecision(promote: true, rollback: false, reasons: [])

    XCTAssertEqual(AgentShadowReleaseTransitionPolicy.afterComparison(current: .deviceShadow, decision: passing), .canary)
    XCTAssertEqual(AgentShadowReleaseTransitionPolicy.afterCanary(decision: passing), .waitingApproval)
  }

  private func sample(
    runId: String,
    passed: Bool,
    resourceId: String = "resource",
    completedAtMillis: Int64
  ) -> AgentEvalSample {
    AgentEvalSample(
      runId: runId,
      scenarioId: "scenario",
      taskClass: .general,
      resourceId: resourceId,
      verdict: passed ? .passed : .failed,
      contractSatisfied: passed,
      verified: true,
      durationMillis: passed ? 1_000 : 120_000,
      failureReasons: passed ? [] : ["failed"],
      evidenceKinds: passed ? [.finalResponse] : [],
      completedAtMillis: completedAtMillis
    )
  }

  private func deviceSnapshot(at millis: Int64) -> AgentDeviceEvalSnapshot {
    AgentDeviceEvalSnapshot(
      capturedAtMillis: millis,
      elapsedRealtimeMillis: millis,
      batteryPercent: 80,
      thermalStatus: 0,
      availableMemoryBytes: 1_000_000,
      networkAvailable: true,
      networkValidated: true
    )
  }

  private func recordedRun(
    runId: String,
    request: String,
    status: AgentRecordedRunStatus,
    finalOutput: AgentMcpJSONObject = [:],
    completedAtMillis: Int64 = 0
  ) -> AgentRecordedRun {
    AgentRecordedRun(
      runId: runId,
      conversationId: "conversation",
      taskThreadId: "task",
      originalRequest: request,
      finalOutput: finalOutput,
      executionResourceId: "local-llm",
      status: status,
      createdAtMillis: 1,
      completedAtMillis: completedAtMillis
    )
  }

  private func candidate(
    id: String,
    targetId: String,
    trust: AgentResourceTrust,
    score: Int
  ) -> AgentResourceCandidate {
    AgentResourceCandidate(
      resource: AgentResourceDescriptor(
        id: id,
        title: id,
        type: trust == .phoneSystem ? .onDeviceModel : .cloudModel,
        location: trust == .phoneSystem ? .phone : .cloud,
        status: .available,
        capabilities: [.chat],
        cost: trust == .phoneSystem ? .free : .high,
        latency: trust == .phoneSystem ? .instant : .slow,
        quality: .strong,
        supportsTools: false,
        targetId: targetId,
        trust: trust
      ),
      score: score
    )
  }

  private func releaseMetrics(passAt1: Double, crashes: Int) -> AgentShadowReleaseMetrics {
    AgentShadowReleaseMetrics(
      passAt1: passAt1,
      passPowerK: passAt1,
      averageLatencyMillis: 1_000,
      averageBatteryDeltaPercent: 1,
      peakThermalStatus: 1,
      crashCount: crashes,
      verifiedRuns: 12
    )
  }

  private func registration(id: String, name: String) -> AgentRegistration {
    AgentRegistration(
      agentId: id,
      installationId: "desktop-1",
      deviceId: "desktop-1",
      providerId: "desktop-1",
      displayName: name,
      kind: .agent,
      location: .trustedDesktop,
      status: .online,
      capabilities: [.chat],
      runtimeFailureDomain: "desktop-1:codex-app-server-or-cli",
      adapterType: "codex-app-server-or-cli",
      updatedAtMillis: 1
    )
  }
}

@MainActor
private final class KnowledgeGapPolicyProbe {
  var reads = 0
  var enabled = true
  var research: GalaxySSIGlobalResearchRuntimeStore?
}
