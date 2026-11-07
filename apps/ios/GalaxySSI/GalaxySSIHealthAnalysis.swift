import Foundation

struct GalaxySSIHealthTrendAnalysis: Identifiable {
  struct Spec {
    let metric: GalaxySSIHealthMetric
    let component: GalaxySSIHealthTrend.Component
    let unit: String
    let source: GalaxySSIHealthTrend.Source
    let device: UUID?
    let origin: GalaxySSIHealthTrend.HealthOrigin
    let aggregation: GalaxySSIHealthTrend.Aggregation
    let through: Date
    let days: Int
    let calendar: Calendar

    var interval: DateInterval {
      let day = calendar.startOfDay(for: through)
      let start = calendar.date(byAdding: .day, value: 1 - days, to: day) ?? day
      let end = calendar.date(byAdding: .day, value: 1, to: day) ?? through
      return DateInterval(start: start, end: end)
    }

    func cohort(_ current: [GalaxySSIHealthReading]) -> [GalaxySSIHealthReading] {
      let window = interval
      return GalaxySSIHealthTrendDevice.matching(current, device: device).filter {
        !$0.deleted && $0.metric == metric && $0.measuredAt >= window.start && $0.measuredAt < window.end &&
          source.includes($0) && (origin == .all || GalaxySSIHealthTrend.HealthOrigin.recorded(in: $0) == origin)
      }
    }

    func chart(_ current: [GalaxySSIHealthReading]) -> GalaxySSIHealthTrend {
      GalaxySSIHealthTrend(current: cohort(current), metric: metric, component: component, now: through,
        dayCount: days, calendar: calendar, unit: unit)
    }

    func versions(_ current: [GalaxySSIHealthReading]) -> [String] {
      cohort(current).map { "\($0.id):\($0.revision)" }.sorted()
    }
  }

  struct Fact: Encodable {
    struct Bucket: Encodable {
      let index: Int
      let value: String
      let recordCount: Int
    }
    let aggregation: String
    let pointCount: Int
    let recordedDays: Int
    let missingDays: Int
    let excludedNonNumeric: Int
    let excludedOtherUnits: Int
    let first: Bucket
    let last: Bucket?
    let delta: String?
  }

  let id = UUID()
  let spec: Spec
  let versions: [String]
  let sourceTitle: String

  func result(_ current: [GalaxySSIHealthReading]) -> (fact: Fact, evidence: GalaxySSIHealthAnalysis.Evidence,
    first: GalaxySSIHealthAnalysis.Evidence, last: GalaxySSIHealthAnalysis.Evidence?)? {
    guard spec.versions(current) == versions else { return nil }
    let chart = spec.chart(current)
    let plotted = chart.points.compactMap { point in
      point.value(spec.aggregation, component: spec.component).map { (point, $0) }
    }
    guard let (firstPoint, firstValue) = plotted.first, let (lastPoint, lastValue) = plotted.last else { return nil }
    let readings = plotted.flatMap { $0.0.readings }
    let cohort = spec.cohort(current).filter { $0.measuredAt <= spec.through }
    let recordedDays = Set(cohort.map { spec.calendar.startOfDay(for: $0.measuredAt) }).count
    let numeric = cohort.filter { spec.component.value(in: $0) != nil }
    let difference = lastValue - firstValue
    let values = plotted.map { $0.1 }
    let mean = values.reduce(Decimal.zero) { $0 + $1 / Decimal(values.count) }
    func exact(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
    func bucket(_ point: GalaxySSIHealthTrend.Point, _ value: Decimal) -> Fact.Bucket {
      .init(index: point.id + 1, value: exact(value), recordCount: point.readings.count)
    }
    func evidence(_ rows: [GalaxySSIHealthReading], days: Int, minimum: Decimal?, maximum: Decimal?,
                  average: Decimal?) -> GalaxySSIHealthAnalysis.Evidence {
      let component = spec.metric == .bloodPressure && spec.component == .value ? "systolic" : spec.component.rawValue
      return .init(metric: spec.metric, aggregate: .init(id: "e1", metric: spec.metric.rawValue, component: component,
        unit: spec.unit, count: rows.count, observedDays: days, minimum: minimum.map(exact), maximum: maximum.map(exact),
        mean: average.map(exact)), readings: rows)
    }
    func sources(_ point: GalaxySSIHealthTrend.Point, value: Decimal) -> GalaxySSIHealthAnalysis.Evidence {
      let leading = point.extremum(spec.aggregation, component: spec.component)
      let rows = leading.map { first in [first] + point.readings.filter { $0.id != first.id } } ?? point.readings
      return evidence(rows, days: 1, minimum: value, maximum: value, average: value)
    }
    let fact = Fact(aggregation: spec.aggregation.rawValue, pointCount: plotted.count, recordedDays: recordedDays,
      missingDays: spec.days - recordedDays, excludedNonNumeric: cohort.count - numeric.count,
      excludedOtherUnits: numeric.filter { spec.component != .pulse && $0.unit != spec.unit }.count,
      first: bucket(firstPoint, firstValue), last: plotted.count > 1 ? bucket(lastPoint, lastValue) : nil,
      delta: plotted.count > 1 && !difference.isNaN ? exact(difference) : nil)
    return (fact, evidence(readings, days: plotted.count, minimum: values.min(), maximum: values.max(),
      average: mean.isNaN ? nil : mean), sources(firstPoint, value: firstValue),
      plotted.count > 1 ? sources(lastPoint, value: lastValue) : nil)
  }
}

struct GalaxySSIHealthAnalysis {
  struct Aggregate: Identifiable, Codable {
    let id: String
    let metric: String
    let component: String
    let unit: String
    let count: Int
    let observedDays: Int
    let minimum: String?
    let maximum: String?
    let mean: String?
  }

  struct Evidence: Identifiable {
    let metric: GalaxySSIHealthMetric
    let aggregate: Aggregate
    let readings: [GalaxySSIHealthReading]
    var id: String { aggregate.id }
  }

  struct Recommendation: Decodable {
    enum NextStep: String, Decodable {
      case reviewSources = "review_sources"
      case collectMore = "collect_more"
      case comparePeriods = "compare_periods"
    }
    let evidence: [String]
    let nextStep: NextStep

    enum CodingKeys: String, CodingKey { case evidence; case nextStep = "next_step" }
  }

  struct Scope {
    let interval: DateInterval
    let metrics: Set<GalaxySSIHealthMetric>

    func readings(in current: [GalaxySSIHealthReading]) -> [GalaxySSIHealthReading] {
      current.filter {
        !$0.deleted && metrics.contains($0.metric) &&
          $0.measuredAt >= interval.start && $0.measuredAt < interval.end
      }
    }
  }

  struct ReportScope: Identifiable, Equatable {
    let id = UUID()
    let interval: DateInterval
    let metrics: Set<GalaxySSIHealthMetric>
    let calendar: Calendar
    let comparison: DateInterval?
    private let revisions: [GalaxySSIHealthMetric: [String]]

    init(scope: Scope, calendar: Calendar, compare: Bool, current: [GalaxySSIHealthReading]) {
      interval = scope.interval
      metrics = scope.metrics
      self.calendar = calendar
      let days = calendar.dateComponents([.day], from: scope.interval.start, to: scope.interval.end).day ?? 0
      let start = compare && days > 0 ? calendar.date(byAdding: .day, value: -days, to: scope.interval.start) : nil
      comparison = start.map { DateInterval(start: $0, end: scope.interval.start) }
      revisions = Self.stamps(current, interval: scope.interval, comparison: comparison, metrics: scope.metrics)
    }

    func refreshed(_ current: [GalaxySSIHealthReading]) -> Self {
      Self(scope: .init(interval: interval, metrics: metrics), calendar: calendar,
           compare: comparison != nil, current: current)
    }

    func isCurrent(_ current: [GalaxySSIHealthReading], selected: Set<GalaxySSIHealthMetric>) -> Bool {
      guard !selected.isEmpty, selected.isSubset(of: metrics) else { return false }
      let latest = Self.stamps(current, interval: interval, comparison: comparison, metrics: selected)
      return selected.allSatisfy { (revisions[$0] ?? []) == (latest[$0] ?? []) }
    }

    private static func stamps(_ current: [GalaxySSIHealthReading], interval: DateInterval,
                               comparison: DateInterval?, metrics: Set<GalaxySSIHealthMetric>)
      -> [GalaxySSIHealthMetric: [String]] {
      let window = DateInterval(start: comparison?.start ?? interval.start, end: interval.end)
      let groups = Dictionary(grouping: Scope(interval: window, metrics: metrics).readings(in: current), by: \.metric)
      return groups.mapValues(GalaxySSIHealthAnalysis.stamps)
    }
  }

  let id = UUID()
  let scope: Scope
  let evidence: [Evidence]
  let versions: [String]
  let requestedDays: Int
  let trend: GalaxySSIHealthTrendAnalysis?
  let trendFact: GalaxySSIHealthTrendAnalysis.Fact?
  let trendFirst: Evidence?
  let trendLast: Evidence?

  init(scope: Scope, current: [GalaxySSIHealthReading], calendar: Calendar) {
    self.scope = scope
    trend = nil; trendFact = nil; trendFirst = nil; trendLast = nil
    let scoped = scope.readings(in: current)
    versions = Self.stamps(scoped)
    requestedDays = max(1, calendar.dateComponents([.day], from: scope.interval.start, to: scope.interval.end).day ?? 1)
    var evidence: [Evidence] = []
    for metric in GalaxySSIHealthMetric.allCases where scope.metrics.contains(metric) {
      let readings = scoped.filter { $0.metric == metric }
      func add(_ component: String, unit: String, values: [(GalaxySSIHealthReading, Decimal)]) {
        let decimals = values.map { $0.1 }
        let mean: Decimal? = decimals.isEmpty ? nil : decimals.reduce(Decimal.zero) { $0 + $1 / Decimal(decimals.count) }
        let source = values.map { $0.0 }
        let days = Set(source.map { calendar.startOfDay(for: $0.measuredAt) }).count
        let aggregate = Aggregate(id: "e\(evidence.count + 1)", metric: metric.rawValue, component: component,
          unit: unit, count: source.count, observedDays: days,
          minimum: decimals.min().map(Self.exact), maximum: decimals.max().map(Self.exact),
          mean: mean.flatMap { $0.isNaN ? nil : Self.exact($0) })
        evidence.append(Evidence(metric: metric, aggregate: aggregate, readings: source))
      }
      let units = metric.units.filter { unit in readings.contains { $0.unit == unit && $0.value != nil } }
      for unit in units {
        let group = readings.filter { $0.unit == unit }
        add(metric == .bloodPressure ? "systolic" : "value", unit: unit,
            values: group.compactMap { reading in reading.value.map { (reading, $0) } })
        if metric == .bloodPressure {
          add("diastolic", unit: unit, values: group.compactMap { reading in reading.diastolic.map { (reading, $0) } })
        }
      }
      if units.isEmpty { add("value", unit: metric.unit, values: []) }
      if metric == .bloodPressure {
        let pulse = readings.compactMap { reading in reading.pulse.map { (reading, $0) } }
        if !pulse.isEmpty { add("pulse", unit: "bpm", values: pulse) }
      }
    }
    self.evidence = evidence
  }

  init?(trend: GalaxySSIHealthTrendAnalysis, current: [GalaxySSIHealthReading]) {
    guard let result = trend.result(current) else { return nil }
    self.trend = trend
    scope = .init(interval: trend.spec.interval, metrics: [trend.spec.metric])
    versions = trend.versions
    requestedDays = trend.spec.days
    evidence = [result.evidence]
    trendFact = result.fact
    trendFirst = result.first
    trendLast = result.last
  }

  func isCurrent(_ current: [GalaxySSIHealthReading]) -> Bool {
    if let trend { return trend.spec.versions(current) == versions }
    return Self.stamps(scope.readings(in: current)) == versions
  }

  func requestJSON() throws -> Data {
    struct Packet: Encodable {
      let requestedDays: Int
      let aggregates: [Aggregate]
      let filteredTrend: GalaxySSIHealthTrendAnalysis.Fact?
    }
    return try JSONEncoder().encode(Packet(requestedDays: requestedDays, aggregates: evidence.map(\.aggregate),
      filteredTrend: trendFact))
  }

  func recommendation(_ output: String) throws -> Recommendation {
    let bytes = Data(output.utf8)
    guard bytes.count <= 2_048,
          let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
          Set(object.keys) == ["evidence", "next_step"] else { throw Failure.invalid }
    let result = try JSONDecoder().decode(Recommendation.self, from: bytes)
    let known = Set(evidence.filter { $0.aggregate.count > 0 }.map(\.id))
    guard !result.evidence.isEmpty, result.evidence.count <= 6, Set(result.evidence).count == result.evidence.count,
          Set(result.evidence).isSubset(of: known) else { throw Failure.invalid }
    return result
  }

  enum Failure: Error { case invalid }

  private static func stamps(_ readings: [GalaxySSIHealthReading]) -> [String] {
    readings.map { "\($0.id):\($0.revision)" }.sorted()
  }

  private static func exact(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
}

enum GalaxySSIHealthSummaryTransport {
  static func endpoint(for model: CloudModelConfig) -> URL? {
    guard model.apiStyle == .openAICompatible, let parts = URLComponents(string: model.endpoint),
          parts.scheme?.lowercased() == "https", parts.host?.isEmpty == false,
          parts.user == nil, parts.password == nil, parts.fragment == nil, parts.query == nil
    else { return nil }
    return parts.url
  }

  static func request(endpoint: URL, model: String, apiKey: String, aggregates: Data) throws -> URLRequest {
    guard let user = String(data: aggregates, encoding: .utf8) else { throw GalaxySSIHealthAnalysis.Failure.invalid }
    var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "model": model, "stream": false,
      "messages": [
        ["role": "system", "content": """
        Return only a JSON object with evidence (1 to 6 distinct nonempty aggregate IDs) and next_step
        (review_sources, collect_more or compare_periods). Do not provide text, diagnoses, values or advice.
        """],
        ["role": "user", "content": user]
      ]
    ])
    return request
  }

  static func send(_ request: URLRequest) async throws -> String {
    let data = try await responseBytes(request)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = object["choices"] as? [[String: Any]],
          let message = choices.first?["message"] as? [String: Any],
          let output = message["content"] as? String
    else { throw GalaxySSIHealthAnalysis.Failure.invalid }
    return output
  }

  static func responseBytes(_ request: URLRequest, limit: Int = 32_768) async throws -> Data {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    let (bytes, response) = try await session.bytes(for: request)
    guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode)
    else { throw GalaxySSIHealthAnalysis.Failure.invalid }
    var data = Data()
    for try await byte in bytes {
      guard data.count < limit else { throw GalaxySSIHealthAnalysis.Failure.invalid }
      data.append(byte)
    }
    return data
  }

  private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
      completionHandler(nil)
    }
  }
}
