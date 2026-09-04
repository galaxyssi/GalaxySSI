import Foundation

final class GalaxySSIVisibleConversationTracker {
  static let shared = GalaxySSIVisibleConversationTracker()

  private let lock = NSLock()
  private var contactIdByToken: [UUID: String] = [:]

  func markVisible(contactId: String, token: UUID) {
    let normalized = contactId.trimmingCharacters(in: .whitespacesAndNewlines)
    lock.lock()
    defer { lock.unlock() }
    if normalized.isEmpty {
      contactIdByToken.removeValue(forKey: token)
    } else {
      contactIdByToken[token] = normalized
    }
  }

  func markHidden(token: UUID) {
    lock.lock()
    contactIdByToken.removeValue(forKey: token)
    lock.unlock()
  }

  func shouldNotify(contactId: String, applicationIsActive: Bool) -> Bool {
    guard applicationIsActive else { return true }
    let normalized = contactId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return true }
    lock.lock()
    defer { lock.unlock() }
    return !contactIdByToken.values.contains(normalized)
  }
}

enum GalaxySSIContactNotificationPresentationPolicy {
  static let contactIdKey = "galaxyssi_open_contact_id"

  static func shouldPresent(
    userInfo: [AnyHashable: Any],
    applicationIsActive: Bool,
    tracker: GalaxySSIVisibleConversationTracker = .shared
  ) -> Bool {
    let contactId = (userInfo[contactIdKey] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !contactId.isEmpty else { return true }
    return tracker.shouldNotify(
      contactId: contactId,
      applicationIsActive: applicationIsActive
    )
  }
}

enum AgentRuntimeNotificationPolicy {
  static func shouldNotify(
    payload: [String: Any],
    applicationIsActive: Bool
  ) -> Bool {
    guard applicationIsActive else { return true }
    let type = payload.string("type").ifBlank("text")
    if type == "agent_task_event" { return false }
    guard type == "text" else { return true }
    let sourceMessageId = payload.string("source_message_id")
      .ifBlank(String(payload.int("source_message_id")))
    guard !sourceMessageId.isBlank, sourceMessageId != "0" else { return true }
    return payload.string("conversation_id").isBlank ||
      payload.string("turn_id").isBlank ||
      payload.string("task_id").isBlank
  }
}
