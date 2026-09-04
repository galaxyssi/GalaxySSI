import XCTest
@testable import GalaxySSI

final class VoiceWhisperBenchmarkPlanningTests: XCTestCase {
  func testAudioValidationAndWindowPadding() throws {
    let pcm = Array(repeating: Int16(7), count: VoiceWhisperBenchmarkAudio.sampleRateHz * 5)
    let audio = try VoiceWhisperBenchmarkAudio(
      version: " zh_cn_v2 ",
      pcm16: pcm,
      expectedTokens: [" \u{6d4b}\u{8bd5} "]
    )

    XCTAssertEqual(audio.version, "zh_cn_v2")
    XCTAssertEqual(audio.expectedTokens, ["\u{6d4b}\u{8bd5}"])
    XCTAssertEqual(audio.window(durationMillis: 1_000).count, VoiceWhisperBenchmarkAudio.sampleRateHz)

    let padded = audio.window(durationMillis: 6_000)
    XCTAssertEqual(padded.count, VoiceWhisperBenchmarkAudio.sampleRateHz * 6)
    XCTAssertEqual(padded.last, 0)
  }

  func testRejectsInvalidAudio() {
    XCTAssertThrowsError(
      try VoiceWhisperBenchmarkAudio(version: "", pcm16: [1, 2, 3], expectedTokens: [])
    ) { error in
      XCTAssertEqual(error as? VoiceWhisperBenchmarkPlanningError, .invalidAudio)
    }
  }

  func testPlanClampsInputsAndComputesTotalSteps() {
    let plan = VoiceWhisperBenchmarkPlan(
      candidateAudioDurationsMillis: [],
      candidateIterations: 99,
      stabilityAudioDurationMillis: 0,
      stabilityIterations: 1,
      abortIterations: 99,
      metricSampleIntervalMillis: 1,
      abortDelayMillis: 2_000,
      abortTimeoutMillis: 100
    )

    XCTAssertEqual(plan.candidateAudioDurationsMillis, [3_000, 5_000])
    XCTAssertEqual(plan.candidateIterations, 5)
    XCTAssertEqual(plan.stabilityIterations, 3)
    XCTAssertEqual(plan.abortIterations, 5)
    XCTAssertEqual(plan.metricSampleIntervalMillis, 10)
    XCTAssertEqual(plan.abortDelayMillis, 1_000)
    XCTAssertEqual(plan.abortTimeoutMillis, 500)
    XCTAssertEqual(plan.totalSteps(threadCandidateCount: 2), 31)
  }

  func testThreadCandidatesMirrorAndroidSearch() {
    XCTAssertEqual(VoiceWhisperThreadSearch.candidates(highPerformanceCoreCount: 1), [1])
    XCTAssertEqual(VoiceWhisperThreadSearch.candidates(highPerformanceCoreCount: 4), [2, 3, 4])
    XCTAssertEqual(VoiceWhisperThreadSearch.candidates(highPerformanceCoreCount: 8), [2, 3, 4, 6, 8])
  }

  func testThreadSearchSelectsStableLowScoreCandidate() throws {
    let measurements = [
      measurement(thread: 2, rtf: 0.42),
      measurement(thread: 2, rtf: 0.46),
      measurement(thread: 4, rtf: 0.35),
      measurement(thread: 4, rtf: 0.90)
    ]

    XCTAssertEqual(try VoiceWhisperThreadSearch.selectBest(measurements: measurements), 2)
    XCTAssertThrowsError(try VoiceWhisperThreadSearch.selectBest(measurements: [])) { error in
      XCTAssertEqual(error as? VoiceWhisperBenchmarkPlanningError, .missingThreadMeasurements)
    }
  }

  func testProgressClampsVisibleFields() {
    let progress = VoiceWhisperBenchmarkProgress(
      stage: .searchingThreads,
      completedSteps: 20,
      totalSteps: 10,
      threadCount: 99,
      detail: String(repeating: "x", count: 300)
    )

    XCTAssertEqual(progress.completedSteps, 10)
    XCTAssertEqual(progress.threadCount, 16)
    XCTAssertEqual(progress.detail.count, 240)
  }

  private func measurement(
    thread: Int,
    rtf: Double,
    thermal: Int = 0,
    energy: Int64? = nil
  ) -> VoiceWhisperBenchmarkMeasurement {
    VoiceWhisperBenchmarkMeasurement(
      threadCount: thread,
      audioDurationMillis: 3_000,
      decodeDurationMillis: Int64((rtf * 3_000).rounded()),
      realTimeFactor: rtf,
      energyDeltaNwh: energy,
      thermalStatusEnd: thermal,
      transcriptCorrect: true
    )
  }
}
