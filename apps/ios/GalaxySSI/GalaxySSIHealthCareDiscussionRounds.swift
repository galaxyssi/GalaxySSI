import Foundation

enum GalaxySSIHealthCareDiscussionRounds {
  struct State: Codable, Equatable {
    enum Phase: String, Codable { case prepared, dispatched, received }
    var index = 0
    var phase = Phase.prepared
    var requestBody: Data
    var response: Data?
    var history: GalaxySSIHealthCareHistoryTool.Output?
    var relatedHistory: [String: GalaxySSIHealthCareHistoryTool.Output] = [:]
    var relatedEntries: [String: GalaxySSIHealthCareHistoryTool.Approval]
    var questionCursor: GalaxySSIHealthCareQuestions.Cursor?
    var feedbackCursor: GalaxySSIHealthCareFeedbackTool.Cursor?
    var historyRemaining = GalaxySSIHealthCareHistoryTool.maximumPages
    var questionRemaining = GalaxySSIHealthCareQuestions.maximumContinuations
    var feedbackRemaining = GalaxySSIHealthCareFeedbackTool.maximumPages

    var canResume: Bool { phase == .received || phase == .prepared }

    init(approval: GalaxySSIHealthCareDiscussion.Approval, request: URLRequest) throws {
      guard approval.research == nil, let body = request.httpBody else { throw GalaxySSIHealthRecords.Failure.invalid }
      requestBody = body
      history = approval.history?.recent
      relatedEntries = approval.relatedHistory
      questionCursor = approval.questionCursor
      feedbackCursor = approval.feedbackCursor
      try validate()
    }

    func request(using template: URLRequest, approval: GalaxySSIHealthCareDiscussion.Approval) throws -> URLRequest {
      guard template.httpMethod == "POST", template.url == approval.endpoint else { throw GalaxySSIHealthRecords.Failure.permission }
      try validate()
      var request = template
      request.httpBody = requestBody
      return request
    }

    func validate() throws {
      guard (0...12).contains(index), !requestBody.isEmpty,
            requestBody.count <= GalaxySSIHealthCareHistoryTool.requestBudget,
            (0...GalaxySSIHealthCareHistoryTool.maximumPages).contains(historyRemaining),
            (0...GalaxySSIHealthCareQuestions.maximumContinuations).contains(questionRemaining),
            (0...GalaxySSIHealthCareFeedbackTool.maximumPages).contains(feedbackRemaining),
            response.map({ !$0.isEmpty && $0.count <= 65_536 }) ?? true,
            (phase == .received) == (response != nil),
            try JSONEncoder().encode(self).count <= 750_000 else { throw GalaxySSIHealthRecords.Failure.invalid }
    }
  }
}

extension GalaxySSIHealthRecords {
  func prepareCareDiscussionRounds(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      request: URLRequest, now: Date = Date()) throws {
    try validateLocalCareDiscussionTurn(approval, now: now)
    let state = try GalaxySSIHealthCareDiscussionRounds.State(approval: approval, request: request)
    _ = try state.request(using: request, approval: approval)
    try updateCareDiscussionExecution(approval) { execution in
      guard execution.state == .prepared, execution.rounds == nil else { throw Failure.stale }
      execution.rounds = state
    }
  }

  func savedCareDiscussionRound(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      now: Date = Date()) throws -> GalaxySSIHealthCareDiscussionRounds.State? {
    let archive = try load()
    guard let execution = archive.localCareDiscussions?[approval.concernID.uuidString]?.turns.last?.execution,
          let state = execution.rounds else { return nil }
    try validateLocalCareDiscussionTurn(approval, now: now)
    guard execution.approval == approval else { throw Failure.stale }
    try state.validate()
    return state
  }

  func prepareNextCareDiscussionRound(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      expected: GalaxySSIHealthCareDiscussionRounds.State, next: GalaxySSIHealthCareDiscussionRounds.State,
      now: Date = Date()) throws {
    try validateLocalCareDiscussionTurn(approval, now: now)
    try next.validate()
    let costs = [expected.historyRemaining - next.historyRemaining,
      expected.questionRemaining - next.questionRemaining, expected.feedbackRemaining - next.feedbackRemaining]
    guard expected.phase == .received, next.phase == .prepared, next.index == expected.index + 1,
          costs.allSatisfy({ (0...1).contains($0) }), costs.reduce(0, +) == 1 else { throw Failure.stale }
    try updateCareDiscussionExecution(approval) { execution in
      guard execution.state == .dispatched, execution.rounds == expected else { throw Failure.stale }
      execution.rounds = next
    }
  }

  func dispatchCareDiscussionRound(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      expected: GalaxySSIHealthCareDiscussionRounds.State, request: URLRequest, now: Date = Date()) throws {
    try validateLocalCareDiscussionTurn(approval, now: now)
    guard expected.phase == .prepared, expected.index > 0,
          try expected.request(using: request, approval: approval).httpBody == request.httpBody else { throw Failure.stale }
    try updateCareDiscussionExecution(approval) { execution in
      guard execution.state == .dispatched, execution.rounds == expected else { throw Failure.stale }
      execution.rounds?.phase = .dispatched
    }
  }

  func retainCareDiscussionRound(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      index: Int, request: URLRequest, response: Data, now: Date = Date()) throws {
    try validateLocalCareDiscussionTurn(approval, now: now)
    guard !response.isEmpty, response.count <= 65_536 else { throw Failure.invalid }
    try updateCareDiscussionExecution(approval) { execution in
      guard execution.state == .dispatched, var state = execution.rounds, state.index == index,
            try state.request(using: request, approval: approval).httpBody == request.httpBody else { throw Failure.stale }
      if state.phase == .received {
        guard state.response == response else { throw Failure.stale }
        return
      }
      guard state.phase == .dispatched else { throw Failure.stale }
      state.response = response
      state.phase = .received
      try state.validate()
      execution.rounds = state
    }
  }
}
