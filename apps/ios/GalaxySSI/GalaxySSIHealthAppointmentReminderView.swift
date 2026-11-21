import SwiftUI
import UIKit
import UserNotifications

@MainActor
struct GalaxySSIHealthAppointmentReminderView: View {
  typealias Appointment = GalaxySSIHealthAppointmentReminder
  let records: GalaxySSIHealthRecords
  let visit: GalaxySSIHealthEncounter.Entry
  let stamp: GalaxySSIHealthEncounter.Stamp
  let language: String
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @State private var reminder: GalaxySSIHealthCareFollowUp.Reminder?
  @State private var editing = false
  @State private var failed = false
  @State private var notifications = false

  var body: some View {
    Section(t("title", "Appointment reminder")) {
      if let reminder {
        Text(state(reminder))
        Text(formatted(reminder.requestedAt)).foregroundColor(.secondary)
        if reminder.appointmentState != .cancelled && reminder.appointmentState != .expired {
          Button(t("cancel_reminder", "Cancel reminder"), role: .destructive) {
            guard accessible else { return }
            do { try records.cancelLocalCareFollowUp(reminder); reload() } catch { failed = true }
          }
        }
      }
      if Appointment.available(visit, now: Date()) {
        Button { editing = true } label: {
          Label(t("set", "Set or change reminder"), systemImage: "bell.badge")
        }
      }
      if !notifications {
        Text(t("in_app", "In-app only. Notifications are off or unavailable.")).foregroundColor(.secondary)
      }
      NavigationLink {
        GalaxySSIHealthRecordingReminderView(records: records, record: { _ in })
      } label: { Text(t("settings", "Notification and quiet-hour settings")) }
      if failed { Text(t("stale", "The visit changed or access is unavailable. Reload the visit.")).foregroundColor(.secondary) }
    }
    .task { await refresh() }
    .onChange(of: scene) { phase in
      if phase != .active { reminder = nil; editing = false; notifications = false }
    }
    .sheet(isPresented: $editing) {
      GalaxySSIHealthAppointmentReminderEditor(visit: visit, previous: reminder, language: language) { date in
        guard accessible else { failed = true; editing = false; return }
        do {
          reminder = try records.saveAppointmentReminder(visit, expected: stamp, previousToken: reminder?.id,
            at: date, confirmed: true)
          editing = false
          failed = false
        } catch { failed = true; editing = false }
      }
    }
  }

  private var accessible: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }

  private func refresh() async {
    guard accessible else { return }
    reload()
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    guard accessible else { reminder = nil; return }
    let allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
    notifications = allowed && ((try? records.load()).flatMap { GalaxySSIHealthRecords.appointmentReminderPreferences($0) } != nil)
  }

  private func reload() {
    guard accessible else { reminder = nil; return }
    do { reminder = try records.appointmentReminder(visit: visit.id); failed = false } catch { failed = true }
  }

  private func state(_ reminder: GalaxySSIHealthCareFollowUp.Reminder) -> String {
    switch reminder.appointmentState ?? .scheduled {
    case .scheduled: return reminder.requestedAt <= Date() ? t("due", "Reminder due") : t("scheduled", "Scheduled")
    case .delivered: return t("delivered", "Delivered")
    case .cancelled: return t("cancelled", "Cancelled")
    case .expired: return t("expired", "Expired")
    }
  }

  private func formatted(_ date: Date) -> String {
    Self.formatted(date, zone: visit.details.zone, language: language)
  }

  static func formatted(_ date: Date, zone: String, language: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language)
    formatter.timeZone = TimeZone(identifier: zone)
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date) + " (" + zone + ")"
  }

  private func t(_ key: String, _ fallback: String) -> String { Appointment.text(key, fallback, language) }
}

@MainActor
private struct GalaxySSIHealthAppointmentReminderEditor: View {
  let visit: GalaxySSIHealthEncounter.Entry
  let language: String
  let save: (Date) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var date: Date
  @State private var confirmed = false
  @State private var offset: Int?

  init(visit: GalaxySSIHealthEncounter.Entry, previous: GalaxySSIHealthCareFollowUp.Reminder?, language: String,
       save: @escaping (Date) -> Void) {
    self.visit = visit; self.language = language; self.save = save
    let proposed = max(Date().addingTimeInterval(60), (visit.details.plannedAt ?? Date()).addingTimeInterval(-3600))
    let initial = previous.flatMap { $0.requestedAt > Date() ? $0.requestedAt : nil } ?? proposed
    _date = State(initialValue: initial)
    _offset = State(initialValue: TimeZone(identifier: visit.details.zone)?.secondsFromGMT(for: initial))
  }

  private var zone: TimeZone { TimeZone(identifier: visit.details.zone) ?? .current }
  private var options: [Date] {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    return GalaxySSIHealthEncounter.possibleTimes(day: date, hour: calendar.component(.hour, from: date),
      minute: calendar.component(.minute, from: date), zone: zone)
  }
  private var resolved: Date? {
    options.count == 1 ? options.first : options.first { zone.secondsFromGMT(for: $0) == offset }
  }
  private var valid: Bool {
    guard let resolved, let planned = visit.details.plannedAt else { return false }
    return TimeZone(identifier: visit.details.zone) != nil && resolved > Date() && resolved < planned
  }

  var body: some View {
    NavigationView {
      Form {
        if let planned = visit.details.plannedAt {
          Text(GalaxySSIHealthAppointmentReminderView.formatted(planned, zone: visit.details.zone, language: language))
        }
        DatePicker(t("time", "Remind me at"), selection: $date, displayedComponents: [.date, .hourAndMinute])
          .environment(\.timeZone, zone)
          .onChange(of: date) { _ in confirmed = false; offset = nil }
        if options.count > 1 {
          Picker(GalaxySSIHealthEncounter.text("offset", "UTC offset", language), selection: $offset) {
            Text(GalaxySSIHealthEncounter.text("choose_offset", "Select an offset", language)).tag(Int?.none)
            ForEach(options, id: \.self) { value in
              Text(GalaxySSIHealthEncounterView.offset(value, zone)).tag(Optional(zone.secondsFromGMT(for: value)))
            }
          }.onChange(of: offset) { _ in confirmed = false }
        }
        if !valid { Text(t("bounds", "Choose a future time before the appointment.")).foregroundColor(.secondary) }
        Toggle(t("confirm", "I confirm this appointment reminder time"), isOn: $confirmed)
        Text(t("notice", "This reminder does not book a visit or change your care plan.")).font(.footnote).foregroundColor(.secondary)
      }
      .navigationTitle(t("title", "Appointment reminder"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button(GalaxySSIHealthEncounter.text("cancel", "Cancel", language)) { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button(GalaxySSIHealthEncounter.text("save", "Save", language)) {
            if confirmed, valid, let resolved { save(resolved) }
          }.disabled(!confirmed || !valid)
        }
      }
    }.navigationViewStyle(.stack)
  }
  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthAppointmentReminder.text(key, fallback, language) }
}
