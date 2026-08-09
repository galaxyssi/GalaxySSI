import Foundation

final class AgentIOSOwnedNotificationStore {
  static let shared = AgentIOSOwnedNotificationStore()

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
      packageName: "com.signalasi.ios",
      title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)),
      textPreview: String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(320)),
      category: String(category.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32)),
      postedAtMillis: postedAtMillis,
      canReply: false
    )
    lock.lock()
    defer { lock.unlock() }
    items.removeAll { $0.key == identifier }
    items.insert(item, at: 0)
    items = Array(items.prefix(AgentIOSNotificationNativeToolCatalog.maxNotifications))
    return identifier
  }

  func snapshot(limit: Int) -> AgentIOSNotificationContext {
    lock.lock()
    defer { lock.unlock() }
    return AgentIOSNotificationContext(
      hasAccess: true,
      items: Array(items.prefix(max(1, min(limit, AgentIOSNotificationNativeToolCatalog.maxNotifications)))),
      sensitiveFlags: [
        "ios_signalasi_owned_notifications_only",
        "ios_third_party_notification_history_unavailable",
        "ios_cross_app_notification_reply_unavailable"
      ],
      totalCount: items.count
    )
  }
}

struct AgentIOSOwnedNotificationToolProvider: AgentIOSNotificationToolProviding {
  var implementationId: String = "signalasi.ios.owned_notification_store"
  var store: AgentIOSOwnedNotificationStore = .shared

  func availability() -> AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .available,
      reason: "iOS exposes current SignalASI-owned notification state; third-party history and cross-app replies remain unavailable."
    )
  }

  func snapshot(limit: Int) -> AgentIOSNotificationContext {
    store.snapshot(limit: limit)
  }

  func reply(notificationKey: String, text: String) -> AgentIOSNotificationReplyResult {
    AgentIOSNotificationReplyResult(
      success: false,
      message: "SignalASI-owned iOS notifications do not expose a reply action.",
      code: "notification_reply_unsupported",
      retryable: false
    )
  }
}
