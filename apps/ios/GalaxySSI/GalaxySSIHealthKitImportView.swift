import SwiftUI

@MainActor
struct GalaxySSIHealthKitImportView: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  @Environment(\.dismiss) private var dismiss
  let records: GalaxySSIHealthRecords
  var recoveryScope: GalaxySSIHealthKitImport.Scope? = nil
  @State private var scopes: Set<GalaxySSIHealthKitImport.Scope> = []
  @State private var days = 14
  @State private var preview: Preview?
  @State private var task: Task<Void, Never>?
  @State private var token = UUID()
  @State private var imported: Int?
  @State private var problem: String?
  @State private var sourceLedger: GalaxySSIHealthSourceAttention?
  @State private var sourceStateUnavailable = false

  private struct Preview {
    let scopes: Set<GalaxySSIHealthKitImport.Scope>
    let interval: DateInterval
    let calendar: Calendar
    let rows: [GalaxySSIHealthReading]
  }

  private var incident: GalaxySSIHealthSourceAttention.Incident? {
    sourceLedger?.active.first { $0.scope == recoveryScope }
  }

  var body: some View {
    Form {
      if scene == .active {
        NavigationLink {
          GalaxySSIHealthMetricDeletionView(records: records, filter: .appleHealth)
        } label: {
          Label(GalaxySSIHealthMetricDeletion.text("apple_health_title", "Local Apple Health Copies", language: language),
                systemImage: "tray.full")
        }
        if GalaxySSIHealthKitImport.available {
          if let recoveryScope {
            Section(t("recovery_title", "Source recovery")) {
              Text(recoveryScope.metric.title(language: language))
              if let incident {
                Text(t("recovery_failed", "The last Apple Health query failed."))
                Text(incident.failedAt, style: .relative).foregroundColor(.secondary)
                Button(t("recovery_acknowledge", "Acknowledge")) {
                  saveSourceState { $0.acknowledge(incident) }
                }
                .disabled(task != nil)
              } else if sourceLedger != nil {
                Text(t("recovery_clear", "No unresolved read failure for this data type."))
                  .foregroundColor(.secondary)
              }
            }
          } else {
            Section(t("scopes", "Read scopes")) {
              ForEach(GalaxySSIHealthKitImport.Scope.allCases) { scope in
                Toggle(scope.metric.title(language: language), isOn: Binding(
                  get: { scopes.contains(scope) },
                  set: { enabled in
                    var updated = scopes
                    if enabled { updated.insert(scope) } else { updated.remove(scope) }
                    scopes = updated
                    saveSourceState { $0.selected = updated }
                    preview = nil
                  }
                ))
              }
            }
            .disabled(task != nil)
          }
          Picker(t("period", "Recent days"), selection: $days) {
            ForEach([7, 14, 30], id: \.self) { Text(String($0)).tag($0) }
          }
          .onChange(of: days) { _ in preview = nil }
          .disabled(task != nil)
          Text(t("rationale", "Selected Apple Health data is read only after you request a preview. Confirmed copies stay in the local health archive. Manage system access in Apple Health."))
            .foregroundColor(.secondary)
          Button(t("preview", "Authorize and preview"), action: prepare).disabled(task != nil || scopes.isEmpty)
          if let preview {
            Section(t("preview_title", "Import preview")) {
              if preview.rows.isEmpty { Text(t("empty", "No readable data. There may be no matching records, or access may be limited.")) }
              ForEach(GalaxySSIHealthKitImport.Scope.allCases.filter { preview.scopes.contains($0) }) { scope in
                HStack {
                  Text(scope.metric.title(language: language))
                  Spacer()
                  Text(String(preview.rows.filter { $0.metric == scope.metric }.count))
                }
              }
              Button(t("save", "Confirm local import")) { save(preview) }.disabled(task != nil || preview.rows.isEmpty)
            }
          }
          if recoveryScope == nil {
            Button(t("disconnect", "Clear import selection")) {
              clear()
              scopes = []
              saveSourceState { $0.selected.removeAll() }
            }
          }
        } else {
          Text(t("unavailable", "HealthKit is unavailable on this device or in this build."))
        }
        if task != nil { ProgressView() }
        if let imported { Text(String(format: t("saved", "%lld new measurements imported"), Int64(imported))) }
        if let problem { Text(problem).foregroundColor(.secondary) }
        if sourceStateUnavailable {
          Text(t("recovery_unavailable", "Source recovery information is unavailable.")).foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle("Apple Health")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if recoveryScope != nil {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("recovery_close", "Close")) { dismiss() }
        }
      }
    }
    .onAppear { loadSourceState() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.sourceAttentionChanged)) { note in
      if note.object as? String == records.owner { loadSourceState() }
    }
    .onChange(of: scene) { phase in
      if phase == .active { loadSourceState() }
      if phase == .background { clear(); scopes = []; sourceLedger = nil; sourceStateUnavailable = false }
    }
    .onDisappear { clear(); scopes = []; sourceLedger = nil }
  }

  private func prepare() {
    var local = calendar
    local.timeZone = timeZone
    let now = Date()
    guard let start = local.date(byAdding: .day, value: -days, to: local.startOfDay(for: now)) else { return }
    let interval = DateInterval(start: start, end: now)
    let selection = scopes
    preview = nil
    run {
      let provider = GalaxySSIHealthKitImport()
      try await provider.authorize(selection)
      try Task.checkCancellation()
      let rows = try await provider.read(selection, interval: interval, calendar: local, onSourceRead: recordRead)
      try Task.checkCancellation()
      guard scene == .active, selection == scopes else { throw GalaxySSIHealthKitImport.Failure.changed }
      preview = Preview(scopes: selection, interval: interval, calendar: local, rows: rows)
    }
  }

  private func save(_ expected: Preview) {
    run {
      let fresh = try await GalaxySSIHealthKitImport().read(
        expected.scopes, interval: expected.interval, calendar: expected.calendar, onSourceRead: recordRead
      )
      try Task.checkCancellation()
      guard scene == .active, expected.scopes == scopes,
            GalaxySSIHealthKitImport.stamp(fresh) == GalaxySSIHealthKitImport.stamp(expected.rows)
      else { preview = nil; throw GalaxySSIHealthKitImport.Failure.changed }
      imported = try records.importHealthKit(fresh)
      preview = nil
    }
  }

  private func recordRead(_ scope: GalaxySSIHealthKitImport.Scope, _ succeeded: Bool) {
    guard scene == .active, !Task.isCancelled else { return }
    saveSourceState { $0.readFinished(scope, succeeded: succeeded, now: Date()) }
  }

  private func loadSourceState() {
    guard scene == .active else { return }
    do {
      let loaded = try records.loadSourceAttention()
      sourceLedger = loaded
      scopes = recoveryScope.map { Set([$0]) } ?? loaded.selected
      sourceStateUnavailable = false
    } catch {
      sourceLedger = nil
      if let recoveryScope { scopes = [recoveryScope] }
      sourceStateUnavailable = true
    }
  }

  private func saveSourceState(_ update: (inout GalaxySSIHealthSourceAttention) -> Void) {
    do {
      try records.updateSourceAttention(update)
      loadSourceState()
    } catch {
      sourceStateUnavailable = true
    }
  }

  private func run(_ action: @escaping @MainActor () async throws -> Void) {
    guard scene == .active, task == nil else { return }
    let request = UUID()
    token = request
    problem = nil
    imported = nil
    task = Task {
      do { try await action() }
      catch {
        if token == request, !Task.isCancelled {
          if case GalaxySSIHealthKitImport.Failure.excessive = error {
            problem = t("excessive", "Too many records. Select fewer scopes or a shorter period.")
          } else { problem = t("failed", "The read failed or data changed. Prepare a fresh preview.") }
        }
      }
      if token == request { task = nil }
    }
  }

  private func clear() {
    token = UUID()
    task?.cancel()
    task = nil; preview = nil; imported = nil; problem = nil
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.healthkit." + key, fallback: fallback, language: language)
  }
}
