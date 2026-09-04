import XCTest
@testable import GalaxySSI

final class VoiceWhisperBenchmarkRecordBuilderTests: XCTestCase {
  func testCertifyBuildsRealtimeRecordFromStableMeasurements() {
    let profile = modelProfile()
    let key = benchmarkKey(for: profile)
    let stability = [
      measurement(thread: 4, rtf: 0.40, transcriptCorrect: true),
      measurement(thread: 4, rtf: 0.50, transcriptCorrect: true),
      measurement(thread: 4, rtf: 0.45, transcriptCorrect: false)
    ]

    let record = VoiceWhisperBenchmarkRecordBuilder.certify(
      key: key,
      profile: profile,
      measurements: stability,
      stabilityMeasurements: stability,
      verificationDurationMillis: 120,
      abortLatenciesMillis: [30, 40, 50],
      highPerformanceCoreCount: 6,
      threadCandidates: [2, 3, 4, 6],
      threadCount: 4,
      createdAtEpochMillis: 1_000
    )

    XCTAssertEqual(record.certification.level, .realtime)
    XCTAssertEqual(record.certification.recommendedMode, .realtimePartial)
    XCTAssertEqual(record.certification.recommendedThreadCount, 4)
    XCTAssertEqual(record.certification.warmRtfP95, 0.5)
    XCTAssertEqual(record.certification.abortLatencyMillisP95, 50)
    XCTAssertEqual(record.verificationDurationMillis, 120)
    XCTAssertEqual(record.threadCandidates, [2, 3, 4, 6])
  }

  func testTerminalRecordKeepsFailureReasonAndThermalFallback() {
    let profile = modelProfile()
    let record = VoiceWhisperBenchmarkRecordBuilder.terminalRecord(
      key: benchmarkKey(for: profile),
      profile: profile,
      level: .remoteRecommended,
      reason: "too hot",
      verificationDurationMillis: 20,
      highPerformanceCoreCount: 4,
      threadCandidates: [2, 4],
      fallbackThermalStatus: 3,
      createdAtEpochMillis: 2_000
    )

    XCTAssertEqual(record.certification.level, .remoteRecommended)
    XCTAssertEqual(record.certification.recommendedMode, .remoteNode)
    XCTAssertEqual(record.certification.recommendedThreadCount, 2)
    XCTAssertEqual(record.certification.maxThermalStatus, 3)
    XCTAssertEqual(record.certification.failureReason, "too hot")
  }

  func testPreflightFailureMatchesAndroidPolicy() {
    let profile = modelProfile(minRam: 512 * 1_024 * 1_024)

    XCTAssertEqual(
      VoiceWhisperBenchmarkRecordBuilder.preflightFailure(
        profile: profile,
        system: VoiceWhisperBenchmarkSystemSnapshot(availableMemoryBytes: 2_000, systemLowMemory: true)
      ),
      "iOS reported system-wide low memory"
    )
    XCTAssertEqual(
      VoiceWhisperBenchmarkRecordBuilder.preflightFailure(
        profile: profile,
        system: VoiceWhisperBenchmarkSystemSnapshot(availableMemoryBytes: 512 * 1_024 * 1_024)
      ),
      "The model does not have enough memory headroom on this device"
    )
    XCTAssertEqual(
      VoiceWhisperBenchmarkRecordBuilder.preflightFailure(
        profile: profile,
        system: VoiceWhisperBenchmarkSystemSnapshot(
          availableMemoryBytes: 2 * 1_024 * 1_024 * 1_024,
          thermalStatus: 3
        )
      ),
      "The device is too hot to certify this model"
    )
  }

  func testTranscriptMatchesSimplifiedAndTraditionalTokens() {
    XCTAssertTrue(
      VoiceWhisperBenchmarkRecordBuilder.transcriptMatches(
        "\u{9019}\u{662f}\u{4e00}\u{6bb5}\u{8a9e}\u{97f3}\u{6e2c}\u{8a66}\u{ff0c}\u{61c9}\u{8a72}\u{53ef}\u{4ee5}\u{8b58}\u{5225}\u{3002}",
        expectedTokens: ["\u{8bed}\u{97f3}", "\u{6d4b}\u{8bd5}", "\u{8bc6}\u{522b}"]
      )
    )
    XCTAssertFalse(
      VoiceWhisperBenchmarkRecordBuilder.transcriptMatches(
        "completely different",
        expectedTokens: ["\u{8bed}\u{97f3}", "\u{6d4b}\u{8bd5}", "\u{8bc6}\u{522b}"]
      )
    )
  }

  func testThermalModerateDefersBenchmark() {
    XCTAssertTrue(
      VoiceWhisperBenchmarkRecordBuilder.thermalAllowsBenchmark(
        VoiceWhisperBenchmarkSystemSnapshot(availableMemoryBytes: 1_000, thermalStatus: 1)
      )
    )
    XCTAssertFalse(
      VoiceWhisperBenchmarkRecordBuilder.thermalAllowsBenchmark(
        VoiceWhisperBenchmarkSystemSnapshot(availableMemoryBytes: 1_000, thermalStatus: 2)
      )
    )
  }

  private func modelProfile(minRam: Int64 = 128 * 1_024 * 1_024) -> VoiceWhisperModelProfile {
    VoiceWhisperModelProfile(
      id: "tiny",
      family: .tiny,
      displayName: "Tiny",
      fileName: "ggml-tiny.bin",
      sizeLabel: "test",
      expectedSizeBytes: 1_024,
      sha256: String(repeating: "a", count: 64),
      recommendedMode: .realtimePartial,
      minAvailableRamBytes: minRam,
      defaultPartialIntervalMillis: 750
    )
  }

  private func benchmarkKey(for profile: VoiceWhisperModelProfile) -> VoiceWhisperBenchmarkKey {
    VoiceWhisperBenchmarkKey(
      manufacturer: "Apple",
      device: "iPhone",
      soc: "A17",
      osVersion: "17.0",
      appVersionCode: 1,
      whisperNativeVersion: "test",
      nativeBuildFingerprint: "test",
      modelProfileId: profile.id,
      modelSha256: profile.sha256,
      benchmarkAudioVersion: "test"
    )
  }

  private func measurement(
    thread: Int,
    rtf: Double,
    transcriptCorrect: Bool
  ) -> VoiceWhisperBenchmarkMeasurement {
    VoiceWhisperBenchmarkMeasurement(
      threadCount: thread,
      audioDurationMillis: 10_000,
      decodeDurationMillis: Int64((rtf * 10_000).rounded()),
      realTimeFactor: rtf,
      loadDurationMillis: 200,
      peakPssBytes: 256 * 1_024 * 1_024,
      thermalStatusEnd: 1,
      transcriptCorrect: transcriptCorrect
    )
  }
}
