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
    typealias Feedback = GalaxySSIHealthCareFeedbackTool
    var review = review
    var bytes = initial
    var history = review.history?.recent
    var relatedHistory: [String: Tool.Output] = [:]
    var relatedEntries = review.relatedHistory
    var questionCursor = review.questionCursor
    var request = request
    var historyRemaining = Tool.maximumPages
    var questionRemaining = Questions.maximumContinuations
    var feedbackCursor = review.feedbackCursor
    var feedbackRemaining = Feedback.maximumPages
    var reviewCalls = 0
    var planRecorded = false
    var reviewRecorded = false
    var questionCalls = 0
    var questionsRecorded = false
    var checkpoint = try records.savedCareDiscussionRound(review)
    if let saved = checkpoint {
      guard saved.phase == .received, let response = saved.response,
            review.model?.apiStyle == style else { throw GalaxySSIHealthRecords.Failure.stale }
      request = try saved.request(using: request, approval: review)
      bytes = response
      history = saved.history
      relatedHistory = saved.relatedHistory
      relatedEntries = saved.relatedEntries
      questionCursor = saved.questionCursor
      feedbackCursor = saved.feedbackCursor
      historyRemaining = saved.historyRemaining
      questionRemaining = saved.questionRemaining
      feedbackRemaining = saved.feedbackRemaining
    }
    while true {
      try Task.checkCancellation()
      guard let contact = currentDestination() else { throw CancellationError() }
      try records.validateLocalCareDiscussionTurn(review)
      guard let call = try Tool.call(bytes, style: style, proposesPlan: review.proposesPlan,
        allowsQuestionRead: review.questions != nil, asksQuestions: review.asksQuestions, allowsFeedbackRead: feedbackCursor != nil,
        allowsReview: review.requiresStructuredReview,
        allowsAutomaticQuestions: review.canProposeAutomaticQuestions && !reviewRecorded)
      else { return bytes }
      let payload: AgentMcpJSONObject
      let purpose: String
      if call.name == Questions.tool {
        guard review.canProposeAutomaticQuestions, !reviewRecorded, questionCalls < 2 else {
          throw GalaxySSIHealthRecords.Failure.permission
        }
        questionCalls += 1
        do {
          let result = try records.retainAutomaticCareQuestions(review, arguments: call.arguments)
          review = result.approval
          questionCursor = review.questionCursor
          payload = result.receipt
          questionsRecorded = true
        } catch GalaxySSIHealthRecords.Failure.invalid {
          payload = ["stored": .bool(false), "error": .string("invalid_health_questions"),
            "message": .string("Supply at most eight necessary questions with exact key, question and purpose fields. Do not supply answers. Correct within this turn.")]
        }
        purpose = "Retained scoped Health clarification questions without user answers"
      } else if call.name == GalaxySSIHealthCareModelReview.function {
        guard reviewCalls < 3 else { throw GalaxySSIHealthRecords.Failure.permission }
        reviewCalls += 1
        do {
          payload = try records.recordLocalCareModelReview(review, arguments: call.arguments).receipt
          reviewRecorded = true
        } catch let failure as GalaxySSIHealthRecords.Failure {
          guard let feedback = GalaxySSIHealthCareModelReview.failure(failure) else { throw failure }
          payload = feedback
        }
        purpose = "Scoped Health model assessment recording result"
      } else if call.name == GalaxySSIHealthCarePlan.tool {
        guard review.requiresStructuredReview, !reviewRecorded, reviewCalls < 3 else { throw GalaxySSIHealthRecords.Failure.permission }
        reviewCalls += 1
        try records.saveLocalCarePlan(review, arguments: call.arguments)
        payload = ["plan_id": .string(review.id.uuidString), "stored": .bool(true), "adopted": .bool(false),
          "scheduled": .bool(false), "clinical_verification": .bool(false)]
        planRecorded = true
        purpose = "Stored unadopted Health plan draft"
      } else if call.name == Feedback.function {
        guard feedbackRemaining > 0, let cursor = feedbackCursor,
              cursor.arguments == call.arguments else { throw GalaxySSIHealthRecords.Failure.permission }
        feedbackRemaining -= 1
        let output = try records.readLocalCareDiscussionFeedback(review, cursor: cursor, remaining: feedbackRemaining)
        feedbackCursor = output.cursor
        payload = output.payload
        purpose = "Approved Health action feedback history"
      } else if call.name == Questions.readTool {
        guard questionRemaining > 0, let cursor = questionCursor,
              cursor.arguments(turn: review.id) == call.arguments else { throw GalaxySSIHealthRecords.Failure.permission }
        questionRemaining -= 1
        let older = try records.readLocalCareDiscussionQuestions(review, after: cursor.after)
        questionCursor = .init(older, remaining: questionRemaining)
        payload = Questions.Cursor.payload(older, cursor: questionCursor, turn: review.id)
        purpose = "Approved Health clarification continuation"
      } else {
        guard historyRemaining > 0 else { throw GalaxySSIHealthRecords.Failure.permission }
        historyRemaining -= 1
        if let prior = history, prior.authorizes(call.arguments, turn: review.id), let cursor = prior.cursor {
          let older = try records.readLocalCareDiscussionHistory(review, after: cursor)
          let output = try Tool.output(older, metric: review.metric, turn: review.id, remaining: historyRemaining)
          history = output
          payload = output.payload
        } else if let (key, _) = relatedEntries.first(where: { $0.value.entryArguments(turn: review.id) == call.arguments }),
                  let metric = GalaxySSIHealthMetric(rawValue: key) {
          let first = try records.readRelatedLocalCareHistory(review, metric: metric)
          let output = try Tool.output(first, metric: metric, turn: review.id, remaining: historyRemaining)
          relatedEntries.removeValue(forKey: key)
          relatedHistory[key] = output
          payload = output.payload
        } else if let (key, prior) = relatedHistory.first(where: { $0.value.authorizes(call.arguments, turn: review.id) }),
                  let metric = GalaxySSIHealthMetric(rawValue: key), let cursor = prior.cursor {
          let older = try records.readRelatedLocalCareHistory(review, metric: metric, after: cursor)
          let output = try Tool.output(older, metric: metric, turn: review.id, remaining: historyRemaining)
          relatedHistory[key] = output
          payload = output.payload
        } else { throw GalaxySSIHealthRecords.Failure.permission }
        purpose = "Approved health measurement history continuation"
      }
      request = try Tool.continuing(request, with: call, payload: payload, style: style,
        proposesPlan: review.proposesPlan && !planRecorded && !reviewRecorded,
        historyAvailable: historyRemaining > 0 && (history?.cursor != nil || !relatedEntries.isEmpty || relatedHistory.values.contains { $0.cursor != nil }),
        allowsMaintenance: review.history != nil,
        questionsAvailable: questionCursor != nil, asksQuestions: review.asksQuestions,
        feedbackAvailable: feedbackCursor != nil, reviewAvailable: review.requiresStructuredReview, reviewRecorded: reviewRecorded,
        automaticQuestionsAvailable: review.canProposeAutomaticQuestions && !questionsRecorded && !reviewRecorded)
      if let saved = checkpoint {
        guard let body = request.httpBody else { throw GalaxySSIHealthRecords.Failure.invalid }
        var next = saved
        next.index += 1
        next.phase = .prepared
        next.requestBody = body
        next.response = nil
        next.history = history
        next.relatedHistory = relatedHistory
        next.relatedEntries = relatedEntries
        next.questionCursor = questionCursor
        next.feedbackCursor = feedbackCursor
        next.historyRemaining = historyRemaining
        next.questionRemaining = questionRemaining
        next.feedbackRemaining = feedbackRemaining
        try records.prepareNextCareDiscussionRound(review, expected: saved, next: next)
        checkpoint = next
      }
      let ticket = AgentDataDisclosureLedger.beginCloudRequest(store: ledger, destination: .init(contact: contact),
        text: "", purpose: purpose,
        textSummary: .init(characters: request.httpBody?.count ?? 0, kinds: [.messageText, .systemInstructions, .toolOutput]))
      guard ticket.allowed else { throw GalaxySSIHealthRecords.Failure.permission }
      var received = false
      do {
        try Task.checkCancellation()
        guard currentDestination() == contact else { throw CancellationError() }
        try records.validateLocalCareDiscussionTurn(review)
        if let saved = checkpoint { try records.dispatchCareDiscussionRound(review, expected: saved, request: request) }
        bytes = try await send(request)
        received = true
        if let saved = checkpoint {
          try records.retainCareDiscussionRound(review, index: saved.index, request: request, response: bytes)
          checkpoint = try records.savedCareDiscussionRound(review)
        }
        AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: .sent)
      } catch {
        AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: received ? .sent : .failed,
          failureReason: received ? "" : "health_scoped_read_not_completed")
        throw error
      }
    }
  }

  static func resume(_ review: GalaxySSIHealthCareDiscussion.Approval, records: GalaxySSIHealthRecords,
      request template: URLRequest, style: GalaxySSICloudAPIStyle, ledger: AgentDataDisclosureStore,
      currentDestination: () -> GalaxySSIContact?, send: (URLRequest) async throws -> Data = {
        try await GalaxySSIHealthSummaryTransport.responseBytes($0, limit: 65_536)
      }) async throws -> Data {
    guard let saved = try records.savedCareDiscussionRound(review), saved.canResume,
          review.model?.apiStyle == style else { throw GalaxySSIHealthRecords.Failure.stale }
    try Task.checkCancellation()
    guard let contact = currentDestination() else { throw CancellationError() }
    let request = try saved.request(using: template, approval: review)
    let bytes: Data
    if saved.phase == .prepared {
      let ticket = AgentDataDisclosureLedger.beginCloudRequest(store: ledger, destination: .init(contact: contact),
        text: "", purpose: "Approved Health scoped continuation recovery",
        textSummary: .init(characters: saved.requestBody.count, kinds: [.messageText, .systemInstructions, .toolOutput]))
      guard ticket.allowed else { throw GalaxySSIHealthRecords.Failure.permission }
      var received = false
      do {
        try Task.checkCancellation()
        guard currentDestination() == contact else { throw CancellationError() }
        if saved.index == 0 { try records.dispatchLocalCareDiscussionTurn(review) }
        else { try records.dispatchCareDiscussionRound(review, expected: saved, request: request) }
        bytes = try await send(request)
        received = true
        AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: .sent)
        try records.retainCareDiscussionRound(review, index: saved.index, request: request, response: bytes)
      } catch {
        AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: received ? .sent : .failed,
          failureReason: received ? "" : "health_scoped_round_recovery_not_completed")
        throw error
      }
    } else {
      guard let retained = saved.response else { throw GalaxySSIHealthRecords.Failure.stale }
      bytes = retained
    }
    if review.allowsAnswerDraft { return bytes }
    return try await finish(review, records: records, initial: bytes, request: request, style: style,
      ledger: ledger, currentDestination: currentDestination, send: send)
  }
}
