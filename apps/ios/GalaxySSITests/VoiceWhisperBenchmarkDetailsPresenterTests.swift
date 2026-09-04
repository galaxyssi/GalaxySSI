import XCTest
@testable import GalaxySSI

final class VoiceWhisperBenchmarkDetailsPresenterTests: XCTestCase {
  func testPresentationFormatsAndroidStyleMetrics() {
    let model = profile()
    let record = VoiceWhisperBenchmarkRecord(
      certification: VoiceWhisperCertification(
        key: key(for: model),
        level: .realtime,
        recommendedMode: .realtimePartial,
        recommendedThreadCount: 4,
        recommendedPartialIntervalMillis: 750,
        warmRtfP50: 0.25,
        warmRtfP95: 0.5,
        loadTimeMillisP95: 123,
        peakPssBytes: 512 * 1_024 * 1_024,
        maxThermalStatus: 2,
        abortLatencyMillisP95: 80,
        createdAtEpochMillis: 2_000
      ),
      measurements: [
        measurement(loadKind: .cold, load: 300, partial: 120, final: 0, rss: 400, native: 120),
        measurement(loadKind: .hot, load: 180, partial: 0, final: 450, rss: 420, native: 140)
      ]
    )

    let presentation = VoiceWhisperBenchmarkDetailsPresenter.presentation(model: model, record: record)

    XCTAssertEqual(presentation.title, "Tiny device certification")
    XCTAssertTrue(presentation.message.contains("Recommended: Real-time certified"))
    XCTAssertTrue(presentation.message.contains("RTF p50 / p95: 0.25 / 0.50"))
    XCTAssertTrue(presentation.message.contains("Peak PSS: 512.0 MB"))
    XCTAssertTrue(presentation.message.contains("Best threads: 4"))
    XCTAssertTrue(presentation.message.contains("Thermal status: 2"))
    XCTAssertTrue(presentation.message.contains("Cancellation p95: 80 ms"))
    XCTAssertTrue(presentation.message.contains("Cold / hot load p95: 300 / 180 ms"))
    XCTAssertTrue(presentation.message.contains("First partial / final tail p95: 120 / 450 ms"))
    XCTAssertTrue(presentation.message.contains("Peak RSS / native heap: 420 B / 140 B"))
  }

  func testPresentationIncludesFailureReason() {
    let model = profile()
    let record = VoiceWhisperBenchmarkRecord(
      certification: VoiceWhisperCertification(
        key: key(for: model),
        level: .unsupported,
        recommendedMode: .remoteNode,
        recommendedThreadCount: 1,
        recommendedPartialIntervalMillis: 0,
        warmRtfP50: 0,
        warmRtfP95: 0,
        createdAtEpochMillis: 2_000,
        failureReason: "Cancellation latency exceeded the safe limit"
      )
    )

    let presentation = VoiceWhisperBenchmarkDetailsPresenter.presentation(model: model, record: record)

    XCTAssertTrue(presentation.message.contains("Recommended: Unsupported on this device"))
    XCTAssertTrue(presentation.message.contains("Reason: Cancellation latency exceeded the safe limit"))
  }

  private func profile() -> VoiceWhisperModelProfile {
    VoiceWhisperModelProfile(
      id: "tiny",
      family: .tiny,
      displayName: "Tiny",
      fileName: "ggml-tiny.bin",
      sizeLabel: "test",
      expectedSizeBytes: 1_024,
      sha256: String(repeating: "a", count: 64),
      recommendedMode: .realtimePartial,
      minAvailableRamBytes: 128 * 1_024 * 1_024,
      defaultPartialIntervalMillis: 750
    )
  }

  private func key(for model: VoiceWhisperModelProfile) -> VoiceWhisperBenchmarkKey {
    VoiceWhisperBenchmarkKey(
      manufacturer: "Apple",
      device: "iPhone",
      soc: "A17",
      osVersion: "17.0",
      appVersionCode: 1,
      whisperNativeVersion: "test",
      nativeBuildFingerprint: "test",
      modelProfileId: model.id,
      modelSha256: model.sha256,
      benchmarkAudioVersion: "test"
    )
  }

  private func measurement(
    loadKind: VoiceWhisperBenchmarkLoadKind,
    load: Int64,
    partial: Int64,
    final: Int64,
    rss: Int64,
    native: Int64
  ) -> VoiceWhisperBenchmarkMeasurement {
    VoiceWhisperBenchmarkMeasurement(
      threadCount: 4,
      loadKind: loadKind,
      audioDurationMillis: 3_000,
      decodeDurationMillis: 1_000,
      realTimeFactor: 0.33,
      loadDurationMillis: load,
      peakRssBytes: rss,
      peakNativeAllocatedBytes: native,
      firstPartialLatencyMillis: partial,
      finalTailLatencyMillis: final,
      transcriptCorrect: true
    )
  }
}
