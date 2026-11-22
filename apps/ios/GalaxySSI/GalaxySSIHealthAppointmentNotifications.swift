import Foundation
import UIKit
import UserNotifications

@MainActor
enum GalaxySSIHealthAppointmentNotifications {
  static func request(_ delivery: GalaxySSIHealthCareFollowUp.Delivery, language: String) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = GalaxySSIHealthRecordingReminderView.text("notification_title", "GalaxySSI reminder", language: language)
    content.body = GalaxySSIHealthAppointmentReminder.text("notification", "Open GalaxySSI to review your appointment.", language)
    content.userInfo = [GalaxySSIHealthAppointmentReminder.notificationKind: GalaxySSIHealthAppointmentReminder.kind]
    return UNNotificationRequest(identifier: delivery.reminder.identifier, content: content,
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, delivery.due.timeIntervalSinceNow), repeats: false))
  }

  nonisolated static func isAppointment(_ request: UNNotificationRequest) -> Bool {
    request.identifier.hasPrefix(GalaxySSIHealthCareFollowUp.prefix) &&
      request.content.userInfo[GalaxySSIHealthAppointmentReminder.notificationKind] as? String == GalaxySSIHealthAppointmentReminder.kind
  }

  static func presentation(_ request: UNNotificationRequest) async -> UNNotificationPresentationOptions {
    guard isAppointment(request), let initial = GalaxySSIHealthCareModelAttentionRuntime.Context.persisted(),
          let token = UUID(uuidString: String(request.identifier.dropFirst(GalaxySSIHealthCareFollowUp.prefix.count))) else { return [] }
    let center = UNUserNotificationCenter.current()
    let permitted = GalaxySSIHealthReviewDelivery.permitted(await center.notificationSettings().authorizationStatus)
    guard permitted, !Task.isCancelled, UIApplication.shared.isProtectedDataAvailable,
          GalaxySSIHealthCareModelAttentionRuntime.Context.persisted()?.owner == initial.owner else { return [] }
    let records = GalaxySSIHealthRecords(owner: initial.owner, secrets: initial.secrets)
    let now = Date()
    guard let reminder = try? records.localCareFollowUpTarget(token: token, now: now), reminder.appointment != nil,
          let archive = try? records.load(),
          GalaxySSIHealthRecords.appointmentReminderPreferences(archive)?.nextAllowed(now, calendar: .autoupdatingCurrent) == now else {
      center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
      center.removeDeliveredNotifications(withIdentifiers: [request.identifier])
      return []
    }
    try? records.markAppointmentDelivered(token: token, now: now)
    return [.banner, .list]
  }

  static func cleanPersisted() async -> Date? {
    guard let initial = GalaxySSIHealthCareModelAttentionRuntime.Context.persisted() else { return Date().addingTimeInterval(60) }
    let center = UNUserNotificationCenter.current()
    let status = await center.notificationSettings().authorizationStatus
    let pending = await center.pendingNotificationRequests().filter(isAppointment)
    let visible = await center.deliveredNotifications().map(\.request).filter(isAppointment)
    guard !Task.isCancelled, UIApplication.shared.isProtectedDataAvailable,
          GalaxySSIHealthCareModelAttentionRuntime.Context.persisted()?.owner == initial.owner else { return nil }
    let records = GalaxySSIHealthRecords(owner: initial.owner, secrets: initial.secrets)
    let dates = Dictionary(uniqueKeysWithValues: pending.compactMap { request -> (String, Date)? in
      guard let date = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate() else { return nil }
      return (request.identifier, date)
    })
    do {
      let plan = try records.localCareFollowUpDelivery(pending: dates, delivered: Set(visible.map(\.identifier)),
        permitted: GalaxySSIHealthReviewDelivery.permitted(status), calendar: .autoupdatingCurrent, now: Date())
      let desired = Set(plan.pending.filter { $0.reminder.appointment != nil }.map(\.reminder.identifier))
      center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { !desired.contains($0) })
      center.removeDeliveredNotifications(withIdentifiers: visible.map(\.identifier).filter { !plan.keepDelivered.contains($0) })
      for item in visible where plan.keepDelivered.contains(item.identifier) {
        if let token = UUID(uuidString: String(item.identifier.dropFirst(GalaxySSIHealthCareFollowUp.prefix.count))) {
          try? records.markAppointmentDelivered(token: token)
        }
      }
      return try records.appointmentCleanupDeadline()
    } catch { return Date().addingTimeInterval(60) }
  }
}
