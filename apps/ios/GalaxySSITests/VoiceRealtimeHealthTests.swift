import XCTest
@testable import GalaxySSI

final class VoiceRealtimeHealthTests: XCTestCase {
  override func setUp() {
    super.setUp()
    VoiceRuntimeHealthRegistry.resetForTests()
  }

  func testActiveRuntimeWinsWhenDependenciesAreReady() {
    let snapshot = evaluate(record: VoiceRuntimeHealthRecord(active: true))

    XCTAssertEqual(snapshot[.asr].state, .active)
  }

  func testDisabledVoiceHealthIsExplicit() {
    let snapshot = evaluate(enabled: false)

    XCTAssertEqual(snapshot[.asr].state, .disabled)
    XCTAssertEqual(snapshot[.asr].issue, .disabled)
  }

  func testMissingDependencyBlocksBeforeRuntimeState() {
    let snapshot = evaluate(
      dependency: VoiceHealthDependency(ready: false, issue: .modelMissing),
      record: VoiceRuntimeHealthRecord(active: true)
    )

    XCTAssertEqual(snapshot[.asr].state, .blocked)
    XCTAssertEqual(snapshot[.asr].issue, .modelMissing)
  }

  func testRecentFailureProducesDegradedHealth() {
    let now: Int64 = 500_000
    let snapshot = evaluate(
      record: VoiceRuntimeHealthRecord(
        lastFailureAtMillis: now - 2_000,
        lastFailureReason: "recognizer busy"
      ),
      nowMillis: now
    )

    XCTAssertEqual(snapshot[.asr].state, .degraded)
    XCTAssertEqual(snapshot[.asr].issue, .recentFailure)
  }

  func testNewerSuccessRecoversRecentFailure() {
    let now: Int64 = 500_000
    let snapshot = evaluate(
      record: VoiceRuntimeHealthRecord(
        lastSuccessAtMillis: now - 1_000,
        lastFailureAtMillis: now - 4_000
      ),
      nowMillis: now
    )

    XCTAssertEqual(snapshot[.asr].state, .healthy)
  }

  func testStaleSuccessReturnsToReadyInsteadOfPermanentHealth() {
    let now = VoiceRealtimeHealthPolicy.successFreshnessMillis + 50_000
    let snapshot = evaluate(
      record: VoiceRuntimeHealthRecord(lastSuccessAtMillis: 1),
      nowMillis: now
    )

    XCTAssertEqual(snapshot[.asr].state, .ready)
  }

  func testRuntimeHealthRegistryPreservesFailureUntilRealSuccess() {
    VoiceRuntimeHealthRegistry.begin(.localWhisperASR, nowMillis: 100)
    VoiceRuntimeHealthRegistry.failure(
      .localWhisperASR,
      reason: " model   failed ",
      nowMillis: 200
    )
    let failed = VoiceRuntimeHealthRegistry.record(.localWhisperASR)
    VoiceRuntimeHealthRegistry.success(.localWhisperASR, nowMillis: 300)
    let recovered = VoiceRuntimeHealthRegistry.record(.localWhisperASR)

    XCTAssertFalse(failed.active)
    XCTAssertEqual(failed.lastFailureReason, "model failed")
    XCTAssertEqual(failed.lastEventAtMillis, 200)
    XCTAssertEqual(recovered.lastSuccessAtMillis, 300)
  }

  func testVoiceRealtimeHealthModelsUseAndroidWireNames() throws {
    let snapshot = VoiceRealtimeHealthPolicy.evaluate(
      probes: [
        VoiceHealthProbe(
          component: .asr,
          enabled: true,
          provider: "Local Whisper",
          dependency: VoiceHealthDependency(ready: false, issue: .runtimeMissing),
          runtime: VoiceRuntimeHealthRecord(lastFailureAtMillis: 200, lastFailureReason: "missing")
        )
      ],
      nowMillis: 1_000
    )
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try JSONEncoder().encode(snapshot)) as? [String: Any]
    )
    let entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
    let runtime = try XCTUnwrap(entries.first?["runtime"] as? [String: Any])

    XCTAssertEqual((object["checked_at_millis"] as? NSNumber)?.int64Value, 1_000)
    XCTAssertEqual(entries.first?["component"] as? String, "ASR")
    XCTAssertEqual(entries.first?["state"] as? String, "BLOCKED")
    XCTAssertEqual(entries.first?["issue"] as? String, "RUNTIME_MISSING")
    XCTAssertEqual((runtime["last_failure_at_millis"] as? NSNumber)?.int64Value, 200)
    XCTAssertEqual(runtime["last_failure_reason"] as? String, "missing")
    XCTAssertEqual(VoiceRuntimeChannel.androidSystemASR.rawValue, "ANDROID_SYSTEM_ASR")
  }

  func testVoiceRealtimeHealthDetectorMapsIOSSettingsAndCapabilities() {
    VoiceRuntimeHealthRegistry.success(.androidWakeASR, nowMillis: 900)
    VoiceRuntimeHealthRegistry.failure(.localWhisperASR, reason: "model crashed", nowMillis: 950)
    let settings = VoiceSettings(
      wakeListeningEnabled: true,
      speechRecognitionEnabled: true,
      textToSpeechEnabled: false,
      autoSendTranscripts: false,
      preferredLocaleIdentifier: "en-US",
      ttsProvider: .microsoftEdge
    )
    let capabilities = VoiceProviderCapabilitySnapshot(
      capabilities: [
        capability(.androidSystemASR, .ready, .ready),
        capability(.whisperCpp, .ready, .ready, metadata: ["model_name": "Whisper Base"]),
        capability(.androidSystemTTS, .unavailable, .ttsEngineMissing),
        capability(.microsoftEdgeTTS, .needsNetwork, .networkRequired),
      ],
      checkedAtMillis: 1_000
    )
    let snapshot = VoiceRealtimeHealthDetector.detect(
      settings: settings,
      capabilities: capabilities,
      checkedAtMillis: 1_000
    )

    XCTAssertEqual(snapshot[.wakeWord].provider, "iOS Speech wake listener")
    XCTAssertEqual(snapshot[.wakeWord].state, .healthy)
    XCTAssertEqual(snapshot[.asr].provider, "Local Whisper / Whisper Base")
    XCTAssertEqual(snapshot[.asr].state, .degraded)
    XCTAssertEqual(snapshot[.tts].provider, "Microsoft Edge TTS")
    XCTAssertEqual(snapshot[.tts].state, .disabled)
    XCTAssertEqual(snapshot[.tts].issue, .disabled)
  }

  func testVoiceRealtimeHealthDetectorUsesSelectedSystemTtsProvider() {
    let settings = VoiceSettings(
      wakeListeningEnabled: false,
      speechRecognitionEnabled: false,
      textToSpeechEnabled: true,
      autoSendTranscripts: false,
      preferredLocaleIdentifier: "en-US",
      ttsProvider: .system
    )
    let capabilities = VoiceProviderCapabilitySnapshot(
      capabilities: [
        capability(.androidSystemTTS, .ready, .ready),
        capability(.microsoftEdgeTTS, .needsNetwork, .networkRequired),
      ],
      checkedAtMillis: 1_000
    )

    let snapshot = VoiceRealtimeHealthDetector.detect(
      settings: settings,
      capabilities: capabilities,
      checkedAtMillis: 1_000
    )

    XCTAssertEqual(snapshot[.tts].provider, "iOS System TTS")
    XCTAssertEqual(snapshot[.tts].state, .ready)
    XCTAssertEqual(snapshot[.tts].issue, .none)
  }

  func testVoiceRealtimeHealthDetectorFallsBackToIOSSpeechRuntimeWhenWhisperBlocked() {
    VoiceRuntimeHealthRegistry.success(.androidSystemASR, nowMillis: 950)
    let settings = VoiceSettings(
      wakeListeningEnabled: false,
      speechRecognitionEnabled: true,
      textToSpeechEnabled: true,
      autoSendTranscripts: false,
      preferredLocaleIdentifier: "zh-Hans"
    )
    let capabilities = VoiceProviderCapabilitySnapshot(
      capabilities: [
        capability(.androidSystemASR, .ready, .ready),
        capability(.whisperCpp, .needsDownload, .whisperModelMissing),
        capability(.androidSystemTTS, .ready, .ready),
      ],
      checkedAtMillis: 1_000
    )
    let snapshot = VoiceRealtimeHealthDetector.detect(
      settings: settings,
      capabilities: capabilities,
      checkedAtMillis: 1_000
    )

    XCTAssertEqual(snapshot[.asr].provider, "iOS Speech / zh-Hans")
    XCTAssertEqual(snapshot[.asr].state, .healthy)
    XCTAssertEqual(snapshot[.asr].runtime.lastSuccessAtMillis, 950)
  }

  func testVoiceRealtimeHealthDependencyMapsCapabilityReasons() {
    let modelMissing = VoiceRealtimeHealthDetector.dependency(
      for: capability(.whisperCpp, .needsDownload, .whisperModelMissing)
    )
    let networkMissing = VoiceRealtimeHealthDetector.dependency(
      for: capability(.microsoftEdgeTTS, .needsNetwork, .networkRequired)
    )
    let unsupported = VoiceRealtimeHealthDetector.dependency(
      for: capability(.androidSystemTTS, .unavailable, .ttsLanguageUnsupported)
    )

    XCTAssertEqual(modelMissing.issue, .modelMissing)
    XCTAssertEqual(networkMissing.issue, .networkRequired)
    XCTAssertEqual(unsupported.issue, .languageUnsupported)
  }

  private func evaluate(
    enabled: Bool = true,
    dependency: VoiceHealthDependency = VoiceHealthDependency(ready: true),
    record: VoiceRuntimeHealthRecord = VoiceRuntimeHealthRecord(),
    nowMillis: Int64 = 1_000
  ) -> VoiceRealtimeHealthSnapshot {
    VoiceRealtimeHealthPolicy.evaluate(
      probes: [
        VoiceHealthProbe(
          component: .asr,
          enabled: enabled,
          provider: "Local Whisper",
          dependency: dependency,
          runtime: record
        )
      ],
      nowMillis: nowMillis
    )
  }

  private func capability(
    _ id: VoiceProviderCapabilityId,
    _ state: VoiceProviderCapabilityState,
    _ reason: VoiceProviderCapabilityReason,
    metadata: [String: String] = [:]
  ) -> VoiceProviderCapability {
    VoiceProviderCapability(id: id, state: state, reason: reason, metadata: metadata)
  }
}
