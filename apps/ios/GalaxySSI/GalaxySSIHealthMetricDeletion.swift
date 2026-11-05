import CryptoKit
import SwiftUI

enum GalaxySSIHealthMetricDeletion {
  enum Filter: String, Codable, Equatable {
    case appleHealth, bluetooth

    func includes(_ reading: GalaxySSIHealthReading, device: UUID?) -> Bool {
      guard reading.tableSource == nil, reading.reportSource == nil else { return false }
      switch self {
      case .appleHealth: return reading.healthKitSource != nil && reading.bluetoothReceipt == nil
      case .bluetooth:
        guard let device else { return false }
        return reading.healthKitSource == nil && reading.bluetoothReceipt?.device == device
      }
    }
  }

  enum Source: String, Codable, CaseIterable {
    case manual, report, table, bluetooth, appleHealth

    init(_ reading: GalaxySSIHealthReading) {
      if reading.healthKitSource != nil { self = .appleHealth }
      else if reading.bluetoothReceipt != nil { self = .bluetooth }
      else if reading.tableSource != nil { self = .table }
      else if reading.reportSource != nil { self = .report }
      else { self = .manual }
    }

    func title(language: String) -> String {
      let fallback: String
      switch self {
      case .manual: fallback = "Manual"
      case .report: fallback = "Report review"
      case .table: fallback = "Table import"
      case .bluetooth: fallback = "Bluetooth"
      case .appleHealth: fallback = "Apple Health"
      }
      return GalaxySSIHealthMetricDeletion.text(rawValue, fallback, language: language)
    }
  }

  struct Scope: Codable, Equatable {
    let metric: GalaxySSIHealthMetric
    let sources: [Source: Int]
    let earliest: Date?
    let latest: Date?
    let drafts: Int
    var filter: Filter?

    var count: Int { sources.values.reduce(0, +) }
    var isEmpty: Bool { count == 0 && drafts == 0 }
  }

  struct Audit: Codable, Identifiable {
    var id = UUID()
    let at: Date
    let scope: Scope
  }

  struct Preview: Equatable {
    let scope: Scope
    let ids: Set<UUID>
    let fingerprint: SHA256.Digest
    let bluetoothDevice: UUID?
  }

  @MainActor
  static func preview(_ metric: GalaxySSIHealthMetric, filter: Filter? = nil, bluetoothDevice: UUID? = nil,
                      in archive: GalaxySSIHealthRecords.Archive) throws -> Preview {
    if filter == .bluetooth {
      guard metric == .bloodPressure, bluetoothDevice != nil else { throw GalaxySSIHealthRecords.Failure.invalid }
      guard archive.derivesOverview == true else { throw GalaxySSIHealthRecords.Failure.permission }
    } else if bluetoothDevice != nil {
      throw GalaxySSIHealthRecords.Failure.invalid
    }
    func matches(_ reading: GalaxySSIHealthReading) -> Bool {
      reading.metric == metric && (filter?.includes(reading, device: bluetoothDevice) ?? true)
    }
    let ids = Set(archive.revisions.lazy.filter(matches).map(\.id))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var hasher = SHA256()
    func append<T: Encodable>(_ value: T) throws {
      hasher.update(data: try encoder.encode(value))
      hasher.update(data: Data([0]))
    }
    if filter == .bluetooth {
      try append(archive.privacyEvents?.last(where: { $0.scope == .overview })?.id)
    }
    var newest: [UUID: GalaxySSIHealthReading] = [:]
    var earliest: Date?
    var latest: Date?
    for reading in archive.revisions where ids.contains(reading.id) {
      // Refuse a history that crosses the requested metric or source.
      guard matches(reading) else { throw GalaxySSIHealthRecords.Failure.invalid }
      try append(reading)
      newest[reading.id] = reading
      earliest = min(earliest ?? reading.measuredAt, reading.measuredAt)
      latest = max(latest ?? reading.measuredAt, reading.measuredAt)
    }
    var drafts = 0
    if let draft = archive.draft, includes(draft, metric: metric, filter: filter, ids: ids) {
      try append(draft)
      drafts += 1
    }
    for item in archive.reportReview ?? [] where filter == nil && item.reading.metric == metric {
      try append(item)
      drafts += 1
    }
    for evidence in archive.tableEvidence ?? [] where ids.contains(evidence.target.record) {
      try append(evidence)
    }
    var counts: [Source: Int] = [:]
    for reading in newest.values { counts[Source(reading), default: 0] += 1 }
    return Preview(scope: .init(metric: metric, sources: counts, earliest: earliest, latest: latest,
                                drafts: drafts, filter: filter), ids: ids, fingerprint: hasher.finalize(),
                   bluetoothDevice: bluetoothDevice)
  }

  static func includes(_ draft: GalaxySSIHealthDraft, metric: GalaxySSIHealthMetric, filter: Filter?,
                       ids: Set<UUID>) -> Bool {
    (filter == nil && draft.metric == metric) || draft.existing.map { ids.contains($0.id) } == true
  }

  static func text(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.metric_deletion." + key, fallback: fallback, language: language)
  }
}

@MainActor
struct GalaxySSIHealthMetricDeletionView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let records: GalaxySSIHealthRecords
  var filter: GalaxySSIHealthMetricDeletion.Filter?
  @State private var review: GalaxySSIHealthMetricDeletion.Preview?
  @State private var history: [GalaxySSIHealthMetricDeletion.Audit] = []
  @State private var confirming = false
  @State private var notice: String?
  @State private var historyLimit = 20

  var body: some View {
    List {
      if scene == .active {
        if let notice { Text(notice).foregroundColor(.secondary) }
        if let review {
          Section(t("review", "Review local deletion")) {
            scopeRows(review.scope)
            Text(filter == .appleHealth
              ? t("apple_health_boundary", "Only GalaxySSI's copies from Apple Health are removed. Other sources, Apple Health data and permissions, exports and backups are unchanged.")
              : t("boundary", "Only GalaxySSI's local copies are removed. Original files, Apple Health, exports and backups are unchanged."))
              .foregroundColor(.secondary)
            Button(t("delete", "Delete local records"), role: .destructive) { confirming = true }
            Button(t("choose_another", "Choose another measurement")) { self.review = nil }
          }
        } else {
          Section(t("choose", "Choose a measurement type")) {
            ForEach(metrics) { metric in
              Button(metric.title(language: language)) { prepare(metric) }
            }
          }
          if !history.isEmpty {
            Section(t("history", "Local deletion history")) {
              ForEach(history.reversed().prefix(historyLimit)) { entry in
                VStack(alignment: .leading, spacing: 4) {
                  scopeRows(entry.scope)
                  Text(entry.at, format: .dateTime).foregroundColor(.secondary)
                }
              }
              if history.count > historyLimit { Button(t("more", "Show more")) { historyLimit += 20 } }
            }
          }
        }
      }
    }
    .navigationTitle(filter == .appleHealth ? t("apple_health_title", "Local Apple Health Copies")
                                          : t("title", "Delete by Measurement Type"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onChange(of: scene) {
      if $0 == .active { reload() }
      else { review = nil; confirming = false; history = []; notice = nil; historyLimit = 20 }
    }
    .alert(t("confirm", "Permanently delete these local records?"), isPresented: $confirming) {
      Button(t("delete", "Delete local records"), role: .destructive, action: erase)
      Button(t("cancel", "Cancel"), role: .cancel) {}
    }
  }

  @ViewBuilder
  private func scopeRows(_ scope: GalaxySSIHealthMetricDeletion.Scope) -> some View {
    Text(scope.metric.title(language: language)).font(.headline)
    if scope.filter == .appleHealth {
      Text(t("apple_health_only", "Apple Health copies only")).foregroundColor(.secondary)
    } else if scope.filter == .bluetooth {
      Text(t("bluetooth_only", "One Bluetooth device only")).foregroundColor(.secondary)
    }
    Text(String(format: t("record_count", "Local records: %lld"), Int64(scope.count)))
    if let earliest = scope.earliest, let latest = scope.latest {
      Text(String(format: t("date_range", "%@ to %@"), earliest.formatted(date: .abbreviated, time: .omitted),
                  latest.formatted(date: .abbreviated, time: .omitted))).foregroundColor(.secondary)
    }
    ForEach(GalaxySSIHealthMetricDeletion.Source.allCases, id: \.rawValue) { source in
      if let count = scope.sources[source] {
        Text(String(format: t("source_count", "%@: %lld"), source.title(language: language), Int64(count)))
      }
    }
    if scope.drafts > 0 {
      Text(String(format: t("drafts", "Drafts: %lld"), Int64(scope.drafts)))
    }
  }

  private func prepare(_ metric: GalaxySSIHealthMetric) {
    guard scene == .active else { return }
    notice = nil
    do {
      let preview = try records.previewMetricDeletion(metric, filter: filter)
      if preview.scope.isEmpty { notice = t("empty", "No local history for this measurement type.") }
      else { review = preview }
    } catch { notice = t("failed", "Could not access local measurement history.") }
  }

  private func erase() {
    guard scene == .active, let review else { return }
    self.review = nil
    do {
      try records.deleteMetricHistory(review)
      reload()
      notice = t("deleted", "The reviewed local history was deleted.")
    } catch GalaxySSIHealthRecords.Failure.stale {
      notice = t("changed", "The local history changed. Review it again before deleting.")
    } catch {
      notice = t("delete_failed", "Deletion could not be completed.")
    }
  }

  private func reload() {
    guard scene == .active else { return }
    do {
      history = (try records.load().metricDeletionHistory ?? []).filter { filter == nil || $0.scope.filter == filter }
    }
    catch { history = []; notice = t("failed", "Could not access local measurement history.") }
  }

  private var metrics: [GalaxySSIHealthMetric] {
    filter == .appleHealth ? GalaxySSIHealthKitImport.Scope.allCases.map(\.metric) : GalaxySSIHealthMetric.allCases
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSIHealthMetricDeletion.text(key, fallback, language: language)
  }
}
