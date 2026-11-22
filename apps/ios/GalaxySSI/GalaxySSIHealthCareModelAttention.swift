import CryptoKit
import Foundation

enum GalaxySSIHealthCareModelAttention {
  static let prefix = "galaxyssi.health.model_attention."
  static let turnKey = "galaxyssi.health.model_attention.turn"
  static let pendingKey = "galaxyssi.pending_health_model_attention"
  static let openNotification = Notification.Name("galaxyssi.open_health_model_attention")
  static let visibilityChanged = Notification.Name("galaxyssi.health_model_attention_visibility")
  static let pageSize = 30

  enum State: String, Codable { case waiting, posted, inAppOnly, stale }
  struct Receipt: Codable, Equatable, Identifiable {
    let owner: String
    let concern: UUID
    let turn: UUID
    let conversation: UUID
    let createdAt: Date
    var state = State.waiting
    var retryAt: Date?
    var id: UUID { concern }
    var identifier: String { GalaxySSIHealthCareModelAttention.identifier(owner: owner, concern: concern) }

    init(_ review: GalaxySSIHealthCareModelReview.Review) {
      owner = review.owner; concern = review.authorization.concern; turn = review.id
      conversation = review.authorization.thread; createdAt = review.createdAt
    }
  }

  static func identifier(owner: String, concern: UUID) -> String {
    prefix + SHA256.hash(data: Data((owner + "\0" + concern.uuidString).utf8)).map { String(format: "%02x", $0) }.joined()
  }
  static func isIdentifier(_ value: String) -> Bool {
    guard value.hasPrefix(prefix) else { return false }
    let suffix = value.dropFirst(prefix.count)
    return suffix.count == 64 && suffix.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  struct VisibleScope: Equatable {
    let owner: String
    let concern: UUID
    let conversation: UUID
  }
  final class Visibility: @unchecked Sendable {
    static let shared = Visibility()
    private let lock = NSLock()
    private var scopes: [UUID: VisibleScope] = [:]
    func update(_ view: UUID, scope: VisibleScope?) {
      lock.lock()
      let changed = scopes[view] != scope
      scopes[view] = scope
      lock.unlock()
      if changed { NotificationCenter.default.post(name: GalaxySSIHealthCareModelAttention.visibilityChanged, object: nil) }
    }
    func contains(owner: String, conversation: UUID) -> Bool {
      lock.lock(); defer { lock.unlock() }
      return scopes.values.contains { $0.owner == owner && $0.conversation == conversation }
    }
  }
}
