import Foundation

@MainActor
enum GalaxySSIHealthCareModelToolLoop {
  static func finish(_ approval: GalaxySSIHealthCareDiscussion.Approval, records: GalaxySSIHealthRecords,
      request: URLRequest, style: GalaxySSICloudAPIStyle, ledger: AgentDataDisclosureStore,
      currentDestination: @escaping () -> GalaxySSIContact?,
      send: @escaping (URLRequest) async throws -> Data = {
        try await GalaxySSIHealthSummaryTransport.responseBytes($0, limit: 65_536)
      }) async throws -> Data {
    try records.validateLocalCareDiscussionTurn(approval)
    guard let saved = try records.savedCareDiscussionRound(approval), saved.canResume else {
      throw GalaxySSIHealthRecords.Failure.stale
    }
    let session = try GalaxySSIHealthCareNativeToolSession(approval: approval, records: records,
      request: request, style: style, currentDestination: currentDestination)
    let registry = try session.registry()
    let cancellation = session.cancellation
    let adapter = Model(session: session, ledger: ledger, send: send)
    let remaining = max(1, Int64((approval.reviewedAt.addingTimeInterval(GalaxySSIHealthCareDiscussion.approvalLifetime)
      .timeIntervalSinceNow * 1_000).rounded(.down)))
    let loopRequest = AgentModelToolLoopRequest(sessionId: approval.threadID.uuidString,
      conversationId: session.conversationID, turnId: approval.id.uuidString,
      taskId: session.workspaceID, workspaceId: session.workspaceID, loopId: approval.id.uuidString,
      messages: [.user(approval.question)],
      budget: .init(maxRounds: 16 - saved.index,
        maxToolCalls: max(1, saved.historyRemaining + saved.questionRemaining + saved.feedbackRemaining + 1),
        maxDepth: 1, maxTokens: 4_000_000, maxDurationMillis: remaining, maxRetriesPerCall: 0),
      callerId: GalaxySSIHealthCareNativeToolSession.caller,
      grantedPermissions: [],
      grantedConsents: [approval.carePermission.uuidString, approval.onlinePermission.uuidString],
      recoveryInputIdentity: approval.destinationDigest,
      observationHistoryEnabled: false,
      cancellationToken: .init { Task.isCancelled || cancellation.token.isCancellationRequested },
      eventSink: .none, collaborationOwner: nil)
    // Recovery is the encrypted, bounded wire-round checkpoint; never use a global model journal.
    let outcome = await AgentModelToolLoop(modelAdapter: adapter, toolRegistry: registry).run(loopRequest)
    guard outcome.status == .completed else {
      if outcome.status == .cancelled { throw CancellationError() }
      throw GalaxySSIHealthRecords.Failure.invalid
    }
    let execution = try records.careDiscussionExecution(approval)
    guard let raw = execution.response ?? execution.rounds?.response else { throw GalaxySSIHealthRecords.Failure.stale }
    return raw
  }

  private struct Model: AgentModelAdapter {
    let session: GalaxySSIHealthCareNativeToolSession
    let ledger: AgentDataDisclosureStore
    let send: (URLRequest) async throws -> Data

    @MainActor
    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
      do { return try await completeScoped(request) }
      catch is CancellationError { session.cancellation.cancel(); throw CancellationError() }
    }

    @MainActor
    private func completeScoped(_ request: AgentModelRequest) async throws -> AgentModelResponse {
      try Task.checkCancellation()
      guard session.currentDestination() != nil else { throw CancellationError() }
      guard request.sessionId == session.approval.threadID.uuidString,
            request.conversationId == session.conversationID, request.turnId == session.approval.id.uuidString,
            request.taskId == session.workspaceID, request.workspaceId == session.workspaceID,
            request.callerId == GalaxySSIHealthCareNativeToolSession.caller,
            session.pending == nil else { throw GalaxySSIHealthRecords.Failure.permission }
      let execution = try session.records.careDiscussionExecution(session.approval)
      if execution.state == .applied {
        // Local plan/questions/draft commit is terminal. No extra provider request is authorized.
        return AgentModelResponse(assistantText: "Approved result retained locally for user review.")
      }
      try session.records.validateLocalCareDiscussionTurn(session.approval)
      guard let state = try session.records.savedCareDiscussionRound(session.approval), state.canResume else {
        throw GalaxySSIHealthRecords.Failure.stale
      }
      let bytes: Data
      if state.phase == .prepared {
        guard let contact = session.currentDestination() else { throw CancellationError() }
        let wire = try state.request(using: session.template, approval: session.approval)
        let ticket = AgentDataDisclosureLedger.beginCloudRequest(store: ledger, destination: .init(contact: contact),
          text: "", purpose: state.index == 0 ? "Approved Health discussion" : "Approved Health native-tool continuation",
          textSummary: .init(characters: state.requestBody.count, kinds: [.messageText, .systemInstructions, .toolOutput]))
        guard ticket.allowed else { throw GalaxySSIHealthRecords.Failure.permission }
        var received = false
        do {
          try Task.checkCancellation()
          guard session.currentDestination() == contact else { throw CancellationError() }
          if state.index == 0 { try session.records.dispatchLocalCareDiscussionTurn(session.approval) }
          else { try session.records.dispatchCareDiscussionRound(session.approval, expected: state, request: wire) }
          bytes = try await send(wire)
          received = true
          try session.records.retainCareDiscussionRound(session.approval, index: state.index, request: wire, response: bytes)
          AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: .sent)
        } catch {
          AgentDataDisclosureLedger.update(store: ledger, ticket: ticket, status: received ? .sent : .failed,
            failureReason: received ? "" : "health_native_tool_round_not_completed")
          throw error
        }
      } else {
        guard let retained = state.response else { throw GalaxySSIHealthRecords.Failure.stale }
        bytes = retained
      }
      if let text = try? GalaxySSIHealthFollowUpTransport.output(bytes, style: session.style) {
        guard !text.isBlank, text.utf8.count <= 6_144,
              !CloudSupervisedResearch.hasUnexecutedMarkup(text) else { throw GalaxySSIHealthRecords.Failure.invalid }
        return AgentModelResponse(assistantText: text)
      }
      let provider: AgentModelToolProvider
      switch session.style {
      case .openAICompatible: provider = .openAICompatible
      case .anthropic: provider = .anthropic
      case .gemini: provider = .gemini
      }
      let codec = AgentModelToolProtocolAdapters.adapter(for: provider,
        limits: .init(maxToolCalls: 1, maxToolResultCharacters: 32_768, maxResponseCharacters: 65_536))
      let response = try codec.decodeResponse(String(decoding: bytes, as: UTF8.self), catalog: session.catalog)
      guard response.toolCalls.count == 1, let call = response.toolCalls.first,
            session.catalog.contains(where: { $0.id == call.toolId }) else { throw GalaxySSIHealthRecords.Failure.permission }
      let arguments: AgentMcpJSONObject
      if GalaxySSIHealthCareNativeToolSession.terminalTools.contains(call.toolId) {
        arguments = try GalaxySSIHealthCarePlan.arguments(bytes, style: session.style, toolName: call.toolId)
      } else {
        let checked = try GalaxySSIHealthCareHistoryTool.call(bytes, style: session.style,
          proposesPlan: session.approval.proposesPlan, allowsQuestionRead: session.approval.questions != nil,
          asksQuestions: session.approval.asksQuestions, allowsFeedbackRead: session.approval.feedbackCursor != nil)
        guard let checked, checked.name == call.toolId else { throw GalaxySSIHealthRecords.Failure.permission }
        arguments = checked.arguments
      }
      guard arguments == call.arguments else { throw GalaxySSIHealthRecords.Failure.permission }
      session.pending = call
      return response
    }
  }
}
