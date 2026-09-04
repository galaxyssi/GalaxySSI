import CryptoKit
import Foundation

struct AgentMemoryUsageRecord: Codable, Equatable, Identifiable {
  var id: String
  var memoryIds: [String]
  var conversationId: String
  var turnId: String
  var querySHA256: String
  var runId: String
  var answerPreview: String
  var selectedAtMillis: Int64
  var answeredAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case id
    case memoryIds = "memory_ids"
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case querySHA256 = "query_sha256"
    case runId = "run_id"
    case answerPreview = "answer_preview"
    case selectedAtMillis = "selected_at_millis"
    case answeredAtMillis = "answered_at_millis"
  }

  init(
    id: String = UUID().uuidString,
    memoryIds: [String],
    conversationId: String,
    turnId: String = "",
    querySHA256: String,
    runId: String = "",
    answerPreview: String = "",
    selectedAtMillis: Int64,
    answeredAtMillis: Int64 = 0
  ) {
    self.id = id
    self.memoryIds = Array(Set(memoryIds.map(Self.clean).filter { !$0.isEmpty })).sorted()
    self.conversationId = Self.clean(conversationId)
    self.turnId = Self.clean(turnId)
    self.querySHA256 = Self.clean(querySHA256)
    self.runId = Self.clean(runId)
    self.answerPreview = String(answerPreview.trimmingCharacters(in: .whitespacesAndNewlines).prefix(320))
    self.selectedAtMillis = max(selectedAtMillis, 0)
    self.answeredAtMillis = max(answeredAtMillis, 0)
  }

  private static func clean(_ value: String) -> String {
    String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
  }
}

struct AgentMemoryTrustProfile: Codable, Equatable, Identifiable {
  var id: String { memoryId }
  var memoryId: String
  var whyRemembered: String
  var source: String
  var currentState: String
  var lastVerifiedAtMillis: Int64
  var privateMemory: Bool
  var usages: [AgentMemoryUsageRecord]

  enum CodingKeys: String, CodingKey {
    case memoryId = "memory_id"
    case whyRemembered = "why_remembered"
    case source
    case currentState = "current_state"
    case lastVerifiedAtMillis = "last_verified_at_millis"
    case privateMemory = "private_memory"
    case usages
  }
}

final class AgentMemoryTrustStore {
  private struct State: Codable {
    var usages: [AgentMemoryUsageRecord] = []
  }

  static let defaultKey = "galaxyssi-ios-agent-memory-trust-v1"
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let key: String
  private let nowMillis: () -> Int64
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    key: String = AgentMemoryTrustStore.defaultKey,
    nowMillis: @escaping () -> Int64 = AgentMemoryClock.nowMillis
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.key = key
    self.nowMillis = nowMillis
  }

  @discardableResult
  func recordSelection(
    memories: [AgentMemoryItem],
    conversationId: String,
    turnId: String = "",
    query: String,
    runId: String = ""
  ) -> AgentMemoryUsageRecord? {
    let memoryIds = Array(memories.filter { !$0.privateMemory }.map(\.id).prefix(32))
    let conversationId = String(conversationId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
    let turnId = String(turnId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
    guard !memoryIds.isEmpty, !conversationId.isEmpty else { return nil }
    let selectedAt = nowMillis()
    let digest = Self.digest(String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8_000)))
    return locked {
      var state = load()
      if let existing = state.usages.last(where: {
        $0.conversationId == conversationId &&
          $0.turnId == turnId &&
          $0.querySHA256 == digest &&
          $0.memoryIds == Array(Set(memoryIds)).sorted() &&
          selectedAt - $0.selectedAtMillis <= Self.selectionDedupeMillis
      }) {
        return existing
      }
      let usage = AgentMemoryUsageRecord(
        memoryIds: memoryIds,
        conversationId: conversationId,
        turnId: turnId,
        querySHA256: digest,
        runId: runId,
        selectedAtMillis: selectedAt
      )
      state.usages.append(usage)
      state.usages = Array(state.usages.suffix(Self.maximumUsageRecords))
      save(state)
      return usage
    }
  }

  @discardableResult
  func attachAnswer(
    conversationId: String,
    runId: String = "",
    answer: String,
    answeredAtMillis: Int64? = nil
  ) -> Int {
    let conversationId = String(conversationId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
    let runId = String(runId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
    let answeredAt = answeredAtMillis ?? nowMillis()
    guard !conversationId.isEmpty, !runId.isEmpty else { return 0 }
    return locked {
      var state = load()
      let indices = state.usages.indices.filter { index in
        let usage = state.usages[index]
        return usage.conversationId == conversationId && (usage.runId.isEmpty || usage.runId == runId) &&
          answeredAt - usage.selectedAtMillis >= 0 &&
          answeredAt - usage.selectedAtMillis <= Self.answerWindowMillis
      }
      guard !indices.isEmpty else { return 0 }
      for index in indices {
        state.usages[index].answerPreview = String(answer
          .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .prefix(Self.maximumAnswerPreviewCharacters))
        state.usages[index].answeredAtMillis = max(answeredAt, state.usages[index].selectedAtMillis)
        if state.usages[index].runId.isEmpty { state.usages[index].runId = runId }
      }
      save(state)
      return indices.count
    }
  }

  func usages(for memoryId: String, limit: Int = 50) -> [AgentMemoryUsageRecord] {
    let memoryId = memoryId.trimmingCharacters(in: .whitespacesAndNewlines)
    return locked {
      Array(load().usages.filter { $0.memoryIds.contains(memoryId) }
        .sorted { $0.selectedAtMillis > $1.selectedAtMillis }
        .prefix(min(max(limit, 1), 200)))
    }
  }

  func recent(limit: Int = 100) -> [AgentMemoryUsageRecord] {
    locked {
      Array(load().usages.sorted { $0.selectedAtMillis > $1.selectedAtMillis }
        .prefix(min(max(limit, 1), 500)))
    }
  }

  func profile(memory: AgentMemoryItem) -> AgentMemoryTrustProfile {
    let records = usages(for: memory.id)
    return AgentMemoryTrustProfile(
      memoryId: memory.id,
      whyRemembered: memory.whyRemembered.isEmpty ? Self.whyFromSource(memory.source) : memory.whyRemembered,
      source: memory.source,
      currentState: Self.currentState(memory.status),
      lastVerifiedAtMillis: max(memory.lastConfirmedAtMillis, memory.timestampMillis),
      privateMemory: memory.privateMemory,
      usages: records
    )
  }

  func clear() {
    locked {
      GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: key, secrets: secrets)
    }
  }

  static func destroyPersistentStore(
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    key: String = AgentMemoryTrustStore.defaultKey
  ) {
    GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: key, secrets: secrets)
  }

  static func whyFromSource(_ source: String) -> String {
    switch source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "explicit_core_memory": return "The user explicitly stated this durable fact."
    case "automatic_learning": return "Repeated successful Agent runs supported this memory."
    case "automatic_failure_learning": return "Repeated failures established a condition that should not be retried unchanged."
    case "memory_edit": return "The user corrected an earlier memory."
    case "memory_conflict_selection", "memory_conflict_merge": return "The user resolved conflicting memory candidates."
    default: return "Saved from an Agent interaction."
    }
  }

  private static func currentState(_ status: AgentMemoryStatus) -> String {
    switch status {
    case .active: return "current"
    case .conflicted: return "conflicted"
    case .superseded: return "historical"
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

  private static func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private static let selectionDedupeMillis: Int64 = 60_000
  private static let answerWindowMillis: Int64 = 30 * 60_000
  private static let maximumAnswerPreviewCharacters = 320
  private static let maximumUsageRecords = 2_000
}
