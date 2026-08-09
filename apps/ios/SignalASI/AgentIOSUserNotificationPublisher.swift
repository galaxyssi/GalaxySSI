import Foundation
import UserNotifications

final class AgentIOSUserNotificationPublisher: AgentActionNotificationPublishing {
  private let center: UNUserNotificationCenter

  init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  func publish(_ notification: AgentActionNotification) {
    let identifier = String(notification.notificationId)
    let content = UNMutableNotificationContent()
    content.title = notification.title
    content.body = notification.detail
    content.sound = notification.ongoing ? nil : .default
    content.categoryIdentifier = Self.categoryIdentifier(for: notification.category)
    content.threadIdentifier = "signalasi.agent.\(notification.taskId)"
    content.userInfo = [
      "signalasi_notification_id": notification.notificationId,
      "signalasi_action_id": notification.actionId,
      "signalasi_task_id": notification.taskId,
      "signalasi_destination": notification.destination.rawValue,
      "signalasi_private_text": notification.privateText
    ]

    AgentIOSOwnedNotificationStore.shared.record(
      identifier: identifier,
      title: notification.title,
      body: notification.detail,
      category: notification.category.rawValue.lowercased(),
      postedAtMillis: notification.createdAtMillis
    )

    // Reusing the stable identifier updates the running operation with its result.
    center.removeDeliveredNotifications(withIdentifiers: [identifier])
    center.add(
      UNNotificationRequest(
        identifier: identifier,
        content: content,
        trigger: nil
      )
    )
  }

  private static func categoryIdentifier(for category: AgentActionNotificationCategory) -> String {
    "signalasi.agent_action.\(category.rawValue.lowercased())"
  }
}
