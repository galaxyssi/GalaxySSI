import CryptoKit
import Foundation

enum GalaxySSIHealthCare {
  static let guidelineURL = URL(string: "https://doi.org/10.2337/dc26-s002")!

  enum Stage: String, Codable, Hashable { case verify, evidence, reviewPlan, waitingResults, reassess, maintenance, paused, closed }
  enum Signal: String, Codable, Equatable {
    case reportLow, reportHigh, notExact, glucoseContext, guidelineReview, guidelineScope, rising, falling, sourceRemoved
  }
  struct Record: Codable, Equatable {
    let id: UUID
    let revision: Int

    init(_ reading: GalaxySSIHealthReading) {
      id = reading.id
      revision = reading.revision
    }
  }
  struct Context: Codable, Equatable {
    enum Applicability: String, Codable, Hashable, CaseIterable { case unknown, applicable, excluded }
    let record: Record
    let applicability: Applicability
    var facts: GalaxySSIHealthCareApplicability.Facts?
  }
  struct Baseline: Codable, Equatable {
    let records: [Record]
    let low: Decimal
    let high: Decimal
  }
  struct Assessment: Codable, Equatable {
    let record: Record?
    let measuredAt: Date?
    let result: String
    let unit: String
    let reference: String
    let signals: [Signal]
    let guidelineVersion: String?
    let baseline: Baseline?

    static let removed = Self(record: nil, measuredAt: nil, result: "", unit: "", reference: "",
      signals: [.sourceRemoved], guidelineVersion: nil, baseline: nil)
  }
  struct Target: Codable, Equatable {
    let value: String
    let source: String
    let rationale: String
    let confirmedBy: String
    let confirmedAt: Date
    var numeric: GalaxySSIHealthCareTarget.Confirmed?
  }
  struct Concern: Codable, Equatable, Identifiable {
    let id: UUID
    let metric: GalaxySSIHealthMetric
    var revision: Int
    var updatedAt: Date
    var assessment: Assessment
    var stage: Stage
    var context: Context?
    var target: Target?
    var targetRevision: Int?
    var reviewNote: String?
    var historyVersion: String? = nil
    var adoptedActions: [GalaxySSIHealthCarePlan.AdoptedAction]?
    var measurement: GalaxySSIHealthCareComparison.Sample?
    var comparison: GalaxySSIHealthCareComparison.Pair?
    var bloodPressureWarning: GalaxySSIHealthCarePriority.Warning?
  }
  struct Ledger: Codable {
    var current: [String: Concern] = [:]
    var history: [String: [Concern]] = [:]
    var deletedInput: [String: String] = [:]
    var bloodPressurePolicyVersion: String?
    var acknowledgedBloodPressure: Record?

    mutating func publish(_ next: Concern) {
      let key = next.metric.rawValue
      if let old = current[key] { history[old.id.uuidString, default: []].append(old) }
      current[key] = next
    }
  }

  static func assess(_ readings: [GalaxySSIHealthReading], context: Context?) -> Assessment? {
    guard let latest = readings.first else { return nil }
    let record = Record(latest)
    let rawReference = latest.referenceInterval ?? ""
    let reference = GalaxySSIHealthReportedResult.parse(rawReference, metric: .glucose, allowFreeformQualitative: false)
    let value = latest.metric == .bloodPressure ? nil : latest.value
    var signals: [Signal] = []
    if latest.metric != .bloodPressure, !rawReference.isEmpty {
      if let value, let reference, let bound = reference.lower {
        if reference.kind == .range, let high = reference.upper {
          if value < bound { signals.append(.reportLow) }
          if value > high { signals.append(.reportHigh) }
        } else if reference.kind == .comparison {
          let op = reference.comparator
          if (op == "<" && value >= bound) || (op == "<=" && value > bound) { signals.append(.reportHigh) }
          if (op == ">" && value <= bound) || (op == ">=" && value < bound) { signals.append(.reportLow) }
        }
      } else if value == nil { signals.append(.notExact) }
    }
    var guideline: String?
    if latest.metric == .glucose, let value,
       value >= (latest.unit == "mg/dL" ? Decimal(100) : Decimal(string: "5.6")!) {
      switch context?.record == record ? context?.applicability : nil {
      case .applicable: signals.append(.guidelineReview); guideline = "ADA 2026"
      case .excluded: signals.append(.guidelineScope)
      default: signals.append(.glucoseContext)
      }
    }
    var days = Set<Double>()
    let condition = latest.conditions.trimmingCharacters(in: .whitespacesAndNewlines)
    let previous = condition.isEmpty || value == nil ? [] : Array(readings.dropFirst().lazy.filter { reading in
      reading.metric == latest.metric && reading.unit == latest.unit &&
        reading.conditions.trimmingCharacters(in: .whitespacesAndNewlines) == condition &&
        reading.referenceInterval == latest.referenceInterval && reading.value != nil &&
        sameSource(reading, latest) && latest.measuredAt.timeIntervalSince(reading.measuredAt) >= 86_400 &&
        days.insert(floor(reading.measuredAt.timeIntervalSince1970 / 86_400)).inserted
    }.prefix(7))
    let numbers = previous.compactMap(\.value)
    let baseline: Baseline?
    if numbers.count >= 2, let low = numbers.min(), let high = numbers.max(), let value {
      baseline = .init(records: previous.map(Record.init), low: low, high: high)
      if value > numbers[0], numbers[0] > numbers[1] { signals.append(.rising) }
      if value < numbers[0], numbers[0] < numbers[1] { signals.append(.falling) }
    } else { baseline = nil }
    let result = latest.reported?.raw ?? [latest.value, latest.diastolic].compactMap { $0 }
      .map { NSDecimalNumber(decimal: $0).stringValue }.joined(separator: " / ")
    return .init(record: record, measuredAt: latest.measuredAt, result: result, unit: latest.unit,
      reference: rawReference, signals: signals, guidelineVersion: guideline, baseline: baseline)
  }

  static func inputDigest(_ assessment: Assessment) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return SHA256.hash(data: try encoder.encode(assessment)).map { String(format: "%02x", $0) }.joined()
  }

  private static func sameSource(_ lhs: GalaxySSIHealthReading, _ rhs: GalaxySSIHealthReading) -> Bool {
    guard lhs.reportSource?.original == rhs.reportSource?.original, lhs.tableSource?.batch == rhs.tableSource?.batch,
          lhs.bluetoothReceipt?.device == rhs.bluetoothReceipt?.device,
          (lhs.healthKitSource == nil) == (rhs.healthKitSource == nil),
          lhs.healthKitSource?.origin == rhs.healthKitSource?.origin else { return false }
    return lhs.healthKitSource == nil || lhs.healthKitSource?.origin != nil
  }
}
