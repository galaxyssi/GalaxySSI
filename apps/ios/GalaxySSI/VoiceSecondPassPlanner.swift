import Foundation

struct VoiceSecondPassPlan: Equatable {
  var request: VoiceSecondPassRequest
  var trigger: VoiceSecondPassTrigger
  var risk: VoiceCommandRisk

  var waitForConfirmation: Bool {
    risk >= .high
  }
}

enum VoiceSecondPassPlanner {
  static func plan(
    sessionId: String,
    fast: TranscriptHypothesis,
    asrResult: VoiceLocalWhisperTranscriptionResult,
    pcmSnapshot: PcmSnapshot,
    secondPassEnabled: Bool = VoiceFeatureFlags.isWhisperSecondPassEnabled(),
    userRequestedAccuracy: Bool = false,
    meetingOrLongRecordMode: Bool = false,
    onlineProviderUnstable: Bool = false,
    riskClassifier: VoiceCommandRiskClassifying = DefaultVoiceCommandRiskClassifier()
  ) -> VoiceSecondPassPlan? {
    let cleanSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard secondPassEnabled,
          !cleanSessionId.isEmpty,
          !fast.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !pcmSnapshot.samples.isEmpty,
          pcmSnapshot.sampleRateHz == 16_000,
          let accurateProfileId = asrResult.secondPassProfileId else {
      return nil
    }
    let profile = VoiceWhisperModelCatalog.model(accurateProfileId)
    guard profile.id == accurateProfileId,
          profile.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
      return nil
    }
    let trigger = VoiceSecondPassTriggerPolicy.evaluate(
      fast: fast,
      utteranceDurationMs: pcmSnapshot.durationMs,
      userRequestedAccuracy: userRequestedAccuracy,
      meetingOrLongRecordMode: meetingOrLongRecordMode,
      onlineProviderUnstable: onlineProviderUnstable
    )
    let request = VoiceSecondPassRequest(
      sessionId: cleanSessionId,
      pcm16: pcmSnapshot.samples,
      sampleRateHz: pcmSnapshot.sampleRateHz,
      language: asrResult.language,
      fast: fast,
      accurateProfileId: profile.id,
      accurateModelSha256: profile.sha256,
      mode: asrResult.secondPassMode ?? .secondPass
    )
    return VoiceSecondPassPlan(
      request: request,
      trigger: trigger,
      risk: riskClassifier.classify(fast.text)
    )
  }
}
