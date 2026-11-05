import SwiftUI

enum GalaxySSIHealthMetricHistory {
  enum Source: String, CaseIterable {
    case manual, appleHealth, bluetooth, table, report

    init(_ reading: GalaxySSIHealthReading) {
      if reading.healthKitSource != nil { self = .appleHealth }
      else if reading.bluetoothReceipt != nil { self = .bluetooth }
      else if reading.tableSource != nil { self = .table }
      else if reading.reportSource != nil { self = .report }
      else { self = .manual }
    }

    var title: String {
      switch self {
      case .manual: return "Manual"
      case .appleHealth: return "Apple Health"
      case .bluetooth: return "Bluetooth"
      case .table: return "Imported table"
      case .report: return "Imported report"
      }
    }
  }

  struct Erasure: Codable, Identifiable {
    var id = UUID()
    let at: Date
    let metric: GalaxySSIHealthMetric
    let records: Int
  }

  struct Plan: Equatable {
    let metric: GalaxySSIHealthMetric
    let start: Date
    let end: Date
    let counts: [Source: Int]
    let versions: [GalaxySSIHealthReading]
    let draft: GalaxySSIHealthDraft?
    let tableLinks: [GalaxySSIHealthTableImport.Evidence]
    let reportLinks: [GalaxySSIHealthReportReview.Evidence]
    var count: Int { counts.values.reduce(0, +) }
  }
}

@MainActor
struct GalaxySSIHealthMetricHistoryView: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  @State private var metrics: [GalaxySSIHealthMetric] = []
  @State private var selected: GalaxySSIHealthMetric?
  @State private var preview: GalaxySSIHealthMetricHistory.Plan?
  @State private var confirming = false
  @State private var failed = false
  @State private var erased: Int?

  var body: some View {
    List {
      if scene == .active {
        if !metrics.isEmpty {
          Picker(t("metric", "Measurement type"), selection: $selected) {
            Text(t("select", "Select a type")).tag(nil as GalaxySSIHealthMetric?)
            ForEach(metrics) { metric in Text(metric.title(language: language)).tag(Optional(metric)) }
          }
          .onChange(of: selected) { _ in preview = nil }
          Button(t("preview", "Review local history"), action: prepare).disabled(selected == nil)
        } else if !failed {
          Text(t("empty", "No local measurement history"))
        }
        if let preview {
          Section(preview.metric.title(language: language)) {
            Text(preview.start.formatted(date: .abbreviated, time: .omitted) + " – " +
                 preview.end.formatted(date: .abbreviated, time: .omitted))
            ForEach(GalaxySSIHealthMetricHistory.Source.allCases, id: \.self) { source in
              if let count = preview.counts[source] {
                HStack { Text(t(source.rawValue, source.title)); Spacer(); Text(String(count)) }
              }
            }
            Button(t("erase", "Erase local history"), role: .destructive) { confirming = true }
          }
        }
        if failed {
          Text(t("failed", "History changed or could not be accessed. Review it again."))
          Button(t("reload", "Reload"), action: reload)
        }
        if let erased { Text(String(format: t("erased", "%lld measurements erased"), Int64(erased))) }
      }
    }
    .navigationTitle(t("title", "Erase Measurement History"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onDisappear(perform: clear)
    .onChange(of: scene) { if $0 == .active { reload() } else { clear() } }
    .confirmationDialog(t("confirm", "Permanently erase this measurement type?"),
                        isPresented: $confirming, titleVisibility: .visible) {
      Button(t("erase", "Erase local history"), role: .destructive, action: erase)
    } message: {
      Text(t("scope", "All reviewed local versions will be removed. Original files and provider data will be kept."))
    }
  }

  private func reload() {
    guard scene == .active else { return }
    do {
      let available = Set(try records.load().revisions.map(\.metric))
      metrics = GalaxySSIHealthMetric.allCases.filter(available.contains)
      if let selected, !available.contains(selected) { self.selected = nil }
      failed = false
    } catch { metrics = []; selected = nil; preview = nil; failed = true }
  }

  private func prepare() {
    guard scene == .active, let selected else { return }
    do { preview = try records.previewMetricErase(selected); failed = false; erased = nil }
    catch { preview = nil; failed = true }
  }

  private func erase() {
    guard scene == .active, let preview else { return }
    self.preview = nil
    do { erased = try records.eraseMetricHistory(preview); reload() }
    catch { reload(); failed = true }
  }

  private func clear() {
    metrics = []; selected = nil; preview = nil; confirming = false; erased = nil; failed = false
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.metric_erase." + key, fallback: fallback, language: language)
  }
}
