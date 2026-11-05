import Foundation

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

  let scope: Scope
  let evidence: [Evidence]
  let versions: [String]
  let requestedDays: Int

  init(scope: Scope, current: [GalaxySSIHealthReading], calendar: Calendar) {
    self.scope = scope
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

  func isCurrent(_ current: [GalaxySSIHealthReading]) -> Bool {
    Self.stamps(scope.readings(in: current)) == versions
  }

  func requestJSON() throws -> Data {
    struct Packet: Encodable {
      let requestedDays: Int
      let aggregates: [Aggregate]
    }
    return try JSONEncoder().encode(Packet(requestedDays: requestedDays, aggregates: evidence.map(\.aggregate)))
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
      guard data.count < 32_768 else { throw GalaxySSIHealthAnalysis.Failure.invalid }
      data.append(byte)
    }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = object["choices"] as? [[String: Any]],
          let message = choices.first?["message"] as? [String: Any],
          let output = message["content"] as? String
    else { throw GalaxySSIHealthAnalysis.Failure.invalid }
    return output
  }

  private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
      completionHandler(nil)
    }
  }
}
