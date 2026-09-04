import Foundation

struct VoiceWhisperCertificationClassification: Codable, Equatable {
  var level: VoiceWhisperCertificationLevel
  var mode: VoiceWhisperExecutionMode
  var partialIntervalMillis: Int64
  var failureReason: String?
}

enum VoiceWhisperCertificationClassifier {
  static func classify(
    profile: VoiceWhisperModelProfile,
    rtfP95: Double,
    transcriptCorrect: Bool,
    maxThermalStatus: Int,
    abortLatencyMillisP95: Int64
  ) -> VoiceWhisperCertificationClassification {
    if !transcriptCorrect {
      return unsupported("Benchmark transcript correctness failed")
    }
    if maxThermalStatus >= thermalSevere {
      return remoteRecommended("Benchmark reached severe thermal pressure")
    }
    if abortLatencyMillisP95 > maxAbortLatencyMillis {
      return unsupported("Cancellation latency exceeded the safe limit")
    }
    if rtfP95 <= realtimeRtfP95 {
      return VoiceWhisperCertificationClassification(
        level: .realtime,
        mode: .realtimePartial,
        partialIntervalMillis: min(max(profile.defaultPartialIntervalMillis, 400), 3_000),
        failureReason: nil
      )
    }
    if rtfP95 <= finalRtfP95 {
      return VoiceWhisperCertificationClassification(
        level: .final,
        mode: .finalOnly,
        partialIntervalMillis: 0,
        failureReason: nil
      )
    }
    return VoiceWhisperCertificationClassification(
      level: .secondPass,
      mode: .secondPass,
      partialIntervalMillis: 0,
      failureReason: "RTF p95=\(formatRtf(rtfP95)) limits this model to background correction"
    )
  }

  private static func unsupported(_ reason: String) -> VoiceWhisperCertificationClassification {
    VoiceWhisperCertificationClassification(
      level: .unsupported,
      mode: .remoteNode,
      partialIntervalMillis: 0,
      failureReason: reason
    )
  }

  private static func remoteRecommended(_ reason: String) -> VoiceWhisperCertificationClassification {
    VoiceWhisperCertificationClassification(
      level: .remoteRecommended,
      mode: .remoteNode,
      partialIntervalMillis: 0,
      failureReason: reason
    )
  }

  private static func formatRtf(_ value: Double) -> String {
    String(format: "%.2f", value)
  }

  private static let realtimeRtfP95 = 0.80
  private static let finalRtfP95 = 1.50
  private static let maxAbortLatencyMillis: Int64 = 300
  private static let thermalSevere = 3
}
