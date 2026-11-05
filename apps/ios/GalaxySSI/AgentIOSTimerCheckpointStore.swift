import Foundation

struct AgentIOSTimerCheckpoint: Codable, Equatable {
  enum State: String, Codable, Equatable {
    case scheduling, scheduled, cancelled, failed
  }

  let id: UUID
  let sourceTurnId: String
  let durationSeconds: Int
  let deadlineMillis: Int64
  var state: State

  var notificationId: String { "galaxyssi.timer.\(id.uuidString)" }

  func evidence(now: Int64) -> [String: String] {
    let remaining = max(0, deadlineMillis - now)
    let status = state == .scheduled ? (remaining > 0 ? "running" : "elapsed") : state.rawValue
    return [
      "schedule": "timer", "operation_id": id.uuidString, "timer_state": status,
      "source_turn_id": sourceTurnId, "deadline_ms": String(deadlineMillis),
      "notification_id": notificationId,
      "remaining_seconds": String(state == .scheduled ? (remaining + 999) / 1_000 : 0),
      "completion_verified": state == .scheduled ? "true" : "false"
    ]
  }
}

final class AgentIOSTimerCheckpointStore {
  enum Reservation {
    case new(AgentIOSTimerCheckpoint)
    case existing(AgentIOSTimerCheckpoint)
    case unavailable
  }

  static let shared = AgentIOSTimerCheckpointStore()
  private static let lock = NSLock()
  private static let key = "galaxyssi.ios.timer-checkpoints.v1"
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore

  init(defaults: UserDefaults = .standard, secrets: GalaxySSISecretStore = KeychainSecretStore.shared) {
    self.defaults = defaults
    self.secrets = secrets
  }

  func current(conversationId: String) -> AgentIOSTimerCheckpoint? {
    locked { load()?[key(conversationId)] }
  }

  func reserve(conversationId: String, turnId: String, duration: Int, now: Int64) -> Reservation {
    guard !conversationId.isBlank, !turnId.isBlank, conversationId.count <= 200, turnId.count <= 200,
          (1...604_800).contains(duration), now > 0, now < Int64.max - 604_800_000 else { return .unavailable }
    return locked {
      guard var records = load() else { return .unavailable }
      let scope = key(conversationId)
      if let existing = records[scope], existing.sourceTurnId == turnId ||
          (existing.deadlineMillis > now && [.scheduled, .scheduling].contains(existing.state)) {
        return .existing(existing)
      }
      if records[scope] == nil, records.count >= 512 {
        guard let expired = records.filter({ $0.value.deadlineMillis <= now || $0.value.state == .cancelled })
          .min(by: { $0.value.deadlineMillis < $1.value.deadlineMillis }) else { return .unavailable }
        records.removeValue(forKey: expired.key)
      }
      let record = AgentIOSTimerCheckpoint(id: UUID(), sourceTurnId: turnId, durationSeconds: duration,
        deadlineMillis: now + Int64(duration) * 1_000, state: .scheduling)
      records[scope] = record
      return save(records) ? .new(record) : .unavailable
    }
  }

  @discardableResult
  func update(conversationId: String, id: UUID, to state: AgentIOSTimerCheckpoint.State) -> Bool {
    locked {
      guard var records = load(), var record = records[key(conversationId)], record.id == id else { return false }
      if record.state == state { return true }
      guard record.state == .scheduling || (record.state == .scheduled && state == .cancelled) else { return false }
      record.state = state
      records[key(conversationId)] = record
      return save(records)
    }
  }

  private func key(_ conversationId: String) -> String { AgentModelLoopRecoveryIdentity.sha256(conversationId) }

  private func load() -> [String: AgentIOSTimerCheckpoint]? {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: Self.key, secrets: secrets) else {
      return GalaxySSIEncryptedUserDefaultsStore.storedKeys(defaults: defaults, prefix: Self.key).isEmpty ? [:] : nil
    }
    return try? JSONDecoder().decode([String: AgentIOSTimerCheckpoint].self, from: data)
  }

  private func save(_ records: [String: AgentIOSTimerCheckpoint]) -> Bool {
    guard let data = try? JSONEncoder().encode(records) else { return false }
    return GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: Self.key, secrets: secrets)
  }

  private func locked<T>(_ body: () -> T) -> T {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    return body()
  }
}
