import Foundation

enum GalaxySSIHealthCarePriority {
  static let version = "bp-record-warning-1"
  static let source = URL(string: "https://www.heart.org/en/health-topics/high-blood-pressure/understanding-blood-pressure-readings/when-to-call-911-for-high-blood-pressure")!
  static let sourceReviewDate = "2025-08-14"

  struct Warning: Codable, Equatable {
    let record: GalaxySSIHealthCare.Record
    let measuredAt: Date
    let unit: String
    let systolic: Decimal
    let diastolic: Decimal

    var displayedValue: String {
      GalaxySSIHealthCareComparison.Sample.number(systolic) + " / " +
        GalaxySSIHealthCareComparison.Sample.number(diastolic) + " " + unit
    }

    var handoff: Handoff {
      .init(recordedAt: ISO8601DateFormatter().string(from: measuredAt), sourceURL: GalaxySSIHealthCarePriority.source,
        sourceReviewDate: GalaxySSIHealthCarePriority.sourceReviewDate)
    }
  }

  struct Handoff: Encodable {
    let rule = GalaxySSIHealthCarePriority.version
    let recordedAt: String
    let sourceURL: URL
    let sourceReviewDate: String
    let currentSymptoms = "unknown"
    let currentEmergencyEstablished = false
    let scope = "adult_nonpregnant_not_assumed"
  }

  struct Cursor: Equatable, Comparable {
    let rank: Int
    let updatedAt: Date
    let id: String

    static func < (lhs: Self, rhs: Self) -> Bool {
      (lhs.rank, lhs.updatedAt, lhs.id) < (rhs.rank, rhs.updatedAt, rhs.id)
    }
  }

  static func evaluate(_ reading: GalaxySSIHealthReading?) -> Warning? {
    guard let reading, reading.metric == .bloodPressure, !reading.deleted, reading.isValid,
          let systolic = reading.value, let diastolic = reading.diastolic else { return nil }
    let scale: Decimal
    switch reading.unit {
    case "mmHg": scale = 1
    // NIST SP 811: one conventional mmHg is 133.3224 Pa.
    case "kPa": scale = Decimal(1_333_224) / Decimal(10_000_000)
    default: return nil
    }
    guard systolic > Decimal(180) * scale || diastolic > Decimal(120) * scale else { return nil }
    return .init(record: .init(reading), measuredAt: reading.measuredAt, unit: reading.unit,
      systolic: systolic, diastolic: diastolic)
  }

  static func page(_ concerns: [GalaxySSIHealthCare.Concern], acknowledged: GalaxySSIHealthCare.Record?,
                   after: Cursor? = nil, limit: Int = 30) -> (rows: [GalaxySSIHealthCare.Concern], next: Cursor?) {
    func cursor(_ concern: GalaxySSIHealthCare.Concern) -> Cursor {
      .init(rank: concern.bloodPressureWarning.map { $0.record != acknowledged } == true ? 1 : 0,
        updatedAt: concern.updatedAt, id: concern.id.uuidString)
    }
    let width = min(30, max(1, limit))
    let eligible = concerns.filter { concern in after.map { cursor(concern) < $0 } ?? true }
      .sorted { cursor($0) > cursor($1) }
    let rows = Array(eligible.prefix(width))
    return (rows, eligible.count > width ? rows.last.map(cursor) : nil)
  }
}
