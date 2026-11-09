import Foundation

@MainActor
extension GalaxySSIHealthRecords {
  typealias VisitJournal = GalaxySSIHealthVisitJournal

  func hasVisitJournal(_ visit: UUID, stamp: GalaxySSIHealthEncounter.Stamp, now: Date = Date()) -> Bool {
    guard let archive = try? load(),
          let (_, scope) = try? visitDocumentContext(concern: stamp.concern, metric: stamp.metric, visit: visit,
            archive: archive, now: now), scope.stamp == stamp else { return false }
    return archive.localVisitJournals?.entries[visit]?.concern == stamp.concern
  }

  func visitJournal(concern: UUID, metric: GalaxySSIHealthMetric, visit: UUID, before: Int? = nil,
      expected: VisitJournal.Page? = nil, now: Date = Date()) throws -> VisitJournal.Page {
    let expires = expected?.expires ?? now.addingTimeInterval(VisitJournal.lifetime)
    guard now < expires, before == nil || expected?.next == before else { throw Failure.stale }
    let archive = try load()
    let (_, scope) = try visitDocumentContext(concern: concern, metric: metric, visit: visit, archive: archive, now: now)
    guard expected == nil || expected?.scope == scope else { throw Failure.stale }
    let result = try (archive.localVisitJournals ?? .init()).page(scope, before: before, expires: expires)
    let checked = try load()
    let (_, latest) = try visitDocumentContext(scope, archive: checked, now: now)
    guard latest == scope, checked.localVisitJournals?.entries[visit] == result.entry else { throw Failure.stale }
    return result
  }

  @discardableResult
  func saveVisitJournal(_ input: VisitJournal.Input, operation: UUID, expected: VisitJournal.Page,
      now: Date = Date()) throws -> VisitJournal.Receipt {
    var archive = try load()
    let (concern, scope) = try visitDocumentContext(expected.scope, archive: archive, now: now)
    var ledger = archive.localVisitJournals ?? .init()
    let (receipt, inserted) = try ledger.save(input, operation: operation, expected: expected, scope: scope,
      concern: concern, now: now)
    if inserted {
      archive.localVisitJournals = ledger
      try publishVisitDocumentChange(concern, archive: &archive, now: now)
    }
    return receipt
  }

  func deleteVisitJournal(_ expected: VisitJournal.Page, now: Date = Date()) throws {
    guard now < expected.expires, let entry = expected.entry else { throw Failure.stale }
    var archive = try load()
    let (concern, scope) = try visitDocumentContext(expected.scope, archive: archive, now: now)
    guard scope == expected.scope, concern.revision < Int.max - 1,
          var ledger = archive.localVisitJournals, ledger.entries[scope.visit.id] == entry,
          entry.concern == concern.id else { throw Failure.stale }
    ledger.remove(concern: concern.id, visit: scope.visit.id)
    archive.localVisitJournals = ledger
    archive.localVisitJournalDiscussions?.removeValue(forKey: scope.visit.id)
    try publishVisitDocumentChange(concern, archive: &archive, now: now)
  }
}
