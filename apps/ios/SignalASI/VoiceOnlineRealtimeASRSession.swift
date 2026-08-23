import Foundation

actor VoiceOnlineRealtimeASRSession {
  typealias EventHandler = (VoiceOnlineRealtimeASREvent) -> Void

  private struct QueuedBatch {
    let data: Data
    let sampleCount: Int
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
  private var finalSeen = false
  private var finishRequested = false
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
  private var queuedAudio: [QueuedBatch] = []

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
    guard let socket, connected else { return }
    do {
      try await socket.send(.string(try VoiceOnlineRealtimeASRProtocol.finishMessage(config: config)))
    } catch {
      fail(code: "finish_send_failed", message: error.localizedDescription, retryable: false)
    }
  }

  func cancel(reason: String) async {
    guard !closed else { return }
    if let socket, connected,
       let message = try? VoiceOnlineRealtimeASRProtocol.abortMessage(config: config, reason: reason) {
      try? await socket.send(.string(message))
    }
    close()
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
    guard let socket, connected else {
      guard queuedAudio.count < Self.maximumQueuedBatches else {
        droppedAudioBatches += 1
        fail(
          code: "send_queue_overflow",
          message: "Realtime ASR audio queue reached its capacity.",
          retryable: false
        )
        return
      }
      queuedAudio.append(queued)
      return
    }
    do {
      try await socket.send(.data(queued.data))
      recordSent(sampleCount: queued.sampleCount)
    } catch {
      queuedAudio.insert(queued, at: 0)
      _ = await handleTransportFailure(
        generation: socketGeneration,
        code: "audio_send_failed",
        message: error.localizedDescription
      )
    }
  }

  private func connect(using credential: VoiceOnlineRealtimeASRCredential) async throws {
    guard !closed else { return }
    socketGeneration += 1
    let generation = socketGeneration
    var request = URLRequest(url: credential.webSocketURL)
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
    for batch in queuedAudio {
      try await socket.send(.data(batch.data))
      recordSent(sampleCount: batch.sampleCount)
    }
    queuedAudio.removeAll(keepingCapacity: false)
    if finishRequested {
      try await socket.send(.string(try VoiceOnlineRealtimeASRProtocol.finishMessage(config: config)))
    }
    receiveTask = Task { [weak self] in
      await self?.receiveLoop(socket: socket, generation: generation)
    }
    heartbeatTask?.cancel()
    heartbeatTask = Task { [weak self] in
      await self?.heartbeatLoop(socket: socket, generation: generation)
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
            close()
            return
          case .failed(let failure) where failure.fatal:
            eventHandler(event)
            close()
            return
          case .closed:
            eventHandler(event)
            close()
            return
          default:
            break
          }
          eventHandler(event)
        case .data:
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
    close()
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

  private func fail(code: String, message: String, retryable: Bool = true) {
    guard !closed else { return }
    emitFailure(code: code, message: message, retryable: retryable, fatal: false)
    close()
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

  private func close() {
    guard !closed else { return }
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
    queuedAudio.removeAll(keepingCapacity: false)
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
}
