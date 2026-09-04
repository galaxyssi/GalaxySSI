import Foundation

final class AgentBenchmarkStore {
  private struct State: Codable {
    var sessions: [String: AgentBenchmarkSession]
    var results: [String: AgentBenchmarkTrialResult]
    var resultCounts: [String: Int]

    init(
      sessions: [String: AgentBenchmarkSession] = [:],
      results: [String: AgentBenchmarkTrialResult] = [:],
      resultCounts: [String: Int] = [:]
    ) {
      self.sessions = sessions
      self.results = results
      self.resultCounts = resultCounts
    }

    enum CodingKeys: String, CodingKey { case sessions, results, resultCounts }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      sessions = try container.decodeIfPresent([String: AgentBenchmarkSession].self, forKey: .sessions) ?? [:]
      results = try container.decodeIfPresent([String: AgentBenchmarkTrialResult].self, forKey: .results) ?? [:]
      resultCounts = try container.decodeIfPresent([String: Int].self, forKey: .resultCounts) ?? [:]
    }
  }

  static let defaultKey = "galaxyssi-ios-agent-benchmark-v1"
  static let maximumSessions = 20
  static let maximumResults = 5_000

  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let key: String
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    key: String = AgentBenchmarkStore.defaultKey
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.key = key
  }

  func saveSession(_ session: AgentBenchmarkSession) {
    locked {
      var state = load()
      let isNewSession = state.sessions[session.id] == nil
      state.sessions[session.id] = session
      if isNewSession { state.resultCounts[session.id] = 0 }
      prune(&state)
      save(state)
    }
  }

  func session(id: String) -> AgentBenchmarkSession? {
    locked { load().sessions[id.trimmingCharacters(in: .whitespacesAndNewlines)] }
  }

  func sessions(limit: Int = AgentBenchmarkStore.maximumSessions) -> [AgentBenchmarkSession] {
    locked {
      Array(load().sessions.values.sorted { $0.updatedAtMillis > $1.updatedAtMillis }
        .prefix(min(max(limit, 1), Self.maximumSessions)))
    }
  }

  @discardableResult
  func saveResult(
    _ result: AgentBenchmarkTrialResult,
    completedTrialsFloor: Int = 0
  ) -> Int {
    guard !result.runId.isBlank else { return 0 }
    return locked {
      var state = load()
      let isNewResult = state.results[result.runId] == nil
      state.results[result.runId] = result
      let current = max(0, state.resultCounts[result.sessionId] ?? 0)
      let updated = AgentBenchmarkProgressCounter.next(
        current: current,
        isNewResult: isNewResult,
        completedTrialsFloor: completedTrialsFloor
      )
      state.resultCounts[result.sessionId] = updated
      if state.results.count > Self.maximumResults + Self.resultPruneBatch {
        prune(&state)
      }
      save(state)
      return updated
    }
  }

  func resultCount(sessionId: String) -> Int? {
    locked { load().resultCounts[sessionId.trimmingCharacters(in: .whitespacesAndNewlines)] }
  }

  func results(sessionId: String, limit: Int = AgentBenchmarkStore.maximumResults) -> [AgentBenchmarkTrialResult] {
    locked {
      Array(load().results.values.filter { $0.sessionId == sessionId }
        .sorted { $0.completedAtMillis < $1.completedAtMillis }
        .suffix(min(max(limit, 1), Self.maximumResults)))
    }
  }

  @discardableResult
  func markStatus(id: String, status: AgentBenchmarkSessionStatus) -> AgentBenchmarkSession? {
    guard var session = session(id: id) else { return nil }
    session.status = status
    session.updatedAtMillis = AgentEvalClock.nowMillis()
    saveSession(session)
    return session
  }

  func clear() {
    GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: key, secrets: secrets)
  }

  private func prune(_ state: inout State) {
    let retainedSessions = state.sessions.values.sorted { $0.updatedAtMillis > $1.updatedAtMillis }
      .prefix(Self.maximumSessions)
    let retainedIds = Set(retainedSessions.map(\.id))
    state.sessions = Dictionary(uniqueKeysWithValues: retainedSessions.map { ($0.id, $0) })
    state.results = Dictionary(uniqueKeysWithValues: state.results.values
      .filter { retainedIds.contains($0.sessionId) }
      .sorted { $0.completedAtMillis > $1.completedAtMillis }
      .prefix(Self.maximumResults)
      .map { ($0.runId, $0) })
    state.resultCounts = state.resultCounts.filter { retainedIds.contains($0.key) }
  }

  private func load() -> State {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets),
          let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
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

  private static let resultPruneBatch = 128
}

enum AgentBenchmarkProgressCounter {
  static func next(current: Int, isNewResult: Bool, completedTrialsFloor: Int) -> Int {
    max(max(0, current) + (isNewResult ? 1 : 0), max(0, completedTrialsFloor))
  }
}

enum AgentBenchmarkStatistics {
  static func scorecard(
    session: AgentBenchmarkSession,
    suite: AgentBenchmarkSuite,
    allResults: [AgentBenchmarkTrialResult],
    nowMillis: Int64 = AgentEvalClock.nowMillis()
  ) -> AgentBenchmarkScorecard {
    let latest = Dictionary(grouping: allResults.filter { $0.sessionId == session.id }, by: \.trialId)
      .compactMap { $0.value.max { $0.completedAtMillis < $1.completedAtMillis } }
    let dimensions = AgentBenchmarkDimension.allCases.map { dimension in
      metric(session: session, caseIds: session.caseIds.filter { suite.benchmarkCase(id: $0)?.dimension == dimension },
        results: latest, target: suite.targetPassRate, resourceId: nil, dimension: dimension)
    }
    let resources = session.resources.map { resource in
      let assigned = session.caseIds.filter { session.resourceIdsByCase[$0, default: []].contains(resource.resourceId) }
      let results = latest.filter { $0.resourceId == resource.resourceId }
      return AgentBenchmarkResourceScore(
        resource: resource,
        overall: metric(session: session, caseIds: assigned, results: results,
          target: suite.targetPassRate, resourceId: resource.resourceId, dimension: nil),
        dimensions: AgentBenchmarkDimension.allCases.map { dimension in
          metric(session: session, caseIds: assigned.filter { suite.benchmarkCase(id: $0)?.dimension == dimension },
            results: results, target: suite.targetPassRate, resourceId: resource.resourceId, dimension: dimension)
        }
      )
    }
    return AgentBenchmarkScorecard(
      session: session,
      overall: metric(session: session, caseIds: session.caseIds, results: latest,
        target: suite.targetPassRate, resourceId: nil, dimension: nil),
      dimensions: dimensions,
      resources: resources,
      generatedAtMillis: nowMillis
    )
  }

  private static func metric(
    session: AgentBenchmarkSession,
    caseIds: [String],
    results: [AgentBenchmarkTrialResult],
    target: Double,
    resourceId: String?,
    dimension: AgentBenchmarkDimension?
  ) -> AgentBenchmarkMetric {
    let assignments = caseIds.flatMap { caseId in
      session.resourceIdsByCase[caseId, default: []]
        .filter { resourceId == nil || $0 == resourceId }
        .map { (caseId, $0) }
    }
    let relevant = results.filter { result in
      assignments.contains { $0.0 == result.caseId && $0.1 == result.resourceId }
    }
    let expectedTrials = assignments.count * session.repetitions
    let completedGroups = assignments.filter { pair in
      relevant.filter { $0.caseId == pair.0 && $0.resourceId == pair.1 }.count >= session.repetitions
    }
    let coveredTasks = caseIds.filter { caseId in
      let assigned = assignments.filter { $0.0 == caseId }
      return !assigned.isEmpty && assigned.allSatisfy { pair in
        relevant.filter { $0.caseId == pair.0 && $0.resourceId == pair.1 }.count >= session.repetitions
      }
    }.count
    let passAt1 = relevant.isEmpty ? nil : Double(relevant.filter(\.passed).count) / Double(relevant.count)
    let passPowerK: Double? = completedGroups.isEmpty ? nil : Double(assignments.filter { pair in
      let group = relevant.filter { $0.caseId == pair.0 && $0.resourceId == pair.1 }
        .sorted { $0.completedAtMillis < $1.completedAtMillis }
      return group.count >= session.repetitions && group.suffix(session.repetitions).allSatisfy(\.passed)
    }.count) / Double(completedGroups.count)
    let qualified = !assignments.isEmpty && relevant.count >= expectedTrials && completedGroups.count == assignments.count
    return AgentBenchmarkMetric(
      dimension: dimension,
      taskCount: caseIds.count,
      coveredTaskCount: coveredTasks,
      expectedTrials: expectedTrials,
      completedTrials: min(relevant.count, expectedTrials),
      verifiedTrials: min(relevant.filter(\.verified).count, expectedTrials),
      passAt1: passAt1,
      passPowerK: passPowerK,
      averageLatencyMillis: average(relevant.map(\.durationMillis)),
      averageReportedCostMicros: average(relevant.map(\.reportedCostMicros)),
      averageBatteryDeltaPercent: relevant.isEmpty ? 0 : Double(relevant.map(\.batteryDeltaPercent).reduce(0, +)) / Double(relevant.count),
      peakThermalStatus: relevant.map(\.peakThermalStatus).max() ?? -1,
      qualified: qualified,
      targetMet: qualified && (passAt1 ?? 0) >= target && (passPowerK ?? 0) >= target
    )
  }

  private static func average(_ values: [Int64]) -> Int64 {
    values.isEmpty ? 0 : values.reduce(0, +) / Int64(values.count)
  }
}

enum AgentBenchmarkComparisonPolicy {
  static func comparable(_ left: AgentBenchmarkSession, _ right: AgentBenchmarkSession) -> Bool {
    left.suiteId == right.suiteId &&
      left.suiteVersion == right.suiteVersion &&
      left.caseIds == right.caseIds &&
      left.repetitions == right.repetitions &&
      left.caseIds.map { left.resourceIdsByCase[$0, default: []].count } ==
        right.caseIds.map { right.resourceIdsByCase[$0, default: []].count }
  }
}
