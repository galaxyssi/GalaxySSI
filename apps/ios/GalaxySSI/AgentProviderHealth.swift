import Foundation

enum AgentProviderFailureKind: String, Codable {
  case timeout
  case transportCrash = "transport_crash"
  case authorization
  case protocolFailure = "protocol"
  case unavailable
  case execution
}

enum AgentProviderCircuitState: String, Codable {
  case closed
  case open
  case halfOpen = "half_open"
}

struct AgentProviderHealthSnapshot: Codable, Equatable {
  var scopeId: String
  var successes: Int
  var failures: Int
  var consecutiveFailures: Int
  var averageLatencyMillis: Int64
  var lastSuccessAtMillis: Int64
  var lastFailureAtMillis: Int64
  var circuitOpenUntilMillis: Int64
  var probeLeaseUntilMillis: Int64
  var lastFailureKind: AgentProviderFailureKind?
  var lastOperation: String

  init(
    scopeId: String,
    successes: Int = 0,
    failures: Int = 0,
    consecutiveFailures: Int = 0,
    averageLatencyMillis: Int64 = 0,
    lastSuccessAtMillis: Int64 = 0,
    lastFailureAtMillis: Int64 = 0,
    circuitOpenUntilMillis: Int64 = 0,
    probeLeaseUntilMillis: Int64 = 0,
    lastFailureKind: AgentProviderFailureKind? = nil,
    lastOperation: String = ""
  ) {
    self.scopeId = scopeId
    self.successes = max(0, successes)
    self.failures = max(0, failures)
    self.consecutiveFailures = max(0, consecutiveFailures)
    self.averageLatencyMillis = max(0, averageLatencyMillis)
    self.lastSuccessAtMillis = max(0, lastSuccessAtMillis)
    self.lastFailureAtMillis = max(0, lastFailureAtMillis)
    self.circuitOpenUntilMillis = max(0, circuitOpenUntilMillis)
    self.probeLeaseUntilMillis = max(0, probeLeaseUntilMillis)
    self.lastFailureKind = lastFailureKind
    self.lastOperation = lastOperation
  }

  func circuitState(nowMillis: Int64) -> AgentProviderCircuitState {
    if circuitOpenUntilMillis > nowMillis { return .open }
    if circuitOpenUntilMillis > 0 && consecutiveFailures > 0 { return .halfOpen }
    return .closed
  }

  static let circuitThreshold = 3
}

struct AgentProviderAttemptDecision {
  var allowed: Bool
  var scopeId: String
  var state: AgentProviderCircuitState
  var retryAtMillis: Int64
  var probe: Bool
}

protocol AgentProviderHealthLedger: AnyObject {
  func acquire(registration: AgentRegistration, operation: String, nowMillis: Int64) -> AgentProviderAttemptDecision
  func recordSuccess(registration: AgentRegistration, operation: String, latencyMillis: Int64, nowMillis: Int64)
  func recordFailure(
    registration: AgentRegistration,
    operation: String,
    kind: AgentProviderFailureKind,
    latencyMillis: Int64,
    nowMillis: Int64
  )
  func snapshot(registration: AgentRegistration) -> AgentProviderHealthSnapshot
  func snapshots() -> [AgentProviderHealthSnapshot]
  func clear()
}

protocol AgentProviderHealthPersistence: AnyObject {
  func load() -> [String: AgentProviderHealthSnapshot]
  func save(_ values: [AgentProviderHealthSnapshot])
  func clear()
}

private final class InMemoryAgentProviderHealthPersistence: AgentProviderHealthPersistence {
  private var values: [String: AgentProviderHealthSnapshot] = [:]

  func load() -> [String: AgentProviderHealthSnapshot] { values }

  func save(_ values: [AgentProviderHealthSnapshot]) {
    self.values = Dictionary(uniqueKeysWithValues: values.map { ($0.scopeId, $0) })
  }

  func clear() { values.removeAll() }
}

final class UserDefaultsAgentProviderHealthPersistence: AgentProviderHealthPersistence {
  private let defaults: UserDefaults
  private let key: String

  init(
    defaults: UserDefaults = .standard,
    key: String = "galaxyssi_agent_provider_health"
  ) {
    self.defaults = defaults
    self.key = key
  }

  func load() -> [String: AgentProviderHealthSnapshot] {
    guard let data = defaults.data(forKey: key),
      let decoded = try? JSONDecoder().decode([AgentProviderHealthSnapshot].self, from: data) else {
      return [:]
    }
    return Dictionary(uniqueKeysWithValues: decoded.map { ($0.scopeId, $0) })
  }

  func save(_ values: [AgentProviderHealthSnapshot]) {
    let retained = values
      .sorted { max($0.lastFailureAtMillis, $0.lastSuccessAtMillis) > max($1.lastFailureAtMillis, $1.lastSuccessAtMillis) }
      .prefix(256)
    if let data = try? JSONEncoder().encode(Array(retained)) {
      defaults.set(data, forKey: key)
    }
  }

  func clear() { defaults.removeObject(forKey: key) }
}

class PersistentAgentProviderHealthLedger: AgentProviderHealthLedger {
  private let persistence: AgentProviderHealthPersistence
  private let lock = NSRecursiveLock()

  init(persistence: AgentProviderHealthPersistence) {
    self.persistence = persistence
  }

  func acquire(
    registration: AgentRegistration,
    operation: String,
    nowMillis: Int64
  ) -> AgentProviderAttemptDecision {
    lock.lock()
    defer { lock.unlock() }
    var values = persistence.load()
    let scopeId = registration.runtimeHealthScope()
    let current = values[scopeId] ?? AgentProviderHealthSnapshot(scopeId: scopeId)
    let state = current.circuitState(nowMillis: nowMillis)
    if state == .open {
      return AgentProviderAttemptDecision(
        allowed: false,
        scopeId: scopeId,
        state: state,
        retryAtMillis: current.circuitOpenUntilMillis,
        probe: false
      )
    }
    if state == .halfOpen && current.probeLeaseUntilMillis > nowMillis {
      return AgentProviderAttemptDecision(
        allowed: false,
        scopeId: scopeId,
        state: state,
        retryAtMillis: current.probeLeaseUntilMillis,
        probe: false
      )
    }
    if state == .halfOpen {
      values[scopeId] = AgentProviderHealthSnapshot(
        scopeId: scopeId,
        successes: current.successes,
        failures: current.failures,
        consecutiveFailures: current.consecutiveFailures,
        averageLatencyMillis: current.averageLatencyMillis,
        lastSuccessAtMillis: current.lastSuccessAtMillis,
        lastFailureAtMillis: current.lastFailureAtMillis,
        circuitOpenUntilMillis: current.circuitOpenUntilMillis,
        probeLeaseUntilMillis: nowMillis + 30_000,
        lastFailureKind: current.lastFailureKind,
        lastOperation: operation
      )
      persistence.save(Array(values.values))
      return AgentProviderAttemptDecision(allowed: true, scopeId: scopeId, state: state, retryAtMillis: 0, probe: true)
    }
    return AgentProviderAttemptDecision(allowed: true, scopeId: scopeId, state: state, retryAtMillis: 0, probe: false)
  }

  func recordSuccess(
    registration: AgentRegistration,
    operation: String,
    latencyMillis: Int64,
    nowMillis: Int64
  ) {
    lock.lock()
    defer { lock.unlock() }
    var values = persistence.load()
    let scopeId = registration.runtimeHealthScope()
    let current = values[scopeId] ?? AgentProviderHealthSnapshot(scopeId: scopeId)
    let clearsFailure = current.consecutiveFailures == 0 ||
      current.lastOperation == operation ||
      (operation == "connect" || operation == "status") &&
        (current.lastFailureKind == .transportCrash || current.lastFailureKind == .authorization ||
          current.lastFailureKind == .protocolFailure || current.lastFailureKind == .unavailable)
    values[scopeId] = AgentProviderHealthSnapshot(
      scopeId: scopeId,
      successes: current.successes + 1,
      failures: current.failures,
      consecutiveFailures: clearsFailure ? 0 : current.consecutiveFailures,
      averageLatencyMillis: rollingAverage(current: current, latencyMillis: latencyMillis),
      lastSuccessAtMillis: nowMillis,
      lastFailureAtMillis: current.lastFailureAtMillis,
      circuitOpenUntilMillis: clearsFailure ? 0 : current.circuitOpenUntilMillis,
      probeLeaseUntilMillis: clearsFailure ? 0 : current.probeLeaseUntilMillis,
      lastFailureKind: clearsFailure ? nil : current.lastFailureKind,
      lastOperation: clearsFailure ? operation : current.lastOperation
    )
    persistence.save(Array(values.values))
  }

  func recordFailure(
    registration: AgentRegistration,
    operation: String,
    kind: AgentProviderFailureKind,
    latencyMillis: Int64,
    nowMillis: Int64
  ) {
    lock.lock()
    defer { lock.unlock() }
    var values = persistence.load()
    let scopeId = registration.runtimeHealthScope()
    let current = values[scopeId] ?? AgentProviderHealthSnapshot(scopeId: scopeId)
    let consecutive = current.consecutiveFailures + 1
    let threshold = Self.threshold(for: kind)
    let openUntil = consecutive >= threshold
      ? nowMillis + Self.cooldown(for: kind, excessFailures: consecutive - threshold)
      : 0
    values[scopeId] = AgentProviderHealthSnapshot(
      scopeId: scopeId,
      successes: current.successes,
      failures: current.failures + 1,
      consecutiveFailures: consecutive,
      averageLatencyMillis: rollingAverage(current: current, latencyMillis: latencyMillis),
      lastSuccessAtMillis: current.lastSuccessAtMillis,
      lastFailureAtMillis: nowMillis,
      circuitOpenUntilMillis: openUntil,
      probeLeaseUntilMillis: 0,
      lastFailureKind: kind,
      lastOperation: operation
    )
    persistence.save(Array(values.values))
  }

  func snapshot(registration: AgentRegistration) -> AgentProviderHealthSnapshot {
    lock.lock()
    defer { lock.unlock() }
    let scopeId = registration.runtimeHealthScope()
    return persistence.load()[scopeId] ?? AgentProviderHealthSnapshot(scopeId: scopeId)
  }

  func snapshots() -> [AgentProviderHealthSnapshot] {
    lock.lock()
    defer { lock.unlock() }
    return persistence.load().values.sorted { $0.scopeId < $1.scopeId }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    persistence.clear()
  }

  private func rollingAverage(current: AgentProviderHealthSnapshot, latencyMillis: Int64) -> Int64 {
    let sample = max(0, latencyMillis)
    let count = Int64(current.successes + current.failures)
    return count <= 0 ? sample : ((current.averageLatencyMillis * count) + sample) / (count + 1)
  }

  private static func threshold(for kind: AgentProviderFailureKind) -> Int {
    switch kind {
    case .transportCrash, .authorization, .protocolFailure: return 1
    case .timeout: return 2
    case .unavailable, .execution: return AgentProviderHealthSnapshot.circuitThreshold
    }
  }

  private static func cooldown(for kind: AgentProviderFailureKind, excessFailures: Int) -> Int64 {
    let base: Int64
    switch kind {
    case .authorization: base = 15 * 60_000
    case .protocolFailure: base = 5 * 60_000
    case .transportCrash: base = 2 * 60_000
    case .timeout: base = 60_000
    case .unavailable: base = 45_000
    case .execution: base = 30_000
    }
    return min(base * Int64(1 << min(max(0, excessFailures), 4)), 30 * 60_000)
  }
}

final class InMemoryAgentProviderHealthLedger: PersistentAgentProviderHealthLedger {
  init() { super.init(persistence: InMemoryAgentProviderHealthPersistence()) }
}

final class UserDefaultsAgentProviderHealthLedger: PersistentAgentProviderHealthLedger {
  init(defaults: UserDefaults = .standard) {
    super.init(persistence: UserDefaultsAgentProviderHealthPersistence(defaults: defaults))
  }
}

struct AgentProviderCircuitOpenError: LocalizedError {
  let scopeId: String
  let retryAtMillis: Int64

  var errorDescription: String? { "Agent runtime is temporarily unavailable" }
}

final class HealthIsolatedAgentAdapter: AgentAdapter {
  private let delegate: AgentAdapter
  private let family: String
  private let healthLedger: AgentProviderHealthLedger
  private let clock: () -> Int64

  var registration: AgentRegistration { delegate.registration }

  init(
    delegate: AgentAdapter,
    family: String,
    healthLedger: AgentProviderHealthLedger,
    clock: @escaping () -> Int64 = AgentControlPlaneClock.nowMillis
  ) {
    self.delegate = delegate
    self.family = family
    self.healthLedger = healthLedger
    self.clock = clock
  }

  func connect() async throws -> AgentProtocolAgreement {
    try await guarded("connect") { try await self.delegate.connect() }
  }

  func disconnect() async { await delegate.disconnect() }

  func status() async throws -> AgentRegistration {
    try await guarded("status") { try await self.delegate.status() }
  }

  func startRun(_ request: AgentRunRequest) async throws -> AgentRunHandle {
    try await guarded("start_run", recordSuccess: false) { try await self.delegate.startRun(request) }
  }

  func sendMessage(runId: String, message: AgentControlMessage) async throws {
    try await guarded("send_message") { try await self.delegate.sendMessage(runId: runId, message: message) }
  }

  func cancelRun(runId: String) async throws {
    try await guarded("cancel_run") { try await self.delegate.cancelRun(runId: runId) }
  }

  func observeEvents(runId: String) -> AsyncStream<AgentRunControlEvent> {
    delegate.observeEvents(runId: runId)
  }

  func recoverRuns() async throws -> [AgentRecoverableRun] {
    try await guarded("recover_runs") { try await self.delegate.recoverRuns() }
  }

  private func guarded<T>(
    _ operation: String,
    recordSuccess: Bool = true,
    _ block: @escaping () async throws -> T
  ) async throws -> T {
    let startedAt = clock()
    let decision = healthLedger.acquire(registration: registration, operation: operation, nowMillis: startedAt)
    guard decision.allowed else {
      throw AgentProviderCircuitOpenError(scopeId: decision.scopeId, retryAtMillis: decision.retryAtMillis)
    }
    do {
      let value = try await block()
      let finishedAt = clock()
      if recordSuccess {
        healthLedger.recordSuccess(
          registration: registration,
          operation: operation,
          latencyMillis: finishedAt - startedAt,
          nowMillis: finishedAt
        )
      }
      return value
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      let finishedAt = clock()
      healthLedger.recordFailure(
        registration: registration,
        operation: operation,
        kind: AgentProviderFailureClassifier.from(error: error),
        latencyMillis: finishedAt - startedAt,
        nowMillis: finishedAt
      )
      throw error
    }
  }

  var adapterFamily: String { family }
}

enum AgentProviderFailureClassifier {
  static func from(error: Error) -> AgentProviderFailureKind {
    classify(String(describing: error), transportException: error is AgentControlPlaneAdapterError)
  }

  static func from(result: AgentActionResult) -> AgentProviderFailureKind {
    classify(
      ([result.message] + result.metadata.map { "\($0.key)=\($0.value)" }).joined(separator: " "),
      transportException: false
    )
  }

  private static func classify(_ raw: String, transportException: Bool) -> AgentProviderFailureKind {
    let message = raw.lowercased()
    if message.contains("timeout") || message.contains("timed out") { return .timeout }
    if message.contains("unauthorized") || message.contains("forbidden") || message.contains("permission") ||
      message.contains("credential") || message.contains("api key") { return .authorization }
    if message.contains("protocol") || (message.contains("version") && message.contains("compatible")) {
      return .protocolFailure
    }
    if transportException || message.contains("connection reset") || message.contains("broken pipe") ||
      message.contains("process exited") || message.contains("process crashed") { return .transportCrash }
    if message.contains("unavailable") || message.contains("offline") || message.contains("not connected") ||
      message.contains("needs_setup") || message.contains("not configured") { return .unavailable }
    return .execution
  }
}

extension AgentRegistration {
  func runtimeHealthScope() -> String {
    let runtime = runtimeFailureDomain.trimmingCharacters(in: .whitespacesAndNewlines)
    if !runtime.isEmpty { return runtime }
    let installation = [installationId, deviceId, providerId]
      .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "unknown"
    return "\(installation):\(agentAdapterFamily())"
  }

  func agentAdapterFamily() -> String {
    let identity = [adapterType, agentId, providerId, displayName].joined(separator: " ").lowercased()
    if identity.contains("codex") { return "codex" }
    if identity.contains("claude-code") || identity.contains("claude_code") || identity.contains("claude code") { return "claude-code" }
    if identity.contains("openclaw") { return "openclaw" }
    if identity.contains("hermes") { return "hermes" }
    if identity.contains("windows-host") || identity.contains("windows_tools") { return "windows-host" }
    if identity.contains("android-device") || identity.contains("android_tools") { return "android-device" }
    if identity.contains("home-assistant") || identity.contains("home assistant") { return "home-assistant" }
    if identity.contains("local-model") || identity.contains("local_model") || identity.contains("local-llm") ||
      (kind == .model && location != .cloud) { return "local-model" }
    if identity.contains("cloud-model") || identity.contains("cloud_model") ||
      (kind == .model && location == .cloud) { return "cloud-model" }
    return "custom"
  }
}
