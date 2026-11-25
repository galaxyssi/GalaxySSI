import Foundation

enum GalaxySSIHealthCareDiscussionRecovery {
  struct Execution: Codable, Equatable {
    enum State: String, Codable { case prepared, dispatched, received, applied, interrupted }

    let approval: GalaxySSIHealthCareDiscussion.Approval
    let agentConversationID: String?
    let startedAt: Date
    var state = State.prepared
    var response: Data?
    var receivedAt: Date?

    init(approval: GalaxySSIHealthCareDiscussion.Approval, agentConversationID: String?, startedAt: Date) throws {
      guard approval.research == nil, approval.model != nil, approval.credentialDigest?.count == 32,
            approval.isCurrent(at: startedAt), startedAt.timeIntervalSince1970.isFinite,
            try approval.providerPayload(now: startedAt).utf8.count <= 100_000 else {
        throw GalaxySSIHealthRecords.Failure.invalid
      }
      self.approval = approval
      self.agentConversationID = agentConversationID
      self.startedAt = startedAt
    }
  }
}

extension GalaxySSIHealthRecords {
  func dispatchLocalCareDiscussionTurn(_ approval: GalaxySSIHealthCareDiscussion.Approval, now: Date = Date()) throws {
    try validateLocalCareDiscussionTurn(approval, now: now)
    try updateCareDiscussionExecution(approval) { execution in
      guard execution.state == .prepared else { throw Failure.stale }
      execution.state = .dispatched
    }
  }

  func retainLocalCareDiscussionResponse(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      response: Data, now: Date = Date()) throws {
    guard !response.isEmpty, response.count <= 65_536 else { throw Failure.invalid }
    try validateLocalCareDiscussionTurn(approval, now: now)
    try updateCareDiscussionExecution(approval) { execution in
      if execution.state == .received {
        guard execution.response == response else { throw Failure.stale }
        return
      }
      guard execution.state == .dispatched, now >= execution.startedAt else { throw Failure.stale }
      execution.response = response
      execution.receivedAt = now
      execution.state = .received
    }
  }

  // A local receipt can be applied again after a crash; this path never sends a request.
  func applySavedLocalCareDiscussionReply(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      now: Date = Date()) throws {
    try validateLocalCareDiscussionTurn(approval, now: now)
    let archive = try load()
    guard let thread = archive.localCareDiscussions?[approval.concernID.uuidString],
          let turn = thread.turns.last, turn.id == approval.id,
          let execution = turn.execution, execution.approval == approval,
          thread.agentConversationID == execution.agentConversationID,
          execution.state == .received, let bytes = execution.response,
          !bytes.isEmpty, bytes.count <= 65_536, let received = execution.receivedAt,
          execution.startedAt <= received, received <= now, approval.isCurrent(at: received),
          let style = approval.model?.apiStyle else { throw Failure.stale }
    if approval.allowsAnswerDraft,
       let draft = try GalaxySSIHealthCareAnswerDraft.argumentsIfPresent(bytes, style: style) {
      _ = try stageLocalCareAnswerDraft(approval, arguments: draft, now: now)
    } else if approval.asksQuestions {
      let arguments = try GalaxySSIHealthCarePlan.arguments(bytes, style: style,
        toolName: GalaxySSIHealthCareQuestions.tool)
      try saveLocalCareQuestionProposals(approval, arguments: arguments, now: now)
    } else if approval.proposesPlan {
      try saveLocalCarePlan(approval,
        arguments: GalaxySSIHealthCarePlan.arguments(bytes, style: style), now: now)
    } else {
      try finishLocalCareDiscussionTurn(approval,
        answer: GalaxySSIHealthFollowUpTransport.output(bytes, style: style), now: now)
    }
  }

  // Cancellation is local and remains possible after consent expires or is revoked.
  func interruptLocalCareDiscussionExecution(_ approval: GalaxySSIHealthCareDiscussion.Approval) throws {
    try updateCareDiscussionExecution(approval) { execution in
      guard execution.state != .applied else { return }
      execution.state = .interrupted
    }
  }

  private func updateCareDiscussionExecution(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      _ change: (inout GalaxySSIHealthCareDiscussionRecovery.Execution) throws -> Void) throws {
    var archive = try load()
    let key = approval.concernID.uuidString
    guard approval.owner == owner, var thread = archive.localCareDiscussions?[key],
          thread.id == approval.threadID, let index = thread.turns.indices.last,
          thread.turns[index].id == approval.id, thread.turns[index].question == approval.question,
          thread.turns[index].destination == approval.destinationDigest,
          var execution = thread.turns[index].execution, execution.approval == approval,
          thread.agentConversationID == execution.agentConversationID else { throw Failure.stale }
    let original = execution
    try change(&execution)
    guard execution != original else { return }
    thread.turns[index].execution = execution
    archive.localCareDiscussions?[key] = thread
    try persistCareDiscussionRecovery(archive)
  }
}
