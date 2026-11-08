import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthCareFollowUpsSection: View {
  let records: GalaxySSIHealthRecords
  let concernID: UUID
  let metric: GalaxySSIHealthMetric

  var body: some View {
    GalaxySSIHealthCareAgendaRows(records: records, filter: nil, scope: .init(concern: concernID, metric: metric))
  }
}

@MainActor
struct GalaxySSIHealthCareAgendaView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var filter = GalaxySSIHealthCareAgenda.Filter.today
  let records: GalaxySSIHealthRecords

  var body: some View {
    List {
      Picker(t("title", "Health Actions"), selection: $filter) {
        Text(t("today", "Today")).tag(GalaxySSIHealthCareAgenda.Filter.today)
        Text(t("later", "Later")).tag(GalaxySSIHealthCareAgenda.Filter.later)
        Text(t("review", "Review")).tag(GalaxySSIHealthCareAgenda.Filter.review)
        Text(t("recorded", "Recorded")).tag(GalaxySSIHealthCareAgenda.Filter.recorded)
      }.pickerStyle(.segmented)
      GalaxySSIHealthCareAgendaRows(records: records, filter: filter, scope: nil)
    }
    .navigationTitle(t("title", "Health Actions"))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.agenda." + key, fallback: fallback, language: language)
  }
}

@MainActor
private struct GalaxySSIHealthCareAgendaRows: View {
  typealias Agenda = GalaxySSIHealthCareAgenda
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  let records: GalaxySSIHealthRecords
  let filter: Agenda.Filter?
  let scope: Agenda.Scope?
  @State private var page: Agenda.Page?
  @State private var cursors: [Agenda.Cursor] = []
  @State private var editor: Editor?
  @State private var cancelling: GalaxySSIHealthCareFollowUp.Reminder?
  @State private var failed = false
  @State private var disallowed = false

  private struct Editor: Identifiable {
    let id = UUID()
    let item: Agenda.Item
    let outcome: Bool
  }

  var body: some View {
    Group {
      if canRead {
        if let page, filter != nil || !page.items.isEmpty {
          Section(filter == nil ? t("title", "Action follow-up") : agenda("title", "Health Actions")) {
            if page.items.isEmpty { Text(agenda("empty", "No actions in this view")).foregroundColor(.secondary) }
            if !page.remindersEnabled, page.items.contains(where: { $0.bucket == .planned }) {
              NavigationLink(t("settings", "Health review notification settings")) {
                GalaxySSIHealthReviewReminderView(records: records)
              }
            }
            ForEach(page.items) { item in row(item, remindersEnabled: page.remindersEnabled) }
            if !cursors.isEmpty || page.next != nil {
              HStack {
                Button(agenda("previous", "Previous")) {
                  if !cursors.isEmpty { cursors.removeLast(); reload() }
                }.disabled(cursors.isEmpty)
                Spacer()
                Button(agenda("next", "Next")) {
                  if let next = page.next { cursors.append(next); reload() }
                }.disabled(page.next == nil)
              }.buttonStyle(.borderless)
            }
          }
        }
        if disallowed && filter != nil {
          Text(agenda("disabled", "Local health review is off.")).foregroundColor(.secondary)
        }
        if failed { Text(t("failed", "The action or reminder could not be updated.")) }
      }
    }
    .onAppear(perform: reset)
    .onDisappear(perform: clear)
    .onChange(of: filter) { _ in reset() }
    .onChange(of: scope) { _ in reset() }
    .onChange(of: scene) { if $0 == .active { reset() } else { clear() } }
    .onChange(of: timeZone) { _ in reset() }
    .onChange(of: store.profile.identityFingerprint) { _ in reset() }
    .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in reset() }
    .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in reset() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reset() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { reset() }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.profileInputsChanged)) {
      if $0.object as? String == records.owner { reset() }
    }
    .sheet(item: $editor) { edit in
      NavigationView {
        GalaxySSIHealthCareFollowUpEditor(records: records, concernID: edit.item.scope.concern, metric: edit.item.scope.metric,
          action: edit.item.action, existing: edit.item.reminder, editingOutcome: edit.outcome)
      }.navigationViewStyle(.stack)
    }
    .confirmationDialog(t("cancel_reminder", "Cancel reminder"),
      isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }), titleVisibility: .visible) {
      Button(t("cancel_reminder", "Cancel reminder"), role: .destructive) {
        guard canRead, let reminder = cancelling else { return }
        cancelling = nil
        do { try records.cancelLocalCareFollowUp(reminder); failed = false }
        catch { failed = true }
      }
    }
  }

  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }

  private func row(_ item: Agenda.Item, remindersEnabled: Bool) -> some View {
    let action = item.action
    return VStack(alignment: .leading, spacing: 7) {
      Text(action.action.description).font(.body.weight(.semibold))
      if scope == nil {
        Text(item.scope.metric.title(language: language)).font(.caption).foregroundColor(.secondary)
      }
      if let proof = action.source.provenance {
        Text(action.source.title).font(.caption).foregroundColor(.secondary)
        Text(proof.quote).font(.caption).textSelection(.enabled)
        Text(proof.retrievedAt, format: .dateTime).font(.caption).foregroundColor(.secondary)
      }
      if let outcome = action.outcome {
        Text(outcome.note)
        Text(outcome.reportedAt, style: .date).font(.caption).foregroundColor(.secondary)
      } else {
        if let reminder = item.reminder {
          Text(t("requested", "Selected reminder time")).font(.caption).foregroundColor(.secondary)
          Text(reminder.requestedAt, format: .dateTime)
          if let scheduled = reminder.submittedFor {
            Text(t("registered", "Registered notification time")).font(.caption).foregroundColor(.secondary)
            Text(scheduled, format: .dateTime)
          }
        } else if let planned = item.plannedAt {
          Text(planned, format: .dateTime).font(.caption).foregroundColor(.secondary)
        }
        if item.bucket == .planned, remindersEnabled {
          Button(item.reminder == nil ? t("schedule", "Schedule reminder") : t("postpone", "Change reminder time")) {
            editor = .init(item: item, outcome: false)
          }.buttonStyle(.borderless)
        }
        if let reminder = item.reminder {
          Button(t("cancel_reminder", "Cancel reminder"), role: .destructive) { cancelling = reminder }
            .buttonStyle(.borderless)
        }
        if item.canRecord {
          Button(t("outcome", "Record outcome")) { editor = .init(item: item, outcome: true) }
            .buttonStyle(.borderless)
        }
        if item.bucket == .review, scope == nil {
          NavigationLink(agenda("open_concern", "Open concern")) {
            GalaxySSIHealthCareDetail(records: records, id: item.scope.concern, metric: item.scope.metric)
          }
        }
      }
    }
  }

  private func reload() {
    guard canRead else { clear(); return }
    var local = calendar
    local.timeZone = timeZone
    do {
      page = try records.localCareAgendaPage(filter: filter, scope: scope, after: cursors.last, calendar: local)
      failed = false
    } catch GalaxySSIHealthRecords.Failure.permission {
      clear()
      disallowed = true
    } catch GalaxySSIHealthRecords.Failure.stale where !cursors.isEmpty {
      reset()
    } catch {
      page = nil
      failed = true
    }
  }

  private func reset() { clear(); reload() }

  private func clear() {
    page = nil; cursors = []; editor = nil; cancelling = nil; failed = false; disallowed = false
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSIHealthCareFollowUpText.text(key, fallback, language: language)
  }

  private func agenda(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.agenda." + key, fallback: fallback, language: language)
  }
}

@MainActor
private struct GalaxySSIHealthCareFollowUpEditor: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let concernID: UUID
  let metric: GalaxySSIHealthMetric
  let action: GalaxySSIHealthCarePlan.AdoptedAction
  let existing: GalaxySSIHealthCareFollowUp.Reminder?
  let editingOutcome: Bool
  @State private var time = Date().addingTimeInterval(3_600)
  @State private var note = ""
  @State private var confirming = false
  @State private var failed = false

  var body: some View {
    Form {
      if canRead {
        Text(action.action.description)
        if editingOutcome {
          TextEditor(text: $note).frame(minHeight: 88).accessibilityLabel(t("outcome", "Record outcome"))
          Button(t("save_outcome", "Save outcome"), action: save).disabled(note.isBlank || note.utf8.count > 2_000)
        } else {
          if let from = action.action.dueFrom, let until = action.action.dueUntil {
            Section(t("clinical_window", "Suggested clinical review window")) {
              Text(from, format: .dateTime)
              Text(until, format: .dateTime)
            }
          }
          DatePicker(t("requested", "Selected reminder time"), selection: $time, in: Date()...)
          Button(t("review_time", "Review reminder time")) { confirming = true }.disabled(time <= Date())
        }
        if failed { Text(t("failed", "The action or reminder could not be updated.")) }
      }
    }
    .navigationTitle(editingOutcome ? t("outcome", "Record outcome") : t("schedule", "Schedule reminder"))
    .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("close", "Close")) { dismiss() } } }
    .onAppear { if let existing, existing.requestedAt > Date() { time = existing.requestedAt } }
    .onChange(of: scene) { if $0 != .active { note = ""; confirming = false; dismiss() } }
    .confirmationDialog(t("confirm", "Confirm reminder"), isPresented: $confirming, titleVisibility: .visible) {
      Button(t("confirm", "Confirm reminder"), action: save)
    } message: { Text(time, format: .dateTime) }
  }

  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }

  private func save() {
    guard canRead else { return }
    do {
      if editingOutcome {
        try records.recordLocalCareOutcome(concernID: concernID, metric: metric, action: action, note: note)
      } else {
        try records.scheduleLocalCareFollowUp(concernID: concernID, metric: metric, actionID: action.id,
          replacing: existing?.id, at: time)
      }
      dismiss()
    } catch { failed = true }
  }
  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthCareFollowUpText.text(key, fallback, language: language) }
}

private enum GalaxySSIHealthCareFollowUpText {
  static func text(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.care_follow_up." + key, fallback: fallback, language: language)
  }
}
