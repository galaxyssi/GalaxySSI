import XCTest
@testable import GalaxySSI

final class VoiceAdaptiveDetectionTests: XCTestCase {
  func testPassiveRenewalPreservesOwnerAndRejectsStoppedOrOldCapture() throws {
    var lease = VoicePassiveCaptureLease()
    let owner = lease.begin()
    let first = try XCTUnwrap(lease.renew(owner: owner, at: 10))
    XCTAssertTrue(lease.accepts(owner: owner, capture: first))
    XCTAssertFalse(lease.needsRenewal(at: 59.9, healthy: true))
    XCTAssertTrue(lease.needsRenewal(at: 60, healthy: true))
    XCTAssertTrue(lease.needsRenewal(at: 20, healthy: false))
    let renewed = try XCTUnwrap(lease.renew(owner: owner, at: 60))
    XCTAssertEqual(lease.owner, owner)
    XCTAssertFalse(lease.accepts(owner: owner, capture: first))
    XCTAssertTrue(lease.accepts(owner: owner, capture: renewed))
    lease.stop()
    XCTAssertNil(lease.renew(owner: owner, at: 120))
    XCTAssertFalse(lease.needsRenewal(at: 120, healthy: false))
    XCTAssertFalse(lease.accepts(owner: owner, capture: renewed))
  }

  func testInputCaptionRejectsPlaybackAndSubmittedSessionCallbacks() {
    var state = VoiceInteractionState(sessionId: "input", phase: .listening, partialText: "User speech")
    XCTAssertEqual(VoiceInputCaptionPolicy.text(state, capturing: true, submittedSession: ""), "User speech")
    XCTAssertEqual(VoiceInputCaptionPolicy.text(state, capturing: true, submittedSession: "input"), "")
    state.phase = .playingTTS
    state.partialText = "Assistant narration"
    XCTAssertEqual(VoiceInputCaptionPolicy.text(state, capturing: true, submittedSession: ""), "")
    state.phase = .listening
    XCTAssertEqual(VoiceInputCaptionPolicy.text(state, capturing: false, submittedSession: ""), "")
  }
  func testNeuralVadResamplesAcrossTapsAndAppliesAttackAndReleaseHysteresis() {
    var scores: [Float] = [0.7, 0.7, 0.4, 0.1, 0.1, 0.1, 0.1]
    var resets = 0
    let vad = VoiceNeuralSpeechVad(sourceRateHz: 48_000, probability: { window in
      XCTAssertEqual(window.count, 512)
      XCTAssertEqual(window.first, 0.25)
      return scores.removeFirst()
    }, resetModel: { resets += 1 })
    let samples = [Int16](repeating: 8192, count: 768)
    func read(_ sequence: Int64) -> VadDecision { vad.accept(frame(sequence: sequence, samples: samples)) }
    XCTAssertFalse(read(0).speechStarted)
    XCTAssertFalse(read(1).speechStarted)
    XCTAssertFalse(read(2).speechStarted)
    XCTAssertTrue(read(3).speechStarted)
    for sequence in 4..<13 { XCTAssertFalse(read(Int64(sequence)).speechEndedCandidate) }
    XCTAssertTrue(read(13).speechEndedCandidate)
    XCTAssertTrue(scores.isEmpty)
    XCTAssertFalse(read(15).isSpeech)
    XCTAssertEqual(resets, 1)
  }

  func testBundledSileroRunsSilenceThroughThePinnedModel() throws {
    let model = try XCTUnwrap(VoiceSileroProbability())
    for _ in 0..<8 {
      XCTAssertLessThan(try model.probability(Array(repeating: 0, count: 512)), 0.35)
    }
    model.reset()
  }

  func testPassiveSpeechDetectorIgnoresWarmupAndFiresOnlyOnceAfterSustainedInput() {
    let detector = VoicePassiveSpeechDetector(startedAt: 10)
    let speech = (0..<320).map { Int16(sin(2.0 * Double.pi * Double($0) / 37.0) * 7_000) }
    for _ in 0..<8 { XCTAssertFalse(detector.accept(speech, now: 10.2)) }
    for _ in 0..<8 { XCTAssertFalse(detector.accept(Array(repeating: 0, count: 320), now: 10.4)) }
    for _ in 0..<3 { XCTAssertFalse(detector.accept(speech, now: 10.5)) }
    XCTAssertTrue(detector.accept(speech, now: 10.6))
    XCTAssertFalse(detector.accept(speech, now: 10.7))
  }
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
