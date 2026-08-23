// Portions based on LiveKit's wake-word Swift implementation.
// Copyright 2026 LiveKit, Inc. Licensed under Apache-2.0.

@preconcurrency import AVFoundation
import Foundation

actor SignalASIOpenWakeWordListener {
  typealias DetectionHandler = @Sendable (Float) -> Void
  typealias FailureHandler = @Sendable (String) -> Void

  private let windowSeconds = 2.0
  private let predictionInterval: TimeInterval = 0.08
  private let cooldown: TimeInterval = 2.5

  private var engine: AVAudioEngine?
  private var converter: AVAudioConverter?
  private var targetFormat: AVAudioFormat?
  private var detector: SignalASIOpenWakeWordDetector?
  private var threshold: Float = 0.5
  private var onDetection: DetectionHandler?
  private var onFailure: FailureHandler?
  private var ringBuffer: [Int16] = []
  private var writeIndex = 0
  private var samplesWritten = 0
  private var lastPredictionTime: CFAbsoluteTime = 0
  private var lastDetectionTime: CFAbsoluteTime = 0
  private var detectionDelivered = false

  static func requestMicrophonePermission() async -> Bool {
    let session = AVAudioSession.sharedInstance()
    switch session.recordPermission {
    case .granted:
      return true
    case .denied:
      return false
    case .undetermined:
      return await withCheckedContinuation { continuation in
        session.requestRecordPermission { granted in
          continuation.resume(returning: granted)
        }
      }
    @unknown default:
      return false
    }
  }

  func start(
    modelName: String,
    threshold: Float,
    onDetection: @escaping DetectionHandler,
    onFailure: @escaping FailureHandler
  ) throws {
    if engine != nil { return }

    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setCategory(
        .playAndRecord,
        mode: .measurement,
        options: [.defaultToSpeaker, .allowBluetooth]
      )
      try audioSession.setActive(true)

      let detector = try SignalASIOpenWakeWordDetector(modelName: modelName)
      let engine = AVAudioEngine()
      let input = engine.inputNode
      let hardwareFormat = input.inputFormat(forBus: 0)
      guard hardwareFormat.sampleRate > 0 else {
        throw SignalASIOpenWakeWordError.unsupportedAudioFormat(0)
      }
      guard let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: SignalASIOpenWakeWordConstants.sampleRate,
        channels: 1,
        interleaved: true
      ), let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
        throw SignalASIOpenWakeWordError.unsupportedAudioFormat(hardwareFormat.sampleRate)
      }

      self.detector = detector
      self.engine = engine
      self.converter = converter
      self.targetFormat = targetFormat
      self.threshold = min(max(threshold, 0.01), 0.99)
      self.onDetection = onDetection
      self.onFailure = onFailure
      ringBuffer = [Int16](
        repeating: 0,
        count: Int(SignalASIOpenWakeWordConstants.sampleRate * windowSeconds)
      )
      writeIndex = 0
      samplesWritten = 0
      lastPredictionTime = 0
      lastDetectionTime = 0
      detectionDelivered = false

      input.installTap(onBus: 0, bufferSize: 1_024, format: hardwareFormat) { [weak self] buffer, _ in
        guard let self,
              let samples = Self.convert(
                buffer: buffer,
                converter: converter,
                targetFormat: targetFormat
              ) else { return }
        Task { await self.ingest(samples) }
      }

      engine.prepare()
      try engine.start()
    } catch {
      stopAudio()
      try? audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
      throw error
    }
  }

  func stop() {
    stopAudio()
    detector = nil
    onDetection = nil
    onFailure = nil
  }

  private func ingest(_ samples: [Int16]) {
    guard !detectionDelivered, !samples.isEmpty, !ringBuffer.isEmpty else { return }
    for sample in samples {
      ringBuffer[writeIndex] = sample
      writeIndex = (writeIndex + 1) % ringBuffer.count
    }
    samplesWritten = min(samplesWritten + samples.count, ringBuffer.count)
    guard samplesWritten == ringBuffer.count else { return }

    let now = CFAbsoluteTimeGetCurrent()
    guard now - lastPredictionTime >= predictionInterval else { return }
    lastPredictionTime = now

    do {
      let confidence = try detector?.confidence(for: linearizedAudio()) ?? 0
      guard confidence >= threshold,
            now - lastDetectionTime >= cooldown else { return }
      lastDetectionTime = now
      detectionDelivered = true
      let handler = onDetection
      stopAudio()
      handler?(confidence)
    } catch {
      let handler = onFailure
      stopAudio()
      handler?(error.localizedDescription)
    }
  }

  private func linearizedAudio() -> [Int16] {
    guard writeIndex > 0 else { return ringBuffer }
    return Array(ringBuffer[writeIndex...]) + Array(ringBuffer[..<writeIndex])
  }

  private func stopAudio() {
    let wasRunning = engine != nil
    if let engine {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
    }
    engine = nil
    converter = nil
    targetFormat = nil
    ringBuffer = []
    writeIndex = 0
    samplesWritten = 0
    if wasRunning {
      try? AVAudioSession.sharedInstance().setActive(
        false,
        options: [.notifyOthersOnDeactivation]
      )
    }
  }

  private nonisolated static func convert(
    buffer inputBuffer: AVAudioPCMBuffer,
    converter: AVAudioConverter,
    targetFormat: AVAudioFormat
  ) -> [Int16]? {
    let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
    let outputCapacity = AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio)) + 8
    guard let outputBuffer = AVAudioPCMBuffer(
      pcmFormat: targetFormat,
      frameCapacity: outputCapacity
    ) else { return nil }

    var suppliedInput = false
    var conversionError: NSError?
    let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outputStatus in
      if suppliedInput {
        outputStatus.pointee = .noDataNow
        return nil
      }
      suppliedInput = true
      outputStatus.pointee = .haveData
      return inputBuffer
    }
    guard status != .error,
          conversionError == nil,
          let channel = outputBuffer.int16ChannelData else { return nil }
    return Array(
      UnsafeBufferPointer(
        start: channel[0],
        count: Int(outputBuffer.frameLength)
      )
    )
  }
}
