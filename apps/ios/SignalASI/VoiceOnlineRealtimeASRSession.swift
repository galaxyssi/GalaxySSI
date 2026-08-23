import Foundation

actor VoiceOnlineRealtimeASRSession {
  typealias EventHandler = (VoiceOnlineRealtimeASREvent) -> Void

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
  private var nextBatchSequence: Int64 = 0
  private var pendingSamples: [Int16] = []
  private var pendingFirstCaptureNanos: Int64 = 0
  private var pendingLastCaptureNanos: Int64 = 0
  private var queuedAudio: [Data] = []

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
      connected = true
      eventHandler(.ready(
        provider: credential.providerID,
        providerSessionID: credential.providerSessionID,
        modelProfileID: ""
      ))
      for audio in queuedAudio {
        try await socket.send(.data(audio))
      }
      queuedAudio.removeAll(keepingCapacity: false)
      if finishRequested {
        try await socket.send(.string(try VoiceOnlineRealtimeASRProtocol.finishMessage(config: config)))
      }
      receiveTask = Task { [weak self] in await self?.receiveLoop() }
      heartbeatTask = Task { [weak self] in await self?.heartbeatLoop() }
      return true
    } catch {
      fail(code: "connect_failed", message: error.localizedDescription)
      return false
    }
  }

  func push(frame: AudioFrame, sourceSampleRateHz: Int) async {
    guard !closed, !finalSeen, !finishRequested, sourceSampleRateHz > 0 else { return }
    let converted = Self.resampleTo16k(frame.samples, sourceRateHz: sourceSampleRateHz)
    guard !converted.isEmpty else { return }
    if pendingSamples.isEmpty {
      pendingFirstCaptureNanos = frame.captureTimeNanos
    }
    pendingLastCaptureNanos = frame.captureTimeNanos
    pendingSamples.append(contentsOf: converted)
    while pendingSamples.count >= Self.batchSamples {
      let samples = Array(pendingSamples.prefix(Self.batchSamples))
      pendingSamples.removeFirst(Self.batchSamples)
      await enqueue(samples: samples)
      pendingFirstCaptureNanos = pendingLastCaptureNanos
    }
  }

  func finishInput() async {
    guard !closed else { return }
    guard !finishRequested else { return }
    finishRequested = true
    if !pendingSamples.isEmpty {
      let samples = pendingSamples
      pendingSamples.removeAll(keepingCapacity: false)
      await enqueue(samples: samples)
    }
    guard let socket, connected else { return }
    do {
      try await socket.send(.string(try VoiceOnlineRealtimeASRProtocol.finishMessage(config: config)))
    } catch {
      fail(code: "finish_send_failed", message: error.localizedDescription)
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

  private func enqueue(samples: [Int16]) async {
    var batch = VoiceOnlineRealtimeASRAudioBatch(
      firstSequence: nextBatchSequence,
      lastSequence: nextBatchSequence,
      firstCaptureTimeNanos: pendingFirstCaptureNanos,
      lastCaptureTimeNanos: pendingLastCaptureNanos,
      samples: samples
    )
    nextBatchSequence += 1
    let data = VoiceOnlineRealtimeASRProtocol.encodeAudio(batch)
    batch.samples = Array(repeating: 0, count: batch.samples.count)
    guard let socket, connected else {
      queuedAudio.append(data)
      if queuedAudio.count > Self.maximumQueuedBatches {
        queuedAudio.removeFirst(queuedAudio.count - Self.maximumQueuedBatches)
      }
      return
    }
    do {
      try await socket.send(.data(data))
    } catch {
      fail(code: "audio_send_failed", message: error.localizedDescription)
    }
  }

  private func receiveLoop() async {
    guard let socket else { return }
    while !Task.isCancelled, !closed {
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
          if case .final = event {
            guard !finalSeen else { continue }
            finalSeen = true
          }
          let terminal: Bool
          switch event {
          case .failed(let failure):
            terminal = failure.fatal
          case .closed:
            terminal = true
          default:
            terminal = finalSeen
          }
          eventHandler(event)
          if terminal {
            close()
            return
          }
        case .data:
          continue
        @unknown default:
          continue
        }
      } catch {
        if !closed {
          fail(code: "network_disconnected", message: error.localizedDescription)
        }
        return
      }
    }
  }

  private func heartbeatLoop() async {
    while !Task.isCancelled, !closed {
      try? await Task.sleep(nanoseconds: 10_000_000_000)
      guard !Task.isCancelled, !closed, let socket,
            let message = try? VoiceOnlineRealtimeASRProtocol.heartbeatMessage(config: config) else {
        continue
      }
      try? await socket.send(.string(message))
    }
  }

  private func fail(code: String, message: String) {
    guard !closed else { return }
    eventHandler(.failed(VoiceOnlineRealtimeASRFailure(
      code: code,
      message: String(message.prefix(240)),
      retryable: true,
      fatal: false,
      providerID: credential?.providerID ?? "signalasi_realtime",
      providerSessionID: credential?.providerSessionID ?? "",
      serverTimestampMs: nil
    )))
    close()
  }

  private func close() {
    guard !closed else { return }
    closed = true
    connected = false
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
  private static let maximumQueuedBatches = 20
}
