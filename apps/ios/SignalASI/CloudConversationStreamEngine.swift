import Foundation

protocol CloudConversationLegacySending {
  func send(contact: SignalASIContact, store: SignalASIStore, turns: [ChatMessage]) async throws -> String
}

extension CloudModelClient: CloudConversationLegacySending {}

final class CloudConversationStreamEngine: CloudModelStreamClient {
  private let modelClient: CloudModelClient
  private let streamClient: CloudModelStreamClient
  private let legacySender: CloudConversationLegacySending
  private let disclosureStore: AgentDataDisclosureStore
  private let elapsedMillis: () -> Int64
  private let lock = NSLock()
  private var activeRoundIds: [String: String] = [:]

  init(
    modelClient: CloudModelClient = CloudModelClient(),
    streamClient: CloudModelStreamClient = URLSessionCloudModelStreamClient(),
    legacySender: CloudConversationLegacySending? = nil,
    disclosureStore: AgentDataDisclosureStore = FileAgentDataDisclosureStore(
      fileURL: AgentDataDisclosureStorePaths.ledgerURL()
    ),
    elapsedMillis: @escaping () -> Int64 = CloudConversationStreamEngine.defaultElapsedMillis
  ) {
    self.modelClient = modelClient
    self.streamClient = streamClient
    self.legacySender = legacySender ?? modelClient
    self.disclosureStore = disclosureStore
    self.elapsedMillis = elapsedMillis
  }

  func streamConversation(
    contact: SignalASIContact,
    store: SignalASIStore,
    turns: [ChatMessage],
    requestId: String = UUID().uuidString
  ) -> AsyncThrowingStream<ModelStreamEvent, Error> {
    let conversationRequestId = Self.normalizedRequestId(requestId)
    return AsyncThrowingStream { continuation in
      let worker = Task {
        await runConversation(
          contact: contact,
          store: store,
          turns: turns,
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
    contact: SignalASIContact,
    store: SignalASIStore,
    turns: [ChatMessage],
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
    var roundCompleted = false
    var lastFinishReason: String?
    var roundFailure: ModelStreamFailed?
    let roundId = "\(requestId):r0"

    do {
      var request = try await modelClient.prepareConversationStreamRequest(
        contact: contact,
        store: store,
        turns: turns,
        requestId: requestId
      )
      request.requestId = roundId
      setActiveRound(roundId, for: requestId)

      for try await event in streamClient.stream(request) {
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
          emittedText = emittedText || !value.text.isEmpty
          emittedSequence += 1
          continuation.yield(
            .textDelta(
              ModelStreamTextDelta(
                requestId: requestId,
                sequence: emittedSequence,
                text: value.text,
                receivedAtElapsedMs: value.receivedAtElapsedMs
              )
            )
          )

        case .toolCallDelta(let value):
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
    contact: SignalASIContact,
    store: SignalASIStore,
    turns: [ChatMessage],
    requestId: String,
    sequence: inout Int64,
    ticket: AgentDisclosureTicket,
    continuation: AsyncThrowingStream<ModelStreamEvent, Error>.Continuation
  ) async {
    do {
      let text = try await legacySender.send(contact: contact, store: store, turns: turns)
      let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cleanText.isEmpty else {
        throw SignalASIError.unsupportedResponse
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

  private static func defaultElapsedMillis() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }
}
