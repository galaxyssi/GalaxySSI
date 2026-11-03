import Foundation
import UserNotifications

final class AgentIOSUserNotificationPublisher: AgentActionNotificationPublishing {
  private let center: UNUserNotificationCenter

  init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  func publish(_ notification: AgentActionNotification) {
    let identifier = String(notification.notificationId)
    switch Self.presentation(for: notification.phase) {
    case .ignore:
      return
    case .dismiss:
      center.removePendingNotificationRequests(withIdentifiers: [identifier])
      center.removeDeliveredNotifications(withIdentifiers: [identifier])
      AgentIOSOwnedNotificationStore.shared.remove(identifier: identifier)
      return
    case .show:
      break
    }
    let content = UNMutableNotificationContent()
    content.title = notification.title
    content.body = notification.detail
    content.sound = notification.ongoing ? nil : .default
    content.categoryIdentifier = Self.categoryIdentifier(for: notification.category)
    content.threadIdentifier = "galaxyssi.agent.\(notification.taskId)"
    content.userInfo = [
      "galaxyssi_notification_id": notification.notificationId,
      "galaxyssi_action_id": notification.actionId,
      "galaxyssi_task_id": notification.taskId,
      "galaxyssi_destination": notification.destination.rawValue,
      "galaxyssi_private_text": notification.privateText
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

  enum Presentation: Equatable { case ignore, dismiss, show }

  static func presentation(for phase: AgentActionNotificationPhase) -> Presentation {
    switch phase {
    case .running: return .ignore
    case .succeeded: return .dismiss
    case .failed: return .show
    }
  }

  private static func categoryIdentifier(for category: AgentActionNotificationCategory) -> String {
    "galaxyssi.agent_action.\(category.rawValue.lowercased())"
  }
}
