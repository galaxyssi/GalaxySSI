import XCTest
@testable import GalaxySSI

final class VoiceSecondPassPlannerTests: XCTestCase {
  func testBuildsRequestWhenRuntimeDecisionRecommendsSecondPass() throws {
    let fast = hypothesis("Compare GPT5.6 with ClaudeCode")
    let plan = try XCTUnwrap(VoiceSecondPassPlanner.plan(
      sessionId: " voice-1 ",
      fast: fast,
      asrResult: result(runSecondPass: true, accurateProfileId: "base"),
      pcmSnapshot: pcm(),
      secondPassEnabled: true
    ))

    XCTAssertEqual(plan.request.sessionId, "voice-1")
    XCTAssertEqual(plan.request.fast, fast)
    XCTAssertEqual(plan.request.pcm16.count, 16_000)
    XCTAssertEqual(plan.request.sampleRateHz, 16_000)
    XCTAssertEqual(plan.request.language, "en")
    XCTAssertEqual(plan.request.accurateProfileId, "base")
    XCTAssertEqual(plan.request.accurateModelSha256, VoiceWhisperModelCatalog.model("base").sha256)
    XCTAssertEqual(plan.request.mode, .secondPass)
    XCTAssertTrue(plan.trigger.requested)
    XCTAssertTrue(plan.trigger.reasons.contains("proper_nouns"))
    XCTAssertFalse(plan.waitForConfirmation)
  }

  func testHighRiskPlanWaitsForConfirmation() throws {
    let plan = try XCTUnwrap(VoiceSecondPassPlanner.plan(
      sessionId: "voice-2",
      fast: hypothesis("Delete Downloads/a.txt"),
      asrResult: result(runSecondPass: true, accurateProfileId: "base"),
      pcmSnapshot: pcm(),
      secondPassEnabled: true
    ))

    XCTAssertEqual(plan.risk, .high)
    XCTAssertTrue(plan.waitForConfirmation)
  }

  func testUserRequestedAccuracyAddsTriggerReason() throws {
    let plan = try XCTUnwrap(VoiceSecondPassPlanner.plan(
      sessionId: "voice-3",
      fast: hypothesis("hello"),
      asrResult: result(runSecondPass: true, accurateProfileId: "base"),
      pcmSnapshot: pcm(),
      secondPassEnabled: true,
      userRequestedAccuracy: true
    ))

    XCTAssertTrue(plan.trigger.reasons.contains("user_requested_accuracy"))
  }

  func testReturnsNilWhenDecisionOrPcmCannotSupportSecondPass() {
    XCTAssertNil(VoiceSecondPassPlanner.plan(
      sessionId: "voice-4",
      fast: hypothesis("hello"),
      asrResult: result(runSecondPass: false, accurateProfileId: nil),
      pcmSnapshot: pcm(),
      secondPassEnabled: true
    ))
    XCTAssertNil(VoiceSecondPassPlanner.plan(
      sessionId: "voice-4",
      fast: hypothesis("hello"),
      asrResult: result(runSecondPass: true, accurateProfileId: "base"),
      pcmSnapshot: pcm(sampleRateHz: 44_100),
      secondPassEnabled: true
    ))
  }

  func testReturnsNilWhenFeatureFlagIsDisabled() {
    XCTAssertNil(VoiceSecondPassPlanner.plan(
      sessionId: "voice-5",
      fast: hypothesis("hello"),
      asrResult: result(runSecondPass: true, accurateProfileId: "base"),
      pcmSnapshot: pcm(),
      secondPassEnabled: false
    ))
  }

  private func result(
    runSecondPass: Bool,
    accurateProfileId: String?
  ) -> VoiceLocalWhisperTranscriptionResult {
    let selected = VoiceWhisperModelCatalog.model("tiny")
    return VoiceLocalWhisperTranscriptionResult(
      text: "fast",
      selectedModel: selected,
      model: selected,
      language: "en",
      audioDurationMs: 1_000,
      sampleRateHz: 16_000,
      threadCount: 2,
      runtimeDecision: VoiceWhisperRuntimeDecision(
        provider: .local,
        fastProfileId: selected.id,
        fastMode: .finalOnly,
        accurateProfileId: accurateProfileId,
        accurateMode: .secondPass,
        partialIntervalMillis: nil,
        threadCount: 2,
        runSecondPass: runSecondPass,
        reasons: ["test"]
      )
    )
  }

  private func hypothesis(_ text: String) -> TranscriptHypothesis {
    TranscriptHypothesis(
      text: text,
      revision: 1,
      provider: "whisper.cpp",
      modelProfileId: "tiny"
    )
  }

  private func pcm(sampleRateHz: Int = 16_000) -> PcmSnapshot {
    PcmSnapshot(
      samples: Array(repeating: 1, count: 16_000),
      sampleRateHz: sampleRateHz,
      speechDetected: true,
      speechStartSample: 0,
      speechEndSampleExclusive: 16_000,
      captureStartSample: 0,
      captureEndSampleExclusive: 16_000
    )
  }
}
