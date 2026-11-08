import CryptoKit
import Foundation

enum GalaxySSIHealthCareSeries {
  static let pageSize = 30
  static let wireProtocol = "galaxyssi.health-history.v1"

  struct Cursor: Equatable {
    let beforeTime: Int64
    let beforeID: UUID

    init?(_ reading: GalaxySSIHealthReading) {
      guard let time = Int64(exactly: (reading.measuredAt.timeIntervalSince1970 * 1_000).rounded(.down)) else { return nil }
      beforeTime = time
      beforeID = reading.id
    }
  }

  struct Binding: Equatable {
    let concern: UUID
    let revision: Int
    let historyVersion: String
    // An existing opt-in may predate epochs; every new opt-in receives a unique one.
    let permission: UUID?
  }

  enum Gap: String {
    case unitsDiffer, conditionsDiffer, conditionsUnknown, sourceDiffers, referenceDiffers,
         nonExactResult, contextUnconfirmed, methodUnverified
  }

  struct Row: Identifiable {
    let record: GalaxySSIHealthCare.Record
    let measuredAt: Date
    let result: String
    let unit: String
    let gaps: [Gap]
    var id: UUID { record.id }
  }

  struct Page {
    let binding: Binding
    let rows: [Row]
    let next: Cursor?
  }

  static func version(_ readings: [GalaxySSIHealthReading]) -> String {
    var digest = SHA256()
    digest.update(data: Data((wireProtocol + "\n").utf8))
    for row in readings {
      digest.update(data: Data("\(row.id.uuidString):\(row.revision)\n".utf8))
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  static func page(_ readings: [GalaxySSIHealthReading], binding: Binding, after: Cursor?) throws -> Page {
    let start: Int
    if let after {
      guard let index = readings.firstIndex(where: { $0.id == after.beforeID }), Cursor(readings[index]) == after
      else { throw GalaxySSIHealthRecords.Failure.stale }
      start = index + 1
    } else { start = 0 }
    let selected = readings.dropFirst(start).prefix(pageSize)
    let current = readings.first
    let rows = selected.map { reading -> Row in
      let record = GalaxySSIHealthCare.Record(reading)
      let numbers = [reading.value, reading.diastolic].compactMap { $0 }
        .map { NSDecimalNumber(decimal: $0).stringValue }
      let gaps = current.flatMap { $0.id == reading.id ? nil : comparisonGaps(reading, $0) } ?? []
      return Row(record: record, measuredAt: reading.measuredAt,
        result: reading.reported?.raw ?? numbers.joined(separator: " / "), unit: reading.unit, gaps: gaps)
    }
    let hasEarlier = start + selected.count < readings.count
    let next = hasEarlier ? selected.last.flatMap(Cursor.init) : nil
    guard !hasEarlier || next != nil else { throw GalaxySSIHealthRecords.Failure.invalid }
    return Page(binding: binding, rows: rows, next: next)
  }

  private static func comparisonGaps(_ earlier: GalaxySSIHealthReading, _ current: GalaxySSIHealthReading) -> [Gap] {
    var gaps: [Gap] = [.methodUnverified]
    if earlier.unit != current.unit { gaps.append(.unitsDiffer) }
    if earlier.conditions.isBlank || current.conditions.isBlank { gaps.append(.conditionsUnknown) }
    else if earlier.conditions != current.conditions { gaps.append(.conditionsDiffer) }
    if !GalaxySSIHealthCare.sameSource(earlier, current) { gaps.append(.sourceDiffers) }
    if (earlier.referenceInterval ?? "") != (current.referenceInterval ?? "") { gaps.append(.referenceDiffers) }
    if earlier.value == nil || current.value == nil { gaps.append(.nonExactResult) }
    // A current glucose context is not confirmation of an earlier sample's context.
    if current.metric == .glucose { gaps.append(.contextUnconfirmed) }
    return gaps
  }
}

extension GalaxySSIHealthRecords {
  func localCareMeasurementPage(id: UUID, metric: GalaxySSIHealthMetric,
                                expected: GalaxySSIHealthCareSeries.Binding? = nil,
                                after: GalaxySSIHealthCareSeries.Cursor? = nil, now: Date = Date()) throws
    -> GalaxySSIHealthCareSeries.Page {
    let archive = try load()
    guard archive.localCareAllowed == true else { throw Failure.permission }
    let readings = archive.current.filter { $0.metric == metric && $0.isValid && $0.measuredAt <= now }
    let latest = readings.first.map { GalaxySSIHealthCare.Record($0) }
    guard let concern = archive.localCare?.current[metric.rawValue], concern.id == id,
          concern.assessment.record == latest else { throw Failure.stale }
    let binding = GalaxySSIHealthCareSeries.Binding(concern: id, revision: concern.revision,
      historyVersion: GalaxySSIHealthCareSeries.version(readings), permission: archive.localCarePermission)
    guard (expected == nil && after == nil) || expected == binding else { throw Failure.stale }
    return try GalaxySSIHealthCareSeries.page(readings, binding: binding, after: after)
  }
}
