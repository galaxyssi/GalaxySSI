import Foundation

enum AgentBenchmarkDimension: String, Codable, CaseIterable, Identifiable {
  case taskQuality = "task_quality"
  case planningAndTools = "planning_and_tools"
  case iosWorld = "ios_world"
  case immediateMemory = "immediate_memory"
  case longTermMemory = "long_term_memory"
  case recovery
  case multiAgent = "multi_agent"

  var id: String { rawValue }
}

struct AgentBenchmarkExpectation: Codable, Equatable {
  var requiredOutputPatterns: [String] = []
  var requiredJsonFields: [String: String] = [:]
  var forbiddenOutputPatterns: [String] = []
  var minimumOutputCharacters: Int = 1
  var minimumPlanEvents: Int = 0
  var minimumToolReceipts: Int = 0
  var minimumVerifiedSources: Int = 0
  var minimumDistinctAgents: Int = 1
  var minimumHandoffs: Int = 0
  var requiredEvidence: Set<AgentOutcomeEvidenceKind> = [.finalResponse]
  var requiredCondition: AgentEvalCondition = .normal
  var memoryHorizonDays: Int = 0
  var iosWorldTaskId: String = ""
  var requireIOSObservedValuesInOutput = false
}

enum AgentBenchmarkReadinessStatus: String, Codable, CaseIterable {
  case ready
  case waiting
  case blocked
}

struct AgentBenchmarkCaseReadiness: Codable, Equatable {
  var caseId: String
  var status: AgentBenchmarkReadinessStatus
  var reasonCode: String = ""
  var eligibleAtMillis: Int64 = 0
}

struct AgentBenchmarkCase: Codable, Equatable, Identifiable {
  var id: String
  var dimension: AgentBenchmarkDimension
  var title: String
  var prompt: String
  var expectation: AgentBenchmarkExpectation
  var critical = true

  var taggedPrompt: String {
    var value = "[evalops:\(id)] \(prompt.trimmingCharacters(in: .whitespacesAndNewlines))"
    if !expectation.iosWorldTaskId.isEmpty {
      value += " [iosworld:\(expectation.iosWorldTaskId)]"
    }
    return value
  }
}

struct AgentBenchmarkSuite: Codable, Equatable, Identifiable {
  var id: String
  var version: String
  var title: String
  var cases: [AgentBenchmarkCase]
  var targetPassRate = 0.90
  var minimumTaskCount = 50
  var maximumTaskCount = 100
  var minimumRepetitions = 3
  var maximumRepetitions = 10

  init(
    id: String,
    version: String,
    title: String,
    cases: [AgentBenchmarkCase],
    targetPassRate: Double = 0.90,
    minimumTaskCount: Int = 50,
    maximumTaskCount: Int = 100,
    minimumRepetitions: Int = 3,
    maximumRepetitions: Int = 10
  ) {
    precondition((minimumTaskCount...maximumTaskCount).contains(cases.count))
    precondition(Set(cases.map(\.id)).count == cases.count)
    self.id = id
    self.version = version
    self.title = title
    self.cases = cases
    self.targetPassRate = min(max(targetPassRate, 0), 1)
    self.minimumTaskCount = minimumTaskCount
    self.maximumTaskCount = maximumTaskCount
    self.minimumRepetitions = minimumRepetitions
    self.maximumRepetitions = maximumRepetitions
  }

  func benchmarkCase(id: String) -> AgentBenchmarkCase? {
    cases.first { $0.id == id }
  }
}

struct AgentBenchmarkResourceSnapshot: Codable, Equatable, Identifiable {
  var resourceId: String
  var displayName: String
  var providerId: String
  var modelId: String
  var adapterType: String
  var capabilitiesHash: String
  var id: String { resourceId }
}

enum AgentBenchmarkSessionStatus: String, Codable, CaseIterable {
  case running
  case completed
  case cancelled
}

struct AgentBenchmarkSession: Codable, Equatable, Identifiable {
  var id: String = UUID().uuidString
  var suiteId: String
  var suiteVersion: String
  var appVersionName: String
  var appBuildNumber: String
  var deviceModel: String
  var systemVersion: String
  var repetitions: Int
  var targetPassRate: Double
  var caseIds: [String]
  var resources: [AgentBenchmarkResourceSnapshot]
  var resourceIdsByCase: [String: [String]]
  var campaignIdsByCase: [String: String]
  var teamResourceIdsByCase: [String: [String]] = [:]
  var readinessByCase: [String: AgentBenchmarkCaseReadiness] = [:]
  var allocationProfile = "codex_90_deepseek_10"
  var status: AgentBenchmarkSessionStatus = .running
  var createdAtMillis: Int64 = AgentEvalClock.nowMillis()
  var updatedAtMillis: Int64 = AgentEvalClock.nowMillis()

  var scheduledCaseIds: [String] {
    readinessByCase.isEmpty ? caseIds : caseIds.filter { readinessByCase[$0]?.status == .ready }
  }

  var expectedTrials: Int {
    scheduledCaseIds.reduce(0) { $0 + (resourceIdsByCase[$1]?.count ?? 0) } * repetitions
  }
}

extension AgentBenchmarkSession {
  private enum CodingKeys: String, CodingKey {
    case id, suiteId, suiteVersion, appVersionName, appBuildNumber, deviceModel, systemVersion
    case repetitions, targetPassRate, caseIds, resources, resourceIdsByCase, campaignIdsByCase
    case teamResourceIdsByCase, readinessByCase, allocationProfile, status, createdAtMillis, updatedAtMillis
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
    suiteId = try values.decodeIfPresent(String.self, forKey: .suiteId) ?? ""
    suiteVersion = try values.decodeIfPresent(String.self, forKey: .suiteVersion) ?? ""
    appVersionName = try values.decodeIfPresent(String.self, forKey: .appVersionName) ?? ""
    appBuildNumber = try values.decodeIfPresent(String.self, forKey: .appBuildNumber) ?? ""
    deviceModel = try values.decodeIfPresent(String.self, forKey: .deviceModel) ?? ""
    systemVersion = try values.decodeIfPresent(String.self, forKey: .systemVersion) ?? ""
    repetitions = try values.decodeIfPresent(Int.self, forKey: .repetitions) ?? 1
    targetPassRate = try values.decodeIfPresent(Double.self, forKey: .targetPassRate) ?? 0.90
    caseIds = try values.decodeIfPresent([String].self, forKey: .caseIds) ?? []
    resources = try values.decodeIfPresent([AgentBenchmarkResourceSnapshot].self, forKey: .resources) ?? []
    resourceIdsByCase = try values.decodeIfPresent([String: [String]].self, forKey: .resourceIdsByCase) ?? [:]
    campaignIdsByCase = try values.decodeIfPresent([String: String].self, forKey: .campaignIdsByCase) ?? [:]
    teamResourceIdsByCase = try values.decodeIfPresent([String: [String]].self, forKey: .teamResourceIdsByCase) ?? [:]
    readinessByCase = try values.decodeIfPresent([String: AgentBenchmarkCaseReadiness].self, forKey: .readinessByCase) ?? [:]
    allocationProfile = try values.decodeIfPresent(String.self, forKey: .allocationProfile) ?? "codex_90_deepseek_10"
    status = try values.decodeIfPresent(AgentBenchmarkSessionStatus.self, forKey: .status) ?? .running
    createdAtMillis = try values.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? AgentEvalClock.nowMillis()
    updatedAtMillis = try values.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ?? createdAtMillis
  }
}

struct AgentBenchmarkTrialResult: Codable, Equatable, Identifiable {
  var id: String = UUID().uuidString
  var sessionId: String
  var caseId: String
  var campaignId: String
  var trialId: String
  var runId: String
  var resourceId: String
  var repetition: Int
  var passed: Bool
  var verified: Bool
  var failureReasons: [String]
  var durationMillis: Int64
  var reportedCostMicros: Int64
  var batteryDeltaPercent: Int
  var peakThermalStatus: Int
  var completedAtMillis: Int64 = AgentEvalClock.nowMillis()
}

struct AgentBenchmarkMetric: Codable, Equatable, Identifiable {
  var dimension: AgentBenchmarkDimension?
  var taskCount: Int
  var coveredTaskCount: Int
  var expectedTrials: Int
  var completedTrials: Int
  var verifiedTrials: Int
  var passAt1: Double?
  var passPowerK: Double?
  var averageLatencyMillis: Int64
  var averageReportedCostMicros: Int64
  var averageBatteryDeltaPercent: Double
  var peakThermalStatus: Int
  var qualified: Bool
  var targetMet: Bool
  var passedTrials: Int = 0
  var capabilityFailureTrials: Int = 0
  var infrastructureFailureTrials: Int = 0
  var waitingForRealConditionTrials: Int = 0
  var evaluableTrials: Int = 0
  var evaluableTaskCount: Int = 0
  var certificationComplete = false
  var plannedTrials: Int = 0
  var notExecutedTrials: Int = 0
  var blockedTrials: Int = 0
  var certificationCoverage: Double? = nil
  var id: String { dimension?.rawValue ?? "overall" }
}

struct AgentBenchmarkTrialEvidence: Codable, Equatable, Identifiable {
  var caseId: String
  var caseTitle: String
  var dimension: AgentBenchmarkDimension
  var resourceName: String
  var repetition: Int
  var classification: AgentBenchmarkTrialClassification
  var failureReasons: [String]
  var rawOutput: String
  var planEventCount: Int
  var toolReceipts: [String]
  var iosWorldEvidence: [String]
  var runId: String

  var id: String { runId }
}

struct AgentBenchmarkResourceScore: Codable, Equatable, Identifiable {
  var resource: AgentBenchmarkResourceSnapshot
  var overall: AgentBenchmarkMetric
  var dimensions: [AgentBenchmarkMetric]
  var id: String { resource.resourceId }
}

struct AgentBenchmarkScorecard: Codable, Equatable {
  var session: AgentBenchmarkSession
  var overall: AgentBenchmarkMetric
  var dimensions: [AgentBenchmarkMetric]
  var resources: [AgentBenchmarkResourceScore]
  var generatedAtMillis: Int64 = AgentEvalClock.nowMillis()
}

struct AgentBenchmarkProgress: Codable, Equatable {
  var completedTrials: Int
  var expectedTrials: Int
  var completedCampaigns: Int
  var totalCampaigns: Int
  var terminal: Bool
}

struct AgentBenchmarkAllocation: Equatable {
  var resources: [AgentRegistration]
  var resourceIdsByCase: [String: [String]]
  var teamResourceIdsByCase: [String: [String]] = [:]
}

struct AgentBenchmarkError: LocalizedError, Equatable {
  var message: String
  var errorDescription: String? { message }
}
