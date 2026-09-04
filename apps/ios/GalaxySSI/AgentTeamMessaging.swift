import Foundation

enum AgentTeamMessageKind: String, Codable, CaseIterable {
  case userDirective = "USER_DIRECTIVE"
  case delegation = "DELEGATION"
  case progress = "PROGRESS"
  case evidence = "EVIDENCE"
  case review = "REVIEW"
  case blocked = "BLOCKED"
  case result = "RESULT"
  case control = "CONTROL"
}

enum AgentTeamMessageState: String, Codable, CaseIterable {
  case pending = "PENDING"
  case delivered = "DELIVERED"
  case acknowledged = "ACKNOWLEDGED"
}

enum AgentTeamMessageError: Error, Equatable {
  case invalid(String)
}

extension AgentTeamMessageError: LocalizedError {
  var errorDescription: String? {
    guard case .invalid(let message) = self else { return nil }
    return message
  }
}

struct AgentTeamMessageEnvelope: Codable, Equatable, Identifiable {
  static let protocolName = "team.v1"
  static let maxIdCharacters = 160
  static let maxTextCharacters = 16_000
  static let maxMetadataEntries = 24
  static let maxMetadataKeyCharacters = 64
  static let maxMetadataValueCharacters = 1_000

  var messageId: String
  var teamId: String
  var conversationId: String
  var supervisorRunId: String
  var fromInstanceId: String
  var toInstanceId: String
  var kind: AgentTeamMessageKind
  var text: String
  var inReplyTo: String
  var sequence: Int64
  var state: AgentTeamMessageState
  var metadata: [String: String]
  var createdAtMillis: Int64
  var deliveredAtMillis: Int64
  var acknowledgedAtMillis: Int64
  var `protocol`: String

  var id: String { messageId }
  var isBroadcast: Bool { cleanTeamMessage(toInstanceId).isEmpty }

  init(
    messageId: String = UUID().uuidString.lowercased(),
    teamId: String,
    conversationId: String,
    supervisorRunId: String,
    fromInstanceId: String,
    toInstanceId: String = "",
    kind: AgentTeamMessageKind,
    text: String,
    inReplyTo: String = "",
    sequence: Int64 = 0,
    state: AgentTeamMessageState = .pending,
    metadata: [String: String] = [:],
    createdAtMillis: Int64 = AgentControlPlaneClock.nowMillis(),
    deliveredAtMillis: Int64 = 0,
    acknowledgedAtMillis: Int64 = 0,
    protocol: String = AgentTeamMessageEnvelope.protocolName
  ) {
    self.messageId = messageId
    self.teamId = teamId
    self.conversationId = conversationId
    self.supervisorRunId = supervisorRunId
    self.fromInstanceId = fromInstanceId
    self.toInstanceId = toInstanceId
    self.kind = kind
    self.text = text
    self.inReplyTo = inReplyTo
    self.sequence = sequence
    self.state = state
    self.metadata = metadata
    self.createdAtMillis = createdAtMillis
    self.deliveredAtMillis = deliveredAtMillis
    self.acknowledgedAtMillis = acknowledgedAtMillis
    self.protocol = `protocol`
  }

  func validated() throws -> AgentTeamMessageEnvelope {
    let messageId = try requiredId(self.messageId, label: "message")
    let teamId = try requiredId(self.teamId, label: "team")
    let conversationId = String(cleanTeamMessage(self.conversationId).prefix(Self.maxIdCharacters))
    let runId = try requiredId(supervisorRunId, label: "Run")
    let sender = try requiredId(fromInstanceId, label: "sender")
    let recipient = String(cleanTeamMessage(toInstanceId).prefix(Self.maxIdCharacters))
    let text = String(cleanTeamMessage(self.text).prefix(Self.maxTextCharacters))
    guard !conversationId.isEmpty else {
      throw AgentTeamMessageError.invalid("Conversation id must not be blank")
    }
    guard !text.isEmpty else {
      throw AgentTeamMessageError.invalid("Team message must not be blank")
    }
    guard recipient.isEmpty || recipient != sender else {
      throw AgentTeamMessageError.invalid("A direct team message must target another instance")
    }
    var boundedMetadata: [String: String] = [:]
    for entry in metadata.sorted(by: { $0.key < $1.key }).prefix(Self.maxMetadataEntries) {
      let key = String(cleanTeamMessage(entry.key).prefix(Self.maxMetadataKeyCharacters))
      guard !key.isEmpty else { continue }
      boundedMetadata[key] = String(entry.value.prefix(Self.maxMetadataValueCharacters))
    }
    return AgentTeamMessageEnvelope(
      messageId: messageId,
      teamId: teamId,
      conversationId: conversationId,
      supervisorRunId: runId,
      fromInstanceId: sender,
      toInstanceId: recipient,
      kind: kind,
      text: text,
      inReplyTo: String(cleanTeamMessage(inReplyTo).prefix(Self.maxIdCharacters)),
      sequence: max(sequence, 0),
      state: state,
      metadata: boundedMetadata,
      createdAtMillis: max(createdAtMillis, 0),
      deliveredAtMillis: max(deliveredAtMillis, 0),
      acknowledgedAtMillis: max(acknowledgedAtMillis, 0),
      protocol: Self.protocolName
    )
  }

  enum CodingKeys: String, CodingKey {
    case messageId = "message_id"
    case teamId = "team_id"
    case conversationId = "conversation_id"
    case supervisorRunId = "supervisor_run_id"
    case fromInstanceId = "from_instance_id"
    case toInstanceId = "to_instance_id"
    case kind
    case text
    case inReplyTo = "in_reply_to"
    case sequence
    case state
    case metadata
    case createdAtMillis = "created_at_millis"
    case deliveredAtMillis = "delivered_at_millis"
    case acknowledgedAtMillis = "acknowledged_at_millis"
    case `protocol`
  }

  private func requiredId(_ value: String, label: String) throws -> String {
    let normalized = String(cleanTeamMessage(value).prefix(Self.maxIdCharacters))
    guard !normalized.isEmpty else {
      throw AgentTeamMessageError.invalid("\(label) id must not be blank")
    }
    return normalized
  }
}

protocol AgentTeamMailbox: AnyObject {
  func append(_ message: AgentTeamMessageEnvelope) throws -> AgentTeamMessageEnvelope
  func messages(supervisorRunId: String, instanceId: String, afterSequence: Int64) -> [AgentTeamMessageEnvelope]
  func markDelivered(messageId: String, atMillis: Int64) -> AgentTeamMessageEnvelope?
  func acknowledge(messageId: String, atMillis: Int64) -> AgentTeamMessageEnvelope?
  func clear(supervisorRunId: String)
}

final class InMemoryAgentTeamMailbox: AgentTeamMailbox {
  private let lock = NSRecursiveLock()
  private var records: [AgentTeamMessageEnvelope] = []

  init(initialMessages: [AgentTeamMessageEnvelope] = []) {
    for message in initialMessages {
      guard let normalized = try? message.validated(),
        !records.contains(where: { $0.messageId == normalized.messageId }) else { continue }
      let last = records.filter { $0.supervisorRunId == normalized.supervisorRunId }
        .map(\.sequence).max() ?? 0
      var sequenced = normalized
      sequenced.sequence = normalized.sequence > last ? normalized.sequence : last + 1
      records.append(sequenced)
    }
  }

  func append(_ message: AgentTeamMessageEnvelope) throws -> AgentTeamMessageEnvelope {
    let normalized = try message.validated()
    lock.lock()
    defer { lock.unlock() }
    if let existing = records.first(where: { $0.messageId == normalized.messageId }) {
      return existing
    }
    var appended = normalized
    appended.sequence = (records.filter { $0.supervisorRunId == normalized.supervisorRunId }
      .map(\.sequence).max() ?? 0) + 1
    records.append(appended)
    return appended
  }

  func messages(
    supervisorRunId: String,
    instanceId: String,
    afterSequence: Int64
  ) -> [AgentTeamMessageEnvelope] {
    lock.lock()
    defer { lock.unlock() }
    return records.filter { message in
      message.supervisorRunId == supervisorRunId &&
        message.sequence > afterSequence &&
        (cleanTeamMessage(instanceId).isEmpty || message.isBroadcast || message.toInstanceId == instanceId)
    }.sorted { $0.sequence < $1.sequence }
  }

  func markDelivered(messageId: String, atMillis: Int64) -> AgentTeamMessageEnvelope? {
    mutate(messageId: messageId) { current in
      guard current.state != .acknowledged else { return current }
      var updated = current
      updated.state = .delivered
      updated.deliveredAtMillis = max(current.deliveredAtMillis, max(current.createdAtMillis, atMillis))
      return updated
    }
  }

  func acknowledge(messageId: String, atMillis: Int64) -> AgentTeamMessageEnvelope? {
    mutate(messageId: messageId) { current in
      var updated = current
      let acknowledgedAt = max(
        max(current.acknowledgedAtMillis, current.deliveredAtMillis),
        max(current.createdAtMillis, atMillis)
      )
      updated.state = .acknowledged
      updated.deliveredAtMillis = current.deliveredAtMillis > 0 ? current.deliveredAtMillis : acknowledgedAt
      updated.acknowledgedAtMillis = acknowledgedAt
      return updated
    }
  }

  func clear(supervisorRunId: String) {
    lock.lock()
    if cleanTeamMessage(supervisorRunId).isEmpty {
      records.removeAll()
    } else {
      records.removeAll { $0.supervisorRunId == supervisorRunId }
    }
    lock.unlock()
  }

  func snapshot() -> [AgentTeamMessageEnvelope] {
    lock.lock()
    defer { lock.unlock() }
    return records
  }

  private func mutate(
    messageId: String,
    mutation: (AgentTeamMessageEnvelope) -> AgentTeamMessageEnvelope
  ) -> AgentTeamMessageEnvelope? {
    lock.lock()
    defer { lock.unlock() }
    guard let index = records.firstIndex(where: { $0.messageId == messageId }) else { return nil }
    records[index] = mutation(records[index])
    return records[index]
  }
}

final class UserDefaultsAgentTeamMailbox: AgentTeamMailbox {
  static let defaultKey = "galaxyssi_agent_team_mailbox_v1"
  static let maxMessages = 5_000

  private let defaults: UserDefaults
  private let key: String
  private let secrets: GalaxySSISecretStore
  private let lock = NSRecursiveLock()
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    defaults: UserDefaults = .standard,
    key: String = UserDefaultsAgentTeamMailbox.defaultKey,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  ) {
    self.defaults = defaults
    self.key = key
    self.secrets = secrets
  }

  func append(_ message: AgentTeamMessageEnvelope) throws -> AgentTeamMessageEnvelope {
    lock.lock()
    defer { lock.unlock() }
    let mailbox = loadLocked()
    let appended = try mailbox.append(message)
    saveLocked(mailbox.snapshot())
    return appended
  }

  func messages(
    supervisorRunId: String,
    instanceId: String,
    afterSequence: Int64
  ) -> [AgentTeamMessageEnvelope] {
    lock.lock()
    defer { lock.unlock() }
    return loadLocked().messages(
      supervisorRunId: supervisorRunId,
      instanceId: instanceId,
      afterSequence: afterSequence
    )
  }

  func markDelivered(messageId: String, atMillis: Int64) -> AgentTeamMessageEnvelope? {
    mutate { $0.markDelivered(messageId: messageId, atMillis: atMillis) }
  }

  func acknowledge(messageId: String, atMillis: Int64) -> AgentTeamMessageEnvelope? {
    mutate { $0.acknowledge(messageId: messageId, atMillis: atMillis) }
  }

  func clear(supervisorRunId: String) {
    lock.lock()
    let mailbox = loadLocked()
    mailbox.clear(supervisorRunId: supervisorRunId)
    saveLocked(mailbox.snapshot())
    lock.unlock()
  }

  static func destroy(
    defaults: UserDefaults = .standard,
    key: String = UserDefaultsAgentTeamMailbox.defaultKey,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  ) {
    GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: key, secrets: secrets)
  }

  private func mutate(
    _ mutation: (InMemoryAgentTeamMailbox) -> AgentTeamMessageEnvelope?
  ) -> AgentTeamMessageEnvelope? {
    lock.lock()
    defer { lock.unlock() }
    let mailbox = loadLocked()
    let updated = mutation(mailbox)
    if updated != nil { saveLocked(mailbox.snapshot()) }
    return updated
  }

  private func loadLocked() -> InMemoryAgentTeamMailbox {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets),
      let messages = try? decoder.decode([AgentTeamMessageEnvelope].self, from: data) else {
      return InMemoryAgentTeamMailbox()
    }
    return InMemoryAgentTeamMailbox(initialMessages: Array(messages.suffix(Self.maxMessages)))
  }

  private func saveLocked(_ messages: [AgentTeamMessageEnvelope]) {
    guard let data = try? encoder.encode(Array(messages.suffix(Self.maxMessages))) else { return }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: key, secrets: secrets)
  }
}

private func cleanTeamMessage(_ value: String) -> String {
  value.trimmingCharacters(in: .whitespacesAndNewlines)
}
