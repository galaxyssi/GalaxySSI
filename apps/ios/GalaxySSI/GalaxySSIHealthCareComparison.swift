import Foundation

enum GalaxySSIHealthCareComparison {
  enum Kind: String, Codable { case newResult, recordCorrection, historyChanged }
  enum Gap: String, Encodable {
    case unitsDiffer, conditionsDiffer, conditionsUnknown, sourceDiffers, referenceDiffers,
         nonExactResult, contextUnconfirmed, contextDiffers, methodUnverified
  }
  enum Field: String, Encodable { case value, systolic, diastolic, pulse }

  struct Sample: Codable, Equatable {
    let record: GalaxySSIHealthCare.Record
    let metric: GalaxySSIHealthMetric
    let measuredAt: Date
    let value: Decimal?
    let diastolic: Decimal?
    let pulse: Decimal?
    let reported: String?
    let unit: String
    let reference: String
    let condition: String
    private let sourceIdentity: String

    init(_ reading: GalaxySSIHealthReading) {
      record = .init(reading)
      metric = reading.metric
      measuredAt = reading.measuredAt
      value = reading.value
      diastolic = reading.diastolic
      pulse = reading.pulse
      reported = reading.reported?.raw
      unit = reading.unit
      reference = reading.referenceInterval ?? ""
      condition = reading.conditions.trimmingCharacters(in: .whitespacesAndNewlines)
      if let bluetooth = reading.bluetoothReceipt { sourceIdentity = "bluetooth:" + bluetooth.device.uuidString }
      else if let report = reading.reportSource { sourceIdentity = "report:" + report.original.uuidString }
      else if let table = reading.tableSource { sourceIdentity = "table:" + table.batch.uuidString }
      else if let health = reading.healthKitSource { sourceIdentity = "apple_health:" + (health.origin ?? health.key) }
      else { sourceIdentity = "manual" }
    }

    var result: String {
      if let reported { return reported }
      return [value, diastolic].compactMap { $0 }.map(Self.number).joined(separator: " / ")
    }

    func sharesSource(with other: Self) -> Bool { sourceIdentity == other.sourceIdentity }
    static func number(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }

    var modelSample: ModelSample {
      .init(measuredAt: ISO8601DateFormatter().string(from: measuredAt), result: result, unit: unit,
        pulse: pulse.map(Self.number), reportReference: reference, conditionRecorded: !condition.isBlank)
    }
  }

  struct Pair: Codable, Equatable {
    let before: Sample
    let after: Sample
    let kind: Kind
    let previousContext: GalaxySSIHealthCare.Context?
    let nearestAtCapture: GalaxySSIHealthCare.Record?

    func gaps(currentContext: GalaxySSIHealthCare.Context?) -> [Gap] {
      var gaps: [Gap] = [.methodUnverified]
      if before.unit != after.unit { gaps.append(.unitsDiffer) }
      if before.condition.isBlank || after.condition.isBlank { gaps.append(.conditionsUnknown) }
      else if before.condition != after.condition { gaps.append(.conditionsDiffer) }
      if !before.sharesSource(with: after) { gaps.append(.sourceDiffers) }
      if before.reference != after.reference { gaps.append(.referenceDiffers) }
      if before.value == nil || after.value == nil ||
        (after.metric == .bloodPressure && (before.diastolic == nil || after.diastolic == nil)) { gaps.append(.nonExactResult) }
      if after.metric == .glucose {
        let newContext = currentContext?.record == after.record ? currentContext?.applicability : nil
        let oldContext = previousContext?.applicability
        if newContext == nil || newContext == .unknown || oldContext == nil || oldContext == .unknown {
          gaps.append(.contextUnconfirmed)
        }
        if let newContext, let oldContext, newContext != oldContext { gaps.append(.contextDiffers) }
      }
      return gaps
    }

    var changes: [Change] {
      guard kind == .newResult else { return [] }
      var changes: [Change] = []
      func add(_ field: Field, unit: String, from: Decimal?, to: Decimal?) {
        guard let from, let to else { return }
        let delta = to - from
        guard !delta.isNaN else { return }
        changes.append(.init(field: field, unit: unit, delta: Sample.number(delta)))
      }
      if before.unit == after.unit {
        add(after.metric == .bloodPressure ? .systolic : .value, unit: after.unit, from: before.value, to: after.value)
        if after.metric == .bloodPressure { add(.diastolic, unit: after.unit, from: before.diastolic, to: after.diastolic) }
      }
      if after.metric == .bloodPressure { add(.pulse, unit: "bpm", from: before.pulse, to: after.pulse) }
      return changes
    }

    func modelValue(currentContext: GalaxySSIHealthCare.Context?) -> ModelComparison {
      let priorStillLive = kind != .recordCorrection
      return .init(kind: kind, before: priorStillLive ? before.modelSample : nil, after: after.modelSample,
        previousContext: priorStillLive ? previousContext?.applicability : nil,
        currentContext: currentContext?.record == after.record ? currentContext?.applicability : nil,
        arithmeticOnly: changes, gaps: gaps(currentContext: currentContext))
    }
  }

  struct ModelSample: Encodable {
    let measuredAt: String
    let result: String
    let unit: String
    let pulse: String?
    let reportReference: String
    let conditionRecorded: Bool
  }
  struct Change: Encodable, Equatable {
    let field: Field
    let unit: String
    let delta: String
  }
  struct ModelComparison: Encodable {
    let kind: Kind
    let before: ModelSample?
    let after: ModelSample
    let previousContext: GalaxySSIHealthCare.Context.Applicability?
    let currentContext: GalaxySSIHealthCare.Context.Applicability?
    let arithmeticOnly: [Change]
    let gaps: [Gap]
    let clinicalDirectionVerified = false
  }

  static func reconcile(_ readings: [GalaxySSIHealthReading], prior: GalaxySSIHealthCare.Concern?) -> (Sample?, Pair?) {
    guard let latest = readings.first else { return (nil, nil) }
    let after = Sample(latest)
    let nearest = readings.dropFirst().prefix(30).first { $0.measuredAt < after.measuredAt }.map(Sample.init)
    func live(_ sample: Sample) -> Bool {
      readings.contains { $0.id == sample.record.id && $0.revision == sample.record.revision }
    }
    func pair(_ before: Sample?, kind: Kind) -> Pair? {
      guard let before else { return nil }
      let previous = [prior?.context, prior?.comparison?.previousContext].compactMap { $0 }
        .first { $0.record == before.record }
      return .init(before: before, after: after, kind: kind, previousContext: previous, nearestAtCapture: nearest?.record)
    }
    if let previous = prior?.measurement {
      if previous.record == after.record {
        if let comparison = prior?.comparison, comparison.nearestAtCapture == nearest?.record,
           comparison.kind == .recordCorrection || live(comparison.before) {
          return (after, comparison)
        }
        return (after, pair(nearest, kind: .historyChanged))
      }
      if previous.record.id == after.record.id { return (after, pair(previous, kind: .recordCorrection)) }
      if live(previous), previous.measuredAt < after.measuredAt { return (after, pair(previous, kind: .newResult)) }
      return (after, pair(nearest, kind: .historyChanged))
    }
    return (after, pair(nearest, kind: prior == nil ? .newResult : .historyChanged))
  }

  static func discussionBasis(_ concern: GalaxySSIHealthCare.Concern) -> String {
    func key(_ record: GalaxySSIHealthCare.Record?) -> String {
      record.map { $0.id.uuidString + ":" + String($0.revision) } ?? ""
    }
    let comparison = concern.comparison
    return AgentModelLoopRecoveryIdentity.sha256(["current": key(concern.measurement?.record),
      "before": key(comparison?.before.record), "kind": comparison?.kind.rawValue ?? "",
      "old_context": comparison?.previousContext?.applicability.rawValue ?? "",
      "new_context": concern.context?.applicability.rawValue ?? ""])
  }
}
