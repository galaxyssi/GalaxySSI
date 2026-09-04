import Foundation

typealias VoiceWhisperStringLocalizer = (String, String) -> String

enum VoiceWhisperModelRowAction: Equatable {
  case current
  case unavailable
  case use
  case useAndTest
  case download
  case retry
  case waiting(progress: Int)

  var title: String {
    switch self {
    case .current:
      return "Current"
    case .unavailable:
      return "Unavailable"
    case .use:
      return "Use"
    case .useAndTest:
      return "Use and test"
    case .download:
      return "Download"
    case .retry:
      return "Retry"
    case .waiting(let progress):
      return progress > 0 ? "\(progress)%" : "Waiting"
    }
  }

  func localizedTitle(_ localized: VoiceWhisperStringLocalizer) -> String {
    switch self {
    case .current:
      return localized("section_current", "Current")
    case .unavailable:
      return localized("voice_asr_model_unsupported", "Unsupported on this device")
    case .use:
      return localized("settings_language_use", "Use")
    case .useAndTest:
      return localized("voice_asr_model_use_and_test", "Use and test")
    case .download:
      return localized("voice_asr_model_download", "Download")
    case .retry:
      return localized("galaxyssi.common.retry", "Retry")
    case .waiting(let progress):
      if progress > 0 {
        return String(format: localized("voice_asr_model_progress_short", "%d%%"), progress)
      }
      return localized("voice_asr_model_waiting", "Waiting")
    }
  }

  var systemImageName: String {
    switch self {
    case .current:
      return "checkmark.circle.fill"
    case .unavailable:
      return "xmark.octagon"
    case .use:
      return "arrow.right.circle"
    case .useAndTest:
      return "speedometer"
    case .download:
      return "arrow.down.circle"
    case .retry:
      return "arrow.clockwise.circle"
    case .waiting:
      return "clock"
    }
  }

  var isEnabled: Bool {
    switch self {
    case .current, .use, .useAndTest, .download, .retry:
      return true
    case .unavailable, .waiting:
      return false
    }
  }
}

struct VoiceWhisperModelRowPresentation: Equatable, Identifiable {
  var model: VoiceWhisperModelProfile
  var selected: Bool
  var available: Bool
  var downloadState: VoiceWhisperModelDownloadState
  var activeDownload: Bool
  var benchmarkRecord: VoiceWhisperBenchmarkRecord?
  var latestBenchmarkRecord: VoiceWhisperBenchmarkRecord?
  var benchmarkProgress: VoiceWhisperBenchmarkProgress?

  var id: String { model.id }
  var title: String { model.displayName }

  var detail: String {
    "\(model.sizeLabel) - \(model.quantization.rawValue)\n\(lifecycleDetail)"
  }

  func localizedDetail(_ localized: VoiceWhisperStringLocalizer) -> String {
    if !model.supportsIOSRuntime {
      return String(
        format: localized(
          "voice_asr_model_platform_detail",
          "%@ - Android/Qualcomm model; unavailable on iOS"
        ),
        "\(model.sizeLabel) · \(model.targetChipset.isEmpty ? model.artifactFormat.rawValue : model.targetChipset)"
      )
    }
    return String(
      format: localized("voice_asr_model_profile_detail", "%@ - %@\n%@"),
      model.sizeLabel,
      model.quantization.rawValue,
      localizedLifecycleDetail(localized)
    )
  }

  var action: VoiceWhisperModelRowAction {
    if !model.supportsIOSRuntime {
      return .unavailable
    }
    if let benchmarkProgress {
      return .waiting(progress: benchmarkProgressPercent(benchmarkProgress))
    }
    if benchmarkRecord?.certification.level == .unsupported {
      return .unavailable
    }
    if available, benchmarkRecord == nil {
      return .useAndTest
    }
    if selected, available {
      return .current
    }
    if available || model.bundled {
      return .use
    }
    if activeDownload || [.pending, .running, .paused].contains(downloadState.status) {
      return .waiting(progress: downloadState.progress)
    }
    if downloadState.status == .failed {
      return .retry
    }
    return .download
  }

  var removable: Bool {
    available && !model.bundled && !selected
  }

  private var lifecycleDetail: String {
    if let benchmarkProgress {
      return "Benchmarking \(benchmarkStageLabel(benchmarkProgress)) \(benchmarkProgressPercent(benchmarkProgress))%"
    }
    if let benchmarkRecord {
      return certificationLabel(benchmarkRecord.certification.level)
    }
    if available, latestBenchmarkRecord != nil {
      return "Previous result is stale and cannot control the current model build."
    }
    if model.bundled {
      return "Included with the app"
    }
    if available {
      return "Installed"
    }
    if activeDownload || [.pending, .running, .paused].contains(downloadState.status) {
      return downloadState.progress > 0 ? "Downloading \(downloadState.progress)%" : "Waiting to download"
    }
    if downloadState.status == .failed {
      return "Install failed"
    }
    return "Download required"
  }

  private func localizedLifecycleDetail(_ localized: VoiceWhisperStringLocalizer) -> String {
    if let benchmarkProgress {
      return String(
        format: localized("voice_asr_model_benchmark_progress", "%@ - %d%%"),
        localizedBenchmarkStageLabel(benchmarkProgress, localized: localized),
        benchmarkProgressPercent(benchmarkProgress)
      )
    }
    if let benchmarkRecord {
      return localizedCertificationLabel(benchmarkRecord.certification.level, localized: localized)
    }
    if available, latestBenchmarkRecord != nil {
      return localized(
        "voice_asr_model_benchmark_stale",
        "Previous result is stale and cannot control the current model build."
      )
    }
    if model.bundled {
      return localized("voice_asr_model_bundled", "Included with the app")
    }
    if available {
      return localized("voice_asr_model_installed_uncertified", "Installed - Ready to use")
    }
    if activeDownload || [.pending, .running, .paused].contains(downloadState.status) {
      if downloadState.progress > 0 {
        return String(format: localized("voice_asr_model_progress", "%d%% downloaded"), downloadState.progress)
      }
      return localized("voice_asr_model_waiting", "Waiting")
    }
    if downloadState.status == .failed {
      return localized("voice_asr_model_install_failed_short", "Install failed")
    }
    return localized("voice_asr_model_download_size", "Download required")
  }

  private func benchmarkProgressPercent(_ progress: VoiceWhisperBenchmarkProgress) -> Int {
    guard progress.totalSteps > 0 else { return 0 }
    return min(max(progress.completedSteps * 100 / progress.totalSteps, 0), 100)
  }

  private func certificationLabel(_ level: VoiceWhisperCertificationLevel) -> String {
    switch level {
    case .untested:
      return "Installed - Benchmark required before real-time use"
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

  private func benchmarkStageLabel(_ progress: VoiceWhisperBenchmarkProgress) -> String {
    switch progress.stage {
    case .verifying:
      return "Verifying model"
    case .checkingDevice:
      return "Checking device"
    case .searchingThreads:
      return "Searching threads"
    case .stability:
      return "Testing stability"
    case .cancellation:
      return "Testing cancellation"
    case .certifying:
      return "Creating certification"
    case .complete:
      return "Complete"
    }
  }

  private func localizedCertificationLabel(
    _ level: VoiceWhisperCertificationLevel,
    localized: VoiceWhisperStringLocalizer
  ) -> String {
    switch level {
    case .untested:
      return localized("voice_asr_model_installed_uncertified", "Installed - Ready to use")
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

  private func localizedBenchmarkStageLabel(
    _ progress: VoiceWhisperBenchmarkProgress,
    localized: VoiceWhisperStringLocalizer
  ) -> String {
    switch progress.stage {
    case .verifying:
      return localized("voice_asr_benchmark_stage_verifying", "Verifying model")
    case .checkingDevice:
      return localized("voice_asr_benchmark_stage_device", "Checking device")
    case .searchingThreads:
      return localized("voice_asr_benchmark_stage_threads", "Searching threads")
    case .stability:
      return localized("voice_asr_benchmark_stage_stability", "Testing stability")
    case .cancellation:
      return localized("voice_asr_benchmark_stage_cancellation", "Testing cancellation")
    case .certifying:
      return localized("voice_asr_benchmark_stage_certifying", "Creating certification")
    case .complete:
      return localized("voice_asr_benchmark_stage_complete", "Complete")
    }
  }
}

enum VoiceWhisperModelSettingsPresenter {
  static let mirrorNoteKey = "voice_asr_model_mirror_note"
  static let mirrorNote = "Downloads use hf-mirror.com. Models are stored in GalaxySSI app data and removed when the app is uninstalled."

  static func rows(
    models: [VoiceWhisperModelProfile] = VoiceWhisperModelCatalog.models,
    selectedModelId: String,
    downloadState: (VoiceWhisperModelProfile) -> VoiceWhisperModelDownloadState,
    isAvailable: (VoiceWhisperModelProfile) -> Bool,
    benchmarkRecord: (VoiceWhisperModelProfile) -> VoiceWhisperBenchmarkRecord? = { _ in nil },
    latestBenchmarkRecord: (VoiceWhisperModelProfile) -> VoiceWhisperBenchmarkRecord? = { _ in nil },
    benchmarkProgress: (VoiceWhisperModelProfile) -> VoiceWhisperBenchmarkProgress? = { _ in nil },
    activeDownloadIds: Set<String> = []
  ) -> [VoiceWhisperModelRowPresentation] {
    let selected = VoiceWhisperModelCatalog.normalizedModelId(selectedModelId)
    return models.map { model in
      VoiceWhisperModelRowPresentation(
        model: model,
        selected: model.id == selected,
        available: isAvailable(model),
        downloadState: downloadState(model),
        activeDownload: activeDownloadIds.contains(model.id),
        benchmarkRecord: benchmarkRecord(model),
        latestBenchmarkRecord: latestBenchmarkRecord(model),
        benchmarkProgress: benchmarkProgress(model)
      )
    }
  }
}
