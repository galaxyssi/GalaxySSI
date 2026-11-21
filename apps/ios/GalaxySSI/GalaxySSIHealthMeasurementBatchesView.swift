import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthMeasurementBatchesView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.sizeCategory) private var sizeCategory
  let records: GalaxySSIHealthRecords
  var initialBatch: String? = nil
  var onSelect: ((String?) -> Void)? = nil
  @State private var groups: [GalaxySSIHealthMeasurementBatches.Group] = []
  @State private var a: String?
  @State private var b: String?
  @State private var report: UUID?
  @State private var first: GalaxySSIHealthMeasurementBatches.Snapshot?
  @State private var second: GalaxySSIHealthMeasurementBatches.Snapshot?
  @State private var initialized = false
  @State private var abnormal = false
  @State private var allowed = false
  @State private var failed = false
  @State private var limit = 30
  @State private var reportLimit = 30
  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }
  private var selected: GalaxySSIHealthMeasurementBatches.Group? { groups.first { $0.id == a } }
  private var visible: [GalaxySSIHealthMeasurementBatches.Group] {
    var rows = Array(groups.prefix(limit))
    for id in [a, b].compactMap({ $0 }) {
      if !rows.contains(where: { $0.id == id }), let row = groups.first(where: { $0.id == id }) { rows.append(row) }
    }
    return rows
  }
  private var metrics: [GalaxySSIHealthMetric] {
    let available = Set((first?.latest.keys.map { $0 } ?? []) + (second?.latest.keys.map { $0 } ?? []))
    return GalaxySSIHealthMetric.allCases.filter { available.contains($0) }.filter {
      !abnormal || [first?.latest[$0], second?.latest[$0]].compactMap { $0 }
        .contains { GalaxySSIHealthOverviewRange.report($0)?.outside == true } }
  }
  var body: some View {
    List {
      if canRead {
        if !allowed && !failed { Text(t("permission", "Enable local measurement summaries in Health Privacy.")) }
        else if failed {
          Text(t("unavailable", "The selected sources or measurements changed. Reload and select again."))
          Button(t("retry", "Reload")) { a = nil; b = nil; report = nil; reload() }
        } else if onSelect != nil { selection }
        else {
          controls
          if first != nil {
            ForEach(metrics) { metric in
              Section(metric.title(language: language)) {
                if sizeCategory.isAccessibilityCategory || [.extraExtraLarge, .extraExtraExtraLarge].contains(sizeCategory) {
                  readings(metric, stacked: true)
                } else { readings(metric, stacked: false) }
                if second != nil {
                  if let delta = difference(metric) {
                    Text(t("difference", "B minus A") + ": " + NSDecimalNumber(decimal: delta).stringValue + " " + (first?.latest[metric]?.unit ?? ""))
                      .font(.caption).foregroundColor(.secondary)
                  } else { Text(t("not_comparable", "These measurements are not directly comparable.")).font(.caption).foregroundColor(.secondary) }
                }
                if let anchor = second?.latest[metric] ?? first?.latest[metric] {
                  NavigationLink {
                    GalaxySSIHealthTrendView(records: records, fixedMetric: metric, comparisonAnchor: anchor,
                      unverifiedComparison: second?.latest[metric] != nil
                        ? second?.requiresMethodReview(anchor) == true : first?.requiresMethodReview(anchor) == true)
                  } label: { Label(t("trend", "Measurement trend"), systemImage: "chart.xyaxis.line") }
                }
              }
            }
            if metrics.isEmpty { Text(t("empty", "No confirmed measurements in this selection.")) }
          }
          if groups.isEmpty { Text(t("empty_sources", "No retained report or table imports")) }
        }
      }
    }
    .navigationTitle(t("title", "Reports and measurement comparison"))
    .navigationBarTitleDisplayMode(.inline).privacySensitive()
    .onAppear(perform: reload)
    .onChange(of: a) { _ in report = nil; reportLimit = 30; reload() }
    .onChange(of: b) { _ in report = nil; reload() }
    .onChange(of: report) { _ in reload() }
    .onChange(of: store.profile.identityFingerprint) { _ in clear() }
    .onChange(of: scene) { if $0 == .active { reload() } else { clear() } }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { changed($0) }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.profileInputsChanged)) { changed($0) }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthOriginalStore.indexChanged)) { changed($0) }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reload() }
  }

  private var selection: some View {
    Group {
      Button(t("latest", "Latest measurements")) { choose(nil) }
      ForEach(visible) { group in Button { choose(group.id) } label: { groupLabel(group) } }
      pagination
      if groups.isEmpty { Text(t("empty_sources", "No retained report or table imports")) }
    }
  }
  private var controls: some View {
    Section {
      Picker(t("a", "Group A"), selection: $a) {
        Text(t("choose_source", "Choose import group")).tag(nil as String?)
        ForEach(visible) { Text(groupName($0)).tag(Optional($0.id)) }
      }
      Picker(t("b", "Group B"), selection: $b) {
        Text(t("none", "No comparison")).tag(nil as String?)
        ForEach(visible) { Text(groupName($0)).tag(Optional($0.id)) }
      }
      pagination
      if let selected { groupLabel(selected) }
      if b == nil, let selected, !selected.originals.isEmpty {
        Picker(t("report", "Report"), selection: $report) {
          Text(t("all_reports", "All reports")).tag(nil as UUID?)
          ForEach(selected.originals.prefix(reportLimit)) { Text($0.name).tag(Optional($0.id)) }
        }
        if selected.originals.count > reportLimit {
          Button(t("more_reports", "More reports")) { reportLimit += 30 }
        }
      }
      Toggle(t("abnormal", "Only out-of-range measurements"), isOn: $abnormal)
      Text(t("scope", "Import dates identify sources, not sampling dates. Values keep their original units and collection conditions; unverified laboratory methods are not directly comparable."))
        .font(.caption).foregroundColor(.secondary)
    }
  }
  @ViewBuilder private var pagination: some View {
    if groups.count > limit { Button(t("more_sources", "More sources")) { limit += 30 } }
  }
  private func groupName(_ group: GalaxySSIHealthMeasurementBatches.Group) -> String {
    group.importedAt.formatted(date: .abbreviated, time: .shortened) + (group.name.isEmpty ? "" : " \u{00B7} " + group.name)
  }
  private func groupLabel(_ group: GalaxySSIHealthMeasurementBatches.Group) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(groupName(group)).foregroundColor(.primary)
      Text(String(format: t("reports", "%lld source files"), Int64(group.reportCount))).font(.caption).foregroundColor(.secondary)
    }.fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
  }
  @ViewBuilder private func readings(_ metric: GalaxySSIHealthMetric, stacked: Bool) -> some View {
    if stacked {
      VStack(alignment: .leading, spacing: 12) {
        reading(first?.latest[metric], label: b == nil ? nil : "A")
        if b != nil { reading(second?.latest[metric], label: "B") }
      }
    } else {
      HStack(alignment: .top, spacing: 12) {
        reading(first?.latest[metric], label: b == nil ? nil : "A").frame(maxWidth: .infinity, alignment: .leading)
        if b != nil { reading(second?.latest[metric], label: "B").frame(maxWidth: .infinity, alignment: .leading) }
      }
    }
  }
  @ViewBuilder private func reading(_ reading: GalaxySSIHealthReading?, label: String?) -> some View {
    if let reading {
      NavigationLink { GalaxySSIHealthCenterView(records: records, initialRecordID: reading.id) } label: {
        VStack(alignment: .leading, spacing: 4) {
          if let label { Text(label).font(.caption).foregroundColor(.secondary) }
          Text(GalaxySSIHealthOverviewHistoryView.amount(reading)).font(.title3.weight(.semibold))
            .foregroundColor(GalaxySSIHealthOverviewRange.report(reading)?.outside == true ? .orange : .primary)
          Text(reading.measuredAt, style: .date).font(.caption).foregroundColor(.secondary)
          Text(reading.measuredAt, style: .time).font(.caption).foregroundColor(.secondary)
          if !reading.conditions.isEmpty { Text(reading.conditions).font(.caption).foregroundColor(.secondary) }
          if let side = reading.measurementSide { Text(sideTitle(side)).font(.caption).foregroundColor(.secondary) }
          if let reference = reading.referenceInterval, !reference.isEmpty {
            Text(t("reference", "Reported reference") + ": " + reference).font(.caption).foregroundColor(.secondary)
          }
        }.fixedSize(horizontal: false, vertical: true)
      }.buttonStyle(.plain)
    } else { Text("\u{2014}").foregroundColor(.secondary) }
  }
  private func sideTitle(_ side: String) -> String {
    t("side_" + side, side == "left" ? "Left" : side == "right" ? "Right" : "Not specified")
  }
  private func difference(_ metric: GalaxySSIHealthMetric) -> Decimal? {
    guard let a = first?.latest[metric], let b = second?.latest[metric],
          first?.requiresMethodReview(a) == false, second?.requiresMethodReview(b) == false else { return nil }
    return GalaxySSIHealthMeasurementComparison.delta(a, b)
  }
  private func choose(_ id: String?) {
    guard canRead, let archive = try? records.load(), archive.derivesOverview == true,
          id == nil || GalaxySSIHealthMeasurementBatches.groups(archive).contains(where: { $0.id == id }) else { reload(); return }
    onSelect?(id)
  }
  private func reload() {
    first = nil; second = nil; groups = []; failed = false; allowed = false
    guard canRead else { return }
    do {
      let archive = try records.load()
      allowed = archive.derivesOverview == true
      guard allowed else { return }
      groups = GalaxySSIHealthMeasurementBatches.groups(archive)
      guard onSelect == nil else { return }
      if !initialized { a = initialBatch ?? groups.first?.id; initialized = true }
      guard let selected else {
        if a != nil { throw GalaxySSIHealthRecords.Failure.stale }
        return
      }
      first = try GalaxySSIHealthMeasurementBatches.snapshot(selected, archive: archive, report: report, now: Date())
      if let b {
        guard let other = groups.first(where: { $0.id == b }) else { throw GalaxySSIHealthRecords.Failure.stale }
        second = try GalaxySSIHealthMeasurementBatches.snapshot(other, archive: archive, now: Date())
      }
    } catch { groups = []; first = nil; second = nil; failed = true }
  }
  private func changed(_ notification: Notification) { if notification.object as? String == records.owner { reload() } }
  private func clear() { first = nil; second = nil; groups = []; allowed = false; failed = false }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.measurement_comparison." + key, fallback: fallback, language: language)
  }
}
