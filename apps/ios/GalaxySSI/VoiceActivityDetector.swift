import Foundation

struct VadDecision: Equatable {
  var probability: Float
  var isSpeech: Bool
  var speechStarted: Bool
  var speechEndedCandidate: Bool
  var rms: Float
  var peak: Int
  var noiseFloorDb: Float
}

protocol VoiceActivityDetector {
  func reset()
  func accept(_ frame: AudioFrame) -> VadDecision
}

final class AdaptiveSpeechVad: VoiceActivityDetector {
  private let attackFrames: Int
  private let releaseFrames: Int
  private let minimumSpeechDb: Float
  private let minimumSnrDb: Float
  private var noiseFloorDb = initialNoiseFloorDb
  private var speechActive = false
  private var positiveFrames = 0
  private var negativeFrames = 0

  init(
    attackFrames: Int = 2,
    releaseFrames: Int = 5,
    minimumSpeechDb: Float = -48,
    minimumSnrDb: Float = 8
  ) {
    self.attackFrames = max(1, attackFrames)
    self.releaseFrames = max(1, releaseFrames)
    self.minimumSpeechDb = minimumSpeechDb
    self.minimumSnrDb = minimumSnrDb
  }

  func reset() {
    noiseFloorDb = Self.initialNoiseFloorDb
    speechActive = false
    positiveFrames = 0
    negativeFrames = 0
  }

  func accept(_ frame: AudioFrame) -> VadDecision {
    let count = min(max(0, frame.validSamples), frame.samples.count)
    guard count > 0 else {
      return VadDecision(
        probability: 0,
        isSpeech: false,
        speechStarted: false,
        speechEndedCandidate: false,
        rms: 0,
        peak: 0,
        noiseFloorDb: noiseFloorDb
      )
    }

    var energy = 0.0
    var peak = 0
    var crossings = 0
    var previous = Int(frame.samples[0])
    for index in 0..<count {
      let value = Int(frame.samples[index])
      energy += Double(value * value)
      peak = max(peak, abs(value))
      if index > 0 && (value >= 0) != (previous >= 0) {
        crossings += 1
      }
      previous = value
    }
    let rmsRaw = sqrt(energy / Double(count))
    let rms = min(max(Float(rmsRaw / Double(Int16.max)), 0), 1)
    let db = Float(20.0 * log10(Double(max(rms, Self.minimumRms))))
    let snr = db - noiseFloorDb
    let zeroCrossingRate = Float(crossings) / Float(count)
    let absoluteScore = min(max((db - minimumSpeechDb) / 18, 0), 1)
    let snrScore = min(max((snr - minimumSnrDb) / 14, 0), 1)
    let structureScore: Float
    if zeroCrossingRate >= 0.015 && zeroCrossingRate <= 0.42 {
      structureScore = 1
    } else if zeroCrossingRate < 0.01 {
      structureScore = 0.35
    } else {
      structureScore = 0.55
    }
    let probability = min(max(absoluteScore * 0.40 + snrScore * 0.45 + structureScore * 0.15, 0), 1)
    let positive = db >= minimumSpeechDb && snr >= minimumSnrDb && probability >= 0.52

    if !speechActive && !positive {
      let alpha: Float = db < noiseFloorDb + 6 ? 0.08 : 0.015
      noiseFloorDb = min(
        max(noiseFloorDb * (1 - alpha) + db * alpha, Self.minimumNoiseFloorDb),
        Self.maximumNoiseFloorDb
      )
    }

    var started = false
    var ended = false
    if positive {
      positiveFrames += 1
      negativeFrames = 0
      if !speechActive && positiveFrames >= attackFrames {
        speechActive = true
        started = true
      }
    } else {
      positiveFrames = 0
      if speechActive {
        negativeFrames += 1
        if negativeFrames >= releaseFrames {
          speechActive = false
          negativeFrames = 0
          ended = true
        }
      }
    }
    return VadDecision(
      probability: probability,
      isSpeech: speechActive || positive,
      speechStarted: started,
      speechEndedCandidate: ended,
      rms: rms,
      peak: peak,
      noiseFloorDb: noiseFloorDb
    )
  }

  private static let initialNoiseFloorDb: Float = -58
  private static let minimumNoiseFloorDb: Float = -72
  private static let maximumNoiseFloorDb: Float = -30
  private static let minimumRms: Float = 0.00001
}
