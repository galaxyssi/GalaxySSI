import SwiftUI

struct VoiceWhisperModelSettingsView: View {
  @EnvironmentObject private var store: SignalASIStore
  private let modelManager: VoiceWhisperModelManager
  private let downloadService: VoiceWhisperModelDownloadService

  @State private var downloadStates: [String: VoiceWhisperModelDownloadState] = [:]
  @State private var availableModelIds: Set<String> = []
  @State private var activeDownloadIds: Set<String> = []
  @State private var statusMessage = ""

  init(
    modelManager: VoiceWhisperModelManager = VoiceWhisperModelManager(),
    downloadService: VoiceWhisperModelDownloadService? = nil
  ) {
    self.modelManager = modelManager
    self.downloadService = downloadService ?? VoiceWhisperModelDownloadService(manager: modelManager)
  }

  var body: some View {
    Form {
      Section("Whisper Model") {
        ForEach(rows) { row in
          Button {
            handle(row)
          } label: {
            HStack(alignment: .center, spacing: 12) {
              Image(systemName: "waveform")
                .foregroundColor(.accentColor)
                .frame(width: 28)
              VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                  .foregroundColor(.primary)
                Text(row.detail)
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              Spacer(minLength: 12)
              Label {
                Text(row.action.title)
              } icon: {
                Image(systemName: row.action.systemImageName)
              }
              .font(.caption.weight(.semibold))
              .foregroundColor(actionColor(row.action))
              .labelStyle(.titleAndIcon)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(!row.action.isEnabled)
        }
      }
      Section {
        Text(VoiceWhisperModelSettingsPresenter.mirrorNote)
          .font(.caption)
          .foregroundColor(.secondary)
        if !statusMessage.isEmpty {
          Text(statusMessage)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle("ASR Model")
    .onAppear(perform: refreshModelState)
  }

  private var rows: [VoiceWhisperModelRowPresentation] {
    VoiceWhisperModelSettingsPresenter.rows(
      selectedModelId: store.voiceSettings.asrModelId,
      downloadState: { downloadStates[$0.id] ?? modelManager.downloadState(for: $0) },
      isAvailable: { availableModelIds.contains($0.id) || $0.bundled },
      activeDownloadIds: activeDownloadIds
    )
  }

  private func handle(_ row: VoiceWhisperModelRowPresentation) {
    switch row.action {
    case .use:
      select(row.model)
    case .download, .retry:
      Task { await download(row.model) }
    case .current, .waiting:
      break
    }
  }

  private func select(_ model: VoiceWhisperModelProfile) {
    store.updateVoiceSettings { $0.asrModelId = model.id }
    statusMessage = "\(model.displayName) selected"
    refreshModelState()
  }

  @MainActor
  private func download(_ model: VoiceWhisperModelProfile) async {
    guard !activeDownloadIds.contains(model.id) else { return }
    activeDownloadIds.insert(model.id)
    statusMessage = "Downloading \(model.displayName)"
    refreshModelState()
    defer {
      activeDownloadIds.remove(model.id)
      refreshModelState()
    }
    do {
      _ = try await downloadService.start(model)
      store.updateVoiceSettings { $0.asrModelId = model.id }
      statusMessage = "\(model.displayName) downloaded and selected"
    } catch {
      statusMessage = "Model download failed. Tap to retry."
    }
  }

  private func refreshModelState() {
    var nextStates: [String: VoiceWhisperModelDownloadState] = [:]
    var nextAvailable = Set<String>()
    for model in VoiceWhisperModelCatalog.models {
      nextStates[model.id] = modelManager.downloadState(for: model)
      if modelManager.isAvailable(model) {
        nextAvailable.insert(model.id)
      }
    }
    downloadStates = nextStates
    availableModelIds = nextAvailable
  }

  private func actionColor(_ action: VoiceWhisperModelRowAction) -> Color {
    switch action {
    case .current:
      return .green
    case .retry:
      return .orange
    case .waiting:
      return .secondary
    case .use, .download:
      return .accentColor
    }
  }
}
