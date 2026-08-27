import Foundation

final class SignalASIVisibleConversationTracker {
  static let shared = SignalASIVisibleConversationTracker()

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
