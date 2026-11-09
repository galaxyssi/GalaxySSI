import CryptoKit
import Foundation

@MainActor
extension GalaxySSIHealthRecords {
  typealias JournalDiscussion = GalaxySSIHealthVisitJournalRead

  func prepareVisitJournalDiscussion(_ expected: VisitJournal.Page, question: String, contact: GalaxySSIContact,
      key: String, now: Date = Date()) throws -> JournalDiscussion.Approval {
    let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard now < expected.expires, !question.isEmpty, question.utf8.count <= 2_048,
          !contact.deleted, contact.deliveryMode == .cloudAPI, let model = contact.selectedCloudModel,
          let endpoint = GalaxySSIHealthCareDiscussion.endpoint(for: model),
          CloudModelCredentialPolicy.isStoredCredential(key) else { throw Failure.permission }
    let credential = SHA256.hash(data: Data(key.utf8))
    let destination = GalaxySSIHealthCareDiscussion.destination(contactID: contact.id, model: model,
      endpoint: endpoint, credential: credential)
    let archive = try load()
    let (_, scope) = try visitDocumentContext(expected.scope, archive: archive, now: now)
    let (entry, binding) = try journalBinding(archive, scope: scope, destination: destination)
    guard expected.scope == scope, expected.entry == entry else { throw Failure.stale }
    let previous = (archive.localVisitJournalDiscussions?[scope.visit.id] ?? []).filter { $0.binding == binding }
    let latest = Array(previous.filter { $0.answer != nil }.suffix(4))
    let summary: AgentMcpJSONObject = ["revision": .int(Int64(binding.revision)),
      "journal_revision": .int(Int64(binding.journalRevision)), "visit_revision": .int(Int64(binding.visitRevision)),
      "goal": .string(entry.goal), "visit_purpose": .string(scope.visit.details.purpose), "state": .string(entry.state.rawValue),
      "source_review_required": .bool(entry.visitRevision != scope.visit.revision), "history_included": .bool(false),
      "read_tool": .string(JournalDiscussion.providerName), "read_tool_id": .string(JournalDiscussion.toolID),
      "prior_exchanges_included": .bool(!latest.isEmpty),
      "self_reported": .bool(true), "clinical_improvement_verified": .bool(false)]
    let payload: AgentMcpJSONObject = ["selected_visit_followup": .object(summary), "question": .string(question),
      "previous": .array(latest.map { .object(["question": .string($0.question), "answer": .string($0.answer ?? "")]) })]
    let text = AgentMcpJSONCodec.stringify(payload)
    guard text.utf8.count <= GalaxySSIHealthCareDiscussion.maximumPayloadBytes else { throw Failure.invalid }
    let transport = GalaxySSIHealthCareDiscussion.Approval(id: UUID(), owner: owner,
      threadID: previous.last?.conversation ?? UUID(), priorTurnID: previous.last?.id, concernID: scope.stamp.concern,
      metric: scope.stamp.metric, concernRevision: scope.stamp.revision, carePermission: scope.stamp.permission,
      onlinePermission: binding.onlinePermission, destinationID: contact.id, destinationDigest: destination,
      destination: .cloud(model: model, endpoint: endpoint, credential: credential), question: question, payload: text, reviewedAt: now)
    return .init(binding: binding, summary: summary, previous: latest, transport: transport,
      expires: min(expected.expires, now.addingTimeInterval(GalaxySSIHealthCareDiscussion.approvalLifetime)))
  }

  func beginVisitJournalDiscussion(_ review: JournalDiscussion.Approval, now: Date = Date()) throws {
    var archive = try load()
    _ = try validateJournalDiscussion(review, archive: archive, now: now, active: false)
    var discussions = archive.localVisitJournalDiscussions ?? [:]
    let visit = review.binding.visit
    var turns = discussions[visit] ?? []
    let prior = turns.last { $0.binding == review.binding }
    guard prior?.id == review.transport.priorTurnID, !turns.contains(where: { $0.id == review.id }) else { throw Failure.stale }
    turns.append(.init(id: review.id, conversation: review.transport.threadID, binding: review.binding,
      question: review.transport.question, answer: nil))
    discussions[visit] = Array(turns.suffix(JournalDiscussion.maximumExchanges))
    archive.localVisitJournalDiscussions = discussions
    try persistVisitJournalDiscussion(archive)
  }

  func validateActiveVisitJournalDiscussion(_ review: JournalDiscussion.Approval, now: Date = Date()) throws {
    _ = try validateJournalDiscussion(review, archive: load(), now: now, active: true)
  }

  func finishVisitJournalDiscussion(_ review: JournalDiscussion.Approval, answer: String, now: Date = Date()) throws {
    let answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !answer.isEmpty, answer.utf8.count <= 4_096 else { throw Failure.invalid }
    var archive = try load()
    _ = try validateJournalDiscussion(review, archive: archive, now: now, active: true)
    guard var turns = archive.localVisitJournalDiscussions?[review.binding.visit],
          let index = turns.firstIndex(where: { $0.id == review.id }) else { throw Failure.stale }
    turns[index].answer = answer
    archive.localVisitJournalDiscussions?[review.binding.visit] = turns
    try persistVisitJournalDiscussion(archive)
  }

  func visitJournalDiscussionRead(_ review: JournalDiscussion.Approval, cursor: inout JournalDiscussion.Cursor,
      arguments: AgentMcpJSONObject, now: Date = Date()) throws -> AgentMcpJSONObject {
    let archive = try load()
    let scope = try validateJournalDiscussion(review, archive: archive, now: now, active: true)
    guard let ledger = archive.localVisitJournals else { throw Failure.stale }
    let output = try cursor.read(arguments, revision: review.binding.revision, page: { before in
      try ledger.page(scope, before: before, expires: review.expires)
    }, field: { revision, name in
      let before = revision < review.binding.journalRevision ? revision + 1 : nil
      let page = try ledger.page(scope, before: before, expires: review.expires)
      guard let row = page.rows.first, row.entry.revision == revision else { throw Failure.stale }
      return JournalDiscussion.text(row.input, field: name)
    })
    _ = try validateJournalDiscussion(review, archive: load(), now: now, active: true)
    return output
  }

  private func journalBinding(_ archive: Archive, scope: VisitDocuments.Scope, destination: String)
      throws -> (VisitJournal.Entry, JournalDiscussion.Binding) {
    guard let online = archive.healthOnlinePermission, scope.visit.details.state == .attended,
          let entry = archive.localVisitJournals?.entries[scope.visit.id],
          entry.concern == scope.stamp.concern, entry.visit == scope.visit.id else { throw Failure.permission }
    return (entry, .init(concern: entry.concern, journal: entry.id, visit: entry.visit, revision: scope.stamp.revision,
      journalRevision: entry.revision, visitRevision: scope.visit.revision, localPermission: scope.stamp.permission,
      onlinePermission: online, destination: destination))
  }

  private func validateJournalDiscussion(_ review: JournalDiscussion.Approval, archive: Archive, now: Date,
      active: Bool) throws -> VisitDocuments.Scope {
    let transport = review.transport
    guard transport.owner == owner, transport.isCurrent(at: now), now < review.expires,
          transport.computedDestinationDigest == review.binding.destination else { throw Failure.permission }
    let (_, scope) = try visitDocumentContext(concern: review.binding.concern, metric: transport.metric,
      visit: review.binding.visit, archive: archive, now: now)
    let (_, current) = try journalBinding(archive, scope: scope, destination: transport.destinationDigest)
    guard current == review.binding else { throw Failure.stale }
    if active {
      guard let last = archive.localVisitJournalDiscussions?[current.visit]?.last,
            last.id == review.id, last.conversation == transport.threadID, last.binding == current,
            last.question == transport.question, last.answer == nil else { throw Failure.stale }
    }
    return scope
  }
}
