import Foundation

enum VoiceWhisperUserVoiceMode: String, Codable, Equatable, CaseIterable, Identifiable {
  case automatic = "AUTOMATIC"
  case fast = "FAST"
  case powerSaver = "POWER_SAVER"
  case accurate = "ACCURATE"
  case privacy = "PRIVACY"
  case manual = "MANUAL"

  var id: String { rawValue }

  var displayTitle: String {
    switch self {
    case .automatic:
      return "Automatic"
    case .fast:
      return "Fast"
    case .powerSaver:
      return "Power saver"
    case .accurate:
      return "Accurate"
    case .privacy:
      return "Privacy"
    case .manual:
      return "Selected model"
    }
  }

  static func normalized(_ value: String?) -> VoiceWhisperUserVoiceMode {
    let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return VoiceWhisperUserVoiceMode(rawValue: clean) ?? .automatic
  }
}

enum VoiceWhisperProviderChoice: String, Codable, Equatable {
  case local = "LOCAL"
  case remote = "REMOTE"
  case unavailable = "UNAVAILABLE"
}

enum VoiceWhisperNetworkState: String, Codable, Equatable {
  case offline = "OFFLINE"
  case metered = "METERED"
  case unmetered = "UNMETERED"
}

struct VoiceWhisperRuntimeEnvironment: Codable, Equatable {
  var network: VoiceWhisperNetworkState
  var availableMemoryBytes: Int64
  var currentPssBytes: Int64
  var thermalStatus: Int
  var batteryPercent: Int?
  var charging: Bool
  var foreground: Bool
  var recentRealTimeFactor: Double?
  var decodeQueueDepth: Int
  var utteranceDurationMillis: Int64
  var highRiskTask: Bool
  var accuracySensitiveTask: Bool
  var remoteAllowed: Bool

  init(
    network: VoiceWhisperNetworkState = .offline,
    availableMemoryBytes: Int64 = 0,
    currentPssBytes: Int64 = 0,
    thermalStatus: Int = 0,
    batteryPercent: Int? = nil,
    charging: Bool = false,
    foreground: Bool = true,
    recentRealTimeFactor: Double? = nil,
    decodeQueueDepth: Int = 0,
    utteranceDurationMillis: Int64 = 0,
    highRiskTask: Bool = false,
    accuracySensitiveTask: Bool = false,
    remoteAllowed: Bool = false
  ) {
    self.network = network
    self.availableMemoryBytes = max(availableMemoryBytes, 0)
    self.currentPssBytes = max(currentPssBytes, 0)
    self.thermalStatus = max(thermalStatus, 0)
    self.batteryPercent = batteryPercent.map { min(max($0, 0), 100) }
    self.charging = charging
    self.foreground = foreground
    self.recentRealTimeFactor = recentRealTimeFactor?.isFinite == true ? recentRealTimeFactor : nil
    self.decodeQueueDepth = max(decodeQueueDepth, 0)
    self.utteranceDurationMillis = max(utteranceDurationMillis, 0)
    self.highRiskTask = highRiskTask
    self.accuracySensitiveTask = accuracySensitiveTask
    self.remoteAllowed = remoteAllowed
  }
}

struct VoiceWhisperRuntimeCandidate: Codable, Equatable {
  var profile: VoiceWhisperModelProfile
  var installed: Bool
  var certification: VoiceWhisperCertification?
}

struct VoiceWhisperRuntimePolicyInput: Codable, Equatable {
  var userMode: VoiceWhisperUserVoiceMode
  var selectedProfileId: String?
  var candidates: [VoiceWhisperRuntimeCandidate]
  var environment: VoiceWhisperRuntimeEnvironment

  init(
    userMode: VoiceWhisperUserVoiceMode = .automatic,
    selectedProfileId: String? = nil,
    candidates: [VoiceWhisperRuntimeCandidate] = [],
    environment: VoiceWhisperRuntimeEnvironment
  ) {
    self.userMode = userMode
    let cleanSelectedProfileId = selectedProfileId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.selectedProfileId = cleanSelectedProfileId.isEmpty ? nil : cleanSelectedProfileId
    self.candidates = candidates
    self.environment = environment
  }
}

struct VoiceWhisperRuntimeDecision: Codable, Equatable {
  var provider: VoiceWhisperProviderChoice
  var fastProfileId: String?
  var fastMode: VoiceWhisperExecutionMode?
  var accurateProfileId: String?
  var accurateMode: VoiceWhisperExecutionMode?
  var partialIntervalMillis: Int64?
  var threadCount: Int?
  var runSecondPass: Bool
  var reasons: [String]
}

enum VoiceWhisperRuntimePolicyEngine {
  static func decide(_ input: VoiceWhisperRuntimePolicyInput) -> VoiceWhisperRuntimeDecision {
    let environment = input.environment
    var reasons: [String] = []
    let usable = input.candidates.filter { candidate in
      guard candidate.installed,
        let certification = candidate.certification,
        localCertificationLevels.contains(certification.level),
        certification.key.modelProfileId == candidate.profile.id else {
        return false
      }
      return memoryAllowed(candidate, environment: environment, reasons: &reasons) &&
        thermalAllowed(candidate, environment: environment, reasons: &reasons)
    }
    let realtime = usable
      .filter { $0.certification?.realtimeCertified == true }
      .sorted { left, right in
        let leftRtf = left.certification?.warmRtfP95 ?? Double.greatestFiniteMagnitude
        let rightRtf = right.certification?.warmRtfP95 ?? Double.greatestFiniteMagnitude
        if leftRtf != rightRtf {
          return leftRtf < rightRtf
        }
        return qualityRank(left.profile.family) > qualityRank(right.profile.family)
      }
    let accurate = usable
      .filter { candidate in
        guard let level = candidate.certification?.level else { return false }
        return [.realtime, .final, .secondPass].contains(level)
      }
      .sorted { left, right in
        let leftRank = qualityRank(left.profile.family)
        let rightRank = qualityRank(right.profile.family)
        if leftRank != rightRank {
          return leftRank > rightRank
        }
        return (left.certification?.warmRtfP95 ?? Double.greatestFiniteMagnitude) <
          (right.certification?.warmRtfP95 ?? Double.greatestFiniteMagnitude)
      }
    let selected = input.selectedProfileId.flatMap { id in
      usable.first { $0.profile.id == id }
    }
    let conservativeLocalFallbacks = input.candidates
      .filter { candidate in
        let hasConservativeCertification = candidate.certification == nil ||
          candidate.certification?.level == .remoteRecommended
        guard candidate.installed, hasConservativeCertification else {
          return false
        }
        return memoryAllowed(candidate, environment: environment, reasons: &reasons) &&
          thermalAllowed(candidate, environment: environment, reasons: &reasons)
      }
      .sorted { left, right in
        let leftSelected = left.profile.id == input.selectedProfileId
        let rightSelected = right.profile.id == input.selectedProfileId
        if leftSelected != rightSelected {
          return leftSelected
        }
        let leftRank = qualityRank(left.profile.family)
        let rightRank = qualityRank(right.profile.family)
        if leftRank != rightRank {
          return leftRank < rightRank
        }
        return left.profile.id < right.profile.id
      }

    if environment.thermalStatus >= thermalCritical {
      reasons.append("Critical thermal pressure blocks local Whisper")
      return remoteOrUnavailable(input, reasons: reasons)
    }
    switch input.userMode {
    case .automatic, .fast:
      guard let fast = realtime.first else {
        reasons.append("Automatic mode requires a current realtime certification")
        let remote = remoteOrUnavailable(input, reasons: reasons)
        guard remote.provider == .unavailable,
              let fallback = conservativeLocalFallbacks.first else {
          return remote
        }
        reasons.append("\(fallback.profile.displayName) is used in conservative final-only mode")
        return uncertifiedLocalDecision(fallback, reasons: reasons)
      }
      let certification = fast.certification!
      let shouldUseSecondPass = (input.userMode == .automatic ||
        environment.highRiskTask || environment.accuracySensitiveTask) &&
        shouldRunSecondPass(environment) &&
        accurate.contains { $0.profile.id != fast.profile.id }
      let accurateCandidate = shouldUseSecondPass ? accurate.first { $0.profile.id != fast.profile.id } : nil
      reasons.append("\(fast.profile.displayName) is realtime-certified at RTF p95=\(formatRtf(certification.warmRtfP95))")
      return localDecision(fast: fast, accurate: accurateCandidate, environment: environment, reasons: reasons)

    case .privacy:
      guard let fast = realtime.first else {
        if let fallback = conservativeLocalFallbacks.first {
          reasons.append("Privacy mode uses \(fallback.profile.displayName) in conservative final-only mode")
          return uncertifiedLocalDecision(fallback, reasons: reasons)
        }
        reasons.append("Privacy mode has no realtime-certified local model")
        return unavailable(reasons)
      }
      reasons.append("Privacy mode keeps audio on this device")
      let accurateCandidate = environment.highRiskTask && shouldRunSecondPass(environment)
        ? accurate.first { $0.profile.id != fast.profile.id }
        : nil
      return localDecision(
        fast: fast,
        accurate: accurateCandidate,
        environment: environment,
        reasons: reasons
      )

    case .powerSaver:
      let efficient = selected ?? usable.min { left, right in
        if left.profile.expectedSizeBytes != right.profile.expectedSizeBytes {
          return left.profile.expectedSizeBytes < right.profile.expectedSizeBytes
        }
        return left.profile.id < right.profile.id
      }
      guard let efficient else {
        if let fallback = conservativeLocalFallbacks.min(by: {
          $0.profile.expectedSizeBytes < $1.profile.expectedSizeBytes
        }) {
          reasons.append("Power saver mode uses the smallest available local model")
          return uncertifiedLocalDecision(fallback, reasons: reasons)
        }
        reasons.append("Power saver mode has no certified local model")
        return remoteOrUnavailable(input, reasons: reasons)
      }
      reasons.append("Power saver mode runs local Whisper only at sentence end")
      return localDecision(
        fast: efficient,
        accurate: nil,
        environment: environment,
        reasons: reasons,
        forceFinal: true
      )

    case .accurate:
      guard let accurateCandidate = accurate.first else {
        reasons.append("No certified accurate local model is available")
        return remoteOrUnavailable(input, reasons: reasons)
      }
      if let fast = realtime.first, fast.profile.id != accurateCandidate.profile.id {
        reasons.append("Realtime pass is followed by a certified accuracy pass")
        return localDecision(fast: fast, accurate: accurateCandidate, environment: environment, reasons: reasons)
      }
      reasons.append("Accurate mode uses \(accurateCandidate.profile.displayName) in final mode")
      return localDecision(fast: accurateCandidate, accurate: nil, environment: environment, reasons: reasons, forceFinal: true)

    case .manual:
      guard let selected else {
        if let fallback = conservativeLocalFallbacks.first(where: {
          $0.profile.id == input.selectedProfileId
        }) {
          reasons.append("The selected model is used in conservative final-only mode")
          return uncertifiedLocalDecision(fallback, reasons: reasons)
        }
        reasons.append("The selected model has no current certification")
        return remoteOrUnavailable(input, reasons: reasons)
      }
      reasons.append("Manual mode uses the selected certified model")
      let accurateCandidate = environment.highRiskTask && shouldRunSecondPass(environment)
        ? accurate.first { $0.profile.id != selected.profile.id }
        : nil
      return localDecision(
        fast: selected,
        accurate: accurateCandidate,
        environment: environment,
        reasons: reasons,
        forceFinal: selected.certification?.realtimeCertified != true
      )
    }
  }

  private static func localDecision(
    fast: VoiceWhisperRuntimeCandidate,
    accurate: VoiceWhisperRuntimeCandidate?,
    environment: VoiceWhisperRuntimeEnvironment,
    reasons: [String],
    forceFinal: Bool = false
  ) -> VoiceWhisperRuntimeDecision {
    guard let certification = fast.certification else {
      return unavailable(reasons)
    }
    var reasons = reasons
    let thermalConstrained = environment.thermalStatus >= thermalSevere
    let backlogConstrained = environment.decodeQueueDepth >= 2 ||
      (environment.recentRealTimeFactor ?? 0) > 1
    let mode: VoiceWhisperExecutionMode = forceFinal || thermalConstrained ? .finalOnly : certification.recommendedMode
    let partialInterval: Int64?
    if mode == .realtimePartial {
      var interval = certification.recommendedPartialIntervalMillis
      if backlogConstrained {
        interval *= 2
      }
      if environment.thermalStatus >= thermalModerate {
        interval *= 2
      }
      partialInterval = min(max(interval, minPartialIntervalMillis), maxPartialIntervalMillis)
    } else {
      partialInterval = nil
    }
    let thermalThreadLimit = thermalConstrained || environment.thermalStatus >= thermalModerate
    let threads = max(thermalThreadLimit ? min(certification.recommendedThreadCount, 2) : certification.recommendedThreadCount, 1)
    if thermalConstrained {
      reasons.append("Severe thermal pressure disables realtime partial decoding")
    }
    if backlogConstrained, partialInterval != nil {
      reasons.append("Decode backlog increased the partial interval")
    }
    return VoiceWhisperRuntimeDecision(
      provider: .local,
      fastProfileId: fast.profile.id,
      fastMode: mode,
      accurateProfileId: accurate?.profile.id,
      accurateMode: accurate?.certification?.recommendedMode,
      partialIntervalMillis: partialInterval,
      threadCount: threads,
      runSecondPass: accurate != nil && environment.thermalStatus < thermalSevere,
      reasons: unique(reasons)
    )
  }

  private static func uncertifiedLocalDecision(
    _ candidate: VoiceWhisperRuntimeCandidate,
    reasons: [String]
  ) -> VoiceWhisperRuntimeDecision {
    VoiceWhisperRuntimeDecision(
      provider: .local,
      fastProfileId: candidate.profile.id,
      fastMode: .finalOnly,
      accurateProfileId: nil,
      accurateMode: nil,
      partialIntervalMillis: nil,
      threadCount: 2,
      runSecondPass: false,
      reasons: unique(reasons)
    )
  }

  private static func memoryAllowed(
    _ candidate: VoiceWhisperRuntimeCandidate,
    environment: VoiceWhisperRuntimeEnvironment,
    reasons: inout [String]
  ) -> Bool {
    let certifiedPeak = candidate.certification?.peakPssBytes ?? 0
    let incrementalMemory = certifiedPeak > 0
      ? max(certifiedPeak - environment.currentPssBytes, 0)
      : candidate.profile.minAvailableRamBytes
    let required = incrementalMemory + memorySafetyMarginBytes
    let allowed = required <= environment.availableMemoryBytes
    if !allowed {
      reasons.append("\(candidate.profile.displayName) needs more certified memory headroom")
    }
    return allowed
  }

  private static func thermalAllowed(
    _ candidate: VoiceWhisperRuntimeCandidate,
    environment: VoiceWhisperRuntimeEnvironment,
    reasons: inout [String]
  ) -> Bool {
    if environment.thermalStatus < thermalSevere {
      return true
    }
    let large = [.medium, .largeV3, .largeV3Turbo].contains(candidate.profile.family)
    if large {
      reasons.append("\(candidate.profile.displayName) is blocked by severe thermal pressure")
    }
    return !large
  }

  private static func shouldRunSecondPass(_ environment: VoiceWhisperRuntimeEnvironment) -> Bool {
    environment.foreground &&
      environment.thermalStatus < thermalSevere &&
      environment.decodeQueueDepth == 0 &&
      (environment.highRiskTask ||
        environment.accuracySensitiveTask ||
        environment.utteranceDurationMillis >= minSecondPassAudioMillis)
  }

  private static func remoteOrUnavailable(
    _ input: VoiceWhisperRuntimePolicyInput,
    reasons: [String]
  ) -> VoiceWhisperRuntimeDecision {
    let environment = input.environment
    if environment.remoteAllowed,
      environment.network != .offline,
      input.userMode != .privacy {
      return VoiceWhisperRuntimeDecision(
        provider: .remote,
        fastProfileId: nil,
        fastMode: .remoteNode,
        accurateProfileId: nil,
        accurateMode: nil,
        partialIntervalMillis: nil,
        threadCount: nil,
        runSecondPass: false,
        reasons: unique(reasons + ["A remote ASR provider is recommended"])
      )
    }
    return unavailable(reasons)
  }

  private static func unavailable(_ reasons: [String]) -> VoiceWhisperRuntimeDecision {
    VoiceWhisperRuntimeDecision(
      provider: .unavailable,
      fastProfileId: nil,
      fastMode: nil,
      accurateProfileId: nil,
      accurateMode: nil,
      partialIntervalMillis: nil,
      threadCount: nil,
      runSecondPass: false,
      reasons: unique(reasons)
    )
  }

  private static func qualityRank(_ family: VoiceWhisperModelFamily) -> Int {
    switch family {
    case .tiny:
      return 1
    case .base:
      return 2
    case .small:
      return 3
    case .medium:
      return 4
    case .largeV3Turbo:
      return 5
    case .largeV3:
      return 6
    }
  }

  private static func formatRtf(_ value: Double) -> String {
    String(format: "%.2f", value)
  }

  private static func unique(_ reasons: [String]) -> [String] {
    var seen: Set<String> = []
    return reasons.filter { seen.insert($0).inserted }
  }

  private static let memorySafetyMarginBytes: Int64 = 256 * 1_024 * 1_024
  private static let minPartialIntervalMillis: Int64 = 400
  private static let maxPartialIntervalMillis: Int64 = 8_000
  private static let minSecondPassAudioMillis: Int64 = 3_000
  private static let thermalModerate = 2
  private static let thermalSevere = 3
  private static let thermalCritical = 4
  private static let localCertificationLevels: Set<VoiceWhisperCertificationLevel> = [.realtime, .final, .secondPass]
}
