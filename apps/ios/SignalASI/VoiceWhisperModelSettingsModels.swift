import Foundation

enum VoiceWhisperModelRowAction: Equatable {
  case current
  case use
  case useAndTest
  case download
  case retry
  case waiting(progress: Int)

  var title: String {
    switch self {
    case .current:
      return "Current"
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

  var systemImageName: String {
    switch self {
    case .current:
      return "checkmark.circle.fill"
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
    case .use, .useAndTest, .download, .retry:
      return true
    case .current, .waiting:
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

  var action: VoiceWhisperModelRowAction {
    if let benchmarkProgress {
      return .waiting(progress: benchmarkProgressPercent(benchmarkProgress))
    }
    if available, benchmarkRecord == nil {
      return .useAndTest
    }
    if selected {
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
}

enum VoiceWhisperModelSettingsPresenter {
  static let mirrorNote = "Downloads use hf-mirror.com. Models are stored in SignalASI app data and removed when the app is uninstalled."

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
