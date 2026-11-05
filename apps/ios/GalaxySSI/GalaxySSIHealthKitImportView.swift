import SwiftUI

@MainActor
struct GalaxySSIHealthKitImportView: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  let records: GalaxySSIHealthRecords
  var focusedScope: GalaxySSIHealthKitImport.Scope?
  @State private var scopes: Set<GalaxySSIHealthKitImport.Scope> = []
  @State private var days = 14
  @State private var preview: Preview?
  @State private var task: Task<Void, Never>?
  @State private var token = UUID()
  @State private var imported: Int?
  @State private var problem: String?

  private struct Preview {
    let scopes: Set<GalaxySSIHealthKitImport.Scope>
    let interval: DateInterval
    let calendar: Calendar
    let rows: [GalaxySSIHealthReading]
  }

  var body: some View {
    Form {
      if scene == .active {
        if GalaxySSIHealthKitImport.available {
          Section(t("scopes", "Read scopes")) {
            ForEach(orderedScopes) { scope in
              Toggle(scope.metric.title(language: language), isOn: Binding(get: { scopes.contains(scope) }, set: { enabled in
                var updated = scopes
                if enabled { updated.insert(scope) } else { updated.remove(scope) }
                do {
                  let stored = try records.load().healthKitSelection ?? []
                  var saved = Set(stored.compactMap(GalaxySSIHealthKitImport.Scope.init(rawValue:)))
                  if enabled { saved.insert(scope) } else { saved.remove(scope) }
                  try records.setHealthKitSelection(saved)
                  scopes = updated; preview = nil
                }
                catch { problem = t("failed", "The read failed or data changed. Prepare a fresh preview.") }
              }))
            }
          }
          .disabled(task != nil)
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
          Button(t("disconnect", "Clear import selection")) {
            clear()
            do { try records.setHealthKitSelection([]); scopes = [] }
            catch { problem = t("failed", "The read failed or data changed. Prepare a fresh preview.") }
          }
        } else {
          Text(t("unavailable", "HealthKit is unavailable on this device or in this build."))
        }
        if task != nil { ProgressView() }
        if let imported { Text(String(format: t("saved", "%lld new measurements imported"), Int64(imported))) }
        if let problem { Text(problem).foregroundColor(.secondary) }
      }
    }
    .navigationTitle("Apple Health")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if let focusedScope { scopes = [focusedScope] }
      else if let archive = try? records.load() {
        scopes = Set((archive.healthKitSelection ?? []).compactMap(GalaxySSIHealthKitImport.Scope.init(rawValue:)))
      }
    }
    .onChange(of: scene) { if $0 == .background { clear() } }
    .onDisappear { clear() }
  }

  private var orderedScopes: [GalaxySSIHealthKitImport.Scope] {
    let all = GalaxySSIHealthKitImport.Scope.allCases
    guard let focusedScope else { return all }
    return [focusedScope] + all.filter { $0 != focusedScope }
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
      let rows = try await provider.read(selection, interval: interval, calendar: local)
      try Task.checkCancellation()
      guard scene == .active, selection == scopes else { throw GalaxySSIHealthKitImport.Failure.changed }
      preview = Preview(scopes: selection, interval: interval, calendar: local, rows: rows)
    }
  }

  private func save(_ expected: Preview) {
    run {
      let fresh = try await GalaxySSIHealthKitImport().read(expected.scopes, interval: expected.interval, calendar: expected.calendar)
      try Task.checkCancellation()
      guard scene == .active, expected.scopes == scopes,
            GalaxySSIHealthKitImport.stamp(fresh) == GalaxySSIHealthKitImport.stamp(expected.rows)
      else { preview = nil; throw GalaxySSIHealthKitImport.Failure.changed }
      imported = try records.importHealthKit(fresh)
      preview = nil
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
