import Foundation

enum GalaxySSIHealthCareFollowUp {
  static let prefix = "galaxyssi.health.care_follow_up."
  static let pendingKey = "galaxyssi.pending_health_care_follow_up"
  static let openNotification = Notification.Name("galaxyssi.open_health_care_follow_up")
  static let maximumPending = 16

  struct Outcome: Codable, Equatable {
    let note: String
    let reportedAt: Date
  }

  struct Reminder: Codable, Equatable, Identifiable {
    let id: UUID
    let actionID: String
    let concernID: UUID
    let metric: GalaxySSIHealthMetric
    let requestedAt: Date
    var submittedFor: Date?

    var identifier: String { GalaxySSIHealthCareFollowUp.prefix + id.uuidString }
  }

  struct Delivery: Equatable {
    let reminder: Reminder
    let due: Date
  }

  struct DeliveryPlan {
    var pending: [Delivery] = []
    var keepDelivered: Set<String> = []
  }

  static func deliveryPlan(reminders: [Reminder], preferences: GalaxySSIHealthReviewDelivery.Preferences?,
      permitted: Bool, pending: [String: Date], delivered: Set<String>, calendar: Calendar, now: Date) -> DeliveryPlan {
    guard permitted, let preferences, preferences.enabled else { return .init() }
    var plan = DeliveryPlan()
    for reminder in reminders.sorted(by: { ($0.requestedAt, $0.identifier) < ($1.requestedAt, $1.identifier) }) {
      let id = reminder.identifier
      if delivered.contains(id) {
        if preferences.nextAllowed(now, calendar: calendar) == now { plan.keepDelivered.insert(id) }
        continue
      }
      if let submitted = reminder.submittedFor, submitted <= now, pending[id] == nil { continue }
      let due: Date
      if let scheduled = pending[id], scheduled > now, scheduled >= reminder.requestedAt.addingTimeInterval(-1),
         preferences.nextAllowed(scheduled, calendar: calendar) == scheduled {
        due = scheduled
      } else {
        due = preferences.nextAllowed(max(reminder.requestedAt, now.addingTimeInterval(2)), calendar: calendar)
      }
      if plan.pending.count < maximumPending {
        plan.pending.append(.init(reminder: reminder, due: due))
      }
    }
    return plan
  }
}
