import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthMeasurementPeriodComparisonView: View {
  typealias Period = GalaxySSIHealthMeasurementPeriod
  typealias Model = GalaxySSIHealthMeasurementPeriods
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.timeZone) private var timeZone
  @Environment(\.locale) private var locale
  @Environment(\.sizeCategory) private var sizeCategory
  let records: GalaxySSIHealthRecords
  var initialPeriod: Period? = nil
  let edit: (GalaxySSIHealthReading) -> Void
  @StateObject private var query = GalaxySSIHealthMeasurementQuery()
  @State private var kind = Period.Kind.week
  @State private var a: Period?
  @State private var b: Period?
  @State private var initialized = false
  @State private var abnormal = false
  @State private var choosing: Target?
  @State private var width: CGFloat = 0
  private enum Target: String, Identifiable { case a, b; var id: String { rawValue } }
  private struct Row: Identifiable {
    let key: Model.Key
    let a: Model.Series?
    let b: Model.Series?
    var id: Model.Key { key }
  }
  private var rows: [Row] {
    let left = Dictionary(uniqueKeysWithValues: (query.output?.first?.series ?? []).map { ($0.key, $0) })
    let right = Dictionary(uniqueKeysWithValues: (query.output?.second?.series ?? []).map { ($0.key, $0) })
    return Model.orderedKeys(Array(left.keys) + Array(right.keys)).compactMap { key in
      let a = left[key], b = right[key]
      guard !abnormal || a.map(Model.highlighted) == true || b.map(Model.highlighted) == true else { return nil }
      return Row(key: key, a: a, b: b)
    }
  }
  var body: some View {
    List {
      if scene == .active && store.profile.identityFingerprint == records.owner {
        controls
        if let failure = query.failure {
          Text(GalaxySSIHealthMeasurementPeriodText.failure(failure, language: language))
          Button(t("retry", "Reload")) { reload() }
        } else if query.output == nil { ProgressView() }
        else {
          ForEach(rows) { row in
            Section {
              if width < 344 || sizeCategory.isAccessibilityCategory || [.extraExtraLarge, .extraExtraExtraLarge].contains(sizeCategory) {
                VStack(alignment: .leading, spacing: 12) { cell(row.a, label: "A"); cell(row.b, label: "B") }
              } else {
                HStack(alignment: .top, spacing: 12) {
                  cell(row.a, label: "A").frame(maxWidth: .infinity, alignment: .leading)
                  cell(row.b, label: "B").frame(maxWidth: .infinity, alignment: .leading)
                }
              }
              differences(row)
              if let anchor = (row.b ?? row.a)?.latest {
                NavigationLink {
                  GalaxySSIHealthTrendView(records: records, fixedMetric: row.key.metric, comparisonAnchor: anchor,
                    unverifiedComparison: (row.b ?? row.a)?.unverifiedMethods == true)
                } label: { Label(t("trend", "Measurement trend"), systemImage: "chart.xyaxis.line") }
              }
            } header: {
              VStack(alignment: .leading, spacing: 3) {
                Text(row.key.metric.title(language: language)).font(.subheadline.weight(.semibold))
                Text(GalaxySSIHealthMeasurementPeriodText.condition(row.key.condition, language: language))
                  .font(.caption).foregroundColor(.secondary)
                if row.key.side != "unspecified" { Text(side(row.key.side)).font(.caption) }
              }.textCase(nil)
            }
          }
          if rows.isEmpty { Text(t("empty", "No matching measurements")) }
        }
      }
    }
    .listStyle(.plain).navigationTitle(t("comparison", "Period comparison"))
    .galaxySSIHealthTheme().privacySensitive()
    .background(GeometryReader { geometry in
      Color.clear.onAppear { width = geometry.size.width }.onChange(of: geometry.size.width) { width = $0 }
    })
    .onAppear {
      if !initialized { initialized = true; a = initialPeriod; kind = initialPeriod?.kind ?? .week }
      reload(preserve: true)
    }
    .onDisappear { query.cancel(clear: false) }
    .onReceive(query.$output) { output in
      if let period = output?.first?.period { a = period }
      if let period = output?.second?.period { b = period }
    }
    .onChange(of: timeZone) { _ in reload() }
    .onChange(of: scene) { if $0 == .active { reload() } else { choosing = nil; query.cancel() } }
    .onChange(of: store.profile.identityFingerprint) { _ in choosing = nil; query.cancel() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { changed($0) }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthOriginalStore.indexChanged)) { changed($0) }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in choosing = nil; query.cancel() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reload() }
    .sheet(item: $choosing) { target in
      NavigationView {
        GalaxySSIHealthMeasurementPeriodPicker(records: records, initialKind: kind, allowsKindChange: false, showsLatest: false) { period in
          if target == .a { a = period } else { b = period }
          choosing = nil; reload()
        }
      }.navigationViewStyle(.stack)
    }
  }
  private var controls: some View {
    Section {
      Picker(t("choose", "Sampling period"), selection: Binding(get: { kind }, set: selectKind)) {
        Text(t("weeks", "By week")).tag(Period.Kind.week)
        Text(t("months", "By month")).tag(Period.Kind.month)
      }.pickerStyle(.segmented)
      periodButton(t("a", "Sampling period A"), period: a, target: .a)
      periodButton(t("b", "Compare with period B"), period: b, target: .b)
      Toggle(t("abnormal", "Abnormal only"), isOn: $abnormal)
      Text(t("basis", "Grouped by sampling date, not upload. Weeks run Monday-Sunday. Matching units, conditions and sides retain the latest actual reading and count, not an average. Unfinished periods may receive new records."))
        .font(.caption).foregroundColor(.secondary)
    }
  }
  private func periodButton(_ title: String, period: Period?, target: Target) -> some View {
    Button { choosing = target } label: {
      VStack(alignment: .leading, spacing: 4) {
        Label(title, systemImage: "calendar")
        if let period { Text(GalaxySSIHealthMeasurementPeriodText.label(period, zone: timeZone, locale: locale)).font(.caption).foregroundColor(.secondary) }
      }.fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
    }
  }
  @ViewBuilder private func cell(_ series: Model.Series?, label: String) -> some View {
    if let series {
      NavigationLink { GalaxySSIHealthOverviewRecordView(records: records, record: series.latest, edit: edit) } label: {
        VStack(alignment: .leading, spacing: 4) {
          Text(label).font(.caption).foregroundColor(.secondary)
          Text(GalaxySSIHealthOverviewHistoryView.amount(series.latest)).font(.title3.weight(.semibold))
            .foregroundColor(GalaxySSIHealthOverviewRange.report(series.latest)?.outside == true ? .orange : .primary)
          Text(series.latest.measuredAt, style: .date).font(.caption).foregroundColor(.secondary)
          Text(series.latest.measuredAt, style: .time).font(.caption).foregroundColor(.secondary)
          Text(String(format: t("count", "%lld readings; latest shown"), Int64(series.count))).font(.caption).foregroundColor(.secondary)
          if series.outsideCount > 0 && GalaxySSIHealthOverviewRange.report(series.latest)?.outside != true {
            Text(String(format: t("prior_outside", "%lld readings in this period exceeded their reported range"), Int64(series.outsideCount)))
              .font(.caption).foregroundColor(.orange)
          }
          if let reference = series.latest.referenceInterval, !reference.isEmpty {
            Text(reference + " " + series.latest.unit).font(.caption).foregroundColor(.secondary)
          }
        }.fixedSize(horizontal: false, vertical: true)
      }.buttonStyle(.plain)
    } else {
      VStack(alignment: .leading, spacing: 4) { Text(label).font(.caption); Text(t("no_reading", "No reading")) }.foregroundColor(.secondary)
    }
  }
  private func differences(_ row: Row) -> some View {
    let components: [GalaxySSIHealthTrend.Component] = row.key.metric == .bloodPressure ? [.value, .diastolic] : [.value]
    let values = components.compactMap { Model.delta(row.b, row.a, component: $0) }
    return Text(values.count == components.count
      ? "A \u{2212} B: " + values.map { NSDecimalNumber(decimal: $0).stringValue }.joined(separator: " / ") + " " + row.key.unit
      : t("not_comparable", "These measurements are not directly comparable."))
      .font(.caption).foregroundColor(.secondary)
  }
  private func selectKind(_ value: Period.Kind) {
    guard value != kind else { return }
    if let old = a, let date = try? old.firstDate(zone: timeZone) { a = try? Period(kind: value, on: date, zone: timeZone) }
    kind = value; b = nil; reload()
  }
  private func reload(preserve: Bool = false) {
    guard scene == .active else { query.cancel(); return }
    query.load(records: records, scope: .comparison(kind: kind, first: a, second: b), zone: timeZone, preservingOutput: preserve) {
      store.profile.identityFingerprint == records.owner
    }
  }
  private func changed(_ notification: Notification) { if notification.object as? String == records.owner { reload(preserve: true) } }
  private func side(_ value: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.measurement_comparison.side_" + value, fallback: value, language: language)
  }
  private func t(_ key: String, _ fallback: String) -> String { GalaxySSIHealthMeasurementPeriodText.text(key, fallback, language) }
}
