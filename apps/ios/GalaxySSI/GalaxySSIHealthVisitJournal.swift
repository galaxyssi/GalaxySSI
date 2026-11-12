import Foundation

enum GalaxySSIHealthVisitJournal {
  static let pageSize = 30
  static let lifetime: TimeInterval = 600

  enum State: String, Codable { case active, review, paused, archived }
  enum Kind: String, Codable, Identifiable {
    case start, checkIn, review, pause, resume, archive, reopen
    var id: Self { self }
  }
  enum Decision: String, Codable, CaseIterable, Identifiable {
    case keep, discussChange, discussMaintenance
    var id: Self { self }
  }

  struct Input: Codable, Equatable {
    let kind: Kind
    var goal = ""
    var feelings = ""
    var function = ""
    var sleep = ""
    var barriers = ""
    var note = ""
    var needsReview = false
    var decision: Decision?

    func validated() throws -> Self {
      func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
      var copy = self
      copy.goal = clean(goal); copy.feelings = clean(feelings); copy.function = clean(function)
      copy.sleep = clean(sleep); copy.barriers = clean(barriers); copy.note = clean(note)
      let checkIn = [copy.feelings, copy.function, copy.sleep, copy.barriers]
      guard copy.goal.utf16.count <= 1_000,
            (checkIn + [copy.note]).allSatisfy({ $0.utf16.count <= 2_000 }),
            (kind == .review) == (decision != nil),
            kind == .start || kind == .review || copy.goal.isEmpty,
            kind == .checkIn || (!needsReview && checkIn.allSatisfy(\.isEmpty)) else {
        throw GalaxySSIHealthRecords.Failure.invalid
      }
      switch kind {
      case .start: guard !copy.goal.isEmpty else { throw GalaxySSIHealthRecords.Failure.invalid }
      case .checkIn: guard (checkIn + [copy.note]).contains(where: { !$0.isEmpty }) else {
        throw GalaxySSIHealthRecords.Failure.invalid
      }
      default: guard !copy.note.isEmpty else { throw GalaxySSIHealthRecords.Failure.invalid }
      }
      return copy
    }
  }

  struct Entry: Codable, Equatable {
    let id: UUID
    let concern: UUID
    let visit: UUID
    let revision: Int
    let visitRevision: Int
    let goal: String
    let state: State
    let createdAt: Date
    let updatedAt: Date
  }

  struct Receipt: Codable, Equatable, Identifiable {
    let id: UUID
    let expectedConcern: Int
    let expectedJournal: Int?
    let entry: Entry
    let input: Input
    let recordedAt: Date
    let source: GalaxySSIHealthCare.Record?
    let visitRevision: Int
  }

  struct Page {
    let scope: GalaxySSIHealthEncounterDocument.Scope
    let entry: Entry?
    let rows: [Receipt]
    let next: Int?
    let expires: Date
  }

  static func commands(_ state: State?, attended: Bool) -> [Kind] {
    switch (state, attended) {
    case (nil, true): return [.start]
    case (.active?, true), (.review?, true): return [.checkIn, .review, .pause, .archive]
    case (.paused?, true): return [.resume, .archive]
    case (.archived?, true): return [.reopen]
    case (.active?, false), (.review?, false): return [.pause, .archive]
    case (.paused?, false): return [.archive]
    default: return []
    }
  }

  struct Ledger: Codable {
    struct Key: Codable { let revision: Int; let operation: UUID }
    private(set) var entries: [UUID: Entry] = [:]
    private(set) var receipts: [UUID: Receipt] = [:]
    private var index: [UUID: [Key]] = [:]

    func page(_ scope: GalaxySSIHealthEncounterDocument.Scope, before: Int?, expires: Date) throws -> Page {
      let entry = entries[scope.visit.id], keys = index[scope.visit.id] ?? []
      guard before.map({ $0 > 0 && $0 <= scope.stamp.revision }) ?? true,
            entry.map({ $0.concern == scope.stamp.concern && $0.visit == scope.visit.id }) ?? keys.isEmpty,
            keys.last?.revision == entry?.revision else { throw GalaxySSIHealthRecords.Failure.stale }
      let end = before ?? Int.max
      var lo = 0, hi = keys.count
      while lo < hi {
        let mid = lo + (hi - lo) / 2
        if keys[mid].revision < end { lo = mid + 1 } else { hi = mid }
      }
      let rows = try keys[..<lo].suffix(pageSize).reversed().map { key -> Receipt in
        guard let receipt = receipts[key.operation], receipt.entry.revision == key.revision,
              receipt.entry.concern == scope.stamp.concern, receipt.entry.visit == scope.visit.id
        else { throw GalaxySSIHealthRecords.Failure.stale }
        return receipt
      }
      return .init(scope: scope, entry: entry, rows: rows, next: lo > pageSize ? rows.last?.entry.revision : nil, expires: expires)
    }

    mutating func save(_ raw: Input, operation: UUID, expected: Page, scope: GalaxySSIHealthEncounterDocument.Scope,
        concern: GalaxySSIHealthCare.Concern, now: Date) throws -> (Receipt, Bool) {
      let input = try raw.validated()
      let visit = scope.visit
      guard now.timeIntervalSince1970.isFinite, now.timeIntervalSince1970 > 0, now < expected.expires,
            expected.scope.visit == visit, scope.stamp.matchesInputs(expected.scope.stamp)
      else { throw GalaxySSIHealthRecords.Failure.stale }
      if let prior = receipts[operation] {
        guard prior.entry.concern == concern.id, prior.entry.visit == visit.id, prior.visitRevision == visit.revision,
              prior.expectedConcern == expected.scope.stamp.revision, prior.expectedJournal == expected.entry?.revision,
              prior.input == input else { throw GalaxySSIHealthRecords.Failure.stale }
        return (prior, false)
      }
      let current = entries[visit.id]
      guard scope == expected.scope, current == expected.entry, concern.revision < Int.max - 1,
            commands(current?.state, attended: visit.details.state == .attended).contains(input.kind),
            current.map({ $0.concern == concern.id && $0.visit == visit.id }) ?? true
      else { throw GalaxySSIHealthRecords.Failure.stale }
      let state: State
      switch input.kind {
      case .start: state = .active
      case .checkIn: state = input.needsReview ? .review : (current?.state ?? .active)
      case .review: state = input.decision == .keep ? .active : .review
      case .pause: state = .paused
      case .resume, .reopen: state = .review
      case .archive: state = .archived
      }
      let time = max(now, concern.updatedAt, current?.updatedAt ?? now)
      let entry = Entry(id: current?.id ?? operation, concern: concern.id, visit: visit.id, revision: concern.revision + 1,
        visitRevision: input.kind == .start || input.kind == .review ? visit.revision : (current?.visitRevision ?? visit.revision),
        goal: input.goal.isEmpty ? (current?.goal ?? "") : input.goal, state: state,
        createdAt: current?.createdAt ?? time, updatedAt: time)
      let receipt = Receipt(id: operation, expectedConcern: concern.revision, expectedJournal: current?.revision,
        entry: entry, input: input, recordedAt: now, source: concern.assessment.record, visitRevision: visit.revision)
      entries[visit.id] = entry
      receipts[operation] = receipt
      index[visit.id, default: []].append(.init(revision: entry.revision, operation: operation))
      return (receipt, true)
    }

    mutating func remove(concern: UUID, visit: UUID? = nil) {
      let owned = entries.values.filter { $0.concern == concern && (visit == nil || $0.visit == visit) }
      for entry in owned {
        for key in index.removeValue(forKey: entry.visit) ?? [] { receipts.removeValue(forKey: key.operation) }
        entries.removeValue(forKey: entry.visit)
      }
    }
  }

  static func text(_ key: String, _ fallback: String, _ language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.visit_journal." + key, fallback: fallback, language: language)
  }
}
