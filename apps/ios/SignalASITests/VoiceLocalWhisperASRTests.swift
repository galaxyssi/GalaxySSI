import XCTest
@testable import SignalASI

final class VoiceLocalWhisperASRTests: XCTestCase {
  func testLocalWhisperASRDecodesTracesAndInvokesRuntime() async throws {
    var elapsedNs: Int64 = 1_000_000_000
    var traces: [String] = []
    let runtime = FakeWhisperRuntime(response: "  hello from whisper  ")
    let service = VoiceLocalWhisperASR(
      runtime: runtime,
      modelAvailable: { $0.id == "base" },
      elapsedClock: {
        elapsedNs += 100_000_000
        return elapsedNs
      },
      trace: { _, event, _, _ in traces.append(event) }
    )
    let result = try await service.transcribe(
      audioFile: try waveFile(),
      settings: settings(asrModelId: "base"),
      language: "en-US",
      traceId: "trace-local-asr"
    )

    XCTAssertEqual(result.text, "hello from whisper")
    XCTAssertEqual(result.model.id, "base")
    XCTAssertEqual(result.language, "en")
    XCTAssertEqual(result.sampleRateHz, 16_000)
    XCTAssertEqual(runtime.requests.single?.model.id, "base")
    XCTAssertEqual(runtime.requests.single?.language, "en")
    XCTAssertTrue(runtime.requests.single?.samples.isEmpty == false)
    XCTAssertEqual(traces, [
      VoiceTraceEvents.asrFinalStarted,
      VoiceTraceEvents.asrDecodeStarted,
      VoiceTraceEvents.asrDecodeCompleted,
      VoiceTraceEvents.asrModelLoadStarted,
      VoiceTraceEvents.whisperFullStarted,
      VoiceTraceEvents.asrModelLoadCompleted,
      VoiceTraceEvents.whisperFullCompleted,
      VoiceTraceEvents.asrFinalReceived,
    ])
  }

  func testLocalWhisperASRReportsMissingModelWithoutInvokingRuntime() async throws {
    var traces: [String] = []
    let runtime = FakeWhisperRuntime(response: "unused")
    let service = VoiceLocalWhisperASR(
      runtime: runtime,
      modelAvailable: { _ in false },
      trace: { _, event, _, _ in traces.append(event) }
    )

    do {
      _ = try await service.transcribe(
        audioFile: try waveFile(),
        settings: settings(asrModelId: "small"),
        traceId: "trace-missing-model"
      )
      XCTFail("Expected missing model")
    } catch {
      XCTAssertEqual(error as? VoiceLocalWhisperASRError, .modelUnavailable("small"))
    }

    XCTAssertTrue(runtime.requests.isEmpty)
    XCTAssertTrue(traces.contains(VoiceTraceEvents.asrFinalFailed))
  }

  func testLanguageAndTranscriptPolicyMatchesAndroidLocalWhisperRules() {
    XCTAssertEqual(VoiceWhisperLanguagePolicy.normalizedRecognitionLanguage("zh-CN"), "zh")
    XCTAssertEqual(VoiceWhisperLanguagePolicy.normalizedRecognitionLanguage("en-US"), "en")
    XCTAssertEqual(VoiceWhisperLanguagePolicy.normalizedRecognitionLanguage("fr-FR"), "auto")
    XCTAssertEqual(
      VoiceWhisperLanguagePolicy.normalizeTranscript("  hello  ", language: "en-US"),
      "hello"
    )
  }

  private final class FakeWhisperRuntime: VoiceLocalWhisperRuntime {
    var requests: [VoiceLocalWhisperRuntimeRequest] = []
    let response: String

    init(response: String) {
      self.response = response
    }

    func transcribe(_ request: VoiceLocalWhisperRuntimeRequest) async throws -> String {
      requests.append(request)
      return response
    }

    func release() {}
  }

  private func waveFile() throws -> URL {
    let snapshot = PcmSnapshot(
      samples: Array(repeating: Int16(2_000), count: 320),
      sampleRateHz: 16_000,
      speechDetected: true,
      speechStartSample: 0,
      speechEndSampleExclusive: 320,
      captureStartSample: 0,
      captureEndSampleExclusive: 320
    )
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("wav")
    try PcmWaveFileAdapter.encode(snapshot).write(to: url)
    return url
  }

  private func settings(asrModelId: String) -> VoiceSettings {
    VoiceSettings(
      wakeListeningEnabled: false,
      speechRecognitionEnabled: true,
      textToSpeechEnabled: true,
      autoSendTranscripts: false,
      preferredLocaleIdentifier: "en-US",
      asrModelId: asrModelId
    )
  }
}

private extension Array {
  var single: Element? {
    count == 1 ? first : nil
  }
}
