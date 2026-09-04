import SwiftUI

struct SignalASIAgentComposerView: View {
  @EnvironmentObject private var store: SignalASIStore
  @Environment(\.scenePhase) private var scenePhase
  @Binding var draft: String
  @Binding var actionTrayPresented: Bool
  @Binding var voiceTranscriptionPending: Bool
  @StateObject private var holdToTalk = SignalASIAgentHoldToTalkController()
  @FocusState private var inputFocused: Bool
  @State private var emptySubmitMessage = ""

  var attachments: [SignalASIDraftAttachment]
  var attachmentError: String
  var canSend: Bool
  var hasPendingPrimaryAction: Bool
  var pendingPrimaryActionResumesTask: Bool
  var pendingPrimaryActionApprovesTask: Bool
  var pendingPrimaryActionWaitingForResponse: Bool
  var pendingPrimaryActionNeedsHighRiskConfirmation: Bool
  var primaryActionInFlight: Bool
  var deviceInputPolicy: AgentDeviceInputTargetPolicy
  var voiceSettings: VoiceSettings
  var focusRequest: Int = 0
  var onRemoveAttachment: (SignalASIDraftAttachment) -> Void
  var onNewSession: () -> Void
  var onOpenSessions: () -> Void
  var onScan: () -> Void
  var onTakePhoto: () -> Void
  var onAddFile: () -> Void
  var onSend: () -> Void
  var onPendingPrimaryAction: () -> Void
  var onVoiceStart: () -> Void
  var onVoiceCancelled: () -> Void
  var onVoiceTranscript: (SignalASIVoiceTranscriptSubmission) -> Void
  var t: (String, String) -> String

  private var uiState: SignalASIAgentComposerUiState {
    SignalASIAgentComposerUiPolicy.resolve(
      hasInput: canSend,
      hasPendingPrimaryAction: hasPendingPrimaryAction,
      textModeActive: inputFocused,
      actionTrayRequested: actionTrayPresented
    )
  }

  private var trayVisible: Bool {
    uiState.showActionTray && !holdToTalk.isRecording
  }

  private var minimumTouchSize: CGFloat {
    CGFloat(deviceInputPolicy.minimumTouchTargetDp)
  }

  private var newGlobalInsightCount: Int {
    store.globalProactiveInboxNewCount()
  }

  private var voiceAuthorizationRequirement: VoiceASRAuthorizationRequirement {
    VoiceASRProviderRoutingPolicy.currentAuthorizationRequirement(settings: voiceSettings)
  }

  private var voicePreparingSubtitle: String {
    switch voiceAuthorizationRequirement {
    case .microphoneOnly:
      return t(
        "signalasi.voice.preparing_microphone_subtitle",
        "Requesting microphone access for on-device Whisper."
      )
    case .microphoneAndSystemSpeech:
      return t(
        "signalasi.voice.preparing_subtitle",
        "Requesting microphone and speech recognition access."
      )
    }
  }

  private var voicePermissionDeniedMessage: String {
    switch voiceAuthorizationRequirement {
    case .microphoneOnly:
      return t("signalasi.voice.microphone_permission_missing", "Microphone permission is missing.")
    case .microphoneAndSystemSpeech:
      return t("signalasi.voice.permission_missing", "Microphone or speech permission is missing.")
    }
  }

  var body: some View {
    VStack(spacing: 8) {
      if newGlobalInsightCount > 0 {
        SignalASIAgentHomeInsightBarView(count: newGlobalInsightCount)
      }
      if !attachments.isEmpty {
        AttachmentPreviewStrip(attachments: attachments, onRemove: onRemoveAttachment)
      }
      if !attachmentError.isEmpty {
        Text(attachmentError)
          .font(.caption)
          .foregroundColor(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if !emptySubmitMessage.isEmpty {
        Text(emptySubmitMessage)
          .font(.caption)
          .foregroundColor(.signalASITextSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if !holdToTalk.statusMessage.isEmpty {
        Text(holdToTalk.statusMessage)
          .font(.caption)
          .foregroundColor(.signalASITextSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if holdToTalk.isPending {
        voicePreparingSurface
          .transition(.move(edge: .bottom).combined(with: .opacity))
      } else if holdToTalk.isRecording {
        recordingSurface
          .transition(.move(edge: .bottom).combined(with: .opacity))
      } else {
        inputRow
      }
      if trayVisible {
        actionTray
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color.signalASIBarBackground)
    .animation(deviceInputPolicy.reduceMotion ? nil : .easeOut(duration: 0.16), value: trayVisible)
    .animation(deviceInputPolicy.reduceMotion ? nil : .easeOut(duration: 0.16), value: holdToTalk.isPending)
    .animation(deviceInputPolicy.reduceMotion ? nil : .easeOut(duration: 0.16), value: holdToTalk.isRecording)
    .onChange(of: canSend) { hasInput in
      emptySubmitMessage = ""
      if hasInput {
        actionTrayPresented = false
      }
    }
    .onChange(of: focusRequest) { _ in
      actionTrayPresented = false
      inputFocused = true
    }
    .onChange(of: scenePhase) { phase in
      guard phase != .active,
            holdToTalk.isPending || holdToTalk.isRecording else { return }
      voiceTranscriptionPending = false
      onVoiceCancelled()
      holdToTalk.cancelFromView()
    }
    .onReceive(
      NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)
    ) { _ in
      guard inputFocused, !holdToTalk.isPending, !holdToTalk.isRecording else { return }
      // Match Android: dismissing the keyboard exits text mode so voice input is available again.
      inputFocused = false
      actionTrayPresented = false
    }
    .onReceive(
      NotificationCenter.default.publisher(for: .signalASIRuntimePlaintextWillClear)
    ) { _ in
      holdToTalk.clearRuntimePlaintext()
      voiceTranscriptionPending = false
      inputFocused = false
      actionTrayPresented = false
      emptySubmitMessage.removeAll(keepingCapacity: false)
    }
    .onDisappear {
      voiceTranscriptionPending = false
      onVoiceCancelled()
      holdToTalk.cancelFromView()
    }
  }

  private var inputRow: some View {
    HStack(alignment: .bottom, spacing: 4) {
      inputShell
      primaryActionButton
    }
    .frame(minHeight: 72)
    .padding(.bottom, 9)
  }

  private var voicePreparingSurface: some View {
    AgentVoiceProcessingIndicator(
      title: t("signalasi.voice.preparing_title", "Preparing voice input"),
      subtitle: voicePreparingSubtitle
    )
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, minHeight: 72)
    .background(Color.signalASISurface)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.signalASIInputStroke, lineWidth: 0.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityLabel(
      Text(t("signalasi.voice.preparing_title", "Preparing voice input"))
    )
  }

  private var inputShell: some View {
    SignalASIGrowingComposerEditor(
      text: $draft,
      placeholder: t("signalasi.agent.goal_hint", "Enter message or hold to talk..."),
      focus: $inputFocused,
      accessibilityIdentifier: "ios.agent.agent-goal-input",
      onTap: { actionTrayPresented = false }
    )
    .contentShape(Rectangle())
    .simultaneousGesture(holdToTalkGesture)
    .accessibilityLabel(Text(t("agent_voice_button", "Hold to talk")))
  }

  private var recordingSurface: some View {
    VStack(spacing: 12) {
      Spacer(minLength: 0)
      Text(holdToTalk.cancelPending
        ? t("voice_release_to_cancel", "Release to cancel")
        : t("agent_voice_recording_hint", "Release to send / Swipe up to cancel"))
        .font(.system(size: 14))
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
      ZStack {
        if holdToTalk.transcript.isEmpty {
          SignalASIAgentRecordingWaveform(
            phase: holdToTalk.waveformPhase,
            amplitude: holdToTalk.waveformAmplitude,
            cancelPending: holdToTalk.cancelPending
          )
        } else {
          SignalASIAgentRecordingTranscript(
            stableText: holdToTalk.stableTranscript,
            unstableText: holdToTalk.unstableTranscript,
            fallbackText: holdToTalk.transcript
          )
        }
      }
      .frame(height: 38)
      Text(holdToTalk.elapsedLabel)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(holdToTalk.cancelPending ? .signalASIAgentVoiceCancel : .white)
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 24)
    .frame(maxWidth: .infinity, minHeight: 236, alignment: .bottom)
    .background(
      LinearGradient(
        gradient: Gradient(stops: [
          .init(color: .clear, location: 0),
          .init(
            color: Color.signalASIAgentRecordingLight.opacity(30.0 / 255.0),
            location: 0.16
          ),
          .init(
            color: Color.signalASIAgentRecordingLight.opacity(132.0 / 255.0),
            location: 0.36
          ),
          .init(
            color: Color.signalASIAgentRecordingMid.opacity(224.0 / 255.0),
            location: 0.64
          ),
          .init(color: Color.signalASIAgentRecordingDeep, location: 1.0),
        ]),
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  private var holdToTalkGesture: some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        // Match Android: text mode owns the composer while the field is focused.
        guard !inputFocused || holdToTalk.isPending || holdToTalk.isRecording else { return }
        holdToTalk.dragChanged(
          translation: value.translation,
          settings: voiceSettings,
          messages: holdToTalkMessages,
          onStart: {
            actionTrayPresented = false
            inputFocused = false
            voiceTranscriptionPending = true
            onVoiceStart()
          },
          onFinish: onVoiceTranscript,
          onCancel: onVoiceCancelled
        )
      }
      .onEnded { value in
        guard !inputFocused || holdToTalk.isPending || holdToTalk.isRecording else { return }
        let didRecord = holdToTalk.isRecording
        holdToTalk.dragEnded(translation: value.translation)
        if !didRecord {
          voiceTranscriptionPending = false
          actionTrayPresented = false
          inputFocused = true
        }
      }
  }

  private var holdToTalkMessages: SignalASIAgentHoldToTalkMessages {
    SignalASIAgentHoldToTalkMessages(
      permissionDenied: voicePermissionDeniedMessage,
      speechDisabled: t("signalasi.voice.speech_disabled", "Speech recognition is turned off."),
      speechUnavailable: t("signalasi.voice.speech_unavailable", "Speech recognition could not start."),
      noSpeech: t("voice_no_speech", "No speech captured."),
      tooShort: t("voice_too_short", "Hold a little longer."),
      cancelled: t("voice_cancelled", "Voice cancelled.")
    )
  }

  @ViewBuilder
  private var primaryActionButton: some View {
    if !uiState.showPrimaryActionSlot {
      EmptyView()
    } else if uiState.showSendButton {
      Button {
        inputFocused = false
        actionTrayPresented = false
        if canSend {
          onSend()
        } else {
          onPendingPrimaryAction()
        }
      } label: {
        Image(systemName: canSend
          ? "paperplane"
          : pendingPrimaryActionResumesTask
            ? "play.fill"
            : pendingPrimaryActionApprovesTask
              ? "checkmark"
              : pendingPrimaryActionWaitingForResponse
                ? "hourglass"
                : pendingPrimaryActionNeedsHighRiskConfirmation
                  ? "exclamationmark.triangle.fill"
                  : "xmark")
          .font(.system(size: canSend ? 25 : 20, weight: canSend ? .medium : .bold))
          .foregroundColor(
            canSend || pendingPrimaryActionResumesTask || pendingPrimaryActionApprovesTask
              ? .signalASIAccent
              : pendingPrimaryActionWaitingForResponse
                ? .signalASITextSecondary
                : pendingPrimaryActionNeedsHighRiskConfirmation
                  ? .orange
                  : .signalASIAgentVoiceCancel
          )
          .frame(width: 54, height: 54)
          .background(canSend ? Color.clear : Color(red: 0.565, green: 0.569, blue: 0.588))
          .clipShape(Circle())
      }
      .buttonStyle(.plain)
      .disabled(!canSend && primaryActionInFlight)
      .frame(minWidth: minimumTouchSize, minHeight: minimumTouchSize)
      .contentShape(Rectangle())
      .accessibilityLabel(Text(canSend
        ? t("signalasi.common.send", "Send")
        : pendingPrimaryActionResumesTask
          ? t("signalasi.agent.resume_task", "Resume task")
          : pendingPrimaryActionApprovesTask
            ? t("signalasi.agent.confirmation.allow_once", "Allow once")
            : pendingPrimaryActionWaitingForResponse
              ? t("agent_status_waiting_response", "Waiting for an Agent response")
            : pendingPrimaryActionNeedsHighRiskConfirmation
              ? t("signalasi.agent.high_risk_confirmation.execute", "Confirm high-risk action")
              : t("signalasi.agent.cancel_task", "Cancel task")))
      .accessibilityIdentifier("ios.agent.composer-primary-action")
    } else {
      Button {
        if actionTrayPresented {
          actionTrayPresented = false
        } else {
          inputFocused = false
          actionTrayPresented = true
        }
      } label: {
        SignalASIComposerMoreButtonIcon(expanded: trayVisible)
          .frame(width: 54, height: 54)
      }
      .buttonStyle(.plain)
      .frame(minWidth: minimumTouchSize, minHeight: minimumTouchSize)
      .contentShape(Rectangle())
      .accessibilityLabel(Text(uiState.showActionTray
        ? t("agent_attachment_close_menu", "Close actions")
        : t("agent_attachment_open_menu", "More actions")))
      .accessibilityIdentifier("ios.agent.composer-more-actions")
    }
  }

  private var actionTray: some View {
    SignalASIComposerActionTray(
      actions: trayActions,
      accessibilityPrefix: "ios.agent.composer",
      minimumTouchSize: minimumTouchSize,
      onSelect: closeTray
    )
  }

  private var trayActions: [SignalASIComposerTrayAction] {
    [
      SignalASIComposerTrayAction(
        id: .newSession,
        title: t("agent_attachment_new_task", "New session"),
        systemImage: "square.and.pencil",
        perform: onNewSession
      ),
      SignalASIComposerTrayAction(
        id: .sessions,
        title: t("agent_attachment_sessions", "Sessions"),
        systemImage: "bubble.left.and.bubble.right",
        perform: onOpenSessions
      ),
      SignalASIComposerTrayAction(
        id: .scan,
        title: t("agent_attachment_scan", "Scan"),
        systemImage: "qrcode.viewfinder",
        perform: onScan
      ),
      SignalASIComposerTrayAction(
        id: .camera,
        title: t("agent_attachment_take_photo", "Take photo"),
        systemImage: "camera",
        perform: onTakePhoto
      ),
      SignalASIComposerTrayAction(
        id: .file,
        title: t("agent_attachment_add_file", "Add file"),
        systemImage: "doc.badge.plus",
        perform: onAddFile
      )
    ]
  }

  private func closeTray() {
    actionTrayPresented = false
  }
}

struct SignalASIAgentVoiceAttachmentSummaryView: View {
  var attachments: [SignalASIDraftAttachment]
  var t: (String, String) -> String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: "paperclip")
          .font(.system(size: 12, weight: .semibold))
        Text(String(
          format: t("agent_attachment_count", "%d attachments"),
          attachments.count
        ))
          .font(.system(size: 12, weight: .semibold))
        Spacer(minLength: 0)
      }
      .foregroundColor(.signalASITextSecondary)

      ForEach(attachments) { attachment in
        HStack(spacing: 8) {
          Image(systemName: attachment.isImage ? "photo" : "doc")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.signalASIAccent)
            .frame(width: 22, height: 22)
          Text(attachment.displayName)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
            .truncationMode(.middle)
          Spacer(minLength: 8)
          Text(attachment.humanSize)
            .font(.system(size: 11))
            .foregroundColor(.signalASITextSecondary)
        }
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.signalASISurface)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.signalASISeparator, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(
      String(
        format: t("agent_attachment_count", "%d attachments"),
        attachments.count
      )
    ))
  }
}

struct SignalASIVoiceTranscriptionPendingView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @State private var isPulsing = false

  var body: some View {
    HStack {
      Spacer(minLength: 48)
      HStack(spacing: 5) {
        ForEach(0..<3, id: \.self) { index in
          Circle()
            .fill(Color.signalASIAgentRecordingDeep)
            .frame(width: 7, height: 7)
            .scaleEffect(isPulsing ? 1 : 0.82)
            .opacity(isPulsing ? 1 : 0.32)
            .animation(
              .easeInOut(duration: 0.45)
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.12),
              value: isPulsing
            )
        }
      }
      .padding(.horizontal, 15)
      .padding(.vertical, 10)
      .frame(minWidth: 96, minHeight: 44)
      .background(Color.signalASIAgentRecordingLight)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(t("signalasi.voice.transcription_pending", "Recognizing voice"))
    .onAppear {
      isPulsing = true
    }
    .onDisappear {
      isPulsing = false
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIAgentRecordingTranscript: View {
  var stableText: String
  var unstableText: String
  var fallbackText: String

  private var unstableColor: Color {
    Color(red: 232.0 / 255.0, green: 1, blue: 233.0 / 255.0)
  }

  var body: some View {
    let stable = stableText.trimmingCharacters(in: .whitespacesAndNewlines)
    let unstable = unstableText.trimmingCharacters(in: .whitespacesAndNewlines)
    let separator = Self.separator(stable: stable, unstable: unstable)
    Group {
      if stable.isEmpty && unstable.isEmpty {
        Text(fallbackText)
      } else {
        (Text(stable).foregroundColor(.white) +
          Text(separator + unstable).foregroundColor(unstableColor))
      }
    }
    .font(.system(size: 15, weight: .semibold))
    .lineLimit(1)
    .truncationMode(.head)
    .frame(maxWidth: .infinity)
  }

  private static func separator(stable: String, unstable: String) -> String {
    guard let last = stable.last,
          let first = unstable.first,
          (last.isLetter || last.isNumber),
          (first.isLetter || first.isNumber),
          !isCJK(last),
          !isCJK(first) else {
      return ""
    }
    return " "
  }

  private static func isCJK(_ character: Character) -> Bool {
    character.unicodeScalars.contains { scalar in
      (0x3400...0x9FFF).contains(scalar.value)
    }
  }
}

private struct SignalASIAgentRecordingWaveform: View {
  var phase: Double
  var amplitude: Double
  var cancelPending: Bool

  private let sampleCount = 56

  var body: some View {
    GeometryReader { proxy in
      let waveformWidth = proxy.size.width * 0.75
      let step = max(1, waveformWidth / CGFloat(sampleCount))
      let maxHeight = max(2, proxy.size.height - 8)
      HStack(alignment: .center, spacing: max(1, step * 0.68)) {
        ForEach(0..<sampleCount, id: \.self) { index in
          Capsule(style: .continuous)
            .fill(cancelPending ? Color.signalASIAgentVoiceCancel : .white)
            .frame(width: min(2, step * 0.32), height: barHeight(index: index, maxHeight: maxHeight))
        }
      }
      .frame(width: waveformWidth, height: proxy.size.height)
      .overlay {
        Rectangle()
          .fill((cancelPending ? Color.signalASIAgentVoiceCancel : .white).opacity(0.28))
          .frame(height: 1)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func barHeight(index: Int, maxHeight: CGFloat) -> CGFloat {
    let normalizedPosition = Double(index) / Double(max(1, sampleCount - 1))
    let centerEnvelope = 0.72 + 0.28 * (1 - abs(normalizedPosition - 0.5) * 2)
    let primary = (sin(Double(index) * 0.82 + phase) + 1) * 0.5
    let secondary = (sin(Double(index) * 0.37 - phase * 1.45) + 1) * 0.5
    let variation = 0.26 + primary * 0.48 + secondary * 0.26
    let animatedLevel = 0.24 + 0.76 * min(1, max(0, amplitude))
    let barAmplitude = 0.10 + 0.90 * centerEnvelope * variation * animatedLevel
    return max(2, maxHeight * CGFloat(min(1, barAmplitude)))
  }
}
