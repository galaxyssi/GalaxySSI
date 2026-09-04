import Foundation
import UIKit

enum AgentLabCampaignStatus: String, Codable, CaseIterable, Identifiable {
  case draft
  case running
  case readyForReview = "ready_for_review"
  case completed
  case cancelled
  var id: String { rawValue }
}

enum AgentLabTrialStatus: String, Codable, CaseIterable, Identifiable {
  case pending
  case running
  case completed
  case failed
  case cancelled
  var id: String { rawValue }
}

struct AgentLabTrial: Codable, Equatable, Identifiable {
  var id: String
  var agentId: String
  var blindAlias: String
  var repetition: Int
  var runId: String
  var status: AgentLabTrialStatus
  var evalSampleId: String

  init(
    id: String = UUID().uuidString,
    agentId: String,
    blindAlias: String,
    repetition: Int,
    runId: String = "",
    status: AgentLabTrialStatus = .pending,
    evalSampleId: String = ""
  ) {
    self.id = id
    self.agentId = agentId
    self.blindAlias = blindAlias
    self.repetition = max(1, repetition)
    self.runId = runId
    self.status = status
    self.evalSampleId = evalSampleId
  }
}

struct AgentLabCampaign: Codable, Equatable, Identifiable {
  var id: String
  var task: String
  var outcomeContract: AgentOutcomeContract
  var trials: [AgentLabTrial]
  var blindReview: Bool
  var status: AgentLabCampaignStatus
  var winnerTrialId: String
  var createdAtMillis: Int64
  var updatedAtMillis: Int64

  init(
    id: String = UUID().uuidString,
    task: String,
    outcomeContract: AgentOutcomeContract,
    trials: [AgentLabTrial],
    blindReview: Bool = true,
    status: AgentLabCampaignStatus = .draft,
    winnerTrialId: String = "",
    createdAtMillis: Int64 = AgentEvalClock.nowMillis(),
    updatedAtMillis: Int64? = nil
  ) {
    self.id = id
    self.task = String(task.prefix(4_000))
    self.outcomeContract = outcomeContract
    self.trials = trials
    self.blindReview = blindReview
    self.status = status
    self.winnerTrialId = winnerTrialId
    self.createdAtMillis = max(0, createdAtMillis)
    self.updatedAtMillis = max(0, updatedAtMillis ?? createdAtMillis)
  }
}

struct AgentLabBlindResult: Codable, Equatable, Identifiable {
  var id: String { trialId }
  var trialId: String
  var label: String
  var verdict: AgentEvalVerdict
  var durationMillis: Int64
  var reportedCostMicros: Int64
  var toolEvidenceCount: Int
  var artifactEvidenceCount: Int
  var recoverySucceeded: Bool
  var failureReasons: [String]
}

struct AgentSpecialtyProfile: Codable, Equatable, Identifiable {
  var id: String { resourceId }
  var resourceId: String
  var strongestTaskClass: AgentEvalTaskClass
  var verifiedSamples: Int
  var passAt1: Double
  var averageLatencyMillis: Int64
}

final class AgentLabStore {
  private struct State: Codable { var campaigns: [String: AgentLabCampaign] = [:] }

  static let defaultKey = "galaxyssi-ios-agent-lab-v1"
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let key: String
  private let nowMillis: () -> Int64
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    key: String = AgentLabStore.defaultKey,
    nowMillis: @escaping () -> Int64 = AgentEvalClock.nowMillis
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.key = key
    self.nowMillis = nowMillis
  }

  func create(task: String, agentIds: [String], repetitions: Int) -> AgentLabCampaign? {
    let task = String(task.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_000))
    var seen = Set<String>()
    let agents = agentIds.compactMap { value -> String? in
      let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return clean.isEmpty || !seen.insert(clean).inserted ? nil : clean
    }.prefixArray(12)
    guard !task.isEmpty, agents.count >= 2 else { return nil }
    let campaignId = UUID().uuidString
    var trials: [AgentLabTrial] = []
    for repetition in 1...min(max(repetitions, 1), 10) {
      for (index, agentId) in agents.enumerated() {
        let scalar = UnicodeScalar(65 + index).map { String(Character($0)) } ?? String(index + 1)
        trials.append(AgentLabTrial(
          agentId: agentId,
          blindAlias: "Agent \(scalar)",
          repetition: repetition
        ))
      }
    }
    let campaign = AgentLabCampaign(
      id: campaignId,
      task: task,
      outcomeContract: AgentOutcomeContractCompiler.compile(runId: "lab:\(campaignId)", goal: task),
      trials: trials,
      createdAtMillis: nowMillis()
    )
    save(campaign)
    return campaign
  }

  func save(_ campaign: AgentLabCampaign) {
    locked {
      var state = load()
      state.campaigns[campaign.id] = campaign
      state.campaigns = Dictionary(uniqueKeysWithValues: state.campaigns.values
        .sorted { $0.updatedAtMillis > $1.updatedAtMillis }
        .prefix(Self.maximumCampaigns)
        .map { ($0.id, $0) })
      persist(state)
    }
  }

  func get(id: String) -> AgentLabCampaign? {
    locked { load().campaigns[id.trimmingCharacters(in: .whitespacesAndNewlines)] }
  }

  func list(limit: Int = AgentLabStore.maximumCampaigns) -> [AgentLabCampaign] {
    locked {
      Array(load().campaigns.values.sorted { $0.updatedAtMillis > $1.updatedAtMillis }
        .prefix(min(max(limit, 1), Self.maximumCampaigns)))
    }
  }

  @discardableResult
  func bindRun(campaignId: String, trialId: String, runId: String) -> AgentLabCampaign? {
    guard var campaign = get(id: campaignId),
          campaign.trials.contains(where: { $0.id == trialId }),
          !runId.isBlank else { return nil }
    campaign.trials = campaign.trials.map { trial in
      guard trial.id == trialId else { return trial }
      var updated = trial
      updated.runId = runId
      updated.status = .running
      return updated
    }
    campaign.status = .running
    campaign.updatedAtMillis = nowMillis()
    save(campaign)
    return campaign
  }

  @discardableResult
  func observe(_ sample: AgentEvalSample) -> AgentLabCampaign? {
    guard var campaign = list().first(where: { $0.trials.contains { $0.runId == sample.runId } }) else { return nil }
    campaign.trials = campaign.trials.map { trial in
      guard trial.runId == sample.runId else { return trial }
      var updated = trial
      updated.status = sample.passed ? .completed : .failed
      updated.evalSampleId = sample.id
      return updated
    }
    let terminal: Set<AgentLabTrialStatus> = [.completed, .failed, .cancelled]
    campaign.status = campaign.trials.allSatisfy { terminal.contains($0.status) } ? .readyForReview : .running
    campaign.updatedAtMillis = nowMillis()
    save(campaign)
    return campaign
  }

  @discardableResult
  func selectWinner(campaignId: String, trialId: String) -> AgentLabCampaign? {
    guard var campaign = get(id: campaignId),
          campaign.trials.contains(where: { $0.id == trialId && $0.status == .completed }) else { return nil }
    campaign.winnerTrialId = trialId
    campaign.status = .completed
    campaign.updatedAtMillis = nowMillis()
    save(campaign)
    return campaign
  }

  func blindResults(campaignId: String, evalStore: AgentEvalOpsStore) -> [AgentLabBlindResult] {
    guard let campaign = get(id: campaignId) else { return [] }
    return campaign.trials.compactMap { trial in
      guard !trial.runId.isEmpty, let sample = evalStore.sample(runId: trial.runId) else { return nil }
      return AgentLabBlindResult(
        trialId: trial.id,
        label: campaign.blindReview ? "\(trial.blindAlias) · \(trial.repetition)" : trial.agentId,
        verdict: sample.verdict,
        durationMillis: sample.durationMillis,
        reportedCostMicros: sample.reportedCostMicros,
        toolEvidenceCount: sample.evidenceKinds.contains(.toolReceipt) ? 1 : 0,
        artifactEvidenceCount: sample.evidenceKinds.contains(.artifactDigest) ? 1 : 0,
        recoverySucceeded: sample.recovered,
        failureReasons: sample.failureReasons
      )
    }.sorted { left, right in
      if left.verdict == right.verdict { return left.durationMillis < right.durationMillis }
      return left.verdict == .passed
    }
  }

  func winnerRunIds(campaignId: String) -> [String] {
    guard let campaign = get(id: campaignId),
          let winner = campaign.trials.first(where: { $0.id == campaign.winnerTrialId }) else { return [] }
    return campaign.trials.filter { $0.agentId == winner.agentId && $0.status == .completed }
      .map(\.runId).filter { !$0.isEmpty }
  }

  private func load() -> State {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets),
          let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
    return state
  }

  private func persist(_ state: State) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: key, secrets: secrets)
  }

  private func locked<T>(_ work: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return work()
  }

  static let maximumCampaigns = 200
}

enum AgentSpecialtyAnalyzer {
  static func profiles(_ samples: [AgentEvalSample]) -> [AgentSpecialtyProfile] {
    Dictionary(grouping: samples.filter(\.verified), by: \.resourceId).compactMap { resourceId, values in
      let taskGroups = Dictionary(grouping: values, by: \.taskClass)
      guard let strongest = taskGroups.max(by: {
        passRate($0.value) < passRate($1.value)
      }) else { return nil }
      let latencies = strongest.value.map(\.durationMillis).filter { $0 > 0 }
      return AgentSpecialtyProfile(
        resourceId: resourceId,
        strongestTaskClass: strongest.key,
        verifiedSamples: strongest.value.count,
        passAt1: passRate(strongest.value),
        averageLatencyMillis: latencies.isEmpty ? 0 : latencies.reduce(0, +) / Int64(latencies.count)
      )
    }.sorted { $0.passAt1 > $1.passAt1 }
  }

  private static func passRate(_ values: [AgentEvalSample]) -> Double {
    values.isEmpty ? 0 : Double(values.filter(\.passed).count) / Double(values.count)
  }
}

enum AgentShadowReleaseStage: String, Codable, CaseIterable, Identifiable {
  case proposed
  case built
  case deviceShadow = "device_shadow"
  case comparing
  case canary
  case waitingApproval = "waiting_approval"
  case released
  case rolledBack = "rolled_back"
  case failed
  var id: String { rawValue }
}

struct AgentShadowReleaseMetrics: Codable, Equatable {
  var passAt1: Double
  var passPowerK: Double
  var averageLatencyMillis: Int64
  var averageBatteryDeltaPercent: Double
  var peakThermalStatus: Int
  var crashCount: Int
  var verifiedRuns: Int
}

struct AgentShadowRelease: Codable, Equatable, Identifiable {
  var id: String
  var evolutionTaskId: String
  var candidateCommit: String
  var candidateBranch: String
  var deviceModel: String
  var stage: AgentShadowReleaseStage
  var baseline: AgentShadowReleaseMetrics?
  var candidate: AgentShadowReleaseMetrics?
  var rollbackReason: String
  var createdAtMillis: Int64
  var updatedAtMillis: Int64

  init(
    id: String = UUID().uuidString,
    evolutionTaskId: String,
    candidateCommit: String,
    candidateBranch: String,
    deviceModel: String,
    stage: AgentShadowReleaseStage = .proposed,
    baseline: AgentShadowReleaseMetrics? = nil,
    candidate: AgentShadowReleaseMetrics? = nil,
    rollbackReason: String = "",
    createdAtMillis: Int64 = AgentEvalClock.nowMillis(),
    updatedAtMillis: Int64? = nil
  ) {
    self.id = id
    self.evolutionTaskId = evolutionTaskId
    self.candidateCommit = candidateCommit
    self.candidateBranch = candidateBranch
    self.deviceModel = deviceModel
    self.stage = stage
    self.baseline = baseline
    self.candidate = candidate
    self.rollbackReason = rollbackReason
    self.createdAtMillis = max(0, createdAtMillis)
    self.updatedAtMillis = max(0, updatedAtMillis ?? createdAtMillis)
  }
}

struct AgentShadowReleaseDecision: Codable, Equatable {
  var promote: Bool
  var rollback: Bool
  var reasons: [String]
}

enum AgentShadowReleasePolicy {
  static func compare(
    baseline: AgentShadowReleaseMetrics,
    candidate: AgentShadowReleaseMetrics
  ) -> AgentShadowReleaseDecision {
    var reasons: [String] = []
    if candidate.crashCount > baseline.crashCount { reasons.append("crash_regression") }
    if candidate.passAt1 + 0.02 < baseline.passAt1 { reasons.append("pass_at_1_regression") }
    if candidate.passPowerK + 0.02 < baseline.passPowerK { reasons.append("pass_power_k_regression") }
    if baseline.averageLatencyMillis > 0,
       Double(candidate.averageLatencyMillis) > Double(baseline.averageLatencyMillis) * 1.15 {
      reasons.append("latency_regression")
    }
    if candidate.averageBatteryDeltaPercent > baseline.averageBatteryDeltaPercent + 1 {
      reasons.append("battery_regression")
    }
    if candidate.peakThermalStatus > baseline.peakThermalStatus + 1 { reasons.append("thermal_regression") }
    if candidate.verifiedRuns < 10 { reasons.append("insufficient_shadow_evidence") }
    let hardFailures: Set<String> = ["crash_regression", "pass_at_1_regression", "pass_power_k_regression"]
    return AgentShadowReleaseDecision(
      promote: reasons.isEmpty,
      rollback: !hardFailures.isDisjoint(with: reasons),
      reasons: reasons
    )
  }
}

final class AgentShadowReleaseStore {
  private struct State: Codable { var releases: [String: AgentShadowRelease] = [:] }

  static let defaultKey = "galaxyssi-ios-shadow-release-v1"
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let key: String
  private let nowMillis: () -> Int64
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    key: String = AgentShadowReleaseStore.defaultKey,
    nowMillis: @escaping () -> Int64 = AgentEvalClock.nowMillis
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.key = key
    self.nowMillis = nowMillis
  }

  func create(task: AgentIOSSelfEvolutionTask, deviceModel: String = UIDevice.current.model) -> AgentShadowRelease? {
    guard !task.candidateCommit.isBlank, !task.candidateBranch.isBlank else { return nil }
    let release = AgentShadowRelease(
      evolutionTaskId: task.taskId,
      candidateCommit: task.candidateCommit,
      candidateBranch: task.candidateBranch,
      deviceModel: deviceModel.ifBlank("iOS"),
      createdAtMillis: nowMillis()
    )
    save(release)
    return release
  }

  func save(_ release: AgentShadowRelease) {
    locked {
      var state = load()
      var updated = release
      updated.updatedAtMillis = nowMillis()
      state.releases[updated.id] = updated
      state.releases = Dictionary(uniqueKeysWithValues: state.releases.values
        .sorted { $0.updatedAtMillis > $1.updatedAtMillis }
        .prefix(100).map { ($0.id, $0) })
      persist(state)
    }
  }

  func list(limit: Int = 100) -> [AgentShadowRelease] {
    locked {
      Array(load().releases.values.sorted { $0.updatedAtMillis > $1.updatedAtMillis }
        .prefix(min(max(limit, 1), 100)))
    }
  }

  private func load() -> State {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets),
          let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
    return state
  }

  private func persist(_ state: State) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: key, secrets: secrets)
  }

  private func locked<T>(_ work: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return work()
  }
}

enum AgentEvolutionLabService {
  @discardableResult
  static func observe(sample: AgentEvalSample, store: AgentLabStore = AgentLabStore()) -> AgentLabCampaign? {
    store.observe(sample)
  }
}

private extension Array {
  func prefixArray(_ count: Int) -> [Element] { Array(prefix(count)) }
}
