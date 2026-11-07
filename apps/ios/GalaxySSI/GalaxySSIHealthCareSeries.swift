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

    var wire: AgentMcpJSONValue {
      .object(["before_time": .int(beforeTime), "before_id": .string(beforeID.uuidString.lowercased())])
    }
  }

  struct Binding: Equatable {
    let concern: UUID
    let revision: Int
    let historyVersion: String
    let permission: UUID
  }

  struct Row: Identifiable {
    let sample: GalaxySSIHealthCareComparison.Sample
    let context: GalaxySSIHealthCare.Context?
    let gaps: [GalaxySSIHealthCareComparison.Gap]
    var id: UUID { sample.record.id }
  }

  struct Page {
    let binding: Binding
    let rows: [Row]
    let next: Cursor?
  }

  static func version(_ readings: [GalaxySSIHealthReading]) -> String {
    var digest = SHA256()
    digest.update(data: Data("galaxyssi.health-history.v1\n".utf8))
    for row in readings {
      digest.update(data: Data("\(row.id.uuidString):\(row.revision)\n".utf8))
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  static func page(_ readings: [GalaxySSIHealthReading], concern: GalaxySSIHealthCare.Concern,
                   binding: Binding, after: Cursor?) throws -> Page {
    let start: Int
    if let after {
      guard let index = readings.firstIndex(where: { $0.id == after.beforeID }), Cursor(readings[index]) == after
      else { throw GalaxySSIHealthRecords.Failure.stale }
      start = index + 1
    } else { start = 0 }
    let selected = readings.dropFirst(start).prefix(pageSize)
    let rows = selected.map { reading -> Row in
      let sample = GalaxySSIHealthCareComparison.Sample(reading)
      let context = [concern.context, concern.comparison?.previousContext].compactMap { $0 }
        .first { $0.record == sample.record }
      let gaps = concern.measurement.flatMap { current -> [GalaxySSIHealthCareComparison.Gap]? in
        guard current.record != sample.record else { return nil }
        return GalaxySSIHealthCareComparison.Pair(before: sample, after: current, kind: .historyChanged,
          previousContext: context, nearestAtCapture: nil).gaps(currentContext: concern.context)
      } ?? []
      return Row(sample: sample, context: context, gaps: gaps)
    }
    let hasEarlier = start + selected.count < readings.count
    let next = hasEarlier ? selected.last.flatMap(Cursor.init) : nil
    guard !hasEarlier || next != nil else { throw GalaxySSIHealthRecords.Failure.invalid }
    return Page(binding: binding, rows: rows, next: next)
  }
}
