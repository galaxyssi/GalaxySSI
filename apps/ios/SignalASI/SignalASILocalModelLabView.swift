import AVFoundation
import CoreLocation
import Foundation
import SwiftUI
import UIKit
import UserNotifications

struct SignalASILocalModelLabView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var selectedProfile = LocalModelRuntimeSettings.selectedProfile()
  @State private var contextTokens = LocalModelRuntimeSettings.contextTokens()
  @State private var deviceSnapshot = LocalModelDeviceSnapshotDetector.capture()
  @State private var acceleratorSnapshot = LocalModelAcceleratorDetector.detect()
  @State private var showingContextChoices = false
  @State private var cameraStatus = ""
  @State private var microphoneStatus = ""
  @State private var locationStatus = ""
  @State private var notificationStatus = ""
  @State private var statusMessage = ""

  private let whisperModelManager = VoiceWhisperModelManager()

  private var estimate: LocalModelRuntimeEstimate {
    LocalModelRuntimeEstimator.estimate(
      LocalModelRuntimeRequest(
        profile: selectedProfile,
        requestedContextTokens: contextTokens,
        modelFileBytes: selectedProfile.expectedModelFileBytes,
        modelFilePresent: true,
        requireModelFile: false
      ),
      device: deviceSnapshot
    )
  }

  private var runtimeAvailable: Bool {
    acceleratorSnapshot.readyKinds.contains(.cpu) ||
      acceleratorSnapshot.readyKinds.contains(.gpu) ||
      acceleratorSnapshot.readyKinds.contains(.coreMLNeuralEngine) ||
      acceleratorSnapshot.readyKinds.contains(.vendorSDK)
  }

  private var localModelConnectorCount: Int {
    store.contacts.filter { contact in
      !contact.deleted &&
        contact.deliveryMode == .link &&
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

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.local_model.title", "Local Model"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASILocalModelLabHeroView(
            title: t("signalasi.local_model.status_title", "Local Model Status"),
            subtitle: preflightDetail,
            systemImage: "cpu",
            tint: readinessTint,
            badge: runtimeAvailable ? readinessLabel(estimate.readiness) : t("signalasi.local_model.preflight_blocked", "Blocked")
          )
          if !statusMessage.isEmpty {
            SignalASILocalModelLabStatusRow(
              title: t("signalasi.local_model.status", "Status"),
              subtitle: statusMessage,
              systemImage: "checkmark.circle",
              tint: .signalASIAccent,
              badge: t("signalasi.status.ready", "Ready")
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
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .confirmationDialog(
      t("signalasi.local_model.context_window", "Context Window"),
      isPresented: $showingContextChoices,
      titleVisibility: .visible
    ) {
      ForEach(contextChoices, id: \.self) { tokens in
        Button(contextLabel(tokens)) {
          setContextTokens(tokens)
        }
      }
      Button(t("signalasi.common.cancel", "Cancel"), role: .cancel) {}
    }
    .onAppear(perform: refreshSnapshots)
  }

  private var manageSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASILocalModelLabSectionTitle(title: t("signalasi.local_model.section_manage", "Model Management"))
      SignalASILocalModelLabNavigationRow(
        title: t("signalasi.local_model.search_title", "Search models"),
        subtitle: t("signalasi.local_model.search_subtitle", "Find downloadable GGUF models across trusted model hubs"),
        systemImage: "magnifyingglass",
        tint: .signalASIInsightText,
        badge: t("signalasi.local_model.search_action", "Search")
      ) {
        SignalASILocalModelSearchView()
      }
      ForEach(LocalModelRuntimeProfiles.all) { profile in
        SignalASILocalModelLabActionRow(
          title: profile.displayName,
          subtitle: profileSubtitle(profile),
          systemImage: "cpu",
          tint: profile.id == selectedProfile.id ? .signalASIAccent : .blue,
          badge: profile.id == selectedProfile.id
            ? t("signalasi.local_model.selected", "Current")
            : t("signalasi.local_model.use_action", "Use")
        ) {
          selectProfile(profile)
        }
      }
      SignalASILocalModelLabActionRow(
        title: t("signalasi.local_model.context_window", "Context Window"),
        subtitle: t("signalasi.local_model.context_window_subtitle", "Larger context increases KV cache usage"),
        systemImage: "text.alignleft",
        tint: .purple,
        badge: contextLabel(contextTokens)
      ) {
        showingContextChoices = true
      }
      SignalASILocalModelLabNavigationRow(
        title: t("signalasi.local_model.asr_model", "Whisper Model"),
        subtitle: VoiceWhisperModelCatalog.model(store.voiceSettings.asrModelId).displayName,
        systemImage: "waveform",
        tint: .teal,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        VoiceWhisperModelSettingsView()
      }
    }
  }

  private var preflightSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASILocalModelLabSectionTitle(title: t("signalasi.local_model.preflight_section", "Runtime Preflight"))
      SignalASILocalModelLabStatusRow(
        title: t("signalasi.local_model.file_estimate", "Estimated Model File"),
        subtitle: selectedProfile.quantizationLabel,
        systemImage: "doc",
        tint: .blue,
        badge: formatBytes(estimate.modelFileBytes)
      )
      SignalASILocalModelLabStatusRow(
        title: t("signalasi.local_model.kv_cache", "KV cache"),
        subtitle: String(
          format: t("signalasi.local_model.kv_cache_subtitle", "Estimated at %d tokens context"),
          estimate.recommendedContextTokens
        ),
        systemImage: "memorychip",
        tint: .purple,
        badge: formatBytes(estimate.kvCacheBytes)
      )
      SignalASILocalModelLabStatusRow(
        title: t("signalasi.local_model.safe_memory", "Working Set / Safe Budget"),
        subtitle: t("signalasi.local_model.safe_memory_subtitle", "Reserve memory for iOS and foreground apps"),
        systemImage: "memorychip",
        tint: readinessTint,
        badge: String(
          format: t("signalasi.local_model.memory_required_value", "%@ / %@"),
          formatBytes(estimate.totalRequiredBytes),
          formatBytes(estimate.safeMemoryBudgetBytes)
        )
      )
      SignalASILocalModelLabStatusRow(
        title: t("signalasi.local_model.threads", "Recommended Threads"),
        subtitle: String(
          format: t("signalasi.local_model.threads_subtitle", "Detected %d CPU cores"),
          estimate.device.cpuCoreCount
        ),
        systemImage: "cpu",
        tint: .blue,
        badge: "\(estimate.recommendedThreads)"
      )
      SignalASILocalModelLabStatusRow(
        title: t("signalasi.local_model.temperature", "Temperature"),
        subtitle: thermalDetail,
        systemImage: "thermometer",
        tint: thermalTint,
        badge: thermalValue
      )
      SignalASILocalModelLabStatusRow(
        title: t("signalasi.local_model.battery", "Battery"),
        subtitle: estimate.device.charging
          ? t("signalasi.local_model.battery_charging", "Charging; longer inference is available")
          : t("signalasi.local_model.battery_not_charging", "Not charging; battery protection applies"),
        systemImage: "battery.75",
        tint: batteryTint,
        badge: estimate.device.batteryPercent.map { "\($0)%" } ?? t("signalasi.status.unknown", "Unknown")
      )
      SignalASILocalModelLabActionRow(
        title: t("signalasi.local_model.refresh_preflight", "Refresh Preflight"),
        subtitle: t("signalasi.local_model.refresh_preflight_subtitle", "Recheck memory, CPU, temperature, and battery"),
        systemImage: "arrow.clockwise",
        tint: .signalASIAccent,
        badge: t("signalasi.common.refresh", "Refresh")
      ) {
        refreshSnapshots()
      }
    }
  }

  private var accelerationSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASILocalModelLabSectionTitle(title: t("signalasi.local_model.acceleration_section", "Acceleration Backends"))
      ForEach(acceleratorSnapshot.capabilities) { capability in
        SignalASILocalModelLabStatusRow(
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
      SignalASILocalModelLabSectionTitle(title: t("signalasi.local_model.section_permissions", "Device Permissions"))
      SignalASILocalModelLabNavigationRow(
        title: t("signalasi.local_model.on_device_permissions", "On-device Agent Permissions"),
        subtitle: t("signalasi.local_model.on_device_permissions_subtitle", "Review microphone, camera, notifications, and device-side execution"),
        systemImage: "checkmark.shield",
        tint: .signalASIAccent,
        badge: t("signalasi.common.view", "View")
      ) {
        OnDeviceAgentPermissionsView()
      }
      SignalASILocalModelLabActionRow(
        title: t("signalasi.on_device_agent.microphone", "Microphone"),
        subtitle: t("signalasi.on_device_agent.microphone_subtitle", "Voice input and hold-to-talk"),
        systemImage: "mic",
        tint: .signalASIAccent,
        badge: microphoneStatus.ifBlank(t("signalasi.permission.needs_setup", "Needs setup"))
      ) {
        requestMicrophone()
      }
      SignalASILocalModelLabActionRow(
        title: t("signalasi.on_device_agent.camera", "Camera"),
        subtitle: t("signalasi.on_device_agent.camera_subtitle", "QR scanning and visual recognition"),
        systemImage: "camera",
        tint: .teal,
        badge: cameraStatus.ifBlank(t("signalasi.permission.needs_setup", "Needs setup"))
      ) {
        requestCamera()
      }
      SignalASILocalModelLabActionRow(
        title: t("signalasi.local_model.location", "Location"),
        subtitle: t("signalasi.local_model.location_subtitle", "Local scenarios can keep location permission disabled"),
        systemImage: "location",
        tint: .purple,
        badge: locationStatus.ifBlank(t("signalasi.permission.needs_setup", "Needs setup"))
      ) {
        openAppSettings()
      }
      SignalASILocalModelLabActionRow(
        title: t("signalasi.local_model.notification_permission", "Notifications"),
        subtitle: t("signalasi.local_model.notification_permission_subtitle", "Background model and Agent prompts"),
        systemImage: "bell.badge",
        tint: .orange,
        badge: notificationStatus.ifBlank(t("signalasi.permission.needs_setup", "Needs setup"))
      ) {
        requestNotifications()
      }
    }
  }

  private var privacyStorageSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASILocalModelLabSectionTitle(title: t("signalasi.local_model.section_privacy_storage", "Privacy & Storage"))
      SignalASILocalModelLabStatusRow(
        title: t("signalasi.local_model.offline_mode", "Offline Mode"),
        subtitle: t("signalasi.local_model.offline_mode_subtitle", "Keep working without network access"),
        systemImage: "lock.shield",
        tint: .signalASIAccent,
        badge: t("signalasi.status.enabled", "Enabled")
      )
      SignalASILocalModelLabStatusRow(
        title: t("signalasi.local_model.storage_usage", "Storage Usage"),
        subtitle: String(
          format: t("signalasi.local_model.storage_usage_subtitle", "%d Whisper models / %d Desktop local model connectors"),
          installedWhisperCount,
          localModelConnectorCount
        ),
        systemImage: "internaldrive",
        tint: .blue,
        badge: formatBytes(selectedProfile.expectedModelFileBytes)
      )
      SignalASILocalModelLabStatusRow(
        title: t("signalasi.local_model.download_source", "Local Model Download"),
        subtitle: t(VoiceWhisperModelSettingsPresenter.mirrorNoteKey, VoiceWhisperModelSettingsPresenter.mirrorNote),
        systemImage: "arrow.down.circle",
        tint: .teal,
        badge: t("signalasi.local_model.hub_source", "Hugging Face model")
      )
    }
  }

  private var preflightDetail: String {
    guard runtimeAvailable else {
      return t("signalasi.local_model.runtime_unavailable", "Local inference runtime is unavailable in this build")
    }
    guard !estimate.issues.isEmpty else {
      return t("signalasi.local_model.preflight_ready_detail", "The estimated workload fits the current safe device budget")
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
      return .signalASIAccent
    case .caution:
      return .orange
    case .blocked:
      return .red
    }
  }

  private var thermalValue: String {
    switch estimate.device.thermalStatus ?? 0 {
    case 0:
      return t("signalasi.local_model.thermal_none", "Nominal")
    case 1:
      return t("signalasi.local_model.thermal_light", "Light")
    case 2:
      return t("signalasi.local_model.thermal_moderate", "Moderate")
    default:
      return t("signalasi.local_model.thermal_severe", "Severe")
    }
  }

  private var thermalDetail: String {
    if let celsius = estimate.device.batteryTemperatureCelsius {
      return String(format: "%.1f C", celsius)
    }
    return t("signalasi.local_model.thermal_unknown", "Thermal state is reported by iOS")
  }

  private var thermalTint: Color {
    let status = estimate.device.thermalStatus ?? 0
    if status >= 3 { return .red }
    if status >= 2 { return .orange }
    return .signalASIAccent
  }

  private var batteryTint: Color {
    guard !estimate.device.charging, let percent = estimate.device.batteryPercent else {
      return .signalASIAccent
    }
    if percent < 10 { return .red }
    if percent < 20 { return .orange }
    return .signalASIAccent
  }

  private var contextChoices: [Int] {
    [2_048, 4_096, 8_192, 16_384, 32_768]
      .filter { $0 <= selectedProfile.maximumContextTokens }
  }

  private func selectProfile(_ profile: LocalModelRuntimeProfile) {
    selectedProfile = profile
    LocalModelRuntimeSettings.setSelectedProfile(profile.id)
    if contextTokens > profile.maximumContextTokens {
      setContextTokens(profile.maximumContextTokens)
    }
    statusMessage = String(format: t("signalasi.local_model.profile_selected", "%@ selected"), profile.displayName)
    refreshSnapshots()
  }

  private func setContextTokens(_ tokens: Int) {
    contextTokens = tokens
    LocalModelRuntimeSettings.setContextTokens(tokens)
    statusMessage = String(format: t("signalasi.local_model.context_selected", "%@ selected"), contextLabel(tokens))
    refreshSnapshots()
  }

  private func refreshSnapshots() {
    selectedProfile = LocalModelRuntimeSettings.selectedProfile()
    contextTokens = min(LocalModelRuntimeSettings.contextTokens(), selectedProfile.maximumContextTokens)
    deviceSnapshot = LocalModelDeviceSnapshotDetector.capture()
    acceleratorSnapshot = LocalModelAcceleratorDetector.detect()
    refreshPermissionStatuses()
  }

  private func profileSubtitle(_ profile: LocalModelRuntimeProfile) -> String {
    String(
      format: t("signalasi.local_model.size_and_quantization", "%@ - %@ - %d tokens"),
      formatBytes(profile.expectedModelFileBytes),
      profile.quantizationLabel,
      profile.defaultContextTokens
    )
  }

  private func contextLabel(_ tokens: Int) -> String {
    String(format: t("signalasi.local_model.context_tokens", "%d tokens"), tokens)
  }

  private func readinessLabel(_ readiness: LocalModelRuntimeReadiness) -> String {
    switch readiness {
    case .ready:
      return t("signalasi.local_model.preflight_ready", "Ready")
    case .caution:
      return t("signalasi.local_model.preflight_caution", "Review")
    case .blocked:
      return t("signalasi.local_model.preflight_blocked", "Blocked")
    }
  }

  private func issueLabel(_ issue: LocalModelRuntimeIssue) -> String {
    switch issue {
    case .modelFileMissing:
      return t("signalasi.local_model.issue_file_missing", "The selected model file is missing")
    case .modelFileInvalid:
      return t("signalasi.local_model.issue_file_invalid", "The selected model file is empty or invalid")
    case .systemLowMemory:
      return t("signalasi.local_model.issue_system_low_memory", "iOS is under memory pressure; retry later")
    case .insufficientMemory:
      return t("signalasi.local_model.issue_insufficient_memory", "The minimum context cannot fit within the safe memory budget")
    case .contextReduced:
      return String(
        format: t("signalasi.local_model.issue_context_reduced", "Context reduced to %d tokens to fit the safe memory budget"),
        estimate.recommendedContextTokens
      )
    case .thermalPressure:
      return t("signalasi.local_model.issue_thermal_pressure", "Thermal pressure detected; recommended threads were reduced")
    case .deviceTooHot:
      return t("signalasi.local_model.issue_device_hot", "Device temperature is too high for sustained local inference")
    case .lowBattery:
      return t("signalasi.local_model.issue_low_battery", "Battery is low; recommended threads were reduced")
    case .criticalBattery:
      return t("signalasi.local_model.issue_critical_battery", "Charge before starting local inference")
    case .powerSaveMode:
      return t("signalasi.local_model.issue_power_save", "Low Power Mode is on; recommended threads were reduced")
    }
  }

  private func acceleratorTitle(_ kind: LocalModelAcceleratorKind) -> String {
    switch kind {
    case .cpu:
      return t("signalasi.local_model.accelerator_cpu", "CPU Backend")
    case .gpu:
      return t("signalasi.local_model.accelerator_gpu", "GPU delegate")
    case .coreMLNeuralEngine:
      return t("signalasi.local_model.accelerator_coreml", "Core ML Neural Engine")
    case .vendorSDK:
      return t("signalasi.local_model.accelerator_vendor", "Vendor SDK")
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
      return .signalASIAccent
    case .hardwareOnly:
      return .orange
    case .unavailable:
      return .signalASITextSecondary
    }
  }

  private func acceleratorStatus(_ state: LocalModelAcceleratorState) -> String {
    switch state {
    case .ready:
      return t("signalasi.local_model.accelerator_ready", "Ready")
    case .hardwareOnly:
      return t("signalasi.local_model.accelerator_hardware_only", "Hardware only")
    case .unavailable:
      return t("signalasi.local_model.accelerator_unavailable", "Unavailable")
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
      return t("signalasi.permission.allowed", "Allowed")
    case .denied, .restricted:
      return t("signalasi.permission.denied", "Denied")
    case .notDetermined:
      return t("signalasi.permission.needs_setup", "Needs setup")
    @unknown default:
      return t("signalasi.status.unknown", "Unknown")
    }
  }

  private func recordPermissionLabel(_ status: AVAudioSession.RecordPermission) -> String {
    switch status {
    case .granted:
      return t("signalasi.permission.allowed", "Allowed")
    case .denied:
      return t("signalasi.permission.denied", "Denied")
    case .undetermined:
      return t("signalasi.permission.needs_setup", "Needs setup")
    @unknown default:
      return t("signalasi.status.unknown", "Unknown")
    }
  }

  private func locationAuthorizationLabel(_ status: CLAuthorizationStatus) -> String {
    switch status {
    case .authorizedAlways, .authorizedWhenInUse:
      return t("signalasi.permission.while_using", "While using")
    case .denied, .restricted:
      return t("signalasi.permission.denied", "Denied")
    case .notDetermined:
      return t("signalasi.permission.needs_setup", "Needs setup")
    @unknown default:
      return t("signalasi.status.unknown", "Unknown")
    }
  }

  private func notificationAuthorizationLabel(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .authorized, .provisional, .ephemeral:
      return t("signalasi.permission.allowed", "Allowed")
    case .denied:
      return t("signalasi.permission.denied", "Denied")
    case .notDetermined:
      return t("signalasi.permission.needs_setup", "Needs setup")
    @unknown default:
      return t("signalasi.status.unknown", "Unknown")
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
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASILocalModelSearchView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var hubResults: [LocalModelHubSearchResult] = []
  @State private var hubSearchInFlight = false
  @State private var hubSearchStatus = ""

  private var profileResults: [LocalModelRuntimeProfile] {
    let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return LocalModelRuntimeProfiles.all }
    let normalized = clean.lowercased()
    return LocalModelRuntimeProfiles.all.filter { profile in
      profile.id.lowercased().contains(normalized) ||
        profile.displayName.lowercased().contains(normalized) ||
        profile.quantizationLabel.lowercased().contains(normalized)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.local_model.search_title", "Search models"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      VStack(spacing: 10) {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .foregroundColor(.signalASITextSecondary)
          TextField(t("signalasi.local_model.search_hint", "Model name or repository"), text: $query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .onSubmit {
              performHubSearch()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color.signalASISearchBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            SignalASILocalModelLabHeroView(
              title: t("signalasi.local_model.artifact_title", "Choose a GGUF file"),
              subtitle: t("signalasi.local_model.artifact_subtitle", "Only single-file models with size and SHA-256 metadata are eligible"),
              systemImage: "doc",
              tint: .signalASIAccent,
              badge: t("signalasi.local_model.hub_source", "Hugging Face model")
            )
            SignalASILocalModelLabActionRow(
              title: t("signalasi.local_model.hub_source", "Hugging Face model"),
              subtitle: t("signalasi.local_model.search_subtitle", "Find downloadable GGUF models across trusted model hubs"),
              systemImage: "globe",
              tint: .blue,
              badge: hubSearchInFlight
                ? t("signalasi.local_model.searching", "Searching...")
                : t("signalasi.local_model.search_action", "Search")
            ) {
              performHubSearch()
            }
            if !hubSearchStatus.isEmpty {
              SignalASILocalModelLabStatusRow(
                title: t("signalasi.local_model.search_status", "Search Status"),
                subtitle: hubSearchStatus,
                systemImage: hubSearchInFlight ? "hourglass" : "info.circle",
                tint: hubSearchInFlight ? .blue : .signalASITextSecondary,
                badge: hubSearchInFlight
                  ? t("signalasi.local_model.searching", "Searching...")
                  : t("signalasi.status.ready", "Ready")
              )
            }
            if !hubResults.isEmpty {
              SignalASILocalModelLabSectionTitle(title: t("signalasi.local_model.hub_results_section", "Model Hub Results"))
              ForEach(hubResults) { result in
                SignalASILocalModelLabActionRow(
                  title: result.displayName,
                  subtitle: hubResultSubtitle(result),
                  systemImage: "globe",
                  tint: .blue,
                  badge: t("signalasi.local_model.open_repository", "Open")
                ) {
                  openHubResult(result)
                }
              }
            }
            SignalASILocalModelLabSectionTitle(title: t("signalasi.local_model.section_profiles", "Workload Profiles"))
            if profileResults.isEmpty {
              SignalASILocalModelLabStatusRow(
                title: t("signalasi.local_model.search_empty", "No downloadable GGUF model found"),
                subtitle: query,
                systemImage: "magnifyingglass",
                tint: .orange,
                badge: t("signalasi.status.unknown", "Unknown")
              )
            } else {
              ForEach(profileResults) { profile in
                SignalASILocalModelLabActionRow(
                  title: profile.displayName,
                  subtitle: profileSubtitle(profile),
                  systemImage: "cpu",
                  tint: .signalASIAccent,
                  badge: t("signalasi.local_model.use_action", "Use")
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
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private func select(_ profile: LocalModelRuntimeProfile) {
    LocalModelRuntimeSettings.setSelectedProfile(profile.id)
    dismiss()
  }

  private func performHubSearch() {
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard term.count >= 2 else {
      hubSearchStatus = t("signalasi.local_model.search_minimum_query", "Enter at least 2 characters to search model hubs.")
      hubResults = []
      return
    }
    guard !hubSearchInFlight else { return }
    hubSearchInFlight = true
    hubSearchStatus = t("signalasi.local_model.searching", "Searching model hubs...")
    Task {
      do {
        let results = try await LocalModelHubSearchClient.search(query: term)
        await MainActor.run {
          hubResults = results
          hubSearchStatus = results.isEmpty
            ? t("signalasi.local_model.search_empty", "No downloadable GGUF model found")
            : String(format: t("signalasi.local_model.hub_result_count", "%d model hub results"), results.count)
          hubSearchInFlight = false
        }
      } catch {
        await MainActor.run {
          hubResults = []
          hubSearchStatus = String(
            format: t("signalasi.local_model.search_error", "Model search failed: %@"),
            error.localizedDescription
          )
          hubSearchInFlight = false
        }
      }
    }
  }

  private func openHubResult(_ result: LocalModelHubSearchResult) {
    guard let url = result.repositoryURL else { return }
    UIApplication.shared.open(url)
  }

  private func hubResultSubtitle(_ result: LocalModelHubSearchResult) -> String {
    let owner = result.author.ifBlank(result.namespace).ifBlank(t("signalasi.local_model.hub_source", "Hugging Face model"))
    return String(
      format: t("signalasi.local_model.repository_downloads", "%@ - %@ downloads"),
      owner,
      compactCount(result.downloads)
    )
  }

  private func profileSubtitle(_ profile: LocalModelRuntimeProfile) -> String {
    String(
      format: t("signalasi.local_model.size_and_quantization", "%@ - %@ - %d tokens"),
      formatBytes(profile.expectedModelFileBytes),
      profile.quantizationLabel,
      profile.defaultContextTokens
    )
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
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct LocalModelHubSearchResult: Identifiable, Decodable {
  var id: String
  var author: String
  var downloads: Int

  enum CodingKeys: String, CodingKey {
    case id
    case modelId
    case author
    case downloads
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = (try container.decodeIfPresent(String.self, forKey: .modelId)) ??
      (try container.decodeIfPresent(String.self, forKey: .id)) ??
      ""
    author = (try container.decodeIfPresent(String.self, forKey: .author)) ?? ""
    downloads = Self.decodeLossyInt(container, forKey: .downloads)
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
    return URL(string: "https://huggingface.co/\(escaped)")
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
}

private enum LocalModelHubSearchClient {
  static func search(query: String) async throws -> [LocalModelHubSearchResult] {
    guard var components = URLComponents(string: "https://huggingface.co/api/models") else {
      return []
    }
    components.queryItems = [
      URLQueryItem(name: "search", value: query),
      URLQueryItem(name: "filter", value: "gguf"),
      URLQueryItem(name: "sort", value: "downloads"),
      URLQueryItem(name: "direction", value: "-1"),
      URLQueryItem(name: "limit", value: "20")
    ]
    guard let url = components.url else { return [] }
    let (data, response) = try await URLSession.shared.data(from: url)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw URLError(.badServerResponse)
    }
    return try JSONDecoder()
      .decode([LocalModelHubSearchResult].self, from: data)
      .filter { !$0.id.isEmpty }
  }
}
