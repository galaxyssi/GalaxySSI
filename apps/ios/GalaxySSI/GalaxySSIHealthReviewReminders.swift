import SwiftUI

enum GalaxySSIHealthReviewReminders {
  static let maximumTableDrafts = 12
  static let pageSize = 30

  struct TableDraft: Codable, Identifiable {
    let id: UUID
    var version = UUID()
    let name: String
    let at: Date
    let data: Data
    let mapping: GalaxySSIHealthTableImport.Mapping
    let worksheet: GalaxySSIHealthXLSX.Selection?
    let retainOriginal: Bool
  }

  enum Action: Codable, Equatable {
    case handled
    case snoozed(Date)

    func hides(at now: Date) -> Bool {
      switch self {
      case .handled: return true
      case .snoozed(let until): return now < until
      }
    }
  }

  struct State: Codable {
    struct Entry: Codable {
      let versions: [UUID]
      let action: Action
    }
    var enabled = false
    var actions: [String: Entry] = [:]
    var notificationPreferences: GalaxySSIHealthReviewDelivery.Preferences?
    var deliveries: [String: GalaxySSIHealthReviewDelivery.Ticket]?
  }

  struct Page {
    let jobs: [Job]
    let hasMore: Bool
  }

  struct Job: Identifiable, Equatable {
    enum Kind: String { case report, table }
    let target: UUID
    let kind: Kind
    let versions: [UUID]
    let at: Date
    var key: String { kind.rawValue + ":" + target.uuidString }
    var id: String { key }
  }

  @MainActor
  static func jobs(in archive: GalaxySSIHealthRecords.Archive) -> [Job] {
    let reports = Dictionary(grouping: archive.reportReview ?? []) { $0.source.original }
    var result = reports.map { id, items in
      Job(target: id, kind: .report, versions: items.map(\.version).sorted { $0.uuidString < $1.uuidString },
          at: items.map { $0.stagedAt ?? $0.reading.measuredAt }.max() ?? .distantPast)
    }
    for draft in archive.tableReviews ?? [] {
      result.append(.init(target: draft.id, kind: .table, versions: [draft.version], at: draft.at))
    }
    return result.sorted { ($0.at, $0.key) > ($1.at, $1.key) }
  }

  static func visible(_ jobs: [Job], state: State, now: Date) -> [Job] {
    guard state.enabled else { return [] }
    return jobs.filter {
      guard let entry = state.actions[$0.key], entry.versions == $0.versions else { return true }
      return !entry.action.hides(at: now)
    }
  }

  static func page(_ jobs: [Job], after cursor: Job?, limit: Int = pageSize) -> Page {
    let candidates = jobs.lazy.filter { job in
      guard let cursor else { return true }
      return (job.at, job.key) < (cursor.at, cursor.key)
    }.prefix(limit + 1)
    return Page(jobs: Array(candidates.prefix(limit)), hasMore: candidates.count > limit)
  }
}

@MainActor
struct GalaxySSIHealthReviewReminderView: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  @State private var enabled = false
  @State private var jobs: [GalaxySSIHealthReviewReminders.Job] = []
  @State private var originalNames: [UUID: String] = [:]
  @State private var tableNames: [UUID: String] = [:]
  @State private var hasMore = false
  @State private var wakeAt: Date?
  @State private var failed = false
  @State private var route: Route?

  private struct Route: Identifiable {
    let job: GalaxySSIHealthReviewReminders.Job
    let original: GalaxySSIHealthOriginalStore.Original?
    var id: String { job.id }
  }

  private var originals: GalaxySSIHealthOriginalStore {
    GalaxySSIHealthOriginalStore(owner: records.owner, secrets: records.secrets, restoreRecordsFile: records.isolatedFile)
  }

  var body: some View {
    List {
      if scene == .active {
        Toggle(t("enabled", "Show report and table review reminders"), isOn: Binding(
          get: { enabled }, set: { value in
            do { try records.setReviewRemindersEnabled(value); reload() } catch { failed = true }
          }))
        if enabled {
          GalaxySSIHealthReviewNotificationSettings(records: records)
          if jobs.isEmpty { Text(t("empty", "No pending reviews")).foregroundColor(.secondary) }
          ForEach(jobs) { job in
            VStack(alignment: .leading, spacing: 6) {
              Button { open(job) } label: {
                Label(title(job), systemImage: job.kind == .report ? "doc.text.magnifyingglass" : "tablecells")
              }
              .disabled(job.kind == .report && originalNames[job.target] == nil)
              HStack {
                Button(t("snooze_hour", "Snooze for one hour")) { update(job, .snoozed(Date().addingTimeInterval(3_600))) }
                Spacer()
                Button(t("handled", "Mark handled")) { update(job, .handled) }
              }
              .font(.subheadline)
              .buttonStyle(.borderless)
            }
          }
          if hasMore { Button(t("more", "Show more reviews")) { loadPage(after: jobs.last) } }
        }
        if failed { Text(t("failed", "The review changed or is unavailable.")).foregroundColor(.secondary) }
      }
    }
    .navigationTitle(t("title", "Health Review Reminders"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onChange(of: scene) {
      if $0 == .active { reload() }
      else { jobs = []; originalNames = [:]; tableNames = [:]; hasMore = false; wakeAt = nil; route = nil }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.reviewInputsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
    .task(id: wakeAt) {
      guard let wakeAt else { return }
      do {
        let delay = min(86_400, max(0, wakeAt.timeIntervalSinceNow))
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        try Task.checkCancellation()
        reload()
      } catch {}
    }
    .sheet(item: $route, onDismiss: reload) { destination in
      NavigationView {
        Group {
          if let original = destination.original {
            GalaxySSIHealthReportBatchView(records: records, store: originals, original: original)
          } else {
            GalaxySSIHealthTableImportView(records: records, resumeReviewID: destination.job.target,
                                            resumeReviewVersion: destination.job.versions.first)
          }
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) {
          Button(t("close", "Close")) { route = nil }
        } }
      }
      .navigationViewStyle(.stack)
    }
  }

  private func reload() { loadPage(after: nil) }

  private func loadPage(after cursor: GalaxySSIHealthReviewReminders.Job?) {
    guard scene == .active else { return }
    do {
      let archive = try records.load()
      let state = archive.reviewReminderState ?? .init()
      enabled = state.enabled
      let now = Date()
      let available = GalaxySSIHealthReviewReminders.jobs(in: archive)
      let visible = GalaxySSIHealthReviewReminders.visible(available, state: state, now: now)
      let page = GalaxySSIHealthReviewReminders.page(visible, after: cursor)
      let seen = Set(jobs.map(\.key))
      jobs = cursor == nil ? page.jobs : jobs + page.jobs.filter { !seen.contains($0.key) }
      hasMore = page.hasMore
      wakeAt = enabled ? available.compactMap { job -> Date? in
        guard let entry = state.actions[job.key], entry.versions == job.versions,
              case .snoozed(let date) = entry.action, date > now else { return nil }
        return date
      }.min() : nil
      tableNames = Dictionary(uniqueKeysWithValues: (archive.tableReviews ?? []).map { ($0.id, $0.name) })
      originalNames = jobs.contains { $0.kind == .report }
        ? Dictionary(uniqueKeysWithValues: try originals.list().originals.map { ($0.id, $0.name) }) : [:]
      failed = false
    } catch { jobs = []; originalNames = [:]; tableNames = [:]; hasMore = false; wakeAt = nil; failed = true }
  }

  private func open(_ job: GalaxySSIHealthReviewReminders.Job) {
    do {
      guard scene == .active else { return }
      let archive = try records.load()
      guard GalaxySSIHealthReviewReminders.visible(
        GalaxySSIHealthReviewReminders.jobs(in: archive), state: archive.reviewReminderState ?? .init(), now: Date()
      ).contains(job) else {
        throw GalaxySSIHealthRecords.Failure.stale
      }
      let original: GalaxySSIHealthOriginalStore.Original?
      if job.kind == .report {
        guard let item = try originals.list().originals.first(where: { $0.id == job.target && $0.kind == .pdf })
        else { throw GalaxySSIHealthRecords.Failure.stale }
        original = item
      } else { original = nil }
      route = Route(job: job, original: original)
    } catch { failed = true }
  }

  private func update(_ job: GalaxySSIHealthReviewReminders.Job, _ action: GalaxySSIHealthReviewReminders.Action) {
    do { try records.updateReviewReminder(job, action: action); reload() }
    catch { failed = true }
  }

  private func title(_ job: GalaxySSIHealthReviewReminders.Job) -> String {
    switch job.kind {
    case .report: return originalNames[job.target] ?? t("report", "Report review")
    case .table: return tableNames[job.target] ?? t("table", "Table review")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.review_reminder." + key, fallback: fallback, language: language)
  }
}
