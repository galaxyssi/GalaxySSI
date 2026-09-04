import Foundation

enum AgentEvalTaskClass: String, Codable, CaseIterable, Identifiable {
  case general
  case code
  case research
  case deviceControl = "device_control"
  case automation
  case memory
  case proactive
  case reliability

  var id: String { rawValue }
}

enum AgentEvalCondition: String, Codable, CaseIterable, Identifiable {
  case normal
  case doze
  case reboot
  case networkLoss = "network_loss"
  case processDeath = "process_death"

  var id: String { rawValue }
}

enum AgentOutcomeEvidenceKind: String, Codable, CaseIterable, Identifiable {
  case finalResponse = "final_response"
  case toolReceipt = "tool_receipt"
  case artifactDigest = "artifact_digest"
  case verifiedSource = "verified_source"
  case recoveryEvent = "recovery_event"
  case memoryProvenance = "memory_provenance"
  case userAcceptance = "user_acceptance"
  case programmaticVerifier = "programmatic_verifier"

  var id: String { rawValue }
}

enum AgentEvalVerdict: String, Codable, CaseIterable, Identifiable {
  case passed
  case failed
  case partial
  case unverified

  var id: String { rawValue }
}

struct AgentOutcomeContract: Codable, Equatable, Identifiable {
  var id: String
  var runId: String
  var goal: String
  var taskClass: AgentEvalTaskClass
  var successCriteria: [String]
  var allowedResources: Set<String>
  var forbiddenResources: Set<String>
  var requiredEvidence: Set<AgentOutcomeEvidenceKind>
  var maxDurationMillis: Int64
  var maxReportedCostMicros: Int64
  var memoryHorizonDays: Int
  var condition: AgentEvalCondition
  var createdAtMillis: Int64

  init(
    id: String = UUID().uuidString,
    runId: String,
    goal: String,
    taskClass: AgentEvalTaskClass,
    successCriteria: [String],
    allowedResources: Set<String> = [],
    forbiddenResources: Set<String> = [],
    requiredEvidence: Set<AgentOutcomeEvidenceKind>,
    maxDurationMillis: Int64,
    maxReportedCostMicros: Int64 = 0,
    memoryHorizonDays: Int = 0,
    condition: AgentEvalCondition = .normal,
    createdAtMillis: Int64 = AgentEvalClock.nowMillis()
  ) {
    self.id = id
    self.runId = runId
    self.goal = String(goal.prefix(4_000))
    self.taskClass = taskClass
    self.successCriteria = successCriteria
    self.allowedResources = allowedResources
    self.forbiddenResources = forbiddenResources
    self.requiredEvidence = requiredEvidence
    self.maxDurationMillis = max(1, maxDurationMillis)
    self.maxReportedCostMicros = max(0, maxReportedCostMicros)
    self.memoryHorizonDays = min(max(0, memoryHorizonDays), 3_650)
    self.condition = condition
    self.createdAtMillis = max(0, createdAtMillis)
  }
}

struct AgentDeviceEvalSnapshot: Codable, Equatable {
  var capturedAtMillis: Int64
  var elapsedRealtimeMillis: Int64
  var batteryPercent: Int
  var chargeCounterMicroAh: Int64
  var energyCounterNanoWh: Int64
  var thermalStatus: Int
  var availableMemoryBytes: Int64
  var lowMemory: Bool
  var powerSaveMode: Bool
  var deviceIdleMode: Bool
  var networkAvailable: Bool
  var networkValidated: Bool

  init(
    capturedAtMillis: Int64,
    elapsedRealtimeMillis: Int64,
    batteryPercent: Int = -1,
    chargeCounterMicroAh: Int64 = 0,
    energyCounterNanoWh: Int64 = 0,
    thermalStatus: Int = -1,
    availableMemoryBytes: Int64 = 0,
    lowMemory: Bool = false,
    powerSaveMode: Bool = false,
    deviceIdleMode: Bool = false,
    networkAvailable: Bool = false,
    networkValidated: Bool = false
  ) {
    self.capturedAtMillis = max(0, capturedAtMillis)
    self.elapsedRealtimeMillis = max(0, elapsedRealtimeMillis)
    self.batteryPercent = batteryPercent < 0 ? -1 : min(batteryPercent, 100)
    self.chargeCounterMicroAh = max(0, chargeCounterMicroAh)
    self.energyCounterNanoWh = max(0, energyCounterNanoWh)
    self.thermalStatus = thermalStatus
    self.availableMemoryBytes = max(0, availableMemoryBytes)
    self.lowMemory = lowMemory
    self.powerSaveMode = powerSaveMode
    self.deviceIdleMode = deviceIdleMode
    self.networkAvailable = networkAvailable
    self.networkValidated = networkValidated
  }
}

struct AgentEvalRunStart: Codable, Equatable {
  var runId: String
  var contract: AgentOutcomeContract
  var device: AgentDeviceEvalSnapshot
}

struct AgentEvalSample: Codable, Equatable, Identifiable {
  var id: String
  var runId: String
  var scenarioId: String
  var taskClass: AgentEvalTaskClass
  var resourceId: String
  var verdict: AgentEvalVerdict
  var contractSatisfied: Bool
  var verified: Bool
  var durationMillis: Int64
  var reportedCostMicros: Int64
  var batteryDeltaPercent: Int
  var chargeConsumedMicroAh: Int64
  var energyConsumedNanoWh: Int64
  var peakThermalStatus: Int
  var memoryDeltaBytes: Int64
  var recoveryAttempted: Bool
  var recovered: Bool
  var condition: AgentEvalCondition
  var memoryHorizonDays: Int
  var proactiveRelevant: Bool?
  var proactiveAccepted: Bool?
  var failureReasons: [String]
  var evidenceKinds: Set<AgentOutcomeEvidenceKind>
  var observedConditions: Set<AgentEvalCondition>?
  var completedAtMillis: Int64

  var passed: Bool { verdict == .passed }

  init(
    id: String = UUID().uuidString,
    runId: String,
    scenarioId: String,
    taskClass: AgentEvalTaskClass,
    resourceId: String,
    verdict: AgentEvalVerdict,
    contractSatisfied: Bool,
    verified: Bool,
    durationMillis: Int64,
    reportedCostMicros: Int64 = 0,
    batteryDeltaPercent: Int = 0,
    chargeConsumedMicroAh: Int64 = 0,
    energyConsumedNanoWh: Int64 = 0,
    peakThermalStatus: Int = -1,
    memoryDeltaBytes: Int64 = 0,
    recoveryAttempted: Bool = false,
    recovered: Bool = false,
    condition: AgentEvalCondition = .normal,
    memoryHorizonDays: Int = 0,
    proactiveRelevant: Bool? = nil,
    proactiveAccepted: Bool? = nil,
    failureReasons: [String] = [],
    evidenceKinds: Set<AgentOutcomeEvidenceKind> = [],
    observedConditions: Set<AgentEvalCondition>? = nil,
    completedAtMillis: Int64 = AgentEvalClock.nowMillis()
  ) {
    self.id = id
    self.runId = runId
    self.scenarioId = scenarioId
    self.taskClass = taskClass
    self.resourceId = resourceId.ifBlank("galaxyssi-mobile")
    self.verdict = verdict
    self.contractSatisfied = contractSatisfied
    self.verified = verified
    self.durationMillis = max(0, durationMillis)
    self.reportedCostMicros = max(0, reportedCostMicros)
    self.batteryDeltaPercent = max(0, batteryDeltaPercent)
    self.chargeConsumedMicroAh = max(0, chargeConsumedMicroAh)
    self.energyConsumedNanoWh = max(0, energyConsumedNanoWh)
    self.peakThermalStatus = peakThermalStatus
    self.memoryDeltaBytes = max(0, memoryDeltaBytes)
    self.recoveryAttempted = recoveryAttempted
    self.recovered = recovered
    self.condition = condition
    self.memoryHorizonDays = min(max(0, memoryHorizonDays), 3_650)
    self.proactiveRelevant = proactiveRelevant
    self.proactiveAccepted = proactiveAccepted
    self.failureReasons = Array(failureReasons.prefix(64))
    self.evidenceKinds = evidenceKinds
    self.observedConditions = observedConditions
    self.completedAtMillis = max(0, completedAtMillis)
  }
}

struct AgentEvalResourceSummary: Codable, Equatable, Identifiable {
  var id: String { "\(resourceId):\(taskClass.rawValue)" }
  var resourceId: String
  var taskClass: AgentEvalTaskClass
  var verifiedRuns: Int
  var passAt1: Double
  var passPowerK: Double
  var averageLatencyMillis: Int64
  var p95LatencyMillis: Int64
  var averageReportedCostMicros: Int64
  var averageBatteryDeltaPercent: Double
  var peakThermalStatus: Int
  var recoveryRate: Double
  var memoryAccuracy: Double?
  var proactiveHitRate: Double?
  var proactiveDisturbanceRate: Double?
}

struct AgentEvalDashboard: Codable, Equatable {
  var totalRuns: Int
  var verifiedRuns: Int
  var passAt1: Double
  var passPowerK: Double
  var averageLatencyMillis: Int64
  var recoveryRate: Double
  var memory30DayAccuracy: Double?
  var memory90DayAccuracy: Double?
  var proactiveHitRate: Double?
  var proactiveDisturbanceRate: Double?
  var resources: [AgentEvalResourceSummary]
  var generatedAtMillis: Int64 = AgentEvalClock.nowMillis()
}

struct AgentEvalOpsSettings: Codable, Equatable {
  var captureRealRuns = true
  var continuousEvaluationEnabled = false
  var repeatedTrials = 3
  var shadowRoutingEnabled = true
  var automaticQualityRoutingEnabled = false
  var minimumAutomaticRoutingSamples = 12
  var attentionThreshold = 0.58
  var skillMarkdownCompatibilityEnabled = true
  var protocolAdaptersEnabled = true
  var shadowReleaseEnabled = true

  var normalized: AgentEvalOpsSettings {
    var value = self
    value.repeatedTrials = min(max(value.repeatedTrials, 2), 10)
    value.minimumAutomaticRoutingSamples = min(max(value.minimumAutomaticRoutingSamples, 6), 100)
    value.attentionThreshold = min(max(value.attentionThreshold, 0), 1)
    return value
  }
}

enum AgentOutcomeContractCompiler {
  static func compile(runId: String, goal: String, nowMillis: Int64 = AgentEvalClock.nowMillis()) -> AgentOutcomeContract {
    let cleanGoal = String(goal.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_000))
    let requirements = AgentTaskRequirementAnalyzer.analyze(cleanGoal)
    let taskClass = classify(goal: cleanGoal, requirements: requirements)
    let condition = condition(cleanGoal)
    var evidence: Set<AgentOutcomeEvidenceKind> = [.finalResponse]
    if !requirements.capabilities.isDisjoint(with: toolCapabilities) { evidence.insert(.toolReceipt) }
    if taskClass == .code { evidence.insert(.artifactDigest) }
    if taskClass == .research { evidence.insert(.verifiedSource) }
    if taskClass == .memory { evidence.insert(.memoryProvenance) }
    if condition != .normal { evidence.insert(.recoveryEvent) }
    let maximumDuration: Int64
    switch requirements.executionHorizon {
    case .interactive: maximumDuration = 15 * 60_000
    case .background: maximumDuration = 2 * 60 * 60_000
    case .longRunning: maximumDuration = 24 * 60 * 60_000
    }
    return AgentOutcomeContract(
      runId: runId,
      goal: cleanGoal,
      taskClass: taskClass,
      successCriteria: criteria(taskClass: taskClass, condition: condition),
      forbiddenResources: requirements.localOnly ? ["cloud"] : [],
      requiredEvidence: evidence,
      maxDurationMillis: maximumDuration,
      memoryHorizonDays: memoryHorizonDays(cleanGoal),
      condition: condition,
      createdAtMillis: nowMillis
    )
  }

  static func classify(goal: String, requirements: AgentTaskRequirements) -> AgentEvalTaskClass {
    let normalized = goal.lowercased()
    if memoryHorizonDays(goal) > 0 || memoryTerms.contains(where: normalized.contains) { return .memory }
    if proactiveTerms.contains(where: normalized.contains) { return .proactive }
    if condition(goal) != .normal { return .reliability }
    if requirements.capabilities.contains(.code) { return .code }
    if requirements.liveDataRequired || requirements.capabilities.contains(.knowledgeSearch) { return .research }
    if requirements.capabilities.contains(.deviceControl) || requirements.capabilities.contains(.appNavigation) {
      return .deviceControl
    }
    if requirements.executionHorizon != .interactive { return .automation }
    return .general
  }

  private static func criteria(taskClass: AgentEvalTaskClass, condition: AgentEvalCondition) -> [String] {
    var values = ["Return one non-empty final result"]
    switch taskClass {
    case .code:
      values += ["Produce integrity-addressed implementation evidence", "Report executable verification results"]
    case .research: values.append("Provide traceable source evidence")
    case .deviceControl: values.append("Complete the requested device state change")
    case .automation: values.append("Complete or checkpoint every planned action")
    case .memory: values.append("Answer from provenance-linked long-term memory")
    case .proactive: values.append("Deliver a relevant and actionable insight")
    case .reliability: values.append("Recover without duplicating the final result")
    case .general: break
    }
    if condition != .normal { values.append("Record recovery evidence for \(condition.rawValue)") }
    return values
  }

  private static func condition(_ goal: String) -> AgentEvalCondition {
    let value = goal.lowercased()
    if ["doze", "idle mode", "\u{4f11}\u{7720}", "\u{5f85}\u{673a}"].contains(where: value.contains) { return .doze }
    if ["reboot", "restart phone", "\u{91cd}\u{542f}"].contains(where: value.contains) { return .reboot }
    if ["network loss", "disconnect network", "\u{65ad}\u{7f51}", "\u{7f51}\u{7edc}\u{4e2d}\u{65ad}"].contains(where: value.contains) {
      return .networkLoss
    }
    if ["process death", "kill process", "\u{8fdb}\u{7a0b}\u{6b7b}\u{4ea1}", "\u{6740}\u{8fdb}\u{7a0b}"].contains(where: value.contains) {
      return .processDeath
    }
    return .normal
  }

  private static func memoryHorizonDays(_ goal: String) -> Int {
    let value = goal.lowercased()
    if ["90 day", "90-day", "90\u{5929}"].contains(where: value.contains) { return 90 }
    if ["30 day", "30-day", "30\u{5929}"].contains(where: value.contains) { return 30 }
    return 0
  }

  private static let toolCapabilities: Set<AgentCapability> = [.code, .deviceControl, .appNavigation, .knowledgeSearch, .mcp, .skill]
  private static let memoryTerms = ["memory", "remember", "recall", "\u{957f}\u{671f}\u{8bb0}\u{5fc6}", "\u{8bb0}\u{4f4f}", "\u{56de}\u{5fc6}"]
  private static let proactiveTerms = ["proactive", "insight", "\u{4e3b}\u{52a8}\u{63d0}\u{793a}", "\u{4e3b}\u{52a8}\u{53d1}\u{73b0}", "\u{6d1e}\u{5bdf}"]
}

enum AgentEvalStatistics {
  static func dashboard(samples: [AgentEvalSample], k: Int = 3, nowMillis: Int64 = AgentEvalClock.nowMillis()) -> AgentEvalDashboard {
    let boundedK = min(max(k, 2), 10)
    let verified = samples.filter(\.verified)
    let groups = Dictionary(grouping: verified) { "\($0.resourceId)|\($0.taskClass.rawValue)" }
    let resources = groups.values.compactMap { values -> AgentEvalResourceSummary? in
      guard let first = values.first else { return nil }
      return resourceSummary(resourceId: first.resourceId, taskClass: first.taskClass, samples: values, k: boundedK)
    }.sorted { $0.passAt1 == $1.passAt1 ? $0.averageLatencyMillis < $1.averageLatencyMillis : $0.passAt1 > $1.passAt1 }
    return AgentEvalDashboard(
      totalRuns: samples.count,
      verifiedRuns: verified.count,
      passAt1: ratio(verified.filter(\.passed).count, verified.count),
      passPowerK: empiricalPassPowerK(samples: verified, k: boundedK),
      averageLatencyMillis: average(verified.map(\.durationMillis)),
      recoveryRate: recoveryRate(verified),
      memory30DayAccuracy: optionalPassRate(verified.filter { $0.memoryHorizonDays == 30 }),
      memory90DayAccuracy: optionalPassRate(verified.filter { $0.memoryHorizonDays == 90 }),
      proactiveHitRate: optionalBooleanRate(verified.compactMap { sample in
        guard let relevant = sample.proactiveRelevant, let accepted = sample.proactiveAccepted else { return nil }
        return relevant && accepted
      }),
      proactiveDisturbanceRate: optionalBooleanRate(verified.compactMap { sample in
        guard let relevant = sample.proactiveRelevant, let accepted = sample.proactiveAccepted else { return nil }
        return !relevant || !accepted
      }),
      resources: resources,
      generatedAtMillis: nowMillis
    )
  }

  static func empiricalPassPowerK(samples: [AgentEvalSample], k: Int) -> Double {
    let boundedK = min(max(k, 2), 10)
    let groups = Dictionary(grouping: samples) { "\($0.scenarioId)|\($0.resourceId)" }.values
      .flatMap { $0.sorted { $0.completedAtMillis < $1.completedAtMillis }.chunked(size: boundedK) }
      .filter { $0.count == boundedK }
    return groups.isEmpty ? 0 : ratio(groups.filter { $0.allSatisfy(\.passed) }.count, groups.count)
  }

  static func theoreticalPassPowerK(passAt1: Double, k: Int) -> Double {
    pow(min(max(passAt1, 0), 1), Double(min(max(k, 2), 10)))
  }

  private static func resourceSummary(resourceId: String, taskClass: AgentEvalTaskClass, samples: [AgentEvalSample], k: Int) -> AgentEvalResourceSummary {
    let latencies = samples.map(\.durationMillis).sorted()
    let memory = samples.filter { $0.memoryHorizonDays > 0 }
    let proactive = samples.filter { $0.taskClass == .proactive }
    return AgentEvalResourceSummary(
      resourceId: resourceId,
      taskClass: taskClass,
      verifiedRuns: samples.count,
      passAt1: ratio(samples.filter(\.passed).count, samples.count),
      passPowerK: empiricalPassPowerK(samples: samples, k: k),
      averageLatencyMillis: average(latencies),
      p95LatencyMillis: percentile(latencies, fraction: 0.95),
      averageReportedCostMicros: average(samples.map(\.reportedCostMicros)),
      averageBatteryDeltaPercent: samples.isEmpty ? 0 : Double(samples.map(\.batteryDeltaPercent).reduce(0, +)) / Double(samples.count),
      peakThermalStatus: samples.map(\.peakThermalStatus).max() ?? -1,
      recoveryRate: recoveryRate(samples),
      memoryAccuracy: optionalPassRate(memory),
      proactiveHitRate: optionalBooleanRate(proactive.compactMap { sample in
        guard let relevant = sample.proactiveRelevant, let accepted = sample.proactiveAccepted else { return nil }
        return relevant && accepted
      }),
      proactiveDisturbanceRate: optionalBooleanRate(proactive.compactMap { sample in
        guard let relevant = sample.proactiveRelevant, let accepted = sample.proactiveAccepted else { return nil }
        return !relevant || !accepted
      })
    )
  }

  private static func recoveryRate(_ samples: [AgentEvalSample]) -> Double {
    let attempted = samples.filter(\.recoveryAttempted)
    return attempted.isEmpty ? 0 : ratio(attempted.filter(\.recovered).count, attempted.count)
  }

  private static func optionalPassRate(_ samples: [AgentEvalSample]) -> Double? {
    samples.isEmpty ? nil : ratio(samples.filter(\.passed).count, samples.count)
  }

  private static func optionalBooleanRate(_ values: [Bool]) -> Double? {
    values.isEmpty ? nil : ratio(values.filter { $0 }.count, values.count)
  }

  private static func average(_ values: [Int64]) -> Int64 {
    let positive = values.map { max(0, $0) }
    return positive.isEmpty ? 0 : positive.reduce(0, +) / Int64(positive.count)
  }

  private static func percentile(_ sorted: [Int64], fraction: Double) -> Int64 {
    guard !sorted.isEmpty else { return 0 }
    let index = Int(Double(sorted.count - 1) * min(max(fraction, 0), 1))
    return sorted[index]
  }

  private static func ratio(_ numerator: Int, _ denominator: Int) -> Double {
    denominator <= 0 ? 0 : Double(numerator) / Double(denominator)
  }
}

enum AgentEvalClock {
  static func nowMillis() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }
}

private extension Array {
  func chunked(size: Int) -> [[Element]] {
    guard size > 0 else { return [] }
    return stride(from: 0, to: count, by: size).map { start in
      Array(self[start..<Swift.min(start + size, count)])
    }
  }
}
