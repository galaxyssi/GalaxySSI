import Foundation

enum VoiceWhisperBenchmarkRecordBuilder {
  static func certify(
    key: VoiceWhisperBenchmarkKey,
    profile: VoiceWhisperModelProfile,
    measurements: [VoiceWhisperBenchmarkMeasurement],
    stabilityMeasurements: [VoiceWhisperBenchmarkMeasurement],
    verificationDurationMillis: Int64,
    abortLatenciesMillis: [Int64],
    highPerformanceCoreCount: Int,
    threadCandidates: [Int],
    threadCount: Int,
    createdAtEpochMillis: Int64
  ) -> VoiceWhisperBenchmarkRecord {
    let stableRtf = stabilityMeasurements.map(\.realTimeFactor)
    let p50 = VoiceWhisperBenchmarkMath.percentile(stableRtf, percentile: 0.50)
    let p95 = VoiceWhisperBenchmarkMath.percentile(stableRtf, percentile: 0.95)
    let maxThermal = measurements.map(\.thermalStatusEnd).max() ?? 0
    let peakPss = measurements.map(\.peakPssBytes).max() ?? 0
    let requiredCorrect = Int(ceil(Double(stabilityMeasurements.count) / 2.0))
    let correct = stabilityMeasurements.filter(\.transcriptCorrect).count >= requiredCorrect
    let abortP95 = VoiceWhisperBenchmarkMath.percentileMillis(abortLatenciesMillis, percentile: 0.95)
    let classification = VoiceWhisperCertificationClassifier.classify(
      profile: profile,
      rtfP95: p95,
      transcriptCorrect: correct,
      maxThermalStatus: maxThermal,
      abortLatencyMillisP95: abortP95
    )
    let certification = VoiceWhisperCertification(
      key: key,
      level: classification.level,
      recommendedMode: classification.mode,
      recommendedThreadCount: threadCount,
      recommendedPartialIntervalMillis: classification.partialIntervalMillis,
      warmRtfP50: p50,
      warmRtfP95: p95,
      loadTimeMillisP95: VoiceWhisperBenchmarkMath.percentileMillis(
        measurements.map(\.loadDurationMillis),
        percentile: 0.95
      ),
      peakPssBytes: peakPss,
      maxThermalStatus: maxThermal,
      abortLatencyMillisP95: abortP95,
      createdAtEpochMillis: createdAtEpochMillis,
      failureReason: classification.failureReason
    )
    return VoiceWhisperBenchmarkRecord(
      certification: certification,
      measurements: measurements,
      verificationDurationMillis: verificationDurationMillis,
      abortLatenciesMillis: abortLatenciesMillis,
      highPerformanceCoreCount: highPerformanceCoreCount,
      threadCandidates: threadCandidates
    )
  }

  static func terminalRecord(
    key: VoiceWhisperBenchmarkKey,
    profile: VoiceWhisperModelProfile,
    level: VoiceWhisperCertificationLevel,
    reason: String,
    verificationDurationMillis: Int64,
    highPerformanceCoreCount: Int,
    threadCandidates: [Int],
    measurements: [VoiceWhisperBenchmarkMeasurement] = [],
    abortLatenciesMillis: [Int64] = [],
    fallbackThermalStatus: Int = 0,
    createdAtEpochMillis: Int64
  ) -> VoiceWhisperBenchmarkRecord {
    let terminalLevel: VoiceWhisperCertificationLevel = level == .remoteRecommended || level == .unsupported
      ? level
      : .unsupported
    let threadCount = threadCandidates.first ?? 1
    let maxThermal = measurements.map(\.thermalStatusEnd).max() ?? max(fallbackThermalStatus, 0)
    let certification = VoiceWhisperCertification(
      key: key,
      level: terminalLevel,
      recommendedMode: .remoteNode,
      recommendedThreadCount: threadCount,
      recommendedPartialIntervalMillis: 0,
      warmRtfP50: VoiceWhisperBenchmarkMath.percentile(measurements.map(\.realTimeFactor), percentile: 0.50),
      warmRtfP95: VoiceWhisperBenchmarkMath.percentile(measurements.map(\.realTimeFactor), percentile: 0.95),
      loadTimeMillisP95: VoiceWhisperBenchmarkMath.percentileMillis(
        measurements.map(\.loadDurationMillis),
        percentile: 0.95
      ),
      peakPssBytes: measurements.map(\.peakPssBytes).max() ?? 0,
      maxThermalStatus: maxThermal,
      abortLatencyMillisP95: VoiceWhisperBenchmarkMath.percentileMillis(abortLatenciesMillis, percentile: 0.95),
      createdAtEpochMillis: createdAtEpochMillis,
      failureReason: reason
    )
    return VoiceWhisperBenchmarkRecord(
      certification: certification,
      measurements: measurements,
      verificationDurationMillis: verificationDurationMillis,
      abortLatenciesMillis: abortLatenciesMillis,
      highPerformanceCoreCount: highPerformanceCoreCount,
      threadCandidates: threadCandidates
    )
  }

  static func preflightFailure(
    profile: VoiceWhisperModelProfile,
    system: VoiceWhisperBenchmarkSystemSnapshot
  ) -> String? {
    if system.systemLowMemory {
      return "iOS reported system-wide low memory"
    }
    if system.availableMemoryBytes < profile.minAvailableRamBytes + memorySafetyMarginBytes {
      return "The model does not have enough memory headroom on this device"
    }
    if system.thermalStatus >= thermalSevere {
      return "The device is too hot to certify this model"
    }
    return nil
  }

  static func thermalAllowsBenchmark(_ system: VoiceWhisperBenchmarkSystemSnapshot) -> Bool {
    system.thermalStatus < thermalModerate
  }

  static func transcriptMatches(_ transcript: String, expectedTokens: Set<String>) -> Bool {
    let normalized = normalizeTranscript(transcript)
    guard !normalized.isEmpty else {
      return false
    }
    let tokens = expectedTokens.map(normalizeTranscript).filter { !$0.isEmpty }
    guard !tokens.isEmpty else {
      return false
    }
    let matched = tokens.filter { normalized.contains($0) }.count
    return matched >= Int(ceil(Double(tokens.count) * minimumCorrectTokenRatio))
  }

  private static func normalizeTranscript(_ value: String) -> String {
    var normalized = ""
    for character in value.lowercased() {
      let mapped = benchmarkScriptNormalization[character] ?? character
      for scalar in String(mapped).unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
        normalized.unicodeScalars.append(scalar)
      }
    }
    return normalized
  }

  private static let memorySafetyMarginBytes: Int64 = 256 * 1_024 * 1_024
  private static let thermalModerate = 2
  private static let thermalSevere = 3
  private static let minimumCorrectTokenRatio = 0.60
  private static let benchmarkScriptNormalization: [Character: Character] = [
    "\u{8a9e}": "\u{8bed}",
    "\u{6e2c}": "\u{6d4b}",
    "\u{8a66}": "\u{8bd5}",
    "\u{5167}": "\u{5185}",
    "\u{6eab}": "\u{6e29}",
    "\u{61c9}": "\u{5e94}",
    "\u{8b58}": "\u{8bc6}",
    "\u{6e96}": "\u{51c6}"
  ]
}
