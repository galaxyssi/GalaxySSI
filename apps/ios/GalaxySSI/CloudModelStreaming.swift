import Foundation

struct AgentCloudDispatchIdentity: Hashable {
  var sourceMessageId: String
  var contactId: String
  var conversationId: String
  var turnId: String
  var taskId: String
  var actionId: String
}

final class AgentCloudDispatchLease {
  private enum State { case active, completed, cancelled }
  private let lock = NSLock()
  private var state: State = .active
  private var cancellation: (() -> Void)?

  var isCancelled: Bool { locked { state == .cancelled } }

  func bindCancellation(_ cancellation: @escaping () -> Void) {
    let cancelNow = locked { () -> Bool in
      self.cancellation = cancellation
      return state == .cancelled
    }
    if cancelNow { cancellation() }
  }

  @discardableResult
  func cancel() -> Bool {
    let outcome = locked { () -> (Bool, (() -> Void)?) in
      guard state == .active else { return (false, nil) }
      state = .cancelled
      return (true, cancellation)
    }
    outcome.1?()
    return outcome.0
  }

  func claimCompletion() -> Bool {
    locked {
      guard state == .active else { return false }
      state = .completed
      cancellation = nil
      return true
    }
  }

  func checkActive() throws {
    if isCancelled { throw CancellationError() }
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}

final class AgentCloudDispatchRegistry {
  static let shared = AgentCloudDispatchRegistry()
  private let lock = NSLock()
  private var active: [AgentCloudDispatchIdentity: AgentCloudDispatchLease] = [:]

  func register(_ identity: AgentCloudDispatchIdentity) -> AgentCloudDispatchLease? {
    locked {
      guard active[identity] == nil else { return nil }
      let lease = AgentCloudDispatchLease()
      active[identity] = lease
      return lease
    }
  }

  @discardableResult
  func cancel(_ identity: AgentCloudDispatchIdentity) -> Bool {
    locked { active[identity] }?.cancel() ?? false
  }

  @discardableResult
  func cancel(taskId: String, conversationId: String = "") -> Int {
    let normalizedTask = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedConversation = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedTask.isEmpty else { return 0 }
    let leases = locked {
      active.filter {
        $0.key.taskId == normalizedTask &&
          (normalizedConversation.isEmpty || $0.key.conversationId == normalizedConversation)
      }.map(\.value)
    }
    return leases.reduce(into: 0) { count, lease in
      if lease.cancel() { count += 1 }
    }
  }

  func release(_ identity: AgentCloudDispatchIdentity, lease: AgentCloudDispatchLease) {
    locked {
      if active[identity] === lease { active.removeValue(forKey: identity) }
    }
  }

  var activeCount: Int { locked { active.count } }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}

enum ModelStreamProvider: String, Codable, Equatable {
  case openAICompatible = "OPENAI_COMPATIBLE"
  case anthropic = "ANTHROPIC"
  case gemini = "GEMINI"
}

enum ModelStreamTransport: String, Codable, Equatable {
  case sse = "SSE"
  case jsonLines = "JSON_LINES"
  case completeJSON = "COMPLETE_JSON"
}

enum ModelStreamCancelReason: String, Codable, Equatable {
  case userStop = "USER_STOP"
  case newRequest = "NEW_REQUEST"
  case sessionChanged = "SESSION_CHANGED"
  case voiceBargeIn = "VOICE_BARGE_IN"
  case appDestroyed = "APP_DESTROYED"
}

struct ModelStreamRequest: Codable, Equatable {
  var requestId: String
  var provider: ModelStreamProvider
  var endpoint: String
  var headers: [String: String]
  var bodyJson: String
  var transport: ModelStreamTransport
  var connectTimeoutMs: Int64
  var readTimeoutMs: Int64

  init(
    requestId: String,
    provider: ModelStreamProvider,
    endpoint: String,
    headers: [String: String],
    bodyJson: String,
    transport: ModelStreamTransport = .sse,
    connectTimeoutMs: Int64 = 20_000,
    readTimeoutMs: Int64 = 300_000
  ) {
    let cleanRequestId = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
    precondition(!cleanRequestId.isEmpty, "Model stream request id must not be blank")
    precondition(Self.endpointAllowed(endpoint), "Model stream endpoint must be HTTPS or loopback HTTP")
    precondition(!bodyJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Model stream body must not be blank")
    precondition((1_000...120_000).contains(connectTimeoutMs), "Model stream connect timeout is invalid")
    precondition((10_000...900_000).contains(readTimeoutMs), "Model stream read timeout is invalid")
    self.requestId = cleanRequestId
    self.provider = provider
    self.endpoint = endpoint
    self.headers = headers
    self.bodyJson = bodyJson
    self.transport = transport
    self.connectTimeoutMs = connectTimeoutMs
    self.readTimeoutMs = readTimeoutMs
  }

  private static func endpointAllowed(_ endpoint: String) -> Bool {
    let lower = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return lower.hasPrefix("https://") ||
      lower.hasPrefix("http://127.0.0.1") ||
      lower.hasPrefix("http://localhost")
  }
}

enum ToolCallArgumentsMode: String, Codable, Equatable {
  case delta
  case snapshot
}

struct ToolCallPayload: Codable, Equatable {
  var callId: String
  var index: Int
  var nameDelta: String
  var argumentsDelta: String
  var argumentsMode: ToolCallArgumentsMode

  private enum CodingKeys: String, CodingKey {
    case callId
    case index
    case nameDelta
    case argumentsDelta
    case argumentsMode
  }

  init(
    callId: String,
    index: Int,
    nameDelta: String = "",
    argumentsDelta: String = "",
    argumentsMode: ToolCallArgumentsMode = .delta
  ) {
    self.callId = callId
    self.index = index
    self.nameDelta = nameDelta
    self.argumentsDelta = argumentsDelta
    self.argumentsMode = argumentsMode
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    callId = try container.decode(String.self, forKey: .callId)
    index = try container.decode(Int.self, forKey: .index)
    nameDelta = try container.decodeIfPresent(String.self, forKey: .nameDelta) ?? ""
    argumentsDelta = try container.decodeIfPresent(String.self, forKey: .argumentsDelta) ?? ""
    argumentsMode = try container.decodeIfPresent(ToolCallArgumentsMode.self, forKey: .argumentsMode) ?? .delta
  }
}

struct ModelUsage: Codable, Equatable {
  var inputTokens: Int64 = 0
  var outputTokens: Int64 = 0
  var cachedInputTokens: Int64 = 0
}

struct ModelStreamError: Codable, Equatable {
  var code: String
  var message: String
  var httpStatus: Int?
  var retryable: Bool
  var partialResponse: Bool

  init(
    code: String,
    message: String,
    httpStatus: Int? = nil,
    retryable: Bool = false,
    partialResponse: Bool = false
  ) {
    self.code = code
    self.message = message
    self.httpStatus = httpStatus
    self.retryable = retryable
    self.partialResponse = partialResponse
  }
}

struct ModelStreamConnected: Codable, Equatable {
  var requestId: String
  var httpStatus: Int
  var connectedAtElapsedMs: Int64
}

struct ModelStreamTextDelta: Codable, Equatable {
  var requestId: String
  var sequence: Int64
  var text: String
  var receivedAtElapsedMs: Int64
}

struct ModelStreamCitationPreview: Codable, Equatable {
  var requestId: String
  var text: String
  var receivedAtElapsedMs: Int64
}

struct ModelStreamToolCallDelta: Codable, Equatable {
  var requestId: String
  var sequence: Int64
  var payload: ToolCallPayload
}

struct ModelStreamUsage: Codable, Equatable {
  var requestId: String
  var usage: ModelUsage
}

struct ModelStreamCompleted: Codable, Equatable {
  var requestId: String
  var finishReason: String?
  var completedAtElapsedMs: Int64
}

struct ModelStreamFailed: Codable, Equatable {
  var requestId: String
  var error: ModelStreamError
}

enum ModelStreamEvent: Equatable {
  case connected(ModelStreamConnected)
  case textDelta(ModelStreamTextDelta)
  case citationPreview(ModelStreamCitationPreview)
  case toolCallDelta(ModelStreamToolCallDelta)
  case usage(ModelStreamUsage)
  case completed(ModelStreamCompleted)
  case failed(ModelStreamFailed)

  var requestId: String {
    switch self {
    case .connected(let event):
      return event.requestId
    case .textDelta(let event):
      return event.requestId
    case .citationPreview(let event):
      return event.requestId
    case .toolCallDelta(let event):
      return event.requestId
    case .usage(let event):
      return event.requestId
    case .completed(let event):
      return event.requestId
    case .failed(let event):
      return event.requestId
    }
  }
}

struct ModelStreamTiming: Equatable {
  var requestId: String
  var milliseconds: [String: Int64]
}

final class ModelStreamTimingTracker {
  private let requestId: String
  private let startedAt: Int64
  private let now: () -> Int64
  private var marks: [String: Int64] = [:]

  init(requestId: String, now: @escaping () -> Int64) {
    self.requestId = requestId
    self.now = now
    self.startedAt = now()
  }

  func mark(_ name: String) {
    if marks[name] == nil { marks[name] = now() }
  }

  func snapshot() -> ModelStreamTiming {
    func since(_ name: String) -> Int64 {
      marks[name].map { max(0, $0 - startedAt) } ?? -1
    }
    func between(_ start: String, _ end: String) -> Int64 {
      guard let from = marks[start], let to = marks[end] else { return -1 }
      return max(0, to - from)
    }
    return ModelStreamTiming(requestId: requestId, milliseconds: [
      "local_queue_ms": since("reader_started"),
      "request_write_ms": between("request_write_start", "request_write_end"),
      "response_headers_wait_ms": between("request_write_end", "response_headers"),
      "headers_to_first_text_ms": between("response_headers", "first_text"),
      "first_frame_ms": since("first_frame"),
      "first_text_ms": since("first_text"),
      "first_tool_ms": since("first_tool"),
      "stream_tail_ms": marks["first_text"].map { max(0, now() - $0) } ?? -1,
      "total_ms": max(0, now() - startedAt)
    ])
  }
}

protocol CloudModelStreamClient {
  func stream(_ request: ModelStreamRequest) -> AsyncThrowingStream<ModelStreamEvent, Error>
  func cancel(requestId: String, reason: ModelStreamCancelReason) async
}

struct AssembledToolCall: Codable, Equatable {
  var callId: String
  var index: Int
  var name: String
  var argumentsJson: String
}

final class ToolCallDeltaAssembler {
  private final class MutableCall {
    var callId: String
    let index: Int
    let name = NSMutableString()
    let arguments = NSMutableString()

    init(callId: String, index: Int) {
      self.callId = callId
      self.index = index
    }
  }

  private let lock = NSLock()
  private var calls: [Int: MutableCall] = [:]

  func accept(_ payload: ToolCallPayload) {
    locked {
      let call = calls[payload.index] ?? {
        let created = MutableCall(callId: payload.callId, index: payload.index)
        calls[payload.index] = created
        return created
      }()
      if call.callId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
         !payload.callId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        call.callId = payload.callId
      }
      appendName(target: call.name, delta: payload.nameDelta)
      appendArguments(target: call.arguments, value: payload.argumentsDelta, mode: payload.argumentsMode)
    }
  }

  func completedCalls() -> [AssembledToolCall] {
    locked {
      calls.values.compactMap { call in
        let name = (call.name as String).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let arguments = (call.arguments as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return AssembledToolCall(
          callId: call.callId.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("tool-\(call.index)"),
          index: call.index,
          name: name,
          argumentsJson: arguments.ifBlank("{}")
        )
      }
      .sorted { $0.index < $1.index }
    }
  }

  func clear() {
    locked {
      calls.removeAll()
    }
  }

  private func appendName(target: NSMutableString, delta: String) {
    guard !delta.isEmpty else { return }
    let current = target as String
    if current.isEmpty {
      target.append(delta)
    } else if delta == current || current.hasSuffix(delta) {
      return
    } else if delta.hasPrefix(current) {
      target.setString(delta)
    } else {
      target.append(delta)
    }
  }

  private func appendArguments(
    target: NSMutableString,
    value: String,
    mode: ToolCallArgumentsMode
  ) {
    guard !value.isEmpty else { return }
    if mode == .snapshot {
      target.setString(value)
    } else {
      appendName(target: target, delta: value)
    }
  }

  private func locked<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }
}

struct ModelStreamUiUpdate: Equatable {
  var text: String
  var firstDelta: Bool
  var complete: Bool
}

final class ModelStreamUiMerger {
  private let minUpdateIntervalMs: Int64
  private let maxCharacters: Int
  private let lock = NSLock()
  private var text = ""
  private var highestSequence: Int64 = 0
  private var lastPublishedAtMs = Int64.min
  private var publishedLength = 0

  init(minUpdateIntervalMs: Int64 = 80, maxCharacters: Int = 200_000) {
    precondition((16...1_000).contains(minUpdateIntervalMs), "Model stream UI interval is invalid")
    precondition(maxCharacters >= 4_096, "Model stream UI cap is too small")
    self.minUpdateIntervalMs = minUpdateIntervalMs
    self.maxCharacters = maxCharacters
  }

  func offer(sequence: Int64, delta: String, nowMs: Int64) -> ModelStreamUiUpdate? {
    locked {
      guard sequence > highestSequence, !delta.isEmpty else { return nil }
      highestSequence = sequence
      if text.count < maxCharacters {
        text.append(String(delta.prefix(maxCharacters - text.count)))
      }
      let first = publishedLength == 0 && !text.isEmpty
      if !first && nowMs - lastPublishedAtMs < minUpdateIntervalMs {
        return nil
      }
      return publish(nowMs: nowMs, first: first, complete: false)
    }
  }

  func flush(nowMs: Int64, complete: Bool = false) -> ModelStreamUiUpdate? {
    locked {
      if text.count == publishedLength, !complete {
        return nil
      }
      return publish(nowMs: nowMs, first: publishedLength == 0 && !text.isEmpty, complete: complete)
    }
  }

  func snapshot() -> String {
    locked { text }
  }

  private func publish(nowMs: Int64, first: Bool, complete: Bool) -> ModelStreamUiUpdate {
    publishedLength = text.count
    lastPublishedAtMs = nowMs
    return ModelStreamUiUpdate(text: text, firstDelta: first, complete: complete)
  }

  private func locked<T>(_ action: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return action()
  }
}
