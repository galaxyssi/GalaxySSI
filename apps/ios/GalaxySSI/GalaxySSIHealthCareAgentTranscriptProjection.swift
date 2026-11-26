import Foundation

enum GalaxySSIHealthCareAgentTranscriptProjection {
  enum Reply: Equatable {
    case answer(String), plan, questions, answerDraft, interruptedControl, interruptedRequest, waiting, noSavedReply
  }

  struct Clock: Equatable {
    let startedAt: Date
    let stoppedAt: Date?
    let deadline: Date

    func running(at now: Date) -> Bool { stoppedAt == nil && now < deadline }
    func seconds(at now: Date) -> Int32 {
      Int32(min(86_400, max(0, (stoppedAt ?? min(now, deadline)).timeIntervalSince(startedAt))))
    }
  }

  struct Row: Identifiable, Equatable {
    let id: UUID
    let question: String
    let reply: Reply
    let clock: Clock?
  }

  static func rows(_ thread: GalaxySSIHealthCareDiscussion.Thread, owner: String, conversation: String,
      now: Date = Date(), workspaces: [String: AgentWorkspace],
      isExecuting: (GalaxySSIHealthCareDiscussion.Approval) -> Bool) -> [Row] {
    guard !owner.isBlank, !conversation.isBlank, thread.archivedAt == nil,
          thread.agentConversationID == conversation else { return [] }
    return thread.turns.suffix(GalaxySSIHealthCareDiscussion.maximumTurns).map { turn in
      var clock: Clock?
      var live = false
      var cancelled = false
      if let execution = turn.execution {
        let approval = execution.approval
        guard execution.agentConversationID == conversation, approval.owner == owner,
              approval.threadID == thread.id, approval.concernID == thread.concernID,
              approval.id == turn.id, approval.question == turn.question,
              approval.destinationDigest == turn.destination else {
          return Row(id: turn.id, question: turn.question, reply: .interruptedRequest, clock: nil)
        }
        let identity = "private:" + AgentModelLoopRecoveryIdentity.sha256(["owner": owner,
          "thread": thread.id.uuidString, "turn": turn.id.uuidString])
        let saved = workspaces[identity].flatMap { value -> AgentWorkspace? in
          value.workspaceId == identity && value.taskId == identity && value.sessionId == thread.id.uuidString &&
            value.conversationId == conversation ? value : nil
        }
        cancelled = saved?.cancellationRequested == true || saved?.status == .cancelled
        live = !cancelled && execution.state != .interrupted && execution.state != .applied &&
          approval.isCurrent(at: now) && isExecuting(approval) && saved.map {
            [.queued, .running, .waitingResponse, .waitingConfirmation].contains($0.status)
          } == true
        let started = execution.startedAt
        if started.timeIntervalSinceReferenceDate.isFinite {
          let deadline = approval.reviewedAt.addingTimeInterval(GalaxySSIHealthCareDiscussion.approvalLifetime)
          let retainedStop = execution.stoppedAt ?? execution.receivedAt
          let stopped: Date?
          if let retainedStop, retainedStop.timeIntervalSinceReferenceDate.isFinite {
            stopped = max(started, retainedStop)
          } else if live { stopped = nil }
          else if let saved {
            stopped = max(started, min(now, Date(timeIntervalSince1970: Double(saved.updatedAtMillis) / 1_000)))
          } else { stopped = started }
          clock = Clock(startedAt: started, stoppedAt: stopped, deadline: max(started, deadline))
        }
      }
      let reply: Reply
      if turn.hasInterruptedReply { reply = .interruptedControl }
      else if turn.execution?.state == .interrupted { reply = .interruptedRequest }
      else if cancelled && turn.execution?.state != .applied { reply = .interruptedRequest }
      else if let answer = turn.retainedAnswer { reply = .answer(answer) }
      else if turn.proposalID != nil { reply = .plan }
      else if turn.questionsRetained == true { reply = .questions }
      else if turn.answerDraftStaged == true { reply = .answerDraft }
      else if live { reply = .waiting }
      else { reply = turn.execution == nil ? .noSavedReply : .interruptedRequest }
      return Row(id: turn.id, question: turn.question, reply: reply, clock: clock)
    }
  }
}
