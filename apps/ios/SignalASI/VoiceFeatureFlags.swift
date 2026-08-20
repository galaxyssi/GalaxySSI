import CryptoKit
import Foundation

let voiceCoordinatorFlag = "voice.coordinator_v1"
let voicePcmCaptureFlag = "voice.audio_record_pcm_v1"
let voiceLocalWhisperRuntimeV2Flag = "voice.local_whisper_runtime_v2"
let voiceWhisperAdaptivePartialV1Flag = "voice.whisper_adaptive_partial_v1"
let voiceWhisperAutoBenchmarkV1Flag = "voice.whisper_auto_benchmark_v1"
let voiceWhisperPolicyEngineV1Flag = "voice.whisper_policy_engine_v1"
let voiceWhisperSecondPassV1Flag = "voice.whisper_second_pass_v1"
let voiceOnlineRealtimeASRV1Flag = "voice.online_realtime_asr_v1"
let voiceRemoteWhisperNodeV1Flag = "voice.remote_whisper_node_v1"

enum VoiceFeatureFlags {
  static func isCoordinatorEnabled(
    userDefaults: UserDefaults = .standard,
    defaultEnabled: Bool = defaultCoordinatorEnabled
  ) -> Bool {
    guard userDefaults.object(forKey: voiceCoordinatorFlag) != nil else {
      return defaultEnabled
    }
    return userDefaults.bool(forKey: voiceCoordinatorFlag)
  }

  static func setCoordinatorEnabled(
    _ enabled: Bool,
    userDefaults: UserDefaults = .standard
  ) {
    userDefaults.set(enabled, forKey: voiceCoordinatorFlag)
  }

  static func resetCoordinatorEnabled(userDefaults: UserDefaults = .standard) {
    userDefaults.removeObject(forKey: voiceCoordinatorFlag)
  }

  static func isPcmCaptureEnabled(
    userDefaults: UserDefaults = .standard,
    defaultEnabled: Bool = defaultPcmCaptureEnabled
  ) -> Bool {
    guard userDefaults.object(forKey: voicePcmCaptureFlag) != nil else {
      return defaultEnabled
    }
    return userDefaults.bool(forKey: voicePcmCaptureFlag)
  }

  static func setPcmCaptureEnabled(
    _ enabled: Bool,
    userDefaults: UserDefaults = .standard
  ) {
    userDefaults.set(enabled, forKey: voicePcmCaptureFlag)
  }

  static func resetPcmCaptureEnabled(userDefaults: UserDefaults = .standard) {
    userDefaults.removeObject(forKey: voicePcmCaptureFlag)
  }

  static func isLocalWhisperRuntimeV2Enabled(
    userDefaults: UserDefaults = .standard,
    defaultEnabled: Bool = defaultLocalWhisperRuntimeV2Enabled
  ) -> Bool {
    guard userDefaults.object(forKey: voiceLocalWhisperRuntimeV2Flag) != nil else {
      return defaultEnabled
    }
    return userDefaults.bool(forKey: voiceLocalWhisperRuntimeV2Flag)
  }

  static func setLocalWhisperRuntimeV2Enabled(
    _ enabled: Bool,
    userDefaults: UserDefaults = .standard
  ) {
    userDefaults.set(enabled, forKey: voiceLocalWhisperRuntimeV2Flag)
  }

  static func resetLocalWhisperRuntimeV2Enabled(userDefaults: UserDefaults = .standard) {
    userDefaults.removeObject(forKey: voiceLocalWhisperRuntimeV2Flag)
  }

  static func isWhisperAdaptivePartialEnabled(
    userDefaults: UserDefaults = .standard,
    defaultEnabled: Bool = defaultWhisperAdaptivePartialEnabled
  ) -> Bool {
    guard userDefaults.object(forKey: voiceWhisperAdaptivePartialV1Flag) != nil else {
      return defaultEnabled
    }
    return userDefaults.bool(forKey: voiceWhisperAdaptivePartialV1Flag)
  }

  static func setWhisperAdaptivePartialEnabled(
    _ enabled: Bool,
    userDefaults: UserDefaults = .standard
  ) {
    userDefaults.set(enabled, forKey: voiceWhisperAdaptivePartialV1Flag)
  }

  static func resetWhisperAdaptivePartialEnabled(userDefaults: UserDefaults = .standard) {
    userDefaults.removeObject(forKey: voiceWhisperAdaptivePartialV1Flag)
  }

  /// A downloaded or selected on-device model is an explicit user opt-in to
  /// local recognition. Keep an existing false value intact so operators can
  /// still disable an individual part of the pipeline as a kill switch.
  static func activateCoreLocalWhisperPipelineIfUnconfigured(
    userDefaults: UserDefaults = .standard
  ) {
    enableIfUnconfigured(voiceCoordinatorFlag, userDefaults: userDefaults)
    enableIfUnconfigured(voicePcmCaptureFlag, userDefaults: userDefaults)
    enableIfUnconfigured(voiceLocalWhisperRuntimeV2Flag, userDefaults: userDefaults)
    enableIfUnconfigured(voiceWhisperAdaptivePartialV1Flag, userDefaults: userDefaults)
  }

  static func isWhisperAutoBenchmarkEnabled(
    userDefaults: UserDefaults = .standard,
    defaultEnabled: Bool = defaultWhisperAutoBenchmarkEnabled
  ) -> Bool {
    guard userDefaults.object(forKey: voiceWhisperAutoBenchmarkV1Flag) != nil else {
      return defaultEnabled
    }
    return userDefaults.bool(forKey: voiceWhisperAutoBenchmarkV1Flag)
  }

  static func setWhisperAutoBenchmarkEnabled(
    _ enabled: Bool,
    userDefaults: UserDefaults = .standard
  ) {
    userDefaults.set(enabled, forKey: voiceWhisperAutoBenchmarkV1Flag)
  }

  static func resetWhisperAutoBenchmarkEnabled(userDefaults: UserDefaults = .standard) {
    userDefaults.removeObject(forKey: voiceWhisperAutoBenchmarkV1Flag)
  }

  static func isWhisperPolicyEngineEnabled(
    userDefaults: UserDefaults = .standard,
    defaultEnabled: Bool = defaultWhisperPolicyEngineEnabled
  ) -> Bool {
    guard userDefaults.object(forKey: voiceWhisperPolicyEngineV1Flag) != nil else {
      return defaultEnabled
    }
    return userDefaults.bool(forKey: voiceWhisperPolicyEngineV1Flag)
  }

  static func setWhisperPolicyEngineEnabled(
    _ enabled: Bool,
    userDefaults: UserDefaults = .standard
  ) {
    userDefaults.set(enabled, forKey: voiceWhisperPolicyEngineV1Flag)
  }

  static func resetWhisperPolicyEngineEnabled(userDefaults: UserDefaults = .standard) {
    userDefaults.removeObject(forKey: voiceWhisperPolicyEngineV1Flag)
  }

  static func isWhisperSecondPassEnabled(
    userDefaults: UserDefaults = .standard,
    defaultEnabled: Bool = defaultWhisperSecondPassEnabled
  ) -> Bool {
    guard userDefaults.object(forKey: voiceWhisperSecondPassV1Flag) != nil else {
      return defaultEnabled
    }
    return userDefaults.bool(forKey: voiceWhisperSecondPassV1Flag)
  }

  static func setWhisperSecondPassEnabled(
    _ enabled: Bool,
    userDefaults: UserDefaults = .standard
  ) {
    userDefaults.set(enabled, forKey: voiceWhisperSecondPassV1Flag)
  }

  static func resetWhisperSecondPassEnabled(userDefaults: UserDefaults = .standard) {
    userDefaults.removeObject(forKey: voiceWhisperSecondPassV1Flag)
  }

  static func isOnlineRealtimeASREnabled(
    userDefaults: UserDefaults = .standard,
    defaultEnabled: Bool = defaultAdvancedASREnabled
  ) -> Bool {
    guard userDefaults.object(forKey: voiceOnlineRealtimeASRV1Flag) != nil else {
      return defaultEnabled
    }
    return userDefaults.bool(forKey: voiceOnlineRealtimeASRV1Flag)
  }

  static func setOnlineRealtimeASREnabled(
    _ enabled: Bool,
    userDefaults: UserDefaults = .standard
  ) {
    userDefaults.set(enabled, forKey: voiceOnlineRealtimeASRV1Flag)
  }

  static func resetOnlineRealtimeASREnabled(userDefaults: UserDefaults = .standard) {
    userDefaults.removeObject(forKey: voiceOnlineRealtimeASRV1Flag)
  }

  static func isRemoteWhisperNodeEnabled(
    userDefaults: UserDefaults = .standard,
    defaultEnabled: Bool = defaultAdvancedASREnabled
  ) -> Bool {
    guard userDefaults.object(forKey: voiceRemoteWhisperNodeV1Flag) != nil else {
      return defaultEnabled
    }
    return userDefaults.bool(forKey: voiceRemoteWhisperNodeV1Flag)
  }

  static func setRemoteWhisperNodeEnabled(
    _ enabled: Bool,
    userDefaults: UserDefaults = .standard
  ) {
    userDefaults.set(enabled, forKey: voiceRemoteWhisperNodeV1Flag)
  }

  static func resetRemoteWhisperNodeEnabled(userDefaults: UserDefaults = .standard) {
    userDefaults.removeObject(forKey: voiceRemoteWhisperNodeV1Flag)
  }

  #if DEBUG
  private static let defaultCoordinatorEnabled = true
  private static let defaultPcmCaptureEnabled = true
  private static let defaultLocalWhisperRuntimeV2Enabled = true
  private static let defaultWhisperAdaptivePartialEnabled = true
  private static let defaultWhisperAutoBenchmarkEnabled = true
  private static let defaultWhisperPolicyEngineEnabled = true
  private static let defaultWhisperSecondPassEnabled = true
  private static let defaultAdvancedASREnabled = true
  #else
  private static let defaultCoordinatorEnabled = false
  private static let defaultPcmCaptureEnabled = false
  private static let defaultLocalWhisperRuntimeV2Enabled = false
  private static let defaultWhisperAdaptivePartialEnabled = false
  private static let defaultWhisperAutoBenchmarkEnabled = false
  private static let defaultWhisperPolicyEngineEnabled = false
  private static let defaultWhisperSecondPassEnabled = false
  private static let defaultAdvancedASREnabled = false
  #endif

  private static func enableIfUnconfigured(
    _ key: String,
    userDefaults: UserDefaults
  ) {
    guard userDefaults.object(forKey: key) == nil else { return }
    userDefaults.set(true, forKey: key)
  }
}

enum VoicePipelineFeature: String, Codable, CaseIterable, Identifiable {
  case pcmCapture = "PCM_CAPTURE"
  case localWhisperRealtime = "LOCAL_WHISPER_REALTIME"
  case onlineRealtimeASR = "ONLINE_REALTIME_ASR"
  case cloudModelStream = "CLOUD_MODEL_STREAM"
  case progressiveTTS = "PROGRESSIVE_TTS"
  case agentOutputDelta = "AGENT_OUTPUT_DELTA"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> VoicePipelineFeature {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .pcmCapture
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum VoiceCircuitState: String, Codable, CaseIterable, Identifiable {
  case closed = "CLOSED"
  case open = "OPEN"
  case halfOpen = "HALF_OPEN"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> VoiceCircuitState {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .closed
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum VoiceRolloutStage: String, Codable, CaseIterable, Identifiable {
  case developer = "DEVELOPER"
  case `internal` = "INTERNAL"
  case optInBeta = "OPT_IN_BETA"
  case stableCohort = "STABLE_COHORT"
  case certifiedExpansion = "CERTIFIED_EXPANSION"
  case defaultWithFallback = "DEFAULT_WITH_FALLBACK"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> VoiceRolloutStage {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .developer
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum VoiceRollbackLevel: String, Codable, CaseIterable, Identifiable {
  case none = "NONE"
  case disableSingleOptimization = "DISABLE_SINGLE_OPTIMIZATION"
  case finalOnly = "FINAL_ONLY"
  case legacyPipeline = "LEGACY_PIPELINE"
  case textOnly = "TEXT_ONLY"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> VoiceRollbackLevel {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .none
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct VoiceRolloutConfig: Codable, Equatable {
  var feature: VoicePipelineFeature
  var stage: VoiceRolloutStage
  var cohortPercent: Int
  var requestedEnabled: Bool
  var explicitlyDisabled: Bool
  var debuggable: Bool
  var internalTester: Bool
  var betaOptIn: Bool

  init(
    feature: VoicePipelineFeature,
    stage: VoiceRolloutStage,
    cohortPercent: Int = 0,
    requestedEnabled: Bool = false,
    explicitlyDisabled: Bool = false,
    debuggable: Bool = false,
    internalTester: Bool = false,
    betaOptIn: Bool = false
  ) {
    self.feature = feature
    self.stage = stage
    self.cohortPercent = cohortPercent
    self.requestedEnabled = requestedEnabled
    self.explicitlyDisabled = explicitlyDisabled
    self.debuggable = debuggable
    self.internalTester = internalTester
    self.betaOptIn = betaOptIn
  }

  enum CodingKeys: String, CodingKey {
    case feature
    case stage
    case cohortPercent = "cohort_percent"
    case requestedEnabled = "requested_enabled"
    case explicitlyDisabled = "explicitly_disabled"
    case debuggable
    case internalTester = "internal_tester"
    case betaOptIn = "beta_opt_in"
  }
}

struct VoiceRolloutEvidence: Codable, Equatable {
  var sampleCount: Int
  var stableReleaseCount: Int
  var newP95Ms: Int64?
  var legacyP95Ms: Int64?
  var crashRate: Double
  var legacyCrashRate: Double
  var anrRate: Double
  var legacyAnrRate: Double
  var fallbackSuccessRate: Double
  var privacyReviewed: Bool
  var securityReviewed: Bool
  var diagnosticsAvailable: Bool
  var supportDocumentationAvailable: Bool
  var deviceCertified: Bool
  var circuitState: VoiceCircuitState

  init(
    sampleCount: Int = 0,
    stableReleaseCount: Int = 0,
    newP95Ms: Int64? = nil,
    legacyP95Ms: Int64? = nil,
    crashRate: Double = 0,
    legacyCrashRate: Double = 0,
    anrRate: Double = 0,
    legacyAnrRate: Double = 0,
    fallbackSuccessRate: Double = 1,
    privacyReviewed: Bool = false,
    securityReviewed: Bool = false,
    diagnosticsAvailable: Bool = false,
    supportDocumentationAvailable: Bool = false,
    deviceCertified: Bool = false,
    circuitState: VoiceCircuitState = .closed
  ) {
    self.sampleCount = sampleCount
    self.stableReleaseCount = stableReleaseCount
    self.newP95Ms = newP95Ms
    self.legacyP95Ms = legacyP95Ms
    self.crashRate = crashRate
    self.legacyCrashRate = legacyCrashRate
    self.anrRate = anrRate
    self.legacyAnrRate = legacyAnrRate
    self.fallbackSuccessRate = fallbackSuccessRate
    self.privacyReviewed = privacyReviewed
    self.securityReviewed = securityReviewed
    self.diagnosticsAvailable = diagnosticsAvailable
    self.supportDocumentationAvailable = supportDocumentationAvailable
    self.deviceCertified = deviceCertified
    self.circuitState = circuitState
  }

  enum CodingKeys: String, CodingKey {
    case sampleCount = "sample_count"
    case stableReleaseCount = "stable_release_count"
    case newP95Ms = "new_p95_ms"
    case legacyP95Ms = "legacy_p95_ms"
    case crashRate = "crash_rate"
    case legacyCrashRate = "legacy_crash_rate"
    case anrRate = "anr_rate"
    case legacyAnrRate = "legacy_anr_rate"
    case fallbackSuccessRate = "fallback_success_rate"
    case privacyReviewed = "privacy_reviewed"
    case securityReviewed = "security_reviewed"
    case diagnosticsAvailable = "diagnostics_available"
    case supportDocumentationAvailable = "support_documentation_available"
    case deviceCertified = "device_certified"
    case circuitState = "circuit_state"
  }
}

struct VoiceRolloutDecision: Codable, Equatable {
  var feature: VoicePipelineFeature
  var enabled: Bool
  var stage: VoiceRolloutStage
  var cohortBucket: Int
  var rollbackLevel: VoiceRollbackLevel
  var reasonCodes: [String]

  enum CodingKeys: String, CodingKey {
    case feature
    case enabled
    case stage
    case cohortBucket = "cohort_bucket"
    case rollbackLevel = "rollback_level"
    case reasonCodes = "reason_codes"
  }
}

enum VoiceRolloutPolicy {
  static func decide(
    config: VoiceRolloutConfig,
    evidence: VoiceRolloutEvidence,
    stableDeviceId: String
  ) -> VoiceRolloutDecision {
    let bucket = VoiceCohortAssigner.bucket(stableDeviceId: stableDeviceId, feature: config.feature)
    if config.explicitlyDisabled {
      return disabled(config: config, bucket: bucket, rollback: .legacyPipeline, reasons: ["explicitly_disabled"])
    }
    if evidence.circuitState != .closed {
      return disabled(config: config, bucket: bucket, rollback: rollback(for: config.feature), reasons: ["circuit_open"])
    }

    var hardSafety: [String] = []
    if !evidence.privacyReviewed { hardSafety.append("privacy_review_required") }
    if !evidence.securityReviewed { hardSafety.append("security_review_required") }
    if !evidence.diagnosticsAvailable { hardSafety.append("diagnostics_required") }
    if requiresDeviceCertification(config.feature), !evidence.deviceCertified {
      hardSafety.append("device_certification_required")
    }
    if !hardSafety.isEmpty {
      return disabled(config: config, bucket: bucket, rollback: rollback(for: config.feature), reasons: hardSafety)
    }

    let audienceEligible: Bool
    switch config.stage {
    case .developer:
      audienceEligible = config.debuggable
    case .internal:
      audienceEligible = config.internalTester || config.debuggable
    case .optInBeta:
      audienceEligible = config.betaOptIn || config.requestedEnabled
    case .stableCohort, .certifiedExpansion:
      audienceEligible = bucket < min(max(config.cohortPercent, 0), 100)
    case .defaultWithFallback:
      audienceEligible = true
    }
    if !audienceEligible {
      return disabled(config: config, bucket: bucket, rollback: .legacyPipeline, reasons: ["outside_rollout_audience"])
    }

    if stageIndex(config.stage) >= stageIndex(.stableCohort) {
      let failures = qualityGateFailures(stage: config.stage, evidence: evidence)
      if !failures.isEmpty {
        return disabled(config: config, bucket: bucket, rollback: rollback(for: config.feature), reasons: failures)
      }
    }
    return VoiceRolloutDecision(
      feature: config.feature,
      enabled: true,
      stage: config.stage,
      cohortBucket: bucket,
      rollbackLevel: .none,
      reasonCodes: ["rollout_eligible"]
    )
  }

  private static func qualityGateFailures(
    stage: VoiceRolloutStage,
    evidence: VoiceRolloutEvidence
  ) -> [String] {
    var failures: [String] = []
    let minimumSamples: Int
    switch stage {
    case .stableCohort:
      minimumSamples = 30
    case .certifiedExpansion:
      minimumSamples = 100
    case .defaultWithFallback:
      minimumSamples = 300
    case .developer, .internal, .optInBeta:
      minimumSamples = 0
    }
    if evidence.sampleCount < minimumSamples { failures.append("insufficient_samples") }
    if evidence.stableReleaseCount < 2 { failures.append("insufficient_stable_releases") }
    if evidence.crashRate > evidence.legacyCrashRate + maxRateRegression { failures.append("crash_rate_regression") }
    if evidence.anrRate > evidence.legacyAnrRate + maxRateRegression { failures.append("anr_rate_regression") }
    if evidence.fallbackSuccessRate < minimumFallbackSuccessRate { failures.append("fallback_unreliable") }
    if let newP95 = evidence.newP95Ms, let legacyP95 = evidence.legacyP95Ms, legacyP95 > 0 {
      if newP95 > Int64(Double(legacyP95) * maximumP95Ratio) {
        failures.append("p95_not_improved")
      }
    } else {
      failures.append("p95_evidence_missing")
    }
    if !evidence.supportDocumentationAvailable { failures.append("support_documentation_required") }
    return failures
  }

  private static func disabled(
    config: VoiceRolloutConfig,
    bucket: Int,
    rollback: VoiceRollbackLevel,
    reasons: [String]
  ) -> VoiceRolloutDecision {
    VoiceRolloutDecision(
      feature: config.feature,
      enabled: false,
      stage: config.stage,
      cohortBucket: bucket,
      rollbackLevel: rollback,
      reasonCodes: reasons
    )
  }

  private static func requiresDeviceCertification(_ feature: VoicePipelineFeature) -> Bool {
    feature == .localWhisperRealtime || feature == .pcmCapture
  }

  private static func rollback(for feature: VoicePipelineFeature) -> VoiceRollbackLevel {
    switch feature {
    case .localWhisperRealtime:
      return .finalOnly
    case .pcmCapture, .onlineRealtimeASR, .cloudModelStream, .progressiveTTS, .agentOutputDelta:
      return .disableSingleOptimization
    }
  }

  private static func stageIndex(_ stage: VoiceRolloutStage) -> Int {
    VoiceRolloutStage.allCases.firstIndex(of: stage) ?? 0
  }

  private static let maxRateRegression = 0.001
  private static let minimumFallbackSuccessRate = 0.98
  private static let maximumP95Ratio = 0.95
}

enum VoiceCohortAssigner {
  static func bucket(stableDeviceId: String, feature: VoicePipelineFeature) -> Int {
    let identity = stableDeviceId.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("anonymous-device")
    let digest = Array(SHA256.hash(data: Data("\(identity):\(feature.rawValue)".utf8)))
    let unsigned = (Int(digest[0]) << 8) | Int(digest[1])
    return unsigned % 100
  }
}
