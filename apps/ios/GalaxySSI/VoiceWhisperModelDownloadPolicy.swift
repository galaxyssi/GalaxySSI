import Foundation

enum VoiceWhisperNetworkClass: String, Codable, Equatable {
  case wifi = "WIFI"
  case unmetered = "UNMETERED"
  case metered = "METERED"
  case offline = "OFFLINE"
  case unknown = "UNKNOWN"
}

enum VoiceWhisperDownloadDecision: String, Codable, Equatable {
  case allow = "ALLOW"
  case requireMeteredConfirmation = "REQUIRE_METERED_CONFIRMATION"
  case waitForNetwork = "WAIT_FOR_NETWORK"
  case insufficientSpace = "INSUFFICIENT_SPACE"
}

struct VoiceWhisperDownloadPolicyResult: Codable, Equatable {
  var decision: VoiceWhisperDownloadDecision
  var requiredFreeBytes: Int64
  var availableFreeBytes: Int64

  init(
    decision: VoiceWhisperDownloadDecision,
    requiredFreeBytes: Int64,
    availableFreeBytes: Int64
  ) {
    self.decision = decision
    self.requiredFreeBytes = max(0, requiredFreeBytes)
    self.availableFreeBytes = max(availableFreeBytes, -1)
  }
}

enum VoiceWhisperModelDownloadPolicy {
  static func evaluate(
    profile: VoiceWhisperModelProfile,
    network: VoiceWhisperNetworkClass,
    availableFreeBytes: Int64,
    meteredConfirmed: Bool = false
  ) -> VoiceWhisperDownloadPolicyResult {
    let required = requiredFreeBytes(profile)
    let decision: VoiceWhisperDownloadDecision
    if availableFreeBytes >= 0, availableFreeBytes < required {
      decision = .insufficientSpace
    } else if network == .offline {
      decision = .waitForNetwork
    } else if requiresUnmetered(profile: profile), network == .metered, !meteredConfirmed {
      decision = .requireMeteredConfirmation
    } else {
      decision = .allow
    }
    return VoiceWhisperDownloadPolicyResult(
      decision: decision,
      requiredFreeBytes: required,
      availableFreeBytes: availableFreeBytes
    )
  }

  static func orderedSources(
    profile: VoiceWhisperModelProfile,
    locale: Locale
  ) -> [String] {
    let preferChinaMirror = (locale.languageCode ?? "").caseInsensitiveCompare("zh") == .orderedSame
    return profile.sourceURLs.sorted { left, right in
      sourceRank(left, preferChinaMirror: preferChinaMirror) < sourceRank(right, preferChinaMirror: preferChinaMirror)
    }
  }

  static func requiresUnmetered(profile: VoiceWhisperModelProfile) -> Bool {
    [.medium, .largeV3, .largeV3Turbo].contains(profile.family)
  }

  static func requiredFreeBytes(_ profile: VoiceWhisperModelProfile) -> Int64 {
    safeAdd(safeMultiply(VoiceWhisperModelVerifier.expectedSizeBytes(for: profile), 2), profile.minFreeStorageBytes)
  }

  private static func sourceRank(_ source: String, preferChinaMirror: Bool) -> Int {
    if preferChinaMirror, source.contains("hf-mirror.com") {
      return 0
    }
    if !preferChinaMirror, source.contains("huggingface.co") {
      return 0
    }
    return 1
  }

  private static func safeMultiply(_ value: Int64, _ multiplier: Int64) -> Int64 {
    let result = value.multipliedReportingOverflow(by: multiplier)
    return result.overflow ? Int64.max : result.partialValue
  }

  private static func safeAdd(_ left: Int64, _ right: Int64) -> Int64 {
    let result = left.addingReportingOverflow(right)
    return result.overflow ? Int64.max : result.partialValue
  }
}
