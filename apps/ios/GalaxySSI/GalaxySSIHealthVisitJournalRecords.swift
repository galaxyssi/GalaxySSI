import Foundation

@MainActor
extension GalaxySSIHealthRecords {
  typealias VisitJournal = GalaxySSIHealthVisitJournal

  private func journalReviewSource(visit: GalaxySSIHealthEncounter.Entry, entry: VisitJournal.Entry,
      permission: UUID) -> GalaxySSIHealthCareFollowUp.JournalReview? {
    guard visit.details.state == .attended, entry.visit == visit.id, entry.concern == visit.concern,
          entry.state == .active || entry.state == .review else { return nil }
    return .init(visit: visit.id, journal: entry.id, visitRevision: visit.revision,
      goalDigest: AgentModelLoopRecoveryIdentity.sha256(entry.goal), permission: permission)
  }

  func visitReviewIsCurrent(_ reminder: GalaxySSIHealthCareFollowUp.Reminder, archive: Archive) -> Bool {
    guard let source = reminder.journalReview, reminder.actionID == source.actionID,
          archive.localCareAllowed == true, archive.localCarePermission == source.permission,
          let concern = archive.localCare?.current[reminder.metric.rawValue], concern.id == reminder.concernID,
          concern.stage != .paused, concern.stage != .closed,
          let visit = archive.localCareEncounters?.entries[source.visit], visit.concern == concern.id,
          let entry = archive.localVisitJournals?.entries[source.visit] else { return false }
    return journalReviewSource(visit: visit, entry: entry, permission: source.permission) == source
  }

  func visitReviewStatus(_ page: VisitJournal.Page, now: Date = Date()) throws
      -> (eligible: Bool, enabled: Bool, reminder: GalaxySSIHealthCareFollowUp.Reminder?) {
    let archive = try load()
    let (concern, scope) = try visitDocumentContext(page.scope, archive: archive, now: now)
    let entry = archive.localVisitJournals?.entries[scope.visit.id]
    guard now < page.expires, scope == page.scope, entry == page.entry else { throw Failure.stale }
    let enabled = Self.careFollowUpPreferences(archive) != nil
    guard concern.stage != .paused, concern.stage != .closed, let entry,
          let source = journalReviewSource(visit: scope.visit, entry: entry, permission: scope.stamp.permission)
    else { return (false, enabled, nil) }
    let reminder = archive.localCareFollowUps?[source.actionID]
    return (true, enabled, reminder?.journalReview == source ? reminder : nil)
  }

  func scheduleVisitReview(_ page: VisitJournal.Page, replacing token: UUID?, at requested: Date,
      now: Date = Date()) throws {
    guard requested.timeIntervalSinceReferenceDate.isFinite, requested > now else { throw Failure.invalid }
    var archive = try load()
    let (concern, scope) = try visitDocumentContext(page.scope, archive: archive, now: now)
    guard now < page.expires, scope == page.scope, concern.revision < Int.max - 1,
          concern.stage != .paused, concern.stage != .closed, let entry = page.entry,
          archive.localVisitJournals?.entries[scope.visit.id] == entry,
          Self.careFollowUpPreferences(archive) != nil,
          let source = journalReviewSource(visit: scope.visit, entry: entry, permission: scope.stamp.permission),
          archive.localCareFollowUps?[source.actionID]?.id == token else { throw Failure.stale }
    var reminders = archive.localCareFollowUps ?? [:]
    reminders[source.actionID] = .init(id: UUID(), actionID: source.actionID, concernID: concern.id,
      metric: concern.metric, requestedAt: requested, journalReview: source)
    archive.localCareFollowUps = reminders
    try publishVisitDocumentChange(concern, archive: &archive, now: now)
  }

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
    try publishVisitDocumentChange(concern, archive: &archive, now: now)
  }
}
