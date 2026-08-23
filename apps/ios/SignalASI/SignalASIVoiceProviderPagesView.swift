import SwiftUI

#if canImport(AVFoundation)
import AVFoundation
#endif

enum SignalASIVoiceProviderFormatter {
  static func capabilityTitle(_ id: VoiceProviderCapabilityId, language: String) -> String {
    switch id {
    case .openWakeWord:
      return t("voice_wake_engine_openwakeword", "OpenWakeWord Local Offline", language: language)
    case .whisperCpp:
      return t("voice_asr_local_title", "On-device whisper.cpp", language: language)
    case .androidSystemASR:
      return t("voice_asr_system_title_ios", "iOS system Speech", language: language)
    case .androidOfflineASR:
      return t("voice_asr_offline_title_ios", "iOS on-device Speech", language: language)
    case .cloudASR:
      return t("voice_asr_cloud_title", "Cloud ASR", language: language)
    case .androidSystemTTS:
      return t("voice_tts_ios", "iOS System TTS", language: language)
    case .microsoftEdgeTTS:
      return t("voice_tts_microsoft", "Microsoft Edge Xiaoxiao", language: language)
    }
  }

  static func capabilityStatus(_ capability: VoiceProviderCapability, language: String) -> String {
    switch capability.state {
    case .ready:
      return t("voice_provider_ready", "Ready", language: language)
    case .checking:
      return t("voice_provider_checking", "Checking", language: language)
    case .needsPermission:
      return t("voice_provider_permission_required", "Permission required", language: language)
    case .needsDownload:
      return t("voice_provider_download_required", "Download required", language: language)
    case .needsNetwork:
      return t("voice_provider_network_required", "Network required", language: language)
    case .unavailable:
      return t("voice_provider_unavailable", "Unavailable", language: language)
    }
  }

  static func capabilityDetail(_ capability: VoiceProviderCapability, language: String) -> String {
    let modelName = capability.metadata["model_name"]?.ifBlank("Whisper") ?? "Whisper"
    let ttsLanguage = capability.metadata["language"]?.ifBlank("auto") ?? "auto"
    let engineCount = capability.metadata["engine_count"]?.ifBlank("0") ?? "0"
    switch capability.reason {
    case .ready:
      return readyDetail(capability.id, modelName: modelName, engineCount: engineCount, language: language)
    case .checking:
      return t(
        "voice_provider_checking_detail_ios",
        "The iOS voice service is still initializing",
        language: language
      )
    case .microphoneMissing:
      return t("voice_capability_microphone_missing", "This device does not report a microphone", language: language)
    case .microphonePermissionRequired:
      return t(
        "voice_capability_microphone_permission",
        "Allow microphone access to use this provider",
        language: language
      )
    case .whisperRuntimeMissing:
      return t(
        "voice_capability_whisper_runtime_missing",
        "The bundled whisper.cpp runtime is not compatible with this device",
        language: language
      )
    case .whisperModelMissing:
      return String(
        format: t(
          "voice_capability_whisper_model_missing",
          "Download the %@ model before using offline transcription",
          language: language
        ),
        modelName
      )
    case .systemRecognizerMissing:
      return t(
        "voice_capability_system_asr_missing_ios",
        "iOS Speech recognition is not available for the selected language",
        language: language
      )
    case .offlineRecognizerMissing:
      return t(
        "voice_capability_offline_asr_missing_ios",
        "iOS on-device speech recognition is not available on this device",
        language: language
      )
    case .networkRequired:
      return t(
        "voice_capability_network_required",
        "Connect to a validated network to use this provider",
        language: language
      )
    case .ttsEngineMissing:
      return t(
        "voice_capability_tts_engine_missing_ios",
        "No ready iOS TTS voice is installed",
        language: language
      )
    case .ttsLanguageUnsupported:
      return String(
        format: t(
          "voice_capability_tts_language_unsupported",
          "The system TTS engine does not support %@",
          language: language
        ),
        ttsLanguage
      )
    }
  }

  static func capabilityTint(_ capability: VoiceProviderCapability) -> Color {
    switch capability.state {
    case .ready:
      return .signalASIAccent
    case .checking:
      return .blue
    case .needsDownload:
      return .purple
    case .needsPermission, .needsNetwork:
      return .orange
    case .unavailable:
      return .red
    }
  }

  static func capabilityIcon(_ id: VoiceProviderCapabilityId) -> String {
    switch id {
    case .openWakeWord:
      return "waveform.badge.mic"
    case .whisperCpp:
      return "cpu"
    case .androidSystemASR:
      return "waveform.and.mic"
    case .androidOfflineASR:
      return "shield.lefthalf.filled"
    case .cloudASR:
      return "cloud"
    case .androidSystemTTS:
      return "speaker.wave.2"
    case .microsoftEdgeTTS:
      return "cloud.bolt"
    }
  }

  private static func readyDetail(
    _ id: VoiceProviderCapabilityId,
    modelName: String,
    engineCount: String,
    language: String
  ) -> String {
    switch id {
    case .openWakeWord:
      return t(
        "voice_openwakeword_ready_detail",
        "The bundled wake-word model is ready for offline listening",
        language: language
      )
    case .whisperCpp:
      return String(
        format: t("voice_asr_whisper_ready_detail", "%@ model is installed and runs fully on this phone", language: language),
        modelName
      )
    case .androidSystemASR:
      return t(
        "voice_asr_system_ready_detail_ios",
        "iOS Speech recognition service is ready for live dictation",
        language: language
      )
    case .androidOfflineASR:
      return t(
        "voice_asr_offline_ready_detail_ios",
        "iOS on-device recognition is available without a network",
        language: language
      )
    case .cloudASR:
      return t(
        "voice_asr_cloud_ready_detail",
        "Secure realtime ASR and a validated network are available",
        language: language
      )
    case .androidSystemTTS:
      return String(
        format: t(
          "voice_tts_system_ready_detail_ios",
          "The active iOS TTS voice supports the selected language; %@ voice(s) installed",
          language: language
        ),
        engineCount
      )
    case .microsoftEdgeTTS:
      return t(
        "voice_tts_cloud_ready_detail",
        "Validated network is ready for Microsoft Edge speech",
        language: language
      )
    }
  }

  private static func t(_ key: String, _ fallback: String, language: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: language)
  }
}

struct SignalASIVoiceASRProviderView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var refreshGeneration = 0
  @State private var showOnlineASRConsent = false

  private var settings: VoiceSettings { store.voiceSettings.normalized }
  private var selectedModel: VoiceWhisperModelProfile {
    VoiceWhisperModelCatalog.model(settings.asrModelId)
  }
  private var networkProbe: AgentMediaNetworkProbe {
    _ = refreshGeneration
    return AgentMediaNetworkDetector.shared.currentProbe
  }
  private var validatedNetworkAvailable: Bool {
    networkProbe.networkPresent && networkProbe.internetCapable && networkProbe.validated
  }
  private var capabilitySettings: VoiceSettings {
    var copy = settings
    copy.preferredLocaleIdentifier = LanguagePolicySettings.resolve(store.languagePolicy.asrLanguage)
    return copy.normalized
  }
  private var capabilities: VoiceProviderCapabilitySnapshot {
    _ = refreshGeneration
    return VoiceProviderCapabilityDetector.detect(
      settings: capabilitySettings,
      validatedNetworkAvailable: validatedNetworkAvailable
    )
  }
  private var route: VoiceASRProviderRoute {
    VoiceASRProviderRoutingPolicy.route(
      settings: capabilitySettings,
      capabilities: capabilities,
      onlineRealtimeAvailable: onlineRealtimeAvailable,
      remoteWhisperAvailable: !verifiedRemoteWhisperNodes.isEmpty
    )
  }
  private var onlineRealtimeASREnabled: Bool {
    VoiceFeatureFlags.isOnlineRealtimeASREnabled()
  }
  private var remoteWhisperNodeEnabled: Bool {
    VoiceFeatureFlags.isRemoteWhisperNodeEnabled()
  }
  private var advancedRecognitionVisible: Bool {
    onlineRealtimeASREnabled || remoteWhisperNodeEnabled
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("voice_asr_provider", "ASR Provider"),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: recognitionPreferenceTitle(settings.asrRecognitionPreference),
            subtitle: recognitionPreferenceSubtitle(settings.asrRecognitionPreference),
            systemImage: "waveform.and.mic",
            tint: SignalASIVoiceProviderFormatter.capabilityTint(route.capability),
            badge: SignalASIVoiceProviderFormatter.capabilityStatus(route.capability, language: interfaceLanguage)
          )
          if advancedRecognitionVisible {
            recognitionSection
          }
          if onlineRealtimeASREnabled {
            onlinePrivacySection
          }
          if remoteWhisperNodeEnabled {
            remoteNodeSection
          }
          deviceCapabilitySection
          if VoiceFeatureFlags.isWhisperPolicyEngineEnabled() {
            runtimePolicySection
          }
          modelSection
          recheckSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .alert(
      t("voice_asr_online_consent_title", "Enable online speech recognition?"),
      isPresented: $showOnlineASRConsent
    ) {
      Button(t("common_cancel", "Cancel"), role: .cancel) {}
      Button(t("common_enable", "Enable")) {
        VoiceFeatureFlags.setOnlineRealtimeASREnabled(true)
        store.updateVoiceSettings {
          $0.onlineAsrAllowed = true
          $0.onlineAsrAudioUploadAllowed = true
        }
        refreshGeneration += 1
      }
    } message: {
      Text(t(
        "voice_asr_online_consent_message",
        "Microphone PCM will be streamed to the configured provider using a short-lived credential."
      ))
    }
  }

  private var recognitionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("voice_asr_recognition_mode_section", "Recognition"))
      SignalASIVoiceProviderMenuRow(
        title: t("voice_asr_recognition_mode_title", "Recognition mode"),
        subtitle: t("voice_asr_recognition_mode_subtitle", "Choose low latency, privacy, or local accuracy"),
        systemImage: "dial.min",
        tint: .purple,
        badge: recognitionPreferenceTitle(settings.asrRecognitionPreference),
        choices: recognitionPreferenceChoices,
        selectedValue: settings.asrRecognitionPreference.rawValue
      ) { value in
        let preference = VoiceRecognitionPreference.normalized(value)
        if preference == .onlineFast {
          VoiceFeatureFlags.setOnlineRealtimeASREnabled(true)
        }
        if preference == .remoteNode {
          VoiceFeatureFlags.setRemoteWhisperNodeEnabled(true)
        }
        store.updateVoiceSettings { $0.setASRRecognitionPreference(preference) }
        refreshGeneration += 1
      }
      SignalASISecurityStatusRow(
        title: t("signalasi.voice.active_route", "Active route"),
        subtitle: route.provider,
        systemImage: "arrow.triangle.branch",
        tint: route.usesFallback ? .orange : .signalASIAccent,
        badge: route.usesFallback
          ? t("signalasi.voice.fallback_route", "Fallback")
          : SignalASIVoiceProviderFormatter.capabilityStatus(route.capability, language: interfaceLanguage)
      )
    }
  }

  private var onlinePrivacySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("voice_asr_online_privacy_section", "Online audio privacy"))
      toggleRow(
        title: t("voice_asr_online_allowed_title", "Online realtime ASR"),
        subtitle: t("voice_asr_online_allowed_subtitle", "When enabled, microphone audio is sent to the selected provider"),
        systemImage: "cloud",
        tint: .blue,
        isOn: onlineConsentGranted
      ) {
        if onlineConsentGranted {
          store.updateVoiceSettings {
            $0.onlineAsrAllowed = false
            $0.onlineAsrAudioUploadAllowed = false
          }
        } else {
          showOnlineASRConsent = true
        }
      }
      toggleRow(
        title: t("voice_asr_wifi_only_title", "Wi-Fi only"),
        subtitle: t("voice_asr_wifi_only_subtitle", "Do not send realtime audio over mobile data"),
        systemImage: "wifi",
        tint: .teal,
        isOn: settings.onlineAsrWifiOnly
      ) {
        store.updateVoiceSettings { $0.onlineAsrWifiOnly.toggle() }
      }
      toggleRow(
        title: t("voice_asr_server_delete_title", "Request server deletion"),
        subtitle: t("voice_asr_server_delete_subtitle", "Ask supported providers to delete session audio and transcripts"),
        systemImage: "shield",
        tint: .signalASIAccent,
        isOn: settings.onlineAsrRequestServerDeletion
      ) {
        store.updateVoiceSettings { $0.onlineAsrRequestServerDeletion.toggle() }
      }
      SignalASISecurityStatusRow(
        title: t("voice_asr_broker_status_title", "Credential service"),
        subtitle: VoiceOnlineRealtimeASRConfiguration.isConfigured
          ? t("voice_asr_broker_configured", "Ephemeral credential broker is configured")
          : t("voice_asr_broker_required", "Configure the realtime ASR credential broker at build time"),
        systemImage: "key.horizontal",
        tint: VoiceOnlineRealtimeASRConfiguration.isConfigured ? .signalASIAccent : .orange,
        badge: VoiceOnlineRealtimeASRConfiguration.isConfigured
          ? t("voice_provider_ready", "Ready")
          : t("voice_provider_unavailable", "Unavailable")
      )
      SignalASISecurityStatusRow(
        title: t("signalasi.voice.network_status", "Network status"),
        subtitle: networkDetail,
        systemImage: "network",
        tint: validatedNetworkAvailable ? .signalASIAccent : .orange,
        badge: validatedNetworkAvailable
          ? t("voice_provider_ready", "Ready")
          : t("voice_provider_network_required", "Network required")
      )
    }
  }

  private var remoteNodeSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("voice_asr_remote_section", "My Desktop accuracy node"))
      toggleRow(
        title: t("voice_asr_remote_allowed_title", "Allow remote accuracy review"),
        subtitle: t(
          "voice_asr_remote_allowed_subtitle",
          "Send encrypted PCM only to a verified paired Desktop, then delete its temporary audio"
        ),
        systemImage: "desktopcomputer",
        tint: .purple,
        isOn: settings.remoteWhisperAllowed
      ) {
        store.updateVoiceSettings {
          $0.remoteWhisperAllowed.toggle()
          if !$0.remoteWhisperAllowed && $0.asrRecognitionPreference == .remoteNode {
            $0.setASRRecognitionPreference(.automatic)
          }
        }
      }
      SignalASISecurityStatusRow(
        title: t("voice_asr_remote_node_title", "Execution device"),
        subtitle: remoteNodeDetail,
        systemImage: "display",
        tint: verifiedRemoteWhisperNodes.isEmpty ? .orange : .signalASIAccent,
        badge: verifiedRemoteWhisperNodes.isEmpty
          ? t("voice_provider_unavailable", "Unavailable")
          : String(verifiedRemoteWhisperNodes.count)
      )
    }
  }

  private var deviceCapabilitySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("voice_provider_device_capabilities", "Device capabilities"))
      ForEach(asrCapabilityIds, id: \.self) { id in
        asrCapabilityRow(capabilities[id])
      }
    }
  }

  private var runtimePolicySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("voice_asr_runtime_mode_section", "Runtime policy"))
      SignalASIVoiceProviderMenuRow(
        title: t("voice_asr_runtime_mode_title", "Model selection"),
        subtitle: t(
          "voice_asr_runtime_mode_subtitle",
          "Automatic uses only models certified for real-time speech on this device."
        ),
        systemImage: "slider.horizontal.3",
        tint: .teal,
        badge: recognitionModeTitle(settings.asrRuntimeMode),
        choices: recognitionModeChoices,
        selectedValue: settings.asrRuntimeMode.rawValue
      ) { value in
        store.updateVoiceSettings { $0.asrRuntimeMode = VoiceWhisperUserVoiceMode.normalized(value) }
      }
    }
  }

  private var modelSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("voice_asr_model_section", "Whisper model"))
      SignalASISecurityNavigationRow(
        title: selectedModel.displayName,
        subtitle: selectedModel.sizeLabel.ifBlank(selectedModel.id),
        systemImage: "square.stack.3d.up",
        tint: .purple,
        badge: t("common_select", "Select")
      ) {
        VoiceWhisperModelSettingsView()
      }
    }
  }

  private var recheckSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("voice_provider_device_check", "Device check"))
      SignalASISecurityActionRow(
        title: t("voice_provider_recheck", "Check again"),
        subtitle: t("voice_provider_recheck_subtitle", "Refresh engine, language, model, permission, and network status"),
        systemImage: "arrow.clockwise",
        tint: .blue,
        badge: t("voice_provider_recheck_action", "Refresh")
      ) {
        refreshGeneration += 1
      }
    }
  }

  @ViewBuilder
  private func asrCapabilityRow(_ capability: VoiceProviderCapability) -> some View {
    let subtitle = asrCapabilityDetail(capability)
    let badge = SignalASIVoiceProviderFormatter.capabilityStatus(capability, language: interfaceLanguage)
    let tint = SignalASIVoiceProviderFormatter.capabilityTint(capability)
    let icon = SignalASIVoiceProviderFormatter.capabilityIcon(capability.id)
    if capability.state == .needsPermission {
      SignalASISecurityActionRow(
        title: SignalASIVoiceProviderFormatter.capabilityTitle(capability.id, language: interfaceLanguage),
        subtitle: subtitle,
        systemImage: icon,
        tint: tint,
        badge: badge
      ) {
        requestMicrophonePermission()
      }
    } else {
      SignalASISecurityStatusRow(
        title: SignalASIVoiceProviderFormatter.capabilityTitle(capability.id, language: interfaceLanguage),
        subtitle: subtitle,
        systemImage: icon,
        tint: tint,
        badge: badge
      )
    }
  }

  private var recognitionPreferenceChoices: [SignalASIVoiceProviderChoice] {
    var preferences: [VoiceRecognitionPreference] = [
      .automatic,
      .onlineFast,
      .localPrivate,
      .localHighAccuracy,
    ]
    if remoteWhisperNodeEnabled && settings.remoteWhisperAllowed && !verifiedRemoteWhisperNodes.isEmpty {
      preferences.append(.remoteNode)
    }
    return preferences.map {
      SignalASIVoiceProviderChoice(value: $0.rawValue, title: recognitionPreferenceTitle($0))
    }
  }

  private var asrCapabilityIds: [VoiceProviderCapabilityId] {
    [.whisperCpp, .androidSystemASR, .androidOfflineASR, .cloudASR]
  }

  private var onlineRealtimeAvailable: Bool {
    VoiceOnlineRealtimeASRConfiguration.isConfigured &&
      VoiceASRProviderRoutingPolicy.onlineAllowed(settings: settings, network: networkProbe)
  }

  private var onlineConsentGranted: Bool {
    settings.onlineAsrAllowed && settings.onlineAsrAudioUploadAllowed
  }

  private var remoteNodeDetail: String {
    guard let node = verifiedRemoteWhisperNodes.first else {
      return t("voice_asr_remote_node_unavailable", "No verified Whisper node is online")
    }
    return "\(node.desktopName) · \(node.activeProfile.modelName)"
  }

  private var verifiedRemoteWhisperNodes: [VoiceRemoteWhisperNodeCapability] {
    _ = refreshGeneration
    return coordinator.verifiedRemoteWhisperNodes
  }

  private var networkDetail: String {
    let transports = networkProbe.transports.joined(separator: ", ").ifBlank("unknown")
    if validatedNetworkAvailable {
      return t("signalasi.voice.network_ready_detail", "Validated network is available") + " / " + transports
    }
    return t("voice_capability_network_required", "Connect to a validated network to use this provider")
  }

  private func asrCapabilityDetail(_ capability: VoiceProviderCapability) -> String {
    if capability.id == .cloudASR && !onlineConsentGranted {
      return t(
        "voice_capability_online_audio_permission",
        "Online ASR is off. Enabling it sends microphone audio to the selected provider."
      )
    }
    return SignalASIVoiceProviderFormatter.capabilityDetail(capability, language: interfaceLanguage)
  }

  private func recognitionModeTitle(_ mode: VoiceWhisperUserVoiceMode) -> String {
    switch mode {
    case .automatic:
      return t("voice_asr_mode_auto", "Automatic")
    case .fast:
      return t("voice_asr_runtime_mode_fast", "Fast")
    case .accurate:
      return t("voice_asr_mode_local_accurate", "Local high accuracy")
    case .privacy:
      return t("voice_asr_mode_local_private", "Local private")
    case .manual:
      return t("voice_asr_runtime_mode_manual", "Selected model")
    }
  }

  private func recognitionPreferenceTitle(_ preference: VoiceRecognitionPreference) -> String {
    switch preference {
    case .automatic:
      return t("voice_asr_mode_auto", "Automatic")
    case .onlineFast:
      return t("voice_asr_mode_online_fast", "Online fast")
    case .localPrivate:
      return t("voice_asr_mode_local_private", "Local private")
    case .localHighAccuracy:
      return t("voice_asr_mode_local_accurate", "Local high accuracy")
    case .remoteNode:
      return t("voice_asr_mode_remote_node", "Remote node")
    }
  }

  private func recognitionPreferenceSubtitle(_ preference: VoiceRecognitionPreference) -> String {
    switch preference {
    case .automatic:
      return t("voice_asr_provider_auto_subtitle", "Use permitted online ASR first, then a ready local model.")
    case .onlineFast:
      return t("voice_asr_online_subtitle", "Prefer low-latency online recognition and fall back to a local model.")
    case .localPrivate:
      return t("voice_asr_local_private_subtitle", "Keep microphone audio on this phone.")
    case .localHighAccuracy:
      return t("voice_asr_local_accurate_subtitle", "Use the most accurate certified local model.")
    case .remoteNode:
      return t("voice_asr_remote_subtitle", "Use a verified paired Desktop accuracy node.")
    }
  }

  private func toggleRow(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    isOn: Bool,
    action: @escaping () -> Void
  ) -> some View {
    SignalASISecurityActionRow(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: isOn ? tint : .orange,
      badge: isOn ? t("common_on", "On") : t("common_off", "Off"),
      action: action
    )
  }

  private func requestMicrophonePermission() {
    #if canImport(AVFoundation)
    AVAudioSession.sharedInstance().requestRecordPermission { _ in
      DispatchQueue.main.async {
        refreshGeneration += 1
      }
    }
    #else
    refreshGeneration += 1
    #endif
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIVoiceTTSProviderView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var refreshGeneration = 0

  private var settings: VoiceSettings { store.voiceSettings.normalized }
  private var networkProbe: AgentMediaNetworkProbe {
    _ = refreshGeneration
    return AgentMediaNetworkDetector.shared.currentProbe
  }
  private var validatedNetworkAvailable: Bool {
    networkProbe.networkPresent && networkProbe.internetCapable && networkProbe.validated
  }
  private var capabilitySettings: VoiceSettings {
    var copy = settings
    copy.preferredLocaleIdentifier = LanguagePolicySettings.resolve(store.languagePolicy.ttsLanguage)
    return copy.normalized
  }
  private var capabilities: VoiceProviderCapabilitySnapshot {
    _ = refreshGeneration
    return VoiceProviderCapabilityDetector.detect(
      settings: capabilitySettings,
      validatedNetworkAvailable: validatedNetworkAvailable
    )
  }
  private var activeTtsCapability: VoiceProviderCapability {
    capabilities[settings.ttsProvider == .system ? .androidSystemTTS : .microsoftEdgeTTS]
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("voice_tts_provider", "TTS Provider"),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: ttsProviderTitle(settings.ttsProvider),
            subtitle: t(
              "voice_tts_provider_subtitle",
              "Choose a provider only after SignalASI verifies it on this device"
            ),
            systemImage: "speaker.wave.2",
            tint: SignalASIVoiceProviderFormatter.capabilityTint(activeTtsCapability),
            badge: SignalASIVoiceProviderFormatter.capabilityStatus(activeTtsCapability, language: interfaceLanguage)
          )
          deviceCapabilitySection
          deviceCheckSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var deviceCapabilitySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("voice_provider_device_capabilities", "Device capabilities"))
      ttsCapabilityRow(provider: .system, capability: capabilities[.androidSystemTTS])
      ttsCapabilityRow(provider: .microsoftEdge, capability: capabilities[.microsoftEdgeTTS])
    }
  }

  private var deviceCheckSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("voice_provider_device_check", "Device check"))
      SignalASIVoiceProviderMenuRow(
        title: t("language_policy_tts_language", "TTS language"),
        subtitle: t("signalasi.voice.tts_language_subtitle", "Language and matching voice for playback"),
        systemImage: "globe",
        tint: .blue,
        badge: voiceLanguageBadge(store.languagePolicy.ttsLanguage),
        choices: voiceLanguageChoices,
        selectedValue: store.languagePolicy.ttsLanguage
      ) { value in
        store.updateLanguagePolicy { $0.ttsLanguage = LanguagePolicySettings.normalizeVoice(value) }
        refreshGeneration += 1
      }
      SignalASISecurityActionRow(
        title: t("voice_provider_recheck", "Check again"),
        subtitle: t("voice_provider_recheck_subtitle", "Refresh engine, language, model, permission, and network status"),
        systemImage: "arrow.clockwise",
        tint: .blue,
        badge: t("voice_provider_recheck_action", "Refresh")
      ) {
        refreshGeneration += 1
      }
    }
  }

  @ViewBuilder
  private func ttsCapabilityRow(provider: VoiceTTSProvider, capability: VoiceProviderCapability) -> some View {
    let selected = settings.ttsProvider == provider
    let action: String = {
      if selected {
        return t("section_current", "Current")
      }
      if capability.ready {
        return t("settings_language_use", "Use")
      }
      return SignalASIVoiceProviderFormatter.capabilityStatus(capability, language: interfaceLanguage)
    }()
    if capability.ready && !selected {
      SignalASISecurityActionRow(
        title: SignalASIVoiceProviderFormatter.capabilityTitle(capability.id, language: interfaceLanguage),
        subtitle: SignalASIVoiceProviderFormatter.capabilityDetail(capability, language: interfaceLanguage),
        systemImage: SignalASIVoiceProviderFormatter.capabilityIcon(capability.id),
        tint: SignalASIVoiceProviderFormatter.capabilityTint(capability),
        badge: action
      ) {
        store.updateVoiceSettings { $0.ttsProvider = provider }
      }
    } else {
      SignalASISecurityStatusRow(
        title: SignalASIVoiceProviderFormatter.capabilityTitle(capability.id, language: interfaceLanguage),
        subtitle: SignalASIVoiceProviderFormatter.capabilityDetail(capability, language: interfaceLanguage),
        systemImage: SignalASIVoiceProviderFormatter.capabilityIcon(capability.id),
        tint: SignalASIVoiceProviderFormatter.capabilityTint(capability),
        badge: action
      )
    }
  }

  private var voiceLanguageChoices: [SignalASIVoiceProviderChoice] {
    LanguagePolicySettings.voiceChoices.map {
      SignalASIVoiceProviderChoice(value: $0, title: voiceLanguageTitle($0))
    }
  }

  private func ttsProviderTitle(_ provider: VoiceTTSProvider) -> String {
    switch provider {
    case .system:
      return t("voice_tts_ios", "iOS System TTS")
    case .microsoftEdge:
      return t("voice_tts_microsoft", "Microsoft Edge Xiaoxiao")
    }
  }

  private func voiceLanguageTitle(_ value: String) -> String {
    switch LanguagePolicySettings.normalizeVoice(value) {
    case LanguagePolicySettings.zhCN:
      return t("signalasi.language.zh_cn", "Simplified Chinese")
    case LanguagePolicySettings.enUS:
      return t("signalasi.language.en_us", "English (United States)")
    case LanguagePolicySettings.zhHK:
      return t("signalasi.language.zh_hk", "Traditional Chinese (Hong Kong)")
    case LanguagePolicySettings.zhTW:
      return t("signalasi.language.zh_tw", "Traditional Chinese (Taiwan)")
    default:
      return t("signalasi.settings_language.auto", "Automatic (follow system)")
    }
  }

  private func voiceLanguageBadge(_ value: String) -> String {
    switch LanguagePolicySettings.normalizeVoice(value) {
    case LanguagePolicySettings.zhCN:
      return t("signalasi.language_policy.zh_cn_short", "zh-CN")
    case LanguagePolicySettings.enUS:
      return t("signalasi.language_policy.en_us_short", "English")
    case LanguagePolicySettings.zhHK:
      return t("signalasi.language_policy.zh_hk_short", "zh-HK")
    case LanguagePolicySettings.zhTW:
      return t("signalasi.language_policy.zh_tw_short", "zh-TW")
    default:
      return t("signalasi.language_policy.auto_short", "Auto")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIVoiceProviderChoice: Identifiable {
  var value: String
  var title: String

  var id: String { value }
}

private struct SignalASIVoiceProviderMenuRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var choices: [SignalASIVoiceProviderChoice]
  var selectedValue: String
  var onSelect: (String) -> Void

  var body: some View {
    Menu {
      ForEach(choices) { choice in
        Button {
          onSelect(choice.value)
        } label: {
          if choice.value == selectedValue {
            Label(choice.title, systemImage: "checkmark")
          } else {
            Text(choice.title)
          }
        }
      }
    } label: {
      SignalASISecurityStatusRow(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge
      )
    }
    .buttonStyle(.plain)
  }
}
