import XCTest
@testable import GalaxySSI

final class VoiceAdaptiveDetectionTests: XCTestCase {
  func testVadAdaptsToSilenceAndDetectsSpeechBoundaries() {
    let vad = AdaptiveSpeechVad()
    for index in 0..<12 {
      let decision = vad.accept(frame(sequence: Int64(index), samples: Array(repeating: 0, count: 320)))
      XCTAssertFalse(decision.isSpeech)
    }

    var started = false
    for index in 0..<8 {
      let samples = (0..<320).map { sample in
        Int16(sin(2.0 * Double.pi * Double(sample) / 37.0) * 7_000)
      }
      started = vad.accept(frame(sequence: Int64(12 + index), samples: samples)).speechStarted || started
    }
    XCTAssertTrue(started)

    var ended = false
    for index in 0..<8 {
      ended = vad.accept(
        frame(sequence: Int64(20 + index), samples: Array(repeating: 0, count: 320))
      ).speechEndedCandidate || ended
    }
    XCTAssertTrue(ended)
  }

  func testAdaptiveEndpointEndsWithinTargetTailWindow() {
    let endpoint = AdaptiveEndpointDetector(
      sampleRateHz: 16_000,
      config: AdaptiveEndpointConfig(normalUtteranceSilenceMs: 650),
      autoEndpoint: true
    )
    var terminal: EndpointReason?
    for index in 0..<100 {
      terminal = endpoint.accept(
        frame(sequence: Int64(index), samples: Array(repeating: 0, count: 320)),
        vad: speechDecision()
      ).endpointReason
    }
    XCTAssertNil(terminal)

    for index in 0..<60 where terminal == nil {
      terminal = endpoint.accept(
        frame(sequence: Int64(100 + index), samples: Array(repeating: 0, count: 320)),
        vad: silenceDecision()
      ).endpointReason
    }

    XCTAssertEqual(terminal, .trailingSilence)
  }

  func testNoSpeechTimeoutIsBounded() {
    let endpoint = AdaptiveEndpointDetector(sampleRateHz: 16_000)
    var update = EndpointUpdate(elapsedMs: 0)
    for index in 0..<125 {
      update = endpoint.accept(
        frame(sequence: Int64(index), samples: Array(repeating: 0, count: 320)),
        vad: silenceDecision()
      )
    }
    XCTAssertEqual(update.endpointReason, .noSpeechTimeout)
    XCTAssertEqual(update.elapsedMs, 2_500)
  }

  private func speechDecision() -> VadDecision {
    VadDecision(
      probability: 0.95,
      isSpeech: true,
      speechStarted: false,
      speechEndedCandidate: false,
      rms: 0.2,
      peak: 7_000,
      noiseFloorDb: -58
    )
  }

  private func silenceDecision() -> VadDecision {
    VadDecision(
      probability: 0.02,
      isSpeech: false,
      speechStarted: false,
      speechEndedCandidate: false,
      rms: 0,
      peak: 0,
      noiseFloorDb: -58
    )
  }

  private func frame(sequence: Int64, samples: [Int]) -> AudioFrame {
    frame(sequence: sequence, samples: samples.map { Int16($0) })
  }

  private func frame(sequence: Int64, samples: [Int16]) -> AudioFrame {
    AudioFrame(
      sequence: sequence,
      captureTimeNanos: sequence * 20_000_000,
      samples: samples
    )
  }
}
