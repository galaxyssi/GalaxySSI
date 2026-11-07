import CoreFoundation
import Foundation

enum GalaxySSIContactReminderAction: String, Codable {
  case request, received, quiet, muted, acknowledged, dismissed, cancelled, disabled

  var isReceipt: Bool { self != .request && self != .cancelled }
}

enum GalaxySSIContactReminderStatus: String, Codable {
  case queued, received, quiet, muted, acknowledged, dismissed, cancelled, disabled, expired, failed

  var terminal: Bool {
    [.acknowledged, .dismissed, .cancelled, .disabled, .expired, .failed].contains(self)
  }

  func applying(_ action: GalaxySSIContactReminderAction, outgoing: Bool) -> Self {
    guard !terminal, action != .request, let next = Self(rawValue: action.rawValue) else { return self }
    if outgoing && action.isReceipt && !next.terminal &&
        (self == .muted || (self == .quiet && next == .received)) { return self }
    return next
  }
}

struct GalaxySSIContactReminderEnvelope: Codable, Equatable {
  static let type = "peer_attention"
  static let lifetime: Int64 = 120_000
  static let soundDuration: Int64 = 30_000
  let id: String
  let createdAt: Int64
  let expiresAt: Int64
  let action: GalaxySSIContactReminderAction

  init(id: String, createdAt: Int64, expiresAt: Int64, action: GalaxySSIContactReminderAction) {
    self.id = id
    self.createdAt = createdAt
    self.expiresAt = expiresAt
    self.action = action
  }

  init?(_ payload: [String: Any], now: Int64) {
    guard payload.string("type") == Self.type, payload["peer_chat"] as? Bool == true,
          let action = GalaxySSIContactReminderAction(rawValue: payload.string("reminder_action")),
          let created = Self.timestamp(payload["created_at"]), let expires = Self.timestamp(payload["expires_at"])
    else { return nil }
    self.init(id: payload.string("reminder_id"), createdAt: created, expiresAt: expires, action: action)
    guard isCurrent(now: now) else { return nil }
  }

  func isCurrent(now: Int64) -> Bool {
    id.range(of: #"^[A-Za-z0-9-]{16,64}$"#, options: .regularExpression) != nil &&
      createdAt > 0 && expiresAt > createdAt && expiresAt - createdAt <= Self.lifetime &&
      now > 0 && (createdAt <= now || createdAt - now <= 30_000) && now < expiresAt
  }

  func payload(messageId: String, recipient: String, sender: String, now: Int64) -> [String: Any] {
    [
      "type": Self.type, "peer_chat": true, "message_id": messageId,
      "reminder_id": id, "reminder_action": action.rawValue,
      "created_at": createdAt, "expires_at": expiresAt, "time": now,
      "contact_id": recipient, "sender": sender
    ]
  }

  private static func timestamp(_ value: Any?) -> Int64? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    return Int64(number.stringValue)
  }
}

struct GalaxySSIContactReminder: Codable, Equatable, Identifiable {
  let id: String
  let peerID: String
  let outgoing: Bool
  let createdAt: Int64
  let expiresAt: Int64
  let historyID: UUID?
  var status: GalaxySSIContactReminderStatus
  var pendingAction: GalaxySSIContactReminderAction?
  var historyPublished: Bool? = nil

  func envelope(_ action: GalaxySSIContactReminderAction) -> GalaxySSIContactReminderEnvelope {
    GalaxySSIContactReminderEnvelope(id: id, createdAt: createdAt, expiresAt: expiresAt, action: action)
  }
}

struct GalaxySSIContactReminderPanelSelection: Equatable {
  let owner: String
  let id: String
  let peerID: String

  func resolve(in records: [GalaxySSIContactReminder], owner currentOwner: String,
               now: Int64) -> GalaxySSIContactReminder? {
    guard owner == currentOwner else { return nil }
    return records.first {
      $0.id == id && $0.peerID == peerID && $0.outgoing && Self.isVisible($0, now: now)
    }
  }

  static func isVisible(_ record: GalaxySSIContactReminder, now: Int64) -> Bool {
    !record.status.terminal && record.expiresAt > now
  }
}

@MainActor
struct GalaxySSIContactReminderStore {
  enum Failure: Error { case unavailable, capacity }
  struct Acceptance {
    let record: GalaxySSIContactReminder
    let shouldAlert: Bool
  }

  private static let capacity = 512
  private static let retention: Int64 = 86_400_000
  let defaults: UserDefaults
  let secrets: GalaxySSISecretStore
  let owner: String

  private var key: String { "galaxyssi.contact-reminders.v1." + AgentModelLoopRecoveryIdentity.sha256(owner) }

  func create(peerID: String, now: Int64) throws -> GalaxySSIContactReminder {
    guard !peerID.isBlank, now > 0, now <= Int64.max - GalaxySSIContactReminderEnvelope.lifetime else {
      throw Failure.unavailable
    }
    var rows = try load(now: now)
    guard rows.count < Self.capacity else { throw Failure.capacity }
    let record = GalaxySSIContactReminder(id: UUID().uuidString.lowercased(), peerID: peerID,
      outgoing: true, createdAt: now, expiresAt: now + GalaxySSIContactReminderEnvelope.lifetime,
      historyID: UUID(), status: .queued, pendingAction: .request)
    rows[record.id] = record
    try save(rows)
    return record
  }

  func receive(_ envelope: GalaxySSIContactReminderEnvelope, authenticatedPeer: String,
               enabled: Bool, quiet: Bool, now: Int64) throws -> Acceptance? {
    guard !authenticatedPeer.isBlank, envelope.isCurrent(now: now) else { return nil }
    var rows = try load(now: now)
    if var previous = rows[envelope.id] {
      guard previous.peerID == authenticatedPeer, previous.createdAt == envelope.createdAt,
            previous.expiresAt == envelope.expiresAt else { return nil }
      if envelope.action == .request {
        guard !previous.outgoing,
              let receipt = GalaxySSIContactReminderAction(rawValue: previous.status.rawValue),
              receipt.isReceipt else { return nil }
        previous.pendingAction = receipt
      } else {
        guard (previous.outgoing && envelope.action.isReceipt) ||
          (!previous.outgoing && envelope.action == .cancelled) else { return nil }
        previous.status = previous.status.applying(envelope.action, outgoing: previous.outgoing)
        if !previous.outgoing || previous.pendingAction == .request { previous.pendingAction = nil }
      }
      rows[previous.id] = previous
      try save(rows)
      return Acceptance(record: previous, shouldAlert: false)
    }
    guard envelope.action == .request || envelope.action == .cancelled else { return nil }
    guard rows.count < Self.capacity else { throw Failure.capacity }
    let cancelled = envelope.action == .cancelled
    let status: GalaxySSIContactReminderStatus = cancelled ? .cancelled : (!enabled ? .disabled : (quiet ? .quiet : .received))
    let record = GalaxySSIContactReminder(id: envelope.id, peerID: authenticatedPeer,
      outgoing: false, createdAt: envelope.createdAt, expiresAt: envelope.expiresAt,
      historyID: cancelled ? nil : UUID(), status: status,
      pendingAction: cancelled ? nil : GalaxySSIContactReminderAction(rawValue: status.rawValue))
    rows[record.id] = record
    try save(rows)
    return Acceptance(record: record, shouldAlert: enabled && !cancelled)
  }

  func act(id: String, action: GalaxySSIContactReminderAction, now: Int64) throws -> GalaxySSIContactReminder? {
    var rows = try load(now: now)
    guard var record = rows[id], !record.status.terminal,
          record.outgoing ? action == .cancelled : [.muted, .acknowledged, .dismissed].contains(action) else { return nil }
    record.status = record.status.applying(action, outgoing: record.outgoing)
    record.pendingAction = action
    rows[id] = record
    try save(rows)
    return record
  }

  func markQueued(id: String, action: GalaxySSIContactReminderAction, now: Int64) throws {
    var rows = try load(now: now)
    guard var record = rows[id], record.pendingAction == action else { return }
    record.pendingAction = nil
    rows[id] = record
    try save(rows)
  }

  func markHistoryPublished(id: String, now: Int64) throws {
    var rows = try load(now: now)
    guard var record = rows[id], record.historyPublished != true else { return }
    record.historyPublished = true
    rows[id] = record
    try save(rows)
  }

  func failRequest(id: String, peerID: String, now: Int64) throws -> GalaxySSIContactReminder? {
    var rows = try load(now: now)
    guard var record = rows[id], record.peerID == peerID, record.outgoing, record.status == .queued else { return nil }
    record.status = .failed
    record.pendingAction = nil
    rows[id] = record
    try save(rows)
    return record
  }

  func records(now: Int64) throws -> [GalaxySSIContactReminder] {
    let rows = try load(now: now)
    return rows.values.sorted { $0.createdAt < $1.createdAt }
  }

  private func load(now: Int64) throws -> [String: GalaxySSIContactReminder] {
    guard !owner.isBlank else { throw Failure.unavailable }
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets) else {
      guard GalaxySSIEncryptedUserDefaultsStore.storedKeys(defaults: defaults, prefix: key).isEmpty else {
        throw Failure.unavailable
      }
      return [:]
    }
    let existing = try JSONDecoder().decode([String: GalaxySSIContactReminder].self, from: data)
    var result: [String: GalaxySSIContactReminder] = [:]
    for (id, var record) in existing {
      guard record.expiresAt > 0,
            record.expiresAt > now || now - record.expiresAt <= Self.retention else { continue }
      if now >= record.expiresAt {
        if !record.status.terminal { record.status = .expired }
        record.pendingAction = nil
      }
      result[id] = record
    }
    return result
  }

  private func save(_ rows: [String: GalaxySSIContactReminder]) throws {
    let data = try JSONEncoder().encode(rows)
    guard GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: key, secrets: secrets) else {
      throw Failure.unavailable
    }
  }
}
