import Foundation

struct GalaxySSIHealthRestoreReceipt: Codable, Equatable, Identifiable {
  static let maximumHistory = 100
  enum Failure: Error { case invalid }

  struct Counts: Codable, Equatable {
    var readings: Int
    var added: Int
    var duplicates: Int
    var conflicts: Int
    var replaced: Int
    var originals: Int
    var originalsAdded: Int
    var originalsReused: Int
    var originalsRepaired: Int
    var originalsUnavailable: Int
    var tablesAdded: Int
    var sources: Int
    var sourcesAdded: Int
    var sourcesReused: Int
    var sourcesSkipped: Int
    var missingReferences: Int

    var isValid: Bool {
      guard [readings, added, duplicates, conflicts, replaced].allSatisfy({ (0...10_000).contains($0) }),
            [originals, originalsAdded, originalsReused, originalsRepaired, originalsUnavailable].allSatisfy({ (0...1_000).contains($0) }),
            [sources, sourcesAdded, sourcesReused, sourcesSkipped].allSatisfy({ (0...20_000).contains($0) }),
            (0...30).contains(tablesAdded), (0...21_030).contains(missingReferences) else { return false }
      return readings == added + duplicates + conflicts + replaced &&
        originals == originalsAdded + originalsReused + originalsRepaired + originalsUnavailable &&
        sources == sourcesAdded + sourcesReused + sourcesSkipped
    }

    var unresolved: Bool { conflicts > 0 || originalsUnavailable > 0 || sourcesSkipped > 0 || missingReferences > 0 }
  }

  let id: UUID
  let at: Date
  let backupFingerprint: String
  let first: Date?
  let last: Date?
  let counts: Counts

  var isValid: Bool {
    guard at.timeIntervalSinceReferenceDate.isFinite, counts.isValid,
          backupFingerprint.utf8.count == 64,
          backupFingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return false }
    if counts.readings == 0 { return first == nil && last == nil }
    guard let first, let last, first.timeIntervalSinceReferenceDate.isFinite,
          last.timeIntervalSinceReferenceDate.isFinite else { return false }
    return first <= last
  }

  static func validHistory(_ entries: [Self], committed: Set<UUID>) -> Bool {
    entries.count <= maximumHistory && Set(entries.map(\.id)).count == entries.count &&
      entries.allSatisfy { $0.isValid && committed.contains($0.id) }
  }

  static func recording(_ receipt: Self, in entries: [Self], committed: Set<UUID>) throws -> [Self] {
    guard receipt.isValid, !committed.contains(receipt.id), validHistory(entries, committed: committed) else { throw Failure.invalid }
    return Array(([receipt] + entries).sorted { ($0.at, $0.id.uuidString) > ($1.at, $1.id.uuidString) }.prefix(maximumHistory))
  }
}
