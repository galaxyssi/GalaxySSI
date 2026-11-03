import CoreFoundation
import CryptoKit
import Foundation

protocol AgentDesktopReplyRecoveryPersisting: AnyObject {
  func loadDesktopReplyRecoveryState() throws -> Data?
  func writeDesktopReplyRecoveryState(_ data: Data) -> Bool
}

struct AgentDesktopReplyDiscoveryProgress: Codable, Equatable {
  var cursor: GalaxySSIChatHistoryCursor? = nil
  var completed = false
}

private struct AgentDesktopReplyRecoveryState: Codable {
  var version = 2
  var records: [String: AgentDesktopReplyRecoveryRecord]
  var discovery = AgentDesktopReplyDiscoveryProgress()
  var retiredDuringDiscovery: Set<String>? = nil
}

enum AgentDesktopReplyDiscoveryPolicy {
  static func eligible(_ source: ChatMessage, identity: AgentTaskIdentity,
                       hasDeliveredReply: Bool, hasActiveTask: Bool) -> Bool {
    source.isMine && !source.isSystem && source.deliveryStatus != .failed &&
      identity.isComplete && identity.taskId == source.id.uuidString &&
      identity.conversationId == source.conversationId &&
      identity.turnId == source.turnId.ifBlank(source.id.uuidString) &&
      (!hasDeliveredReply || hasActiveTask)
  }
}

struct AgentManagedDesktopReplySource: Codable, Equatable {
  var ownerRunId: String
  var sourceMessageId: Int64
  var executionGeneration: Int64
}

struct AgentTeamDesktopReplySource: Codable, Equatable {
  var supervisorRunId: String
  var memberId: String
  var sourceMessageId: String
}

struct AgentDesktopReplyBinding: Codable, Equatable {
  var desktopId: String
  var displayContactId: String
  var sourceId: UUID
  var contactId: String
  var agentId: String
  var identity: AgentTaskIdentity
  var managedSource: AgentManagedDesktopReplySource? = nil
  var teamSource: AgentTeamDesktopReplySource? = nil
  var sourceIdentity: String { teamSource?.sourceMessageId ?? managedSource.map { String($0.sourceMessageId) } ?? sourceId.uuidString }

  var fields: [String: String] {
    ["client_route_id": identity.clientRouteId, "conversation_id": identity.conversationId,
     "task_id": identity.taskId, "turn_id": identity.turnId, "contact_id": contactId,
     "source_message_id": sourceIdentity, "agent_id": agentId]
  }

  var isValid: Bool {
    identity.isComplete && !(managedSource != nil && teamSource != nil) && (teamSource.map {
      !$0.supervisorRunId.isBlank && $0.supervisorRunId.count <= 200 && !$0.memberId.isBlank &&
        $0.memberId.count <= 200 && UUID(uuidString: $0.sourceMessageId) != nil
    } ?? true) && (managedSource.map {
      !$0.ownerRunId.isBlank && $0.ownerRunId.count <= 200 && $0.sourceMessageId > 0 &&
        AgentRemoteOutcomePolicy.validGeneration($0.executionGeneration)
    } ?? true) && ([desktopId, displayContactId] + Array(fields.values))
      .allSatisfy { !$0.isBlank && $0.count <= 200 }
  }

  var key: String {
    var values = [desktopId, displayContactId] + fields.keys.sorted().map { fields[$0]! }
    if let managedSource { values += [managedSource.ownerRunId, String(managedSource.executionGeneration)] }
    if let teamSource { values += ["team-observer", teamSource.supervisorRunId, teamSource.memberId] }
    let data = (try? JSONEncoder().encode(values)) ?? Data()
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  func matches(_ payload: [String: Any]) -> Bool {
    fields.allSatisfy { field in
      if field.key == "source_message_id", let managedSource,
         let number = payload[field.key] as? NSNumber {
        return CFGetTypeID(number) != CFBooleanGetTypeID() && number.doubleValue.isFinite &&
          number.int64Value == managedSource.sourceMessageId && number.int64Value <= 9_007_199_254_740_991 &&
          Double(number.int64Value) == number.doubleValue
      }
      return payload[field.key] as? String == field.value
    }
  }

  static func managed(record: AgentManagedResponseRecord, desktopId: String, agentId: String,
                      identity: AgentTaskIdentity) -> AgentDesktopReplyBinding? {
    guard record.conversationId == identity.conversationId, record.turnId == identity.turnId,
          record.taskId == identity.taskId else { return nil }
    // Numeric managed sources have no visible outgoing UUID. This key is local only, never sent on the wire.
    let bytes = Array(SHA256.hash(data: Data(("managed:" + record.ownerRunId).utf8)).prefix(16))
    let localKey = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    let binding = AgentDesktopReplyBinding(desktopId: desktopId, displayContactId: "managed",
      sourceId: localKey, contactId: record.contactId, agentId: agentId, identity: identity,
      managedSource: AgentManagedDesktopReplySource(ownerRunId: record.ownerRunId,
        sourceMessageId: record.sourceMessageId, executionGeneration: record.executionGeneration))
    return binding.isValid ? binding : nil
  }

  static func teamObserver(owner: AgentTeamReplyOwner, desktopId: String, agentId: String,
                           identity: AgentTaskIdentity) -> AgentDesktopReplyBinding? {
    guard owner.deliveryMode == .observe, let source = UUID(uuidString: owner.sourceMessageId),
          identity.conversationId == owner.conversationId, identity.turnId == owner.turnId,
          identity.taskId == owner.sourceMessageId else { return nil }
    let binding = AgentDesktopReplyBinding(desktopId: desktopId, displayContactId: "team-observer",
      sourceId: source, contactId: owner.contactId, agentId: agentId, identity: identity,
      teamSource: AgentTeamDesktopReplySource(supervisorRunId: owner.supervisorRunId,
        memberId: owner.memberId, sourceMessageId: owner.sourceMessageId))
    return binding.isValid ? binding : nil
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
  private var retiredDuringDiscovery: Set<String> = []
  private(set) var discoveryProgress = AgentDesktopReplyDiscoveryProgress()

  init(defaults: UserDefaults, secrets: GalaxySSISecretStore, journal: AgentDesktopReplyRecoveryPersisting) {
    self.journal = journal
    do {
      if let data = try journal.loadDesktopReplyRecoveryState() {
        let decoded = try Self.decode(data)
        records = decoded.records
        discoveryProgress = decoded.discovery
        retiredDuringDiscovery = decoded.retiredDuringDiscovery ?? []
        // SQLite is authoritative after migration, including when the last pending request was retired.
        GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: Self.storageKey, secrets: secrets)
      } else if let legacy = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: Self.storageKey, secrets: secrets) {
        let decoded = try Self.decode(legacy)
        guard journal.writeDesktopReplyRecoveryState(legacy) else { healthy = false; return }
        records = decoded.records
        discoveryProgress = decoded.discovery
        retiredDuringDiscovery = decoded.retiredDuringDiscovery ?? []
        GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: Self.storageKey, secrets: secrets)
      } else if defaults.data(forKey: Self.storageKey + ".encrypted.v1") != nil { healthy = false }
    } catch { healthy = false }
  }

  var pending: [AgentDesktopReplyRecoveryRecord] {
    records.values.sorted { $0.lastProbeAt == $1.lastProbeAt ? $0.binding.key < $1.binding.key : $0.lastProbeAt < $1.lastProbeAt }
  }

  @discardableResult
  func advanceDiscovery(expected: AgentDesktopReplyDiscoveryProgress,
                        nextCursor: GalaxySSIChatHistoryCursor?, hasMore: Bool) -> Bool {
    guard discoveryProgress == expected, !expected.completed, !hasMore || nextCursor != nil else { return false }
    return save(records, discovery: AgentDesktopReplyDiscoveryProgress(cursor: nextCursor, completed: !hasMore))
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
    if let managed = record.binding.managedSource,
       Self.integer(payload["execution_generation"], minimum: 1) != managed.executionGeneration { return false }
    if record.generation == 0 { return true }
    guard let generation = Self.integer(payload["execution_generation"], minimum: 1),
          let sequence = Self.integer(payload["status_sequence"], minimum: 0) else { return false }
    return generation > record.generation || (generation == record.generation && sequence >= record.sequence)
  }

  @discardableResult
  func track(_ binding: AgentDesktopReplyBinding, now: Int64) -> Bool {
    guard healthy, binding.isValid, now > 0 else { return false }
    if records[binding.key] != nil || retiredDuringDiscovery.contains(binding.key) { return true }
    var next = records
    next[binding.key] = AgentDesktopReplyRecoveryRecord(binding: binding, createdAt: now)
    return save(next)
  }

  @discardableResult
  func retire(_ binding: AgentDesktopReplyBinding) -> Bool {
    var next = records
    next.removeValue(forKey: binding.key)
    let retired = discoveryProgress.completed ? retiredDuringDiscovery : retiredDuringDiscovery.union([binding.key])
    guard save(next, retired: retired) else { return false }
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
          query.binding.managedSource == nil || query.binding.managedSource?.executionGeneration == generation,
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

  private func save(_ next: [String: AgentDesktopReplyRecoveryRecord],
                    discovery: AgentDesktopReplyDiscoveryProgress? = nil, retired: Set<String>? = nil) -> Bool {
    let progress = discovery ?? discoveryProgress
    let retiredKeys = progress.completed ? [] : (retired ?? retiredDuringDiscovery)
    let state = AgentDesktopReplyRecoveryState(records: next, discovery: progress, retiredDuringDiscovery: retiredKeys)
    guard healthy, let data = try? JSONEncoder().encode(state),
          journal.writeDesktopReplyRecoveryState(data) else { return false }
    records = next
    discoveryProgress = state.discovery
    retiredDuringDiscovery = retiredKeys
    return true
  }

  private static func decode(_ data: Data) throws -> AgentDesktopReplyRecoveryState {
    let decoded: AgentDesktopReplyRecoveryState
    if let current = try? JSONDecoder().decode(AgentDesktopReplyRecoveryState.self, from: data) {
      decoded = current
    } else {
      decoded = AgentDesktopReplyRecoveryState(records:
        try JSONDecoder().decode([String: AgentDesktopReplyRecoveryRecord].self, from: data))
    }
    guard decoded.version == 2, decoded.records.allSatisfy({ $0.key == $0.value.binding.key && $0.value.binding.isValid &&
      $0.value.createdAt > 0 && ($0.value.resultManifest?.isValid ?? true) }) else {
      throw GalaxySSIError.invalidPayload("Invalid Desktop recovery journal")
    }
    return decoded
  }
}
