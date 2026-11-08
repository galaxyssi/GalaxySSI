import Foundation

enum GalaxySSIHealthEncounter {
  enum State: String, CaseIterable, Codable, Identifiable {
    case planned, booked, attended, cancelled
    var id: String { rawValue }

    func title(_ language: String) -> String {
      let fallback: String
      switch self {
      case .planned: fallback = "Planned"
      case .booked: fallback = "Booking recorded"
      case .attended: fallback = "Attended"
      case .cancelled: fallback = "Cancelled"
      }
      return GalaxySSIHealthEncounter.text(rawValue, fallback, language)
    }
  }

  struct Draft: Codable, Equatable {
    var purpose = ""
    var facility = ""
    var state = State.planned
    var plannedAt: Date?
    var attendedAt: Date?
    var zone = TimeZone.current.identifier
    var note = ""

    func validated(now: Date) throws -> Self {
      var copy = self
      copy.purpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
      copy.facility = facility.trimmingCharacters(in: .whitespacesAndNewlines)
      copy.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !copy.purpose.isEmpty, copy.purpose.utf16.count <= 500, copy.facility.utf16.count <= 500,
            copy.note.utf16.count <= 4_000, TimeZone(identifier: zone) != nil,
            now.timeIntervalSince1970.isFinite, now.timeIntervalSince1970 > 0,
            [plannedAt, attendedAt].compactMap({ $0 }).allSatisfy({
              $0.timeIntervalSince1970.isFinite && $0.timeIntervalSince1970 > 0
            }), (state == .attended) == (attendedAt != nil),
            state != .booked || plannedAt != nil, attendedAt.map({ $0 <= now }) ?? true
      else { throw GalaxySSIHealthRecords.Failure.invalid }
      return copy
    }
  }

  struct Entry: Codable, Equatable, Identifiable {
    let id: UUID
    let concern: UUID
    let revision: Int
    let source: GalaxySSIHealthCare.Record?
    let created: Date
    let updated: Date
    let details: Draft
  }

  struct Stamp: Equatable {
    let concern: UUID
    let metric: GalaxySSIHealthMetric
    let revision: Int
    let permission: UUID
    let records: [GalaxySSIHealthCare.Record]

    func matchesInputs(_ other: Self) -> Bool {
      concern == other.concern && metric == other.metric && permission == other.permission && records == other.records
    }
  }

  struct Receipt: Codable, Equatable {
    let expectedConcern: Int
    let expectedEntry: Int?
    let entry: Entry
  }

  struct Page {
    let stamp: Stamp
    let entry: Entry?
    let rows: [Entry]
    let next: Int?
  }

  struct Ledger: Codable {
    var entries: [UUID: Entry] = [:]
    var receipts: [UUID: Receipt] = [:]

    func page(_ stamp: Stamp, entryID: UUID?, before: Int?) throws -> Page {
      let selected: Entry?
      let candidates: [Entry]
      if let entryID {
        guard let entry = entries[entryID], entry.concern == stamp.concern else {
          throw GalaxySSIHealthRecords.Failure.stale
        }
        selected = entry
        candidates = receipts.values.compactMap { receipt in
          receipt.entry.id == entryID && receipt.entry.concern == stamp.concern ? receipt.entry : nil
        }
      } else {
        selected = nil
        candidates = entries.values.filter { $0.concern == stamp.concern }
      }
      let page = Array(candidates.filter { $0.revision < (before ?? Int.max) }
        .sorted { $0.revision > $1.revision }.prefix(31))
      return .init(stamp: stamp, entry: selected, rows: Array(page.prefix(30)),
        next: page.count > 30 ? page[29].revision : nil)
    }

    mutating func save(id: UUID, operation: UUID, expected: Stamp, expectedEntry: Int?, draft: Draft,
        concern: GalaxySSIHealthCare.Concern, now: Date) throws -> (receipt: Receipt, inserted: Bool) {
      let details = try draft.validated(now: now)
      if let prior = receipts[operation] {
        guard prior.entry.id == id, prior.entry.concern == concern.id, prior.expectedConcern == expected.revision,
              prior.expectedEntry == expectedEntry, prior.entry.details == details else {
          throw GalaxySSIHealthRecords.Failure.stale
        }
        return (prior, false)
      }
      let current = entries[id]
      guard concern.revision == expected.revision, concern.revision < Int.max - 1,
            current?.revision == expectedEntry, current.map({ $0.concern == concern.id }) ?? true else {
        throw GalaxySSIHealthRecords.Failure.stale
      }
      let entry = Entry(id: id, concern: concern.id, revision: concern.revision + 1,
        source: current == nil ? concern.assessment.record : current?.source, created: current?.created ?? now,
        updated: max(now, concern.updatedAt, current?.updated ?? now), details: details)
      let receipt = Receipt(expectedConcern: expected.revision, expectedEntry: expectedEntry, entry: entry)
      entries[id] = entry
      receipts[operation] = receipt
      return (receipt, true)
    }

    mutating func remove(concern: UUID, entry: UUID? = nil) {
      func keep(_ value: Entry) -> Bool { value.concern != concern || (entry != nil && value.id != entry) }
      entries = entries.filter { keep($0.value) }
      receipts = receipts.filter { keep($0.value.entry) }
    }
  }

  static func possibleTimes(day: Date, hour: Int, minute: Int, zone: TimeZone) -> [Date] {
    guard (0..<24).contains(hour), (0..<60).contains(minute) else { return [] }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    var components = calendar.dateComponents([.year, .month, .day], from: day)
    components.hour = hour
    components.minute = minute
    components.second = 0
    let start = calendar.startOfDay(for: day).addingTimeInterval(-1)
    let candidates = [Calendar.RepeatedTimePolicy.first, .last].compactMap { policy in
      calendar.nextDate(after: start, matching: components, matchingPolicy: .strict, repeatedTimePolicy: policy)
    }.filter { calendar.isDate($0, inSameDayAs: day) }
    return Array(Set(candidates)).sorted()
  }

  static func text(_ key: String, _ fallback: String, _ language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.encounter." + key, fallback: fallback, language: language)
  }
}
