import Foundation

final class AgentIOSOwnedNotificationStore {
  static let shared = AgentIOSOwnedNotificationStore()
  static let didRecordNotification = Notification.Name("galaxyssi.ios.owned_notification_recorded")

  private let lock = NSLock()
  private var items: [AgentIOSNotificationItem] = []

  init() {}

  @discardableResult
  func record(
    identifier: String,
    title: String,
    body: String,
    category: String = "",
    postedAtMillis: Int64
  ) -> String {
    let item = AgentIOSNotificationItem(
      key: identifier,
      packageName: "com.galaxyssi.ios",
      title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)),
      textPreview: String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(320)),
      category: String(category.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32)),
      postedAtMillis: postedAtMillis,
      canReply: false,
      sensitiveFlags: notificationSensitiveFlags(title: title, body: body)
    )
    lock.lock()
    items.removeAll { $0.key == identifier }
    items.insert(item, at: 0)
    items = Array(items.prefix(AgentIOSNotificationNativeToolCatalog.maxNotifications))
    lock.unlock()
    NotificationCenter.default.post(name: Self.didRecordNotification, object: item)
    return identifier
  }

  private func notificationSensitiveFlags(title: String, body: String) -> [String] {
    let value = "\(title) \(body)".lowercased()
    let terms = [
      "password", "passcode", "verification", "otp", "2fa", "bank", "payment",
      "private key", "access token", "api key", "\u{5bc6}\u{7801}", "\u{9a8c}\u{8bc1}\u{7801}", "\u{79c1}\u{94a5}", "\u{94f6}\u{884c}\u{5361}", "\u{652f}\u{4ed8}"
    ]
    return terms
      .filter { value.contains($0) }
      .map { "notification_\($0.replacingOccurrences(of: " ", with: "_"))" }
  }

  func snapshot(limit: Int) -> AgentIOSNotificationContext {
    lock.lock()
    defer { lock.unlock() }
    return AgentIOSNotificationContext(
      hasAccess: true,
      items: Array(items.prefix(max(1, min(limit, AgentIOSNotificationNativeToolCatalog.maxNotifications)))),
      sensitiveFlags: [
        "ios_galaxyssi_owned_notifications_only",
        "ios_third_party_notification_history_unavailable",
        "ios_cross_app_notification_reply_unavailable"
      ],
      totalCount: items.count
    )
  }

  func remove(identifier: String) {
    let cleanIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanIdentifier.isEmpty else { return }
    lock.lock()
    items.removeAll { $0.key == cleanIdentifier }
    lock.unlock()
  }
}

struct AgentIOSOwnedNotificationToolProvider: AgentIOSNotificationToolProviding {
  var implementationId: String = "galaxyssi.ios.owned_notification_store"
  var store: AgentIOSOwnedNotificationStore = .shared

  func availability() -> AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS exposes current GalaxySSI-owned notification state; third-party history and cross-app replies remain unavailable."
    )
  }

  func snapshot(limit: Int) -> AgentIOSNotificationContext {
    store.snapshot(limit: limit)
  }

  func reply(notificationKey: String, text: String) -> AgentIOSNotificationReplyResult {
    AgentIOSNotificationReplyResult(
      success: false,
      message: "GalaxySSI-owned iOS notifications do not expose a reply action.",
      code: "notification_reply_unsupported",
      retryable: false
    )
  }
}
