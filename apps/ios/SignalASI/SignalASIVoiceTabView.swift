import Foundation
import SwiftUI

struct SignalASIVoiceTabView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @StateObject private var holdToTalk = SignalASIAgentHoldToTalkController()
  @State private var voiceState = VoiceInteractionCoordinatorRegistry.coordinator.snapshot()
  @State private var observerId = ""
  @State private var submitStatus = ""

  private var settings: VoiceSettings { store.voiceSettings }

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          wakeSurface
          if isVoiceProcessing {
            voiceProcessingStrip(title: voiceProcessingTitle, subtitle: voiceProcessingSubtitle)
          } else if !submitStatus.isEmpty || !holdToTalk.statusMessage.isEmpty {
            statusStrip
          }
          liveTranscriptSection
          quickControlsSection
          liveHealthSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
      .background(Color.signalASIPageBackground.ignoresSafeArea())
      .navigationBarHidden(true)
      .onAppear(perform: startObserving)
      .onDisappear(perform: stopObserving)
    }
    .navigationViewStyle(StackNavigationViewStyle())
  }

  private var wakeSurface: some View {
    VStack(spacing: 18) {
      HStack(spacing: 10) {
        wakeStatusPill
        Spacer(minLength: 8)
        NavigationLink(destination: SignalASIVoiceAssistantSettingsView()) {
          Image(systemName: "gearshape.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 40, height: 40)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(t("voice_settings_title", "Voice Wake & ASR/TTS")))
      }

      SignalASIVoiceWakeOrb(
        isActive: settings.wakeListeningEnabled || holdToTalk.isRecording,
        isRecording: holdToTalk.isRecording
      )

      VStack(spacing: 7) {
        Text(settings.wakeListeningEnabled
          ? t("voice_status_low_power", "Low-power listening")
          : t("voice_status_disabled", "Voice wake is off"))
          .font(.system(size: 24, weight: .bold))
          .foregroundColor(.white)
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .minimumScaleFactor(0.78)

        Text(settings.wakeListeningEnabled
          ? t("voice_hint_wake", "Say \"hello\" to start talking")
          : t("voice_status_disabled_detail", "Enable it in Settings > Voice Wake & ASR/TTS"))
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(Color.white.opacity(0.82))
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }

      holdToTalkSurface
      wakeToggleButton
    }
    .padding(16)
    .frame(maxWidth: .infinity, minHeight: 430)
    .background(
      LinearGradient(
        colors: [
          Color(red: 0.01, green: 0.03, blue: 0.05),
          Color(red: 0.02, green: 0.08, blue: 0.11),
          Color(red: 0.03, green: 0.13, blue: 0.16),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color(red: 0.10, green: 0.84, blue: 0.82).opacity(0.38), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var wakeStatusPill: some View {
    HStack(spacing: 7) {
      Circle()
        .fill(settings.wakeListeningEnabled ? Color.signalASIAccent : Color.orange)
        .frame(width: 8, height: 8)
      Text(settings.wakeListeningEnabled
        ? t("voice_status_low_power", "Low-power listening")
        : t("common_off", "Off"))
        .font(.system(size: 13, weight: .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }
    .foregroundColor(.white)
    .padding(.horizontal, 12)
    .frame(minHeight: 34)
    .background(Color.white.opacity(0.12))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var holdToTalkSurface: some View {
    VStack(spacing: 8) {
      if holdToTalk.isPending {
        Text(t("signalasi.voice.preparing_title", "Preparing voice input"))
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.78)
        AgentVoiceProcessingIndicator(
          title: t("signalasi.voice.preparing_title", "Preparing voice input"),
          subtitle: t("signalasi.voice.preparing_subtitle", "Requesting microphone and speech recognition access.")
        )
        .padding(.horizontal, 8)
      } else if holdToTalk.isRecording {
        Text(holdToTalk.cancelPending
          ? t("voice_release_to_cancel", "Release to cancel")
          : t("agent_voice_recording_hint", "Release to send / Swipe up to cancel"))
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.78)
        SignalASIVoiceInlineWaveform(phase: holdToTalk.waveformPhase, cancelPending: holdToTalk.cancelPending)
          .frame(height: 28)
        Text(holdToTalk.transcript.ifBlank(holdToTalk.elapsedLabel))
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(Color.white.opacity(0.86))
          .lineLimit(1)
          .truncationMode(.head)
      } else {
        Label(t("signalasi.voice.recorder", "Hold to Talk"), systemImage: "mic.fill")
          .font(.system(size: 17, weight: .bold))
          .foregroundColor(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.78)
        Text(t("signalasi.voice.recorder_subtitle", "Open live recording and send transcribed text"))
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(Color.white.opacity(0.72))
          .lineLimit(2)
          .multilineTextAlignment(.center)
      }
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, minHeight: 76)
    .background(holdToTalk.cancelPending ? Color.red.opacity(0.22) : Color.white.opacity(0.11))
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.white.opacity(0.22), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .contentShape(Rectangle())
    .gesture(holdToTalkGesture)
    .accessibilityLabel(Text(t("signalasi.voice.recorder", "Hold to Talk")))
  }

  private var wakeToggleButton: some View {
    Button {
      store.updateVoiceSettings { $0.wakeListeningEnabled.toggle() }
    } label: {
      HStack(spacing: 8) {
        Image(systemName: settings.wakeListeningEnabled ? "pause.circle.fill" : "play.circle.fill")
          .font(.system(size: 20, weight: .semibold))
        Text(settings.wakeListeningEnabled
          ? t("signalasi.voice.turn_off_wake", "Turn off voice wake")
          : t("signalasi.voice.turn_on_wake", "Turn on low-power listening"))
          .font(.system(size: 15, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.72)
      }
      .foregroundColor(.white)
      .frame(maxWidth: .infinity, minHeight: 46)
      .background(settings.wakeListeningEnabled ? Color.white.opacity(0.13) : Color.signalASIAccent)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private var statusStrip: some View {
    Text(submitStatus.ifBlank(holdToTalk.statusMessage))
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.signalASITextSecondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func voiceProcessingStrip(title: String, subtitle: String) -> some View {
    AgentVoiceProcessingIndicator(title: title, subtitle: subtitle)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var isVoiceProcessing: Bool {
    switch voiceState.phase {
    case .finalizingASR, .routing, .executingLocalAction,
         .waitingModelFirstToken, .startingAgent, .agentRunning:
      return true
    default:
      return false
    }
  }

  private var voiceProcessingTitle: String {
    switch voiceState.phase {
    case .finalizingASR:
      return t("signalasi.voice.processing_transcribing", "Recognizing voice")
    case .routing:
      return t("signalasi.voice.processing_routing", "Routing voice task")
    case .executingLocalAction:
      return t("signalasi.voice.processing_local_action", "Running phone action")
    case .waitingModelFirstToken:
      return t("signalasi.voice.processing_model", "Waiting for model")
    case .startingAgent, .agentRunning:
      return t("signalasi.voice.processing_agent", "Waiting for Agent")
    default:
      return t("signalasi.voice.processing_title", "Processing voice input")
    }
  }

  private var voiceProcessingSubtitle: String {
    switch voiceState.phase {
    case .finalizingASR:
      return t("signalasi.voice.processing_transcribing_detail", "Finalizing the local transcript.")
    case .routing:
      return t("signalasi.voice.processing_routing_detail", "Selecting the configured voice destination.")
    case .executingLocalAction:
      return t("signalasi.voice.processing_local_action_detail", "The phone Agent is executing the requested action.")
    case .waitingModelFirstToken:
      return t("signalasi.voice.processing_model_detail", "The selected model is preparing its first response.")
    case .startingAgent, .agentRunning:
      return t("signalasi.voice.processing_agent_detail", "The selected Agent is working on the request.")
    default:
      return t("signalasi.voice.processing_detail", "Voice input is being prepared.")
    }
  }

  private var liveTranscriptSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.voice.live_transcript", "Live Transcript"))
      SignalASISecurityStatusRow(
        title: t("signalasi.voice.phase", "Phase"),
        subtitle: visibleTranscript.ifBlank(t("signalasi.voice.no_live_transcript", "Voice activity appears here after wake or recording.")),
        systemImage: "text.bubble",
        tint: phaseTint,
        badge: phaseLabel(voiceState.phase)
      )
    }
  }

  private var quickControlsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.voice.quick_controls", "Quick Controls"))
      SignalASISecurityNavigationRow(
        title: t("cc_voice_title", "Voice & Interaction"),
        subtitle: t("cc_voice_subtitle", "Wake word, ASR, TTS, and task routing"),
        systemImage: "waveform",
        tint: .signalASIAccent,
        badge: t("common_view", "View")
      ) {
        SignalASIVoiceControlCenterView()
      }
      SignalASISecurityNavigationRow(
        title: t("voice_settings_title", "Voice Wake & ASR/TTS"),
        subtitle: settings.wakeWordsText,
        systemImage: "slider.horizontal.3",
        tint: .blue,
        badge: onOff(settings.wakeListeningEnabled)
      ) {
        SignalASIVoiceAssistantSettingsView()
      }
      SignalASISecurityNavigationRow(
        title: t("signalasi.advanced.voice_models", "Voice Models"),
        subtitle: VoiceWhisperModelCatalog.model(settings.asrModelId).displayName,
        systemImage: "cpu",
        tint: .purple,
        badge: t("common_view", "View")
      ) {
        VoiceWhisperModelSettingsView()
      }
    }
  }

  private var liveHealthSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("voice_health_section", "Live Health"))
      SignalASISecurityStatusRow(
        title: t("voice_health_wake", "Wake Word"),
        subtitle: settings.wakeWordsText,
        systemImage: "mic.circle",
        tint: settings.wakeListeningEnabled ? .signalASIAccent : .gray,
        badge: onOff(settings.wakeListeningEnabled)
      )
      SignalASISecurityStatusRow(
        title: t("voice_health_asr", "Speech Recognition"),
        subtitle: VoiceWhisperModelCatalog.model(settings.asrModelId).displayName,
        systemImage: "waveform.and.mic",
        tint: settings.speechRecognitionEnabled ? .signalASIAccent : .gray,
        badge: onOff(settings.speechRecognitionEnabled)
      )
      SignalASISecurityStatusRow(
        title: t("voice_health_tts", "Speech Synthesis"),
        subtitle: t(settings.ttsProvider.displayTitle, settings.ttsProvider.displayTitle),
        systemImage: "speaker.wave.2",
        tint: settings.textToSpeechEnabled && settings.speakReplies ? .signalASIAccent : .gray,
        badge: onOff(settings.textToSpeechEnabled && settings.speakReplies)
      )
      SignalASISecurityStatusRow(
        title: t("signalasi.voice.target", "Target"),
        subtitle: voiceTargetContact.displayName,
        systemImage: "arrow.triangle.branch",
        tint: .blue,
        badge: routingLabel
      )
      SignalASISecurityStatusRow(
        title: t("signalasi.voice.language", "Language"),
        subtitle: languageFormatter.summary(
          policy: store.languagePolicy,
          asrLocaleIdentifier: settings.preferredLocaleIdentifier
        ),
        systemImage: "globe",
        tint: .signalASIInsightText,
        badge: languageFormatter.statusBadge(for: store.languagePolicy)
      )
    }
  }

  private var holdToTalkGesture: some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        holdToTalk.dragChanged(
          translation: value.translation,
          settings: settings,
          messages: holdToTalkMessages,
          onStart: {
            submitStatus = ""
          },
          onFinish: submitVoiceTranscript
        )
      }
      .onEnded { value in
        holdToTalk.dragEnded(translation: value.translation)
      }
  }

  private var holdToTalkMessages: SignalASIAgentHoldToTalkMessages {
    SignalASIAgentHoldToTalkMessages(
      permissionDenied: t("signalasi.voice.permission_missing", "Microphone or speech permission is missing."),
      speechDisabled: t("signalasi.voice.speech_disabled", "Speech recognition is turned off."),
      speechUnavailable: t("signalasi.voice.speech_unavailable", "Speech recognition could not start."),
      noSpeech: t("voice_no_speech", "No speech captured."),
      tooShort: t("voice_too_short", "Hold a little longer."),
      cancelled: t("voice_cancelled", "Voice cancelled.")
    )
  }

  private var visibleTranscript: String {
    (voiceState.correctedText ?? "")
      .ifBlank(voiceState.finalText ?? "")
      .ifBlank(voiceState.stableText)
      .ifBlank(voiceState.partialText)
  }

  private var phaseTint: Color {
    switch voiceState.phase {
    case .idle, .completed, .cancelled:
      return .gray
    case .failed:
      return .orange
    case .playingTTS, .streamingModelText, .agentRunning:
      return .signalASIAccent
    default:
      return .blue
    }
  }

  private var routingLabel: String {
    switch settings.routingMode {
    case .nativeAgent:
      return t("voice_routing_native_agent", "Native Agent")
    case .contact:
      return t("voice_routing_contact", "Chat Contact")
    }
  }

  private var languageFormatter: SignalASILanguagePolicyFormatter {
    SignalASILanguagePolicyFormatter { key, fallback in
      t(key, fallback)
    }
  }

  private var voiceTargetContact: SignalASIContact {
    let targetId = settings.routingMode == .nativeAgent ? "hermes" : settings.targetContactId
    return store.visibleContacts.first { $0.id == targetId } ??
      store.visibleContacts.first { $0.id == settings.targetContactId } ??
      store.visibleContacts.first { $0.id == "hermes" } ??
      SignalASIContact.hermes()
  }

  private func submitVoiceTranscript(_ text: String) {
    let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanText.isEmpty else { return }
    let contact = voiceTargetContact
    submitStatus = String(
      format: t("Sending voice transcript to %@", "Sending voice transcript to %@"),
      contact.displayName
    )
    Task {
      await coordinator.send(cleanText, to: contact, agentGoalOverride: cleanText)
      await MainActor.run {
        submitStatus = t("signalasi.voice.sent", "Voice transcript sent")
      }
    }
  }

  private func startObserving() {
    voiceState = VoiceInteractionCoordinatorRegistry.coordinator.snapshot()
    guard observerId.isEmpty else { return }
    observerId = VoiceInteractionCoordinatorRegistry.coordinator.observe { next in
      Task { @MainActor in
        voiceState = next
      }
    }
  }

  private func stopObserving() {
    holdToTalk.cancelFromView()
    guard !observerId.isEmpty else { return }
    VoiceInteractionCoordinatorRegistry.coordinator.removeObserver(observerId)
    observerId = ""
  }

  private func onOff(_ value: Bool) -> String {
    t(value ? "common_on" : "common_off", value ? "On" : "Off")
  }

  private func phaseLabel(_ phase: VoiceInteractionPhase) -> String {
    switch phase {
    case .idle:
      return t("signalasi.voice.phase.idle", "Idle")
    case .preparing:
      return t("signalasi.voice.phase.preparing", "Preparing")
    case .listening:
      return t("signalasi.voice.phase.listening", "Listening")
    case .endpointing:
      return t("signalasi.voice.phase.endpointing", "Endpointing")
    case .finalizingASR:
      return t("signalasi.voice.phase.finalizing_asr", "Finalizing")
    case .routing:
      return t("signalasi.voice.phase.routing", "Routing")
    case .executingLocalAction:
      return t("signalasi.voice.phase.local_action", "Local Action")
    case .waitingModelFirstToken:
      return t("signalasi.voice.phase.waiting_model", "Waiting")
    case .streamingModelText:
      return t("signalasi.voice.phase.streaming", "Streaming")
    case .playingTTS:
      return t("signalasi.voice.phase.tts", "Speaking")
    case .startingAgent:
      return t("signalasi.voice.phase.starting_agent", "Starting")
    case .agentRunning:
      return t("signalasi.voice.phase.agent_running", "Agent")
    case .completed:
      return t("signalasi.voice.phase.completed", "Done")
    case .cancelled:
      return t("signalasi.voice.phase.cancelled", "Cancelled")
    case .failed:
      return t("signalasi.voice.phase.failed", "Failed")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIVoiceWakeOrb: View {
  var isActive: Bool
  var isRecording: Bool

  var body: some View {
    ZStack {
      Circle()
        .stroke(Color.white.opacity(0.08), lineWidth: 18)
        .frame(width: 214, height: 214)
      Circle()
        .stroke(tint.opacity(isActive ? 0.42 : 0.18), lineWidth: 4)
        .frame(width: 172, height: 172)
      Circle()
        .fill(tint.opacity(isActive ? 0.20 : 0.10))
        .frame(width: 126, height: 126)
      Image(systemName: isRecording ? "waveform" : "mic.fill")
        .font(.system(size: isRecording ? 54 : 48, weight: .bold))
        .foregroundColor(.white)
    }
    .frame(maxWidth: .infinity, minHeight: 226)
  }

  private var tint: Color {
    isRecording ? .signalASIAgentRecordingMid : (isActive ? .signalASIAccent : .orange)
  }
}

private struct SignalASIVoiceInlineWaveform: View {
  var phase: Double
  var cancelPending: Bool

  var body: some View {
    HStack(alignment: .center, spacing: 4) {
      ForEach(0..<18, id: \.self) { index in
        Capsule()
          .fill(cancelPending ? Color.red.opacity(0.86) : Color.white.opacity(0.82))
          .frame(width: 4, height: barHeight(index))
      }
    }
    .frame(maxWidth: .infinity)
  }

  private func barHeight(_ index: Int) -> CGFloat {
    let wave = sin(phase + Double(index) * 0.72)
    return CGFloat(10 + max(0, wave) * 18)
  }
}
