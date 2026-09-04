import SwiftUI

struct VoiceWhisperModelSettingsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
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
  @State private var pendingMeteredModel: VoiceWhisperModelProfile?
  @State private var showingMeteredDownloadConfirmation = false

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
      Section(header: Text(t("voice_asr_model_section", "Whisper Model"))) {
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
                Text(row.localizedDetail(t))
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              Spacer(minLength: 12)
              Label {
                Text(row.action.localizedTitle(t))
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
                Label(t("voice_asr_model_remove", "Remove model"), systemImage: "trash")
              }
            }
          }
        }
      }
      Section {
        Text(t(VoiceWhisperModelSettingsPresenter.mirrorNoteKey, VoiceWhisperModelSettingsPresenter.mirrorNote))
          .font(.caption)
          .foregroundColor(.secondary)
        if !statusMessage.isEmpty {
          Text(statusMessage)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle(t("ASR Model", "ASR Model"))
    .onAppear(perform: refreshModelState)
    .alert(item: $benchmarkDetails) { details in
      Alert(
        title: Text(details.title),
        message: Text(details.message),
        dismissButton: .default(Text(t("Done", "Done")))
      )
    }
    .alert(
      t("voice_asr_metered_download_title", "Download model over metered network?"),
      isPresented: $showingMeteredDownloadConfirmation
    ) {
      Button(t("voice_asr_metered_download_confirm", "Download")) {
        guard let model = pendingMeteredModel else { return }
        pendingMeteredModel = nil
        Task { await download(model, meteredConfirmed: true) }
      }
      Button(t("common_cancel", "Cancel"), role: .cancel) {
        pendingMeteredModel = nil
      }
    } message: {
      Text(String(format: t(
        "voice_asr_metered_download_message",
        "%@ is a large model. Downloading it over cellular or a metered connection may use significant data."
      ), pendingMeteredModel?.displayName ?? "Whisper"))
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
        benchmarkDetails = VoiceWhisperBenchmarkDetailsPresenter.presentation(model: row.model, record: record, localized: t)
      }
    case .unavailable:
      statusMessage = t(
        "voice_asr_model_unsupported",
        "Unsupported on this iPhone"
      )
    case .waiting:
      break
    }
  }

  private func remove(_ model: VoiceWhisperModelProfile) {
    do {
      _ = try modelManager.delete(model, active: modelManager.isLoaded(model.id))
      try? benchmarkManager.remove(profile: model)
      statusMessage = String(format: t("voice_asr_model_removed_status", "%@ removed"), model.displayName)
    } catch {
      statusMessage = t("voice_asr_model_remove_failed", "Model remove failed.")
    }
    refreshModelState()
  }

  private func select(_ model: VoiceWhisperModelProfile) {
    store.updateVoiceSettings {
      $0.asrModelId = model.id
      $0.asrRuntimeMode = .manual
    }
    statusMessage = String(format: t("voice_asr_model_selected_status", "%@ selected"), model.displayName)
    refreshModelState()
  }

  @MainActor
  private func download(
    _ model: VoiceWhisperModelProfile,
    meteredConfirmed: Bool = false
  ) async {
    guard !activeDownloadIds.contains(model.id) else { return }
    activeDownloadIds.insert(model.id)
    statusMessage = String(format: t("voice_asr_model_download_started", "Downloading %@"), model.displayName)
    refreshModelState()
    defer {
      activeDownloadIds.remove(model.id)
      refreshModelState()
    }
    do {
      _ = try await downloadService.start(model, meteredConfirmed: meteredConfirmed)
      store.updateVoiceSettings {
        $0.asrModelId = model.id
        $0.asrRuntimeMode = .manual
      }
      statusMessage = String(format: t("voice_asr_model_ready", "%@ downloaded and selected"), model.displayName)
    } catch let error as VoiceWhisperModelManagerError {
      if case .meteredDownloadConfirmationRequired = error {
        pendingMeteredModel = model
        showingMeteredDownloadConfirmation = true
        statusMessage = t(
          "voice_asr_metered_download_required",
          "Confirm the metered-network download to continue."
        )
      } else {
        statusMessage = t("voice_asr_model_download_failed", "Model download failed. Tap to retry.")
      }
    } catch {
      statusMessage = t("voice_asr_model_download_failed", "Model download failed. Tap to retry.")
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
    statusMessage = String(format: t("voice_asr_model_benchmarking_named", "Benchmarking %@"), model.displayName)
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
      statusMessage = String(format: t("voice_asr_model_benchmark_complete", "%@ certification completed"), model.displayName)
    } catch {
      statusMessage = String(format: t("voice_asr_model_benchmark_failed", "Benchmark could not finish: %@"), error.localizedDescription)
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
    case .unavailable:
      return .orange
    case .retry:
      return .orange
    case .waiting:
      return .secondary
    case .use, .useAndTest, .download:
      return .accentColor
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
