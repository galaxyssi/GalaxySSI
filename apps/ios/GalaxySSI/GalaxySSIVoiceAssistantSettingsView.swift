import SwiftUI

struct GalaxySSIVoiceAssistantSettingsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore

  private var settings: VoiceSettings { store.voiceSettings }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("voice_settings_title", "Voice Wake & ASR/TTS"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t("voice_low_power_title", "Low-power Voice Listening"),
            subtitle: t(
              "voice_low_power_subtitle",
              "After wake-up, play the Xiaoxiao welcome voice and keep listening through ASR."
            ),
            systemImage: "waveform",
            tint: settings.wakeListeningEnabled ? .galaxySSIAccent : .orange,
            badge: onOff(settings.wakeListeningEnabled)
          )

          liveHealthSection
          listeningSection
          asrSection
          ttsSection
          targetSection
          recorderSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var liveHealthSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("voice_health_section", "Live Health"))
      GalaxySSISecurityStatusRow(
        title: t("voice_health_wake", "Wake Word"),
        subtitle: settings.wakeListeningEnabled
          ? t("voice_health_active_detail_ios", "Low-power wake monitoring is active for the voice page")
          : t("voice_health_disabled_detail", "Low-power wake monitoring is turned off"),
        systemImage: "mic.circle",
        tint: healthTint(settings.wakeListeningEnabled),
        badge: settings.wakeListeningEnabled
          ? t("voice_health_active", "Active")
          : t("voice_health_disabled", "Disabled")
      )
      GalaxySSISecurityStatusRow(
        title: t("voice_health_asr", "Speech Recognition"),
        subtitle: asrProviderSummary,
        systemImage: "waveform.and.mic",
        tint: healthTint(settings.speechRecognitionEnabled),
        badge: settings.speechRecognitionEnabled
          ? t("voice_health_ready", "Ready")
          : t("voice_health_disabled", "Disabled")
      )
      GalaxySSISecurityStatusRow(
        title: t("voice_health_tts", "Speech Synthesis"),
        subtitle: ttsProviderSummary,
        systemImage: "speaker.wave.2",
        tint: healthTint(settings.textToSpeechEnabled && settings.speakReplies),
        badge: settings.textToSpeechEnabled && settings.speakReplies
          ? t("voice_health_ready", "Ready")
          : t("voice_health_disabled", "Disabled")
      )
    }
  }

  private var listeningSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("voice_section_listening", "Listening"))
      toggleRow(
        title: t("voice_low_power_monitor", "Low-power Listening"),
        subtitle: t("voice_low_power_monitor_subtitle", "Keep listening for wake words on the voice page"),
        systemImage: "mic",
        tint: .galaxySSIAccent,
        isOn: settings.wakeListeningEnabled
      ) {
        store.updateVoiceSettings { $0.wakeListeningEnabled.toggle() }
      }
      GalaxySSIVoiceMenuRow(
        title: t("voice_wake_engine", "Wake Engine"),
        subtitle: wakeProviderTitle(settings.wakeProvider),
        systemImage: "cpu",
        tint: .purple,
        badge: t("common_select", "Select"),
        choices: wakeProviderChoices,
        selectedValue: settings.wakeProvider.rawValue
      ) { value in
        store.updateVoiceSettings { $0.wakeProvider = VoiceWakeProvider.normalized(value) }
      }
      GalaxySSISecurityStatusRow(
        title: t("voice_wake_words", "Wake Word"),
        subtitle: settings.wakeWordsText,
        systemImage: "text.quote",
        tint: .blue,
        badge: ""
      )
      GalaxySSIVoiceMenuRow(
        title: t("voice_openwakeword_model", "openWakeWord Model"),
        subtitle: settings.wakeModel,
        systemImage: "link",
        tint: .teal,
        badge: t("common_select", "Select"),
        choices: VoiceSettings.supportedWakeModels.map {
          GalaxySSIVoiceChoice(value: $0, title: $0)
        },
        selectedValue: settings.wakeModel
      ) { value in
        store.updateVoiceSettings { $0.wakeModel = value }
      }
      GalaxySSIVoiceSliderRow(
        title: t("voice_wake_threshold", "Wake Threshold"),
        subtitle: t("galaxyssi.voice.threshold_subtitle", "Higher values reduce accidental wake-ups"),
        systemImage: "slider.horizontal.3",
        tint: .orange,
        badge: settings.wakeThreshold.formatted(.number.precision(.fractionLength(2))),
        value: Binding(
          get: { settings.wakeThreshold },
          set: { value in store.updateVoiceSettings { $0.wakeThreshold = value } }
        )
      )
    }
  }

  private var asrSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("voice_section_asr", "ASR"))
      toggleRow(
        title: t("galaxyssi.voice.speech_recognition", "Speech recognition"),
        subtitle: t("galaxyssi.voice.speech_recognition_subtitle", "Turn spoken input into transcripts"),
        systemImage: "waveform.and.mic",
        tint: .galaxySSIAccent,
        isOn: settings.speechRecognitionEnabled
      ) {
        store.updateVoiceSettings { $0.speechRecognitionEnabled.toggle() }
      }
      GalaxySSISecurityNavigationRow(
        title: t("voice_asr_provider", "ASR Provider"),
        subtitle: asrProviderSummary,
        systemImage: "cpu",
        tint: .purple,
        badge: t("common_select", "Select")
      ) {
        GalaxySSIVoiceASRProviderView()
      }
      GalaxySSIVoiceMenuRow(
        title: t("voice_asr_language", "ASR Language"),
        subtitle: t("galaxyssi.voice.asr_language_subtitle", "Language used by speech recognition"),
        systemImage: "globe",
        tint: .blue,
        badge: voiceLanguageBadge(store.languagePolicy.asrLanguage),
        choices: voiceLanguageChoices,
        selectedValue: store.languagePolicy.asrLanguage
      ) { value in
        store.updateLanguagePolicy { $0.asrLanguage = value }
      }
      toggleRow(
        title: t("galaxyssi.voice.auto_send_transcripts", "Auto-send transcripts"),
        subtitle: t("galaxyssi.voice.auto_send_transcripts_subtitle", "Send recognized speech without manual review"),
        systemImage: "paperplane",
        tint: .orange,
        isOn: settings.autoSendTranscripts
      ) {
        store.updateVoiceSettings { $0.autoSendTranscripts.toggle() }
      }
    }
  }

  private var ttsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("voice_section_tts", "TTS"))
      toggleRow(
        title: t("voice_speak_replies", "Speak Replies"),
        subtitle: t("voice_speak_replies_subtitle", "Use TTS to play Agent replies automatically"),
        systemImage: "speaker.wave.2",
        tint: .galaxySSIAccent,
        isOn: settings.speakReplies
      ) {
        store.updateVoiceSettings { $0.speakReplies.toggle() }
      }
      toggleRow(
        title: t("galaxyssi.voice.text_to_speech", "Text to speech"),
        subtitle: t("galaxyssi.voice.text_to_speech_subtitle", "Enable speech playback for voice sessions"),
        systemImage: "speaker",
        tint: .blue,
        isOn: settings.textToSpeechEnabled
      ) {
        store.updateVoiceSettings { $0.textToSpeechEnabled.toggle() }
      }
      GalaxySSISecurityNavigationRow(
        title: t("voice_tts_provider", "TTS Provider"),
        subtitle: ttsProviderSummary,
        systemImage: "speaker.wave.2",
        tint: .orange,
        badge: GalaxySSIVoiceProviderFormatter.capabilityStatus(activeTtsCapability, language: interfaceLanguage)
      ) {
        GalaxySSIVoiceTTSProviderView()
      }
      GalaxySSIVoiceMenuRow(
        title: t("language_policy_tts_language", "TTS language"),
        subtitle: t("galaxyssi.voice.tts_language_subtitle", "Language and matching voice for playback"),
        systemImage: "globe",
        tint: .blue,
        badge: voiceLanguageBadge(store.languagePolicy.ttsLanguage),
        choices: voiceLanguageChoices,
        selectedValue: store.languagePolicy.ttsLanguage
      ) { value in
        store.updateLanguagePolicy { $0.ttsLanguage = value }
      }
      GalaxySSIVoiceMenuRow(
        title: t("voice_microsoft_voice", "Microsoft Voice"),
        subtitle: t("galaxyssi.voice.microsoft_voice_subtitle", "Select a Microsoft Xiaoxiao voice for Edge TTS"),
        systemImage: "person.wave.2",
        tint: .purple,
        badge: microsoftVoiceTitle(settings.microsoftVoice),
        choices: microsoftVoiceChoices,
        selectedValue: settings.microsoftVoice
      ) { value in
        store.updateVoiceSettings {
          $0.ttsProvider = .microsoftEdge
          $0.microsoftVoice = MicrosoftTTSVoiceCatalog.canonical(value)
        }
        store.updateLanguagePolicy { $0.ttsLanguage = LanguagePolicySettings.zhCN }
      }
      GalaxySSIVoiceTextFieldRow(
        title: t("voice_welcome_text", "Welcome Text"),
        subtitle: t("galaxyssi.voice.welcome_subtitle", "Spoken after the wake phrase succeeds"),
        systemImage: "quote.bubble",
        tint: .teal,
        badge: t("common_edit", "Edit"),
        text: Binding(
          get: { settings.welcomeText },
          set: { value in store.updateVoiceSettings { $0.welcomeText = value } }
        )
      )
    }
  }

  private var targetSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("voice_section_target", "Conversation Target"))
      GalaxySSIVoiceMenuRow(
        title: t("voice_routing_mode", "Voice Routing"),
        subtitle: t(
          "voice_routing_mode_subtitle",
          "Choose whether spoken goals run through Native Agent or go directly to a chat contact"
        ),
        systemImage: "arrow.triangle.branch",
        tint: .galaxySSIAccent,
        badge: routingModeTitle(settings.routingMode),
        choices: routingModeChoices,
        selectedValue: settings.routingMode.rawValue
      ) { value in
        store.updateVoiceSettings { $0.routingMode = VoiceRoutingMode(rawValue: value) ?? .nativeAgent }
      }
      GalaxySSIVoiceMenuRow(
        title: settings.routingMode == .nativeAgent
          ? t("voice_stt_target", "Agent target")
          : t("voice_default_target", "Send to by Default"),
        subtitle: targetContactLabel,
        systemImage: "person.crop.circle",
        tint: .blue,
        badge: t("common_select", "Select"),
        choices: targetContactChoices,
        selectedValue: settings.targetContactId
      ) { value in
        store.updateVoiceSettings { $0.targetContactId = value }
      }
    }
  }

  private var recorderSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.voice.session_section", "Voice Session"))
      GalaxySSISecurityNavigationRow(
        title: t("galaxyssi.voice.recorder", "Hold to Talk"),
        subtitle: t("galaxyssi.voice.recorder_subtitle", "Open the live recorder and send transcripts"),
        systemImage: "mic.circle",
        tint: .galaxySSIAccent,
        badge: t("common_view", "View")
      ) {
        VoiceSettingsView()
      }
    }
  }

  private var asrProviderSummary: String {
    let model = VoiceWhisperModelCatalog.model(settings.asrModelId).displayName
    switch settings.asrRecognitionPreference {
    case .automatic:
      return "\(t("voice_asr_provider_auto", "Automatic")) / \(model)"
    case .onlineFast:
      return t("voice_asr_mode_online_fast", "Online fast")
    case .localPrivate:
      return "\(t("voice_asr_mode_local_private", "Local private")) / \(model)"
    case .localHighAccuracy:
      return "\(t("voice_asr_mode_local_accurate", "Local high accuracy")) / \(model)"
    case .remoteNode:
      return t("voice_asr_mode_remote_node", "Remote node")
    }
  }

  private var ttsProviderSummary: String {
    switch settings.ttsProvider {
    case .system:
      return t("voice_tts_ios", "iOS System TTS")
    case .microsoftEdge:
      return "\(t("voice_tts_microsoft", "Microsoft Edge Xiaoxiao")) / \(settings.microsoftVoice)"
    }
  }

  private var activeTtsCapability: VoiceProviderCapability {
    let probe = AgentMediaNetworkDetector.shared.currentProbe
    var capabilitySettings = settings.normalized
    capabilitySettings.preferredLocaleIdentifier = LanguagePolicySettings.resolve(store.languagePolicy.ttsLanguage)
    let capabilities = VoiceProviderCapabilityDetector.detect(
      settings: capabilitySettings,
      validatedNetworkAvailable: probe.networkPresent && probe.internetCapable && probe.validated
    )
    return capabilities[
      settings.ttsProvider == .system ? .androidSystemTTS : .microsoftEdgeTTS
    ]
  }

  private var wakeProviderChoices: [GalaxySSIVoiceChoice] {
    [
      GalaxySSIVoiceChoice(
        value: VoiceWakeProvider.openWakeWord.rawValue,
        title: t("voice_wake_engine_openwakeword", "openWakeWord Local Offline")
      ),
      GalaxySSIVoiceChoice(
        value: VoiceWakeProvider.androidASR.rawValue,
        title: t("voice_wake_engine_ios_speech", "iOS Speech wake")
      )
    ]
  }

  private var routingModeChoices: [GalaxySSIVoiceChoice] {
    [
      GalaxySSIVoiceChoice(
        value: VoiceRoutingMode.nativeAgent.rawValue,
        title: t("voice_routing_native_agent", "Native Agent")
      ),
      GalaxySSIVoiceChoice(
        value: VoiceRoutingMode.contact.rawValue,
        title: t("voice_routing_contact", "Chat Contact")
      )
    ]
  }

  private var voiceLanguageChoices: [GalaxySSIVoiceChoice] {
    LanguagePolicySettings.voiceChoices.map {
      GalaxySSIVoiceChoice(value: $0, title: voiceLanguageTitle($0))
    }
  }

  private var microsoftVoiceChoices: [GalaxySSIVoiceChoice] {
    MicrosoftTTSVoiceCatalog.voices.map {
      GalaxySSIVoiceChoice(value: $0, title: microsoftVoiceTitle($0), subtitle: $0)
    }
  }

  private func microsoftVoiceTitle(_ voiceId: String) -> String {
    switch MicrosoftTTSVoiceCatalog.canonical(voiceId) {
    case MicrosoftTTSVoiceCatalog.xiaoxiaoDragonHDFlash:
      return t("voice_microsoft_xiaoxiao_dragon_hd_flash", "Xiaoxiao Dragon HD Flash")
    case MicrosoftTTSVoiceCatalog.xiaoxiao2DragonHDFlash:
      return t("voice_microsoft_xiaoxiao2_dragon_hd_flash", "Xiaoxiao 2 Dragon HD Flash")
    default:
      return t("voice_microsoft_xiaoxiao", "Xiaoxiao Neural")
    }
  }

  private var targetContactChoices: [GalaxySSIVoiceChoice] {
    let contacts = store.visibleContacts
    guard !contacts.isEmpty else {
      return [GalaxySSIVoiceChoice(value: settings.targetContactId, title: targetContactLabel)]
    }
    return contacts.map {
      GalaxySSIVoiceChoice(value: $0.id, title: $0.displayName, subtitle: $0.id)
    }
  }

  private var targetContactLabel: String {
    store.visibleContacts.first { $0.id == settings.targetContactId }?.displayName ??
      settings.targetContactId.ifBlank("hermes")
  }

  private func toggleRow(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    isOn: Bool,
    action: @escaping () -> Void
  ) -> some View {
    GalaxySSISecurityActionRow(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: isOn ? tint : .orange,
      badge: onOff(isOn),
      action: action
    )
  }

  private func wakeProviderTitle(_ provider: VoiceWakeProvider) -> String {
    switch provider {
    case .openWakeWord:
      return t("voice_wake_engine_openwakeword", "openWakeWord Local Offline")
    case .androidASR:
      return t("voice_wake_engine_ios_speech", "iOS Speech wake")
    }
  }

  private func routingModeTitle(_ mode: VoiceRoutingMode) -> String {
    switch mode {
    case .nativeAgent:
      return t("voice_routing_native_agent", "Native Agent")
    case .contact:
      return t("voice_routing_contact", "Chat Contact")
    }
  }

  private func voiceLanguageTitle(_ value: String) -> String {
    switch LanguagePolicySettings.normalizeVoice(value) {
    case LanguagePolicySettings.zhCN:
      return t("galaxyssi.language.zh_cn", "Simplified Chinese")
    case LanguagePolicySettings.enUS:
      return t("galaxyssi.language.en_us", "English (United States)")
    case LanguagePolicySettings.zhHK:
      return t("galaxyssi.language.zh_hk", "Traditional Chinese (Hong Kong)")
    case LanguagePolicySettings.zhTW:
      return t("galaxyssi.language.zh_tw", "Traditional Chinese (Taiwan)")
    default:
      return t("galaxyssi.settings_language.auto", "Automatic (follow system)")
    }
  }

  private func voiceLanguageBadge(_ value: String) -> String {
    switch LanguagePolicySettings.normalizeVoice(value) {
    case LanguagePolicySettings.zhCN:
      return t("galaxyssi.language_policy.zh_cn_short", "zh-CN")
    case LanguagePolicySettings.enUS:
      return t("galaxyssi.language_policy.en_us_short", "English")
    case LanguagePolicySettings.zhHK:
      return t("galaxyssi.language_policy.zh_hk_short", "zh-HK")
    case LanguagePolicySettings.zhTW:
      return t("galaxyssi.language_policy.zh_tw_short", "zh-TW")
    default:
      return t("galaxyssi.language_policy.auto_short", "Auto")
    }
  }

  private func healthTint(_ enabled: Bool) -> Color {
    enabled ? .galaxySSIAccent : .orange
  }

  private func onOff(_ enabled: Bool) -> String {
    enabled ? t("common_on", "On") : t("common_off", "Off")
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIVoiceChoice: Identifiable {
  var value: String
  var title: String
  var subtitle: String = ""

  var id: String { value }
}

private struct GalaxySSIVoiceMenuRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var choices: [GalaxySSIVoiceChoice]
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
      GalaxySSIVoiceRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        showsDisclosure: true
      )
    }
    .buttonStyle(.plain)
  }
}

private struct GalaxySSIVoiceTextFieldRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  @Binding var text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSIVoiceRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        showsDisclosure: false
      )
      TextField("", text: $text)
        .font(.system(size: 14))
        .foregroundColor(.galaxySSITextPrimary)
        .textInputAutocapitalization(.sentences)
        .disableAutocorrection(true)
        .padding(.horizontal, 12)
        .frame(minHeight: 42)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }
}

private struct GalaxySSIVoiceSliderRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  @Binding var value: Double

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSIVoiceRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        showsDisclosure: false
      )
      Slider(value: $value, in: 0.01...0.99)
        .tint(tint)
        .padding(.horizontal, 12)
        .frame(minHeight: 42)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }
}

private struct GalaxySSIVoiceRowContent: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var showsDisclosure: Bool

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 42, height: 42)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      if !badge.isEmpty {
        Text(badge)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(tint)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .padding(.horizontal, 8)
          .frame(minHeight: 28)
          .background(tint.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      if showsDisclosure {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
