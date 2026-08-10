import SwiftUI

struct SignalASIAgentComposerView: View {
  @EnvironmentObject private var store: SignalASIStore
  @Binding var draft: String
  @Binding var actionTrayPresented: Bool
  @Binding var voiceTranscriptionPending: Bool
  @StateObject private var holdToTalk = SignalASIAgentHoldToTalkController()
  @FocusState private var inputFocused: Bool

  var attachments: [SignalASIDraftAttachment]
  var attachmentError: String
  var canSend: Bool
  var hasPendingPrimaryAction: Bool
  var pendingPrimaryActionResumesTask: Bool
  var pendingPrimaryActionApprovesTask: Bool
  var pendingPrimaryActionWaitingForResponse: Bool
  var pendingPrimaryActionNeedsHighRiskConfirmation: Bool
  var deviceInputPolicy: AgentDeviceInputTargetPolicy
  var voiceSettings: VoiceSettings
  var focusRequest: Int = 0
  var onRemoveAttachment: (SignalASIDraftAttachment) -> Void
  var onNewSession: () -> Void
  var onScan: () -> Void
  var onTakePhoto: () -> Void
  var onAddFile: () -> Void
  var onSend: () -> Void
  var onPendingPrimaryAction: () -> Void
  var onVoiceStart: () -> Void
  var onVoiceCancelled: () -> Void
  var onVoiceTranscript: (String) -> Void
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

  private var globalInsightTitle: String {
    String(
      format: t(
        "agent_global_new_insights",
        "SignalASI has %d new findings"
      ),
      newGlobalInsightCount
    )
  }

  var body: some View {
    VStack(spacing: 8) {
      if newGlobalInsightCount > 0 {
        NavigationLink(destination: SignalASIGlobalAgentInsightInboxView()) {
          HStack(spacing: 9) {
            Image(systemName: "sparkles")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(.signalASIInsightText)
              .frame(width: 20, height: 20)
            Text(globalInsightTitle)
              .font(.system(size: 13, weight: .bold))
              .foregroundColor(.signalASIInsightText)
              .lineLimit(1)
              .truncationMode(.tail)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
              .font(.system(size: 13, weight: .bold))
              .foregroundColor(.signalASIInsightText)
              .frame(width: 18, height: 18)
          }
          .padding(.horizontal, 12)
          .frame(maxWidth: .infinity, minHeight: 44)
          .background(Color.signalASIInsightBackground)
          .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .stroke(Color.signalASIInsightStroke, lineWidth: 1)
          )
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(globalInsightTitle))
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
      if hasInput {
        actionTrayPresented = false
      }
    }
    .onChange(of: focusRequest) { _ in
      actionTrayPresented = false
      inputFocused = true
    }
    .onReceive(
      NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)
    ) { _ in
      guard inputFocused, !holdToTalk.isPending, !holdToTalk.isRecording else { return }
      // Match Android: dismissing the keyboard exits text mode so voice input is available again.
      inputFocused = false
      actionTrayPresented = false
    }
    .onDisappear {
      voiceTranscriptionPending = false
      onVoiceCancelled()
      holdToTalk.cancelFromView()
    }
  }

  private var inputRow: some View {
    HStack(spacing: 4) {
      inputShell
      primaryActionButton
    }
    .frame(minHeight: 72)
  }

  private var voicePreparingSurface: some View {
    AgentVoiceProcessingIndicator(
      title: t("signalasi.voice.preparing_title", "Preparing voice input"),
      subtitle: t(
        "signalasi.voice.preparing_subtitle",
        "Requesting microphone and speech recognition access."
      )
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
    ZStack(alignment: .topLeading) {
      if draft.isEmpty {
        Text(t("signalasi.agent.goal_hint", "Enter message or hold to talk..."))
          .font(.system(size: 15))
          .foregroundColor(.signalASITextSecondary)
          .padding(.leading, 12)
          .padding(.top, 16)
          .allowsHitTesting(false)
      }
      TextEditor(text: $draft)
        .font(.system(size: 15))
        .foregroundColor(.signalASITextPrimary)
        .textInputAutocapitalization(.sentences)
        .focused($inputFocused)
        .frame(height: 54)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.clear)
        .onSubmit {
          guard canSend else { return }
          inputFocused = false
          actionTrayPresented = false
          onSend()
        }
        .onTapGesture {
          actionTrayPresented = false
        }
    }
    .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
    .background(Color.signalASISurface)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.signalASIInputStroke, lineWidth: 0.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            cancelPending: holdToTalk.cancelPending
          )
        } else {
          Text(holdToTalk.transcript)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: .infinity)
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
        colors: [
          Color.clear,
          Color.signalASIAgentRecordingLight.opacity(0.52),
          Color.signalASIAgentRecordingMid.opacity(0.88),
          Color.signalASIAgentRecordingDeep,
        ],
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
      permissionDenied: t("signalasi.voice.permission_missing", "Microphone or speech permission is missing."),
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
          ? "arrow.up"
          : pendingPrimaryActionResumesTask
            ? "play.fill"
            : pendingPrimaryActionApprovesTask
              ? "checkmark"
              : pendingPrimaryActionWaitingForResponse
                ? "hourglass"
                : pendingPrimaryActionNeedsHighRiskConfirmation
                  ? "exclamationmark.triangle.fill"
                  : "xmark")
          .font(.system(size: 20, weight: .bold))
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
          .background(Color.white)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .buttonStyle(.plain)
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
    } else {
      Button {
        if actionTrayPresented {
          actionTrayPresented = false
        } else {
          inputFocused = false
          actionTrayPresented = true
        }
      } label: {
        Image(systemName: "plus")
          .font(.system(size: 22, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .rotationEffect(.degrees(trayVisible ? 45 : 0))
          .frame(width: 54, height: 54)
          .background(Color.signalASISurface)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .buttonStyle(.plain)
      .frame(minWidth: minimumTouchSize, minHeight: minimumTouchSize)
      .contentShape(Rectangle())
      .accessibilityLabel(Text(uiState.showActionTray
        ? t("agent_attachment_close_menu", "Close actions")
        : t("agent_attachment_open_menu", "More actions")))
    }
  }

  private var actionTray: some View {
    HStack(spacing: 0) {
      SignalASIAgentComposerTrayButton(
        title: t("agent_attachment_new_task", "New session"),
        systemImage: "square.and.pencil",
        minimumTouchSize: minimumTouchSize
      ) {
        closeTray()
        onNewSession()
      }
      SignalASIAgentComposerTrayNavigationLink(
        title: t("agent_attachment_sessions", "Sessions"),
        systemImage: "tray.full",
        minimumTouchSize: minimumTouchSize,
        destination: SignalASIAgentSessionsView()
      ) {
        closeTray()
      }
      SignalASIAgentComposerTrayButton(
        title: t("agent_attachment_scan", "Scan"),
        systemImage: "qrcode.viewfinder",
        minimumTouchSize: minimumTouchSize
      ) {
        closeTray()
        onScan()
      }
      SignalASIAgentComposerTrayButton(
        title: t("agent_attachment_take_photo", "Take photo"),
        systemImage: "camera",
        minimumTouchSize: minimumTouchSize
      ) {
        closeTray()
        onTakePhoto()
      }
      SignalASIAgentComposerTrayButton(
        title: t("agent_attachment_add_file", "Add file"),
        systemImage: "doc",
        minimumTouchSize: minimumTouchSize
      ) {
        closeTray()
        onAddFile()
      }
    }
    .frame(height: 96)
    .background(Color.signalASIBarBackground)
  }

  private func closeTray() {
    actionTrayPresented = false
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

private struct SignalASIAgentRecordingWaveform: View {
  var phase: Double
  var cancelPending: Bool

  private let sampleCount = 56

  var body: some View {
    GeometryReader { proxy in
      let step = max(1, proxy.size.width / CGFloat(sampleCount))
      let maxHeight = max(2, proxy.size.height - 8)
      HStack(alignment: .center, spacing: max(1, step * 0.68)) {
        ForEach(0..<sampleCount, id: \.self) { index in
          Capsule(style: .continuous)
            .fill(cancelPending ? Color.signalASIAgentVoiceCancel : .white)
            .frame(width: min(2, step * 0.32), height: barHeight(index: index, maxHeight: maxHeight))
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .overlay(
        Rectangle()
          .fill((cancelPending ? Color.signalASIAgentVoiceCancel : .white).opacity(0.28))
          .frame(height: 1),
        alignment: .center
      )
    }
  }

  private func barHeight(index: Int, maxHeight: CGFloat) -> CGFloat {
    let normalizedPosition = Double(index) / Double(max(1, sampleCount - 1))
    let centerEnvelope = 0.72 + 0.28 * (1 - abs(normalizedPosition - 0.5) * 2)
    let primary = (sin(Double(index) * 0.82 + phase) + 1) * 0.5
    let secondary = (sin(Double(index) * 0.37 - phase * 1.45) + 1) * 0.5
    let variation = 0.26 + primary * 0.48 + secondary * 0.26
    let amplitude = 0.10 + 0.90 * centerEnvelope * variation
    return max(2, maxHeight * CGFloat(min(1, amplitude)))
  }
}

private struct SignalASIAgentComposerTrayButton: View {
  var title: String
  var systemImage: String
  var minimumTouchSize: CGFloat
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      SignalASIAgentComposerTrayContent(
        title: title,
        systemImage: systemImage,
        minimumTouchSize: minimumTouchSize
      )
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }
}

private struct SignalASIAgentComposerTrayNavigationLink<Destination: View>: View {
  var title: String
  var systemImage: String
  var minimumTouchSize: CGFloat
  var destination: Destination
  var onNavigate: () -> Void

  var body: some View {
    NavigationLink(destination: destination) {
      SignalASIAgentComposerTrayContent(
        title: title,
        systemImage: systemImage,
        minimumTouchSize: minimumTouchSize
      )
    }
    .simultaneousGesture(
      TapGesture().onEnded { _ in
        // Let NavigationLink activate before removing the tray that owns it.
        DispatchQueue.main.async {
          onNavigate()
        }
      }
    )
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }
}

private struct SignalASIAgentComposerTrayContent: View {
  var title: String
  var systemImage: String
  var minimumTouchSize: CGFloat

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: systemImage)
        .font(.system(size: 25, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
        .frame(width: 30, height: 30)
      Text(title)
        .font(.system(size: 12, weight: .regular))
        .foregroundColor(.signalASITextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, minHeight: minimumTouchSize)
    .contentShape(Rectangle())
  }
}
