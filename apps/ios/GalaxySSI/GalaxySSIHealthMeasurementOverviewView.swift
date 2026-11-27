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
  @State private var selection = GalaxySSIHealthMeasurementSelection()
  private var period: Period? { selection.displayed }
  @State private var abnormal = false
  let compare: (Period?) -> Void
  let edit: (GalaxySSIHealthReading) -> Void
  let manual: (GalaxySSIHealthMetric) -> Void
  @StateObject private var query = GalaxySSIHealthMeasurementQuery()
  @StateObject private var staged = GalaxySSIHealthMeasurementQuery()
  @State private var selectionFailure: GalaxySSIHealthMeasurementQuery.Failure?
  @State private var picker: PickerRequest?
  @State private var width: CGFloat = 300
  private struct PickerRequest: Identifiable { let id = UUID(); let kind: Period.Kind }
  @State private var expanded = false
  @State private var visible = false
  @State private var readingAnchor = GalaxySSIHealthMetricReadingAnchor()
  private func readingKey(_ item: Item) -> String {
    let dimension = item.series.map { series in
      AgentModelLoopRecoveryIdentity.sha256(["unit": series.key.unit, "condition": series.key.condition, "side": series.key.side])
    } ?? "missing"
    return item.metric.metric.rawValue + ":" + dimension
  }
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
        Toggle(t("abnormal", "Abnormal only"), isOn: Binding(get: { abnormal }, set: {
          readingAnchor.capture(); abnormal = $0
        })).disabled(!allowed || selection.pending != nil)
        Button { compare(period) } label: {
          Label(t("comparison", "Period comparison"), systemImage: "arrow.left.arrow.right")
            .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
        }.disabled(!allowed || selection.pending != nil)
      }.font(.subheadline)
      if selection.pending != nil { ProgressView().accessibilityLabel(t("loading", "Loading measurements")) }
      if let selectionFailure {
        Text(GalaxySSIHealthMeasurementPeriodText.failure(selectionFailure, language: language)).font(.caption).foregroundColor(.secondary)
      }
      if let failure = query.failure {
        Text(GalaxySSIHealthMeasurementPeriodText.failure(failure, language: language)).font(.caption).foregroundColor(.secondary)
        Button(t("retry", "Reload")) { reload() }
      } else if query.output == nil || !query.hasScope(scope) { ProgressView() }
      else {
        VStack(spacing: 0) {
          ForEach(displayed) { item in
            previewRow(item)
              .background(GalaxySSIHealthMetricReadingAnchor.Marker(anchor: readingAnchor, key: readingKey(item)))
            Divider()
          }
          if filtered.isEmpty { Text(t("empty", "No matching measurements")).font(.caption).foregroundColor(.secondary).padding(12) }
        }.background(RoundedRectangle(cornerRadius: 8).stroke(Color(uiColor: .separator), lineWidth: 0.5))
          .disabled(selection.pending != nil).opacity(selection.pending == nil ? 1 : 0.6)
        if filtered.count > previewSize { expansionToggle.disabled(selection.pending != nil) }
      }
    }
    .onAppear {
      visible = true
      readingAnchor.allowed = { visible && scene == .active && store.profile.identityFingerprint == records.owner &&
        UIApplication.shared.isProtectedDataAvailable }
      reload(preserve: true)
    }
    .onChange(of: displayed.map(readingKey)) { keys in readingAnchor.restore(keys: keys) }
    .onChange(of: abnormal) { _ in readingAnchor.restore(keys: displayed.map(readingKey)) }
    .onChange(of: period) { _ in readingAnchor.restore(keys: displayed.map(readingKey)) }
    .onDisappear { visible = false; readingAnchor.clear(); readingAnchor.allowed = nil; picker = nil; cancelSelection(); query.cancel(clear: false) }
    .onChange(of: timeZone) { _ in picker = nil; reload() }
    .onChange(of: allowed) { if !$0 { clearPrivate(); reload() } }
    .onChange(of: now) { _ in reload(preserve: true) }
    .onChange(of: scene) { if $0 == .active { reload() } else { clearPrivate() } }
    .onChange(of: store.profile.identityFingerprint) { _ in clearPrivate() }
    .onReceive(staged.$output) { value in
      if value != nil, let request = selection.pending {
        // Published emits before storage changes; adopt after this actor turn.
        Task { @MainActor in
          guard selection.pending == request, staged.output != nil else { return }
          finishSelection()
        }
      }
    }
    .onReceive(staged.$failure) { value in
      if let failure = value, let request = selection.pending {
        Task { @MainActor in
          guard selection.pending == request else { return }
          failSelection(failure)
        }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { changed($0) }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthOriginalStore.indexChanged)) { changed($0) }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clearPrivate() }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in clearPrivate() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reload() }
    .background(GeometryReader { geometry in
      Color.clear.onAppear { width = geometry.size.width }.onChange(of: geometry.size.width) { width = $0 }
    })
    .sheet(item: $picker) { request in
      NavigationView {
        GalaxySSIHealthMeasurementPeriodPicker(records: records, initialKind: request.kind, allowsKindChange: false, showsLatest: false) { chosen in
          guard picker?.id == request.id, visible, scene == .active, store.profile.identityFingerprint == records.owner else { return }
          select(chosen)
        }
      }.navigationViewStyle(.stack)
    }
  }
  private var heading: some View {
    HStack(alignment: .top, spacing: 12) {
      Text(GalaxySSILocalization.string("galaxyssi.health.overview_list.heading", fallback: "Measurements", language: language))
        .font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader).frame(minHeight: 44)
      Spacer(minLength: 0)
      Menu {
        Button(t("latest", "Latest measurements")) { select(nil) }
        Button(t("weeks", "By week")) { picker = PickerRequest(kind: .week) }.disabled(!allowed)
        Button(t("months", "By month")) { picker = PickerRequest(kind: .month) }.disabled(!allowed)
      } label: {
        Text(selectorLabel).font(.subheadline).lineLimit(1).truncationMode(.tail)
          .padding(.horizontal, 12).padding(.vertical, 4)
          .frame(minWidth: 48, maxWidth: max(48, min(180, width * 0.6)), minHeight: 48)
          .fixedSize(horizontal: true, vertical: false)
          .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(uiColor: .separator), lineWidth: 0.5))
      }.accessibilityLabel(selectorLabel).help(selectorLabel).accessibilityIdentifier("health-measurement-period-filter")
    }
    .background(GalaxySSIHealthMetricReadingAnchor.Marker(anchor: readingAnchor, key: "filter"))
  }
  private var expansionToggle: some View {
    Button { readingAnchor.capture(); expanded.toggle() } label: {
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
    cancelSelection()
    guard visible else { query.cancel(clear: false); return }
    guard scene == .active else { query.cancel(); return }
    query.load(records: records, scope: scope,
      zone: timeZone, preservingOutput: preserve) { store.profile.identityFingerprint == records.owner }
  }
  private var selectorLabel: String {
    selection.selected.map { GalaxySSIHealthMeasurementPeriodText.label($0, zone: timeZone, locale: locale) } ?? t("latest", "Latest measurements")
  }
  private func select(_ value: Period?) {
    guard visible, scene == .active, store.profile.identityFingerprint == records.owner else { return }
    picker = nil; selectionFailure = nil
    let previous = selection.pending
    guard let request = selection.choose(value) else {
      if previous != selection.pending { staged.cancel() }
      return
    }
    staged.load(records: records, scope: .overview(period: request.period, abnormal: false, after: nil, expanded: false, outsideIDs: []), zone: timeZone) {
      visible && scene == .active && store.profile.identityFingerprint == records.owner
    }
  }
  private func finishSelection() {
    guard visible, scene == .active, store.profile.identityFingerprint == records.owner, let request = selection.pending,
          staged.hasScope(.overview(period: request.period, abnormal: false, after: nil, expanded: false, outsideIDs: [])) else { return }
    readingAnchor.capture()
    guard query.adopt(staged, records: records) else { readingAnchor.clear(); failSelection(.changed); return }
    if selection.commit(request) { expanded = false }
    staged.cancel()
  }
  private func failSelection(_ failure: GalaxySSIHealthMeasurementQuery.Failure) {
    guard selection.pending != nil else { return }
    cancelSelection(); selectionFailure = failure
    if !query.isCurrent(records: records) { reload() }
  }
  private func cancelSelection() { selection.cancel(); staged.cancel() }
  private func clearPrivate() {
    readingAnchor.clear()
    picker = nil; cancelSelection(); selection = .init(); selectionFailure = nil
    abnormal = false; expanded = false; query.cancel()
  }
  private func changed(_ notification: Notification) { if notification.object as? String == records.owner { reload(preserve: true) } }
  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthMeasurementPeriodText.text(key, fallback, language) }
}
