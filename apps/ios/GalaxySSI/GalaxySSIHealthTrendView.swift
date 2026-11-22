import SwiftUI
import UIKit

struct GalaxySSIHealthTrendDevice: Identifiable {
  let id: UUID
  let name: String?

  static func options(in readings: [GalaxySSIHealthReading], metric: GalaxySSIHealthMetric) -> [Self] {
    let receipts = readings.filter { !$0.deleted && $0.metric == metric }.compactMap(\.bluetoothReceipt)
    return Dictionary(grouping: receipts, by: \.device).map { id, matches in
      let name = matches.sorted { $0.receivedAt > $1.receivedAt }.lazy
        .compactMap { $0.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
      return Self(id: id, name: name)
    }.sorted { $0.id.uuidString < $1.id.uuidString }
  }

  static func matching(_ readings: [GalaxySSIHealthReading], device: UUID?) -> [GalaxySSIHealthReading] {
    guard let device else { return readings }
    return readings.filter { $0.bluetoothReceipt?.device == device }
  }
}

struct GalaxySSIHealthTrend {
  enum Aggregation: String, CaseIterable {
    case mean, min, max, latest
  }

  enum Source: String, CaseIterable {
    case all, manual, bluetooth, table, healthKit, report

    func includes(_ reading: GalaxySSIHealthReading) -> Bool {
      switch self {
      case .all: return true
      case .manual: return reading.tableSource == nil && reading.bluetoothReceipt == nil &&
          reading.healthKitSource == nil && reading.reportSource == nil
      case .bluetooth: return reading.tableSource == nil && reading.bluetoothReceipt != nil
      case .table: return reading.tableSource != nil
      case .healthKit: return reading.healthKitSource != nil
      case .report: return reading.reportSource != nil
      }
    }
  }

  enum HealthOrigin: Hashable {
    case all, application(String), dailySteps, unidentified

    static func recorded(in reading: GalaxySSIHealthReading) -> Self? {
      guard let receipt = reading.healthKitSource else { return nil }
      if let id = receipt.origin {
        let bytes = id.utf8
        guard (1...255).contains(bytes.count), bytes.first != 46, bytes.last != 46,
              !id.contains(".."), bytes.contains(where: { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }),
              bytes.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) ||
                (97...122).contains($0) || $0 == 45 || $0 == 46 }) else { return .unidentified }
        return .application(id)
      }
      return reading.metric == .steps && receipt.name == nil ? .dailySteps : .unidentified
    }

    fileprivate var sortKey: String {
      switch self {
      case .all: return ""
      case .dailySteps: return "0"
      case .application(let id): return "1" + id
      case .unidentified: return "2"
      }
    }
  }

  struct OriginPage {
    struct Option: Identifiable {
      let id: HealthOrigin
      let name: String?
    }
    let options: [Option]
    let hasMore: Bool
  }

  static func origins(in readings: [GalaxySSIHealthReading], metric: GalaxySSIHealthMetric,
                      from: Date, through: Date, after: HealthOrigin? = nil) -> OriginPage {
    let limit = 30
    var candidates: [HealthOrigin: GalaxySSIHealthReading] = [:]
    let cursor = after?.sortKey ?? ""
    for reading in readings where !reading.deleted && reading.metric == metric &&
      reading.measuredAt >= from && reading.measuredAt <= through {
      guard let origin = HealthOrigin.recorded(in: reading), origin.sortKey > cursor else { continue }
      if let existing = candidates[origin] {
        if (reading.measuredAt, reading.id.uuidString) > (existing.measuredAt, existing.id.uuidString) {
          candidates[origin] = reading
        }
      } else if candidates.count <= limit {
        candidates[origin] = reading
      } else if let last = candidates.keys.max(by: { $0.sortKey < $1.sortKey }), origin.sortKey < last.sortKey {
        candidates.removeValue(forKey: last)
        candidates[origin] = reading
      }
    }
    let keys = candidates.keys.sorted { $0.sortKey < $1.sortKey }
    return OriginPage(options: keys.prefix(limit).map { .init(id: $0, name: candidates[$0]?.healthKitSource?.name) },
                      hasMore: keys.count > limit)
  }

  enum Component: String, CaseIterable {
    case value, diastolic, pulse

    func value(in reading: GalaxySSIHealthReading) -> Decimal? {
      switch self {
      case .value: return reading.value
      case .diastolic: return reading.diastolic
      case .pulse: return reading.pulse
      }
    }
  }

  struct Point: Identifiable {
    let id: Int
    let day: Date
    let readings: [GalaxySSIHealthReading]
    let mean: Decimal?
    var forceUnverifiedMethods = false

    var revisions: [UUID: Int] { Dictionary(uniqueKeysWithValues: readings.map { ($0.id, $0.revision) }) }
    var unverifiedMethods: Bool { forceUnverifiedMethods || readings.contains(where: GalaxySSIHealthMeasurementComparison.unverifiedMethod) }

    func extremum(_ aggregation: Aggregation, component: Component) -> GalaxySSIHealthReading? {
      guard aggregation != .mean else { return nil }
      if aggregation == .latest {
        return readings.filter { component.value(in: $0) != nil }.max { ($0.measuredAt, $0.id.uuidString) < ($1.measuredAt, $1.id.uuidString) }
      }
      return readings.reduce(nil as GalaxySSIHealthReading?) { best, reading in
        guard let value = component.value(in: reading) else { return best }
        guard let best, let previous = component.value(in: best) else { return reading }
        return (aggregation == .min ? value < previous : value > previous) ? reading : best
      }
    }

    func value(_ aggregation: Aggregation, component: Component) -> Decimal? {
      aggregation == .mean ? (unverifiedMethods ? nil : mean) : extremum(aggregation, component: component).flatMap { component.value(in: $0) }
    }
  }

  struct ChartDatum: Identifiable {
    let point: Point
    let value: Decimal
    var id: Int { point.id }

    func matches(_ other: Self) -> Bool {
      id == other.id && point.day == other.point.day && value == other.value && point.revisions == other.point.revisions
    }
  }

  func chartData(_ aggregation: Aggregation, component: Component) -> [ChartDatum] {
    points.compactMap { point in
      point.value(aggregation, component: component).map { ChartDatum(point: point, value: $0) }
    }
  }

  let points: [Point]
  let minimum: Decimal?
  let maximum: Decimal?
  let mean: Decimal?
  var unverifiedMethods: Bool { points.contains(where: \.unverifiedMethods) }

  init(current: [GalaxySSIHealthReading], metric: GalaxySSIHealthMetric, component: Component,
       now: Date, dayCount: Int, calendar: Calendar, unit: String? = nil, source: Source = .all,
       healthOrigin: HealthOrigin = .all, forceUnverifiedMethods: Bool = false) {
    let today = calendar.startOfDay(for: now)
    let dates = (0..<max(1, min(dayCount, 366))).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    let days = Set(dates)
    let scoped = current.filter {
      !$0.deleted && $0.metric == metric && $0.measuredAt <= now && source.includes($0) &&
        (healthOrigin == .all || HealthOrigin.recorded(in: $0) == healthOrigin) &&
        (component == .pulse || $0.unit == (unit ?? metric.unit)) &&
        days.contains(calendar.startOfDay(for: $0.measuredAt)) && component.value(in: $0) != nil
    }
    let grouped = Dictionary(grouping: scoped) { calendar.startOfDay(for: $0.measuredAt) }
    points = dates.enumerated().map { index, day in
      let readings = (grouped[day] ?? []).sorted {
        $0.measuredAt == $1.measuredAt ? $0.id.uuidString < $1.id.uuidString : $0.measuredAt < $1.measuredAt
      }
      return Point(id: index, day: day, readings: readings,
                   mean: forceUnverifiedMethods || readings.contains(where: GalaxySSIHealthMeasurementComparison.unverifiedMethod) ? nil :
                     Self.average(readings.compactMap { component.value(in: $0) }), forceUnverifiedMethods: forceUnverifiedMethods)
    }
    let values = scoped.compactMap { component.value(in: $0) }
    minimum = values.min()
    maximum = values.max()
    mean = forceUnverifiedMethods || scoped.contains(where: GalaxySSIHealthMeasurementComparison.unverifiedMethod) ? nil : Self.average(values)
  }

  var validDays: Int { points.filter { !$0.readings.isEmpty }.count }

  private static func average(_ values: [Decimal]) -> Decimal? {
    guard !values.isEmpty else { return nil }
    let divisor = Decimal(values.count)
    let result = values.reduce(Decimal.zero) { $0 + $1 / divisor }
    return result.isNaN ? nil : result
  }
}

@MainActor
struct GalaxySSIHealthTrendView: View {
  @Environment(\.galaxySSIAtlasPinnedAnalysis) private var atlasPinnedAnalysis
  @Environment(\.galaxySSIAtlasAnalysisSelection) private var atlasAnalysisSelection
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  @Environment(\.locale) private var locale
  let records: GalaxySSIHealthRecords
  private let fixedMetric: GalaxySSIHealthMetric?
  private let recordMeasurement: ((GalaxySSIHealthMetric) -> Void)?
  private let comparisonAnchor: GalaxySSIHealthReading?
  private let unverifiedComparison: Bool
  private let atlasWindow: Binding<GalaxySSIHealthAtlasWindow>?
  @State private var metric: GalaxySSIHealthMetric
  @State private var component = GalaxySSIHealthTrend.Component.value
  @State private var selectedUnit: String?
  @State private var days = 7
  @State private var aggregation = GalaxySSIHealthTrend.Aggregation.mean
  @State private var source = GalaxySSIHealthTrend.Source.all
  @State private var snapshotTime = Date()
  @State private var snapshotCalendar: Calendar?
  @State private var focusedDay: Date?
  @State private var allowed = false
  @State private var device: UUID?
  @State private var devices: [GalaxySSIHealthTrendDevice] = []
  @State private var trend: GalaxySSIHealthTrend?
  @State private var trendVersions: [String] = []
  @State private var explanation: GalaxySSIHealthTrendAnalysis?
  @State private var recordAfterExplanation: GalaxySSIHealthMetric?
  @State private var fallbackEditor: GalaxySSIHealthMetric?
  @State private var selected: GalaxySSIHealthTrend.Point?
  @State private var showsChartData = false
  @State private var changed = false
  @State private var error = false
  @State private var shown = 30
  @State private var jumpTarget: UUID?
  @State private var origin = GalaxySSIHealthTrend.HealthOrigin.all
  @State private var originPage: GalaxySSIHealthTrend.OriginPage?
  @State private var originCursors: [GalaxySSIHealthTrend.HealthOrigin] = []
  @State private var selectedOriginTitle: String?
  @State private var atlasAnalysisIdentity: GalaxySSIHealthAtlasTrendAction.Identity?
  @State private var protectedDataBlocked = false

  init(records: GalaxySSIHealthRecords, fixedMetric: GalaxySSIHealthMetric? = nil,
       recordMeasurement: ((GalaxySSIHealthMetric) -> Void)? = nil, comparisonAnchor: GalaxySSIHealthReading? = nil,
       unverifiedComparison: Bool = false, atlasWindow: Binding<GalaxySSIHealthAtlasWindow>? = nil) {
    self.records = records
    self.fixedMetric = fixedMetric
    self.recordMeasurement = recordMeasurement
    self.comparisonAnchor = comparisonAnchor
    self.unverifiedComparison = unverifiedComparison
    self.atlasWindow = atlasWindow
    _metric = State(initialValue: fixedMetric ?? .bloodPressure)
    if atlasWindow != nil { _aggregation = State(initialValue: .latest) }
    if let comparisonAnchor {
      _selectedUnit = State(initialValue: comparisonAnchor.unit)
      _source = State(initialValue: Self.trendSource(comparisonAnchor))
      _device = State(initialValue: comparisonAnchor.bluetoothReceipt?.device)
      _origin = State(initialValue: GalaxySSIHealthTrend.HealthOrigin.recorded(in: comparisonAnchor) ?? .all)
      _aggregation = State(initialValue: unverifiedComparison || GalaxySSIHealthMeasurementComparison.unverifiedMethod(comparisonAnchor) ? .latest : .mean)
      _days = State(initialValue: 180)
    }
  }

  var body: some View {
    List {
      if scene == .active {
        if error {
          Text(t("unavailable", "Trends unavailable"))
          Button(t("refresh", "Refresh"), action: reload)
        } else if !allowed {
          Text(t("permission", "Enable the local measurement summary in Health Privacy to view trends."))
        } else {
          if fixedMetric == nil {
            Picker(t("metric", "Measurement"), selection: $metric) {
              ForEach(GalaxySSIHealthMetric.allCases) { Text(metricTitle($0)).tag($0) }
            }
          } else {
            Text(metricTitle(metric))
          }
          if let comparisonAnchor {
            if !comparisonAnchor.conditions.isEmpty { Text(comparisonAnchor.conditions).font(.caption).foregroundColor(.secondary) }
            if let side = comparisonAnchor.measurementSide {
              Text(GalaxySSILocalization.string("galaxyssi.health.measurement_comparison.side_" + side,
                fallback: side == "left" ? "Left" : side == "right" ? "Right" : "Not specified", language: language))
                .font(.caption).foregroundColor(.secondary)
            }
          }
          if metric == .bloodPressure {
            Picker(t("component", "Component"), selection: $component) {
              Text(t("systolic", "Systolic")).tag(GalaxySSIHealthTrend.Component.value)
              Text(t("diastolic", "Diastolic")).tag(GalaxySSIHealthTrend.Component.diastolic)
              Text(t("pulse", "Pulse")).tag(GalaxySSIHealthTrend.Component.pulse)
            }
          }
          if component != .pulse && metric.units.count > 1 {
            Picker(t("unit", "Unit"), selection: Binding(
              get: { selectedUnit ?? metric.unit }, set: { selectedUnit = $0; reload() })) {
              ForEach(metric.units, id: \.self) { Text($0).tag($0) }
            }
            .disabled(comparisonAnchor != nil)
          }
          if let atlasWindow {
            Picker(t("period", "Period"), selection: atlasWindow) {
              ForEach(GalaxySSIHealthAtlasWindow.allCases, id: \.self) { window in
                Text(GalaxySSIHealthAtlasText.get("health_atlas_" + window.rawValue, language)).tag(window)
              }
            }
          } else {
            Picker(t("period", "Period"), selection: $days) {
              ForEach([7, 30, 90], id: \.self) { value in
                Text(String(format: t("days", "%lld days"), Int64(value))).tag(value)
              }
              if comparisonAnchor != nil { Text(t("six_months", "6 months")).tag(180) }
            }
          }
          if source != .healthKit && (!devices.isEmpty || device != nil) {
            Picker(t("bluetooth_filter", "Bluetooth device"), selection: $device) {
              Text(t("all_devices", "No device filter")).tag(nil as UUID?)
              ForEach(devices) { option in
                Text(deviceTitle(option)).tag(Optional(option.id))
              }
              if let device, !devices.contains(where: { $0.id == device }) {
                Text(t("device_unavailable", "Selected device unavailable")).tag(Optional(device))
              }
            }
            .disabled(comparisonAnchor != nil)
          }
          Picker(t("aggregation", "Aggregation"), selection: $aggregation) {
            ForEach(trend?.unverifiedMethods == true ? [.latest] : GalaxySSIHealthTrend.Aggregation.allCases, id: \.self) {
              Text(aggregationTitle($0)).tag($0)
            }
          }
          Picker(t("source", "Source"), selection: $source) {
            ForEach(GalaxySSIHealthTrend.Source.allCases, id: \.self) { Text(sourceTitle($0)).tag($0) }
          }.disabled(comparisonAnchor != nil)
          if source == .healthKit { originPicker.disabled(comparisonAnchor != nil) }
          if changed {
            Text(t("changed", "Measurements changed. Refresh to view current results."))
            Button(t("refresh", "Refresh"), action: reload)
          } else if let trend {
            if atlasWindow != nil,
               let reading = trend.points.flatMap(\.readings).filter({ component.value(in: $0) != nil })
                .max(by: { ($0.measuredAt, $0.id.uuidString) < ($1.measuredAt, $1.id.uuidString) }),
               let value = component.value(in: reading),
               let point = trend.points.first(where: { $0.readings.contains(where: { $0.id == reading.id }) }) {
              Section(t("latest", "Latest")) {
                statistic(t("latest", "Latest"), value)
                Text(reading.measuredAt, style: .date)
                Text(reading.measuredAt, style: .time)
                Text(readingSource(reading)).font(.caption).foregroundColor(.secondary)
                Button(GalaxySSIHealthAtlasText.get("health_atlas_source", language)) { selected = point }
              }
            }
            if let minimum = trend.minimum, let maximum = trend.maximum {
              if !atlasPinnedAnalysis {
                Button(action: explainTrend) {
                  Label(t("explain", "Explain this trend"), systemImage: "text.bubble")
                }
              }
              Section(t("summary", "Summary")) {
                Text(String(format: t("coverage", "%lld of %lld days with readings"), Int64(trend.validDays), Int64(trend.points.count)))
                if let average = trend.mean { statistic(t("mean", "Mean"), average) }
                statistic(t("min", "Minimum"), minimum)
                statistic(t("max", "Maximum"), maximum)
                if trend.unverifiedMethods {
                  Text(t("unverified_methods", "Laboratory methods are unverified; results are shown separately.")).font(.caption).foregroundColor(.secondary)
                }
                let data = trend.chartData(aggregation, component: component)
                chart(trend, data: data)
                Button { toggleChartData(data) } label: {
                  Label(t("chart_data", "Chart data"), systemImage: showsChartData ? "chevron.down" : "list.bullet")
                }
                .disabled(data.isEmpty)
                if showsChartData {
                  ForEach(data.reversed(), content: chartDatumRow)
                }
              }
            } else {
              Text(t("empty", "No confirmed measurements for this period."))
            }
          }
        }
      }
    }
    .navigationTitle(t("title", "Measurement Trends"))
    .galaxySSIHealthTheme()
    .onAppear(perform: reload)
    .onChange(of: metric) { _ in component = .value; selectedUnit = nil; resetOrigins(); reload() }
    .onChange(of: component) { _ in reload() }
    .onChange(of: days) { _ in resetOrigins(); reload() }
    .onChange(of: device) { _ in reload() }
    .onChange(of: calendar) { _ in reload() }
    .onChange(of: atlasWindow?.wrappedValue) { _ in resetOrigins(); reload() }
    .onChange(of: timeZone) { _ in reload() }
    .onChange(of: scene) { if $0 == .background { device = nil; devices = [] } }
    .onChange(of: source) { _ in resetOrigins(); reload() }
    .onDisappear { resetOrigins(); selected = nil; trend = nil; showsChartData = false; atlasAnalysisIdentity = nil }
    .onChange(of: aggregation) { _ in
      selected = nil; focusedDay = nil; showsChartData = false
      if atlasPinnedAnalysis { reload() }
    }
    .onChange(of: scene) { phase in
      if phase == .active { reload() }
      else { trend = nil; selected = nil; focusedDay = nil; allowed = false; showsChartData = false; resetOrigins() }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.trendInputsChanged)) { event in
      guard event.object as? String == records.owner, scene == .active else { return }
      invalidate()
    }
    .onChange(of: scene) { phase in
      if phase != .active {
        trendVersions = []; explanation = nil; recordAfterExplanation = nil; fallbackEditor = nil
        atlasAnalysisIdentity = nil
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
      protectedDataBlocked = true
      atlasAnalysisIdentity = nil; trend = nil; selected = nil; focusedDay = nil; allowed = false
      trendVersions = []; explanation = nil; showsChartData = false; resetOrigins()
      device = nil; devices = []; recordAfterExplanation = nil; fallbackEditor = nil
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
      protectedDataBlocked = false
      if scene == .active { reload() }
    }
    .safeAreaInset(edge: .bottom) {
      if atlasPinnedAnalysis { GalaxySSIHealthAtlasPinnedAnalysisButton(enabled: atlasAnalysisReady, action: explainTrend) }
    }
    .sheet(item: $explanation, onDismiss: {
      if let metric = recordAfterExplanation {
        recordAfterExplanation = nil
        if scene == .active {
          if let recordMeasurement { recordMeasurement(metric) }
          else { fallbackEditor = metric }
        }
      }
    }) { route in
      NavigationView {
        GalaxySSIHealthAssistantView(records: records, trendScope: route) { _ in
          recordAfterExplanation = route.spec.metric
          explanation = nil
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) {
          Button(t("done", "Done")) { explanation = nil }
        } }
      }.navigationViewStyle(.stack)
    }
    .sheet(item: $fallbackEditor, onDismiss: reload) { metric in
      NavigationView {
        GalaxySSIHealthCenterView(records: records, initialRecordMetric: metric)
          .toolbar { ToolbarItem(placement: .cancellationAction) {
            Button(t("done", "Done")) { fallbackEditor = nil }
          } }
      }.navigationViewStyle(.stack)
    }
    .sheet(item: $selected) { point in
      NavigationView {
        ScrollViewReader { proxy in
          List {
            if scene == .active && allowed && !changed {
              Section(t("audit", "Point audit")) {
                Text(metricTitle(metric) + " · " + componentTitle + " · " + unit)
                Text(aggregationTitle(aggregation) + " · " + (selectedOriginTitle ?? sourceTitle(source)))
                Text(point.day, style: .date)
                if let value = point.value(aggregation, component: component) {
                  statistic(aggregationTitle(aggregation), value)
                }
                if let exact = point.extremum(aggregation, component: component),
                   let index = point.readings.firstIndex(where: { $0.id == exact.id }) {
                  Button(t("extremum", "Jump to the exact contributing revision")) {
                    if shown > index {
                      proxy.scrollTo(exact.id, anchor: .center)
                    } else {
                      jumpTarget = exact.id
                      shown = index + 1
                    }
                  }
                }
              }
              ForEach(point.readings.prefix(shown)) { reading in
                VStack(alignment: .leading, spacing: 4) {
                  if let value = component.value(in: reading) { Text(number(value) + " " + unit) }
                  Text(reading.measuredAt, style: .time).foregroundColor(.secondary)
                  Text(readingSource(reading)).foregroundColor(.secondary)
                  Text(String(format: t("revision", "Revision %lld"), Int64(reading.revision)))
                    .foregroundColor(.secondary)
                }
                .id(reading.id)
              }
              if point.readings.count > shown { Button(t("more", "Show more")) { shown += 30 } }
            }
          }
          .onChange(of: shown) { _ in
            if let jumpTarget {
              proxy.scrollTo(jumpTarget, anchor: .center)
              self.jumpTarget = nil
            }
          }
          .navigationTitle(point.day.formatted(date: .abbreviated, time: .omitted))
          .galaxySSIHealthTheme()
          .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button(t("done", "Done")) { selected = nil }
          } }
        }
      }
      .navigationViewStyle(.stack)
    }
  }

  private func reload() {
    atlasAnalysisIdentity = nil
    guard scene == .active, !protectedDataBlocked, UIApplication.shared.isProtectedDataAvailable else { return }
    selected = nil
    showsChartData = false
    focusedDay = nil
    trend = nil
    trendVersions = []
    changed = false
    do {
      let archive = try records.load()
      allowed = archive.derivesOverview == true
      error = false
      guard allowed else { devices = []; resetOrigins(); return }
      let current = archive.current
      devices = source == .healthKit ? [] : GalaxySSIHealthTrendDevice.options(in: current, metric: metric)
      snapshotTime = comparisonAnchor.map { min($0.measuredAt, Date()) } ?? Date()
      var local = calendar
      local.timeZone = timeZone
      snapshotCalendar = local
      if let atlasWindow { days = atlasWindow.wrappedValue.days(through: snapshotTime, calendar: local) }
      if atlasWindow != nil, selectedUnit == nil,
         let latest = trendSpec.cohort(current).filter({ metric.units.contains($0.unit) && component.value(in: $0) != nil })
          .max(by: { ($0.measuredAt, $0.id.uuidString) < ($1.measuredAt, $1.id.uuidString) }) {
        selectedUnit = latest.unit
      }
      if source == .healthKit {
        let today = local.startOfDay(for: snapshotTime)
        let start = local.date(byAdding: .day, value: 1 - days, to: today) ?? today
        originPage = GalaxySSIHealthTrend.origins(in: current, metric: metric, from: start, through: snapshotTime,
                                                  after: originCursors.last)
      }
      let spec = trendSpec
      trend = spec.chart(current)
      if trend?.unverifiedMethods == true { aggregation = .latest }
      trendVersions = spec.versions(current)
      if atlasPinnedAnalysis { atlasAnalysisIdentity = currentAtlasIdentity }
    } catch { allowed = false; error = true; resetOrigins() }
  }

  private var trendSpec: GalaxySSIHealthTrendAnalysis.Spec {
    let local = snapshotCalendar ?? calendar
    var length = days
    if comparisonAnchor != nil, days == 180,
       let start = local.date(byAdding: .month, value: -6, to: local.startOfDay(for: snapshotTime)),
       let span = local.dateComponents([.day], from: start, to: local.startOfDay(for: snapshotTime)).day {
      length = span + 1
    }
    return .init(metric: metric, component: component, unit: unit, source: source,
      device: source == .healthKit ? nil : device, origin: source == .healthKit ? origin : .all,
      aggregation: aggregation, through: snapshotTime, days: length, calendar: local, comparisonAnchor: comparisonAnchor,
      unverifiedComparison: unverifiedComparison)
  }

  private func makeTrend(_ current: [GalaxySSIHealthReading]) -> GalaxySSIHealthTrend { trendSpec.chart(current) }

  private func explainTrend() {
    guard scene == .active, allowed, !changed, trend != nil else { return }
    guard !protectedDataBlocked, UIApplication.shared.isProtectedDataAvailable else { return }
    guard !atlasPinnedAnalysis || atlasAnalysisReady else { return }
    do {
      let archive = try records.load()
      let label = selectedOriginTitle ?? device.flatMap { id in devices.first { $0.id == id } }.map(deviceTitle)
      let route = GalaxySSIHealthTrendAnalysis(spec: trendSpec, versions: trendVersions,
        sourceTitle: label.map { sourceTitle(source) + " / " + $0 } ?? sourceTitle(source))
      guard route.spec.calendar.timeZone == timeZone else { reload(); return }
      guard archive.derivesOverview == true, route.spec.versions(archive.current) == route.versions
      else { invalidate(); return }
      guard route.result(archive.current) != nil else { return }
      explanation = route
    } catch { invalidate() }
  }

  private func toggleChartData(_ data: [GalaxySSIHealthTrend.ChartDatum]) {
    if showsChartData { showsChartData = false; return }
    guard scene == .active, allowed, !changed, !data.isEmpty else { return }
    do {
      let archive = try records.load()
      guard archive.derivesOverview == true else { invalidate(); return }
      let fresh = makeTrend(archive.current).chartData(aggregation, component: component)
      guard data.count == fresh.count, zip(data, fresh).allSatisfy({ $0.0.matches($0.1) })
      else { invalidate(); return }
      showsChartData = true
    } catch { invalidate() }
  }

  private func chartDatumRow(_ datum: GalaxySSIHealthTrend.ChartDatum) -> some View {
    Button { openAudit(datum) } label: {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          if focusedDay == datum.point.day {
            Image(systemName: "checkmark.circle").foregroundColor(.accentColor).accessibilityHidden(true)
          }
          Text(datum.point.day, style: .date)
          Spacer()
          Text(number(datum.value) + " " + unit)
        }
        Text(componentTitle + " · " + aggregationTitle(aggregation) + " · " +
          String(format: t("chart_data_count", "Records: %lld"), Int64(datum.point.readings.count)))
          .font(.caption).foregroundColor(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private func openAudit(_ datum: GalaxySSIHealthTrend.ChartDatum) {
    guard scene == .active, allowed, !changed else { return }
    do {
      let archive = try records.load()
      guard archive.derivesOverview == true,
            let fresh = makeTrend(archive.current).chartData(aggregation, component: component)
              .first(where: { $0.id == datum.id }), fresh.matches(datum) else { invalidate(); return }
      shown = 30
      jumpTarget = nil
      focusedDay = fresh.point.day
      selected = fresh.point
    } catch { invalidate() }
  }

  private func invalidate() {
    atlasAnalysisIdentity = nil
    selected = nil
    showsChartData = false
    focusedDay = nil
    trend = nil
    trendVersions = []
    guard !protectedDataBlocked, UIApplication.shared.isProtectedDataAvailable else { allowed = false; return }
    do {
      allowed = try records.load().derivesOverview == true; changed = allowed
      if !allowed { resetOrigins() }
    } catch { allowed = false; error = true; resetOrigins() }
  }

  private var currentAtlasIdentity: GalaxySSIHealthAtlasTrendAction.Identity {
    .init(spec: trendSpec, environmentCalendar: calendar, timeZone: timeZone, selection: atlasAnalysisSelection)
  }
  private var atlasAnalysisReady: Bool {
    GalaxySSIHealthAtlasTrendAction.ready(captured: atlasAnalysisIdentity, current: currentAtlasIdentity,
      foreground: scene == .active, protectedData: !protectedDataBlocked && UIApplication.shared.isProtectedDataAvailable, permitted: allowed,
      changed: changed, hasChartData: trend?.chartData(aggregation, component: component).isEmpty == false)
  }

  private func chart(_ trend: GalaxySSIHealthTrend, data: [GalaxySSIHealthTrend.ChartDatum]) -> some View {
    GeometryReader { geometry in
      Canvas { context, size in
        let values = data.map { NSDecimalNumber(decimal: $0.value).doubleValue }
        guard let low = values.min(), let high = values.max(), low.isFinite, high.isFinite else { return }
        let range = high - low
        var prior: CGPoint?
        var priorID: Int?
        var priorComparable = false
        for (datum, value) in zip(data, values) {
          let point = datum.point
          if priorID != point.id - 1 { prior = nil }
          let fraction = range > 0 ? (value - low) / range : 0.5
          let position = CGPoint(x: 8 + CGFloat(point.id) / CGFloat(max(1, trend.points.count - 1)) * (size.width - 16),
                                 y: 8 + CGFloat(1 - fraction) * (size.height - 16))
          if let prior, priorComparable, !point.unverifiedMethods {
            var path = Path()
            path.move(to: prior)
            path.addLine(to: position)
            context.stroke(path, with: .color(.accentColor), lineWidth: 2)
          }
          let radius: CGFloat = focusedDay == point.day ? 6 : 3
          context.fill(Path(ellipseIn: CGRect(x: position.x - radius, y: position.y - radius,
                                              width: 2 * radius, height: 2 * radius)),
                       with: .color(.accentColor))
          prior = position
          priorID = point.id
          priorComparable = !point.unverifiedMethods
        }
      }
      .contentShape(Rectangle())
      .gesture(DragGesture(minimumDistance: 0).onEnded { event in
        let width = max(1, geometry.size.width - 16)
        let index = Int(((event.location.x - 8) / width * CGFloat(trend.points.count - 1)).rounded())
        if let datum = data.first(where: { $0.id == index }) { openAudit(datum) }
      })
    }
    .frame(height: 120)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(t("chart", "Measurement chart")))
    .accessibilityAction(named: Text(t("chart_data", "Chart data"))) {
      if !showsChartData { toggleChartData(data) }
    }
  }

  private var unit: String { metric == .bloodPressure && component == .pulse ? "bpm" : (selectedUnit ?? metric.unit) }
  private var componentTitle: String {
    switch component {
    case .value: return metric == .bloodPressure ? t("systolic", "Systolic") : t("metric", "Measurement")
    case .diastolic: return t("diastolic", "Diastolic")
    case .pulse: return t("pulse", "Pulse")
    }
  }

  private func aggregationTitle(_ value: GalaxySSIHealthTrend.Aggregation) -> String {
    switch value {
    case .mean: return t("mean", "Mean")
    case .min: return t("min", "Minimum")
    case .max: return t("max", "Maximum")
    case .latest: return t("latest", "Latest reading")
    }
  }

  private func sourceTitle(_ value: GalaxySSIHealthTrend.Source) -> String {
    switch value {
    case .all: return t("source_all", "All sources")
    case .manual: return t("source_manual", "Manual measurements")
    case .bluetooth: return t("source_bluetooth", "Bluetooth monitor")
    case .table: return t("source_table", "Imported table")
    case .healthKit: return t("source_healthkit", "Apple Health")
    case .report: return t("source_report", "Report measurements")
    }
  }

  private static func trendSource(_ reading: GalaxySSIHealthReading) -> GalaxySSIHealthTrend.Source {
    switch GalaxySSIHealthMeasurementComparison.source(reading) {
    case .manual: return .manual
    case .report: return .report
    case .table: return .table
    case .bluetooth: return .bluetooth
    case .healthKit: return .healthKit
    }
  }

  private var originPicker: some View {
    Group {
      Picker(t("health_origin", "Apple Health origin"), selection: Binding(get: { origin }, set: selectOrigin)) {
        Text(t("health_origin_all", "All Apple Health origins")).tag(GalaxySSIHealthTrend.HealthOrigin.all)
        ForEach(originPage?.options ?? []) { option in
          Text(originTitle(option.id, name: option.name)).tag(option.id)
        }
        if origin != .all && originPage?.options.contains(where: { $0.id == origin }) != true {
          Text(selectedOriginTitle ?? t("health_origin_unavailable", "Selected origin unavailable")).tag(origin)
        }
      }
      if !originCursors.isEmpty || originPage?.hasMore == true {
        HStack {
          Button(t("health_origin_previous", "Previous origins")) {
            if !originCursors.isEmpty { originCursors.removeLast(); reload() }
          }
          .disabled(originCursors.isEmpty)
          Spacer()
          Button(t("health_origin_next", "Next origins")) {
            if let last = originPage?.options.last, originPage?.hasMore == true {
              originCursors.append(last.id)
              reload()
            }
          }
          .disabled(originPage?.hasMore != true)
        }
        .buttonStyle(.borderless)
      }
    }
  }

  private func selectOrigin(_ value: GalaxySSIHealthTrend.HealthOrigin) {
    guard allowed, scene == .active else { return }
    if value == origin { return }
    let option = originPage?.options.first { $0.id == value }
    guard value == .all || option != nil else { return }
    origin = value
    selectedOriginTitle = originTitle(value, name: option?.name)
    reload()
  }

  private func resetOrigins() {
    origin = .all
    originPage = nil
    originCursors = []
    selectedOriginTitle = nil
  }

  private func originTitle(_ value: GalaxySSIHealthTrend.HealthOrigin, name: String?) -> String {
    switch value {
    case .all: return t("health_origin_all", "All Apple Health origins")
    case .dailySteps: return t("health_origin_steps", "Apple Health daily step total")
    case .unidentified: return t("health_origin_unknown", "Unidentified Apple Health origin")
    case .application(let id):
      let label = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return label.isEmpty || label == id ? id : label + " · " + id
    }
  }

  private func number(_ value: Decimal) -> String { value.formatted(.number.locale(locale)) }
  private func statistic(_ title: String, _ value: Decimal) -> some View {
    HStack { Text(title); Spacer(); Text(number(value) + " " + unit).foregroundColor(.secondary) }
  }

  private func metricTitle(_ metric: GalaxySSIHealthMetric) -> String {
    metric.title(language: language)
  }

  private func deviceTitle(_ option: GalaxySSIHealthTrendDevice) -> String {
    let number = (devices.firstIndex { $0.id == option.id } ?? 0) + 1
    return (option.name ?? t("unnamed_device", "Unnamed Bluetooth device")) + " · " + String(number)
  }

  private func readingSource(_ reading: GalaxySSIHealthReading) -> String {
    if let origin = GalaxySSIHealthTrend.HealthOrigin.recorded(in: reading) {
      return originTitle(origin, name: reading.healthKitSource?.name)
    }
    if reading.tableSource != nil { return t("table", "Source: imported table") }
    if reading.reportSource != nil { return t("source_report", "Source: report review") }
    guard let receipt = reading.bluetoothReceipt else { return t("manual", "Source: manual measurements") }
    if let option = devices.first(where: { $0.id == receipt.device }) { return deviceTitle(option) }
    return t("bluetooth", "Source: Bluetooth monitor")
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.trend." + key, fallback: fallback, language: language)
  }
}
