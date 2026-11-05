import SwiftUI

enum GalaxySSIHealthKitCopies {
  struct Erasure: Codable, Identifiable {
    var id = UUID()
    let at: Date
    let scope: String
    let records: Int
  }

  struct Plan: Equatable {
    let scope: GalaxySSIHealthKitImport.Scope
    let count: Int
    let start: Date
    let end: Date
    let versions: [GalaxySSIHealthReading]
    let draft: GalaxySSIHealthDraft?
    let links: [GalaxySSIHealthTableImport.Evidence]
    let reportLinks: [GalaxySSIHealthReportReview.Evidence]
  }

  static func includes(_ reading: GalaxySSIHealthReading, scope: GalaxySSIHealthKitImport.Scope) -> Bool {
    guard reading.metric == scope.metric, reading.bluetoothReceipt == nil, reading.tableSource == nil,
          reading.reportSource == nil,
          let source = reading.healthKitSource, source.key.utf8.count == 64 else { return false }
    return source.key.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}

@MainActor
struct GalaxySSIHealthKitCopiesView: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  @State private var counts: [String: Int] = [:]
  @State private var preview: GalaxySSIHealthKitCopies.Plan?
  @State private var confirming = false
  @State private var failed = false
  @State private var erased: Int?

  var body: some View {
    List {
      if scene == .active {
        ForEach(GalaxySSIHealthKitImport.Scope.allCases) { scope in
          Button { prepare(scope) } label: {
            HStack {
              Text(scope.metric.title(language: language))
              Spacer()
              Text(String(counts[scope.rawValue] ?? 0)).foregroundColor(.secondary)
            }
          }
          .disabled((counts[scope.rawValue] ?? 0) == 0)
        }
        if let erased { Text(String(format: t("erased", "%lld local copies erased"), Int64(erased))) }
        if failed {
          Text(t("failed", "The local copies changed or could not be accessed. Review them again."))
          Button(t("reload", "Reload local copies"), action: reload)
        }
      }
    }
    .navigationTitle(t("title", "Apple Health Local Copies"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onDisappear(perform: clear)
    .onChange(of: scene) { if $0 == .active { reload() } else { clear() } }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.trendInputsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
    .confirmationDialog(t("confirm", "Permanently erase these local copies?"),
                        isPresented: $confirming, titleVisibility: .visible) {
      Button(t("erase", "Erase local copies"), role: .destructive, action: erase)
      Button(t("cancel", "Cancel"), role: .cancel) { preview = nil }
    } message: {
      if let preview {
        Text(preview.scope.metric.title(language: language) + "\n" +
          String(format: t("count", "%lld local copies"), Int64(preview.count)) + "\n" +
          preview.start.formatted(date: .abbreviated, time: .omitted) + " – " +
          preview.end.formatted(date: .abbreviated, time: .omitted))
      }
    }
  }

  private func reload() {
    guard scene == .active else { return }
    do {
      counts = try records.healthKitCopyCounts()
      failed = false
    } catch { counts = [:]; failed = true }
  }

  private func prepare(_ scope: GalaxySSIHealthKitImport.Scope) {
    guard scene == .active else { return }
    do {
      preview = try records.previewHealthKitErase(scope)
      confirming = true
      erased = nil; failed = false
    } catch { reload(); failed = true }
  }

  private func erase() {
    guard scene == .active, let preview else { return }
    self.preview = nil
    do { erased = try records.eraseHealthKitCopies(preview); reload() }
    catch { reload(); failed = true }
  }

  private func clear() {
    counts = [:]; preview = nil; confirming = false; erased = nil; failed = false
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.healthkit_copies." + key, fallback: fallback, language: language)
  }
}
