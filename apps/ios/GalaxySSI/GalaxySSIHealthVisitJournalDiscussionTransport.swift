import CryptoKit
import Foundation

@MainActor
enum GalaxySSIHealthVisitJournalDiscussionTransport {
  typealias Review = GalaxySSIHealthVisitJournalRead.Approval

  static func run(_ review: Review, records: GalaxySSIHealthRecords, ledger: AgentDataDisclosureStore,
      currentRoute: () -> (GalaxySSIContact, String)?,
      send: (URLRequest) async throws -> Data = {
        try await GalaxySSIHealthSummaryTransport.responseBytes($0, limit: 65_536)
      }) async throws -> String {
    let invalid = GalaxySSIHealthRecords.Failure.permission
    func approvedRoute() -> (GalaxySSIContact, String)? {
      guard let (contact, key) = currentRoute(), contact.id == review.transport.destinationID,
            !contact.deleted, contact.deliveryMode == .cloudAPI,
            contact.selectedCloudModel == review.transport.model,
            SHA256.hash(data: Data(key.utf8)) == review.transport.credentialDigest,
            !ledger.blockedDestinationIds().contains(contact.id) else { return nil }
      return (contact, key)
    }
    guard let style = review.transport.model?.apiStyle, let (_, key) = approvedRoute() else { throw invalid }
    var request = try GalaxySSIHealthCareDiscussion.request(review.transport, key: key, journalRead: true)
    try records.beginVisitJournalDiscussion(review)
    var cursor = GalaxySSIHealthVisitJournalRead.Cursor()
    while true {
      try Task.checkCancellation()
      guard let (contact, _) = approvedRoute() else { throw invalid }
      try records.validateActiveVisitJournalDiscussion(review)
      let ticket = AgentDataDisclosureLedger.beginCloudRequest(store: ledger, destination: .init(contact: contact),
        text: "", purpose: "Explicit post-visit journal discussion",
        textSummary: .init(characters: request.httpBody?.count ?? 0, kinds: [.messageText, .systemInstructions, .toolOutput]))
      guard ticket.allowed else { throw invalid }
      let bytes: Data
      do {
        try Task.checkCancellation()
        guard approvedRoute()?.0 == contact else { throw invalid }
        try records.validateActiveVisitJournalDiscussion(review)
        bytes = try await send(request)
        AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: .sent)
      } catch {
        AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: .failed,
          failureReason: "health_visit_journal_discussion_not_completed")
        throw error
      }
      try Task.checkCancellation()
      guard approvedRoute()?.0 == contact else { throw invalid }
      try records.validateActiveVisitJournalDiscussion(review)
      typealias Tools = GalaxySSIHealthCareHistoryTool
      guard let call = try Tools.call(bytes, style: style, proposesPlan: false, allowsJournalRead: cursor.available) else {
        let answer = try GalaxySSIHealthFollowUpTransport.output(bytes, style: style)
        try records.finishVisitJournalDiscussion(review, answer: answer)
        return answer
      }
      guard call.name == GalaxySSIHealthVisitJournalRead.providerName else { throw invalid }
      let output = try records.visitJournalDiscussionRead(review, cursor: &cursor, arguments: call.arguments)
      request = try Tools.continuing(request, with: call, payload: output, style: style, proposesPlan: false,
        historyAvailable: false, journalAvailable: cursor.available)
    }
  }
}
