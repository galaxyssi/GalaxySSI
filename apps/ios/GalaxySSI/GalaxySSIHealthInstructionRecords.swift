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

  func saveVisitInstruction(id: UUID, operation: UUID, expectedEntry: Int?, expected: VisitDocuments.Scope,
      source: Instructions.Source, draft: Instructions.Draft, now: Date, modelProposalID: UUID? = nil) throws -> Instructions.Receipt {
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
      if let modelProposalID {
        guard let proposal = archive.localInstructionProposals?[modelProposalID],
              archive.healthOnlinePermission == proposal.binding.onlinePermission,
              let entry = ledger.current[id], proposal.draft == draft else { throw Failure.stale }
        if proposal.state == .applied {
          guard ledger.receipts[operation]?.entry.modelProposalID == modelProposalID else { throw Failure.stale }
        } else {
          guard proposal.state == .pending, entry.draft.canRequestProposal,
                try proposal.binding == instructionProposalBinding(entry, scope: scope, archive: archive)
          else { throw Failure.stale }
        }
      }
      let (receipt, inserted) = try ledger.save(id: id, operation: operation, scope: scope, expectedEntry: expectedEntry,
        expectedConcern: expected.stamp.revision, source: source, draft: draft, now: now, modelProposalID: modelProposalID)
      if inserted {
        archive.localCareInstructions = ledger
        let pending = (archive.localInstructionProposals ?? [:]).values.filter {
          $0.binding.instruction == id && $0.state == .pending
        }
        for proposal in pending {
          archive.localInstructionProposals?[proposal.id]?.state = proposal.id == modelProposalID ? .applied : .dismissed
        }
        var current = concern
        Self.invalidateInstructionActions(in: &current, archive: &archive) { $0.instruction == id }
        try publishVisitDocumentChange(current, archive: &archive, now: now, notify: false)
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
    guard scope == history.scope, concern.revision < Int.max - 1, entry.concern == concern.id,
          entry.visit == scope.visit.id,
          var ledger = archive.localCareInstructions, ledger.current[entry.id] == entry else { throw Failure.stale }
    ledger.remove(concern: concern.id, visit: entry.visit, entry: entry.id)
    archive.localCareInstructions = ledger
    archive.localInstructionProposals = archive.localInstructionProposals?.filter { $0.value.binding.instruction != entry.id }
    var current = concern
    Self.invalidateInstructionActions(in: &current, archive: &archive) { $0.instruction == entry.id }
    try publishVisitDocumentChange(current, archive: &archive, now: now)
  }

  @discardableResult
  func confirmVisitInstructionAction(_ history: Instructions.History, acknowledged: Bool,
      now: Date = Date()) throws -> GalaxySSIHealthCarePlan.AdoptedAction {
    guard acknowledged, now < history.expires, now.timeIntervalSince1970.isFinite, now.timeIntervalSince1970 > 0
    else { throw Failure.invalid }
    let originals = visitOriginalStore
    let (action, inserted) = try originals.withRestoreLease { lease -> (GalaxySSIHealthCarePlan.AdoptedAction, Bool) in
      try originals.reconcileRestores(lease: lease)
      var archive = try load()
      let (concern, scope) = try visitDocumentContext(history.scope, archive: archive, now: now)
      let entry = history.item.entry
      guard scope.visit == history.scope.visit, scope.stamp.matchesInputs(history.scope.stamp),
            concern.stage != .paused, concern.stage != .closed, concern.assessment.record != nil,
            localCareProfileIsCurrent(concern.profileScope),
            archive.localCareInstructions?.current[entry.id] == entry, entry.concern == concern.id,
            entry.visit == scope.visit.id, entry.draft.eligibleForAction,
            let link = archive.localCareEncounterDocuments?[entry.source.linkID], entry.source.matches(link),
            let sourceURL = URL(string: "galaxyssi-health-original:" + entry.source.originalID.uuidString)
      else { throw Failure.stale }
      let original = try verifiedVisitDocumentOriginal(link, scope: scope, archive: archive, originals: originals, lease: lease)
      _ = try originals.read(original, lease: lease)
      let basis = try GalaxySSIHealthCare.inputDigest(concern.assessment)
      let reference = Instructions.ActionReference(instruction: entry.id, revision: entry.revision, visit: entry.visit,
        link: link.id, original: original.id, fingerprint: entry.source.fingerprint, page: entry.source.page,
        pageCount: entry.source.pageCount, permission: scope.stamp.permission, profileEpoch: concern.profileScopeEpoch,
        assessment: basis)
      var actions = concern.adoptedActions ?? []
      if let saved = actions.first(where: { $0.proposalID == entry.id && $0.action.id == entry.revision }) {
        guard saved.instruction == reference else { throw Failure.stale }
        return (saved, false)
      }
      guard scope == history.scope, concern.revision < Int.max - 1 else { throw Failure.stale }
      let action = GalaxySSIHealthCarePlan.AdoptedAction(proposalID: entry.id,
        action: .init(id: entry.revision, kind: .clinicalInstruction, description: entry.draft.value(.name).text,
          rationale: entry.draft.value(.details).text, sourceIndex: 0, dueFrom: nil, dueUntil: nil),
        source: .init(title: original.name, url: sourceURL, version: String(entry.revision), applicability: ""),
        confirmedAt: now, instruction: reference)
      actions.append(action)
      var current = concern
      current.adoptedActions = actions
      try publishVisitDocumentChange(current, archive: &archive, now: now, notify: false)
      return (action, true)
    }
    if inserted { NotificationCenter.default.post(name: Self.recordsChanged, object: owner) }
    return action
  }

  func instructionActionIsCurrent(_ action: GalaxySSIHealthCarePlan.AdoptedAction,
      concern: GalaxySSIHealthCare.Concern, archive: Archive, now: Date, verifyOriginal: Bool = true) -> Bool {
    guard let ref = action.instruction, action.action.kind == .clinicalInstruction,
          concern.stage != .paused, concern.stage != .closed,
          ref.instruction == action.proposalID, ref.revision == action.action.id,
          archive.matchesLocalCarePermission(ref.permission), ref.profileEpoch == concern.profileScopeEpoch,
          (try? GalaxySSIHealthCare.inputDigest(concern.assessment)) == ref.assessment,
          let entry = archive.localCareInstructions?.current[ref.instruction], entry.concern == concern.id, ref.matches(entry),
          archive.localCareEncounters?.entries[ref.visit]?.concern == concern.id,
          let link = archive.localCareEncounterDocuments?[ref.link], link.concern == concern.id,
          link.visit == ref.visit, entry.source.matches(link) else { return false }
    // Archive writes can already hold the original-store lease. Delivery and review verify the file independently.
    guard verifyOriginal else { return true }
    let originals = visitOriginalStore
    return (try? originals.withRestoreLease { lease in
      let (_, scope) = try visitDocumentContext(concern: concern.id, metric: concern.metric, visit: ref.visit,
        archive: archive, now: now)
      let original = try verifiedVisitDocumentOriginal(link, scope: scope, archive: archive, originals: originals, lease: lease)
      _ = try originals.read(original, lease: lease)
      return true
    }) == true
  }

  static func invalidateInstructionActions(in concern: inout GalaxySSIHealthCare.Concern, archive: inout Archive,
      matching: (Instructions.ActionReference) -> Bool) {
    guard var actions = concern.adoptedActions else { return }
    for index in actions.indices {
      guard var ref = actions[index].instruction, !ref.invalidated, matching(ref) else { continue }
      ref.invalidated = true
      actions[index].instruction = ref
      archive.localCareFollowUps?.removeValue(forKey: actions[index].id)
    }
    concern.adoptedActions = actions
  }
}
