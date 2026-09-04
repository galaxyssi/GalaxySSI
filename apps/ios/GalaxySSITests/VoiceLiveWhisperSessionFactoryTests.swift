import XCTest
@testable import GalaxySSI

final class VoiceLiveWhisperSessionFactoryTests: XCTestCase {
  func testSkipsWhenRuntimeOrAdaptivePartialIsDisabled() {
    let runtimeOff = factory(runtimeEnabled: false)
    let adaptiveOff = factory(adaptivePartialEnabled: false)

    XCTAssertEqual(runtimeOff.decide(settings: settings()), .skip(.runtimeDisabled))
    XCTAssertEqual(adaptiveOff.decide(settings: settings()), .skip(.adaptivePartialDisabled))
  }

  func testSkipsWhenPolicyDecisionIsNotLocalRealtime() {
    let factory = factory(
      policyEngineEnabled: true,
      decisionProvider: { _, _, _ in
        VoiceWhisperRuntimeDecision(
          provider: .remote,
          fastProfileId: nil,
          fastMode: .remoteNode,
          accurateProfileId: nil,
          accurateMode: nil,
          partialIntervalMillis: nil,
          threadCount: nil,
          runSecondPass: false,
          reasons: ["remote preferred"]
        )
      }
    )

    XCTAssertEqual(factory.decide(settings: settings()), .skip(.policyNotLocalRealtime))
  }

  func testPolicyDecisionPlansCertifiedRealtimeSession() {
    let factory = factory(
      policyEngineEnabled: true,
      certificationProvider: { profile in Self.certification(profile, partialIntervalMillis: 880) },
      decisionProvider: { _, _, queue in
        XCTAssertEqual(queue.queuedPartials, 2)
        return VoiceWhisperRuntimeDecision(
          provider: .local,
          fastProfileId: "base",
          fastMode: .realtimePartial,
          accurateProfileId: nil,
          accurateMode: nil,
          partialIntervalMillis: 1_100,
          threadCount: 2,
          runSecondPass: false,
          reasons: ["base realtime"]
        )
      }
    )

    let decision = factory.decide(
      settings: settings(asrModelId: "tiny"),
      queue: VoiceWhisperDecodeQueueSnapshot(queuedPartials: 2)
    )

    guard case .start(let plan) = decision else {
      return XCTFail("Expected live Whisper session plan")
    }
    XCTAssertEqual(plan.profile.id, "base")
    XCTAssertEqual(plan.language, "en")
    XCTAssertEqual(plan.certifiedPartialIntervalMillis, 1_100)
    XCTAssertEqual(plan.realtimeCertified, true)
    XCTAssertEqual(plan.decision?.fastMode, .some(.realtimePartial))
  }

  func testModelUnavailableSkipsAndMakeSessionCreatesWhenAvailable() {
    let unavailable = factory(modelAvailable: { $0.id != "tiny" })
    XCTAssertEqual(unavailable.decide(settings: settings(asrModelId: "tiny")), .skip(.modelUnavailable))

    let available = factory(policyEngineEnabled: false)
    let session = available.makeSession(
      voiceSessionId: "voice-1",
      settings: settings(asrModelId: "tiny"),
      scheduler: NoopLiveWhisperScheduler(),
      onUpdate: { _ in }
    )

    XCTAssertEqual(session?.modelProfileId, "tiny")
  }

  private func factory(
    runtimeEnabled: Bool = true,
    adaptivePartialEnabled: Bool = true,
    policyEngineEnabled: Bool = false,
    modelAvailable: @escaping (VoiceWhisperModelProfile) -> Bool = { _ in true },
    certificationProvider: @escaping (VoiceWhisperModelProfile) -> VoiceWhisperCertification? = { _ in nil },
    decisionProvider: VoiceLiveWhisperDecisionProvider? = nil
  ) -> VoiceLiveWhisperSessionFactory {
    VoiceLiveWhisperSessionFactory(
      runtimeEnabled: { runtimeEnabled },
      adaptivePartialEnabled: { adaptivePartialEnabled },
      policyEngineEnabled: { policyEngineEnabled },
      modelAvailable: modelAvailable,
      certificationProvider: certificationProvider,
      decisionProvider: decisionProvider,
      elapsedClock: { 1_000 }
    )
  }

  private func settings(
    asrModelId: String = "tiny",
    runtimeMode: VoiceWhisperUserVoiceMode = .automatic
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

  private static func certification(
    _ profile: VoiceWhisperModelProfile,
    partialIntervalMillis: Int64
  ) -> VoiceWhisperCertification {
    VoiceWhisperCertification(
      key: VoiceWhisperBenchmarkKey(
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
      ),
      level: .realtime,
      recommendedMode: .realtimePartial,
      recommendedThreadCount: 2,
      recommendedPartialIntervalMillis: partialIntervalMillis,
      warmRtfP50: 0.3,
      warmRtfP95: 0.5,
      createdAtEpochMillis: 1
    )
  }
}

private final class NoopLiveWhisperScheduler: VoiceWhisperDecodeScheduling {
  func submit(_ request: VoiceScheduledWhisperDecode) async -> VoiceScheduledWhisperResult {
    .dropped(request: request, reason: .schedulerClosed)
  }

  func cancelSession(_ sessionId: String) {}
  func queueSnapshot() -> VoiceWhisperDecodeQueueSnapshot { VoiceWhisperDecodeQueueSnapshot() }
  func close() {}
}
