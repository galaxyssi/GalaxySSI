import SwiftUI
import UIKit
import UserNotifications

enum GalaxySSIHealthReviewDelivery {
  static let prefix = "galaxyssi.health.review."
  static let pendingKey = "galaxyssi.pending_health_review_token"
  static let openNotification = Notification.Name("galaxyssi.open_health_review")

  struct Preferences: Codable, Equatable {
    var enabled = false
    var pausedUntil: Date?
    var quietStart = 22
    var quietEnd = 8
    var incidentEnabled: Bool?
    var incidentScopes: Set<String>?

    func allows(_ job: GalaxySSIHealthReviewReminders.Job, reviewEnabled: Bool) -> Bool {
      guard job.kind == .incident else { return reviewEnabled && enabled }
      return incidentEnabled == true && job.scope.map { incidentScopes?.contains($0) ?? true } == true
    }

    func nextAllowed(_ date: Date, calendar: Calendar) -> Date {
      let date = max(date, pausedUntil ?? .distantPast)
      guard quietStart != quietEnd else { return date }
      let hour = calendar.component(.hour, from: date)
      let quiet = quietStart < quietEnd ? (quietStart..<quietEnd).contains(hour) : hour >= quietStart || hour < quietEnd
      guard quiet else { return date }
      return calendar.nextDate(after: date, matching: DateComponents(hour: quietEnd, minute: 0),
                               matchingPolicy: .nextTime) ?? date
    }
  }

  struct Ticket: Codable, Equatable {
    let token: UUID
    let due: Date
    let cycle: Date?
    var submitted = false
    var identifier: String { GalaxySSIHealthReviewDelivery.prefix + token.uuidString }
  }

  static func token(_ identifier: String) -> UUID? {
    guard identifier.hasPrefix(prefix) else { return nil }
    return UUID(uuidString: String(identifier.dropFirst(prefix.count)))
  }

  static func plan(jobs: [GalaxySSIHealthReviewReminders.Job], state: GalaxySSIHealthReviewReminders.State,
                   now: Date, calendar: Calendar, permitted: Bool, scheduled: Set<UUID>, delivered: Set<UUID>)
    -> ([String: Ticket], [Ticket]) {
    let prefs = state.notificationPreferences ?? .init()
    let paused = (prefs.pausedUntil ?? .distantPast) > now
    let existing = state.deliveries ?? [:]
    var next: [String: Ticket] = [:]
    var desired: [Ticket] = []
    var pendingCount = 0
    for job in jobs {
      let enabled = permitted && prefs.allows(job, reviewEnabled: state.enabled)
      let action = state.actions[job.key]
      if action == .handled { continue }
      let snooze: Date?
      if case .snoozed(let until) = action { snooze = until } else { snooze = nil }
      if var ticket = existing[job.key], ticket.cycle == snooze,
         delivered.contains(ticket.token) || (ticket.submitted && ticket.due <= now) {
        ticket.submitted = true
        next[job.key] = ticket
        if enabled && !paused { desired.append(ticket) }
        continue
      }
      guard enabled, pendingCount < 24 else { continue }
      let earliest = prefs.nextAllowed(max(now.addingTimeInterval(2), snooze ?? .distantPast), calendar: calendar)
      let ticket: Ticket
      if let previous = existing[job.key], previous.cycle == snooze,
         previous.due > now, previous.due >= (snooze ?? .distantPast),
         prefs.nextAllowed(previous.due, calendar: calendar) == previous.due {
        var resumed = previous
        if scheduled.contains(previous.token) { resumed.submitted = true }
        ticket = resumed
      } else { ticket = Ticket(token: UUID(), due: earliest, cycle: snooze) }
      next[job.key] = ticket
      desired.append(ticket)
      pendingCount += 1
    }
    return (next, desired)
  }
}

@MainActor
struct GalaxySSIHealthReviewNotificationSettings: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let reviewEnabled: Bool
  @State private var preferences = GalaxySSIHealthReviewDelivery.Preferences()
  @State private var failed = false

  var body: some View {
    Section(t("system_section", "System notifications")) {
      if reviewEnabled { Toggle(t("system", "System review notifications"), isOn: setting(\.enabled)) }
      Toggle(t("incident_system", "Sync failure notifications"), isOn: Binding(
        get: { preferences.incidentEnabled == true }, set: { value in change { $0.incidentEnabled = value } }))
      if preferences.incidentEnabled == true {
        DisclosureGroup(t("incident_scopes", "Sync failure scopes")) {
          ForEach(syncScopes) { scope in
            Toggle(scope.metric.title(language: language), isOn: Binding(
              get: { preferences.incidentScopes?.contains(scope.rawValue) ?? true },
              set: { enabled in change { prefs in
                var scopes = prefs.incidentScopes ?? Set(syncScopes.map(\.rawValue))
                if enabled { scopes.insert(scope.rawValue) } else { scopes.remove(scope.rawValue) }
                prefs.incidentScopes = scopes
              } }))
          }
        }
      }
      if preferences.enabled && reviewEnabled || preferences.incidentEnabled == true {
        Picker(t("quiet_start", "Quiet hours begin"), selection: setting(\.quietStart)) { hours }
        Picker(t("quiet_end", "Quiet hours end"), selection: setting(\.quietEnd)) { hours }
        if (preferences.pausedUntil ?? .distantPast) > Date() {
          Button(t("resume_notifications", "Resume notifications")) { change { $0.pausedUntil = nil } }
        } else {
          Button(t("pause_notifications", "Pause notifications for one hour")) {
            change { $0.pausedUntil = Date().addingTimeInterval(3_600) }
          }
        }
      }
      if failed { Text(t("failed", "The review changed or is unavailable.")).foregroundColor(.secondary) }
    }
    .onAppear {
      preferences = (try? records.load().reviewReminderState?.notificationPreferences) ?? .init()
    }
  }

  private var syncScopes: [GalaxySSIHealthKitImport.Scope] {
    GalaxySSIHealthKitImport.Scope.allCases.filter { $0 != .steps }
  }

  private var hours: some View {
    ForEach(0..<24) { hour in Text(String(format: "%02d:00", hour)).tag(hour) }
  }

  private func setting<Value>(_ key: WritableKeyPath<GalaxySSIHealthReviewDelivery.Preferences, Value>) -> Binding<Value> {
    Binding(get: { preferences[keyPath: key] }, set: { value in change { $0[keyPath: key] = value } })
  }

  private func change(_ update: (inout GalaxySSIHealthReviewDelivery.Preferences) -> Void) {
    var edited = preferences
    update(&edited)
    do { try records.setReviewNotificationPreferences(edited); preferences = edited; failed = false }
    catch { failed = true }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.review_reminder." + key, fallback: fallback, language: language)
  }
}

@MainActor
struct GalaxySSIHealthReviewNotificationLifecycle: ViewModifier {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let store: GalaxySSIStore
  @State private var generation = UUID()
  @State private var destination: Destination?

  private struct Destination: Identifiable {
    let records: GalaxySSIHealthRecords
    let job: GalaxySSIHealthReviewReminders.Job
    let original: GalaxySSIHealthOriginalStore.Original?
    var id: String { job.key }
  }

  private var records: GalaxySSIHealthRecords {
    GalaxySSIHealthRecords(owner: store.profile.identityFingerprint, secrets: store.secrets)
  }

  func body(content: Content) -> some View {
    content
      .onAppear(perform: refresh)
      .onChange(of: scene) { if $0 == .active { refresh() } else if $0 == .background { destination = nil } }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refresh() }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthReviewDelivery.openNotification)) { _ in refresh() }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.reviewInputsChanged)) {
        if $0.object as? String == records.owner { refresh() }
      }
      .task(id: generation) { await reconcile() }
      .sheet(item: $destination) { route in
        NavigationView {
          Group {
            if let original = route.original {
              GalaxySSIHealthReportBatchView(records: route.records,
                store: GalaxySSIHealthOriginalStore(owner: route.records.owner, secrets: route.records.secrets), original: original)
            } else if route.job.kind == .incident, let scope = route.job.scope.flatMap(GalaxySSIHealthKitImport.Scope.init(rawValue:)) {
              GalaxySSIHealthKitSyncView(records: route.records, focusedScope: scope)
            } else {
              GalaxySSIHealthTableImportView(records: route.records, resumeReviewID: route.job.target)
            }
          }
          .toolbar { ToolbarItem(placement: .cancellationAction) {
            Button(t("close", "Close")) { destination = nil }
          } }
        }
        .navigationViewStyle(.stack)
      }
  }

  private func refresh() {
    guard scene == .active else { return }
    openPending()
    generation = UUID()
  }

  private func reconcile() async {
    guard scene == .active else { return }
    let records = records
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    let pending = await center.pendingNotificationRequests()
    let delivered = await center.deliveredNotifications()
    guard !Task.isCancelled, records.owner == store.profile.identityFingerprint else { return }
    let pendingIDs = Set(pending.compactMap { GalaxySSIHealthReviewDelivery.token($0.identifier) })
    let deliveredIDs = Set(delivered.compactMap { GalaxySSIHealthReviewDelivery.token($0.request.identifier) })
    let permitted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    guard let desired = try? records.reconcileReviewDelivery(now: Date(), calendar: .autoupdatingCurrent,
      permitted: permitted, scheduled: pendingIDs, delivered: deliveredIDs) else { return }
    let keep = Set(desired.map(\.token))
    center.removePendingNotificationRequests(withIdentifiers: pendingIDs.subtracting(keep).map { GalaxySSIHealthReviewDelivery.prefix + $0.uuidString })
    center.removeDeliveredNotifications(withIdentifiers: deliveredIDs.subtracting(keep).map { GalaxySSIHealthReviewDelivery.prefix + $0.uuidString })
    for ticket in desired where !pendingIDs.contains(ticket.token) && !deliveredIDs.contains(ticket.token) &&
      !(ticket.submitted && ticket.due <= Date()) {
      guard !Task.isCancelled else { return }
      let content = UNMutableNotificationContent()
      content.title = t("notification_title", "GalaxySSI reminder")
      content.body = t("notification_body", "Open GalaxySSI to review.")
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, ticket.due.timeIntervalSinceNow), repeats: false)
      do {
        try await center.add(UNNotificationRequest(identifier: ticket.identifier, content: content, trigger: trigger))
        try records.markReviewDeliverySubmitted(ticket)
      } catch { center.removePendingNotificationRequests(withIdentifiers: [ticket.identifier]) }
    }
  }

  private func openPending() {
    let defaults = UserDefaults.standard
    let key = GalaxySSIHealthReviewDelivery.pendingKey
    guard let raw = defaults.string(forKey: key), let token = UUID(uuidString: raw) else { return }
    defaults.removeObject(forKey: key)
    let records = records
    guard let archive = try? records.load(), let state = archive.reviewReminderState,
          let entry = state.deliveries?.first(where: { $0.value.token == token }),
          let job = GalaxySSIHealthReviewReminders.deliveryJobs(in: archive).first(where: { $0.key == entry.key }),
          state.notificationPreferences?.allows(job, reviewEnabled: state.enabled) == true,
          state.actions[job.key]?.hides(at: Date()) != true else { return }
    let original: GalaxySSIHealthOriginalStore.Original?
    if job.kind == .report {
      let originals = GalaxySSIHealthOriginalStore(owner: records.owner, secrets: records.secrets)
      guard let item = try? originals.list().originals.first(where: { $0.id == job.target }) else { return }
      original = item
    } else { original = nil }
    destination = .init(records: records, job: job, original: original)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.review_reminder." + key, fallback: fallback, language: language)
  }
}
