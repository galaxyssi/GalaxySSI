import Foundation

struct AgentContinuousEvalDecision: Equatable {
  var schedule: Bool
  var reason: String
}

enum AgentContinuousEvalPolicy {
  static func decide(
    settings: AgentEvalOpsSettings,
    run: AgentRecordedRun,
    sample: AgentEvalSample,
    availableAgentCount: Int,
    lastScheduledAtMillis: Int64,
    nowMillis: Int64 = AgentEvalClock.nowMillis()
  ) -> AgentContinuousEvalDecision {
    let reason: String
    if !settings.captureRealRuns {
      reason = "real_run_capture_disabled"
    } else if !settings.continuousEvaluationEnabled {
      reason = "continuous_evaluation_disabled"
    } else if run.conversationId.hasPrefix("lab:") {
      reason = "agent_lab_run"
    } else if run.status != .completed {
      reason = "run_not_completed"
    } else if run.originalRequest.isBlank {
      reason = "empty_task"
    } else if AgentLearningAnalyzer.containsSensitiveData(run.originalRequest) {
      reason = "sensitive_task"
    } else if availableAgentCount < 2 {
      reason = "insufficient_agents"
    } else if sample.scenarioId.isBlank {
      reason = "missing_scenario"
    } else if lastScheduledAtMillis > 0, nowMillis - lastScheduledAtMillis < 24 * 60 * 60_000 {
      reason = "scenario_cooldown"
    } else {
      reason = "scheduled"
    }
    return AgentContinuousEvalDecision(schedule: reason == "scheduled", reason: reason)
  }
}

final class AgentContinuousEvalStore {
  private struct State: Codable { var timestamps: [String: Int64] = [:] }

  static let defaultKey = "galaxyssi-ios-continuous-eval-v1"
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let key: String
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    key: String = AgentContinuousEvalStore.defaultKey
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.key = key
  }

  func lastScheduledAtMillis(scenarioId: String) -> Int64 {
    locked { load().timestamps[String(scenarioId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))] ?? 0 }
  }

  func recordScheduled(scenarioId: String, atMillis: Int64) {
    locked {
      var state = load()
      state.timestamps[String(scenarioId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))] = max(0, atMillis)
      if state.timestamps.count > 2_000 {
        state.timestamps = Dictionary(uniqueKeysWithValues: state.timestamps.sorted { $0.value > $1.value }.prefix(2_000))
      }
      save(state)
    }
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
}

enum AgentContinuousEvalCoordinator {
  static func observeCompletedRun(
    run: AgentRecordedRun,
    sample: AgentEvalSample,
    nowMillis: Int64 = AgentEvalClock.nowMillis()
  ) {
    Task {
      guard let runtime = AgentEvolutionLabRuntimeRegistry.shared.current() else { return }
      let settings = AgentEvalOpsStore().settings()
      let agents = Array((try? await runtime.availableAgents())?.prefix(4) ?? [])
      let store = AgentContinuousEvalStore()
      let decision = AgentContinuousEvalPolicy.decide(
        settings: settings,
        run: run,
        sample: sample,
        availableAgentCount: agents.count,
        lastScheduledAtMillis: store.lastScheduledAtMillis(scenarioId: sample.scenarioId),
        nowMillis: nowMillis
      )
      guard decision.schedule else { return }
      guard (try? await runtime.createAndStart(
        task: run.originalRequest,
        agentIds: agents.map(\.agentId),
        repetitions: settings.repeatedTrials
      )) != nil else { return }
      store.recordScheduled(scenarioId: sample.scenarioId, atMillis: nowMillis)
    }
  }
}
