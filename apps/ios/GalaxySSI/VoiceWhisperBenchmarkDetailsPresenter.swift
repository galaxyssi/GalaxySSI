import Foundation

struct VoiceWhisperBenchmarkDetailsPresentation: Equatable, Identifiable {
  var id: String
  var title: String
  var message: String
}

enum VoiceWhisperBenchmarkDetailsPresenter {
  static func presentation(
    model: VoiceWhisperModelProfile,
    record: VoiceWhisperBenchmarkRecord,
    localized: VoiceWhisperStringLocalizer = { _, fallback in fallback }
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
      String(
        format: localized("voice_asr_model_benchmark_recommendation", "Recommended: %@"),
        certificationLabel(certification.level, localized: localized)
      ),
      String(
        format: localized(
          "voice_asr_model_benchmark_metrics",
          "RTF p50 / p95: %.2f / %.2f\nPeak PSS: %@\nBest threads: %d\nThermal status: %d\nCancellation p95: %d ms"
        ),
        certification.warmRtfP50,
        certification.warmRtfP95,
        formatBytes(certification.peakPssBytes),
        certification.recommendedThreadCount,
        certification.maxThermalStatus,
        Int(certification.abortLatencyMillisP95)
      ),
      String(
        format: localized(
          "voice_asr_model_benchmark_latency_metrics",
          "Cold / hot load p95: %d / %d ms\nFirst partial / final tail p95: %d / %d ms"
        ),
        Int(coldLoadP95),
        Int(hotLoadP95),
        Int(firstPartialP95),
        Int(finalTailP95)
      ),
      String(
        format: localized("voice_asr_model_benchmark_memory_metrics", "Peak RSS / native heap: %@ / %@"),
        formatBytes(measurements.map(\.peakRssBytes).max() ?? 0),
        formatBytes(measurements.map(\.peakNativeAllocatedBytes).max() ?? 0)
      ),
      certification.failureReason.map {
        String(format: localized("voice_asr_model_benchmark_failure_reason", "Reason: %@"), $0)
      }
    ]
    .compactMap { $0 }
    .joined(separator: "\n")
    return VoiceWhisperBenchmarkDetailsPresentation(
      id: certification.key.stableId,
      title: String(
        format: localized("voice_asr_model_benchmark_details_title", "%@ device certification"),
        model.displayName
      ),
      message: message
    )
  }

  private static func certificationLabel(
    _ level: VoiceWhisperCertificationLevel,
    localized: VoiceWhisperStringLocalizer
  ) -> String {
    switch level {
    case .untested:
      return localized("voice_asr_model_benchmark_required", "Benchmark required")
    case .realtime:
      return localized("voice_asr_model_certified_realtime", "Real-time certified")
    case .final:
      return localized("voice_asr_model_certified_final", "Final transcription")
    case .secondPass:
      return localized("voice_asr_model_certified_second_pass", "Background accuracy pass")
    case .remoteRecommended:
      return localized("voice_asr_model_remote_recommended", "Remote recommended")
    case .unsupported:
      return localized("voice_asr_model_unsupported", "Unsupported on this device")
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
