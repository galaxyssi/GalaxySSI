import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthMeasurementOverviewView: View {
  typealias Period = GalaxySSIHealthMeasurementPeriod
  typealias Model = GalaxySSIHealthMeasurementPeriods
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
  @Binding var abnormal: Bool
  let choosePeriod: (Period.Kind) -> Void
  let compare: () -> Void
  let edit: (GalaxySSIHealthReading) -> Void
  let manual: (GalaxySSIHealthMetric) -> Void
  @StateObject private var query = GalaxySSIHealthMeasurementQuery()
  @State private var expanded = false
  @State private var after: Model.Cursor?
  @State private var history: [Model.Cursor?] = []
  private enum ItemID: Hashable { case series(Model.Key), missing(GalaxySSIHealthMetric) }
  private struct Item: Identifiable {
    let metric: GalaxySSIHealthOverview.Metric
    let series: Model.Series?
    var id: ItemID { series.map { .series($0.key) } ?? .missing(metric.metric) }
    var highlighted: Bool { metric.outsideRange || (series?.outsideCount ?? 0) > 0 }
  }
  private var outsideIDs: Set<UUID> {
    period == nil ? Set(latestMetrics.filter(\.outsideRange).compactMap { $0.reading?.id }) : []
  }
  private var scope: GalaxySSIHealthMeasurementQuery.Scope {
    .overview(period: period, abnormal: abnormal, after: after, expanded: expanded, outsideIDs: outsideIDs)
  }
  private var preview: [Item] {
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
    let filtered = items.filter { !abnormal || $0.highlighted }
    let highlighted = filtered.filter(\.highlighted).sorted { $0.metric.outsideRange && !$1.metric.outsideRange }
    let rest = filtered.enumerated().filter { !$0.element.highlighted }.sorted {
      ($0.element.metric.reading == nil ? 1 : 0, $0.offset) < ($1.element.metric.reading == nil ? 1 : 0, $1.offset)
    }.map(\.element)
    return highlighted + Array(rest.prefix(max(0, 5 - highlighted.count)))
  }
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
          ForEach(preview) { item in
            previewRow(item)
            Divider()
          }
          if preview.isEmpty { Text(t("empty", "No matching measurements")).font(.caption).foregroundColor(.secondary).padding(12) }
        }.background(RoundedRectangle(cornerRadius: 8).stroke(Color(uiColor: .separator), lineWidth: 0.5))
        recordExpansion
      }
    }
    .onAppear { reload(preserve: true) }
    .onDisappear { query.cancel(clear: false) }
    .onChange(of: period) { _ in reset(collapse: true) }
    .onChange(of: abnormal) { _ in reset(collapse: true) }
    .onChange(of: timeZone) { _ in reset(collapse: false) }
    .onChange(of: outsideIDs) { _ in reload(preserve: true) }
    .onChange(of: now) { _ in reload(preserve: true) }
    .onChange(of: scene) { if $0 == .active { reload() } else { query.cancel() } }
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
        Button(t("latest", "Latest measurements")) { period = nil; reset(collapse: true) }
        Button(t("weeks", "By week")) { choosePeriod(.week) }.disabled(!allowed)
        Button(t("months", "By month")) { choosePeriod(.month) }.disabled(!allowed)
      } label: {
        Label(period.map { GalaxySSIHealthMeasurementPeriodText.label($0, zone: timeZone, locale: locale) }
          ?? t("latest", "Latest measurements"), systemImage: "calendar")
          .font(.subheadline).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
      }.accessibilityIdentifier("health-measurement-period-filter")
    }
  }
  private var recordExpansion: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        expanded.toggle(); after = nil; history = []; reload()
      } label: {
        HStack {
          Spacer()
          Text(expanded ? t("collapse_records", "Collapse records") : t("expand_records", "View all records"))
          Image(systemName: expanded ? "chevron.up" : "chevron.right")
          Spacer()
        }.font(.subheadline).frame(minHeight: 56)
      }.accessibilityIdentifier("health-overview-all-records")
      if expanded, let page = query.output?.records {
        ForEach(page.readings) { reading in
          NavigationLink { GalaxySSIHealthOverviewRecordView(records: records, record: reading, edit: edit) } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(reading.metric.title(language: language)).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
              Text(GalaxySSIHealthOverviewHistoryView.amount(reading)).foregroundColor(.primary)
              Text(reading.measuredAt, style: .date).font(.caption).foregroundColor(.secondary)
              Text(reading.measuredAt, style: .time).font(.caption).foregroundColor(.secondary)
              Text(GalaxySSIHealthMeasurementPeriodText.condition(reading.normalizedMeasurementCondition, language: language))
                .font(.caption).foregroundColor(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).fixedSize(horizontal: false, vertical: true)
          }.buttonStyle(.plain).id(reading.id)
          Divider()
        }
        if page.readings.isEmpty { Text(t("empty", "No matching measurements")).font(.caption).foregroundColor(.secondary) }
        HStack {
          if !history.isEmpty {
            Button { after = history.removeLast(); reload() } label: { Label(t("previous_page", "Previous page"), systemImage: "chevron.left") }
          }
          Spacer(minLength: 4)
          Text(String(format: t("page", "Page %lld"), Int64(history.count + 1))).font(.caption).foregroundColor(.secondary)
          if let next = page.next {
            Button { history.append(after); after = next; reload() } label: { Label(t("next_page", "Next page"), systemImage: "chevron.right") }
          }
        }.font(.subheadline).frame(minHeight: 44)
      }
    }
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
  private func reset(collapse: Bool) { if collapse { expanded = false }; after = nil; history = []; reload() }
  private func reload(preserve: Bool = false) {
    guard scene == .active else { query.cancel(); return }
    query.load(records: records, scope: scope,
      zone: timeZone, preservingOutput: preserve) { store.profile.identityFingerprint == records.owner }
  }
  private func changed(_ notification: Notification) { if notification.object as? String == records.owner { reload(preserve: true) } }
  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthMeasurementPeriodText.text(key, fallback, language) }
}
