import CryptoKit
import Foundation
import OnnxRuntimeBindings

final class VoiceSileroProbability {
  private enum Failure: Error { case invalidModel, invalidTensor }
  private let session: ORTSession
  private var state = Data(count: 256 * MemoryLayout<Float>.size)
  private var context = [Float](repeating: 0, count: 64)

  // The runtime session is shared; recurrent tensors belong to each capture.
  private static let bundledSession: ORTSession? = {
    guard let url = Bundle.main.url(forResource: "silero_vad_16k_op15", withExtension: "onnx", subdirectory: "vad")
    else { return nil }
    return try? makeSession(url)
  }()

  private static func makeSession(_ url: URL) throws -> ORTSession {
    let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
    let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    guard bytes.count == 1_289_603,
          digest == "7ed98ddbad84ccac4cd0aeb3099049280713df825c610a8ed34543318f1b2c49"
    else { throw Failure.invalidModel }
    return try GalaxySSIOpenWakeWordEnvironment.makeSession(modelURL: url, singleThreaded: true)
  }

  init?() {
    guard let session = Self.bundledSession else { return nil }
    self.session = session
  }

  func reset() {
    state.resetBytes(in: 0..<state.count)
    for i in context.indices { context[i] = 0 }
  }

  func probability(_ window: [Float]) throws -> Float {
    guard window.count == 512 else { throw Failure.invalidTensor }
    let audio = context + window
    let input = try audio.withUnsafeBytes { bytes in
      try ORTValue(tensorData: NSMutableData(bytes: bytes.baseAddress, length: bytes.count),
                   elementType: .float, shape: [1, 576])
    }
    let recurrent = try ORTValue(tensorData: NSMutableData(data: state), elementType: .float, shape: [2, 1, 128])
    var sampleRate: Int64 = 16_000
    let rate = try withUnsafeBytes(of: &sampleRate) { bytes in
      try ORTValue(tensorData: NSMutableData(bytes: bytes.baseAddress, length: bytes.count),
                   elementType: .int64, shape: [])
    }
    let outputs = try session.run(withInputs: ["input": input, "state": recurrent, "sr": rate],
                                  outputNames: ["output", "stateN"], runOptions: nil)
    guard let result = try outputs["output"]?.tensorData(), result.length == MemoryLayout<Float>.size,
          let next = try outputs["stateN"]?.tensorData(), next.length == state.count else { throw Failure.invalidTensor }
    var score: Float = 0
    withUnsafeMutableBytes(of: &score) { $0.copyMemory(from: UnsafeRawBufferPointer(start: result.bytes, count: result.length)) }
    guard score.isFinite, (0...1).contains(score) else { throw Failure.invalidTensor }
    state.withUnsafeMutableBytes { $0.copyMemory(from: UnsafeRawBufferPointer(start: next.bytes, count: next.length)) }
    context = Array(window.suffix(64))
    return score
  }
}

final class VoiceNeuralSpeechVad: VoiceActivityDetector {
  private let sourceRateHz: Int
  private let probability: ([Float]) throws -> Float
  private let resetModel: () -> Void
  private let fallback = AdaptiveSpeechVad()
  private var window = [Float](repeating: 0, count: 512)
  private var filled = 0
  private var active = false
  private var positive = 0
  private var negative = 0
  private var score: Float = 0
  private var lastSequence: Int64?
  private var resamplePhase = 0
  private var resampleSum: Float = 0
  private var resampleCount = 0
  private(set) var usingNeural = true

  convenience init?(sourceRateHz: Int) {
    guard (16_000...192_000).contains(sourceRateHz), let model = VoiceSileroProbability() else { return nil }
    self.init(sourceRateHz: sourceRateHz, probability: model.probability, resetModel: model.reset)
  }

  init(sourceRateHz: Int, probability: @escaping ([Float]) throws -> Float, resetModel: @escaping () -> Void = {}) {
    precondition(sourceRateHz >= 16_000)
    self.sourceRateHz = sourceRateHz
    self.probability = probability
    self.resetModel = resetModel
  }

  func reset() {
    for i in window.indices { window[i] = 0 }
    filled = 0; active = false; positive = 0; negative = 0; score = 0
    resamplePhase = 0; resampleSum = 0; resampleCount = 0; lastSequence = nil
    fallback.reset()
    resetModel()
  }

  func accept(_ frame: AudioFrame) -> VadDecision {
    guard usingNeural else { return fallback.accept(frame) }
    if let lastSequence, frame.sequence != lastSequence &+ 1 { reset() }
    lastSequence = frame.sequence
    let count = min(max(frame.validSamples, 0), frame.samples.count)
    var energy = 0.0, peak = 0
    var started = false, ended = false
    for sample in frame.samples.prefix(count) {
      let value = Int(sample)
      energy += Double(value * value)
      peak = max(peak, abs(value))
      // Keep the fractional rate and average across tap boundaries without altering ASR PCM.
      resamplePhase += 16_000
      resampleSum += Float(sample) / 32_768
      resampleCount += 1
      guard resamplePhase >= sourceRateHz else { continue }
      resamplePhase -= sourceRateHz
      window[filled] = resampleSum / Float(resampleCount)
      resampleSum = 0; resampleCount = 0
      filled += 1
      guard filled == window.count else { continue }
      guard let value = try? probability(window), value.isFinite, (0...1).contains(value) else {
        reset()
        usingNeural = false
        return fallback.accept(frame)
      }
      filled = 0
      score = value
      if score >= (active ? 0.35 : 0.60) {
        positive = min(positive + 1, 2)
        negative = 0
        if !active, positive == 2 { active = true; started = true }
      } else {
        positive = 0
        if active { negative += 1 }
        if active, negative == 4 { active = false; ended = true; negative = 0 }
      }
    }
    let rms = count > 0 ? Float(sqrt(energy / Double(count)) / 32_768) : 0
    return VadDecision(probability: score, isSpeech: active || started, speechStarted: started,
                       speechEndedCandidate: ended, rms: rms, peak: peak, noiseFloorDb: -58)
  }

  deinit { reset() }
}
