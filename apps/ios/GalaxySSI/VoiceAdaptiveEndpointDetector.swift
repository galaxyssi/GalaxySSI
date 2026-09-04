import Foundation

struct AdaptiveEndpointConfig: Equatable {
  var noSpeechTimeoutMs: Int64
  var minimumSpeechMs: Int64
  var shortUtteranceSilenceMs: Int64
  var normalUtteranceSilenceMs: Int64
  var longUtteranceSilenceMs: Int64
  var minTrailingSilenceMs: Int64
  var maxTrailingSilenceMs: Int64
  var maxDurationMs: Int64
  var preRollMs: Int
  var postRollMs: Int

  init(
    noSpeechTimeoutMs: Int64 = 2_500,
    minimumSpeechMs: Int64 = 240,
    shortUtteranceSilenceMs: Int64 = 850,
    normalUtteranceSilenceMs: Int64 = 650,
    longUtteranceSilenceMs: Int64 = 500,
    minTrailingSilenceMs: Int64 = 350,
    maxTrailingSilenceMs: Int64 = 1_200,
    maxDurationMs: Int64 = 60_000,
    preRollMs: Int = 300,
    postRollMs: Int = 400
  ) {
    precondition((1_500...3_000).contains(noSpeechTimeoutMs))
    precondition(minTrailingSilenceMs >= 250 && minTrailingSilenceMs <= maxTrailingSilenceMs)
    precondition(maxTrailingSilenceMs <= 1_500)
    precondition(maxDurationMs > noSpeechTimeoutMs)
    precondition((0...1_000).contains(preRollMs))
    precondition((0...1_000).contains(postRollMs))
    self.noSpeechTimeoutMs = noSpeechTimeoutMs
    self.minimumSpeechMs = minimumSpeechMs
    self.shortUtteranceSilenceMs = shortUtteranceSilenceMs
    self.normalUtteranceSilenceMs = normalUtteranceSilenceMs
    self.longUtteranceSilenceMs = longUtteranceSilenceMs
    self.minTrailingSilenceMs = minTrailingSilenceMs
    self.maxTrailingSilenceMs = maxTrailingSilenceMs
    self.maxDurationMs = maxDurationMs
    self.preRollMs = preRollMs
    self.postRollMs = postRollMs
  }
}

enum EndpointReason: String, Codable, Equatable {
  case trailingSilence = "TRAILING_SILENCE"
  case noSpeechTimeout = "NO_SPEECH_TIMEOUT"
  case maxDuration = "MAX_DURATION"
}

struct EndpointUpdate: Equatable {
  var elapsedMs: Int64
  var speechStarted: Bool
  var speechEndedCandidate: Bool
  var trailingSilenceMs: Int64
  var endpointReason: EndpointReason?

  init(
    elapsedMs: Int64,
    speechStarted: Bool = false,
    speechEndedCandidate: Bool = false,
    trailingSilenceMs: Int64 = 0,
    endpointReason: EndpointReason? = nil
  ) {
    self.elapsedMs = max(0, elapsedMs)
    self.speechStarted = speechStarted
    self.speechEndedCandidate = speechEndedCandidate
    self.trailingSilenceMs = max(0, trailingSilenceMs)
    self.endpointReason = endpointReason
  }
}

final class AdaptiveEndpointDetector {
  private let sampleRateHz: Int
  private let config: AdaptiveEndpointConfig
  private let autoEndpoint: Bool
  private var consumedSamples: Int64 = 0
  private var firstSpeechSample: Int64?
  private var lastSpeechSampleExclusive: Int64?
  private var terminalReason: EndpointReason?

  init(
    sampleRateHz: Int,
    config: AdaptiveEndpointConfig = AdaptiveEndpointConfig(),
    autoEndpoint: Bool = true
  ) {
    self.sampleRateHz = max(1, sampleRateHz)
    self.config = config
    self.autoEndpoint = autoEndpoint
  }

  func reset() {
    consumedSamples = 0
    firstSpeechSample = nil
    lastSpeechSampleExclusive = nil
    terminalReason = nil
  }

  func accept(_ frame: AudioFrame, vad: VadDecision) -> EndpointUpdate {
    let frameStart = consumedSamples
    consumedSamples += Int64(frame.validSamples)
    if vad.isSpeech {
      if firstSpeechSample == nil {
        firstSpeechSample = frameStart
      }
      lastSpeechSampleExclusive = consumedSamples
    }
    let elapsedMs = samplesToMs(consumedSamples)
    let speechStartMs = firstSpeechSample.map(samplesToMs)
    let speechDurationMs = speechStartMs.map { max(0, elapsedMs - $0) } ?? 0
    let trailingSilenceMs = lastSpeechSampleExclusive.map {
      samplesToMs(max(0, consumedSamples - $0))
    } ?? elapsedMs

    if terminalReason == nil && autoEndpoint {
      if firstSpeechSample == nil && elapsedMs >= config.noSpeechTimeoutMs {
        terminalReason = .noSpeechTimeout
      } else if elapsedMs >= config.maxDurationMs {
        terminalReason = .maxDuration
      } else if firstSpeechSample != nil &&
          speechDurationMs >= config.minimumSpeechMs &&
          trailingSilenceMs >= targetTrailingSilence(speechDurationMs) {
        terminalReason = .trailingSilence
      }
    }
    return EndpointUpdate(
      elapsedMs: elapsedMs,
      speechStarted: vad.speechStarted,
      speechEndedCandidate: vad.speechEndedCandidate,
      trailingSilenceMs: trailingSilenceMs,
      endpointReason: terminalReason
    )
  }

  private func targetTrailingSilence(_ speechDurationMs: Int64) -> Int64 {
    let target: Int64
    if speechDurationMs < 1_200 {
      target = config.shortUtteranceSilenceMs
    } else if speechDurationMs < 5_000 {
      target = config.normalUtteranceSilenceMs
    } else {
      target = config.longUtteranceSilenceMs
    }
    return min(max(target, config.minTrailingSilenceMs), config.maxTrailingSilenceMs)
  }

  private func samplesToMs(_ samples: Int64) -> Int64 {
    samples * 1_000 / Int64(sampleRateHz)
  }
}
