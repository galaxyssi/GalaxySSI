import CryptoKit
import Foundation

struct AgentRoutingUsageSummary: Equatable {
  var samples: Int
  var averageTotalTokens: Int64
  var reportedCostSamples: Int
  var averageReportedCostMicros: Int64?
}

struct AgentRoutingUsageSnapshot: Equatable {
  var resources: [String: AgentRoutingUsageSummary] = [:]
}

enum AgentRoutingUsageEligibility {
  static func allows(_ session: AgentConversation?) -> Bool {
    guard let session else { return false }
    return session.status == .active && !session.privateMode && !session.trackingPaused && session.mergedIntoConversationId.isBlank
  }
}

final class AgentRoutingUsageStore {
  private struct Entry: Codable, Equatable {
    var key: String
    var resourceId: String
    var conversationId: String
    var inputTokens: Int64
    var outputTokens: Int64
    var reportedCostMicros: Int64?
    var observedAtMillis: Int64

    var valid: Bool {
      key.count == 64 && key.allSatisfy { $0.isHexDigit } &&
        Self.validID(resourceId) && Self.validID(conversationId) &&
        inputTokens >= 0 && outputTokens >= 0 && inputTokens <= Int64.max - outputTokens &&
        (reportedCostMicros.map { $0 >= 0 } ?? true) && observedAtMillis > 0
    }

    static func validID(_ value: String) -> Bool { !value.isBlank && value.utf8.count <= 512 }
  }
  private struct State: Codable {
    var version = 1
    var entries: [Entry] = []
  }

  static let maximumEntries = 1_000
  static let retentionMillis: Int64 = 30 * 24 * 60 * 60 * 1_000
  private static let lock = NSRecursiveLock()
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let owner: String
  var storageKey: String { "galaxyssi.ios.routing-usage.v1." + Self.digest(Data(owner.utf8)) }

  init(owner: String, defaults: UserDefaults = .standard, secrets: GalaxySSISecretStore = KeychainSecretStore.shared) {
    self.owner = owner
    self.defaults = defaults
    self.secrets = secrets
  }

  static func validUsage(_ usage: ModelUsage) -> Bool {
    usage.inputTokens >= 0 && usage.outputTokens >= 0 && usage.cachedInputTokens >= 0 &&
      usage.cachedInputTokens <= usage.inputTokens && usage.inputTokens <= Int64.max - usage.outputTokens
  }

  @discardableResult
  func record(resourceId: String, conversationId: String, observationId: String, usage: ModelUsage,
              reportedCostMicros: Int64? = nil, nowMillis: Int64) -> Bool {
    guard Entry.validID(owner), !observationId.isBlank, observationId.utf8.count <= 2_048,
          Self.validUsage(usage),
          let identity = try? JSONEncoder().encode([resourceId, conversationId, observationId]) else { return false }
    let entry = Entry(key: Self.digest(identity), resourceId: resourceId, conversationId: conversationId,
      inputTokens: usage.inputTokens, outputTokens: usage.outputTokens,
      reportedCostMicros: reportedCostMicros, observedAtMillis: nowMillis)
    guard entry.valid, entry.inputTokens > 0 || entry.outputTokens > 0 || reportedCostMicros != nil else { return false }
    Self.lock.lock(); defer { Self.lock.unlock() }
    guard var state = load() else { return false }
    if let prior = state.entries.first(where: { $0.key == entry.key }) {
      return prior.resourceId == resourceId && prior.conversationId == conversationId &&
        prior.inputTokens == entry.inputTokens && prior.outputTokens == entry.outputTokens &&
        prior.reportedCostMicros == reportedCostMicros
    }
    state.entries = Array((retained(state.entries, nowMillis: nowMillis) + [entry]).sorted {
      $0.observedAtMillis == $1.observedAtMillis ? $0.key < $1.key : $0.observedAtMillis > $1.observedAtMillis
    }.prefix(Self.maximumEntries))
    guard let data = try? JSONEncoder().encode(state), data.count <= 1_100_000 else { return false }
    return GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: storageKey, secrets: secrets)
  }

  func snapshot(eligibleConversationIds: Set<String>, nowMillis: Int64) -> AgentRoutingUsageSnapshot {
    guard Entry.validID(owner), nowMillis > 0, !eligibleConversationIds.isEmpty else { return .init() }
    Self.lock.lock(); defer { Self.lock.unlock() }
    guard let state = load() else { return .init() }
    let entries = retained(state.entries, nowMillis: nowMillis).filter { eligibleConversationIds.contains($0.conversationId) }
    let grouped = Dictionary(grouping: entries, by: \.resourceId)
    return AgentRoutingUsageSnapshot(resources: grouped.mapValues { entries in
      let costs = entries.compactMap(\.reportedCostMicros)
      return AgentRoutingUsageSummary(samples: entries.count,
        averageTotalTokens: Self.average(entries.map { $0.inputTokens + $0.outputTokens }),
        reportedCostSamples: costs.count, averageReportedCostMicros: costs.isEmpty ? nil : Self.average(costs))
    })
  }

  private func load() -> State? {
    guard GalaxySSIEncryptedUserDefaultsStore.contains(defaults: defaults, key: storageKey) else { return State() }
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: storageKey, secrets: secrets),
          data.count <= 1_100_000, let state = try? JSONDecoder().decode(State.self, from: data), state.version == 1,
          state.entries.count <= Self.maximumEntries, state.entries.allSatisfy(\.valid),
          Set(state.entries.map(\.key)).count == state.entries.count else { return nil }
    return state
  }

  private func retained(_ entries: [Entry], nowMillis: Int64) -> [Entry] {
    entries.filter { $0.observedAtMillis <= nowMillis && nowMillis - $0.observedAtMillis <= Self.retentionMillis }
  }

  private static func average(_ values: [Int64]) -> Int64 {
    guard !values.isEmpty else { return 0 }
    let count = Int64(values.count)
    let quotients = values.reduce(Int64(0)) { $0 + $1 / count }
    let remainders = values.reduce(Int64(0)) { $0 + $1 % count }
    return quotients + remainders / count
  }

  private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
