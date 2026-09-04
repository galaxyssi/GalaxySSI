import AVFoundation
import CoreLocation
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

struct GalaxySSILocalModelLabView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var selectedProfile = LocalModelRuntimeSettings.selectedProfile()
  @State private var contextTokens = LocalModelRuntimeSettings.contextTokens()
  @State private var deviceSnapshot = LocalModelDeviceSnapshotDetector.capture()
  @State private var acceleratorSnapshot = LocalModelAcceleratorDetector.detect()
  @State private var inferenceSnapshot = LocalModelInferenceRuntime.shared.snapshot()
  @State private var showingContextChoices = false
  @State private var cameraStatus = ""
  @State private var microphoneStatus = ""
  @State private var locationStatus = ""
  @State private var notificationStatus = ""
  @State private var statusMessage = ""
  @State private var catalogRevision = 0
  @State private var showingModelImporter = false
  @State private var profileToDelete: LocalModelRuntimeProfile?
  @State private var showingDeleteConfirmation = false
  @State private var artifactToStart: LocalModelHubArtifact?
  @State private var showingMeteredDownloadConfirmation = false
  @StateObject private var downloads = LocalModelArtifactDownloadCoordinator.shared

  private let whisperModelManager = VoiceWhisperModelManager()
  private let localModelStorage = LocalModelRuntimeStorage()

  private var localModelProfiles: [LocalModelRuntimeProfile] {
    _ = catalogRevision
    return LocalModelRuntimeCatalog.profiles()
  }

  private var estimate: LocalModelRuntimeEstimate {
    LocalModelRuntimeEstimator.estimate(
      LocalModelRuntimeRequest(
        profile: selectedProfile,
        requestedContextTokens: contextTokens,
        modelFileBytes: selectedModelStorage?.installed == true
          ? selectedProfile.expectedModelFileBytes
          : (selectedProfile.downloadable ? 0 : selectedProfile.expectedModelFileBytes),
        modelFilePresent: selectedProfile.downloadable
          ? selectedModelStorage?.installed == true
          : true,
        requireModelFile: selectedProfile.downloadable
      ),
      device: deviceSnapshot
    )
  }

  private var runtimeAvailable: Bool {
    inferenceSnapshot.available
  }

  private var localModelConnectorCount: Int {
    store.contacts.filter { contact in
      !contact.deleted &&
        contact.deliveryMode.isGalaxySSILinkFamily &&
        (contact.agentKind.lowercased().contains("model") ||
          contact.id.lowercased().contains("local-model") ||
          contact.displayName.lowercased().contains("local model"))
    }.count
  }

  private var installedWhisperCount: Int {
    VoiceWhisperModelCatalog.models.filter { model in
      model.bundled || whisperModelManager.isAvailable(model)
    }.count
  }

  private var installedLocalModelCount: Int {
    localModelProfiles.filter { localModelStorage.inspect($0).installed }.count
  }

  private var selectedModelStorage: LocalModelStorageSnapshot? {
    guard selectedProfile.downloadable else { return nil }
    return localModelStorage.inspect(selectedProfile)
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.local_model.title", "Local Model"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSILocalModelLabHeroView(
            title: t("galaxyssi.local_model.status_title", "Local Model Status"),
            subtitle: preflightDetail,
            systemImage: "cpu",
            tint: readinessTint,
            badge: runtimeAvailable ? readinessLabel(estimate.readiness) : t("galaxyssi.local_model.preflight_blocked", "Blocked")
          )
          if !statusMessage.isEmpty {
            GalaxySSILocalModelLabStatusRow(
              title: t("galaxyssi.local_model.status", "Status"),
              subtitle: statusMessage,
              systemImage: "checkmark.circle",
              tint: .galaxySSIAccent,
              badge: t("galaxyssi.status.ready", "Ready")
            )
          }
          manageSection
          preflightSection
          accelerationSection
          permissionsSection
          privacyStorageSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .confirmationDialog(
      t("galaxyssi.local_model.context_window", "Context Window"),
      isPresented: $showingContextChoices,
      titleVisibility: .visible
    ) {
      ForEach(contextChoices, id: \.self) { tokens in
        Button(contextLabel(tokens)) {
          setContextTokens(tokens)
        }
      }
      Button(t("galaxyssi.common.cancel", "Cancel"), role: .cancel) {}
    }
    .confirmationDialog(
      t("galaxyssi.local_model.delete_title", "Delete downloaded model?"),
      isPresented: $showingDeleteConfirmation,
      titleVisibility: .visible,
      presenting: profileToDelete
    ) { profile in
      Button(t("galaxyssi.local_model.delete_action", "Delete"), role: .destructive) {
        deleteLocalModel(profile)
        profileToDelete = nil
      }
      Button(t("galaxyssi.common.cancel", "Cancel"), role: .cancel) {
        profileToDelete = nil
      }
    } message: { profile in
      Text(
        String(
          format: t("galaxyssi.local_model.delete_message", "Remove %@ from this iPhone?"),
          profile.displayName
        )
      )
    }
    .alert(
      t("galaxyssi.local_model.metered_download_title", "Download over cellular data?"),
      isPresented: $showingMeteredDownloadConfirmation
    ) {
      Button(t("galaxyssi.local_model.metered_download_confirm", "Download")) {
        guard let artifact = artifactToStart else { return }
        startModelDownload(artifact)
        artifactToStart = nil
      }
      Button(t("galaxyssi.common.cancel", "Cancel"), role: .cancel) {
        artifactToStart = nil
      }
    } message: {
      Text(String(format: t(
        "galaxyssi.local_model.metered_download_message",
        "This model is %@. Downloading it over cellular or a metered connection may use significant data."
      ), formatBytes(artifactToStart?.sizeBytes ?? 0)))
    }
    .onAppear(perform: refreshSnapshots)
    .onChange(of: downloads.states) { _ in
      refreshSnapshots()
    }
    .fileImporter(
      isPresented: $showingModelImporter,
      allowedContentTypes: [.data, .item],
      allowsMultipleSelection: false,
      onCompletion: importModelFile
    )
  }

  private var manageSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSILocalModelLabSectionTitle(title: t("galaxyssi.local_model.section_manage", "Model Management"))
      GalaxySSILocalModelLabNavigationRow(
        title: t("galaxyssi.local_model.search_title", "Search models"),
        subtitle: t("galaxyssi.local_model.search_subtitle", "Find downloadable GGUF models across trusted model hubs"),
        systemImage: "magnifyingglass",
        tint: .galaxySSIInsightText,
        badge: t("galaxyssi.local_model.search_action", "Search")
      ) {
        GalaxySSILocalModelSearchView()
      }
      GalaxySSILocalModelLabActionRow(
        title: t("galaxyssi.local_model.import_title", "Import verified model"),
        subtitle: t(
          "galaxyssi.local_model.import_subtitle",
          "Import a trusted GGUF file from Files"
        ),
        systemImage: "square.and.arrow.down",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.local_model.import_action", "Files")
      ) {
        showingModelImporter = true
      }
      ForEach(localModelProfiles) { profile in
        let artifact = LocalModelRuntimeCatalog.artifact(for: profile)
        let downloadState = artifact.map { downloads.state(for: $0) } ?? .notInstalled
        let installed = artifact != nil
          ? downloadState == .ready
          : localModelStorage.inspect(profile).installed
        if !profile.supportsIOSRuntime {
          GalaxySSILocalModelLabStatusRow(
            title: profile.displayName,
            subtitle: profileSubtitle(profile),
            systemImage: "xmark.octagon",
            tint: .orange,
            badge: t("galaxyssi.local_model.unsupported", "Unsupported")
          )
          .contextMenu {
            if profile.sourceTrust == .signedDeployment {
              Button(role: .destructive) {
                deleteLocalModel(profile)
              } label: {
                Label(
                  t("galaxyssi.local_model.remove_catalog_entry", "Remove catalog entry"),
                  systemImage: "trash"
                )
              }
            }
          }
        } else if installed {
          GalaxySSILocalModelLabToggleRow(
            title: profile.displayName,
            subtitle: profileSubtitle(profile),
            systemImage: "cpu",
            tint: profile.id == selectedProfile.id ? .galaxySSIAccent : .blue,
            badge: modelDownloadBadge(
              profile: profile,
              artifact: artifact,
              state: downloadState,
              installed: installed
            ),
            isOn: LocalModelRuntimeSettings.isProfileEnabled(profile),
            onToggle: { setProfileEnabled(profile, enabled: $0) }
          )
          .contextMenu {
            Button(role: .destructive) {
              profileToDelete = profile
              showingDeleteConfirmation = true
            } label: {
              Label(
                t("galaxyssi.local_model.delete_action", "Delete"),
                systemImage: "trash"
              )
            }
          }
        } else {
          GalaxySSILocalModelLabActionRow(
            title: profile.displayName,
            subtitle: profileSubtitle(profile),
            systemImage: "cpu",
            tint: profile.id == selectedProfile.id ? .galaxySSIAccent : .blue,
            badge: modelDownloadBadge(
              profile: profile,
              artifact: artifact,
              state: downloadState,
              installed: installed
            )
          ) {
            handleModelAction(profile: profile, artifact: artifact, state: downloadState)
          }
        }
      }
      GalaxySSILocalModelLabActionRow(
        title: t("galaxyssi.local_model.context_window", "Context Window"),
        subtitle: t("galaxyssi.local_model.context_window_subtitle", "Larger context increases KV cache usage"),
        systemImage: "text.alignleft",
        tint: .purple,
        badge: contextLabel(contextTokens)
      ) {
        showingContextChoices = true
      }
      GalaxySSILocalModelLabNavigationRow(
        title: t("galaxyssi.local_model.asr_model", "Whisper Model"),
        subtitle: VoiceWhisperModelCatalog.model(store.voiceSettings.asrModelId).displayName,
        systemImage: "waveform",
        tint: .teal,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        VoiceWhisperModelSettingsView()
      }
    }
  }

  private func modelDownloadBadge(
    profile: LocalModelRuntimeProfile,
    artifact: LocalModelHubArtifact?,
    state: LocalModelArtifactInstallState,
    installed: Bool
  ) -> String {
    guard artifact != nil else {
      return profile.id == selectedProfile.id
        ? LocalModelRuntimeSettings.isProfileEnabled(profile)
          ? t("galaxyssi.local_model.enabled", "Enabled")
          : t("galaxyssi.local_model.selected", "Current")
        : installed
          ? t("galaxyssi.local_model.download_ready", "Ready")
          : t("galaxyssi.local_model.use_action", "Use")
    }
    switch state {
    case .downloading:
      return t("galaxyssi.local_model.download_active", "Downloading")
    case .verifying:
      return t("galaxyssi.local_model.download_verifying", "Verifying")
    case .installing:
      return t("galaxyssi.local_model.download_installing", "Installing")
    case .paused:
      return t("galaxyssi.local_model.download_resume", "Resume")
    case .notInstalled:
      return t("galaxyssi.local_model.download_action", "Download")
    case .failed:
      return t("galaxyssi.common.retry", "Retry")
    case .ready:
      return LocalModelRuntimeSettings.isProfileEnabled(profile)
        ? t("galaxyssi.local_model.enabled", "Enabled")
        : t("galaxyssi.local_model.download_ready", "Ready")
    }
  }

  private var preflightSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSILocalModelLabSectionTitle(title: t("galaxyssi.local_model.preflight_section", "Runtime Preflight"))
      GalaxySSILocalModelLabStatusRow(
        title: t("galaxyssi.local_model.file_estimate", "Estimated Model File"),
        subtitle: selectedProfile.quantizationLabel,
        systemImage: "doc",
        tint: .blue,
        badge: formatBytes(estimate.modelFileBytes)
      )
      GalaxySSILocalModelLabStatusRow(
        title: t("galaxyssi.local_model.native_runtime", "Native Inference Runtime"),
        subtitle: runtimeAvailable
          ? String(
              format: t("galaxyssi.local_model.native_runtime_ready_detail", "%@ backend is available"),
              inferenceSnapshot.backend
            ) + "\n\(inferenceSnapshot.executionIsolation) / \(inferenceSnapshot.backendScope)"
          : t("galaxyssi.local_model.native_runtime_unavailable_detail", "A bundled GGUF backend is required before local inference can start"),
        systemImage: "bolt.horizontal.circle",
        tint: runtimeAvailable ? .galaxySSIAccent : .orange,
        badge: runtimeAvailable
          ? t("galaxyssi.local_model.runtime_ready", "Ready")
          : t("galaxyssi.local_model.runtime_unavailable", "Unavailable")
      )
      GalaxySSILocalModelLabStatusRow(
        title: t("galaxyssi.local_model.background_runtime", "Background Inference"),
        subtitle: inferenceSnapshot.backgroundReady
          ? t("galaxyssi.local_model.background_runtime_ready_detail", "The selected model can run when no interactive inference is active")
          : t("galaxyssi.local_model.background_runtime_deferred_detail", "Background inference is deferred while the runtime is unavailable or foreground work is active"),
        systemImage: "moon.zzz",
        tint: inferenceSnapshot.backgroundReady ? .galaxySSIAccent : .orange,
        badge: inferenceSnapshot.backgroundReady
          ? t("galaxyssi.local_model.background_runtime_ready", "Eligible")
          : t("galaxyssi.local_model.background_runtime_deferred", "Deferred")
      )
      GalaxySSILocalModelLabStatusRow(
        title: t("galaxyssi.local_model.kv_cache", "KV cache"),
        subtitle: String(
          format: t("galaxyssi.local_model.kv_cache_subtitle", "Estimated at %d tokens context"),
          estimate.recommendedContextTokens
        ),
        systemImage: "memorychip",
        tint: .purple,
        badge: formatBytes(estimate.kvCacheBytes)
      )
      GalaxySSILocalModelLabStatusRow(
        title: t("galaxyssi.local_model.safe_memory", "Working Set / Safe Budget"),
        subtitle: t("galaxyssi.local_model.safe_memory_subtitle", "Reserve memory for iOS and foreground apps"),
        systemImage: "memorychip",
        tint: readinessTint,
        badge: String(
          format: t("galaxyssi.local_model.memory_required_value", "%@ / %@"),
          formatBytes(estimate.totalRequiredBytes),
          formatBytes(estimate.safeMemoryBudgetBytes)
        )
      )
      GalaxySSILocalModelLabStatusRow(
        title: t("galaxyssi.local_model.threads", "Recommended Threads"),
        subtitle: String(
          format: t("galaxyssi.local_model.threads_subtitle", "Detected %d CPU cores"),
          estimate.device.cpuCoreCount
        ),
        systemImage: "cpu",
        tint: .blue,
        badge: "\(estimate.recommendedThreads)"
      )
      GalaxySSILocalModelLabStatusRow(
        title: t("galaxyssi.local_model.temperature", "Temperature"),
        subtitle: thermalDetail,
        systemImage: "thermometer",
        tint: thermalTint,
        badge: thermalValue
      )
      GalaxySSILocalModelLabStatusRow(
        title: t("galaxyssi.local_model.battery", "Battery"),
        subtitle: estimate.device.charging
          ? t("galaxyssi.local_model.battery_charging", "Charging; longer inference is available")
          : t("galaxyssi.local_model.battery_not_charging", "Not charging; battery protection applies"),
        systemImage: "battery.75",
        tint: batteryTint,
        badge: estimate.device.batteryPercent.map { "\($0)%" } ?? t("galaxyssi.status.unknown", "Unknown")
      )
      GalaxySSILocalModelLabActionRow(
        title: t("galaxyssi.local_model.refresh_preflight", "Refresh Preflight"),
        subtitle: t("galaxyssi.local_model.refresh_preflight_subtitle", "Recheck memory, CPU, temperature, and battery"),
        systemImage: "arrow.clockwise",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.refresh", "Refresh")
      ) {
        refreshSnapshots()
      }
    }
  }

  private var accelerationSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSILocalModelLabSectionTitle(title: t("galaxyssi.local_model.acceleration_section", "Acceleration Backends"))
      ForEach(acceleratorSnapshot.capabilities) { capability in
        GalaxySSILocalModelLabStatusRow(
          title: acceleratorTitle(capability.kind),
          subtitle: "\(capability.hardwareEvidence)\n\(capability.runtimeEvidence)",
          systemImage: acceleratorIcon(capability.kind),
          tint: acceleratorTint(capability.state),
          badge: acceleratorStatus(capability.state)
        )
      }
    }
  }

  private var permissionsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSILocalModelLabSectionTitle(title: t("galaxyssi.local_model.section_permissions", "Device Permissions"))
      GalaxySSILocalModelLabNavigationRow(
        title: t("galaxyssi.local_model.on_device_permissions", "On-device Agent Permissions"),
        subtitle: t("galaxyssi.local_model.on_device_permissions_subtitle", "Review microphone, camera, notifications, and device-side execution"),
        systemImage: "checkmark.shield",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.view", "View")
      ) {
        OnDeviceAgentPermissionsView()
      }
      GalaxySSILocalModelLabActionRow(
        title: t("galaxyssi.on_device_agent.microphone", "Microphone"),
        subtitle: t("galaxyssi.on_device_agent.microphone_subtitle", "Voice input and hold-to-talk"),
        systemImage: "mic",
        tint: .galaxySSIAccent,
        badge: microphoneStatus.ifBlank(t("galaxyssi.permission.needs_setup", "Needs setup"))
      ) {
        requestMicrophone()
      }
      GalaxySSILocalModelLabActionRow(
        title: t("galaxyssi.on_device_agent.camera", "Camera"),
        subtitle: t("galaxyssi.on_device_agent.camera_subtitle", "QR scanning and visual recognition"),
        systemImage: "camera",
        tint: .teal,
        badge: cameraStatus.ifBlank(t("galaxyssi.permission.needs_setup", "Needs setup"))
      ) {
        requestCamera()
      }
      GalaxySSILocalModelLabActionRow(
        title: t("galaxyssi.local_model.location", "Location"),
        subtitle: t("galaxyssi.local_model.location_subtitle", "Local scenarios can keep location permission disabled"),
        systemImage: "location",
        tint: .purple,
        badge: locationStatus.ifBlank(t("galaxyssi.permission.needs_setup", "Needs setup"))
      ) {
        openAppSettings()
      }
      GalaxySSILocalModelLabActionRow(
        title: t("galaxyssi.local_model.notification_permission", "Notifications"),
        subtitle: t("galaxyssi.local_model.notification_permission_subtitle", "Background model and Agent prompts"),
        systemImage: "bell.badge",
        tint: .orange,
        badge: notificationStatus.ifBlank(t("galaxyssi.permission.needs_setup", "Needs setup"))
      ) {
        requestNotifications()
      }
    }
  }

  private var privacyStorageSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSILocalModelLabSectionTitle(title: t("galaxyssi.local_model.section_privacy_storage", "Privacy & Storage"))
      GalaxySSILocalModelLabStatusRow(
        title: t("galaxyssi.local_model.offline_mode", "Offline Mode"),
        subtitle: t("galaxyssi.local_model.offline_mode_subtitle", "Keep working without network access"),
        systemImage: "lock.shield",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.status.enabled", "Enabled")
      )
      GalaxySSILocalModelLabStatusRow(
        title: t("galaxyssi.local_model.storage_usage", "Storage Usage"),
        subtitle: String(
          format: t("galaxyssi.local_model.storage_usage_subtitle", "%d Whisper models / %d downloaded local models / %d Desktop local model connectors"),
          installedWhisperCount,
          installedLocalModelCount,
          localModelConnectorCount
        ),
        systemImage: "internaldrive",
        tint: .blue,
        badge: formatBytes(selectedProfile.expectedModelFileBytes)
      )
      GalaxySSILocalModelLabStatusRow(
        title: t("galaxyssi.local_model.download_source", "Local Model Download"),
        subtitle: t(VoiceWhisperModelSettingsPresenter.mirrorNoteKey, VoiceWhisperModelSettingsPresenter.mirrorNote),
        systemImage: "arrow.down.circle",
        tint: .teal,
        badge: t("galaxyssi.local_model.hub_source", "Hugging Face model")
      )
    }
  }

  private var preflightDetail: String {
    guard runtimeAvailable else {
      return t("galaxyssi.local_model.runtime_unavailable", "Local inference runtime is unavailable in this build")
    }
    guard !estimate.issues.isEmpty else {
      return t("galaxyssi.local_model.preflight_ready_detail", "The estimated workload fits the current safe device budget")
    }
    return estimate.issues
      .sorted { $0.rawValue < $1.rawValue }
      .map(issueLabel)
      .joined(separator: "\n")
  }

  private var readinessTint: Color {
    guard runtimeAvailable else { return .orange }
    switch estimate.readiness {
    case .ready:
      return .galaxySSIAccent
    case .caution:
      return .orange
    case .blocked:
      return .red
    }
  }

  private var thermalValue: String {
    switch estimate.device.thermalStatus ?? 0 {
    case 0:
      return t("galaxyssi.local_model.thermal_none", "Nominal")
    case 1:
      return t("galaxyssi.local_model.thermal_light", "Light")
    case 2:
      return t("galaxyssi.local_model.thermal_moderate", "Moderate")
    default:
      return t("galaxyssi.local_model.thermal_severe", "Severe")
    }
  }

  private var thermalDetail: String {
    if let celsius = estimate.device.batteryTemperatureCelsius {
      return String(format: "%.1f C", celsius)
    }
    return t("galaxyssi.local_model.thermal_unknown", "Thermal state is reported by iOS")
  }

  private var thermalTint: Color {
    let status = estimate.device.thermalStatus ?? 0
    if status >= 3 { return .red }
    if status >= 2 { return .orange }
    return .galaxySSIAccent
  }

  private var batteryTint: Color {
    guard !estimate.device.charging, let percent = estimate.device.batteryPercent else {
      return .galaxySSIAccent
    }
    if percent < 10 { return .red }
    if percent < 20 { return .orange }
    return .galaxySSIAccent
  }

  private var contextChoices: [Int] {
    [2_048, 4_096, 8_192, 16_384, 32_768]
      .filter { $0 <= selectedProfile.maximumContextTokens }
  }

  private func handleModelAction(
    profile: LocalModelRuntimeProfile,
    artifact: LocalModelHubArtifact?,
    state: LocalModelArtifactInstallState
  ) {
    guard let artifact else {
      setProfileEnabled(profile, enabled: true)
      return
    }
    switch state {
    case .notInstalled, .failed:
      beginModelDownload(artifact)
    case .paused:
      beginModelDownload(artifact)
    case .downloading, .verifying, .installing:
      downloads.cancel(artifact)
      statusMessage = t("galaxyssi.local_model.download_cancelled", "Download cancelled")
    case .ready:
      setProfileEnabled(profile, enabled: true)
    }
  }

  private func beginModelDownload(_ artifact: LocalModelHubArtifact) {
    if downloads.requiresMeteredNetworkConfirmation() {
      artifactToStart = artifact
      showingMeteredDownloadConfirmation = true
    } else {
      startModelDownload(artifact)
    }
  }

  private func startModelDownload(_ artifact: LocalModelHubArtifact) {
    let previousState = downloads.state(for: artifact)
    downloads.start(artifact)
    statusMessage = downloads.state(for: artifact) == .failed
      ? downloads.error(for: artifact) ?? t("galaxyssi.local_model.download_failed", "Download failed")
      : previousState == .paused
      ? t("galaxyssi.local_model.download_resumed", "Download resumed")
      : t("galaxyssi.local_model.download_started", "Download started")
  }

  private func setProfileEnabled(_ profile: LocalModelRuntimeProfile, enabled: Bool) {
    guard enabled != LocalModelRuntimeSettings.isProfileEnabled(profile) else { return }
    LocalModelRuntimeSettings.setProfileEnabled(profile, enabled: enabled)
    if !enabled {
      LocalModelInferenceRuntime.shared.unloadIfSelected(profileId: profile.id)
    }
    if enabled {
      statusMessage = String(
        format: t("galaxyssi.local_model.enabled_profile", "%@ enabled"),
        profile.displayName
      )
    } else {
      LocalModelInferenceRuntime.shared.unloadIfSelected(profileId: profile.id)
      statusMessage = String(
        format: t("galaxyssi.local_model.disabled_profile", "%@ disabled"),
        profile.displayName
      )
    }
    refreshSnapshots()
  }

  private func deleteLocalModel(_ profile: LocalModelRuntimeProfile) {
    if let artifact = LocalModelRuntimeCatalog.artifact(for: profile) {
      downloads.delete(artifact)
    } else {
      LocalModelRuntimeSettings.setProfileEnabled(profile, enabled: false)
      LocalModelInferenceRuntime.shared.unloadIfSelected(profileId: profile.id)
      try? localModelStorage.delete(profile)
      LocalModelRuntimeCatalog.removeProfile(profile)
    }
    statusMessage = String(
      format: t("galaxyssi.local_model.delete_completed", "%@ deleted"),
      profile.displayName
    )
    refreshSnapshots()
  }

  private func setContextTokens(_ tokens: Int) {
    contextTokens = tokens
    LocalModelRuntimeSettings.setContextTokens(tokens)
    statusMessage = String(format: t("galaxyssi.local_model.context_selected", "%@ selected"), contextLabel(tokens))
    refreshSnapshots()
  }

  private func refreshSnapshots() {
    selectedProfile = LocalModelRuntimeSettings.selectedProfile()
    contextTokens = min(LocalModelRuntimeSettings.contextTokens(), selectedProfile.maximumContextTokens)
    deviceSnapshot = LocalModelDeviceSnapshotDetector.capture()
    acceleratorSnapshot = LocalModelAcceleratorDetector.detect()
    inferenceSnapshot = LocalModelInferenceRuntime.shared.snapshot()
    catalogRevision += 1
    refreshPermissionStatuses()
  }

  private func importModelFile(_ result: Result<[URL], Error>) {
    switch result {
    case .failure(let error):
      statusMessage = error.localizedDescription
    case .success(let urls):
      guard let url = urls.first else { return }
      statusMessage = t("galaxyssi.local_model.import_verifying", "Verifying model file...")
      Task.detached(priority: .userInitiated) {
        do {
          let imported = try LocalModelVerifiedFileImporter.install(from: url)
          await MainActor.run {
            let profile = LocalModelRuntimeCatalog.find(imported.profileId)
            LocalModelRuntimeSettings.setSelectedProfile(profile.id)
            LocalModelRuntimeSettings.setProfileEnabled(profile, enabled: true)
            statusMessage = String(
              format: t("galaxyssi.local_model.import_success", "%@ imported and enabled"),
              imported.profileName
            )
            refreshSnapshots()
          }
        } catch {
          await MainActor.run {
            statusMessage = String(
              format: t("galaxyssi.local_model.import_failed", "Model import failed: %@"),
              error.localizedDescription
            )
          }
        }
      }
    }
  }

  private func profileSubtitle(_ profile: LocalModelRuntimeProfile) -> String {
    if !profile.supportsIOSRuntime {
      let chipset = profile.targetChipset.isEmpty ? "Android" : profile.targetChipset
      return String(
        format: t(
          "galaxyssi.local_model.unsupported_subtitle",
          "%@ is an Android/vendor deployment and cannot run on iOS"
        ),
        chipset
      )
    }
    var detail = String(
      format: t("galaxyssi.local_model.profile_details", "%@ - %@ - %@B"),
      formatBytes(profile.expectedModelFileBytes),
      profile.quantizationLabel,
      parameterLabel(profile.parameterCountBillions)
    )
    if profile.defaultNoThink {
      detail += "\n" + t("galaxyssi.local_model.default_no_think", "Default no-think mode")
    }
    return detail
  }

  private func parameterLabel(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
  }

  private func contextLabel(_ tokens: Int) -> String {
    String(format: t("galaxyssi.local_model.context_tokens", "%d tokens"), tokens)
  }

  private func readinessLabel(_ readiness: LocalModelRuntimeReadiness) -> String {
    switch readiness {
    case .ready:
      return t("galaxyssi.local_model.preflight_ready", "Ready")
    case .caution:
      return t("galaxyssi.local_model.preflight_caution", "Review")
    case .blocked:
      return t("galaxyssi.local_model.preflight_blocked", "Blocked")
    }
  }

  private func issueLabel(_ issue: LocalModelRuntimeIssue) -> String {
    switch issue {
    case .unsupportedPlatform:
      return t("galaxyssi.local_model.issue_unsupported_platform", "This model format is not supported by the iOS inference runtime")
    case .modelFileMissing:
      return t("galaxyssi.local_model.issue_file_missing", "The selected model file is missing")
    case .modelFileInvalid:
      return t("galaxyssi.local_model.issue_file_invalid", "The selected model file is empty or invalid")
    case .systemLowMemory:
      return t("galaxyssi.local_model.issue_system_low_memory", "iOS is under memory pressure; retry later")
    case .insufficientMemory:
      return t("galaxyssi.local_model.issue_insufficient_memory", "The minimum context cannot fit within the safe memory budget")
    case .contextReduced:
      return String(
        format: t("galaxyssi.local_model.issue_context_reduced", "Context reduced to %d tokens to fit the safe memory budget"),
        estimate.recommendedContextTokens
      )
    case .thermalPressure:
      return t("galaxyssi.local_model.issue_thermal_pressure", "Thermal pressure detected; recommended threads were reduced")
    case .deviceTooHot:
      return t("galaxyssi.local_model.issue_device_hot", "Device temperature is too high for sustained local inference")
    case .lowBattery:
      return t("galaxyssi.local_model.issue_low_battery", "Battery is low; recommended threads were reduced")
    case .criticalBattery:
      return t("galaxyssi.local_model.issue_critical_battery", "Charge before starting local inference")
    case .powerSaveMode:
      return t("galaxyssi.local_model.issue_power_save", "Low Power Mode is on; recommended threads were reduced")
    }
  }

  private func acceleratorTitle(_ kind: LocalModelAcceleratorKind) -> String {
    switch kind {
    case .cpu:
      return t("galaxyssi.local_model.accelerator_cpu", "CPU Backend")
    case .gpu:
      return t("galaxyssi.local_model.accelerator_gpu", "GPU delegate")
    case .coreMLNeuralEngine:
      return t("galaxyssi.local_model.accelerator_coreml", "Core ML Neural Engine")
    case .vendorSDK:
      return t("galaxyssi.local_model.accelerator_vendor", "Vendor SDK")
    }
  }

  private func acceleratorIcon(_ kind: LocalModelAcceleratorKind) -> String {
    switch kind {
    case .cpu:
      return "cpu"
    case .gpu:
      return "display"
    case .coreMLNeuralEngine:
      return "brain.head.profile"
    case .vendorSDK:
      return "bolt"
    }
  }

  private func acceleratorTint(_ state: LocalModelAcceleratorState) -> Color {
    switch state {
    case .ready:
      return .galaxySSIAccent
    case .hardwareOnly:
      return .orange
    case .unavailable:
      return .galaxySSITextSecondary
    }
  }

  private func acceleratorStatus(_ state: LocalModelAcceleratorState) -> String {
    switch state {
    case .ready:
      return t("galaxyssi.local_model.accelerator_ready", "Ready")
    case .hardwareOnly:
      return t("galaxyssi.local_model.accelerator_hardware_only", "Hardware only")
    case .unavailable:
      return t("galaxyssi.local_model.accelerator_unavailable", "Unavailable")
    }
  }

  private func refreshPermissionStatuses() {
    cameraStatus = authorizationLabel(AVCaptureDevice.authorizationStatus(for: .video))
    microphoneStatus = recordPermissionLabel(AVAudioSession.sharedInstance().recordPermission)
    locationStatus = locationAuthorizationLabel(CLLocationManager.authorizationStatus())
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        notificationStatus = notificationAuthorizationLabel(settings.authorizationStatus)
      }
    }
  }

  private func requestCamera() {
    AVCaptureDevice.requestAccess(for: .video) { _ in
      DispatchQueue.main.async {
        refreshPermissionStatuses()
      }
    }
  }

  private func requestMicrophone() {
    AVAudioSession.sharedInstance().requestRecordPermission { _ in
      DispatchQueue.main.async {
        refreshPermissionStatuses()
      }
    }
  }

  private func requestNotifications() {
    Task {
      _ = await NotificationService.requestAuthorization()
      refreshPermissionStatuses()
    }
  }

  private func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }

  private func authorizationLabel(_ status: AVAuthorizationStatus) -> String {
    switch status {
    case .authorized:
      return t("galaxyssi.permission.allowed", "Allowed")
    case .denied, .restricted:
      return t("galaxyssi.permission.denied", "Denied")
    case .notDetermined:
      return t("galaxyssi.permission.needs_setup", "Needs setup")
    @unknown default:
      return t("galaxyssi.status.unknown", "Unknown")
    }
  }

  private func recordPermissionLabel(_ status: AVAudioSession.RecordPermission) -> String {
    switch status {
    case .granted:
      return t("galaxyssi.permission.allowed", "Allowed")
    case .denied:
      return t("galaxyssi.permission.denied", "Denied")
    case .undetermined:
      return t("galaxyssi.permission.needs_setup", "Needs setup")
    @unknown default:
      return t("galaxyssi.status.unknown", "Unknown")
    }
  }

  private func locationAuthorizationLabel(_ status: CLAuthorizationStatus) -> String {
    switch status {
    case .authorizedAlways, .authorizedWhenInUse:
      return t("galaxyssi.permission.while_using", "While using")
    case .denied, .restricted:
      return t("galaxyssi.permission.denied", "Denied")
    case .notDetermined:
      return t("galaxyssi.permission.needs_setup", "Needs setup")
    @unknown default:
      return t("galaxyssi.status.unknown", "Unknown")
    }
  }

  private func notificationAuthorizationLabel(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .authorized, .provisional, .ephemeral:
      return t("galaxyssi.permission.allowed", "Allowed")
    case .denied:
      return t("galaxyssi.permission.denied", "Denied")
    case .notDetermined:
      return t("galaxyssi.permission.needs_setup", "Needs setup")
    @unknown default:
      return t("galaxyssi.status.unknown", "Unknown")
    }
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let value = Double(max(0, bytes))
    let gib = value / 1_073_741_824
    if gib >= 1 {
      return String(format: "%.1f GiB", gib)
    }
    let mib = value / 1_048_576
    return String(format: "%.0f MiB", mib)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSILocalModelSearchView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var hubResults: [LocalModelHubSearchResult] = []
  @State private var hubSearchInFlight = false
  @State private var hubSearchStatus = ""

  private var profileResults: [LocalModelRuntimeProfile] {
    let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let profiles = LocalModelRuntimeCatalog.profiles()
    guard !clean.isEmpty else { return profiles }
    let normalized = clean.lowercased()
    return profiles.filter { profile in
      profile.id.lowercased().contains(normalized) ||
        profile.displayName.lowercased().contains(normalized) ||
        profile.quantizationLabel.lowercased().contains(normalized)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.local_model.search_title", "Search models"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      VStack(spacing: 10) {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .foregroundColor(.galaxySSITextSecondary)
          TextField(t("galaxyssi.local_model.search_hint", "Model name or repository"), text: $query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .onSubmit {
              performHubSearch()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color.galaxySSISearchBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            GalaxySSILocalModelLabHeroView(
              title: t("galaxyssi.local_model.artifact_title", "Choose a GGUF file"),
              subtitle: t("galaxyssi.local_model.artifact_subtitle", "Only single-file models with size and SHA-256 metadata are eligible"),
              systemImage: "doc",
              tint: .galaxySSIAccent,
              badge: t("galaxyssi.local_model.hub_source", "Hugging Face model")
            )
            GalaxySSILocalModelLabActionRow(
              title: t("galaxyssi.local_model.hub_source", "Hugging Face model"),
              subtitle: t("galaxyssi.local_model.search_subtitle", "Find downloadable GGUF models across trusted model hubs"),
              systemImage: "globe",
              tint: .blue,
              badge: hubSearchInFlight
                ? t("galaxyssi.local_model.searching", "Searching...")
                : t("galaxyssi.local_model.search_action", "Search")
            ) {
              performHubSearch()
            }
            if !hubSearchStatus.isEmpty {
              GalaxySSILocalModelLabStatusRow(
                title: t("galaxyssi.local_model.search_status", "Search Status"),
                subtitle: hubSearchStatus,
                systemImage: hubSearchInFlight ? "hourglass" : "info.circle",
                tint: hubSearchInFlight ? .blue : .galaxySSITextSecondary,
                badge: hubSearchInFlight
                  ? t("galaxyssi.local_model.searching", "Searching...")
                  : t("galaxyssi.status.ready", "Ready")
              )
            }
            if !hubResults.isEmpty {
              GalaxySSILocalModelLabSectionTitle(title: t("galaxyssi.local_model.hub_results_section", "Model Hub Results"))
              ForEach(hubResults) { result in
                GalaxySSILocalModelLabNavigationRow(
                  title: result.displayName,
                  subtitle: hubResultSubtitle(result),
                  systemImage: "globe",
                  tint: .blue,
                  badge: t("galaxyssi.local_model.open_repository", "Open")
                ) {
                  GalaxySSILocalModelHubArtifactView(model: result)
                }
              }
            }
            GalaxySSILocalModelLabSectionTitle(title: t("galaxyssi.local_model.section_profiles", "Workload Profiles"))
            if profileResults.isEmpty {
              GalaxySSILocalModelLabStatusRow(
                title: t("galaxyssi.local_model.search_empty", "No downloadable GGUF model found"),
                subtitle: query,
                systemImage: "magnifyingglass",
                tint: .orange,
                badge: t("galaxyssi.status.unknown", "Unknown")
              )
            } else {
              ForEach(profileResults) { profile in
                GalaxySSILocalModelLabActionRow(
                  title: profile.displayName,
                  subtitle: profileSubtitle(profile),
                  systemImage: "cpu",
                  tint: .galaxySSIAccent,
                  badge: t("galaxyssi.local_model.use_action", "Use")
                ) {
                  select(profile)
                }
              }
            }
          }
          .padding(.top, 12)
          .padding(.bottom, 18)
        }
      }
      .padding(.horizontal, 12)
      .padding(.top, 12)
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private func select(_ profile: LocalModelRuntimeProfile) {
    LocalModelRuntimeSettings.setSelectedProfile(profile.id)
    dismiss()
  }

  private func performHubSearch() {
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard term.count >= 2 else {
      hubSearchStatus = t("galaxyssi.local_model.search_minimum_query", "Enter at least 2 characters to search model hubs.")
      hubResults = []
      return
    }
    guard !hubSearchInFlight else { return }
    hubSearchInFlight = true
    hubSearchStatus = t("galaxyssi.local_model.searching", "Searching model hubs...")
    Task {
      do {
        let results = try await LocalModelHubSearchClient.search(query: term)
        await MainActor.run {
          hubResults = results
          hubSearchStatus = results.isEmpty
            ? t("galaxyssi.local_model.search_empty", "No downloadable GGUF model found")
            : String(format: t("galaxyssi.local_model.hub_result_count", "%d model hub results"), results.count)
          hubSearchInFlight = false
        }
      } catch {
        await MainActor.run {
          hubResults = []
          hubSearchStatus = String(
            format: t("galaxyssi.local_model.search_error", "Model search failed: %@"),
            error.localizedDescription
          )
          hubSearchInFlight = false
        }
      }
    }
  }

  private func hubResultSubtitle(_ result: LocalModelHubSearchResult) -> String {
    let owner = result.author.ifBlank(result.namespace).ifBlank(t("galaxyssi.local_model.hub_source", "Hugging Face model"))
    return String(
      format: t("galaxyssi.local_model.repository_downloads", "%@ - %@ - %@ downloads"),
      owner,
      hubSourceLabel(result.source),
      compactCount(result.downloads)
    )
  }

  private func hubSourceLabel(_ source: LocalModelHubSource) -> String {
    switch source {
    case .huggingFace:
      return t("galaxyssi.local_model.source_huggingface", "Hugging Face")
    case .modelScope:
      return t("galaxyssi.local_model.source_modelscope", "ModelScope")
    }
  }

  private func profileSubtitle(_ profile: LocalModelRuntimeProfile) -> String {
    var detail = String(
      format: t("galaxyssi.local_model.profile_details", "%@ - %@ - %@B"),
      formatBytes(profile.expectedModelFileBytes),
      profile.quantizationLabel,
      parameterLabel(profile.parameterCountBillions)
    )
    if profile.defaultNoThink {
      detail += "\n" + t("galaxyssi.local_model.default_no_think", "Default no-think mode")
    }
    return detail
  }

  private func parameterLabel(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let value = Double(max(0, bytes))
    let gib = value / 1_073_741_824
    if gib >= 1 {
      return String(format: "%.1f GiB", gib)
    }
    let mib = value / 1_048_576
    return String(format: "%.0f MiB", mib)
  }

  private func compactCount(_ value: Int) -> String {
    if value >= 1_000_000 {
      return String(format: "%.1fM", Double(value) / 1_000_000.0)
    }
    if value >= 1_000 {
      return String(format: "%.1fK", Double(value) / 1_000.0)
    }
    return "\(value)"
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct LocalModelHubSearchResult: Identifiable, Decodable {
  var id: String
  var author: String
  var downloads: Int
  var source: LocalModelHubSource = .huggingFace
  var visionCapable: Bool = false

  enum CodingKeys: String, CodingKey {
    case id
    case modelId
    case author
    case downloads
    case tags
  }

  init(
    id: String,
    author: String,
    downloads: Int,
    source: LocalModelHubSource = .huggingFace,
    visionCapable: Bool = false
  ) {
    self.id = id
    self.author = author
    self.downloads = max(0, downloads)
    self.source = source
    self.visionCapable = visionCapable
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try (
      container.decodeIfPresent(String.self, forKey: .modelId) ??
        container.decodeIfPresent(String.self, forKey: .id)
    ) ?? ""
    author = (try container.decodeIfPresent(String.self, forKey: .author)) ?? ""
    downloads = Self.decodeLossyInt(container, forKey: .downloads)
    let tags = (try? container.decodeIfPresent([String].self, forKey: .tags)) ?? []
    visionCapable = Self.isVisionCapable(tags)
  }

  var displayName: String {
    id.split(separator: "/").last.map(String.init) ?? id
  }

  var namespace: String {
    id.split(separator: "/").first.map(String.init) ?? ""
  }

  var repositoryURL: URL? {
    guard !id.isEmpty,
          let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
      return nil
    }
    switch source {
    case .huggingFace:
      return URL(string: "https://huggingface.co/\(escaped)")
    case .modelScope:
      return URL(string: "https://modelscope.cn/models/\(escaped)")
    }
  }

  private static func decodeLossyInt(
    _ container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) -> Int {
    if let value = try? container.decode(Int.self, forKey: key) {
      return max(0, value)
    }
    if let value = try? container.decode(Double.self, forKey: key) {
      return max(0, Int(value))
    }
    return 0
  }

  private static func isVisionCapable(_ tags: [String]) -> Bool {
    tags.contains { tag in
      let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return normalized == "image-text-to-text" ||
        normalized == "task:image-text-to-text" ||
        normalized == "vision"
    }
  }
}

private enum LocalModelHubSearchClient {
  static func search(query: String) async throws -> [LocalModelHubSearchResult] {
    var receivedEmptyResponse = false
    var lastError: Error?
    for source in sourceOrder() {
      do {
        let results = try await search(query: query, source: source)
        if !results.isEmpty { return results }
        receivedEmptyResponse = true
      } catch {
        lastError = error
      }
    }
    if receivedEmptyResponse { return [] }
    throw lastError ?? URLError(.badServerResponse)
  }

  private static func search(query: String, source: LocalModelHubSource) async throws -> [LocalModelHubSearchResult] {
    switch source {
    case .huggingFace:
      guard var components = URLComponents(string: "https://huggingface.co/api/models") else {
        throw URLError(.badURL)
      }
      components.queryItems = [
        URLQueryItem(name: "search", value: query),
        URLQueryItem(name: "filter", value: "gguf"),
        URLQueryItem(name: "sort", value: "downloads"),
        URLQueryItem(name: "direction", value: "-1"),
        URLQueryItem(name: "limit", value: "20")
      ]
      guard let url = components.url else { throw URLError(.badURL) }
      let data = try await requestData(url: url)
      return try JSONDecoder()
        .decode([LocalModelHubSearchResult].self, from: data)
        .filter { !$0.id.isEmpty }
    case .modelScope:
      let modelScopeQuery = query.localizedCaseInsensitiveContains("gguf") ? query : "\(query) GGUF"
      guard var components = URLComponents(string: "https://modelscope.cn/openapi/v1/models") else {
        throw URLError(.badURL)
      }
      components.queryItems = [
        URLQueryItem(name: "search", value: modelScopeQuery),
        URLQueryItem(name: "sort", value: "downloads"),
        URLQueryItem(name: "page_number", value: "1"),
        URLQueryItem(name: "page_size", value: "20")
      ]
      guard let url = components.url else { throw URLError(.badURL) }
      let data = try await requestData(url: url)
      return parseModelScopeSearchResults(data)
    }
  }

  private static func requestData(url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("GalaxySSI-iOS", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw URLError(.badServerResponse)
    }
    return data
  }

  private static func parseModelScopeSearchResults(_ data: Data) -> [LocalModelHubSearchResult] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let dataObject = (root["data"] as? [String: Any]) ?? (root["Data"] as? [String: Any]),
          let models = (dataObject["models"] as? [[String: Any]]) ?? (dataObject["Models"] as? [[String: Any]]) else {
      return []
    }
    return models.compactMap { value in
      guard let id = value["id"] as? String, id.contains("/") else { return nil }
      let tags = stringArray(value["tags"])
      guard tags.contains(where: { ["gguf", "library:gguf", "custom_tag:gguf"].contains($0.lowercased()) }) else {
        return nil
      }
      return LocalModelHubSearchResult(
        id: id,
        author: id.split(separator: "/").first.map(String.init) ?? "",
        downloads: intValue(value["downloads"]),
        source: .modelScope,
        visionCapable: tags.contains { tag in
          let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
          return normalized == "task:image-text-to-text" || normalized == "vision"
        }
      )
    }
  }

  private static func sourceOrder() -> [LocalModelHubSource] {
    Locale.current.languageCode?.lowercased() == "zh"
      ? [.modelScope, .huggingFace]
      : [.huggingFace, .modelScope]
  }

  private static func stringArray(_ value: Any?) -> [String] {
    if let values = value as? [String] { return values }
    return (value as? [Any])?.compactMap { $0 as? String } ?? []
  }

  private static func intValue(_ value: Any?) -> Int {
    if let number = value as? NSNumber { return max(0, number.intValue) }
    if let string = value as? String { return max(0, Int(Double(string) ?? 0)) }
    return 0
  }
}
