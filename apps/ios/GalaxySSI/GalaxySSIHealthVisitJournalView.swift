import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthVisitJournalView: View {
  typealias Journal = GalaxySSIHealthVisitJournal
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @EnvironmentObject private var store: GalaxySSIStore
  let records: GalaxySSIHealthRecords
  let concern: UUID
  let metric: GalaxySSIHealthMetric
  let visit: UUID

  @State private var reviewEligible = false
  @State private var reviewEnabled = false
  @State private var reviewReminder: GalaxySSIHealthCareFollowUp.Reminder?
  @State private var reviewTime: Date?
  @State private var reviewConfirmation = false
  @State private var cancellingReview = false
  @State private var reviewFailed = false
  @State private var visibilityID = UUID()
  @State private var journalVisible = false

  @State private var page: Journal.Page?
  @State private var rows: [Journal.Receipt] = []
  @State private var editor: Journal.Input?
  @State private var operation = UUID()
  @State private var deleting = false
  @State private var saving = false
  @State private var failed = false
  @State private var invalid = false

  var body: some View {
    NavigationView {
      Group {
        if !canRead { Color.clear }
        else if let editor {
          edit(Binding(get: { self.editor ?? editor }, set: { self.editor = $0 }))
        } else { journal }
      }
      .navigationTitle(t("title", "Post-visit journal"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          if editor != nil { Button(t("cancel", "Cancel")) { editor = nil; invalid = false } }
          else { Button(t("done", "Done")) { dismiss() } }
        }
        ToolbarItem(placement: .confirmationAction) {
          if editor != nil { Button(t("save", "Save"), action: save) }
        }
      }
    }
    .navigationViewStyle(.stack)
    .task { load() }
    .task(id: page?.expires) {
      guard let expires = page?.expires else { return }
      let seconds = max(0, min(Journal.lifetime, expires.timeIntervalSinceNow))
      do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } catch { return }
      if !Task.isCancelled, page?.expires == expires { clear(failed: true) }
    }
    .onChange(of: scene) { if $0 == .active { reload() } else { clear() } }
    .onChange(of: store.profile.identityFingerprint) { _ in reload() }
    .onChange(of: editor != nil) { _ in updateReviewVisibility() }
    .onDisappear { clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in clear(failed: true) }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { change in
      if !saving, change.object as? String == records.owner { reload() }
    }
  }

  private var journal: some View {
    List {
      if let page {
        Section {
          if let entry = page.entry {
            Text(entry.goal).font(.headline)
            Text(stateTitle(entry.state))
            if entry.visitRevision != page.scope.visit.revision {
              Text(t("visit_changed", "The visit record changed. Review the goal against the updated visit."))
                .foregroundColor(.secondary)
            }
          }
          Text(t("notice", "Self-reported notes only. Journal changes do not alter treatment or clinical status."))
            .font(.footnote).foregroundColor(.secondary)
        }
        if reviewEligible { reviewSection }
        let commands = Journal.commands(page.entry?.state, attended: page.scope.visit.details.state == .attended)
        if let primary = commands.first {
          Button(commandTitle(primary)) { begin(primary) }.buttonStyle(.borderedProminent)
          ForEach(commands.dropFirst()) { command in
            Button(commandTitle(command)) { begin(command) }
          }
        }
        if page.entry != nil {
          Section(t("history", "Journal history")) {
            ForEach(rows) { receipt in
              DisclosureGroup {
                entryDetails(receipt.input)
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(commandTitle(receipt.input.kind))
                  Text(receipt.recordedAt, format: .dateTime).font(.footnote).foregroundColor(.secondary)
                }
              }
            }
            if page.next != nil { Button(t("more", "Show more")) { load(append: true) } }
          }
          Button(t("delete", "Delete journal"), role: .destructive) { deleting = true }
        }
      }
      if failed {
        Text(t("unavailable", "The visit changed or the journal is unavailable.")).foregroundColor(.secondary)
        Button(t("reload", "Reload"), action: reload)
      }
    }
    .confirmationDialog(t("delete_confirm", "Delete this journal and its history?"), isPresented: $deleting,
      titleVisibility: .visible) {
      Button(t("delete", "Delete journal"), role: .destructive, action: delete)
    }
    .onAppear { journalVisible = true; updateReviewVisibility() }
    .onDisappear { journalVisible = false; updateReviewVisibility() }
  }

  private var reviewSection: some View {
    Section(reviewText("title", "Post-visit review")) {
      if let reminder = reviewReminder {
        Text(reminder.requestedAt, format: .dateTime)
        if let scheduled = reminder.submittedFor, abs(scheduled.timeIntervalSince(reminder.requestedAt)) >= 60 {
          Text(reviewText("registered", "Registered notification time")).font(.caption).foregroundColor(.secondary)
          Text(scheduled, format: .dateTime)
        }
      }
      if reviewEnabled {
        if let time = reviewTime {
          DatePicker(reviewText("time", "Review date and time"),
            selection: Binding(get: { reviewTime ?? time }, set: { reviewTime = $0 }),
            in: Date()..., displayedComponents: [.date, .hourAndMinute])
          Button(reviewText("continue", "Review selected time")) {
            cancellingReview = false
            reviewConfirmation = true
          }.disabled(time <= Date())
          Button(t("cancel", "Cancel")) { reviewTime = nil }
        } else {
          Button(reviewReminder == nil ? reviewText("schedule", "Schedule review reminder") :
            reviewText("change", "Change reminder time")) {
            reviewFailed = false
            reviewTime = max(reviewReminder?.requestedAt ?? .distantPast, Date().addingTimeInterval(3_600))
          }
          if reviewReminder != nil {
            Button(reviewText("cancel", "Cancel reminder"), role: .destructive) {
              cancellingReview = true
              reviewConfirmation = true
            }
          }
        }
      } else {
        NavigationLink(reviewText("settings", "Health reminder settings")) {
          GalaxySSIHealthReviewReminderView(records: records)
        }
      }
      if reviewFailed { Text(reviewText("failed", "Could not update the review reminder.")).foregroundColor(.secondary) }
    }
    .alert(cancellingReview ? reviewText("cancel", "Cancel reminder") :
      reviewText("confirm_title", "Confirm review reminder"), isPresented: $reviewConfirmation) {
      if cancellingReview {
        Button(reviewText("cancel", "Cancel reminder"), role: .destructive, action: commitReview)
        Button(reviewText("keep", "Keep reminder"), role: .cancel) {}
      } else {
        Button(reviewText("confirm", "Confirm reminder"), action: commitReview)
        Button(t("cancel", "Cancel"), role: .cancel) {}
      }
    } message: {
      if !cancellingReview, let time = reviewTime {
        Text(time, format: .dateTime) + Text("\n" + reviewText("notice",
          "This is a reminder to review your journal, not a treatment instruction."))
      }
    }
  }

  private func reviewText(_ key: String, _ fallback: String) -> String {
    GalaxySSIHealthCareFollowUp.JournalReview.text(key, fallback, language)
  }

  private func updateReviewVisibility() {
    GalaxySSIHealthCareFollowUp.JournalVisibility.shared.update(visibilityID,
      reminder: canRead && journalVisible && editor == nil ? reviewReminder : nil)
  }

  private func commitReview() {
    guard canRead, let page, !saving else { return }
    saving = true
    defer { saving = false }
    do {
      if cancellingReview, let reminder = reviewReminder {
        try records.cancelLocalCareFollowUp(reminder)
      } else if !cancellingReview, let reviewTime {
        try records.scheduleVisitReview(page, replacing: reviewReminder?.id, at: reviewTime)
      } else { return }
      reload()
    } catch {
      reload()
      reviewFailed = true
    }
  }

  private func edit(_ draft: Binding<Journal.Input>) -> some View {
    Form {
      Section(commandTitle(draft.wrappedValue.kind)) {
        if draft.wrappedValue.kind == .start || draft.wrappedValue.kind == .review {
          TextField(t("goal", "Goal"), text: draft.goal)
        }
        if draft.wrappedValue.kind == .checkIn {
          TextField(t("feelings", "Physical feelings"), text: draft.feelings)
          TextField(t("function", "Daily function"), text: draft.function)
          TextField(t("sleep", "Sleep"), text: draft.sleep)
          TextField(t("barriers", "Barriers"), text: draft.barriers)
          Toggle(t("needs_review", "Request a review"), isOn: draft.needsReview)
        }
        if draft.wrappedValue.kind == .review {
          Picker(t("decision", "Review decision"), selection: Binding(
            get: { draft.wrappedValue.decision ?? .keep }, set: { draft.wrappedValue.decision = $0 })) {
            ForEach(Journal.Decision.allCases) { decision in Text(decisionTitle(decision)).tag(decision) }
          }
        }
        Text(t("note", "Note"))
        TextEditor(text: draft.note).frame(minHeight: 88).accessibilityLabel(t("note", "Note"))
      }
      if invalid {
        Text(t("invalid", "Enter the required fields within the allowed length.")).foregroundColor(.secondary)
      }
    }
  }

  @ViewBuilder private func entryDetails(_ input: Journal.Input) -> some View {
    forField(t("goal", "Goal"), input.goal)
    forField(t("feelings", "Physical feelings"), input.feelings)
    forField(t("function", "Daily function"), input.function)
    forField(t("sleep", "Sleep"), input.sleep)
    forField(t("barriers", "Barriers"), input.barriers)
    forField(t("note", "Note"), input.note)
    if let decision = input.decision { Text(decisionTitle(decision)) }
    if input.needsReview { Text(t("needs_review", "Request a review")) }
  }

  @ViewBuilder private func forField(_ label: String, _ value: String) -> some View {
    if !value.isEmpty {
      VStack(alignment: .leading, spacing: 3) {
        Text(label).font(.footnote).foregroundColor(.secondary)
        Text(value).textSelection(.enabled)
      }
    }
  }

  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }
  private func t(_ key: String, _ fallback: String) -> String { Journal.text(key, fallback, language) }
  private func commandTitle(_ kind: Journal.Kind) -> String {
    switch kind {
    case .start: return t("start", "Start journal")
    case .checkIn: return t("check_in", "Record check-in")
    case .review: return t("review", "Review goal")
    case .pause: return t("pause", "Pause journal")
    case .resume: return t("resume", "Resume for review")
    case .archive: return t("archive", "Archive journal")
    case .reopen: return t("reopen", "Reopen for review")
    }
  }
  private func stateTitle(_ state: Journal.State) -> String {
    switch state {
    case .active: return t("state_active", "Active")
    case .review: return t("state_review", "Review pending")
    case .paused: return t("state_paused", "Paused")
    case .archived: return t("state_archived", "Archived")
    }
  }
  private func decisionTitle(_ decision: Journal.Decision) -> String {
    switch decision {
    case .keep: return t("keep", "Continue this journal")
    case .discussChange: return t("discuss_change", "Discuss a change")
    case .discussMaintenance: return t("discuss_maintenance", "Discuss maintenance")
    }
  }

  private func clear(failed: Bool = false) {
    page = nil; rows = []; editor = nil; operation = UUID(); deleting = false; invalid = false; self.failed = failed
    reviewReminder = nil; reviewEligible = false; reviewEnabled = false; reviewTime = nil
    reviewConfirmation = false; cancellingReview = false; reviewFailed = false
    GalaxySSIHealthCareFollowUp.JournalVisibility.shared.update(visibilityID, reminder: nil)
  }
  private func reload() { clear(); load() }
  private func load(append: Bool = false) {
    guard canRead else { clear(); return }
    if append && page?.next == nil { return }
    do {
      let loaded = try records.visitJournal(concern: concern, metric: metric, visit: visit,
        before: append ? page?.next : nil, expected: append ? page : nil)
      let review = try records.visitReviewStatus(loaded)
      rows = (append ? rows : []) + loaded.rows
      page = loaded; failed = false
      reviewEligible = review.eligible; reviewEnabled = review.enabled; reviewReminder = review.reminder
      updateReviewVisibility()
    } catch { clear(failed: true) }
  }
  private func begin(_ kind: Journal.Kind) {
    guard canRead, let page, Date() < page.expires else { clear(failed: true); return }
    operation = UUID()
    editor = .init(kind: kind, goal: kind == .review ? page.entry?.goal ?? "" : "",
      decision: kind == .review ? .keep : nil)
  }
  private func save() {
    guard canRead, let page, let editor, !saving else { return }
    saving = true
    defer { saving = false }
    do {
      _ = try records.saveVisitJournal(editor, operation: operation, expected: page)
      reload()
    } catch GalaxySSIHealthRecords.Failure.invalid { invalid = true }
    catch { clear(failed: true) }
  }
  private func delete() {
    guard canRead, let page, !saving else { return }
    saving = true
    defer { saving = false }
    do { try records.deleteVisitJournal(page); reload() }
    catch { clear(failed: true) }
  }
}
