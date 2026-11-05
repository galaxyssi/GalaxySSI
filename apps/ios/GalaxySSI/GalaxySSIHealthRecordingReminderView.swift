import SwiftUI
import UIKit
import UserNotifications

@MainActor
struct GalaxySSIHealthRecordingNotificationLifecycle: ViewModifier {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let store: GalaxySSIStore
  @State private var generation = UUID()

  func body(content: Content) -> some View {
    content
      .onChange(of: scene) { if $0 == .active { generation = UUID() } }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
        generation = UUID()
      }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecordingReminders.changed)) {
        if $0.object as? String == store.profile.identityFingerprint { generation = UUID() }
      }
      .task(id: generation) { await schedule() }
  }

  private func schedule() async {
    guard scene == .active else { return }
    let owner = store.profile.identityFingerprint
    let records = GalaxySSIHealthRecords(owner: owner, secrets: store.secrets)
    let center = UNUserNotificationCenter.current()
    let authorization = await center.notificationSettings().authorizationStatus
    let pending = await center.pendingNotificationRequests().filter {
      $0.identifier.hasPrefix(GalaxySSIHealthRecordingReminders.prefix)
    }
    let delivered = await center.deliveredNotifications().filter {
      $0.request.identifier.hasPrefix(GalaxySSIHealthRecordingReminders.prefix)
    }
    guard !Task.isCancelled, owner == store.profile.identityFingerprint else { return }
    let now = Date()
    let calendar = Calendar.autoupdatingCurrent
    guard let ledger = try? records.loadRecordingReminders(at: now, calendar: calendar) else { return }
    let upcoming = authorization == .authorized || authorization == .provisional
      ? ledger.upcoming(at: now, calendar: calendar) : []
    let desired = Set(upcoming.map { GalaxySSIHealthRecordingReminders.notificationID(owner: owner, day: $0.0) })
    center.removePendingNotificationRequests(withIdentifiers: pending.filter { !desired.contains($0.identifier) }.map(\.identifier))
    let handled = Set(ledger.history.filter { $0.completedAt != nil || $0.disabled ||
      ($0.snoozedUntil ?? .distantPast) > now }.map {
        GalaxySSIHealthRecordingReminders.notificationID(owner: owner, day: $0.day)
      })
    center.removeDeliveredNotifications(withIdentifiers: delivered.map(\.request.identifier).filter {
      !ledger.settings.enabled || !ledger.settings.notifications || handled.contains($0)
    })
    for (day, due) in upcoming {
      guard !Task.isCancelled else { return }
      let id = GalaxySSIHealthRecordingReminders.notificationID(owner: owner, day: day)
      if let previous = pending.first(where: { $0.identifier == id })?.trigger as? UNCalendarNotificationTrigger,
         let date = previous.nextTriggerDate(), abs(date.timeIntervalSince(due)) < 1 { continue }
      let content = UNMutableNotificationContent()
      content.title = GalaxySSIHealthRecordingReminderView.text("notification_title", "GalaxySSI reminder", language: language)
      content.body = GalaxySSIHealthRecordingReminderView.text("notification_body", "Open GalaxySSI to review.", language: language)
      var date = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: due)
      date.timeZone = calendar.timeZone
      let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: false)
      do {
        try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        let fresh = try records.load().recordingReminders
        if fresh?.settings.version != ledger.settings.version || fresh?.history != ledger.history {
          center.removePendingNotificationRequests(withIdentifiers: [id])
        }
      } catch { continue }
    }
  }
}

@MainActor
struct GalaxySSIHealthRecordingReminderView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let records: GalaxySSIHealthRecords
  let record: (GalaxySSIHealthMetric) -> Void
  @State private var ledger = GalaxySSIHealthRecordingReminders.Ledger()
  @State private var draft = GalaxySSIHealthRecordingReminders.Settings()
  @State private var filter = Filter.pending
  @State private var limit = 30
  @State private var failed = false
  @State private var incidents: [GalaxySSIHealthKitSync.Incident] = []
  @State private var confirmingIncident = false
  @State private var incidentToAcknowledge: GalaxySSIHealthKitSync.Incident?

  private enum Filter: String, CaseIterable { case pending, handled, all }

  var body: some View {
    List {
      if scene == .active {
        Section(t("preferences", "Recording preferences")) {
          Toggle(t("enabled", "Daily recording plan"), isOn: $draft.enabled)
          if draft.enabled {
            Picker(t("category", "Measurement"), selection: $draft.category) {
              ForEach(GalaxySSIHealthRecordingReminders.Category.allCases) { item in
                Text(item.metric.title(language: language)).tag(item)
              }
            }
            DatePicker(t("time", "Daily time"), selection: timeBinding, displayedComponents: .hourAndMinute)
            Toggle(t("notifications", "System notifications"), isOn: $draft.notifications)
            if draft.notifications {
              hourPicker(t("quiet_start", "Quiet hours begin"), value: $draft.quietStart)
              hourPicker(t("quiet_end", "Quiet hours end"), value: $draft.quietEnd)
            }
            Toggle(t("pause", "Pause for 24 hours"), isOn: Binding(
              get: { (draft.pausedUntil ?? .distantPast) > Date() },
              set: { draft.pausedUntil = $0 ? Date().addingTimeInterval(86_400) : nil }))
          }
          Button(t("save", "Save preferences"), action: save)
        }
        Section {
          Picker(t("filter", "Filter"), selection: $filter) {
            Text(t("pending", "Pending")).tag(Filter.pending)
            Text(t("handled", "Handled")).tag(Filter.handled)
            Text(t("all", "All")).tag(Filter.all)
          }.pickerStyle(.segmented)
        }
        Section(t("history", "Recording reminders")) {
          let items = ledger.history.filter {
            let handled = $0.completedAt != nil || $0.disabled || expired($0)
            return filter == .all || (filter == .handled ? handled : !handled)
          }
          if items.isEmpty { Text(t("empty", "No reminders")).foregroundColor(.secondary) }
          ForEach(items.prefix(limit)) { item in
            NavigationLink {
              detail(item.day)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(item.category.metric.title(language: language))
                Text(item.scheduledAt, style: .date).foregroundColor(.secondary)
                Text(status(item)).foregroundColor(.secondary)
              }
            }
          }
          if items.count > limit { Button(t("more", "Show more")) { limit += 30 } }
        }
        connections
        if failed { Text(t("failed", "The reminder changed or could not be saved.")).foregroundColor(.secondary) }
      }
    }
    .navigationTitle(t("title", "Health Recording Reminders"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { reload(resetDraft: true); reloadIncidents() }
    .onChange(of: scene) {
      if $0 == .active { reload(resetDraft: true); reloadIncidents() }
      else {
        ledger = .init(); draft = .init(); incidents = []
        confirmingIncident = false; incidentToAcknowledge = nil
      }
    }
    .onChange(of: filter) { _ in limit = 30 }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.syncIncidentsChanged)) {
      if $0.object as? String == records.owner { reloadIncidents() }
    }
    .confirmationDialog(t("incident_confirm", "Acknowledge this sync failure?"),
                        isPresented: $confirmingIncident, titleVisibility: .visible, presenting: incidentToAcknowledge) { incident in
      Button(t("incident_acknowledge", "Acknowledge")) { acknowledge(incident) }
    }
  }

  private var connections: some View {
    Section(t("connections", "Data Connections")) {
      let visible = incidents.filter { filter == .all || (filter == .handled ? $0.handled : !$0.handled) }
      if visible.isEmpty { Text(t("incidents_empty", "No sync incidents")).foregroundColor(.secondary) }
      ForEach(visible) { incident in
        NavigationLink {
          GalaxySSIHealthKitSyncView(records: records, focusedScope: incident.scope)
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(incident.scope.metric.title(language: language))
            Text(incidentReason(incident.status)).foregroundColor(.secondary)
            if let failedAt = incident.failedAt {
              incidentDate(t("incident_failed_at", "Last failure"), at: failedAt)
            }
            if let lastSuccess = incident.lastSuccess {
              incidentDate(t("incident_last_success", "Last successful sync before failure"), at: lastSuccess)
            }
            if let resolvedAt = incident.resolvedAt {
              incidentDate(t("incident_resolved", "Resolved"), at: resolvedAt)
            } else if let acknowledgedAt = incident.acknowledgedAt {
              incidentDate(t("incident_acknowledged", "Acknowledged"), at: acknowledgedAt)
            }
          }
        }
        if !incident.handled {
          Button {
            incidentToAcknowledge = incident
            confirmingIncident = true
          } label: {
            Label(t("incident_acknowledge", "Acknowledge"), systemImage: "checkmark.circle")
          }
        }
      }
    }
  }

  private func incidentDate(_ title: String, at date: Date) -> some View {
    Text(title + ": " + date.formatted(date: .abbreviated, time: .shortened)).foregroundColor(.secondary)
  }

  private func incidentReason(_ status: GalaxySSIHealthKitSync.Status) -> String {
    let fallback: String
    switch status {
    case .permission: fallback = "System access required"
    case .unavailable: fallback = "Apple Health is unavailable"
    default: fallback = "Sync failed; local copies were kept"
    }
    return GalaxySSILocalization.string("galaxyssi.health.healthkit_sync." + status.rawValue,
                                        fallback: fallback, language: language)
  }

  private func reloadIncidents() {
    guard scene == .active else { return }
    do { incidents = try records.load().syncIncidents }
    catch { incidents = []; failed = true }
  }

  private func acknowledge(_ incident: GalaxySSIHealthKitSync.Incident) {
    guard scene == .active else { return }
    do { try records.acknowledgeHealthKitIncident(incident); reloadIncidents() }
    catch { reloadIncidents(); failed = true }
    incidentToAcknowledge = nil
  }

  private var timeBinding: Binding<Date> {
    Binding(get: {
      Calendar.current.date(bySettingHour: draft.hour, minute: draft.minute, second: 0, of: Date()) ?? Date()
    }, set: {
      let date = Calendar.current.dateComponents([.hour, .minute], from: $0)
      draft.hour = date.hour ?? 9
      draft.minute = date.minute ?? 0
    })
  }

  private func hourPicker(_ title: String, value: Binding<Int>) -> some View {
    Picker(title, selection: value) {
      ForEach(0..<24) { hour in Text(String(format: "%02d:00", hour)).tag(hour) }
    }
  }

  private func detail(_ day: String) -> some View {
    List {
      if scene == .active, let item = ledger.history.first(where: { $0.day == day }) {
        Text(item.category.metric.title(language: language))
        Text(item.scheduledAt, format: .dateTime)
        Text(item.zone).foregroundColor(.secondary)
        Text(status(item))
        if ledger.settings.enabled && item.completedAt == nil && !item.disabled && !expired(item) {
          Button(t("record", "Record measurement")) { record(item.category.metric) }
          Button(t("complete", "Mark complete")) { update(item, complete: true) }
          Button(t("snooze", "Snooze for one hour")) { update(item, complete: false) }
          Button(t("disable", "Disable daily plan"), role: .destructive) {
            var disabled = ledger.settings
            disabled.enabled = false
            do { try records.saveRecordingReminderSettings(disabled, at: Date()); reload(resetDraft: true) }
            catch { failed = true }
          }
        }
      }
    }
    .navigationTitle(t("detail", "Recording Reminder"))
    .onAppear { reload() }
  }

  private func status(_ item: GalaxySSIHealthRecordingReminders.Occurrence) -> String {
    if item.completedAt != nil { return t("completed", "Completed") }
    if item.disabled { return t("disabled", "Disabled") }
    if expired(item) { return t("expired", "Expired") }
    if (item.snoozedUntil ?? .distantPast) > Date() { return t("snoozed", "Snoozed") }
    return t("pending", "Pending")
  }

  private func expired(_ item: GalaxySSIHealthRecordingReminders.Occurrence) -> Bool {
    item.day < GalaxySSIHealthRecordingReminders.Ledger.key(Date(), calendar: .autoupdatingCurrent)
  }

  private func reload(resetDraft: Bool = false) {
    guard scene == .active else { return }
    do {
      ledger = try records.loadRecordingReminders(at: Date(), calendar: .autoupdatingCurrent)
      if resetDraft { draft = ledger.settings }
      failed = false
    } catch { failed = true }
  }

  private func save() {
    do { try records.saveRecordingReminderSettings(draft, at: Date()); reload(resetDraft: true) }
    catch { reload(resetDraft: true); failed = true }
  }

  private func update(_ item: GalaxySSIHealthRecordingReminders.Occurrence, complete: Bool) {
    do { try records.updateRecordingReminder(item, complete: complete, at: Date()); reload() }
    catch { reload(); failed = true }
  }

  private func t(_ key: String, _ fallback: String) -> String { Self.text(key, fallback, language: language) }
  static func text(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.recording_reminder." + key, fallback: fallback, language: language)
  }
}
