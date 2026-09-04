import Foundation

enum VoiceLiveWhisperSessionSkipReason: String, Codable, Equatable {
  case runtimeDisabled = "RUNTIME_DISABLED"
  case adaptivePartialDisabled = "ADAPTIVE_PARTIAL_DISABLED"
  case policyNotLocalRealtime = "POLICY_NOT_LOCAL_REALTIME"
  case modelUnavailable = "MODEL_UNAVAILABLE"
}

struct VoiceLiveWhisperSessionPlan: Equatable {
  var profile: VoiceWhisperModelProfile
  var language: String
  var certifiedPartialIntervalMillis: Int64?
  var realtimeCertified: Bool
  var finalProfileId: String?
  var threadCount: Int?
  var decision: VoiceWhisperRuntimeDecision?
}

enum VoiceLiveWhisperSessionFactoryDecision: Equatable {
  case start(VoiceLiveWhisperSessionPlan)
  case skip(VoiceLiveWhisperSessionSkipReason)
}

typealias VoiceLiveWhisperDecisionProvider = (
  _ settings: VoiceSettings,
  _ selectedProfile: VoiceWhisperModelProfile,
  _ queue: VoiceWhisperDecodeQueueSnapshot
) -> VoiceWhisperRuntimeDecision?

typealias VoiceLiveWhisperPostFastDecisionProvider = (
  _ settings: VoiceSettings,
  _ selectedProfile: VoiceWhisperModelProfile,
  _ fastResult: VoiceNativeWhisperResult,
  _ snapshot: PcmSnapshot,
  _ queue: VoiceWhisperDecodeQueueSnapshot
) -> VoiceWhisperRuntimeDecision?

final class VoiceLiveWhisperSessionFactory {
  private let runtimeEnabled: () -> Bool
  private let adaptivePartialEnabled: () -> Bool
  private let policyEngineEnabled: () -> Bool
  private let secondPassEnabled: () -> Bool
  private let profileProvider: (String?) -> VoiceWhisperModelProfile
  private let modelAvailable: (VoiceWhisperModelProfile) -> Bool
  private let certificationProvider: (VoiceWhisperModelProfile) -> VoiceWhisperCertification?
  private let decisionProvider: VoiceLiveWhisperDecisionProvider
  private let postFastDecisionProvider: VoiceLiveWhisperPostFastDecisionProvider
  private let languageProvider: (VoiceSettings) -> String
  private let elapsedClock: () -> Int64

  init(
    runtimeEnabled: @escaping () -> Bool = { VoiceFeatureFlags.isLocalWhisperRuntimeV2Enabled() },
    adaptivePartialEnabled: @escaping () -> Bool = { VoiceFeatureFlags.isWhisperAdaptivePartialEnabled() },
    policyEngineEnabled: @escaping () -> Bool = { VoiceFeatureFlags.isWhisperPolicyEngineEnabled() },
    secondPassEnabled: @escaping () -> Bool = { VoiceFeatureFlags.isWhisperSecondPassEnabled() },
    profileProvider: @escaping (String?) -> VoiceWhisperModelProfile = { VoiceWhisperModelCatalog.model($0) },
    modelAvailable: ((VoiceWhisperModelProfile) -> Bool)? = nil,
    certificationProvider: ((VoiceWhisperModelProfile) -> VoiceWhisperCertification?)? = nil,
    decisionProvider: VoiceLiveWhisperDecisionProvider? = nil,
    postFastDecisionProvider: VoiceLiveWhisperPostFastDecisionProvider? = nil,
    languageProvider: @escaping (VoiceSettings) -> String = {
      VoiceWhisperLanguagePolicy.normalizedRecognitionLanguage($0.preferredLocaleIdentifier)
    },
    elapsedClock: @escaping () -> Int64 = VoiceLiveWhisperSessionFactory.defaultElapsedClock
  ) {
    let modelManager = VoiceWhisperModelManager()
    let benchmarkManager = VoiceWhisperBenchmarkManager()
    self.runtimeEnabled = runtimeEnabled
    self.adaptivePartialEnabled = adaptivePartialEnabled
    self.policyEngineEnabled = policyEngineEnabled
    self.secondPassEnabled = secondPassEnabled
    self.profileProvider = profileProvider
    self.modelAvailable = modelAvailable ?? { modelManager.isAvailable($0) }
    self.certificationProvider = certificationProvider ?? { benchmarkManager.current(profile: $0)?.certification }
    self.decisionProvider = decisionProvider ?? { settings, selected, queue in
      benchmarkManager.decide(
        userMode: settings.asrRuntimeMode,
        selectedProfileId: selected.id,
        context: VoiceWhisperBenchmarkDecisionContext(decodeQueueDepth: queue.queuedPartials)
      )
    }
    self.postFastDecisionProvider = postFastDecisionProvider ?? { settings, selected, fastResult, snapshot, queue in
      let confidence = VoiceLiveWhisperSessionFactory.confidence(fastResult)
      let averageLogProbability = VoiceLiveWhisperSessionFactory.averageLogProbability(fastResult)
      let fast = TranscriptHypothesis(
        text: fastResult.text,
        revision: 1,
        provider: voiceLocalWhisperProviderId,
        modelProfileId: selected.id,
        confidence: confidence,
        isFinal: true,
        language: fastResult.detectedLanguage,
        segmentStartMs: 0,
        segmentEndMs: snapshot.durationMs,
        averageLogProb: averageLogProbability
      )
      let trigger = VoiceSecondPassTriggerPolicy.evaluate(
        fast: fast,
        utteranceDurationMs: snapshot.durationMs,
        userRequestedAccuracy: settings.asrRuntimeMode == .accurate
      )
      let risk = DefaultVoiceCommandRiskClassifier.classify(fast.text)
      return benchmarkManager.decide(
        userMode: settings.asrRuntimeMode,
        selectedProfileId: selected.id,
        context: VoiceWhisperBenchmarkDecisionContext(
          decodeQueueDepth: queue.queuedPartials,
          utteranceDurationMillis: snapshot.durationMs,
          highRiskTask: risk >= .high,
          accuracySensitiveTask: trigger.requested
        )
      )
    }
    self.languageProvider = languageProvider
    self.elapsedClock = elapsedClock
  }

  func decide(
    settings: VoiceSettings,
    queue: VoiceWhisperDecodeQueueSnapshot = VoiceWhisperDecodeQueueSnapshot()
  ) -> VoiceLiveWhisperSessionFactoryDecision {
    guard runtimeEnabled() else {
      return .skip(.runtimeDisabled)
    }
    let selected = profileProvider(settings.asrModelId)
    let decision = policyEngineEnabled() ? decisionProvider(settings, selected, queue) : nil
    let profile: VoiceWhisperModelProfile
    let realtimeCapture: Bool
    if let decision {
      guard decision.provider == .local,
            let fastMode = decision.fastMode,
            [.realtimePartial, .finalOnly].contains(fastMode),
            let fastProfileId = decision.fastProfileId?.trimmingCharacters(in: .whitespacesAndNewlines),
            !fastProfileId.isEmpty else {
        return .skip(.policyNotLocalRealtime)
      }
      profile = profileProvider(fastProfileId)
      realtimeCapture = fastMode == .realtimePartial
    } else {
      profile = selected
      realtimeCapture = true
    }
    if realtimeCapture, !adaptivePartialEnabled() {
      return .skip(.adaptivePartialDisabled)
    }

    guard modelAvailable(profile) else {
      return .skip(.modelUnavailable)
    }

    let requestedFinalProfileId = secondPassEnabled() && decision?.runSecondPass == true
      ? decision?.accurateProfileId?.trimmingCharacters(in: .whitespacesAndNewlines)
      : nil
    let finalProfileId = requestedFinalProfileId?.isEmpty == false ? requestedFinalProfileId : nil
    if let finalProfileId, !finalProfileId.isEmpty,
       !modelAvailable(profileProvider(finalProfileId)) {
      return .skip(.modelUnavailable)
    }

    let certification = decision == nil ? nil : certificationProvider(profile)
    return .start(
      VoiceLiveWhisperSessionPlan(
        profile: profile,
        language: languageProvider(settings),
        certifiedPartialIntervalMillis: realtimeCapture
          ? (decision?.partialIntervalMillis ?? certification?.recommendedPartialIntervalMillis)
          : nil,
        realtimeCertified: realtimeCapture && (decision == nil || certification?.realtimeCertified == true),
        finalProfileId: finalProfileId,
        threadCount: decision?.threadCount,
        decision: decision
      )
    )
  }

  func makeSession(
    voiceSessionId: String,
    settings: VoiceSettings,
    scheduler: VoiceWhisperDecodeScheduling,
    queue: VoiceWhisperDecodeQueueSnapshot = VoiceWhisperDecodeQueueSnapshot(),
    onUpdate: @escaping (VoiceLiveWhisperTranscriptUpdate) -> Void
  ) -> VoiceLiveWhisperTranscriptionSession? {
    guard case .start(let plan) = decide(settings: settings, queue: queue) else {
      return nil
    }
    let postFastProvider = postFastDecisionProvider
    let sessionPostFastDecisionProvider: VoiceLiveWhisperSessionPostFastDecisionProvider? =
      policyEngineEnabled() && secondPassEnabled() && plan.finalProfileId == nil
        ? { result, snapshot, currentQueue in
          postFastProvider(settings, plan.profile, result, snapshot, currentQueue)
        }
        : nil
    return VoiceLiveWhisperTranscriptionSession(
      voiceSessionId: voiceSessionId,
      profile: plan.profile,
      language: plan.language,
      scheduler: scheduler,
      elapsedClock: elapsedClock,
      certifiedPartialIntervalMillis: plan.certifiedPartialIntervalMillis,
      realtimeCertified: plan.realtimeCertified,
      finalProfileId: plan.finalProfileId,
      threadCount: plan.threadCount,
      postFastDecisionProvider: sessionPostFastDecisionProvider,
      onUpdate: onUpdate
    )
  }

  private static func confidence(_ result: VoiceNativeWhisperResult) -> Float? {
    let values = result.segments
      .map(\.averageLogProbability)
      .filter { $0.isFinite }
    guard !values.isEmpty else { return nil }
    let meanConfidence = values.reduce(0.0) { $0 + exp(Double($1)) } / Double(values.count)
    return Float(min(max(meanConfidence, 0), 1))
  }

  private static func averageLogProbability(_ result: VoiceNativeWhisperResult) -> Float? {
    let values = result.segments
      .map(\.averageLogProbability)
      .filter { $0.isFinite }
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +) / Float(values.count)
  }

  private static func defaultElapsedClock() -> Int64 {
    Int64(ProcessInfo.processInfo.systemUptime * 1_000)
  }
}
