import CryptoKit
import Foundation

@MainActor
extension GalaxySSIHealthRecords {
  typealias InstructionAssist = GalaxySSIHealthInstructionProposal

  func instructionProposalBinding(_ entry: Instructions.Entry, scope: VisitDocuments.Scope, archive: Archive)
      throws -> InstructionAssist.Binding {
    guard let online = archive.healthOnlinePermission, scope.stamp.concern == entry.concern, scope.visit.id == entry.visit
    else { throw Failure.permission }
    return .init(owner: owner, concern: entry.concern, visit: entry.visit, visitRevision: scope.visit.revision,
      instruction: entry.id, revision: entry.revision, sourceDigest: try InstructionAssist.Binding.digest(entry.source),
      localPermission: scope.stamp.permission, onlinePermission: online)
  }

  func pendingVisitInstructionProposal(_ history: Instructions.History, now: Date = Date()) throws -> InstructionAssist.Proposal? {
    guard now < history.expires else { throw Failure.stale }
    let archive = try load()
    let (_, scope) = try visitDocumentContext(history.scope, archive: archive, now: now)
    let entry = history.item.entry
    guard history.scope == scope, archive.localCareInstructions?.current[entry.id] == entry
    else { throw Failure.stale }
    guard let binding = try? instructionProposalBinding(entry, scope: scope, archive: archive) else { return nil }
    return archive.localInstructionProposals?.values.first { $0.binding == binding && $0.state == .pending }
  }

  func prepareVisitInstructionProposal(_ history: Instructions.History, contactID: String, model: CloudModelConfig,
      key: String, now: Date = Date()) throws -> InstructionAssist.Approval {
    guard now < history.expires, history.item.entry.draft.canRequestProposal,
          let endpoint = GalaxySSIHealthCareDiscussion.endpoint(for: model),
          CloudModelCredentialPolicy.isStoredCredential(key) else { throw Failure.permission }
    return try withInstructionProposalSource(history.scope, entry: history.item.entry, now: now) { archive, scope in
      let entry = history.item.entry
      let binding = try instructionProposalBinding(entry, scope: scope, archive: archive)
      guard !hasPendingInstructionProposal(binding, archive: archive) else { throw Failure.stale }
      return .init(id: UUID(), binding: binding, concernRevision: scope.stamp.revision, contactID: contactID,
        model: model, endpoint: endpoint,
        destination: GalaxySSIHealthCareDiscussion.destination(contactID: contactID, model: model, endpoint: endpoint,
          credential: SHA256.hash(data: Data(key.utf8))),
        source: entry.source, expires: history.expires)
    }
  }

  func validateVisitInstructionProposal(_ approval: InstructionAssist.Approval, history: Instructions.History,
      now: Date = Date()) throws {
    guard now < approval.expires, now < history.expires else { throw Failure.stale }
    try withInstructionProposalSource(history.scope, entry: history.item.entry, now: now) { archive, scope in
      try checkInstructionProposal(approval, history: history, archive: archive, scope: scope)
      guard !hasPendingInstructionProposal(approval.binding, archive: archive) else { throw Failure.stale }
    }
  }

  func stageVisitInstructionProposal(_ input: AgentMcpJSONObject, approval: InstructionAssist.Approval,
      history: Instructions.History, now: Date = Date()) throws -> InstructionAssist.Proposal {
    guard now < approval.expires, now < history.expires else { throw Failure.stale }
    return try withInstructionProposalSource(history.scope, entry: history.item.entry, now: now) { archive, scope in
      try checkInstructionProposal(approval, history: history, archive: archive, scope: scope)
      let candidate = try InstructionAssist.Proposal.parse(input, approval: approval, now: now)
      var proposals = archive.localInstructionProposals ?? [:]
      if let prior = proposals[approval.id] {
        guard prior.binding == candidate.binding, prior.destination == candidate.destination,
              prior.kind == candidate.kind, prior.fields == candidate.fields else { throw Failure.stale }
        return prior
      }
      guard !hasPendingInstructionProposal(approval.binding, archive: archive) else { throw Failure.stale }
      proposals[approval.id] = candidate
      var updated = archive
      updated.localInstructionProposals = proposals
      try persistInstructionProposals(updated)
      return candidate
    }
  }

  func dismissVisitInstructionProposal(_ proposal: InstructionAssist.Proposal, history: Instructions.History,
      now: Date = Date()) throws {
    guard now < history.expires else { throw Failure.stale }
    var archive = try load()
    let (_, scope) = try visitDocumentContext(history.scope, archive: archive, now: now)
    guard scope == history.scope, archive.localCareInstructions?.current[history.item.id] == history.item.entry,
          try proposal.binding == instructionProposalBinding(history.item.entry, scope: scope, archive: archive),
          archive.localInstructionProposals?[proposal.id] == proposal, proposal.state == .pending
    else { throw Failure.stale }
    archive.localInstructionProposals?[proposal.id]?.state = .dismissed
    try persistInstructionProposals(archive)
  }

  @discardableResult
  func applyVisitInstructionProposal(_ proposal: InstructionAssist.Proposal, history: Instructions.History,
      now: Date = Date()) throws -> Instructions.Receipt {
    guard now < history.expires, proposal.state == .pending else { throw Failure.stale }
    let entry = history.item.entry
    return try saveVisitInstruction(id: entry.id, operation: proposal.id, expectedEntry: entry.revision,
      expected: history.scope, source: entry.source, draft: proposal.draft, now: now, modelProposalID: proposal.id)
  }

  private func hasPendingInstructionProposal(_ binding: InstructionAssist.Binding, archive: Archive) -> Bool {
    archive.localInstructionProposals?.values.contains { $0.binding == binding && $0.state == .pending } == true
  }

  private func checkInstructionProposal(_ approval: InstructionAssist.Approval, history: Instructions.History,
      archive: Archive, scope: VisitDocuments.Scope) throws {
    let entry = history.item.entry
    guard scope.stamp.revision == approval.concernRevision, approval.source == entry.source, entry.draft.canRequestProposal,
          try approval.binding == instructionProposalBinding(entry, scope: scope, archive: archive)
    else { throw Failure.stale }
  }

  private func withInstructionProposalSource<T>(_ expected: VisitDocuments.Scope, entry: Instructions.Entry, now: Date,
      _ work: (Archive, VisitDocuments.Scope) throws -> T) throws -> T {
    let originals = visitOriginalStore
    return try originals.withRestoreLease { lease in
      try originals.reconcileRestores(lease: lease)
      let archive = try load()
      let (_, scope) = try visitDocumentContext(expected, archive: archive, now: now)
      guard scope == expected, archive.localCareInstructions?.current[entry.id] == entry,
            let link = archive.localCareEncounterDocuments?[entry.source.linkID], entry.source.matches(link)
      else { throw Failure.stale }
      let original = try verifiedVisitDocumentOriginal(link, scope: scope, archive: archive, originals: originals, lease: lease)
      _ = try originals.read(original, lease: lease)
      return try work(archive, scope)
    }
  }
}
