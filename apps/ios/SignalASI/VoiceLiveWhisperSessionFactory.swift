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

final class VoiceLiveWhisperSessionFactory {
  private let runtimeEnabled: () -> Bool
  private let adaptivePartialEnabled: () -> Bool
  private let policyEngineEnabled: () -> Bool
  private let profileProvider: (String?) -> VoiceWhisperModelProfile
  private let modelAvailable: (VoiceWhisperModelProfile) -> Bool
  private let certificationProvider: (VoiceWhisperModelProfile) -> VoiceWhisperCertification?
  private let decisionProvider: VoiceLiveWhisperDecisionProvider
  private let languageProvider: (VoiceSettings) -> String
  private let elapsedClock: () -> Int64

  init(
    runtimeEnabled: @escaping () -> Bool = { VoiceFeatureFlags.isLocalWhisperRuntimeV2Enabled() },
    adaptivePartialEnabled: @escaping () -> Bool = { VoiceFeatureFlags.isWhisperAdaptivePartialEnabled() },
    policyEngineEnabled: @escaping () -> Bool = { VoiceFeatureFlags.isWhisperPolicyEngineEnabled() },
    profileProvider: @escaping (String?) -> VoiceWhisperModelProfile = { VoiceWhisperModelCatalog.model($0) },
    modelAvailable: ((VoiceWhisperModelProfile) -> Bool)? = nil,
    certificationProvider: ((VoiceWhisperModelProfile) -> VoiceWhisperCertification?)? = nil,
    decisionProvider: VoiceLiveWhisperDecisionProvider? = nil,
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

    let certification = decision == nil ? nil : certificationProvider(profile)
    return .start(
      VoiceLiveWhisperSessionPlan(
        profile: profile,
        language: languageProvider(settings),
        certifiedPartialIntervalMillis: realtimeCapture
          ? (decision?.partialIntervalMillis ?? certification?.recommendedPartialIntervalMillis)
          : nil,
        realtimeCertified: realtimeCapture && (decision == nil || certification?.realtimeCertified == true),
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
    return VoiceLiveWhisperTranscriptionSession(
      voiceSessionId: voiceSessionId,
      profile: plan.profile,
      language: plan.language,
      scheduler: scheduler,
      elapsedClock: elapsedClock,
      certifiedPartialIntervalMillis: plan.certifiedPartialIntervalMillis,
      realtimeCertified: plan.realtimeCertified,
      onUpdate: onUpdate
    )
  }

  private static func defaultElapsedClock() -> Int64 {
    Int64(ProcessInfo.processInfo.systemUptime * 1_000)
  }
}
