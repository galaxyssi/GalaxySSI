import XCTest
@testable import GalaxySSI

final class VoiceLocalWhisperASRTests: XCTestCase {
  func testLocalWhisperASRDecodesTracesAndInvokesRuntime() async throws {
    var elapsedNs: Int64 = 1_000_000_000
    var traces: [String] = []
    var loadedModelIds: [String] = []
    var unloadedModelIds: [String?] = []
    let runtime = FakeWhisperRuntime(response: "  hello from whisper  ")
    let modelFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("ggml-base.bin")
    let service = VoiceLocalWhisperASR(
      runtime: runtime,
      modelAvailable: { $0.id == "base" },
      modelFileProvider: { _ in modelFileURL },
      markModelLoaded: { loadedModelIds.append($0) },
      markModelUnloaded: { unloadedModelIds.append($0) },
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
    XCTAssertEqual(result.selectedModel.id, "base")
    XCTAssertEqual(result.model.id, "base")
    XCTAssertEqual(result.language, "en")
    XCTAssertEqual(result.sampleRateHz, 16_000)
    XCTAssertEqual(runtime.requests.single?.model.id, "base")
    XCTAssertEqual(Optional(result.threadCount), runtime.requests.single?.threadCount)
    XCTAssertEqual(runtime.requests.single?.modelFileURL, modelFileURL)
    XCTAssertEqual(runtime.requests.single?.language, "en")
    XCTAssertTrue(runtime.requests.single?.samples.isEmpty == false)
    XCTAssertEqual(loadedModelIds, ["base"])
    service.release()
    XCTAssertEqual(unloadedModelIds, [Optional("base")])
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
      modelFileProvider: { _ in XCTFail("Model file should not be resolved"); return nil },
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

  func testRuntimeDecisionCanSwitchCertifiedModelAndThreadCount() async throws {
    let runtime = FakeWhisperRuntime(response: "policy model")
    let tinyURL = FileManager.default.temporaryDirectory.appendingPathComponent("ggml-tiny.bin")
    let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent("ggml-base.bin")
    let service = VoiceLocalWhisperASR(
      runtime: runtime,
      modelAvailable: { ["tiny", "base"].contains($0.id) },
      modelFileProvider: { model in model.id == "base" ? baseURL : tinyURL },
      runtimeDecisionProvider: { _, selected, _ in
        VoiceWhisperRuntimeDecision(
          provider: .local,
          fastProfileId: selected.id == "tiny" ? "base" : selected.id,
          fastMode: .finalOnly,
          accurateProfileId: nil,
          accurateMode: nil,
          partialIntervalMillis: nil,
          threadCount: 6,
          runSecondPass: false,
          reasons: ["test decision"]
        )
      }
    )

    let result = try await service.transcribe(
      audioFile: try waveFile(),
      settings: settings(asrModelId: "tiny", runtimeMode: .automatic),
      language: "en-US",
      traceId: "trace-policy-asr"
    )

    XCTAssertEqual(result.model.id, "base")
    XCTAssertEqual(result.selectedModel.id, "tiny")
    XCTAssertEqual(runtime.requests.single?.model.id, "base")
    XCTAssertEqual(runtime.requests.single?.modelFileURL, baseURL)
    XCTAssertEqual(runtime.requests.single?.threadCount, 6)
    XCTAssertEqual(result.threadCount, 6)
    XCTAssertEqual(result.runtimeDecision?.provider, .some(.local))
    XCTAssertNil(result.secondPassProfileId)
  }

  func testRuntimeDecisionReportsSecondPassRecommendation() async throws {
    let runtime = FakeWhisperRuntime(response: "accurate later")
    let service = VoiceLocalWhisperASR(
      runtime: runtime,
      modelAvailable: { $0.id == "tiny" },
      runtimeDecisionProvider: { _, selected, _ in
        VoiceWhisperRuntimeDecision(
          provider: .local,
          fastProfileId: selected.id,
          fastMode: .finalOnly,
          accurateProfileId: "base",
          accurateMode: .secondPass,
          partialIntervalMillis: nil,
          threadCount: 2,
          runSecondPass: true,
          reasons: ["accuracy pass"]
        )
      }
    )

    let result = try await service.transcribe(
      audioFile: try waveFile(),
      settings: settings(asrModelId: "tiny", runtimeMode: .automatic),
      language: "en-US",
      traceId: "trace-second-pass"
    )

    XCTAssertEqual(result.model.id, "tiny")
    XCTAssertEqual(result.threadCount, 2)
    XCTAssertEqual(result.runtimeDecision?.accurateProfileId, .some("base"))
    XCTAssertEqual(result.secondPassProfileId, .some("base"))
    XCTAssertEqual(result.secondPassMode, .some(.secondPass))
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

  private func settings(
    asrModelId: String,
    runtimeMode: VoiceWhisperUserVoiceMode = .manual
  ) -> VoiceSettings {
    VoiceSettings(
      wakeListeningEnabled: false,
      speechRecognitionEnabled: true,
      textToSpeechEnabled: true,
      autoSendTranscripts: false,
      preferredLocaleIdentifier: "en-US",
      asrModelId: asrModelId,
      asrRuntimeMode: runtimeMode
    )
  }
}

private extension Array {
  var single: Element? {
    count == 1 ? first : nil
  }
}
