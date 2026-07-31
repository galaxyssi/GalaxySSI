import Foundation

enum VoiceWhisperModelRowAction: Equatable {
  case current
  case use
  case download
  case retry
  case waiting(progress: Int)

  var title: String {
    switch self {
    case .current:
      return "Current"
    case .use:
      return "Use"
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
    case .use, .download, .retry:
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

  var id: String { model.id }
  var title: String { model.displayName }

  var detail: String {
    "\(model.sizeLabel) - \(model.quantization.rawValue)\n\(lifecycleDetail)"
  }

  var action: VoiceWhisperModelRowAction {
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
}

enum VoiceWhisperModelSettingsPresenter {
  static let mirrorNote = "Downloads use hf-mirror.com. Models are stored in SignalASI app data and removed when the app is uninstalled."

  static func rows(
    models: [VoiceWhisperModelProfile] = VoiceWhisperModelCatalog.models,
    selectedModelId: String,
    downloadState: (VoiceWhisperModelProfile) -> VoiceWhisperModelDownloadState,
    isAvailable: (VoiceWhisperModelProfile) -> Bool,
    activeDownloadIds: Set<String> = []
  ) -> [VoiceWhisperModelRowPresentation] {
    let selected = VoiceWhisperModelCatalog.normalizedModelId(selectedModelId)
    return models.map { model in
      VoiceWhisperModelRowPresentation(
        model: model,
        selected: model.id == selected,
        available: isAvailable(model),
        downloadState: downloadState(model),
        activeDownload: activeDownloadIds.contains(model.id)
      )
    }
  }
}
