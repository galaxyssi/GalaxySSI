import Foundation

final class URLSessionCloudModelStreamClient: CloudModelStreamClient {
  private let session: URLSession
  private let elapsedMillis: () -> Int64
  private let lock = NSLock()
  private var activeTasks: [String: Task<Void, Never>] = [:]
  private var cancelReasons: [String: ModelStreamCancelReason] = [:]

  init(
    session: URLSession = .shared,
    elapsedMillis: @escaping () -> Int64 = URLSessionCloudModelStreamClient.defaultElapsedMillis
  ) {
    self.session = session
    self.elapsedMillis = elapsedMillis
  }

  func stream(_ request: ModelStreamRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let worker = Task { [weak self] in
        guard let self else {
          continuation.finish()
          return
        }
        await self.run(request, continuation: continuation)
      }
      if !register(task: worker, requestId: request.requestId) {
        worker.cancel()
        continuation.yield(
          .failed(
            ModelStreamFailed(
              requestId: request.requestId,
              error: ModelStreamError(
                code: "DUPLICATE_REQUEST_ID",
                message: "A stream with this request ID is already active"
              )
            )
          )
        )
        continuation.finish()
        return
      }
      continuation.onTermination = { [weak self] _ in
        Task {
          await self?.cancel(requestId: request.requestId, reason: .sessionChanged)
        }
      }
    }
  }

  func cancel(requestId: String, reason: ModelStreamCancelReason) async {
    let task = locked { () -> Task<Void, Never>? in
      guard let task = activeTasks.removeValue(forKey: requestId) else {
        return nil
      }
      cancelReasons[requestId] = reason
      return task
    }
    task?.cancel()
  }

  func activeRequestIds() -> Set<String> {
    locked { Set(activeTasks.keys) }
  }

  private func run(
    _ request: ModelStreamRequest,
    continuation: AsyncThrowingStream<ModelStreamEvent, Error>.Continuation
  ) async {
    let state = ModelStreamEmissionState()
    do {
      let urlRequest = try Self.urlRequest(for: request)
      let adapter = ModelStreamProviderAdapters.create(provider: request.provider)
      let (bytes, response) = try await session.bytes(for: urlRequest)
      try throwIfCancelled(request.requestId)
      guard let http = response as? HTTPURLResponse else {
        yieldFailed(
          requestId: request.requestId,
          error: ModelStreamError(code: "INVALID_RESPONSE", message: "Provider did not return an HTTP response"),
          continuation: continuation
        )
        return
      }
      continuation.yield(
        .connected(
          ModelStreamConnected(
            requestId: request.requestId,
            httpStatus: http.statusCode,
            connectedAtElapsedMs: elapsedMillis()
          )
        )
      )
      guard (200...299).contains(http.statusCode) else {
        let body = try await collectBody(bytes)
        yieldFailed(
          requestId: request.requestId,
          error: ModelStreamError(
            code: Self.httpErrorCode(status: http.statusCode, body: body),
            message: Self.providerErrorMessage(body).ifBlank("HTTP \(http.statusCode)"),
            httpStatus: http.statusCode,
            retryable: http.statusCode == 408 || http.statusCode == 429 || http.statusCode >= 500
          ),
          continuation: continuation
        )
        return
      }

      if request.transport == .completeJSON {
        let body = try await collectBody(bytes)
        _ = emitParsedFrame(
          requestId: request.requestId,
          frame: adapter.parseCompleteJSON(data: body),
          state: state,
          continuation: continuation
        )
      } else {
        let accumulator = ModelStreamFrameAccumulator(transport: request.transport)
        for try await line in bytes.lines {
          try throwIfCancelled(request.requestId)
          for frame in accumulator.accept(line: line) {
            if emitParsedFrame(
              requestId: request.requestId,
              frame: adapter.parse(data: frame.data, eventName: frame.eventName),
              state: state,
              continuation: continuation
            ) {
              break
            }
          }
          if state.sawTerminal { break }
        }
        if !state.sawTerminal, let finalFrame = accumulator.finish() {
          _ = emitParsedFrame(
            requestId: request.requestId,
            frame: adapter.parse(data: finalFrame.data, eventName: finalFrame.eventName),
            state: state,
            continuation: continuation
          )
        }
      }
      if !state.sawTerminal {
        try throwIfCancelled(request.requestId)
        if let finishReason = state.finishReason?.nonBlankForStream {
          continuation.yield(
            .completed(
              ModelStreamCompleted(
                requestId: request.requestId,
                finishReason: finishReason,
                completedAtElapsedMs: elapsedMillis()
              )
            )
          )
        } else {
          yieldFailed(
            requestId: request.requestId,
            error: ModelStreamError(
              code: "STREAM_INTERRUPTED",
              message: "The provider stream ended before a completion event",
              retryable: true,
              partialResponse: state.emittedPayload
            ),
            continuation: continuation
          )
        }
      }
    } catch {
      let cancelledBy = cancelReason(request.requestId)
      yieldFailed(
        requestId: request.requestId,
        error: ModelStreamError(
          code: cancelledBy == nil ? "NETWORK_ERROR" : "CANCELLED",
          message: cancelledBy?.rawValue ?? error.localizedDescription.ifBlank("Network stream failed"),
          retryable: cancelledBy == nil,
          partialResponse: state.emittedPayload
        ),
        continuation: continuation
      )
    }
    removeActive(request.requestId)
    continuation.finish()
  }

  private func emitParsedFrame(
    requestId: String,
    frame: ParsedModelStreamFrame,
    state: ModelStreamEmissionState,
    continuation: AsyncThrowingStream<ModelStreamEvent, Error>.Continuation
  ) -> Bool {
    if let providerSequence = frame.providerSequence {
      if let last = state.lastProviderSequence, providerSequence <= last {
        return false
      }
      state.lastProviderSequence = providerSequence
    }
    if let error = frame.error {
      continuation.yield(
        .failed(
          ModelStreamFailed(
            requestId: requestId,
            error: ModelStreamError(
              code: error.code,
              message: error.message,
              httpStatus: error.httpStatus,
              retryable: error.retryable,
              partialResponse: state.emittedPayload || error.partialResponse
            )
          )
        )
      )
      state.sawTerminal = true
      return true
    }
    for delta in frame.textDeltas where !delta.isEmpty {
      state.emittedPayload = true
      continuation.yield(
        .textDelta(
          ModelStreamTextDelta(
            requestId: requestId,
            sequence: state.nextSequence(),
            text: delta,
            receivedAtElapsedMs: elapsedMillis()
          )
        )
      )
    }
    for payload in frame.toolDeltas {
      state.emittedPayload = true
      continuation.yield(
        .toolCallDelta(
          ModelStreamToolCallDelta(
            requestId: requestId,
            sequence: state.nextSequence(),
            payload: payload
          )
        )
      )
    }
    if let usage = frame.usage {
      continuation.yield(.usage(ModelStreamUsage(requestId: requestId, usage: usage)))
    }
    if let finishReason = frame.finishReason?.nonBlankForStream {
      state.finishReason = finishReason
    }
    guard frame.terminal else { return false }
    state.sawTerminal = true
    continuation.yield(
      .completed(
        ModelStreamCompleted(
          requestId: requestId,
          finishReason: state.finishReason,
          completedAtElapsedMs: elapsedMillis()
        )
      )
    )
    return true
  }

  private func yieldFailed(
    requestId: String,
    error: ModelStreamError,
    continuation: AsyncThrowingStream<ModelStreamEvent, Error>.Continuation
  ) {
    continuation.yield(.failed(ModelStreamFailed(requestId: requestId, error: error)))
  }

  private static func urlRequest(for request: ModelStreamRequest) throws -> URLRequest {
    guard let url = URL(string: request.endpoint) else {
      throw GalaxySSIError.invalidPayload("Cloud stream endpoint is not a URL.")
    }
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.timeoutInterval = TimeInterval(max(request.connectTimeoutMs, request.readTimeoutMs)) / 1_000
    urlRequest.httpBody = Data(request.bodyJson.utf8)
    urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue(
      request.transport == .completeJSON ? "application/json" : "text/event-stream",
      forHTTPHeaderField: "Accept"
    )
    for (name, value) in request.headers {
      urlRequest.setValue(value, forHTTPHeaderField: name)
    }
    return urlRequest
  }

  private func collectBody(_ bytes: URLSession.AsyncBytes) async throws -> String {
    var data = Data()
    for try await byte in bytes {
      data.append(byte)
    }
    return String(data: data, encoding: .utf8) ?? ""
  }

  private func register(task: Task<Void, Never>, requestId: String) -> Bool {
    locked {
      guard activeTasks[requestId] == nil else { return false }
      activeTasks[requestId] = task
      cancelReasons.removeValue(forKey: requestId)
      return true
    }
  }

  private func removeActive(_ requestId: String) {
    locked {
      activeTasks.removeValue(forKey: requestId)
      cancelReasons.removeValue(forKey: requestId)
    }
  }

  private func cancelReason(_ requestId: String) -> ModelStreamCancelReason? {
    locked { cancelReasons[requestId] }
  }

  private func throwIfCancelled(_ requestId: String) throws {
    if Task.isCancelled || cancelReason(requestId) != nil {
      throw CancellationError()
    }
  }

  private func locked<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }

  private static func httpErrorCode(status: Int, body: String) -> String {
    let lower = body.lowercased()
    if [404, 405, 415, 501].contains(status) || (lower.contains("stream") && lower.contains("support")) {
      return "STREAM_UNSUPPORTED"
    }
    return "HTTP_\(status)"
  }

  private static func providerErrorMessage(_ body: String) -> String {
    guard let data = body.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return body.prefixTextForStream(1_000)
    }
    let error = json["error"] as? [String: Any] ?? json
    return (error["message"] as? String)?.ifBlank(body.prefixTextForStream(1_000)) ??
      body.prefixTextForStream(1_000)
  }

  private static func defaultElapsedMillis() -> Int64 {
    Int64(ProcessInfo.processInfo.systemUptime * 1_000)
  }
}

final class ModelStreamEmissionState {
  private var sequence: Int64 = 0
  var emittedPayload = false
  var sawTerminal = false
  var finishReason: String?
  var lastProviderSequence: Int64?

  func nextSequence() -> Int64 {
    sequence += 1
    return sequence
  }
}

struct ModelStreamFrame: Equatable {
  var eventName: String?
  var data: String
}

final class ModelStreamFrameAccumulator {
  private let transport: ModelStreamTransport
  private var eventName: String?
  private var dataLines: [String] = []

  init(transport: ModelStreamTransport) {
    self.transport = transport
  }

  func accept(line: String) -> [ModelStreamFrame] {
    switch transport {
    case .jsonLines:
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? [] : [ModelStreamFrame(eventName: nil, data: trimmed)]
    case .sse:
      return acceptSSE(line)
    case .completeJSON:
      return []
    }
  }

  func finish() -> ModelStreamFrame? {
    guard transport == .sse, !dataLines.isEmpty else { return nil }
    let frame = ModelStreamFrame(eventName: eventName, data: dataLines.joined(separator: "\n"))
    eventName = nil
    dataLines.removeAll()
    return frame
  }

  private func acceptSSE(_ line: String) -> [ModelStreamFrame] {
    if line.isEmpty {
      guard let frame = finish() else {
        eventName = nil
        return []
      }
      return [frame]
    }
    if line.hasPrefix(":") {
      return []
    }
    if line.hasPrefix("event:") {
      eventName = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
    } else if line.hasPrefix("data:") {
      dataLines.append(String(line.dropFirst("data:".count)).trimmingCharacters(in: CharacterSet(charactersIn: " ")))
    } else if line.first == "{" || line.first == "[" {
      dataLines.append(line)
    }
    return []
  }
}

private extension String {
  var nonBlankForStream: String? {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
  }

  func prefixTextForStream(_ limit: Int) -> String {
    String(prefix(max(0, limit)))
  }
}
