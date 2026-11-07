import SwiftUI

@MainActor
struct GalaxySSIHealthCareFollowUpsSection: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let concernID: UUID
  let metric: GalaxySSIHealthMetric
  @State private var actions: [GalaxySSIHealthCarePlan.AdoptedAction] = []
  @State private var reminders: [String: GalaxySSIHealthCareFollowUp.Reminder] = [:]
  @State private var eligible = Set<String>()
  @State private var preferencesEnabled = false
  @State private var editor: Editor?
  @State private var cancelling: GalaxySSIHealthCareFollowUp.Reminder?
  @State private var failed = false
  @State private var limit = 20

  private struct Editor: Identifiable {
    enum Kind { case schedule, outcome }
    let id = UUID()
    let kind: Kind
    let action: GalaxySSIHealthCarePlan.AdoptedAction
    let existing: GalaxySSIHealthCareFollowUp.Reminder?
  }

  var body: some View {
    Group {
      if scene == .active, !actions.isEmpty {
        Section(t("title", "Action follow-up")) {
          if !preferencesEnabled, !eligible.isEmpty {
            NavigationLink(t("settings", "Health review notification settings")) {
              GalaxySSIHealthReviewReminderView(records: records)
            }
          }
          ForEach(actions.prefix(limit), content: row)
          if actions.count > limit { Button(t("more", "Show more")) { limit += 20 } }
          if failed { Text(t("failed", "The action or reminder could not be updated.")) }
        }
      }
    }
    .onAppear(perform: reload)
    .onChange(of: scene) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
    .sheet(item: $editor) { edit in
      NavigationView {
        GalaxySSIHealthCareFollowUpEditor(records: records, concernID: concernID, metric: metric,
          action: edit.action, existing: edit.existing, editingOutcome: edit.kind == .outcome)
      }.navigationViewStyle(.stack)
    }
    .confirmationDialog(t("cancel_reminder", "Cancel reminder"),
      isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }), titleVisibility: .visible) {
      Button(t("cancel_reminder", "Cancel reminder"), role: .destructive) {
        guard scene == .active, let reminder = cancelling else { return }
        do { try records.cancelLocalCareFollowUp(reminder); failed = false }
        catch { failed = true }
        cancelling = nil
      }
    }
  }

  private func row(_ action: GalaxySSIHealthCarePlan.AdoptedAction) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(action.action.description).font(.body.weight(.semibold))
      if let proof = action.source.provenance {
        Text(action.source.title).font(.caption).foregroundColor(.secondary)
        Text(proof.quote).font(.caption).textSelection(.enabled)
        Text(proof.retrievedAt, format: .dateTime).font(.caption).foregroundColor(.secondary)
      }
      if let outcome = action.outcome {
        Text(outcome.note)
        Text(outcome.reportedAt, style: .date).font(.caption).foregroundColor(.secondary)
      } else {
        if let reminder = reminders[action.id] {
          Text(t("requested", "Selected reminder time")).font(.caption).foregroundColor(.secondary)
          Text(reminder.requestedAt, format: .dateTime)
          if let scheduled = reminder.submittedFor {
            Text(t("registered", "Registered notification time")).font(.caption).foregroundColor(.secondary)
            Text(scheduled, format: .dateTime)
          }
        }
        if eligible.contains(action.id), preferencesEnabled {
          Button(reminders[action.id] == nil ? t("schedule", "Schedule reminder") : t("postpone", "Change reminder time")) {
            editor = .init(kind: .schedule, action: action, existing: reminders[action.id])
          }.buttonStyle(.borderless)
        }
        if let reminder = reminders[action.id] {
          Button(t("cancel_reminder", "Cancel reminder"), role: .destructive) { cancelling = reminder }
            .buttonStyle(.borderless)
        }
        Button(t("outcome", "Record outcome")) { editor = .init(kind: .outcome, action: action, existing: nil) }
          .buttonStyle(.borderless)
      }
    }
  }

  private func reload() {
    guard scene == .active, let archive = try? records.load(), archive.localCareAllowed == true,
          let concern = archive.localCare?.current[metric.rawValue], concern.id == concernID, concern.stage != .closed else {
      actions = []; reminders = [:]; eligible = []; preferencesEnabled = false
      editor = nil; cancelling = nil
      return
    }
    actions = concern.adoptedActions ?? []
    eligible = Set(actions.compactMap { action in
      GalaxySSIHealthRecords.careFollowUpIsCurrent(concernID: concernID, metric: metric, actionID: action.id,
        archive: archive) ? action.id : nil
    })
    reminders = (archive.localCareFollowUps ?? [:]).filter { $0.value.concernID == concernID && eligible.contains($0.key) }
    preferencesEnabled = GalaxySSIHealthRecords.careFollowUpPreferences(archive) != nil
    if let editor, !actions.contains(editor.action) || (editor.kind == .schedule &&
       (!eligible.contains(editor.action.id) || !preferencesEnabled)) { self.editor = nil }
  }

  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthCareFollowUpText.text(key, fallback, language: language) }
}

@MainActor
private struct GalaxySSIHealthCareFollowUpEditor: View {
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
      if scene == .active {
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

  private func save() {
    guard scene == .active else { return }
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
