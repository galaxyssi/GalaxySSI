import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthEncounterView: View {
  typealias Encounter = GalaxySSIHealthEncounter
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let concern: UUID
  let metric: GalaxySSIHealthMetric
  let entryID: UUID?
  @State private var page: Encounter.Page?
  @State private var rows: [Encounter.Entry] = []
  @State private var editor: Editor?
  @State private var deleting = false
  @State private var saving = false
  @State private var failed = false
  @State private var reloadID = UUID()
  @State private var loadedAt: Date?
  @State private var selectedEntryID: UUID?
  @State private var showingDocuments = false
  @State private var showingInstructions = false
  @State private var showingJournal = false
  @State private var journalAvailable = false

  private struct Editor: Identifiable {
    let id: UUID
    let operation = UUID()
    let entry: Encounter.Entry?
    let stamp: Encounter.Stamp
  }

  init(records: GalaxySSIHealthRecords, concern: UUID, metric: GalaxySSIHealthMetric, entryID: UUID? = nil) {
    self.records = records
    self.concern = concern
    self.metric = metric
    self.entryID = entryID
  }

  var body: some View {
    List {
      if canRead {
        if let page {
          if let entry = page.entry {
            Section { details(entry) }
            Button { showingDocuments = true } label: { Label(t("documents", "Visit documents"), systemImage: "doc.on.doc") }
            Button { showingInstructions = true } label: {
              Label(GalaxySSIHealthInstruction.text("title", "Instruction drafts", language), systemImage: "list.bullet.rectangle")
            }
            if journalAvailable {
              Button { showingJournal = true } label: {
                Label(GalaxySSIHealthVisitJournal.text("title", "Post-visit journal", language), systemImage: "book.closed")
              }
            }
            Section(t("history", "Change history")) {
              ForEach(rows, id: \.revision) { version in
                DisclosureGroup(revision(version)) { details(version) }
              }
              if page.next != nil { Button(t("more", "Show more")) { load(append: true) } }
            }
            Button(t("edit", "Edit visit")) { editor = Editor(id: entry.id, entry: entry, stamp: page.stamp) }
            Button(t("delete", "Delete visit"), role: .destructive) { deleting = true }
          } else {
            Button { editor = Editor(id: UUID(), entry: nil, stamp: page.stamp) } label: {
              Label(t("add", "Add visit"), systemImage: "plus")
            }
            if rows.isEmpty { Text(t("empty", "No visits recorded")).foregroundColor(.secondary) }
            ForEach(rows) { entry in
              Button { selectedEntryID = entry.id } label: {
                HStack {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(entry.details.purpose).foregroundColor(.primary)
                    Text(entry.details.state.title(language)).font(.footnote).foregroundColor(.secondary)
                  }
                  Spacer()
                  Image(systemName: "chevron.right").font(.footnote).foregroundColor(.secondary)
                }
              }
            }
            if page.next != nil { Button(t("more", "Show more")) { load(append: true) } }
          }
        }
        if failed {
          Text(t("stale", "The visit or its source changed, or access is unavailable.")).foregroundColor(.secondary)
          Button(t("retry", "Reload")) { requestLoad() }
        }
      }
    }
    .navigationTitle(entryID == nil ? t("title", "Visit records") : t("detail", "Visit details"))
    .navigationBarTitleDisplayMode(.inline)
    .background {
      NavigationLink(isActive: Binding(get: { selectedEntryID != nil }, set: {
        if !$0 { selectedEntryID = nil }
      })) {
        if let selectedEntryID {
          GalaxySSIHealthEncounterView(records: records, concern: concern, metric: metric, entryID: selectedEntryID)
        }
      } label: { EmptyView() }.hidden()
    }
    .sheet(item: $editor) { edit in
      GalaxySSIHealthEncounterEditor(entry: edit.entry, language: language) { draft in save(draft, editor: edit) }
    }
    .sheet(isPresented: $showingDocuments) {
      if let entryID { GalaxySSIHealthEncounterDocumentsView(records: records, concern: concern, metric: metric, visit: entryID) }
    }
    .sheet(isPresented: $showingInstructions) {
      if let entryID { GalaxySSIHealthInstructionReviewView(records: records, concern: concern, metric: metric, visit: entryID) }
    }
    .sheet(isPresented: $showingJournal) {
      if let entryID { GalaxySSIHealthVisitJournalView(records: records, concern: concern, metric: metric, visit: entryID) }
    }
    .confirmationDialog(t("delete_confirm", "Delete this visit and its change history?"),
                        isPresented: $deleting, titleVisibility: .visible) {
      Button(t("delete", "Delete visit"), role: .destructive, action: delete)
    }
    .task(id: reloadID) { if canRead { load() } }
    .task(id: loadedAt) {
      guard let start = loadedAt else { return }
      do { try await Task.sleep(nanoseconds: 600_000_000_000) } catch { return }
      if !Task.isCancelled, loadedAt == start { clear(failed: true) }
    }
    .onChange(of: scene) { if $0 == .active { requestLoad() } else { clear() } }
    .onChange(of: store.profile.identityFingerprint) { _ in requestLoad() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in clear(failed: true) }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in requestLoad() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { change in
      guard !saving, change.object as? String == records.owner else { return }
      requestLoad()
    }
  }

  @ViewBuilder private func details(_ entry: Encounter.Entry) -> some View {
    Text(entry.details.purpose).font(.headline)
    Text(entry.details.state.title(language))
    if !entry.details.facility.isBlank { Text(entry.details.facility) }
    labeled(t("planned_at", "Planned time"), date(entry.details.plannedAt, zone: entry.details.zone))
    labeled(t("attended_at", "Actual visit time"), date(entry.details.attendedAt, zone: entry.details.zone))
    if let source = entry.source {
      Text(String(format: t("source_revision", "Source measurement revision %lld"), Int64(source.revision)))
        .font(.footnote).foregroundColor(.secondary)
    }
    if !entry.details.note.isBlank { Text(entry.details.note) }
    Text(t("notice", "Self-reported. This is not a hospital booking or a clinical record."))
      .font(.footnote).foregroundColor(.secondary)
  }

  private func labeled(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.footnote).foregroundColor(.secondary)
      Text(value)
    }
  }

  private func revision(_ entry: Encounter.Entry) -> String {
    String(format: t("revision", "Revision %lld"), Int64(entry.revision)) + " · " + date(entry.updated, zone: entry.details.zone)
  }

  private func date(_ value: Date?, zone: String) -> String {
    guard let value, let timeZone = TimeZone(identifier: zone) else { return t("unspecified", "Not set") }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language)
    formatter.timeZone = timeZone
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: value) + " (" + zone + ", " + Self.offset(value, timeZone) + ")"
  }

  static func offset(_ date: Date, _ zone: TimeZone) -> String {
    let seconds = zone.secondsFromGMT(for: date)
    return String(format: "UTC%@%02d:%02d", seconds < 0 ? "-" : "+", abs(seconds) / 3600, abs(seconds) % 3600 / 60)
  }

  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }

  private func t(_ key: String, _ fallback: String) -> String { Encounter.text(key, fallback, language) }

  private func clear(failed: Bool = false) {
    page = nil; rows = []; editor = nil; deleting = false; loadedAt = nil; journalAvailable = false; self.failed = failed
  }

  private func requestLoad() {
    clear()
    reloadID = UUID()
  }

  private func load(append: Bool = false) {
    guard canRead else { clear(); return }
    if append, page?.next == nil { return }
    do {
      let value = try records.localCareEncounterPage(id: concern, metric: metric, entryID: entryID,
        before: append ? page?.next : nil, expected: append ? page?.stamp : nil)
      rows = append ? rows + value.rows : value.rows
      page = value
      journalAvailable = value.entry.map {
        $0.details.state == .attended || records.hasVisitJournal($0.id, stamp: value.stamp)
      } ?? false
      if !append { loadedAt = Date() }
      failed = false
    } catch { clear(failed: true) }
  }

  private func save(_ draft: Encounter.Draft, editor edit: Editor) {
    guard canRead, editor?.operation == edit.operation else { return }
    saving = true
    defer { saving = false }
    do {
      _ = try records.saveLocalCareEncounter(draft, id: edit.id, operation: edit.operation,
        expected: edit.stamp, expectedEntry: edit.entry?.revision)
      requestLoad()
    } catch { clear(failed: true) }
  }

  @Environment(\.dismiss) private var dismiss

  private func delete() {
    guard canRead, let page, let entry = page.entry else { return }
    saving = true
    defer { saving = false }
    do {
      try records.deleteLocalCareEncounter(entry, expected: page.stamp)
      clear()
      dismiss()
    } catch { clear(failed: true) }
  }
}
