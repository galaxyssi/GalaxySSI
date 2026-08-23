import SwiftUI

struct SignalASIVoiceControlCenterView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  var showsBackButton = true

  private var settings: VoiceSettings {
    store.voiceSettings
  }

  private var capabilities: VoiceProviderCapabilitySnapshot {
    VoiceProviderCapabilityDetector.detect(
      settings: settings,
      validatedNetworkAvailable: false
    )
  }

  private var asrCapability: VoiceProviderCapability {
    asrRoute.capability
  }

  private var asrRoute: VoiceASRProviderRoute {
    VoiceASRProviderRoutingPolicy.route(
      settings: settings,
      capabilities: capabilities,
      remoteWhisperAvailable: !coordinator.verifiedRemoteWhisperNodes.isEmpty
    )
  }

  private var ttsCapability: VoiceProviderCapability {
    switch settings.ttsProvider {
    case .system:
      return capabilities[.androidSystemTTS]
    case .microsoftEdge:
      return capabilities[.microsoftEdgeTTS]
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_voice_title", "Voice & Interaction"),
        leading: {
          if showsBackButton {
            SignalASIBackButton()
          } else {
            Color.clear
          }
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: t("voice_low_power_title", "Low-power Voice Listening"),
            subtitle: t("voice_low_power_subtitle", "Wake, listen, transcribe, route, and speak replies on this device"),
            systemImage: "waveform",
            tint: settings.wakeListeningEnabled ? .signalASIAccent : .signalASIInsightText,
            badge: enabledLabel(settings.wakeListeningEnabled)
          )
          badgeStrip
          listeningSection
          asrSection
          routingSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var badgeStrip: some View {
    HStack(spacing: 8) {
      SignalASIVoiceMetric(
        value: enabledLabel(settings.wakeListeningEnabled),
        label: t("voice_low_power_monitor", "Low-power Monitor"),
        tint: settings.wakeListeningEnabled ? .signalASIAccent : .gray
      )
      SignalASIVoiceMetric(
        value: capabilityLabel(asrCapability),
        label: t("voice_asr_provider", "ASR Provider"),
        tint: capabilityTint(asrCapability)
      )
      SignalASIVoiceMetric(
        value: "TTS",
        label: t("voice_tts_provider", "TTS Provider"),
        tint: capabilityTint(ttsCapability)
      )
    }
  }

  private var listeningSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("voice_section_listening", "Listening"))
      SignalASISecurityNavigationRow(
        title: t("voice_wake_words", "Wake Word"),
        subtitle: settings.wakeWordsText,
        systemImage: "mic",
        tint: .blue,
        badge: ""
      ) {
        VoiceSettingsView()
      }
      SignalASISecurityNavigationRow(
        title: t("voice_wake_engine", "Wake Engine"),
        subtitle: t(settings.wakeProvider.displayTitle, settings.wakeProvider.displayTitle),
        systemImage: "cpu",
        tint: settings.wakeListeningEnabled ? .signalASIAccent : .gray,
        badge: enabledLabel(settings.wakeListeningEnabled)
      ) {
        VoiceSettingsView()
      }
      SignalASIVoiceToggleRow(
        title: t("voice_low_power_monitor", "Low-power Monitor"),
        subtitle: t("voice_low_power_monitor_subtitle", "Listen for the wake phrase without opening a conversation"),
        systemImage: "waveform.circle",
        tint: settings.wakeListeningEnabled ? .signalASIAccent : .gray,
        isOn: settings.wakeListeningEnabled
      ) {
        store.updateVoiceSettings { $0.wakeListeningEnabled.toggle() }
      }
    }
  }

  private var asrSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("voice_section_asr", "ASR"))
      SignalASISecurityNavigationRow(
        title: t("voice_asr_provider", "ASR Provider"),
        subtitle: asrRoute.provider,
        systemImage: "waveform",
        tint: capabilityTint(asrCapability),
        badge: capabilityLabel(asrCapability)
      ) {
        SignalASIVoiceASRProviderView()
      }
      SignalASISecurityNavigationRow(
        title: t("voice_tts_provider", "TTS Provider"),
        subtitle: t(settings.ttsProvider.displayTitle, settings.ttsProvider.displayTitle),
        systemImage: "speaker.wave.2",
        tint: capabilityTint(ttsCapability),
        badge: capabilityLabel(ttsCapability)
      ) {
        VoiceSettingsView()
      }
    }
  }

  private var routingSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("voice_section_target", "Conversation Target"))
      SignalASISecurityNavigationRow(
        title: t("voice_routing_mode", "Voice Routing"),
        subtitle: t("voice_routing_mode_subtitle", "Choose whether spoken goals run through Native Agent or go directly to a chat contact"),
        systemImage: "arrow.triangle.branch",
        tint: .blue,
        badge: t(settings.routingMode.displayTitle, settings.routingMode.displayTitle)
      ) {
        VoiceSettingsView()
      }
      SignalASISecurityNavigationRow(
        title: t("voice_settings_title", "Voice Settings"),
        subtitle: t("voice_settings_subtitle", "Configure wake, ASR, TTS, locale, routing, and recording"),
        systemImage: "slider.horizontal.3",
        tint: .signalASIInsightText,
        badge: t("common_view", "View")
      ) {
        VoiceSettingsView()
      }
    }
  }

  private func enabledLabel(_ value: Bool) -> String {
    t(value ? "status_enabled" : "common_off", value ? "Enabled" : "Off")
  }

  private func capabilityLabel(_ capability: VoiceProviderCapability) -> String {
    switch capability.state {
    case .ready:
      return t("signalasi.status.ready", "Ready")
    case .checking:
      return t("voice_capability_checking", "Checking")
    case .needsPermission:
      return t("signalasi.permission.needs_setup", "Needs setup")
    case .needsDownload:
      return t("voice_capability_needs_download", "Download")
    case .needsNetwork:
      return t("voice_capability_needs_network", "Network")
    case .unavailable:
      return t("signalasi.status.not_available", "Unavailable")
    }
  }

  private func capabilityTint(_ capability: VoiceProviderCapability) -> Color {
    switch capability.state {
    case .ready:
      return .signalASIAccent
    case .checking:
      return .blue
    case .needsPermission, .needsDownload, .needsNetwork:
      return .orange
    case .unavailable:
      return .gray
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIVoiceMetric: View {
  var value: String
  var label: String
  var tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(value)
        .font(.system(size: 17, weight: .bold))
        .foregroundColor(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      Text(label)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.signalASITextSecondary)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    .padding(.horizontal, 10)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SignalASIVoiceToggleRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var isOn: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
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
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Text(subtitle)
            .font(.system(size: 13))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(2)
        }
        Spacer(minLength: 8)
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 20, weight: .semibold))
          .foregroundColor(isOn ? .signalASIAccent : .signalASITextSecondary)
      }
      .padding(12)
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}
