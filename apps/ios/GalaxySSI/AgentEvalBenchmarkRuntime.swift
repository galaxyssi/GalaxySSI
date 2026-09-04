import Foundation
import UIKit

enum AgentBenchmarkAllocationPolicy {
  static func codexDeepSeek90To10(
    suite: AgentBenchmarkSuite,
    available: [AgentRegistration]
  ) throws -> AgentBenchmarkAllocation {
    guard let codex = select(available, matching: "codex") else {
      throw AgentBenchmarkError(message: "A currently available Codex Agent is required")
    }
    guard let deepSeek = select(available, matching: "deepseek") else {
      throw AgentBenchmarkError(message: "A currently available DeepSeek model is required")
    }
    guard codex.agentId != deepSeek.agentId else {
      throw AgentBenchmarkError(message: "Codex and DeepSeek must be different resources")
    }
    let soloCases = suite.cases.filter { $0.dimension != .multiAgent }
    guard !soloCases.isEmpty, soloCases.count.isMultiple(of: 10) else {
      throw AgentBenchmarkError(message: "The 90/10 profile requires a non-empty Single-Agent case count divisible by ten")
    }
    var assignments: [String: [String]] = [:]
    for (index, item) in soloCases.enumerated() {
      assignments[item.id] = [(index + 1).isMultiple(of: 10) ? deepSeek.agentId : codex.agentId]
    }
    let multiAgentCases = suite.cases.filter { $0.dimension == .multiAgent }
    multiAgentCases.forEach { assignments[$0.id] = [codex.agentId] }
    let codexCount = soloCases.filter { assignments[$0.id]?.contains(codex.agentId) == true }.count
    let deepSeekCount = soloCases.filter { assignments[$0.id]?.contains(deepSeek.agentId) == true }.count
    guard codexCount * 10 == soloCases.count * 9, deepSeekCount * 10 == soloCases.count else {
      throw AgentBenchmarkError(message: "Single-Agent benchmark allocation must remain 90% Codex and 10% DeepSeek")
    }
    let teams = Dictionary(uniqueKeysWithValues: multiAgentCases.map { ($0.id, [codex.agentId, deepSeek.agentId]) })
    return AgentBenchmarkAllocation(
      resources: [codex, deepSeek], resourceIdsByCase: assignments, teamResourceIdsByCase: teams)
  }

  private static func select(_ available: [AgentRegistration], matching name: String) -> AgentRegistration? {
    available.filter { registration in
      [registration.agentId, registration.displayName, registration.providerId,
       registration.providerProfile?.modelId ?? "", registration.providerProfile?.productId ?? ""]
        .contains { $0.localizedCaseInsensitiveContains(name) }
    }.max { left, right in
      if left.hasCapacity != right.hasCapacity { return !left.hasCapacity }
      return left.updatedAtMillis < right.updatedAtMillis
    }
  }
}

final class AgentBenchmarkCoordinator {
  private let suite: AgentBenchmarkSuite
  private let benchmarkStore: AgentBenchmarkStore
  private let labStore: AgentLabStore
  private let labRuntime: AgentEvolutionLabRuntime

  init(
    suite: AgentBenchmarkSuite = AgentEvalBenchmarkCatalog.standard,
    benchmarkStore: AgentBenchmarkStore = AgentBenchmarkStore(),
    labStore: AgentLabStore = AgentLabStore(),
    labRuntime: AgentEvolutionLabRuntime
  ) {
    self.suite = suite
    self.benchmarkStore = benchmarkStore
    self.labStore = labStore
    self.labRuntime = labRuntime
  }

  func startCodexDeepSeek90To10(repetitions: Int) async throws -> AgentBenchmarkSession {
    if let current = benchmarkStore.sessions().first, !progress(current).terminal {
      throw AgentBenchmarkError(message: "A comprehensive benchmark is already running")
    }
    let count = min(max(repetitions, suite.minimumRepetitions), suite.maximumRepetitions)
    let allocation = try AgentBenchmarkAllocationPolicy.codexDeepSeek90To10(
      suite: suite,
      available: try await labRuntime.availableAgents()
    )
    if suite.cases.contains(where: { $0.dimension == .iosWorld }) { AgentIOSWorldBenchmarkFixtures.install() }
    AgentBenchmarkMemoryFixtures.prepare(for: suite)
    let capabilities = AgentBenchmarkHarnessCapabilityProbe.current(multiAgent: false)
    let readiness = AgentBenchmarkPreflight.assess(
      suite: suite,
      capabilities: capabilities,
      memories: UserDefaultsAgentMemoryStore().snapshot().activeItems
    )
    let readyCases = suite.cases.filter { readiness[$0.id]?.status == .ready }
    guard !readyCases.isEmpty else {
      throw AgentBenchmarkError(message: "No benchmark case is ready for evidence-backed execution")
    }
    var campaignIds: [String: String] = [:]
    do {
      for item in readyCases {
        guard let campaign = labStore.create(
          task: AgentBenchmarkHarnessProtocol.executionPrompt(for: item, trialId: item.id),
          agentIds: allocation.resourceIdsByCase[item.id, default: []],
          repetitions: count,
          executionPolicyPrompt: item.taggedPrompt
        ) else {
          throw AgentBenchmarkError(message: "Unable to create benchmark campaign \(item.id)")
        }
        campaignIds[item.id] = campaign.id
      }
    } catch {
      campaignIds.values.forEach { _ = labStore.cancel(campaignId: $0) }
      throw error
    }
    let info = Bundle.main.infoDictionary ?? [:]
    let session = AgentBenchmarkSession(
      suiteId: suite.id,
      suiteVersion: suite.version,
      appVersionName: info["CFBundleShortVersionString"] as? String ?? "",
      appBuildNumber: info["CFBundleVersion"] as? String ?? "",
      deviceModel: UIDevice.current.model,
      systemVersion: UIDevice.current.systemVersion,
      repetitions: count,
      targetPassRate: suite.targetPassRate,
      caseIds: suite.cases.map(\.id),
      resources: allocation.resources.map(Self.snapshot),
      resourceIdsByCase: allocation.resourceIdsByCase,
      campaignIdsByCase: campaignIds,
      teamResourceIdsByCase: allocation.teamResourceIdsByCase,
      readinessByCase: readiness
    )
    benchmarkStore.saveSession(session)
    for campaignId in campaignIds.values { try labRuntime.start(campaignId: campaignId) }
    return session
  }

  func latest() -> AgentBenchmarkSession? {
    benchmarkStore.sessions().first { $0.suiteId == suite.id && $0.suiteVersion == suite.version }
  }

  @discardableResult
  func resumeLatestIncomplete(
    condition: AgentEvalCondition = .processDeath,
    reason: String = "Comprehensive benchmark resumed after interruption"
  ) -> Int {
    guard let session = benchmarkStore.sessions().first(where: {
      $0.status == .running && $0.suiteId == suite.id && $0.suiteVersion == suite.version
    }) else {
      return 0
    }
    return labRuntime.resumeIncomplete(
      campaignIds: Array(session.campaignIdsByCase.values),
      condition: condition,
      reason: reason
    )
  }

  func scorecard(_ session: AgentBenchmarkSession) -> AgentBenchmarkScorecard {
    AgentBenchmarkStatistics.scorecard(
      session: session,
      suite: suite,
      allResults: benchmarkStore.results(sessionId: session.id)
    )
  }

  func progress(_ session: AgentBenchmarkSession) -> AgentBenchmarkProgress {
    let campaigns = session.campaignIdsByCase.values.compactMap { labStore.get(id: $0) }
    let terminalCampaigns = campaigns.filter { [.readyForReview, .completed, .cancelled].contains($0.status) }.count
    let completedTrials = campaigns.reduce(0) { count, campaign in
      count + campaign.trials.filter { [.completed, .failed, .cancelled].contains($0.status) }.count
    }
    return AgentBenchmarkProgress(
      completedTrials: completedTrials,
      expectedTrials: session.expectedTrials,
      completedCampaigns: terminalCampaigns,
      totalCampaigns: session.scheduledCaseIds.count,
      terminal: session.status != .running ||
        (campaigns.count == session.scheduledCaseIds.count && terminalCampaigns == campaigns.count)
    )
  }

  func cancel(sessionId: String) async -> Bool {
    guard let session = benchmarkStore.session(id: sessionId) else { return false }
    for campaignId in session.campaignIdsByCase.values { _ = await labRuntime.cancel(campaignId: campaignId) }
    _ = benchmarkStore.markStatus(id: session.id, status: .cancelled)
    return true
  }

  func trialEvidence(
    _ session: AgentBenchmarkSession,
    dimension: AgentBenchmarkDimension? = nil,
    recordedRunStore: AgentRecordedRunStoring = UserDefaultsAgentRecordedRunStore(),
    eventStore: AgentRunEventPersistence = UserDefaultsAgentRunEventStore(),
    worldStore: AgentIOSWorldStore = AgentIOSWorldStore()
  ) -> [AgentBenchmarkTrialEvidence] {
    let resources = Dictionary(uniqueKeysWithValues: session.resources.map { ($0.resourceId, $0) })
    let runs = recordedRunStore.runs(for: "")
    return benchmarkStore.results(sessionId: session.id).reversed().compactMap { result in
      guard let item = suite.benchmarkCase(id: result.caseId), dimension == nil || item.dimension == dimension else {
        return nil
      }
      let run = runs.first { $0.runId == result.runId }
      let events = eventStore.events(runId: result.runId)
      let world = worldStore.results(limit: 500).first { $0.runId == result.runId }
      return AgentBenchmarkTrialEvidence(
        caseId: item.id, caseTitle: item.title, dimension: item.dimension,
        resourceName: resources[result.resourceId]?.displayName ?? result.resourceId,
        repetition: result.repetition,
        classification: AgentBenchmarkTrialClassificationPolicy.classify(result),
        failureReasons: result.failureReasons,
        rawOutput: run.map { AgentBenchmarkTrialEvaluator.finalText($0.finalOutput) } ?? "",
        planEventCount: events.filter { [.planning, .stepStarted, .stepCompleted].contains($0.type) }.count,
        toolReceipts: run?.toolCalls.map {
          "\($0.toolName): \($0.status.rawValue)" + ($0.errorMessage.isBlank ? "" : " (\($0.errorMessage.prefix(160)))")
        } ?? [],
        iosWorldEvidence: world?.verifierResults.map {
          "\($0.verifierId): \($0.actual) (\($0.passed ? "passed" : "failed"))"
        } ?? [],
        runId: result.runId
      )
    }
  }

  private static func snapshot(_ registration: AgentRegistration) -> AgentBenchmarkResourceSnapshot {
    AgentBenchmarkResourceSnapshot(
      resourceId: registration.agentId,
      displayName: registration.displayName,
      providerId: registration.providerId,
      modelId: registration.providerProfile?.modelId.ifBlank(registration.displayName) ?? registration.displayName,
      adapterType: registration.adapterType.ifBlank(registration.providerProfile?.adapterType ?? ""),
      capabilitiesHash: registration.capabilitiesHash
    )
  }
}

enum AgentBenchmarkTrialEvaluator {
  static func evaluate(
    session: AgentBenchmarkSession,
    benchmarkCase: AgentBenchmarkCase,
    campaign: AgentLabCampaign,
    trial: AgentLabTrial,
    run: AgentRecordedRun,
    sample: AgentEvalSample,
    events: [AgentRunControlEvent],
    iosWorldResult: AgentIOSWorldResult?
  ) -> AgentBenchmarkTrialResult {
    let output = finalText(run.finalOutput)
    let expectation = benchmarkCase.expectation
    var failures: [String] = []
    if run.status != .completed { failures.append("run_status:\(run.status.rawValue.lowercased())") }
    failures += sample.failureReasons.filter {
      $0.hasPrefix("run_failure:") || $0.hasPrefix("duration_budget_exceeded") || $0.hasPrefix("cost_budget_exceeded")
    }
    if output.count < expectation.minimumOutputCharacters { failures.append("output_too_short") }
    for (index, pattern) in expectation.requiredOutputPatterns.enumerated() where !matches(pattern, output) {
      failures.append("required_output_pattern:\(index)")
    }
    for (index, pattern) in expectation.forbiddenOutputPatterns.enumerated() where matches(pattern, output) {
      failures.append("forbidden_output_pattern:\(index)")
    }
    if !expectation.requiredJsonFields.isEmpty {
      if let data = output.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
         let parsed = try? JSONSerialization.jsonObject(with: data),
         let object = parsed as? [String: Any] {
        for (key, expected) in expectation.requiredJsonFields where String(describing: object[key] ?? "") != expected {
          failures.append("required_json_field:\(key)")
        }
      } else {
        failures.append("invalid_json_output")
      }
    }
    expectation.requiredEvidence.subtracting(sample.evidenceKinds).forEach {
      failures.append("missing_evidence:\($0.rawValue)")
    }
    if expectation.minimumVerifiedSources > 0,
       Set(run.sources.compactMap { $0.objectValue?["url"]?.stringValue ?? $0.objectValue?["citation_id"]?.stringValue })
        .count < expectation.minimumVerifiedSources {
      failures.append("insufficient_verified_sources")
    }
    let planEvents = max(events.filter { [.planning, .stepStarted, .stepCompleted].contains($0.type) }.count,
      run.agentPlan.filter { $0.objectValue?.isEmpty == false }.count)
    if planEvents < expectation.minimumPlanEvents { failures.append("missing_plan_evidence") }
    let receipts = max(run.toolCalls.filter { $0.status == .succeeded }.count,
      events.filter { $0.type == .toolCompleted && $0.payload["status"]?.stringValue == "succeeded" }.count)
    if receipts < expectation.minimumToolReceipts { failures.append("missing_tool_receipt") }
    for call in run.toolCalls where call.status != .succeeded {
      let message = call.errorMessage.lowercased()
      let infrastructure = ["network", "timeout", "timed_out", "unavailable", "connection", "transport"]
        .contains(where: message.contains)
      failures.append("\(infrastructure ? "tool_infrastructure" : "tool_failure"):\(call.toolName):\(call.errorMessage.prefix(160))")
    }
    let distinctAgents = Set(events.map(\.agentId).filter { !$0.isBlank }).count
    if distinctAgents < expectation.minimumDistinctAgents { failures.append("insufficient_distinct_agents") }
    if events.filter({ $0.type == .handoff }).count < expectation.minimumHandoffs {
      failures.append("missing_handoff_evidence")
    }
    if expectation.requiredCondition != .normal {
      if sample.observedConditions?.contains(expectation.requiredCondition) != true { failures.append("condition_not_observed") }
      if sample.observedConditions?.contains(expectation.requiredCondition) == true, !sample.recovered {
        failures.append("recovery_failed_after_observation")
      }
    }
    if expectation.memoryHorizonDays > 0, sample.memoryHorizonDays < expectation.memoryHorizonDays {
      failures.append("memory_horizon_not_verified")
    }
    if !expectation.iosWorldTaskId.isEmpty {
      if iosWorldResult?.taskId != expectation.iosWorldTaskId || iosWorldResult?.passed != true {
        failures.append("ios_world_not_verified")
      } else if expectation.requireIOSObservedValuesInOutput {
        iosWorldResult?.verifierResults.filter { !$0.verifierId.hasPrefix("required-bundle:") }
          .map(\.actual).filter { !$0.isBlank && !["true", "false"].contains($0.lowercased()) }
          .enumerated().forEach { index, actual in
            if !output.localizedCaseInsensitiveContains(actual) { failures.append("ios_world_value_missing:\(index)") }
          }
      }
    }
    return AgentBenchmarkTrialResult(
      sessionId: session.id,
      caseId: benchmarkCase.id,
      campaignId: campaign.id,
      trialId: trial.id,
      runId: run.runId,
      resourceId: trial.agentId,
      repetition: trial.repetition,
      passed: Set(failures).isEmpty,
      verified: sample.verified && run.status != .running,
      failureReasons: Array(Set(failures)).sorted(),
      durationMillis: sample.durationMillis,
      reportedCostMicros: sample.reportedCostMicros,
      batteryDeltaPercent: sample.batteryDeltaPercent,
      peakThermalStatus: sample.peakThermalStatus,
      completedAtMillis: sample.completedAtMillis
    )
  }

  private static func matches(_ pattern: String, _ output: String) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
    let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  static func finalText(_ output: AgentMcpJSONObject) -> String {
    for key in ["text", "message", "content", "result"] {
      if let value = output[key]?.stringValue, !value.isBlank { return value }
    }
    return ""
  }

}

enum AgentBenchmarkService {
  static func observe(
    run: AgentRecordedRun,
    sample: AgentEvalSample,
    benchmarkStore: AgentBenchmarkStore = AgentBenchmarkStore(),
    labStore: AgentLabStore = AgentLabStore(),
    recordedRunStore: AgentRecordedRunStoring = UserDefaultsAgentRecordedRunStore(),
    eventStore: AgentRunEventPersistence = UserDefaultsAgentRunEventStore(),
    worldStore: AgentIOSWorldStore = AgentIOSWorldStore(),
    suite: AgentBenchmarkSuite? = nil
  ) {
    guard let campaign = labStore.campaignForRun(run.runId),
          let session = benchmarkStore.sessions().first(where: { candidate in
      candidate.status == .running && candidate.campaignIdsByCase.values.contains(campaign.id)
    }),
          let suite = suite ?? AgentEvalBenchmarkCatalog.suite(id: session.suiteId, version: session.suiteVersion)
    else { return }
    guard let mapping = session.campaignIdsByCase.first(where: { $0.value == campaign.id }),
      let item = suite.benchmarkCase(id: mapping.key),
      let trial = campaign.trials.first(where: { $0.runId == run.runId }) else { return }
    let canonicalRun = recordedRunStore.runs(for: "").first { $0.runId == run.runId } ?? run
    let worldResult = worldStore.results(limit: 500).first { $0.runId == run.runId }
    let completedFloor: Int
    if benchmarkStore.resultCount(sessionId: session.id) == nil {
      completedFloor = session.campaignIdsByCase.values.compactMap { labStore.get(id: $0) }.reduce(0) { count, candidate in
        count + candidate.trials.filter { AgentLabRecoveryPolicy.terminalTrials.contains($0.status) }.count
      }
    } else {
      completedFloor = 0
    }
    let completed = benchmarkStore.saveResult(AgentBenchmarkTrialEvaluator.evaluate(
      session: session,
      benchmarkCase: item,
      campaign: campaign,
      trial: trial,
      run: canonicalRun,
      sample: sample,
      events: eventStore.events(runId: run.runId),
      iosWorldResult: worldResult
    ), completedTrialsFloor: completedFloor)
    if completed >= session.expectedTrials { _ = benchmarkStore.markStatus(id: session.id, status: .completed) }
  }
}

enum AgentIOSWorldBenchmarkFixtures {
  static func install(
    defaults: UserDefaults = .standard,
    store: AgentIOSWorldStore = AgentIOSWorldStore(),
    nowMillis: Int64 = AgentEvalClock.nowMillis()
  ) {
    let bundleId = Bundle.main.bundleIdentifier ?? "com.galaxyssi.GalaxySSI"
    let info = Bundle.main.infoDictionary ?? [:]
    let values: [(String, String)] = [
      ("foreground", "GalaxySSI"),
      ("screen_title", "Agent Lab"),
      ("bundle_id", bundleId),
      ("app_version", info["CFBundleShortVersionString"] as? String ?? "unknown"),
      ("app_build", info["CFBundleVersion"] as? String ?? "unknown"),
      ("locale", Locale.current.identifier),
      ("time_zone", TimeZone.current.identifier),
      ("low_power", String(ProcessInfo.processInfo.isLowPowerModeEnabled)),
      ("device_model", UIDevice.current.model),
      ("system_version", UIDevice.current.systemVersion)
    ]
    var tasks: [AgentIOSWorldTask] = []
    for (index, value) in values.enumerated() {
      let number = String(format: "%02d", index + 1)
      let id = "ios-world-\(number)"
      let key = "galaxyssi.benchmark.\(value.0)"
      defaults.set(value.1, forKey: key)
      tasks.append(AgentIOSWorldTask(
        id: id,
        instruction: "[evalops:\(id)] Observe \(value.0.replacingOccurrences(of: "_", with: " ")) [iosworld:\(id)]",
        verifiers: [AgentIOSWorldVerifier(id: "\(id)-verifier", kind: .userDefault,
          target: key, operation: "equals", expected: value.1)],
        requiredBundleIdentifiers: index == 2 ? [bundleId] : [],
        source: AgentEvalBenchmarkCatalog.standard.version,
        importedAtMillis: nowMillis
      ))
    }
    _ = store.importTasks(tasks)
  }
}

enum AgentBenchmarkMemoryFixtures {
  @discardableResult
  static func prepare(
    for suite: AgentBenchmarkSuite = AgentEvalBenchmarkCatalog.standard,
    store: AgentMemoryStore = UserDefaultsAgentMemoryStore(),
    nowMillis: Int64 = AgentMemoryClock.nowMillis()
  ) -> Int {
    let longTermValues = [
      ("M30-01", "GSSI-M30-ALPHA"), ("M30-02", "GSSI-M30-BRAVO"),
      ("M30-03", "GSSI-M30-CHARLIE"), ("M30-04", "GSSI-M30-DELTA"),
      ("M30-05", "GSSI-M30-ECHO"), ("M90-01", "GSSI-M90-FOXTROT"),
      ("M90-02", "GSSI-M90-GOLF"), ("M90-03", "GSSI-M90-HOTEL"),
      ("M90-04", "GSSI-M90-INDIA"), ("M90-05", "GSSI-M90-JULIET")
    ]
    let immediateValues: [(String, String, AgentMemoryKind, String)] = [
      ("IM-01", "GSSI-IM-NOVA", .identity, ""),
      ("IM-02", "GSSI-IM-DARK", .preference, ""),
      ("IM-03", "GSSI-IM-PHONE", .identity, ""),
      ("IM-04", "GSSI-IM-PROJECT", .task, ""),
      ("IM-05", "GSSI-IM-KNOWLEDGE", .knowledge, ""),
      ("IM-06", "GSSI-IM-WORKFLOW", .workflow, ""),
      ("IM-07", "GSSI-IM-DECISION", .task, ""),
      ("IM-08", "GSSI-IM-CURRENT", .knowledge, "GSSI-IM-OLD"),
      ("IM-09-A", "GSSI-IM-ALPHA", .knowledge, ""),
      ("IM-09-B", "GSSI-IM-BETA", .knowledge, ""),
      ("IM-10", "GSSI-IM-PROVENANCE", .knowledge, "")
    ]
    let immediateCount = suite.cases.contains { $0.dimension == .immediateMemory } ? immediateValues.filter { fixture in
      let (id, value, kind, oldValue) = fixture
      let key = "evalops.immediate.\(id.lowercased())"
      let active = store.snapshot().activeItems.first { $0.key == key }
      if let active, active.value.contains(value), ["evalops_immediate_fixture", "memory_edit"].contains(active.source) {
        return true
      }
      if let active { return store.update(itemId: active.id, value: "\(id) = \(value)", key: key)?.item != nil }
      if !oldValue.isEmpty,
         let old = store.remember(AgentMemoryItem(
          kind: kind, value: "\(id) = \(oldValue)", timestampMillis: nowMillis,
          source: "evalops_immediate_fixture", key: key, important: true, confidence: 1
         )).item {
        return store.update(itemId: old.id, value: "\(id) = \(value)", key: key)?.item != nil
      }
      return store.remember(AgentMemoryItem(
        kind: kind, value: "\(id) = \(value)", timestampMillis: nowMillis,
        source: "evalops_immediate_fixture", key: key,
        important: true, confidence: 1, whyRemembered: "Versioned immediate cross-session Agent benchmark fixture"
      )).item != nil
    }.count : 0
    guard suite.cases.contains(where: { $0.dimension == .longTermMemory }) else { return immediateCount }
    return immediateCount + longTermValues.filter { entry in
      let (fixture, value) = entry
      let key = "evalops.fixture.\(fixture.lowercased())"
      if store.snapshot().activeItems.contains(where: { $0.key == key && $0.value == "\(fixture) = \(value)" }) {
        return true
      }
      store.remember(AgentMemoryItem(
        kind: .knowledge,
        value: "\(fixture) = \(value)",
        timestampMillis: nowMillis,
        source: "evalops_fixture",
        key: key,
        important: true,
        confidence: 1,
        whyRemembered: "Versioned long-horizon Agent benchmark fixture"
      )).item != nil
    }.count
  }
}
