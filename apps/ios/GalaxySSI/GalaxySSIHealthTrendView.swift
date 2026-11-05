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
      case .manual: return reading.tableSource == nil && reading.bluetoothReceipt == nil && reading.healthKitSource == nil
      case .bluetooth: return reading.tableSource == nil && reading.bluetoothReceipt != nil
      case .table: return reading.tableSource != nil
      case .healthKit: return reading.healthKitSource != nil
      }
    }
  }

  enum HealthOrigin: Hashable {
    case all, application(String), dailySteps, unidentified

    func includes(_ reading: GalaxySSIHealthReading) -> Bool {
      if self == .all { return true }
      return Self.origin(of: reading) == self
    }

    static func origin(of reading: GalaxySSIHealthReading) -> Self? {
      guard let receipt = reading.healthKitSource else { return nil }
      if let origin = receipt.origin, !origin.isEmpty { return .application(origin) }
      return reading.metric == .steps ? .dailySteps : .unidentified
    }
  }

  struct OriginOption: Identifiable {
    let id: HealthOrigin
    let name: String?
  }

  static func origins(in readings: [GalaxySSIHealthReading], metric: GalaxySSIHealthMetric) -> [OriginOption] {
    var ids = Set<HealthOrigin>()
    var options: [OriginOption] = []
    for reading in readings where !reading.deleted && reading.metric == metric {
      guard let id = HealthOrigin.origin(of: reading), ids.insert(id).inserted else { continue }
      options.append(.init(id: id, name: reading.healthKitSource?.name))
    }
    return options
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
        healthOrigin.includes($0) &&
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
  @State private var metric = GalaxySSIHealthMetric.bloodPressure
  @State private var component = GalaxySSIHealthTrend.Component.value
  @State private var selectedUnit: String?
  @State private var days = 7
  @State private var aggregation = GalaxySSIHealthTrend.Aggregation.mean
  @State private var source = GalaxySSIHealthTrend.Source.all
  @State private var snapshotTime = Date()
  @State private var focusedDay: Date?
  @State private var allowed = false
  @State private var device: UUID?
  @State private var devices: [GalaxySSIHealthTrendDevice] = []
  @State private var trend: GalaxySSIHealthTrend?
  @State private var selected: GalaxySSIHealthTrend.Point?
  @State private var changed = false
  @State private var error = false
  @State private var shown = 30
  @State private var jumpTarget: UUID?
  @State private var origin = GalaxySSIHealthTrend.HealthOrigin.all
  @State private var origins: [GalaxySSIHealthTrend.OriginOption] = []
  @State private var originLimit = 30

  var body: some View {
    List {
      if scene == .active {
        if error {
          Text(t("unavailable", "Trends unavailable"))
          Button(t("refresh", "Refresh"), action: reload)
        } else if !allowed {
          Text(t("permission", "Enable the local measurement summary in Health Privacy to view trends."))
        } else {
          Picker(t("metric", "Measurement"), selection: $metric) {
            ForEach(GalaxySSIHealthMetric.allCases) { Text(metricTitle($0)).tag($0) }
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
          if source == .bluetooth && (!devices.isEmpty || device != nil) {
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
    .onChange(of: metric) { _ in component = .value; selectedUnit = nil; resetOrigin(); reload() }
    .onChange(of: component) { _ in reload() }
    .onChange(of: days) { _ in reload() }
    .onChange(of: device) { _ in reload() }
    .onChange(of: source) { _ in device = nil; resetOrigin(); reload() }
    .onChange(of: origin) { _ in reload() }
    .onChange(of: aggregation) { _ in selected = nil; focusedDay = nil }
    .onChange(of: scene) { phase in
      if phase == .active { reload() }
      else {
        trend = nil; selected = nil; focusedDay = nil; allowed = false
        resetOrigin(); device = nil; devices = []
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.trendInputsChanged)) { event in
      guard event.object as? String == records.owner, scene == .active else { return }
      invalidate()
    }
    .sheet(item: $selected) { point in
      NavigationView {
        ScrollViewReader { proxy in
          List {
            if scene == .active && allowed && !changed {
              Section(t("audit", "Point audit")) {
                Text(metricTitle(metric) + " · " + componentTitle + " · " + unit)
                Text(aggregationTitle(aggregation) + " · " + auditSource)
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
                  Text(contributorSource(reading)).foregroundColor(.secondary)
                  if let application = reading.healthKitSource?.origin, !application.isEmpty {
                    Text(application).font(.footnote).foregroundColor(.secondary)
                  }
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
    changed = false
    do {
      let archive = try records.load()
      allowed = archive.derivesOverview == true
      error = false
      guard allowed else { resetOrigin(); device = nil; devices = []; return }
      devices = GalaxySSIHealthTrendDevice.options(in: archive.current, metric: metric)
      origins = source == .healthKit ? GalaxySSIHealthTrend.origins(in: archive.current, metric: metric) : []
      snapshotTime = Date()
      trend = makeTrend(archive.current)
    } catch { allowed = false; error = true }
  }

  private func makeTrend(_ current: [GalaxySSIHealthReading]) -> GalaxySSIHealthTrend {
    var local = calendar
    local.timeZone = timeZone
    let filtered = GalaxySSIHealthTrendDevice.matching(current, device: source == .bluetooth ? device : nil)
    return GalaxySSIHealthTrend(current: filtered, metric: metric, component: component,
      now: snapshotTime, dayCount: days, calendar: local, unit: selectedUnit, source: source,
      healthOrigin: source == .healthKit ? origin : .all)
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
    do {
      allowed = try records.load().derivesOverview == true
      changed = allowed
      if !allowed { resetOrigin(); device = nil; devices = [] }
    }
    catch { allowed = false; error = true }
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
    case .healthKit: return "Apple Health"
    }
  }

  private var originPicker: some View {
    Group {
      Picker(t("health_origin", "Apple Health origin"), selection: $origin) {
        Text(t("health_origin_all", "All Apple Health origins")).tag(GalaxySSIHealthTrend.HealthOrigin.all)
        ForEach(origins.prefix(originLimit)) { option in
          Text(originTitle(option.id, name: option.name)).tag(option.id)
        }
        if origin != .all && !origins.prefix(originLimit).contains(where: { $0.id == origin }) {
          Text(t("health_origin_unavailable", "Selected origin unavailable")).tag(origin)
        }
      }
      if origins.count > originLimit {
        Button(t("health_origin_more", "Show more origins")) { originLimit += 30 }
      }
    }
  }

  private func resetOrigin() {
    origin = .all
    origins = []
    originLimit = 30
  }

  private var auditSource: String {
    if source == .bluetooth, let device {
      return devices.first { $0.id == device }.map(deviceTitle) ?? t("device_unavailable", "Selected device unavailable")
    }
    guard source == .healthKit else { return sourceTitle(source) }
    return originTitle(origin, name: origins.first { $0.id == origin }?.name)
  }

  private func originTitle(_ origin: GalaxySSIHealthTrend.HealthOrigin, name: String?) -> String {
    switch origin {
    case .all: return t("health_origin_all", "All Apple Health origins")
    case .dailySteps: return t("health_origin_steps", "Apple Health daily step total")
    case .unidentified: return t("health_origin_unknown", "Unidentified Apple Health origin")
    case .application(let id):
      guard let name, !name.isEmpty, name != id else { return id }
      return name + " · " + id
    }
  }

  private func contributorSource(_ reading: GalaxySSIHealthReading) -> String {
    if let origin = GalaxySSIHealthTrend.HealthOrigin.origin(of: reading) {
      return originTitle(origin, name: reading.healthKitSource?.name)
    }
    return readingSource(reading)
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
    if reading.tableSource != nil { return t("table", "Source: imported table") }
    guard let receipt = reading.bluetoothReceipt else { return t("manual", "Source: manual measurements") }
    if let option = devices.first(where: { $0.id == receipt.device }) { return deviceTitle(option) }
    return t("bluetooth", "Source: Bluetooth monitor")
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.trend." + key, fallback: fallback, language: language)
  }
}
