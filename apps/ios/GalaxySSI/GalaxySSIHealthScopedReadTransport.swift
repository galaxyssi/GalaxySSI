import Foundation

@MainActor
enum GalaxySSIHealthScopedReadTransport {
  static func finish(_ review: GalaxySSIHealthCareDiscussion.Approval, records: GalaxySSIHealthRecords,
      initial: Data, request: URLRequest, style: GalaxySSICloudAPIStyle, ledger: AgentDataDisclosureStore,
      currentDestination: () -> GalaxySSIContact?, send: (URLRequest) async throws -> Data = {
        try await GalaxySSIHealthSummaryTransport.responseBytes($0, limit: 65_536)
      }) async throws -> Data {
    typealias Tool = GalaxySSIHealthCareHistoryTool
    typealias Questions = GalaxySSIHealthCareQuestions
    var bytes = initial
    var history = review.history?.recent
    var questionCursor = review.questionCursor
    var request = request
    var historyRemaining = Tool.maximumPages
    var questionRemaining = Questions.maximumContinuations
    while true {
      try Task.checkCancellation()
      guard let contact = currentDestination() else { throw CancellationError() }
      try records.validateLocalCareDiscussionTurn(review)
      guard let call = try Tool.call(bytes, style: style, proposesPlan: review.proposesPlan,
        allowsQuestionRead: review.questions != nil, asksQuestions: review.asksQuestions)
      else { return bytes }
      let payload: AgentMcpJSONObject
      let purpose: String
      if call.name == Questions.readTool {
        guard questionRemaining > 0, let cursor = questionCursor,
              cursor.arguments(turn: review.id) == call.arguments else { throw GalaxySSIHealthRecords.Failure.permission }
        questionRemaining -= 1
        let older = try records.readLocalCareDiscussionQuestions(review, after: cursor.after)
        questionCursor = .init(older, remaining: questionRemaining)
        payload = Questions.Cursor.payload(older, cursor: questionCursor, turn: review.id)
        purpose = "Approved Health clarification continuation"
      } else {
        guard historyRemaining > 0, let prior = history, prior.authorizes(call.arguments, turn: review.id),
              let cursor = prior.cursor else { throw GalaxySSIHealthRecords.Failure.permission }
        historyRemaining -= 1
        let older = try records.readLocalCareDiscussionHistory(review, after: cursor)
        let output = try Tool.output(older, metric: review.metric, turn: review.id, remaining: historyRemaining)
        history = output
        payload = output.payload
        purpose = "Approved health measurement history continuation"
      }
      request = try Tool.continuing(request, with: call, payload: payload, style: style,
        proposesPlan: review.proposesPlan, historyAvailable: history?.cursor != nil, allowsMaintenance: review.history != nil,
        questionsAvailable: questionCursor != nil, asksQuestions: review.asksQuestions)
      let ticket = AgentDataDisclosureLedger.beginCloudRequest(store: ledger, destination: .init(contact: contact),
        text: "", purpose: purpose,
        textSummary: .init(characters: request.httpBody?.count ?? 0, kinds: [.messageText, .systemInstructions, .toolOutput]))
      guard ticket.allowed else { throw GalaxySSIHealthRecords.Failure.permission }
      do {
        try Task.checkCancellation()
        guard currentDestination() == contact else { throw CancellationError() }
        try records.validateLocalCareDiscussionTurn(review)
        bytes = try await send(request)
        AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: .sent)
      } catch {
        AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: .failed,
          failureReason: "health_scoped_read_not_completed")
        throw error
      }
    }
  }
}
