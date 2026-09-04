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
    var assignments: [String: [String]] = [:]
    for dimension in AgentBenchmarkDimension.allCases {
      let cases = suite.cases.filter { $0.dimension == dimension }
      guard cases.count == 10 else {
        throw AgentBenchmarkError(message: "The 90/10 profile requires ten cases per dimension")
      }
      for (index, item) in cases.enumerated() {
        assignments[item.id] = [index == cases.count - 1 ? deepSeek.agentId : codex.agentId]
      }
    }
    guard assignments.values.filter({ $0.contains(codex.agentId) }).count == 54,
          assignments.values.filter({ $0.contains(deepSeek.agentId) }).count == 6 else {
      throw AgentBenchmarkError(message: "The benchmark allocation must remain 90% Codex and 10% DeepSeek")
    }
    return AgentBenchmarkAllocation(resources: [codex, deepSeek], resourceIdsByCase: assignments)
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
    AgentIOSWorldBenchmarkFixtures.install()
    AgentBenchmarkMemoryFixtures.prepare()
    var campaignIds: [String: String] = [:]
    do {
      for item in suite.cases {
        guard let campaign = labStore.create(
          task: item.taggedPrompt,
          agentIds: allocation.resourceIdsByCase[item.id, default: []],
          repetitions: count
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
      campaignIdsByCase: campaignIds
    )
    benchmarkStore.saveSession(session)
    for campaignId in campaignIds.values { try labRuntime.start(campaignId: campaignId) }
    return session
  }

  func latest() -> AgentBenchmarkSession? { benchmarkStore.sessions().first }

  @discardableResult
  func resumeLatestIncomplete(
    condition: AgentEvalCondition = .processDeath,
    reason: String = "Comprehensive benchmark resumed after interruption"
  ) -> Int {
    guard let session = benchmarkStore.sessions().first(where: { $0.status == .running }) else {
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
      totalCampaigns: session.caseIds.count,
      terminal: session.status != .running ||
        (campaigns.count == session.caseIds.count && terminalCampaigns == campaigns.count)
    )
  }

  func cancel(sessionId: String) async -> Bool {
    guard let session = benchmarkStore.session(id: sessionId) else { return false }
    for campaignId in session.campaignIdsByCase.values { _ = await labRuntime.cancel(campaignId: campaignId) }
    _ = benchmarkStore.markStatus(id: session.id, status: .cancelled)
    return true
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
    expectation.requiredEvidence.subtracting(sample.evidenceKinds).forEach {
      failures.append("missing_evidence:\($0.rawValue)")
    }
    let planEvents = events.filter { [.planning, .stepStarted, .stepCompleted].contains($0.type) }.count +
      run.agentPlan.filter { $0.objectValue?.isEmpty == false }.count
    if planEvents < expectation.minimumPlanEvents { failures.append("missing_plan_evidence") }
    let receipts = run.toolCalls.filter { $0.status == .succeeded }.count + events.filter { $0.type == .toolCompleted }.count
    if receipts < expectation.minimumToolReceipts { failures.append("missing_tool_receipt") }
    let distinctAgents = Set(events.map(\.agentId).filter { !$0.isBlank }).count
    if distinctAgents < expectation.minimumDistinctAgents { failures.append("insufficient_distinct_agents") }
    if events.filter({ $0.type == .handoff }).count < expectation.minimumHandoffs {
      failures.append("missing_handoff_evidence")
    }
    if expectation.requiredCondition != .normal {
      if sample.observedConditions?.contains(expectation.requiredCondition) != true { failures.append("condition_not_observed") }
      if !sample.recovered { failures.append("recovery_not_verified") }
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
      verified: run.status != .running,
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

  private static func finalText(_ output: AgentMcpJSONObject) -> String {
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
    suite: AgentBenchmarkSuite = AgentEvalBenchmarkCatalog.standard
  ) {
    guard let campaign = labStore.campaignForRun(run.runId),
          let session = benchmarkStore.sessions().first(where: { candidate in
      candidate.status == .running && candidate.suiteId == suite.id && candidate.suiteVersion == suite.version &&
        candidate.campaignIdsByCase.values.contains(campaign.id)
    }) else { return }
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
    store: AgentMemoryStore = UserDefaultsAgentMemoryStore(),
    nowMillis: Int64 = AgentMemoryClock.nowMillis()
  ) -> Int {
    let values = [
      ("M30-01", "GSSI-M30-ALPHA", 31), ("M30-02", "GSSI-M30-BRAVO", 31),
      ("M30-03", "GSSI-M30-CHARLIE", 31), ("M30-04", "GSSI-M30-DELTA", 31),
      ("M30-05", "GSSI-M30-ECHO", 31), ("M90-01", "GSSI-M90-FOXTROT", 91),
      ("M90-02", "GSSI-M90-GOLF", 91), ("M90-03", "GSSI-M90-HOTEL", 91),
      ("M90-04", "GSSI-M90-INDIA", 91), ("M90-05", "GSSI-M90-JULIET", 91)
    ]
    return values.filter { entry in
      let (fixture, value, ageDays) = entry
      store.remember(AgentMemoryItem(
        kind: .knowledge,
        value: "\(fixture) = \(value)",
        timestampMillis: nowMillis - Int64(ageDays * 86_400_000),
        source: "evalops_fixture",
        key: "evalops.fixture.\(fixture.lowercased())",
        important: true,
        confidence: 1,
        whyRemembered: "Versioned long-horizon Agent benchmark fixture"
      )).item != nil
    }.count
  }
}
