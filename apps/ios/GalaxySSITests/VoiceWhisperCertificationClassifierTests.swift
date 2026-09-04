import XCTest
@testable import GalaxySSI

final class VoiceWhisperCertificationClassifierTests: XCTestCase {
  func testRealtimeFinalAndSecondPassThresholdsMatchAndroidPolicy() {
    XCTAssertEqual(
      VoiceWhisperCertificationClassifier.classify(
        profile: profile(partialInterval: 750),
        rtfP95: 0.80,
        transcriptCorrect: true,
        maxThermalStatus: 0,
        abortLatencyMillisP95: 300
      ),
      VoiceWhisperCertificationClassification(
        level: .realtime,
        mode: .realtimePartial,
        partialIntervalMillis: 750,
        failureReason: nil
      )
    )
    XCTAssertEqual(
      VoiceWhisperCertificationClassifier.classify(
        profile: profile(partialInterval: 750),
        rtfP95: 1.50,
        transcriptCorrect: true,
        maxThermalStatus: 0,
        abortLatencyMillisP95: 0
      ).level,
      .final
    )

    let secondPass = VoiceWhisperCertificationClassifier.classify(
      profile: profile(partialInterval: 750),
      rtfP95: 1.51,
      transcriptCorrect: true,
      maxThermalStatus: 0,
      abortLatencyMillisP95: 0
    )
    XCTAssertEqual(secondPass.level, .secondPass)
    XCTAssertEqual(secondPass.mode, .secondPass)
    XCTAssertTrue(secondPass.failureReason?.contains("1.51") == true)
  }

  func testRealtimePartialIntervalIsClamped() {
    XCTAssertEqual(
      VoiceWhisperCertificationClassifier.classify(
        profile: profile(partialInterval: 200),
        rtfP95: 0.2,
        transcriptCorrect: true,
        maxThermalStatus: 0,
        abortLatencyMillisP95: 0
      ).partialIntervalMillis,
      400
    )
    XCTAssertEqual(
      VoiceWhisperCertificationClassifier.classify(
        profile: profile(partialInterval: 4_000),
        rtfP95: 0.2,
        transcriptCorrect: true,
        maxThermalStatus: 0,
        abortLatencyMillisP95: 0
      ).partialIntervalMillis,
      3_000
    )
  }

  func testFailureAndRemoteRecommendedOutcomes() {
    XCTAssertEqual(
      VoiceWhisperCertificationClassifier.classify(
        profile: profile(partialInterval: 750),
        rtfP95: 0.2,
        transcriptCorrect: false,
        maxThermalStatus: 0,
        abortLatencyMillisP95: 0
      ).level,
      .unsupported
    )
    XCTAssertEqual(
      VoiceWhisperCertificationClassifier.classify(
        profile: profile(partialInterval: 750),
        rtfP95: 0.2,
        transcriptCorrect: true,
        maxThermalStatus: 3,
        abortLatencyMillisP95: 0
      ),
      VoiceWhisperCertificationClassification(
        level: .remoteRecommended,
        mode: .remoteNode,
        partialIntervalMillis: 0,
        failureReason: "Benchmark reached severe thermal pressure"
      )
    )
    XCTAssertEqual(
      VoiceWhisperCertificationClassifier.classify(
        profile: profile(partialInterval: 750),
        rtfP95: 0.2,
        transcriptCorrect: true,
        maxThermalStatus: 0,
        abortLatencyMillisP95: 301
      ).failureReason,
      "Cancellation latency exceeded the safe limit"
    )
  }

  private func profile(partialInterval: Int64) -> VoiceWhisperModelProfile {
    VoiceWhisperModelProfile(
      id: "tiny",
      displayName: "Tiny",
      fileName: "ggml-tiny.bin",
      sizeLabel: "test",
      expectedSizeBytes: 1_024,
      sha256: String(repeating: "a", count: 64),
      defaultPartialIntervalMillis: partialInterval
    )
  }
}
