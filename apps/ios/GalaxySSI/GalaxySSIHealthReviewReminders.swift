import SwiftUI

enum GalaxySSIHealthReviewReminders {
  struct TableDraft: Codable {
    let id: UUID
    let name: String
    let at: Date
    let data: Data
    let mapping: GalaxySSIHealthTableImport.Mapping
    let worksheet: GalaxySSIHealthXLSX.Selection?
    var retainOriginal: Bool?
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
    var enabled = false
    var actions: [String: Action] = [:]
    var notificationPreferences: GalaxySSIHealthReviewDelivery.Preferences?
    var deliveries: [String: GalaxySSIHealthReviewDelivery.Ticket]?
  }

  struct Job: Identifiable, Equatable {
    enum Kind: String { case report, table, incident }
    let target: UUID
    let kind: Kind
    let versions: [UUID]
    let at: Date
    var scope: String?
    var key: String { kind.rawValue + ":" + target.uuidString }
    var id: String { key }
  }

  @MainActor
  static func jobs(in archive: GalaxySSIHealthRecords.Archive) -> [Job] {
    let reports = Dictionary(grouping: archive.reportReview ?? []) { $0.source.original }
    var result = reports.map { id, items in
      Job(target: id, kind: .report, versions: items.map(\.version).sorted { $0.uuidString < $1.uuidString },
          at: items.map { $0.reading.measuredAt }.max() ?? .distantPast)
    }
    if let draft = archive.tableReview {
      result.append(.init(target: draft.id, kind: .table, versions: [draft.id], at: draft.at))
    }
    return result.sorted { ($0.at, $0.key) > ($1.at, $1.key) }
  }

  static func visible(_ jobs: [Job], state: State, now: Date) -> [Job] {
    guard state.enabled else { return [] }
    return jobs.filter { state.actions[$0.key]?.hides(at: now) != true }
  }

  @MainActor
  static func deliveryJobs(in archive: GalaxySSIHealthRecords.Archive) -> [Job] {
    let selected = archive.healthKitSelection ?? []
    let failures = (archive.healthKitIncidents ?? [:]).values.filter {
      !$0.acknowledged && selected.contains($0.scope)
    }.map {
      Job(target: $0.id, kind: .incident, versions: [$0.version], at: $0.lastFailureAt, scope: $0.scope)
    }
    return failures.sorted { ($0.at, $0.key) > ($1.at, $1.key) } + jobs(in: archive)
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
  @State private var tableName: String?
  @State private var limit = 30
  @State private var failed = false
  @State private var route: Route?
  @State private var incidents: [GalaxySSIHealthKitSync.Incident] = []
  @State private var incidentScope: GalaxySSIHealthKitImport.Scope?

  private struct Route: Identifiable {
    let job: GalaxySSIHealthReviewReminders.Job
    let original: GalaxySSIHealthOriginalStore.Original?
    var id: String { job.id }
  }

  private var originals: GalaxySSIHealthOriginalStore {
    GalaxySSIHealthOriginalStore(owner: records.owner, secrets: records.secrets)
  }

  var body: some View {
    List {
      if scene == .active {
        Toggle(t("enabled", "Show report and table review reminders"), isOn: Binding(
          get: { enabled }, set: { value in
            do { try records.setReviewRemindersEnabled(value); reload() } catch { failed = true }
          }))
        if enabled {
          if jobs.isEmpty { Text(t("empty", "No pending reviews")).foregroundColor(.secondary) }
          ForEach(jobs.prefix(limit)) { job in
            VStack(alignment: .leading, spacing: 6) {
              Button { open(job) } label: {
                Label(title(job), systemImage: job.kind == .report ? "doc.text.magnifyingglass" : "tablecells")
              }
              HStack {
                Button(t("snooze_hour", "Snooze for one hour")) { update(job, .snoozed(Date().addingTimeInterval(3_600))) }
                Spacer()
                Button(t("handled", "Mark handled")) { update(job, .handled) }
              }
              .font(.subheadline)
              .buttonStyle(.borderless)
            }
          }
          if jobs.count > limit { Button(t("more", "Show more reviews")) { limit += 30 } }
        }
        GalaxySSIHealthReviewNotificationSettings(records: records, reviewEnabled: enabled)
        Section(t("connections", "Data Connections")) {
          if incidents.isEmpty { Text(t("connections_empty", "No unresolved sync failures")).foregroundColor(.secondary) }
          ForEach(incidents) { incident in
            VStack(alignment: .leading, spacing: 6) {
              Button { openIncident(incident) } label: {
                Label(incident.metric?.title(language: language) ?? "Apple Health", systemImage: "exclamationmark.circle")
              }
              Text(incidentStatus(incident.status)).foregroundColor(.secondary)
              Text(incident.lastFailureAt, style: .date).foregroundColor(.secondary)
              Button(t("acknowledge_incident", "Acknowledge")) {
                do { try records.acknowledgeHealthKitIncident(incident); reload() }
                catch { failed = true }
              }
              .buttonStyle(.borderless)
            }
          }
        }
        if failed { Text(t("failed", "The review changed or is unavailable.")).foregroundColor(.secondary) }
      }
    }
    .navigationTitle(t("title", "Health Review Reminders"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onChange(of: scene) {
      if $0 == .active { reload() }
      else { jobs = []; originalNames = [:]; tableName = nil; route = nil; incidents = []; incidentScope = nil }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.reviewInputsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
    .sheet(item: $route, onDismiss: reload) { destination in
      NavigationView {
        Group {
          if let original = destination.original {
            GalaxySSIHealthReportBatchView(records: records, store: originals, original: original)
          } else {
            GalaxySSIHealthTableImportView(records: records, resumeReviewID: destination.job.target)
          }
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) {
          Button(t("close", "Close")) { route = nil }
        } }
      }
      .navigationViewStyle(.stack)
    }
    .sheet(item: $incidentScope, onDismiss: reload) { scope in
      NavigationView {
        GalaxySSIHealthKitSyncView(records: records, focusedScope: scope)
          .toolbar { ToolbarItem(placement: .cancellationAction) {
            Button(t("close", "Close")) { incidentScope = nil }
          } }
      }
      .navigationViewStyle(.stack)
    }
  }

  private func openIncident(_ incident: GalaxySSIHealthKitSync.Incident) {
    do {
      guard scene == .active, let scope = GalaxySSIHealthKitImport.Scope(rawValue: incident.scope),
            try records.load().healthKitIncidents?[incident.scope] == incident else {
        throw GalaxySSIHealthRecords.Failure.stale
      }
      incidentScope = scope
    } catch { reload(); failed = true }
  }

  private func incidentStatus(_ status: GalaxySSIHealthKitSync.Status) -> String {
    switch status {
    case .permission: return t("connection_permission", "System access required")
    case .unavailable: return t("connection_unavailable", "Apple Health unavailable")
    default: return t("connection_failed", "Synchronization failed")
    }
  }

  private func reload() {
    guard scene == .active else { return }
    do {
      let archive = try records.load()
      incidents = (archive.healthKitIncidents ?? [:]).values.filter { !$0.acknowledged }
        .sorted { ($0.lastFailureAt, $0.scope) > ($1.lastFailureAt, $1.scope) }
      let state = archive.reviewReminderState ?? .init()
      enabled = state.enabled
      jobs = GalaxySSIHealthReviewReminders.visible(GalaxySSIHealthReviewReminders.jobs(in: archive), state: state, now: Date())
      tableName = archive.tableReview?.name
      originalNames = jobs.contains { $0.kind == .report }
        ? Dictionary(uniqueKeysWithValues: try originals.list().originals.map { ($0.id, $0.name) }) : [:]
      failed = false
    } catch { jobs = []; originalNames = [:]; tableName = nil; incidents = []; failed = true }
  }

  private func open(_ job: GalaxySSIHealthReviewReminders.Job) {
    do {
      guard scene == .active,
            GalaxySSIHealthReviewReminders.jobs(in: try records.load()).contains(job) else {
        throw GalaxySSIHealthRecords.Failure.stale
      }
      let original: GalaxySSIHealthOriginalStore.Original?
      if job.kind == .report {
        guard let item = try originals.list().originals.first(where: { $0.id == job.target })
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
    case .table: return tableName ?? t("table", "Table review")
    case .incident: return t("connection_failed", "Synchronization failed")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.review_reminder." + key, fallback: fallback, language: language)
  }
}
