import SwiftUI

struct VoiceWhisperModelSettingsView: View {
  @EnvironmentObject private var store: SignalASIStore
  private let modelManager: VoiceWhisperModelManager
  private let downloadService: VoiceWhisperModelDownloadService
  private let benchmarkManager: VoiceWhisperBenchmarkManager
  private let benchmarkCoordinator: VoiceWhisperBenchmarkRunCoordinator

  @State private var downloadStates: [String: VoiceWhisperModelDownloadState] = [:]
  @State private var availableModelIds: Set<String> = []
  @State private var activeDownloadIds: Set<String> = []
  @State private var benchmarkRecords: [String: VoiceWhisperBenchmarkRecord] = [:]
  @State private var latestBenchmarkRecords: [String: VoiceWhisperBenchmarkRecord] = [:]
  @State private var benchmarkProgress: [String: VoiceWhisperBenchmarkProgress] = [:]
  @State private var activeBenchmarkIds: Set<String> = []
  @State private var benchmarkDetails: VoiceWhisperBenchmarkDetailsPresentation?
  @State private var statusMessage = ""

  init(
    modelManager: VoiceWhisperModelManager = VoiceWhisperModelManager(),
    downloadService: VoiceWhisperModelDownloadService? = nil,
    benchmarkManager: VoiceWhisperBenchmarkManager? = nil,
    benchmarkCoordinator: VoiceWhisperBenchmarkRunCoordinator? = nil
  ) {
    let resolvedBenchmarkManager = benchmarkManager ?? VoiceWhisperBenchmarkManager()
    self.modelManager = modelManager
    self.downloadService = downloadService ?? VoiceWhisperModelDownloadService(manager: modelManager)
    self.benchmarkManager = resolvedBenchmarkManager
    self.benchmarkCoordinator = benchmarkCoordinator ?? VoiceWhisperBenchmarkDefaultFactory.makeCoordinator(
      modelManager: modelManager,
      benchmarkManager: resolvedBenchmarkManager
    )
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
          .swipeActions(edge: .trailing) {
            if row.removable {
              Button(role: .destructive) {
                remove(row.model)
              } label: {
                Label("Remove", systemImage: "trash")
              }
            }
          }
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
    .alert(item: $benchmarkDetails) { details in
      Alert(
        title: Text(details.title),
        message: Text(details.message),
        dismissButton: .default(Text("Done"))
      )
    }
  }

  private var rows: [VoiceWhisperModelRowPresentation] {
    VoiceWhisperModelSettingsPresenter.rows(
      selectedModelId: store.voiceSettings.asrModelId,
      downloadState: { downloadStates[$0.id] ?? modelManager.downloadState(for: $0) },
      isAvailable: { availableModelIds.contains($0.id) || $0.bundled },
      benchmarkRecord: { benchmarkRecords[$0.id] },
      latestBenchmarkRecord: { latestBenchmarkRecords[$0.id] },
      benchmarkProgress: { benchmarkProgress[$0.id] },
      activeDownloadIds: activeDownloadIds
    )
  }

  private func handle(_ row: VoiceWhisperModelRowPresentation) {
    switch row.action {
    case .use:
      select(row.model)
    case .useAndTest:
      select(row.model)
      Task { await benchmark(row.model, force: false) }
    case .download, .retry:
      Task { await download(row.model) }
    case .current:
      if let record = row.benchmarkRecord {
        benchmarkDetails = VoiceWhisperBenchmarkDetailsPresenter.presentation(model: row.model, record: record)
      }
    case .waiting:
      break
    }
  }

  private func remove(_ model: VoiceWhisperModelProfile) {
    do {
      _ = try modelManager.delete(model, active: modelManager.isLoaded(model.id))
      try? benchmarkManager.remove(profile: model)
      statusMessage = "\(model.displayName) removed"
    } catch {
      statusMessage = "Model remove failed."
    }
    refreshModelState()
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

  @MainActor
  private func benchmark(_ model: VoiceWhisperModelProfile, force: Bool) async {
    guard !activeBenchmarkIds.contains(model.id) else { return }
    activeBenchmarkIds.insert(model.id)
    benchmarkProgress[model.id] = VoiceWhisperBenchmarkProgress(
      stage: .verifying,
      completedSteps: 0,
      totalSteps: 1
    )
    statusMessage = "Benchmarking \(model.displayName)"
    refreshModelState()
    defer {
      activeBenchmarkIds.remove(model.id)
      benchmarkProgress.removeValue(forKey: model.id)
      refreshModelState()
    }
    do {
      let record = try await benchmarkCoordinator.benchmark(profile: model, force: force) { progress in
        Task { @MainActor in
          benchmarkProgress[model.id] = progress
        }
      }
      benchmarkRecords[model.id] = record
      latestBenchmarkRecords.removeValue(forKey: model.id)
      statusMessage = "\(model.displayName) certification completed"
    } catch {
      statusMessage = "Benchmark could not finish: \(error.localizedDescription)"
    }
  }

  private func refreshModelState() {
    var nextStates: [String: VoiceWhisperModelDownloadState] = [:]
    var nextAvailable = Set<String>()
    var nextBenchmarkRecords: [String: VoiceWhisperBenchmarkRecord] = [:]
    var nextLatestRecords: [String: VoiceWhisperBenchmarkRecord] = [:]
    for model in VoiceWhisperModelCatalog.models {
      nextStates[model.id] = modelManager.downloadState(for: model)
      if modelManager.isAvailable(model) {
        nextAvailable.insert(model.id)
        if let record = benchmarkManager.current(profile: model) {
          nextBenchmarkRecords[model.id] = record
        } else if let latest = benchmarkManager.latest(profile: model) {
          nextLatestRecords[model.id] = latest
        }
      }
    }
    downloadStates = nextStates
    availableModelIds = nextAvailable
    benchmarkRecords = nextBenchmarkRecords
    latestBenchmarkRecords = nextLatestRecords
  }

  private func actionColor(_ action: VoiceWhisperModelRowAction) -> Color {
    switch action {
    case .current:
      return .green
    case .retry:
      return .orange
    case .waiting:
      return .secondary
    case .use, .useAndTest, .download:
      return .accentColor
    }
  }
}
