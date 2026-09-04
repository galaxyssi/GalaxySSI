import XCTest
@testable import GalaxySSI

final class VoiceProviderCapabilityTests: XCTestCase {
  func testVoiceProviderCapabilityPolicyReportsReadyProviders() {
    let snapshot = VoiceProviderCapabilityPolicy.evaluate(probe(), checkedAtMillis: 1_000)

    XCTAssertTrue(snapshot.capabilities.allSatisfy { $0.ready })
    XCTAssertEqual(snapshot.checkedAtMillis, 1_000)
    XCTAssertEqual(snapshot.readyIds, VoiceProviderCapabilityId.allCases)
    XCTAssertEqual(snapshot[.whisperCpp].metadata["model_id"], "whisper-base")
    XCTAssertEqual(snapshot[.androidSystemTTS].metadata["engine_count"], "2")
  }

  func testVoiceProviderCapabilityPolicyOrdersMissingMicrophoneBeforeRuntimeAndPermission() {
    let snapshot = VoiceProviderCapabilityPolicy.evaluate(
      probe(
        hasMicrophone: false,
        microphonePermissionGranted: false,
        whisperRuntimeAvailable: false,
        whisperModelAvailable: false
      )
    )

    XCTAssertEqual(snapshot[.whisperCpp].state, .unavailable)
    XCTAssertEqual(snapshot[.whisperCpp].reason, .microphoneMissing)
    XCTAssertEqual(snapshot[.androidSystemASR].reason, .microphoneMissing)
    XCTAssertEqual(snapshot[.cloudASR].reason, .microphoneMissing)
  }

  func testVoiceProviderCapabilityPolicyHandlesWhisperRuntimeModelAndPermissionGates() {
    let runtimeMissing = VoiceProviderCapabilityPolicy.evaluate(
      probe(whisperRuntimeAvailable: false)
    )[.whisperCpp]
    let modelMissing = VoiceProviderCapabilityPolicy.evaluate(
      probe(whisperModelAvailable: false)
    )[.whisperCpp]
    let permissionMissing = VoiceProviderCapabilityPolicy.evaluate(
      probe(microphonePermissionGranted: false)
    )[.whisperCpp]

    XCTAssertEqual(runtimeMissing.state, .unavailable)
    XCTAssertEqual(runtimeMissing.reason, .whisperRuntimeMissing)
    XCTAssertEqual(modelMissing.state, .needsDownload)
    XCTAssertEqual(modelMissing.reason, .whisperModelMissing)
    XCTAssertEqual(modelMissing.metadata["model_name"], "Whisper Base")
    XCTAssertEqual(permissionMissing.state, .needsPermission)
    XCTAssertEqual(permissionMissing.reason, .microphonePermissionRequired)
  }

  func testVoiceProviderCapabilityPolicyHandlesSystemOfflineAndCloudAsrGates() {
    let systemMissing = VoiceProviderCapabilityPolicy.evaluate(
      probe(systemAsrAvailable: false)
    )
    let offlineMissing = VoiceProviderCapabilityPolicy.evaluate(
      probe(offlineAsrAvailable: false)
    )[.androidOfflineASR]
    let networkMissing = VoiceProviderCapabilityPolicy.evaluate(
      probe(validatedNetworkAvailable: false)
    )

    XCTAssertEqual(systemMissing[.androidSystemASR].state, .unavailable)
    XCTAssertEqual(systemMissing[.androidSystemASR].reason, .systemRecognizerMissing)
    XCTAssertEqual(systemMissing[.cloudASR].reason, .systemRecognizerMissing)
    XCTAssertEqual(offlineMissing.state, .unavailable)
    XCTAssertEqual(offlineMissing.reason, .offlineRecognizerMissing)
    XCTAssertEqual(networkMissing[.cloudASR].state, .needsNetwork)
    XCTAssertEqual(networkMissing[.microsoftEdgeTTS].state, .needsNetwork)
  }

  func testVoiceProviderCapabilityPolicyHandlesTtsCheckingMissingAndUnsupportedLanguage() {
    let checking = VoiceProviderCapabilityPolicy.evaluate(
      probe(ttsInitialized: false)
    )[.androidSystemTTS]
    let missing = VoiceProviderCapabilityPolicy.evaluate(
      probe(ttsReady: false, ttsEngineCount: 0)
    )[.androidSystemTTS]
    let unsupported = VoiceProviderCapabilityPolicy.evaluate(
      probe(ttsLanguageSupported: false, ttsLanguage: "zz-ZZ")
    )[.androidSystemTTS]

    XCTAssertEqual(checking.state, .checking)
    XCTAssertEqual(checking.reason, .checking)
    XCTAssertEqual(missing.state, .unavailable)
    XCTAssertEqual(missing.reason, .ttsEngineMissing)
    XCTAssertEqual(missing.metadata["engine_count"], "0")
    XCTAssertEqual(unsupported.reason, .ttsLanguageUnsupported)
    XCTAssertEqual(unsupported.metadata["language"], "zz-ZZ")
  }

  func testVoiceProviderCapabilityModelsUseAndroidWireNames() throws {
    let snapshot = VoiceProviderCapabilityPolicy.evaluate(
      probe(validatedNetworkAvailable: false),
      checkedAtMillis: 2_000
    )
    let encoded = try JSONEncoder().encode(snapshot)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let capabilities = try XCTUnwrap(object["capabilities"] as? [[String: Any]])
    let probeObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try JSONEncoder().encode(probe())) as? [String: Any]
    )

    XCTAssertEqual((object["checked_at_millis"] as? NSNumber)?.int64Value ?? 0, 2_000)
    XCTAssertEqual(capabilities.map { $0["id"] as? String ?? "" }, [
      "WHISPER_CPP",
      "ANDROID_SYSTEM_ASR",
      "ANDROID_OFFLINE_ASR",
      "CLOUD_ASR",
      "ANDROID_SYSTEM_TTS",
      "MICROSOFT_EDGE_TTS",
    ])
    XCTAssertEqual(capabilities[3]["state"] as? String, "NEEDS_NETWORK")
    XCTAssertEqual(capabilities[3]["reason"] as? String, "NETWORK_REQUIRED")
    XCTAssertEqual(probeObject["microphone_permission_granted"] as? Bool, true)
    XCTAssertEqual(probeObject["whisper_model_id"] as? String, "whisper-base")
    XCTAssertEqual(probeObject["tts_language"] as? String, "en-US")
    XCTAssertEqual(VoiceProviderCapabilityId.fromWireValue("cloud_asr"), Optional(.cloudASR))
    XCTAssertEqual(VoiceProviderCapabilityState.fromWireValue("NEEDS_PERMISSION"), .needsPermission)
    XCTAssertEqual(VoiceProviderCapabilityReason.fromWireValue("TTS_ENGINE_MISSING"), .ttsEngineMissing)
  }

  func testVoiceProviderCapabilityDetectorBuildsProbeFromIOSSettingsAndRuntimeNames() {
    let settings = VoiceSettings(
      wakeListeningEnabled: false,
      speechRecognitionEnabled: true,
      textToSpeechEnabled: true,
      autoSendTranscripts: false,
      preferredLocaleIdentifier: "en-US",
      asrModelId: "base"
    )
    let whisperRuntime = VoiceProviderCapabilityDetector.whisperRuntimeAvailable([
      "GalaxySSI.app",
      "libwhisper.dylib",
    ])
    let noRuntime = VoiceProviderCapabilityDetector.whisperRuntimeAvailable([
      "GalaxySSI.app",
      "libnot-a-model.dylib",
    ])

    let detectorProbe = VoiceProviderCapabilityDetector.probe(
      settings: settings,
      validatedNetworkAvailable: false,
      whisperRuntimeLibraryNames: ["libwhisperkit.dylib"],
      whisperModelAvailable: false,
      ttsInitialized: false,
      hasMicrophone: true,
      microphonePermissionGranted: true,
      systemAsrAvailable: true,
      offlineAsrAvailable: true,
      ttsReady: true,
      ttsEngineCount: 2,
      ttsLanguageSupported: true
    )
    let snapshot = VoiceProviderCapabilityPolicy.evaluate(detectorProbe, checkedAtMillis: 3_000)

    XCTAssertTrue(whisperRuntime)
    XCTAssertFalse(noRuntime)
    XCTAssertEqual(snapshot.checkedAtMillis, 3_000)
    XCTAssertEqual(detectorProbe.whisperModelId, "base")
    XCTAssertEqual(detectorProbe.whisperModelName, "Base")
    XCTAssertEqual(snapshot[.whisperCpp].state, .needsDownload)
    XCTAssertEqual(snapshot[.cloudASR].state, .needsNetwork)
    XCTAssertEqual(snapshot[.androidSystemTTS].state, .checking)
  }

  private func probe(
    hasMicrophone: Bool = true,
    microphonePermissionGranted: Bool = true,
    whisperRuntimeAvailable: Bool = true,
    whisperModelAvailable: Bool = true,
    whisperModelId: String = "whisper-base",
    whisperModelName: String = "Whisper Base",
    systemAsrAvailable: Bool = true,
    offlineAsrAvailable: Bool = true,
    validatedNetworkAvailable: Bool = true,
    ttsInitialized: Bool = true,
    ttsReady: Bool = true,
    ttsEngineCount: Int = 2,
    ttsLanguageSupported: Bool = true,
    ttsLanguage: String = "en-US"
  ) -> VoiceDeviceCapabilityProbe {
    VoiceDeviceCapabilityProbe(
      hasMicrophone: hasMicrophone,
      microphonePermissionGranted: microphonePermissionGranted,
      whisperRuntimeAvailable: whisperRuntimeAvailable,
      whisperModelAvailable: whisperModelAvailable,
      whisperModelId: whisperModelId,
      whisperModelName: whisperModelName,
      systemAsrAvailable: systemAsrAvailable,
      offlineAsrAvailable: offlineAsrAvailable,
      validatedNetworkAvailable: validatedNetworkAvailable,
      ttsInitialized: ttsInitialized,
      ttsReady: ttsReady,
      ttsEngineCount: ttsEngineCount,
      ttsLanguageSupported: ttsLanguageSupported,
      ttsLanguage: ttsLanguage
    )
  }
}
