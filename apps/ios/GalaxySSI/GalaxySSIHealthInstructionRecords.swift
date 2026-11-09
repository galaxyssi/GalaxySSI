import Foundation

@MainActor
extension GalaxySSIHealthRecords {
  typealias Instructions = GalaxySSIHealthInstruction

  func visitInstructions(concern: UUID, metric: GalaxySSIHealthMetric, visit: UUID, before: Int? = nil,
      expected: VisitDocuments.Scope? = nil, now: Date = Date()) throws -> Instructions.Page {
    let originals = visitOriginalStore
    return try originals.withRestoreLease { lease in
      try originals.reconcileRestores(lease: lease)
      let archive = try load()
      let (_, scope) = try visitDocumentContext(concern: concern, metric: metric, visit: visit, archive: archive, now: now)
      guard before == nil || expected != nil, expected == nil || expected == scope else { throw Failure.stale }
      let rows = (archive.localCareInstructions?.current ?? [:]).values.filter { entry in
        entry.concern == concern && entry.visit == visit && (before.map { entry.revision < $0 } ?? true)
      }.sorted { $0.revision > $1.revision }.prefix(Instructions.pageSize + 1)
      let items = rows.prefix(Instructions.pageSize).map { instructionItem($0, scope: scope, archive: archive,
        originals: originals, lease: lease) }
      return .init(scope: scope, items: items, next: rows.count > Instructions.pageSize ? items.last?.entry.revision : nil)
    }
  }

  func visitInstructionHistory(id: UUID, expected: VisitDocuments.Scope, before: Int? = nil,
      validUntil: Date? = nil, now: Date = Date()) throws -> Instructions.History {
    let expires = min(validUntil ?? .distantFuture, now.addingTimeInterval(Instructions.readingLifetime))
    guard now < expires else { throw Failure.stale }
    let originals = visitOriginalStore
    return try originals.withRestoreLease { lease in
      try originals.reconcileRestores(lease: lease)
      let archive = try load()
      let (_, scope) = try visitDocumentContext(expected, archive: archive, now: now)
      guard expected == scope, let ledger = archive.localCareInstructions, let entry = ledger.current[id],
            entry.concern == scope.stamp.concern, entry.visit == scope.visit.id else { throw Failure.stale }
      let matching = ledger.receipts.values.filter { receipt in
        receipt.entry.id == entry.id && receipt.entry.concern == entry.concern && receipt.entry.visit == entry.visit &&
          (before.map { receipt.entry.revision < $0 } ?? true)
      }.sorted { $0.entry.revision > $1.entry.revision }.prefix(Instructions.pageSize + 1)
      let receipts = Array(matching.prefix(Instructions.pageSize))
      return .init(scope: scope, item: instructionItem(entry, scope: scope, archive: archive, originals: originals, lease: lease),
        receipts: receipts, next: matching.count > Instructions.pageSize ? receipts.last?.entry.revision : nil, expires: expires)
    }
  }

  private func instructionItem(_ entry: Instructions.Entry, scope: VisitDocuments.Scope, archive: Archive,
      originals: GalaxySSIHealthOriginalStore, lease: GalaxySSIHealthOriginalStore.RestoreLease) -> Instructions.Item {
    let original: VisitDocuments.Original?
    if let link = archive.localCareEncounterDocuments?[entry.source.linkID], entry.source.matches(link) {
      original = try? verifiedVisitDocumentOriginal(link, scope: scope, archive: archive, originals: originals, lease: lease)
    } else { original = nil }
    return .init(entry: entry, originalName: original?.name)
  }

  func readVisitInstructionSource(_ link: VisitDocuments.Link, page: Int, expected: VisitDocuments.Scope,
      forceOCR: Bool = false) async throws -> Instructions.Reading {
    let originals = visitOriginalStore
    let capturedAt = Date()
    let (bytes, original) = try originals.withRestoreLease { lease -> (Data, VisitDocuments.Original) in
      try originals.reconcileRestores(lease: lease)
      let archive = try load()
      let (_, scope) = try visitDocumentContext(expected, archive: archive, now: capturedAt)
      guard scope == expected, page > 0, page <= link.pageCount, link.page == nil || link.page == page
      else { throw Failure.stale }
      let original = try verifiedVisitDocumentOriginal(link, scope: scope, archive: archive, originals: originals, lease: lease)
      return (try originals.read(original, lease: lease), original)
    }
    let kind = original.kind, count = link.pageCount
    let worker = Task.detached(priority: .userInitiated) { () throws -> GalaxySSIHealthPDFText.Result in
      try Task.checkCancellation()
      if kind == .image {
        guard page == 1, count == 1 else { throw Failure.stale }
        return try GalaxySSIHealthPDFText.readImage(bytes)
      }
      guard try GalaxySSIHealthPDFText.pageCount(bytes) == count else { throw Failure.stale }
      return try GalaxySSIHealthPDFText.read(bytes, page: page - 1, forceOCR: forceOCR)
    }
    let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    try Task.checkCancellation()
    let now = Date(), expires = capturedAt.addingTimeInterval(Instructions.readingLifetime)
    guard now < expires, !result.regions.isEmpty else { throw Failure.unavailable }
    return try originals.withRestoreLease { lease in
      try originals.reconcileRestores(lease: lease)
      let archive = try load()
      let (_, scope) = try visitDocumentContext(expected, archive: archive, now: now)
      guard scope == expected, try verifiedVisitDocumentOriginal(link, scope: scope, archive: archive,
        originals: originals, lease: lease) == original else { throw Failure.stale }
      return .init(scope: scope, link: link, page: page, result: result, capturedAt: capturedAt, expires: expires)
    }
  }

  @discardableResult
  func createVisitInstruction(from reading: Instructions.Reading, selected: Set<Int>, operation: UUID,
      now: Date = Date()) throws -> Instructions.Receipt {
    guard now >= reading.capturedAt, now < reading.expires else { throw Failure.stale }
    let source = try Instructions.Source.select(reading, ids: selected)
    return try saveVisitInstruction(id: operation, operation: operation, expectedEntry: nil, expected: reading.scope,
      source: source, draft: .init(), now: now)
  }

  @discardableResult
  func updateVisitInstruction(_ draft: Instructions.Draft, history: Instructions.History, operation: UUID,
      now: Date = Date()) throws -> Instructions.Receipt {
    guard now < history.expires else { throw Failure.stale }
    return try saveVisitInstruction(id: history.item.id, operation: operation, expectedEntry: history.item.entry.revision,
      expected: history.scope, source: history.item.entry.source, draft: draft, now: now)
  }

  private func saveVisitInstruction(id: UUID, operation: UUID, expectedEntry: Int?, expected: VisitDocuments.Scope,
      source: Instructions.Source, draft: Instructions.Draft, now: Date) throws -> Instructions.Receipt {
    let originals = visitOriginalStore
    let (receipt, inserted) = try originals.withRestoreLease { lease -> (Instructions.Receipt, Bool) in
      try originals.reconcileRestores(lease: lease)
      var archive = try load()
      let (concern, scope) = try visitDocumentContext(expected, archive: archive, now: now)
      guard scope.visit == expected.visit, scope.stamp.matchesInputs(expected.stamp),
            let link = archive.localCareEncounterDocuments?[source.linkID], source.matches(link) else { throw Failure.stale }
      let original = try verifiedVisitDocumentOriginal(link, scope: scope, archive: archive, originals: originals, lease: lease)
      _ = try originals.read(original, lease: lease)
      var ledger = archive.localCareInstructions ?? .init()
      let (receipt, inserted) = try ledger.save(id: id, operation: operation, scope: scope, expectedEntry: expectedEntry,
        expectedConcern: expected.stamp.revision, source: source, draft: draft, now: now)
      if inserted {
        archive.localCareInstructions = ledger
        try publishVisitDocumentChange(concern, archive: &archive, now: now, notify: false)
      }
      return (receipt, inserted)
    }
    if inserted { NotificationCenter.default.post(name: Self.recordsChanged, object: owner) }
    return receipt
  }

  func deleteVisitInstruction(_ history: Instructions.History, now: Date = Date()) throws {
    guard now < history.expires else { throw Failure.stale }
    var archive = try load()
    let (concern, scope) = try visitDocumentContext(history.scope, archive: archive, now: now)
    let entry = history.item.entry
    guard scope == history.scope, concern.revision < Int.max - 1, entry.concern == concern.id, entry.visit == scope.visit.id,
          var ledger = archive.localCareInstructions, ledger.current[entry.id] == entry else { throw Failure.stale }
    ledger.remove(concern: concern.id, visit: entry.visit, entry: entry.id)
    archive.localCareInstructions = ledger
    try publishVisitDocumentChange(concern, archive: &archive, now: now)
  }
}
