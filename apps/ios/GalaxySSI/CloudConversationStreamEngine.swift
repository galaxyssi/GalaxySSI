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
}

final class CloudConversationStreamEngine: CloudModelStreamClient {
  private static let maxParallelToolCalls = 4

  private struct ToolExecutionOutcome {
    var index: Int
    var call: AssembledToolCall
    var output: String?
    var errorMessage: String?
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
    toolExecutor: CloudConversationToolExecuting = CloudWebGroundingToolExecutor(),
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
    let conversationRequestId = Self.normalizedRequestId(requestId)
    return AsyncThrowingStream { continuation in
      let worker = Task {
        await runConversation(
          contact: contact,
          store: store,
          turns: turns,
          images: images,
          requestId: conversationRequestId,
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
    continuation: AsyncThrowingStream<ModelStreamEvent, Error>.Continuation
  ) async {
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
      var evidenceResults: [(String, String)] = []
      let progress = CloudWebToolLoopProgress()
      var round = 0

      while true {
        let currentRound = round
        round += 1
        let roundId = "\(requestId):r\(currentRound)"
        let finalRound = progress.finalizationRequested
        let bufferForCitationVerification = !evidenceResults.isEmpty
        let roundRequest = try prepared.requestForRound(roundId: roundId, finalRound: finalRound)
        let assembler = ToolCallDeltaAssembler()
        let inlineProtocolGuard = InlineToolProtocolStreamGuard()
        var roundCompleted = false
        var roundFailure: ModelStreamFailed?
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
            continuation.yield(.usage(ModelStreamUsage(requestId: requestId, usage: value.usage)))

          case .completed(let value):
            roundCompleted = true
            lastFinishReason = value.finishReason

          case .failed(let value):
            roundFailure = ModelStreamFailed(requestId: requestId, error: value.error)
          }
        }
        setActiveRound(nil, for: requestId)

        if let failure = roundFailure {
          if !emittedText && failure.error.code == "STREAM_UNSUPPORTED" {
            await emitLegacyConversation(
              contact: contact,
              store: store,
              turns: turns,
              images: images,
              requestId: requestId,
              sequence: &emittedSequence,
              ticket: ticket,
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
          guard progress.cached(toolName: call.name, arguments: arguments) == nil else { return nil }
          let key = progress.semanticKey(toolName: call.name, arguments: arguments)
          return freshKeys.insert(key).inserted ? call : nil
        }

        let outcomes = await executeToolCalls(
          preparedCalls,
          context: CloudConversationToolExecutionContext(
            requestId: requestId,
            conversationId: conversationId,
            turnId: turnId
          )
        )
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
        for outcome in outcomes {
          guard let output = outcome.output,
                let arguments = try? CloudModelStreamJSON.mcpObject(from: outcome.call.argumentsJson) else {
            continue
          }
          if progress.record(toolName: outcome.call.name, arguments: arguments, output: output) {
            madeProgress = true
            evidenceResults.append((outcome.call.name, output))
          }
        }
        let results = parsedCalls.compactMap { item -> (AssembledToolCall, String)? in
          let (call, arguments) = item
          guard let output = progress.cached(toolName: call.name, arguments: arguments) else { return nil }
          return (call, output)
        }

        if usesInlineProtocol {
          prepared.appendInlineToolResults(rawRoundText, results: results)
        } else {
          try prepared.appendToolResults(results)
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

  private func emitLegacyConversation(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    turns: [ChatMessage],
    images: [CloudImagePayload],
    requestId: String,
    sequence: inout Int64,
    ticket: AgentDisclosureTicket,
    continuation: AsyncThrowingStream<ModelStreamEvent, Error>.Continuation
  ) async {
    do {
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
    context: CloudConversationToolExecutionContext
  ) async -> [ToolExecutionOutcome] {
    guard !calls.isEmpty else { return [] }

    var outcomes: [ToolExecutionOutcome] = []
    for start in stride(from: 0, to: calls.count, by: Self.maxParallelToolCalls) {
      let end = min(start + Self.maxParallelToolCalls, calls.count)
      let batch = Array(calls[start..<end])
      let batchOutcomes = await withTaskGroup(of: ToolExecutionOutcome.self) { group in
        for (offset, call) in batch.enumerated() {
          group.addTask { [toolExecutor] in
            do {
              let output = try toolExecutor.executeTool(call: call, context: context)
              return ToolExecutionOutcome(
                index: start + offset,
                call: call,
                output: output,
                errorMessage: nil
              )
            } catch {
              return ToolExecutionOutcome(
                index: start + offset,
                call: call,
                output: nil,
                errorMessage: error.localizedDescription.ifBlank(String(describing: error))
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
