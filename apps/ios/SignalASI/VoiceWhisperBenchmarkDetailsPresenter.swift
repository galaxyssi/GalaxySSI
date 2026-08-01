import Foundation

struct VoiceWhisperBenchmarkDetailsPresentation: Equatable, Identifiable {
  var id: String
  var title: String
  var message: String
}

enum VoiceWhisperBenchmarkDetailsPresenter {
  static func presentation(
    model: VoiceWhisperModelProfile,
    record: VoiceWhisperBenchmarkRecord
  ) -> VoiceWhisperBenchmarkDetailsPresentation {
    let certification = record.certification
    let measurements = record.measurements
    let coldLoadP95 = VoiceWhisperBenchmarkMath.percentileMillis(
      measurements.filter { $0.loadKind == .cold }.map(\.loadDurationMillis),
      percentile: 0.95
    )
    let hotLoadP95 = VoiceWhisperBenchmarkMath.percentileMillis(
      measurements.filter { $0.loadKind == .hot }.map(\.loadDurationMillis),
      percentile: 0.95
    )
    let firstPartialP95 = VoiceWhisperBenchmarkMath.percentileMillis(
      measurements.map(\.firstPartialLatencyMillis).filter { $0 > 0 },
      percentile: 0.95
    )
    let finalTailP95 = VoiceWhisperBenchmarkMath.percentileMillis(
      measurements.map(\.finalTailLatencyMillis).filter { $0 > 0 },
      percentile: 0.95
    )
    let message = [
      "Recommended: \(certificationLabel(certification.level))",
      String(
        format: "RTF p50 / p95: %.2f / %.2f",
        certification.warmRtfP50,
        certification.warmRtfP95
      ),
      "Peak PSS: \(formatBytes(certification.peakPssBytes))",
      "Best threads: \(certification.recommendedThreadCount)",
      "Thermal status: \(certification.maxThermalStatus)",
      "Cancellation p95: \(certification.abortLatencyMillisP95) ms",
      "Cold / hot load p95: \(coldLoadP95) / \(hotLoadP95) ms",
      "First partial / final tail p95: \(firstPartialP95) / \(finalTailP95) ms",
      "Peak RSS / native heap: \(formatBytes(measurements.map(\.peakRssBytes).max() ?? 0)) / " +
        "\(formatBytes(measurements.map(\.peakNativeAllocatedBytes).max() ?? 0))",
      certification.failureReason.map { "Reason: \($0)" }
    ]
    .compactMap { $0 }
    .joined(separator: "\n")
    return VoiceWhisperBenchmarkDetailsPresentation(
      id: certification.key.stableId,
      title: "\(model.displayName) device certification",
      message: message
    )
  }

  private static func certificationLabel(_ level: VoiceWhisperCertificationLevel) -> String {
    switch level {
    case .untested:
      return "Benchmark required"
    case .realtime:
      return "Real-time certified"
    case .final:
      return "Final transcription"
    case .secondPass:
      return "Background accuracy pass"
    case .remoteRecommended:
      return "Remote recommended"
    case .unsupported:
      return "Unsupported on this device"
    }
  }

  private static func formatBytes(_ bytes: Int64) -> String {
    let safeBytes = max(bytes, 0)
    if safeBytes >= 1_024 * 1_024 * 1_024 {
      return String(format: "%.1f GB", Double(safeBytes) / Double(1_024 * 1_024 * 1_024))
    }
    if safeBytes >= 1_024 * 1_024 {
      return String(format: "%.1f MB", Double(safeBytes) / Double(1_024 * 1_024))
    }
    if safeBytes >= 1_024 {
      return String(format: "%.1f KB", Double(safeBytes) / 1_024.0)
    }
    return "\(safeBytes) B"
  }
}
