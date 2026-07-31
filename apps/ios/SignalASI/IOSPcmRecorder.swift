import AVFoundation
import Foundation

final class IOSPcmRecorder: PcmRecorder {
  private let audioEngine: AVAudioEngine
  private let audioSession: AVAudioSession
  private let elapsedClock: () -> Int64
  private let lock = NSLock()
  private var continuation: AsyncStream<AudioFrame>.Continuation?
  private var activeConfig: PcmCaptureConfig?
  private var sequence: Int64 = 0
  private var state = PcmRecorderState()

  init(
    audioEngine: AVAudioEngine = AVAudioEngine(),
    audioSession: AVAudioSession = .sharedInstance(),
    elapsedClock: @escaping () -> Int64 = IOSPcmRecorder.defaultElapsedClock
  ) {
    self.audioEngine = audioEngine
    self.audioSession = audioSession
    self.elapsedClock = elapsedClock
  }

  func start(config: PcmCaptureConfig) throws -> AsyncStream<AudioFrame> {
    try beginState(config: config)
    let stream = AsyncStream<AudioFrame>(bufferingPolicy: .bufferingNewest(config.outputQueueCapacity)) { continuation in
      self.locked { self.continuation = continuation }
    }
    do {
      try configureAudioSession(config)
      let input = audioEngine.inputNode
      let format = input.outputFormat(forBus: 0)
      input.removeTap(onBus: 0)
      input.installTap(
        onBus: 0,
        bufferSize: AVAudioFrameCount(config.samplesPerFrame),
        format: format
      ) { [weak self] buffer, _ in
        self?.accept(buffer: buffer)
      }
      audioEngine.prepare()
      try audioEngine.start()
      locked {
        state.phase = .recording
        state.audioSource = "av_audio_engine"
        state.inputRoute = inputRouteName()
      }
      return stream
    } catch {
      failStart(error)
      throw PcmCaptureError(code: "ios_pcm_capture_failed", message: error.localizedDescription)
    }
  }

  func requestStop(reason: PcmStopReason) {
    finish(reason: reason)
  }

  func stop(reason: PcmStopReason) async {
    finish(reason: reason)
  }

  func currentState() -> PcmRecorderState {
    locked { state }
  }

  private func beginState(config: PcmCaptureConfig) throws {
    try locked {
      guard state.phase == .idle || state.phase == .stopped || state.phase == .failed else {
        throw PcmCaptureError(code: "ios_pcm_capture_busy", message: "PCM capture is already running.")
      }
      activeConfig = config
      sequence = 0
      state = PcmRecorderState(phase: .starting, inputRoute: inputRouteName())
    }
  }

  private func configureAudioSession(_ config: PcmCaptureConfig) throws {
    try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
    try audioSession.setPreferredSampleRate(Double(config.sampleRateHz))
    try audioSession.setPreferredIOBufferDuration(Double(config.frameDurationMs) / 1_000.0)
    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
  }

  private func accept(buffer: AVAudioPCMBuffer) {
    let samples = VoicePcmTapPipeline.int16Samples(from: buffer)
    let route = inputRouteName()
    let frame = locked { () -> (AsyncStream<AudioFrame>.Continuation, AudioFrame)? in
      var diagnostics = state.diagnostics
      if route != state.inputRoute && !route.isEmpty {
        diagnostics.inputRouteChangeCount += 1
        state.inputRoute = route
      }
      guard !samples.isEmpty else {
        diagnostics.zeroReadCount += 1
        state.diagnostics = diagnostics
        return nil
      }
      if let expected = activeConfig?.samplesPerFrame, samples.count < expected {
        diagnostics.shortReadCount += 1
      }
      let frame = AudioFrame(
        sequence: sequence,
        captureTimeNanos: elapsedClock(),
        samples: samples
      )
      sequence += 1
      state.currentAmplitude = samples.map { abs(Int($0)) }.max() ?? 0
      state.capturedSamples += Int64(frame.validSamples)
      state.diagnostics = diagnostics
      guard let continuation = continuation else { return nil }
      return (continuation, frame)
    }
    if let frame = frame {
      frame.0.yield(frame.1)
    }
  }

  private func finish(reason: PcmStopReason) {
    let stream = locked { () -> AsyncStream<AudioFrame>.Continuation? in
      guard state.phase == .starting || state.phase == .recording || state.phase == .stopping else {
        return nil
      }
      state.phase = .stopping
      state.stopReason = reason
      let stream = continuation
      continuation = nil
      return stream
    }
    audioEngine.inputNode.removeTap(onBus: 0)
    audioEngine.stop()
    try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    stream?.finish()
    locked {
      state.phase = reason == .captureFailure ? .failed : .stopped
      activeConfig = nil
    }
  }

  private func failStart(_ error: Error) {
    let stream = locked { () -> AsyncStream<AudioFrame>.Continuation? in
      state.phase = .failed
      state.stopReason = .captureFailure
      state.errorCode = (error as? PcmCaptureError)?.code ?? "ios_pcm_capture_failed"
      activeConfig = nil
      let stream = continuation
      continuation = nil
      return stream
    }
    stream?.finish()
    audioEngine.inputNode.removeTap(onBus: 0)
    audioEngine.stop()
    try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func inputRouteName() -> String {
    let inputs = audioSession.currentRoute.inputs
    guard !inputs.isEmpty else { return "" }
    return inputs.map { input in
      let name = input.portName.trimmingCharacters(in: .whitespacesAndNewlines)
      return name.isEmpty ? input.portType.rawValue : name
    }.joined(separator: ",")
  }

  private func locked<T>(_ action: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try action()
  }

  private static func defaultElapsedClock() -> Int64 {
    Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
  }
}
