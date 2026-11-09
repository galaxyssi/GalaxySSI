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
  typealias GoalWorkHandler = @MainActor (AgentMcpJSONObject) async -> AgentMcpJSONObject
  typealias GoalContinuationHandler = @MainActor (String) async -> AgentMcpJSONObject?
  typealias DesktopEvidenceRefresh = @MainActor (AgentMcpJSONObject, AgentCollaborationToolEvidenceScope) async -> String?
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
  private let legacySender: CloudConversationLegacySending?
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
    self.legacySender = legacySender
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
    collaborationModelAudit: AgentCollaborationToolEvidenceScope? = nil,
    goalWorkHandler: GoalWorkHandler? = nil,
    workInputPublisher: GoalWorkHandler? = nil,
    goalContinuationHandler: GoalContinuationHandler? = nil,
    desktopEvidenceRefresh: DesktopEvidenceRefresh? = nil,
    researchRetrySource: ChatMessage? = nil,
    retainResearch: Bool = true
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
          goalWorkHandler: goalWorkHandler,
          workInputPublisher: workInputPublisher,
          goalContinuationHandler: goalContinuationHandler,
          desktopEvidenceRefresh: desktopEvidenceRefresh,
          researchRetrySource: researchRetrySource,
          retainResearch: retainResearch,
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
    goalWorkHandler: GoalWorkHandler?,
    workInputPublisher: GoalWorkHandler?,
    goalContinuationHandler: GoalContinuationHandler?,
    desktopEvidenceRefresh: DesktopEvidenceRefresh?,
    researchRetrySource: ChatMessage?,
    retainResearch: Bool,
    continuation: AsyncThrowingStream<ModelStreamEvent, Error>.Continuation
  ) async {
    defer { CloudImageAnnotationSession.discard(requestId: requestId) }
    if retainResearch, images.isEmpty, collaborationEvidence == nil, collaborationModelAudit == nil,
       let researchRetrySource,
       let request = try? await modelClient.prepareConversationStreamRequest(contact: contact, store: store,
         turns: turns, requestId: requestId),
       let cached = await CloudResearchObservationRecovery.replay(store: store, contact: contact, request: request,
         turns: turns, retrySource: researchRetrySource) {
      let now = elapsedMillis()
      continuation.yield(.textDelta(.init(requestId: requestId, sequence: 1, text: cached, receivedAtElapsedMs: now)))
      continuation.yield(.completed(.init(requestId: requestId, finishReason: "recovered_synthesis", completedAtElapsedMs: now)))
      continuation.finish()
      return
    }
    let ticket = AgentDataDisclosureLedger.beginCloudRequest(
      store: disclosureStore,
      destination: AgentDataDisclosureCloudDestination(contact: contact),
      text: turns.map(\.content).joined(separator: "\n"),
      historyCount: turns.count,
      systemInstructions: true,
      toolOutput: researchRetrySource != nil,
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
    let disclosureOwner = await MainActor.run { store.profile.identityFingerprint }
    let researchDisclosure = turns.last?.isMine == true ? AgentLocalResearchCollector() : nil
    var previewPresentation = CloudCitationPreviewPresentation()

    @discardableResult
    func publishPreview(_ candidate: String, at elapsed: Int64) -> Bool {
      guard let text = previewPresentation.replace(candidate) else { return false }
      continuation.yield(.citationPreview(.init(requestId: requestId, text: text, receivedAtElapsedMs: elapsed)))
      return true
    }

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
      let goalAssessmentOnly = collaborationEvidence == nil && collaborationModelAudit != nil && goalWorkHandler != nil
      if collaborationRecallScope != nil {
        prepared.installCollaborationRecall(originalsOnly: collaborationEvidence == nil)
      }
      if collaborationRecallScope != nil {
        prepared.installCollaborationPublication(assessmentOnly: collaborationEvidence == nil,
          canRunGoalWork: collaborationEvidence == nil && goalWorkHandler != nil)
      }
      if workInputPublisher != nil {
        guard collaborationRecallScope == nil, turns.last?.readOnlyAnalysis == true else { throw CancellationError() }
        prepared.installWorkInputPublication()
      }
      let publishName = CloudModelStreamMutableConversation.collaborationPublishName
      var publishedMilestones = Set<String>()
      var visitedWorkInputResponses = Set<String>()
      var evidenceResults: [(String, String)] = []
      var visitedSourceAccessPages = Set<String>()
      let evidencePromptLedger = CloudEvidencePromptLedger(query: turns.last?.content ?? "")
      let progress = CloudWebToolLoopProgress()
      var visitedWorkflowChecks = Set<String>()
      let research = CloudResearchRuntimeBudget(limits: .configured(contact.cloud_research_limits))
      let recovery: CloudResearchObservationRecovery?
      if retainResearch && images.isEmpty && collaborationRecallScope == nil {
        recovery = await CloudResearchObservationRecovery.open(store: store, contact: contact, request: request,
          turns: turns, retrySource: researchRetrySource)
      } else { recovery = nil }
      if let recovery {
        evidenceResults = await recovery.restore(into: &prepared, progress: progress, budget: research, ledger: evidencePromptLedger)
      }
      var round = 0
      var useCompleteJSON = false

      while true {
        if !progress.finalizationRequested, let reason = research.stopReason {
          progress.requestFinalization()
          prepared.appendResearchGuidance(research.guidance(stopped: reason))
        }
        let currentRound = round
        round += 1
        research.beginRound()
        let roundId = "\(requestId):r\(currentRound)"
        let finalRound = progress.finalizationRequested
        let continuationConversation = goalAssessmentOnly && finalRound ? prepared : nil
        let bufferForCitationVerification = !evidenceResults.isEmpty
        let citationPreview = bufferForCitationVerification && !progress.performedDeepResearch
          ? CloudCitationPreview(evidence: evidenceResults)
          : nil
        var previewShown = false
        let preparedRound = try prepared.requestForRound(roundId: roundId, finalRound: finalRound,
          finalInstruction: goalAssessmentOnly ? CloudModelStreamMutableConversation.goalAssessmentFinalInstruction : nil)
        let roundRequest = useCompleteJSON
          ? try CloudConversationNonStreamingToolEngine.compatibilityRequest(preparedRound) : preparedRound
        let assembler = ToolCallDeltaAssembler()
        let inlineProtocolGuard = InlineToolProtocolStreamGuard()
        var roundCompleted = false
        var roundFailure: ModelStreamFailed?
        var observedUsage: ModelUsage?
        var reportedModel: String?
        var audit = try await beginCollaborationAudit(scope: collaborationModelAudit, round: currentRound,
          request: roundRequest, route: useCompleteJSON ? .compatibility : .streaming, contact: contact, store: store)
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

        do {
          for try await event in CloudResearchRoundDeadline.stream(streamClient.stream(roundRequest),
            millis: research.limits.modelMillis) {
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
              if !goalAssessmentOnly, let preview = citationPreview?.append(visibleText),
                 publishPreview(preview, at: value.receivedAtElapsedMs) {
                previewShown = true
              }
              if !goalAssessmentOnly && !visibleText.isEmpty && !bufferForCitationVerification {
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
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          try Task.checkCancellation()
          roundFailure = ModelStreamFailed(requestId: requestId, error: Self.streamError(from: error, partialResponse: emittedText))
        }
        try Task.checkCancellation()
        finishAudit()
        setActiveRound(nil, for: requestId)

        if legacySender == nil, !useCompleteJSON, !emittedText, roundFailure?.error.code == "STREAM_UNSUPPORTED" {
          publishPreview("", at: elapsedMillis())
          useCompleteJSON = true
          continue
        }

        let incomplete = roundFailure?.error ?? (!roundCompleted ? ModelStreamError(
          code: "STREAM_INTERRUPTED", message: "The provider stream ended before completion", retryable: true
        ) : nil)
        if let incomplete, CloudResearchRuntimeBudget.canRecover(incomplete),
           CloudResearchRuntimeBudget.hasCitableEvidence(evidenceResults) {
          publishPreview("", at: elapsedMillis())
          if research.requestInterruptedSynthesis(hasEvidence: true, finalizing: finalRound) {
            progress.requestFinalization()
            prepared.appendResearchGuidance(research.guidance(stopped: "model_round_interrupted"))
            continue
          }
          finishEvidenceOnly(evidenceResults, requestId: requestId, sequence: emittedSequence + 1,
            ticket: ticket, continuation: continuation)
          return
        }

        if let failure = roundFailure {
          publishPreview("", at: elapsedMillis())
          if let legacySender, !emittedText && currentRound == 0 && failure.error.code == "STREAM_UNSUPPORTED" {
            let fallbackAudit = try await beginCollaborationAudit(scope: collaborationModelAudit, round: currentRound,
              request: roundRequest, route: .compatibility, contact: contact, store: store)
            await emitLegacyConversation(
              sender: legacySender,
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
          publishPreview("", at: elapsedMillis())
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
        if !goalAssessmentOnly && !visibleTail.isEmpty && !bufferForCitationVerification {
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
          publishPreview("", at: elapsedMillis())
        }
        if goalAssessmentOnly && (calls.isEmpty || finalRound) {
          let candidate = calls.isEmpty ? rawRoundText : ""
          if let goalContinuationHandler, let context = await goalContinuationHandler(candidate) {
            try Task.checkCancellation()
            if let continuationConversation { prepared = continuationConversation }
            progress.resumeGoalAssessment()
            prepared.appendGoalContinuation(context)
            continue
          }
          continuation.yield(.textDelta(ModelStreamTextDelta(requestId: requestId, sequence: emittedSequence + 1,
            text: candidate, receivedAtElapsedMs: elapsedMillis())))
          AgentDataDisclosureLedger.update(store: disclosureStore, ticket: ticket, status: .sent)
          continuation.yield(.completed(ModelStreamCompleted(requestId: requestId, finishReason: lastFinishReason,
            completedAtElapsedMs: elapsedMillis())))
          continuation.finish()
          return
        }
        if calls.isEmpty {
          if CloudWebGrounding.containsInternalToolProtocol(rawRoundText),
             !finalRound,
             progress.requestFormatRepair("stream_internal_protocol") {
            prepared.appendInlineToolRepairPrompt(rawRoundText)
            continue
          }
          if bufferForCitationVerification, !CloudWebGrounding.containsInternalToolProtocol(rawRoundText),
             research.requestEmptySynthesis(rawRoundText,
               hasEvidence: CloudResearchRuntimeBudget.hasCitableEvidence(evidenceResults)) {
            progress.requestFinalization()
            prepared.appendResearchGuidance(research.guidance(stopped: "empty_synthesis"))
            continue
          }
          if bufferForCitationVerification {
            let draft = CloudWebGrounding.stripInternalToolProtocol(rawRoundText)
            if !draft.isBlank, let qualityReview = CloudResearchQualityStandard.repairIfNeeded(draft, evidence: evidenceResults),
               !CloudWebGrounding.citationValidation(draft, results: evidenceResults).requiresRepair {
              if progress.requestRepair("stream_research_quality") {
                // This draft passed citation verification; keep it provisional while improving coverage.
                prepared.appendResearchQualityRepair(draft: draft, prompt: qualityReview)
                progress.requestFinalization()
                continue
              }
              finishEvidenceOnly(evidenceResults, requestId: requestId, sequence: emittedSequence + 1,
                ticket: ticket, continuation: continuation)
              return
            }
          }
          if bufferForCitationVerification {
            let candidate = CloudWebGrounding.stripInternalToolProtocol(rawRoundText)
            if !finalRound, prepared.canRequestBodyReadingReview, progress.performedDeepResearch,
               let review = CloudWebGrounding.bodyReadingReviewPrompt(candidate, results: evidenceResults),
               progress.requestRepair("research_body_reading") {
              prepared.appendBodyReadingReview(draft: candidate, prompt: review)
              continue
            }
            let repairPrompt = CloudWebGrounding.citationRepairPrompt(candidate, results: evidenceResults)
            if !candidate.isBlank,
               let repairPrompt,
               !finalRound,
               progress.requestRepair("stream_citations") {
              publishPreview("", at: elapsedMillis())
              prepared.appendCitationRepairPrompt(draft: candidate, prompt: repairPrompt)
              progress.requestFinalization()
              continue
            }
            if !candidate.isBlank, repairPrompt != nil,
               let partial = CloudWebGrounding.partialCitationRepairPrompt(candidate, results: evidenceResults),
               progress.requestPartialSynthesisRepair(after: "stream_citations") {
              publishPreview("", at: elapsedMillis())
              prepared.appendCitationRepairPrompt(draft: candidate, prompt: partial)
              continue
            }
            let visibleAnswer = !candidate.isBlank && repairPrompt == nil
              ? AgentIOSWebEvidenceVerification.resolveCitations(candidate, encodedToolResults: evidenceResults).text
              : CloudWebGrounding.evidenceFallback(results: evidenceResults)
            if !candidate.isBlank, repairPrompt == nil, roundCompleted,
               !CloudWebGrounding.containsInternalToolProtocol(rawRoundText),
               CloudImageAnnotationSession.artifactSuffix(requestId: requestId).isEmpty {
              await recovery?.recordFinal(visibleAnswer, store: store)
            }
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
          if progress.requestFormatRepair(repairKey) {
            prepared.appendToolArgumentRepairPrompt(invalidToolCall)
          } else {
            progress.requestFinalization()
          }
          continue
        }

        var freshKeys = Set<String>()
        let preparedCalls = parsedCalls.compactMap { item -> AssembledToolCall? in
          let (call, arguments) = item
          if workInputPublisher != nil, call.name != publishName { return nil }
          if AgentCollaborationWorkflowCheck.isCall(call.name, arguments) {
            let key = progress.semanticKey(toolName: call.name, arguments: arguments)
            return freshKeys.insert(key).inserted ? call : nil
          }
          if call.name == publishName { return call }
          guard AgentCollaborationSourceAccess.matches(tool: call.name, input: arguments) ||
                progress.cached(toolName: call.name, arguments: arguments) == nil else { return nil }
          let key = progress.semanticKey(toolName: call.name, arguments: arguments)
          return freshKeys.insert(key).inserted ? call : nil
        }
        guard research.reserveTools(preparedCalls.count) else {
          progress.requestFinalization()
          prepared.appendResearchGuidance(research.guidance(stopped: research.stopReason ?? "tool_batch_limit"))
          continue
        }

        var outcomes = await executeToolCalls(
          preparedCalls,
          context: CloudConversationToolExecutionContext(
            requestId: requestId,
            researchToolTimeoutMillis: research.limits.toolMillis,
            conversationId: conversationId,
            turnId: turnId,
            images: images,
            readOnlyAnalysis: turns.last?.readOnlyAnalysis ?? false,
            researchDisclosure: researchDisclosure
          ),
          onObservation: { call, output in
            await recovery?.record(call: call, output: output, store: store)
          },
          collaborationRecall: collaborationRecallScope.map { scope in
            { arguments in
              let sync = await desktopEvidenceRefresh?(arguments, scope)
              return await MainActor.run {
                guard var result = Self.scopedCollaborationRecall(arguments, scope: scope, allowsResearch: collaborationEvidence != nil,
                  resourceID: contact.id, session: store.agentSession(id: scope.conversationId), history: .shared) else { return nil }
                if let sync { result["live_sync"] = .string(sync) }
                return result
              }
            }
          },
          collaborationPublish: workInputPublisher.map { publisher in
            { arguments in await publisher(arguments) }
          } ?? collaborationRecallScope.map { scope in
            { arguments in
              let mode = arguments.string("mode")
              if AgentCollaborationGoalAssessmentPolicy.dispatchesWork(mode), let goalWorkHandler {
                guard collaborationEvidence == nil, collaborationModelAudit == scope else { return nil }
                return await goalWorkHandler(arguments)
              }
              return await MainActor.run {
                let needsCoordinator = AgentCollaborationGoalAssessmentPolicy.requiresCoordinator(mode)
                guard collaborationEvidence != nil || mode == "validate_assessment" || needsCoordinator else {
                  return nil
                }
                guard let session = store.agentSession(id: scope.conversationId), session.id == scope.conversationId,
                      let roster = session.collaborationRoster,
                      scope.rosterMember(in: roster)?.resourceId == contact.id,
                      session.mergedIntoConversationId.isBlank, !session.privateMode, !session.trackingPaused else { return nil }
                if needsCoordinator {
                  guard collaborationEvidence == nil, collaborationModelAudit == scope,
                        roster.coordinatorId == scope.rosterMember(in: roster)?.id,
                        let task = store.agentTask(id: scope.turnId), task.sessionId == scope.conversationId, !task.blocked,
                        task.phase == .executing || task.phase == .waitingResponse,
                        !PhoneExecutionAuthority.isCancelled(taskId: task.taskId) else { return nil }
                }
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
                    let roster = session.collaborationRoster, scope.rosterMember(in: roster)?.resourceId == contact.id,
                    session.mergedIntoConversationId.isBlank,
                    !session.privateMode, !session.trackingPaused else { return nil }
              return try? AgentTeamExecutionHistoryStore.shared.recordCloudEvidence(evidence)
            }
            if let output = outcome.output {
              outcomes[index].output = Self.cloudEvidenceOutput(output, receipt: receipt)
            }
          }
        }
        if let source = turns.last, let receipt = researchDisclosure?.drain(), receipt.visible {
          await MainActor.run { store.persistLocalResearchDisclosure(receipt, source: source, owner: disclosureOwner) }
        }
        if let failedOutcome = outcomes.first(where: { $0.errorMessage != nil }) {
          publishPreview("", at: elapsedMillis())
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
        var newResearchEvidence = false
        let retrievalBatch = parsedCalls.contains { CloudResearchRuntimeBudget.isRetrievalTool($0.0.name) }
        var workflowCheckResults: [String: String] = [:]
        var publicationResults: [String: String] = [:]
        var sourceAccessResults: [String: String] = [:]
        for outcome in outcomes {
          guard let output = outcome.output,
                let arguments = try? CloudModelStreamJSON.mcpObject(from: outcome.call.argumentsJson) else {
            continue
          }
          if AgentCollaborationWorkflowCheck.isCall(outcome.call.name, arguments) {
            let key = progress.semanticKey(toolName: outcome.call.name, arguments: arguments)
            workflowCheckResults[key] = output
            if let result = try? CloudModelStreamJSON.mcpObject(from: output), result["status"] == .string("returned"),
               visitedWorkflowChecks.insert(key).inserted { madeProgress = true }
            continue
          }
          if outcome.call.name == publishName {
            publicationResults[outcome.call.callId] = output
            if let receipt = try? CloudModelStreamJSON.mcpObject(from: output) {
              if workInputPublisher != nil, receipt["status"] == .string("recorded"), receipt["replayed"] == .bool(false) {
                madeProgress = true
              }
              if arguments["mode"] == .string(AgentCollaborationGoalAssessmentPolicy.workInputMode),
                 receipt["success"] == .bool(true),
                 visitedWorkInputResponses.insert(AgentMcpJSONCodec.sha256(receipt)).inserted { madeProgress = true }
            }
            if let receipt = try? CloudModelStreamJSON.mcpObject(from: output), receipt["status"] == .string("published"),
               publishedMilestones.insert(receipt.string("milestone_id")).inserted { madeProgress = true }
            if AgentCollaborationGoalAssessmentPolicy.isCoordinatorMutation(arguments.string("mode")),
               let receipt = try? CloudModelStreamJSON.mcpObject(from: output),
               ["contract_established", "work_admitted"].contains(receipt.string("status")),
               receipt["replayed"] == .bool(false) {
              madeProgress = true
            }
            if AgentCollaborationGoalAssessmentPolicy.dispatchesWork(arguments.string("mode")),
               let receipt = try? CloudModelStreamJSON.mcpObject(from: output),
               receipt["new_execution"] == .bool(true) {
              madeProgress = true
            }
            if arguments["mode"] == .string("publish"),
               let receipt = try? CloudModelStreamJSON.mcpObject(from: output), receipt["rejected_draft_preserved"] == .bool(true),
               progress.requestRepair("collaboration_milestone_publication") { madeProgress = true }
            if arguments["mode"] == .string("validate_assessment"),
               let checked = try? CloudModelStreamJSON.mcpObject(from: output), checked["status"] == .string("returned"),
               checked["success"] == .bool(true),
               progress.requestRepair("collaboration_assessment_preflight") { madeProgress = true }
            if arguments["mode"] == .string(AgentCollaborationGoalAssessmentPolicy.establishContractMode),
               let receipt = try? CloudModelStreamJSON.mcpObject(from: output),
               receipt["status"] == .string("assessment_rejected"),
               progress.requestRepair("collaboration_initial_assessment") { madeProgress = true }
            if arguments["mode"] == .string(AgentCollaborationGoalAssessmentPolicy.assessmentRepairMode),
               let page = try? CloudModelStreamJSON.mcpObject(from: output),
               page["status"] == .string("assessment_repair_page"), let offset = page["offset"]?.intValue,
               visitedSourceAccessPages.insert("assessment:" + page.string("draft_sha256") + ":" + String(offset)).inserted {
              madeProgress = true
            }
            if arguments["mode"] == .string(AgentCollaborationGoalAssessmentPolicy.appendWorkMode),
               let rejected = try? CloudModelStreamJSON.mcpObject(from: output),
               rejected["status"] == .string("work_rejected"),
               progress.requestRepair("collaboration_work_lineage") { madeProgress = true }
            continue
          }
          if AgentCollaborationSourceAccess.matches(tool: outcome.call.name, input: arguments) {
            let key = progress.semanticKey(toolName: outcome.call.name, arguments: arguments)
            sourceAccessResults[key] = output
            if let page = try? CloudModelStreamJSON.mcpObject(from: output), page["status"] == .string("returned"),
               visitedSourceAccessPages.insert(key).inserted { madeProgress = true }
            continue
          }
          if progress.record(toolName: outcome.call.name, arguments: arguments, output: output) {
            newResearchEvidence = research.observe(tool: outcome.call.name, output: output) || newResearchEvidence
            madeProgress = true
            if AgentCollaborationCandidateRecall.isHistoryCall(outcome.call.name, arguments) { continue }
            if outcome.call.name.lowercased() != CloudImageAnnotationPlan.toolName &&
                !CloudWebToolLoopProgress.isNonEvidenceRecall(toolName: outcome.call.name, arguments: arguments) {
              evidenceResults.append((outcome.call.name, output))
            }
          }
        }
        let results = parsedCalls.compactMap { item -> (AssembledToolCall, String)? in
          if AgentCollaborationWorkflowCheck.isCall(item.0.name, item.1) {
            let key = progress.semanticKey(toolName: item.0.name, arguments: item.1)
            return workflowCheckResults[key].map { (item.0, $0) }
          }
          let (call, arguments) = item
          if call.name == publishName, let output = publicationResults[call.callId] { return (call, output) }
          if AgentCollaborationSourceAccess.matches(tool: call.name, input: arguments) {
            let key = progress.semanticKey(toolName: call.name, arguments: arguments)
            return sourceAccessResults[key].map { (call, $0) }
          }
          guard let output = progress.cached(toolName: call.name, arguments: arguments) else { return nil }
          CloudImageAnnotationSession.selectResult(output, requestId: requestId)
          return (call, output)
        }

        let rawEvidence = evidenceResults.map(\.1)
        let projectedEvidence = evidencePromptLedger.project(rawEvidence)
        var projectionByOriginal: [String: String] = [:]
        for output in workflowCheckResults.values { projectionByOriginal[output] = output }
        for (original, projection) in zip(rawEvidence, projectedEvidence) {
          projectionByOriginal[original] = projection
        }
        let promptResults = results.map { call, output in
          if let arguments = try? CloudModelStreamJSON.mcpObject(from: call.argumentsJson),
             AgentCollaborationCandidateRecall.isHistoryCall(call.name, arguments) { return (call, output) }
          if call.name == publishName { return (call, output) }
          if let arguments = try? CloudModelStreamJSON.mcpObject(from: call.argumentsJson),
             CloudWebToolLoopProgress.isNonEvidenceRecall(toolName: call.name, arguments: arguments) {
            return (call, output)
          }
          if let arguments = try? CloudModelStreamJSON.mcpObject(from: call.argumentsJson),
             AgentCollaborationSourceAccess.matches(tool: call.name, input: arguments) {
            return (call, output)
          }
          return (call, projectionByOriginal[output] ?? evidencePromptLedger.project(output))
        }
        if usesInlineProtocol {
          prepared.appendInlineToolResults(rawRoundText, results: promptResults)
        } else {
          try prepared.appendToolResults(promptResults)
        }
        if retrievalBatch {
          research.finishRetrievalBatch(madeProgress: newResearchEvidence)
          if research.stopReason == nil { prepared.appendResearchGuidance(research.guidance()) }
        } else if !madeProgress {
          progress.requestFinalization()
        }
      }
    } catch is CancellationError {
      await cancel(requestId: requestId, reason: .userStop)
    } catch {
      publishPreview("", at: elapsedMillis())
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

  private func finishEvidenceOnly(_ evidence: [(String, String)], requestId: String, sequence: Int64,
    ticket: AgentDisclosureTicket, continuation: AsyncThrowingStream<ModelStreamEvent, Error>.Continuation) {
    let now = elapsedMillis()
    let fallback = CloudWebGrounding.evidenceFallback(results: evidence) +
      CloudImageAnnotationSession.artifactSuffix(requestId: requestId)
    continuation.yield(.textDelta(.init(requestId: requestId, sequence: sequence, text: fallback, receivedAtElapsedMs: now)))
    AgentDataDisclosureLedger.update(store: disclosureStore, ticket: ticket, status: .sent)
    continuation.yield(.completed(.init(requestId: requestId, finishReason: "evidence_only", completedAtElapsedMs: now)))
    continuation.finish()
  }

  private func beginCollaborationAudit(scope: AgentCollaborationToolEvidenceScope?, round: Int,
    request: ModelStreamRequest, route: AgentCollaborationModelAdmission.Route,
    contact: GalaxySSIContact, store: GalaxySSIStore) async throws -> AgentCollaborationModelAdmission? {
    guard let scope else { return nil }
    let candidate = AgentCollaborationModelAdmission(id: UUID(), scope: scope, round: round,
      provider: request.provider,
      requestedModel: route == .streaming ? (try? CloudModelStreamJSON.object(from: request.bodyJson))?["model"] as? String : nil,
      startedAtMillis: AgentControlPlaneClock.nowMillis(), route: route)
    return try await MainActor.run {
      guard let session = store.agentSession(id: scope.conversationId), session.id == scope.conversationId,
            let roster = session.collaborationRoster, let member = scope.rosterMember(in: roster),
            member.resourceId == contact.id, (member.modelId.isBlank || member.modelId == contact.selectedCloudModel?.id),
            session.mergedIntoConversationId.isBlank,
            !session.privateMode, !session.trackingPaused,
            (try? AgentTeamExecutionHistoryStore.shared.admitCollaborationModelCall(candidate)) != nil else {
        throw GalaxySSIError.invalidPayload(GalaxySSILocalization.string("galaxyssi.collaboration.member_binding_invalid",
          fallback: "A collaboration member or its assigned model changed. Check the group settings and try again.",
          language: store.languagePolicy.interfaceLanguage))
      }
      return candidate
    }
  }

  private func emitLegacyConversation(
    sender: CloudConversationLegacySending,
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
      let text = try await sender.send(contact: contact, store: store, turns: turns, images: images)
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

  static func scopedCollaborationRecall(_ input: AgentMcpJSONObject, scope: AgentCollaborationToolEvidenceScope,
                                        allowsResearch: Bool, resourceID: String, session: AgentConversation?,
                                        history: AgentTeamExecutionHistoryStore) -> AgentMcpJSONObject? {
    guard allowsResearch || ["goal", "dependency", "acceptance_record", "native_evidence",
      "desktop_evidence", "desktop_evidence_list"].contains(input.string("mode")),
          let session, session.id == scope.conversationId,
          let roster = session.collaborationRoster,
          scope.rosterMember(in: roster)?.resourceId == resourceID,
          session.mergedIntoConversationId.isBlank,
          !session.privateMode, !session.trackingPaused else { return nil }
    return try? history.recallCollaborationOriginal(input, scope: scope)
  }

  private func executeToolCalls(
    _ calls: [AssembledToolCall],
    context: CloudConversationToolExecutionContext,
    onObservation: ((AssembledToolCall, String) async -> Void)? = nil,
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
          if let output = outcome.output { await onObservation?(outcome.call, output) }
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
      retryable: CloudResearchRuntimeBudget.canRecover(error),
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
