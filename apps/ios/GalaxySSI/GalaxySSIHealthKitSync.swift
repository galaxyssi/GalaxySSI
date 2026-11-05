import HealthKit
import SwiftUI

enum GalaxySSIHealthKitSync {
  static let pageSize = 250
  static let pagesPerRun = 12

  enum Status: String, Codable {
    case running, empty, success, interrupted, permission, unavailable, locked, failed

    var raisesIncident: Bool { self == .permission || self == .unavailable || self == .failed }
  }

  struct Incident: Codable, Identifiable, Equatable {
    var id = UUID()
    var version = UUID()
    let scope: GalaxySSIHealthKitImport.Scope
    var status: Status
    var failedAt: Date?
    var lastSuccess: Date?
    var acknowledgedAt: Date?
    var resolvedAt: Date?

    var handled: Bool { acknowledgedAt != nil || resolvedAt != nil }

    static func legacy(scope: GalaxySSIHealthKitImport.Scope, checkpoint: Checkpoint?) -> Self? {
      guard let checkpoint, checkpoint.status.raisesIncident else { return nil }
      return .init(id: checkpoint.run, version: checkpoint.run, scope: scope, status: checkpoint.status,
                   failedAt: checkpoint.lastAttemptAt, lastSuccess: checkpoint.finishedAt)
    }
  }

  struct Checkpoint: Codable, Equatable {
    let floor: Date
    var previousCoverageUnverified = false
    var anchor: Data?
    var run = UUID()
    var status = Status.interrupted
    var insertedThisRun = 0
    var readThisRun = 0
    var finishedAt: Date?
    var lastAttemptAt: Date?
  }

  struct Page {
    let rows: [GalaxySSIHealthReading]
    let anchor: Data?
    let providerCount: Int
    let more: Bool
  }

  enum Failure: Error { case invalidAnchor, unavailable, stalled }

  static func classification(_ error: Error) -> Status {
    if error is CancellationError { return .interrupted }
    if case Failure.unavailable = error { return .unavailable }
    if case GalaxySSIHealthKitImport.Failure.unavailable = error { return .unavailable }
    let ns = error as NSError
    guard ns.domain == HKErrorDomain else { return .failed }
    switch HKError.Code(rawValue: ns.code) {
    case .errorAuthorizationDenied?, .errorAuthorizationNotDetermined?: return .permission
    case .errorHealthDataRestricted?, .errorHealthDataUnavailable?: return .unavailable
    case .errorDatabaseInaccessible?: return .locked
    case .errorUserCanceled?: return .interrupted
    default: return .failed
    }
  }

  @MainActor
  static func run(scope: GalaxySSIHealthKitImport.Scope, records: GalaxySSIHealthRecords, floor: Date,
                  reset: Bool, isActive: () -> Bool, read: (Checkpoint) async throws -> Page,
                  onCheckpoint: (Checkpoint) -> Void) async throws -> Checkpoint {
    func checkActive() throws {
      try Task.checkCancellation()
      guard isActive() else { throw CancellationError() }
    }
    try checkActive()
    var checkpoint = try records.beginHealthKitSync(scope, floor: floor, reset: reset)
    var resetUsed = reset
    onCheckpoint(checkpoint)
    do {
      for _ in 0..<pagesPerRun {
        try checkActive()
        let page: Page
        do { page = try await read(checkpoint) }
        catch Failure.invalidAnchor where !resetUsed {
          try checkActive()
          checkpoint = try records.beginHealthKitSync(scope, floor: floor, reset: true)
          resetUsed = true
          onCheckpoint(checkpoint)
          continue
        }
        try checkActive()
        checkpoint = try records.commitHealthKitPage(scope: scope, expected: checkpoint, page: page, at: Date())
        onCheckpoint(checkpoint)
        if !page.more { return checkpoint }
      }
      try records.finishHealthKitSync(scope, run: checkpoint.run, status: .interrupted)
      checkpoint.status = .interrupted
      return checkpoint
    } catch {
      try? records.finishHealthKitSync(scope, run: checkpoint.run, status: classification(error))
      throw error
    }
  }
}

extension GalaxySSIHealthRecords.Archive {
  var syncIncidents: [GalaxySSIHealthKitSync.Incident] {
    GalaxySSIHealthKitImport.Scope.allCases.compactMap { syncIncident($0) }.sorted {
      let left = $0.failedAt ?? .distantPast, right = $1.failedAt ?? .distantPast
      return left == right ? $0.scope.rawValue < $1.scope.rawValue : left > right
    }
  }

  func syncIncident(_ scope: GalaxySSIHealthKitImport.Scope) -> GalaxySSIHealthKitSync.Incident? {
    guard scope != .steps else { return nil }
    return healthKitIncidents?[scope.rawValue] ?? .legacy(scope: scope, checkpoint: healthKitSync?[scope.rawValue])
  }

  mutating func setSyncIncident(_ incident: GalaxySSIHealthKitSync.Incident) {
    var incidents = healthKitIncidents ?? [:]
    incidents[incident.scope.rawValue] = incident
    healthKitIncidents = incidents
  }

  mutating func recordSyncFailure(_ scope: GalaxySSIHealthKitImport.Scope,
                                  status: GalaxySSIHealthKitSync.Status, at now: Date) {
    let lastSuccess = healthKitSync?[scope.rawValue]?.finishedAt
    var incident: GalaxySSIHealthKitSync.Incident
    if let existing = syncIncident(scope), existing.resolvedAt == nil {
      incident = existing
      incident.version = UUID()
      incident.status = status
      incident.failedAt = now
      incident.lastSuccess = lastSuccess ?? existing.lastSuccess
    } else {
      incident = .init(scope: scope, status: status, failedAt: now, lastSuccess: lastSuccess)
    }
    setSyncIncident(incident)
  }
}

@MainActor
final class GalaxySSIHealthKitSyncProvider {
  private typealias Batch = ([HKSample], Int, HKQueryAnchor?)
  private let store = HKHealthStore()
  private var pending: (id: UUID, query: HKAnchoredObjectQuery, continuation: CheckedContinuation<Batch, Error>)?

  func page(scope: GalaxySSIHealthKitImport.Scope,
            checkpoint: GalaxySSIHealthKitSync.Checkpoint) async throws -> GalaxySSIHealthKitSync.Page {
    guard GalaxySSIHealthKitImport.available, scope != .steps, checkpoint.floor < Date() else {
      throw GalaxySSIHealthKitSync.Failure.unavailable
    }
    let type: HKSampleType?
    switch scope {
    case .sleep: type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
    case .bloodPressure: type = HKObjectType.correlationType(forIdentifier: .bloodPressure)
    default: type = scope.quantity
    }
    guard let type else { throw GalaxySSIHealthKitSync.Failure.unavailable }
    let previous: HKQueryAnchor?
    if let bytes = checkpoint.anchor {
      guard bytes.count <= 16_384,
            let decoded = try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: bytes)
      else { throw GalaxySSIHealthKitSync.Failure.invalidAnchor }
      previous = decoded
    } else { previous = nil }
    let predicate = HKQuery.predicateForSamples(withStart: checkpoint.floor, end: nil, options: .strictStartDate)
    let id = UUID()
    let result: Batch = try await withTaskCancellationHandler(operation: {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Batch, Error>) in
        guard pending == nil else {
          continuation.resume(throwing: GalaxySSIHealthKitSync.Failure.stalled)
          return
        }
        let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: previous,
                                        limit: GalaxySSIHealthKitSync.pageSize) { [weak self] _, samples, deleted, anchor, error in
          let outcome: Result<Batch, Error>
          if let error {
            let ns = error as NSError
            if ns.domain == HKErrorDomain, ns.code == HKError.Code.errorNoData.rawValue {
              outcome = .success(([], 0, previous))
            } else if previous != nil, ns.domain == HKErrorDomain, ns.code == HKError.Code.errorInvalidArgument.rawValue {
              outcome = .failure(GalaxySSIHealthKitSync.Failure.invalidAnchor)
            } else { outcome = .failure(error) }
          } else if let anchor {
            outcome = .success((samples ?? [], deleted?.count ?? 0, anchor))
          } else { outcome = .failure(GalaxySSIHealthKitSync.Failure.stalled) }
          Task { @MainActor [weak self] in self?.finish(id, outcome: outcome) }
        }
        pending = (id, query, continuation)
        store.execute(query)
      }
    }, onCancel: { [weak self] in
      Task { @MainActor [weak self] in self?.finish(id, outcome: .failure(CancellationError()), cancel: true) }
    })
    try Task.checkCancellation()
    let (samples, deleted, anchor) = result
    let count = samples.count + deleted
    let more = count >= GalaxySSIHealthKitSync.pageSize
    if more && anchor == previous { throw GalaxySSIHealthKitSync.Failure.stalled }
    let bytes = try anchor.map { try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
    let interval = DateInterval(start: checkpoint.floor, end: max(checkpoint.floor, Date()))
    let rows = samples.compactMap { GalaxySSIHealthKitImport.convert($0, scope: scope, interval: interval) }
    return .init(rows: rows, anchor: bytes, providerCount: count, more: more)
  }

  private func finish(_ id: UUID, outcome: Result<Batch, Error>, cancel: Bool = false) {
    guard let pending, pending.id == id else { return }
    self.pending = nil
    if cancel { store.stop(pending.query) }
    pending.continuation.resume(with: outcome)
  }
}

@MainActor
struct GalaxySSIHealthKitSyncView: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let focusedScope: GalaxySSIHealthKitImport.Scope?
  @State private var selected: Set<GalaxySSIHealthKitImport.Scope>
  @State private var checkpoints: [String: GalaxySSIHealthKitSync.Checkpoint] = [:]
  @State private var incidents: [GalaxySSIHealthKitImport.Scope: GalaxySSIHealthKitSync.Incident] = [:]
  @State private var task: Task<Void, Never>?
  @State private var token = UUID()
  @State private var current: GalaxySSIHealthKitImport.Scope?
  @State private var failure: GalaxySSIHealthKitSync.Status?
  @State private var confirmingReset = false
  @State private var lastBluetoothReceipt: Date?

  init(records: GalaxySSIHealthRecords, focusedScope: GalaxySSIHealthKitImport.Scope? = nil) {
    let scope = focusedScope == .steps ? nil : focusedScope
    self.records = records
    self.focusedScope = scope
    _selected = State(initialValue: Set(scope.map { [$0] } ?? []))
  }

  private var scopes: [GalaxySSIHealthKitImport.Scope] {
    let available = GalaxySSIHealthKitImport.Scope.allCases.filter { $0 != .steps }
    guard let focusedScope else { return available }
    return [focusedScope] + available.filter { $0 != focusedScope }
  }

  var body: some View {
    List {
      if scene == .active {
        if let focusedScope {
          Section(t("recovery", "Sync recovery")) {
            Text(focusedScope.metric.title(language: language)).font(.headline)
            if let incident = incidents[focusedScope], incident.resolvedAt == nil {
              Text(statusText(incident.status, running: false)).foregroundColor(.secondary)
            }
          }
        }
        if GalaxySSIHealthKitImport.available {
          Section(t("scopes", "Apple Health scopes")) {
            ForEach(scopes) { scope in
              Toggle(isOn: Binding(get: { selected.contains(scope) }, set: {
                if $0 { selected.insert(scope) } else { selected.remove(scope) }
              })) {
                VStack(alignment: .leading) {
                  Text(scope.metric.title(language: language))
                  if let checkpoint = checkpoints[scope.rawValue] {
                    Text(statusText(checkpoint.status, running: current == scope)).foregroundColor(.secondary)
                    if let at = checkpoint.finishedAt { Text(at, style: .date).foregroundColor(.secondary) }
                    Text(t("coverage_floor", "Scan start") + ": " + checkpoint.floor.formatted(date: .abbreviated, time: .omitted))
                      .foregroundColor(.secondary)
                    if checkpoint.status == .success {
                      Text(String(format: t("counts", "%lld readable changes · %lld newly saved"),
                                  Int64(checkpoint.readThisRun), Int64(checkpoint.insertedThisRun)))
                        .foregroundColor(.secondary)
                    }
                    if checkpoint.previousCoverageUnverified {
                      Text(t("old_unverified", "Older coverage could not be verified after restarting the cursor."))
                        .foregroundColor(.secondary)
                    }
                  }
                }
              }.disabled(task != nil)
            }
          }
          Button(t("run", "Authorize and sync selected scopes")) { start(reset: false) }
            .disabled(task != nil || selected.isEmpty)
          Button(t("restart", "Restart recent scan")) { confirmingReset = true }
            .disabled(task != nil || selected.isEmpty)
          if task != nil {
            ProgressView()
            Button(t("stop", "Stop sync"), action: stop)
          }
          NavigationLink {
            GalaxySSIHealthKitImportView(records: records)
          } label: { Text(t("manual", "Preview import and daily step totals")) }
        } else { Text(statusText(.unavailable, running: false)) }
        if let failure { Text(statusText(failure, running: false)).foregroundColor(.secondary) }
        Section(t("bluetooth", "Bluetooth live collection")) {
          if let lastBluetoothReceipt {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("bluetooth_last", "Last saved Bluetooth reading"))
              Text(lastBluetoothReceipt, format: .dateTime).foregroundColor(.secondary)
            }
          } else {
            Text(t("bluetooth_empty", "No saved Bluetooth readings")).foregroundColor(.secondary)
          }
          NavigationLink {
            GalaxySSIHealthBluetoothView(records: records)
          } label: { Text(t("bluetooth_open", "Open Bluetooth collection")) }
        }
      }
    }
    .navigationTitle(t("title", "Sync and Data Coverage"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onDisappear(perform: stop)
    .onChange(of: scene) {
      if $0 == .active { reload() }
      else if $0 == .background || current != nil {
        stop(); checkpoints = [:]; incidents = [:]; lastBluetoothReceipt = nil
      }
    }
    .confirmationDialog(t("reset_confirm", "Restart the selected scans? Local records will be kept."),
                        isPresented: $confirmingReset, titleVisibility: .visible) {
      Button(t("restart", "Restart recent scan")) { start(reset: true) }
    }
  }

  private func start(reset: Bool) {
    guard task == nil, scene == .active, !selected.isEmpty else { return }
    var local = calendar
    local.timeZone = timeZone
    let now = Date()
    guard let floor = local.date(byAdding: .day, value: -30, to: local.startOfDay(for: now)) else { return }
    let selection = selected
    let request = UUID()
    token = request
    failure = nil
    task = Task {
      defer {
        if token == request { task = nil; current = nil; reload() }
      }
      do { try await GalaxySSIHealthKitImport().authorize(selection) }
      catch {
        if token == request, scene == .active, !Task.isCancelled {
          let status = GalaxySSIHealthKitSync.classification(error)
          failure = status
          try? records.recordHealthKitAuthorizationFailure(selection, status: status)
        }
        return
      }
      let provider = GalaxySSIHealthKitSyncProvider()
      for scope in scopes where selection.contains(scope) {
        guard !Task.isCancelled, token == request, scene == .active else { return }
        current = scope
        do {
          let finished = try await GalaxySSIHealthKitSync.run(scope: scope, records: records, floor: floor, reset: reset,
            isActive: { token == request && scene == .active },
            read: { try await provider.page(scope: scope, checkpoint: $0) },
            onCheckpoint: { checkpoints[scope.rawValue] = $0 })
          if token == request { checkpoints[scope.rawValue] = finished }
        } catch {
          if token == request { failure = GalaxySSIHealthKitSync.classification(error); reload() }
        }
      }
    }
  }

  private func stop() {
    token = UUID()
    task?.cancel()
    task = nil; current = nil
    reload()
  }

  private func reload() {
    guard scene == .active else { return }
    do {
      let archive = try records.load()
      checkpoints = archive.healthKitSync ?? [:]
      incidents = Dictionary(uniqueKeysWithValues: archive.syncIncidents.map { ($0.scope, $0) })
      lastBluetoothReceipt = archive.current.compactMap { $0.bluetoothReceipt?.receivedAt }.max()
    }
    catch { failure = .failed }
  }

  private func statusText(_ status: GalaxySSIHealthKitSync.Status, running: Bool) -> String {
    switch status {
    case .running where running: return t("running", "Syncing")
    case .running, .interrupted: return t("interrupted", "Interrupted; can resume")
    case .empty: return t("empty", "No readable changes; check Apple Health access if data is expected")
    case .success: return t("success", "Sync completed")
    case .permission: return t("permission", "System access required")
    case .unavailable: return t("unavailable", "Apple Health is unavailable")
    case .locked: return t("locked", "Unlock this device to resume syncing")
    case .failed: return t("failed", "Sync failed; local copies were kept")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.healthkit_sync." + key, fallback: fallback, language: language)
  }
}
