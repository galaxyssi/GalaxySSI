import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthMeasurementOverviewView: View {
  typealias Period = GalaxySSIHealthMeasurementPeriod
  typealias Model = GalaxySSIHealthMeasurementPeriods
  typealias Item = GalaxySSIHealthMeasurementList.Item
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.locale) private var locale
  @Environment(\.timeZone) private var timeZone
  let records: GalaxySSIHealthRecords
  let latestMetrics: [GalaxySSIHealthOverview.Metric]
  let birthDate: Date?
  let now: Date
  let allowed: Bool
  @Binding var period: Period?
  @State private var abnormal = false
  let choosePeriod: (Period.Kind) -> Void
  let compare: () -> Void
  let edit: (GalaxySSIHealthReading) -> Void
  let manual: (GalaxySSIHealthMetric) -> Void
  @StateObject private var query = GalaxySSIHealthMeasurementQuery()
  @State private var expanded = false
  @State private var visible = false
  private var scope: GalaxySSIHealthMeasurementQuery.Scope {
    .overview(period: period, abnormal: false, after: nil, expanded: false, outsideIDs: [])
  }
  private var items: [Item] {
    guard query.hasScope(scope), let summary = query.output?.first, summary.period == period else { return [] }
    var items: [Item] = []
    let cutoff = Period.calendar(timeZone).date(byAdding: .day, value: -6, to: Period.calendar(timeZone).startOfDay(for: now)) ?? now
    if period == nil {
      let byMetric = Dictionary(uniqueKeysWithValues: summary.series.map { ($0.key.metric, $0) })
      for baseline in latestMetrics where baseline.metric != .steps {
        let series = byMetric[baseline.metric], reading = series?.latest
        let ranges = baseline.reading == reading ? baseline.ranges : [reading.flatMap(GalaxySSIHealthOverviewRange.report)].compactMap { $0 }
        items.append(Item(metric: .init(metric: baseline.metric, reading: reading,
          freshness: reading.map { $0.measuredAt >= cutoff ? .recent : .stale } ?? .missing, ranges: ranges), series: series))
      }
      let shown = Set(items.map { $0.metric.metric })
      for series in summary.series where !shown.contains(series.key.metric) && visibleMetric(series.key.metric) {
        items.append(item(series, cutoff: cutoff))
      }
    } else {
      items = summary.series.filter { visibleMetric($0.key.metric) }.map { item($0, cutoff: cutoff) }
    }
    return items
  }
  private var filtered: [Item] { GalaxySSIHealthMeasurementList.rows(items, abnormal: allowed && abnormal) }
  private var previewSize: Int { GalaxySSIHealthMeasurementList.previewSize(filtered) }
  private var displayed: [Item] { expanded ? filtered : Array(filtered.prefix(previewSize)) }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      heading
      HStack(alignment: .top, spacing: 12) {
        Toggle(t("abnormal", "Abnormal only"), isOn: $abnormal).disabled(!allowed)
        Button(action: compare) {
          Label(t("comparison", "Period comparison"), systemImage: "arrow.left.arrow.right")
            .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
        }.disabled(!allowed)
      }.font(.subheadline)
      if let failure = query.failure {
        Text(GalaxySSIHealthMeasurementPeriodText.failure(failure, language: language)).font(.caption).foregroundColor(.secondary)
        Button(t("retry", "Reload")) { reload() }
      } else if query.output == nil || !query.hasScope(scope) { ProgressView() }
      else {
        VStack(spacing: 0) {
          ForEach(displayed) { item in
            previewRow(item)
            Divider()
          }
          if filtered.isEmpty { Text(t("empty", "No matching measurements")).font(.caption).foregroundColor(.secondary).padding(12) }
        }.background(RoundedRectangle(cornerRadius: 8).stroke(Color(uiColor: .separator), lineWidth: 0.5))
        if filtered.count > previewSize { expansionToggle }
      }
    }
    .onAppear { visible = true; reload(preserve: true) }
    .onDisappear { visible = false; query.cancel(clear: false) }
    .onChange(of: period) { _ in expanded = false; reload() }
    .onChange(of: timeZone) { _ in reload() }
    .onChange(of: allowed) { if !$0 { abnormal = false } }
    .onChange(of: now) { _ in reload(preserve: true) }
    .onChange(of: scene) { if $0 == .active { reload() } else { abnormal = false; query.cancel() } }
    .onChange(of: store.profile.identityFingerprint) { _ in query.cancel() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { changed($0) }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthOriginalStore.indexChanged)) { changed($0) }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in query.cancel() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reload() }
  }
  private var heading: some View {
    HStack(alignment: .top, spacing: 12) {
      Text(GalaxySSILocalization.string("galaxyssi.health.overview_list.heading", fallback: "Measurements", language: language))
        .font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader).frame(minHeight: 44)
      Spacer(minLength: 0)
      Menu {
        Button(t("latest", "Latest measurements")) { period = nil; expanded = false }
        Button(t("weeks", "By week")) { choosePeriod(.week) }.disabled(!allowed)
        Button(t("months", "By month")) { choosePeriod(.month) }.disabled(!allowed)
      } label: {
        Label(period.map { GalaxySSIHealthMeasurementPeriodText.label($0, zone: timeZone, locale: locale) }
          ?? t("latest", "Latest measurements"), systemImage: "calendar")
          .font(.subheadline).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
      }.accessibilityIdentifier("health-measurement-period-filter")
    }
  }
  private var expansionToggle: some View {
    Button { expanded.toggle() } label: {
      HStack {
        Spacer()
        Text(expanded ? t("collapse_records", "Collapse records") : t("expand_records", "View all records"))
        Image(systemName: expanded ? "chevron.up" : "chevron.right")
        Spacer()
      }.font(.subheadline).frame(minHeight: 56)
    }.accessibilityIdentifier("health-overview-all-records")
  }
  @ViewBuilder private func previewRow(_ item: Item) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if period != nil, let reading = item.metric.reading {
        NavigationLink {
          GalaxySSIHealthTrendView(records: records, fixedMetric: reading.metric, comparisonAnchor: reading,
            unverifiedComparison: item.series?.unverifiedMethods == true)
        } label: { summary(item) }.buttonStyle(.plain)
      } else {
        NavigationLink {
          GalaxySSIHealthOverviewMetricDetailView(records: records, metric: item.metric.metric, open: edit, manual: manual)
        } label: { summary(item) }.buttonStyle(.plain)
      }
      if period != nil, let series = item.series, series.outsideCount > 0 && !item.metric.outsideRange {
        Text(String(format: t("prior_outside", "%lld readings in this period exceeded their reported range"), Int64(series.outsideCount)))
          .font(.caption).foregroundColor(.orange).padding(.horizontal, 12).padding(.bottom, 8)
      }
    }
  }
  private func summary(_ item: Item) -> some View {
    GalaxySSIHealthOverviewMetricRow(item: item.metric, records: records, open: edit, manual: manual,
      birthDate: birthDate, summaryOnly: true, showsGuidance: period == nil, caption: caption(item)).padding(.horizontal, 12)
  }
  private func caption(_ item: Item) -> String? {
    guard let reading = item.metric.reading else { return nil }
    let formatter = DateFormatter(); formatter.locale = locale; formatter.timeZone = timeZone; formatter.dateStyle = .short
    var parts = [formatter.string(from: reading.measuredAt)]
    let condition = reading.normalizedMeasurementCondition
    if condition != "unspecified" && !(reading.metric == .glucose && condition == "fasting") {
      parts.append(GalaxySSIHealthMeasurementPeriodText.condition(condition, language: language))
    }
    if period != nil, let series = item.series { parts.append(String(format: t("count", "%lld readings; latest shown"), Int64(series.count))) }
    return parts.joined(separator: " \u{00B7} ")
  }
  private func item(_ series: Model.Series, cutoff: Date) -> Item {
    Item(metric: .init(metric: series.key.metric, reading: series.latest, freshness: series.latest.measuredAt >= cutoff ? .recent : .stale,
      ranges: [GalaxySSIHealthOverviewRange.report(series.latest)].compactMap { $0 }), series: series)
  }
  private func visibleMetric(_ metric: GalaxySSIHealthMetric) -> Bool { ![.steps, .temperature, .oxygenSaturation].contains(metric) }
  private func reload(preserve: Bool = false) {
    guard visible else { query.cancel(clear: false); return }
    guard scene == .active else { query.cancel(); return }
    query.load(records: records, scope: scope,
      zone: timeZone, preservingOutput: preserve) { store.profile.identityFingerprint == records.owner }
  }
  private func changed(_ notification: Notification) { if notification.object as? String == records.owner { reload(preserve: true) } }
  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthMeasurementPeriodText.text(key, fallback, language) }
}
