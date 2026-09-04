import CryptoKit
import Foundation

enum AgentConnectorCapacityPolicy {
  static let maximumParallelRuns = 10

  static func normalize(_ value: Int) -> Int {
    min(max(value, 1), maximumParallelRuns)
  }
}

enum AgentRuntimeIdentity {
  static func key(_ registration: AgentRegistration) -> String {
    registration.runtimeFailureDomain
      .ifBlank(registration.failureDomain)
      .ifBlank([registration.installationId, registration.adapterType]
        .filter { !$0.isBlank }
        .joined(separator: ":"))
      .ifBlank(registration.agentId)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }
}

enum AgentMentionCandidatePolicy {
  private static let genericAliases: Set<String> = ["codex", "hermes", "claude-code", "openclaw"]

  static func select(
    targets: [AgentCallableTarget],
    registrations: [AgentRegistration],
    reservedByAgentId: [String: Int],
    limit: Int
  ) -> [AgentRegistration] {
    let availableTargetIds = Set(targets.filter {
      $0.status == .available && [.agent, .model].contains($0.kind)
    }.map(\.id))
    var seen = Set<String>()
    let reachable = registrations.filter {
      availableTargetIds.contains($0.agentId) &&
        [.agent, .model].contains($0.kind) &&
        [.online, .idle, .busy].contains($0.status) &&
        seen.insert($0.agentId).inserted
    }
    let concreteProducts = Set(reachable.filter {
      !genericAliases.contains($0.agentId.lowercased())
    }.map(productId))

    return Array(reachable.filter { registration in
      let id = registration.agentId.lowercased()
      return !(genericAliases.contains(id) && concreteProducts.contains(productId(registration)))
    }.filter { registration in
      registration.activeRuns + (reservedByAgentId[registration.agentId] ?? 0) <
        max(registration.maxParallelRuns, 1)
    }.sorted { lhs, rhs in
      if lhs.activeRuns != rhs.activeRuns { return lhs.activeRuns < rhs.activeRuns }
      return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }.prefix(max(limit, 0)))
  }

  static func registration(for target: AgentCallableTarget, activeRuns: Int = 0) -> AgentRegistration {
    let profile = target.providerProfile
    let isLocalModel = target.id == "local-llm" ||
      target.capabilities.contains(.localInference) ||
      profile?.kind == .localModel
    let isSharedRemote = target.kind == .agent ||
      (target.kind == .model && !isLocalModel)
    let maximum = isSharedRemote
      ? AgentConnectorCapacityPolicy.maximumParallelRuns
      : AgentConnectorCapacityPolicy.normalize(profile?.maxParallelRuns ?? (isLocalModel ? 2 : 1))
    let product = (profile?.metadata["native_product_identity"] ?? "")
      .ifBlank(profile?.productId ?? "")
      .ifBlank(target.id.split(separator: ":").last.map(String.init) ?? target.id)
      .lowercased()
    let runtimeFailureDomain = target.runtimeFailureDomain.ifBlank(
      [target.failureDomain, product].filter { !$0.isBlank }.joined(separator: ":")
    )
    return AgentRegistration(
      agentId: target.id,
      installationId: target.failureDomain.ifBlank(target.id),
      deviceId: target.failureDomain.ifBlank(target.id),
      providerId: profile?.providerId.ifBlank("signalasi-connectors") ?? "signalasi-connectors",
      displayName: target.title,
      kind: target.kind,
      location: profile?.location ?? (target.id == "local-llm" ? .phone : .trustedDesktop),
      status: target.status == .available ? .online : .offline,
      capabilities: Set(target.capabilities),
      toolIds: profile?.toolIds ?? [],
      connectionKind: target.kind == .model ? .http : .signalasiLink,
      cost: profile?.pricing.tier ?? .free,
      latency: profile?.latency ?? .normal,
      trust: profile?.trust ?? .verifiedPaired,
      activeRuns: max(activeRuns, 0),
      maxParallelRuns: maximum,
      failureDomain: target.failureDomain,
      runtimeFailureDomain: runtimeFailureDomain,
      adapterType: target.adapterType,
      independentlyUpgradeable: target.independentlyUpgradeable,
      providerProfile: profile.map { current in
        var updated = current
        updated.maxParallelRuns = maximum
        return updated
      }
    )
  }

  private static func productId(_ registration: AgentRegistration) -> String {
    let raw = (registration.providerProfile?.metadata["native_product_identity"] ?? "")
      .ifBlank(registration.providerProfile?.productId ?? "")
      .ifBlank(registration.agentId.split(separator: ":").last.map(String.init) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "_", with: "-")
    return raw == "claude-code" ? "claude" : raw
  }
}

struct AgentGlobalRunSlot: Codable, Equatable {
  var ownerId: String
  var runtimeKey: String
  var sourceMessageId: String
  var startedAtMillis: Int64
  var lastActivityAtMillis: Int64

  init(
    ownerId: String,
    runtimeKey: String,
    sourceMessageId: String = "",
    startedAtMillis: Int64,
    lastActivityAtMillis: Int64? = nil
  ) {
    self.ownerId = ownerId
    self.runtimeKey = runtimeKey
    self.sourceMessageId = sourceMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.startedAtMillis = startedAtMillis
    self.lastActivityAtMillis = lastActivityAtMillis ?? startedAtMillis
  }
}

final class AgentGlobalRunSlotLedger {
  private var slots: [String: AgentGlobalRunSlot]

  init(records: [AgentGlobalRunSlot] = []) {
    slots = Dictionary(uniqueKeysWithValues: records.map { ($0.ownerId, $0) })
  }

  func acquire(
    ownerId: String,
    runtimeKey: String,
    maxParallelRuns: Int,
    nowMillis: Int64
  ) -> Bool {
    let owner = ownerId.trimmingCharacters(in: .whitespacesAndNewlines)
    let runtime = runtimeKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !owner.isEmpty, !runtime.isEmpty else { return false }
    if let current = slots[owner] { return current.runtimeKey == runtime }
    guard activeCount(runtimeKey: runtime) < AgentConnectorCapacityPolicy.normalize(maxParallelRuns) else {
      return false
    }
    slots[owner] = AgentGlobalRunSlot(
      ownerId: owner,
      runtimeKey: runtime,
      startedAtMillis: nowMillis
    )
    return true
  }

  func bindSourceMessage(ownerId: String, sourceMessageId: String) -> Bool {
    let source = sourceMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !source.isEmpty, var current = slots[ownerId] else { return false }
    current.sourceMessageId = source
    slots[ownerId] = current
    return true
  }

  func release(ownerId: String) -> Bool {
    slots.removeValue(forKey: ownerId) != nil
  }

  func release(sourceMessageId: String) -> Bool {
    let source = sourceMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !source.isEmpty else { return false }
    let owners = slots.values.filter { $0.sourceMessageId == source }.map(\.ownerId)
    owners.forEach { slots.removeValue(forKey: $0) }
    return !owners.isEmpty
  }

  func touch(sourceMessageId: String, nowMillis: Int64) -> Bool {
    let source = sourceMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !source.isEmpty, nowMillis > 0 else { return false }
    let owners = slots.values.filter { $0.sourceMessageId == source }.map(\.ownerId)
    for owner in owners where slots[owner] != nil {
      slots[owner]?.lastActivityAtMillis = nowMillis
    }
    return !owners.isEmpty
  }

  func activeCount(runtimeKey: String) -> Int {
    slots.values.filter { $0.runtimeKey == runtimeKey }.count
  }

  func activeCounts() -> [String: Int] {
    Dictionary(grouping: slots.values, by: \.runtimeKey).mapValues(\.count)
  }

  func prune(before cutoffMillis: Int64) -> Bool {
    let owners = slots.values.filter { $0.lastActivityAtMillis < cutoffMillis }.map(\.ownerId)
    owners.forEach { slots.removeValue(forKey: $0) }
    return !owners.isEmpty
  }

  func records() -> [AgentGlobalRunSlot] {
    Array(slots.values)
  }
}

protocol AgentGlobalRunSlotStoring: AnyObject {
  func acquire(registration: AgentRegistration, ownerId: String) -> Bool
  func bindSourceMessage(ownerId: String, sourceMessageId: String)
  func release(ownerId: String)
  func release(sourceMessageId: String)
  func touch(sourceMessageId: String, nowMillis: Int64)
  func activeCounts() -> [String: Int]
}

final class InMemoryAgentGlobalRunSlotStore: AgentGlobalRunSlotStoring {
  private let lock = NSRecursiveLock()
  private let ledger = AgentGlobalRunSlotLedger()
  private let nowMillis: () -> Int64

  init(nowMillis: @escaping () -> Int64 = { AgentControlPlaneClock.nowMillis() }) {
    self.nowMillis = nowMillis
  }

  func acquire(registration: AgentRegistration, ownerId: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return ledger.acquire(
      ownerId: ownerId,
      runtimeKey: AgentRuntimeIdentity.key(registration),
      maxParallelRuns: registration.maxParallelRuns,
      nowMillis: nowMillis()
    )
  }

  func bindSourceMessage(ownerId: String, sourceMessageId: String) {
    lock.lock()
    _ = ledger.bindSourceMessage(ownerId: ownerId, sourceMessageId: sourceMessageId)
    lock.unlock()
  }

  func release(ownerId: String) {
    lock.lock()
    _ = ledger.release(ownerId: ownerId)
    lock.unlock()
  }

  func release(sourceMessageId: String) {
    lock.lock()
    _ = ledger.release(sourceMessageId: sourceMessageId)
    lock.unlock()
  }

  func touch(sourceMessageId: String, nowMillis: Int64) {
    lock.lock()
    _ = ledger.touch(sourceMessageId: sourceMessageId, nowMillis: nowMillis)
    lock.unlock()
  }

  func activeCounts() -> [String: Int] {
    lock.lock()
    defer { lock.unlock() }
    return ledger.activeCounts()
  }
}

final class UserDefaultsAgentGlobalRunSlotStore: AgentGlobalRunSlotStoring {
  static let shared = UserDefaultsAgentGlobalRunSlotStore()

  private let defaults: UserDefaults
  private let key: String
  private let secrets: SignalASISecretStore
  private let lock = NSRecursiveLock()
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private var terminalSources: [String: Int64] = [:]
  private let nowMillis: () -> Int64

  init(
    defaults: UserDefaults = .standard,
    key: String = "signalasi_agent_global_run_slots_v1",
    secrets: SignalASISecretStore = KeychainSecretStore.shared,
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) {
    self.defaults = defaults
    self.key = key
    self.secrets = secrets
    self.nowMillis = nowMillis
  }

  static func destroy(
    defaults: UserDefaults = .standard,
    key: String = "signalasi_agent_global_run_slots_v1",
    secrets: SignalASISecretStore = KeychainSecretStore.shared
  ) {
    SignalASIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: key, secrets: secrets)
  }

  func acquire(registration: AgentRegistration, ownerId: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let ledger = loadPrunedLocked(now: nowMillis())
    let acquired = ledger.acquire(
      ownerId: ownerId,
      runtimeKey: AgentRuntimeIdentity.key(registration),
      maxParallelRuns: registration.maxParallelRuns,
      nowMillis: nowMillis()
    )
    if acquired { persistLocked(ledger) }
    return acquired
  }

  func bindSourceMessage(ownerId: String, sourceMessageId: String) {
    lock.lock()
    defer { lock.unlock() }
    let now = nowMillis()
    let ledger = loadPrunedLocked(now: now)
    pruneTerminalSourcesLocked(now: now)
    let source = sourceMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
    if terminalSources.removeValue(forKey: source) != nil {
      if ledger.release(ownerId: ownerId) { persistLocked(ledger) }
    } else if ledger.bindSourceMessage(ownerId: ownerId, sourceMessageId: source) {
      persistLocked(ledger)
    }
  }

  func release(ownerId: String) {
    lock.lock()
    defer { lock.unlock() }
    let ledger = loadPrunedLocked(now: nowMillis())
    if ledger.release(ownerId: ownerId) { persistLocked(ledger) }
  }

  func release(sourceMessageId: String) {
    let source = sourceMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !source.isEmpty else { return }
    lock.lock()
    defer { lock.unlock() }
    let now = nowMillis()
    pruneTerminalSourcesLocked(now: now)
    let ledger = loadPrunedLocked(now: now)
    if ledger.release(sourceMessageId: source) {
      persistLocked(ledger)
    } else {
      terminalSources[source] = now
    }
  }

  func touch(sourceMessageId: String, nowMillis: Int64) {
    lock.lock()
    defer { lock.unlock() }
    let ledger = loadPrunedLocked(now: nowMillis)
    if ledger.touch(sourceMessageId: sourceMessageId, nowMillis: nowMillis) {
      persistLocked(ledger)
    }
  }

  func activeCounts() -> [String: Int] {
    lock.lock()
    defer { lock.unlock() }
    return loadPrunedLocked(now: nowMillis()).activeCounts()
  }

  private func loadPrunedLocked(now: Int64) -> AgentGlobalRunSlotLedger {
    let records: [AgentGlobalRunSlot]
    if let data = SignalASIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets),
       let decoded = try? decoder.decode([AgentGlobalRunSlot].self, from: data) {
      records = decoded
    } else {
      records = []
    }
    let ledger = AgentGlobalRunSlotLedger(records: records)
    if ledger.prune(before: now - Self.slotLeaseMillis) { persistLocked(ledger) }
    return ledger
  }

  private func persistLocked(_ ledger: AgentGlobalRunSlotLedger) {
    guard let data = try? encoder.encode(ledger.records()) else { return }
    _ = SignalASIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: key, secrets: secrets)
  }

  private func pruneTerminalSourcesLocked(now: Int64) {
    terminalSources = terminalSources.filter { now - $0.value <= Self.terminalSourceTTLMillis }
  }

  static func ownerId(action: AgentAction, connectorId: String) -> String {
    ownerId(components: [
      action.parameters["_signalasi_conversation_id"] ?? "",
      action.parameters["_signalasi_turn_id"] ?? "",
      action.id,
      connectorId
    ])
  }

  static func ownerId(components: [String]) -> String {
    let source = components.joined(separator: "\u{001f}")
    return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private static let slotLeaseMillis: Int64 = 20 * 60 * 1_000
  private static let terminalSourceTTLMillis: Int64 = 60_000
}
