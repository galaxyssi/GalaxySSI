import Foundation
import SwiftUI

private struct GalaxySSIVoiceRiskConfirmation: Identifiable {
  let id = UUID()
  var text: String
  var contact: GalaxySSIContact
  var risk: VoiceCommandRisk
  var sessionId: String
  var correctionReview: VoiceTranscriptCorrectionReview?
}

struct GalaxySSIVoiceTabView: View {
  var onNavigateToMainTab: ((GalaxySSIMainTab) -> Void)? = nil
  var onBackToSettings: (() -> Void)? = nil

  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @StateObject private var holdToTalk = GalaxySSIAgentHoldToTalkController()
  @StateObject private var wakeListener = GalaxySSIVoiceWakeController()
  @StateObject private var replySpeech = VoiceProgressiveReplySpeechService()
  @State private var voiceState = VoiceInteractionCoordinatorRegistry.coordinator.snapshot()
  @State private var observerId = ""
  @State private var voiceAgentRunListenerId = ""
  @State private var submitStatus = ""
  @State private var lastVoiceTranscript = ""
  @State private var lastVoiceTargetId = ""
  @State private var lastVoiceTargetName = ""
  @State private var lastVoiceSubmissionAt = Date.distantFuture
  @State private var activeVoiceReplySessionId = ""
  @State private var activeVoiceReplyContactId = ""
  @State private var activeVoiceReplyRouteKind: VoiceRouteKind?
  @State private var activeVoiceReplyPlaybackSessionId = ""
  @State private var progressiveVoiceReplySessionId = ""
  @State private var progressiveVoiceReplyText = ""
  @State private var wakeWelcomeSessionId = ""
  @State private var wakeWelcomeTimeoutTask: Task<Void, Never>?
  @State private var pendingRiskConfirmation: GalaxySSIVoiceRiskConfirmation?
  @State private var viewVisible = false

  private var settings: VoiceSettings { store.voiceSettings }

  private var voiceAuthorizationRequirement: VoiceASRAuthorizationRequirement {
    VoiceASRProviderRoutingPolicy.currentAuthorizationRequirement(settings: settings)
  }

  private var voicePreparingSubtitle: String {
    switch voiceAuthorizationRequirement {
    case .microphoneOnly:
      return t(
        "galaxyssi.voice.preparing_microphone_subtitle",
        "Requesting microphone access for on-device Whisper."
      )
    case .microphoneAndSystemSpeech:
      return t(
        "galaxyssi.voice.preparing_subtitle",
        "Requesting microphone and speech recognition access."
      )
    }
  }

  private var voicePermissionDeniedMessage: String {
    switch voiceAuthorizationRequirement {
    case .microphoneOnly:
      return t("galaxyssi.voice.microphone_permission_missing", "Microphone permission is missing.")
    case .microphoneAndSystemSpeech:
      return t("galaxyssi.voice.permission_missing", "Microphone or speech permission is missing.")
    }
  }

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          wakeSurface
          if isVoiceProcessing {
            voiceProcessingStrip(title: voiceProcessingTitle, subtitle: voiceProcessingSubtitle)
          } else if !submitStatus.isEmpty || !holdToTalk.statusMessage.isEmpty ||
              !wakeListener.failureDescription.isEmpty {
            statusStrip
          }
          liveTranscriptSection
          voiceReplySection
          quickControlsSection
          liveHealthSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
      .background(Color.galaxySSIPageBackground.ignoresSafeArea())
      .navigationBarHidden(true)
      .onAppear {
        viewVisible = true
        startObserving()
        startReplyObserving()
        wakeListener.activate(
          settings: settings,
          onWakeDetected: speakWakeWelcomeThenListen,
          onWakeCommand: submitVoiceTranscript
        )
      }
      .onChange(of: settings) { value in
        wakeListener.update(settings: value)
      }
      .onDisappear {
        viewVisible = false
        cancelRiskConfirmation(pendingRiskConfirmation, reportStatus: false)
        pendingRiskConfirmation = nil
        stopObserving()
      }
      .onReceive(
        NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)
      ) { _ in
        holdToTalk.clearRuntimePlaintext()
        wakeListener.deactivate()
        _ = replySpeech.stop()
        submitStatus.removeAll(keepingCapacity: false)
        lastVoiceTranscript.removeAll(keepingCapacity: false)
        progressiveVoiceReplyText.removeAll(keepingCapacity: false)
        pendingRiskConfirmation = nil
      }
      .onReceive(
        NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextDidRestore)
      ) { _ in
        guard viewVisible else { return }
        wakeListener.activate(
          settings: settings,
          onWakeDetected: speakWakeWelcomeThenListen,
          onWakeCommand: submitVoiceTranscript
        )
      }
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .alert(item: $pendingRiskConfirmation) { confirmation in
      Alert(
        title: Text(t("galaxyssi.voice.risk_confirmation_title", "Confirm voice command")),
        message: Text(VoiceRiskConfirmationMessageFormatter.message(
          text: confirmation.text,
          riskLabel: voiceRiskLabel(confirmation.risk),
          correctionReview: confirmation.correctionReview,
          localize: t
        )),
        primaryButton: .default(Text(t("galaxyssi.voice.risk_confirmation_execute", "Execute"))) {
          executeRiskConfirmedVoiceTranscript(confirmation)
        },
        secondaryButton: .cancel(Text(t("galaxyssi.common.cancel", "Cancel"))) {
          cancelRiskConfirmation(confirmation, reportStatus: true)
        }
      )
    }
  }

  private var wakeSurface: some View {
    VStack(spacing: 18) {
      HStack(spacing: 10) {
        if let onBackToSettings {
          Button(action: onBackToSettings) {
            Image(systemName: "chevron.left")
              .font(.system(size: 19, weight: .semibold))
              .foregroundColor(.white)
              .frame(width: 40, height: 40)
              .background(Color.white.opacity(0.12))
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(t("galaxyssi.common.back", "Back")))
        }
        wakeStatusPill
        Spacer(minLength: 8)
        if let onNavigateToMainTab {
          Button {
            onNavigateToMainTab(.sessions)
          } label: {
            Image(systemName: "message.fill")
              .font(.system(size: 17, weight: .semibold))
              .foregroundColor(.white)
              .frame(width: 40, height: 40)
              .background(Color.white.opacity(0.12))
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(t("galaxyssi.voice.open_messages", "Open messages")))
        }
        NavigationLink(destination: GalaxySSIVoiceAssistantSettingsView()) {
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

      Button(action: handleWakeOrbTap) {
        GalaxySSIVoiceWakeOrb(
          isActive: wakeListener.isListening || wakeListener.isPreparing ||
            wakeListener.isCommandCapturing || holdToTalk.isRecording,
          isRecording: wakeListener.isCommandCapturing || holdToTalk.isRecording
        )
      }
      .buttonStyle(.plain)
      .disabled(!replySpeech.isSpeaking || wakeListener.isCommandCapturing)
      .accessibilityLabel(Text(t("galaxyssi.voice.barge_in_action", "Interrupt reply and speak")))

      VStack(spacing: 7) {
        Text(wakeSurfaceTitle)
          .font(.system(size: 24, weight: .bold))
          .foregroundColor(.white)
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .minimumScaleFactor(0.78)

        Text(wakeSurfaceSubtitle)
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
        .fill(wakeListener.isListening ? Color.galaxySSIAccent : Color.orange)
        .frame(width: 8, height: 8)
      Text(wakeStatusLabel)
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
        Text(t("galaxyssi.voice.preparing_title", "Preparing voice input"))
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.78)
        AgentVoiceProcessingIndicator(
          title: t("galaxyssi.voice.preparing_title", "Preparing voice input"),
          subtitle: voicePreparingSubtitle
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
        GalaxySSIVoiceInlineWaveform(phase: holdToTalk.waveformPhase, cancelPending: holdToTalk.cancelPending)
          .frame(height: 28)
        Text(holdToTalk.transcript.ifBlank(holdToTalk.elapsedLabel))
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(Color.white.opacity(0.86))
          .lineLimit(1)
          .truncationMode(.head)
      } else {
        Label(t("galaxyssi.voice.recorder", "Hold to Talk"), systemImage: "mic.fill")
          .font(.system(size: 17, weight: .bold))
          .foregroundColor(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.78)
        Text(t("galaxyssi.voice.recorder_subtitle", "Open live recording and send transcribed text"))
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
    .accessibilityLabel(Text(t("galaxyssi.voice.recorder", "Hold to Talk")))
  }

  private var wakeToggleButton: some View {
    Button {
      store.updateVoiceSettings { $0.wakeListeningEnabled.toggle() }
    } label: {
      HStack(spacing: 8) {
        Image(systemName: settings.wakeListeningEnabled ? "pause.circle.fill" : "play.circle.fill")
          .font(.system(size: 20, weight: .semibold))
        Text(settings.wakeListeningEnabled
          ? t("galaxyssi.voice.turn_off_wake", "Turn off voice wake")
          : t("galaxyssi.voice.turn_on_wake", "Turn on low-power listening"))
          .font(.system(size: 15, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.72)
      }
      .foregroundColor(.white)
      .frame(maxWidth: .infinity, minHeight: 46)
      .background(settings.wakeListeningEnabled ? Color.white.opacity(0.13) : Color.galaxySSIAccent)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private var statusStrip: some View {
    Text(submitStatus.ifBlank(holdToTalk.statusMessage).ifBlank(wakeListener.failureDescription))
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
      .background(Color.galaxySSISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func voiceProcessingStrip(title: String, subtitle: String) -> some View {
    AgentVoiceProcessingIndicator(title: title, subtitle: subtitle)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.galaxySSISurface)
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

  private var wakeSurfaceTitle: String {
    if wakeListener.isCommandCapturing {
      return t("galaxyssi.voice.listening_command", "Listening")
    }
    if !wakeWelcomeSessionId.isEmpty {
      return t("galaxyssi.voice.wake_detected", "Awake")
    }
    if replySpeech.isSpeaking {
      return t("galaxyssi.voice.barge_in_title", "Speaking reply")
    }
    if !settings.wakeListeningEnabled {
      return t("voice_status_disabled", "Voice wake is off")
    }
    if wakeListener.isListening {
      return t("voice_status_low_power", "Low-power listening")
    }
    if wakeListener.isPreparing {
      return t("galaxyssi.voice.preparing_title", "Preparing voice input")
    }
    if !wakeListener.failureDescription.isEmpty {
      return t("galaxyssi.voice.permission_missing", "Microphone or speech permission is missing.")
    }
    return t("galaxyssi.voice.preparing_title", "Preparing voice input")
  }

  private var wakeSurfaceSubtitle: String {
    if wakeListener.isCommandCapturing {
      return t("galaxyssi.voice.listening_command_detail", "Speak naturally. Recording stops after a short pause.")
    }
    if !wakeWelcomeSessionId.isEmpty {
      return t("galaxyssi.voice.speaking_welcome", "Speaking the wake welcome, then listening.")
    }
    if replySpeech.isSpeaking {
      return t("galaxyssi.voice.barge_in_subtitle", "Tap the voice icon to interrupt and speak.")
    }
    if !settings.wakeListeningEnabled {
      return t("voice_status_disabled_detail", "Enable it in Settings > Voice Wake & ASR/TTS")
    }
    if !wakeListener.failureDescription.isEmpty {
      return wakeListener.failureDescription
    }
    return t("voice_hint_wake", "Say \"hello\" to start talking")
  }

  private var wakeStatusLabel: String {
    if wakeListener.isCommandCapturing {
      return t("galaxyssi.voice.listening_command", "Listening")
    }
    if wakeListener.isListening {
      return t("voice_status_low_power", "Low-power listening")
    }
    if wakeListener.isPreparing {
      return t("galaxyssi.voice.preparing_title", "Preparing voice input")
    }
    return t("common_off", "Off")
  }

  private var voiceProcessingTitle: String {
    switch voiceState.phase {
    case .finalizingASR:
      return t("galaxyssi.voice.processing_transcribing", "Recognizing voice")
    case .routing:
      return t("galaxyssi.voice.processing_routing", "Routing voice task")
    case .executingLocalAction:
      return t("galaxyssi.voice.processing_local_action", "Running phone action")
    case .waitingModelFirstToken:
      return t("galaxyssi.voice.processing_model", "Waiting for model")
    case .startingAgent, .agentRunning:
      return t("galaxyssi.voice.processing_agent", "Waiting for Agent")
    default:
      return t("galaxyssi.voice.processing_title", "Processing voice input")
    }
  }

  private var voiceProcessingSubtitle: String {
    switch voiceState.phase {
    case .finalizingASR:
      return t("galaxyssi.voice.processing_transcribing_detail", "Finalizing the local transcript.")
    case .routing:
      return t("galaxyssi.voice.processing_routing_detail", "Selecting the configured voice destination.")
    case .executingLocalAction:
      return t("galaxyssi.voice.processing_local_action_detail", "The phone Agent is executing the requested action.")
    case .waitingModelFirstToken:
      return t("galaxyssi.voice.processing_model_detail", "The selected model is preparing its first response.")
    case .startingAgent, .agentRunning:
      return t("galaxyssi.voice.processing_agent_detail", "The selected Agent is working on the request.")
    default:
      return t("galaxyssi.voice.processing_detail", "Voice input is being prepared.")
    }
  }

  private var liveTranscriptSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.voice.live_transcript", "Live Transcript"))
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.voice.phase", "Phase"),
        subtitle: visibleTranscript.ifBlank(t("galaxyssi.voice.no_live_transcript", "Voice activity appears here after wake or recording.")),
        systemImage: "text.bubble",
        tint: phaseTint,
        badge: phaseLabel(voiceState.phase)
      )
    }
  }

  @ViewBuilder
  private var voiceReplySection: some View {
    if !lastVoiceTranscript.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        GalaxySSISecuritySectionTitle(title: t("galaxyssi.voice.activity", "Voice Activity"))
        GalaxySSISecurityStatusRow(
          title: t("galaxyssi.voice.transcript", "You said"),
          subtitle: lastVoiceTranscript,
          systemImage: "mic.fill",
          tint: .blue,
          badge: lastVoiceTargetName
        )
        if let reply = latestVoiceReply {
          if replySpeech.isSpeaking {
            Button(action: handleWakeOrbTap) {
              voiceReplyStatusRow(reply)
            }
            .buttonStyle(.plain)
            .disabled(wakeListener.isCommandCapturing)
            .accessibilityLabel(Text(t("galaxyssi.voice.barge_in_action", "Interrupt reply and speak")))
          } else {
            voiceReplyStatusRow(reply)
          }
        } else if !submitStatus.isEmpty {
          GalaxySSISecurityStatusRow(
            title: t("galaxyssi.voice.reply", "Reply"),
            subtitle: submitStatus,
            systemImage: "arrow.triangle.2.circlepath",
            tint: .galaxySSIInsightText,
            badge: t("galaxyssi.voice.reply_pending", "Waiting")
          )
        }
      }
    }
  }

  private func voiceReplyStatusRow(_ reply: ChatMessage) -> some View {
    GalaxySSISecurityStatusRow(
      title: t("galaxyssi.voice.reply", "Reply"),
      subtitle: reply.content,
      systemImage: "text.bubble.fill",
      tint: .galaxySSIAccent,
      badge: t("galaxyssi.voice.reply_received", "Received")
    )
  }

  private var quickControlsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.voice.quick_controls", "Quick Controls"))
      GalaxySSISecurityNavigationRow(
        title: t("cc_voice_title", "Voice & Interaction"),
        subtitle: t("cc_voice_subtitle", "Wake word, ASR, TTS, and task routing"),
        systemImage: "waveform",
        tint: .galaxySSIAccent,
        badge: t("common_view", "View")
      ) {
        GalaxySSIVoiceControlCenterView()
      }
      GalaxySSISecurityNavigationRow(
        title: t("voice_settings_title", "Voice Wake & ASR/TTS"),
        subtitle: settings.wakeWordsText,
        systemImage: "slider.horizontal.3",
        tint: .blue,
        badge: onOff(settings.wakeListeningEnabled)
      ) {
        GalaxySSIVoiceAssistantSettingsView()
      }
      GalaxySSISecurityNavigationRow(
        title: t("galaxyssi.advanced.voice_models", "Voice Models"),
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
      GalaxySSISecuritySectionTitle(title: t("voice_health_section", "Live Health"))
      GalaxySSISecurityStatusRow(
        title: t("voice_health_wake", "Wake Word"),
        subtitle: settings.wakeWordsText,
        systemImage: "mic.circle",
        tint: settings.wakeListeningEnabled ? .galaxySSIAccent : .gray,
        badge: onOff(settings.wakeListeningEnabled)
      )
      GalaxySSISecurityStatusRow(
        title: t("voice_health_asr", "Speech Recognition"),
        subtitle: VoiceWhisperModelCatalog.model(settings.asrModelId).displayName,
        systemImage: "waveform.and.mic",
        tint: settings.speechRecognitionEnabled ? .galaxySSIAccent : .gray,
        badge: onOff(settings.speechRecognitionEnabled)
      )
      GalaxySSISecurityStatusRow(
        title: t("voice_health_tts", "Speech Synthesis"),
        subtitle: t(settings.ttsProvider.displayTitle, settings.ttsProvider.displayTitle),
        systemImage: "speaker.wave.2",
        tint: settings.textToSpeechEnabled && settings.speakReplies ? .galaxySSIAccent : .gray,
        badge: onOff(settings.textToSpeechEnabled && settings.speakReplies)
      )
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.voice.target", "Target"),
        subtitle: voiceTargetContact.displayName,
        systemImage: "arrow.triangle.branch",
        tint: .blue,
        badge: routingLabel
      )
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.voice.language", "Language"),
        subtitle: languageFormatter.summary(
          policy: store.languagePolicy,
          asrLocaleIdentifier: settings.preferredLocaleIdentifier
        ),
        systemImage: "globe",
        tint: .galaxySSIInsightText,
        badge: languageFormatter.statusBadge(for: store.languagePolicy)
      )
    }
  }

  private var holdToTalkGesture: some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        interruptActiveVoiceReply()
        wakeListener.pauseForManualCapture()
        holdToTalk.dragChanged(
          translation: value.translation,
          settings: settings,
          messages: holdToTalkMessages,
          onStart: {
            submitStatus = ""
          },
          onFinish: submitVoiceTranscript,
          onCancel: {}
        )
      }
      .onEnded { value in
        holdToTalk.dragEnded(translation: value.translation)
        wakeListener.resumeAfterManualCapture()
      }
  }

  private func handleWakeOrbTap() {
    guard replySpeech.isSpeaking, !wakeListener.isCommandCapturing else { return }
    if wakeWelcomeSessionId.isEmpty {
      interruptActiveVoiceReply()
    } else {
      cancelWakeWelcomePlayback()
    }
    if wakeListener.beginTapToSpeak() {
      submitStatus = t("galaxyssi.voice.listening_command", "Listening")
    }
  }

  private func speakWakeWelcomeThenListen() {
    cancelWakeWelcomePlayback()
    let sessionId = UUID().uuidString
    guard let request = VoiceReplyPlaybackPolicy.wakeWelcomeRequest(
      settings: settings,
      languagePolicy: store.languagePolicy,
      sessionId: sessionId
    ) else {
      beginWakeCommandCapture()
      return
    }
    wakeWelcomeSessionId = sessionId
    submitStatus = t("galaxyssi.voice.wake_detected", "Awake")
    replySpeech.speak(request) { started in
      guard wakeWelcomeSessionId == started.sessionId else { return }
      submitStatus = t("galaxyssi.voice.speaking_welcome", "Speaking wake welcome")
    } onDone: { done, _, _ in
      finishWakeWelcome(sessionId: done.sessionId)
    }
    wakeWelcomeTimeoutTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 4_500_000_000)
      guard !Task.isCancelled, wakeWelcomeSessionId == sessionId else { return }
      _ = replySpeech.stop()
      finishWakeWelcome(sessionId: sessionId)
    }
  }

  private func finishWakeWelcome(sessionId: String) {
    guard wakeWelcomeSessionId == sessionId else { return }
    wakeWelcomeTimeoutTask?.cancel()
    wakeWelcomeTimeoutTask = nil
    wakeWelcomeSessionId = ""
    beginWakeCommandCapture()
  }

  private func cancelWakeWelcomePlayback() {
    guard !wakeWelcomeSessionId.isEmpty else { return }
    wakeWelcomeTimeoutTask?.cancel()
    wakeWelcomeTimeoutTask = nil
    wakeWelcomeSessionId = ""
    _ = replySpeech.stop()
  }

  private func beginWakeCommandCapture() {
    if wakeListener.beginTapToSpeak() {
      submitStatus = t("galaxyssi.voice.listening_command", "Listening")
    }
  }

  private var holdToTalkMessages: GalaxySSIAgentHoldToTalkMessages {
    GalaxySSIAgentHoldToTalkMessages(
      permissionDenied: voicePermissionDeniedMessage,
      speechDisabled: t("galaxyssi.voice.speech_disabled", "Speech recognition is turned off."),
      speechUnavailable: t("galaxyssi.voice.speech_unavailable", "Speech recognition could not start."),
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
      return .galaxySSIAccent
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

  private var languageFormatter: GalaxySSILanguagePolicyFormatter {
    GalaxySSILanguagePolicyFormatter { key, fallback in
      t(key, fallback)
    }
  }

  private var voiceTargetContact: GalaxySSIContact {
    let targetId = settings.routingMode == .nativeAgent ? "hermes" : settings.targetContactId
    return store.visibleContacts.first { $0.id == targetId } ??
      store.visibleContacts.first { $0.id == settings.targetContactId } ??
      store.visibleContacts.first { $0.id == "hermes" } ??
      GalaxySSIContact.hermes()
  }

  private var latestVoiceReply: ChatMessage? {
    guard !lastVoiceTargetId.isEmpty else { return nil }
    return store.messages(for: lastVoiceTargetId)
      .reversed()
      .first { message in
        !message.isMine && !message.isSystem && message.createdAt >= lastVoiceSubmissionAt
      }
  }

  private func submitVoiceTranscript(_ submission: GalaxySSIVoiceTranscriptSubmission) {
    submitVoiceTranscript(
      submission.text,
      correctionReview: submission.correctionReview,
      sessionId: submission.sessionId
    )
  }

  private func submitVoiceTranscript(_ text: String) {
    submitVoiceTranscript(
      text,
      correctionReview: nil,
      sessionId: VoiceInteractionCoordinatorRegistry.coordinator.snapshot().sessionId
    )
  }

  private func submitVoiceTranscript(
    _ text: String,
    correctionReview: VoiceTranscriptCorrectionReview?,
    sessionId: String
  ) {
    let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanText.isEmpty else { return }
    let contact = voiceTargetContact
    let risk = DefaultVoiceCommandRiskClassifier.classify(cleanText)
    let registeredSessionId = VoiceExecutionLedgerBridge.register(
      sessionId: sessionId,
      text: cleanText,
      correctionReview: correctionReview,
      risk: risk
    )
    if let correctionReview {
      _ = VoiceCorrectionJournal.shared.persist(
        review: correctionReview,
        conversationId: store.activeAgentConversationId.ifBlank(contact.id),
        turnId: correctionReview.sessionId,
        risk: risk
      )
    }
    if risk >= .high {
      pendingRiskConfirmation = GalaxySSIVoiceRiskConfirmation(
        text: cleanText,
        contact: contact,
        risk: risk,
        sessionId: registeredSessionId,
        correctionReview: correctionReview
      )
      submitStatus = t("galaxyssi.voice.risk_confirmation_required", "Voice command requires confirmation")
      return
    }
    sendVoiceTranscript(
      cleanText,
      to: contact,
      correctionReview: correctionReview,
      risk: risk,
      preferredSessionId: registeredSessionId
    )
  }

  private func executeRiskConfirmedVoiceTranscript(_ confirmation: GalaxySSIVoiceRiskConfirmation) {
    sendVoiceTranscript(
      confirmation.text,
      to: confirmation.contact,
      correctionReview: confirmation.correctionReview,
      risk: confirmation.risk,
      preferredSessionId: confirmation.sessionId
    )
  }

  private func cancelRiskConfirmation(
    _ confirmation: GalaxySSIVoiceRiskConfirmation?,
    reportStatus: Bool
  ) {
    guard let confirmation else { return }
    let voiceCoordinator = VoiceInteractionCoordinatorRegistry.coordinator
    let current = voiceCoordinator.snapshot()
    if !confirmation.sessionId.isEmpty,
       current.sessionId == confirmation.sessionId,
       !current.phase.isTerminal {
      _ = voiceCoordinator.dispatch(
        .cancelled(sessionId: confirmation.sessionId, reasonCode: "risk_confirmation_cancelled")
      )
    }
    if reportStatus {
      submitStatus = t("galaxyssi.voice.risk_confirmation_cancelled", "Voice command cancelled")
    }
  }

  private func sendVoiceTranscript(
    _ cleanText: String,
    to contact: GalaxySSIContact,
    correctionReview: VoiceTranscriptCorrectionReview?,
    risk: VoiceCommandRisk,
    preferredSessionId: String
  ) {
    let ledgerSessionId = VoiceExecutionLedgerBridge.register(
      sessionId: preferredSessionId,
      text: cleanText,
      correctionReview: correctionReview,
      risk: risk
    )
    guard VoiceExecutionLedgerBridge.claimPrimaryDispatch(sessionId: ledgerSessionId) else {
      submitStatus = t("galaxyssi.voice.duplicate_ignored", "Duplicate voice request ignored")
      return
    }
    guard let session = startVoiceReplySession(transcript: cleanText, contact: contact) else {
      VoiceExecutionLedger.shared.remove(sessionId: ledgerSessionId)
      submitStatus = t("galaxyssi.voice.session_failed", "Voice request could not be started")
      return
    }
    VoiceExecutionLedgerBridge.recordRoute(sessionId: ledgerSessionId, decision: session.decision)
    lastVoiceTranscript = cleanText
    lastVoiceTargetId = contact.id
    lastVoiceTargetName = contact.displayName
    lastVoiceSubmissionAt = Date()
    submitStatus = String(
      format: t("Sending voice transcript to %@", "Sending voice transcript to %@"),
      contact.displayName
    )
    if session.decision.kind == .remoteAgent {
      _ = VoiceAgentRunBridgeRegistry.shared.createRun(
        VoiceAgentRunRequest(
          sessionId: session.sessionId,
          conversationId: store.activeAgentConversationId,
          turnId: session.sessionId,
          taskId: session.sessionId,
          sourceMessageId: session.sessionId,
          contactId: contact.id,
          agentId: contact.galaxySSIId,
          agentName: contact.displayName,
          goal: cleanText,
          idempotencyKey: "voice:\(session.sessionId)",
          traceId: session.sessionId,
          createdAtMillis: Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        )
      )
    }
    Task {
      let sent = await coordinator.send(
        cleanText,
        to: contact,
        agentGoalOverride: cleanText,
        voiceSessionId: session.decision.kind == .remoteAgent ? session.sessionId : ""
      )
      await MainActor.run {
        submitStatus = sent
          ? t("galaxyssi.voice.sent", "Voice transcript sent")
          : coordinator.lastError.ifBlank(t("galaxyssi.voice.send_failed", "Voice transcript could not be sent"))
        finishVoiceSendIfNoReplyPlaybackStarted(session)
      }
    }
  }

  private func voiceRiskLabel(_ risk: VoiceCommandRisk) -> String {
    switch risk {
    case .critical:
      return t("galaxyssi.voice.risk_critical", "critical")
    case .high:
      return t("galaxyssi.voice.risk_high", "high")
    case .medium:
      return t("galaxyssi.voice.risk_medium", "medium")
    case .low:
      return t("galaxyssi.voice.risk_low", "low")
    case .conversation:
      return t("galaxyssi.voice.risk_conversation", "conversation")
    }
  }

  private func startVoiceReplySession(
    transcript: String,
    contact: GalaxySSIContact
  ) -> (sessionId: String, decision: VoiceRouteDecision)? {
    let voiceCoordinator = VoiceInteractionCoordinatorRegistry.coordinator
    let current = voiceCoordinator.snapshot()
    let decision = VoiceRouteDecision(
      kind: voiceRouteKind(for: contact),
      targetId: contact.id,
      reasonCode: "voice_auto_send"
    )
    let sessionId: String

    if current.phase == .routing,
       current.finalText?.trimmingCharacters(in: .whitespacesAndNewlines) == transcript {
      sessionId = current.sessionId
    } else {
      if !current.sessionId.isEmpty, !current.phase.isTerminal, current.phase != .idle {
        _ = voiceCoordinator.cancel(reasonCode: "new_utterance")
      }
      let transition = voiceCoordinator.begin(
        config: VoiceSessionConfig(
          source: "ios_voice_home",
          language: settings.preferredLocaleIdentifier,
          targetId: contact.id,
          routingMode: settings.routingMode.rawValue,
          speakReplies: settings.speakReplies,
          continueInBackground: settings.wakeListeningEnabled
        )
      )
      guard transition.accepted else { return nil }
      sessionId = transition.current.sessionId
      _ = voiceCoordinator.dispatch(.capturePrepared(sessionId: sessionId))
      _ = voiceCoordinator.dispatch(.speechStarted(sessionId: sessionId, atElapsedNs: 0))
      _ = voiceCoordinator.dispatch(.speechEnded(sessionId: sessionId, atElapsedNs: 0))
      _ = voiceCoordinator.dispatch(.finalizationStarted(sessionId: sessionId))
      _ = voiceCoordinator.dispatch(
        .transcriptFinal(
          sessionId: sessionId,
          value: TranscriptHypothesis(text: transcript, revision: 1)
        )
      )
    }

    guard voiceCoordinator.dispatch(
      .routeSelected(sessionId: sessionId, decision: decision)
    ).accepted else {
      return nil
    }
    activeVoiceReplySessionId = sessionId
    activeVoiceReplyContactId = contact.id
    activeVoiceReplyRouteKind = decision.kind
    return (sessionId, decision)
  }

  private func voiceRouteKind(for contact: GalaxySSIContact) -> VoiceRouteKind {
    switch contact.deliveryMode {
    case .local:
      return .localAction
    case .cloudAPI:
      return .cloudModel
    case .link, .pcConnector:
      return .remoteAgent
    }
  }

  private func startReplyObserving() {
    coordinator.onIncomingMessage = handleIncomingVoiceReply
    coordinator.onIncomingMessageDelta = handleIncomingVoiceReplyDelta
    guard voiceAgentRunListenerId.isEmpty else { return }
    voiceAgentRunListenerId = VoiceAgentRunBridgeRegistry.shared.addListener(handleVoiceAgentRunUpdate)
  }

  private func handleIncomingVoiceReply(_ message: ChatMessage) {
    guard let request = VoiceReplyPlaybackPolicy.request(
      message: message,
      settings: settings,
      languagePolicy: store.languagePolicy,
      activeSessionId: activeVoiceReplySessionId,
      activeTargetContactId: activeVoiceReplyContactId
    ) else {
      return
    }
    if activeVoiceReplyRouteKind == .cloudModel,
       progressiveVoiceReplySessionId == request.sessionId {
      appendProgressiveVoiceReply(request: request, content: request.text, isFinal: true)
      return
    }
    updateVoiceReplyRoute(for: request, message: message)
    activeVoiceReplyPlaybackSessionId = request.sessionId
    replySpeech.speak(request) { started in
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .playbackStarted(sessionId: started.sessionId, utteranceId: started.utteranceId)
      )
      submitStatus = t("voice_status_speaking", "Speaking reply")
    } onDone: { done, success, _ in
      completeVoiceReplyPlayback(done, success: success)
    }
  }

  private func handleIncomingVoiceReplyDelta(_ message: ChatMessage) {
    guard activeVoiceReplyRouteKind == .cloudModel,
          let request = VoiceReplyPlaybackPolicy.request(
            message: message,
            settings: settings,
            languagePolicy: store.languagePolicy,
            activeSessionId: activeVoiceReplySessionId,
            activeTargetContactId: activeVoiceReplyContactId
          ) else {
      return
    }
    _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
      .modelDelta(sessionId: request.sessionId, text: request.text)
    )
    if progressiveVoiceReplySessionId != request.sessionId {
      progressiveVoiceReplySessionId = request.sessionId
      progressiveVoiceReplyText = ""
      activeVoiceReplyPlaybackSessionId = request.sessionId
      replySpeech.beginProgressive(request) { started in
        _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
          .playbackStarted(sessionId: started.sessionId, utteranceId: started.utteranceId)
        )
        submitStatus = t("voice_status_speaking", "Speaking reply")
      } onDone: { done, success, _ in
        completeVoiceReplyPlayback(done, success: success)
      }
    }
    appendProgressiveVoiceReply(request: request, content: request.text, isFinal: false)
  }

  private func updateVoiceReplyRoute(for request: VoiceReplyPlaybackRequest, message: ChatMessage) {
    switch activeVoiceReplyRouteKind {
    case .remoteAgent:
      _ = VoiceAgentRunBridgeRegistry.shared.markFinalResult(
        sessionId: request.sessionId,
        content: request.text
      )
      let runId = VoiceAgentRunBridgeRegistry.shared.find(sessionId: request.sessionId)?.runId
        ?? message.id.uuidString
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .agentAccepted(sessionId: request.sessionId, runId: runId)
      )
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .agentProgress(sessionId: request.sessionId, runId: runId)
      )
    case .cloudModel:
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .modelDelta(sessionId: request.sessionId, text: request.text)
      )
    case .localAction, .none:
      break
    }
  }

  private func handleVoiceAgentRunUpdate(_ update: VoiceAgentRunUpdate) {
    guard update.snapshot.sessionId == activeVoiceReplySessionId else { return }
    if update.firstAcceptance {
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .agentAccepted(sessionId: update.snapshot.sessionId, runId: update.snapshot.runId)
      )
    }
    if update.firstProgress {
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .agentProgress(sessionId: update.snapshot.sessionId, runId: update.snapshot.runId)
      )
    }
    if !update.message.isEmpty {
      submitStatus = update.message
    }
    switch update.snapshot.state {
    case .failed, .timedOut:
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .failed(
          sessionId: update.snapshot.sessionId,
          failure: VoiceFailure(
            code: update.snapshot.state.rawValue.lowercased(),
            recoverable: true,
            stage: .agentRunning,
            detail: update.message.ifBlank("The remote Agent run failed.")
          )
        )
      )
      clearActiveVoiceReplySession(update.snapshot.sessionId)
    case .cancelled:
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .cancelled(sessionId: update.snapshot.sessionId, reasonCode: "remote_cancelled")
      )
      clearActiveVoiceReplySession(update.snapshot.sessionId)
    case .created, .accepted, .queued, .starting, .running, .waitingInput, .waitingApproval, .cancelling, .completed:
      break
    }
  }

  private func appendProgressiveVoiceReply(
    request: VoiceReplyPlaybackRequest,
    content: String,
    isFinal: Bool
  ) {
    guard progressiveVoiceReplySessionId == request.sessionId else { return }
    let normalized = String(content.prefix(VoiceReplyPlaybackPolicy.maximumSpokenCharacters))
    let delta = normalized.hasPrefix(progressiveVoiceReplyText)
      ? String(normalized.dropFirst(progressiveVoiceReplyText.count))
      : normalized
    progressiveVoiceReplyText = normalized
    replySpeech.appendProgressive(delta, isFinal: isFinal)
  }

  private func finishVoiceSendIfNoReplyPlaybackStarted(
    _ session: (sessionId: String, decision: VoiceRouteDecision)
  ) {
    if session.decision.kind == .localAction {
      guard activeVoiceReplyPlaybackSessionId != session.sessionId else { return }
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .localActionCompleted(sessionId: session.sessionId)
      )
      clearActiveVoiceReplySession(session.sessionId)
      return
    }
    if !settings.speakReplies {
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(.completed(sessionId: session.sessionId))
      clearActiveVoiceReplySession(session.sessionId)
      return
    }
    if session.decision.kind == .cloudModel,
       activeVoiceReplyPlaybackSessionId != session.sessionId,
       !replySpeech.isSpeaking,
       activeVoiceReplySessionId == session.sessionId {
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(.completed(sessionId: session.sessionId))
      clearActiveVoiceReplySession(session.sessionId)
    }
  }

  private func completeVoiceReplyPlayback(_ done: VoiceReplyPlaybackRequest, success: Bool) {
    if success {
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(.completed(sessionId: done.sessionId))
      submitStatus = t("galaxyssi.voice.sent", "Voice transcript sent")
    } else {
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .cancelled(sessionId: done.sessionId, reasonCode: "tts_cancelled")
      )
    }
    clearActiveVoiceReplySession(done.sessionId)
  }

  private func interruptActiveVoiceReply() {
    if !wakeWelcomeSessionId.isEmpty {
      cancelWakeWelcomePlayback()
      return
    }
    let sessionId = activeVoiceReplySessionId
    let hadPlayback = replySpeech.stop()
    guard !sessionId.isEmpty else { return }
    _ = VoiceAgentRunBridgeRegistry.shared.markCancellationRequested(sessionId: sessionId)
    _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
      .cancelled(sessionId: sessionId, reasonCode: "barge_in")
    )
    clearActiveVoiceReplySession(sessionId)
    if hadPlayback {
      submitStatus = t("voice_reply_interrupted", "Voice reply interrupted.")
    }
  }

  private func clearActiveVoiceReplySession(_ sessionId: String) {
    if activeVoiceReplySessionId == sessionId {
      activeVoiceReplySessionId = ""
      activeVoiceReplyContactId = ""
      activeVoiceReplyRouteKind = nil
    }
    if activeVoiceReplyPlaybackSessionId == sessionId {
      activeVoiceReplyPlaybackSessionId = ""
    }
    if progressiveVoiceReplySessionId == sessionId {
      progressiveVoiceReplySessionId = ""
      progressiveVoiceReplyText = ""
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
    wakeListener.deactivate()
    holdToTalk.cancelFromView()
    cancelWakeWelcomePlayback()
    replySpeech.stop()
    coordinator.onIncomingMessage = nil
    coordinator.onIncomingMessageDelta = nil
    if !voiceAgentRunListenerId.isEmpty {
      VoiceAgentRunBridgeRegistry.shared.removeListener(voiceAgentRunListenerId)
      voiceAgentRunListenerId = ""
    }
    if !activeVoiceReplySessionId.isEmpty {
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .completed(sessionId: activeVoiceReplySessionId)
      )
      clearActiveVoiceReplySession(activeVoiceReplySessionId)
    }
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
      return t("galaxyssi.voice.phase.idle", "Idle")
    case .preparing:
      return t("galaxyssi.voice.phase.preparing", "Preparing")
    case .listening:
      return t("galaxyssi.voice.phase.listening", "Listening")
    case .endpointing:
      return t("galaxyssi.voice.phase.endpointing", "Endpointing")
    case .finalizingASR:
      return t("galaxyssi.voice.phase.finalizing_asr", "Finalizing")
    case .routing:
      return t("galaxyssi.voice.phase.routing", "Routing")
    case .executingLocalAction:
      return t("galaxyssi.voice.phase.local_action", "Local Action")
    case .waitingModelFirstToken:
      return t("galaxyssi.voice.phase.waiting_model", "Waiting")
    case .streamingModelText:
      return t("galaxyssi.voice.phase.streaming", "Streaming")
    case .playingTTS:
      return t("galaxyssi.voice.phase.tts", "Speaking")
    case .startingAgent:
      return t("galaxyssi.voice.phase.starting_agent", "Starting")
    case .agentRunning:
      return t("galaxyssi.voice.phase.agent_running", "Agent")
    case .completed:
      return t("galaxyssi.voice.phase.completed", "Done")
    case .cancelled:
      return t("galaxyssi.voice.phase.cancelled", "Cancelled")
    case .failed:
      return t("galaxyssi.voice.phase.failed", "Failed")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIVoiceWakeOrb: View {
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
    isRecording ? .galaxySSIAgentRecordingMid : (isActive ? .galaxySSIAccent : .orange)
  }
}

private struct GalaxySSIVoiceInlineWaveform: View {
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
