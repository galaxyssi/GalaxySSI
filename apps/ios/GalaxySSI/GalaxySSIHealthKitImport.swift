import CryptoKit
import HealthKit

@MainActor
struct GalaxySSIHealthKitImport {
  enum Failure: Error { case unavailable, excessive, changed }
  struct Source: Codable, Hashable {
    let key: String
    let origin: String?
    let name: String?
  }

  enum Scope: String, CaseIterable, Identifiable {
    case sleep, steps, heartRate, restingHeartRate, bloodPressure, weight
    var id: String { rawValue }
    var metric: GalaxySSIHealthMetric {
      switch self {
      case .sleep: return .sleepDuration
      case .steps: return .steps
      case .heartRate: return .heartRate
      case .restingHeartRate: return .restingHeartRate
      case .bloodPressure: return .bloodPressure
      case .weight: return .weight
      }
    }
    var quantity: HKQuantityType? {
      switch self {
      case .steps: return HKObjectType.quantityType(forIdentifier: .stepCount)
      case .heartRate: return HKObjectType.quantityType(forIdentifier: .heartRate)
      case .restingHeartRate: return HKObjectType.quantityType(forIdentifier: .restingHeartRate)
      case .weight: return HKObjectType.quantityType(forIdentifier: .bodyMass)
      default: return nil
      }
    }
    var readTypes: [HKObjectType] {
      switch self {
      case .bloodPressure:
        return [HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
                HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)].compactMap { $0 }
      case .sleep: return HKObjectType.categoryType(forIdentifier: .sleepAnalysis).map { [$0] } ?? []
      default: return quantity.map { [$0] } ?? []
      }
    }
  }

  static var available: Bool {
    #if GALAXYSSI_HEALTHKIT
    return HKHealthStore.isHealthDataAvailable()
    #else
    return false
    #endif
  }

  private let store = HKHealthStore()
  static let limit = 5_000

  func authorize(_ scopes: Set<Scope>) async throws {
    guard Self.available, !scopes.isEmpty else { throw Failure.unavailable }
    try await store.requestAuthorization(toShare: [], read: Set(scopes.flatMap(\.readTypes)))
  }

  func read(_ scopes: Set<Scope>, interval: DateInterval, calendar: Calendar) async throws -> [GalaxySSIHealthReading] {
    guard Self.available, !scopes.isEmpty, interval.duration <= 31 * 86_400 else { throw Failure.unavailable }
    var rows: [GalaxySSIHealthReading] = []
    for scope in Scope.allCases where scopes.contains(scope) {
      try Task.checkCancellation()
      if scope == .steps, let type = scope.quantity {
        var day = interval.start
        let today = calendar.startOfDay(for: interval.end)
        while day < today, let next = calendar.date(byAdding: .day, value: 1, to: day), next <= today {
          try Task.checkCancellation()
          if let total = try await steps(type, start: day, end: next), total.isFinite,
             total >= 0, total.rounded() == total {
            let key = "steps:\(day.timeIntervalSinceReferenceDate)"
            rows.append(.init(metric: .steps, measuredAt: day, value: Decimal(total),
                              healthKitSource: .init(key: Self.digest(key), origin: nil, name: nil)))
          }
          day = next
        }
      } else {
        let type: HKSampleType?
        switch scope {
        case .sleep: type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .bloodPressure: type = HKObjectType.correlationType(forIdentifier: .bloodPressure)
        default: type = scope.quantity
        }
        guard let type else { throw Failure.unavailable }
        let samples = try await readSamples(type, interval: interval)
        rows.append(contentsOf: samples.compactMap { Self.convert($0, scope: scope, interval: interval) })
      }
      guard rows.count <= Self.limit else { throw Failure.excessive }
    }
    return rows.sorted { ($0.healthKitSource?.key ?? "") < ($1.healthKitSource?.key ?? "") }
  }

  private func readSamples(_ type: HKSampleType, interval: DateInterval) async throws -> [HKSample] {
    let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
    return try await withCheckedThrowingContinuation { continuation in
      let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: Self.limit + 1, sortDescriptors: nil) {
        _, samples, error in
        if let error { continuation.resume(throwing: error); return }
        let samples = samples ?? []
        if samples.count > Self.limit { continuation.resume(throwing: Failure.excessive) }
        else { continuation.resume(returning: samples) }
      }
      store.execute(query)
    }
  }

  private func steps(_ type: HKQuantityType, start: Date, end: Date) async throws -> Double? {
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
    return try await withCheckedThrowingContinuation { continuation in
      let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) {
        _, result, error in
        if let error {
          let failure = error as NSError
          if failure.domain == HKErrorDomain && failure.code == HKError.Code.errorNoData.rawValue {
            continuation.resume(returning: nil)
          } else { continuation.resume(throwing: error) }
          return
        }
        continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: .count()))
      }
      store.execute(query)
    }
  }

  static func convert(_ sample: HKSample, scope: Scope, interval: DateInterval) -> GalaxySSIHealthReading? {
    guard sample.startDate >= interval.start, sample.startDate < interval.end else { return nil }
    let origin = sample.sourceRevision.source
    let source = Source(key: digest(scope.rawValue + ":" + origin.bundleIdentifier + ":" + sample.uuid.uuidString),
                        origin: origin.bundleIdentifier, name: String(origin.name.prefix(100)))
    var value: Double
    var lower: Double?
    var unit: String?
    switch scope {
    case .sleep:
      guard let category = sample as? HKCategorySample, sample.endDate <= interval.end,
            [1, 3, 4, 5].contains(category.value) else { return nil }
      value = sample.endDate.timeIntervalSince(sample.startDate) / 60
      unit = "min"
    case .bloodPressure:
      guard let correlation = sample as? HKCorrelation,
            let systolic = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
            let diastolic = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic),
            let high = correlation.objects(for: systolic).first as? HKQuantitySample,
            let low = correlation.objects(for: diastolic).first as? HKQuantitySample else { return nil }
      value = high.quantity.doubleValue(for: .millimeterOfMercury())
      lower = low.quantity.doubleValue(for: .millimeterOfMercury())
    case .weight, .heartRate, .restingHeartRate:
      guard let quantity = sample as? HKQuantitySample else { return nil }
      let measure: HKUnit = scope == .weight ? .gramUnit(with: .kilo) : HKUnit.count().unitDivided(by: .minute())
      value = quantity.quantity.doubleValue(for: measure)
    case .steps: return nil
    }
    guard value.isFinite, lower?.isFinite != false else { return nil }
    let reading = GalaxySSIHealthReading(metric: scope.metric, measuredAt: sample.startDate, value: Decimal(value),
      diastolic: lower.map { Decimal($0) }, unitOverride: unit, healthKitSource: source)
    return reading.isValid ? reading : nil
  }

  private nonisolated static func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  struct PreviewRow: Hashable {
    let source: Source?
    let metric: GalaxySSIHealthMetric
    let value: Decimal?
    let diastolic: Decimal?
    let measuredAt: Date
    let unit: String
  }

  nonisolated static func stamp(_ readings: [GalaxySSIHealthReading]) -> [PreviewRow: Int] {
    readings.reduce(into: [:]) { counts, reading in
      let row = PreviewRow(source: reading.healthKitSource, metric: reading.metric,
        value: reading.value, diastolic: reading.diastolic, measuredAt: reading.measuredAt, unit: reading.unit)
      counts[row, default: 0] += 1
    }
  }
}
