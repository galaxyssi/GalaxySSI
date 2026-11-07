import SwiftUI
import UIKit
import UserNotifications

@MainActor
struct GalaxySSIHealthCareFollowUpLifecycle: ViewModifier {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let store: GalaxySSIStore
  @State private var generation = UUID()
  @State private var destination: Destination?

  private struct Destination: Identifiable {
    let id: UUID
    let owner: String
    let metric: GalaxySSIHealthMetric
  }

  func body(content: Content) -> some View {
    content
      .onChange(of: scene) { phase in
        if phase != .active { destination = nil }
        generation = UUID()
      }
      .onChange(of: store.profile.identityFingerprint) { _ in destination = nil; generation = UUID() }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthCareFollowUp.openNotification)) { _ in
        generation = UUID()
      }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
        generation = UUID()
      }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
        if $0.object as? String == store.profile.identityFingerprint { generation = UUID() }
      }
      .task(id: generation) { await reconcile() }
      .sheet(item: $destination) { route in
        NavigationView {
          List {
            GalaxySSIHealthCareFollowUpsSection(records: .init(owner: route.owner, secrets: store.secrets),
              concernID: route.id, metric: route.metric)
          }
          .navigationTitle(route.metric.title(language: language))
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button(GalaxySSILocalization.string("galaxyssi.common.close", fallback: "Close", language: language)) {
                destination = nil
              }
            }
          }
        }.navigationViewStyle(.stack)
      }
  }

  private func reconcile() async {
    let owner = store.profile.identityFingerprint
    let records = GalaxySSIHealthRecords(owner: owner, secrets: store.secrets)
    let center = UNUserNotificationCenter.current()
    let authorized = await center.notificationSettings().authorizationStatus
    let scheduled = await center.pendingNotificationRequests()
    let delivered = await center.deliveredNotifications()
    guard !Task.isCancelled, store.profile.identityFingerprint == owner else { return }
    let prefix = GalaxySSIHealthCareFollowUp.prefix
    let ours = scheduled.filter { $0.identifier.hasPrefix(prefix) }
    let visible = delivered.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
    let pending = Dictionary(uniqueKeysWithValues: ours.compactMap { request -> (String, Date)? in
      guard let trigger = request.trigger as? UNTimeIntervalNotificationTrigger,
            let date = trigger.nextTriggerDate() else { return nil }
      return (request.identifier, date)
    })
    let calendar = Calendar.autoupdatingCurrent
    let now = Date()
    guard let plan = try? records.localCareFollowUpDelivery(pending: pending, delivered: Set(visible),
      permitted: GalaxySSIHealthReviewDelivery.permitted(authorized), calendar: calendar, now: now) else { return }
    let slots = max(0, 64 - (scheduled.count - ours.count))
    let selected = plan.pending.prefix(slots)
    let desired = Set(selected.map(\.reminder.identifier))
    center.removePendingNotificationRequests(withIdentifiers: ours.map(\.identifier).filter { !desired.contains($0) })
    center.removeDeliveredNotifications(withIdentifiers: visible.filter { !plan.keepDelivered.contains($0) })
    guard scene == .active else { return }
    openPending(records: records, permitted: GalaxySSIHealthReviewDelivery.permitted(authorized), now: now)
    for delivery in selected {
      guard scene == .active, !Task.isCancelled, store.profile.identityFingerprint == owner else { return }
      let id = delivery.reminder.identifier
      if let date = pending[id], abs(date.timeIntervalSince(delivery.due)) < 1,
         delivery.reminder.submittedFor != nil { continue }
      let content = UNMutableNotificationContent()
      content.title = GalaxySSIHealthRecordingReminderView.text("notification_title", "GalaxySSI reminder", language: language)
      content.body = GalaxySSIHealthRecordingReminderView.text("notification_body", "Open GalaxySSI to review.", language: language)
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delivery.due.timeIntervalSinceNow), repeats: false)
      do {
        if pending[id].map({ abs($0.timeIntervalSince(delivery.due)) < 1 }) != true {
          try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        guard store.profile.identityFingerprint == owner else { throw GalaxySSIHealthRecords.Failure.stale }
        try records.markLocalCareFollowUpSubmitted(delivery, calendar: calendar, now: Date())
      } catch {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
      }
    }
  }

  private func openPending(records: GalaxySSIHealthRecords, permitted: Bool, now: Date) {
    let defaults = UserDefaults.standard
    let key = GalaxySSIHealthCareFollowUp.pendingKey
    guard let raw = defaults.string(forKey: key) else { return }
    defaults.removeObject(forKey: key)
    guard permitted, let token = UUID(uuidString: raw),
          let reminder = try? records.localCareFollowUpTarget(token: token, now: now) else { return }
    destination = .init(id: reminder.concernID, owner: records.owner, metric: reminder.metric)
  }
}
