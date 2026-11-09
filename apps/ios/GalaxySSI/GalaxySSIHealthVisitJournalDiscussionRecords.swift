import CryptoKit
import Foundation

@MainActor
extension GalaxySSIHealthRecords {
  typealias JournalDiscussion = GalaxySSIHealthVisitJournalRead

  func prepareVisitJournalDiscussion(_ expected: VisitJournal.Page, question: String, contact: GalaxySSIContact,
      key: String, now: Date = Date()) throws -> JournalDiscussion.Approval {
    guard !contact.deleted, contact.deliveryMode == .cloudAPI, let model = contact.selectedCloudModel,
          let endpoint = GalaxySSIHealthCareDiscussion.endpoint(for: model),
          CloudModelCredentialPolicy.isStoredCredential(key) else { throw Failure.permission }
    let credential = SHA256.hash(data: Data(key.utf8))
    return try prepareVisitJournalDiscussion(expected, question: question,
      route: .cloud(contactID: contact.id, model: model, endpoint: endpoint, credential: credential), now: now)
  }

  func prepareVisitJournalDiscussion(_ expected: VisitJournal.Page, question: String, localProfile: LocalModelRuntimeProfile,
      now: Date = Date()) throws -> JournalDiscussion.Approval {
    guard LocalModelRuntimeCatalog.profiles().contains(localProfile),
          LocalModelInferenceRuntime.shared.ready(profile: localProfile) else { throw Failure.permission }
    return try prepareVisitJournalDiscussion(expected, question: question,
      route: .local(localProfile, contextTokens: LocalModelRuntimeSettings.contextTokens()), now: now)
  }

  func prepareVisitJournalDiscussion(_ expected: VisitJournal.Page, question: String, route: JournalDiscussion.Route,
      now: Date) throws -> JournalDiscussion.Approval {
    let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard now < expected.expires, !question.isEmpty, question.utf8.count <= 2_048 else { throw Failure.permission }
    let archive = try load()
    let (_, scope) = try visitDocumentContext(expected.scope, archive: archive, now: now)
    let (entry, binding) = try journalBinding(archive, scope: scope, route: route)
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
    return .init(id: UUID(), owner: owner, conversation: previous.last?.conversation ?? UUID(), prior: previous.last?.id,
      metric: scope.stamp.metric, route: route, question: question, payload: text, reviewedAt: now,
      binding: binding, summary: summary, previous: latest,
      expires: min(expected.expires, now.addingTimeInterval(GalaxySSIHealthCareDiscussion.approvalLifetime)))
  }

  func beginVisitJournalDiscussion(_ review: JournalDiscussion.Approval, now: Date = Date()) throws {
    var archive = try load()
    _ = try validateJournalDiscussion(review, archive: archive, now: now, active: false)
    var discussions = archive.localVisitJournalDiscussions ?? [:]
    let visit = review.binding.visit
    var turns = discussions[visit] ?? []
    let prior = turns.last { $0.binding == review.binding }
    guard prior?.id == review.prior, !turns.contains(where: { $0.id == review.id }) else { throw Failure.stale }
    turns.append(.init(id: review.id, conversation: review.conversation, binding: review.binding,
      question: review.question, answer: nil))
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

  private func journalBinding(_ archive: Archive, scope: VisitDocuments.Scope, route: JournalDiscussion.Route)
      throws -> (VisitJournal.Entry, JournalDiscussion.Binding) {
    let online = route.requiresOnline ? archive.healthOnlinePermission : nil
    guard (!route.requiresOnline || online != nil), scope.visit.details.state == .attended,
          let entry = archive.localVisitJournals?.entries[scope.visit.id],
          entry.concern == scope.stamp.concern, entry.visit == scope.visit.id else { throw Failure.permission }
    return (entry, .init(concern: entry.concern, journal: entry.id, visit: entry.visit, revision: scope.stamp.revision,
      journalRevision: entry.revision, visitRevision: scope.visit.revision, localPermission: scope.stamp.permission,
      onlinePermission: online, destination: route.digest))
  }

  private func validateJournalDiscussion(_ review: JournalDiscussion.Approval, archive: Archive, now: Date,
      active: Bool) throws -> VisitDocuments.Scope {
    guard review.owner == owner, now >= review.reviewedAt, now < review.expires,
          review.route.digest == review.binding.destination else { throw Failure.permission }
    let (_, scope) = try visitDocumentContext(concern: review.binding.concern, metric: review.metric,
      visit: review.binding.visit, archive: archive, now: now)
    let (_, current) = try journalBinding(archive, scope: scope, route: review.route)
    guard current == review.binding else { throw Failure.stale }
    if active {
      guard let last = archive.localVisitJournalDiscussions?[current.visit]?.last,
            last.id == review.id, last.conversation == review.conversation, last.binding == current,
            last.question == review.question, last.answer == nil else { throw Failure.stale }
    }
    return scope
  }
}
