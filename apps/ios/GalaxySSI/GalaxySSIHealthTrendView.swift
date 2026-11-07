import SwiftUI

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
    case mean, min, max
  }

  enum Source: String, CaseIterable {
    case all, manual, bluetooth, table, healthKit

    func includes(_ reading: GalaxySSIHealthReading) -> Bool {
      switch self {
      case .all: return true
      case .manual: return reading.tableSource == nil && reading.bluetoothReceipt == nil &&
          reading.healthKitSource == nil && reading.reportSource == nil
      case .bluetooth: return reading.tableSource == nil && reading.bluetoothReceipt != nil
      case .table: return reading.tableSource != nil
      case .healthKit: return reading.healthKitSource != nil
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

    var revisions: [UUID: Int] { Dictionary(uniqueKeysWithValues: readings.map { ($0.id, $0.revision) }) }

    func extremum(_ aggregation: Aggregation, component: Component) -> GalaxySSIHealthReading? {
      guard aggregation != .mean else { return nil }
      return readings.reduce(nil as GalaxySSIHealthReading?) { best, reading in
        guard let value = component.value(in: reading) else { return best }
        guard let best, let previous = component.value(in: best) else { return reading }
        return (aggregation == .min ? value < previous : value > previous) ? reading : best
      }
    }

    func value(_ aggregation: Aggregation, component: Component) -> Decimal? {
      aggregation == .mean ? mean : extremum(aggregation, component: component).flatMap { component.value(in: $0) }
    }
  }

  let points: [Point]
  let minimum: Decimal?
  let maximum: Decimal?
  let mean: Decimal?

  init(current: [GalaxySSIHealthReading], metric: GalaxySSIHealthMetric, component: Component,
       now: Date, dayCount: Int, calendar: Calendar, unit: String? = nil, source: Source = .all,
       healthOrigin: HealthOrigin = .all) {
    let today = calendar.startOfDay(for: now)
    let dates = (0..<max(1, min(dayCount, 90))).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
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
                   mean: Self.average(readings.compactMap { component.value(in: $0) }))
    }
    let values = scoped.compactMap { component.value(in: $0) }
    minimum = values.min()
    maximum = values.max()
    mean = Self.average(values)
  }

  var validDays: Int { points.filter { $0.mean != nil }.count }

  private static func average(_ values: [Decimal]) -> Decimal? {
    guard !values.isEmpty else { return nil }
    let divisor = Decimal(values.count)
    let result = values.reduce(Decimal.zero) { $0 + $1 / divisor }
    return result.isNaN ? nil : result
  }
}

@MainActor
struct GalaxySSIHealthTrendView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  @Environment(\.locale) private var locale
  let records: GalaxySSIHealthRecords
  private let fixedMetric: GalaxySSIHealthMetric?
  private let recordMeasurement: (GalaxySSIHealthMetric) -> Void
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
  @State private var selected: GalaxySSIHealthTrend.Point?
  @State private var changed = false
  @State private var error = false
  @State private var shown = 30
  @State private var jumpTarget: UUID?
  @State private var origin = GalaxySSIHealthTrend.HealthOrigin.all
  @State private var originPage: GalaxySSIHealthTrend.OriginPage?
  @State private var originCursors: [GalaxySSIHealthTrend.HealthOrigin] = []
  @State private var selectedOriginTitle: String?

  init(records: GalaxySSIHealthRecords, fixedMetric: GalaxySSIHealthMetric? = nil,
       recordMeasurement: @escaping (GalaxySSIHealthMetric) -> Void) {
    self.records = records
    self.fixedMetric = fixedMetric
    self.recordMeasurement = recordMeasurement
    _metric = State(initialValue: fixedMetric ?? .bloodPressure)
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
          }
          Picker(t("period", "Period"), selection: $days) {
            ForEach([7, 30, 90], id: \.self) { value in
              Text(String(format: t("days", "%lld days"), Int64(value))).tag(value)
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
          }
          Picker(t("aggregation", "Aggregation"), selection: $aggregation) {
            ForEach(GalaxySSIHealthTrend.Aggregation.allCases, id: \.self) { Text(aggregationTitle($0)).tag($0) }
          }
          Picker(t("source", "Source"), selection: $source) {
            ForEach(GalaxySSIHealthTrend.Source.allCases, id: \.self) { Text(sourceTitle($0)).tag($0) }
          }
          if source == .healthKit { originPicker }
          if changed {
            Text(t("changed", "Measurements changed. Refresh to view current results."))
            Button(t("refresh", "Refresh"), action: reload)
          } else if let trend {
            if let average = trend.mean, let minimum = trend.minimum, let maximum = trend.maximum {
              Button(action: explainTrend) {
                Label(t("explain", "Explain this trend"), systemImage: "text.bubble")
              }
              Section(t("summary", "Summary")) {
                Text(String(format: t("coverage", "%lld of %lld days with readings"), Int64(trend.validDays), Int64(days)))
                statistic(t("mean", "Mean"), average)
                statistic(t("min", "Minimum"), minimum)
                statistic(t("max", "Maximum"), maximum)
                chart(trend)
              }
              Section(t("sources", "Daily source records")) {
                ForEach(trend.points.reversed().filter { $0.mean != nil }) { point in
                  Button { openAudit(point) } label: {
                    HStack {
                      if focusedDay == point.day {
                        Image(systemName: "checkmark.circle").foregroundColor(.accentColor).accessibilityHidden(true)
                      }
                      Text(point.day, style: .date)
                      Spacer()
                      if let value = point.value(aggregation, component: component) { Text(number(value) + " " + unit) }
                    }
                  }
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
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onChange(of: metric) { _ in component = .value; selectedUnit = nil; resetOrigins(); reload() }
    .onChange(of: component) { _ in reload() }
    .onChange(of: days) { _ in resetOrigins(); reload() }
    .onChange(of: device) { _ in reload() }
    .onChange(of: scene) { if $0 == .background { device = nil; devices = [] } }
    .onChange(of: source) { _ in resetOrigins(); reload() }
    .onDisappear { resetOrigins(); selected = nil; trend = nil }
    .onChange(of: aggregation) { _ in selected = nil; focusedDay = nil }
    .onChange(of: scene) { phase in
      if phase == .active { reload() }
      else { trend = nil; selected = nil; focusedDay = nil; allowed = false; resetOrigins() }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.trendInputsChanged)) { event in
      guard event.object as? String == records.owner, scene == .active else { return }
      invalidate()
    }
    .onChange(of: scene) { phase in
      if phase != .active { trendVersions = []; explanation = nil; recordAfterExplanation = nil }
    }
    .sheet(item: $explanation, onDismiss: {
      if let metric = recordAfterExplanation {
        recordAfterExplanation = nil
        if scene == .active { recordMeasurement(metric) }
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
          .navigationBarTitleDisplayMode(.inline)
          .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button(t("done", "Done")) { selected = nil }
          } }
        }
      }
      .navigationViewStyle(.stack)
    }
  }

  private func reload() {
    guard scene == .active else { return }
    selected = nil
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
      snapshotTime = Date()
      var local = calendar
      local.timeZone = timeZone
      snapshotCalendar = local
      if source == .healthKit {
        let today = local.startOfDay(for: snapshotTime)
        let start = local.date(byAdding: .day, value: 1 - days, to: today) ?? today
        originPage = GalaxySSIHealthTrend.origins(in: current, metric: metric, from: start, through: snapshotTime,
                                                  after: originCursors.last)
      }
      let spec = trendSpec
      trend = spec.chart(current)
      trendVersions = spec.versions(current)
    } catch { allowed = false; error = true; resetOrigins() }
  }

  private var trendSpec: GalaxySSIHealthTrendAnalysis.Spec {
    let local = snapshotCalendar ?? calendar
    return .init(metric: metric, component: component, unit: unit, source: source,
      device: source == .healthKit ? nil : device, origin: source == .healthKit ? origin : .all,
      aggregation: aggregation, through: snapshotTime, days: days, calendar: local)
  }

  private func makeTrend(_ current: [GalaxySSIHealthReading]) -> GalaxySSIHealthTrend { trendSpec.chart(current) }

  private func explainTrend() {
    guard scene == .active, allowed, !changed, trend != nil else { return }
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

  private func openAudit(_ point: GalaxySSIHealthTrend.Point) {
    do {
      let archive = try records.load()
      guard archive.derivesOverview == true,
            let fresh = makeTrend(archive.current).points.first(where: { $0.day == point.day }),
            fresh.revisions == point.revisions else { invalidate(); return }
      shown = 30
      jumpTarget = nil
      focusedDay = point.day
      selected = fresh
    } catch { invalidate() }
  }

  private func invalidate() {
    selected = nil
    focusedDay = nil
    trend = nil
    trendVersions = []
    do {
      allowed = try records.load().derivesOverview == true; changed = allowed
      if !allowed { resetOrigins() }
    } catch { allowed = false; error = true; resetOrigins() }
  }

  private func chart(_ trend: GalaxySSIHealthTrend) -> some View {
    GeometryReader { geometry in
      Canvas { context, size in
        let values = trend.points.compactMap { $0.value(aggregation, component: component).map { NSDecimalNumber(decimal: $0).doubleValue } }
        guard let low = values.min(), let high = values.max(), low.isFinite, high.isFinite else { return }
        let range = high - low
        var prior: CGPoint?
        for point in trend.points {
          guard let aggregate = point.value(aggregation, component: component) else { prior = nil; continue }
          let value = NSDecimalNumber(decimal: aggregate).doubleValue
          let fraction = range > 0 ? (value - low) / range : 0.5
          let position = CGPoint(x: 8 + CGFloat(point.id) / CGFloat(max(1, trend.points.count - 1)) * (size.width - 16),
                                 y: 8 + CGFloat(1 - fraction) * (size.height - 16))
          if let prior {
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
        }
      }
      .contentShape(Rectangle())
      .gesture(DragGesture(minimumDistance: 0).onEnded { event in
        let width = max(1, geometry.size.width - 16)
        let index = Int(((event.location.x - 8) / width * CGFloat(trend.points.count - 1)).rounded())
        guard trend.points.indices.contains(index), trend.points[index].mean != nil else { return }
        openAudit(trend.points[index])
      })
    }
    .frame(height: 120)
    .accessibilityHidden(true)
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
    }
  }

  private func sourceTitle(_ value: GalaxySSIHealthTrend.Source) -> String {
    switch value {
    case .all: return t("source_all", "All sources")
    case .manual: return t("source_manual", "Manual measurements")
    case .bluetooth: return t("source_bluetooth", "Bluetooth monitor")
    case .table: return t("source_table", "Imported table")
    case .healthKit: return t("source_healthkit", "Apple Health")
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
