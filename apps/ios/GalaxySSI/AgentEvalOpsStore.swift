import Foundation
import UIKit

final class AgentEvalOpsStore {
  private struct State: Codable {
    var settings = AgentEvalOpsSettings()
    var starts: [String: AgentEvalRunStart] = [:]
    var samples: [String: AgentEvalSample] = [:]
  }

  static let defaultKey = "galaxyssi-ios-agent-evalops-v1"

  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let key: String
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    key: String = AgentEvalOpsStore.defaultKey
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.key = key
  }

  func settings() -> AgentEvalOpsSettings {
    locked { load().settings.normalized }
  }

  @discardableResult
  func updateSettings(_ transform: (AgentEvalOpsSettings) -> AgentEvalOpsSettings) -> AgentEvalOpsSettings {
    locked {
      var state = load()
      state.settings = transform(state.settings).normalized
      save(state)
      return state.settings
    }
  }

  func saveStart(_ start: AgentEvalRunStart) {
    guard !start.runId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    locked {
      var state = load()
      state.starts[start.runId] = start
      save(state)
    }
  }

  func start(runId: String) -> AgentEvalRunStart? {
    locked { load().starts[runId.trimmingCharacters(in: .whitespacesAndNewlines)] }
  }

  func saveSample(_ sample: AgentEvalSample) {
    guard !sample.runId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    locked {
      var state = load()
      state.samples[sample.runId] = sample
      state.starts.removeValue(forKey: sample.runId)
      let retained = state.samples.values
        .sorted { $0.completedAtMillis > $1.completedAtMillis }
        .prefix(Self.maximumSamples)
      state.samples = Dictionary(uniqueKeysWithValues: retained.map { ($0.runId, $0) })
      save(state)
    }
  }

  func sample(runId: String) -> AgentEvalSample? {
    locked { load().samples[runId.trimmingCharacters(in: .whitespacesAndNewlines)] }
  }

  func samples(limit: Int = AgentEvalOpsStore.maximumSamples) -> [AgentEvalSample] {
    locked {
      Array(load().samples.values)
        .sorted { $0.completedAtMillis > $1.completedAtMillis }
        .prefixArray(min(max(limit, 1), Self.maximumSamples))
    }
  }

  @discardableResult
  func recordProactiveFeedback(runId: String, relevant: Bool, accepted: Bool) -> AgentEvalSample? {
    locked {
      var state = load()
      guard var sample = state.samples[runId] else { return nil }
      sample.proactiveRelevant = relevant
      sample.proactiveAccepted = accepted
      state.samples[runId] = sample
      save(state)
      return sample
    }
  }

  func dashboard() -> AgentEvalDashboard {
    let value = settings()
    return AgentEvalStatistics.dashboard(samples: samples(), k: value.repeatedTrials)
  }

  func clearResults() {
    locked {
      var state = load()
      state.starts.removeAll()
      state.samples.removeAll()
      save(state)
    }
  }

  static func destroyPersistentStore(
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    key: String = AgentEvalOpsStore.defaultKey
  ) {
    GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: key, secrets: secrets)
  }

  private func load() -> State {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets),
          let state = try? JSONDecoder().decode(State.self, from: data) else {
      return State()
    }
    return state
  }

  private func save(_ state: State) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: key, secrets: secrets)
  }

  private func locked<T>(_ work: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return work()
  }

  static let maximumSamples = 5_000
}

enum AgentDeviceEvalProbe {
  static func capture(
    nowMillis: Int64 = AgentEvalClock.nowMillis(),
    processInfo: ProcessInfo = .processInfo,
    device: UIDevice = .current,
    networkProbe: AgentMediaNetworkProbe = AgentMediaNetworkDetector.shared.currentProbe,
    memorySnapshot: AgentIOSDeviceMemorySnapshot = AgentIOSDefaultDeviceMemoryStatusProvider().snapshot()
  ) -> AgentDeviceEvalSnapshot {
    device.isBatteryMonitoringEnabled = true
    let batteryPercent = device.batteryLevel >= 0
      ? min(max(Int((device.batteryLevel * 100).rounded()), 0), 100)
      : -1
    return AgentDeviceEvalSnapshot(
      capturedAtMillis: nowMillis,
      elapsedRealtimeMillis: Int64((processInfo.systemUptime * 1_000).rounded()),
      batteryPercent: batteryPercent,
      thermalStatus: thermalStatus(processInfo.thermalState),
      availableMemoryBytes: memorySnapshot.availableBytes,
      lowMemory: memorySnapshot.lowMemory,
      powerSaveMode: processInfo.isLowPowerModeEnabled,
      deviceIdleMode: false,
      networkAvailable: networkProbe.networkPresent,
      networkValidated: networkProbe.validated
    )
  }

  private static func thermalStatus(_ state: ProcessInfo.ThermalState) -> Int {
    switch state {
    case .nominal: return 0
    case .fair: return 1
    case .serious: return 2
    case .critical: return 3
    @unknown default: return -1
    }
  }
}

enum AgentEvalOpsService {
  static func observeRunStarted(
    _ run: AgentRecordedRun,
    store: AgentEvalOpsStore = AgentEvalOpsStore(),
    device: AgentDeviceEvalSnapshot? = nil
  ) {
    guard store.settings().captureRealRuns,
          !AgentLearningAnalyzer.containsSensitiveData(run.originalRequest),
          store.start(runId: run.runId) == nil else { return }
    let contract = AgentOutcomeContractCompiler.compile(
      runId: run.runId,
      goal: run.originalRequest,
      nowMillis: run.createdAtMillis > 0 ? run.createdAtMillis : AgentEvalClock.nowMillis()
    )
    store.saveStart(AgentEvalRunStart(
      runId: run.runId,
      contract: contract,
      device: device ?? AgentDeviceEvalProbe.capture()
    ))
  }

  @discardableResult
  static func observeRunCompleted(
    _ run: AgentRecordedRun,
    store: AgentEvalOpsStore = AgentEvalOpsStore(),
    memoryTrustStore: AgentMemoryTrustStore = AgentMemoryTrustStore(),
    completedDevice: AgentDeviceEvalSnapshot? = nil,
    events: [AgentRunControlEvent]? = nil
  ) -> AgentEvalSample? {
    guard store.settings().captureRealRuns,
          !AgentLearningAnalyzer.containsSensitiveData(run.originalRequest),
          store.sample(runId: run.runId) == nil else { return nil }
    let currentDevice = completedDevice ?? AgentDeviceEvalProbe.capture()
    let start = store.start(runId: run.runId) ?? AgentEvalRunStart(
      runId: run.runId,
      contract: AgentOutcomeContractCompiler.compile(runId: run.runId, goal: run.originalRequest),
      device: AgentDeviceEvalSnapshot(
        capturedAtMillis: run.createdAtMillis,
        elapsedRealtimeMillis: 0,
        batteryPercent: currentDevice.batteryPercent,
        thermalStatus: currentDevice.thermalStatus,
        availableMemoryBytes: currentDevice.availableMemoryBytes,
        lowMemory: currentDevice.lowMemory,
        powerSaveMode: currentDevice.powerSaveMode,
        networkAvailable: currentDevice.networkAvailable,
        networkValidated: currentDevice.networkValidated
      )
    )
    let sample = assess(
      start: start,
      completedDevice: currentDevice,
      run: run,
      events: events ?? UserDefaultsAgentRunEventStore().events(runId: run.runId)
    )
    store.saveSample(sample)
    _ = memoryTrustStore.attachAnswer(
      conversationId: run.conversationId,
      runId: run.runId,
      answer: finalText(run.finalOutput),
      answeredAtMillis: run.completedAtMillis > 0 ? run.completedAtMillis : AgentEvalClock.nowMillis()
    )
    AgentTrajectoryLearningService.observe(run: run, sample: sample)
    AgentEvolutionLabService.observe(sample: sample)
    return sample
  }

  static func assess(
    start: AgentEvalRunStart,
    completedDevice: AgentDeviceEvalSnapshot,
    run: AgentRecordedRun,
    events: [AgentRunControlEvent]
  ) -> AgentEvalSample {
    let contract = start.contract
    let evidence = collectEvidence(run: run, events: events)
    let duration = max(0, run.completedAtMillis - run.createdAtMillis)
    var reasons: [String] = []
    if run.status != .completed { reasons.append("run_status:\(run.status.rawValue.lowercased())") }
    contract.requiredEvidence.subtracting(evidence).forEach { reasons.append("missing_evidence:\($0.rawValue)") }
    if duration > contract.maxDurationMillis { reasons.append("duration_budget_exceeded") }
    let cost = reportedCostMicros(run)
    if contract.maxReportedCostMicros > 0, cost > contract.maxReportedCostMicros {
      reasons.append("cost_budget_exceeded")
    }
    let resource = run.executionResourceId.lowercased()
    contract.forbiddenResources.filter(resource.contains).forEach { reasons.append("forbidden_resource:\($0)") }
    if !contract.allowedResources.isEmpty, !contract.allowedResources.contains(where: resource.contains) {
      reasons.append("resource_not_allowed")
    }
    let verdict: AgentEvalVerdict
    if reasons.isEmpty {
      verdict = .passed
    } else if run.status == .completed, !evidence.isEmpty {
      verdict = .partial
    } else if run.status == .running {
      verdict = .unverified
    } else {
      verdict = .failed
    }
    let recoveryAttempted = contract.condition != .normal || events.contains {
      $0.type == .retrying || $0.type == .runRecovered
    }
    let recovered = run.status == .completed && events.contains { $0.type == .runRecovered }
    return AgentEvalSample(
      runId: run.runId,
      scenarioId: AgentLearningAnalyzer.stableKey(run.originalRequest),
      taskClass: contract.taskClass,
      resourceId: run.executionResourceId.ifBlank("galaxyssi-mobile"),
      verdict: verdict,
      contractSatisfied: reasons.isEmpty,
      verified: contract.requiredEvidence.isSubset(of: evidence),
      durationMillis: duration,
      reportedCostMicros: cost,
      batteryDeltaPercent: positiveDelta(start.device.batteryPercent, completedDevice.batteryPercent),
      chargeConsumedMicroAh: positiveDelta(start.device.chargeCounterMicroAh, completedDevice.chargeCounterMicroAh),
      energyConsumedNanoWh: positiveDelta(start.device.energyCounterNanoWh, completedDevice.energyCounterNanoWh),
      peakThermalStatus: max(start.device.thermalStatus, completedDevice.thermalStatus),
      memoryDeltaBytes: positiveDelta(start.device.availableMemoryBytes, completedDevice.availableMemoryBytes),
      recoveryAttempted: recoveryAttempted,
      recovered: recovered,
      condition: contract.condition,
      memoryHorizonDays: contract.memoryHorizonDays,
      failureReasons: reasons,
      evidenceKinds: evidence,
      completedAtMillis: run.completedAtMillis > 0 ? run.completedAtMillis : AgentEvalClock.nowMillis()
    )
  }

  private static func collectEvidence(
    run: AgentRecordedRun,
    events: [AgentRunControlEvent]
  ) -> Set<AgentOutcomeEvidenceKind> {
    var evidence = Set<AgentOutcomeEvidenceKind>()
    if finalText(run.finalOutput).isBlank == false { evidence.insert(.finalResponse) }
    if run.toolCalls.contains(where: { $0.status == .succeeded && AgentLearningAnalyzer.hasTrustedExecutionEvidence($0) }) {
      evidence.insert(.toolReceipt)
    }
    if run.artifacts.contains(where: artifactHasDigest) { evidence.insert(.artifactDigest) }
    if !run.sources.isEmpty { evidence.insert(.verifiedSource) }
    if events.contains(where: { $0.type == .runRecovered }) { evidence.insert(.recoveryEvent) }
    let memoryPayload = "\(run.sources)\n\(run.finalOutput)".lowercased()
    if run.status == .completed,
       ["memory", "event_id", "provenance"].contains(where: memoryPayload.contains) {
      evidence.insert(.memoryProvenance)
    }
    if run.userFeedback.contains(where: positiveFeedback) { evidence.insert(.userAcceptance) }
    return evidence
  }

  private static func finalText(_ object: AgentMcpJSONObject) -> String {
    ["text", "message", "content", "result"]
      .compactMap { object[$0]?.stringValue }
      .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
  }

  private static func artifactHasDigest(_ artifact: AgentArtifactReference) -> Bool {
    let value = "\(artifact.id)\n\(artifact.uri)\n\(artifact.metadataJson)"
    return value.range(of: #"(?i)[0-9a-f]{64}"#, options: .regularExpression) != nil
  }

  private static func reportedCostMicros(_ run: AgentRecordedRun) -> Int64 {
    let roots: [AgentMcpJSONValue] = [
      .object(run.finalOutput),
      .array(run.sources),
      .object(run.renderSpec)
    ]
    return roots.map(reportedCostMicros).max() ?? 0
  }

  private static func reportedCostMicros(_ value: AgentMcpJSONValue) -> Int64 {
    switch value {
    case .object(let object):
      let direct = ["reported_cost_micros", "cost_micros", "actual_cost_micros"]
        .compactMap { object[$0]?.intValue }
        .max() ?? 0
      return max(direct, object.values.map(reportedCostMicros).max() ?? 0)
    case .array(let values):
      return values.map(reportedCostMicros).max() ?? 0
    default:
      return 0
    }
  }

  private static func positiveFeedback(_ value: String) -> Bool {
    let normalized = value.lowercased()
    return ["good", "correct", "works", "passed", "\u{53ef}\u{4ee5}", "\u{6b63}\u{786e}", "\u{5f88}\u{597d}", "\u{901a}\u{8fc7}"]
      .contains(where: normalized.contains)
  }

  private static func positiveDelta(_ start: Int, _ end: Int) -> Int {
    start < 0 || end < 0 ? 0 : max(0, start - end)
  }

  private static func positiveDelta(_ start: Int64, _ end: Int64) -> Int64 {
    start <= 0 || end <= 0 ? 0 : max(0, start - end)
  }
}

private extension Array {
  func prefixArray(_ count: Int) -> [Element] {
    Array(prefix(count))
  }
}
