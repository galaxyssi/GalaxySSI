import SwiftUI
import UIKit

struct SignalASIConversationComposer: View {
  @Binding var draft: String
  @Binding var attachments: [SignalASIDraftAttachment]
  @Binding var attachmentError: String
  @Binding var attachmentMenuPresented: Bool
  @Binding var textModeActive: Bool

  var deviceInputPolicy: AgentDeviceInputTargetPolicy
  var voiceSettings: VoiceSettings
  var dedicatedPeerVoiceCapture = false
  var onNewSession: () -> Void
  var onOpenSessions: () -> Void
  var onScan: () -> Void
  var onTakePhoto: () -> Void
  var onAddFile: () -> Void
  var onSend: () -> Void
  var onVoiceTranscript: (SignalASIVoiceTranscriptSubmission) -> Void
  var t: (String, String) -> String

  @StateObject private var holdToTalk = SignalASIAgentHoldToTalkController()
  @StateObject private var peerVoiceRecorder = SignalASIPeerVoiceMessageRecorder()
  @FocusState private var inputFocused: Bool

  private var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
  }

  private var uiState: SignalASIAgentComposerUiState {
    SignalASIAgentComposerUiPolicy.resolve(
      hasInput: canSend,
      hasPendingPrimaryAction: false,
      textModeActive: textModeActive,
      actionTrayRequested: attachmentMenuPresented
    )
  }

  private var trayVisible: Bool {
    uiState.showActionTray && !voiceCapturePending && !voiceCaptureRecording
  }

  private var minimumTouchSize: CGFloat {
    CGFloat(deviceInputPolicy.minimumTouchTargetDp)
  }

  private var voicePermissionDeniedMessage: String {
    if dedicatedPeerVoiceCapture {
      return t("signalasi.voice.microphone_permission_missing", "Microphone permission is missing.")
    }
    switch VoiceASRProviderRoutingPolicy.currentAuthorizationRequirement(settings: voiceSettings) {
    case .microphoneOnly:
      return t("signalasi.voice.microphone_permission_missing", "Microphone permission is missing.")
    case .microphoneAndSystemSpeech:
      return t("signalasi.voice.permission_missing", "Microphone or speech permission is missing.")
    }
  }

  var body: some View {
    VStack(spacing: 8) {
      if !attachments.isEmpty {
        AttachmentPreviewStrip(attachments: attachments) { attachment in
          attachments.removeAndWipe(id: attachment.id)
        }
      }
      if !attachmentError.isEmpty {
        Text(attachmentError)
          .font(.caption)
          .foregroundColor(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if !activeVoiceStatusMessage.isEmpty {
        Text(activeVoiceStatusMessage)
          .font(.caption)
          .foregroundColor(.signalASITextSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if voiceCapturePending || voiceCaptureRecording {
        voiceCaptureSurface
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
    .onChange(of: canSend) { hasInput in
      if hasInput {
        attachmentMenuPresented = false
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)
    ) { _ in
      guard inputFocused, !voiceCapturePending, !voiceCaptureRecording else { return }
      inputFocused = false
      textModeActive = false
      attachmentMenuPresented = false
    }
    .onReceive(
      NotificationCenter.default.publisher(for: .signalASIRuntimePlaintextWillClear)
    ) { _ in
      holdToTalk.clearRuntimePlaintext()
      peerVoiceRecorder.cancelFromView()
      draft.removeAll(keepingCapacity: false)
      attachments.wipeSensitive()
      attachmentError.removeAll(keepingCapacity: false)
      inputFocused = false
      textModeActive = false
      attachmentMenuPresented = false
    }
    .onChange(of: inputFocused) { focused in
      if textModeActive != focused {
        textModeActive = focused
      }
      if focused {
        attachmentMenuPresented = false
      }
      guard focused, !voiceCaptureRecording else { return }
      holdToTalk.cancelFromView()
      peerVoiceRecorder.cancelFromView()
      attachmentMenuPresented = false
    }
    .onChange(of: textModeActive) { active in
      if inputFocused != active {
        inputFocused = active
      }
    }
    .onDisappear {
      holdToTalk.cancelFromView()
      peerVoiceRecorder.cancelFromView()
      attachmentMenuPresented = false
    }
  }

  private var inputRow: some View {
    HStack(spacing: 4) {
      inputShell
      primaryActionButton
    }
    .frame(minHeight: 72)
  }

  private var inputShell: some View {
    ZStack(alignment: .topLeading) {
      if draft.isEmpty {
        Text(t("signalasi.message.input_hint", "Message or hold to talk..."))
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
          attachmentMenuPresented = false
          onSend()
        }
        .onTapGesture {
          attachmentMenuPresented = false
        }
    }
    .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
    .contentShape(Rectangle())
    .simultaneousGesture(holdToTalkGesture)
    .accessibilityLabel(Text(t("agent_voice_button", "Hold to talk")))
  }

  @ViewBuilder
  private var primaryActionButton: some View {
    if uiState.showPrimaryActionSlot {
      Button {
        if canSend {
          inputFocused = false
          attachmentMenuPresented = false
          onSend()
        } else if attachmentMenuPresented {
          attachmentMenuPresented = false
        } else {
          inputFocused = false
          attachmentMenuPresented = true
        }
      } label: {
        if uiState.showSendButton {
          Image(systemName: "arrow.up")
            .font(.system(size: 21, weight: .bold))
            .foregroundColor(.signalASIAccent)
            .frame(width: 54, height: 54)
            .background(Color(red: 0.655, green: 0.906, blue: 0.847))
            .clipShape(Circle())
        } else {
          SignalASIComposerMoreButtonIcon(expanded: trayVisible)
            .frame(width: 54, height: 54)
        }
      }
      .buttonStyle(.plain)
      .frame(minWidth: 54, minHeight: 54)
      .contentShape(Rectangle())
      .accessibilityLabel(Text(
        uiState.showSendButton
          ? t("signalasi.common.send", "Send")
          : trayVisible
            ? t("agent_attachment_close_menu", "Close actions")
            : t("agent_attachment_open_menu", "More actions")
      ))
      .accessibilityIdentifier("ios.chat.composer-primary-action")
    }
  }

  private var voiceCaptureSurface: some View {
    VStack(spacing: 12) {
      Spacer(minLength: 0)
      Text(voiceCapturePending
        ? t("signalasi.voice.preparing_title", "Preparing voice input")
        : voiceCaptureCancelPending
          ? t("voice_release_to_cancel", "Release to cancel")
          : t("agent_voice_recording_hint", "Release to send / Swipe up to cancel"))
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
      if voiceCaptureRecording {
        let stableTranscript = dedicatedPeerVoiceCapture
          ? ""
          : holdToTalk.stableTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let unstableTranscript = dedicatedPeerVoiceCapture
          ? ""
          : holdToTalk.unstableTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if stableTranscript.isEmpty && unstableTranscript.isEmpty {
          SignalASIChatVoiceWaveform(
            phase: voiceWaveformPhase,
            amplitude: voiceWaveformAmplitude,
            cancelPending: voiceCaptureCancelPending,
            color: .white
          )
          .frame(height: 38)
        } else {
          SignalASIChatVoiceTranscript(
            stableText: stableTranscript,
            unstableText: unstableTranscript,
            cancelPending: holdToTalk.cancelPending
          )
          .frame(maxWidth: .infinity, minHeight: 38)
        }
        Text(voiceElapsedLabel)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(voiceCaptureCancelPending ? .red : .white)
      }
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
        guard !textModeActive || voiceCapturePending || voiceCaptureRecording else { return }
        attachmentMenuPresented = false
        if dedicatedPeerVoiceCapture {
          peerVoiceRecorder.dragChanged(
            translation: value.translation,
            messages: holdToTalkMessages,
            onFinish: { recording in
              onVoiceTranscript(SignalASIVoiceTranscriptSubmission(
                text: "",
                correctionReview: nil,
                sessionId: UUID().uuidString.lowercased(),
                audioData: recording.data,
                audioDurationMillis: recording.durationMillis,
                audioMimeType: recording.mimeType,
                audioFileExtension: recording.fileExtension,
                audioSourceURL: recording.fileURL
              ))
            },
            onCancel: {}
          )
        } else {
          holdToTalk.dragChanged(
            translation: value.translation,
            settings: voiceSettings,
            messages: holdToTalkMessages,
            onStart: {},
            onFinish: onVoiceTranscript,
            onCancel: {}
          )
        }
      }
      .onEnded { value in
        guard !textModeActive || voiceCapturePending || voiceCaptureRecording else { return }
        let wasCapturingVoice = voiceCapturePending || voiceCaptureRecording
        if dedicatedPeerVoiceCapture {
          peerVoiceRecorder.dragEnded(translation: value.translation)
        } else {
          holdToTalk.dragEnded(translation: value.translation)
        }
        if !wasCapturingVoice {
          attachmentMenuPresented = false
          inputFocused = true
        }
      }
  }

  private var actionTray: some View {
    SignalASIComposerActionTray(
      actions: [
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
        ),
      ],
      accessibilityPrefix: "ios.chat.composer",
      minimumTouchSize: minimumTouchSize,
      onSelect: { attachmentMenuPresented = false }
    )
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

  private var voiceCapturePending: Bool {
    dedicatedPeerVoiceCapture ? peerVoiceRecorder.isPending : holdToTalk.isPending
  }

  private var voiceCaptureRecording: Bool {
    dedicatedPeerVoiceCapture ? peerVoiceRecorder.isRecording : holdToTalk.isRecording
  }

  private var voiceCaptureCancelPending: Bool {
    dedicatedPeerVoiceCapture ? peerVoiceRecorder.cancelPending : holdToTalk.cancelPending
  }

  private var voiceElapsedLabel: String {
    dedicatedPeerVoiceCapture ? peerVoiceRecorder.elapsedLabel : holdToTalk.elapsedLabel
  }

  private var voiceWaveformPhase: Double {
    dedicatedPeerVoiceCapture ? peerVoiceRecorder.waveformPhase : holdToTalk.waveformPhase
  }

  private var voiceWaveformAmplitude: Double {
    dedicatedPeerVoiceCapture ? peerVoiceRecorder.waveformAmplitude : holdToTalk.waveformAmplitude
  }

  private var activeVoiceStatusMessage: String {
    dedicatedPeerVoiceCapture ? peerVoiceRecorder.statusMessage : holdToTalk.statusMessage
  }
}

private struct SignalASIChatVoiceTranscript: View {
  var stableText: String
  var unstableText: String
  var cancelPending: Bool

  var body: some View {
    let separator = Self.separator(stable: stableText, unstable: unstableText)
    (Text(stableText).foregroundColor(cancelPending ? .red : .white) +
      Text(separator + unstableText).foregroundColor(cancelPending ? .red : Self.unstableColor))
      .font(.system(size: 15, weight: .medium))
      .multilineTextAlignment(.center)
      .lineLimit(2)
      .minimumScaleFactor(0.8)
  }

  private static let unstableColor = Color(red: 232.0 / 255.0, green: 1, blue: 233.0 / 255.0)

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

private struct SignalASIChatVoiceWaveform: View {
  var phase: Double
  var amplitude: Double
  var cancelPending: Bool
  var color: Color = .signalASIAccent

  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<18, id: \.self) { index in
        Capsule()
          .fill(cancelPending ? Color.red : color)
          .frame(
            width: 3,
            height: 8 + abs(sin(phase + Double(index) * 0.58)) * (8 + amplitude * 18)
          )
      }
    }
    .accessibilityHidden(true)
  }
}
