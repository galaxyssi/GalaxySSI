import CoreFoundation
import CryptoKit
import Foundation

protocol AgentDesktopReplyRecoveryPersisting: AnyObject {
  func loadDesktopReplyRecoveryState() throws -> Data?
  func writeDesktopReplyRecoveryState(_ data: Data) -> Bool
}

struct AgentDesktopReplyBinding: Codable, Equatable {
  var desktopId: String
  var displayContactId: String
  var sourceId: UUID
  var contactId: String
  var agentId: String
  var identity: AgentTaskIdentity

  var fields: [String: String] {
    ["client_route_id": identity.clientRouteId, "conversation_id": identity.conversationId,
     "task_id": identity.taskId, "turn_id": identity.turnId, "contact_id": contactId,
     "source_message_id": sourceId.uuidString, "agent_id": agentId]
  }

  var isValid: Bool {
    identity.isComplete && ([desktopId, displayContactId] + Array(fields.values))
      .allSatisfy { !$0.isBlank && $0.count <= 200 }
  }

  var key: String {
    let values = [desktopId, displayContactId] + fields.keys.sorted().map { fields[$0]! }
    let data = (try? JSONEncoder().encode(values)) ?? Data()
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  func matches(_ payload: [String: Any]) -> Bool {
    fields.allSatisfy { payload[$0.key] as? String == $0.value }
  }
}

struct AgentDesktopReplyRecoveryRecord: Codable, Equatable {
  var binding: AgentDesktopReplyBinding
  var createdAt: Int64
  var lastProbeAt: Int64 = 0
  var lastResponseAt: Int64 = 0
  var misses = 0
  var terminalObservedAt: Int64 = 0
  var generation: Int64 = 0
  var sequence: Int64 = -1
  var status = ""
  var resultManifest: AgentDesktopResultManifest? = nil

  func expiryReason(now: Int64) -> String? {
    if terminalObservedAt > 0 {
      return now >= terminalObservedAt && now - terminalObservedAt >= 15 * 60_000
        ? "desktop_result_unavailable" : nil
    }
    let anchor = max(createdAt, lastResponseAt)
    guard anchor > 0, now >= anchor, now - anchor >= 5 * 60_000, misses >= 3,
          lastProbeAt > 0, now >= lastProbeAt, now - lastProbeAt <= 120_000 else { return nil }
    return "desktop_status_unavailable"
  }
}

// Owned by the main-thread MessageCoordinator. This journal is independent of task checkpoints.
@MainActor
final class AgentDesktopReplyRecovery {
  static let storageKey = "galaxyssi.desktop.pending-replies.v1"
  static let terminalStatuses: Set<String> = ["completed", "failed", "timed_out", "cancelled"]
  private static let statuses: Set<String> = terminalStatuses.union([
    "accepted", "queued", "starting", "running", "recovering", "waiting_input",
    "waiting_approval", "pausing", "paused", "takeover", "interrupted"
  ])
  private struct Query {
    var binding: AgentDesktopReplyBinding
    var startedAt: Int64
  }
  private let journal: AgentDesktopReplyRecoveryPersisting
  private var records: [String: AgentDesktopReplyRecoveryRecord] = [:]
  private var queries: [String: Query] = [:]
  private var healthy = true

  init(defaults: UserDefaults, secrets: GalaxySSISecretStore, journal: AgentDesktopReplyRecoveryPersisting) {
    self.journal = journal
    do {
      if let data = try journal.loadDesktopReplyRecoveryState() {
        records = try Self.decode(data)
        // SQLite is authoritative after migration, including when the last pending request was retired.
        GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: Self.storageKey, secrets: secrets)
      } else if let legacy = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: Self.storageKey, secrets: secrets) {
        let decoded = try Self.decode(legacy)
        guard journal.writeDesktopReplyRecoveryState(legacy) else { healthy = false; return }
        records = decoded
        GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: Self.storageKey, secrets: secrets)
      } else if defaults.data(forKey: Self.storageKey + ".encrypted.v1") != nil { healthy = false }
    } catch { healthy = false }
  }

  var pending: [AgentDesktopReplyRecoveryRecord] {
    records.values.sorted { $0.lastProbeAt == $1.lastProbeAt ? $0.binding.key < $1.binding.key : $0.lastProbeAt < $1.lastProbeAt }
  }

  func expectedBinding(_ response: [String: Any]) -> AgentDesktopReplyBinding? {
    queries[response.string("request_id")]?.binding
  }

  func record(for binding: AgentDesktopReplyBinding) -> AgentDesktopReplyRecoveryRecord? { records[binding.key] }

  @discardableResult
  func attachManifest(_ manifest: AgentDesktopResultManifest, to expected: AgentDesktopReplyRecoveryRecord) -> Bool {
    guard manifest.isValid, var current = records[expected.binding.key],
          current.generation == expected.generation,
          current.resultManifest == nil || current.resultManifest == manifest else { return false }
    current.resultManifest = manifest
    var next = records
    next[expected.binding.key] = current
    return save(next)
  }

  func acceptsFinal(_ payload: [String: Any], desktopId: String) -> Bool {
    guard let record = records.values.first(where: { $0.binding.desktopId == desktopId && $0.binding.matches(payload) }) else { return true }
    if record.generation == 0 { return true }
    guard let generation = Self.integer(payload["execution_generation"], minimum: 1),
          let sequence = Self.integer(payload["status_sequence"], minimum: 0) else { return false }
    return generation > record.generation || (generation == record.generation && sequence >= record.sequence)
  }

  @discardableResult
  func track(_ binding: AgentDesktopReplyBinding, now: Int64) -> Bool {
    guard healthy, binding.isValid, now > 0 else { return false }
    if records[binding.key] != nil { return true }
    var next = records
    next[binding.key] = AgentDesktopReplyRecoveryRecord(binding: binding, createdAt: now)
    return save(next)
  }

  @discardableResult
  func retire(_ binding: AgentDesktopReplyBinding) -> Bool {
    var next = records
    next.removeValue(forKey: binding.key)
    guard save(next) else { return false }
    queries = queries.filter { $0.value.binding != binding }
    return true
  }

  func request(_ binding: AgentDesktopReplyBinding, online: Bool, now: Int64) -> [String: Any]? {
    guard var record = records[binding.key], now > 0,
          record.lastProbeAt == 0 || (now >= record.lastProbeAt && now - record.lastProbeAt >= 30_000) else { return nil }
    queries = queries.filter { now < $0.value.startedAt || now - $0.value.startedAt <= 120_000 }
    if online && queries.count >= 128 { return nil }
    record.lastProbeAt = now
    record.misses = min(record.misses, 1_000_000) + 1
    var next = records
    next[binding.key] = record
    guard save(next), online else { return nil }
    let nonce = UUID().uuidString
    queries[nonce] = Query(binding: binding, startedAt: now)
    return ["type": "agent_task_recovery_request", "request_id": nonce,
      "desktop_id": binding.desktopId, "client_route_id": binding.identity.clientRouteId,
      "items": [binding.fields], "include_result_page": true]
  }

  func receive(_ payload: [String: Any], authenticatedDesktopId: String, now: Int64) -> AgentDesktopReplyRecoveryRecord? {
    guard payload.string("type") == "agent_task_recovery_result",
          let query = queries[payload.string("request_id")],
          now >= query.startedAt, now - query.startedAt <= 120_000,
          authenticatedDesktopId == query.binding.desktopId,
          payload.string("client_route_id") == query.binding.identity.clientRouteId,
          let items = payload["items"] as? [[String: Any]], items.count == 1,
          query.binding.matches(items[0]), var record = records[query.binding.key],
          let status = items[0]["status"] as? String, Self.statuses.contains(status),
          let runId = items[0]["remote_run_id"] as? String, !runId.isBlank, runId.count <= 200,
          let generation = Self.integer(items[0]["execution_generation"], minimum: 1),
          let sequence = Self.integer(items[0]["status_sequence"], minimum: 0),
          generation > record.generation || (generation == record.generation && sequence >= record.sequence) else { return nil }
    if generation == record.generation, record.terminalObservedAt > 0, !Self.terminalStatuses.contains(status) { return nil }
    if generation > record.generation { record.terminalObservedAt = 0; record.resultManifest = nil }
    record.generation = generation
    record.sequence = sequence
    record.status = status
    record.lastResponseAt = now
    record.misses = 0
    if Self.terminalStatuses.contains(status), record.terminalObservedAt == 0 { record.terminalObservedAt = now }
    var next = records
    next[query.binding.key] = record
    guard save(next) else { return nil }
    queries.removeValue(forKey: payload.string("request_id"))
    return record
  }

  static func integer(_ value: Any?, minimum: Int64) -> Int64? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite, number.int64Value >= minimum,
          number.int64Value <= 9_007_199_254_740_991,
          Double(number.int64Value) == number.doubleValue else { return nil }
    return number.int64Value
  }

  private func save(_ next: [String: AgentDesktopReplyRecoveryRecord]) -> Bool {
    guard healthy, let data = try? JSONEncoder().encode(next),
          journal.writeDesktopReplyRecoveryState(data) else { return false }
    records = next
    return true
  }

  private static func decode(_ data: Data) throws -> [String: AgentDesktopReplyRecoveryRecord] {
    let decoded = try JSONDecoder().decode([String: AgentDesktopReplyRecoveryRecord].self, from: data)
    guard decoded.allSatisfy({ $0.key == $0.value.binding.key && $0.value.binding.isValid &&
      $0.value.createdAt > 0 && ($0.value.resultManifest?.isValid ?? true) }) else {
      throw GalaxySSIError.invalidPayload("Invalid Desktop recovery journal")
    }
    return decoded
  }
}
