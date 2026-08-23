import Foundation

actor VoiceOnlineRealtimeASRSession {
  typealias EventHandler = (VoiceOnlineRealtimeASREvent) -> Void

  private struct QueuedBatch {
    let data: Data
    let sampleCount: Int
  }

  private enum Outbound {
    case audio(QueuedBatch)
    case finish
  }

  private let config: VoiceOnlineRealtimeASRConfig
  private let credentialSource: VoiceOnlineRealtimeASRCredentialSource
  private let eventHandler: EventHandler
  private var credential: VoiceOnlineRealtimeASRCredential?
  private var socket: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var heartbeatTask: Task<Void, Never>?
  private var connected = false
  private var closed = false
  private var terminalEventSent = false
  private var finalSeen = false
  private var finishRequested = false
  private var drainingOutbound = false
  private var socketGeneration = 0
  private var reconnectCount = 0
  private var droppedAudioBatches = 0
  private var sentAudioSamples: Int64 = 0
  private var audioSent = false
  private var highestRevision = -1
  private var lastInputFrameSequence: Int64?
  private var pendingSamples: [Int16] = []
  private var pendingFirstSequence: Int64 = 0
  private var pendingLastSequence: Int64 = 0
  private var pendingFirstCaptureNanos: Int64 = 0
  private var pendingLastCaptureNanos: Int64 = 0
  private var outboundQueue: [Outbound] = []

  init(
    config: VoiceOnlineRealtimeASRConfig,
    credentialSource: VoiceOnlineRealtimeASRCredentialSource = VoiceOnlineRealtimeASRCredentialSource(),
    eventHandler: @escaping EventHandler
  ) {
    self.config = config
    self.credentialSource = credentialSource
    self.eventHandler = eventHandler
  }

  @discardableResult
  func start() async -> Bool {
    guard !closed else { return false }
    guard socket == nil else { return connected }
    do {
      let credential = try await credentialSource.issue(config: config)
      guard !closed else {
        credential.clear()
        return false
      }
      self.credential = credential
      do {
        try await connect(using: credential)
        return true
      } catch {
        return await handleTransportFailure(
          generation: socketGeneration,
          code: "connect_failed",
          message: error.localizedDescription
        )
      }
    } catch {
      fail(code: "connect_failed", message: error.localizedDescription)
      return false
    }
  }

  func push(frame: AudioFrame, sourceSampleRateHz: Int) async {
    guard !closed, !finalSeen, !finishRequested, sourceSampleRateHz > 0 else { return }
    if let credential, credential.expires(within: 1_000) {
      fail(
        code: "credential_expired",
        message: VoiceOnlineRealtimeASRError.credentialExpired.localizedDescription,
        retryable: true,
        fatal: true
      )
      return
    }
    let converted = Self.resampleTo16k(frame.samples, sourceRateHz: sourceSampleRateHz)
    guard !converted.isEmpty else { return }
    if let previous = lastInputFrameSequence,
       frame.sequence != previous + 1,
       !pendingSamples.isEmpty {
      await flushPending()
    }
    lastInputFrameSequence = frame.sequence
    if pendingSamples.isEmpty {
      pendingFirstSequence = frame.sequence
      pendingFirstCaptureNanos = frame.captureTimeNanos
    }
    pendingLastSequence = frame.sequence
    pendingLastCaptureNanos = frame.captureTimeNanos
    pendingSamples.append(contentsOf: converted)
    while pendingSamples.count >= Self.batchSamples {
      let samples = Array(pendingSamples.prefix(Self.batchSamples))
      pendingSamples.removeFirst(Self.batchSamples)
      await enqueue(
        samples: samples,
        firstSequence: pendingFirstSequence,
        lastSequence: pendingLastSequence,
        firstCaptureNanos: pendingFirstCaptureNanos,
        lastCaptureNanos: pendingLastCaptureNanos
      )
      pendingFirstSequence = pendingLastSequence
      pendingFirstCaptureNanos = pendingLastCaptureNanos
    }
  }

  func finishInput() async {
    guard !closed else { return }
    guard !finishRequested else { return }
    finishRequested = true
    await flushPending()
    guard outboundQueue.count < Self.maximumQueuedBatches else {
      fail(
        code: "send_queue_overflow",
        message: "Realtime ASR send queue reached its capacity before input could finish.",
        retryable: false
      )
      return
    }
    outboundQueue.append(.finish)
    await drainOutbound()
  }

  func cancel(reason: String) async {
    guard !closed else { return }
    if let socket, connected,
       let message = try? VoiceOnlineRealtimeASRProtocol.abortMessage(config: config, reason: reason) {
      try? await socket.send(.string(message))
    }
    close(reasonCode: reason.ifBlank("session_cancelled"))
  }

  private func flushPending() async {
    guard !pendingSamples.isEmpty else { return }
    let samples = pendingSamples
    pendingSamples.removeAll(keepingCapacity: false)
    await enqueue(
      samples: samples,
      firstSequence: pendingFirstSequence,
      lastSequence: pendingLastSequence,
      firstCaptureNanos: pendingFirstCaptureNanos,
      lastCaptureNanos: pendingLastCaptureNanos
    )
  }

  private func enqueue(
    samples: [Int16],
    firstSequence: Int64,
    lastSequence: Int64,
    firstCaptureNanos: Int64,
    lastCaptureNanos: Int64
  ) async {
    var batch = VoiceOnlineRealtimeASRAudioBatch(
      firstSequence: firstSequence,
      lastSequence: lastSequence,
      firstCaptureTimeNanos: firstCaptureNanos,
      lastCaptureTimeNanos: lastCaptureNanos,
      samples: samples
    )
    let queued = QueuedBatch(
      data: VoiceOnlineRealtimeASRProtocol.encodeAudio(batch),
      sampleCount: batch.samples.count
    )
    batch.samples = Array(repeating: 0, count: batch.samples.count)
    guard outboundQueue.count < Self.maximumQueuedBatches else {
      droppedAudioBatches += 1
      emitFailure(
        code: "send_queue_overflow",
        message: "Realtime ASR audio queue reached its capacity.",
        retryable: false,
        fatal: false
      )
      return
    }
    outboundQueue.append(.audio(queued))
    await drainOutbound()
  }

  private func connect(using credential: VoiceOnlineRealtimeASRCredential) async throws {
    guard !closed else { throw CancellationError() }
    guard !credential.expires(within: 1_000) else {
      fail(
        code: "credential_expired",
        message: VoiceOnlineRealtimeASRError.credentialExpired.localizedDescription,
        retryable: true,
        fatal: true
      )
      throw VoiceOnlineRealtimeASRError.credentialExpired
    }
    socketGeneration += 1
    let generation = socketGeneration
    var request = URLRequest(url: credential.webSocketURL)
    request.timeoutInterval = Self.connectTimeoutSeconds
    request.setValue(credential.authorizationValue, forHTTPHeaderField: credential.authorizationHeader)
    request.setValue(credential.providerSessionID, forHTTPHeaderField: "X-SignalASI-Session")
    let socket = URLSession.shared.webSocketTask(with: request)
    self.socket = socket
    socket.resume()
    try await socket.send(.string(try VoiceOnlineRealtimeASRProtocol.startMessage(
      config: config,
      credential: credential
    )))
    guard !closed, generation == socketGeneration else {
      socket.cancel(with: .goingAway, reason: nil)
      throw CancellationError()
    }
    connected = true
    eventHandler(.ready(
      provider: credential.providerID,
      providerSessionID: credential.providerSessionID,
      modelProfileID: ""
    ))
    receiveTask = Task { [weak self] in
      await self?.receiveLoop(socket: socket, generation: generation)
    }
    heartbeatTask?.cancel()
    heartbeatTask = Task { [weak self] in
      await self?.heartbeatLoop(socket: socket, generation: generation)
    }
    await drainOutbound()
    guard !closed else { throw CancellationError() }
  }

  private func drainOutbound() async {
    guard !drainingOutbound, connected, !closed else { return }
    drainingOutbound = true
    defer { drainingOutbound = false }
    while !closed, connected, !outboundQueue.isEmpty {
      guard let socket else { return }
      let generation = socketGeneration
      let outbound = outboundQueue[0]
      do {
        switch outbound {
        case .audio(let batch):
          try await socket.send(.data(batch.data))
        case .finish:
          try await socket.send(.string(try VoiceOnlineRealtimeASRProtocol.finishMessage(config: config)))
        }
        guard !closed, connected, generation == socketGeneration, !outboundQueue.isEmpty else {
          return
        }
        outboundQueue.removeFirst()
        if case .audio(let batch) = outbound {
          recordSent(sampleCount: batch.sampleCount)
        }
      } catch {
        let code: String
        switch outboundQueue.first {
        case .some(.finish):
          code = "finish_send_failed"
        default:
          code = "audio_send_failed"
        }
        guard await handleTransportFailure(
          generation: generation,
          code: code,
          message: error.localizedDescription
        ) else { return }
      }
    }
  }

  private func receiveLoop(socket: URLSessionWebSocketTask, generation: Int) async {
    while !Task.isCancelled, !closed, generation == socketGeneration {
      do {
        let message = try await socket.receive()
        guard let credential else { continue }
        switch message {
        case .string(let text):
          guard let event = VoiceOnlineRealtimeASRProtocol.parseEvent(
            text,
            config: config,
            credential: credential
          ) else { continue }
          switch event {
          case .partial(let hypothesis, let stable):
            guard acceptRevision(hypothesis.revision, allowSame: stable) else { continue }
          case .final(let hypothesis):
            guard hypothesis.transcriptId == config.transcriptID, !finalSeen else { continue }
            finalSeen = true
            highestRevision = max(highestRevision, hypothesis.revision)
            eventHandler(event)
            emitMetrics()
            close(reasonCode: "final_received")
            return
          case .failed(let failure) where failure.fatal:
            eventHandler(event)
            close(reasonCode: failure.code)
            return
          case .closed(_, _, let reasonCode):
            eventHandler(event)
            terminalEventSent = true
            close(reasonCode: reasonCode.ifBlank("provider_closed"), emitClosed: false)
            return
          default:
            break
          }
          eventHandler(event)
        case .data:
          emitFailure(
            code: "unexpected_binary_event",
            message: "Realtime ASR provider returned an unexpected binary event.",
            retryable: true,
            fatal: false
          )
          continue
        @unknown default:
          continue
        }
      } catch {
        if !closed, generation == socketGeneration {
          _ = await handleTransportFailure(
            generation: generation,
            code: "network_disconnected",
            message: error.localizedDescription
          )
        }
        return
      }
    }
  }

  private func heartbeatLoop(socket: URLSessionWebSocketTask, generation: Int) async {
    while !Task.isCancelled, !closed, generation == socketGeneration {
      try? await Task.sleep(nanoseconds: 10_000_000_000)
      guard !Task.isCancelled, !closed, generation == socketGeneration,
            let message = try? VoiceOnlineRealtimeASRProtocol.heartbeatMessage(config: config) else {
        continue
      }
      try? await socket.send(.string(message))
    }
  }

  private func handleTransportFailure(
    generation: Int,
    code: String,
    message: String
  ) async -> Bool {
    guard !closed, generation == socketGeneration else { return false }
    var failureCode = code
    var failureMessage = message
    while !closed,
          !audioSent,
          !finishRequested,
          reconnectCount < Self.maximumReconnects,
          let credential,
          !credential.expires(within: 2_000) {
      emitFailure(code: failureCode, message: failureMessage, retryable: true, fatal: false)
      disconnectForReconnect()
      reconnectCount += 1
      let delayMs = min(reconnectCount * 150, 600)
      try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
      guard !Task.isCancelled, !closed else { return false }
      do {
        try await connect(using: credential)
        return true
      } catch {
        failureCode = "reconnect_failed"
        failureMessage = error.localizedDescription
      }
    }
    emitFailure(code: failureCode, message: failureMessage, retryable: false, fatal: false)
    close(reasonCode: failureCode)
    return false
  }

  private func disconnectForReconnect() {
    connected = false
    heartbeatTask?.cancel()
    heartbeatTask = nil
    socket?.cancel(with: .goingAway, reason: nil)
    socket = nil
  }

  private func acceptRevision(_ revision: Int, allowSame: Bool) -> Bool {
    if revision < highestRevision || (!allowSame && revision == highestRevision) {
      return false
    }
    highestRevision = max(highestRevision, revision)
    return true
  }

  private func recordSent(sampleCount: Int) {
    audioSent = true
    sentAudioSamples += Int64(max(0, sampleCount))
  }

  private func emitMetrics() {
    guard let credential else { return }
    eventHandler(.metrics(VoiceOnlineRealtimeASRMetrics(
      providerID: credential.providerID,
      providerSessionID: credential.providerSessionID,
      audioSentMs: sentAudioSamples * 1_000 / Int64(VoiceOnlineRealtimeASRProtocol.sampleRateHz),
      firstPartialLatencyMs: nil,
      finalLatencyMs: nil,
      reconnectCount: reconnectCount,
      droppedAudioBatches: droppedAudioBatches,
      serverTimestampMs: nil
    )))
  }

  private func fail(
    code: String,
    message: String,
    retryable: Bool = true,
    fatal: Bool = false
  ) {
    guard !closed else { return }
    emitFailure(code: code, message: message, retryable: retryable, fatal: fatal)
    close(reasonCode: code)
  }

  private func emitFailure(code: String, message: String, retryable: Bool, fatal: Bool) {
    eventHandler(.failed(VoiceOnlineRealtimeASRFailure(
      code: code,
      message: String(message.prefix(240)),
      retryable: retryable,
      fatal: fatal,
      providerID: credential?.providerID ?? "signalasi_realtime",
      providerSessionID: credential?.providerSessionID ?? "",
      serverTimestampMs: nil
    )))
  }

  private func close(reasonCode: String, emitClosed: Bool = true) {
    guard !closed else { return }
    let providerID = credential?.providerID ?? "signalasi_realtime"
    let providerSessionID = credential?.providerSessionID ?? ""
    closed = true
    connected = false
    socketGeneration += 1
    receiveTask?.cancel()
    heartbeatTask?.cancel()
    receiveTask = nil
    heartbeatTask = nil
    socket?.cancel(with: .goingAway, reason: nil)
    socket = nil
    credential?.clear()
    credential = nil
    pendingSamples = Array(repeating: 0, count: pendingSamples.count)
    pendingSamples.removeAll(keepingCapacity: false)
    outboundQueue.removeAll(keepingCapacity: false)
    if emitClosed, !terminalEventSent {
      terminalEventSent = true
      eventHandler(.closed(
        provider: providerID,
        providerSessionID: providerSessionID,
        reasonCode: reasonCode.ifBlank("session_closed")
      ))
    }
  }

  private static func resampleTo16k(_ input: [Int16], sourceRateHz: Int) -> [Int16] {
    guard !input.isEmpty, sourceRateHz > 0 else { return [] }
    guard sourceRateHz != VoiceOnlineRealtimeASRProtocol.sampleRateHz else { return input }
    let outputCount = max(
      1,
      Int(Int64(input.count) * Int64(VoiceOnlineRealtimeASRProtocol.sampleRateHz) / Int64(sourceRateHz))
    )
    return (0..<outputCount).map { index in
      let source = Double(index) * Double(sourceRateHz) /
        Double(VoiceOnlineRealtimeASRProtocol.sampleRateHz)
      let left = min(max(Int(source.rounded(.down)), 0), input.count - 1)
      let right = min(left + 1, input.count - 1)
      let fraction = source - Double(left)
      let value = Double(input[left]) + (Double(input[right]) - Double(input[left])) * fraction
      return Int16(min(max(Int(value.rounded()), Int(Int16.min)), Int(Int16.max)))
    }
  }

  private static let batchSamples = 960
  private static let maximumQueuedBatches = 12
  private static let maximumReconnects = 2
  private static let connectTimeoutSeconds: TimeInterval = 5
}
