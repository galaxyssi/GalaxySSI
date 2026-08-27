import CryptoKit
import Foundation

struct AgentTaskIdentity: Codable, Equatable {
  var clientRouteId: String
  var conversationId: String
  var taskId: String
  var turnId: String

  var isComplete: Bool {
    !isBlank(clientRouteId) &&
      !isBlank(conversationId) &&
      !isBlank(taskId) &&
      !isBlank(turnId)
  }

  init(
    clientRouteId: String,
    conversationId: String,
    taskId: String,
    turnId: String
  ) {
    self.clientRouteId = clientRouteId
    self.conversationId = conversationId
    self.taskId = taskId
    self.turnId = turnId
  }

  enum CodingKeys: String, CodingKey {
    case clientRouteId = "client_route_id"
    case conversationId = "conversation_id"
    case taskId = "task_id"
    case turnId = "turn_id"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    clientRouteId = try container.decodeIfPresent(String.self, forKey: .clientRouteId) ?? ""
    conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId) ?? ""
    taskId = try container.decodeIfPresent(String.self, forKey: .taskId) ?? ""
    turnId = try container.decodeIfPresent(String.self, forKey: .turnId) ?? ""
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(clientRouteId, forKey: .clientRouteId)
    try container.encode(conversationId, forKey: .conversationId)
    try container.encode(taskId, forKey: .taskId)
    try container.encode(turnId, forKey: .turnId)
  }

  private func isBlank(_ value: String) -> Bool {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

enum AgentTaskIdentityPolicy {
  static func conversationId(contactId: String, requested: String) -> String {
    trim(requested).isEmpty ? "contact:\(trim(contactId))" : trim(requested)
  }

  static func turnId(
    sourceMessageId: Int64?,
    requested: String,
    fallbackUUID: () -> UUID = { UUID() }
  ) -> String {
    let explicit = trim(requested)
    if !explicit.isEmpty {
      return explicit
    }
    if let sourceMessageId, sourceMessageId > 0 {
      return "message:\(sourceMessageId)"
    }
    return fallbackUUID().uuidString.lowercased()
  }

  static func taskId(
    ownerId: String,
    contactId: String,
    sourceMessageId: Int64?,
    conversationId: String,
    turnId: String,
    requested: String = ""
  ) -> String {
    let explicit = trim(requested)
    if !explicit.isEmpty {
      return explicit
    }
    let seed = [
      trim(ownerId),
      trim(contactId),
      sourceMessageId.map { String($0) } ?? "",
      trim(conversationId),
      trim(turnId)
    ].joined(separator: "\u{001f}")
    return nameBasedUUID(seed).uuidString.lowercased()
  }

  static func taskId(
    ownerId: String,
    contactId: String,
    sourceMessageId: String,
    conversationId: String,
    turnId: String,
    requested: String = ""
  ) -> String {
    let explicit = trim(requested)
    if !explicit.isEmpty {
      return explicit
    }
    let seed = [
      trim(ownerId),
      trim(contactId),
      trim(sourceMessageId),
      trim(conversationId),
      trim(turnId)
    ].joined(separator: "\u{001f}")
    return nameBasedUUID(seed).uuidString.lowercased()
  }

  static func matchesDesktopResponse(
    expected: [String: String],
    conversationId: String,
    taskId: String,
    turnId: String
  ) -> Bool {
    guard expected["resource_location"] == "desktop" else { return true }
    let expectedConversationId = expected["conversation_id"] ?? ""
    let expectedTaskId = expected["remote_task_id"] ?? ""
    let expectedTurnId = expected["turn_id"] ?? ""
    return !isBlank(expectedConversationId) &&
      !isBlank(expectedTaskId) &&
      !isBlank(expectedTurnId) &&
      conversationId == expectedConversationId &&
      taskId == expectedTaskId &&
      turnId == expectedTurnId
  }

  static func routesToMainAgent(
    superseded: Bool,
    hasRuntime: Bool,
    resolvedConversationId: String
  ) -> Bool {
    superseded || hasRuntime || !isBlank(resolvedConversationId)
  }

  static func matchesResponseIdentity(
    expectedConversationId: String,
    expectedTurnId: String,
    expectedTaskId: String,
    actualConversationId: String,
    actualTurnId: String,
    actualTaskId: String
  ) -> Bool {
    let expectedConversationId = trim(expectedConversationId)
    let expectedTurnId = trim(expectedTurnId)
    let expectedTaskId = trim(expectedTaskId)
    let actualConversationId = trim(actualConversationId)
    let actualTurnId = trim(actualTurnId)
    let actualTaskId = trim(actualTaskId)
    let expectedHasTurnIdentity = !expectedConversationId.isEmpty || !expectedTurnId.isEmpty
    let actualHasTurnIdentity = !actualConversationId.isEmpty || !actualTurnId.isEmpty
    if !expectedHasTurnIdentity && !actualHasTurnIdentity { return true }
    if !expectedHasTurnIdentity || !actualHasTurnIdentity { return false }
    guard expectedConversationId == actualConversationId,
          expectedTurnId == actualTurnId else {
      return false
    }
    return expectedTaskId.isEmpty || actualTaskId.isEmpty || expectedTaskId == actualTaskId
  }

  private static func nameBasedUUID(_ value: String) -> UUID {
    var bytes = Array(Insecure.MD5.hash(data: Data(value.utf8)))
    bytes[6] = (bytes[6] & 0x0f) | 0x30
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    return UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5],
      bytes[6], bytes[7],
      bytes[8], bytes[9],
      bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    ))
  }

  private static func trim(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isBlank(_ value: String) -> Bool {
    trim(value).isEmpty
  }
}

final class AgentTaskIdentityStore {
  private let defaults: UserDefaults
  private let storageKeyPrefix: String
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    storageKeyPrefix: String = "signalasi_agent_task_identities"
  ) {
    self.defaults = defaults
    self.storageKeyPrefix = storageKeyPrefix
  }

  func register(
    contactId: String,
    sourceMessageId: Int64,
    identity: AgentTaskIdentity
  ) {
    guard sourceMessageId > 0 else { return }
    register(
      contactId: contactId,
      sourceMessageId: String(sourceMessageId),
      identity: identity
    )
  }

  func register(
    contactId: String,
    sourceMessageId: String,
    identity: AgentTaskIdentity
  ) {
    guard let contactId = clean(contactId),
          let sourceMessageId = clean(sourceMessageId),
          identity.isComplete,
          let encoded = try? encoder.encode(identity) else {
      return
    }
    lock.lock()
    defer { lock.unlock() }
    defaults.set(
      String(decoding: encoded, as: UTF8.self),
      forKey: storageKey(contactId, sourceMessageId)
    )
  }

  func matches(payload: [String: Any]) -> Bool {
    matchesStored(payload: payload, requireRegistered: false)
  }

  func matchesRegistered(payload: [String: Any]) -> Bool {
    matchesStored(payload: payload, requireRegistered: true)
  }

  func identity(contactId: String, sourceMessageId: String) -> AgentTaskIdentity? {
    guard let contactId = clean(contactId),
          let sourceMessageId = clean(sourceMessageId) else {
      return nil
    }
    lock.lock()
    defer { lock.unlock() }
    guard let encoded = defaults.string(forKey: storageKey(contactId, sourceMessageId)) else {
      return nil
    }
    return decodeIdentity(encoded)
  }

  private func matchesStored(payload: [String: Any], requireRegistered: Bool) -> Bool {
    guard let contactId = clean(payload.string("contact_id")),
          let sourceMessageId = clean(sourceMessageIdentity(from: payload)) else {
      return false
    }
    lock.lock()
    defer { lock.unlock() }
    let encoded = defaults.string(forKey: storageKey(contactId, sourceMessageId))
    guard let encoded else {
      return !requireRegistered
    }
    guard let expected = decodeIdentity(encoded) else {
      return false
    }
    return payload.string("client_route_id") == expected.clientRouteId &&
      payload.string("conversation_id") == expected.conversationId &&
      payload.string("task_id") == expected.taskId &&
      payload.string("turn_id") == expected.turnId
  }

  private func sourceMessageIdentity(from payload: [String: Any]) -> String {
    let source = payload.string("source_message_id")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !source.isEmpty {
      return source
    }
    return payload.string("client_message_id")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func decodeIdentity(_ encoded: String) -> AgentTaskIdentity? {
    guard let data = encoded.data(using: .utf8) else { return nil }
    return try? decoder.decode(AgentTaskIdentity.self, from: data)
  }

  private func storageKey(_ contactId: String, _ sourceMessageId: String) -> String {
    let raw = "\(contactId)\u{001f}\(sourceMessageId)"
    let digest = SHA256.hash(data: Data(raw.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    return "\(storageKeyPrefix).\(digest)"
  }

  private func clean(_ value: String) -> String? {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? nil : clean
  }
}
