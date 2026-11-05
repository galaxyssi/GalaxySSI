import HealthKit
import SwiftUI

enum GalaxySSIHealthKitSync {
  static let pageSize = 250
  static let pagesPerRun = 12

  enum Status: String, Codable {
    case running, empty, success, interrupted, permission, unavailable, failed
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
  }

  struct Page {
    let rows: [GalaxySSIHealthReading]
    let anchor: Data
    let providerCount: Int
    let more: Bool
  }

  struct Coverage {
    let selected: Bool
    let lastReadableAt: Date?
    let lastCompletedAt: Date?

    init(scope: GalaxySSIHealthKitImport.Scope, selection: Set<String>, reads: [String: Date],
         checkpoints: [String: Checkpoint]) {
      selected = selection.contains(scope.rawValue)
      lastReadableAt = reads[scope.rawValue]
      lastCompletedAt = checkpoints[scope.rawValue]?.finishedAt
    }
  }

  enum Failure: Error { case invalidAnchor, unavailable, stalled }

  static func classification(_ error: Error) -> Status {
    if error is CancellationError { return .interrupted }
    if case Failure.unavailable = error { return .unavailable }
    let ns = error as NSError
    guard ns.domain == HKErrorDomain else { return .failed }
    switch HKError.Code(rawValue: ns.code) {
    case .errorAuthorizationDenied?, .errorAuthorizationNotDetermined?: return .permission
    case .errorHealthDataRestricted?, .errorHealthDataUnavailable?: return .unavailable
    default: return .failed
    }
  }
}

@MainActor
struct GalaxySSIHealthKitSyncProvider {
  private let store = HKHealthStore()

  func page(scope: GalaxySSIHealthKitImport.Scope, checkpoint: GalaxySSIHealthKitSync.Checkpoint,
            now: Date) async throws -> GalaxySSIHealthKitSync.Page {
    guard GalaxySSIHealthKitImport.available, scope != .steps, checkpoint.floor < now else {
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
    let result: ([HKSample], Int, HKQueryAnchor) = try await withCheckedThrowingContinuation { continuation in
      let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: previous,
                                      limit: GalaxySSIHealthKitSync.pageSize) { _, samples, deleted, anchor, error in
        if let error {
          let ns = error as NSError
          if previous != nil, ns.domain == HKErrorDomain, ns.code == HKError.Code.errorInvalidArgument.rawValue {
            continuation.resume(throwing: GalaxySSIHealthKitSync.Failure.invalidAnchor)
          } else { continuation.resume(throwing: error) }
        } else if let anchor {
          continuation.resume(returning: (samples ?? [], deleted?.count ?? 0, anchor))
        } else { continuation.resume(throwing: GalaxySSIHealthKitSync.Failure.stalled) }
      }
      store.execute(query)
    }
    try Task.checkCancellation()
    let (samples, deleted, anchor) = result
    let count = samples.count + deleted
    let more = count >= GalaxySSIHealthKitSync.pageSize
    if more && anchor == previous { throw GalaxySSIHealthKitSync.Failure.stalled }
    let bytes = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    let interval = DateInterval(start: checkpoint.floor, end: now)
    let rows = samples.compactMap { GalaxySSIHealthKitImport.convert($0, scope: scope, interval: interval) }
    return .init(rows: rows, anchor: bytes, providerCount: count, more: more)
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
  @State private var selected: Set<GalaxySSIHealthKitImport.Scope> = []
  @State private var checkpoints: [String: GalaxySSIHealthKitSync.Checkpoint] = [:]
  @State private var task: Task<Void, Never>?
  @State private var token = UUID()
  @State private var current: GalaxySSIHealthKitImport.Scope?
  @State private var failure: GalaxySSIHealthKitSync.Status?
  @State private var confirmingReset = false
  @State private var loadedSelection = false

  init(records: GalaxySSIHealthRecords, focusedScope: GalaxySSIHealthKitImport.Scope? = nil) {
    self.records = records
    self.focusedScope = focusedScope
  }

  private var scopes: [GalaxySSIHealthKitImport.Scope] {
    let all = GalaxySSIHealthKitImport.Scope.allCases.filter { $0 != .steps }
    guard let focusedScope, all.contains(focusedScope) else { return all }
    return [focusedScope] + all.filter { $0 != focusedScope }
  }

  var body: some View {
    List {
      if scene == .active {
        if GalaxySSIHealthKitImport.available {
          Section(t("scopes", "Apple Health scopes")) {
            ForEach(scopes) { scope in
              Toggle(isOn: Binding(get: { selected.contains(scope) }, set: {
                setSelected(scope, enabled: $0)
              })) {
                VStack(alignment: .leading) {
                  Text(scope.metric.title(language: language))
                  if let checkpoint = checkpoints[scope.rawValue] {
                    Text(statusText(checkpoint.status, running: current == scope)).foregroundColor(.secondary)
                    if let at = checkpoint.finishedAt { Text(at, style: .date).foregroundColor(.secondary) }
                    Text(t("coverage_floor", "Coverage start") + ": " + checkpoint.floor.formatted(date: .abbreviated, time: .omitted))
                      .foregroundColor(.secondary)
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
        NavigationLink {
          GalaxySSIHealthBluetoothView(records: records)
        } label: { Text(t("bluetooth", "Bluetooth live collection")) }
      }
    }
    .navigationTitle(t("title", "Sync and Data Coverage"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onDisappear(perform: stop)
    .onChange(of: scene) { if $0 == .active { reload() } else if $0 == .background { stop(); checkpoints = [:] } }
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
      catch { if token == request { failure = GalaxySSIHealthKitSync.classification(error) }; return }
      let provider = GalaxySSIHealthKitSyncProvider()
      for scope in scopes where selection.contains(scope) {
        guard !Task.isCancelled, token == request, scene == .active else { return }
        current = scope
        var run: UUID?
        do {
          var checkpoint = try records.beginHealthKitSync(scope, floor: floor, reset: reset)
          run = checkpoint.run
          var resetUsed = reset
          for _ in 0..<GalaxySSIHealthKitSync.pagesPerRun {
            let page: GalaxySSIHealthKitSync.Page
            do { page = try await provider.page(scope: scope, checkpoint: checkpoint, now: now) }
            catch GalaxySSIHealthKitSync.Failure.invalidAnchor where !resetUsed {
              try Task.checkCancellation()
              guard token == request, scene == .active else { throw CancellationError() }
              checkpoint = try records.beginHealthKitSync(scope, floor: floor, reset: true)
              run = checkpoint.run
              resetUsed = true
              continue
            }
            try Task.checkCancellation()
            guard token == request, scene == .active else { throw CancellationError() }
            checkpoint = try records.commitHealthKitPage(scope: scope, expected: checkpoint, page: page, at: Date())
            checkpoints[scope.rawValue] = checkpoint
            if !page.more { break }
          }
          try records.finishHealthKitSync(scope, run: checkpoint.run, status: .interrupted)
        } catch {
          let status = GalaxySSIHealthKitSync.classification(error)
          if let run { try? records.finishHealthKitSync(scope, run: run, status: status) }
          if token == request { failure = status }
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
      if !loadedSelection {
        let saved = Set((archive.healthKitSelection ?? []).compactMap(GalaxySSIHealthKitImport.Scope.init(rawValue:)))
        if let focusedScope { selected = [focusedScope] }
        else { selected = saved.subtracting([.steps]) }
        loadedSelection = true
      }
    }
    catch { failure = .failed }
  }

  private func setSelected(_ scope: GalaxySSIHealthKitImport.Scope, enabled: Bool) {
    do {
      let archived = try records.load().healthKitSelection ?? []
      var saved = Set(archived.compactMap(GalaxySSIHealthKitImport.Scope.init(rawValue:)))
      if enabled { saved.insert(scope) } else { saved.remove(scope) }
      try records.setHealthKitSelection(saved)
      if enabled { selected.insert(scope) } else { selected.remove(scope) }
    } catch { failure = .failed }
  }

  private func statusText(_ status: GalaxySSIHealthKitSync.Status, running: Bool) -> String {
    switch status {
    case .running where running: return t("running", "Syncing")
    case .running, .interrupted: return t("interrupted", "Interrupted; can resume")
    case .empty: return t("empty", "No readable changes")
    case .success: return t("success", "Sync completed")
    case .permission: return t("permission", "System access required")
    case .unavailable: return t("unavailable", "Apple Health is unavailable")
    case .failed: return t("failed", "Sync failed; local copies were kept")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.healthkit_sync." + key, fallback: fallback, language: language)
  }
}
