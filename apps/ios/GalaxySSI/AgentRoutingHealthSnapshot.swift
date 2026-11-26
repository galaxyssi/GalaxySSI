import Foundation

enum AgentProviderAvailabilityPolicy {
  static func observingReadiness(_ current: AgentProviderHealthSnapshot,
                                registration: AgentRegistration, nowMillis: Int64) -> AgentProviderHealthSnapshot? {
    guard [.online, .idle, .busy].contains(registration.status), nowMillis > 0,
          current.circuitState(nowMillis: nowMillis) == .open,
          current.probeLeaseUntilMillis <= nowMillis,
          registration.lastHeartbeatMillis > current.lastFailureAtMillis,
          registration.lastHeartbeatMillis <= nowMillis || registration.lastHeartbeatMillis - nowMillis <= 60_000,
          current.lastFailureKind == .transportCrash || current.lastFailureKind == .unavailable ||
            (current.lastFailureKind == .execution && current.lastOperation == "start_run") else { return nil }
    var observed = current
    observed.circuitOpenUntilMillis = nowMillis
    return observed
  }
}

struct AgentRoutingResourceHealth: Equatable {
  var target: AgentProviderHealthSnapshot?
  var domain: AgentProviderHealthSnapshot?
  var selectable: Bool

  var targetLatencyMillis: Int64 {
    Self.reliability(target) == nil ? 0 : max(0, target?.averageLatencyMillis ?? 0)
  }
  var domainLatencyMillis: Int64 {
    Self.reliability(domain) == nil ? 0 : max(0, domain?.averageLatencyMillis ?? 0)
  }

  static func reliability(_ snapshot: AgentProviderHealthSnapshot?) -> Int? {
    guard let snapshot, snapshot.successes >= 0, snapshot.failures >= 0,
          snapshot.successes > 0 || snapshot.failures > 0 else { return nil }
    let total = Double(snapshot.successes) + Double(snapshot.failures)
    return Int(min(100, max(0, Double(snapshot.successes) / total * 100)))
  }
}

struct AgentRoutingHealthSnapshot: Equatable {
  private(set) var resources: [String: AgentRoutingResourceHealth] = [:]

  init(registrations: [AgentRegistration], snapshots: [AgentProviderHealthSnapshot], nowMillis: Int64) {
    guard nowMillis > 0 else { return }
    let records = snapshots.reduce(into: [String: AgentProviderHealthSnapshot]()) { $0[$1.scopeId] = $1 }
    for registration in registrations where !registration.agentId.isBlank && resources[registration.agentId] == nil {
      let runtime = records[registration.runtimeHealthScope()]
      let observed = runtime.flatMap {
        AgentProviderAvailabilityPolicy.observingReadiness($0, registration: registration, nowMillis: nowMillis)
      } ?? runtime
      let provider = registration.cloudProviderHealthScopeId.flatMap { records[$0] }
      let runtimeAllowed = observed.map {
        $0.circuitState(nowMillis: nowMillis) != .open &&
          ($0.circuitState(nowMillis: nowMillis) != .halfOpen || $0.probeLeaseUntilMillis <= nowMillis)
      } ?? true
      let providerAllowed = provider.map { provider in
        provider.circuitState(nowMillis: nowMillis) != .open || observed.map {
          CloudProviderHealthRecoveryPolicy.shouldRecoverProviderCircuit(target: $0, provider: provider, nowMillis: nowMillis)
        } == true
      } ?? true
      let target = records[registration.targetHealthScopeId]
      let domain = provider ?? runtime
      resources[registration.agentId] = AgentRoutingResourceHealth(target: target,
        domain: domain?.scopeId == target?.scopeId ? nil : domain, selectable: runtimeAllowed && providerAllowed)
    }
  }

  func allows(targetId: String) -> Bool { resources[targetId]?.selectable ?? true }

  static func capture(registrations: [AgentRegistration], ledger: AgentProviderHealthLedger,
                      nowMillis: Int64) -> AgentRoutingHealthSnapshot {
    // Read only: selection must not acquire a probe lease, reset a circuit or record success.
    AgentRoutingHealthSnapshot(registrations: registrations, snapshots: ledger.snapshots(), nowMillis: nowMillis)
  }
}
