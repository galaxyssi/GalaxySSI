import SwiftUI

struct GalaxySSIHealthTrend {
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
  }

  let points: [Point]
  let minimum: Decimal?
  let maximum: Decimal?
  let mean: Decimal?

  init(current: [GalaxySSIHealthReading], metric: GalaxySSIHealthMetric, component: Component,
       now: Date, dayCount: Int, calendar: Calendar) {
    let today = calendar.startOfDay(for: now)
    let dates = (0..<max(1, min(dayCount, 90))).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    let days = Set(dates)
    let scoped = current.filter {
      !$0.deleted && $0.metric == metric && $0.measuredAt <= now &&
        days.contains(calendar.startOfDay(for: $0.measuredAt)) && component.value(in: $0) != nil
    }
    let grouped = Dictionary(grouping: scoped) { calendar.startOfDay(for: $0.measuredAt) }
    points = dates.enumerated().map { index, day in
      let readings = grouped[day] ?? []
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
  @State private var days = 7
  @State private var allowed = false
  @State private var trend: GalaxySSIHealthTrend?
  @State private var selected: GalaxySSIHealthTrend.Point?
  @State private var changed = false
  @State private var error = false
  @State private var shown = 30

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
          Picker(t("period", "Period"), selection: $days) {
            ForEach([7, 30, 90], id: \.self) { value in
              Text(String(format: t("days", "%lld days"), Int64(value))).tag(value)
            }
          }
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
                  Button { shown = 30; selected = point } label: {
                    HStack {
                      Text(point.day, style: .date)
                      Spacer()
                      if let value = point.mean { Text(number(value) + " " + unit) }
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
    .onChange(of: metric) { _ in component = .value; reload() }
    .onChange(of: component) { _ in reload() }
    .onChange(of: days) { _ in reload() }
    .onChange(of: scene) { phase in
      if phase == .active { reload() }
      else { trend = nil; selected = nil; allowed = false }
    }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.trendInputsChanged)) { event in
      guard event.object as? String == records.owner, scene == .active else { return }
      selected = nil
      trend = nil
      do { allowed = try records.load().derivesOverview == true; changed = allowed }
      catch { allowed = false; error = true }
    }
    .sheet(item: $selected) { point in
      NavigationView {
        List {
          if scene == .active && allowed && !changed {
            ForEach(point.readings.prefix(shown)) { reading in
              VStack(alignment: .leading, spacing: 4) {
                if let value = component.value(in: reading) { Text(number(value) + " " + unit) }
                Text(reading.measuredAt, style: .time).foregroundColor(.secondary)
                Text(reading.tableSource != nil ? t("table", "Source: imported table") :
                  (reading.bluetoothReceipt == nil ? t("manual", "Source: manual measurements") :
                    t("bluetooth", "Source: Bluetooth monitor"))).foregroundColor(.secondary)
                Text(String(format: t("revision", "Revision %lld"), Int64(reading.revision)))
                  .foregroundColor(.secondary)
              }
            }
            if point.readings.count > shown { Button(t("more", "Show more")) { shown += 30 } }
          }
        }
        .navigationTitle(point.day.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) {
          Button(t("done", "Done")) { selected = nil }
        } }
      }
      .navigationViewStyle(.stack)
    }
  }

  private func reload() {
    guard scene == .active else { return }
    selected = nil
    trend = nil
    changed = false
    do {
      let archive = try records.load()
      allowed = archive.derivesOverview == true
      error = false
      guard allowed else { return }
      var local = calendar
      local.timeZone = timeZone
      trend = GalaxySSIHealthTrend(current: archive.current, metric: metric, component: component,
                                   now: Date(), dayCount: days, calendar: local)
    } catch { allowed = false; error = true }
  }

  private func chart(_ trend: GalaxySSIHealthTrend) -> some View {
    Canvas { context, size in
      let values = trend.points.compactMap { $0.mean.map { NSDecimalNumber(decimal: $0).doubleValue } }
      guard let low = values.min(), let high = values.max(), low.isFinite, high.isFinite else { return }
      let range = high - low
      var prior: CGPoint?
      for point in trend.points {
        guard let mean = point.mean else { prior = nil; continue }
        let value = NSDecimalNumber(decimal: mean).doubleValue
        let fraction = range > 0 ? (value - low) / range : 0.5
        let position = CGPoint(x: 8 + CGFloat(point.id) / CGFloat(max(1, trend.points.count - 1)) * (size.width - 16),
                               y: 8 + CGFloat(1 - fraction) * (size.height - 16))
        if let prior {
          var path = Path()
          path.move(to: prior)
          path.addLine(to: position)
          context.stroke(path, with: .color(.accentColor), lineWidth: 2)
        }
        context.fill(Path(ellipseIn: CGRect(x: position.x - 3, y: position.y - 3, width: 6, height: 6)),
                     with: .color(.accentColor))
        prior = position
      }
    }
    .frame(height: 120)
    .accessibilityHidden(true)
  }

  private var unit: String { metric == .bloodPressure && component == .pulse ? "bpm" : metric.unit }
  private func number(_ value: Decimal) -> String { value.formatted(.number.locale(locale)) }
  private func statistic(_ title: String, _ value: Decimal) -> some View {
    HStack { Text(title); Spacer(); Text(number(value) + " " + unit).foregroundColor(.secondary) }
  }

  private func metricTitle(_ metric: GalaxySSIHealthMetric) -> String {
    let label: (String, String)
    switch metric {
    case .bloodPressure: label = ("blood_pressure", "Blood pressure")
    case .glucose: label = ("glucose", "Blood glucose")
    case .weight: label = ("weight", "Weight")
    case .heartRate: label = ("heart_rate", "Heart rate")
    }
    return GalaxySSILocalization.string("galaxyssi.health." + label.0, fallback: label.1, language: language)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.trend." + key, fallback: fallback, language: language)
  }
}
