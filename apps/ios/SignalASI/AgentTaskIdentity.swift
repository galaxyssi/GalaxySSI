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
