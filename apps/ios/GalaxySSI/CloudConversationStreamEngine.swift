import Foundation

protocol CloudConversationLegacySending {
  func send(contact: GalaxySSIContact, store: GalaxySSIStore, turns: [ChatMessage]) async throws -> String
  func send(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    turns: [ChatMessage],
    images: [CloudImagePayload]
  ) async throws -> String
}

extension CloudConversationLegacySending {
  func send(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    turns: [ChatMessage],
    images: [CloudImagePayload]
  ) async throws -> String {
    try await send(contact: contact, store: store, turns: turns)
  }
}

extension CloudModelClient: CloudConversationLegacySending {}

protocol CloudConversationStreaming {
  func streamConversation(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    turns: [ChatMessage],
    requestId: String
  ) -> AsyncThrowingStream<ModelStreamEvent, Error>
  func streamConversation(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    turns: [ChatMessage],
    images: [CloudImagePayload],
    requestId: String
  ) -> AsyncThrowingStream<ModelStreamEvent, Error>
  func cancel(requestId: String, reason: ModelStreamCancelReason) async
}

extension CloudConversationStreaming {
  func streamConversation(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    turns: [ChatMessage],
    images: [CloudImagePayload],
    requestId: String
  ) -> AsyncThrowingStream<ModelStreamEvent, Error> {
    streamConversation(contact: contact, store: store, turns: turns, requestId: requestId)
  }

  func cancel(requestId: String, reason: ModelStreamCancelReason) async {}
}

final class CloudConversationStreamEngine: CloudModelStreamClient {
  private static let maxParallelToolCalls = 4

  private struct ToolExecutionOutcome {
    var index: Int
    var call: AssembledToolCall
    var output: String?
    var errorMessage: String?
    var startedAtMillis: Int64
    var finishedAtMillis: Int64
  }

  private let modelClient: CloudModelClient
  private let streamClient: CloudModelStreamClient
  private let legacySender: CloudConversationLegacySending
  private let toolExecutor: CloudConversationToolExecuting
  private let disclosureStore: AgentDataDisclosureStore
  private let elapsedMillis: () -> Int64
  private let lock = NSLock()
  private var activeRoundIds: [String: String] = [:]

  init(
    modelClient: CloudModelClient = CloudModelClient(),
    streamClient: CloudModelStreamClient = URLSessionCloudModelStreamClient(),
    legacySender: CloudConversationLegacySending? = nil,
    toolExecutor: CloudConversationToolExecuting = CloudConversationToolExecutor(),
    disclosureStore: AgentDataDisclosureStore = FileAgentDataDisclosureStore(
      fileURL: AgentDataDisclosureStorePaths.ledgerURL()
    ),
    elapsedMillis: @escaping () -> Int64 = CloudConversationStreamEngine.defaultElapsedMillis
  ) {
    self.modelClient = modelClient
    self.streamClient = streamClient
    self.legacySender = legacySender ?? modelClient
    self.toolExecutor = toolExecutor
    self.disclosureStore = disclosureStore
    self.elapsedMillis = elapsedMillis
  }

  func streamConversation(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    turns: [ChatMessage],
    requestId: String = UUID().uuidString
  ) -> AsyncThrowingStream<ModelStreamEvent, Error> {
    streamConversation(
      contact: contact,
      store: store,
      turns: turns,
      images: [],
      requestId: requestId
    )
  }

  func streamConversation(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    turns: [ChatMessage],
    images: [CloudImagePayload],
    requestId: String = UUID().uuidString
  ) -> AsyncThrowingStream<ModelStreamEvent, Error> {
    streamConversation(contact: contact, store: store, turns: turns, images: images,
      requestId: requestId, collaborationEvidence: nil)
  }

  func streamConversation(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    turns: [ChatMessage],
    images: [CloudImagePayload],
    requestId: String,
    collaborationEvidence: AgentCollaborationToolEvidenceScope?,
    collaborationModelAudit: AgentCollaborationToolEvidenceScope? = nil
  ) -> AsyncThrowingStream<ModelStreamEvent, Error> {
    let conversationRequestId = Self.normalizedRequestId(requestId)
    return AsyncThrowingStream { continuation in
      let worker = Task {
        await runConversation(
          contact: contact,
          store: store,
          turns: turns,
          images: images,
          requestId: conversationRequestId,
          collaborationEvidence: collaborationEvidence,
          collaborationModelAudit: collaborationModelAudit ?? collaborationEvidence,
          continuation: continuation
        )
      }
      continuation.onTermination = { [weak self] _ in
        worker.cancel()
        Task {
          await self?.cancel(requestId: conversationRequestId, reason: .sessionChanged)
        }
      }
    }
  }

  func stream(_ request: ModelStreamRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
    streamClient.stream(request)
  }

  func cancel(requestId: String, reason: ModelStreamCancelReason) async {
    let targetRequestId = locked {
      activeRoundIds[requestId] ?? requestId
    }
    await streamClient.cancel(requestId: targetRequestId, reason: reason)
  }

  func activeProviderRequestId(for requestId: String) -> String? {
    locked {
      activeRoundIds[requestId]
    }
  }

  private func runConversation(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    turns: [ChatMessage],
    images: [CloudImagePayload],
    requestId: String,
    collaborationEvidence: AgentCollaborationToolEvidenceScope?,
    collaborationModelAudit: AgentCollaborationToolEvidenceScope?,
    continuation: AsyncThrowingStream<ModelStreamEvent, Error>.Continuation
  ) async {
    defer { CloudImageAnnotationSession.discard(requestId: requestId) }
    let ticket = AgentDataDisclosureLedger.beginCloudRequest(
      store: disclosureStore,
      destination: AgentDataDisclosureCloudDestination(contact: contact),
      text: turns.map(\.content).joined(separator: "\n"),
      historyCount: turns.count,
      systemInstructions: true,
      toolOutput: false,
      purpose: "Streaming conversation response",
      attachments: images.map {
        AgentDataDisclosureAttachment(
          displayName: $0.displayName,
          mimeType: $0.mimeType,
          sizeBytes: Int64($0.data.count)
        )
      },
      conversationId: turns.last?.conversationId ?? "",
      taskId: requestId,
      turnId: turns.last?.turnId.ifBlank(requestId) ?? requestId
    )
    guard ticket.allowed else {
      continuation.yield(
        .failed(
          ModelStreamFailed(
            requestId: requestId,
            error: ModelStreamError(
              code: "DISCLOSURE_BLOCKED",
              message: "Cloud data disclosure is not allowed"
            )
          )
        )
      )
      continuation.finish()
      return
    }

    var emittedText = false
    var emittedSequence: Int64 = 0
    var connected = false
    var lastFinishReason: String?
    let conversationId = turns.last?.conversationId ?? ""
    let turnId = turns.last?.turnId.ifBlank(requestId) ?? requestId

    do {
      let request = try await modelClient.prepareConversationStreamRequest(
        contact: contact,
        store: store,
        turns: turns,
        requestId: requestId,
        images: images
      )
      var prepared = try CloudModelStreamMutableConversation(request: request)
      let collaborationRecallScope = collaborationEvidence ?? collaborationModelAudit
      if collaborationRecallScope != nil {
        prepared.installCollaborationRecall(originalsOnly: collaborationEvidence == nil)
      }
      if collaborationEvidence != nil { prepared.installCollaborationPublication() }
      let publishName = CloudModelStreamMutableConversation.collaborationPublishName
      var publishedMilestones = Set<String>()
      var evidenceResults: [(String, String)] = []
      let evidencePromptLedger = CloudEvidencePromptLedger(query: turns.last?.content ?? "")
      let progress = CloudWebToolLoopProgress()
      var round = 0

      while true {
        let currentRound = round
        round += 1
        let roundId = "\(requestId):r\(currentRound)"
        let finalRound = progress.finalizationRequested
        let bufferForCitationVerification = !evidenceResults.isEmpty
        let citationPreview = bufferForCitationVerification
          ? CloudCitationPreview(evidence: evidenceResults)
          : nil
        var previewShown = false
        let roundRequest = try prepared.requestForRound(roundId: roundId, finalRound: finalRound)
        let assembler = ToolCallDeltaAssembler()
        let inlineProtocolGuard = InlineToolProtocolStreamGuard()
        var roundCompleted = false
        var roundFailure: ModelStreamFailed?
        var observedUsage: ModelUsage?
        var reportedModel: String?
        var audit = await beginCollaborationAudit(scope: collaborationModelAudit, round: currentRound,
          request: roundRequest, route: .streaming, store: store)
        func finishAudit() {
          guard let admission = audit else { return }
          audit = nil
          let state: AgentCollaborationModelSettlement.State = Task.isCancelled ? .cancelled :
            (roundFailure != nil ? .failed : (roundCompleted ? .completed : .interrupted))
          try? AgentTeamExecutionHistoryStore.shared.settleCollaborationModelCall(admission, settlement: .init(
            state: state, finishedAtMillis: max(admission.startedAtMillis, AgentControlPlaneClock.nowMillis()),
            reportedUsage: observedUsage, usageComplete: false, costMicros: nil, reportedModel: reportedModel))
        }
        defer { finishAudit() }
        setActiveRound(roundId, for: requestId)

        for try await event in streamClient.stream(roundRequest) {
          try Task.checkCancellation()
          switch event {
          case .connected(let value):
            guard !connected else { continue }
            connected = true
            continuation.yield(
              .connected(
                ModelStreamConnected(
                  requestId: requestId,
                  httpStatus: value.httpStatus,
                  connectedAtElapsedMs: value.connectedAtElapsedMs
                )
              )
            )

          case .textDelta(let value):
            let visibleText = inlineProtocolGuard.append(value.text)
            if let preview = citationPreview?.append(visibleText) {
              previewShown = true
              continuation.yield(.citationPreview(ModelStreamCitationPreview(
                requestId: requestId,
                text: preview,
                receivedAtElapsedMs: value.receivedAtElapsedMs
              )))
            }
            if !visibleText.isEmpty && !bufferForCitationVerification {
              emittedText = true
              emittedSequence += 1
              continuation.yield(
                .textDelta(
                  ModelStreamTextDelta(
                    requestId: requestId,
                    sequence: emittedSequence,
                    text: visibleText,
                    receivedAtElapsedMs: value.receivedAtElapsedMs
                  )
                )
              )
            }

          case .citationPreview:
            continue

          case .toolCallDelta(let value):
            assembler.accept(value.payload)
            emittedSequence += 1
            continuation.yield(
              .toolCallDelta(
                ModelStreamToolCallDelta(
                  requestId: requestId,
                  sequence: emittedSequence,
                  payload: value.payload
                )
              )
            )

          case .usage(let value):
            if value.usage.inputTokens >= 0, value.usage.outputTokens >= 0,
               (0...value.usage.inputTokens).contains(value.usage.cachedInputTokens) {
              observedUsage = value.usage
            }
            continuation.yield(.usage(ModelStreamUsage(requestId: requestId, usage: value.usage)))

          case .completed(let value):
            roundCompleted = true
            reportedModel = value.reportedModel
            lastFinishReason = value.finishReason

          case .failed(let value):
            roundFailure = ModelStreamFailed(requestId: requestId, error: value.error)
          }
        }
        finishAudit()
        setActiveRound(nil, for: requestId)

        if let failure = roundFailure {
          if previewShown {
            continuation.yield(.citationPreview(ModelStreamCitationPreview(
              requestId: requestId,
              text: "",
              receivedAtElapsedMs: elapsedMillis()
            )))
          }
          if !emittedText && failure.error.code == "STREAM_UNSUPPORTED" {
            let fallbackAudit = await beginCollaborationAudit(scope: collaborationModelAudit, round: currentRound,
              request: roundRequest, route: .compatibility, store: store)
            await emitLegacyConversation(
              contact: contact,
              store: store,
              turns: turns,
              images: images,
              requestId: requestId,
              sequence: &emittedSequence,
              ticket: ticket,
              audit: fallbackAudit,
              continuation: continuation
            )
          } else {
            AgentDataDisclosureLedger.update(
              store: disclosureStore,
              ticket: ticket,
              status: .failed,
              failureReason: failure.error.message
            )
            continuation.yield(.failed(failure))
          }
          continuation.finish()
          return
        }

        guard roundCompleted else {
          if previewShown {
            continuation.yield(.citationPreview(ModelStreamCitationPreview(
              requestId: requestId,
              text: "",
              receivedAtElapsedMs: elapsedMillis()
            )))
          }
          let error = ModelStreamError(
            code: "STREAM_INTERRUPTED",
            message: "The provider stream ended before completion",
            retryable: true,
            partialResponse: emittedText
          )
          AgentDataDisclosureLedger.update(
            store: disclosureStore,
            ticket: ticket,
            status: .failed,
            failureReason: error.message
          )
          continuation.yield(.failed(ModelStreamFailed(requestId: requestId, error: error)))
          continuation.finish()
          return
        }

        let visibleTail = inlineProtocolGuard.finishVisibleText()
        if !visibleTail.isEmpty && !bufferForCitationVerification {
          emittedText = true
          emittedSequence += 1
          continuation.yield(
            .textDelta(
              ModelStreamTextDelta(
                requestId: requestId,
                sequence: emittedSequence,
                text: visibleTail,
                receivedAtElapsedMs: elapsedMillis()
              )
            )
          )
        }

        let rawRoundText = inlineProtocolGuard.rawText()
        let structuredCalls = assembler.completedCalls()
        let inlineCalls = CloudWebGrounding.parseInlineToolCalls(rawRoundText)
        let usesInlineProtocol = structuredCalls.isEmpty && !inlineCalls.isEmpty
        let calls = usesInlineProtocol
          ? inlineCalls.enumerated().map { index, call in
            AssembledToolCall(
              callId: "inline-r\(currentRound)-\(index)",
              index: index,
              name: call.name,
              argumentsJson: Self.inlineArgumentsJSON(call.arguments)
            )
          }
          : structuredCalls
        if previewShown && (!calls.isEmpty || CloudWebGrounding.containsInternalToolProtocol(rawRoundText)) {
          continuation.yield(.citationPreview(ModelStreamCitationPreview(
            requestId: requestId,
            text: "",
            receivedAtElapsedMs: elapsedMillis()
          )))
        }
        if calls.isEmpty {
          if CloudWebGrounding.containsInternalToolProtocol(rawRoundText),
             !finalRound,
             progress.requestRepair("stream_internal_protocol") {
            prepared.appendInlineToolRepairPrompt(rawRoundText)
            continue
          }
          if bufferForCitationVerification {
            let candidate = CloudWebGrounding.stripInternalToolProtocol(rawRoundText)
            let repairPrompt = CloudWebGrounding.citationRepairPrompt(candidate, results: evidenceResults)
            if !candidate.isBlank,
               let repairPrompt,
               !finalRound,
               progress.requestRepair("stream_citations") {
              if previewShown {
                continuation.yield(.citationPreview(ModelStreamCitationPreview(
                  requestId: requestId,
                  text: "",
                  receivedAtElapsedMs: elapsedMillis()
                )))
              }
              prepared.appendCitationRepairPrompt(draft: candidate, prompt: repairPrompt)
              continue
            }
            let visibleAnswer = !candidate.isBlank && repairPrompt == nil
              ? candidate
              : CloudWebGrounding.evidenceFallback(results: evidenceResults)
            if !visibleAnswer.isBlank {
              emittedText = true
              emittedSequence += 1
              continuation.yield(
                .textDelta(
                  ModelStreamTextDelta(
                    requestId: requestId,
                    sequence: emittedSequence,
                    text: visibleAnswer,
                    receivedAtElapsedMs: elapsedMillis()
                  )
                )
              )
            }
          }
          let artifactSuffix = CloudImageAnnotationSession.artifactSuffix(requestId: requestId)
          if !artifactSuffix.isEmpty {
            emittedText = true
            emittedSequence += 1
            continuation.yield(.textDelta(ModelStreamTextDelta(
              requestId: requestId,
              sequence: emittedSequence,
              text: artifactSuffix,
              receivedAtElapsedMs: elapsedMillis()
            )))
          }
          AgentDataDisclosureLedger.update(store: disclosureStore, ticket: ticket, status: .sent)
          continuation.yield(
            .completed(
              ModelStreamCompleted(
                requestId: requestId,
                finishReason: lastFinishReason,
                completedAtElapsedMs: elapsedMillis()
              )
            )
          )
          continuation.finish()
          return
        }

        if finalRound {
          let visibleAnswer = CloudWebGrounding.evidenceFallback(results: evidenceResults)
          if !visibleAnswer.isBlank {
            emittedText = true
            emittedSequence += 1
            continuation.yield(
              .textDelta(
                ModelStreamTextDelta(
                  requestId: requestId,
                  sequence: emittedSequence,
                  text: visibleAnswer,
                  receivedAtElapsedMs: elapsedMillis()
                )
              )
            )
          }
          let artifactSuffix = CloudImageAnnotationSession.artifactSuffix(requestId: requestId)
          if !artifactSuffix.isEmpty {
            emittedText = true
            emittedSequence += 1
            continuation.yield(.textDelta(ModelStreamTextDelta(
              requestId: requestId,
              sequence: emittedSequence,
              text: artifactSuffix,
              receivedAtElapsedMs: elapsedMillis()
            )))
          }
          AgentDataDisclosureLedger.update(store: disclosureStore, ticket: ticket, status: .sent)
          continuation.yield(
            .completed(
              ModelStreamCompleted(
                requestId: requestId,
                finishReason: lastFinishReason,
                completedAtElapsedMs: elapsedMillis()
              )
            )
          )
          continuation.finish()
          return
        }

        var parsedCalls: [(AssembledToolCall, AgentMcpJSONObject)] = []
        var invalidToolCall: AssembledToolCall?
        for call in calls {
          guard let arguments = try? CloudModelStreamJSON.mcpObject(from: call.argumentsJson) else {
            invalidToolCall = call
            break
          }
          parsedCalls.append((call, arguments))
        }

        if let invalidToolCall {
          let repairKey = "stream_tool_arguments:\(invalidToolCall.name.lowercased())"
          if progress.requestRepair(repairKey) {
            prepared.appendToolArgumentRepairPrompt(invalidToolCall)
          } else {
            progress.requestFinalization()
          }
          continue
        }

        var freshKeys = Set<String>()
        let preparedCalls = parsedCalls.compactMap { item -> AssembledToolCall? in
          let (call, arguments) = item
          if call.name == publishName { return call }
          guard progress.cached(toolName: call.name, arguments: arguments) == nil else { return nil }
          let key = progress.semanticKey(toolName: call.name, arguments: arguments)
          return freshKeys.insert(key).inserted ? call : nil
        }

        var outcomes = await executeToolCalls(
          preparedCalls,
          context: CloudConversationToolExecutionContext(
            requestId: requestId,
            conversationId: conversationId,
            turnId: turnId,
            images: images,
            readOnlyAnalysis: turns.last?.readOnlyAnalysis ?? false
          ),
          collaborationRecall: collaborationRecallScope.map { scope in
            { arguments in
              await MainActor.run {
                guard collaborationEvidence != nil || ["goal", "dependency"].contains(arguments.string("mode")) else {
                  return nil
                }
                guard let session = store.agentSession(id: scope.conversationId), session.id == scope.conversationId,
                      let roster = session.collaborationRoster,
                      let member = scope.memberId.split(separator: ":").first,
                      let memberId = UUID(uuidString: String(member)),
                      roster.members.contains(where: { $0.id == memberId }),
                      session.mergedIntoConversationId.isBlank,
                      !session.privateMode, !session.trackingPaused else { return nil }
                return try? AgentTeamExecutionHistoryStore.shared.recallCollaborationOriginal(arguments, scope: scope)
              }
            }
          },
          collaborationPublish: collaborationEvidence.map { scope in
            { arguments in
              await MainActor.run {
                guard let session = store.agentSession(id: scope.conversationId), session.id == scope.conversationId,
                      let roster = session.collaborationRoster,
                      let member = scope.memberId.split(separator: ":").first,
                      let memberId = UUID(uuidString: String(member)), roster.members.contains(where: { $0.id == memberId }),
                      session.mergedIntoConversationId.isBlank, !session.privateMode, !session.trackingPaused else { return nil }
                return try? AgentTeamExecutionHistoryStore.shared.publishCollaborationMilestone(arguments, scope: scope)
              }
            }
          }
        )
        if let scope = collaborationEvidence {
          for index in outcomes.indices {
            let outcome = outcomes[index]
            if outcome.call.name == CloudModelStreamMutableConversation.collaborationRecallName ||
                outcome.call.name == publishName { continue }
            let evidence = AgentCollaborationCloudToolEvidence(scope: scope, round: round,
              call: outcome.call, output: outcome.output ?? outcome.errorMessage ?? "",
              succeeded: outcome.output != nil, startedAtMillis: outcome.startedAtMillis,
              finishedAtMillis: outcome.finishedAtMillis)
            let receipt = await MainActor.run { () -> AgentMcpJSONObject? in
              guard let session = store.agentSession(id: scope.conversationId), session.id == scope.conversationId,
                    session.collaborationRoster != nil, session.mergedIntoConversationId.isBlank,
                    !session.privateMode, !session.trackingPaused else { return nil }
              return try? AgentTeamExecutionHistoryStore.shared.recordCloudEvidence(evidence)
            }
            if let output = outcome.output {
              outcomes[index].output = Self.cloudEvidenceOutput(output, receipt: receipt)
            }
          }
        }
        if let failedOutcome = outcomes.first(where: { $0.errorMessage != nil }) {
          let streamError = ModelStreamError(
            code: "INVALID_TOOL_ARGUMENTS",
            message: "Tool arguments were incomplete: \(failedOutcome.errorMessage ?? "unknown error")"
          )
          AgentDataDisclosureLedger.update(
            store: disclosureStore,
            ticket: ticket,
            status: .failed,
            failureReason: streamError.message
          )
          continuation.yield(.failed(ModelStreamFailed(requestId: requestId, error: streamError)))
          continuation.finish()
          return
        }

        var madeProgress = false
        var publicationResults: [String: String] = [:]
        for outcome in outcomes {
          guard let output = outcome.output,
                let arguments = try? CloudModelStreamJSON.mcpObject(from: outcome.call.argumentsJson) else {
            continue
          }
          if outcome.call.name == publishName {
            publicationResults[outcome.call.callId] = output
            if let receipt = try? CloudModelStreamJSON.mcpObject(from: output), receipt["status"] == .string("published"),
               publishedMilestones.insert(receipt.string("milestone_id")).inserted { madeProgress = true }
            continue
          }
          if progress.record(toolName: outcome.call.name, arguments: arguments, output: output) {
            madeProgress = true
            if outcome.call.name.lowercased() != CloudImageAnnotationPlan.toolName &&
                !CloudWebToolLoopProgress.isRuleRecall(toolName: outcome.call.name, arguments: arguments) {
              evidenceResults.append((outcome.call.name, output))
            }
          }
        }
        let results = parsedCalls.compactMap { item -> (AssembledToolCall, String)? in
          let (call, arguments) = item
          if call.name == publishName, let output = publicationResults[call.callId] { return (call, output) }
          guard let output = progress.cached(toolName: call.name, arguments: arguments) else { return nil }
          CloudImageAnnotationSession.selectResult(output, requestId: requestId)
          return (call, output)
        }

        let rawEvidence = evidenceResults.map(\.1)
        let projectedEvidence = evidencePromptLedger.project(rawEvidence)
        var projectionByOriginal: [String: String] = [:]
        for (original, projection) in zip(rawEvidence, projectedEvidence) {
          projectionByOriginal[original] = projection
        }
        let promptResults = results.map { call, output in
          if call.name == publishName { return (call, output) }
          if let arguments = try? CloudModelStreamJSON.mcpObject(from: call.argumentsJson),
             CloudWebToolLoopProgress.isRuleRecall(toolName: call.name, arguments: arguments) {
            return (call, output)
          }
          return (call, projectionByOriginal[output] ?? evidencePromptLedger.project(output))
        }
        if usesInlineProtocol {
          prepared.appendInlineToolResults(rawRoundText, results: promptResults)
        } else {
          try prepared.appendToolResults(promptResults)
        }
        if !madeProgress {
          progress.requestFinalization()
        }
      }
    } catch is CancellationError {
      await cancel(requestId: requestId, reason: .userStop)
    } catch {
      let streamError = Self.streamError(from: error, partialResponse: emittedText)
      AgentDataDisclosureLedger.update(
        store: disclosureStore,
        ticket: ticket,
        status: .failed,
        failureReason: streamError.message
      )
      continuation.yield(.failed(ModelStreamFailed(requestId: requestId, error: streamError)))
    }
    setActiveRound(nil, for: requestId)
    continuation.finish()
  }

  private func beginCollaborationAudit(scope: AgentCollaborationToolEvidenceScope?, round: Int,
    request: ModelStreamRequest, route: AgentCollaborationModelAdmission.Route,
    store: GalaxySSIStore) async -> AgentCollaborationModelAdmission? {
    guard let scope else { return nil }
    let candidate = AgentCollaborationModelAdmission(id: UUID(), scope: scope, round: round,
      provider: request.provider,
      requestedModel: route == .streaming ? (try? CloudModelStreamJSON.object(from: request.bodyJson))?["model"] as? String : nil,
      startedAtMillis: AgentControlPlaneClock.nowMillis(), route: route)
    return await MainActor.run {
      guard let session = store.agentSession(id: scope.conversationId), session.id == scope.conversationId,
            session.collaborationRoster != nil, session.mergedIntoConversationId.isBlank,
            !session.privateMode, !session.trackingPaused,
            (try? AgentTeamExecutionHistoryStore.shared.admitCollaborationModelCall(candidate)) != nil else { return nil }
      return candidate
    }
  }

  private func emitLegacyConversation(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    turns: [ChatMessage],
    images: [CloudImagePayload],
    requestId: String,
    sequence: inout Int64,
    ticket: AgentDisclosureTicket,
    audit: AgentCollaborationModelAdmission?,
    continuation: AsyncThrowingStream<ModelStreamEvent, Error>.Continuation
  ) async {
    var auditState: AgentCollaborationModelSettlement.State = .interrupted
    defer {
      if let audit {
        try? AgentTeamExecutionHistoryStore.shared.settleCollaborationModelCall(audit, settlement: .init(
          state: auditState, finishedAtMillis: max(audit.startedAtMillis, AgentControlPlaneClock.nowMillis()),
          reportedUsage: nil, usageComplete: false, costMicros: nil))
      }
    }
    do {
      try Task.checkCancellation()
      let text = try await legacySender.send(
        contact: contact,
        store: store,
        turns: turns,
        images: images
      )
      let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cleanText.isEmpty else {
        throw GalaxySSIError.unsupportedResponse
      }
      try Task.checkCancellation()
      auditState = .completed
      sequence += 1
      let now = elapsedMillis()
      continuation.yield(
        .textDelta(
          ModelStreamTextDelta(
            requestId: requestId,
            sequence: sequence,
            text: cleanText,
            receivedAtElapsedMs: now
          )
        )
      )
      AgentDataDisclosureLedger.update(store: disclosureStore, ticket: ticket, status: .sent)
      continuation.yield(
        .completed(
          ModelStreamCompleted(
            requestId: requestId,
            finishReason: "compatibility",
            completedAtElapsedMs: now
          )
        )
      )
    } catch {
      auditState = error is CancellationError || Task.isCancelled ? .cancelled : .failed
      let streamError = Self.streamError(from: error, partialResponse: false)
      AgentDataDisclosureLedger.update(
        store: disclosureStore,
        ticket: ticket,
        status: .failed,
        failureReason: streamError.message
      )
      continuation.yield(.failed(ModelStreamFailed(requestId: requestId, error: streamError)))
    }
  }

  private func executeToolCalls(
    _ calls: [AssembledToolCall],
    context: CloudConversationToolExecutionContext,
    collaborationRecall: ((AgentMcpJSONObject) async -> AgentMcpJSONObject?)? = nil,
    collaborationPublish: ((AgentMcpJSONObject) async -> AgentMcpJSONObject?)? = nil
  ) async -> [ToolExecutionOutcome] {
    guard !calls.isEmpty else { return [] }

    var outcomes: [ToolExecutionOutcome] = []
    for start in stride(from: 0, to: calls.count, by: Self.maxParallelToolCalls) {
      let end = min(start + Self.maxParallelToolCalls, calls.count)
      let batch = Array(calls[start..<end])
      let batchOutcomes = await withTaskGroup(of: ToolExecutionOutcome.self) { group in
        for (offset, call) in batch.enumerated() {
          group.addTask { [toolExecutor] in
            let started = AgentControlPlaneClock.nowMillis()
            do {
              let output: String
              if call.name == CloudModelStreamMutableConversation.collaborationRecallName {
                let args = try CloudModelStreamJSON.mcpObject(from: call.argumentsJson)
                let recalled = await collaborationRecall?(args)
                output = AgentMcpJSONCodec.stringify(recalled ?? ["status": .string("unavailable")])
              } else if call.name == CloudModelStreamMutableConversation.collaborationPublishName {
                let args = try CloudModelStreamJSON.mcpObject(from: call.argumentsJson)
                let receipt = await collaborationPublish?(args)
                output = AgentMcpJSONCodec.stringify(receipt ?? ["success": .bool(false), "status": .string("unavailable")])
              } else {
                output = try toolExecutor.executeTool(call: call, context: context)
              }
              return ToolExecutionOutcome(
                index: start + offset,
                call: call,
                output: output,
                errorMessage: nil,
                startedAtMillis: started, finishedAtMillis: AgentControlPlaneClock.nowMillis()
              )
            } catch {
              return ToolExecutionOutcome(
                index: start + offset,
                call: call,
                output: nil,
                errorMessage: error.localizedDescription.ifBlank(String(describing: error)),
                startedAtMillis: started, finishedAtMillis: AgentControlPlaneClock.nowMillis()
              )
            }
          }
        }

        var completed: [ToolExecutionOutcome] = []
        for await outcome in group {
          completed.append(outcome)
        }
        return completed.sorted { $0.index < $1.index }
      }
      outcomes.append(contentsOf: batchOutcomes)
    }
    return outcomes
  }

  static func cloudEvidenceOutput(_ output: String, receipt: AgentMcpJSONObject?) -> String {
    var object = (try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(output.utf8)))
      ?? ["output": .string(output)]
    object.removeValue(forKey: "galaxyssi_evidence_receipt")
    object.removeValue(forKey: "galaxyssi_evidence_recording")
    if let receipt {
      object["galaxyssi_evidence_receipt"] = .object(receipt)
    } else {
      object["galaxyssi_evidence_recording"] = .object([
        "status": .string("not_durable"), "do_not_reexecute": .bool(true)
      ])
    }
    return AgentMcpJSONCodec.stringify(object)
  }

  private func setActiveRound(_ roundId: String?, for requestId: String) {
    locked {
      if let roundId {
        activeRoundIds[requestId] = roundId
      } else {
        activeRoundIds.removeValue(forKey: requestId)
      }
    }
  }

  private func locked<T>(_ work: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return work()
  }

  private static func normalizedRequestId(_ requestId: String) -> String {
    requestId.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(UUID().uuidString)
  }

  private static func streamError(from error: Error, partialResponse: Bool) -> ModelStreamError {
    ModelStreamError(
      code: "STREAM_FAILED",
      message: error.localizedDescription.ifBlank(String(describing: error)),
      retryable: false,
      partialResponse: partialResponse
    )
  }

  private static func inlineArgumentsJSON(_ arguments: AgentMcpJSONObject) -> String {
    guard let data = try? JSONEncoder().encode(arguments) else { return "{}" }
    return String(decoding: data, as: UTF8.self)
  }

  private static func defaultElapsedMillis() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }
}

extension CloudConversationStreamEngine: CloudConversationStreaming {}
