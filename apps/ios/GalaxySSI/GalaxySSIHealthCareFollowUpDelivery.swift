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
  @State private var maintenanceDeadline: Date?

  private struct Destination: Identifiable {
    let id: UUID
    let concern: UUID
    let owner: String
    let metric: GalaxySSIHealthMetric
    let visit: UUID?
    var appointment = false
    var lab: GalaxySSIHealthAgentLab.Launch? = nil
  }

  func body(content: Content) -> some View {
    content
      .onChange(of: scene) { phase in
        if phase != .active { destination = nil; maintenanceDeadline = nil }
        generation = UUID()
      }
      .onChange(of: store.profile.identityFingerprint) { _ in
        destination = nil; maintenanceDeadline = nil; generation = UUID()
      }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
        destination = nil
        maintenanceDeadline = nil
      }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
        generation = UUID()
      }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthCareFollowUp.openNotification)) { _ in
        generation = UUID()
      }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecordingReminders.changed)) {
        if $0.object as? String == store.profile.identityFingerprint { generation = UUID() }
      }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
        generation = UUID()
      }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
        if $0.object as? String == store.profile.identityFingerprint { generation = UUID() }
      }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.profileInputsChanged)) {
        if $0.object as? String == store.profile.identityFingerprint { generation = UUID() }
      }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthOriginalStore.indexChanged)) {
        if $0.object as? String == store.profile.identityFingerprint { generation = UUID() }
      }
      .task(id: generation) { await reconcile() }
      .task(id: maintenanceDeadline) {
        guard scene == .active, let maintenanceDeadline else { return }
        let owner = store.profile.identityFingerprint
        let delay = min(86_400, max(0, maintenanceDeadline.timeIntervalSinceNow))
        do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        catch { return }
        guard scene == .active, !Task.isCancelled, owner == store.profile.identityFingerprint,
              UIApplication.shared.isProtectedDataAvailable else { return }
        self.maintenanceDeadline = nil
        generation = UUID()
      }
      .sheet(item: $destination) { route in
        if let lab = route.lab {
          GalaxySSIHealthAgentLabView(launch: lab)
        } else if route.appointment, let visit = route.visit {
          appointment(route, visit: visit)
        } else if let visit = route.visit {
          GalaxySSIHealthVisitJournalView(records: .init(owner: route.owner, secrets: store.secrets),
            concern: route.concern, metric: route.metric, visit: visit)
        } else {
          followUps(route)
        }
      }
  }

  private func appointment(_ route: Destination, visit: UUID) -> some View {
    NavigationView {
      GalaxySSIHealthEncounterView(records: .init(owner: route.owner, secrets: store.secrets), concern: route.concern,
        metric: route.metric, entryID: visit)
        .toolbar { ToolbarItem(placement: .cancellationAction) {
          Button(GalaxySSILocalization.string("galaxyssi.common.close", fallback: "Close", language: language)) { destination = nil }
        } }
    }.navigationViewStyle(.stack).environmentObject(store)
  }

  private func followUps(_ route: Destination) -> some View {
    NavigationView {
      List {
        GalaxySSIHealthCareFollowUpsSection(records: .init(owner: route.owner, secrets: store.secrets),
          concernID: route.concern, metric: route.metric)
      }
      .navigationTitle(route.metric.title(language: language))
      .galaxySSIHealthTheme()
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(GalaxySSILocalization.string("galaxyssi.common.close", fallback: "Close", language: language)) {
            destination = nil
          }
        }
      }
    }.navigationViewStyle(.stack)
  }

  private func reconcile() async {
    let owner = store.profile.identityFingerprint
    let records = GalaxySSIHealthRecords(owner: owner, secrets: store.secrets)
    if scene == .active, !Task.isCancelled, UIApplication.shared.isProtectedDataAvailable {
      maintenanceDeadline = try? records.reconcileLocalCareMaintenance()
    }
    let center = UNUserNotificationCenter.current()
    let authorized = await center.notificationSettings().authorizationStatus
    let scheduled = await center.pendingNotificationRequests()
    let delivered = await center.deliveredNotifications()
    guard !Task.isCancelled, store.profile.identityFingerprint == owner,
          UIApplication.shared.isProtectedDataAvailable else { return }
    do {
      let expiry = try records.appointmentCleanupDeadline()
      if let expiry { maintenanceDeadline = maintenanceDeadline.map { min($0, expiry) } ?? expiry }
      GalaxySSIHealthAppointmentBackground.schedule(expiry)
    } catch { /* Keep the prior cleanup request when protected state cannot be read. */ }
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
    for id in visible where plan.keepDelivered.contains(id) {
      if let token = UUID(uuidString: String(id.dropFirst(prefix.count))) {
        try? records.markAppointmentDelivered(token: token, now: now)
      }
    }
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
          let request = delivery.reminder.appointment != nil ? GalaxySSIHealthAppointmentNotifications.request(delivery, language: language)
            : UNNotificationRequest(identifier: id, content: content, trigger: trigger)
          try await center.add(request)
        }
        guard store.profile.identityFingerprint == owner, UIApplication.shared.isProtectedDataAvailable
        else { throw GalaxySSIHealthRecords.Failure.stale }
        try records.markLocalCareFollowUpSubmitted(delivery, calendar: calendar, now: Date())
      } catch {
        let current = await center.pendingNotificationRequests().first { $0.identifier == id }
        let date = (current?.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
        if date.map({ abs($0.timeIntervalSince(delivery.due)) < 2 }) == true {
          center.removePendingNotificationRequests(withIdentifiers: [id])
        }
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
    if let lab = reminder.labReview {
      guard let session = store.agentSession(id: lab.conversation), session.status == .active,
        session.collaborationRoster == nil, session.globalTopicKey.isBlank, session.mergedIntoConversationId.isBlank,
        store.switchAgentSession(session.id) else { return }
      destination = .init(id: reminder.id, concern: reminder.concernID, owner: records.owner, metric: reminder.metric,
        visit: nil, lab: .init(owner: records.owner, conversation: lab.conversation, mode: .results, through: lab.through))
      return
    }
    destination = .init(id: reminder.id, concern: reminder.concernID, owner: records.owner, metric: reminder.metric,
      visit: reminder.appointment?.visit ?? reminder.journalReview?.visit, appointment: reminder.appointment != nil)
  }
}
