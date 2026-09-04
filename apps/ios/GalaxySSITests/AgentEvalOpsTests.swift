import Foundation
import XCTest
@testable import GalaxySSI

@MainActor
final class AgentEvalOpsTests: XCTestCase {
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
}
