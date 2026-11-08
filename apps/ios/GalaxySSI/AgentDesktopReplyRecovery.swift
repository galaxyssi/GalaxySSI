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
  var supersededCodexBindings: [AgentDesktopReplyBinding]? = nil
}

enum AgentDesktopReplyDiscoveryPolicy {
  static let localExecutionStarted = "local_execution_started"

  private static let nonDesktopStages: Set<String> = [
    "cloud_request", "cloud_reply", "cloud_error", "cloud_reply_received",
    "peer_send_started", "phone_contact_delivered", localExecutionStarted, "local_model_reply", "delivered_local_estimate"
  ]

  static func mayOwn(_ source: ChatMessage) -> Bool {
    source.isMine && !source.isSystem && source.deliveryStatus != .failed &&
      !source.deliveryTrace.contains { nonDesktopStages.contains($0.stage) }
  }

  static func mayRecover(conversationID: String, savedSessionExists: Bool, taskCancelled: Bool) -> Bool {
    !taskCancelled && (!conversationID.hasPrefix("ios-agent-") || savedSessionExists)
  }

  static func isDesktopEndpoint(_ contact: GalaxySSIContact) -> Bool {
    !contact.deleted && contact.type.caseInsensitiveCompare("agent") == .orderedSame &&
      contact.trustState == .verified && contact.deliveryMode.isGalaxySSILinkFamily &&
      !contact.desktopId.isBlank && !contact.connectorAgentId.isBlank
  }

  static func matchesSource(_ source: ChatMessage, identity: AgentTaskIdentity) -> Bool {
    mayOwn(source) && identity.isComplete && identity.taskId == source.id.uuidString &&
      identity.conversationId == source.conversationId &&
      identity.turnId == source.turnId.ifBlank(source.id.uuidString)
  }

  static func eligible(_ source: ChatMessage, identity: AgentTaskIdentity,
                       hasDeliveredReply: Bool, hasActiveTask: Bool) -> Bool {
    matchesSource(source, identity: identity) && (!hasDeliveredReply || hasActiveTask)
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
  var primary: Bool? = nil
}

enum AgentDesktopCollaborationPublicationWire {
  static let requestType = "collaboration_publish_request"
  static let responseType = "collaboration_publish_result"
  static let contract = "galaxyssi.collaboration-publish/1"

  static func accepts(phase: String, input: AgentMcpJSONObject) -> Bool {
    ["publish", "status", "receipt", "list", "validate_assessment"].contains(phase) && input["mode"] == .string(phase)
  }

  static func permits(phase: String, observer: Bool) -> Bool {
    observer || phase == "validate_assessment"
  }
}

struct AgentDesktopCollaborationResponseReplay {
  enum Lookup: Equatable {
    case missing, identityMismatch, response(AgentMcpJSONObject)
  }

  private struct Entry {
    var fingerprint: String
    var expiresAt: Int64
    var bytes: Int
    var result: AgentMcpJSONObject
  }

  private var entries: [String: Entry] = [:]
  private var activeByDesktop: [String: Int] = [:]
  private let maximumEntries = 64
  private let maximumBytes = 512 * 1_024

  mutating func begin(desktopId: String) -> Bool {
    let active = activeByDesktop[desktopId, default: 0]
    guard active < 4 else { return false }
    activeByDesktop[desktopId] = active + 1
    return true
  }

  mutating func end(desktopId: String) {
    let remaining = activeByDesktop[desktopId, default: 0] - 1
    activeByDesktop[desktopId] = remaining > 0 ? remaining : nil
  }

  mutating func lookup(key: String, fingerprint: String, now: Int64) -> Lookup {
    prune(now: now)
    guard let existing = entries[key] else { return .missing }
    return existing.fingerprint == fingerprint ? .response(existing.result) : .identityMismatch
  }

  mutating func remember(_ result: AgentMcpJSONObject, key: String, fingerprint: String,
                         expiresAt: Int64, now: Int64) {
    guard result["success"] == .bool(true), expiresAt > now, expiresAt - now <= 60_000 else { return }
    prune(now: now)
    guard entries[key] == nil else { return }
    let bytes = AgentMcpJSONCodec.stringify(result).utf8.count
    guard bytes <= maximumBytes else { return }
    var total = entries.values.reduce(bytes) { $0 + $1.bytes }
    while entries.count >= maximumEntries || total > maximumBytes {
      guard let oldest = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt }) else { return }
      total -= oldest.value.bytes
      entries.removeValue(forKey: oldest.key)
    }
    entries[key] = Entry(fingerprint: fingerprint, expiresAt: expiresAt, bytes: bytes, result: result)
  }

  private mutating func prune(now: Int64) {
    entries = entries.filter { $0.value.expiresAt > now }
  }
}

enum AgentDesktopCollaborationArchiveRecall {
  static let requestType = "collaboration_recall_request"
  static let responseType = "collaboration_recall_result"
  static let contract = "galaxyssi.collaboration-recall/2"

  static func recordId(memberId: String) -> String {
    AgentMcpJSONCodec.sha256(["kind": .string("ios_dependency_reply"), "member_id": .string(memberId)])
  }

  static func selector(_ input: AgentMcpJSONObject) -> (recordId: String, offset: Int64)? {
    let id = input.string("record_id")
    guard Set(input.keys).isSubset(of: ["mode", "record_id", "offset"]), input["mode"] == .string("archive"),
          id.utf8.count == 64, id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
          case .int(let offset) = input["offset"] ?? .int(0), offset >= 0 else { return nil }
    return (id, offset)
  }

  static func goalSelector(_ input: AgentMcpJSONObject, scope: AgentCollaborationToolEvidenceScope, generation: Int64)
    -> AgentMcpJSONObject? {
    guard Set(input.keys).isSubset(of: ["mode", "section", "cursor"]), input["mode"] == .string("goal_contract"),
          case .string(let section) = input["section"] ?? .string("goal"),
          AgentCollaborationInlineOriginals.recallSections.contains(section),
          case .string(let cursor) = input["cursor"] ?? .string("") else { return nil }
    var query: AgentMcpJSONObject = ["mode": .string("goal"), "section": .string(section)]
    if cursor.isEmpty { return query }
    let parts = cursor.split(separator: ".", omittingEmptySubsequences: false)
    guard cursor.utf8.count <= 160, parts.count == 3, let offset = Int64(parts[0]), offset > 0,
          String(offset) == parts[0], parts[1].utf8.count == 64,
          parts[1].utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
          cursor == goalCursor(scope: scope, generation: generation, section: section, hash: String(parts[1]), offset: offset)
    else { return nil }
    query["offset"] = .int(offset)
    query["sha256"] = .string(String(parts[1]))
    return query
  }

  static func goalCursor(scope: AgentCollaborationToolEvidenceScope, generation: Int64,
                         section: String, hash: String, offset: Int64) -> String {
    let binding = AgentMcpJSONCodec.sha256([
      "run": .string(scope.runId), "group": .string(scope.conversationId), "turn": .string(scope.turnId),
      "member": .string(scope.memberId), "source": .string(scope.sourceId), "section": .string(section),
      "sha256": .string(hash), "offset": .int(offset), "generation": .int(generation)
    ])
    return "\(offset).\(hash).\(binding)"
  }
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
  var attemptSourceId: UUID? = nil
  var sourceIdentity: String {
    teamSource?.sourceMessageId ?? managedSource.map { String($0.sourceMessageId) } ??
      attemptSourceId?.uuidString ?? sourceId.uuidString
  }

  var fields: [String: String] {
    ["client_route_id": identity.clientRouteId, "conversation_id": identity.conversationId,
     "task_id": identity.taskId, "turn_id": identity.turnId, "contact_id": contactId,
     "source_message_id": sourceIdentity, "agent_id": agentId]
  }

  var isValid: Bool {
    identity.isComplete && !(managedSource != nil && teamSource != nil) &&
      (attemptSourceId == nil || (managedSource == nil && teamSource == nil && attemptSourceId != sourceId)) &&
      (teamSource.map {
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
    if let teamSource {
      values += [teamSource.primary == true ? "team-primary" : "team-observer", teamSource.supervisorRunId, teamSource.memberId]
    }
    if attemptSourceId != nil { values += ["codex-replay", sourceId.uuidString] }
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

  static func teamPrimary(owner: AgentTeamReplyOwner, desktopId: String, agentId: String,
                          identity: AgentTaskIdentity, outgoing: ChatMessage) -> AgentDesktopReplyBinding? {
    guard owner.deliveryMode == .respond, UUID(uuidString: owner.sourceMessageId) != nil,
          outgoing.isMine, !outgoing.isSystem, outgoing.conversationId == owner.conversationId,
          outgoing.turnId.ifBlank(outgoing.id.uuidString) == owner.turnId,
          identity.conversationId == owner.conversationId, identity.turnId == owner.turnId,
          identity.taskId == owner.sourceMessageId else { return nil }
    let binding = AgentDesktopReplyBinding(desktopId: desktopId, displayContactId: outgoing.contactId,
      sourceId: outgoing.id, contactId: owner.contactId, agentId: agentId, identity: identity,
      teamSource: AgentTeamDesktopReplySource(supervisorRunId: owner.supervisorRunId,
        memberId: owner.memberId, sourceMessageId: owner.sourceMessageId, primary: true))
    return binding.isValid ? binding : nil
  }
}

struct AgentDesktopAcceptedReply: Codable, Equatable {
  let remoteMessageId: String
  let receipt: AgentResultReceipt
  let acceptedAt: Int64
  let contentSHA256: String

  func matches(_ binding: AgentDesktopReplyBinding, generation: Int64) -> Bool {
    !remoteMessageId.isBlank && remoteMessageId.utf8.count <= 512 && acceptedAt > 0 &&
      receipt.executionGeneration == generation && receipt.desktopId == binding.desktopId &&
      binding.matches(receipt.payload) &&
      AgentResultReceipt.fromPayload(receipt.payload, desktopId: binding.desktopId) == receipt &&
      contentSHA256.utf8.count == 64 && contentSHA256.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  static func digest(_ content: String) -> String {
    SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
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
  var codexProgress: AgentDesktopCodexProgress? = nil
  var codexReplay: AgentCodexReplaySeed? = nil
  var codexDispatchPending: Bool? = nil

  func isCodexSilent(now: Int64) -> Bool {
    terminalObservedAt == 0 && AgentCodexSilenceRecoveryPolicy.isSilent(
      status: status, since: codexProgress?.lastProgressAt ?? createdAt, now: now
    )
  }

  var acceptedReply: AgentDesktopAcceptedReply? = nil

  func accepts(status: String, generation: Int64, sequence: Int64) -> Bool {
    if let acceptedReply {
      return generation == acceptedReply.receipt.executionGeneration && status == "completed" &&
        sequence >= self.sequence
    }
    if generation != self.generation { return generation > self.generation }
    guard sequence >= self.sequence else { return false }
    if terminalObservedAt > 0 || sequence == self.sequence { return status == self.status }
    return true
  }

  func expiryReason(now: Int64) -> String? {
    guard acceptedReply == nil else { return nil }
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

struct AgentDesktopCodexProgress: Codable, Equatable {
  var generation: Int64
  var sequence: Int64
  var lastProgressAt: Int64
  var eventIds: [String]

  mutating func observe(_ updates: [AgentConnectorPublicProgress], now: Int64) {
    for event in updates.sorted(by: { ($0.generation, $0.sequence) < ($1.generation, $1.sequence) })
      where event.countsForCodexSilence {
      guard event.generation >= generation else { continue }
      if event.generation > generation {
        generation = event.generation
        sequence = -1
        eventIds = []
      }
      guard event.sequence >= sequence, !eventIds.contains(event.eventId) else { continue }
      sequence = event.sequence
      eventIds = Array((eventIds + [event.eventId]).suffix(128))
      lastProgressAt = max(lastProgressAt, now)
    }
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
  private var supersededCodexBindings: [AgentDesktopReplyBinding] = []
  private(set) var discoveryProgress = AgentDesktopReplyDiscoveryProgress()

  init(defaults: UserDefaults, secrets: GalaxySSISecretStore, journal: AgentDesktopReplyRecoveryPersisting) {
    self.journal = journal
    do {
      if let data = try journal.loadDesktopReplyRecoveryState() {
        let decoded = try Self.decode(data)
        records = decoded.records
        discoveryProgress = decoded.discovery
        retiredDuringDiscovery = decoded.retiredDuringDiscovery ?? []
        supersededCodexBindings = decoded.supersededCodexBindings ?? []
        // SQLite is authoritative after migration, including when the last pending request was retired.
        GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: Self.storageKey, secrets: secrets)
      } else if let legacy = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: Self.storageKey, secrets: secrets) {
        let decoded = try Self.decode(legacy)
        guard journal.writeDesktopReplyRecoveryState(legacy) else { healthy = false; return }
        records = decoded.records
        discoveryProgress = decoded.discovery
        retiredDuringDiscovery = decoded.retiredDuringDiscovery ?? []
        supersededCodexBindings = decoded.supersededCodexBindings ?? []
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

  func isSupersededCodexPayload(_ payload: [String: Any], desktopId: String) -> Bool {
    supersededCodexBindings.contains { $0.desktopId == desktopId && $0.matches(payload) }
  }

  func scheduleCodexReplay(from old: AgentDesktopReplyRecoveryRecord, to next: AgentDesktopReplyBinding,
                           replay: AgentCodexReplaySeed, now: Int64) -> Bool {
    guard now > 0, records[old.binding.key] == old, old.codexReplay != nil,
          next.isValid, next.sourceId == old.binding.sourceId,
          next.identity.conversationId == old.binding.identity.conversationId,
          next.identity.turnId == old.binding.identity.turnId,
          next.displayContactId == old.binding.displayContactId,
          next.desktopId == old.binding.desktopId,
          next.attemptSourceId != nil, next.sourceIdentity != old.binding.sourceIdentity,
          next.contactId == replay.budget.expectedTarget, records[next.key] == nil else { return false }
    var updated = records
    updated.removeValue(forKey: old.binding.key)
    updated[next.key] = AgentDesktopReplyRecoveryRecord(binding: next, createdAt: now,
      codexReplay: replay, codexDispatchPending: true)
    let superseded = Array((supersededCodexBindings + [old.binding]).suffix(512))
    guard save(updated, superseded: superseded) else { return false }
    queries = queries.filter { $0.value.binding != old.binding }
    return true
  }

  func markCodexReplayDispatched(_ binding: AgentDesktopReplyBinding) -> Bool {
    guard var record = records[binding.key] else { return true }
    guard record.codexDispatchPending == true else { return true }
    record.codexDispatchPending = false
    var updated = records
    updated[binding.key] = record
    return save(updated)
  }

  @discardableResult
  func observeCodexProgress(_ updates: [AgentConnectorPublicProgress], binding: AgentDesktopReplyBinding, now: Int64) -> Bool {
    guard var record = records[binding.key], record.terminalObservedAt == 0 else { return false }
    let eligible = updates.filter {
      $0.countsForCodexSilence && ($0.generation > record.generation ||
        ($0.generation == record.generation && $0.sequence >= max(0, record.sequence)))
    }
    guard !eligible.isEmpty else { return true }
    var progress = record.codexProgress ?? AgentDesktopCodexProgress(
      generation: record.generation, sequence: -1, lastProgressAt: record.createdAt, eventIds: [])
    progress.observe(eligible, now: now)
    guard progress != record.codexProgress else { return true }
    record.codexProgress = progress
    var next = records
    next[binding.key] = record
    return save(next)
  }

  @discardableResult
  func attachManifest(_ manifest: AgentDesktopResultManifest, to expected: AgentDesktopReplyRecoveryRecord) -> Bool {
    guard manifest.isValid, var current = records[expected.binding.key],
          current.generation == expected.generation, current.status == expected.status,
          current.acceptedReply.map({ $0.receipt.resultSHA256 == manifest.digest }) ?? true,
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
    let status = payload.string("task_status")
    if let accepted = record.acceptedReply {
      return status == "completed" && accepted.remoteMessageId == payload.string("message_id") &&
        accepted.receipt == AgentResultReceipt.fromPayload(payload, desktopId: desktopId)
    }
    return record.accepts(status: status, generation: generation, sequence: sequence)
  }

  func acceptCompletedReply(_ payload: [String: Any], binding: AgentDesktopReplyBinding, content: String,
                            now: Int64) -> AgentDesktopReplyRecoveryRecord? {
    guard binding.managedSource == nil, binding.teamSource == nil, binding.matches(payload),
          payload.string("type") == "text", payload.string("task_status") == "completed",
          var current = records[binding.key],
          let receipt = AgentResultReceipt.fromPayload(payload, desktopId: binding.desktopId),
          let generation = Self.integer(payload["execution_generation"], minimum: 1),
          let sequence = Self.integer(payload["status_sequence"], minimum: 0)
    else { return nil }
    let accepted = AgentDesktopAcceptedReply(remoteMessageId: payload.string("message_id"), receipt: receipt,
      acceptedAt: now, contentSHA256: AgentDesktopAcceptedReply.digest(content))
    guard accepted.matches(binding, generation: generation) else { return nil }
    if let prior = current.acceptedReply {
      return prior.receipt == receipt && prior.remoteMessageId == accepted.remoteMessageId &&
        prior.contentSHA256 == accepted.contentSHA256 ? current : nil
    }
    guard current.accepts(status: "completed", generation: generation, sequence: sequence) else { return nil }
    if current.generation != generation || current.resultManifest?.digest != receipt.resultSHA256 {
      current.resultManifest = nil
    }
    if current.generation != generation { current.terminalObservedAt = 0 }
    current.generation = generation
    current.sequence = sequence
    current.status = "completed"
    current.terminalObservedAt = current.terminalObservedAt > 0 ? current.terminalObservedAt : now
    current.acceptedReply = accepted
    var next = records
    next[binding.key] = current
    return save(next) ? current : nil
  }

  @discardableResult
  func track(_ binding: AgentDesktopReplyBinding, now: Int64, codexReplay: AgentCodexReplaySeed? = nil) -> Bool {
    guard healthy, binding.isValid, now > 0 else { return false }
    if records[binding.key] != nil || retiredDuringDiscovery.contains(binding.key) ||
       supersededCodexBindings.contains(binding) { return true }
    var next = records
    next[binding.key] = AgentDesktopReplyRecoveryRecord(binding: binding, createdAt: now, codexReplay: codexReplay)
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
          record.accepts(status: status, generation: generation, sequence: sequence) else { return nil }
    if generation > record.generation {
      record.terminalObservedAt = 0
      record.resultManifest = nil
      if record.generation > 0, record.codexProgress != nil {
        record.codexProgress = AgentDesktopCodexProgress(generation: generation, sequence: -1,
          lastProgressAt: now, eventIds: [])
      }
    }
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
                    discovery: AgentDesktopReplyDiscoveryProgress? = nil, retired: Set<String>? = nil,
                    superseded: [AgentDesktopReplyBinding]? = nil) -> Bool {
    let progress = discovery ?? discoveryProgress
    let retiredKeys = progress.completed ? [] : (retired ?? retiredDuringDiscovery)
    let tombstones = superseded ?? supersededCodexBindings
    let state = AgentDesktopReplyRecoveryState(records: next, discovery: progress, retiredDuringDiscovery: retiredKeys,
      supersededCodexBindings: tombstones.isEmpty ? nil : tombstones)
    guard healthy, let data = try? JSONEncoder().encode(state),
          journal.writeDesktopReplyRecoveryState(data) else { return false }
    records = next
    discoveryProgress = state.discovery
    retiredDuringDiscovery = retiredKeys
    supersededCodexBindings = tombstones
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
    guard decoded.version == 2, (decoded.supersededCodexBindings?.count ?? 0) <= 512,
      decoded.supersededCodexBindings?.allSatisfy(\.isValid) != false,
      decoded.records.allSatisfy({ entry in
      let record = entry.value
      return entry.key == record.binding.key && record.binding.isValid &&
      record.createdAt > 0 && (record.resultManifest?.isValid ?? true) &&
      (record.acceptedReply.map { accepted in
        record.status == "completed" && accepted.matches(record.binding, generation: record.generation)
      } ?? true) }) else {
      throw GalaxySSIError.invalidPayload("Invalid Desktop recovery journal")
    }
    return decoded
  }
}
